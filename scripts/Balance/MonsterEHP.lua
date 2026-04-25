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
    local hpScale = F.Piecewise4(Config.HP_SCALE_SEGMENTS, p.stageNum)
    local waveScale = F.Linear(1.0, 0.04, math.max(0, p.waveInStage - 1))
    local round = Config.GetThemeRound
        and Config.GetThemeRound(p.stageNum)
        or (math.floor((p.stageNum - 1) / 25) + 1)
    local roundHPMult = 1.0 + (round - 1) * 0.5

    local rawHP = role.baseHP * hpScale * waveScale * roundHPMult

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
    -- 软上限
    local softCritDmg = p.critDmg
    if Balance.SoftCapStat and Balance.SOFT_CAPS and Balance.SOFT_CAPS.critDmg then
        softCritDmg = Balance.SoftCapStat(p.critDmg, Balance.SOFT_CAPS.critDmg)
    end
    local effectiveCritDmg = math.max(0, softCritDmg - critDmgReduce)
    local critExpMult = 1 + p.critRate * (baseCritMult - 1 + effectiveCritDmg)

    -- 4c. 元素抗性乘区
    local elemResist = 0
    if Config.THEME_ELEMENT_RESIST and Config.THEME_ELEMENT_RESIST[themeId] then
        elemResist = Config.THEME_ELEMENT_RESIST[themeId][p.heroElement] or 0
    end
    local elemResistFactor = 1 - elemResist  -- < 1 = 怪物弱于此元素, > 1 = 怪物抗此元素

    -- 4d. 伤害加成乘区
    local softDmgBonus = p.dmgBonus
    if Balance.SoftCapStat and Balance.SOFT_CAPS and Balance.SOFT_CAPS.dmgBonus then
        softDmgBonus = Balance.SoftCapStat(p.dmgBonus, Balance.SOFT_CAPS.dmgBonus)
    end
    local effectiveDmgBonus = math.max(0, softDmgBonus - dmgBonusReduce)
    local dmgBonusMult = 1 + effectiveDmgBonus

    -- 4e. 元素伤害乘区
    local softElemDmg = p.elemDmg
    if Balance.SoftCapStat and Balance.SOFT_CAPS and Balance.SOFT_CAPS.elemDmg then
        softElemDmg = Balance.SoftCapStat(p.elemDmg, Balance.SOFT_CAPS.elemDmg)
    end
    local effectiveElemDmg = math.max(0, softElemDmg + p.elemMastery - elemDmgReduce)
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

    local hpScale = F.Piecewise4(Config.HP_SCALE_SEGMENTS, stageNum)
    local waveScale = F.Linear(1.0, 0.04, math.max(0, waveInStage - 1))
    local round = math.floor((stageNum - 1) / 25) + 1
    local roundHPMult = 1.0 + (round - 1) * 0.5

    return role.baseHP * hpScale * waveScale * roundHPMult
end

return MonsterEHP
