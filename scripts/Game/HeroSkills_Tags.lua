-- Game/HeroSkills_Tags.lua
-- 技能标签系统：初始化 / 触发 / active 更新 / 升级
-- 从 HeroSkills.lua 拆分，注入到 HeroSkills 表

local Config   = require("Game.Config")
local State    = require("Game.State")
local HeroData = require("Game.HeroData")
local AffixTagResolver = require("Game.AffixTagResolver")

local AddFloatingText = State.AddFloatingText
local COLOR_FROZEN = { 100, 180, 255, 255 }

-- 延迟 require（避免循环依赖）
local _Enemy, _Debuff
local function GetEnemy()
    if not _Enemy then _Enemy = require("Game.Enemy") end
    return _Enemy
end
local function GetDebuff()
    if not _Debuff then _Debuff = require("Game.Debuff") end
    return _Debuff
end

--- 注入标签系统函数到 HeroSkills 表
---@param HeroSkills table
return function(HeroSkills)

-- ============================================================================
-- 初始化塔的技能标签状态
-- ============================================================================

--- 从 Config.HERO_SKILL_TAGS 读取定义，结合 HeroData 持久化层级
---@param tower table
function HeroSkills.InitTagState(tower)
    local heroId = tower.typeDef.id
    local tagDefs = Config.HERO_SKILL_TAGS[heroId]
    if not tagDefs then
        tower.tags = {}
        return
    end

    tower.tags = {}
    for i, tagDef in ipairs(tagDefs) do
        local tier = HeroData.GetTagTier(heroId, tagDef.id)
        local unlocked = HeroData.IsTagUnlocked(heroId, tagDef)

        -- 顺序解锁：前一个标签 tier > 0 才能解锁后一个
        local reqMet = true
        if i > 1 then
            local prevTag = tagDefs[i - 1]
            if HeroData.GetTagTier(heroId, prevTag.id) <= 0 then
                reqMet = false
            end
        end

        -- 检查显式依赖标签
        if reqMet and tagDef.requires then
            for _, reqId in ipairs(tagDef.requires) do
                if HeroData.GetTagTier(heroId, reqId) <= 0 then
                    reqMet = false
                    break
                end
            end
        end

        tower.tags[tagDef.id] = {
            def      = tagDef,
            tier     = (unlocked and reqMet) and tier or 0,
            maxTier  = tagDef.maxTier or 1,
            unlocked = unlocked,
            reqMet   = reqMet,
            -- 运行时状态（用于 cooldown / stacks 等）
            cd       = 0,
            stacks   = 0,
            timer    = 0,
        }

        -- 被动标签立即应用属性加成
        if tagDef.type == "passive" and tier > 0 and unlocked and reqMet then
            local eff = tagDef.effects and tagDef.effects[tier]
            if eff then
                if eff.atkSpdBonus then
                    tower.atkSpdBonus = (tower.atkSpdBonus or 0) + eff.atkSpdBonus
                end
                if eff.critRate then
                    tower.critRate = (tower.critRate or 0) + eff.critRate
                end
                if eff.critDmg then
                    tower.critDmg = (tower.critDmg or 0) + eff.critDmg
                end
                if eff.rangeBonus then
                    tower.range = (tower.range or 0) + eff.rangeBonus
                end
                if eff.bossExtraDmg then
                    tower.bossExtraDmg = math.max(tower.bossExtraDmg or 0, eff.bossExtraDmg)
                end
                if eff.armorIgnore then
                    tower.armorIgnore = (tower.armorIgnore or 0) + eff.armorIgnore
                end
                if eff.bonusPerWave then
                    local hs = tower.hstate
                    if hs then
                        hs.bonusPerWaveRate = eff.bonusPerWave
                        hs.bonusPerWaveMax  = eff.maxBonus or 0.50
                        hs.bonusPerWaveSpd  = 0
                    end
                end
                -- 血契标签 blood_pact: atkPerMark 已在 HeroSkills.UpdateFrame 中
                -- 通过 tower.tags["blood_pact"] → resonanceAtkBonus 路径处理，
                -- 无需在 passive init 中重复写入 hstate

                -- 月蚀天象标签：击杀加攻 / 满月时长 / 满月激活纯伤
                if eff.soulAtkPerKillBonus or eff.fullMoonDurationBonus or eff.fullMoonAoePct then
                    local hs = tower.hstate
                    if hs then
                        if eff.soulAtkPerKillBonus then
                            hs.soulAtkPerKillBonus = eff.soulAtkPerKillBonus
                        end
                        if eff.fullMoonDurationBonus then
                            hs.fullMoonDurationBonus = eff.fullMoonDurationBonus
                        end
                        if eff.fullMoonAoePct then
                            hs.fullMoonAoePct = eff.fullMoonAoePct
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 标签查询
-- ============================================================================

--- 获取标签当前层级的效果表
---@param tower table
---@param tagId string
---@return table|nil effect, table|nil tagState
function HeroSkills.GetTagEffect(tower, tagId)
    local ts = tower.tags and tower.tags[tagId]
    if not ts or ts.tier <= 0 then return nil, nil end
    local eff = ts.def.effects and ts.def.effects[ts.tier]
    return eff, ts
end

--- 按触发类型批量应用标签
--- triggerType: "on_hit" | "on_crit" | "on_kill"
---@param tower table
---@param target table|nil
---@param triggerType string
---@param extra table|nil
function HeroSkills.ApplyTags(tower, target, triggerType, extra)
    if not tower.tags then return end

    for tagId, ts in pairs(tower.tags) do
        if ts.tier > 0 and ts.def.type == triggerType then
            local eff = ts.def.effects and ts.def.effects[ts.tier]
            if eff then
                HeroSkills.ApplyTag(tower, target, ts, eff, extra)
            end
        end
    end
end

-- ============================================================================
-- 应用单个标签效果
-- ============================================================================

---@param tower table
---@param target table|nil
---@param tagState table
---@param eff table
---@param extra table|nil
function HeroSkills.ApplyTag(tower, target, tagState, eff, extra)
    local tagDef = tagState.def
    local tagId  = tagDef.id

    -- 查询第3层词条加成
    local tagBonus = AffixTagResolver.GetTagBonus(tower, tagId)

    -- 概率检查（通用：eff.chance）
    if eff.chance then
        local finalChance = eff.chance + (tagBonus.tagChance_add or 0)
        if math.random() > finalChance then return end
    end

    local Enemy = GetEnemy()

    -- ================================================================
    -- 通用效果分支（按效果字段匹配）
    -- ================================================================

    -- 减速效果
    if eff.slowRate and target and target.alive then
        local slowRate = eff.slowRate + (tagBonus.tagSlowRate_add or 0)
        local slowDur  = (eff.slowDuration or eff.duration or 2.0) + (tagBonus.tagSlowDur_add or 0)
        Enemy.ApplySlow(target, slowDur, slowRate)
    end

    -- DOT 效果
    if eff.dotMultiplier and target and target.alive then
        local mult = eff.dotMultiplier + (tagBonus.tagDotMult_add or 0)
        tower.tagDotMultiplier = (tower.tagDotMultiplier or 1.0) * mult
    end

    if eff.dotAtkPct and target and target.alive then
        local dotDmg = tower.attack * (eff.dotAtkPct + (tagBonus.tagDotPct_add or 0))
        local dotDur = eff.dotDuration or 3.0
        Enemy.ApplyDOT(target, dotDmg, dotDur)
    end

    -- 物理易伤
    if eff.physVuln and target and target.alive then
        local vuln = eff.physVuln + (tagBonus.tagVuln_add or 0)
        local dur  = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        target.physVuln = math.max(target.physVuln or 0, vuln)
        target.physVulnTimer = math.max(target.physVulnTimer or 0, dur)
    end

    -- 法术易伤
    if eff.magicVuln and target and target.alive then
        local vuln = eff.magicVuln + (tagBonus.tagVuln_add or 0)
        local dur  = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        target.magicVuln = math.max(target.magicVuln or 0, vuln)
        target.magicVulnTimer = math.max(target.magicVulnTimer or 0, dur)
    end

    -- 破甲
    if eff.armorBreak and target and target.alive then
        local breakAmt = eff.armorBreak * (1 + (tagBonus.tagArmorBreak_amp or 0))
        target.armorBreak = math.min((target.armorBreak or 0) + breakAmt, 1.0)
    end

    if eff.defReducePerStack and target and target.alive then
        local reduce = eff.defReducePerStack * (1 + (tagBonus.tagArmorBreak_amp or 0))
        target.defReduce = math.min((target.defReduce or 0) + reduce, 0.80)
    end

    -- 增伤标记
    if eff.ampRate and target and target.alive then
        local amp = eff.ampRate + (tagBonus.tagAmp_add or 0)
        target.ampDamage = math.max(target.ampDamage or 0, amp)
    end

    -- 攻速爆发（on_kill 类）
    if eff.atkSpdBurst then
        local burst = eff.atkSpdBurst + (tagBonus.tagAtkSpd_add or 0)
        local dur   = eff.burstDuration or 3.0
        tower.hstate.killAtkBurst = burst
        tower.hstate.killAtkBurstTimer = dur
    end

    -- 击杀加伤（on_kill 类叠层）
    if eff.killDmgBonus then
        local bonus = eff.killDmgBonus + (tagBonus.tagDmgBonus_add or 0)
        local max   = eff.maxStacks or 3
        tower.hstate.killDmgStacks = math.min((tower.hstate.killDmgStacks or 0) + 1, max)
        tower.hstate.killDmgBonus  = bonus
    end

    -- 击杀爆炸（phantom_chain / holy_chain）
    if eff.deathExplosionPct and target then
        local explDmg = tower.attack * eff.deathExplosionPct
        local explRange = eff.explosionRange or 40
        local rangeSq = explRange * explRange
        for _, e in ipairs(State.enemies) do
            if e.alive and e ~= target then
                local dx = e.x - target.x
                local dy = e.y - target.y
                if dx * dx + dy * dy < rangeSq then
                    Enemy.TakeDamage(e, explDmg)
                end
            end
        end
    end

    -- 眩晕
    if eff.stunChance and target and target.alive then
        local stunChance = eff.stunChance + (tagBonus.tagStunChance_add or 0)
        if math.random() < stunChance then
            local stunDur = (eff.stunDuration or 1.0) + (tagBonus.tagStunDur_add or 0)
            HeroSkills.ApplyStun(target, stunDur)
        end
    end

    -- 溅射
    if eff.splashRange and target and target.alive then
        local range = eff.splashRange + (tagBonus.tagSplashRange_add or 0)
        local rangeSq = range * range
        local splashDmg = (extra and extra.damage or tower.attack) * (eff.splashPct or 0.50)
        for _, e in ipairs(State.enemies) do
            if e.alive and e ~= target then
                local dx = e.x - target.x
                local dy = e.y - target.y
                if dx * dx + dy * dy < rangeSq then
                    Enemy.TakeDamage(e, splashDmg)
                end
            end
        end
    end

    -- 治疗削弱
    if eff.healReduction and target and target.alive then
        target.healReduction = math.max(target.healReduction or 0, eff.healReduction)
    end

    -- 连锁
    if eff.chainRange and target and target.alive then
        local chainRange = eff.chainRange + (tagBonus.tagChainRange_add or 0)
        local maxTargets = eff.chainMaxTargets or 2
        local rangeSq = chainRange * chainRange
        local count = 0
        local chainDmg = (extra and extra.damage or tower.attack) * (eff.chainDmgPct or 0.50)
        for _, e in ipairs(State.enemies) do
            if e.alive and e ~= target and count < maxTargets then
                local dx = e.x - target.x
                local dy = e.y - target.y
                if dx * dx + dy * dy < rangeSq then
                    Enemy.TakeDamage(e, chainDmg)
                    count = count + 1
                end
            end
        end
    end

    -- ================================================================
    -- 以下为新增标签效果处理（v1.0.82）
    -- ================================================================

    -- 首击加伤（shadow_stab: firstHitMult）
    if eff.firstHitMult and target and target.alive then
        tagState._hitTargets = tagState._hitTargets or {}
        if not tagState._hitTargets[target] then
            tagState._hitTargets[target] = true
            local baseDmg = extra and extra.damage or tower.attack
            local bonusDmg = baseDmg * (eff.firstHitMult - 1)
            Enemy.TakeDamage(target, bonusDmg)
            AddFloatingText({
                text     = "暗刺",
                x        = target.x + (math.random() - 0.5) * 10,
                y        = target.y - (target.typeDef.size or 8) - 20,
                life     = 0.6,
                color    = { 180, 80, 220, 255 },
                fontSize = 12,
            })
        end
    end

    -- 概率AOE伤害（conflagration）
    if eff.aoeDmgPct and target and target.alive then
        local aoeDmg = tower.attack * eff.aoeDmgPct
        local aoeRange = eff.aoeRange or 40
        local rangeSq = aoeRange * aoeRange
        for _, e in ipairs(State.enemies) do
            if e.alive and e ~= target then
                local dx = e.x - target.x
                local dy = e.y - target.y
                if dx * dx + dy * dy < rangeSq then
                    Enemy.TakeDamage(e, aoeDmg)
                end
            end
        end
    end

    -- 魔抗降低（searing / spatial_warp / chaos_rift 等）
    if eff.resReduce and target and target.alive then
        local dur = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        if eff.aoeRange and not eff.aoeDmgPct then
            local rangeSq = eff.aoeRange * eff.aoeRange
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    local dx = e.x - target.x
                    local dy = e.y - target.y
                    if dx * dx + dy * dy < rangeSq then
                        e.tagResReduce = math.max(e.tagResReduce or 0, eff.resReduce)
                        e.tagResReduceTimer = math.max(e.tagResReduceTimer or 0, dur)
                    end
                end
            end
        else
            target.tagResReduce = math.max(target.tagResReduce or 0, eff.resReduce)
            target.tagResReduceTimer = math.max(target.tagResReduceTimer or 0, dur)
        end
    end

    -- 物防降低百分比
    if eff.defReduce and target and target.alive then
        local dur = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        target.tagDefReduce = math.min((target.tagDefReduce or 0) + eff.defReduce, 0.60)
        target.tagDefReduceTimer = math.max(target.tagDefReduceTimer or 0, dur)
    end

    -- 受伤加成标记（pierce_mark: bonusDmg）
    if eff.bonusDmg and not eff.defReducePct and target and target.alive then
        local dur = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        target.tagBonusDmg = math.max(target.tagBonusDmg or 0, eff.bonusDmg)
        target.tagBonusDmgTimer = math.max(target.tagBonusDmgTimer or 0, dur)
    end

    -- 叠层受伤加成（shadow_mark / charge / toxin_layer / hellfire_brand）
    if eff.dmgPerStack and target and target.alive then
        target.tagDmgStacks = math.min((target.tagDmgStacks or 0) + 1, eff.maxStacks or 5)
        target.tagDmgPerStack = eff.dmgPerStack
        target.tagDmgStackTimer = eff.stackDuration or eff.duration or 6.0
    end

    -- 每N次攻击真伤（heavy_blow）
    if eff.everyN and target and target.alive then
        tagState._hitCount = (tagState._hitCount or 0) + 1
        if tagState._hitCount >= eff.everyN then
            tagState._hitCount = 0
            local trueDmg = tower.attack * (eff.trueDmgPct or 0.50)
            Enemy.TakeDamage(target, trueDmg)
            AddFloatingText({
                text     = "重击",
                x        = target.x + (math.random() - 0.5) * 10,
                y        = target.y - (target.typeDef.size or 8) - 20,
                life     = 0.6,
                color    = { 255, 160, 60, 255 },
                fontSize = 12,
            })
        end
    end

    -- 低血线真伤（divine_wrath）
    if eff.lowHpThreshold and target and target.alive then
        local hpRatio = target.hp / (target.maxHp or target.hp)
        if hpRatio < eff.lowHpThreshold then
            local trueDmg = tower.attack * (eff.trueDmgPct or 1.0)
            Enemy.TakeDamage(target, trueDmg)
        end
    end

    -- 冰封（frozen）
    if eff.freezeChance and target and target.alive then
        if math.random() < eff.freezeChance then
            local dur = eff.freezeDuration or 0.8
            if target.isBoss then
                dur = dur * (Config.BOSS_BALANCE.stunDurationMult or 0.50)
                Enemy.ApplySlow(target, dur, 0.50 * (Config.BOSS_BALANCE.slowEfficiency or 0.50))
            else
                Enemy.ApplySlow(target, dur, 1.0)
                GetDebuff().Apply(target, "frozen", { duration = dur })
            end
            if eff.bonusDmg then
                target.tagFrozenBonusDmg = eff.bonusDmg
                target.tagFrozenTimer = dur
            end
            AddFloatingText({
                text     = "冰封",
                x        = target.x + (math.random() - 0.5) * 10,
                y        = target.y - (target.typeDef.size or 8) - 16,
                life     = 0.6,
                color    = COLOR_FROZEN,
                fontSize = 12,
            })
        end
    end

    -- 逐层暴击叠加（blood_eye）
    if eff.critRatePerHit and target and target.alive then
        tagState.stacks = math.min((tagState.stacks or 0) + 1, eff.maxCritStacks or 5)
        tower.tagCritRateBonus = tagState.stacks * eff.critRatePerHit
        tower.tagCritDmgBonus  = eff.critDmgBonus or 0
    end

    -- 魔焰叠层暴击暴伤（infernal_stack）
    if eff.critPerStack and target and target.alive then
        tagState.stacks = math.min((tagState.stacks or 0) + 1, eff.maxStacks or 5)
        tagState.timer  = eff.stackDuration or 5.0
        tower.tagInfernalCritRate = tagState.stacks * eff.critPerStack
        tower.tagInfernalCritDmg = tagState.stacks * eff.critDmgPerStack
    end

    -- 连续攻击同目标叠伤（focus_fire）
    if eff.dmgIncPerHit and target and target.alive then
        if tagState._lastTarget == target then
            tagState._focusStacks = math.min((tagState._focusStacks or 0) + 1, eff.maxStacks or 10)
        else
            tagState._lastTarget = target
            tagState._focusStacks = 1
        end
        tower.tagFocusFireBonus = tagState._focusStacks * eff.dmgIncPerHit
    end

    -- 穿透（penetrate）
    if eff.pierce and target and target.alive then
        local pierceDmg = tower.attack * (eff.pierceDmgPct or 0.60)
        local bestDist = math.huge
        local bestEnemy = nil
        for _, e in ipairs(State.enemies) do
            if e.alive and e ~= target then
                local dx = e.x - target.x
                local dy = e.y - target.y
                local dist = dx * dx + dy * dy
                if dist < bestDist and dist < 80 * 80 then
                    bestDist = dist
                    bestEnemy = e
                end
            end
        end
        if bestEnemy then
            Enemy.TakeDamage(bestEnemy, pierceDmg)
        end
    end

    -- 拉拽（dimension_collapse）
    if eff.pullChance and target and target.alive then
        if math.random() < eff.pullChance then
            target.pathProgress = math.max(0, (target.pathProgress or 0) - (eff.pullDistance or 30))
        end
    end

    -- 斩杀（annihilate）
    if eff.executeThreshold and target and target.alive then
        local hpRatio = target.hp / (target.maxHp or target.hp)
        if target.isBoss then
            local bossCap = eff.bossCap or 0
            if bossCap > 0 and hpRatio < bossCap then
                target.hp = 0
                target.alive = false
            end
        else
            if hpRatio < eff.executeThreshold then
                target.hp = 0
                target.alive = false
            end
        end
    end

    -- 破甲扩散（aftershock）
    if eff.spreadRange and eff.spreadRatio and target and target.alive then
        local armorVal = target.armorBreak or 0
        if armorVal > 0 then
            local rangeSq = eff.spreadRange * eff.spreadRange
            for _, e in ipairs(State.enemies) do
                if e.alive and e ~= target then
                    local dx = e.x - target.x
                    local dy = e.y - target.y
                    if dx * dx + dy * dy < rangeSq then
                        e.armorBreak = math.min((e.armorBreak or 0) + armorVal * eff.spreadRatio, 1.0)
                    end
                end
            end
        end
    end

    -- 无视护盾（shadow_chain）
    if eff.ignoreShield and target and target.alive then
        tower._tagIgnoreShield = true
    end

    -- 链接分伤（fate_thread）
    if eff.linkDmgShare and target and target.alive then
        target.tagLinked = true
        target.tagLinkShare = eff.linkDmgShare
    end

    -- 链接减速/魔抗（fate_entangle）
    if eff.linkedSlow and target and target.alive then
        if target.tagLinked then
            Enemy.ApplySlow(target, 2.0, eff.linkedSlow)
            if eff.linkedResShred then
                target.tagResReduce = (target.tagResReduce or 0) + eff.linkedResShred
                target.tagResReduceTimer = math.max(target.tagResReduceTimer or 0, 3.0)
            end
        end
    end

    -- ================================================================
    -- 击杀相关 on_kill 效果
    -- ================================================================

    -- 击杀缩短主动CD（soul_drain）
    if eff.cdReduce then
        if tower.skillTimers then
            for timerId, v in pairs(tower.skillTimers) do
                tower.skillTimers[timerId] = math.max(0, v - eff.cdReduce)
            end
        end
        if tower.tags then
            for _, ts2 in pairs(tower.tags) do
                if ts2.def.type == "active" and ts2.cd > 0 then
                    ts2.cd = math.max(0, ts2.cd - eff.cdReduce)
                end
            end
        end
    end

    -- 击杀后必暴（fallen_glory）
    if eff.guaranteedCrit then
        tower.tagGuaranteedCrit = true
        tower.tagGuaranteedCritDmg = eff.critDmgBonus or 0
    end

    -- 击杀CD概率缩短（lord_will）
    if eff.cdResetAmount then
        if tower.skillTimers then
            for timerId, v in pairs(tower.skillTimers) do
                tower.skillTimers[timerId] = math.max(0, v - eff.cdResetAmount)
            end
        end
    end

    -- 额外掉落（life_spring）
    if eff.extraDropChance and target and math.random() < eff.extraDropChance then
        local LootDrop      = require("Game.LootDrop")
        local DivineBlessDB = require("Game.DivineBlessData")
        local enemyTier = target.isBoss and "boss" or (target.isElite and "elite" or "normal")
        local s = State.currentStage - 1
        local dropScale = 1.0 + s * Config.KILL_DROP.stageScale + s * s * (Config.KILL_DROP.stageQuadratic or 0)
        local mfloor = math.floor

        -- 冥晶
        local crystalBase = Config.KILL_DROP.crystal[enemyTier] or 0
        if crystalBase > 0 then
            local amt = mfloor(crystalBase * dropScale)
            local multi = DivineBlessDB.GetBuffValue("crystal_multi")
            if multi > 1.0 then amt = mfloor(amt * multi) end
            if amt > 0 then LootDrop.Spawn("nether_crystal", amt, target.x, target.y) end
        end
        -- 噬魂石
        local stoneBase = Config.KILL_DROP.stone[enemyTier] or 0
        if stoneBase > 0 then
            local amt = mfloor(stoneBase * dropScale)
            local multi = DivineBlessDB.GetBuffValue("stone_multi")
            if multi > 1.0 then amt = mfloor(amt * multi) end
            if amt > 0 then LootDrop.Spawn("devour_stone", amt, target.x, target.y) end
        end
        -- 锻魂铁
        local ironBase = Config.KILL_DROP.iron[enemyTier] or 0
        if ironBase > 0 then
            local amt = mfloor(ironBase * dropScale)
            local multi = DivineBlessDB.GetBuffValue("iron_multi")
            if multi > 1.0 then amt = mfloor(amt * multi) end
            if amt > 0 then LootDrop.Spawn("forge_iron", amt, target.x, target.y) end
        end

        AddFloatingText({
            text = "额外掉落!",
            x = target.x, y = target.y - (target.typeDef and target.typeDef.size or 8) - 20,
            life = 0.8,
            color = { 100, 255, 100, 255 },
            fontSize = 12,
        })
    end
end

-- ============================================================================
-- active 类标签更新（v1.0.82）
-- ============================================================================

---@param tower table
---@param dt number
function HeroSkills.UpdateTagActive(tower, dt)
    if not tower.tags then return end
    if tower.shackled then return end

    local Enemy = GetEnemy()

    for tagId, ts in pairs(tower.tags) do
        if ts.tier <= 0 or ts.def.type ~= "active" then goto next_active end
        local eff = ts.def.effects and ts.def.effects[ts.tier]
        if not eff or not eff.interval then goto next_active end

        ts.cd = (ts.cd or 0) - dt
        if ts.cd > 0 then goto next_active end
        ts.cd = eff.interval

        -- blizzard: 全屏减速
        if eff.slowPct then
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    Enemy.ApplySlow(e, eff.duration or 3.0, eff.slowPct)
                end
            end
        end

        -- war_cry: 全体攻击 buff
        if eff.atkBuffPct then
            State.tagWarCryBuff = {
                atkMult = eff.atkBuffPct,
                timer   = eff.duration or 5.0,
            }
        end

        -- shadow_devour: 全屏伤害
        if eff.damagePct and not eff.slowPct and not eff.detonateAll and not eff.trueDmgToLinked then
            local dmg = HeroSkills.GetEffectiveAttack(tower) * eff.damagePct
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    Enemy.TakeDamage(e, dmg)
                end
            end
            if eff.slowDuration and eff.slowPct then
                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        Enemy.ApplySlow(e, eff.slowDuration, eff.slowPct)
                    end
                end
            end
        end

        -- wilds_call: 全体自然之力 + 鲜花环
        if eff.wreathAtkBonus then
            for _, t in ipairs(State.towers) do
                if t.hstate then
                    t.hstate.naturalForce = (t.hstate.naturalForce or 0) + (eff.force or 30)
                    t.hstate.wreathActive = true
                    t.hstate.wreathTimer  = eff.wreathDuration or 6.0
                    t.hstate.wreathBonus  = eff.wreathAtkBonus
                end
            end
        end

        -- crimson_eclipse: 引爆暗影印记 + 全队攻速 buff
        if eff.detonateAll then
            for _, e in ipairs(State.enemies) do
                if e.alive and e.tagDmgStacks and e.tagDmgStacks > 0 then
                    local burstDmg = HeroSkills.GetEffectiveAttack(tower) * e.tagDmgStacks * 0.50
                    Enemy.TakeDamage(e, burstDmg)
                    e.tagDmgStacks = 0
                end
            end
            if eff.teamSpdBuff then
                State.tagTeamSpdBuff = {
                    spdMult = eff.teamSpdBuff,
                    timer   = eff.buffDuration or 5.0,
                }
            end
        end

        -- hunt_decree: 标记目标受伤加成
        if eff.vulnRate and not eff.spreadOnKill then
            local best = nil
            local bestHp = 0
            for _, e in ipairs(State.enemies) do
                if e.alive and e.hp > bestHp then
                    bestHp = e.hp
                    best = e
                end
            end
            if best then
                best.ampDamage = math.max(best.ampDamage or 0, eff.vulnRate)
                best.ampDamageTimer = eff.duration or 8.0
            end
        end

        -- abyss_mark: 标记血量最高敌人（死亡转移版）
        if eff.vulnRate and eff.spreadOnKill then
            local best = nil
            local bestHp = 0
            for _, e in ipairs(State.enemies) do
                if e.alive and e.hp > bestHp then
                    bestHp = e.hp
                    best = e
                end
            end
            if best then
                best.ampDamage = math.max(best.ampDamage or 0, eff.vulnRate)
                best.ampDamageTimer = eff.duration or 12.0
                best.tagAbyssMarked = true
            end
        end

        -- final_weave: 对链接目标真伤
        if eff.trueDmgToLinked then
            local trueDmg = HeroSkills.GetEffectiveAttack(tower) * eff.trueDmgToLinked
            for _, e in ipairs(State.enemies) do
                if e.alive and e.tagLinked then
                    Enemy.TakeDamage(e, trueDmg)
                end
            end
            if eff.resetCd then
                for _, t in ipairs(State.towers) do
                    if t.skillTimers then
                        for timerId, _ in pairs(t.skillTimers) do
                            t.skillTimers[timerId] = 0
                        end
                    end
                end
            end
        end

        ::next_active::
    end
end

-- ============================================================================
-- 升级标签（供 UI / 技能书 调用）
-- ============================================================================

---@param heroId string
---@param tagId string
---@return boolean success, string|nil error
function HeroSkills.UpgradeTag(heroId, tagId)
    local tagDefs = Config.HERO_SKILL_TAGS[heroId]
    if not tagDefs then return false, "hero_no_tags" end

    local tagDef
    for _, td in ipairs(tagDefs) do
        if td.id == tagId then tagDef = td; break end
    end
    if not tagDef then return false, "tag_not_found" end

    if not HeroData.IsTagUnlocked(heroId, tagDef) then
        return false, "tag_locked"
    end

    -- 顺序解锁：前一个标签必须 tier > 0
    for i, td in ipairs(tagDefs) do
        if td.id == tagId and i > 1 then
            local prevTag = tagDefs[i - 1]
            if HeroData.GetTagTier(heroId, prevTag.id) <= 0 then
                return false, "prev_tag_required"
            end
            break
        end
    end

    -- 显式依赖
    if tagDef.requires then
        for _, reqId in ipairs(tagDef.requires) do
            if HeroData.GetTagTier(heroId, reqId) <= 0 then
                return false, "requires_" .. reqId
            end
        end
    end

    local curTier = HeroData.GetTagTier(heroId, tagDef.id)
    local maxTier = tagDef.maxTier or 1
    if curTier >= maxTier then return false, "max_tier" end

    -- 消耗技能书
    local rarity = Config.HERO_RARITY and Config.HERO_RARITY[heroId] or "N"
    local costTable = Config.SKILL_BOOK_COST and Config.SKILL_BOOK_COST[rarity]
    local costMap = costTable and costTable[curTier]
    if costMap then
        local Currency = require("Game.Currency")
        for bookId, amount in pairs(costMap) do
            if not Currency.Has(bookId, amount) then
                return false, "not_enough_skill_book"
            end
        end
        for bookId, amount in pairs(costMap) do
            Currency.Spend(bookId, amount)
        end
    end

    HeroData.SetTagTier(heroId, tagDef.id, curTier + 1)
    return true
end

end -- return function(HeroSkills)
