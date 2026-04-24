-- Game/RelicCalc.lua
-- 遗物数值缩放工具
-- V(relic, baseValue) = baseValue × 品质倍率 × (1 + star × 0.15) × (1 + (level-1) × 0.03)

local Config = require("Game.Config")

local RelicCalc = {}

-- 本地缓存品质倍率表（避免每次查 Config）
local QUALITY_MULT = Config.RELIC_QUALITY_MULT

--- 通用数值缩放
--- @param relic table  { quality, star, level, ... }
--- @param baseValue number  精良(green) Lv1 ★0 基准值
--- @return number 缩放后的值
function RelicCalc.V(relic, baseValue)
    local qm = QUALITY_MULT[relic.quality] or 1.0
    local sm = 1 + (relic.star or 0) * 0.15
    local lm = 1 + ((relic.level or 1) - 1) * 0.03
    return baseValue * qm * sm * lm
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
--- @param relic table 遗物数据
--- @param willReduction number 急速充能减少的次数
--- @return number
function RelicCalc.GetEffectiveChargeMax(relic, willReduction)
    local base = Config.RELIC_CHARGE_MAX
    local starReduce = RelicCalc.V(relic, Config.RELIC_CHARGE_STAR_REDUCE)
    local effective = base - willReduction - starReduce
    return math.max(Config.RELIC_CHARGE_MIN, math.floor(effective))
end

return RelicCalc
