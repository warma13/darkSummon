-- Game/WelfareData.lua
-- 限时福利数据：每日看广告领宝箱 + 每周广告进度领暗影精粹

local HeroData      = require("Game.HeroData")
local ChestData     = require("Game.ChestData")
local Currency      = require("Game.Currency")
local WAD           = require("Game.WeeklyActivityData")
local SaveRegistry  = require("Game.SaveRegistry")
local InventoryData = require("Game.InventoryData")

local WelfareData = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 宝箱周每日奖励（11 次，第 1 次免费，后续看广告解锁，从朽木→青铜→黄金→铂金）
--- 每天重置
WelfareData.DAILY_AD_REWARDS = {
    { chestId = "wood",     amount = 5,  free = true },  -- 第 1 次：免费 5 朽木
    { chestId = "wood",     amount = 20 },   -- 第 2 次：20 朽木 = 20 分
    { chestId = "wood",     amount = 30 },   -- 第 3 次：30 朽木 = 30 分
    { chestId = "bronze",   amount = 5  },   -- 第 3 次：5 青铜 = 50 分
    { chestId = "bronze",   amount = 8  },   -- 第 4 次：8 青铜 = 80 分
    { chestId = "gold",     amount = 5  },   -- 第 5 次：5 黄金 = 100 分
    { chestId = "gold",     amount = 8  },   -- 第 6 次：8 黄金 = 160 分
    { chestId = "gold",     amount = 10 },   -- 第 7 次：10 黄金 = 200 分
    { chestId = "platinum", amount = 8  },   -- 第 8 次：8 铂金 = 400 分
    { chestId = "platinum", amount = 10 },   -- 第 9 次：10 铂金 = 500 分
    { chestId = "platinum", amount = 15 },   -- 第 10 次：15 铂金 = 750 分
}
-- 每日总直接积分: 2290，× 7天 × 2.08滚雪球 ≈ 33,346

WelfareData.MAX_DAILY_ADS = #WelfareData.DAILY_AD_REWARDS

--- 招募周每日奖励（10 次，第 1 次免费，后续看广告，奖励为招募券）
--- 每天重置，共 10 次/天
WelfareData.RECRUIT_DAILY_REWARDS = {
    { ticketAmount = 6,  free = true },  -- 第 1 次：免费 6 包
    { ticketAmount = 8  },               -- 第 2 次：8 包（广告）
    { ticketAmount = 8  },               -- 第 3 次：8 包
    { ticketAmount = 10 },               -- 第 4 次：10 包
    { ticketAmount = 10 },               -- 第 5 次：10 包
    { ticketAmount = 12 },               -- 第 6 次：12 包
    { ticketAmount = 12 },               -- 第 7 次：12 包
    { ticketAmount = 12 },               -- 第 8 次：12 包
    { ticketAmount = 14 },               -- 第 9 次：14 包
    { ticketAmount = 16 },               -- 第 10 次：16 包
    { ticketAmount = 20 },               -- 第 11 次：20 包
}
-- 合计：6+8+8+10+10+12+12+12+14+16+20 = 128 包/天

WelfareData.MAX_RECRUIT_DAILY = #WelfareData.RECRUIT_DAILY_REWARDS

--- 返回当前周有效的每日奖励列表
---@return table rewards, number maxCount
function WelfareData.GetEffectiveDailyRewards()
    if WAD.GetCurrentWeekType() == "recruit" then
        return WelfareData.RECRUIT_DAILY_REWARDS, WelfareData.MAX_RECRUIT_DAILY
    end
    return WelfareData.DAILY_AD_REWARDS, WelfareData.MAX_DAILY_ADS
end

--- 每周广告进度里程碑（累计一周，每 10 次广告领 1000 暗影精粹）
WelfareData.WEEKLY_MILESTONES = {
    { threshold = 10, rewardAmount = 1000 },
    { threshold = 20, rewardAmount = 1000 },
    { threshold = 30, rewardAmount = 1000 },
    { threshold = 40, rewardAmount = 1000 },
    { threshold = 50, rewardAmount = 1000 },
    { threshold = 60, rewardAmount = 1000 },
}

-- ============================================================================
-- 数据访问
-- ============================================================================

local TodayStr = require("Game.DateUtil").TodayStr

function WelfareData.EnsureData()
    if not HeroData.welfareData then
        HeroData.welfareData = {
            -- 每日数据
            dailyDate = TodayStr(),
            dailyAdCount = 0,           -- 今天已看广告次数
            dailyClaimed = {},          -- 今天已领取的奖励 { [1]=true, ... }
            -- 每周数据
            weeklyAdTotal = 0,          -- 本周累计看广告次数
            weeklyClaimed = {},         -- 本周已领取的暗影精粹 { [1]=true, ... }
        }
    end

    -- 迁移：prepend 免费宝箱后，旧存档的 dailyClaimed 索引需要 +1
    local data = HeroData.welfareData
    if not data.freeChestMigrated then
        local old = data.dailyClaimed or {}
        local shifted = {}
        for k, v in pairs(old) do
            local idx = tonumber(k)
            if idx then
                shifted[idx + 1] = v
            end
        end
        data.dailyClaimed = shifted
        data.freeChestMigrated = true
        print("[WelfareData] Migrated dailyClaimed indices +1 for free chest")
    end

    -- 迁移：在位置2插入新自选包8后，旧存档的 dailyClaimed 索引 2~N 需要 +1
    if not data.recruitPack8Migrated then
        local old = data.dailyClaimed or {}
        local shifted = {}
        for k, v in pairs(old) do
            local idx = tonumber(k)
            if idx and idx >= 2 then
                shifted[idx + 1] = v
            elseif idx then
                shifted[idx] = v
            end
        end
        data.dailyClaimed = shifted
        data.recruitPack8Migrated = true
        print("[WelfareData] Migrated dailyClaimed indices +1 at pos 2 for new recruit pack 8")
    end

    -- 检查周期是否变更：cycleStartDate 与当前周期不一致时重置周计数
    local currentCycleStart = WAD.GetCurrentWeekStart()
    if data.cycleStartDate ~= currentCycleStart then
        local oldCycle = data.cycleStartDate or "?"
        data.weeklyAdTotal = 0
        data.weeklyClaimed = {}
        -- 周期切换时必须重置每日领取，否则宝箱周的领取记录会被误认为招募周已领
        data.dailyAdCount = 0
        data.dailyClaimed = {}
        data.cycleStartDate = currentCycleStart
        print("[WelfareData] Cycle reset: " .. oldCycle .. " -> " .. currentCycleStart
            .. " (weekType=" .. WAD.GetCurrentWeekType() .. "), daily claims also reset")
    end

    return data
end

--- 检查并重置每日数据
local function ResetDailyIfNeeded(data)
    local today = TodayStr()
    if data.dailyDate ~= today then
        data.dailyDate = today
        data.dailyAdCount = 0
        data.dailyClaimed = {}
    end
end

--- 检查活动是否在进行中（依赖 WeeklyActivityData 的活动周期）
function WelfareData.IsActive()
    return WAD.IsActive()
end

-- ============================================================================
-- 每日广告宝箱
-- ============================================================================

--- 获取今日已看广告次数
function WelfareData.GetDailyAdCount()
    local data = WelfareData.EnsureData()
    ResetDailyIfNeeded(data)
    return data.dailyAdCount
end

--- 获取某个奖励是否已领取
function WelfareData.IsDailyClaimed(index)
    local data = WelfareData.EnsureData()
    ResetDailyIfNeeded(data)
    return data.dailyClaimed[index] or false
end

--- 某个奖励是否已解锁（第1个默认解锁，后续需要前一个已领取）
function WelfareData.IsDailyUnlocked(index)
    if index == 1 then return true end
    return WelfareData.IsDailyClaimed(index - 1)
end

--- 看广告并领取对应奖励（自动适配宝箱周/招募周）
function WelfareData.ClaimDailyReward(index, onDone)
    local data = WelfareData.EnsureData()
    ResetDailyIfNeeded(data)

    local rewards, maxCount = WelfareData.GetEffectiveDailyRewards()

    -- 校验
    if index < 1 or index > maxCount then
        if onDone then onDone(false, "无效索引") end
        return
    end
    if data.dailyClaimed[index] then
        if onDone then onDone(false, "已领取") end
        return
    end
    if not WelfareData.IsDailyUnlocked(index) then
        if onDone then onDone(false, "未解锁") end
        return
    end

    local reward = rewards[index]

    -- 免费奖励直接发放
    if reward.free then
        WelfareData._ApplyDailyReward(data, index, reward)
        if onDone then onDone(true) end
        return
    end

    -- 看广告
    local AdHelper = require("Game.AdHelper")
    AdHelper.ShowRewardAd(function()
        WelfareData._ApplyDailyReward(data, index, reward)
        if onDone then onDone(true) end
    end, function(reason)
        if onDone then onDone(false, reason) end
    end)
end

function WelfareData._ApplyDailyReward(data, index, reward)
    if reward.ticketAmount then
        -- 招募周：发放招募券自选包（可在仓库选择招募池兑换对应票券）
        InventoryData.Add("recruit_ticket_select_box", reward.ticketAmount)
    else
        -- 宝箱周：发放宝箱
        ChestData.Add(reward.chestId, reward.amount)
        ChestData.Save()
    end

    -- 标记已领取
    data.dailyClaimed[index] = true
    data.dailyAdCount = data.dailyAdCount + 1

    -- 累加每周广告计数（免费奖励不计入）
    if not reward.free then
        data.weeklyAdTotal = (data.weeklyAdTotal or 0) + 1
    end

    -- 广告奖励是关键操作，立即保存（不走延迟）
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
function WelfareData.GetWeeklyAdTotal()
    local data = WelfareData.EnsureData()
    return data.weeklyAdTotal or 0
end

--- 某个每周里程碑是否可领取
function WelfareData.IsWeeklyClaimable(index)
    local data = WelfareData.EnsureData()
    local m = WelfareData.WEEKLY_MILESTONES[index]
    if not m then return false end
    return (data.weeklyAdTotal or 0) >= m.threshold and not (data.weeklyClaimed[index] or false)
end

--- 某个每周里程碑是否已领取
function WelfareData.IsWeeklyClaimed(index)
    local data = WelfareData.EnsureData()
    return data.weeklyClaimed[index] or false
end

--- 领取每周里程碑奖励
function WelfareData.ClaimWeeklyMilestone(index)
    local data = WelfareData.EnsureData()
    local m = WelfareData.WEEKLY_MILESTONES[index]
    if not m then return false end
    if (data.weeklyAdTotal or 0) < m.threshold then return false end
    if data.weeklyClaimed[index] then return false end

    -- 发放暗影精粹
    Currency.Add("shadow_essence", m.rewardAmount)
    data.weeklyClaimed[index] = true

    -- 立即保存
    local SlotSave = require("Game.SlotSaveSystem")
    if SlotSave.GetActiveSlot() > 0 then
        SlotSave.SaveNow()
    else
        HeroData.Save()
    end
    return true
end

--- 是否有任何可领取的奖励（红点）
function WelfareData.HasClaimable()
    if not WelfareData.IsActive() then return false end
    local data = WelfareData.EnsureData()
    ResetDailyIfNeeded(data)

    -- 检查每日广告奖励：是否有已解锁且未领取的
    local _, maxCount = WelfareData.GetEffectiveDailyRewards()
    for i = 1, maxCount do
        if WelfareData.IsDailyUnlocked(i) and not (data.dailyClaimed[i] or false) then
            return true
        end
    end

    -- 检查每周进度奖励
    for i, m in ipairs(WelfareData.WEEKLY_MILESTONES) do
        if (data.weeklyAdTotal or 0) >= m.threshold and not (data.weeklyClaimed[i] or false) then
            return true
        end
    end

    return false
end

--- 重置（活动周期结束时由 WeeklyActivityData 调用）
function WelfareData.ResetAll()
    HeroData.welfareData = nil
    WelfareData.EnsureData()
    HeroData.Save()
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("welfareData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.welfareData
    end,
    deserialize = function(saved, _saveData)
        HeroData.welfareData = saved or nil
    end,
})

return WelfareData
