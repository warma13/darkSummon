-- Game/CodexData.lua
-- 图鉴系统：英雄星级 + 遗物星级 → 全局战力加成
-- 纯计算模块，无需持久化（基于 HeroData / RelicData 实时计算）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")

local M = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

-- 每颗英雄星提供的全局攻击加成（百分比）
-- 例如：0.005 = 0.5% / 星，10个英雄共100星 → 50% 全局攻击加成
M.ATK_PER_HERO_STAR = 0.005

-- 每颗遗物星提供的全局攻击加成（百分比）
-- 遗物星更稀有，加成更高
M.ATK_PER_RELIC_STAR = 0.01

-- ============================================================================
-- 英雄图鉴
-- ============================================================================

--- 获取所有英雄的星级明细
---@return table[] { { id, name, rarity, star, atkBonus }, ... }
function M.GetHeroCodexList()
    local list = {}
    local totalStar = 0
    for _, td in ipairs(Config.TOWER_TYPES) do
        local h = HeroData.Get(td.id)
        local star = (h and h.star) or 0
        local bonus = star * M.ATK_PER_HERO_STAR
        list[#list + 1] = {
            id = td.id,
            name = td.name,
            rarity = td.rarity,
            star = star,
            atkBonus = bonus,
        }
        totalStar = totalStar + star
    end
    -- 按星数降序排列，星数相同按品质降序
    local RARITY_ORDER = { LR = 6, UR = 5, SSR = 4, SR = 3, R = 2, N = 1 }
    table.sort(list, function(a, b)
        if a.star ~= b.star then return a.star > b.star end
        local ra = RARITY_ORDER[a.rarity] or 0
        local rb = RARITY_ORDER[b.rarity] or 0
        return ra > rb
    end)
    return list, totalStar
end

--- 获取英雄图鉴总加成
---@return number atkPct  全局攻击加成百分比
---@return number totalStars  总星数
function M.GetHeroCodexBonus()
    local totalStar = 0
    for _, td in ipairs(Config.TOWER_TYPES) do
        local h = HeroData.Get(td.id)
        local star = (h and h.star) or 0
        totalStar = totalStar + star
    end
    return totalStar * M.ATK_PER_HERO_STAR, totalStar
end

-- ============================================================================
-- 遗物图鉴
-- ============================================================================

--- 获取所有遗物的星级明细
---@return table[] { { id, name, slot, quality, star, atkBonus }, ... }
---@return number totalStars
function M.GetRelicCodexList()
    local RelicData = require("Game.RelicData")
    local list = {}
    local totalStar = 0
    for relicId, relicDef in pairs(Config.RELICS) do
        if RelicData.IsOwned(relicId) then
            local _level, star = RelicData.GetProgress(relicId)
            star = star or 0
            local bonus = star * M.ATK_PER_RELIC_STAR
            list[#list + 1] = {
                id = relicId,
                name = relicDef.name,
                slot = relicDef.slot,
                quality = relicDef.minQuality,
                star = star,
                atkBonus = bonus,
            }
            totalStar = totalStar + star
        end
    end
    -- 按星数降序排列，星数相同按品质降序
    local QUALITY_ORDER = {}
    for i, q in ipairs(Config.RELIC_QUALITIES) do
        QUALITY_ORDER[q.id] = i
    end
    table.sort(list, function(a, b)
        if a.star ~= b.star then return a.star > b.star end
        local qa = QUALITY_ORDER[a.quality] or 0
        local qb = QUALITY_ORDER[b.quality] or 0
        return qa > qb
    end)
    return list, totalStar
end

--- 获取遗物图鉴总加成
---@return number atkPct  全局攻击加成百分比
---@return number totalStars  总星数
function M.GetRelicCodexBonus()
    local RelicData = require("Game.RelicData")
    local totalStar = 0
    for relicId, _ in pairs(Config.RELICS) do
        if RelicData.IsOwned(relicId) then
            local _level, star = RelicData.GetProgress(relicId)
            star = star or 0
            totalStar = totalStar + star
        end
    end
    return totalStar * M.ATK_PER_RELIC_STAR, totalStar
end

-- ============================================================================
-- 总图鉴加成
-- ============================================================================

--- 获取图鉴总攻击加成（英雄 + 遗物）
---@return number atkPct  总全局攻击加成百分比
---@return table detail  { heroAtkPct, heroStars, relicAtkPct, relicStars }
function M.GetTotalBonus()
    local heroAtk, heroStars = M.GetHeroCodexBonus()
    local relicAtk, relicStars = M.GetRelicCodexBonus()
    return heroAtk + relicAtk, {
        heroAtkPct = heroAtk,
        heroStars = heroStars,
        relicAtkPct = relicAtk,
        relicStars = relicStars,
    }
end

return M
