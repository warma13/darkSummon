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
    for _, tagDef in ipairs(tagDefs) do
        local tier = HeroData.GetTagTier(heroId, tagDef.id)
        local unlocked = HeroData.IsTagUnlocked(heroId, tagDef)

        -- 如果解锁条件满足但 tier 为0，且 tagDef 默认 tier > 0，自动激活
        if unlocked and tier == 0 and tagDef.tier and tagDef.tier > 0 then
            tier = tagDef.tier
            HeroData.SetTagTier(heroId, tagDef.id, tier)
        end

        -- 检查依赖标签
        local reqMet = true
        if tagDef.requires then
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

    -- 检查依赖
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

    -- 消耗技能书（如果有配置）
    local cost = Config.SKILL_BOOK_COST and Config.SKILL_BOOK_COST[curTier + 1]
    if cost then
        local Currency = require("Game.Currency")
        if not Currency.CanAfford("skill_book", cost) then
            return false, "not_enough_skill_book"
        end
        Currency.Spend("skill_book", cost, "UpgradeTag_" .. tagId)
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
    end
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
        e.armorBreak = nil
        e.defReduce = nil
        e.healReduction = nil
    end
end

return HeroSkills
