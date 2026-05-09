------------------------------------------------------------------------
-- MonsterEHP.lua  —  怪物有效生命 (Effective HP) 计算器
-- 将怪物的原始 HP 转化为"英雄需要输出多少等效伤害才能击杀"
-- 依赖: Config_Enemies, Config_Heroes (BASE_CRIT_MULT), FormulaLib, Config_Balance
------------------------------------------------------------------------
local MonsterEHP = {}

local Config   = require "Game.Config"
local Balance  = Config.Balance
local F        = require "Game.FormulaLib"

------------------------------------------------------------
-- 默认参数
------------------------------------------------------------
local DEFAULTS = {
    stageNum    = 1,
    waveInStage = 1,
    roleId      = "minion",
    themeId     = nil,         -- nil = 自动按关卡号推算
    heroElement = "shadow",

    -- 英雄属性 (用于计算各乘区的"穿过率")
    heroDamage  = 0,           -- 英雄每击伤害 (finalAtk), 用于 Diminishing DEF 公式; 0=退化为旧公式
    armorPen    = 0,
    critRate    = 0,
    critDmg     = 0,
    dmgBonus    = 0,
    elemDmg     = 0,
    elemMastery = 0,
}

------------------------------------------------------------
-- 内部辅助
------------------------------------------------------------

--- 按关卡号推算主题 ID
local function inferThemeId(stageNum)
    if Config.GetThemeByStage then
        local t = Config.GetThemeByStage(stageNum)
        return t and t.id or "undead"
    end
    -- 手动推算: 5 关一个主题, 5 个主题循环
    local themes = Config.THEMES or { "undead", "lava", "forest", "frost", "void" }
    local idx = ((stageNum - 1) % (#themes * (Config.STAGES_PER_THEME or 5)))
    local themeIdx = math.floor(idx / (Config.STAGES_PER_THEME or 5)) + 1
    if type(themes[themeIdx]) == "table" then
        return themes[themeIdx].id or "undead"
    end
    return themes[themeIdx] or "undead"
end

--- 获取怪物缩放系数 (Piecewise4 from ENEMY_SCALING)
local function getScalingValue(segments, stageNum)
    return F.Piecewise4(segments, stageNum)
end

------------------------------------------------------------
-- 核心: 计算怪物有效生命
------------------------------------------------------------

---@param params table  见 DEFAULTS
---@return table
function MonsterEHP.Calc(params)
    local p = {}
    for k, v in pairs(DEFAULTS) do
        p[k] = (params and params[k] ~= nil) and params[k] or v
    end
    -- pairs() 会跳过 DEFAULTS 中值为 nil 的键 (如 themeId),
    -- 但 heroDamage 默认为 0 所以 pairs 可以遍历到它。
    -- 这里显式读取一次以防万一:
    if params and params.heroDamage then
        p.heroDamage = params.heroDamage
    end

    local role = Config.ENEMY_ROLES[p.roleId]
    if not role then
        error("MonsterEHP: unknown roleId '" .. tostring(p.roleId) .. "'")
    end

    local themeId = p.themeId or inferThemeId(p.stageNum)

    -- ---- 1. 原始 HP ----
    local hpScale = Config.GetStageHPScale(p.stageNum)
    local waveScale = F.Linear(1.0, 0.04, math.max(0, p.waveInStage - 1))
    local round = Config.GetThemeRound
        and Config.GetThemeRound(p.stageNum)
        or (math.floor((p.stageNum - 1) / 25) + 1)
    local roundHPMult = 1.0 + (round - 1) * 0.5

    -- 小怪 tierMult (与 Wave.lua 对齐)
    local tier = math.ceil(p.stageNum / 10)
    local minionExp = Config.MINION_TIER_EXPONENT or 1.00
    local minionTierMult = tier ^ minionExp

    local rawHP = role.baseHP * hpScale * waveScale * roundHPMult * minionTierMult

    -- ---- 2. 原始 DEF（独立缩放，与 HP 解耦）----
    local defScale = Config.GetStageDEFScale
        and Config.GetStageDEFScale(p.stageNum)
        or (hpScale * (Config.ENEMY_DEF_HP_RATIO or 0.10))  -- fallback 兼容
    local rawDEF = math.floor((role.baseDEF or 0) * defScale)

    -- ---- 3. 怪物缩放减免 ----
    local scaling = Config.ENEMY_SCALING or {}
    local critDmgReduce   = scaling.critDmgReduce   and getScalingValue(scaling.critDmgReduce,   p.stageNum) or 0
    local dmgBonusReduce  = scaling.dmgBonusReduce  and getScalingValue(scaling.dmgBonusReduce,  p.stageNum) or 0
    local elemDmgReduce   = scaling.elemDmgReduce   and getScalingValue(scaling.elemDmgReduce,   p.stageNum) or 0
    local armorPenResist  = scaling.armorPenResist   and getScalingValue(scaling.armorPenResist,  p.stageNum) or 0

    -- ---- 4. 各乘区 (从 EHP 视角: 乘区值 > 1 = 怪物更难杀) ----

    -- 4a. DEF 乘区
    -- armorPen 是百分比 (0.0~1.0)，与 Combat.lua 一致:
    --   enemyDEF = enemyDEF * (1 - armorPen)
    local effectivePen = math.min(1.0, math.max(0, p.armorPen)) * (1 - armorPenResist)
    local effectiveDEF = math.max(0, rawDEF * (1 - effectivePen))
    -- Combat.lua 使用 F.Diminishing(DEF, damage) = damage / (damage + DEF)
    -- 即 throughput = damage / (damage + DEF)
    -- 对应 EHP_factor = (damage + DEF) / damage = 1 + DEF / damage
    -- 当未提供 heroDamage 时退化为旧公式 (damage=1)
    local heroDmg = (p.heroDamage and p.heroDamage > 0) and p.heroDamage or 1
    local defFactor = 1 + effectiveDEF / heroDmg

    -- 4b. 暴击期望乘区 (降低 EHP)
    local baseCritMult = Config.BASE_CRIT_MULT or 1.50
    local effectiveCritDmg = math.max(0, p.critDmg - critDmgReduce)
    local critExpMult = 1 + p.critRate * (baseCritMult - 1 + effectiveCritDmg)

    -- 4c. 元素抗性乘区
    local elemResist = 0
    if Config.THEME_ELEMENT_RESIST and Config.THEME_ELEMENT_RESIST[themeId] then
        elemResist = Config.THEME_ELEMENT_RESIST[themeId][p.heroElement] or 0
    end
    local elemResistFactor = 1 - elemResist  -- < 1 = 怪物弱于此元素, > 1 = 怪物抗此元素

    -- 4d. 伤害加成乘区
    local effectiveDmgBonus = math.max(0, p.dmgBonus - dmgBonusReduce)
    local dmgBonusMult = 1 + effectiveDmgBonus

    -- 4e. 元素伤害乘区
    local effectiveElemDmg = math.max(0, p.elemDmg + p.elemMastery - elemDmgReduce)
    local elemDmgMult = 1 + effectiveElemDmg

    -- 4f. 冰冻/易伤 (模拟器中默认 1.0)
    local chillMult = 1.0
    local vulnMult  = 1.0

    -- ---- 5. 总增伤乘积 ----
    local totalDmgMult = critExpMult * elemResistFactor * dmgBonusMult * elemDmgMult * chillMult * vulnMult
    -- (DEF 是加法层，不在乘积中)

    -- ---- 6. 有效 HP ----
    -- EHP = rawHP × defFactor / totalDmgMult
    local effectiveHP = rawHP * defFactor / totalDmgMult

    return {
        -- 原始值
        rawHP       = rawHP,
        rawDEF      = rawDEF,
        hpScale     = hpScale,
        round       = round,
        roundHPMult = roundHPMult,

        -- DEF 层
        effectivePen  = effectivePen,
        effectiveDEF  = effectiveDEF,
        defFactor     = defFactor,

        -- 各增伤乘区 (从英雄视角, > 1 = 英雄伤害增幅)
        critExpMult     = critExpMult,
        elemResistFactor = elemResistFactor,
        dmgBonusMult    = dmgBonusMult,
        elemDmgMult     = elemDmgMult,
        chillMult       = chillMult,
        vulnMult        = vulnMult,
        totalDmgMult    = totalDmgMult,

        -- 怪物缩放减免
        monsterScaling = {
            critDmgReduce  = critDmgReduce,
            dmgBonusReduce = dmgBonusReduce,
            elemDmgReduce  = elemDmgReduce,
            armorPenResist = armorPenResist,
        },

        -- 最终结果
        effectiveHP = effectiveHP,

        -- 输入快照
        themeId     = themeId,
        roleId      = p.roleId,
        stageNum    = p.stageNum,
    }
end

------------------------------------------------------------
-- 便捷: 只拿原始 HP (无英雄属性依赖)
------------------------------------------------------------
function MonsterEHP.RawHP(stageNum, roleId, waveInStage)
    waveInStage = waveInStage or 1
    roleId = roleId or "minion"
    local role = Config.ENEMY_ROLES[roleId]
    if not role then return 0 end

    local hpScale = Config.GetStageHPScale(stageNum)
    local waveScale = F.Linear(1.0, 0.04, math.max(0, waveInStage - 1))
    local round = math.floor((stageNum - 1) / 25) + 1
    local roundHPMult = 1.0 + (round - 1) * 0.5

    -- 小怪也有 tierMult 缩放 (与 Wave.lua 对齐)
    local tier = math.ceil(stageNum / 10)
    local minionExp = Config.MINION_TIER_EXPONENT or 1.00
    local tierMult = tier ^ minionExp

    return role.baseHP * hpScale * waveScale * roundHPMult * tierMult
end

------------------------------------------------------------
-- Boss 相关: tierMult 计算
------------------------------------------------------------

--- Boss 等级 (每 10 关升一级)
---@param stageNum number
---@return number
function MonsterEHP.GetBossTier(stageNum)
    return math.ceil(stageNum / 10)
end

--- tierMult = bossTier ^ exponent
---@param stageNum number
---@param exponent? number 默认读取 Config.BOSS_TIER_EXPONENT
---@return number
function MonsterEHP.GetTierMult(stageNum, exponent)
    exponent = exponent or Config.BOSS_TIER_EXPONENT or 1.50
    local tier = MonsterEHP.GetBossTier(stageNum)
    return tier ^ exponent
end

------------------------------------------------------------
-- Boss 原始 HP (含 tierMult，无英雄属性依赖)
------------------------------------------------------------

--- 计算 Boss 原始 HP（含 tierMult + roundHPMult + hpScale + waveScale）
--- 与 Wave.lua 的实际生成逻辑对齐
---@param stageNum number
---@param exponent? number tierMult 指数，默认读取 Config.BOSS_TIER_EXPONENT
---@return number rawHP
---@return table detail { bossDef, hpScale, waveScale, roundHPMult, tierMult, bossTier }
function MonsterEHP.BossRawHP(stageNum, exponent)
    exponent = exponent or Config.BOSS_TIER_EXPONENT or 1.50

    local bossDef = Config.BuildBossDef(stageNum)
    local hpScale = Config.GetStageHPScale(stageNum)
    -- Boss 出现在 wave 10 (BOSS_WAVE)
    local bossWave = Config.BOSS_WAVE or 10
    local waveScale = F.Linear(1.0, 0.04, math.max(0, bossWave - 1))

    local bossTier = MonsterEHP.GetBossTier(stageNum)
    local tierMult = bossTier ^ exponent

    -- bossDef.baseHP 已含 roundHPMult (BuildBossDef 内部乘了)
    local rawHP = bossDef.baseHP * hpScale * waveScale * tierMult

    return rawHP, {
        bossDef     = bossDef,
        hpScale     = hpScale,
        waveScale   = waveScale,
        roundHPMult = 1.0 + (Config.GetThemeRound(stageNum) - 1) * 0.5,
        tierMult    = tierMult,
        bossTier    = bossTier,
        exponent    = exponent,
    }
end

------------------------------------------------------------
-- Boss EHP 完整计算 (含 tierMult + 7 乘区)
------------------------------------------------------------

--- Boss 有效生命计算（与 Calc 结构一致，额外含 tierMult）
---@param params table  与 Calc 相同的参数, 额外支持:
---   bossExponent: tierMult 指数 (默认读取 Config.BOSS_TIER_EXPONENT)
---@return table 与 Calc 返回格式兼容, 额外含 tierMult/bossTier
function MonsterEHP.BossCalc(params)
    local p = {}
    for k, v in pairs(DEFAULTS) do
        p[k] = (params and params[k] ~= nil) and params[k] or v
    end
    if params and params.heroDamage then
        p.heroDamage = params.heroDamage
    end

    local exponent = (params and params.bossExponent) or Config.BOSS_TIER_EXPONENT or 1.50

    -- Boss 定义
    local bossDef = Config.BuildBossDef(p.stageNum)
    local themeId = bossDef.themeId or (p.themeId or inferThemeId(p.stageNum))

    -- ---- 1. 原始 HP (含 tierMult) ----
    local hpScale = Config.GetStageHPScale(p.stageNum)
    local bossWave = Config.BOSS_WAVE or 10
    local waveScale = F.Linear(1.0, 0.04, math.max(0, bossWave - 1))

    local bossTier = MonsterEHP.GetBossTier(p.stageNum)
    local tierMult = bossTier ^ exponent

    -- bossDef.baseHP 已含 roundHPMult
    local rawHP = bossDef.baseHP * hpScale * waveScale * tierMult

    -- ---- 2. 原始 DEF ----
    local defScale = Config.GetStageDEFScale
        and Config.GetStageDEFScale(p.stageNum)
        or (hpScale * (Config.ENEMY_DEF_HP_RATIO or 0.10))
    local rawDEF = math.floor((bossDef.baseDEF or 0) * defScale)

    -- ---- 3. 怪物缩放减免 ----
    local scaling = Config.ENEMY_SCALING or {}
    local critDmgReduce   = scaling.critDmgReduce   and getScalingValue(scaling.critDmgReduce,   p.stageNum) or 0
    local dmgBonusReduce  = scaling.dmgBonusReduce  and getScalingValue(scaling.dmgBonusReduce,  p.stageNum) or 0
    local elemDmgReduce   = scaling.elemDmgReduce   and getScalingValue(scaling.elemDmgReduce,   p.stageNum) or 0
    local armorPenResist  = scaling.armorPenResist   and getScalingValue(scaling.armorPenResist,  p.stageNum) or 0

    -- ---- 4. 各乘区 ----
    local effectivePen = math.min(1.0, math.max(0, p.armorPen)) * (1 - armorPenResist)
    local effectiveDEF = math.max(0, rawDEF * (1 - effectivePen))
    local heroDmg = (p.heroDamage and p.heroDamage > 0) and p.heroDamage or 1
    local defFactor = 1 + effectiveDEF / heroDmg

    local baseCritMult = Config.BASE_CRIT_MULT or 1.50
    local effectiveCritDmg = math.max(0, p.critDmg - critDmgReduce)
    local critExpMult = 1 + p.critRate * (baseCritMult - 1 + effectiveCritDmg)

    local elemResist = 0
    if Config.THEME_ELEMENT_RESIST and Config.THEME_ELEMENT_RESIST[themeId] then
        elemResist = Config.THEME_ELEMENT_RESIST[themeId][p.heroElement] or 0
    end
    local elemResistFactor = 1 - elemResist

    local effectiveDmgBonus = math.max(0, p.dmgBonus - dmgBonusReduce)
    local dmgBonusMult = 1 + effectiveDmgBonus

    local effectiveElemDmg = math.max(0, p.elemDmg + p.elemMastery - elemDmgReduce)
    local elemDmgMult = 1 + effectiveElemDmg

    local chillMult = 1.0
    local vulnMult  = 1.0

    local totalDmgMult = critExpMult * elemResistFactor * dmgBonusMult * elemDmgMult * chillMult * vulnMult

    local effectiveHP = rawHP * defFactor / totalDmgMult

    return {
        rawHP       = rawHP,
        rawDEF      = rawDEF,
        hpScale     = hpScale,
        round       = Config.GetThemeRound(p.stageNum),
        roundHPMult = 1.0 + (Config.GetThemeRound(p.stageNum) - 1) * 0.5,

        effectivePen  = effectivePen,
        effectiveDEF  = effectiveDEF,
        defFactor     = defFactor,

        critExpMult      = critExpMult,
        elemResistFactor = elemResistFactor,
        dmgBonusMult     = dmgBonusMult,
        elemDmgMult      = elemDmgMult,
        chillMult        = chillMult,
        vulnMult         = vulnMult,
        totalDmgMult     = totalDmgMult,

        monsterScaling = {
            critDmgReduce  = critDmgReduce,
            dmgBonusReduce = dmgBonusReduce,
            elemDmgReduce  = elemDmgReduce,
            armorPenResist = armorPenResist,
        },

        effectiveHP = effectiveHP,

        -- Boss 专有
        tierMult    = tierMult,
        bossTier    = bossTier,
        exponent    = exponent,
        bossName    = bossDef.name,
        themeId     = themeId,
        roleId      = "__boss",
        stageNum    = p.stageNum,
    }
end

return MonsterEHP
