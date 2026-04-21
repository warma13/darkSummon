-- Game/Config_Balance.lua
-- 集中化平衡参数 + 英雄/怪物战力对比函数
-- 用于数值设计时快速评估英雄 DPS vs 怪物 EHP

local F = require("Game.FormulaLib")

local function apply(Config)

local Balance = {}
Config.Balance = Balance

-- ============================================================================
-- 英雄侧参数（引用 Config 中已有常量，不重复定义）
-- ============================================================================
Balance.HERO = {
    MAX_LEVEL       = Config.MAX_LEVEL,                 -- 6000
    GROWTH_PCT      = Config.RARITY_GROWTH_PCT,         -- 品质→成长率
    ADVANCE_GATES   = Config.ADVANCE_GATES,             -- 20阶
    STAR_NORMAL     = Config.STAR_NORMAL_MULT,          -- 1.10
    STAR_CROWN      = Config.STAR_CROWN_MULT,           -- 1.15
    STAR_CROWN_START = Config.STAR_CROWN_START,         -- 21
    TIER_ADVANCE    = Config.TIER_ADVANCE_MULT,         -- 1.40
    MAX_STAR        = Config.MAX_HERO_STAR,             -- 30
    STAR_TIERS      = Config.STAR_TIERS,
    SPD_BONUS_CURVE = Config.SPD_BONUS_CURVE,
    SPD_BONUS_MAX   = Config.SPD_BONUS_MAX,
}

-- ============================================================================
-- 怪物侧参数
-- ============================================================================
Balance.MONSTER = {
    HP_SEGMENTS       = Config.HP_SCALE_SEGMENTS,
    DEF_HP_RATIO      = Config.ENEMY_DEF_HP_RATIO,     -- 0.10
    SPEED_PER_STAGE   = Config.STAGE_SPEED_PER_STAGE,   -- 0.02
    SPEED_CAP         = Config.STAGE_SPEED_CAP,          -- 1.8
    WAVE_HP_PER_WAVE  = Config.WAVE_HP_PER_WAVE,         -- 0.04
    ROUND_HP_K        = 0.5,    -- roundHPMult = 1 + (round-1)*0.5
    ROUND_SPD_K       = 0.1,    -- roundSpdMult = min(1 + (round-1)*0.1, 2.0)
    ROUND_SPD_CAP     = 2.0,
}

-- ============================================================================
-- 战斗公式参数
-- ============================================================================
Balance.COMBAT = {
    BASE_CRIT_MULT = Config.BASE_CRIT_MULT,   -- 1.50
}

-- ============================================================================
-- 英雄战力预估
-- ============================================================================

--- 计算等级倍率
---@param level number
---@param rarity string "N"/"R"/"SR"/"SSR"/"UR"/"LR"
---@return number
function Balance.CalcLevelMult(level, rarity)
    local g = Balance.HERO.GROWTH_PCT[rarity] or 0.06
    return F.Linear(1.0, g, math.max(0, level - 1))
end

--- 计算进阶倍率
---@param advanceLevel number 0~20
---@return number
function Balance.CalcAdvanceMult(advanceLevel)
    if advanceLevel <= 0 then return 1.0 end
    local n = math.min(advanceLevel, #Balance.HERO.ADVANCE_GATES)
    return F.CompoundMult(n, function(i)
        local gate = Balance.HERO.ADVANCE_GATES[i]
        return gate and (1.0 + gate.bonus) or 1.0
    end)
end

--- 计算升星倍率
---@param star number 0~30
---@return number
function Balance.CalcStarMult(star)
    if star <= 0 then return 1.0 end
    local mult = 1.0
    local crownStart = Balance.HERO.STAR_CROWN_START
    local normalM = Balance.HERO.STAR_NORMAL
    local crownM = Balance.HERO.STAR_CROWN
    local tierAdv = Balance.HERO.TIER_ADVANCE
    local tiers = Balance.HERO.STAR_TIERS

    -- 获取星级所属段
    local function getTier(s)
        for idx, tier in ipairs(tiers) do
            if s >= tier.starRange[1] and s <= tier.starRange[2] then
                return idx
            end
        end
        return 1
    end

    local prevTier = 0
    for s = 1, star do
        local curTier = getTier(s)
        if curTier > prevTier and prevTier > 0 then
            mult = mult * tierAdv
        end
        if s >= crownStart then
            mult = mult * crownM
        else
            mult = mult * normalM
        end
        prevTier = curTier
    end
    return mult
end

--- 预估英雄总战力倍率（等级 x 进阶 x 升星，不含装备/符文/技能）
---@param level number
---@param star number
---@param advanceLevel number
---@param rarity string
---@return number
function Balance.ExpectedHeroPowerMult(level, star, advanceLevel, rarity)
    return Balance.CalcLevelMult(level, rarity)
         * Balance.CalcAdvanceMult(advanceLevel)
         * Balance.CalcStarMult(star)
end

-- ============================================================================
-- 怪物 EHP 预估
-- ============================================================================

--- 预估怪物 HP 缩放（给定关卡号 + 关内波次号）
---@param stageNum number
---@param waveInStage number|nil 默认1
---@return number hpScale
function Balance.ExpectedMonsterHPScale(stageNum, waveInStage)
    waveInStage = waveInStage or 1
    local stageScale = F.Piecewise4(Balance.MONSTER.HP_SEGMENTS, stageNum)
    local waveScale = F.Linear(1.0, Balance.MONSTER.WAVE_HP_PER_WAVE, waveInStage - 1)
    return stageScale * waveScale
end

--- 预估怪物 EHP（含 DEF 等效）
---@param stageNum number
---@param waveInStage number|nil
---@param roleId string|nil 默认 "infantry"
---@return number ehp  等效生命值
---@return number rawHP 原始血量
---@return number def  防御值
function Balance.ExpectedMonsterEHP(stageNum, waveInStage, roleId)
    roleId = roleId or "infantry"
    local role = Config.ENEMY_ROLES[roleId]
    if not role then return 0, 0, 0 end

    local hpScale = Balance.ExpectedMonsterHPScale(stageNum, waveInStage)

    -- 轮次加成
    local round = Config.GetThemeRound(stageNum)
    local roundHPMult = F.Linear(1.0, Balance.MONSTER.ROUND_HP_K, round - 1)

    local rawHP = role.baseHP * roundHPMult * hpScale
    local def = math.floor((role.baseDEF or 0) * hpScale * Balance.MONSTER.DEF_HP_RATIO)

    -- EHP = HP / (1 - DEF减伤) = HP / (ATK/(ATK+DEF)) 近似为 HP * (1 + DEF/ATK)
    -- 简化：用 DEF 作为等效 HP 增量
    local ehp = rawHP + def * 2  -- 粗略近似

    return ehp, rawHP, def
end

-- ============================================================================
-- 战斗属性软上限（对数衰减）
-- ============================================================================
Balance.SOFT_CAPS = {
    dmgBonus = { threshold = 0.80, scale = 1.0 },
    critDmg  = { threshold = 1.00, scale = 1.5 },
    elemDmg  = { threshold = 0.80, scale = 1.0 },
}

--- 软上限函数：超过阈值后对数衰减
---@param raw number 原始值
---@param cap table { threshold: number, scale: number }
---@return number 软上限后的值
function Balance.SoftCapStat(raw, cap)
    if raw <= cap.threshold then return raw end
    local over = raw - cap.threshold
    return cap.threshold + cap.scale * math.log(1 + over / cap.scale)
end

--- 便捷：批量应用软上限
---@param dmgBonus number
---@param critDmg number
---@param elemDmg number
---@return number, number, number
function Balance.ApplySoftCaps(dmgBonus, critDmg, elemDmg)
    local caps = Balance.SOFT_CAPS
    return Balance.SoftCapStat(dmgBonus, caps.dmgBonus),
           Balance.SoftCapStat(critDmg, caps.critDmg),
           Balance.SoftCapStat(elemDmg, caps.elemDmg)
end

-- ============================================================================
-- 战力对比
-- ============================================================================

--- 战力比: 英雄ATK倍率 / 怪物HP缩放（粗略，理想 ~1.0 表示平衡）
---@param level number
---@param star number
---@param advLv number
---@param rarity string
---@param stageNum number
---@return number ratio
function Balance.PowerRatio(level, star, advLv, rarity, stageNum)
    local heroMult = Balance.ExpectedHeroPowerMult(level, star, advLv, rarity)
    local monsterScale = Balance.ExpectedMonsterHPScale(stageNum, 1)
    if monsterScale <= 0 then return 0 end
    return heroMult / monsterScale
end

--- 估算装备等级（假设装备等级约为关卡的 2/3）
---@param stageNum number
---@return number equipLevel
local function EstimateEquipLevel(stageNum)
    return math.min(math.floor(stageNum * 0.67), Config.EQUIP_MAX_LEVEL or 4000)
end

--- 估算装备提供的战斗属性加成（含淬炼粗略估算）
---@param equipLv number 装备等级
---@return number dmgBonus, number critDmg, number elemDmg
local function EstimateEquipBonuses(equipLv)
    -- 装备各槽基础: armor→dmgBonus, helmet→critDmg, mount→elemDmg
    -- 公式: statBase * equipLv * tierMult (假设中后期用橙/红品)
    local tierMult = 1.0
    if equipLv >= 3000 then tierMult = 5.0      -- 红
    elseif equipLv >= 2000 then tierMult = 3.0  -- 橙
    elseif equipLv >= 1000 then tierMult = 2.0  -- 紫
    elseif equipLv >= 500 then tierMult = 1.5   -- 蓝
    end

    local dmgBonus = 0.002 * equipLv * tierMult     -- armor slot
    local critDmg  = 0.003 * equipLv * tierMult     -- helmet slot
    local elemDmg  = 0.002 * equipLv * tierMult     -- mount slot

    -- 淬炼粗略: 约为装备的 40%
    dmgBonus = dmgBonus * 1.4
    critDmg  = critDmg  * 1.4
    elemDmg  = elemDmg  * 1.4

    return dmgBonus, critDmg, elemDmg
end

--- 打印战力对比表（调试用，含装备估算和软上限）
---@param fromStage number
---@param toStage number
---@param step number
---@param rarity string|nil 默认 "SSR"
function Balance.PrintPowerTable(fromStage, toStage, step, rarity)
    rarity = rarity or "SSR"
    print("=== 战力对比表（含装备+软上限） ===")
    print(string.format("%-7s %-11s %-11s %-11s %-7s %-7s %-7s %-7s",
        "Stage", "HeroBase", "MonsterHP", "MonDEF", "Ratio",
        "dmgB_s", "critD_s", "elemD_s"))
    print(string.rep("-", 80))

    for stage = fromStage, toStage, step do
        local level = math.min(stage, Balance.HERO.MAX_LEVEL)
        local star = math.min(math.floor(stage / 200), Balance.HERO.MAX_STAR)
        local advLv = math.min(math.floor(stage / 300), 20)

        local heroMult = Balance.ExpectedHeroPowerMult(level, star, advLv, rarity)
        local _, rawHP, def = Balance.ExpectedMonsterEHP(stage, 1, "infantry")
        local ratio = Balance.PowerRatio(level, star, advLv, rarity, stage)

        -- 装备估算
        local equipLv = EstimateEquipLevel(stage)
        local rawDmgB, rawCritD, rawElemD = EstimateEquipBonuses(equipLv)

        -- 应用软上限
        local softDmgB, softCritD, softElemD = Balance.ApplySoftCaps(rawDmgB, rawCritD, rawElemD)

        print(string.format("%-7d %-11.1f %-11.0f %-11.0f %-7.3f %-7.2f %-7.2f %-7.2f",
            stage, heroMult, rawHP, def, ratio,
            softDmgB, softCritD, softElemD))
    end
    print("=== END ===")
    print("dmgB_s/critD_s/elemD_s = 软上限后的 dmgBonus/critDmg/elemDmg")
end

end

return apply
