-- Game/HeroSkills.lua
-- 英雄技能效果系统 — 薄调度器
-- 每个英雄的具体实现位于 Game/Heroes/{heroId}.lua
-- 被动技能随升星升级，主动技能随进阶升级，技能倍率 × 觉醒倍率 乘算

local Config   = require("Game.Config")
local State    = require("Game.State")
local HeroData = require("Game.HeroData")

local HeroSkills = {}

-- ============================================================================
-- 英雄模块接口契约（EmmyLua 类型定义）
-- 每个 Heroes/{id}.lua 模块可实现以下任意 hook 函数。
-- HeroSkills 调度器按需调用，未实现的 hook 将被跳过。
-- ============================================================================

---@class HeroModule
---@field ModifyDamage?      fun(tower: table, target: table, damage: number): number        伤害修正（被动）
---@field ModifySlowRate?    fun(tower: table, rate: number, target: table?): number         减速修正（被动）
---@field ModifyDotDamage?   fun(tower: table, dmg: number, target: table?): number          DOT 伤害修正（被动）
---@field ModifyAttackSpeed? fun(tower: table, speed: number): number                        攻速修正（被动）
---@field ModifyRange?       fun(tower: table, range: number): number                        射程修正（被动）
---@field ShouldMultiShot?   fun(tower: table): boolean                                      是否连射（被动）
---@field OnHit?             fun(tower: table, target: table, killed: boolean)                命中触发（被动）
---@field HandleSlowSpread?  fun(tower: table, target: table, dur: number, rate: number)      减速扩散（被动）
---@field TriggerActive?     fun(tower: table, skill: table)                                  主动技能释放
---@field UpdateAura?        fun(source: table, towers: table)                                光环更新（每帧）
---@field UpdateFrame?       fun(towers: table, dt: number, gx: number, gy: number)           帧更新（需要每帧 tick 的英雄专属系统）
---@field UpdateGlobal?      fun(dt: number)                                                  全局帧更新（诅咒 DOT 等全局 tick）

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

---@type table<string, HeroModule>
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
    ember_wraith      = require("Game.Heroes.ember_wraith"),
    dream_weave       = require("Game.Heroes.dream_weave"),
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
---@return HeroModule|nil
local function getmod(tower)
    return tower.typeDef and _modules[tower.typeDef.id]
end

-- ============================================================================
-- 星级缩放系数
-- ============================================================================

--- 根据英雄星级计算缩放系数：0星→10%，满星→100%
---@param heroStar number  0-30
---@return number  0.10 ~ 1.00
function HeroSkills.GetStarScaleFactor(heroStar)
    local maxStar = Config.MAX_HERO_STAR or 30
    return 0.10 + 0.90 * math.sqrt(math.min(heroStar, maxStar) / maxStar)
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

--- 星级缩放：0星→10%，满星→100%
--- 配置值（Config_Meta.lua）= 30星满值，低星按此系数缩放
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

    -- 星级缩放系数：0星→10%，满星→100%
    -- 配置值 = 30星满值，通过 starScaleFactor 缩放到当前星级
    local maxStar = Config.MAX_HERO_STAR or 30
    local starScaleFactor = 0.10 + 0.90 * math.sqrt(math.min(heroStar, maxStar) / maxStar)

    tower.skills      = {}

    for i, skillDef in ipairs(baseSkills) do
        local skill = CloneSkill(skillDef)
        -- 星级缩放（配置满值 × 星级系数）
        if not skill.starScale then
            ApplyStarScale(skill, starScaleFactor)
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

    -- 被动技能属性（如暴击率/暴击伤害）应用到塔面板
    for _, skill in ipairs(tower.skills) do
        if skill.type == "passive" then
            if skill.critRate then
                tower.critRate = (tower.critRate or 0) + skill.critRate
            end
            if skill.critDmg then
                tower.critDmg = (tower.critDmg or 0) + skill.critDmg
            end
        end
    end

    -- 英雄专属状态子命名空间（避免字段污染 tower 顶层）
    tower.hstate = {
        -- Shadow Mage: 灵魂收割
        soulReapStacks      = 0,
        -- Eternal Archfiend: 魔焰之力 + 永恒侵蚀 + 深渊印记
        demonFlameStacks    = 0,
        demonFlameTimer     = nil,
        erodeStacks         = 0,
        erodeTimer          = nil,
        bonusDmgBonus       = 0,
        abyssMarkTarget     = nil,
        abyssMarkTimer      = 0,
        -- Glacial Sovereign: 凌冽寒意
        chillGlobalCounter  = 0,
        chillTickTimer      = 0,
        -- Crimson Night: 暗影之针 + 绯瞳锁定
        shadowNeedleStacks  = 0,
        shadowNeedleTimer   = nil,
        bloodEyeStacks      = 0,
        bloodEyeDecayTimer  = nil,
        bonusCritRate       = 0,
        bonusCritDmg        = 0,
        -- Ember Wraith: 灼烧系统 + 共振
        resonanceBurnCount  = 0,
        resonanceAtkBonus   = 0,
        resonanceDotAmp     = 0,
        -- Dream Weave: 幻梦印记（per-target）+ 梦境共鸣光环
        dreamSpdBuff        = nil,   -- lucid_pulse 叠印记期间攻速加成
        dreamAuraSpdBuff    = nil,   -- 被其他梦璃光环覆盖的攻速加成
        dreamAuraCritBuff   = nil,   -- 被光环覆盖的暴击率加成
        dreamAuraAtkBuff    = nil,   -- 被光环覆盖的攻击力加成
        dreamAuraCritDmgBuff = nil,  -- 被光环覆盖的暴击伤害加成
        -- Nature Elf: 自然之力 + 鲜花环 + 翠意庇护（由 nature_elf 写入其他塔）
        naturalForce        = 0,
        naturalForceTimer   = 0,
        natureFlatAtk       = 0,
        wreathActive        = false,
        wreathTimer         = 0,
        wreathBonus         = 0,
        verdantActive       = false,
        verdantTimer        = 0,
        verdantCooldownTimer = 0,
        natPulseTimer       = 0,
        natActiveCd         = 0,
    }

    -- 技能标签初始化（从 Config.HERO_SKILL_TAGS 读取，结合持久化层级）
    HeroSkills.InitTagState(tower)
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

    -- 共享：BOSS 额外伤害（标签 bossExtraDmg 写入 tower.bossExtraDmg）
    if target.isBoss and tower.bossExtraDmg and tower.bossExtraDmg > 0 then
        damage = damage * (1 + tower.bossExtraDmg)
    end

    -- 共享：因果律 — 全体友方概率双倍伤害
    if State.causalityActive then
        if math.random() < (State.causalityChance or 0.15) then
            damage = damage * 2
        end
    end

    -- ================================================================
    -- 标签系统：target 上的伤害加成（v1.0.82）
    -- ================================================================

    -- 标签受伤加成（pierce_mark: tagBonusDmg）
    if target.tagBonusDmg and target.tagBonusDmg > 0 then
        damage = damage * (1 + target.tagBonusDmg)
    end

    -- 叠层受伤加成（shadow_mark/charge: tagDmgStacks * tagDmgPerStack）
    if target.tagDmgStacks and target.tagDmgStacks > 0 and target.tagDmgPerStack then
        damage = damage * (1 + target.tagDmgStacks * target.tagDmgPerStack)
    end

    -- 冰封受伤加成（frozen tag: tagFrozenBonusDmg）
    if target.tagFrozenBonusDmg and target.tagFrozenTimer and target.tagFrozenTimer > 0 then
        damage = damage * (1 + target.tagFrozenBonusDmg)
    end

    -- 魔抗降低：在 damage 计算中作为增伤（简化处理，tagResReduce 视为百分比增伤）
    if target.tagResReduce and target.tagResReduce > 0 and target.tagResReduceTimer and target.tagResReduceTimer > 0 then
        -- resReduce 单位是点数，转换为增伤比例（每10点魔抗约10%增伤）
        local resAmp = target.tagResReduce * 0.01
        damage = damage * (1 + resAmp)
    end

    -- 物防降低（tagDefReduce）
    if target.tagDefReduce and target.tagDefReduce > 0 and target.tagDefReduceTimer and target.tagDefReduceTimer > 0 then
        damage = damage * (1 + target.tagDefReduce)
    end

    -- 物理易伤（physVuln）
    if target.physVuln and target.physVuln > 0 and target.physVulnTimer and target.physVulnTimer > 0 then
        damage = damage * (1 + target.physVuln)
    end

    -- 法术易伤（magicVuln）
    if target.magicVuln and target.magicVuln > 0 and target.magicVulnTimer and target.magicVulnTimer > 0 then
        damage = damage * (1 + target.magicVuln)
    end

    -- 护甲穿透（armorIgnore — 被动标签，tower 上的属性）
    if tower.armorIgnore and tower.armorIgnore > 0 then
        -- armorIgnore 视为百分比增伤（无视敌方护甲比例）
        damage = damage * (1 + tower.armorIgnore)
    end

    -- ================================================================
    -- 标签系统：tower 上的伤害加成
    -- ================================================================

    -- 连续攻击叠伤（focus_fire）
    if tower.tagFocusFireBonus and tower.tagFocusFireBonus > 0 then
        damage = damage * (1 + tower.tagFocusFireBonus)
    end

    -- ================================================================
    -- 标签系统：conditional 标签处理
    -- ================================================================

    -- 粉碎（shatter: 破甲满层时DEF降低 + 受伤加成）
    if tower.tags then
        local shatterEff, shatterTs = HeroSkills.GetTagEffect(tower, "shatter")
        if shatterEff and shatterEff.defReducePct and target.alive then
            -- 检查 sunder 破甲是否满层
            local sunderEff = HeroSkills.GetTagEffect(tower, "sunder")
            local armorStacks = target.tagSunderStacks or 0
            local maxStacks = sunderEff and sunderEff.maxStacks or 3
            if armorStacks >= maxStacks then
                damage = damage * (1 + shatterEff.defReducePct)
                if shatterEff.bonusDmg then
                    damage = damage * (1 + shatterEff.bonusDmg)
                end
            end
        end

        -- 冰晶棺（ice_coffin: 满5层寒意受伤加成）
        local iceCoffinEff = HeroSkills.GetTagEffect(tower, "ice_coffin")
        if iceCoffinEff and iceCoffinEff.atMaxChill and target.alive then
            local chillStacks = target.chillStacks or 0
            if chillStacks >= 5 then
                damage = damage * (1 + (iceCoffinEff.dmgAmp or 0.30))
            end
        end

        -- 弱点射击（weakness_shot: 标记满时必暴）—— 由 GetEffectiveCritRate 处理

        -- 暗影爆发（shadow_burst: 印记满层引爆真伤）
        local sbEff = HeroSkills.GetTagEffect(tower, "shadow_burst")
        if sbEff and sbEff.atMaxStacks and target.alive then
            local smEff = HeroSkills.GetTagEffect(tower, "shadow_mark")
            local stacks = target.tagDmgStacks or 0
            local maxS = smEff and smEff.maxStacks or 3
            if stacks >= maxS then
                local trueDmg = tower.attack * (sbEff.trueDmgPct or 1.5)
                GetEnemy().TakeDamage(target, trueDmg)
                target.tagDmgStacks = 0
                -- 虚空撕裂后续效果（void_tear）
                local vtEff = HeroSkills.GetTagEffect(tower, "void_tear")
                if vtEff and vtEff.postBurstResShred then
                    local rangeSq = 50 * 50
                    for _, e in ipairs(State.enemies) do
                        if e.alive then
                            local dx = e.x - target.x
                            local dy = e.y - target.y
                            if dx * dx + dy * dy < rangeSq then
                                e.tagResReduce = (e.tagResReduce or 0) + vtEff.postBurstResShred
                                e.tagResReduceTimer = vtEff.duration or 4.0
                            end
                        end
                    end
                end
            end
        end

        -- 雷暴（lightning_storm: 满层引爆范围伤害）
        local lsEff = HeroSkills.GetTagEffect(tower, "lightning_storm")
        if lsEff and lsEff.atMaxStacks and target.alive then
            local chgEff = HeroSkills.GetTagEffect(tower, "charge")
            local stacks = target.tagDmgStacks or 0
            local maxS = chgEff and chgEff.maxStacks or 3
            if stacks >= maxS then
                local burstDmg = tower.attack * (lsEff.burstDmgPct or 2.0)
                local aoeRange = lsEff.aoeRange or 50
                local rangeSq = aoeRange * aoeRange
                local Enemy = GetEnemy()
                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        local dx = e.x - target.x
                        local dy = e.y - target.y
                        if dx * dx + dy * dy < rangeSq then
                            Enemy.TakeDamage(e, burstDmg)
                        end
                    end
                end
                target.tagDmgStacks = 0
                -- 超载（overload）
                local olEff = HeroSkills.GetTagEffect(tower, "overload")
                if olEff and olEff.postBurstSlowImmuneLift then
                    for _, e in ipairs(State.enemies) do
                        if e.alive then
                            local dx = e.x - target.x
                            local dy = e.y - target.y
                            if dx * dx + dy * dy < rangeSq then
                                e.slowImmuneLift = olEff.duration or 3.0
                                if olEff.resShred then
                                    e.tagResReduce = (e.tagResReduce or 0) + olEff.resShred
                                    e.tagResReduceTimer = olEff.duration or 3.0
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return damage
end

-- ============================================================================
-- 被动技能效果 — 命中触发
-- ============================================================================

--- 暴击命中回调（由 Combat.lua 在暴击时调用）
---@param tower table
---@param target table
---@param damage number 暴击造成的最终伤害
function HeroSkills.OnCritHit(tower, target, damage)
    local mod = getmod(tower)
    if mod and mod.OnCritHit then
        mod.OnCritHit(tower, target, damage)
    end

    -- 技能标签：on_crit 触发
    HeroSkills.ApplyTags(tower, target, "on_crit", { damage = damage })
end

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

    -- 技能标签：on_hit 触发
    HeroSkills.ApplyTags(tower, target, "on_hit", { damage = tower.attack, killed = killed })

    -- 技能标签：on_kill 触发
    if killed then
        HeroSkills.ApplyTags(tower, target, "on_kill", { damage = tower.attack })
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

    -- ================================================================
    -- 标签系统：攻速加成（v1.0.82）
    -- ================================================================

    -- killAtkBurst: 击杀后攻速爆发（on_kill 标签触发）
    local hs = tower.hstate
    if hs and hs.killAtkBurst and hs.killAtkBurstTimer and hs.killAtkBurstTimer > 0 then
        baseSpeed = baseSpeed / (1 + hs.killAtkBurst)
    end

    -- teamSpdBuff: 全队攻速 buff（crimson_eclipse active 标签）
    if State.tagTeamSpdBuff and State.tagTeamSpdBuff.timer > 0 then
        baseSpeed = baseSpeed / (1 + State.tagTeamSpdBuff.spdMult)
    end

    -- bonusPerWave: 每波叠加攻速（passive 动态标签）
    if hs and hs.bonusPerWaveSpd and hs.bonusPerWaveSpd > 0 then
        baseSpeed = baseSpeed / (1 + hs.bonusPerWaveSpd)
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
        tower.auraAtkBuff      = 0
        tower.auraSpdBuff      = 0
        tower.auraCritRateBuff = 0
        tower.auraCritDmgBuff  = 0
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

    -- ================================================================
    -- 标签系统：aura 类标签处理（v1.0.82）
    -- ================================================================
    for si = 1, towerCount do
        local source = towers[si]
        if not source.tags then goto continue_aura end

        for tagId, ts in pairs(source.tags) do
            if ts.tier <= 0 or ts.def.type ~= "aura" then goto next_tag end
            local eff = ts.def.effects and ts.def.effects[ts.tier]
            if not eff then goto next_tag end

            local auraRange = eff.auraRange or 9999  -- 无 auraRange 视为全局

            -- 友方 buff 类光环（atkBuff / spdBuff / critRateBuff / critDmgBuff）
            if eff.atkBuff or eff.spdBuff or eff.critRateBuff or eff.critDmgBuff then
                local rangeSq = auraRange * auraRange
                for ti = 1, towerCount do
                    local t = towers[ti]
                    if t ~= source then
                        local dx = t._sx - source._sx
                        local dy = t._sy - source._sy
                        if dx * dx + dy * dy < rangeSq then
                            if eff.atkBuff then
                                t.auraAtkBuff = t.auraAtkBuff + eff.atkBuff
                            end
                            if eff.spdBuff then
                                t.auraSpdBuff = t.auraSpdBuff + eff.spdBuff
                            end
                            if eff.critRateBuff then
                                t.auraCritRateBuff = t.auraCritRateBuff + eff.critRateBuff
                            end
                            if eff.critDmgBuff then
                                t.auraCritDmgBuff = t.auraCritDmgBuff + eff.critDmgBuff
                            end
                        end
                    end
                end
                -- nature_aura T3: atkRatio 固定攻击加成（翎嫣ATK × ratio）
                if eff.atkRatio then
                    local flatAtk = HeroSkills.GetEffectiveAttack(source) * eff.atkRatio
                    local rangeSq2 = auraRange * auraRange
                    for ti = 1, towerCount do
                        local t = towers[ti]
                        if t ~= source then
                            local dx = t._sx - source._sx
                            local dy = t._sy - source._sy
                            if dx * dx + dy * dy < rangeSq2 then
                                t.hstate = t.hstate or {}
                                t.hstate.natureFlatAtk = (t.hstate.natureFlatAtk or 0) + flatAtk
                            end
                        end
                    end
                end
            end

            -- 全局攻击 buff（shadow_dominion: globalAtkBuff）
            if eff.globalAtkBuff then
                for ti = 1, towerCount do
                    local t = towers[ti]
                    if t ~= source then
                        t.auraAtkBuff = t.auraAtkBuff + eff.globalAtkBuff
                    end
                end
            end

            -- 全局暴击 buff（absolute_rule: globalCritBuff）
            if eff.globalCritBuff then
                for ti = 1, towerCount do
                    local t = towers[ti]
                    t.auraCritRateBuff = t.auraCritRateBuff + eff.globalCritBuff
                end
            end

            -- 因果律（causality: doubleDmgChance — 全局概率双倍伤害）
            if eff.doubleDmgChance then
                State.causalityActive = true
                State.causalityChance = math.max(State.causalityChance, eff.doubleDmgChance)
            end

            -- 敌方 debuff 光环（death_whisper: resReduce / wither: defReduce）
            if eff.resReduce or eff.defReduce then
                local rangeSq = auraRange * auraRange
                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        local dx = e.x - source._sx
                        local dy = e.y - source._sy
                        if dx * dx + dy * dy < rangeSq then
                            if eff.resReduce then
                                e.tagResReduce = math.max(e.tagResReduce or 0, eff.resReduce)
                                e.tagResReduceTimer = 1.0  -- 光环持续刷新，1秒足够
                            end
                            if eff.defReduce then
                                e.tagDefReduce = math.min((e.tagDefReduce or 0) + eff.defReduce, 0.60)
                                e.tagDefReduceTimer = 1.0
                            end
                        end
                    end
                end
            end

            -- 寒意光环（arctic_chill: chillPerSec — 在 UpdateFrame 中按 dt 累计，这里标记源）
            if eff.chillPerSec then
                source._tagArcticChill = eff
            end

            -- 全局减速光环（winter_domain: globalSlowAura）
            if eff.globalSlowAura then
                local Enemy = GetEnemy()
                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        Enemy.ApplySlow(e, 1.0, eff.globalSlowAura)
                    end
                end
            end

            -- 毒雾领域（miasma_zone: auraDotPct — 光环 DOT）
            if eff.auraDotPct then
                source._tagMiasmaZone = eff
            end

            ::next_tag::
        end
        ::continue_aura::
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
-- 标签系统：active 类标签更新（v1.0.82）
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

        -- ---- blizzard: 全屏减速 ----
        if eff.slowPct then
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    Enemy.ApplySlow(e, eff.duration or 3.0, eff.slowPct)
                end
            end
        end

        -- ---- war_cry: 全体攻击 buff ----
        if eff.atkBuffPct then
            State.tagWarCryBuff = {
                atkMult = eff.atkBuffPct,
                timer   = eff.duration or 5.0,
            }
        end

        -- ---- shadow_devour: 全屏伤害 ----
        if eff.damagePct and not eff.slowPct and not eff.detonateAll and not eff.trueDmgToLinked then
            local dmg = HeroSkills.GetEffectiveAttack(tower) * eff.damagePct
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    Enemy.TakeDamage(e, dmg)
                end
            end
            -- 如果同时有减速（dragon_wrath 原版 active）
            if eff.slowDuration and eff.slowPct then
                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        Enemy.ApplySlow(e, eff.slowDuration, eff.slowPct)
                    end
                end
            end
        end

        -- ---- wilds_call: 全体自然之力 + 鲜花环 ----
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

        -- ---- crimson_eclipse: 引爆暗影印记 + 全队攻速 buff ----
        if eff.detonateAll then
            -- 引爆所有标记了 tagDmgStacks 的敌人
            for _, e in ipairs(State.enemies) do
                if e.alive and e.tagDmgStacks and e.tagDmgStacks > 0 then
                    local burstDmg = HeroSkills.GetEffectiveAttack(tower) * e.tagDmgStacks * 0.50
                    Enemy.TakeDamage(e, burstDmg)
                    e.tagDmgStacks = 0
                end
            end
            -- 全队攻速 buff
            if eff.teamSpdBuff then
                State.tagTeamSpdBuff = {
                    spdMult = eff.teamSpdBuff,
                    timer   = eff.buffDuration or 5.0,
                }
            end
        end

        -- ---- hunt_decree: 标记目标受伤加成 ----
        if eff.vulnRate and not eff.spreadOnKill then
            -- 找血量最高的敌人
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

        -- ---- abyss_mark: 标记血量最高敌人（死亡转移版） ----
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

        -- ---- final_weave: 对链接目标真伤 ----
        if eff.trueDmgToLinked then
            local trueDmg = HeroSkills.GetEffectiveAttack(tower) * eff.trueDmgToLinked
            for _, e in ipairs(State.enemies) do
                if e.alive and e.tagLinked then
                    Enemy.TakeDamage(e, trueDmg)
                end
            end
            -- T2: 重置全体友方 CD
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

    -- ================================================================
    -- 标签系统：帧更新（v1.0.82）
    -- ================================================================
    local Enemy = GetEnemy()

    for _, tower in ipairs(towers) do
        -- 更新标签 active CD 倒计时
        HeroSkills.UpdateTagActive(tower, dt)

        -- infernal_stack 叠层衰减
        if tower.tags then
            for _, ts in pairs(tower.tags) do
                if ts.timer and ts.timer > 0 then
                    ts.timer = ts.timer - dt
                    if ts.timer <= 0 then
                        ts.stacks = 0
                        ts.timer  = 0
                        -- 清除关联的 tower 运行时字段
                        tower.tagInfernalCritRate = nil
                        tower.tagInfernalCritDmg  = nil
                    end
                end
            end
        end

        -- 击杀攻速爆发衰减
        local hs = tower.hstate
        if hs and hs.killAtkBurstTimer and hs.killAtkBurstTimer > 0 then
            hs.killAtkBurstTimer = hs.killAtkBurstTimer - dt
            if hs.killAtkBurstTimer <= 0 then
                hs.killAtkBurst = nil
                hs.killAtkBurstTimer = nil
            end
        end

        -- 必暴衰减（使用一次后清除）
        if tower.tagGuaranteedCrit then
            -- 实际消耗由 Combat 在暴击判定时读取并清除
        end

        -- arctic_chill: 寒意光环每帧施加寒意
        if tower._tagArcticChill then
            local ac = tower._tagArcticChill
            local rangeSq = (ac.auraRange or 80) * (ac.auraRange or 80)
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    local dx = e.x - (tower._sx or 0)
                    local dy = e.y - (tower._sy or 0)
                    if dx * dx + dy * dy < rangeSq then
                        e._chillAccum = (e._chillAccum or 0) + ac.chillPerSec * dt
                        if e._chillAccum >= 1.0 then
                            e._chillAccum = e._chillAccum - 1.0
                            e.chillStacks = math.min((e.chillStacks or 0) + 1, ac.maxStacks or 5)
                            e.chillTimer  = ac.duration or 5.0
                            local slowRate = e.chillStacks * (ac.slowPerStack or 0.10)
                            Enemy.ApplySlow(e, ac.duration or 5.0, slowRate)
                        end
                    end
                end
            end
        end

        -- miasma_zone: 毒雾光环每帧 DOT
        if tower._tagMiasmaZone then
            local mz = tower._tagMiasmaZone
            local rangeSq = (mz.auraRange or 80) * (mz.auraRange or 80)
            local dotDmg = HeroSkills.GetEffectiveAttack(tower) * mz.auraDotPct * dt
            for _, e in ipairs(State.enemies) do
                if e.alive then
                    local dx = e.x - (tower._sx or 0)
                    local dy = e.y - (tower._sy or 0)
                    if dx * dx + dy * dy < rangeSq then
                        Enemy.TakeDamage(e, dotDmg)
                    end
                end
            end
        end

        -- ember_resonance: 每帧统计灼烧中敌人数量，动态调整攻击/DOT
        if tower.tags and tower.tags["ember_resonance"] then
            local erTs = tower.tags["ember_resonance"]
            if erTs.tier > 0 then
                local eff = erTs.def.effects and erTs.def.effects[erTs.tier]
                if eff then
                    local burnCount = 0
                    for _, e in ipairs(State.enemies) do
                        if e.alive and e.igniteStacks and e.igniteStacks > 0 then
                            burnCount = burnCount + 1
                        end
                    end
                    burnCount = math.min(burnCount, eff.maxBurns or 12)
                    hs = tower.hstate
                    if hs then
                        hs.resonanceAtkBonus = burnCount * (eff.atkPerBurn or 0.04)
                        hs.resonanceDotAmp   = burnCount * (eff.dotAmpPerBurn or 0.06)
                    end
                end
            end
        end

        -- blood_pact: 每帧统计所有敌人上的暗影印记层数
        if tower.tags and tower.tags["blood_pact"] then
            local bpTs = tower.tags["blood_pact"]
            if bpTs.tier > 0 then
                local eff = bpTs.def.effects and bpTs.def.effects[bpTs.tier]
                if eff and eff.atkPerMark then
                    local totalMarks = 0
                    for _, e in ipairs(State.enemies) do
                        if e.alive and e.tagDmgStacks and e.tagDmgStacks > 0 then
                            totalMarks = totalMarks + e.tagDmgStacks
                        end
                    end
                    hs = tower.hstate
                    if hs then
                        hs.resonanceAtkBonus = (hs.resonanceAtkBonus or 0) + totalMarks * eff.atkPerMark
                    end
                end
            end
        end
    end

    -- enemy 上标签 timer 衰减
    for _, e in ipairs(State.enemies) do
        if not e.alive then goto next_enemy end

        if e.physVulnTimer and e.physVulnTimer > 0 then
            e.physVulnTimer = e.physVulnTimer - dt
            if e.physVulnTimer <= 0 then e.physVuln = nil; e.physVulnTimer = nil end
        end
        if e.magicVulnTimer and e.magicVulnTimer > 0 then
            e.magicVulnTimer = e.magicVulnTimer - dt
            if e.magicVulnTimer <= 0 then e.magicVuln = nil; e.magicVulnTimer = nil end
        end
        if e.tagResReduceTimer and e.tagResReduceTimer > 0 then
            e.tagResReduceTimer = e.tagResReduceTimer - dt
            if e.tagResReduceTimer <= 0 then e.tagResReduce = nil; e.tagResReduceTimer = nil end
        end
        if e.tagDefReduceTimer and e.tagDefReduceTimer > 0 then
            e.tagDefReduceTimer = e.tagDefReduceTimer - dt
            if e.tagDefReduceTimer <= 0 then e.tagDefReduce = nil; e.tagDefReduceTimer = nil end
        end
        if e.tagBonusDmgTimer and e.tagBonusDmgTimer > 0 then
            e.tagBonusDmgTimer = e.tagBonusDmgTimer - dt
            if e.tagBonusDmgTimer <= 0 then e.tagBonusDmg = nil; e.tagBonusDmgTimer = nil end
        end
        if e.tagFrozenTimer and e.tagFrozenTimer > 0 then
            e.tagFrozenTimer = e.tagFrozenTimer - dt
            if e.tagFrozenTimer <= 0 then e.tagFrozenBonusDmg = nil; e.tagFrozenTimer = nil end
        end
        if e.tagDmgStackTimer and e.tagDmgStackTimer > 0 then
            e.tagDmgStackTimer = e.tagDmgStackTimer - dt
            if e.tagDmgStackTimer <= 0 then e.tagDmgStacks = nil; e.tagDmgPerStack = nil; e.tagDmgStackTimer = nil end
        end
        if e.ampDamageTimer and e.ampDamageTimer > 0 then
            e.ampDamageTimer = e.ampDamageTimer - dt
            if e.ampDamageTimer <= 0 then
                e.ampDamage = nil; e.ampDamageTimer = nil
                e.tagAbyssMarked = nil
            end
        end
        if e.slowImmuneLift and e.slowImmuneLift > 0 then
            e.slowImmuneLift = e.slowImmuneLift - dt
            if e.slowImmuneLift <= 0 then e.slowImmuneLift = nil end
        end

        -- abyss_mark 死亡转移
        if e.tagAbyssMarked and not e.alive then
            local best = nil
            local bestHp = 0
            for _, e2 in ipairs(State.enemies) do
                if e2.alive and e2.hp > bestHp then
                    bestHp = e2.hp
                    best = e2
                end
            end
            if best then
                best.ampDamage = e.ampDamage or 0.30
                best.ampDamageTimer = 10.0
                best.tagAbyssMarked = true
            end
            e.tagAbyssMarked = nil
        end

        ::next_enemy::
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

    -- ================================================================
    -- 标签系统：全局 buff 计时器衰减（v1.0.82）
    -- ================================================================

    -- war_cry: 全队攻击 buff
    if State.tagWarCryBuff then
        State.tagWarCryBuff.timer = State.tagWarCryBuff.timer - dt
        if State.tagWarCryBuff.timer <= 0 then
            State.tagWarCryBuff = nil
        end
    end

    -- crimson_eclipse: 全队攻速 buff
    if State.tagTeamSpdBuff then
        State.tagTeamSpdBuff.timer = State.tagTeamSpdBuff.timer - dt
        if State.tagTeamSpdBuff.timer <= 0 then
            State.tagTeamSpdBuff = nil
        end
    end

    -- causality: 每帧由 UpdateAuras 重新写入，这里不需要衰减
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
    -- 称号攻击加成
    local okTD, TD = pcall(require, "Game.TitleData")
    if okTD then
        local titleAtk = TD.GetGlobalAtkBonus()
        if titleAtk > 0 then pctBucket = pctBucket + titleAtk end
    end
    local hs = tower.hstate
    if hs and hs.wreathActive and hs.wreathBonus and hs.wreathBonus > 0 then
        pctBucket = pctBucket + hs.wreathBonus
    end
    if hs and hs.resonanceAtkBonus and hs.resonanceAtkBonus > 0 then
        pctBucket = pctBucket + hs.resonanceAtkBonus
    end

    -- ================================================================
    -- 标签系统：攻击力加成（v1.0.82）
    -- ================================================================

    -- war_cry: 全队攻击 buff（active 标签触发）
    if State.tagWarCryBuff and State.tagWarCryBuff.timer > 0 then
        pctBucket = pctBucket + State.tagWarCryBuff.atkMult
    end

    -- 击杀叠伤（on_kill 标签：killDmgBonus）
    if hs and hs.killDmgStacks and hs.killDmgStacks > 0 and hs.killDmgBonus then
        pctBucket = pctBucket + hs.killDmgStacks * hs.killDmgBonus
    end

    local atk = baseAtk * (1 + pctBucket)

    -- 固定值加成（加法）
    if hs and hs.natureFlatAtk and hs.natureFlatAtk > 0 then
        atk = atk + hs.natureFlatAtk
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
    local hs2 = tower.hstate
    if hs2 and hs2.bonusCritRate and hs2.bonusCritRate > 0 then
        rate = rate + hs2.bonusCritRate
    end

    -- ================================================================
    -- 标签系统：暴击率加成（v1.0.82）
    -- ================================================================

    -- blood_eye: 连续命中叠加暴击率
    if tower.tagCritRateBonus and tower.tagCritRateBonus > 0 then
        rate = rate + tower.tagCritRateBonus
    end

    -- infernal_stack: 灼烧叠层暴击加成
    if tower.tagInfernalCritRate and tower.tagInfernalCritRate > 0 then
        rate = rate + tower.tagInfernalCritRate
    end

    -- fallen_glory: 击杀后必暴（暂时将暴击率设为100%）
    if tower.tagGuaranteedCrit then
        rate = 1.0
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
-- 技能标签系统
-- ============================================================================

local AffixTagResolver = require("Game.AffixTagResolver")

--- 初始化塔的技能标签状态
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

                -- ---- 标签被动：BOSS 额外伤害 ----
                if eff.bossExtraDmg then
                    tower.bossExtraDmg = math.max(tower.bossExtraDmg or 0, eff.bossExtraDmg)
                end

                -- ---- 标签被动：护甲穿透 ----
                if eff.armorIgnore then
                    tower.armorIgnore = (tower.armorIgnore or 0) + eff.armorIgnore
                end

                -- ---- 标签被动：每波攻速叠加 ----
                if eff.bonusPerWave then
                    local hs = tower.hstate
                    if hs then
                        hs.bonusPerWaveRate = eff.bonusPerWave
                        hs.bonusPerWaveMax  = eff.maxBonus or 0.50
                        hs.bonusPerWaveSpd  = 0  -- 每波开始时按波数计算
                    end
                end
            end
        end
    end
end

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
---@param target table|nil  目标敌人（on_kill 时可能已死亡）
---@param triggerType string
---@param extra table|nil   附加参数 { damage, killed, ... }
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

--- 应用单个标签效果
--- 通用效果在此处理，特殊效果委托给英雄模块
---@param tower table
---@param target table|nil
---@param tagState table  tower.tags[tagId]
---@param eff table       当前 tier 的效果数值
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
    -- 英雄模块可在自己的 OnHit/OnCritHit 中做更精细的处理，
    -- 这里只处理数据驱动的通用效果
    -- ================================================================

    -- 减速效果
    if eff.slowRate and target and target.alive then
        local slowRate = eff.slowRate + (tagBonus.tagSlowRate_add or 0)
        local slowDur  = (eff.slowDuration or eff.duration or 2.0) + (tagBonus.tagSlowDur_add or 0)
        Enemy.ApplySlow(target, slowDur, slowRate)
    end

    -- DOT 效果
    if eff.dotMultiplier and target and target.alive then
        -- dotMultiplier 作为 tower.dotMultiplier 的加成
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

    -- 法术易伤（soul_leech: magicVuln）
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

    -- 击杀爆炸（phantom_chain / holy_chain: deathExplosionPct + explosionRange）
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
        -- 通过 tagState 记录已攻击过的目标
        tagState._hitTargets = tagState._hitTargets or {}
        if not tagState._hitTargets[target] then
            tagState._hitTargets[target] = true
            -- 追加额外伤害 = baseDamage * (mult - 1)
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

    -- 概率AOE伤害（conflagration: chance + aoeDmgPct + aoeRange）
    -- chance 已在通用概率检查中处理，到这里说明概率已通过
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
    -- 支持单目标和 AOE（当 aoeRange 存在时，范围内敌人均受影响）
    if eff.resReduce and target and target.alive then
        local dur = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        if eff.aoeRange and not eff.aoeDmgPct then
            -- AOE 魔抗降低（chaos_rift: on_crit + resReduce + aoeRange）
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
            -- 单目标魔抗降低
            target.tagResReduce = math.max(target.tagResReduce or 0, eff.resReduce)
            target.tagResReduceTimer = math.max(target.tagResReduceTimer or 0, dur)
        end
    end

    -- 物防降低百分比（scald: defReduce / brittle: defReduce）
    if eff.defReduce and target and target.alive then
        local dur = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        target.tagDefReduce = math.min((target.tagDefReduce or 0) + eff.defReduce, 0.60)
        target.tagDefReduceTimer = math.max(target.tagDefReduceTimer or 0, dur)
    end

    -- 受伤加成标记（pierce_mark: bonusDmg — 不同于 ampRate，独立叠加）
    if eff.bonusDmg and not eff.defReducePct and target and target.alive then
        local dur = (eff.duration or 3.0) + (tagBonus.tagDur_add or 0)
        target.tagBonusDmg = math.max(target.tagBonusDmg or 0, eff.bonusDmg)
        target.tagBonusDmgTimer = math.max(target.tagBonusDmgTimer or 0, dur)
    end

    -- 叠层受伤加成（shadow_mark / charge / toxin_layer / hellfire_brand: dmgPerStack）
    if eff.dmgPerStack and target and target.alive then
        target.tagDmgStacks = math.min((target.tagDmgStacks or 0) + 1, eff.maxStacks or 5)
        target.tagDmgPerStack = eff.dmgPerStack
        target.tagDmgStackTimer = eff.stackDuration or eff.duration or 6.0
    end

    -- 每N次攻击真伤（heavy_blow: everyN + trueDmgPct）
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

    -- 低血线真伤（divine_wrath: lowHpThreshold + trueDmgPct）
    if eff.lowHpThreshold and target and target.alive then
        local hpRatio = target.hp / (target.maxHp or target.hp)
        if hpRatio < eff.lowHpThreshold then
            local trueDmg = tower.attack * (eff.trueDmgPct or 1.0)
            Enemy.TakeDamage(target, trueDmg)
        end
    end

    -- 冰封（frozen: freezeChance + freezeDuration + bonusDmg）
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
            -- 冰封受伤加成
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

    -- 逐层暴击叠加（blood_eye: critRatePerHit + maxCritStacks + critDmgBonus）
    if eff.critRatePerHit and target and target.alive then
        tagState.stacks = math.min((tagState.stacks or 0) + 1, eff.maxCritStacks or 5)
        -- 将叠加的暴击率/暴伤写入 tower 的运行时加成
        tower.tagCritRateBonus = tagState.stacks * eff.critRatePerHit
        tower.tagCritDmgBonus  = eff.critDmgBonus or 0
    end

    -- 魔焰叠层暴击暴伤（infernal_stack: critPerStack + critDmgPerStack）
    if eff.critPerStack and target and target.alive then
        tagState.stacks = math.min((tagState.stacks or 0) + 1, eff.maxStacks or 5)
        tagState.timer  = eff.stackDuration or 5.0
        tower.tagInfernalCritRate = tagState.stacks * eff.critPerStack
        tower.tagInfernalCritDmg = tagState.stacks * eff.critDmgPerStack
    end

    -- 连续攻击同目标叠伤（focus_fire: dmgIncPerHit + maxStacks）
    if eff.dmgIncPerHit and target and target.alive then
        if tagState._lastTarget == target then
            tagState._focusStacks = math.min((tagState._focusStacks or 0) + 1, eff.maxStacks or 10)
        else
            tagState._lastTarget = target
            tagState._focusStacks = 1
        end
        -- 伤害加成由 ModifyDamage 读取
        tower.tagFocusFireBonus = tagState._focusStacks * eff.dmgIncPerHit
    end

    -- 穿透（penetrate: pierce + pierceDmgPct）
    if eff.pierce and target and target.alive then
        local pierceDmg = tower.attack * (eff.pierceDmgPct or 0.60)
        -- 查找目标身后最近的敌人
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

    -- 拉拽（dimension_collapse: pullChance + pullDistance）
    if eff.pullChance and target and target.alive then
        if math.random() < eff.pullChance then
            -- 将目标位置向路径回退 pullDistance 像素
            target.pathProgress = math.max(0, (target.pathProgress or 0) - (eff.pullDistance or 30))
        end
    end

    -- 斩杀（annihilate: executeThreshold）
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

    -- 破甲扩散（aftershock: spreadRange + spreadRatio）
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

    -- 无视护盾（shadow_chain: ignoreShield — 标记到 tower 供伤害流程读取）
    if eff.ignoreShield and target and target.alive then
        tower._tagIgnoreShield = true
    end

    -- 链接分伤（fate_thread: linkDmgShare + maxLinks）
    if eff.linkDmgShare and target and target.alive then
        target.tagLinked = true
        target.tagLinkShare = eff.linkDmgShare
        -- 收集所有 linked 目标由 TakeDamage 流程读取
    end

    -- 链接减速/魔抗（fate_entangle: linkedSlow + linkedResShred）
    if eff.linkedSlow and target and target.alive then
        if target.tagLinked then
            Enemy.ApplySlow(target, 2.0, eff.linkedSlow)
            if eff.linkedResShred then
                target.tagResReduce = (target.tagResReduce or 0) + eff.linkedResShred
                target.tagResReduceTimer = math.max(target.tagResReduceTimer or 0, 3.0)
            end
        end
    end

    -- 击杀相关 on_kill 效果（不在 on_hit 触发，由 ApplyTags on_kill 调用）

    -- 击杀缩短主动CD（soul_drain: cdReduce）
    if eff.cdReduce then
        if tower.skillTimers then
            for timerId, v in pairs(tower.skillTimers) do
                tower.skillTimers[timerId] = math.max(0, v - eff.cdReduce)
            end
        end
        -- 同时缩短标签 active CD
        if tower.tags then
            for _, ts2 in pairs(tower.tags) do
                if ts2.def.type == "active" and ts2.cd > 0 then
                    ts2.cd = math.max(0, ts2.cd - eff.cdReduce)
                end
            end
        end
    end

    -- 击杀后必暴（fallen_glory: guaranteedCrit + critDmgBonus）
    if eff.guaranteedCrit then
        tower.tagGuaranteedCrit = true
        tower.tagGuaranteedCritDmg = eff.critDmgBonus or 0
    end

    -- 击杀CD概率缩短（lord_will: chance + cdResetAmount）
    if eff.cdResetAmount then
        -- chance 已在通用概率检查中处理
        if tower.skillTimers then
            for timerId, v in pairs(tower.skillTimers) do
                tower.skillTimers[timerId] = math.max(0, v - eff.cdResetAmount)
            end
        end
    end

    -- 额外掉落（life_spring: extraDropChance）
    if eff.extraDropChance and target and math.random() < eff.extraDropChance then
        local LootDrop     = require("Game.LootDrop")
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

--- 升级标签（供 UI / 技能书 调用）
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

    -- 检查解锁条件
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

    -- 检查显式依赖
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

    -- 消耗多阶技能书（按英雄稀有度查表）
    local rarity = Config.HERO_RARITY and Config.HERO_RARITY[heroId] or "N"
    local costTable = Config.SKILL_BOOK_COST and Config.SKILL_BOOK_COST[rarity]
    local costMap = costTable and costTable[curTier]  -- curTier=1→升到T2的费用表
    if costMap then
        local Currency = require("Game.Currency")
        -- 检查所有技能书是否足够
        for bookId, amount in pairs(costMap) do
            if not Currency.Has(bookId, amount) then
                return false, "not_enough_skill_book"
            end
        end
        -- 全部足够才扣除
        for bookId, amount in pairs(costMap) do
            Currency.Spend(bookId, amount)
        end
    end

    HeroData.SetTagTier(heroId, tagDef.id, curTier + 1)
    return true
end

-- ============================================================================
-- 每波重置
-- ============================================================================

function HeroSkills.OnWaveStart()
    for _, tower in ipairs(State.towers) do
        if tower.hstate then
            tower.hstate.killAtkStacks = 0
            -- Eternal Archfiend: 每波重置层数和标记
            tower.hstate.demonFlameStacks = 0
            tower.hstate.demonFlameTimer  = nil
            tower.hstate.erodeStacks      = 0
            tower.hstate.erodeTimer       = nil
            tower.hstate.bonusDmgBonus    = 0
            tower.hstate.abyssMarkTarget  = nil
            tower.hstate.abyssMarkTimer   = 0
            tower.hstate.bonusCritRate    = 0
            tower.hstate.bonusCritDmg     = 0
            -- 标签系统运行时状态重置
            tower.hstate.killAtkBurst      = nil
            tower.hstate.killAtkBurstTimer = nil
            tower.hstate.killDmgStacks     = 0
            tower.hstate.killDmgBonus      = 0
            -- 被动动态标签
            tower.hstate.resonanceAtkBonus  = 0
            tower.hstate.resonanceDotAmp    = 0
            -- 鲜花环
            tower.hstate.wreathActive = false
            tower.hstate.wreathTimer  = 0
            tower.hstate.wreathBonus  = 0
            tower.hstate.natureFlatAtk = 0
            -- bonusPerWave: 按当前波数重新计算
            if tower.hstate.bonusPerWaveRate then
                local wave = State.wave or 1
                tower.hstate.bonusPerWaveSpd = math.min(
                    (wave - 1) * tower.hstate.bonusPerWaveRate,
                    tower.hstate.bonusPerWaveMax or 0.50
                )
            end
        end
        -- 标签运行时状态重置（cd / stacks / timer）
        if tower.tags then
            for _, ts in pairs(tower.tags) do
                ts.cd     = 0
                ts.stacks = 0
                ts.timer  = 0
            end
            tower.tagDotMultiplier = nil
        end
        -- tower 上的标签字段重置
        tower.tagCritRateBonus    = nil
        tower.tagCritDmgBonus     = nil
        tower.tagInfernalCritRate = nil
        tower.tagInfernalCritDmg  = nil
        tower.tagGuaranteedCrit   = nil
        tower.tagGuaranteedCritDmg = nil
        tower.tagFocusFireBonus   = nil
        tower._tagArcticChill     = nil
        tower._tagMiasmaZone      = nil
        tower._tagIgnoreShield    = nil
    end

    -- 全局标签 buff 重置
    State.tagWarCryBuff   = nil
    State.tagTeamSpdBuff  = nil
    State.causalityActive = nil
    State.causalityChance = nil

    for _, e in ipairs(State.enemies) do
        e.slowSpread = nil
        e.dotSpread  = nil
        e.chillStacks = nil
        e.chillTimer  = nil
        -- shadowNeedle 已迁移到 tower 上，enemy 上不再需要清理
        -- Ember Wraith: 灼烧清理
        e.igniteStacks = nil
        e.igniteTimer = nil
        e.igniteDotDmg = nil
        e.igniteSource = nil
        e.igniteTickTimer = nil
        e._igniteSpreadDone = nil
        -- 标签系统 enemy 字段清理
        e.physVuln = nil
        e.physVulnTimer = nil
        e.magicVuln = nil
        e.magicVulnTimer = nil
        e.armorBreak = nil
        e.defReduce = nil
        e.healReduction = nil
        -- 标签新增 enemy 字段
        e.tagResReduce = nil
        e.tagResReduceTimer = nil
        e.tagDefReduce = nil
        e.tagDefReduceTimer = nil
        e.tagBonusDmg = nil
        e.tagBonusDmgTimer = nil
        e.tagFrozenBonusDmg = nil
        e.tagFrozenTimer = nil
        e.tagDmgStacks = nil
        e.tagDmgPerStack = nil
        e.tagDmgStackTimer = nil
        e.tagLinked = nil
        e.tagAbyssMarked = nil
        e.tagSunderStacks = nil
        e.ampDamage = nil
        e.ampDamageTimer = nil
        e._chillAccum = nil
        e.slowImmuneLift = nil
    end
end

return HeroSkills
