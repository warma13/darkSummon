-- Game/DailyDealData.lua
-- 每日特惠数据管理（每日重置）

local HeroData      = require("Game.HeroData")
local Currency      = require("Game.Currency")
local Config        = require("Game.Config")

local DailyDealData = {}

-- ============================================================================
-- 奖励配置
-- ============================================================================

--- 免费礼包内容（统一 GrantReward 格式）
DailyDealData.FREE_PACK = {
    { type = "currency", id = "shadow_essence", amount = 66 },
    { type = "currency", id = "devour_stone",   amount = 50 },
}

--- 广告解锁奖励（每个广告位看一次广告领取全部奖励）
DailyDealData.AD_REWARDS = {
    {
        id = "ad_combo_1",
        label = "特惠礼包",
        items = {
            { icon = "shadow_essence",      text = "暗影精粹 ×10" },
            { icon = "nether_crystal_pack", text = "冥晶礼包（4小时挂机收益）" },
            { icon = "shadow_essence_bag",  text = "暗影精粹福袋（128~1288）" },
        },
        rewards = {
            { type = "currency", id = "shadow_essence",      amount = 10, name = "暗影精粹" },
            { type = "item",     id = "nether_crystal_pack",  amount = 1,  name = "冥晶礼包" },
            { type = "item",     id = "shadow_essence_bag",   amount = 1,  name = "暗影精粹福袋" },
        },
    },
    {
        id = "ad_combo_2",
        label = "特惠礼包 II",
        items = {
            { icon = "shadow_essence",      text = "暗影精粹 ×30" },
            { icon = "nether_crystal_pack", text = "冥晶礼包（4小时挂机收益）" },
            { icon = "shadow_essence_bag",  text = "暗影精粹福袋 ×2（各128~1288）" },
        },
        rewards = {
            { type = "currency", id = "shadow_essence",      amount = 30, name = "暗影精粹" },
            { type = "item",     id = "nether_crystal_pack",  amount = 1,  name = "冥晶礼包" },
            { type = "item",     id = "shadow_essence_bag",   amount = 2,  name = "暗影精粹福袋" },
        },
    },
    {
        id = "ad_combo_3",
        label = "特惠礼包 III",
        items = {
            { icon = "shadow_essence",      text = "暗影精粹 ×60" },
            { icon = "nether_crystal_pack", text = "冥晶礼包 ×3（各4小时挂机收益）" },
            { icon = "random_ur_shard_box", text = "随机UR碎片箱 ×10" },
        },
        rewards = {
            { type = "currency", id = "shadow_essence",      amount = 60, name = "暗影精粹" },
            { type = "item",     id = "nether_crystal_pack",  amount = 3,  name = "冥晶礼包" },
            { type = "item",     id = "random_ur_shard_box",  amount = 10, name = "随机UR碎片箱" },
        },
    },
}

-- ============================================================================
-- 数据结构
-- ============================================================================
-- dailyDeal = {
--   lastDate = "2026-04-08",   -- 上次操作日期（用于每日重置）
--   freeClaimed = false,       -- 免费礼包是否已领
--   adClaimed = { false, false, false },  -- 每个广告位是否已领
-- }

local TodayStr = require("Game.DateUtil").TodayStr

--- 创建默认数据
---@return table
local function DefaultData()
    return {
        lastDate    = TodayStr(),
        freeClaimed = false,
        adClaimed   = { false, false, false },
    }
end

--- 加载数据（自动每日重置）
function DailyDealData.Load()
    local saved = HeroData.activityData and HeroData.activityData.dailyDeal
    if saved and saved.lastDate then
        DailyDealData.data = saved
        -- 每日重置检查
        if saved.lastDate ~= TodayStr() then
            print("[DailyDealData] New day, resetting daily deals")
            DailyDealData.data = DefaultData()
            DailyDealData.Save()
        end
    else
        DailyDealData.data = DefaultData()
    end
end

--- 保存数据
function DailyDealData.Save()
    if not HeroData.activityData then
        HeroData.activityData = {}
    end
    HeroData.activityData.dailyDeal = DailyDealData.data
    HeroData.Save()
end

--- 免费礼包是否已领
---@return boolean
function DailyDealData.IsFreeClaimed()
    if not DailyDealData.data then DailyDealData.Load() end
    return DailyDealData.data.freeClaimed == true
end

--- 领取免费礼包
---@return boolean success
---@return string msg
---@return table|nil claimedRewards  已领取的奖励列表（GrantReward 格式）
function DailyDealData.ClaimFree()
    if DailyDealData.IsFreeClaimed() then
        return false, "今日已领取"
    end
    Currency.GrantRewards(DailyDealData.FREE_PACK)
    DailyDealData.data.freeClaimed = true
    DailyDealData.Save()
    return true, "暗影精粹×66, 噬魂石×50", DailyDealData.FREE_PACK
end

--- 指定广告奖励是否已领（index 1~3）
---@param index number
---@return boolean
function DailyDealData.IsAdClaimed(index)
    if not DailyDealData.data then DailyDealData.Load() end
    return DailyDealData.data.adClaimed[index] == true
end

--- 指定广告奖励是否可领（需先领取前一个）
---@param index number
---@return boolean
function DailyDealData.CanClaimAd(index)
    if DailyDealData.IsAdClaimed(index) then return false end
    if index > 1 and not DailyDealData.IsAdClaimed(index - 1) then return false end
    return true
end

--- 领取广告奖励
---@param index number
---@return boolean success
---@return string msg
---@return table|nil claimedRewards  已领取的奖励列表（GrantReward 格式）
function DailyDealData.ClaimAd(index)
    if not DailyDealData.CanClaimAd(index) then
        if DailyDealData.IsAdClaimed(index) then
            return false, "已领取", nil
        end
        return false, "请先领取前一个奖励", nil
    end
    local reward = DailyDealData.AD_REWARDS[index]
    if not reward then return false, "奖励不存在", nil end

    Currency.GrantRewards(reward.rewards)
    DailyDealData.data.adClaimed[index] = true
    DailyDealData.Save()

    -- 通知积天好礼系统
    local ok, AccumulatedRewardData = pcall(require, "Game.AccumulatedRewardData")
    if ok and AccumulatedRewardData then
        AccumulatedRewardData.RecordAdWatch()
    end

    return true, reward.label, reward.rewards
end

--- 是否有任何未领取奖励（用于红点）
---@return boolean
function DailyDealData.HasUnclaimed()
    if not DailyDealData.IsFreeClaimed() then return true end
    for i = 1, #DailyDealData.AD_REWARDS do
        if DailyDealData.CanClaimAd(i) then return true end
    end
    return false
end

return DailyDealData
