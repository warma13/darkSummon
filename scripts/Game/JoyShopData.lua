-- Game/JoyShopData.lua
-- 欢乐商店数据模块：欢乐币获取（每日首局 + 排行结算）+ 兑换商品
-- 每日重置购买记录与首局/结算标记

local Currency     = require("Game.Currency")
local HeroData     = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")
local TodayKey     = require("Game.DateUtil").TodayKey

local JoyShopData = {}

-- ============================================================================
-- 常量
-- ============================================================================

--- 每日首局奖励欢乐币数量
local FIRST_GAME_REWARD = 30

--- 排行榜结算奖励梯度
local RANK_REWARDS = {
    { maxRank = 1,  amount = 100 },  -- 第1名
    { maxRank = 3,  amount = 60 },   -- 第2-3名
    { maxRank = 10, amount = 30 },   -- 第4-10名
    { maxRank = 20, amount = 15 },   -- 第11-20名
}
local RANK_PARTICIPATE_REWARD = 5    -- 参与但未上榜

-- ============================================================================
-- 商品定义
-- ============================================================================

---@class JoyShopItem
---@field id string
---@field name string
---@field icon string
---@field cost number
---@field amount number
---@field reward table
---@field dailyLimit number

JoyShopData.SHOP_ITEMS = {
    -- ── 礼包 / 福袋 ──────────────────────────────────────
    {
        id = "nether_crystal_pack_x1",
        name = "冥晶礼包×1",
        icon = "nether_crystal_pack",
        cost = 15,
        amount = 1,
        reward = { type = "item", id = "nether_crystal_pack", amount = 1 },
        dailyLimit = 2,
    },
    {
        id = "shadow_essence_bag_x1",
        name = "暗影精粹福袋×1",
        icon = "shadow_essence_bag",
        cost = 25,
        amount = 1,
        reward = { type = "item", id = "shadow_essence_bag", amount = 1 },
        dailyLimit = 1,
    },
    -- ── 招募 / 碎片 ──────────────────────────────────────
    {
        id = "recruit_ticket_x3",
        name = "招募券自选包×3",
        icon = "recruit_ticket_select_box",
        cost = 35,
        amount = 3,
        reward = { type = "item", id = "recruit_ticket_select_box", amount = 3 },
        dailyLimit = 1,
    },
    {
        id = "ur_shard_box_x1",
        name = "万能UR碎片箱×1",
        icon = "ur_shard_box",
        cost = 60,
        amount = 1,
        reward = { type = "item", id = "ur_shard_box", amount = 1 },
        dailyLimit = 1,
    },
    -- ── 符文材料 ──────────────────────────────────────────
    {
        id = "abyss_crystal_x5",
        name = "深渊结晶×5",
        icon = "abyss_crystal",
        cost = 30,
        amount = 5,
        reward = { type = "currency", id = "abyss_crystal", amount = 5 },
        dailyLimit = 1,
    },
    {
        id = "random_mythic_rune_x1",
        name = "随机神话符文箱×1",
        icon = "random_mythic_rune_box",
        cost = 80,
        amount = 1,
        reward = { type = "item", id = "random_mythic_rune_box", amount = 1 },
        dailyLimit = 1,
    },
    {
        id = "rift_dust_x50",
        name = "裂隙之尘×50",
        icon = "rift_dust",
        cost = 20,
        amount = 50,
        reward = { type = "currency", id = "rift_dust", amount = 50 },
        dailyLimit = 2,
    },
    -- ── 基础材料 ──────────────────────────────────────────
    {
        id = "forge_iron_x300",
        name = "锻魂铁×300",
        icon = "forge_iron",
        cost = 15,
        amount = 300,
        reward = { type = "currency", id = "forge_iron", amount = 300 },
        dailyLimit = 2,
    },
    {
        id = "devour_stone_x200",
        name = "噬魂石×200",
        icon = "devour_stone",
        cost = 15,
        amount = 200,
        reward = { type = "currency", id = "devour_stone", amount = 200 },
        dailyLimit = 2,
    },
    -- ── 宝箱 ─────────────────────────────────────────────
    {
        id = "bronze_chest_x2",
        name = "青铜宝箱×2",
        icon = "bronze_chest",
        cost = 10,
        amount = 2,
        reward = { type = "chest", id = "bronze", amount = 2 },
        dailyLimit = 3,
    },
    {
        id = "gold_chest_x1",
        name = "黄金宝箱×1",
        icon = "gold_chest",
        cost = 25,
        amount = 1,
        reward = { type = "chest", id = "gold", amount = 1 },
        dailyLimit = 2,
    },
    {
        id = "platinum_chest_x1",
        name = "铂金宝箱×1",
        icon = "platinum_chest",
        cost = 50,
        amount = 1,
        reward = { type = "chest", id = "platinum", amount = 1 },
        dailyLimit = 1,
    },
}

-- ============================================================================
-- 数据存取（购买记录存入 HeroData.joyShop）
-- ============================================================================

--- 获取/初始化记录（跨日重置）
---@return table
local function getRecords()
    if not HeroData.joyShop then
        HeroData.joyShop = { day = TodayKey(), firstGameDone = false, settlementDone = false, bought = {} }
    end
    local today = TodayKey()
    if HeroData.joyShop.day ~= today then
        HeroData.joyShop = { day = today, firstGameDone = false, settlementDone = false, bought = {} }
    end
    return HeroData.joyShop
end

--- 获取今日已购买次数
---@param itemId string
---@return number
function JoyShopData.GetBoughtCount(itemId)
    local rec = getRecords()
    return rec.bought[itemId] or 0
end

--- 获取剩余可购买次数
---@param itemId string
---@return number
function JoyShopData.GetRemaining(itemId)
    for _, item in ipairs(JoyShopData.SHOP_ITEMS) do
        if item.id == itemId then
            if item.dailyLimit <= 0 then return -1 end
            return math.max(0, item.dailyLimit - JoyShopData.GetBoughtCount(itemId))
        end
    end
    return 0
end

--- 执行购买
---@param itemId string
---@return boolean success
---@return string msg
---@return table|nil rewards
function JoyShopData.Purchase(itemId)
    local item
    for _, it in ipairs(JoyShopData.SHOP_ITEMS) do
        if it.id == itemId then item = it; break end
    end
    if not item then return false, "商品不存在" end

    -- 检查限购
    if item.dailyLimit > 0 then
        local bought = JoyShopData.GetBoughtCount(itemId)
        if bought >= item.dailyLimit then
            return false, "今日已达购买上限"
        end
    end

    -- 检查欢乐币
    if not Currency.Has("joy_coin", item.cost) then
        return false, "欢乐币不足（需要" .. item.cost .. "）"
    end

    -- 扣费
    Currency.Spend("joy_coin", item.cost)

    -- 发放奖励
    Currency.GrantReward(item.reward, "JoyShop")

    -- 记录购买次数
    local rec = getRecords()
    rec.bought[itemId] = (rec.bought[itemId] or 0) + 1

    -- 立即保存
    HeroData.Save(true)

    local iconImg = Currency.GetImage(item.icon)
    local rewards = {
        { icon = iconImg, name = item.name, amount = item.amount },
    }

    return true, "兑换成功！获得" .. item.name, rewards
end

-- ============================================================================
-- 每日首局奖励
-- ============================================================================

--- 今日首局是否已完成
---@return boolean
function JoyShopData.IsFirstGameDone()
    local rec = getRecords()
    return rec.firstGameDone == true
end

--- 游戏完成时调用，判断是否为今日首局并发放奖励
---@return boolean isFirst  是否是今日首局
---@return number amount    获得的欢乐币数量
function JoyShopData.OnGameComplete()
    local rec = getRecords()
    if rec.firstGameDone then
        return false, 0
    end
    rec.firstGameDone = true
    Currency.Add("joy_coin", FIRST_GAME_REWARD)
    HeroData.Save(true)
    return true, FIRST_GAME_REWARD
end

-- ============================================================================
-- 排行榜结算
-- ============================================================================

--- 今日结算是否已执行
---@return boolean
function JoyShopData.IsSettlementDone()
    local rec = getRecords()
    return rec.settlementDone == true
end

--- 根据排名计算奖励
---@param rank number  排名（1-based）
---@return number
local function calcRankReward(rank)
    for _, tier in ipairs(RANK_REWARDS) do
        if rank <= tier.maxRank then
            return tier.amount
        end
    end
    return RANK_PARTICIPATE_REWARD
end

--- 检查昨日排行榜结算（异步）
--- 打开小游戏页面时调用一次
---@param callback fun(awarded:boolean, amount:number, rank:number|nil)
function JoyShopData.CheckSettlement(callback)
    local rec = getRecords()
    if rec.settlementDone then
        if callback then callback(false, 0, nil) end
        return
    end

    if not clientCloud then
        rec.settlementDone = true
        HeroData.Save(true)
        if callback then callback(false, 0, nil) end
        return
    end

    -- 昨日排行 key
    local yesterdayKey = "yang_daily_" .. os.date("%Y%m%d", os.time() - 86400)

    clientCloud:GetRankList(yesterdayKey, 0, 20, false, {
        ok = function(rankList)
            rec.settlementDone = true

            if not rankList or #rankList == 0 then
                HeroData.Save(true)
                if callback then callback(false, 0, nil) end
                return
            end

            -- 找自己的排名
            local myRank = nil
            for i, entry in ipairs(rankList) do
                if entry.userId == clientCloud.userId then
                    myRank = i
                    break
                end
            end

            if not myRank then
                -- 没上榜，检查是否有参与（有昨日分数）
                clientCloud:Get(yesterdayKey, {
                    ok = function(_, iscores)
                        local myScore = iscores and iscores[yesterdayKey] or 0
                        if myScore > 0 then
                            local amount = RANK_PARTICIPATE_REWARD
                            Currency.Add("joy_coin", amount)
                            HeroData.Save(true)
                            if callback then callback(true, amount, nil) end
                        else
                            HeroData.Save(true)
                            if callback then callback(false, 0, nil) end
                        end
                    end,
                    error = function()
                        HeroData.Save(true)
                        if callback then callback(false, 0, nil) end
                    end,
                })
                return
            end

            local amount = calcRankReward(myRank)
            Currency.Add("joy_coin", amount)
            HeroData.Save(true)
            if callback then callback(true, amount, myRank) end
        end,
        error = function()
            -- 网络失败不标记已结算，下次再试
            if callback then callback(false, 0, nil) end
        end,
    })
end

--- 获取首局奖励数量（供 UI 展示）
---@return number
function JoyShopData.GetFirstGameRewardAmount()
    return FIRST_GAME_REWARD
end

--- 获取排行奖励梯度（供 UI 展示）
---@return table[]
function JoyShopData.GetRankRewardTiers()
    return RANK_REWARDS
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("joyShop", {
    group = "meta_game",
    order = 75,
    serialize = function()
        return HeroData.joyShop
    end,
    deserialize = function(saved, _saveData)
        HeroData.joyShop = saved or nil
    end,
})

return JoyShopData
