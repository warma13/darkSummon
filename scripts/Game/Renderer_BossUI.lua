-- Game/Renderer_BossUI.lua
-- BOSS UI: 血条、出场动画、翠影/憎恨 BOSS 技能特效

return function(Renderer, ctx)

local Config        = require("Game.Config")
local State         = require("Game.State")
local Grid          = require("Game.Grid")
local WorldBossData = require("Game.WorldBossData")
local DamageStats   = require("Game.DamageStats")

-- NanoVG 文本缓存（仅值变化时重新格式化）
local nvgTextCache = {
    bossPct = nil, bossName = nil, bossHpStr = nil,
    bossRemainSec = nil, bossTimeStr = nil,
    -- 憎恨 BOSS 技能缓存
    shackleTough = nil, shackleMax = nil, shackleStr = nil,
    shackleTimer = nil, shackleTimerStr = nil,
    destTough = nil, destMax = nil, destStr = nil,
    destTimer = nil, destTimerStr = nil,
    destRadius = nil, destInfoStr = nil,
}

-- ============================================================================
-- 公共绘制工具
-- ============================================================================

--- 绘制伤害计数器底板（复用于世界BOSS和普通BOSS）
local function DrawDamageCounter(vg, dmgY, dmgStr, barX, barW)
    local dmgBgW = 90
    local dmgBgH = 18
    local dmgBgX = barX + barW - dmgBgW

    nvgBeginPath(vg)
    nvgRoundedRect(vg, dmgBgX, dmgY, dmgBgW, dmgBgH, 4)
    nvgFillColor(vg, nvgRGBA(30, 15, 10, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dmgBgX, dmgY, dmgBgW, dmgBgH, 4)
    nvgStrokeColor(vg, nvgRGBA(255, 100, 50, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFaceId(vg, Renderer.fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 140, 60, 255))
    nvgText(vg, dmgBgX + dmgBgW * 0.5, dmgY + dmgBgH * 0.5, dmgStr, nil)
end

--- 绘制施法阶段屏幕边框描边 + 抖动（复用于翠影/憎恨）
--- @return number pulse 脉动值，供角落发光等后续效果使用
local function DrawCastingBorder(vg, w, h, color, timer, borderW, alphaMax)
    local pulse = 0.3 + 0.7 * math.abs(math.sin(timer * 6))
    local a = math.floor(pulse * alphaMax)
    local cr, cg, cb = color[1], color[2], color[3]

    nvgSave(vg)
    nvgTranslate(vg,
        math.sin(timer * 32) * borderW * 0.5,
        math.cos(timer * 26) * borderW * 0.375)

    nvgBeginPath(vg); nvgRect(vg, 0, 0, w, borderW)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, a)); nvgFill(vg)
    nvgBeginPath(vg); nvgRect(vg, 0, h - borderW, w, borderW)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, a)); nvgFill(vg)
    nvgBeginPath(vg); nvgRect(vg, 0, borderW, borderW, h - borderW * 2)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, a)); nvgFill(vg)
    nvgBeginPath(vg); nvgRect(vg, w - borderW, borderW, borderW, h - borderW * 2)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, a)); nvgFill(vg)

    nvgRestore(vg)
    return pulse
end

-- ============================================================================
-- BOSS 血条 + 倒计时（顶栏下方）
-- ============================================================================

function Renderer.DrawBossBar(vg, w)
    if not State.bossActive then return end

    -- 找到当前存活的 BOSS
    local boss = nil
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isBoss then
            boss = e
            break
        end
    end

    -- 安全区偏移（与顶部 HUD 保持一致）
    local safeTop = 0
    if GetSafeAreaInsets then
        local rect = GetSafeAreaInsets(false)
        safeTop = rect.min.y / graphics:GetDPR()
    end
    local barY = safeTop + 54  -- HUD(safeTop+8+h40) 下方留 6px
    local barH = 22
    local marginX = 12
    local barX = marginX
    local barW = w - marginX * 2

    -- 背景底板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(15, 10, 25, 210))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 6)
    nvgStrokeColor(vg, nvgRGBA(200, 50, 50, 140))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- BOSS 血条（左半部分）
    local hpAreaX = barX + 6
    local hpAreaW = barW * 0.62
    local hpBarY = barY + 5
    local hpBarH = barH - 10

    -- 血条背景槽
    nvgBeginPath(vg)
    nvgRoundedRect(vg, hpAreaX, hpBarY, hpAreaW, hpBarH, 4)
    nvgFillColor(vg, nvgRGBA(40, 20, 20, 200))
    nvgFill(vg)

    if boss then
        local hpRatio = (boss.maxHP == math.huge) and 1.0 or math.max(0, boss.hp / boss.maxHP)

        -- 血条填充（渐变红色）
        local hpFillW = hpAreaW * hpRatio
        if hpFillW > 1 then
            local grad = nvgLinearGradient(vg, hpAreaX, hpBarY, hpAreaX + hpFillW, hpBarY,
                nvgRGBA(220, 50, 30, 255), nvgRGBA(180, 30, 20, 255))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, hpAreaX, hpBarY, hpFillW, hpBarH, 4)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end

        -- 血量百分比文字
        nvgFontFaceId(vg, Renderer.fontId)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        local pct = math.floor(hpRatio * 100)
        if pct ~= nvgTextCache.bossPct or boss.typeDef.name ~= nvgTextCache.bossName then
            nvgTextCache.bossPct = pct
            nvgTextCache.bossName = boss.typeDef.name
            nvgTextCache.bossHpStr = boss.typeDef.name .. "  " .. pct .. "%"
        end
        nvgText(vg, hpAreaX + hpAreaW * 0.5, hpBarY + hpBarH * 0.5,
            nvgTextCache.bossHpStr, nil)
    else
        -- BOSS 已死但倒计时还在（刚击杀瞬间）
        nvgFontFaceId(vg, Renderer.fontId)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
        nvgText(vg, hpAreaX + hpAreaW * 0.5, hpBarY + hpBarH * 0.5, "已击杀!", nil)
    end

    -- 右侧区域
    local rightX = hpAreaX + hpAreaW + 8
    local rightW = barW - hpAreaW - 20
    local remain = math.max(0, State.bossTimer)
    local remainSec = math.floor(remain)
    if remainSec ~= nvgTextCache.bossRemainSec then
        nvgTextCache.bossRemainSec = remainSec
        nvgTextCache.bossTimeStr = string.format("%02d:%02d", math.floor(remainSec / 60), remainSec % 60)
    end
    local timeStr = nvgTextCache.bossTimeStr

    nvgFontFaceId(vg, Renderer.fontId)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 时间不足时闪烁警告
    local timerAlpha = 255
    if remain <= 10 then
        timerAlpha = (math.floor(State.time * 4) % 2 == 0) and 255 or 140
    end

    local isWorldBoss = State.worldBossActive

    -- BOSS 标签 + 倒计时（世界BOSS和普通BOSS共用）
    nvgFontSize(vg, 9)
    nvgFillColor(vg, nvgRGBA(255, 80, 60, timerAlpha))
    nvgText(vg, rightX, barY + barH * 0.3, "BOSS", nil)

    nvgFontSize(vg, 13)
    local tr, tg, tb = 255, 200, 160
    if remain <= 10 then tr, tg, tb = 255, 80, 60 end
    nvgFillColor(vg, nvgRGBA(tr, tg, tb, timerAlpha))
    nvgText(vg, rightX + 30, barY + barH * 0.3, timeStr, nil)

    -- 伤害计数器（世界BOSS始终显示，普通BOSS有伤害时显示）
    local totalDmg
    if isWorldBoss then
        totalDmg = State.worldBossTotalDamage or 0
    else
        totalDmg = DamageStats.GetTotalBossDmg()
    end
    if totalDmg > 0 then
        local dmgY = barY + barH + 3
        local dmgStr = "伤害 " .. WorldBossData.FormatDamage(totalDmg)
        DrawDamageCounter(vg, dmgY, dmgStr, barX, barW)
    end

    -- 剩余时间进度条（仅普通BOSS）
    if not isWorldBoss then
        local timerBarX = rightX
        local timerBarW = rightW
        local timerBarY = barY + barH * 0.65
        local timerBarH = 3
        local maxTimer = State.bossTimerMax or Config.BOSS_TIMER_MAX
        local timerRatio = remain / maxTimer
        local tr2, tg2, tb2 = 255, 200, 160
        if remain <= 10 then tr2, tg2, tb2 = 255, 80, 60 end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, timerBarX, timerBarY, timerBarW, timerBarH, 1)
        nvgFillColor(vg, nvgRGBA(40, 30, 30, 180))
        nvgFill(vg)

        if timerRatio > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, timerBarX, timerBarY, timerBarW * timerRatio, timerBarH, 1)
            nvgFillColor(vg, nvgRGBA(tr2, tg2, tb2, 200))
            nvgFill(vg)
        end
    end
end

-- ============================================================================
-- BOSS 出场动画（居中框+文字，从大缩到正常，停留后淡出）
-- ============================================================================

function Renderer.DrawBossIntro(vg, w, h)
    local intro = State.bossIntro
    if not intro then return end
    if Renderer.fontId == -1 then return end

    local t = intro.timer

    -- 时间轴：0.0~0.4s 缩放进入, 0.4~1.4s 停留, 1.4~2.0s 淡出
    local scale = 1.0
    local alpha = 1.0

    if t < 0.4 then
        local p = t / 0.4
        local ease = 1.0 - (1.0 - p) ^ 3
        scale = 2.5 - 1.5 * ease
    elseif t > 1.4 then
        alpha = 1.0 - (t - 1.4) / 0.6
        if alpha <= 0 then
            State.bossIntro = nil
            return
        end
    end

    local cx = w * 0.5
    local oy = Renderer.gridOffsetY or 0
    local topY = oy + Config.CELL_SIZE * 0.5
    local labelY = topY - Config.CELL_SIZE * 1.1
    local overloadTextY = labelY - 16
    local cy = overloadTextY - 42

    local boxW = 220
    local boxH = 60
    local sW = boxW * scale
    local sH = boxH * scale
    local a = math.floor(alpha * 255)

    nvgSave(vg)

    -- 暗色遮罩
    if alpha > 0.3 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 60)))
        nvgFill(vg)
    end

    -- 外发光
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - sW * 0.5 - 4, cy - sH * 0.5 - 4, sW + 8, sH + 8, 10 * scale)
    nvgFillColor(vg, nvgRGBA(200, 40, 40, math.floor(alpha * 80)))
    nvgFill(vg)

    -- 框背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - sW * 0.5, cy - sH * 0.5, sW, sH, 8 * scale)
    nvgFillColor(vg, nvgRGBA(20, 8, 8, math.floor(alpha * 220)))
    nvgFill(vg)

    -- 框边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - sW * 0.5, cy - sH * 0.5, sW, sH, 8 * scale)
    nvgStrokeColor(vg, nvgRGBA(220, 50, 50, a))
    nvgStrokeWidth(vg, 2 * scale)
    nvgStroke(vg)

    -- 装饰横线（框内上下）
    local lineInset = 12 * scale
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - sW * 0.5 + lineInset, cy - sH * 0.5 + 6 * scale)
    nvgLineTo(vg, cx + sW * 0.5 - lineInset, cy - sH * 0.5 + 6 * scale)
    nvgStrokeColor(vg, nvgRGBA(180, 40, 40, math.floor(alpha * 120)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - sW * 0.5 + lineInset, cy + sH * 0.5 - 6 * scale)
    nvgLineTo(vg, cx + sW * 0.5 - lineInset, cy + sH * 0.5 - 6 * scale)
    nvgStroke(vg)

    -- BOSS 名称
    nvgFontFaceId(vg, Renderer.fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 22 * scale)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
    nvgText(vg, cx + 1, cy - 3 * scale + 1, intro.name, nil)
    nvgFillColor(vg, nvgRGBA(255, 220, 180, a))
    nvgText(vg, cx, cy - 3 * scale, intro.name, nil)

    -- 副标题
    nvgFontSize(vg, 11 * scale)
    nvgFillColor(vg, nvgRGBA(220, 80, 80, math.floor(alpha * 200)))
    nvgText(vg, cx, cy + 14 * scale, "- BOSS -", nil)

    nvgRestore(vg)
end

-- ============================================================================
-- 翠影秘境 BOSS 技能特效（施法描边+抖动、沉寂领域冲击环）
-- ============================================================================

function Renderer.DrawEmeraldBossSkillFX(vg, w, h)
    local sk = State.emeraldBossSkill

    -- 施法阶段：屏幕边框 + 角落发光
    if sk and sk.phase == "casting" then
        local c = sk.color or { 200, 50, 50 }
        local t = sk.timer or 0

        local pulse = DrawCastingBorder(vg, w, h, c, t, 4, 180)

        -- 角落加强发光
        local cornerSize = 16
        local ca = math.floor(pulse * 100)
        local cr, cg, cb = c[1], c[2], c[3]
        nvgBeginPath(vg); nvgRect(vg, 0, 0, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, ca)); nvgFill(vg)
        nvgBeginPath(vg); nvgRect(vg, w - cornerSize, 0, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, ca)); nvgFill(vg)
        nvgBeginPath(vg); nvgRect(vg, 0, h - cornerSize, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, ca)); nvgFill(vg)
        nvgBeginPath(vg); nvgRect(vg, w - cornerSize, h - cornerSize, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, ca)); nvgFill(vg)
    end

    -- 沉默冲击环（execute 阶段）
    if sk and sk.ringRadius and sk.ringDuration then
        local rt = sk.ringTimer or 0
        local progress = math.min(1.0, rt / sk.ringDuration)
        local radius = sk.ringRadius or 0
        if radius > 0 then
            local ringAlpha = (1.0 - progress) * 200
            local rx = sk.ringX or (w * 0.5)
            local ry = sk.ringY or (h * 0.5)

            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, radius)
            nvgStrokeColor(vg, nvgRGBA(140, 50, 200, math.floor(ringAlpha)))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, radius * 0.85)
            nvgStrokeColor(vg, nvgRGBA(180, 100, 255, math.floor(ringAlpha * 0.6)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end

-- ============================================================================
-- 憎恨化身 BOSS 技能特效
-- ============================================================================

function Renderer.DrawHatredBossSkillFX(vg, w, h)
    local hk = State.hatredBossSkill
    if not hk then return end

    local CELL = Config.CELL_SIZE
    local ox = Renderer.gridOffsetX or 0
    local oy = Renderer.gridOffsetY or 0

    -- ======== 1. 毁灭践踏 3×3 区域高亮 + 韧性条 ========
    local sc = hk.starCrush
    if sc then
        local cx, cy = Grid.CellToScreen(sc.centerCol, sc.centerRow, ox, oy)
        local halfArea = CELL * 1.5
        local areaX = cx - halfArea
        local areaY = cy - halfArea
        local areaSize = CELL * 3

        local progress = 1.0 - math.max(0, (sc.timer or 0) / (sc.totalTime or 3.0))
        local pulse = 0.5 + 0.5 * math.abs(math.sin((sc.timer or 0) * 5))

        -- 区域底色
        nvgBeginPath(vg)
        nvgRect(vg, areaX, areaY, areaSize, areaSize)
        nvgFillColor(vg, nvgRGBA(160, 30, 60, math.floor(40 + 30 * pulse)))
        nvgFill(vg)

        -- 区域网格线
        nvgStrokeColor(vg, nvgRGBA(200, 60, 80, math.floor(100 * pulse)))
        nvgStrokeWidth(vg, 1)
        for i = 0, 3 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, areaX + i * CELL, areaY)
            nvgLineTo(vg, areaX + i * CELL, areaY + areaSize)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, areaX, areaY + i * CELL)
            nvgLineTo(vg, areaX + areaSize, areaY + i * CELL)
            nvgStroke(vg)
        end

        -- 区域边框
        nvgBeginPath(vg)
        nvgRect(vg, areaX, areaY, areaSize, areaSize)
        nvgStrokeColor(vg, nvgRGBA(220, 50, 70, math.floor(120 + 100 * progress)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 进度填充（从下往上）
        local fillH = areaSize * progress
        nvgBeginPath(vg)
        nvgRect(vg, areaX, areaY + areaSize - fillH, areaSize, fillH)
        nvgFillColor(vg, nvgRGBA(180, 20, 50, math.floor(50 + 40 * pulse)))
        nvgFill(vg)

        -- 韧性条（区域上方）
        local barW = areaSize
        local barH = 6
        local barX = areaX
        local barY = areaY - barH - 4
        local tRatio = math.max(0, (sc.toughness or 0) / math.max(1, sc.maxToughness or 1))

        nvgBeginPath(vg)
        nvgRect(vg, barX, barY, barW, barH)
        nvgFillColor(vg, nvgRGBA(30, 30, 30, 180))
        nvgFill(vg)

        if tRatio > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, barX, barY, barW * tRatio, barH)
            nvgFillColor(vg, nvgRGBA(240, 180, 40, 220))
            nvgFill(vg)
        end

        nvgBeginPath(vg)
        nvgRect(vg, barX, barY, barW, barH)
        nvgStrokeColor(vg, nvgRGBA(200, 160, 30, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 韧性文字（缓存）
        local sTough = sc.toughness or 0
        local sMax = sc.maxToughness or 0
        if sTough ~= nvgTextCache.shackleTough or sMax ~= nvgTextCache.shackleMax then
            nvgTextCache.shackleTough = sTough
            nvgTextCache.shackleMax = sMax
            nvgTextCache.shackleStr = "韧性 " .. sTough .. "/" .. sMax
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(255, 220, 60, 220))
        nvgText(vg, barX + barW * 0.5, barY - 1, nvgTextCache.shackleStr)

        -- 倒计时文字（缓存到 0.1s 精度）
        local sTimerKey = math.floor((sc.timer or 0) * 10)
        if sTimerKey ~= nvgTextCache.shackleTimer then
            nvgTextCache.shackleTimer = sTimerKey
            nvgTextCache.shackleTimerStr = string.format("%.1f", math.max(0, sTimerKey * 0.1))
        end
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, math.floor(180 + 60 * pulse)))
        nvgText(vg, cx, cy, nvgTextCache.shackleTimerStr)
    end

    -- ======== 2. 终焉毁灭固定区域 + 韧性条 + 倒计时 ========
    local dest = hk.destruction
    if dest then
        local dcx, dcy = Grid.CellToScreen(dest.centerCol, dest.centerRow, ox, oy)
        local radius = dest.radius or 1
        local pulse = 0.5 + 0.5 * math.abs(math.sin(State.time * 3))
        local timer = dest.timer or 0
        local totalTime = dest.totalTime or 5.0
        local timerRatio = math.max(0, timer / math.max(0.01, totalTime))

        -- 覆盖区域
        local coveredSize = radius * CELL
        nvgBeginPath(vg)
        nvgRect(vg, dcx - coveredSize, dcy - coveredSize, coveredSize * 2, coveredSize * 2)
        local urgencyAlpha = math.floor(40 + 40 * (1 - timerRatio) + 20 * pulse)
        nvgFillColor(vg, nvgRGBA(180, 10, 10, urgencyAlpha))
        nvgFill(vg)

        -- 区域边框
        nvgBeginPath(vg)
        nvgRect(vg, dcx - coveredSize, dcy - coveredSize, coveredSize * 2, coveredSize * 2)
        local borderAlpha = math.floor(140 + 100 * (1 - timerRatio) * pulse)
        nvgStrokeColor(vg, nvgRGBA(255, 30, 30, math.min(255, borderAlpha)))
        nvgStrokeWidth(vg, 2 + (1 - timerRatio))
        nvgStroke(vg)

        -- 中心标记
        nvgBeginPath(vg)
        nvgCircle(vg, dcx, dcy, 6 + 2 * pulse)
        nvgFillColor(vg, nvgRGBA(255, 20, 20, 200))
        nvgFill(vg)

        -- 中心倒计时文字（缓存）
        local dTimerKey = math.floor(math.max(0, timer) * 10)
        if dTimerKey ~= nvgTextCache.destTimer then
            nvgTextCache.destTimer = dTimerKey
            nvgTextCache.destTimerStr = string.format("%.1f", dTimerKey * 0.1)
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(200 + 55 * pulse)))
        nvgText(vg, dcx, dcy, nvgTextCache.destTimerStr)

        -- 韧性条（屏幕顶部居中）
        local barW = 200
        local barH = 10
        local barX = (w - barW) * 0.5
        local barY = 50
        local tRatio = math.max(0, (dest.toughness or 0) / math.max(1, dest.maxToughness or 1))

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(30, 30, 30, 200))
        nvgFill(vg)

        if tRatio > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * tRatio, barH, 3)
            local paint = nvgLinearGradient(vg, barX, barY, barX + barW * tRatio, barY,
                nvgRGBA(255, 60, 20, 230), nvgRGBA(255, 200, 40, 230))
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 40, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 韧性文字（缓存）
        local dTough = dest.toughness or 0
        local dMax = dest.maxToughness or 0
        if dTough ~= nvgTextCache.destTough or dMax ~= nvgTextCache.destMax then
            nvgTextCache.destTough = dTough
            nvgTextCache.destMax = dMax
            nvgTextCache.destStr = "终焉毁灭 韧性 " .. dTough .. "/" .. dMax
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(255, 220, 60, 240))
        nvgText(vg, w * 0.5, barY - 2, nvgTextCache.destStr)

        -- 区域大小+倒计时文字（缓存）
        if radius ~= nvgTextCache.destRadius or dTimerKey ~= nvgTextCache.destTimer then
            nvgTextCache.destRadius = radius
            local side = radius * 2 + 1
            nvgTextCache.destInfoStr = "毁灭区域: " .. side .. "x" .. side ..
                "  倒计时: " .. (nvgTextCache.destTimerStr or "0.0") .. "s"
        end
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 100, 100, 200))
        nvgText(vg, w * 0.5, barY + barH + 2, nvgTextCache.destInfoStr)
    end

    -- ======== 3. 施法边框（复用公共函数） ========
    local casting = hk.casting
    if casting and casting.phase then
        local c = casting.color or { 180, 40, 60 }
        local t = casting.timer or 0
        DrawCastingBorder(vg, w, h, c, t, 3, 150)
    end

    -- ======== 4. BOSS 身上的光环指示器 ========
    local bx = hk.bossX
    local by = hk.bossY
    local bSize = hk.bossSize or 22
    if bx and by then
        local halfS = bSize * 0.5

        -- 嘲讽光环
        if hk.tauntActive then
            local imgSize = bSize * 2.8
            local centerY = by - imgSize * 0.5
            local tPulse = 0.5 + 0.5 * math.abs(math.sin(State.time * 4))
            nvgBeginPath(vg)
            nvgCircle(vg, bx, centerY, halfS + 4 + tPulse * 3)
            nvgStrokeColor(vg, nvgRGBA(220, 40, 40, math.floor(120 + 80 * tPulse)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 嘲讽图标（旋转小三角）
            local iconR = halfS + 10
            for i = 0, 3 do
                local angle = (i * math.pi * 0.5) + State.time * 0.8
                local ix = bx + math.cos(angle) * iconR
                local iy = centerY + math.sin(angle) * iconR
                nvgBeginPath(vg)
                local triSize = 4
                nvgMoveTo(vg, ix + math.cos(angle + math.pi) * triSize,
                              iy + math.sin(angle + math.pi) * triSize)
                nvgLineTo(vg, ix + math.cos(angle + math.pi * 0.5 + math.pi) * triSize * 0.6,
                              iy + math.sin(angle + math.pi * 0.5 + math.pi) * triSize * 0.6)
                nvgLineTo(vg, ix + math.cos(angle - math.pi * 0.5 + math.pi) * triSize * 0.6,
                              iy + math.sin(angle - math.pi * 0.5 + math.pi) * triSize * 0.6)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 60, 60, math.floor(160 + 60 * tPulse)))
                nvgFill(vg)
            end
        end
    end
end

-- ============================================================================
-- 通用 Boss 技能特效（施法描边+护盾光环+脉冲波纹+吞噬/诅咒指示）
-- ============================================================================

function Renderer.DrawGenericBossSkillFX(vg, w, h)
    local gk = State.genericBossSkill
    if not gk then return end

    -- ======== 1. 施法阶段描边 ========
    local casting = gk.casting
    if casting and casting.phase then
        local c = casting.color or { 160, 80, 200 }
        local t = casting.timer or 0

        local pulse = DrawCastingBorder(vg, w, h, c, t, 3, 160)

        -- 技能名称提示（施法期间在屏幕上方居中显示）
        if casting.name and Renderer.fontId and Renderer.fontId ~= -1 then
            local nameAlpha = math.floor(pulse * 220)
            nvgFontFaceId(vg, Renderer.fontId)
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, nameAlpha))
            nvgText(vg, w * 0.5 + 1, 38 + 1, casting.name, nil)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], nameAlpha))
            nvgText(vg, w * 0.5, 38, casting.name, nil)
        end
    end

    -- ======== 2. 护盾激活指示 ========
    if gk.shieldActive then
        local st = gk.shieldTimer or 0
        local sPulse = 0.5 + 0.5 * math.abs(math.sin(st * 4))

        for _, e in ipairs(State.enemies) do
            if e.alive and e.isBoss and e.screenX and e.screenY then
                local bx = e.screenX
                local by = e.screenY - (e.drawSize or 22) * 0.3

                nvgBeginPath(vg)
                nvgCircle(vg, bx, by, (e.drawSize or 22) * 0.8 + 3 * sPulse)
                nvgStrokeColor(vg, nvgRGBA(60, 160, 255, math.floor(120 + 80 * sPulse)))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)

                nvgBeginPath(vg)
                nvgCircle(vg, bx, by, (e.drawSize or 22) * 0.5 + 2 * sPulse)
                nvgStrokeColor(vg, nvgRGBA(100, 200, 255, math.floor(80 + 60 * sPulse)))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                break
            end
        end
    end

    -- ======== 3. 脉冲波纹（AOE 沉默后的扩散环） ========
    if gk.pulseEffect and gk.pulseEffect > 0 then
        local pt = gk.pulseEffect
        local radius = (1.0 - pt) * math.min(w, h) * 0.4
        local alpha = math.floor(pt * 180)

        nvgBeginPath(vg)
        nvgCircle(vg, w * 0.5, h * 0.5, radius)
        nvgStrokeColor(vg, nvgRGBA(140, 50, 200, alpha))
        nvgStrokeWidth(vg, 2 + pt * 2)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgCircle(vg, w * 0.5, h * 0.5, radius * 0.7)
        nvgStrokeColor(vg, nvgRGBA(180, 100, 255, math.floor(alpha * 0.5)))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- ======== 4. 吞噬/诅咒激活时的屏幕边缘微光 ========
    if gk.devourActive then
        local grad = nvgLinearGradient(vg, 0, h, 0, h - 20,
            nvgRGBA(120, 20, 20, 60), nvgRGBA(120, 20, 20, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, h - 20, w, 20)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    if gk.curseActive then
        local grad = nvgLinearGradient(vg, 0, 0, 0, 16,
            nvgRGBA(80, 20, 120, 50), nvgRGBA(80, 20, 120, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, 16)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end
end

end
