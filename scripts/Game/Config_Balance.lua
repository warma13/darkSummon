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
    DEF_HP_RATIO      = Config.ENEMY_DEF_HP_RATIO,     -- 0.25
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

--- 打印战力对比表（调试用，输出到控制台）
---@param fromStage number
---@param toStage number
---@param step number
---@param rarity string|nil 默认 "SSR"
function Balance.PrintPowerTable(fromStage, toStage, step, rarity)
    rarity = rarity or "SSR"
    local g = Balance.HERO.GROWTH_PCT[rarity] or 0.12
    print("=== 战力对比表 ===")
    print(string.format("%-8s %-12s %-12s %-12s %-8s",
        "Stage", "HeroPower", "MonsterHP", "MonsterDEF", "Ratio"))
    print(string.rep("-", 60))

    for stage = fromStage, toStage, step do
        -- 假设玩家进度: level ≈ stage, star 按进度估算, advance 按关卡估算
        local level = math.min(stage, Balance.HERO.MAX_LEVEL)
        local star = math.min(math.floor(stage / 200), Balance.HERO.MAX_STAR)
        local advLv = math.min(math.floor(stage / 300), 20)

        local heroMult = Balance.ExpectedHeroPowerMult(level, star, advLv, rarity)
        local _, rawHP, def = Balance.ExpectedMonsterEHP(stage, 1, "infantry")
        local ratio = Balance.PowerRatio(level, star, advLv, rarity, stage)

        print(string.format("%-8d %-12.1f %-12.0f %-12.0f %-8.3f",
            stage, heroMult, rawHP, def, ratio))
    end
    print("=== END ===")
end

end

return apply
