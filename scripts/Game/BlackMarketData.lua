-- Game/BlackMarketData.lua
-- 黑市商店：使用暗影精粹购买限量礼包

local Currency     = require("Game.Currency")
local HeroData     = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")
local Toast        = require("Game.Toast")
local WAD          = require("Game.WeeklyActivityData")

local BMD = {}

-- ============================================================================
-- 黑市礼包配置（11个礼包，按参考图排列）
-- ============================================================================

BMD.PACKAGES = {
    {
        id    = "bm_welfare",
        name  = "黑市福利",
        cost  = 0,
        limit = 1,
        tag   = "免费",
        rewards = {
            { type = "currency", id = "shadow_essence", amount = 500 },
        },
    },
    {
        id    = "bm_welcome",
        name  = "黑市见面礼",
        cost  = 600,
        limit = 1,
        rewards = {
            { type = "item", id = "recruit_ticket_select_box", amount = 5 },
        },
    },
    {
        id    = "bm_surprise",
        name  = "黑市惊喜礼",
        cost  = 1200,
        limit = 1,
        rewards = {
            { type = "item", id = "recruit_ticket_select_box", amount = 10 },
        },
    },
    {
        id    = "bm_basic",
        name  = "初级黑市包",
        cost  = 2500,
        limit = 1,
        rewards = {
            { type = "currency", id = "devour_stone", amount = 6000 },
        },
    },
    {
        id    = "bm_mid",
        name  = "中级黑市包",
        cost  = 5000,
        limit = 1,
        rewards = {
            { type = "chest", id = "wood",     amount = 10 },
            { type = "chest", id = "bronze",   amount = 10 },
            { type = "chest", id = "gold",     amount = 10 },
            { type = "chest", id = "platinum", amount = 10 },
        },
    },
    {
        id    = "bm_nightmare",
        name  = "遗物精华包",
        cost  = 5000,
        limit = 2,
        rewards = {
            { type = "currency", id = "relic_essence", amount = 5000 },
        },
    },
    {
        id    = "bm_high",
        name  = "高级黑市包",
        cost  = 8000,
        limit = 1,
        rewards = {
            { type = "item", id = "recruit_ticket_select_box", amount = 40 },
            { type = "item", id = "random_ur_shard_box",       amount = 50 },
        },
    },
    {
        id    = "bm_top_forge",
        name  = "遗物碎片包",
        cost  = 12000,
        limit = 1,
        rewards = {
            { type = "item", id = "random_relic_shard_box", amount = 150 },
        },
    },
    {
        id    = "bm_premium",
        name  = "特级黑市包",
        cost  = 20000,
        limit = 4,
        rewards = {
            { type = "item",  id = "random_ur_shard_box", amount = 150 },
            { type = "item",  id = "ur_shard_box",        amount = 40 },
            { type = "chest", id = "diamond",             amount = 2 },
        },
    },
    {
        id    = "bm_pale_jade",
        name  = "神话符文包",
        cost  = 20000,
        limit = 1,
        rewards = {
            { type = "item", id = "random_mythic_rune_box", amount = 3 },
        },
    },
    {
        id    = "bm_shadow_orb",
        name  = "暗影宝珠包",
        cost  = 25000,
        limit = 1,
        rewards = {
            { type = "currency", id = "shadow_orb", amount = 10 },
        },
    },
}

-- ============================================================================
-- 数据访问
-- ============================================================================

---@return table
function BMD.EnsureData()
    if not HeroData.blackMarketData then
        HeroData.blackMarketData = {
            weekStart = WAD.GetCurrentWeekStart(),
            purchased = {},   -- { [packageId] = count }
        }
    end
    local data = HeroData.blackMarketData
    if not data.purchased then data.purchased = {} end
    return data
end

--- 检查周重置
local function CheckWeekReset(data)
    local expected = WAD.GetCurrentWeekStart()
    if data.weekStart ~= expected then
        data.weekStart = expected
        data.purchased = {}
        print("[BlackMarket] Week reset")
    end
end

--- 活动是否激活（仅在市场周生效）
---@return boolean
function BMD.IsActive()
    return WAD.IsActive() and WAD.GetCurrentWeekType() == "market"
end

-- ============================================================================
-- 购买
-- ============================================================================

--- 获取某礼包已购买次数
---@param packageId string
---@return number
function BMD.GetPurchaseCount(packageId)
    local data = BMD.EnsureData()
    CheckWeekReset(data)
    return data.purchased[packageId] or 0
end

--- 购买黑市礼包
---@param index number  PACKAGES 的索引
---@return boolean success, string msg
function BMD.Purchase(index)
    if not BMD.IsActive() then return false, "活动未开放" end
    local data = BMD.EnsureData()
    CheckWeekReset(data)

    local pkg = BMD.PACKAGES[index]
    if not pkg then return false, "无效商品" end

    -- 检查限购
    local bought = data.purchased[pkg.id] or 0
    if pkg.limit > 0 and bought >= pkg.limit then
        return false, "已达购买上限"
    end

    -- 检查 & 扣除暗影精粹（免费礼包跳过）
    if pkg.cost > 0 then
        if not Currency.Has("shadow_essence", pkg.cost) then
            return false, "暗影精粹不足（需要" .. pkg.cost .. "）"
        end
        Currency.Spend("shadow_essence", pkg.cost)
    end

    data.purchased[pkg.id] = bought + 1

    -- 直接发放奖励
    for _, reward in ipairs(pkg.rewards) do
        Currency.GrantReward(reward)
    end

    print("[BlackMarket] Purchased " .. pkg.id .. " (count: " .. (bought + 1) .. ")")
    HeroData.Save()

    -- 构建奖励展示列表
    local Config = require("Game.Config")
    local displayRewards = {}
    for _, reward in ipairs(pkg.rewards) do
        local rName = reward.id
        local rIcon = reward.id
        local cdef = Config.CURRENCY[reward.id]
        if cdef then
            rName = cdef.name or reward.id
            rIcon = cdef.image or reward.id
        else
            -- 尝试从 ITEM_DEFS 获取名称
            local okI, InvD = pcall(require, "Game.InventoryData")
            if okI and InvD.ITEM_DEFS and InvD.ITEM_DEFS[reward.id] then
                rName = InvD.ITEM_DEFS[reward.id].name or reward.id
            end
            -- 尝试从 Config_Heroes 获取图标
            local heroConf = Config.CURRENCY[reward.id]
            if heroConf and heroConf.image then
                rIcon = heroConf.image
            end
        end
        if reward.type == "chest" then
            rName = (cdef and cdef.name or reward.id) .. "宝箱"
        end
        displayRewards[#displayRewards + 1] = {
            icon = rIcon,
            name = rName,
            amount = reward.amount,
        }
    end

    return true, "购买成功", displayRewards
end

--- 是否有可购买的礼包（红点）
---@return boolean
function BMD.HasAffordable()
    if not BMD.IsActive() then return false end
    local data = BMD.EnsureData()
    CheckWeekReset(data)
    local tokens = Currency.Get("shadow_essence")
    for _, pkg in ipairs(BMD.PACKAGES) do
        local bought = data.purchased[pkg.id] or 0
        local canBuy = (pkg.limit == 0 or bought < pkg.limit)
        if canBuy and tokens >= pkg.cost then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

SaveRegistry.Register("blackMarketData", {
    group = "meta_game",
    order = 75,
    serialize = function()
        return HeroData.blackMarketData
    end,
    deserialize = function(saved, _saveData)
        HeroData.blackMarketData = saved or nil
    end,
})

return BMD
