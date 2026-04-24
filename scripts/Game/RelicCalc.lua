-- Game/RelicCalc.lua
-- 遗物数值缩放工具
-- V(relic, baseValue) = baseValue × 品质倍率 × 升级加成（升星不影响数值，升星提供机制增强）

local Config = require("Game.Config")

local RelicCalc = {}

-- 本地缓存品质倍率表（避免每次查 Config）
local QUALITY_MULT = Config.RELIC_QUALITY_MULT

--- 通用数值缩放（仅受品质和等级影响，升星不影响）
--- V = base × 品质倍率 × 升级加成
--- 升级(level): 线性成长，每级 +5%（便宜，稳定数值成长）
--- 升星: 不影响 V()，通过 StarValue() 提供独立机制增强
--- @param relic table  { quality, level, ... }
--- @param baseValue number  精良(green) Lv1 基准值
--- @return number 缩放后的值
function RelicCalc.V(relic, baseValue)
    local qm = QUALITY_MULT[relic.quality] or 1.0
    local lm = 1 + ((relic.level or 1) - 1) * 0.05
    return baseValue * qm * lm
end

--- 星级机制增强值（渐进递减公式）
--- value = max × star / (star + halfStar)
--- star=0 → 0, star→∞ → max（但增速递减）
--- 例: max=8, halfStar=3 → ★1=2.0, ★2=4.8, ★3=4.0, ★5=5.0, ★10=6.15
--- @param star number 当前星级
--- @param starEffect table { max, halfStar, ... } 来自 Config_Relics
--- @return number 渐进增强值
function RelicCalc.StarValue(star, starEffect)
    if not starEffect then return 0 end
    local s = star or 0
    if s <= 0 then return 0 end
    local max = starEffect.max or 0
    local half = starEffect.halfStar or 3
    return max * s / (s + half)
end

--- 星级机制增强值的格式化描述
--- @param star number 当前星级
--- @param starEffect table
--- @return string 如 "充能-3.2" "持续+1.5秒"
function RelicCalc.FormatStarValue(star, starEffect)
    if not starEffect then return "" end
    local val = RelicCalc.StarValue(star, starEffect)
    -- 根据类型格式化
    local t = starEffect.type
    if t == "critDmg" or t == "critRate" or t == "chanceAdd" or t == "shareRatio"
        or t == "redBonus" or t == "amplifyAdd" or t == "fallbackAdd" then
        return string.format("%.1f%%", val * 100)
    elseif t == "markCount" or t == "spreadCount" then
        return string.format("%d", math.floor(val))
    else
        return string.format("%.1f", val)
    end
end

--- 获取升级费用（遗物精华）
--- cost(lv) = floor(80 * 1.08^(lv-1))
--- @param level number 当前等级
--- @return number
function RelicCalc.GetUpgradeCost(level)
    return math.floor(Config.RELIC_UPGRADE_BASE_COST
        * Config.RELIC_UPGRADE_COST_RATE ^ (level - 1))
end

--- 获取升星碎片费用
--- shards(star) = floor(5 * 1.25^(star-1))
--- @param currentStar number 当前星级（要升到 currentStar+1）
--- @return number
function RelicCalc.GetStarUpShardCost(currentStar)
    return math.floor(Config.RELIC_STAR_BASE_SHARDS
        * Config.RELIC_STAR_SHARD_RATE ^ (currentStar))
end

--- 获取有效充能上限
--- 充能减少来源: 急速充能(will固定值) + 力部位遗物星级效果(chargeReduce渐进值)
--- @param relic table 力部位遗物数据（含 star）
--- @param willReduction number 急速充能减少的次数
--- @return number
function RelicCalc.GetEffectiveChargeMax(relic, willReduction)
    local base = Config.RELIC_CHARGE_MAX
    -- 力部位遗物自身星级的充能减少（渐进值）
    local relicDef = Config.RELICS[relic.id]
    local starReduce = 0
    if relicDef and relicDef.starEffect and relicDef.starEffect.type == "chargeReduce" then
        starReduce = RelicCalc.StarValue(relic.star, relicDef.starEffect)
    end
    local effective = base - willReduction - starReduce
    return math.max(Config.RELIC_CHARGE_MIN, math.floor(effective))
end

return RelicCalc
