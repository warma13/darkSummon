-- Game/WeeklyActivityData.lua
-- 单周活动：宝箱达标奖励（累积开箱积分，4轮循环）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local MailboxData = require("Game.MailboxData")
local SaveRegistry = require("Game.SaveRegistry")
local Toast = require("Game.Toast")

local WAD = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 活动持续天数（每周重置）
WAD.EVENT_DAYS = 7

--- 最大轮数
WAD.MAX_ROUNDS = 4

--- 每轮里程碑 { threshold, rewards, desc }
WAD.MILESTONES = {
    {
        threshold = 1000,
        desc = "青铜宝箱x10 随机UR碎片x20 暗影精粹x1000",
        rewards = {
            { type = "chest",    id = "bronze", amount = 10 },
            { type = "item",     id = "random_ur_shard_box", amount = 20 },
            { type = "currency", id = "shadow_essence", amount = 1000 },
        },
    },
    {
        threshold = 2000,
        desc = "青铜宝箱x10 随机UR碎片x40 暗影精粹x1500",
        rewards = {
            { type = "chest",    id = "bronze", amount = 10 },
            { type = "item",     id = "random_ur_shard_box", amount = 40 },
            { type = "currency", id = "shadow_essence", amount = 1500 },
        },
    },
    {
        threshold = 4000,
        desc = "青铜宝箱x10 万能UR碎片x40 暗影精粹x2000",
        rewards = {
            { type = "chest",    id = "bronze", amount = 10 },
            { type = "item",     id = "ur_shard_box", amount = 40 },
            { type = "currency", id = "shadow_essence", amount = 2000 },
        },
    },
    {
        threshold = 8000,
        desc = "青铜宝箱x10 万能UR碎片x80 暗影精粹x2500",
        rewards = {
            { type = "chest",    id = "bronze", amount = 10 },
            { type = "item",     id = "ur_shard_box", amount = 80 },
            { type = "currency", id = "shadow_essence", amount = 2500 },
        },
    },
}

--- 单轮满分
WAD.ROUND_MAX = WAD.MILESTONES[#WAD.MILESTONES].threshold  -- 8000

-- ============================================================================
-- 数据访问
-- ============================================================================

-- ============================================================================
-- 开服时间工具
-- ============================================================================

--- 获取宝箱周活动起始时间戳（当天0点）
local function ServerStartTime()
    local s = Config.WEEKLY_ACTIVITY_START
    local y, m, d = s:match("(%d+)-(%d+)-(%d+)")
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- 计算当前所在的周期起始日期字符串（从开服起每 EVENT_DAYS 天一个周期）
local function GetCurrentWeekStart()
    local t0 = ServerStartTime()
    local daysSince = math.max(0, math.floor((os.time() - t0) / 86400))
    local weekNum = math.floor(daysSince / WAD.EVENT_DAYS)
    local weekStartTs = t0 + weekNum * WAD.EVENT_DAYS * 86400
    return os.date("%Y-%m-%d", weekStartTs)
end

--- 计算当前周期编号（从 0 开始）
local function GetCurrentWeekNum()
    local t0 = ServerStartTime()
    local daysSince = math.max(0, math.floor((os.time() - t0) / 86400))
    return math.floor(daysSince / WAD.EVENT_DAYS)
end

--- 对外暴露当前周期起始日（供其他模块同步重置）
---@return string  "YYYY-MM-DD"
function WAD.GetCurrentWeekStart()
    return GetCurrentWeekStart()
end

--- 当前周类型：三周轮换（0=宝箱周，1=招募周，2=黑市/掉落/换购周）
---@return "chest"|"recruit"|"market"
function WAD.GetCurrentWeekType()
    local phase = GetCurrentWeekNum() % 3
    if phase == 0 then return "chest"
    elseif phase == 1 then return "recruit"
    else return "market"
    end
end

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 确保数据结构存在
---@return table
function WAD.EnsureData()
    if not HeroData.weeklyActivityData then
        HeroData.weeklyActivityData = {
            startDate = GetCurrentWeekStart(),  -- 当前周期起始日（开服对齐）
            score = 0,
            round = 1,
            claimed = {},
        }
    end
    return HeroData.weeklyActivityData
end

--- 日期字符串转时间戳
local function DateStrToTime(dateStr)
    local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if not y then return 0 end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- 检查是否需要周重置（与开服对齐的周期边界）
local function CheckWeekReset(data)
    local expectedStart = GetCurrentWeekStart()
    if data.startDate ~= expectedStart then
        local savedTs  = DateStrToTime(data.startDate or "")
        local expectTs = DateStrToTime(expectedStart)
        -- 旧周期未过期（今天仍在 savedTs + EVENT_DAYS 窗口内）：只归一化，不清数据
        local nowTs = os.time()
        if savedTs > 0 and (savedTs + WAD.EVENT_DAYS * 86400 > nowTs) then
            data.startDate = expectedStart
        else
            -- 旧周期确实过期或存档日期无效，才真正重置
            data.startDate = expectedStart
            data.score = 0
            data.round = 1
            data.claimed = {}
            -- 同步重置限时福利的广告计数
            local okWF, WelfareData = pcall(require, "Game.WelfareData")
            if okWF and WelfareData.ResetAll then
                WelfareData.ResetAll()
            end
        end
    end
end

--- 活动是否在有效期内
---@return boolean
function WAD.IsActive()
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    return data.round <= WAD.MAX_ROUNDS
end

--- 获取剩余天数
---@return number
function WAD.GetRemainingDays()
    local data = WAD.EnsureData()
    if not data.startDate or data.startDate == "" then return WAD.EVENT_DAYS end
    local startY, startM, startD = data.startDate:match("(%d+)-(%d+)-(%d+)")
    if not startY then return WAD.EVENT_DAYS end
    local startTime = os.time({ year = tonumber(startY), month = tonumber(startM),
                                day = tonumber(startD), hour = 0 })
    local endTime = startTime + WAD.EVENT_DAYS * 86400
    local remaining = math.ceil((endTime - os.time()) / 86400)
    return math.max(0, remaining)
end

--- 获取剩余时间字符串（X天XX小时）
---@return string
function WAD.GetRemainingTimeStr()
    local data = WAD.EnsureData()
    if not data.startDate or data.startDate == "" then return WAD.EVENT_DAYS .. "天00小时" end
    local startY, startM, startD = data.startDate:match("(%d+)-(%d+)-(%d+)")
    if not startY then return WAD.EVENT_DAYS .. "天00小时" end
    local startTime = os.time({ year = tonumber(startY), month = tonumber(startM),
                                day = tonumber(startD), hour = 0 })
    local endTime = startTime + WAD.EVENT_DAYS * 86400
    local remainSec = math.max(0, endTime - os.time())
    local days = math.floor(remainSec / 86400)
    local hours = math.floor((remainSec % 86400) / 3600)
    return days .. "天" .. string.format("%02d", hours) .. "小时"
end

-- ============================================================================
-- 积分 & 轮数
-- ============================================================================

--- 获取当前累计总积分
---@return number
function WAD.GetScore()
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    return data.score
end

--- 获取当前轮有效积分（去掉前几轮已消耗的部分）
---@return number
function WAD.GetRoundScore()
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    -- 全部轮次已完成，显示满分
    if data.round > WAD.MAX_ROUNDS then
        return WAD.ROUND_MAX
    end
    local roundOffset = (data.round - 1) * WAD.ROUND_MAX
    return math.min(WAD.ROUND_MAX, math.max(0, data.score - roundOffset))
end

--- 获取当前轮数
---@return number
function WAD.GetRound()
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    return data.round
end

--- 添加积分（由宝箱系统 hook 调用）
--- 自动检查里程碑，达标后发放奖励到邮件
---@param amount number
function WAD.AddScore(amount)
    -- 只在宝箱周计分（与招募周 RMD.AddCount 对称）
    if WAD.GetCurrentWeekType() ~= "chest" then return end
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    if data.round > WAD.MAX_ROUNDS then return end  -- 已完成全部轮数
    -- 封顶：总积分不超过 MAX_ROUNDS × ROUND_MAX
    local maxTotal = WAD.MAX_ROUNDS * WAD.ROUND_MAX
    data.score = math.min(data.score + amount, maxTotal)

    -- 自动检查并发放已达标的里程碑奖励到邮件
    WAD._AutoClaimToMailbox(data)
end

--- 自动将已达标未领取的里程碑奖励发放到邮件
---@param data table
function WAD._AutoClaimToMailbox(data)
    if data.round > WAD.MAX_ROUNDS then return end
    local anyClaimed = false
    local roundOffset = (data.round - 1) * WAD.ROUND_MAX
    local roundScore = math.max(0, data.score - roundOffset)

    for i, milestone in ipairs(WAD.MILESTONES) do
        if roundScore >= milestone.threshold and not data.claimed[i] then
            data.claimed[i] = true
            anyClaimed = true

            -- 发放到邮件
            MailboxData.Add({
                title = "单周活动奖励",
                desc = milestone.threshold .. "积分达标奖励（第" .. data.round .. "轮）",
                rewards = milestone.rewards,
            })

            Toast.Show("活动达标: " .. milestone.threshold .. "积分! 奖励已发送到邮件", { 255, 200, 60 })
            print("[WeeklyActivity] Auto-claimed milestone " .. i .. " to mailbox: " .. milestone.threshold)
        end
    end

    if anyClaimed then
        -- 检查是否本轮全部领完 → 进入下一轮
        local allClaimed = true
        for i = 1, #WAD.MILESTONES do
            if not data.claimed[i] then allClaimed = false; break end
        end
        if allClaimed then
            data.round = data.round + 1
            data.claimed = {}
            print("[WeeklyActivity] Round completed! Now round " .. data.round)
        end
        HeroData.Save()
    end
end

-- ============================================================================
-- 里程碑奖励
-- ============================================================================

--- 获取里程碑状态
---@param index number
---@return boolean canClaim, boolean claimed, boolean reached
function WAD.GetMilestoneStatus(index)
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    local milestone = WAD.MILESTONES[index]
    if not milestone then return false, false, false end
    local claimed = data.claimed[index] or false
    local roundOffset = (data.round - 1) * WAD.ROUND_MAX
    local roundScore = math.max(0, data.score - roundOffset)
    local reached = roundScore >= milestone.threshold
    return reached and not claimed, claimed, reached
end

--- 是否有可领取奖励（红点 - 积分已达到门槛且未领取时才显示）
---@return boolean
function WAD.HasClaimable()
    local data = WAD.EnsureData()
    CheckWeekReset(data)
    if data.round > WAD.MAX_ROUNDS then return false end
    local roundOffset = (data.round - 1) * WAD.ROUND_MAX
    local roundScore = math.max(0, data.score - roundOffset)
    for i, m in ipairs(WAD.MILESTONES) do
        if roundScore >= m.threshold and not (data.claimed[i] or false) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("weeklyActivityData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.weeklyActivityData
    end,
    deserialize = function(saved, _saveData)
        HeroData.weeklyActivityData = saved or nil
    end,
})

return WAD
