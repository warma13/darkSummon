-- Game/DailyTaskData.lua
-- 每日任务系统：永久性每日任务，每日重置，奖励直接给货币

local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")  -- 里程碑奖励发放用
local SaveRegistry = require("Game.SaveRegistry")

local DailyTaskData = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 每日任务定义 { id, desc, target, points }
--- 单任务不给奖励，只给积分，积分用于兑换里程碑奖励
DailyTaskData.DAILY_TASKS = {
    { id = "idle",    desc = "领取挂机收益3次", target = 3,  points = 15 },
    { id = "boss",    desc = "挑战Boss副本1次", target = 1,  points = 15 },
    { id = "recruit", desc = "招募2次",         target = 2,  points = 15 },
    { id = "chest",   desc = "开启3个宝箱",   target = 3,  points = 10 },
    { id = "signin",  desc = "完成每日签到",   target = 1,  points = 10 },
    { id = "battle",  desc = "完成10次战斗",  target = 10, points = 25 },
    { id = "watchAd", desc = "观看3次广告",   target = 3,  points = 30 },
}

--- 里程碑奖励 { threshold, rewards, desc }
DailyTaskData.MILESTONES = {
    { threshold = 15,  desc = "锻魂铁x100",
      rewards = { { type = "currency", id = "forge_iron", amount = 100 } } },
    { threshold = 30,  desc = "朽木宝箱x1",
      rewards = { { type = "chest", id = "bronze_chest", amount = 1 } } },
    { threshold = 50,  desc = "暗影精粹x30",
      rewards = { { type = "currency", id = "shadow_essence", amount = 30 } } },
    { threshold = 70,  desc = "青铜宝箱x1",
      rewards = { { type = "chest", id = "bronze_chest", amount = 1 } } },
    { threshold = 85,  desc = "资源副本门票x1",
      rewards = { { type = "item", id = "dungeon_ticket", amount = 1 } } },
    { threshold = 100, desc = "免广券x1",
      rewards = { { type = "currency", id = "ad_ticket", amount = 1 } } },
}

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 获取当前日期字符串
local TodayStr = require("Game.DateUtil").TodayStr

--- 确保数据结构存在
---@return table data
function DailyTaskData.EnsureData()
    if not HeroData.dailyTaskData then
        HeroData.dailyTaskData = {
            taskProgress = {},       -- { summon=N, merge=N, ... }
            taskClaimed  = {},       -- { summon=true, ... }
            lastTaskDate = "",       -- 任务进度所属日期
            totalPoints  = 0,        -- 累计积分（永不重置）
            milestonesClaimed = {},  -- { [1]=true, [2]=true, ... }
        }
    end
    -- 兼容旧存档：补齐新字段
    local d = HeroData.dailyTaskData
    if d.totalPoints == nil then d.totalPoints = 0 end
    if d.milestonesClaimed == nil then d.milestonesClaimed = {} end
    return d
end

--- 检查今日是否需要重置任务进度（积分和里程碑也每日重置）
---@param data table
local function CheckDailyReset(data)
    local today = TodayStr()
    if data.lastTaskDate ~= today then
        data.taskProgress = {}
        data.taskClaimed = {}
        data.totalPoints = 0
        data.milestonesClaimed = {}
        data.lastTaskDate = today
    end
    -- 兼容：将旧的数字键 milestonesClaimed 转为字符串键（cjson 安全）
    if data.milestonesClaimed then
        local fixed = {}
        for k, v in pairs(data.milestonesClaimed) do
            fixed[tostring(k)] = v
        end
        data.milestonesClaimed = fixed
    end
end

-- ============================================================================
-- 每日任务
-- ============================================================================

--- 增加任务进度（由各系统 hook 调用）
---@param taskId string  "summon"|"merge"|"stage"|"chest"|"signin"|"battle"
---@param amount number
function DailyTaskData.AddProgress(taskId, amount)
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)
    data.taskProgress[taskId] = (data.taskProgress[taskId] or 0) + amount
end

--- 获取任务进度
---@param taskId string
---@return number current, number target, boolean claimed
function DailyTaskData.GetTaskProgress(taskId)
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)
    local taskDef = nil
    for _, t in ipairs(DailyTaskData.DAILY_TASKS) do
        if t.id == taskId then taskDef = t; break end
    end
    if not taskDef then return 0, 0, false end
    local current = data.taskProgress[taskId] or 0
    local claimed = data.taskClaimed[taskId] or false
    return current, taskDef.target, claimed
end

--- 领取任务奖励（直接给货币）
---@param taskId string
---@return boolean success
---@return string msg
function DailyTaskData.ClaimTask(taskId)
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)

    local taskDef = nil
    for _, t in ipairs(DailyTaskData.DAILY_TASKS) do
        if t.id == taskId then taskDef = t; break end
    end
    if not taskDef then return false, "未知任务" end

    if data.taskClaimed[taskId] then
        return false, "已领取"
    end
    local current = data.taskProgress[taskId] or 0
    if current < taskDef.target then
        return false, "未完成"
    end

    data.taskClaimed[taskId] = true
    local pts = taskDef.points or 0
    data.totalPoints = (data.totalPoints or 0) + pts
    HeroData.Save()

    -- 同步周积分
    local ok2, WPD = pcall(require, "Game.WeeklyPointsData")
    if ok2 and WPD then WPD.AddPoints(pts) end

    print("[DailyTask] Task " .. taskId .. " claimed, +" .. pts
        .. " pts (total=" .. data.totalPoints .. ")")
    return true, "+" .. pts .. " 积分"
end

--- 获取总积分
---@return number
function DailyTaskData.GetTotalPoints()
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)
    return data.totalPoints or 0
end

-- ============================================================================
-- 里程碑奖励
-- ============================================================================

--- 检查里程碑是否可领取
---@param index number
---@return boolean canClaim, boolean claimed, boolean reached
function DailyTaskData.GetMilestoneStatus(index)
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)
    local milestone = DailyTaskData.MILESTONES[index]
    if not milestone then return false, false, false end
    local key = tostring(index)
    local claimed = data.milestonesClaimed[key] or false
    local reached = (data.totalPoints or 0) >= milestone.threshold
    return reached and not claimed, claimed, reached
end

--- 领取里程碑奖励
---@param index number
---@return boolean success
---@return string msg
function DailyTaskData.ClaimMilestone(index)
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)
    local milestone = DailyTaskData.MILESTONES[index]
    if not milestone then return false, "无效里程碑" end
    local key = tostring(index)
    if data.milestonesClaimed[key] then
        return false, "已领取"
    end
    if (data.totalPoints or 0) < milestone.threshold then
        return false, "积分不足"
    end

    data.milestonesClaimed[key] = true
    Currency.GrantRewards(milestone.rewards)
    HeroData.Save()
    print("[DailyTask] Milestone " .. index .. " claimed: " .. milestone.desc)
    return true, "获得 " .. milestone.desc
end

--- 是否有任何可领取的任务（红点）
---@return boolean
function DailyTaskData.HasClaimable()
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)

    -- 任务奖励（已完成但未领取）
    for _, t in ipairs(DailyTaskData.DAILY_TASKS) do
        local current = data.taskProgress[t.id] or 0
        local claimed = data.taskClaimed[t.id] or false
        if current >= t.target and not claimed then return true end
    end

    -- 里程碑（已达成但未领取）
    for i, m in ipairs(DailyTaskData.MILESTONES) do
        if (data.totalPoints or 0) >= m.threshold and not data.milestonesClaimed[tostring(i)] then
            return true
        end
    end

    -- 周积分里程碑（已达成但未领取）
    local ok2, WPD = pcall(require, "Game.WeeklyPointsData")
    if ok2 and WPD and WPD.HasClaimable then
        if WPD.HasClaimable() then return true end
    end

    -- 成就奖励（已达成但未领取）
    local ok3, AchData = pcall(require, "Game.AchievementData")
    if ok3 and AchData and AchData.HasClaimable then
        if AchData.HasClaimable() then return true end
    end

    return false
end

--- 获取已完成任务数
---@return number completed, number total
function DailyTaskData.GetCompletedCount()
    local data = DailyTaskData.EnsureData()
    CheckDailyReset(data)
    local completed = 0
    local total = #DailyTaskData.DAILY_TASKS
    for _, t in ipairs(DailyTaskData.DAILY_TASKS) do
        local current = data.taskProgress[t.id] or 0
        if current >= t.target then completed = completed + 1 end
    end
    return completed, total
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("dailyTaskData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.dailyTaskData
    end,
    deserialize = function(saved, _saveData)
        HeroData.dailyTaskData = saved or nil
    end,
})

return DailyTaskData
