-- Game/AccumulatedRewardData.lua
-- 积天好礼数据管理
-- 规则：每日观看广告数达3个算累积1天，每15天轮换一次

local HeroData  = require("Game.HeroData")
local Currency  = require("Game.Currency")
local AdTracker = require("Game.AdTracker")

local AccumulatedRewardData = {}

-- ============================================================================
-- 奖励配置（15天一轮）
-- ============================================================================

--- 每天的奖励定义
--- 第15天额外附赠幽影珠×5
AccumulatedRewardData.REWARDS = {
    { currency = "devour_stone",    amount = 288,  label = "噬魂石 ×288" },
    { currency = "forge_iron",      amount = 488,  label = "锻魂铁 ×488" },
    { currency = "shadow_essence",  amount = 288,  label = "暗影精粹 ×288" },
    { currency = "devour_stone",    amount = 388,  label = "噬魂石 ×388" },
    { currency = "forge_iron",      amount = 588,  label = "锻魂铁 ×588" },
    { currency = "shadow_essence",  amount = 288,  label = "暗影精粹 ×288" },
    { currency = "devour_stone",    amount = 488,  label = "噬魂石 ×488" },
    { currency = "forge_iron",      amount = 688,  label = "锻魂铁 ×688" },
    { currency = "shadow_essence",  amount = 488,  label = "暗影精粹 ×488" },
    { currency = "devour_stone",    amount = 588,  label = "噬魂石 ×588" },
    { currency = "forge_iron",      amount = 788,  label = "锻魂铁 ×788" },
    { currency = "shadow_essence",  amount = 488,  label = "暗影精粹 ×488" },
    { currency = "devour_stone",    amount = 688,  label = "噬魂石 ×688" },
    { currency = "forge_iron",      amount = 888,  label = "锻魂铁 ×888" },
    { currency = "shadow_orb",      amount = 5,    label = "幽影珠 ×5" },
}

AccumulatedRewardData.CYCLE_LENGTH = 15   -- 每轮天数
AccumulatedRewardData.ADS_PER_DAY  = 3    -- 每天需要看的广告数

-- ============================================================================
-- 数据结构
-- ============================================================================
-- accumulatedReward = {
--   accDays       = 0,         -- 累积已确认天数（已领取奖励数）
--   todayDate     = "2026-04-08",  -- 今日日期
--   todayAdCount  = 0,         -- 今日已观看广告数
--   todayQualified = false,    -- 今日是否已达标（3个广告）
--   claimed       = {},        -- 当轮已领取奖励索引表 { [1]=true, [2]=true, ... }
-- }

local TodayStr = require("Game.DateUtil").TodayStr

--- 创建默认数据
---@return table
local function DefaultData()
    return {
        accDays        = 0,
        todayDate      = TodayStr(),
        todayAdCount   = 0,
        todayQualified = false,
        claimed        = {},
    }
end

--- 加载数据
function AccumulatedRewardData.Load()
    local saved = HeroData.activityData and HeroData.activityData.accumulatedReward
    if saved and saved.todayDate then
        AccumulatedRewardData.data = saved
        -- 日期变化：检查昨天是否达标并累积
        if saved.todayDate ~= TodayStr() then
            AccumulatedRewardData._OnNewDay()
        end
    else
        AccumulatedRewardData.data = DefaultData()
    end
end

--- 保存数据
function AccumulatedRewardData.Save()
    if not HeroData.activityData then
        HeroData.activityData = {}
    end
    HeroData.activityData.accumulatedReward = AccumulatedRewardData.data
    HeroData.Save()
end

--- 新的一天到来时的处理
function AccumulatedRewardData._OnNewDay()
    local d = AccumulatedRewardData.data
    -- 昨天如果达标了（但还没累积过），累积1天
    if d.todayQualified then
        d.accDays = d.accDays + 1
    end
    -- 重置今日计数
    d.todayDate      = TodayStr()
    d.todayAdCount   = 0
    d.todayQualified = false
    -- 如果上一轮已完成（所有奖励已领完），开启新一轮
    if d.accDays >= AccumulatedRewardData.CYCLE_LENGTH then
        local allClaimed = true
        for i = 1, AccumulatedRewardData.CYCLE_LENGTH do
            if not d.claimed[i] then allClaimed = false; break end
        end
        if allClaimed then
            d.accDays = 0
            d.claimed = {}
        end
    end
    AccumulatedRewardData.Save()
end

--- 从 AdTracker 同步今日广告数并更新达标状态
function AccumulatedRewardData.Sync()
    local d = AccumulatedRewardData.data
    if d.todayDate ~= TodayStr() then
        AccumulatedRewardData._OnNewDay()
    end
    local count = AdTracker.GetTodayCount()
    d.todayAdCount = count
    if count >= AccumulatedRewardData.ADS_PER_DAY and not d.todayQualified then
        d.todayQualified = true
        d.accDays = d.accDays + 1
        print("[AccumulatedReward] Today qualified! accDays = " .. d.accDays)
    end
    AccumulatedRewardData.Save()
end

--- 兼容旧调用（内部转为 Sync）
AccumulatedRewardData.RecordAdWatch = AccumulatedRewardData.Sync
AccumulatedRewardData.SyncFromDailyDeal = AccumulatedRewardData.Sync

--- 获取累积天数
---@return number
function AccumulatedRewardData.GetAccDays()
    return AccumulatedRewardData.data.accDays or 0
end

--- 获取今日已观看广告数
---@return number
function AccumulatedRewardData.GetTodayAdCount()
    return AccumulatedRewardData.data.todayAdCount or 0
end

--- 今日是否已达标
---@return boolean
function AccumulatedRewardData.IsTodayQualified()
    return AccumulatedRewardData.data.todayQualified == true
end

--- 指定天数的奖励是否可领取
---@param dayIndex number  1~15
---@return boolean
function AccumulatedRewardData.CanClaim(dayIndex)
    local d = AccumulatedRewardData.data
    if d.claimed[dayIndex] then return false end
    return d.accDays >= dayIndex
end

--- 指定天数的奖励是否已领取
---@param dayIndex number
---@return boolean
function AccumulatedRewardData.IsClaimed(dayIndex)
    return AccumulatedRewardData.data.claimed[dayIndex] == true
end

--- 领取奖励
---@param dayIndex number  1~15
---@return boolean success
---@return string msg
---@return table|nil claimedReward  已领取的奖励 { id, amount }
function AccumulatedRewardData.Claim(dayIndex)
    if not AccumulatedRewardData.CanClaim(dayIndex) then
        if AccumulatedRewardData.IsClaimed(dayIndex) then
            return false, "已领取"
        end
        return false, "累积天数不足"
    end
    local reward = AccumulatedRewardData.REWARDS[dayIndex]
    if not reward then return false, "奖励不存在" end

    -- 发放奖励（走统一接口）
    Currency.GrantReward({ type = "currency", id = reward.currency, amount = reward.amount })
    local msg = reward.label

    AccumulatedRewardData.data.claimed[dayIndex] = true
    AccumulatedRewardData.Save()
    return true, msg, { id = reward.currency, amount = reward.amount }
end

--- 是否有可领取的奖励（红点提示）
---@return boolean
function AccumulatedRewardData.HasUnclaimed()
    local d = AccumulatedRewardData.data
    for i = 1, AccumulatedRewardData.CYCLE_LENGTH do
        if d.accDays >= i and not d.claimed[i] then
            return true
        end
    end
    return false
end

--- 获取当前轮次进度信息
---@return number accDays       累积天数
---@return number todayAdCount  今日广告数
---@return boolean todayDone    今日是否达标
function AccumulatedRewardData.GetProgress()
    local d = AccumulatedRewardData.data
    return d.accDays or 0, d.todayAdCount or 0, d.todayQualified == true
end

return AccumulatedRewardData
