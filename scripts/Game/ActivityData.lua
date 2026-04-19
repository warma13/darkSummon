-- Game/ActivityData.lua
-- 活动系统数据管理 - 每日签到（30天循环）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local SaveRegistry = require("Game.SaveRegistry")

local ActivityData = {}

-- ============================================================================
-- 签到奖励配置（30天固定周期，5天轮换）
-- ============================================================================

-- 签到总天数
local CYCLE_DAYS = 30

-- 三种动态递增货币的基础值和每次递增量
local DYNAMIC_CURRENCIES = {
    shadow_essence = { base = 50,  increment = 10 },
    devour_stone   = { base = 100, increment = 20 },
    forge_iron     = { base = 200, increment = 40 },
}

-- 货币中文名映射
local CURRENCY_NAMES = {
    shadow_essence = "暗影精粹",
    devour_stone   = "噬魂石",
    forge_iron     = "锻魂铁",
    ur_shard_box   = "万能UR碎片箱",
}

-- 5天一轮的奖励模板（动态货币不写 amount，运行时计算）
local CYCLE_PATTERN = {
    { type = "currency", id = "shadow_essence" },       -- 第1天
    { type = "currency", id = "devour_stone" },         -- 第2天
    { type = "currency", id = "shadow_essence" },       -- 第3天
    { type = "currency", id = "forge_iron" },           -- 第4天
    { type = "item",     id = "ur_shard_box", amount = 2 },  -- 第5天
}

-- 预计算30天的实际奖励（含动态数量）
ActivityData.SIGN_IN_REWARDS = {}
do
    local occurrenceCount = {}  -- 每种动态货币已出现次数
    for day = 1, CYCLE_DAYS do
        local reward = { day = day }
        if day == CYCLE_DAYS then
            -- 第30天：全勤奖 - 万能UR碎片箱×5
            reward.type = "item"
            reward.id = "ur_shard_box"
            reward.amount = 5
        else
            -- 5天轮换
            local patternIdx = ((day - 1) % 5) + 1
            local tmpl = CYCLE_PATTERN[patternIdx]
            reward.type = tmpl.type
            reward.id = tmpl.id
            -- 动态货币：根据出现次数计算递增数量
            local dyn = DYNAMIC_CURRENCIES[tmpl.id]
            if dyn then
                occurrenceCount[tmpl.id] = (occurrenceCount[tmpl.id] or 0) + 1
                local n = occurrenceCount[tmpl.id]
                reward.amount = dyn.base + (n - 1) * dyn.increment
            else
                reward.amount = tmpl.amount
            end
        end
        -- 生成 label
        local name = CURRENCY_NAMES[reward.id]
        if name then
            reward.label = name .. "×" .. reward.amount
        else
            reward.label = "奖励"
        end
        ActivityData.SIGN_IN_REWARDS[day] = reward
    end
end

-- ============================================================================
-- 数据结构
-- ============================================================================
-- activityData = {
--   signIn = {
--     totalLogins = 7,              -- 累计登录天数（开游戏自动+1）
--     claimedCount = 5,             -- 已顺序领取到第几天
--     lastLoginDate = "2026-04-08", -- 上次登录日期（防同天重复计数）
--     cycleStart = "2026-03-10",    -- 本轮30天周期开始日期
--   }
-- }

--- 获取今天的日期字符串
---@return string  "YYYY-MM-DD"
local function TodayStr()
    return os.date("%Y-%m-%d")
end

--- 将 "YYYY-MM-DD" 转为 os.time 时间戳（当天0点）
---@param dateStr string
---@return number
local function DateToTime(dateStr)
    local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if not y then return 0 end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- 计算两个日期之间相差天数
---@param startDate string  "YYYY-MM-DD"
---@return number  经过的天数（今天 - startDate）
local function DaysSince(startDate)
    local t0 = DateToTime(startDate)
    local t1 = DateToTime(TodayStr())
    if t0 == 0 or t1 == 0 then return 0 end
    return math.floor((t1 - t0) / 86400)
end

--- 获取当前所在的30天周期起始日期（从开服日期起对齐）
---@return string "YYYY-MM-DD"
local function GetCurrentCycleStart()
    local t0 = DateToTime(Config.SERVER_START_DATE)
    local daysSince = math.max(0, math.floor((DateToTime(TodayStr()) - t0) / 86400))
    local cycleNum = math.floor(daysSince / CYCLE_DAYS)
    return os.date("%Y-%m-%d", t0 + cycleNum * CYCLE_DAYS * 86400)
end

--- 初始化默认数据
function ActivityData.InitDefault()
    return {
        signIn = {
            totalLogins = 0,
            claimedCount = 0,
            lastLoginDate = "",
            cycleStart = GetCurrentCycleStart(),  -- 本轮30天周期开始日期（开服对齐）
        },
    }
end

--- 从 HeroData 加载
function ActivityData.Load()
    local saved = HeroData.activityData
    if saved and saved.signIn and saved.signIn.totalLogins ~= nil then
        ActivityData.data = saved
        local si = ActivityData.data.signIn
        si.totalLogins = si.totalLogins or 0
        si.claimedCount = si.claimedCount or 0
        si.lastLoginDate = si.lastLoginDate or ""
        si.cycleStart = si.cycleStart or GetCurrentCycleStart()

        -- 兼容旧数据：如果存在 month 字段但没有 cycleStart，迁移
        if si.month and not saved.signIn.cycleStart then
            si.cycleStart = GetCurrentCycleStart()
            si.month = nil
        end

        -- 30天周期重置：当前周期起点与存储不一致时，判断旧周期是否真的过期
        local expectedCycleStart = GetCurrentCycleStart()
        if si.cycleStart ~= expectedCycleStart then
            local savedTs = DateToTime(si.cycleStart or "")
            local nowTs   = DateToTime(TodayStr())
            -- 旧周期未过期（savedTs有效且今天还在其30天窗口内）：只归一化，不清数据
            -- 这样无论 SERVER_START_DATE 如何调整，只要玩家的周期还没满30天就不清
            if savedTs > 0 and (savedTs + CYCLE_DAYS * 86400 > nowTs) then
                print("[ActivityData] Normalizing cycleStart: " .. (si.cycleStart or "") .. " -> " .. expectedCycleStart)
                si.cycleStart = expectedCycleStart
                ActivityData.Save()
            else
                -- 旧周期确实过期（满30天），或存档日期无效，才真正重置
                print("[ActivityData] New cycle started (" .. expectedCycleStart .. "), resetting sign-in")
                si.totalLogins = 0
                si.claimedCount = 0
                si.lastLoginDate = ""
                si.cycleStart = expectedCycleStart
                ActivityData.Save()
            end
        end
    else
        ActivityData.data = ActivityData.InitDefault()
    end

    -- 一次性补偿迁移：本期因代码变更导致签到天数不足的玩家，补到第7天
    local si2 = ActivityData.data.signIn
    if not si2._compV1 then
        if si2.totalLogins < 7 then
            si2.totalLogins = 7
            print("[ActivityData] compV1: restored totalLogins to 7")
        end
        si2._compV1 = true
        ActivityData.Save()
    end
end

--- 保存到 HeroData
function ActivityData.Save()
    HeroData.activityData = ActivityData.data
    HeroData.Save()
end

--- 记录今日登录（打开游戏/刷新活动页时自动调用，只加登录天数不领奖）
function ActivityData.MarkLogin()
    local si = ActivityData.data.signIn
    if si.lastLoginDate == TodayStr() then
        return -- 今天已记录过
    end
    si.totalLogins = si.totalLogins + 1
    -- 30天上限
    if si.totalLogins > CYCLE_DAYS then
        si.totalLogins = CYCLE_DAYS
    end
    si.lastLoginDate = TodayStr()
    ActivityData.Save()
    print("[ActivityData] MarkLogin: day " .. si.totalLogins)
end

--- 获取累计登录天数
---@return number
function ActivityData.GetTotalDays()
    return ActivityData.data.signIn.totalLogins
end

--- 获取已领取天数
---@return number
function ActivityData.GetClaimedCount()
    return ActivityData.data.signIn.claimedCount
end

--- 获取未领取天数
---@return number
function ActivityData.GetUnclaimedCount()
    local si = ActivityData.data.signIn
    return si.totalLogins - si.claimedCount
end

--- 获取当前周期剩余天数
---@return number
function ActivityData.GetRemainingDays()
    local si = ActivityData.data and ActivityData.data.signIn
    if not si or not si.cycleStart then return CYCLE_DAYS end
    return math.max(0, CYCLE_DAYS - DaysSince(si.cycleStart))
end

--- 指定天数是否已领取（day <= claimedCount 即已领取）
---@param day number 1-CYCLE_DAYS
---@return boolean
function ActivityData.IsDayClaimed(day)
    return day <= ActivityData.data.signIn.claimedCount
end

--- 指定天数是否已登录但未领取（claimedCount < day <= totalLogins）
---@param day number 1-CYCLE_DAYS
---@return boolean
function ActivityData.IsDayUnclaimed(day)
    local si = ActivityData.data.signIn
    return day > si.claimedCount and day <= si.totalLogins
end

--- 发放指定天的奖励
---@param day number
local function GrantReward(day)
    local reward = ActivityData.SIGN_IN_REWARDS[day]
    if reward then
        Currency.GrantReward(reward)
    end
    return reward
end

--- 签到：领取今天的奖励（仅当 unclaimed == 1 时调用）
---@return boolean success
---@return string msg
---@return table|nil claimedRewards  已领取的奖励列表 { {id, amount, type}, ... }
function ActivityData.SignIn()
    local si = ActivityData.data.signIn
    local unclaimed = si.totalLogins - si.claimedCount
    if unclaimed <= 0 then
        return false, "今日已签到"
    end

    si.claimedCount = si.claimedCount + 1
    local reward = GrantReward(si.claimedCount)
    ActivityData.Save()

    -- 开服好礼任务追踪
    local ok, LGD = pcall(require, "Game.LaunchGiftData")
    if ok and LGD then LGD.AddProgress("signin", 1) end
    -- 每日任务追踪
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("signin", 1) end

    local label = reward and reward.label or "签到奖励"
    print("[ActivityData] SignIn: claimed day " .. si.claimedCount .. " -> " .. label)
    local claimedRewards = reward and { { id = reward.id, amount = reward.amount, type = reward.type } } or nil
    return true, label, claimedRewards
end

--- 领取全部：一次性领取所有未领取的天
---@return boolean success
---@return string msg
---@return table|nil claimedRewards  已领取的奖励列表 { {id, amount, type}, ... }
function ActivityData.ClaimAll()
    local si = ActivityData.data.signIn
    local unclaimed = si.totalLogins - si.claimedCount
    if unclaimed <= 0 then
        return false, "没有可领取的奖励"
    end

    local labels = {}
    local claimedRewards = {}
    for _ = 1, unclaimed do
        si.claimedCount = si.claimedCount + 1
        local reward = GrantReward(si.claimedCount)
        if reward then
            labels[#labels + 1] = reward.label
            claimedRewards[#claimedRewards + 1] = { id = reward.id, amount = reward.amount, type = reward.type }
        end
    end
    ActivityData.Save()

    local msg = table.concat(labels, ", ")
    print("[ActivityData] ClaimAll: claimed " .. unclaimed .. " days -> " .. msg)
    return true, msg, claimedRewards
end

--- 获取当天奖励信息
---@param day number 1-30
---@return table|nil  reward def
function ActivityData.GetDayReward(day)
    return ActivityData.SIGN_IN_REWARDS[day]
end

--- 检查是否有可领取的签到（用于红点提示）
---@return boolean
function ActivityData.HasUnclaimedReward()
    return ActivityData.GetUnclaimedCount() > 0
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("activityData", {
    group = "meta_game",
    order = 60,
    serialize = function()
        return HeroData.activityData
    end,
    deserialize = function(saved, _saveData)
        HeroData.activityData = saved or nil
        ActivityData.Load()
    end,
})

return ActivityData
