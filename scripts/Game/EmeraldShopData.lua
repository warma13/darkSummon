-- Game/EmeraldShopData.lua
-- 翠影秘境·兑换商店 — 用翠影凭证兑换翎嫣招募券、碎片、资源等
-- 活动结束后翠影凭证清零，商品有活动期间总限购
-- 经济模型：6次/日 × 平均~515凭证 ≈ 3090/日，30天总产出 ≈ 92700
-- 清空商店总需 84200 凭证，留有 ~10% 余量

local Config   = require("Game.Config")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local Toast    = require("Game.Toast")
local SaveRegistry = require("Game.SaveRegistry")

local EmeraldShop = {}

--- 翠影凭证货币 ID
local CURRENCY_ID = "emerald_token"

-- ============================================================================
-- 商品定义（4 大类）
-- 限购次数为活动期间总限购（非每日重置）
-- ============================================================================

EmeraldShop.CATEGORIES = {
    { id = "core",     name = "核心道具",   color = { 100, 220, 140 } },
    { id = "general",  name = "通用资源",   color = { 180, 180, 220 } },
    { id = "rare",     name = "稀有道具",   color = { 220, 180, 60 } },
    { id = "extra",    name = "其他",       color = { 160, 160, 180 } },
}

EmeraldShop.SHOP_ITEMS = {
    -- ═══════════ 核心道具 ═══════════
    -- 翎嫣之誓: 800凭证/10抽 × 60次 = 48000凭证（30天共600抽，每日≈20抽）
    {
        id = "linyan_oath_x10",
        category = "core",
        name = "翎嫣之誓×10",
        icon = "linyan_oath",
        cost = 800,
        amount = 10,
        reward = { type = "currency", id = "linyan_oath", amount = 10 },
        limit = 60,
        tag = "每日≈20抽",
        tagColor = { 100, 220, 140 },
    },
    -- 翎嫣碎片: 500凭证/10碎片 × 30次 = 15000凭证（30天共300碎片，每日≈10个）
    {
        id = "linyan_shard_x10",
        category = "core",
        name = "翎嫣碎片×10",
        icon = "linyan_oath",
        cost = 500,
        amount = 10,
        reward = { type = "fragment", id = "nature_elf", amount = 10 },
        limit = 30,
        tag = "每日≈10个",
        tagColor = { 220, 180, 60 },
    },

    -- ═══════════ 通用资源 ═══════════
    -- 冥晶百万级: 200凭证/100万 × 30次 = 6000凭证（总3000万冥晶）
    {
        id = "nether_crystal_x1m",
        category = "general",
        name = "冥晶×100万",
        icon = "nether_crystal",
        cost = 200,
        amount = 1000000,
        reward = { type = "currency", id = "nether_crystal", amount = 1000000 },
        limit = 30,
    },
    {
        id = "void_pact_x10",
        category = "general",
        name = "虚空契约×10",
        icon = "void_pact",
        cost = 700,
        amount = 10,
        reward = { type = "currency", id = "void_pact", amount = 10 },
        limit = 8,
    },
    {
        id = "devour_stone_x1000",
        category = "general",
        name = "噬魂石×1000",
        icon = "devour_stone",
        cost = 200,
        amount = 1000,
        reward = { type = "currency", id = "devour_stone", amount = 1000 },
        limit = 8,
    },
    {
        id = "forge_iron_x1000",
        category = "general",
        name = "锻魂铁×1000",
        icon = "forge_iron",
        cost = 200,
        amount = 1000,
        reward = { type = "currency", id = "forge_iron", amount = 1000 },
        limit = 8,
    },

    -- ═══════════ 稀有道具 ═══════════
    {
        id = "ur_shard_box_x1",
        category = "rare",
        name = "万能UR碎片箱×1",
        icon = "ur_shard_box",
        cost = 300,
        amount = 1,
        reward = { type = "item", id = "ur_shard_box", amount = 1 },
        limit = 3,
        tag = "稀有",
        tagColor = { 255, 200, 50 },
    },
    {
        id = "pale_jade_x500",
        category = "rare",
        name = "粹玉×500",
        icon = "pale_jade",
        cost = 250,
        amount = 500,
        reward = { type = "currency", id = "pale_jade", amount = 500 },
        limit = 5,
    },
    {
        id = "shadow_essence_x500",
        category = "rare",
        name = "暗影精粹×500",
        icon = "shadow_essence",
        cost = 250,
        amount = 500,
        reward = { type = "currency", id = "shadow_essence", amount = 500 },
        limit = 5,
    },

    -- ═══════════ 其他 ═══════════
    {
        id = "gold_chest_x1",
        category = "extra",
        name = "黄金宝箱×1",
        icon = "gold_chest",
        cost = 150,
        amount = 1,
        reward = { type = "chest", id = "gold", amount = 1 },
        limit = 10,
    },
    {
        id = "platinum_chest_x1",
        category = "extra",
        name = "铂金宝箱×1",
        icon = "platinum_chest",
        cost = 300,
        amount = 1,
        reward = { type = "chest", id = "platinum", amount = 1 },
        limit = 5,
    },
}

-- 预构建 ID 映射
local ITEM_MAP = {}
for _, item in ipairs(EmeraldShop.SHOP_ITEMS) do
    ITEM_MAP[item.id] = item
end

-- ============================================================================
-- 数据存取（购买记录存入 HeroData.emeraldShop）
-- ============================================================================

--- 获取购买记录表
---@return table
local function getRecords()
    if not HeroData.emeraldShop then
        HeroData.emeraldShop = { bought = {} }
    end
    return HeroData.emeraldShop
end

--- 获取已购买次数
---@param itemId string
---@return number
function EmeraldShop.GetBoughtCount(itemId)
    local rec = getRecords()
    return rec.bought[itemId] or 0
end

--- 获取剩余可购买次数
---@param itemId string
---@return number (-1=无限)
function EmeraldShop.GetRemaining(itemId)
    local item = ITEM_MAP[itemId]
    if not item then return 0 end
    if item.limit <= 0 then return -1 end
    return math.max(0, item.limit - EmeraldShop.GetBoughtCount(itemId))
end

--- 获取指定分类的商品列表
---@param categoryId string
---@return table[]
function EmeraldShop.GetItemsByCategory(categoryId)
    local items = {}
    for _, item in ipairs(EmeraldShop.SHOP_ITEMS) do
        if item.category == categoryId then
            items[#items + 1] = item
        end
    end
    return items
end

--- 执行购买
---@param itemId string
---@return boolean success
---@return string msg
---@return table|nil rewards (供 RewardDisplay)
function EmeraldShop.Purchase(itemId)
    local item = ITEM_MAP[itemId]
    if not item then return false, "商品不存在", nil end

    -- 检查限购
    if item.limit > 0 then
        local bought = EmeraldShop.GetBoughtCount(itemId)
        if bought >= item.limit then
            return false, "已达购买上限", nil
        end
    end

    -- 检查翠影凭证
    if not Currency.Has(CURRENCY_ID, item.cost) then
        return false, "翠影凭证不足（需要" .. item.cost .. "）", nil
    end

    -- 扣费
    Currency.Spend(CURRENCY_ID, item.cost)

    -- 发放奖励
    Currency.GrantReward(item.reward)

    -- 记录购买
    local rec = getRecords()
    rec.bought[itemId] = (rec.bought[itemId] or 0) + 1

    -- 保存
    HeroData.Save(true)

    -- 构建奖励展示
    local iconImg = Currency.GetImage(item.icon)
    local rewards = {
        { icon = iconImg, name = item.name, amount = item.amount },
    }

    return true, "兑换成功！获得" .. item.name, rewards
end

--- 获取清空商店所需的总凭证数
---@return number
function EmeraldShop.GetTotalCostToClear()
    local total = 0
    for _, item in ipairs(EmeraldShop.SHOP_ITEMS) do
        total = total + item.cost * item.limit
    end
    return total
end

--- 活动结束清空翠影凭证
function EmeraldShop.OnEventEnd()
    local balance = Currency.Get(CURRENCY_ID)
    if balance > 0 then
        Currency.Set(CURRENCY_ID, 0)
        Toast.Show("活动结束，翠影凭证已清零", { 255, 200, 80 })
        print("[EmeraldShop] Event ended, cleared " .. balance .. " emerald tokens")
    end
end

--- 是否有可购买的商品（红点提示）
---@return boolean
function EmeraldShop.HasAvailable()
    local balance = Currency.Get(CURRENCY_ID)
    for _, item in ipairs(EmeraldShop.SHOP_ITEMS) do
        if balance >= item.cost and EmeraldShop.GetRemaining(item.id) ~= 0 then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

SaveRegistry.Register("emeraldShop", {
    group = "meta_game",
    order = 86,
    initDefault = function()
        HeroData.emeraldShop = nil
    end,
    serialize = function()
        return HeroData.emeraldShop
    end,
    deserialize = function(saved, _saveData)
        HeroData.emeraldShop = saved or nil

        -- 迁移：linyan_shard 误存为货币 → 转移到 nature_elf 碎片
        local stray = HeroData.currencies and HeroData.currencies["linyan_shard"]
        if stray and stray > 0 then
            local h = HeroData.heroes and HeroData.heroes["nature_elf"]
            if h then
                h.fragments = h.fragments + stray
                print("[EmeraldShop] Migrated " .. stray .. " linyan_shard → nature_elf fragments")
            end
            HeroData.currencies["linyan_shard"] = nil
        end
    end,
})

return EmeraldShop
