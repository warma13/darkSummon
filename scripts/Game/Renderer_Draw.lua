-- Game/Renderer_Draw.lua
-- 绘制：敌人、弹道、粒子、飘字、合成闪光、拖拽、技能闪光、怪物计数

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

local Enemy = require("Game.Enemy")

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
            EmitDebuffParticles(e, Renderer.frameDt)

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

--- 技能闪光颜色表 { r, g, b, alphaScale }
local SKILL_FLASH_COLORS = {
    void_storm         = { 0.4,  0.1,  0.6,  0.15 },
    arrow_rain         = { 0.2,  0.6,  0.2,  0.1  },
    hell_gate          = { 0.6,  0.1,  0.1,  0.1  },
    emerald_shackle    = { 0.15, 0.5,  0.2,  0.12 },
    emerald_silence    = { 0.45, 0.15, 0.6,  0.15 },
    emerald_decay      = { 0.4,  0.45, 0.15, 0.1  },
    hatred_summon      = { 0.7,  0.35, 0.1,  0.12 },
    hatred_fortress    = { 0.15, 0.35, 0.7,  0.12 },
    hatred_taunt       = { 0.6,  0.08, 0.08, 0.15 },
    hatred_star_crush  = { 0.5,  0.1,  0.6,  0.18 },
    hatred_destruction = { 0.8,  0.05, 0.05, 0.20 },
    relic_cast         = { 0.55, 0.3,  0.8,  0.22 },
}

--- 绘制技能闪光效果
function Renderer.DrawSkillFlash(vg, w, h)
    if not State.skillFlash then return end
    local sf = State.skillFlash
    local alpha = sf.timer / 0.5

    local c = SKILL_FLASH_COLORS[sf.type]
    if not c then return end

    -- 全屏闪光覆盖
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBAf(c[1], c[2], c[3], alpha * c[4]))
    nvgFill(vg)

    -- relic_cast 额外扩散亮线
    if sf.type == "relic_cast" then
        local spread = (1.0 - alpha) * math.max(w, h) * 0.6
        local cx, cy = w * 0.5, h * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, spread)
        nvgStrokeColor(vg, nvgRGBAf(0.9, 0.75, 1.0, alpha * 0.35))
        nvgStrokeWidth(vg, 3.0 * alpha)
        nvgStroke(vg)
    end
end


end
