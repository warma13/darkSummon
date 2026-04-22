-- Game/Renderer_Towers.lua
-- 塔渲染：背景、路径、网格、塔图标、塔绘制

return function(Renderer, ctx)

local Config      = require("Game.Config")
local State       = require("Game.State")
local Grid        = require("Game.Grid")
local SpriteSheet = ctx.SpriteSheet
local rgba        = ctx.rgba
local HeroAnim         = require("Game.HeroAnim")
local LeaderWingEffect = require("Game.LeaderWingEffect")
local Debuff           = require("Game.Debuff")
local Tower            = require("Game.Tower")

-- 星级字符串缓存（避免每帧 string.rep）
local starStrCache = {}
for i = 1, 10 do starStrCache[i] = string.rep("★", i) end

-- 背景图片 handle（仅本模块使用）
local bgImageHandle = -1

---@diagnostic disable: undefined-global
local cjson = cjson  -- 引擎内置全局变量
---@diagnostic enable: undefined-global

-- 背景遮罩透明度（0~255，默认100）
Renderer.bgOverlayAlpha = 230  -- 默认90%（0.9*255≈230）
-- 翎嫣光环圈常显开关（默认开启）
Renderer.showNatureAuraRing = false
-- 增减益标签显示开关（默认开启）
Renderer.showBuffDebuffLabels = true

local BG_SETTINGS_FILE = "bg_settings.json"

function Renderer.LoadBgSettings()
    if not fileSystem:FileExists(BG_SETTINGS_FILE) then return end
    local f = File:new(BG_SETTINGS_FILE, FILE_READ)
    if f then
        local raw = f:ReadString()
        f:Close()
        local ok, data = pcall(cjson.decode, raw)
        if ok and data then
            if data.overlayAlpha then
                Renderer.bgOverlayAlpha = math.floor(math.max(0, math.min(255, data.overlayAlpha)))
            end
            if data.showNatureAuraRing ~= nil then
                Renderer.showNatureAuraRing = data.showNatureAuraRing
            end
            if data.showBuffDebuffLabels ~= nil then
                Renderer.showBuffDebuffLabels = data.showBuffDebuffLabels
            end
        end
    end
end

function Renderer.SaveBgSettings()
    local f = File:new(BG_SETTINGS_FILE, FILE_WRITE)
    if f then
        f:WriteString(cjson.encode({
            overlayAlpha         = Renderer.bgOverlayAlpha,
            showNatureAuraRing   = Renderer.showNatureAuraRing,
            showBuffDebuffLabels = Renderer.showBuffDebuffLabels,
        }))
        f:Close()
    end
end

function Renderer.SetBgOverlayAlpha(alpha)
    Renderer.bgOverlayAlpha = math.floor(math.max(0, math.min(255, alpha)))
    Renderer.SaveBgSettings()
end

function Renderer.SetShowNatureAuraRing(show)
    Renderer.showNatureAuraRing = show
    Renderer.SaveBgSettings()
end

function Renderer.SetShowBuffDebuffLabels(show)
    Renderer.showBuffDebuffLabels = show
    Renderer.SaveBgSettings()
end

Renderer.LoadBgSettings()

function Renderer.DrawBackground(vg, w, h)
    Renderer._screenW = w
    Renderer._screenH = h
    -- 渐变底色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    local grad = nvgLinearGradient(vg, 0, 0, 0, h,
        rgba(Config.COLORS.bg),
        rgba(Config.COLORS.bgGrad))
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 背景图片（cover 模式）
    if bgImageHandle <= 0 then
        bgImageHandle = nvgCreateImage(vg, "image/battle_bg.png", 0)
    end
    if bgImageHandle > 0 then
        local imgW, imgH = nvgImageSize(vg, bgImageHandle)
        -- cover：保持比例填满区域
        local scale = math.max(w / imgW, h / imgH)
        local sw, sh = imgW * scale, imgH * scale
        local ox, oy = (w - sw) * 0.5, (h - sh) * 0.5
        local pat = nvgImagePattern(vg, ox, oy, sw, sh, 0, bgImageHandle, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, pat)
        nvgFill(vg)
    end

    -- 黑色半透明遮罩（透明度可调）
    if Renderer.bgOverlayAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        local bgc = Config.COLORS.bg
        nvgFillColor(vg, nvgRGBA(bgc[1], bgc[2], bgc[3], Renderer.bgOverlayAlpha))
        nvgFill(vg)
    end
end

--- 绘制路径
function Renderer.DrawPath(vg, ox, oy)
    local wps = Config.PATH_WAYPOINTS
    if #wps < 2 then return end

    local x0, y0 = Grid.WaypointToScreen(wps[1], ox, oy)

    -- 第1层: 路径边框（最宽，先画）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x0, y0)
    for i = 2, #wps do
        local x, y = Grid.WaypointToScreen(wps[i], ox, oy)
        nvgLineTo(vg, x, y)
    end
    if Config.PATH_LOOP then
        nvgClosePath(vg)
    end
    nvgStrokeWidth(vg, Config.CELL_SIZE * 0.9)
    nvgStrokeColor(vg, rgba(Config.COLORS.pathBorder))
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 第2层: 路径填充（后画，覆盖边框中心）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x0, y0)
    for i = 2, #wps do
        local x, y = Grid.WaypointToScreen(wps[i], ox, oy)
        nvgLineTo(vg, x, y)
    end
    if Config.PATH_LOOP then
        nvgClosePath(vg)
    end
    nvgStrokeWidth(vg, Config.CELL_SIZE * 0.75)
    nvgStrokeColor(vg, rgba(Config.COLORS.pathColor))
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
end

--- 绘制网格
function Renderer.DrawGrid(vg, ox, oy)
    -- 网格区域半透明底色（略微透出背景图）
    local gw = Config.GRID_COLS * Config.CELL_SIZE
    local gh = Config.GRID_ROWS * Config.CELL_SIZE
    nvgBeginPath(vg)
    nvgRect(vg, ox, oy, gw, gh)
    local bgc = Config.COLORS.bg
    nvgFillColor(vg, nvgRGBA(bgc[1], bgc[2], bgc[3], 200))
    nvgFill(vg)

    -- 合并绘制：所有非路径格子背景 → 一次 fill，边框 → 一次 stroke
    local half = Config.CELL_SIZE * 0.5 - 2
    local cellW = half * 2

    -- 批量填充背景
    nvgBeginPath(vg)
    for c = 1, Config.GRID_COLS do
        for r = 1, Config.GRID_ROWS do
            if not Grid.IsPathCell(c, r) then
                local cx, cy = Grid.CellToScreen(c, r, ox, oy)
                nvgRoundedRect(vg, cx - half, cy - half, cellW, cellW, 4)
            end
        end
    end
    nvgFillColor(vg, rgba(Config.COLORS.gridCell))
    nvgFill(vg)

    -- 批量描边边框
    nvgBeginPath(vg)
    for c = 1, Config.GRID_COLS do
        for r = 1, Config.GRID_ROWS do
            if not Grid.IsPathCell(c, r) then
                local cx, cy = Grid.CellToScreen(c, r, ox, oy)
                nvgRoundedRect(vg, cx - half, cy - half, cellW, cellW, 4)
            end
        end
    end
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, rgba(Config.COLORS.gridLine))
    nvgStroke(vg)

end

--- 绘制塔图标（alpha: 0~255，默认255不透明，towerRef 可选的塔引用）
local function DrawTowerIcon(vg, icon, x, y, size, color, star, alpha, towerRef)
    alpha = alpha or 255
    local r, g, b = color[1], color[2], color[3]
    local a2 = math.floor(alpha * 0.7)  -- 次要元素透明度

    -- 有精灵图的角色：使用 SpriteSheet 模块绘制
    if SpriteSheet.Has(icon) then
        local drawSize = size * 1.1
        -- 攻击时切换到帧1（攻击姿势），否则帧0（待机）
        local frameIdx = 0
        if towerRef and towerRef.attackAnimTimer and towerRef.attackAnimTimer > 0 then
            frameIdx = 1
        end
        -- 朝向翻转（由 Combat 层更新 tower.faceLeft，渲染层只读）
        local flipX = towerRef and towerRef.faceLeft or false
        SpriteSheet.DrawEx(vg, icon, frameIdx, x, y, drawSize, alpha, flipX)
        -- 星级标记仍然用矢量绘制
        if star and star > 0 then
            nvgFontFaceId(vg, Renderer.fontId)
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(
                Config.COLORS.starColor[1], Config.COLORS.starColor[2],
                Config.COLORS.starColor[3], alpha))
            nvgText(vg, x, y + drawSize * 0.5 + 2, starStrCache[star] or string.rep("\u{2605}", star), nil)
        end
        return
    end

    if icon == "grunt" then
        -- 骷髅小兵：骷髅头形（圆头+下颚）
        nvgBeginPath(vg)
        nvgCircle(vg, x, y - size * 0.08, size * 0.3)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 眼窝
        nvgBeginPath(vg)
        nvgCircle(vg, x - size * 0.1, y - size * 0.12, size * 0.07)
        nvgCircle(vg, x + size * 0.1, y - size * 0.12, size * 0.07)
        nvgFillColor(vg, nvgRGBA(20, 10, 10, alpha))
        nvgFill(vg)
        -- 下颚
        nvgBeginPath(vg)
        nvgRect(vg, x - size * 0.15, y + size * 0.12, size * 0.3, size * 0.1)
        nvgFillColor(vg, nvgRGBA(r - 30, g - 30, b - 30, a2))
        nvgFill(vg)

    elseif icon == "bat_m" then
        -- 蝙蝠：展翅形
        local s = size * 0.38
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s * 0.3)
        nvgLineTo(vg, x - s * 1.2, y - s * 0.8)
        nvgLineTo(vg, x - s * 0.7, y)
        nvgLineTo(vg, x - s * 1.0, y + s * 0.3)
        nvgLineTo(vg, x - s * 0.3, y + s * 0.1)
        nvgLineTo(vg, x, y + s * 0.4)
        nvgLineTo(vg, x + s * 0.3, y + s * 0.1)
        nvgLineTo(vg, x + s * 1.0, y + s * 0.3)
        nvgLineTo(vg, x + s * 0.7, y)
        nvgLineTo(vg, x + s * 1.2, y - s * 0.8)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 眼睛
        nvgBeginPath(vg)
        nvgCircle(vg, x - size * 0.06, y - size * 0.02, size * 0.04)
        nvgCircle(vg, x + size * 0.06, y - size * 0.02, size * 0.04)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, alpha))
        nvgFill(vg)

    elseif icon == "hound" then
        -- 地狱犬：犬头+火焰尾
        local s = size * 0.35
        nvgBeginPath(vg)
        nvgEllipse(vg, x, y, s * 1.1, s * 0.7)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 耳朵
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.5, y - s * 0.5)
        nvgLineTo(vg, x - s * 0.8, y - s * 1.1)
        nvgLineTo(vg, x - s * 0.1, y - s * 0.6)
        nvgClosePath(vg)
        nvgMoveTo(vg, x + s * 0.5, y - s * 0.5)
        nvgLineTo(vg, x + s * 0.8, y - s * 1.1)
        nvgLineTo(vg, x + s * 0.1, y - s * 0.6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 火焰眼
        nvgBeginPath(vg)
        nvgCircle(vg, x - s * 0.3, y - s * 0.1, s * 0.15)
        nvgCircle(vg, x + s * 0.3, y - s * 0.1, s * 0.15)
        nvgFillColor(vg, nvgRGBA(255, 160, 30, alpha))
        nvgFill(vg)

    elseif icon == "archer" then
        -- 骷髅弓手：十字准星
        local s = size * 0.4
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s, y)
        nvgLineTo(vg, x + s, y)
        nvgMoveTo(vg, x, y - s)
        nvgLineTo(vg, x, y + s)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, size * 0.15)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

    elseif icon == "demon" then
        -- 恶魔领主：菱形
        local s = size * 0.4
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s)
        nvgLineTo(vg, x + s, y)
        nvgLineTo(vg, x, y + s)
        nvgLineTo(vg, x - s, y)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

    elseif icon == "assassin" then
        -- 暗影刺客：匕首形
        local s = size * 0.4
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s)
        nvgLineTo(vg, x + s * 0.3, y + s * 0.2)
        nvgLineTo(vg, x, y + s * 0.6)
        nvgLineTo(vg, x - s * 0.3, y + s * 0.2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 剑柄
        nvgBeginPath(vg)
        nvgRect(vg, x - s * 0.35, y + s * 0.15, s * 0.7, size * 0.06)
        nvgFillColor(vg, nvgRGBA(r, g, b, a2))
        nvgFill(vg)

    elseif icon == "golem" then
        -- 石像鬼：方块体 + 肩甲
        local s = size * 0.32
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - s, y - s * 0.8, s * 2, s * 1.8, 3)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 肩甲
        nvgBeginPath(vg)
        nvgRect(vg, x - s * 1.3, y - s * 0.7, s * 0.5, s * 0.8)
        nvgRect(vg, x + s * 0.8, y - s * 0.7, s * 0.5, s * 0.8)
        nvgFillColor(vg, nvgRGBA(r - 20, g - 20, b, a2))
        nvgFill(vg)
        -- 眼睛
        nvgBeginPath(vg)
        nvgCircle(vg, x - s * 0.35, y - s * 0.2, s * 0.15)
        nvgCircle(vg, x + s * 0.35, y - s * 0.2, s * 0.15)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, alpha))
        nvgFill(vg)

    elseif icon == "necro" then
        -- 亡灵法师：扇形+暗能量
        nvgBeginPath(vg)
        nvgArc(vg, x, y, size * 0.35, 0, math.pi * 1.5, 1)
        nvgLineTo(vg, x, y)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

    elseif icon == "flame" then
        -- 炎魔：火焰三角
        local s = size * 0.4
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s)
        nvgLineTo(vg, x + s * 0.7, y + s * 0.6)
        nvgLineTo(vg, x - s * 0.7, y + s * 0.6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s * 0.4)
        nvgLineTo(vg, x + s * 0.3, y + s * 0.4)
        nvgLineTo(vg, x - s * 0.3, y + s * 0.4)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, a2))
        nvgFill(vg)

    elseif icon == "knight" then
        -- 死亡骑士：盾牌形
        local s = size * 0.38
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s, y - s * 0.8)
        nvgLineTo(vg, x + s, y - s * 0.8)
        nvgLineTo(vg, x + s, y + s * 0.2)
        nvgLineTo(vg, x, y + s * 0.9)
        nvgLineTo(vg, x - s, y + s * 0.2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 十字纹
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s * 0.5)
        nvgLineTo(vg, x, y + s * 0.4)
        nvgMoveTo(vg, x - s * 0.4, y - s * 0.1)
        nvgLineTo(vg, x + s * 0.4, y - s * 0.1)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, a2))
        nvgStroke(vg)

    elseif icon == "witch" then
        -- 女巫：尖帽+圆脸
        local s = size * 0.35
        -- 帽子
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - s * 1.3)
        nvgLineTo(vg, x + s * 0.6, y - s * 0.2)
        nvgLineTo(vg, x - s * 0.6, y - s * 0.2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 脸
        nvgBeginPath(vg)
        nvgCircle(vg, x, y + s * 0.2, s * 0.5)
        nvgFillColor(vg, nvgRGBA(r + 30, g + 30, b + 30, alpha))
        nvgFill(vg)

    elseif icon == "drummer" then
        -- 战鼓手：鼓形
        local s = size * 0.35
        nvgBeginPath(vg)
        nvgEllipse(vg, x, y, s * 0.9, s * 0.6)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 鼓棒
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.5, y - s * 0.9)
        nvgLineTo(vg, x - s * 0.1, y - s * 0.1)
        nvgMoveTo(vg, x + s * 0.5, y - s * 0.9)
        nvgLineTo(vg, x + s * 0.1, y - s * 0.1)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha))
        nvgStroke(vg)
        -- 鼓棒头
        nvgBeginPath(vg)
        nvgCircle(vg, x - s * 0.5, y - s * 0.9, s * 0.12)
        nvgCircle(vg, x + s * 0.5, y - s * 0.9, s * 0.12)
        nvgFillColor(vg, nvgRGBA(255, 200, 100, alpha))
        nvgFill(vg)

    elseif icon == "mage" then
        -- 暗影法师：双环
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, size * 0.35)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, size * 0.45)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, a2))
        nvgStroke(vg)

    elseif icon == "hunter" then
        -- 暗夜猎手：弓形
        local s = size * 0.4
        nvgBeginPath(vg)
        nvgArc(vg, x + s * 0.2, y, s * 0.8, -math.pi * 0.6, math.pi * 0.6, 2)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha))
        nvgStroke(vg)
        -- 弦
        nvgBeginPath(vg)
        local yOff = s * 0.8 * math.sin(math.pi * 0.6)
        nvgMoveTo(vg, x + s * 0.2 + s * 0.8 * math.cos(math.pi * 0.6), y - yOff)
        nvgLineTo(vg, x + s * 0.2 + s * 0.8 * math.cos(math.pi * 0.6), y + yOff)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, a2))
        nvgStroke(vg)
        -- 箭头
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.6, y)
        nvgLineTo(vg, x + s * 0.4, y)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.6, y)
        nvgLineTo(vg, x - s * 0.35, y - s * 0.15)
        nvgLineTo(vg, x - s * 0.35, y + s * 0.15)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

    elseif icon == "plague" then
        -- 瘟疫使者：毒瓶/骷髅毒气
        local s = size * 0.32
        -- 瓶身
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - s * 0.6, y - s * 0.2, s * 1.2, s * 1.3, 4)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 瓶颈
        nvgBeginPath(vg)
        nvgRect(vg, x - s * 0.2, y - s * 0.7, s * 0.4, s * 0.55)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 毒气冒泡
        nvgBeginPath(vg)
        nvgCircle(vg, x - s * 0.2, y - s * 0.9, s * 0.12)
        nvgCircle(vg, x + s * 0.15, y - s * 1.0, s * 0.1)
        nvgCircle(vg, x, y - s * 1.15, s * 0.08)
        nvgFillColor(vg, nvgRGBA(r, g + 40, b, a2))
        nvgFill(vg)

    elseif icon == "storm" then
        -- 风暴领主：闪电形
        local s = size * 0.4
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.1, y - s)
        nvgLineTo(vg, x + s * 0.5, y - s)
        nvgLineTo(vg, x + s * 0.05, y - s * 0.1)
        nvgLineTo(vg, x + s * 0.5, y - s * 0.1)
        nvgLineTo(vg, x - s * 0.15, y + s)
        nvgLineTo(vg, x + s * 0.05, y + s * 0.05)
        nvgLineTo(vg, x - s * 0.4, y + s * 0.05)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

    elseif icon == "archangel" then
        -- 堕天使：翅膀+光环
        local s = size * 0.35
        -- 光环
        nvgBeginPath(vg)
        nvgEllipse(vg, x, y - s * 1.1, s * 0.5, s * 0.15)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha))
        nvgStroke(vg)
        -- 身体
        nvgBeginPath(vg)
        nvgCircle(vg, x, y - s * 0.2, s * 0.4)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 翅膀
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.3, y - s * 0.1)
        nvgLineTo(vg, x - s * 1.3, y - s * 0.6)
        nvgLineTo(vg, x - s * 0.9, y + s * 0.1)
        nvgLineTo(vg, x - s * 0.3, y + s * 0.3)
        nvgClosePath(vg)
        nvgMoveTo(vg, x + s * 0.3, y - s * 0.1)
        nvgLineTo(vg, x + s * 1.3, y - s * 0.6)
        nvgLineTo(vg, x + s * 0.9, y + s * 0.1)
        nvgLineTo(vg, x + s * 0.3, y + s * 0.3)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, a2))
        nvgFill(vg)
        -- 长裙
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.35, y + s * 0.1)
        nvgLineTo(vg, x + s * 0.35, y + s * 0.1)
        nvgLineTo(vg, x + s * 0.5, y + s * 0.9)
        nvgLineTo(vg, x - s * 0.5, y + s * 0.9)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

    elseif icon == "dragon" then
        -- 深渊巨龙：龙头轮廓
        local s = size * 0.38
        -- 龙头
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.8, y - s * 0.2)
        nvgLineTo(vg, x + s * 0.8, y - s * 0.4)
        nvgLineTo(vg, x + s * 1.0, y)
        nvgLineTo(vg, x + s * 0.8, y + s * 0.3)
        nvgLineTo(vg, x - s * 0.3, y + s * 0.5)
        nvgLineTo(vg, x - s * 0.8, y + s * 0.2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 龙角
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.3, y - s * 0.2)
        nvgLineTo(vg, x - s * 0.5, y - s * 1.0)
        nvgLineTo(vg, x, y - s * 0.3)
        nvgClosePath(vg)
        nvgMoveTo(vg, x + s * 0.2, y - s * 0.35)
        nvgLineTo(vg, x + s * 0.1, y - s * 1.1)
        nvgLineTo(vg, x + s * 0.5, y - s * 0.35)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 龙眼
        nvgBeginPath(vg)
        nvgCircle(vg, x + s * 0.3, y - s * 0.1, s * 0.12)
        nvgFillColor(vg, nvgRGBA(255, 200, 0, alpha))
        nvgFill(vg)

    elseif icon == "weaver" then
        -- 命运织者：沙漏形
        local s = size * 0.35
        -- 上三角
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.8, y - s * 0.9)
        nvgLineTo(vg, x + s * 0.8, y - s * 0.9)
        nvgLineTo(vg, x, y)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 下三角
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y)
        nvgLineTo(vg, x + s * 0.8, y + s * 0.9)
        nvgLineTo(vg, x - s * 0.8, y + s * 0.9)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, a2))
        nvgFill(vg)
        -- 中心光点
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, s * 0.15)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, alpha))
        nvgFill(vg)

    elseif icon == "archfiend" then
        -- 深渊魔神：恶魔五角星+双角
        local s = size * 0.4
        -- 五角星
        nvgBeginPath(vg)
        for i = 0, 4 do
            local angle = -math.pi / 2 + i * math.pi * 2 / 5
            local px = x + math.cos(angle) * s
            local py = y + math.sin(angle) * s
            if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
        -- 内圈
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, s * 0.4)
        nvgFillColor(vg, nvgRGBA(40, 10, 10, alpha))
        nvgFill(vg)
        -- 恶魔角
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - s * 0.4, y - s * 0.7)
        nvgLineTo(vg, x - s * 0.6, y - s * 1.3)
        nvgLineTo(vg, x - s * 0.15, y - s * 0.8)
        nvgClosePath(vg)
        nvgMoveTo(vg, x + s * 0.4, y - s * 0.7)
        nvgLineTo(vg, x + s * 0.6, y - s * 1.3)
        nvgLineTo(vg, x + s * 0.15, y - s * 0.8)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
    else
        -- 未知图标 fallback：简单圆形
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, size * 0.3)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
    end

    -- 星级标记
    if star and star > 0 then
        nvgFontFaceId(vg, Renderer.fontId)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(
            Config.COLORS.starColor[1], Config.COLORS.starColor[2],
            Config.COLORS.starColor[3], alpha))
        local starStr = starStrCache[star] or string.rep("\u{2605}", star)
        nvgText(vg, x, y + size * 0.5 + 2, starStr, nil)
    end
end

--- 绘制所有塔
function Renderer.DrawTowers(vg, ox, oy)
    for _, tower in ipairs(State.towers) do
        local cx, cy = Grid.CellToScreen(tower.col, tower.row, ox, oy)
        local size = Config.CELL_SIZE * 0.8
        local gc = tower.typeDef.glowColor

        -- 翎嫣自然光环圈（常显，可在设置中控制显隐）
        -- 在最底层绘制，不受漂浮/缩放动画影响
        if Renderer.showNatureAuraRing and tower.typeDef.special == "nature_aura" then
            local auraR = tower.typeDef.auraRange or 120
            -- 以被动脉冲周期（baseSpeed 1.5s）为动画频率
            local period   = tower.typeDef.baseSpeed or 1.5
            local phase    = (State.time % period) / period        -- 0→1 循环
            local pulse    = math.sin(phase * math.pi * 2) * 0.5 + 0.5  -- 0→1→0

            -- 柔光填充（极低透明度，随脉冲微动）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, auraR)
            nvgFillColor(vg, nvgRGBA(80, 220, 130, math.floor(10 + pulse * 10)))
            nvgFill(vg)

            -- 主轮廓描边（随脉冲亮度变化）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, auraR)
            nvgStrokeWidth(vg, 1.5)
            nvgStrokeColor(vg, nvgRGBA(100, 235, 150, math.floor(90 + pulse * 70)))
            nvgStroke(vg)

            -- 外扩波纹（从边缘向外扩散后消失，模拟脉冲发出）
            local waveR     = auraR + phase * 20
            local waveAlpha = math.floor((1 - phase) * 60)
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, waveR)
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBA(140, 255, 170, waveAlpha))
            nvgStroke(vg)
        end

        -- 获取每塔独立的呼吸/攻击动画变换
        local ha = HeroAnim.GetDrawTransform(tower)

        -- 精灵图角色待机漂浮动画（per-tower 独立相位，避免所有英雄同步）
        local hasSprite = SpriteSheet.Has(tower.typeDef.icon)
        local isDragged = State.dragging and State.dragTower and State.dragTower.id == tower.id
        if hasSprite and not isDragged then
            cy = cy + ha.bobY
        end

        local towerAlpha = isDragged and 80 or 255

        -- 出生动画缩放
        local scale = 1.0
        if tower.spawnTime > 0 then
            local t = tower.spawnTime / 0.5
            scale = 1.0 + t * 0.5
        end

        -- 底部浮动阴影（椭圆，随漂浮动画缩放）
        local floatPhase = ha.floatPhase          -- -1~1，与 bobY 同相位
        local shadowScaleX = 1.0 - floatPhase * 0.12  -- 漂浮高时阴影小
        local shadowAlpha = isDragged and 20 or math.floor(80 - floatPhase * 25)
        local shadowRx = Config.CELL_SIZE * 0.3 * shadowScaleX
        local shadowRy = Config.CELL_SIZE * 0.1 * shadowScaleX
        -- 阴影固定在格子底部（不随漂浮上下移动）
        local _, baseCy = Grid.CellToScreen(tower.col, tower.row, ox, oy)
        local shadowY = baseCy + Config.CELL_SIZE * 0.32
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, shadowY, shadowRx, shadowRy)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowAlpha))
        nvgFill(vg)

        -- 选中高亮（非拖拽中才显示攻击范围）
        if not isDragged and State.selectedTower and State.selectedTower.id == tower.id then
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, tower.range)
            nvgStrokeWidth(vg, 1)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
            nvgStroke(vg)
        end

        -- 主角翅膀特效（在 nvgSave/Scale 块之外绘制，不受攻击压缩影响）
        if tower.typeDef.isLeader and not isDragged then
            LeaderWingEffect.Draw(vg, cx, cy, size)
        end

        -- 塔图标（出生缩放 × 攻击压缩弹出，锚点在脚底）
        nvgSave(vg)
        local totalScaleX = scale * ha.scaleX
        local totalScaleY = scale * ha.scaleY
        if totalScaleX ~= 1.0 or totalScaleY ~= 1.0 then
            local spriteHalf = size * 1.1 * 0.5   -- DrawTowerIcon 内部 drawSize = size*1.1
            local pivotY = cy + spriteHalf         -- 脚底锚点
            nvgTranslate(vg, cx, pivotY)
            nvgScale(vg, totalScaleX, totalScaleY)
            nvgTranslate(vg, -cx, -pivotY)
        end
        DrawTowerIcon(vg, tower.typeDef.icon, cx, cy, size, tower.typeDef.color, tower.star, towerAlpha, tower)
        nvgRestore(vg)

        -- ─── 头顶文字标签（减益 + 增益） ───
        if not isDragged and Renderer.fontId >= 0 and Renderer.showBuffDebuffLabels then
            local labels = {}  -- { text, r, g, b }

            -- ── 减益 ──
            if Debuff.Has(tower, "shackle") then
                labels[#labels + 1] = { "禁锢", 40, 160, 60 }
            end
            if Debuff.Has(tower, "silence") then
                labels[#labels + 1] = { "沉默", 140, 50, 200 }
            end
            if Tower.HasDebuff(tower, "emerald_decay_atk") then
                labels[#labels + 1] = { "衰竭", 100, 140, 40 }
            end

            -- ── 增益（仅显示重要状态：免控、层数、临时增益） ──
            -- 翠意庇护 → 显示"免控"（翎嫣免疫沉默+禁锢）
            if tower.verdantActive then
                labels[#labels + 1] = { "免控", 255, 220, 80 }
            end
            -- 翎嫣鲜花环（+攻击力临时增益）
            if tower.wreathActive then
                labels[#labels + 1] = { "鲜花环", 255, 150, 200 }
            end
            -- 绯夜缚瞳锁定层数（代码内部名 bloodEye，技能名"缚瞳锁定"）
            if (tower.bloodEyeStacks or 0) > 0 then
                labels[#labels + 1] = { "缚瞳x" .. tower.bloodEyeStacks, 220, 40, 60 }
            end
            -- 影法师灵魂收割层数
            if (tower.soulReapStacks or 0) > 0 then
                labels[#labels + 1] = { "收割x" .. tower.soulReapStacks, 180, 60, 220 }
            end
            -- 永恒大魔击杀层数
            if (tower.killAtkStacks or 0) > 0 then
                labels[#labels + 1] = { "杀意x" .. tower.killAtkStacks, 200, 50, 50 }
            end
            -- 英勇战歌（战鼓祭司全体主动技，临时增益）
            if State.heroicAnthemBuff then
                labels[#labels + 1] = { "战歌", 255, 220, 100 }
            end

            if #labels > 0 then
                nvgFontFaceId(vg, Renderer.fontId)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                local labelY = cy - size * 0.55 - 2
                for idx = #labels, 1, -1 do
                    local lb = labels[idx]
                    local yPos = labelY - (idx - 1) * 13
                    local pulse = math.sin(State.time * 3.5 + idx * 1.2) * 0.2 + 0.8
                    local a = math.floor(220 * pulse)
                    nvgFontSize(vg, 10)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
                    nvgText(vg, cx + 1, yPos + 1, lb[1], nil)
                    nvgFillColor(vg, nvgRGBA(lb[2], lb[3], lb[4], a))
                    nvgText(vg, cx, yPos, lb[1], nil)
                end
            end
        end

        -- 等级小字（非拖拽时显示）
        if not isDragged and tower.heroLevel and tower.heroLevel > 1 and Renderer.fontId >= 0 then
            nvgFontFaceId(vg, Renderer.fontId)
            nvgFontSize(vg, 8)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(180, 180, 200, 160))
            nvgText(vg, cx, cy + size * 0.5 + 10, "Lv." .. tower.heroLevel, nil)
        end
    end
end

--- 绘制敌人形状

-- 导出 DrawTowerIcon（Draw 模块的 DrawDragOverlay 需要）
ctx.DrawTowerIcon = DrawTowerIcon

end
