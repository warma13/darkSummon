-- Game/DropEventData.lua
-- 掉落活动：每日看广告领取暗烬碎片+暗影精粹（11份，由少到多）
-- 第1份免费，后续看广告解锁
-- 每周广告进度条：累计看60次得暗影精粹

local HeroData     = require("Game.HeroData")
local Currency     = require("Game.Currency")
local WAD          = require("Game.WeeklyActivityData")
local SaveRegistry = require("Game.SaveRegistry")

local DED = {}

-- ============================================================================
-- 活动专属道具 ID
-- ============================================================================

DED.TOKEN_ID   = "dark_ember_shard"   -- 暗烬碎片（活动专属掉落道具）
DED.TOKEN_NAME = "暗烬碎片"

-- ============================================================================
-- 每日掉落配置（11份，由少到多，总计 2560 暗烬碎片 + 10000 暗影精粹）
-- 第1份免费，后续看广告
-- ============================================================================

--- 暗烬碎片分配（由少到多，总 2560）:
--- 80 + 100 + 120 + 160 + 200 + 220 + 260 + 300 + 320 + 360 + 440 = 2560
--- 暗影精粹分配（由少到多，总 10000）:
--- 400 + 500 + 600 + 700 + 800 + 900 + 1000 + 1050 + 1100 + 1350 + 1600 = 10000
DED.DAILY_REWARDS = {
    { token = 80,   essence = 400,  free = true },   -- 第1份：免费
    { token = 100,  essence = 500  },                 -- 第2份（广告）
    { token = 120,  essence = 600  },                 -- 第3份
    { token = 160,  essence = 700  },                 -- 第4份
    { token = 200,  essence = 800  },                 -- 第5份
    { token = 220,  essence = 900  },                 -- 第6份
    { token = 260,  essence = 1000 },                 -- 第7份
    { token = 300,  essence = 1050 },                 -- 第8份
    { token = 320,  essence = 1100 },                 -- 第9份
    { token = 360,  essence = 1350 },                 -- 第10份
    { token = 440,  essence = 1600 },                 -- 第11份
}

DED.MAX_DAILY = #DED.DAILY_REWARDS  -- 11

--- 每周广告进度里程碑（累计一周，每10次广告领1000暗影精粹，共60次6000暗影精粹）
DED.WEEKLY_MILESTONES = {
    { threshold = 10, rewardAmount = 1000 },
    { threshold = 20, rewardAmount = 1000 },
    { threshold = 30, rewardAmount = 1000 },
    { threshold = 40, rewardAmount = 1000 },
    { threshold = 50, rewardAmount = 1000 },
    { threshold = 60, rewardAmount = 1000 },
}

-- ============================================================================
-- 换购商店配置（用暗烬碎片兑换物品）
-- ============================================================================

DED.SHOP_ITEMS = {
    -- 1: 超值大礼包（限购1）
    {
        id       = "shop_mega_bundle",
        name     = "超值大礼包",
        cost     = 7000,
        limit    = 1,
        rewards  = {
            { type = "item", id = "ur_shard_box",              amount = 100 },
            { type = "item", id = "random_ur_shard_box",       amount = 200 },
            { type = "item", id = "recruit_ticket_select_box", amount = 20 },
        },
    },
    -- 2: 随机UR碎片箱×20（限购1）
    {
        id       = "shop_random_ur_20",
        name     = "随机UR碎片箱×20",
        cost     = 800,
        limit    = 1,
        rewards  = {
            { type = "item", id = "random_ur_shard_box", amount = 20 },
        },
    },
    -- 3: 随机UR碎片箱×5（不限购）
    {
        id       = "shop_random_ur_5",
        name     = "随机UR碎片箱×5",
        cost     = 300,
        limit    = 0,
        rewards  = {
            { type = "item", id = "random_ur_shard_box", amount = 5 },
        },
    },
    -- 4: 招募自选包×1（不限购）
    {
        id       = "shop_recruit_select_1",
        name     = "招募自选包×1",
        cost     = 150,
        limit    = 0,
        rewards  = {
            { type = "item", id = "recruit_ticket_select_box", amount = 1 },
        },
    },
    -- 5: 深渊结晶×1（不限购）
    {
        id       = "shop_abyss_crystal_1",
        name     = "深渊结晶×1",
        cost     = 200,
        limit    = 0,
        rewards  = {
            { type = "currency", id = "abyss_crystal", amount = 1 },
        },
    },
    -- 6: 裂隙之尘×50（不限购）
    {
        id       = "shop_rift_dust",
        name     = "裂隙之尘×50",
        cost     = 100,
        limit    = 0,
        rewards  = {
            { type = "currency", id = "rift_dust", amount = 50 },
        },
    },
    -- 7: 噬魂石×500（不限购）
    {
        id       = "shop_devour_stone",
        name     = "噬魂石×500",
        cost     = 80,
        limit    = 0,
        rewards  = {
            { type = "currency", id = "devour_stone", amount = 500 },
        },
    },
    -- 8: 锻魂铁×200（不限购）
    {
        id       = "shop_forge_iron",
        name     = "锻魂铁×200",
        cost     = 60,
        limit    = 0,
        rewards  = {
            { type = "currency", id = "forge_iron", amount = 200 },
        },
    },
    -- 9: 虚空契约×5（不限购）
    {
        id       = "shop_void_pact",
        name     = "虚空契约×5",
        cost     = 120,
        limit    = 0,
        rewards  = {
            { type = "currency", id = "void_pact", amount = 5 },
        },
    },
    -- 10: 朽木宝箱（3分钟挂机收益，不限购）
    {
        id       = "shop_wood_chest_1",
        name     = "朽木宝箱×1",
        desc     = "开启获得3分钟挂机收益",
        cost     = 30,
        limit    = 0,
        rewards  = {
            { type = "chest", id = "wood", amount = 1 },
        },
    },
}

-- ============================================================================
-- 数据访问
-- ============================================================================

local TodayStr = require("Game.DateUtil").TodayStr

---@return table
function DED.EnsureData()
    if not HeroData.dropEventData then
        HeroData.dropEventData = {
            weekStart     = WAD.GetCurrentWeekStart(),
            tokens        = 0,            -- 暗烬碎片余额
            -- 每日领取
            dailyDate     = TodayStr(),
            dailyClaimed  = {},           -- { [1]=true, ... }
            dailyAdCount  = 0,            -- 今日已看广告次数
            -- 每周进度
            weeklyAdTotal = 0,            -- 本周累计广告次数
            weeklyClaimed = {},           -- { [1]=true, ... }
            -- 换购
            purchased     = {},           -- { [shopItemId] = count }
        }
    end
    local data = HeroData.dropEventData
    if not data.purchased then data.purchased = {} end
    if not data.dailyClaimed then data.dailyClaimed = {} end
    if not data.weeklyClaimed then data.weeklyClaimed = {} end
    return data
end

--- 检查周重置
local function CheckWeekReset(data)
    local expected = WAD.GetCurrentWeekStart()
    if data.weekStart ~= expected then
        data.weekStart     = expected
        data.tokens        = 0
        data.dailyDate     = TodayStr()
        data.dailyClaimed  = {}
        data.dailyAdCount  = 0
        data.weeklyAdTotal = 0
        data.weeklyClaimed = {}
        data.purchased     = {}
        print("[DropEvent] Week reset")
    end
end

--- 检查日重置
local function CheckDailyReset(data)
    local today = TodayStr()
    if data.dailyDate ~= today then
        data.dailyDate    = today
        data.dailyClaimed = {}
        data.dailyAdCount = 0
    end
end

--- 活动是否激活（仅在市场周生效）
---@return boolean
function DED.IsActive()
    return WAD.IsWeekValid() and WAD.GetCurrentWeekType() == "market"
end

-- ============================================================================
-- 暗烬碎片余额
-- ============================================================================

---@return number
function DED.GetTokens()
    local data = DED.EnsureData()
    CheckWeekReset(data)
    return data.tokens
end

--- 消费暗烬碎片
---@param amount number
---@return boolean
function DED.SpendTokens(amount)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    if data.tokens < amount then return false end
    data.tokens = data.tokens - amount
    return true
end

-- ============================================================================
-- 每日掉落领取（11份看广告）
-- ============================================================================

--- 获取今日已看广告次数
---@return number
function DED.GetDailyAdCount()
    local data = DED.EnsureData()
    CheckWeekReset(data)
    CheckDailyReset(data)
    return data.dailyAdCount
end

--- 某份是否已领取
---@param index number 1~11
---@return boolean
function DED.IsDailyClaimed(index)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    CheckDailyReset(data)
    return data.dailyClaimed[index] or false
end

--- 某份是否已解锁（第1份默认解锁，后续需前一份已领取）
---@param index number
---@return boolean
function DED.IsDailyUnlocked(index)
    if index == 1 then return true end
    return DED.IsDailyClaimed(index - 1)
end

--- 领取某份掉落奖励
---@param index number 1~11
---@param onDone function(success, msg)
function DED.ClaimDailyReward(index, onDone)
    if not DED.IsActive() then
        if onDone then onDone(false, "活动未开放") end
        return
    end
    local data = DED.EnsureData()
    CheckWeekReset(data)
    CheckDailyReset(data)

    if index < 1 or index > DED.MAX_DAILY then
        if onDone then onDone(false, "无效索引") end
        return
    end
    if data.dailyClaimed[index] then
        if onDone then onDone(false, "已领取") end
        return
    end
    if not DED.IsDailyUnlocked(index) then
        if onDone then onDone(false, "未解锁") end
        return
    end

    local reward = DED.DAILY_REWARDS[index]

    -- 免费奖励直接发放
    if reward.free then
        DED._ApplyReward(data, index, reward)
        if onDone then onDone(true) end
        return
    end

    -- 看广告
    local AdHelper = require("Game.AdHelper")
    AdHelper.ShowRewardAd(function()
        DED._ApplyReward(data, index, reward)
        if onDone then onDone(true) end
    end, function(reason)
        if onDone then onDone(false, reason) end
    end)
end

--- 发放奖励内部实现
function DED._ApplyReward(data, index, reward)
    -- 暗烬碎片加到活动余额
    if reward.token > 0 then
        data.tokens = data.tokens + reward.token
    end
    -- 暗影精粹直接发放
    if reward.essence > 0 then
        Currency.GrantReward({ type = "currency", id = "shadow_essence", amount = reward.essence }, "DropEvent")
    end

    data.dailyClaimed[index] = true
    data.dailyAdCount = data.dailyAdCount + 1

    -- 累加每周广告计数（免费不计入）
    if not reward.free then
        data.weeklyAdTotal = (data.weeklyAdTotal or 0) + 1
    end

    -- 立即保存
    local SlotSave = require("Game.SlotSaveSystem")
    if SlotSave.GetActiveSlot() > 0 then
        SlotSave.SaveNow()
    else
        HeroData.Save()
    end
end

-- ============================================================================
-- 每周广告进度（暗影精粹）
-- ============================================================================

--- 获取本周累计广告次数
---@return number
function DED.GetWeeklyAdTotal()
    local data = DED.EnsureData()
    CheckWeekReset(data)
    return data.weeklyAdTotal or 0
end

--- 某个里程碑是否可领取
---@param index number
---@return boolean
function DED.IsWeeklyClaimable(index)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    local m = DED.WEEKLY_MILESTONES[index]
    if not m then return false end
    return (data.weeklyAdTotal or 0) >= m.threshold and not (data.weeklyClaimed[index] or false)
end

--- 某个里程碑是否已领取
---@param index number
---@return boolean
function DED.IsWeeklyClaimed(index)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    return data.weeklyClaimed[index] or false
end

--- 领取每周里程碑
---@param index number
---@return boolean
function DED.ClaimWeeklyMilestone(index)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    local m = DED.WEEKLY_MILESTONES[index]
    if not m then return false end
    if (data.weeklyAdTotal or 0) < m.threshold then return false end
    if data.weeklyClaimed[index] then return false end

    Currency.GrantReward({ type = "currency", id = "shadow_essence", amount = m.rewardAmount }, "DropEventWeekly")
    data.weeklyClaimed[index] = true

    local SlotSave = require("Game.SlotSaveSystem")
    if SlotSave.GetActiveSlot() > 0 then
        SlotSave.SaveNow()
    else
        HeroData.Save()
    end
    return true
end

-- ============================================================================
-- 换购商店
-- ============================================================================

--- 获取某商品已购买次数
---@param shopItemId string
---@return number
function DED.GetPurchaseCount(shopItemId)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    return data.purchased[shopItemId] or 0
end

--- 购买换购商店物品
---@param shopIndex number  SHOP_ITEMS 的索引
---@param count? number     购买数量（默认1）
---@return boolean success, string msg
function DED.PurchaseShopItem(shopIndex, count)
    count = count or 1
    if count < 1 then return false, "数量无效" end
    if not DED.IsActive() then return false, "活动未开放" end
    local data = DED.EnsureData()
    CheckWeekReset(data)

    local item = DED.SHOP_ITEMS[shopIndex]
    if not item then return false, "无效商品" end

    local bought = data.purchased[item.id] or 0
    if item.limit > 0 then
        local remaining = item.limit - bought
        if remaining <= 0 then return false, "已达购买上限" end
        if count > remaining then return false, "超出剩余可购数量（剩" .. remaining .. "次）" end
    end

    local totalCost = item.cost * count
    if data.tokens < totalCost then
        return false, "暗烬碎片不足（需要" .. totalCost .. "）"
    end

    data.tokens = data.tokens - totalCost
    data.purchased[item.id] = bought + count

    -- 发放奖励（按数量倍数）
    for _, reward in ipairs(item.rewards) do
        local batchReward = { type = reward.type, id = reward.id, amount = reward.amount * count }
        Currency.GrantReward(batchReward, "DropEventShop")
    end

    print("[DropEvent] Purchased " .. item.id .. " x" .. count .. " (total: " .. (bought + count) .. ")")
    HeroData.Save()
    return true, "换购成功", item, count
end

--- 获取某商品最大可购买数量
---@param shopIndex number
---@return number
function DED.GetMaxPurchasable(shopIndex)
    local data = DED.EnsureData()
    CheckWeekReset(data)
    local item = DED.SHOP_ITEMS[shopIndex]
    if not item then return 0 end

    local bought = data.purchased[item.id] or 0
    -- 按余额计算
    local byTokens = item.cost > 0 and math.floor(data.tokens / item.cost) or 999
    -- 按限购计算
    if item.limit > 0 then
        local remaining = item.limit - bought
        return math.max(0, math.min(byTokens, remaining))
    end
    return math.max(0, math.min(byTokens, 999))
end

--- 是否有可领取的（红点）
---@return boolean
function DED.HasClaimable()
    if not DED.IsActive() then return false end
    local data = DED.EnsureData()
    CheckWeekReset(data)
    CheckDailyReset(data)

    -- 检查每日奖励
    for i = 1, DED.MAX_DAILY do
        if DED.IsDailyUnlocked(i) and not (data.dailyClaimed[i] or false) then
            return true
        end
    end

    -- 检查每周进度
    for i, m in ipairs(DED.WEEKLY_MILESTONES) do
        if (data.weeklyAdTotal or 0) >= m.threshold and not (data.weeklyClaimed[i] or false) then
            return true
        end
    end

    return false
end

--- 换购商店是否有可购买项（红点）
---@return boolean
function DED.HasAffordableItem()
    if not DED.IsActive() then return false end
    local data = DED.EnsureData()
    CheckWeekReset(data)
    for _, item in ipairs(DED.SHOP_ITEMS) do
        local bought = data.purchased[item.id] or 0
        local canBuy = (item.limit == 0 or bought < item.limit)
        if canBuy and data.tokens >= item.cost then
            return true
        end
    end
    return false
end

-- 兼容旧接口
DED.HasClaimableDay = DED.HasClaimable
DED.IsDayClaimed = DED.IsDailyClaimed
DED.GetCurrentDay = function() return 1 end -- 不再有天数概念

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

SaveRegistry.Register("dropEventData", {
    group = "meta_game",
    order = 74,
    serialize = function()
        return HeroData.dropEventData
    end,
    deserialize = function(saved, _saveData)
        HeroData.dropEventData = saved or nil
    end,
})

return DED
