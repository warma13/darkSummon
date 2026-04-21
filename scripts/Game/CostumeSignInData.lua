-- Game/CostumeSignInData.lua
-- 时装签到活动数据层
-- 活动持续14天，累积签到7次即可获得全部奖励（无需连续）

local Config       = require("Game.Config")
local HeroData     = require("Game.HeroData")
local Currency     = require("Game.Currency")
local SaveRegistry = require("Game.SaveRegistry")

local M = {}

-- ============================================================================
-- 活动配置
-- ============================================================================

M.EVENT_DAYS   = 14  -- 活动持续天数
M.MAX_SIGN_INS = 7   -- 累积签到次数上限（达到即完成，无需连续）

-- 7天奖励表（Day 7 为 SSR 时装大奖）
M.REWARDS = {
    [1] = { type = "currency", id = "shadow_essence", amount = 500 },
    [2] = { type = "currency", id = "nether_crystal",  amount = 10000 },
    [3] = { type = "currency", id = "shadow_essence", amount = 1500 },
    [4] = { type = "currency", id = "nether_crystal",  amount = 100000 },
    [5] = { type = "currency", id = "shadow_essence", amount = 3000 },
    [6] = { type = "currency", id = "nether_crystal",  amount = 500000 },
    [7] = { type = "costume",  id = "wing_shadow",  amount = 1 },
}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@type table|nil
local _data = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

local TodayStr = require("Game.DateUtil").TodayStr

---@param dateStr string
---@return number
local function DateToTime(dateStr)
    local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if not y then return 0 end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

---@param startDate string
---@return number 从 startDate 到今天的完整天数
local function DaysSince(startDate)
    local t0 = DateToTime(startDate)
    local t1 = DateToTime(TodayStr())
    if t0 <= 0 or t1 <= 0 then return 0 end
    return math.max(0, math.floor((t1 - t0) / 86400))
end

--- 获取活动起始日期（直接取配置，无需对齐计算）
---@return string "YYYY-MM-DD"
local function GetCurrentPeriodStart()
    return Config.COSTUME_SIGN_IN_START
end

local function DefaultData()
    return {
        startDate      = GetCurrentPeriodStart(),  -- 当前周期起始日（开服对齐）
        lastSignInDate = "",
        loginDays      = 0,
        claimedDays    = {},
    }
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 活动是否在有效期内（7天内）
---@return boolean
function M.IsEventActive()
    if not _data then return false end
    return DaysSince(_data.startDate) < M.EVENT_DAYS
end

--- 今天是否已手动签到
---@return boolean
function M.HasSignedInToday()
    if not _data then return false end
    return _data.lastSignInDate == TodayStr()
end

--- 今天是否可以签到
---@return boolean
function M.CanSignInToday()
    if not M.IsEventActive() then return false end
    if M.HasSignedInToday() then return false end
    return (_data.loginDays or 0) < M.MAX_SIGN_INS
end

--- 下一个待签到的天数（1-based，已全部完成时返回 MAX_SIGN_INS+1）
---@return number
function M.GetNextSignInDay()
    if not _data then return 1 end
    return math.min((_data.loginDays or 0) + 1, M.MAX_SIGN_INS + 1)
end

--- 累计签到天数
---@return number
function M.GetLoginDays()
    return _data and (_data.loginDays or 0) or 0
end

--- 指定天是否已领取
---@param day number
---@return boolean
function M.IsDayClaimed(day)
    if not _data or not _data.claimedDays then return false end
    for _, d in ipairs(_data.claimedDays) do
        if d == day then return true end
    end
    return false
end

--- 是否有红点（今天可签到）
---@return boolean
function M.HasClaimable()
    return M.CanSignInToday()
end

--- 获取某天的奖励定义
---@param day number
---@return table|nil
function M.GetDayReward(day)
    return M.REWARDS[day]
end

--- 剩余活动天数（0 = 已结束）
---@return number
function M.GetRemainingDays()
    if not _data then return 0 end
    return math.max(0, M.EVENT_DAYS - DaysSince(_data.startDate))
end

-- ============================================================================
-- 操作接口
-- ============================================================================

--- 手动签到并即时领取当天奖励
---@return boolean
---@return string
---@return table|nil
function M.SignInToday()
    if not M.IsEventActive() then return false, "活动已结束", nil end
    if M.HasSignedInToday() then return false, "今日已签到", nil end
    if (_data.loginDays or 0) >= M.MAX_SIGN_INS then return false, "签到已全部完成", nil end

    -- 累积签到天数 +1，记录签到日期
    _data.loginDays      = (_data.loginDays or 0) + 1
    _data.lastSignInDate = TodayStr()

    local day    = _data.loginDays
    local reward = M.REWARDS[day]

    -- 发放奖励
    if reward then
        if reward.type == "currency" then
            Currency.Add(reward.id, reward.amount)
        elseif reward.type == "costume" then
            local ok2, CD = pcall(require, "Game.CostumeData")
            if ok2 and CD.Unlock then
                CD.Unlock(reward.id)
            end
        end
        _data.claimedDays[#_data.claimedDays + 1] = day
    end

    M.Save()

    -- 开服好礼任务追踪
    local okL, LGD = pcall(require, "Game.LaunchGiftData")
    if okL and LGD then LGD.AddProgress("signin", 1) end
    -- 每日任务追踪
    local okD, DTD = pcall(require, "Game.DailyTaskData")
    if okD and DTD then DTD.AddProgress("signin", 1) end

    return true, "签到成功", reward
end

-- ============================================================================
-- 持久化
-- ============================================================================

function M.Save()
    HeroData.costumeSignInData = _data
    HeroData.Save()
end

-- ============================================================================
-- SaveRegistry 注册
-- ============================================================================

SaveRegistry.Register("costumeSignInData", {
    group = "meta_game",
    order = 56,
    initDefault = function()
        _data = DefaultData()
        HeroData.costumeSignInData = nil
    end,
    serialize = function()
        return _data
    end,
    deserialize = function(saved)
        if saved and type(saved) == "table" and saved.startDate then
            _data = saved
            _data.loginDays      = _data.loginDays or 0
            _data.lastSignInDate = _data.lastSignInDate or _data.lastLoginDate or ""
            _data.claimedDays    = _data.claimedDays or {}
            -- 进入新的14天周期时重置
            local expectedStart = GetCurrentPeriodStart()
            if _data.startDate ~= expectedStart then
                local savedTs  = DateToTime(_data.startDate or "")
                local expectTs = DateToTime(expectedStart)
                -- 旧周期未过期（今天仍在 savedTs + EVENT_DAYS 窗口内）：只归一化，不清数据
                local nowTs = os.time()
                if savedTs > 0 and (savedTs + M.EVENT_DAYS * 86400 > nowTs) then
                    _data.startDate = expectedStart
                else
                    _data = DefaultData()
                end
            end
        else
            _data = DefaultData()
        end
        HeroData.costumeSignInData = _data
    end,
})

return M
