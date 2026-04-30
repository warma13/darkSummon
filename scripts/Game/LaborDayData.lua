-- Game/LaborDayData.lua
-- 劳动节限时签到活动数据模块（5.1 ~ 5.7 共7天）

local HeroData     = require("Game.HeroData")
local Currency     = require("Game.Currency")
local MailboxData  = require("Game.MailboxData")
local SaveRegistry = require("Game.SaveRegistry")
local Toast        = require("Game.Toast")
local DateUtil     = require("Game.DateUtil")

local LDD = {}

-- ============================================================================
-- 活动时间配置
-- ============================================================================

--- 活动开始日期（含）
LDD.START_DATE = "2026-05-01"
--- 活动结束日期（含，共7天）
LDD.END_DATE   = "2026-05-07"
--- 签到总天数
LDD.TOTAL_DAYS = 7

-- ============================================================================
-- 签到奖励配置（7天递增，第7天大奖）
-- ============================================================================

LDD.REWARDS = {
    {
        day = 1,
        label = "暗影精粹×500",
        rewards = { { type = "currency", id = "shadow_essence", amount = 500 } },
    },
    {
        day = 2,
        label = "锻魂铁×2000",
        rewards = { { type = "currency", id = "forge_iron", amount = 2000 } },
    },
    {
        day = 3,
        label = "深渊结晶×5",
        rewards = { { type = "currency", id = "abyss_crystal", amount = 5 } },
    },
    {
        day = 4,
        label = "招募券×3",
        rewards = { { type = "item", id = "recruit_ticket_select_box", amount = 3 } },
    },
    {
        day = 5,
        label = "暗影精粹×1500",
        rewards = { { type = "currency", id = "shadow_essence", amount = 1500 } },
    },
    {
        day = 6,
        label = "随机神话符文箱×1",
        rewards = { { type = "item", id = "random_mythic_rune_box", amount = 1 } },
    },
    {
        day = 7,
        label = "万能UR碎片箱×3 + 暗影精粹×3000",
        rewards = {
            { type = "item",     id = "ur_shard_box",    amount = 3 },
            { type = "currency", id = "shadow_essence",  amount = 3000 },
        },
    },
}

-- ============================================================================
-- 时间工具
-- ============================================================================

---@param dateStr string "YYYY-MM-DD"
---@return number
local function DateToTime(dateStr)
    local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if not y then return 0 end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- 活动是否正在进行
---@return boolean
function LDD.IsActive()
    local today = DateUtil.TodayStr()
    return today >= LDD.START_DATE and today <= LDD.END_DATE
end

--- 活动是否已结束
---@return boolean
function LDD.IsExpired()
    return DateUtil.TodayStr() > LDD.END_DATE
end

--- 获取活动剩余时间字符串
---@return string
function LDD.GetRemainingTimeStr()
    if not LDD.IsActive() then return "已结束" end
    local endTs = DateToTime(LDD.END_DATE) + 86400 -- 结束日当天24:00
    local remainSec = math.max(0, endTs - os.time())
    local days = math.floor(remainSec / 86400)
    local hours = math.floor((remainSec % 86400) / 3600)
    return days .. "天" .. string.format("%02d", hours) .. "小时"
end

--- 获取活动已进行的天数（从第1天开始）
---@return number
function LDD.GetEventDay()
    local startTs = DateToTime(LDD.START_DATE)
    local todayTs = DateToTime(DateUtil.TodayStr())
    local day = math.floor((todayTs - startTs) / 86400) + 1
    return math.max(1, math.min(day, LDD.TOTAL_DAYS))
end

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 确保数据结构存在
---@return table
function LDD.EnsureData()
    if not HeroData.laborDayData then
        HeroData.laborDayData = {
            signedDays = {},       -- { ["2026-05-01"] = true, ... }
            claimedDays = {},      -- { [1] = true, [2] = true, ... }
            lastSignDate = "",
            doubleDate  = "",      -- 翻倍计数的日期
            doubleUsed  = 0,       -- 当天已使用翻倍次数
        }
    end
    -- 兼容旧存档
    local d = HeroData.laborDayData
    if d.doubleDate == nil then d.doubleDate = "" end
    if d.doubleUsed == nil then d.doubleUsed = 0 end
    return d
end

--- 今天是否已签到
---@return boolean
function LDD.HasSignedToday()
    local data = LDD.EnsureData()
    return data.signedDays[DateUtil.TodayStr()] == true
end

--- 获取已签到天数
---@return number
function LDD.GetSignedCount()
    local data = LDD.EnsureData()
    local count = 0
    for _ in pairs(data.signedDays) do
        count = count + 1
    end
    return count
end

--- 签到（每天只能签一次）
---@return boolean success
function LDD.SignIn()
    if not LDD.IsActive() then return false end
    if LDD.HasSignedToday() then return false end

    local data = LDD.EnsureData()
    local today = DateUtil.TodayStr()
    data.signedDays[today] = true
    data.lastSignDate = today

    -- 自动领取对应天数的奖励
    local signedCount = LDD.GetSignedCount()
    local reward = LDD.REWARDS[signedCount]
    if reward and not data.claimedDays[signedCount] then
        data.claimedDays[signedCount] = true
        -- 发放奖励到邮箱
        MailboxData.Add({
            title = "劳动节签到奖励",
            desc = "第" .. signedCount .. "天签到奖励",
            rewards = reward.rewards,
        })
        Toast.Show("签到成功！第" .. signedCount .. "天奖励已发送到邮箱", { 255, 200, 60 })
    end

    local okLM, LMD2 = pcall(require, "Game.LaborMedalData")
    if okLM then LMD2.EarnMedals("labor_signin") end

    HeroData.Save()
    return true
end

--- 第 N 天奖励的状态
---@param dayIndex number 1~7
---@return string "locked"|"available"|"claimed"|"missed"
function LDD.GetDayStatus(dayIndex)
    local data = LDD.EnsureData()
    -- 已领取
    if data.claimedDays[dayIndex] then return "claimed" end
    -- 当前签到数 >= dayIndex → 已解锁可领
    local signedCount = LDD.GetSignedCount()
    if signedCount >= dayIndex then return "available" end
    -- 活动中且今天可签到 → 如果签了就够解锁这天
    if LDD.IsActive() and not LDD.HasSignedToday() and (signedCount + 1) >= dayIndex then
        return "available"
    end
    -- 活动已结束且未解锁
    if LDD.IsExpired() then return "missed" end
    -- 活动中但还没到
    return "locked"
end

--- 是否有可操作项（红点：可签到或有未领取奖励）
---@return boolean
function LDD.HasClaimable()
    if not LDD.IsActive() then return false end
    return not LDD.HasSignedToday()
end

-- ============================================================================
-- 劳动加倍：全服收益翻倍
-- ============================================================================

--- 每日翻倍次数上限
LDD.DOUBLE_DAILY_LIMIT = 10

--- 获取今日剩余翻倍次数
---@return number
function LDD.GetDoubleRemaining()
    if not LDD.IsActive() then return 0 end
    local data = LDD.EnsureData()
    local today = DateUtil.TodayStr()
    if data.doubleDate ~= today then
        return LDD.DOUBLE_DAILY_LIMIT
    end
    return math.max(0, LDD.DOUBLE_DAILY_LIMIT - data.doubleUsed)
end

--- 今日已使用翻倍次数
---@return number
function LDD.GetDoubleUsed()
    local data = LDD.EnsureData()
    local today = DateUtil.TodayStr()
    if data.doubleDate ~= today then return 0 end
    return data.doubleUsed
end

--- 消耗一次翻倍机会，返回实际倍率（有次数=2，无次数=1）
---@return number multiplier
function LDD.ConsumeDouble()
    if not LDD.IsActive() then return 1 end
    local data = LDD.EnsureData()
    local today = DateUtil.TodayStr()
    -- 跨天重置
    if data.doubleDate ~= today then
        data.doubleDate = today
        data.doubleUsed = 0
    end
    if data.doubleUsed >= LDD.DOUBLE_DAILY_LIMIT then
        return 1
    end
    data.doubleUsed = data.doubleUsed + 1
    return 2
end

--- 对一个数量应用翻倍（消耗一次翻倍机会）
--- ⚠️ 一次结算涉及多种货币时，请改用 ApplyToMap / ConsumeDouble 以避免多次消耗
---@param amount number 原始数量
---@return number 翻倍后的数量
function LDD.ApplyMultiplier(amount)
    local mult = LDD.ConsumeDouble()
    return math.floor(amount * mult)
end

--- 对一组 key=amount 的表统一应用翻倍（只消耗一次机会）
--- 例: ApplyToMap({ gold = 100, gem = 5 }) → { gold = 200, gem = 10 }
---@param map table<string, number>
---@return table<string, number> 同一个表（原地修改）
function LDD.ApplyToMap(map)
    local mult = LDD.ConsumeDouble()
    if mult <= 1 then return map end
    for k, v in pairs(map) do
        if type(v) == "number" then
            map[k] = math.floor(v * mult)
        end
    end
    return map
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("laborDayData", {
    group = "meta_game",
    order = 75,
    serialize = function()
        return HeroData.laborDayData
    end,
    deserialize = function(saved, _saveData)
        HeroData.laborDayData = saved or nil
    end,
})

return LDD
