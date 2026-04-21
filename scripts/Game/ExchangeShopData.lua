-- Game/ExchangeShopData.lua
-- 兑换商店数据模块：用暗影精粹兑换宝箱、契约券、材料、碎片箱等
-- 每种商品有每日限购次数，次日重置

local Config   = require("Game.Config")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")
local TodayKey = require("Game.DateUtil").TodayKey

local ExchangeShopData = {}

-- ============================================================================
-- 商品定义
-- ============================================================================

---@class ExchangeShopItem
---@field id string          唯一标识
---@field name string        显示名称
---@field icon string        货币/物品 ID（用于 RewardIcon）
---@field cost number        暗影精粹价格
---@field amount number      每次获得数量
---@field reward table       奖励 { type, id, amount }
---@field dailyLimit number  每日限购次数（0=不限）
---@field tag? string        标签（如 "热门"、"超值"）
---@field tagColor? table    标签颜色

ExchangeShopData.SHOP_ITEMS = {
    -- 宝箱类
    {
        id = "bronze_chest_x2",
        name = "青铜宝箱×2",
        icon = "bronze_chest",
        cost = 200,
        amount = 2,
        reward = { type = "chest", id = "bronze", amount = 2 },
        dailyLimit = 1,
        discount = "5折",
    },
    {
        id = "gold_chest_x1",
        name = "黄金宝箱×1",
        icon = "gold_chest",
        cost = 200,
        amount = 1,
        reward = { type = "chest", id = "gold", amount = 1 },
        dailyLimit = 1,
        discount = "7折",
    },
    {
        id = "platinum_chest_x1",
        name = "铂金宝箱×1",
        icon = "platinum_chest",
        cost = 500,
        amount = 1,
        reward = { type = "chest", id = "platinum", amount = 1 },
        dailyLimit = 1,
        discount = "8折",
    },
    -- 材料类
    {
        id = "devour_stone_x200",
        name = "噬魂石×200",
        icon = "devour_stone",
        cost = 240,
        amount = 200,
        reward = { type = "currency", id = "devour_stone", amount = 200 },
        dailyLimit = 1,
    },
    {
        id = "forge_iron_x300",
        name = "锻魂铁×300",
        icon = "forge_iron",
        cost = 200,
        amount = 300,
        reward = { type = "currency", id = "forge_iron", amount = 300 },
        dailyLimit = 1,
    },
    -- 契约券类
    {
        id = "void_pact_x10",
        name = "虚空契约×10",
        icon = "void_pact",
        cost = 2400,
        amount = 10,
        reward = { type = "currency", id = "void_pact", amount = 10 },
        dailyLimit = 1,
        discount = "8折",
    },
    {
        id = "frost_pact_x10",
        name = "霜誓契约×10",
        icon = "frost_pact",
        cost = 2400,
        amount = 10,
        reward = { type = "currency", id = "frost_pact", amount = 10 },
        dailyLimit = 1,
        discount = "8折",
    },
    -- 碎片箱类
    {
        id = "ur_shard_random_x2",
        name = "随机UR碎片箱×2",
        icon = "random_ur_shard_box",
        cost = 400,
        amount = 2,
        reward = { type = "item", id = "random_ur_shard_box", amount = 2 },
        dailyLimit = 1,
    },
    {
        id = "ssr_shard_random_x5",
        name = "随机SSR碎片箱×5",
        icon = "ssr_shard_random_box",
        cost = 300,
        amount = 5,
        reward = { type = "item", id = "ssr_shard_random_box", amount = 5 },
        dailyLimit = 1,
    },
    {
        id = "r_shard_random_x1",
        name = "随机R碎片箱×1",
        icon = "r_shard_random_box",
        cost = 200,
        amount = 1,
        reward = { type = "item", id = "r_shard_random_box", amount = 1 },
        dailyLimit = 1,
    },
    -- 淬炼类
    {
        id = "pale_jade_x800",
        name = "粹玉×800",
        icon = "pale_jade",
        cost = 1600,
        amount = 800,
        reward = { type = "currency", id = "pale_jade", amount = 800 },
        dailyLimit = 1,
    },
    {
        id = "rainbow_jade_x1",
        name = "封魂玉×1",
        icon = "rainbow_jade",
        cost = 500,
        amount = 1,
        reward = { type = "currency", id = "rainbow_jade", amount = 1 },
        dailyLimit = 1,
    },
}

-- ============================================================================
-- 数据存取（购买记录存入 HeroData.exchangeShop）
-- ============================================================================

--- 获取今日日期字符串
---@return string
local function getTodayKey()
    return TodayKey()
end

--- 获取购买记录表（懒初始化）
---@return table
local function getRecords()
    if not HeroData.exchangeShop then
        HeroData.exchangeShop = { day = getTodayKey(), bought = {} }
    end
    -- 跨日重置
    local today = getTodayKey()
    if HeroData.exchangeShop.day ~= today then
        HeroData.exchangeShop = { day = today, bought = {} }
    end
    return HeroData.exchangeShop
end

--- 获取今日已购买次数
---@param itemId string
---@return number
function ExchangeShopData.GetBoughtCount(itemId)
    local rec = getRecords()
    return rec.bought[itemId] or 0
end

--- 获取商品剩余可购买次数
---@param itemId string
---@return number  -1=无限
function ExchangeShopData.GetRemaining(itemId)
    for _, item in ipairs(ExchangeShopData.SHOP_ITEMS) do
        if item.id == itemId then
            if item.dailyLimit <= 0 then return -1 end
            return math.max(0, item.dailyLimit - ExchangeShopData.GetBoughtCount(itemId))
        end
    end
    return 0
end

--- 执行购买
---@param itemId string
---@return boolean success
---@return string msg
function ExchangeShopData.Purchase(itemId)
    local item
    for _, it in ipairs(ExchangeShopData.SHOP_ITEMS) do
        if it.id == itemId then item = it; break end
    end
    if not item then return false, "商品不存在" end

    -- 检查限购
    if item.dailyLimit > 0 then
        local bought = ExchangeShopData.GetBoughtCount(itemId)
        if bought >= item.dailyLimit then
            return false, "今日已达购买上限"
        end
    end

    -- 检查暗影精粹
    if not Currency.Has("shadow_essence", item.cost) then
        return false, "暗影精粹不足（需要" .. item.cost .. "）"
    end

    -- 扣费
    Currency.Spend("shadow_essence", item.cost)

    -- 发放奖励
    Currency.GrantReward(item.reward)

    -- 记录购买次数
    local rec = getRecords()
    rec.bought[itemId] = (rec.bought[itemId] or 0) + 1

    -- 立即保存（不可逆消费操作）
    HeroData.Save(true)

    -- 构建奖励展示列表（供 RewardDisplay 使用）
    local iconImg = Currency.GetImage(item.icon)
    local rewards = {
        { icon = iconImg, name = item.name, amount = item.amount },
    }

    return true, "兑换成功！获得" .. item.name, rewards
end

--- 获取今日已刷新次数
---@return number
function ExchangeShopData.GetTodayRefreshCount()
    local rec = getRecords()
    return rec.refreshCount or 0
end

--- 记录一次刷新
function ExchangeShopData.RecordRefresh()
    local rec = getRecords()
    rec.refreshCount = (rec.refreshCount or 0) + 1
    HeroData.Save(true)
end

--- 重置所有商品购买记录（刷新商店后调用）
function ExchangeShopData.ResetPurchases()
    local rec = getRecords()
    rec.bought = {}
    HeroData.Save(true)
end

--- 是否有可购买的商品（用于红点提示）
---@return boolean
function ExchangeShopData.HasAvailable()
    local essence = Currency.Get("shadow_essence")
    for _, item in ipairs(ExchangeShopData.SHOP_ITEMS) do
        if essence >= item.cost then
            if item.dailyLimit <= 0 or ExchangeShopData.GetBoughtCount(item.id) < item.dailyLimit then
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("exchangeShop", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.exchangeShop
    end,
    deserialize = function(saved, _saveData)
        HeroData.exchangeShop = saved or nil
    end,
})

return ExchangeShopData
