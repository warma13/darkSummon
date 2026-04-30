-- Game/LeaderWeaponEffect.lua
-- 主角(Leader)武器皮肤战场特效
-- 待机时武器在身侧微浮，攻击时武器向前挥出
-- 配置由 CostumeData 驱动

local State       = require("Game.State")
local CostumeData = require("Game.CostumeData")

local M = {}

local MAX_ALPHA   = 0.92
local ATK_DUR     = 0.30   -- 与 HeroAnim 攻击动画同步

-- 图像句柄缓存
local imageCache  = {}

local function EnsureImage(vg, def)
    local id = def.id
    if not imageCache[id] then
        imageCache[id] = nvgCreateImage(vg, def.preview, 0)
    end
    return imageCache[id]
end

--------------------------------------------------------------------------------
-- 攻击曲线 —— 法杖：前刺
-- t: 0→1, 返回: angle, offsetX, alphaMul
--------------------------------------------------------------------------------
local function AttackCurveStaff(t)
    if t < 0.2 then
        local p = t / 0.2
        local ease = p * p
        return -0.15 * ease, -2 * ease, 1.0
    elseif t < 0.5 then
        local p = (t - 0.2) / 0.3
        local ease = 1 - (1 - p) * (1 - p)
        return -0.15 + 0.5 * ease, -2 + 12 * ease, 1.0
    else
        local p = (t - 0.5) / 0.5
        local ease = p * p * (3 - 2 * p)
        return 0.35 * (1 - ease), 10 * (1 - ease), 1.0 - 0.3 * (1 - ease)
    end
end

--------------------------------------------------------------------------------
-- 攻击曲线 —— 剑/刀：举起劈砍
-- 蓄力抬高 → 向下劈砍 → 回收
--------------------------------------------------------------------------------
local function AttackCurveBlade(t)
    if t < 0.25 then
        -- 蓄力：向后转（抬起）
        local p = t / 0.25
        local ease = p * p
        return -1.0 * ease, 0, 1.0
    elseif t < 0.5 then
        -- 劈砍：向前转砍下
        local p = (t - 0.25) / 0.25
        local ease = 1 - (1 - p) * (1 - p)
        return -1.0 + 2.2 * ease, 0, 1.0
    else
        -- 回收：转回待机
        local p = (t - 0.5) / 0.5
        local ease = p * p * (3 - 2 * p)
        return 1.2 * (1 - ease), 0, 1.0 - 0.2 * (1 - ease)
    end
end

local function AttackCurve(t, weaponType)
    if weaponType == "blade" then
        return AttackCurveBlade(t)
    else
        return AttackCurveStaff(t)
    end
end

--- 绘制主角武器（在 DrawTowerIcon 之后调用，叠在角色上层）
---@param vg any
---@param x number      主角中心 x
---@param y number      主角中心 y
---@param size number   塔基础尺寸
---@param tower table   塔数据（读取 attackAnimTimer, faceLeft）
function M.Draw(vg, x, y, size, tower)
    local def = CostumeData.GetEquippedDef("weapon")
    if not def then return end

    local img = EnsureImage(vg, def)
    if not img or img <= 0 then return end

    local faceLeft = tower.faceLeft or false
    local atkTimer = tower.attackAnimTimer or 0
    local wType = def.weaponType or "staff"

    -- 武器尺寸
    local weapW = size * 0.55
    local weapH = size * 0.55

    -- 基础偏移（待机位置：角色下部，手持位置）
    local baseOffX = size * 0.3
    local baseOffY = size * 0.3

    local angle, extraOffX, alphaMul

    if atkTimer > 0 then
        local progress = 1.0 - (atkTimer / ATK_DUR)
        progress = math.max(0, math.min(1, progress))
        angle, extraOffX, alphaMul = AttackCurve(progress, wType)
    else
        -- 待机：轻微浮动
        local bob = math.sin(State.time * 2.5) * 0.08
        angle    = bob
        extraOffX = 0
        alphaMul  = 0.85
    end

    -- 朝向翻转
    local dirSign = faceLeft and -1 or 1

    local finalX = x + (baseOffX + extraOffX) * dirSign
    local finalY = y + baseOffY

    -- NanoVG 绘制（带旋转+镜像）
    nvgSave(vg)
    nvgTranslate(vg, finalX, finalY)
    if faceLeft then
        nvgScale(vg, -1, 1)  -- 水平镜像：同时翻转图片和旋转方向
    end
    nvgRotate(vg, angle)  -- 直接用原始角度，镜像由 nvgScale 处理

    -- 攻击时添加发光
    if atkTimer > 0 then
        local glowR = (def.rarityColor and def.rarityColor[1] or 180) / 255
        local glowG = (def.rarityColor and def.rarityColor[2] or 100) / 255
        local glowB = (def.rarityColor and def.rarityColor[3] or 255) / 255
        local glowAlpha = 0.35 * alphaMul
        local glowSize = weapW * 0.8
        local gp = nvgRadialGradient(vg, 0, 0, glowSize * 0.1, glowSize,
            nvgRGBAf(glowR, glowG, glowB, glowAlpha),
            nvgRGBAf(glowR, glowG, glowB, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, glowSize)
        nvgFillPaint(vg, gp)
        nvgFill(vg)
    end

    -- 绘制武器图片
    local drawL, drawT
    if wType == "blade" then
        -- blade: 旋转180°使剑刃朝上，旋转中心在剑柄（底部）
        nvgRotate(vg, math.pi)
        drawL = -weapW * 0.5
        drawT = 0               -- 图片在原点下方绘制，180°翻转后在原点上方，底边（剑柄）在原点
    else
        -- staff: 中心旋转
        drawL = -weapW * 0.5
        drawT = -weapH * 0.5
    end
    local paint = nvgImagePattern(vg, drawL, drawT, weapW, weapH, 0, img, MAX_ALPHA * alphaMul)
    nvgBeginPath(vg)
    nvgRect(vg, drawL, drawT, weapW, weapH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgRestore(vg)
end

--- 清除图像缓存
function M.Reset()
    imageCache = {}
end

return M
