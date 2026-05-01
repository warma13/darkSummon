-- Game/Heroes/dream_weave.lua
-- 梦璃：幻梦印记 (dream_mark) + 梦境共鸣 (dream_resonance) + 万象沉梦 (dreamscape)
local M = {}

local State = require("Game.State")

local AddFloatingText = State.AddFloatingText

-- 飘字颜色
local COLOR_DREAM_BURST = { 155, 115, 207, 255 }   -- 琉璃紫 — 沉梦爆发
local COLOR_DREAM_SPLASH = { 130, 100, 190, 255 }   -- 淡紫 — 意识冲击
local COLOR_DREAMSCAPE = { 180, 130, 230, 255 }      -- 亮紫 — 万象沉梦

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

-- ============================================================================
-- 被动①：幻梦印记 — OnHit
-- 叠加印记到目标(per-target)，满层沉梦：眩晕+爆发+溅射
-- ============================================================================

---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local mark = has(tower, "dream_mark")
    if not mark or not target.alive then return end

    local HeroSkills = require("Game.HeroSkills")
    local Combat     = require("Game.Combat")
    local Enemy      = require("Game.Enemy")

    -- 叠加1层幻梦印记（per-target），刷新持续时间
    local maxStacks = mark.maxStacks or 4
    target.dreamStacks = math.min((target.dreamStacks or 0) + 1, maxStacks)
    target.dreamStackTimer = mark.stackDuration or 5.0

    -- 技能标签：lucid_pulse — 叠印记期间攻速加成
    local tags = tower.tagState
    if tags then
        local lp = tags.lucid_pulse
        if lp and lp.effects then
            local eff = lp.effects
            -- 减速 on hit
            if eff.slowOnHit and eff.slowDuration then
                local Debuff = require("Game.Debuff")
                local slowDur = eff.slowDuration
                if target.isBoss then
                    slowDur = slowDur * (require("Game.Config").BOSS_BALANCE.slowEfficiency or 0.50)
                end
                Debuff.Apply(target, "slow", { pct = eff.slowOnHit, duration = slowDur })
            end
            -- 叠印记期间攻速+
            if eff.stackSpeedUp then
                tower.hstate.dreamSpdBuff = eff.stackSpeedUp
            end
        end
    end

    -- 满层触发沉梦
    if target.dreamStacks >= maxStacks then
        local atk = HeroSkills.GetEffectiveAttack(tower)

        -- === 眩晕 ===
        local stunDur = mark.stunDuration or 1.5
        -- 技能标签 deep_slumber：额外眩晕时间
        if tags then
            local ds = tags.deep_slumber
            if ds and ds.effects and ds.effects.extraStunDuration then
                stunDur = stunDur + ds.effects.extraStunDuration
            end
        end
        HeroSkills.ApplyStun(target, stunDur)

        -- === 爆发伤害 ===
        local burstPct = mark.burstAtkPct or 2.50
        -- 技能标签 deep_slumber：额外爆发倍率
        if tags then
            local ds = tags.deep_slumber
            if ds and ds.effects then
                if ds.effects.burstAtkPctBonus then
                    burstPct = burstPct + ds.effects.burstAtkPctBonus
                end
                if ds.effects.armorIgnore then
                    target.armorReduceFromDot = ds.effects.armorIgnore
                end
            end
        end
        local burstDmg = atk * burstPct
        local finalDmg = Combat.CalcFinalDamage(tower, target, burstDmg)
        Enemy.TakeDamage(target, finalDmg)

        -- 爆发飘字
        local size = target.typeDef.size or 8
        AddFloatingText({
            text     = "沉梦爆发!",
            x        = target.x + (math.random() - 0.5) * 10,
            y        = target.y - size - 20,
            life     = 1.0,
            color    = COLOR_DREAM_BURST,
            fontSize = 14,
        })

        -- === 溅射伤害（意识冲击） ===
        local splashPct = mark.splashAtkPct or 1.20
        local splashRadius = mark.splashRadius or 50
        local splashDmg = atk * splashPct
        for _, e in ipairs(State.enemies) do
            if e.alive and e ~= target then
                local dx = e.x - target.x
                local dy = e.y - target.y
                if dx * dx + dy * dy <= splashRadius * splashRadius then
                    local sDmg = Combat.CalcFinalDamage(tower, e, splashDmg)
                    Enemy.TakeDamage(e, sDmg)
                    AddFloatingText({
                        text     = "意识冲击",
                        x        = e.x + (math.random() - 0.5) * 8,
                        y        = e.y - (e.typeDef.size or 8) - 14,
                        life     = 0.7,
                        color    = COLOR_DREAM_SPLASH,
                        fontSize = 11,
                    })
                end
            end
        end

        -- 消耗全部印记
        target.dreamStacks = 0
        target.dreamStackTimer = nil

        print("[Heroes] dream_mark burst on enemy " .. tostring(target.id)
            .. " dmg=" .. math.floor(finalDmg))
    end
end

-- ============================================================================
-- 主动：万象沉梦 — TriggerActive
-- 全屏幻梦伤害+眩晕，已有印记的敌人每层额外加成
-- ============================================================================

---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "dreamscape" then return end

    local HeroSkills = require("Game.HeroSkills")
    local Combat     = require("Game.Combat")
    local Enemy      = require("Game.Enemy")

    local atk = HeroSkills.GetEffectiveAttack(tower)
    local basePct = skill.baseAtkPct or 7.0
    local stunDur = skill.stunDuration or 1.0
    local stackBonus = skill.stackBonusPct or 0.80

    -- 技能标签 nightmare_wave：冷却减少已在 skill.interval 处理
    local tags = tower.tagState
    local afterStunDot, dotDuration, globalDreamApply
    if tags then
        local nw = tags.nightmare_wave
        if nw and nw.effects then
            afterStunDot = nw.effects.afterStunDot
            dotDuration = nw.effects.dotDuration
            globalDreamApply = nw.effects.globalDreamApply
        end
    end

    -- 技能闪光
    State.skillFlash = { type = "dreamscape", timer = 0.8, tower = tower }

    local totalDmg = 0
    for _, e in ipairs(State.enemies) do
        if e.alive then
            -- 计算伤害：基础 + 每层印记额外加成
            local stacks = e.dreamStacks or 0
            local dmgPct = basePct + stackBonus * stacks
            local dmg = atk * dmgPct
            local finalDmg = Combat.CalcFinalDamage(tower, e, dmg)
            Enemy.TakeDamage(e, finalDmg)
            totalDmg = totalDmg + finalDmg

            -- 眩晕
            HeroSkills.ApplyStun(e, stunDur)

            -- 技能标签：眩晕后 DOT
            if afterStunDot and dotDuration then
                local Debuff = require("Game.Debuff")
                Debuff.Apply(e, "dot", {
                    duration = dotDuration,
                    tickDamage = atk * afterStunDot,
                    source = tower,
                })
            end

            -- 消耗所有幻梦印记
            e.dreamStacks = 0
            e.dreamStackTimer = nil
        end
    end

    -- 技能标签：全屏施加幻梦印记
    if globalDreamApply and globalDreamApply > 0 then
        local mark = has(tower, "dream_mark")
        local maxStacks = mark and (mark.maxStacks or 4) or 4
        local stackDur = mark and (mark.stackDuration or 5.0) or 5.0
        for _, e in ipairs(State.enemies) do
            if e.alive then
                e.dreamStacks = math.min((e.dreamStacks or 0) + globalDreamApply, maxStacks)
                e.dreamStackTimer = stackDur
            end
        end
    end

    -- 伤害飘字（总伤害）
    local dmgText = tostring(math.floor(totalDmg))
    if totalDmg >= 1e8 then
        dmgText = string.format("%.1f亿", totalDmg / 1e8):gsub("%.0亿", "亿")
    elseif totalDmg >= 1e4 then
        dmgText = string.format("%.1f万", totalDmg / 1e4):gsub("%.0万", "万")
    end

    -- 用 tower 位置显示主动技能飘字
    AddFloatingText({
        text     = "万象沉梦!",
        x        = tower._sx or 0,
        y        = (tower._sy or 0) - 30,
        life     = 1.2,
        color    = COLOR_DREAMSCAPE,
        fontSize = 16,
    })
    AddFloatingText({
        text     = dmgText .. "!",
        x        = (tower._sx or 0) + (math.random() - 0.5) * 20,
        y        = (tower._sy or 0) - 50,
        vx       = (math.random() - 0.5) * 60,
        vy       = -(60 + math.random() * 30),
        life     = 0.9,
        maxLife  = 0.9,
        color    = COLOR_DREAMSCAPE,
        fontSize = 15,
        isCrit   = true,
    })

    print("[Heroes] dreamscape total dmg=" .. math.floor(totalDmg))
end

-- ============================================================================
-- 帧更新：印记衰减 + 梦境共鸣光环 + 眩晕计数增益
-- ============================================================================

---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    -- 1) 衰减所有敌人身上的幻梦印记计时器
    for _, e in ipairs(State.enemies) do
        if e.alive and e.dreamStackTimer and e.dreamStackTimer > 0 then
            e.dreamStackTimer = e.dreamStackTimer - dt
            if e.dreamStackTimer <= 0 then
                e.dreamStacks = (e.dreamStacks or 1) - 1
                if (e.dreamStacks or 0) <= 0 then
                    e.dreamStacks = 0
                    e.dreamStackTimer = nil
                else
                    e.dreamStackTimer = 1.5  -- 后续逐层衰减间隔
                end
            end
        end
    end

    -- 2) 统计全局被眩晕的敌人数量（用于梦境共鸣额外攻击力加成）
    local stunnedCount = 0
    for _, e in ipairs(State.enemies) do
        if e.alive and e.stunTimer and e.stunTimer > 0 then
            stunnedCount = stunnedCount + 1
        end
    end

    -- 3) 遍历 dream_weave 塔，应用梦境共鸣光环
    for _, tower in ipairs(towers) do
        if tower.typeDef and tower.typeDef.id == "dream_weave" and tower.hstate then
            local hs = tower.hstate
            local resonance = has(tower, "dream_resonance")
            if not resonance then goto continueTower end

            local auraRange = resonance.auraRange or 110
            local spdBuff = resonance.auraSpdBuff or 0.25
            local critBuff = resonance.auraCritBuff or 0.15

            -- 技能标签 dream_echo：额外光环增益
            local tags = tower.tagState
            local extraAtkBuff = 0
            local extraCritDmg = 0
            if tags then
                local de = tags.dream_echo
                if de and de.effects then
                    extraAtkBuff = de.effects.auraAtkBuff or 0
                    extraCritDmg = de.effects.auraCritDmg or 0
                    if de.effects.auraRangeBonus then
                        auraRange = auraRange + de.effects.auraRangeBonus
                    end
                end
            end

            -- 眩晕敌人额外攻击力加成
            local stunAtkBonus = math.min(
                stunnedCount * (resonance.stunAtkBonusPerEnemy or 0.05),
                resonance.stunAtkBonusMax or 0.25
            )

            -- 总攻击力加成
            local totalAtkBuff = stunAtkBonus + extraAtkBuff

            -- 对范围内友方塔施加光环效果
            for _, ally in ipairs(towers) do
                if ally ~= tower and ally.typeDef then
                    local dx = (ally._sx or 0) - (tower._sx or 0)
                    local dy = (ally._sy or 0) - (tower._sy or 0)
                    if dx * dx + dy * dy <= auraRange * auraRange then
                        -- 攻速加成（累加到 hstate，由引擎读取）
                        if ally.hstate then
                            ally.hstate.dreamAuraSpdBuff = spdBuff
                            ally.hstate.dreamAuraCritBuff = critBuff
                            ally.hstate.dreamAuraAtkBuff = totalAtkBuff
                            ally.hstate.dreamAuraCritDmgBuff = extraCritDmg
                        end
                    else
                        -- 离开范围清除
                        if ally.hstate then
                            ally.hstate.dreamAuraSpdBuff = nil
                            ally.hstate.dreamAuraCritBuff = nil
                            ally.hstate.dreamAuraAtkBuff = nil
                            ally.hstate.dreamAuraCritDmgBuff = nil
                        end
                    end
                end
            end

            -- lucid_pulse 攻速加成衰减（非叠印记状态时清除）
            if hs.dreamSpdBuff and not tower.target then
                hs.dreamSpdBuff = nil
            end

            ::continueTower::
        end
    end
end

return M
