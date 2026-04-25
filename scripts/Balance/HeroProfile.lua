------------------------------------------------------------------------
-- HeroProfile.lua  —  英雄属性快照构建器
-- 复现 Tower.lua / HeroData.lua 的 ATK/SPD/副属性 计算链
-- 依赖: Config_Balance, Config_Heroes, Config_Core, FormulaLib
------------------------------------------------------------------------
local HeroProfile = {}

local Config   = require "Game.Config"          -- 门面：已合并 Core/Heroes/Enemies/Balance
local Balance  = Config.Balance                  -- Config_Balance 挂在 Config.Balance 上
local F        = require "Game.FormulaLib"

------------------------------------------------------------
-- 默认参数 (所有可选字段的零值)
------------------------------------------------------------
local DEFAULTS = {
    heroId         = "shadow_mage",
    level          = 1,
    star           = 0,        -- 英雄星级 0~30
    advanceLevel   = 0,        -- 进阶 0~20
    battleStar     = 1,        -- 战斗星级 1~5
    equipAtk       = 0,
    atkPctBonus    = 0,        -- 神器/符文 攻击力%
    relicAtkPct    = 0,        -- 遗物攻击力%
    relicSpdPct    = 0,        -- 遗物速度%
    relicCritDmgPct = 0,       -- 遗物暴伤%
    equipArmorPen  = 0,
    equipCritRate  = 0,
    equipCritDmg   = 0,
    equipDmgBonus  = 0,
    spdPctBonus    = 0,        -- 速度%加成 (神器等)
    elemDmg        = 0,
    elemMastery    = 0,
    isLeader       = false,
    -- 以下用于模拟神圣加成 (可选)
    divineAtkPct   = 0,
    divineSpdPct   = 0,
}

------------------------------------------------------------
-- 查找 TOWER_TYPES 中的 baseSpeed
------------------------------------------------------------
local _baseSpeedCache = {}
local function getBaseSpeed(heroId)
    if _baseSpeedCache[heroId] then
        return _baseSpeedCache[heroId]
    end
    for _, t in ipairs(Config.TOWER_TYPES) do
        if t.id == heroId then
            _baseSpeedCache[heroId] = t.baseSpeed
            return t.baseSpeed
        end
    end
    _baseSpeedCache[heroId] = 1.0  -- fallback
    return 1.0
end

------------------------------------------------------------
-- 核心: 构建英雄属性快照
------------------------------------------------------------

---@param params table  见 DEFAULTS 的 key 列表
---@return table profile
function HeroProfile.Build(params)
    local p = {}
    for k, v in pairs(DEFAULTS) do
        p[k] = (params and params[k] ~= nil) and params[k] or v
    end

    local base = Config.HERO_BASE_STATS[p.heroId]
    if not base then
        error("HeroProfile: unknown heroId '" .. tostring(p.heroId) .. "'")
    end

    local rarity  = Config.HERO_RARITY and Config.HERO_RARITY[p.heroId] or "N"
    local element = Config.HERO_ELEMENT and Config.HERO_ELEMENT[p.heroId] or "shadow"

    -- ---- 1. 三大乘区 (复用 Config_Balance) ----
    local levelMult = Balance.CalcLevelMult(p.level, rarity)
    local advMult   = Balance.CalcAdvanceMult(p.advanceLevel)
    local starMult  = Balance.CalcStarMult(p.star)
    local totalMult = levelMult * advMult * starMult

    -- ---- 2. heroAtk (HeroData.GetHeroStats 的结果) ----
    local rawAtk  = math.floor(base.atk * levelMult)
    local heroAtk = math.floor(rawAtk * advMult * starMult)

    -- ---- 3. 战斗星级 & 最终 ATK (Tower.lua) ----
    local battleStarMult = (Config.STAR_MULTIPLIER and Config.STAR_MULTIPLIER[p.battleStar]) or 1.0

    local finalAtk
    if p.isLeader then
        -- 领袖无 battleStarMult
        finalAtk = (heroAtk + p.equipAtk)
                 * (1 + p.atkPctBonus + p.divineAtkPct)
                 * (1 + p.relicAtkPct)
    else
        finalAtk = (heroAtk * battleStarMult + p.equipAtk)
                 * (1 + p.atkPctBonus + p.divineAtkPct)
                 * (1 + p.relicAtkPct)
    end
    finalAtk = math.floor(finalAtk)

    -- ---- 4. 攻击间隔 (Tower.lua) ----
    local baseSpeed = getBaseSpeed(p.heroId)
    local starSpeedMult = (Config.STAR_SPEED_MULT and Config.STAR_SPEED_MULT[p.battleStar]) or 1.0
    local spdBonus = math.min(
        F.Piecewise(Config.SPD_BONUS_CURVE, totalMult),
        Config.SPD_BONUS_MAX or 0.30
    )
    local attackInterval
    if p.isLeader then
        attackInterval = baseSpeed / (1 + spdBonus + p.spdPctBonus + p.relicSpdPct + p.divineSpdPct)
    else
        attackInterval = baseSpeed / starSpeedMult / (1 + spdBonus + p.spdPctBonus + p.relicSpdPct + p.divineSpdPct)
    end

    -- ---- 5. 副属性 (HeroData.GetHeroStats + 装备) ----
    local n = math.max(0, p.level - 1)
    local heroArmorPen = (base.armorPen or 0) + n * (base.armorPenGrowth or 0)
    local heroCritRate = (base.critRate or 0) + n * (base.critRateGrowth or 0)
    local heroCritDmg  = (base.critDmg or 0)  + n * (base.critDmgGrowth or 0)

    -- armorPen 是百分比 (0.0~1.0)，与 Combat.lua 一致
    local armorPen = math.min(1.0, heroArmorPen + p.equipArmorPen)
    local critRate = heroCritRate + p.equipCritRate
    local critDmg  = heroCritDmg + p.equipCritDmg + p.relicCritDmgPct
    local dmgBonus = p.equipDmgBonus

    -- ---- 6. 软上限 ----
    local softCritDmg, softDmgBonus, softElemDmg
    if Balance.ApplySoftCaps then
        softDmgBonus, softCritDmg, softElemDmg = Balance.ApplySoftCaps(dmgBonus, critDmg, p.elemDmg)
    else
        softCritDmg  = critDmg
        softDmgBonus = dmgBonus
        softElemDmg  = p.elemDmg
    end

    return {
        -- 身份
        heroId   = p.heroId,
        rarity   = rarity,
        element  = element,
        isLeader = p.isLeader,

        -- 最终战斗属性
        finalAtk       = finalAtk,
        attackInterval  = attackInterval,
        dps             = finalAtk / attackInterval,  -- raw DPS (无减伤)

        -- 副属性 (raw, 未软上限)
        armorPen  = armorPen,
        critRate  = critRate,
        critDmg   = critDmg,
        dmgBonus  = dmgBonus,
        elemDmg   = p.elemDmg,
        elemMastery = p.elemMastery,

        -- 副属性 (软上限后)
        softCritDmg  = softCritDmg,
        softDmgBonus = softDmgBonus,
        softElemDmg  = softElemDmg,

        -- 中间值 (调试/报表)
        rawAtk         = rawAtk,
        heroAtk        = heroAtk,
        levelMult      = levelMult,
        advMult        = advMult,
        starMult       = starMult,
        totalMult      = totalMult,
        battleStarMult = battleStarMult,
        starSpeedMult  = starSpeedMult,
        spdBonus       = spdBonus,
        baseSpeed      = baseSpeed,

        -- 输入参数 (用于敏感度分析回溯)
        params = p,
    }
end

------------------------------------------------------------
-- 便捷: 只拿倍率 (用于交叉验证)
------------------------------------------------------------
function HeroProfile.PowerMult(level, star, advanceLevel, rarity)
    local levelMult = Balance.CalcLevelMult(level, rarity or "N")
    local advMult   = Balance.CalcAdvanceMult(advanceLevel or 0)
    local starMult  = Balance.CalcStarMult(star or 0)
    return levelMult * advMult * starMult
end

return HeroProfile
