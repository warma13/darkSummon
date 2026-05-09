-- Game/Renderer_OverlayUI.lua
-- 棋盘覆盖 UI: 遗物充能条、训练木桩调控面板

return function(Renderer, ctx)

local Config       = require("Game.Config")
local State        = require("Game.State")
local RelicEffects = require("Game.RelicEffects")
local RelicData    = require("Game.RelicData")
local FormatUtil   = require("Game.FormatUtil")

-- 从 ctx 获取共享工具函数
local EnsureMobImage = ctx.EnsureMobImage
local DrawMobImage   = ctx.DrawMobImage

-- TrainingDummyData 延迟 require
local _TDD
local function GetTDD()
    if not _TDD then _TDD = require("Game.TrainingDummyData") end
    return _TDD
end

-- ============================================================================
-- 遗物充能条（棋盘下方）
-- ============================================================================

local _relicChargeGlowTime = 0

function Renderer.DrawRelicChargeBar(vg, ox, oy)

    local charge = RelicEffects.GetChargeState()
    if not charge or charge.max <= 0 then return end

    -- 检查是否有力量遗物装备且有充能
    local powerRelic = RelicData.GetEquipped("power")
    if not powerRelic then return end
    local relicDef = Config.RELICS and Config.RELICS[powerRelic.id]
    if not relicDef or not relicDef.hasCharge then return end

    local gridW = Config.GRID_COLS * Config.CELL_SIZE
    local gridH = Config.GRID_ROWS * Config.CELL_SIZE

    -- 图标尺寸和位置：棋盘正下方居中
    local iconSize = 36
    local gap = 6
    local cx = ox + gridW * 0.5        -- 水平居中
    local ty = oy + gridH + gap        -- 棋盘下方
    local iconX = cx - iconSize * 0.5
    local iconY = ty

    -- 优先使用遗物专属图片，fallback 到槽位图标
    local relicIcon = relicDef and relicDef.image
    if not relicIcon then
        relicIcon = "image/relic_slot_power_20260424084412.png"
        for _, s in ipairs(Config.RELIC_SLOTS) do
            if s.id == "power" then relicIcon = s.icon; break end
        end
    end
    local img = EnsureMobImage(vg, relicIcon)

    -- 背景暗框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, iconX - 2, iconY - 2, iconSize + 4, iconSize + 4, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 绘制遗物图标（变暗作为底）
    if img > 0 then
        local paint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, img, 0.3)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 4)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- 充能填充（从下往上）
    local pct = math.min(charge.current / charge.max, 1.0)
    local fillH = math.floor(iconSize * pct)
    local fillY = iconY + iconSize - fillH

    if fillH > 0 then
        -- 裁剪区域：只显示下方填充部分
        nvgSave(vg)
        nvgScissor(vg, iconX, fillY, iconSize, fillH)

        -- 亮色图标（被裁剪为充能部分）
        if img > 0 then
            local paint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, img, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 4)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end

        -- 充能色调覆盖
        nvgBeginPath(vg)
        nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 4)
        nvgFillColor(vg, nvgRGBA(180, 120, 255, 40))
        nvgFill(vg)

        nvgRestore(vg)

        -- 充能液面线（发光分界线）
        nvgBeginPath(vg)
        nvgMoveTo(vg, iconX + 2, fillY)
        nvgLineTo(vg, iconX + iconSize - 2, fillY)
        nvgStrokeColor(vg, nvgRGBA(200, 160, 255, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 满充能发光效果
    if charge.ready then
        _relicChargeGlowTime = _relicChargeGlowTime + Renderer.frameDt
        local pulse = 0.5 + 0.5 * math.sin(_relicChargeGlowTime * 4.0)
        local glowAlpha = math.floor(80 + 120 * pulse)

        -- 外发光
        nvgBeginPath(vg)
        nvgRoundedRect(vg, iconX - 4, iconY - 4, iconSize + 8, iconSize + 8, 8)
        nvgStrokeColor(vg, nvgRGBA(220, 180, 255, glowAlpha))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
    else
        _relicChargeGlowTime = 0
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, iconX - 1, iconY - 1, iconSize + 2, iconSize + 2, 5)
    nvgStrokeColor(vg, nvgRGBA(150, 120, 200, charge.ready and 255 or 120))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 充能数字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 180, 255, charge.ready and 255 or 180))
    nvgText(vg, cx, iconY + iconSize + 3,
        charge.ready and "MAX" or (math.floor(charge.current) .. "/" .. math.floor(charge.max)))

    -- 释放爆发特效（冲击波 + 闪光）
    local castFX = State.relicCastFX
    if castFX and castFX.timer > 0 then
        local progress = 1.0 - (castFX.timer / castFX.maxTimer)  -- 0→1
        local fadeOut = math.max(0, castFX.timer / castFX.maxTimer)  -- 1→0

        -- 扩散冲击波环
        local maxRadius = iconSize * 2.5
        local ringRadius = iconSize * 0.5 + maxRadius * progress
        local ringAlpha = math.floor(200 * fadeOut)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, iconY + iconSize * 0.5, ringRadius)
        nvgStrokeColor(vg, nvgRGBA(220, 180, 255, ringAlpha))
        nvgStrokeWidth(vg, 2.5 * fadeOut)
        nvgStroke(vg)

        -- 第二层内环（稍快扩散）
        local innerRadius = iconSize * 0.3 + maxRadius * 0.7 * progress
        local innerAlpha = math.floor(140 * fadeOut)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, iconY + iconSize * 0.5, innerRadius)
        nvgStrokeColor(vg, nvgRGBA(180, 140, 255, innerAlpha))
        nvgStrokeWidth(vg, 1.5 * fadeOut)
        nvgStroke(vg)

        -- 图标区域强闪光（前半段）
        if progress < 0.4 then
            local flashAlpha = math.floor(180 * (1.0 - progress / 0.4))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX - 3, iconY - 3, iconSize + 6, iconSize + 6, 7)
            nvgFillColor(vg, nvgRGBA(255, 230, 255, flashAlpha))
            nvgFill(vg)
        end
    end
end

-- ============================================================================
-- 训练木桩 · 实时调控面板（棋盘下方）
-- ============================================================================

function Renderer.DrawTrainingDummyPanel(vg, ox, oy)
    local td = State.trainingDummy
    if not td then return end

    local gridW = Config.GRID_COLS * Config.CELL_SIZE
    local gridH = Config.GRID_ROWS * Config.CELL_SIZE

    -- 面板位置：棋盘下方，遗物图标再下方
    local panelY = oy + gridH + 58
    local panelX = ox

    -- 3 列 × 2 行
    local cols = 3
    local rows = 2
    local gapX, gapY = 6, 4
    local btnW = math.floor((gridW - gapX * (cols - 1)) / cols)
    local btnH = 28

    -- 半透明背景
    local bgH = rows * btnH + (rows - 1) * gapY + 8
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX - 4, panelY - 4, gridW + 8, bgH, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
    nvgFill(vg)

    -- 6 个按钮定义：{ label, color, action }
    local buttons = {
        -- 第 1 行
        { td.movingEnabled and "运动:开" or "运动:关",
          td.movingEnabled and { 60, 180, 80 } or { 120, 120, 120 }, 1 },
        { "防御 " .. FormatUtil.FormatNum(td.curDEF),
          td.curDEF ~= td.initDEF and { 200, 140, 40 } or { 100, 100, 140 }, 2 },
        { "魔抗 " .. FormatUtil.FormatNum(td.curRES),
          td.curRES ~= td.initRES and { 140, 80, 200 } or { 100, 100, 140 }, 3 },
        -- 第 2 行
        { "+木桩", { 60, 140, 200 }, 4 },
        { "重置", { 160, 120, 40 }, 5 },
        { "清空木桩", { 180, 60, 60 }, 6 },
    }

    local btns = td._buttons or {}
    td._buttons = btns

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for i, def in ipairs(buttons) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = panelX + col * (btnW + gapX)
        local by = panelY + row * (btnH + gapY)
        local c = def[2]

        btns[i] = { x = bx, y = by, w = btnW, h = btnH, action = def[3] }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 180))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, btnW, btnH, 5)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, bx + btnW * 0.5, by + btnH * 0.5, def[1])
    end
    -- 清理多余旧按钮
    for i = #buttons + 1, #btns do btns[i] = nil end
end

end
