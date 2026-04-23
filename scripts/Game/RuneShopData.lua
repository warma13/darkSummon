-- Game/RuneShopData.lua
-- 符文商店数据模块：每日刷新随机符文，用深渊货币购买
-- 整合在兑换商店的"符文商店"标签页中

local Currency     = require("Game.Currency")
local HeroData     = require("Game.HeroData")
local RuneData     = require("Game.RuneData")
local RuneConfig   = require("Game.Config_Runes")
local SaveRegistry = require("Game.SaveRegistry")
local TodayKey     = require("Game.DateUtil").TodayKey

local RuneShopData = {}

-- ============================================================================
-- 定价表（基于分解值 2.5~3.5 倍）
-- ============================================================================

-- 定价原则：分解值的 3~4 倍（越高品质倍率越高，防止套利）
-- 分解值：白5尘 绿10尘 蓝20尘 紫40尘+1封 橙60尘+2封+1晶 红100尘+3封+3晶
---@type table<string, {dust:number, seal:number, crystal:number}>
RuneShopData.PRICE_TABLE = {
    white  = { dust = 15,   seal = 0, crystal = 0 },  -- 3x
    green  = { dust = 35,   seal = 0, crystal = 0 },  -- 3.5x
    blue   = { dust = 70,   seal = 0, crystal = 0 },  -- 3.5x
    purple = { dust = 120,  seal = 3, crystal = 0 },  -- 尘3x 封3x
    orange = { dust = 200,  seal = 6, crystal = 3 },   -- 尘3.3x 封3x 晶3x
    red    = { dust = 400,  seal = 10, crystal = 10 }, -- 尘4x 封3.3x 晶3.3x
}

-- ============================================================================
-- 每日品质分布：固定 18 个槽位
-- 2神话 + 3传说 + 4史诗 + 3稀有 + 3精良 + 3普通
-- ============================================================================

local DAILY_SLOTS = {
    -- 神话 x2
    { quality = "red" },
    { quality = "red" },
    -- 传说 x3
    { quality = "orange" },
    { quality = "orange" },
    { quality = "orange" },
    -- 史诗 x4
    { quality = "purple" },
    { quality = "purple" },
    { quality = "purple" },
    { quality = "purple" },
    -- 稀有 x3
    { quality = "blue" },
    { quality = "blue" },
    { quality = "blue" },
    -- 精良 x4
    { quality = "green" },
    { quality = "green" },
    { quality = "green" },
    { quality = "green" },
    -- 普通 x4
    { quality = "white" },
    { quality = "white" },
    { quality = "white" },
    { quality = "white" },
}

-- ============================================================================
-- 内部：生成指定品质的符文
-- ============================================================================

--- 生成一个指定品质的符文（不走 RuneData.Generate 的随机品质，而是强制品质）
---@param qualityId string
---@return table rune
local function GenerateRuneWithQuality(qualityId)
    local quality = RuneConfig.QUALITY_MAP[qualityId]
    if not quality then
        quality = RuneConfig.QUALITIES[1]
        qualityId = "white"
    end

    -- 随机系列
    local series = RuneConfig.SERIES[math.random(1, #RuneConfig.SERIES)]

    -- 词条数量 = 初始词条数
    local affixCount = quality.initAffixes
    local affixes = {}
    local existingIds = {}

    -- 60/40 分配：先基础后特殊
    local baseCount = math.ceil(affixCount * 0.6)
    local specialCount = affixCount - baseCount

    local function rollAffix(category)
        local pool = category == "base" and RuneConfig.AFFIX_BASE or RuneConfig.AFFIX_SPECIAL
        local totalW = 0
        local candidates = {}
        for _, a in ipairs(pool) do
            if not existingIds[a.id] then
                totalW = totalW + a.weight
                candidates[#candidates + 1] = { def = a, w = a.weight }
            end
        end
        if totalW <= 0 then return nil end
        local r = math.random() * totalW
        local acc = 0
        for _, c in ipairs(candidates) do
            acc = acc + c.w
            if r <= acc then return c.def end
        end
        return candidates[#candidates].def
    end

    local function calcValue(def)
        local base = def.minVal + math.random() * (def.maxVal - def.minVal)
        return base * quality.coeff * (0.8 + math.random() * 0.4)
    end

    for _ = 1, baseCount do
        local def = rollAffix("base")
        if def then
            existingIds[def.id] = true
            affixes[#affixes + 1] = {
                id = def.id, name = def.name,
                value = calcValue(def), unit = def.unit, locked = false,
            }
        end
    end
    for _ = 1, specialCount do
        local def = rollAffix("special")
        if def then
            existingIds[def.id] = true
            affixes[#affixes + 1] = {
                id = def.id, name = def.name,
                value = calcValue(def), unit = def.unit, locked = false,
            }
        end
    end

    -- 注意：这里不分配 runeId，购买时再通过 RuneData 分配，避免 ID 浪费
    return {
        qualityId = qualityId,
        seriesId = series.id,
        affixes = affixes,
        maxAffixes = quality.maxAffixes,
    }
end

-- ============================================================================
-- 数据存取
-- ============================================================================

--- 确保今日数据存在（跨日自动刷新）
---@return table
local function ensureToday()
    local today = TodayKey()

    local slotCount = #DAILY_SLOTS
    local oldCount = HeroData.runeShop and HeroData.runeShop.items and #HeroData.runeShop.items or 0
    if not HeroData.runeShop or HeroData.runeShop.day ~= today or oldCount ~= slotCount then
        -- 生成新的每日商品
        local items = {}
        for i, slot in ipairs(DAILY_SLOTS) do
            items[i] = {
                rune = GenerateRuneWithQuality(slot.quality),
                bought = false,
            }
        end
        HeroData.runeShop = {
            day = today,
            items = items,
        }
    end

    return HeroData.runeShop
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 获取今日商品列表
---@return table[] items  { rune, bought }
function RuneShopData.GetItems()
    return ensureToday().items
end

--- 获取某商品的价格
---@param qualityId string
---@return table {dust, seal, crystal}
function RuneShopData.GetPrice(qualityId)
    return RuneShopData.PRICE_TABLE[qualityId] or RuneShopData.PRICE_TABLE.white
end

--- 检查是否买得起
---@param qualityId string
---@return boolean
function RuneShopData.CanAfford(qualityId)
    local price = RuneShopData.GetPrice(qualityId)
    if not Currency.Has("rift_dust", price.dust) then return false end
    if price.seal > 0 and not Currency.Has("rune_seal", price.seal) then return false end
    if price.crystal > 0 and not Currency.Has("abyss_crystal", price.crystal) then return false end
    return true
end

--- 购买符文
---@param index number 商品索引 (1-6)
---@return boolean success
---@return string msg
function RuneShopData.Purchase(index)
    local data = ensureToday()
    local item = data.items[index]
    if not item then return false, "商品不存在" end
    if item.bought then return false, "已购买" end

    local price = RuneShopData.GetPrice(item.rune.qualityId)

    -- 检查货币
    if not Currency.Has("rift_dust", price.dust) then
        return false, "裂隙之尘不足（需要" .. price.dust .. "）"
    end
    if price.seal > 0 and not Currency.Has("rune_seal", price.seal) then
        return false, "符文封印不足（需要" .. price.seal .. "）"
    end
    if price.crystal > 0 and not Currency.Has("abyss_crystal", price.crystal) then
        return false, "深渊结晶不足（需要" .. price.crystal .. "）"
    end

    -- 检查背包容量
    local curCount, cap = RuneData.GetBagCapacity()
    if curCount >= cap then
        return false, "符文背包已满（" .. cap .. "）"
    end

    -- 扣费
    Currency.Spend("rift_dust", price.dust)
    if price.seal > 0 then Currency.Spend("rune_seal", price.seal) end
    if price.crystal > 0 then Currency.Spend("abyss_crystal", price.crystal) end

    -- 复制符文数据并分配正式 runeId
    local rune = {}
    for k, v in pairs(item.rune) do
        rune[k] = v
    end
    -- 深拷贝 affixes
    rune.affixes = {}
    for i, a in ipairs(item.rune.affixes) do
        rune.affixes[i] = {}
        for k, v in pairs(a) do rune.affixes[i][k] = v end
    end

    -- 通过 RuneData 生成正式 ID 并入包
    local genRune = RuneData.Generate(1.0)
    rune.runeId = genRune.runeId  -- 借用生成的 ID

    local ok, addMsg = RuneData.AddToBag(rune)
    if not ok then
        -- 回滚货币（理论上不会走到这里，前面已检查容量）
        Currency.Add("rift_dust", price.dust)
        if price.seal > 0 then Currency.Add("rune_seal", price.seal) end
        if price.crystal > 0 then Currency.Add("abyss_crystal", price.crystal) end
        return false, addMsg
    end

    -- 标记已购买
    item.bought = true

    -- 即时保存
    HeroData.Save(true)

    local quality = RuneConfig.QUALITY_MAP[item.rune.qualityId]
    local series = RuneConfig.SERIES_MAP[item.rune.seriesId]
    local qName = quality and quality.name or "?"
    local sName = series and series.name or "?"
    return true, "获得" .. qName .. sName .. "符文！"
end

--- 是否有可购买的商品（红点用）
---@return boolean
function RuneShopData.HasAvailable()
    local data = ensureToday()
    local curCount, cap = RuneData.GetBagCapacity()
    if curCount >= cap then return false end

    for _, item in ipairs(data.items) do
        if not item.bought and RuneShopData.CanAfford(item.rune.qualityId) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry
-- ============================================================================

SaveRegistry.Register("runeShop", {
    group = "meta_game",
    order = 71,
    serialize = function()
        return HeroData.runeShop
    end,
    deserialize = function(saved)
        HeroData.runeShop = saved or nil
    end,
})

return RuneShopData
