-- Game/Renderer_Draw.lua
-- 绘制：敌人、弹道、粒子、飘字、合成闪光、拖拽、Boss血条等

return function(Renderer, ctx)

local Config      = require("Game.Config")
local State       = require("Game.State")
local Grid        = require("Game.Grid")
local SpriteSheet = ctx.SpriteSheet
local EnemyAnim   = require("Game.EnemyAnim")
local HeroSkills  = require("Game.HeroSkills")

-- 从 ctx 获取共享工具函数
local rgba                    = ctx.rgba
local DrawCircleBloom         = ctx.DrawCircleBloom
local EnsureMobImage          = ctx.EnsureMobImage
local DrawMobImage            = ctx.DrawMobImage
local EmitDebuffParticles     = ctx.EmitDebuffParticles
local DrawEnemyDebuffParticles = ctx.DrawEnemyDebuffParticles

-- 避免在每帧绘制函数中 require（Lua require 有表查找开销）
local Enemy        = require("Game.Enemy")
local RelicEffects  = require("Game.RelicEffects")
local RelicData     = require("Game.RelicData")
local WorldBossData = require("Game.WorldBossData")
local DamageStats   = require("Game.DamageStats")

-- BattleManager 延迟 require（避免循环依赖：Combat→HatredBossSkills→Renderer→BM→Combat）
local _BM
local function GetBM()
    if not _BM then _BM = require("Game.BattleManager") end
    return _BM
end

-- NanoVG 文本缓存（仅值变化时重新格式化）
local nvgTextCache = {
    overloadRemain = nil, overloadStr = nil,
    enemyCount = nil, enemyMax = nil, countStr = nil,
    nextWaveSec = nil, nextWaveStr = nil,
    bossPct = nil, bossName = nil, bossHpStr = nil,
    bossRemainSec = nil, bossTimeStr = nil,
    -- 世界Boss技能渲染缓存
    shackleTough = nil, shackleMax = nil, shackleStr = nil,
    shackleTimer = nil, shackleTimerStr = nil,
    destTough = nil, destMax = nil, destStr = nil,
    destTimer = nil, destTimerStr = nil,
    destRadius = nil, destAreaStr = nil, destInfoStr = nil,
}

local function DrawEnemyShape(vg, x, y, size, shape, r, g, b, alpha)
    alpha = alpha or 255
    nvgBeginPath(vg)
    if shape == "diamond" then
        nvgMoveTo(vg, x, y - size)
        nvgLineTo(vg, x + size, y)
        nvgLineTo(vg, x, y + size)
        nvgLineTo(vg, x - size, y)
        nvgClosePath(vg)
    elseif shape == "square" then
        local h = size * 0.8
        nvgRect(vg, x - h, y - h, h * 2, h * 2)
    elseif shape == "triangle" then
        nvgMoveTo(vg, x, y - size)
        nvgLineTo(vg, x + size * 0.87, y + size * 0.5)
        nvgLineTo(vg, x - size * 0.87, y + size * 0.5)
        nvgClosePath(vg)
    else  -- circle (default)
        nvgCircle(vg, x, y, size)
    end
    nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
    nvgFill(vg)
end

--- 绘制敌人
function Renderer.DrawEnemies(vg)
    for _, e in ipairs(State.enemies) do
        if e.alive or e._dyingAnim then
            local size = e.typeDef.size
            local c = e.typeDef.color
            local shape = e.typeDef.shape or "circle"

            -- 受击抖动偏移
            local shakeX, shakeY = 0, 0
            if e.hitShakeTimer and e.hitShakeTimer > 0 then
                local intensity = e.hitShakeIntensity or 2
                shakeX = (math.random() - 0.5) * 2 * intensity
                shakeY = (math.random() - 0.5) * 2 * intensity
            end
            local drawX = e.x + shakeX
            local drawY = e.y + shakeY

            -- BOSS 视觉外偏：仅在顶部路径段向上偏移，其余路径保持在路径中点
            if e.isBoss then
                local nx, ny = e._pnx or 0, e._pny or -1
                -- 顶部路径段法线朝上 (ny ≈ -1)，仅此段应用偏移
                if ny < -0.5 then
                    local bossOffset = Config.CELL_SIZE * 0.6
                    drawX = drawX + nx * bossOffset
                    drawY = drawY + ny * bossOffset
                end
            end

            -- 隐身无敌状态：半透明
            local bodyAlpha = 255
            if e.phaseActive then
                bodyAlpha = math.floor(60 + math.sin(e.animTime * 6) * 30)
            end

            -- 根据路径方向决定朝向（精灵图默认朝左）
            -- 上→朝右(翻), 右→朝左(不翻), 下→朝左(不翻), 左→朝右(翻)
            local pdx, pdy = e._pdx or 1, e._pdy or 0
            local flipX = (pdx < -0.1) or (pdy < -0.1)

            -- 代码动画变换（呼吸/受击后退/出生弹跳/死亡淡出）
            local atr = EnemyAnim.GetDrawTransform(e, State.time)
            local isDying = e._dyingAnim and not e.alive
            local spriteY = drawY + atr.bobY + atr.offsetY  -- 呼吸浮动叠加到精灵（阴影/血条不跟随）

            -- 敌人身体：精灵图 > 单张图片 > 矢量形状
            local ssName = e.typeDef.spriteSheet
            local mobIcon = e.typeDef.icon
            local mobImg = mobIcon and EnsureMobImage(vg, mobIcon) or -1
            local imgSize = e.isBoss and (size * 2.8) or (size * 2.5)

            -- 应用缩放和透明度（锚点在脚底，朝上缩放）
            nvgSave(vg)
            if atr.alpha < 1.0 then
                nvgGlobalAlpha(vg, atr.alpha)
            end
            if atr.scaleX ~= 1.0 or atr.scaleY ~= 1.0 then
                local pivotY = drawY + imgSize * 0.5   -- 脚底锚点
                nvgTranslate(vg, drawX, pivotY)
                nvgScale(vg, atr.scaleX, atr.scaleY)
                nvgTranslate(vg, -drawX, -pivotY)
            end

            if ssName and SpriteSheet.Has(ssName) then
                -- 精灵图动画：帧0=站立, 1=施法, 2=攻击
                local frameIdx = e.castingFrame or 0
                if frameIdx > 0 and not SpriteSheet.HasFrame(ssName, frameIdx) then
                    frameIdx = 0
                end
                SpriteSheet.DrawEx(vg, ssName, frameIdx, drawX, spriteY, imgSize, bodyAlpha, flipX)
            elseif mobImg > 0 then
                DrawMobImage(vg, mobImg, drawX, spriteY, imgSize, bodyAlpha, flipX)
            else
                DrawEnemyShape(vg, drawX, spriteY, size, shape, c[1], c[2], c[3], bodyAlpha)
            end

            -- 受击闪白叠加层（内层 save/restore 仅切换混合模式，缩放由外层保持）
            if e.hitFlash and e.hitFlash > 0 then
                local flashAlpha = math.floor(200 * (e.hitFlash / 0.12))
                nvgSave(vg)
                nvgGlobalCompositeOperation(vg, NVG_LIGHTER)
                if ssName and SpriteSheet.Has(ssName) then
                    SpriteSheet.DrawEx(vg, ssName, 0, drawX, spriteY, imgSize, flashAlpha, flipX)
                elseif mobImg > 0 then
                    DrawMobImage(vg, mobImg, drawX, spriteY, imgSize, flashAlpha, flipX)
                else
                    DrawEnemyShape(vg, drawX, spriteY, size, shape, 255, 255, 255, flashAlpha)
                end
                nvgRestore(vg)
            end
            nvgRestore(vg)  -- 恢复外层：缩放/透明度

            -- 死亡动画中跳过所有 UI 元素（血条/被动/护盾/粒子）
            if not isDying then

            -- 坦克被动视觉指示
            if e.typeDef.tankPassive then
                local tp = e.typeDef.tankPassive
                if tp == "regen" then
                    -- 持续回血：绿色 + 号脉冲
                    local rPulse = 0.5 + math.sin(e.animTime * 3) * 0.5
                    nvgFontFaceId(vg, Renderer.fontId)
                    nvgFontSize(vg, 8)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(80, 220, 80, math.floor(180 * rPulse)))
                    nvgText(vg, drawX + size * 0.7, drawY - size * 0.7, "+", nil)
                elseif tp == "dot_immune" then
                    -- DOT 免疫：暗红色 X 标记
                    nvgFontFaceId(vg, Renderer.fontId)
                    nvgFontSize(vg, 8)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(200, 60, 60, 120))
                    nvgText(vg, drawX + size * 0.7, drawY - size * 0.7, "x", nil)
                end
            end

            -- 特殊被动视觉指示
            if e.typeDef.specialPassive then
                local sp = e.typeDef.specialPassive
                if sp == "poison_trail" then
                    -- 毒径：身后绿色小尾迹点
                    local tPulse = 0.6 + math.sin(e.animTime * 5) * 0.4
                    nvgBeginPath(vg)
                    nvgCircle(vg, drawX - 3, drawY + size * 0.5, 2)
                    nvgCircle(vg, drawX + 2, drawY + size * 0.8, 1.5)
                    nvgFillColor(vg, nvgRGBA(60, 180, 40, math.floor(140 * tPulse)))
                    nvgFill(vg)
                elseif sp == "regen_lost" then
                    -- 失血回复：暗红色心跳脉冲
                    local hbPulse = math.abs(math.sin(e.animTime * 2))
                    DrawCircleBloom(vg, drawX, drawY, size * 0.5 * (0.8 + hbPulse * 0.4), 0.8, 0.2, 0.2, 0.15 * hbPulse)
                elseif sp == "first_hit_armor" and e.firstHitArmored then
                    -- 首击减伤（未消耗）：金色盔甲闪光
                    local aPulse = 0.6 + math.sin(e.animTime * 1.5) * 0.4
                    nvgBeginPath(vg)
                    nvgCircle(vg, drawX, drawY, size + 2)
                    nvgStrokeWidth(vg, 1.5)
                    nvgStrokeColor(vg, nvgRGBA(220, 180, 60, math.floor(120 * aPulse)))
                    nvgStroke(vg)
                elseif sp == "death_silence" then
                    -- 死亡沉默：紫色十字标记
                    if Renderer.fontId >= 0 then
                        nvgFontFaceId(vg, Renderer.fontId)
                        nvgFontSize(vg, 8)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(160, 80, 200, 100))
                        nvgText(vg, drawX - size * 0.7, drawY - size * 0.7, "†", nil)
                    end
                end
            end

            -- 护盾视觉（蓝色外环）
            if e.shield and e.shield > 0 then
                local shieldRatio = e.shield / (e.maxShield > 0 and e.maxShield or 1)
                nvgBeginPath(vg)
                nvgArc(vg, drawX, drawY, size + 5, -math.pi / 2, -math.pi / 2 + math.pi * 2 * shieldRatio, 2)
                nvgStrokeWidth(vg, 2.5)
                nvgStrokeColor(vg, nvgRGBA(150, 180, 255, 200))
                nvgStroke(vg)
            end

            -- Debuff 粒子发射（每帧为有 debuff 的敌人生成粒子）
            EmitDebuffParticles(e, 1.0 / 60.0)

            -- 绘制该敌人的 debuff 粒子
            DrawEnemyDebuffParticles(vg, e.id)

            -- 血条
            local barW = e.isBoss and size * 3.5 or size * 2.5
            local barH = e.isBoss and 4 or 3
            local barX = drawX - barW * 0.5
            local barY = drawY - size - 8

            -- 护盾条（在血条上方）
            if e.maxShield and e.maxShield > 0 then
                barY = barY - 5
            end

            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 1)
            nvgFillColor(vg, rgba(Config.COLORS.hpBarBg))
            nvgFill(vg)

            local hpRatio = (e.maxHP == math.huge) and 1.0 or (e.hp / e.maxHP)
            if hpRatio > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 1)
                local hpColor = e.isBoss and Config.COLORS.hpBarBoss or Config.COLORS.hpBarFill
                nvgFillColor(vg, rgba(hpColor))
                nvgFill(vg)
            end

            -- 护盾条（蓝色，血条下方）
            if e.maxShield and e.maxShield > 0 and e.shield > 0 then
                local sBarY = barY + barH + 1
                nvgBeginPath(vg)
                nvgRoundedRect(vg, barX, sBarY, barW, 2, 1)
                nvgFillColor(vg, nvgRGBA(40, 40, 60, 180))
                nvgFill(vg)
                local sRatio = e.shield / e.maxShield
                nvgBeginPath(vg)
                nvgRoundedRect(vg, barX, sBarY, barW * sRatio, 2, 1)
                nvgFillColor(vg, nvgRGBA(100, 160, 255, 220))
                nvgFill(vg)
            end

            -- BOSS 名字标签
            if e.isBoss and Renderer.fontId >= 0 then
                nvgFontFaceId(vg, Renderer.fontId)
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(255, 200, 60, 220))
                nvgText(vg, drawX, barY - 2, e.typeDef.name, nil)
            end

            -- 词缀名称标签（血条上方，拼接显示）
            if e.affixes and #e.affixes > 0 and Renderer.fontId >= 0 then
                -- 词缀列表不变，缓存拼接结果到敌人上
                if not e._affixStr then
                    local parts = {}
                    for _, a in ipairs(e.affixes) do
                        parts[#parts + 1] = a.name or a.id
                    end
                    e._affixStr = table.concat(parts, "·")
                end
                local affixStr = e._affixStr
                local affixY = barY - (e.isBoss and 14 or 2)
                nvgFontFaceId(vg, Renderer.fontId)
                nvgFontSize(vg, 8)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                -- 半透明黑底增加可读性
                local tw = nvgTextBounds(vg, 0, 0, affixStr, nil, nil)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, drawX - tw * 0.5 - 2, affixY - 9, tw + 4, 10, 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
                nvgFill(vg)
                -- 词缀文字（橙黄色，精英感）
                nvgFillColor(vg, nvgRGBA(255, 200, 100, 220))
                nvgText(vg, drawX, affixY, affixStr, nil)
            end

            end  -- if not isDying

        end
    end
end

--- 绘制弹道
function Renderer.DrawProjectiles(vg)
    for _, p in ipairs(State.projectiles) do
        local c = p.color
        if p.spriteSheet and SpriteSheet.HasFrame(p.spriteSheet, 2) then
            -- 精灵图弹体：帧2，旋转指向目标
            local angle = math.atan(p.ty - p.y, p.tx - p.x)
            SpriteSheet.DrawRotated(vg, p.spriteSheet, 2, p.x, p.y, 20, 255, angle)
            -- 附加光晕（使用塔颜色）
            DrawCircleBloom(vg, p.x, p.y, 6, c[1] / 255, c[2] / 255, c[3] / 255, 0.25)
        else
            -- 普通弹道光点
            DrawCircleBloom(vg, p.x, p.y, 4, c[1] / 255, c[2] / 255, c[3] / 255, 0.3)
            nvgBeginPath(vg)
            nvgCircle(vg, p.x, p.y, 3)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 255))
            nvgFill(vg)
        end
    end
end

--- 绘制粒子特效
function Renderer.DrawParticles(vg)
    for _, pt in ipairs(State.particles) do
        local alpha = math.floor(255 * (pt.life / (pt.maxLife or 1.0)))
        local c = pt.color
        nvgBeginPath(vg)
        nvgCircle(vg, pt.x, pt.y, pt.size * (pt.life / (pt.maxLife or 1.0)))
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgFill(vg)
    end
end

--- 绘制飘字
function Renderer.DrawFloatingTexts(vg)
    if Renderer.fontId == -1 then return end
    nvgFontFaceId(vg, Renderer.fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, ft in ipairs(State.floatingTexts) do
        local c = ft.color
        if not c then goto continueFT end
        local alpha = math.floor(255 * math.min(ft.life * 2, 1.0))  -- 后半段淡出
        if alpha <= 0 then goto continueFT end
        local baseFontSize = ft.fontSize or 14

        if ft.isCrit then
            -- 暴击飘字：弹出缩放效果（先放大再收回）
            local maxLife = ft.maxLife or 0.9
            local elapsed = maxLife - ft.life
            local scale = 1.0
            if elapsed < 0.1 then
                scale = 1.0 + (elapsed / 0.1) * 0.5   -- 0→0.1s 放大到1.5x
            elseif elapsed < 0.2 then
                scale = 1.5 - ((elapsed - 0.1) / 0.1) * 0.5  -- 0.1→0.2s 回到1.0x
            end
            nvgFontSize(vg, baseFontSize * scale)
            -- 暴击描边（深色底边增加可读性）
            nvgFillColor(vg, nvgRGBA(40, 0, 0, alpha))
            nvgText(vg, ft.x + 1, ft.y + 1, ft.text, nil)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
            nvgText(vg, ft.x, ft.y, ft.text, nil)
        else
            -- 普通飘字
            nvgFontSize(vg, baseFontSize)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
            nvgText(vg, ft.x, ft.y, ft.text, nil)
        end
        ::continueFT::
    end
end

--- 绘制合成闪光
function Renderer.DrawMergeFlash(vg, ox, oy)
    if State.mergeFlash > 0 and State.mergeFlashPos then
        local cx, cy = Grid.CellToScreen(State.mergeFlashPos.col, State.mergeFlashPos.row, ox, oy)
        local alpha = State.mergeFlash / 0.5
        DrawCircleBloom(vg, cx, cy, 40 * (1 + (1 - alpha)), 1, 0.9, 0.5, alpha * 0.6)

        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 20 * (2 - alpha))
        nvgFillColor(vg, nvgRGBAf(1, 1, 0.8, alpha * 0.5))
        nvgFill(vg)
    end
end

--- 绘制拖拽视觉反馈
function Renderer.DrawDragOverlay(vg, ox, oy)
    if not State.dragging or not State.dragTower then return end

    local tower = State.dragTower
    local size = Config.CELL_SIZE * 0.8
    local gc = tower.typeDef.glowColor
    local tc = State.dragTargetCol
    local tr = State.dragTargetRow

    -- 1. 目标格子高亮提示（半透明背景）
    if State.dragValid then
        local tx, ty = Grid.CellToScreen(tc, tr, ox, oy)
        local half = Config.CELL_SIZE * 0.5 - 1

        -- 目标格半透明高亮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx - half, ty - half, half * 2, half * 2, 4)
        nvgFillColor(vg, nvgRGBA(tower.typeDef.color[1], tower.typeDef.color[2], tower.typeDef.color[3], 40))
        nvgFill(vg)

        -- 目标格边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx - half, ty - half, half * 2, half * 2, 4)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(tower.typeDef.color[1], tower.typeDef.color[2], tower.typeDef.color[3], 120))
        nvgStroke(vg)

        -- 目标格半透明塔图标预览
        ctx.DrawTowerIcon(vg, tower.typeDef.icon, tx, ty, size, tower.typeDef.color, tower.star, 100, tower)

        -- 如果目标格有塔且可合成，显示合成提示
        local targetTower = State.grid[tc][tr]
        if targetTower and targetTower.typeIndex == tower.typeIndex
            and targetTower.star == tower.star and tower.star < Config.MAX_STAR then
            -- 合成闪烁提示
            local pulse = math.sin(State.time * 6) * 0.3 + 0.7
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx - half, ty - half, half * 2, half * 2, 4)
            nvgStrokeWidth(vg, 2.5)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(200 * pulse)))
            nvgStroke(vg)
        end
    end

    -- 2. 跟随鼠标的塔图标 + 攻击范围圈
    local mx, my = State.dragX, State.dragY

    -- 攻击范围圈（半透明）
    local effRange = HeroSkills.ModifyRange(tower, tower.range)
    nvgBeginPath(vg)
    nvgCircle(vg, mx, my, effRange)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(gc[1] * 255, gc[2] * 255, gc[3] * 255, 60))
    nvgStroke(vg)
    -- 范围填充
    nvgBeginPath(vg)
    nvgCircle(vg, mx, my, effRange)
    nvgFillColor(vg, nvgRGBA(gc[1] * 255, gc[2] * 255, gc[3] * 255, 15))
    nvgFill(vg)

    -- 塔图标（跟随鼠标，完全不透明）
    ctx.DrawTowerIcon(vg, tower.typeDef.icon, mx, my, size * 1.1, tower.typeDef.color, tower.star, 220, tower)
end

--- 绘制怪物数量指示器 + 倒计时（路径上方）
function Renderer.DrawEnemyCount(vg, ox, oy)
    local count = Enemy.GetAliveCount()
    local bm = GetBM()
    local max = (bm.IsActive() and bm.config.overloadLimit) or Config.MAX_ENEMIES

    -- 路径顶部中央位置
    local centerX = ox + Config.GRID_COLS * Config.CELL_SIZE * 0.5
    local topY = oy + Config.CELL_SIZE * 0.5  -- 路径第一行中心
    local labelY = topY - Config.CELL_SIZE * 1.1 -- 路径上方（上移）

    nvgFontFaceId(vg, Renderer.fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 超限警告（显示在怪物计数上方）
    if State.overloading then
        local remain = math.max(0, Config.OVERLOAD_COUNTDOWN - State.overloadTimer)
        local remainKey = math.floor(remain * 10) -- 缓存到 0.1s 精度
        if remainKey ~= nvgTextCache.overloadRemain then
            nvgTextCache.overloadRemain = remainKey
            nvgTextCache.overloadStr = string.format("超限! %.1fs", remain)
        end
        local blink = (math.floor(State.time * 4) % 2 == 0)
        local alpha = blink and 255 or 180
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(255, 50, 50, alpha))
        nvgText(vg, centerX, labelY - 16, nvgTextCache.overloadStr, nil)
    end

    do
        -- 缓存 count/max 拼接（仅变化时重新拼接）
        if count ~= nvgTextCache.enemyCount or max ~= nvgTextCache.enemyMax then
            nvgTextCache.enemyCount = count
            nvgTextCache.enemyMax = max
            nvgTextCache.countStr = count .. "/" .. max
        end
        local countText = nvgTextCache.countStr

        -- 怪物数颜色（接近上限时变色）
        local r, g, b, a = 180, 180, 200, 200
        if State.overloading then
            r, g, b, a = 255, 80, 80, 220
        elseif count >= max - 2 then
            r, g, b, a = 255, 180, 60, 240
        end

        -- 怪物图标（图片替代 emoji）
        local monsterIcon = EnsureMobImage(vg, "image/icon_monster.png")
        if monsterIcon > 0 then
            DrawMobImage(vg, monsterIcon, centerX - 28, labelY, 18, 255)
        end
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(r, g, b, a))
        nvgText(vg, centerX, labelY, countText, nil)

        -- 下一波倒计时（仅非最后一波时显示）
        if State.phase == State.PHASE_PLAYING
           and State.currentWave < Config.WAVES_PER_STAGE then
            local nextWaveIn = math.max(0, Config.WAVE_INTERVAL - State.waveTimer)
            local sec = math.ceil(nextWaveIn)
            if sec ~= nvgTextCache.nextWaveSec then
                nvgTextCache.nextWaveSec = sec
                nvgTextCache.nextWaveStr = string.format("下一波 %ds", sec)
            end
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(160, 150, 180, 180))
            nvgText(vg, centerX, labelY + 16, nvgTextCache.nextWaveStr, nil)
        end
    end
end

--- 绘制技能闪光效果
function Renderer.DrawSkillFlash(vg, w, h)
    if not State.skillFlash then return end
    local sf = State.skillFlash
    local alpha = sf.timer / 0.5

    if sf.type == "void_storm" then
        -- 全屏紫色闪光
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.4, 0.1, 0.6, alpha * 0.15))
        nvgFill(vg)
    elseif sf.type == "arrow_rain" then
        -- 全屏绿色闪光
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.2, 0.6, 0.2, alpha * 0.1))
        nvgFill(vg)
    elseif sf.type == "hell_gate" then
        -- 全屏红色闪光
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.6, 0.1, 0.1, alpha * 0.1))
        nvgFill(vg)
    elseif sf.type == "emerald_shackle" then
        -- 全屏深绿闪光（荆棘禁锢）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.15, 0.5, 0.2, alpha * 0.12))
        nvgFill(vg)
    elseif sf.type == "emerald_silence" then
        -- 全屏紫色冲击（沉寂领域）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.45, 0.15, 0.6, alpha * 0.15))
        nvgFill(vg)
    elseif sf.type == "emerald_decay" then
        -- 全屏暗黄绿闪光（自然衰竭）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.4, 0.45, 0.15, alpha * 0.1))
        nvgFill(vg)
    elseif sf.type == "hatred_summon" then
        -- 全屏橙色闪光（深渊召唤）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.7, 0.35, 0.1, alpha * 0.12))
        nvgFill(vg)
    elseif sf.type == "hatred_fortress" then
        -- 全屏蓝色闪光（憎恨壁垒）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.15, 0.35, 0.7, alpha * 0.12))
        nvgFill(vg)
    elseif sf.type == "hatred_taunt" then
        -- 全屏深红闪光（怨恨嘲讽）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.6, 0.08, 0.08, alpha * 0.15))
        nvgFill(vg)
    elseif sf.type == "hatred_star_crush" then
        -- 全屏紫红闪光（毁灭践踏）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.5, 0.1, 0.6, alpha * 0.18))
        nvgFill(vg)
    elseif sf.type == "hatred_destruction" then
        -- 全屏深红闪光（终焉毁灭扩散）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.8, 0.05, 0.05, alpha * 0.20))
        nvgFill(vg)
    elseif sf.type == "relic_cast" then
        -- 全屏金紫闪光（遗物释放）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBAf(0.55, 0.3, 0.8, alpha * 0.22))
        nvgFill(vg)
        -- 中心向外扩散的亮线
        local spread = (1.0 - alpha) * math.max(w, h) * 0.6
        local cx, cy = w * 0.5, h * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, spread)
        nvgStrokeColor(vg, nvgRGBAf(0.9, 0.75, 1.0, alpha * 0.35))
        nvgStrokeWidth(vg, 3.0 * alpha)
        nvgStroke(vg)
    end
end

--- BOSS 倒计时 + 血条（顶栏下方）
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

    -- 判断是否世界BOSS模式（显示伤害计数器）
    local isWorldBoss = State.worldBossActive

    if isWorldBoss then
        -- 世界BOSS：右侧倒计时（与普通BOSS一致的位置）
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(255, 80, 60, timerAlpha))
        nvgText(vg, rightX, barY + barH * 0.3, "BOSS", nil)

        nvgFontSize(vg, 13)
        local tr, tg, tb = 255, 200, 160
        if remain <= 10 then tr, tg, tb = 255, 80, 60 end
        nvgFillColor(vg, nvgRGBA(tr, tg, tb, timerAlpha))
        nvgText(vg, rightX + 30, barY + barH * 0.3, timeStr, nil)

        -- 血条下方右侧：伤害计数器（带背景底板）
        local dmgY = barY + barH + 3
        local totalDmg = State.worldBossTotalDamage or 0
        local dmgStr = "伤害 " .. WorldBossData.FormatDamage(totalDmg)

        -- 底板背景
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

        -- 伤害文字
        nvgFontFaceId(vg, Renderer.fontId)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 140, 60, 255))
        nvgText(vg, dmgBgX + dmgBgW * 0.5, dmgY + dmgBgH * 0.5, dmgStr, nil)
    else
        -- 普通BOSS：原有布局
        -- "BOSS" 标签
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(255, 80, 60, timerAlpha))
        nvgText(vg, rightX, barY + barH * 0.3, "BOSS", nil)

        -- 倒计时数字
        nvgFontSize(vg, 13)
        local tr, tg, tb = 255, 200, 160
        if remain <= 10 then tr, tg, tb = 255, 80, 60 end
        nvgFillColor(vg, nvgRGBA(tr, tg, tb, timerAlpha))
        nvgText(vg, rightX + 30, barY + barH * 0.3, timeStr, nil)

        -- 血条下方右侧：伤害计数器
        local totalBossDmg = DamageStats.GetTotalBossDmg()
        if totalBossDmg > 0 then
            local dmgY = barY + barH + 3
            local dmgStr = "伤害 " .. WorldBossData.FormatDamage(totalBossDmg)
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
    end

    -- 剩余时间进度条（小的）
    local timerBarX = rightX
    local timerBarW = rightW
    local timerBarY = barY + barH * 0.65
    local timerBarH = 3
    local maxTimer = State.bossTimerMax or Config.BOSS_TIMER_MAX
    local timerRatio = remain / maxTimer
    local tr2, tg2, tb2 = 255, 200, 160
    if remain <= 10 then tr2, tg2, tb2 = 255, 80, 60 end

    if not isWorldBoss then
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

--- BOSS 出场动画（居中框+文字，从大缩到正常，停留后淡出）
function Renderer.DrawBossIntro(vg, w, h)
    local intro = State.bossIntro
    if not intro then return end
    if Renderer.fontId == -1 then return end

    local t = intro.timer
    local dur = intro.duration  -- 总时长 2.0s

    -- 时间轴：
    -- 0.0~0.4s  缩放进入（从 2.5x → 1.0x，ease-out）
    -- 0.4~1.4s  停留展示
    -- 1.4~2.0s  淡出
    local scale = 1.0
    local alpha = 1.0

    if t < 0.4 then
        -- 缩放进入：ease-out (1 - (1-p)^3)
        local p = t / 0.4
        local ease = 1.0 - (1.0 - p) ^ 3
        scale = 2.5 - 1.5 * ease  -- 2.5 → 1.0
    elseif t > 1.4 then
        -- 淡出
        alpha = 1.0 - (t - 1.4) / 0.6
        if alpha <= 0 then
            State.bossIntro = nil
            return
        end
    end

    local cx = w * 0.5
    -- 放在超限提醒文字上方（与怪物计数区域对齐）
    local oy = Renderer.gridOffsetY or 0
    local topY = oy + Config.CELL_SIZE * 0.5
    local labelY = topY - Config.CELL_SIZE * 1.1
    local overloadTextY = labelY - 16
    local cy = overloadTextY - 42  -- 框中心在超限文字上方

    -- 框尺寸（基准）
    local boxW = 220
    local boxH = 60
    local sW = boxW * scale
    local sH = boxH * scale
    local a = math.floor(alpha * 255)

    nvgSave(vg)

    -- 暗色遮罩（轻微）
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
    -- 文字阴影
    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
    nvgText(vg, cx + 1, cy - 3 * scale + 1, intro.name, nil)
    -- 文字主体
    nvgFillColor(vg, nvgRGBA(255, 220, 180, a))
    nvgText(vg, cx, cy - 3 * scale, intro.name, nil)

    -- 副标题 "BOSS"
    nvgFontSize(vg, 11 * scale)
    nvgFillColor(vg, nvgRGBA(220, 80, 80, math.floor(alpha * 200)))
    nvgText(vg, cx, cy + 14 * scale, "- BOSS -", nil)

    nvgRestore(vg)
end

--- 翠影秘境 BOSS 技能特效（施法描边+抖动、沉寂领域冲击环）
function Renderer.DrawEmeraldBossSkillFX(vg, w, h)
    local sk = State.emeraldBossSkill

    -- ======== 施法阶段：屏幕边框描边 + 轻微抖动 ========
    if sk and sk.phase == "casting" then
        local c = sk.color or { 200, 50, 50 }
        local t = sk.timer or 0
        -- alpha 脉动：0.3 + 0.7 * |sin(t*6)|
        local pulse = 0.3 + 0.7 * math.abs(math.sin(t * 6))
        local a = math.floor(pulse * 180)
        local borderW = 4

        nvgSave(vg)

        -- 轻微屏幕抖动（通过整体偏移模拟）
        local shakeX = math.sin(t * 35) * 2
        local shakeY = math.cos(t * 28) * 1.5
        nvgTranslate(vg, shakeX, shakeY)

        -- 四边描边
        -- 上
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, borderW)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)
        -- 下
        nvgBeginPath(vg)
        nvgRect(vg, 0, h - borderW, w, borderW)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)
        -- 左
        nvgBeginPath(vg)
        nvgRect(vg, 0, borderW, borderW, h - borderW * 2)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)
        -- 右
        nvgBeginPath(vg)
        nvgRect(vg, w - borderW, borderW, borderW, h - borderW * 2)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)

        -- 角落加强发光（四角各一个小方块）
        local cornerSize = 16
        local ca = math.floor(pulse * 100)
        -- 左上
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], ca))
        nvgFill(vg)
        -- 右上
        nvgBeginPath(vg)
        nvgRect(vg, w - cornerSize, 0, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], ca))
        nvgFill(vg)
        -- 左下
        nvgBeginPath(vg)
        nvgRect(vg, 0, h - cornerSize, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], ca))
        nvgFill(vg)
        -- 右下
        nvgBeginPath(vg)
        nvgRect(vg, w - cornerSize, h - cornerSize, cornerSize, cornerSize)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], ca))
        nvgFill(vg)

        nvgRestore(vg)
    end

    -- ======== 沉默冲击环（execute 阶段） ========
    if sk and sk.ringRadius and sk.ringDuration then
        local rt = sk.ringTimer or 0
        local progress = math.min(1.0, rt / sk.ringDuration)
        local radius = sk.ringRadius or 0
        if radius > 0 then
            local ringAlpha = (1.0 - progress) * 200
            local rx = sk.ringX or (w * 0.5)
            local ry = sk.ringY or (h * 0.5)

            -- 外环
            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, radius)
            nvgStrokeColor(vg, nvgRGBA(140, 50, 200, math.floor(ringAlpha)))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            -- 内环（更亮，半径略小）
            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, radius * 0.85)
            nvgStrokeColor(vg, nvgRGBA(180, 100, 255, math.floor(ringAlpha * 0.6)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end

--- 憎恨化身 BOSS 技能特效
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
        local halfArea = CELL * 1.5  -- 3 格的一半
        local areaX = cx - halfArea
        local areaY = cy - halfArea
        local areaSize = CELL * 3

        local progress = 1.0 - math.max(0, (sc.timer or 0) / (sc.totalTime or 3.0))
        local pulse = 0.5 + 0.5 * math.abs(math.sin((sc.timer or 0) * 5))

        -- 区域底色（脉动红/紫）
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

        -- 区域边框（进度越高越亮）
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

        -- 背景
        nvgBeginPath(vg)
        nvgRect(vg, barX, barY, barW, barH)
        nvgFillColor(vg, nvgRGBA(30, 30, 30, 180))
        nvgFill(vg)

        -- 韧性值（橙黄色）
        if tRatio > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, barX, barY, barW * tRatio, barH)
            nvgFillColor(vg, nvgRGBA(240, 180, 40, 220))
            nvgFill(vg)
        end

        -- 韧性条边框
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
        local pulse = 0.5 + 0.5 * math.abs(math.sin(os.clock() * 3))
        local timer = dest.timer or 0
        local totalTime = dest.totalTime or 5.0
        local timerRatio = math.max(0, timer / math.max(0.01, totalTime))

        -- 覆盖区域（深红半透明方块，用切比雪夫距离 radius 格）
        local coveredSize = radius * CELL
        nvgBeginPath(vg)
        nvgRect(vg, dcx - coveredSize, dcy - coveredSize, coveredSize * 2, coveredSize * 2)
        local urgencyAlpha = math.floor(40 + 40 * (1 - timerRatio) + 20 * pulse)
        nvgFillColor(vg, nvgRGBA(180, 10, 10, urgencyAlpha))
        nvgFill(vg)

        -- 区域边框（随倒计时越来越亮）
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

        -- 中心倒计时文字（缓存到 0.1s 精度）
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

        -- 韧性条（屏幕顶部居中显示）
        local barW = 200
        local barH = 10
        local barX = (w - barW) * 0.5
        local barY = 50
        local tRatio = math.max(0, (dest.toughness or 0) / math.max(1, dest.maxToughness or 1))

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(30, 30, 30, 200))
        nvgFill(vg)

        -- 韧性值（红黄渐变）
        if tRatio > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * tRatio, barH, 3)
            local paint = nvgLinearGradient(vg, barX, barY, barX + barW * tRatio, barY,
                nvgRGBA(255, 60, 20, 230), nvgRGBA(255, 200, 40, 230))
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end

        -- 边框
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

    -- ======== 3. 施法边框（通用，复用 Emerald 风格） ========
    local casting = hk.casting
    if casting and casting.phase then
        local c = casting.color or { 180, 40, 60 }
        local t = casting.timer or 0
        local pulse = 0.3 + 0.7 * math.abs(math.sin(t * 6))
        local a = math.floor(pulse * 150)
        local borderW = 3

        nvgSave(vg)
        local shakeX = math.sin(t * 30) * 1.5
        local shakeY = math.cos(t * 25) * 1.0
        nvgTranslate(vg, shakeX, shakeY)

        -- 四边
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, borderW)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, 0, h - borderW, w, borderW)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, 0, borderW, borderW, h - borderW * 2)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, w - borderW, borderW, borderW, h - borderW * 2)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
        nvgFill(vg)

        nvgRestore(vg)
    end

    -- ======== 4. BOSS 身上的光环指示器 ========
    local bx = hk.bossX
    local by = hk.bossY
    local bSize = hk.bossSize or 22
    if bx and by then
        local halfS = bSize * 0.5

        -- 嘲讽光环（红色脉动圆环，画在精灵图中心）
        if hk.tauntActive then
            local imgSize = bSize * 2.8
            local centerY = by - imgSize * 0.5  -- 精灵图中心
            local tPulse = 0.5 + 0.5 * math.abs(math.sin(os.clock() * 4))
            nvgBeginPath(vg)
            nvgCircle(vg, bx, centerY, halfS + 4 + tPulse * 3)
            nvgStrokeColor(vg, nvgRGBA(220, 40, 40, math.floor(120 + 80 * tPulse)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 嘲讽图标（小三角朝内）
            local iconR = halfS + 10
            for i = 0, 3 do
                local angle = (i * math.pi * 0.5) + os.clock() * 0.8
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

        -- 壁垒护盾：无额外绘制（仅数值减伤效果）
    end
end

-- ============================================================================
-- 遗物充能条（棋盘下方）
-- ============================================================================

local _relicChargeImgCache = {}
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
        _relicChargeGlowTime = _relicChargeGlowTime + 1.0 / 60.0
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

end
