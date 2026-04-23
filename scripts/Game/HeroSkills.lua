-- Game/HeroSkills.lua
-- 英雄技能效果系统 — 薄调度器
-- 每个英雄的具体实现位于 Game/Heroes/{heroId}.lua
-- 被动技能随升星升级，主动技能随进阶升级，技能倍率 × 觉醒倍率 乘算

local Config   = require("Game.Config")
local State    = require("Game.State")
local HeroData = require("Game.HeroData")

local HeroSkills = {}

-- 飘字安全添加（带数量上限）
local AddFloatingText = State.AddFloatingText

-- 预定义飘字颜色（避免每次创建新 table）
local COLOR_FROZEN      = { 100, 180, 255, 255 }
local COLOR_CURSE_BURST = { 140, 180, 140, 255 }
local COLOR_DOUBLE_SOUL = { 160, 80, 200, 255 }
local COLOR_STUN        = { 255, 220, 60, 255 }

-- 延迟 require 缓存（避免循环依赖）
local _Enemy, _Combat, _CostumeData, _Debuff
local function GetEnemy()
    if not _Enemy then _Enemy = require("Game.Enemy") end
    return _Enemy
end
local function GetDebuff()
    if not _Debuff then _Debuff = require("Game.Debuff") end
    return _Debuff
end
local function GetCombat()
    if not _Combat then _Combat = require("Game.Combat") end
    return _Combat
end
local function GetCostumeData()
    if not _CostumeData then _CostumeData = require("Game.CostumeData") end
    return _CostumeData
end

-- ============================================================================
-- 英雄模块注册表
-- ============================================================================

local _modules = {
    skeleton_grunt    = require("Game.Heroes.skeleton_grunt"),
    bat_minion        = require("Game.Heroes.bat_minion"),
    hell_hound        = require("Game.Heroes.hell_hound"),
    skeleton_archer   = require("Game.Heroes.skeleton_archer"),
    demon_warrior     = require("Game.Heroes.demon_warrior"),
    ghost_assassin    = require("Game.Heroes.ghost_assassin"),
    stone_golem       = require("Game.Heroes.stone_golem"),
    necromancer       = require("Game.Heroes.necromancer"),
    inferno_flame     = require("Game.Heroes.inferno_flame"),
    armor_breaker     = require("Game.Heroes.armor_breaker"),
    frost_witch       = require("Game.Heroes.frost_witch"),
    war_drummer       = require("Game.Heroes.war_drummer"),
    shadow_mage       = require("Game.Heroes.shadow_mage"),
    abyss_hunter      = require("Game.Heroes.abyss_hunter"),
    plague_doctor     = require("Game.Heroes.plague_doctor"),
    storm_lord        = require("Game.Heroes.storm_lord"),
    glacial_sovereign = require("Game.Heroes.glacial_sovereign"),
    fallen_archangel  = require("Game.Heroes.fallen_archangel"),
    void_dragon       = require("Game.Heroes.void_dragon"),
    fate_weaver       = require("Game.Heroes.fate_weaver"),
    eternal_archfiend = require("Game.Heroes.eternal_archfiend"),
    leader            = require("Game.Heroes.leader"),
    nature_elf        = require("Game.Heroes.nature_elf"),
    crimson_night     = require("Game.Heroes.crimson_night"),
}

-- 按 hook 类型缓存有实现的模块列表（避免每帧遍历所有模块）
local _withUpdateFrame  = {}
local _withUpdateGlobal = {}
for _, mod in pairs(_modules) do
    if mod.UpdateFrame  then _withUpdateFrame[#_withUpdateFrame + 1]   = mod end
    if mod.UpdateGlobal then _withUpdateGlobal[#_withUpdateGlobal + 1] = mod end
end

--- 获取塔对应的英雄模块（可能为 nil）
---@param tower table
---@return table|nil
local function getmod(tower)
    return tower.typeDef and _modules[tower.typeDef.id]
end

-- ============================================================================
-- 技能等级计算
-- ============================================================================

---@param heroStar number  0-30
---@return number  1-7
function HeroSkills.GetPassiveSkillLevel(heroStar)
    local level = 1
    for _, threshold in ipairs(Config.PASSIVE_UPGRADE_STARS) do
        if heroStar >= threshold then level = level + 1 end
    end
    return level
end

---@param advanceLevel number  0-20
---@return number  1-5
function HeroSkills.GetActiveSkillLevel(advanceLevel)
    local level = 1
    for _, threshold in ipairs(Config.ACTIVE_UPGRADE_GATES) do
        if advanceLevel >= threshold then level = level + 1 end
    end
    return level
end

---@param passiveLevel number  1-7
---@return number
function HeroSkills.GetPassiveMultiplier(passiveLevel)
    local mult = 1.0
    for i = 1, passiveLevel - 1 do
        mult = mult * (Config.PASSIVE_UPGRADE_MULTS[i] or 1.0)
    end
    return mult
end

---@param activeLevel number  1-5
---@return number
function HeroSkills.GetActiveMultiplier(activeLevel)
    local mult = 1.0
    for i = 1, activeLevel - 1 do
        mult = mult * (Config.ACTIVE_UPGRADE_MULTS[i] or 1.0)
    end
    return mult
end

---@param activeLevel number  1-5
---@return number
function HeroSkills.GetActiveCDMultiplier(activeLevel)
    local mult = 1.0
    for i = 1, activeLevel - 1 do
        mult = mult * (Config.ACTIVE_UPGRADE_CD_MULTS[i] or 1.0)
    end
    return mult
end

-- ============================================================================
-- 工具函数
-- ============================================================================

---@param tower table
---@param skillId string
---@return table|nil
function HeroSkills.HasSkill(tower, skillId)
    if not tower.skills then return nil end
    for _, skill in ipairs(tower.skills) do
        if skill.id == skillId then return skill end
    end
    return nil
end

local function CloneSkill(skillDef)
    local copy = {}
    for k, v in pairs(skillDef) do copy[k] = v end
    return copy
end

local NUMERIC_KEYS = {
    "chance", "damagePct", "bonusDmg", "duration",
    "burnDuration", "bonusPerWave", "maxBonus", "slowPct",
    "newSlowRate", "dotMultiplier", "bossAtkPct", "chainRange",
    "curseDmgAtkPct", "killDmgBonus", "atkSpdBonus", "slowRate",
    "slowDuration", "dotAtkPct", "armorBreak", "fullStackBonus",
    "ampRate", "atkBuff", "spdBuff", "atkBuffPct", "burstMult",
    "rangeBonus", "hpPct", "critRate", "critDmg", "critRateBuff",
    "healReduction", "doubleDmgChance", "critSplashPct",
    "killAtkBonus", "globalAtkBuff", "cdResetAmount", "armorReduce",
    "spreadRatio", "bossExtraDmg",
}

local function ApplySkillMult(skill, mult)
    if mult <= 1.0 then return end
    for _, key in ipairs(NUMERIC_KEYS) do
        if skill[key] then skill[key] = skill[key] * mult end
    end
    if skill.chance then
        skill.chance = math.min(skill.chance, skill.maxChance or 0.80)
    end
    if skill.interval and mult > 1.0 then
        skill.interval = skill.interval / mult
    end
end

--- 星级缩放：0星→10%，满星→100%，线性插值
--- 与 ApplySkillMult 不同：即使 factor < 1.0 也应用，且不影响 interval
---@param skill table  克隆后的技能
---@param factor number  0.10 ~ 1.00
local function ApplyStarScale(skill, factor)
    if factor >= 1.0 then return end
    for _, key in ipairs(NUMERIC_KEYS) do
        if skill[key] then skill[key] = skill[key] * factor end
    end
    if skill.chance then
        skill.chance = math.min(skill.chance, skill.maxChance or 0.80)
    end
end

-- ============================================================================
-- 初始化塔技能
-- ============================================================================

---@param tower table
function HeroSkills.InitTowerSkills(tower)
    local heroId    = tower.typeDef.id
    local baseSkills = HeroData.GetUnlockedSkills(heroId)

    local heroInfo     = HeroData.Get(heroId)
    local heroStar     = (heroInfo and heroInfo.star)         or 0
    local advanceLevel = (heroInfo and heroInfo.advanceLevel) or 0
    local awaken       = (heroInfo and heroInfo.awakening)    or 0
    local awakenDefs   = Config.HERO_AWAKENING[heroId]

    local passiveLevel  = HeroSkills.GetPassiveSkillLevel(heroStar)
    local activeLevel   = HeroSkills.GetActiveSkillLevel(advanceLevel)
    local passiveMult   = HeroSkills.GetPassiveMultiplier(passiveLevel)
    local activeDmgMult = HeroSkills.GetActiveMultiplier(activeLevel)
    local activeCdMult  = HeroSkills.GetActiveCDMultiplier(activeLevel)

    -- 星级缩放系数：0星→10%，满星→100%
    local maxStar = Config.MAX_HERO_STAR or 30
    local starScaleFactor = 0.10 + 0.90 * math.sqrt(math.min(heroStar, maxStar) / maxStar)

    tower.skills      = {}
    tower.skillLevels = { passive = passiveLevel, active = activeLevel }

    for i, skillDef in ipairs(baseSkills) do
        local skill = CloneSkill(skillDef)
        -- 先应用星级缩放（基础值 × 星级系数）
        ApplyStarScale(skill, starScaleFactor)
        -- 再叠加技能等级倍率
        if skill.type == "passive" then
            ApplySkillMult(skill, passiveMult)
        elseif skill.type == "active" then
            ApplySkillMult(skill, activeDmgMult)
            if skill.interval then
                skill.interval = skill.interval * activeCdMult
            end
        end
        if awaken > 0 and awakenDefs then
            for a = 1, math.min(awaken, #awakenDefs) do
                local node = awakenDefs[a]
                if node then
                    if node.skillIdx == i then
                        ApplySkillMult(skill, node.mult or 1.5)
                    end
                    if node.allMult and a <= awaken and not node.skillIdx then
                        ApplySkillMult(skill, node.allMult)
                    end
                end
            end
        end
        tower.skills[#tower.skills + 1] = skill
    end

    tower.skillTimers = {}
    tower.skillStacks = {}
    for _, skill in ipairs(tower.skills) do
        if skill.type == "active" and skill.interval then
            tower.skillTimers[skill.id] = skill.interval
        end
    end

    tower.killAtkStacks       = 0
    tower.soulReapStacks      = 0
    tower.chillGlobalCounter  = 0
    tower.chillTickTimer      = 0
end

-- ============================================================================
-- 被动技能效果 — 伤害修正
-- ============================================================================

---@param tower table
---@param target table
---@param baseDamage number
---@return number
function HeroSkills.ModifyDamage(tower, target, baseDamage)
    local damage = baseDamage
    local mod = getmod(tower)

    -- 英雄专属伤害修正
    if mod and mod.ModifyDamage then
        damage = mod.ModifyDamage(tower, target, damage)
    end

    -- 共享：弱点/致命/神罚之光标记增伤
    if target.ampDamage and target.ampDamage > 0 then
        damage = damage * (1 + target.ampDamage)
    end

    -- 共享：因果律 — 全体友方概率双倍伤害
    if State.causalityActive then
        if math.random() < (State.causalityChance or 0.15) then
            damage = damage * 2
        end
    end

    return damage
end

-- ============================================================================
-- 被动技能效果 — 命中触发
-- ============================================================================

---@param tower table
---@param target table
---@param killed boolean
function HeroSkills.OnHit(tower, target, killed)
    local mod = getmod(tower)

    -- 英雄专属命中效果
    if mod and mod.OnHit then
        mod.OnHit(tower, target, killed)
    end

    -- ====================================================================
    -- 共享：符文套装效果
    -- ====================================================================
    if tower.runeSetEffects then
        local Enemy = GetEnemy()
        for _, eff in ipairs(tower.runeSetEffects) do

            -- 烈焰 set3: 攻击附带灼烧DOT
            if eff.effect == "burn_dot" and target.alive then
                local dotDmg = tower.attack * (eff.dotPct or 0.02)
                Enemy.ApplyDOT(target, dotDmg, eff.dotDur or 3.0)
            end

            -- 寒霜 set3: 概率冻结
            if eff.effect == "freeze" and target.alive then
                if math.random() < (eff.chance or 0.15) then
                    if target.isBoss then
                        if Config.BOSS_BALANCE and Config.BOSS_BALANCE.freezeImmune then
                            Enemy.ApplySlow(target, eff.dur or 1.0,
                                0.50 * (Config.BOSS_BALANCE.slowEfficiency or 0.50))
                        end
                    else
                        Enemy.ApplySlow(target, eff.dur or 1.0, 1.0)
                        if GetDebuff().Apply(target, "frozen", { duration = eff.dur or 1.0 }) then
                            AddFloatingText({
                                text     = "冰冻",
                                x        = target.x + (math.random() - 0.5) * 10,
                                y        = target.y - (target.typeDef.size or 8) - 16,
                                life     = 0.6,
                                color    = COLOR_FROZEN,
                                fontSize = 12,
                            })
                        end
                    end
                end
            end

            -- 亡灵 set3: 诅咒叠层，满层触发真实伤害
            if eff.effect == "curse_stack" and target.alive then
                target.runesCurseStacks = (target.runesCurseStacks or 0) + 1
                if target.runesCurseStacks >= (eff.stackMax or 5) then
                    local trueDmg = tower.attack * (eff.dmgPct or 0.20)
                    Enemy.TakeDamage(target, trueDmg)
                    target.runesCurseStacks = 0
                    AddFloatingText({
                        text     = "诅咒爆发",
                        x        = target.x + (math.random() - 0.5) * 10,
                        y        = target.y - (target.typeDef.size or 8) - 20,
                        life     = 0.7,
                        color    = COLOR_CURSE_BURST,
                        fontSize = 13,
                    })
                end
            end

            -- 暗影 set3: 击杀时概率双倍暗魂
            if eff.effect == "double_soul" and killed then
                if math.random() < (eff.chance or 0.15) then
                    local soulReward = Config.GetKillSoul and Config.GetKillSoul(target) or 1
                    local Currency   = require("Game.Currency")
                    Currency.GrantReward({ type = "currency", id = "dark_soul", amount = soulReward }, "HeroSkillDoubleSoul")
                    AddFloatingText({
                        text     = "暗魂×2",
                        x        = target.x,
                        y        = target.y - (target.typeDef.size or 8) - 24,
                        life     = 0.8,
                        color    = COLOR_DOUBLE_SOUL,
                        fontSize = 14,
                    })
                end
            end
        end
    end

    -- 共享：符文词条 killReset — 击杀回复攻速
    if killed and tower.runeBonus and tower.runeBonus.killReset and tower.runeBonus.killReset > 0 then
        if math.random() < tower.runeBonus.killReset then
            tower.attackTimer = 0
        end
    end
end

-- ============================================================================
-- 被动技能效果 — 减速/DOT 修正
-- ============================================================================

---@param tower table
---@param baseSlowRate number
---@param target table|nil
---@return number
function HeroSkills.ModifySlowRate(tower, baseSlowRate, target)
    local mod = getmod(tower)
    if mod and mod.ModifySlowRate then
        local r = mod.ModifySlowRate(tower, baseSlowRate, target)
        if r ~= baseSlowRate then return r end  -- 英雄专属覆盖了，直接返回
    end

    -- 共享：BOSS 减速效率衰减
    if target and target.isBoss then
        baseSlowRate = baseSlowRate * (Config.BOSS_BALANCE.slowEfficiency or 0.50)
    end

    -- 共享：符文词条 slow_amp
    if tower.runeBonus and tower.runeBonus.slow_amp and tower.runeBonus.slow_amp > 0 then
        baseSlowRate = baseSlowRate * (1 + tower.runeBonus.slow_amp)
    end

    return baseSlowRate
end

---@param tower table
---@param baseDotDmg number
---@param target table|nil
---@return number
function HeroSkills.ModifyDotDamage(tower, baseDotDmg, target)
    local mod = getmod(tower)
    if mod and mod.ModifyDotDamage then
        baseDotDmg = mod.ModifyDotDamage(tower, baseDotDmg, target)
    end

    -- 共享：符文词条 dot_amp
    if tower.runeBonus and tower.runeBonus.dot_amp and tower.runeBonus.dot_amp > 0 then
        baseDotDmg = baseDotDmg * (1 + tower.runeBonus.dot_amp)
    end

    return baseDotDmg
end

-- ============================================================================
-- 被动技能效果 — 攻速/连射/范围
-- ============================================================================

---@param tower table
---@return boolean
function HeroSkills.ShouldMultiShot(tower)
    local mod = getmod(tower)
    if mod and mod.ShouldMultiShot then
        return mod.ShouldMultiShot(tower)
    end
    return false
end

---@param tower table
---@param baseSpeed number
---@return number
function HeroSkills.ModifyAttackSpeed(tower, baseSpeed)
    local mod = getmod(tower)
    if mod and mod.ModifyAttackSpeed then
        baseSpeed = mod.ModifyAttackSpeed(tower, baseSpeed)
    end

    -- 共享：战鼓光环攻速加成
    if tower.auraSpdBuff and tower.auraSpdBuff > 0 then
        baseSpeed = baseSpeed / (1 + tower.auraSpdBuff)
    end

    -- 共享：scorch 灼烧减速
    if tower.scorchTimer and tower.scorchTimer > 0 then
        local reduce = tower.scorchReduction or 0.10
        baseSpeed = baseSpeed / (1 - reduce)
    end

    -- 共享：符文词条 cdr（技能冷却缩减）
    if tower.runeBonus and tower.runeBonus.cdr and tower.runeBonus.cdr > 0 then
        baseSpeed = baseSpeed / (1 + tower.runeBonus.cdr)
    end

    return baseSpeed
end

---@param tower table
---@param baseRange number
---@return number
function HeroSkills.ModifyRange(tower, baseRange)
    local mod = getmod(tower)
    if mod and mod.ModifyRange then
        return mod.ModifyRange(tower, baseRange)
    end
    return baseRange
end

-- ============================================================================
-- 被动技能效果 — 减速扩散
-- ============================================================================

---@param tower table
---@param target table
---@param slowDuration number
---@param slowRate number
function HeroSkills.HandleSlowSpread(tower, target, slowDuration, slowRate)
    local mod = getmod(tower)
    if mod and mod.HandleSlowSpread then
        mod.HandleSlowSpread(tower, target, slowDuration, slowRate)
    end
end

-- ============================================================================
-- 光环系统
-- ============================================================================

---@param towers table
---@param gridOffsetX number
---@param gridOffsetY number
function HeroSkills.UpdateAuras(towers, gridOffsetX, gridOffsetY)
    local Grid       = require("Game.Grid")
    local towerCount = #towers

    -- 重置所有塔的光环 buff + 缓存屏幕坐标
    for i = 1, towerCount do
        local tower = towers[i]
        tower.auraAtkBuff     = 0
        tower.auraSpdBuff     = 0
        tower.auraCritRateBuff = 0
        local sx, sy = Grid.CellToScreen(tower.col, tower.row, gridOffsetX, gridOffsetY)
        tower._sx, tower._sy = sx, sy
    end

    -- 重置全局技能状态
    State.causalityActive = false
    State.causalityChance = 0

    -- 每个塔作为光环源，调用对应模块的 UpdateAura
    for si = 1, towerCount do
        local source = towers[si]
        local mod    = getmod(source)
        if mod and mod.UpdateAura then
            mod.UpdateAura(source, towers)
        end
    end
end

-- ============================================================================
-- 主动技能
-- ============================================================================

---@param tower table
---@param dt number
function HeroSkills.UpdateActive(tower, dt)
    if not tower.skills or not tower.skillTimers then return end
    if tower.shackled then return end

    for _, skill in ipairs(tower.skills) do
        if skill.type == "active" and skill.interval then
            local timerId = skill.id
            tower.skillTimers[timerId] = (tower.skillTimers[timerId] or 0) - dt
            if tower.skillTimers[timerId] <= 0 then
                tower.skillTimers[timerId] = skill.interval
                HeroSkills.TriggerActive(tower, skill)
            end
        end
    end
end

---@param tower table
---@param skill table
function HeroSkills.TriggerActive(tower, skill)
    local mod = getmod(tower)
    if mod and mod.TriggerActive then
        mod.TriggerActive(tower, skill)
        return
    end

    -- 旧版兼容占位（未迁移技能）
    if skill.id == "arrow_rain" then
        State.skillFlash = { type = "arrow_rain", timer = 0.5, tower = tower }
    elseif skill.id == "hell_gate" then
        State.skillFlash = { type = "hell_gate", timer = 0.5, tower = tower }
    end
end

-- ============================================================================
-- 统一帧更新（替代 UpdateChillPassive + UpdateNatureAura）
-- ============================================================================

--- 每帧调用，处理所有需要帧更新的英雄专属系统
---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function HeroSkills.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    for _, mod in ipairs(_withUpdateFrame) do
        mod.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    end
end

-- ============================================================================
-- 全局帧更新（诅咒DOT 等全局 tick 效果）
-- ============================================================================

--- 替代 UpdateCurseDOT：调用各英雄模块的 UpdateGlobal
---@param dt number
function HeroSkills.UpdateCurseDOT(dt)
    for _, mod in ipairs(_withUpdateGlobal) do
        mod.UpdateGlobal(dt)
    end
end

--- 更新临时全局 buff（英勇战歌计时器 + 重置 healReduction）
---@param dt number
function HeroSkills.UpdateGlobalBuffs(dt)
    if State.heroicAnthemBuff then
        State.heroicAnthemBuff.timer = State.heroicAnthemBuff.timer - dt
        if State.heroicAnthemBuff.timer <= 0 then
            State.heroicAnthemBuff = nil
        end
    end
    State.healReduction = 0
end

-- ============================================================================
-- 眩晕（BOSS减半）
-- ============================================================================

---@param target table
---@param duration number
function HeroSkills.ApplyStun(target, duration)
    -- 静态免疫检查（immune_cc / void_aura 已注册）
    if GetDebuff().IsImmune(target, "stun") then return end
    if target.isBoss then
        duration = duration * (Config.BOSS_BALANCE.stunDurationMult or 0.50)
    end
    if not target.stunTimer or target.stunTimer <= 0 then
        AddFloatingText({
            text     = "眩晕",
            x        = target.x + (math.random() - 0.5) * 10,
            y        = target.y - (target.typeDef.size or 8) - 16,
            life     = 0.6,
            color    = COLOR_STUN,
            fontSize = 12,
        })
    end
    GetDebuff().Apply(target, "stun", { duration = duration })
end

-- ============================================================================
-- 获取塔最终攻击力/暴击率
-- ============================================================================

---@param tower table
---@return number
function HeroSkills.GetEffectiveAttack(tower)
    -- 先应用 debuff 削弱，再叠加光环/时装等增益
    local Tower = require("Game.Tower")
    local baseAtk = Tower.GetEffectiveAttack(tower)

    -- 加算桶：所有百分比加成先相加，再一次性乘算
    local pctBucket = 0
    if tower.auraAtkBuff and tower.auraAtkBuff > 0 then
        pctBucket = pctBucket + tower.auraAtkBuff
    end
    if State.heroicAnthemBuff then
        pctBucket = pctBucket + State.heroicAnthemBuff.atkMult
    end
    local CD    = GetCostumeData()
    local bonus = CD.GetGlobalAtkBonus()
    if bonus > 0 then pctBucket = pctBucket + bonus end
    if tower.wreathActive and tower.wreathBonus and tower.wreathBonus > 0 then
        pctBucket = pctBucket + tower.wreathBonus
    end

    local atk = baseAtk * (1 + pctBucket)

    -- 固定值加成（加法）
    if tower.natureFlatAtk and tower.natureFlatAtk > 0 then
        atk = atk + tower.natureFlatAtk
    end

    return atk
end

---@param tower table
---@return number
function HeroSkills.GetEffectiveSpeed(tower)
    local Tower = require("Game.Tower")
    return HeroSkills.ModifyAttackSpeed(tower, Tower.GetEffectiveSpeed(tower))
end

---@param tower table
---@return number
function HeroSkills.GetEffectiveCritRate(tower)
    local Tower = require("Game.Tower")
    local rate = Tower.GetEffectiveCritRate(tower)
    if tower.auraCritRateBuff and tower.auraCritRateBuff > 0 then
        rate = rate + tower.auraCritRateBuff
    end
    -- 英雄模块额外暴击率（绯夜绯瞳锁定等）
    if tower.bonusCritRate and tower.bonusCritRate > 0 then
        rate = rate + tower.bonusCritRate
    end
    return rate
end

-- ============================================================================
-- 命运终章（暴击溅射）
-- ============================================================================

---@param tower table
---@param target table
---@param damage number
function HeroSkills.CheckCritSplash(tower, target, damage)
    -- 命运织者 fate_finale
    for _, t in ipairs(State.towers) do
        local splash = HeroSkills.HasSkill(t, "fate_finale")
        if splash then
            local splashDmg = damage * (splash.critSplashPct or 0.50)
            local Enemy = GetEnemy()
            for _, e in ipairs(State.enemies) do
                if e.alive and e ~= target then
                    local dx = e.x - target.x
                    local dy = e.y - target.y
                    if dx * dx + dy * dy < 3600 then -- 60²
                        Enemy.TakeDamage(e, splashDmg)
                    end
                end
            end
            break
        end
    end

    -- 符文套装：雷霆 set3 — 暴击时溅射
    if tower.runeSetEffects then
        for _, eff in ipairs(tower.runeSetEffects) do
            if eff.effect == "crit_splash" then
                local splashDmg = damage * (eff.splashPct or 0.30)
                local Enemy = GetEnemy()
                for _, e in ipairs(State.enemies) do
                    if e.alive and e ~= target then
                        local dx = e.x - target.x
                        local dy = e.y - target.y
                        if dx * dx + dy * dy < 2500 then -- 50²
                            Enemy.TakeDamage(e, splashDmg)
                        end
                    end
                end
                break
            end
        end
    end
end

-- ============================================================================
-- 每波重置
-- ============================================================================

function HeroSkills.OnWaveStart()
    for _, tower in ipairs(State.towers) do
        tower.killAtkStacks = 0
    end
    for _, e in ipairs(State.enemies) do
        e.slowSpread = nil
        e.dotSpread  = nil
        e.chillStacks = nil
        e.chillTimer  = nil
        -- shadowNeedle 已迁移到 tower 上，enemy 上不再需要清理
    end
end

return HeroSkills
