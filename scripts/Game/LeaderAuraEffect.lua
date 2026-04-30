-- Game/LeaderAuraEffect.lua
-- 主角(Leader)光环时装战场特效
-- 脚底旋转光环 + 呼吸脉冲 + 攻击时爆发
-- 绘制在角色图标之下（最底层）

local State       = require("Game.State")
local CostumeData = require("Game.CostumeData")

local M = {}

local BASE_ALPHA  = 0.6
local ATK_DUR     = 0.30   -- 与攻击动画同步

-- 图像句柄缓存
local imageCache  = {}

local function EnsureImage(vg, def)
    local id = def.id
    if not imageCache[id] then
        imageCache[id] = nvgCreateImage(vg, def.preview, 0)
    end
    return imageCache[id]
end

--- 绘制脚底光环（在 DrawTowerIcon 之前调用，位于角色下方）
---@param vg any
---@param x number      主角中心 x
---@param y number      主角中心 y
---@param size number   塔基础尺寸
---@param tower table   塔数据（读取 attackAnimTimer）
function M.Draw(vg, x, y, size, tower)
    local def = CostumeData.GetEquippedDef("aura")
    if not def then return end

    local img = EnsureImage(vg, def)
    if not img or img <= 0 then return end

    local atkTimer = tower.attackAnimTimer or 0
    local t = State.time

    -- ── 旋转 ──
    local rotSpeed = 0.8  -- 每秒旋转弧度
    local rotation = t * rotSpeed

    -- ── 呼吸脉冲（仅透明度，不缩放） ──
    local breathPhase = math.sin(t * 1.8) -- 慢周期
    local finalAlpha  = BASE_ALPHA + breathPhase * 0.1  -- 0.5 ~ 0.7

    -- ── 攻击时增强发光（不改变尺寸） ──
    local atkGlow = 0
    if atkTimer > 0 then
        local progress = 1.0 - (atkTimer / ATK_DUR)
        progress = math.max(0, math.min(1, progress))
        if progress < 0.3 then
            local p = progress / 0.3
            atkGlow = 1 - (1 - p) * (1 - p)
            finalAlpha = math.min(1.0, finalAlpha + 0.3 * atkGlow)
        else
            local p = (progress - 0.3) / 0.7
            atkGlow = 1.0 - p * p * (3 - 2 * p)
            finalAlpha = math.min(1.0, finalAlpha + 0.3 * atkGlow)
        end
    end

    -- 光环尺寸（固定大小，不随角色缩放）
    local auraR = size * 0.65  -- 圆形半径

    -- 光环位置（脚底偏下）
    local auraY = y + size * 0.35
    local squash = 0.55  -- 垂直压缩比，模拟地面透视

    nvgSave(vg)
    nvgTranslate(vg, x, auraY)
    nvgScale(vg, 1, squash)   -- 先压扁（透视）
    nvgRotate(vg, rotation)   -- 再旋转（绕Z轴平转）

    -- 攻击时外层发光
    if atkGlow > 0 then
        local cr = (def.rarityColor and def.rarityColor[1] or 200) / 255
        local cg = (def.rarityColor and def.rarityColor[2] or 160) / 255
        local cb = (def.rarityColor and def.rarityColor[3] or 255) / 255
        local glowRadius = auraR * 1.2
        local gp = nvgRadialGradient(vg, 0, 0, glowRadius * 0.2, glowRadius,
            nvgRGBAf(cr, cg, cb, 0.4 * atkGlow),
            nvgRGBAf(cr, cg, cb, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, glowRadius)
        nvgFillPaint(vg, gp)
        nvgFill(vg)
    end

    -- 绘制光环图片（圆形，旋转+压扁后呈现为地面旋转光环）
    local drawS = auraR * 2
    local drawL = -auraR
    local drawT = -auraR
    local paint = nvgImagePattern(vg, drawL, drawT, drawS, drawS, 0, img, finalAlpha)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, auraR)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgRestore(vg)
end

--- 清除图像缓存
function M.Reset()
    imageCache = {}
end

return M
