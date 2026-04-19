-- Game/LeaderWingEffect.lua
-- 主角(Leader)翅膀精灵图动画特效
-- 配置由 CostumeData 驱动，支持运行时切换时装

local State       = require("Game.State")
local CostumeData = require("Game.CostumeData")

local M = {}

-- 最大整体不透明度（0~1）
local MAX_ALPHA = 0.88

-- 图像句柄缓存：costumeId -> handle
local imageCache = {}

--- 懒加载精灵图（按 costumeId 缓存）
local function EnsureImage(vg, def)
    local id = def.id
    if not imageCache[id] then
        imageCache[id] = nvgCreateImage(vg, def.preview, 0)
    end
    return imageCache[id]
end

--- 绘制单帧（内部辅助）
local function DrawFrame(vg, img, fIdx, gridCols, gridRows, drawLeft, drawTop, dispW, dispH, alpha)
    local fCol   = fIdx % gridCols
    local fRow   = math.floor(fIdx / gridCols)
    local sheetW = dispW * gridCols
    local sheetH = dispH * gridRows
    local patOx  = drawLeft - fCol * dispW
    local patOy  = drawTop  - fRow * dispH
    local paint  = nvgImagePattern(vg, patOx, patOy, sheetW, sheetH, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, drawLeft, drawTop, dispW, dispH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制主角翅膀（需在 DrawTowerIcon 之前调用）
---@param vg any      NanoVG 上下文
---@param x number    主角中心 x（屏幕坐标）
---@param y number    主角中心 y（屏幕坐标，含漂浮偏移）
---@param size number 塔基础尺寸（Config.CELL_SIZE * 0.8）
function M.Draw(vg, x, y, size)
    -- 读取当前装备的翅膀定义
    local def = CostumeData.GetEquippedDef("wing")
    if not def then return end   -- 未装备翅膀则不绘制

    local img = EnsureImage(vg, def)
    if not img or img <= 0 then return end

    local gridCols   = def.gridCols   or 2
    local gridRows   = def.gridRows   or 2
    local frameCount = def.frameCount or 4
    local frames     = def.frames     -- 可选：指定播放帧子集
    local fps        = def.fps        or 1.2

    -- 决定实际帧数量
    local playCount = frames and #frames or frameCount
    local fps_eff   = fps

    -- 连续时间轴
    local t        = (State.time * fps_eff) % playCount
    local curSlot  = math.floor(t)
    local nextSlot = (curSlot + 1) % playCount
    local blend    = t - curSlot

    -- 映射到精灵图实际帧索引（0-based）
    local curIdx  = frames and frames[curSlot  + 1] or curSlot
    local nextIdx = frames and frames[nextSlot + 1] or nextSlot

    -- 呼吸缩放（±3%）
    local breath   = 1.0 + math.sin(State.time * 1.8) * 0.03
    local dispW    = size * 1.4 * breath
    local dispH    = size * 1.4 * breath
    local drawLeft = x - dispW * 0.5
    local drawTop  = y - dispH * 0.5 - size * 0.05

    -- 交叉淡入淡出补帧
    DrawFrame(vg, img, curIdx,  gridCols, gridRows, drawLeft, drawTop, dispW, dispH, MAX_ALPHA * (1 - blend))
    DrawFrame(vg, img, nextIdx, gridCols, gridRows, drawLeft, drawTop, dispW, dispH, MAX_ALPHA * blend)
end

--- 清除图像缓存（换装后调用可强制重载）
function M.Reset()
    imageCache = {}
end

return M
