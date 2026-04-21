-- Game/WeeklyPointsData.lua
-- 周积分系统：累积每日任务积分，提供每周里程碑奖励
-- 每7天与 WeeklyActivityData 周期同步重置

local HeroData      = require("Game.HeroData")
local Currency      = require("Game.Currency")
local SaveRegistry  = require("Game.SaveRegistry")

local WeeklyPointsData = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 每日任务满分 100 分，6 天即可达 600 分
WeeklyPointsData.MILESTONES = {
    { threshold = 100, desc = "锻魂铁x500",
      rewards = { { type = "currency", id = "forge_iron", amount = 500 } } },
    { threshold = 200, desc = "万能SSR碎片箱x10",
      rewards = { { type = "item", id = "ssr_shard_select_box", amount = 10 } } },
    { threshold = 300, desc = "免广券x3",
      rewards = { { type = "currency", id = "ad_ticket", amount = 3 } } },
    { threshold = 450, desc = "万能UR碎片箱x10",
      rewards = { { type = "item", id = "ur_shard_box", amount = 10 } } },
    { threshold = 600, desc = "钻石宝箱x1",
      rewards = { { type = "chest", id = "diamond", amount = 1 } } },
}

-- ============================================================================
-- 工具：当前周起始日
-- ============================================================================

--- 获取当前周期起始日期字符串（与 WAD 同步，或本地降级）
--- WAD.GetCurrentWeekStart() 已返回 "YYYY-MM-DD" 字符串，直接复用
---@return string  "YYYY-MM-DD"
local function GetCurrentWeekStartKey()
    local ok, WAD = pcall(require, "Game.WeeklyActivityData")
    if ok and WAD and WAD.GetCurrentWeekStart then
        return WAD.GetCurrentWeekStart()  -- 已是 "YYYY-MM-DD" 字符串
    end
    -- 降级：以本地时间最近的周一为起点
    local t = os.time()
    local wd = tonumber(os.date("%w", t))  -- 0=Sunday
    local daysSinceMonday = (wd == 0) and 6 or (wd - 1)
    local midnightToday = t - (t % 86400)
    local mondayTs = midnightToday - daysSinceMonday * 86400
    return os.date("%Y-%m-%d", mondayTs)
end

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 确保数据结构存在
---@return table data
function WeeklyPointsData.EnsureData()
    if not HeroData.weeklyPointsData then
        HeroData.weeklyPointsData = {
            weekStart         = GetCurrentWeekStartKey(),  -- 当前周起始日期 key
            weeklyPoints      = 0,     -- 本周累计积分
            milestonesClaimed = {},    -- { ["1"]=true, ... }
        }
    end
    local d = HeroData.weeklyPointsData
    if d.weeklyPoints == nil then d.weeklyPoints = 0 end
    if d.milestonesClaimed == nil then d.milestonesClaimed = {} end
    return d
end

--- 检查是否需要重置（每次访问均调用）
---@param data table
local function CheckWeekReset(data)
    local key = GetCurrentWeekStartKey()
    if data.weekStart ~= key then
        data.weekStart         = key
        data.weeklyPoints      = 0
        data.milestonesClaimed = {}
        HeroData.Save()
        print("[WeeklyPoints] 新的一周，积分重置（weekStart=" .. key .. "）")
    end
    -- 兼容：DeepNormalizeIntKeys 将 "1"→1，需还原为字符串键
    if data.milestonesClaimed then
        local fixed = {}
        for k, v in pairs(data.milestonesClaimed) do
            fixed[tostring(k)] = v
        end
        data.milestonesClaimed = fixed
    end
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 获取本周累计积分
---@return number
function WeeklyPointsData.GetPoints()
    local data = WeeklyPointsData.EnsureData()
    CheckWeekReset(data)
    return data.weeklyPoints or 0
end

--- 增加本周积分（由 DailyTaskData.ClaimTask 调用）
---@param amount number
function WeeklyPointsData.AddPoints(amount)
    if not amount or amount <= 0 then return end
    local data = WeeklyPointsData.EnsureData()
    CheckWeekReset(data)
    data.weeklyPoints = (data.weeklyPoints or 0) + amount
    HeroData.Save()
    print("[WeeklyPoints] +", amount, "pts (total=", data.weeklyPoints, ")")
end

--- 获取里程碑状态
---@param index number
---@return boolean canClaim, boolean claimed, boolean reached
function WeeklyPointsData.GetMilestoneStatus(index)
    local data = WeeklyPointsData.EnsureData()
    CheckWeekReset(data)
    local milestone = WeeklyPointsData.MILESTONES[index]
    if not milestone then return false, false, false end
    local key = tostring(index)
    local claimed = data.milestonesClaimed[key] or false
    local reached = (data.weeklyPoints or 0) >= milestone.threshold
    return reached and not claimed, claimed, reached
end

--- 领取里程碑奖励
---@param index number
---@return boolean success, string msg
function WeeklyPointsData.ClaimMilestone(index)
    local data = WeeklyPointsData.EnsureData()
    CheckWeekReset(data)
    local milestone = WeeklyPointsData.MILESTONES[index]
    if not milestone then return false, "无效里程碑" end
    local key = tostring(index)
    if data.milestonesClaimed[key] then
        return false, "已领取"
    end
    if (data.weeklyPoints or 0) < milestone.threshold then
        return false, "积分不足"
    end
    data.milestonesClaimed[key] = true
    Currency.GrantRewards(milestone.rewards)
    HeroData.Save()
    print("[WeeklyPoints] Milestone", index, "claimed:", milestone.desc)
    return true, "获得 " .. milestone.desc
end

--- 是否有可领取的里程碑奖励（红点用）
---@return boolean
function WeeklyPointsData.HasClaimable()
    local data = WeeklyPointsData.EnsureData()
    CheckWeekReset(data)
    local pts = data.weeklyPoints or 0
    for i, m in ipairs(WeeklyPointsData.MILESTONES) do
        if pts >= m.threshold and not data.milestonesClaimed[tostring(i)] then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("weeklyPointsData", {
    group = "meta_game",
    order = 73,
    serialize = function()
        return HeroData.weeklyPointsData
    end,
    deserialize = function(saved, _saveData)
        HeroData.weeklyPointsData = saved or nil
    end,
})

return WeeklyPointsData
