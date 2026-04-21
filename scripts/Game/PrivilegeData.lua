-- Game/PrivilegeData.lua
-- 尊享特权数据模块 - 福利卡 / 周卡 / 月卡 / 终身卡
-- 通过观看广告解锁，解锁后每日可领取奖励

local Config = require("Game.Config")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local TodayStr = require("Game.DateUtil").TodayStr

local PrivilegeData = {}

-- ============================================================================
-- 卡片定义
-- ============================================================================
PrivilegeData.CARDS = {
    {
        id          = "welfare",
        name        = "福利卡",
        adsRequired = 0,     -- 免费
        -- 解锁立得
        instant     = {},
        -- 被动增益（显示用，实际由 AFK/战斗系统读取）
        buffs       = {},
        -- 每日可领
        daily       = {
            { currency = "shadow_essence", amount = 10 },
        },
    },
    {
        id          = "weekly",
        name        = "周卡",
        adsRequired = 7,
        duration    = 7,          -- 解锁后有效天数
        buffLabel   = "7天增益",
        instant     = {
            { currency = "shadow_essence", amount = 80 },
        },
        buffs       = {
            "挂机冥晶收益+10%",
            "挂机收益10%概率翻倍",
        },
        daily       = {
            { currency = "shadow_essence", amount = 200 },
            { currency = "bronze_chest",   amount = 1, label = "青铜宝箱", rewardType = "chest", chestId = "bronze" },
        },
    },
    {
        id          = "monthly",
        name        = "月卡",
        adsRequired = 15,
        duration    = 30,         -- 解锁后有效天数
        buffLabel   = "30天增益",
        instant     = {
            { currency = "shadow_essence", amount = 300 },
        },
        buffs       = {
            "挂机收益增加2小时",
            "挂机收益10%概率翻倍",
        },
        daily       = {
            { currency = "shadow_essence", amount = 200 },
            { currency = "devour_stone",   amount = 100 },
            { currency = "void_pact",      amount = 1 },
        },
    },
    {
        id          = "lifetime",
        name        = "终身卡",
        adsRequired = 100,
        dailyAdLimit = 10,    -- 每天最多看10次广告
        buffLabel   = "永久增益",
        instant     = {
            { currency = "shadow_essence", amount = 1280 },
        },
        buffs       = {
            "挂机收益增加2小时",
            "挂机冥晶收益+10%",
        },
        daily       = {
            { currency = "shadow_essence", amount = 200 },
            { currency = "devour_stone",   amount = 200 },
            { currency = "void_pact",      amount = 3 },
        },
    },
}

-- ============================================================================
-- 数据访问
-- ============================================================================
local function EnsureData()
    if not HeroData.activityData then
        HeroData.activityData = {}
    end
    if not HeroData.activityData.privilege then
        HeroData.activityData.privilege = {}
    end
    return HeroData.activityData.privilege
end

local function GetCardData(cardId)
    local data = EnsureData()
    if not data[cardId] then
        data[cardId] = {
            adsWatched     = 0,       -- 已观看广告数
            unlocked       = false,   -- 是否已解锁
            instantClaimed = false,   -- 解锁奖励是否已领
            lastClaimDate  = nil,     -- 上次每日领取日期 "YYYY-MM-DD"
            unlockDate     = nil,     -- 解锁日期 "YYYY-MM-DD"（用于过期计算）
            todayAdsWatched = 0,      -- 今日已看广告数
            lastAdDate      = nil,    -- 上次看广告日期 "YYYY-MM-DD"
        }
    end
    return data[cardId]
end

--- 计算日期差（天数），a - b
---@param dateA string "YYYY-MM-DD"
---@param dateB string "YYYY-MM-DD"
---@return number
local function DaysBetween(dateA, dateB)
    local yA, mA, dA = dateA:match("(%d+)-(%d+)-(%d+)")
    local yB, mB, dB = dateB:match("(%d+)-(%d+)-(%d+)")
    if not yA or not yB then return 0 end
    local tA = os.time({ year = tonumber(yA), month = tonumber(mA), day = tonumber(dA), hour = 0 })
    local tB = os.time({ year = tonumber(yB), month = tonumber(mB), day = tonumber(dB), hour = 0 })
    return math.floor((tA - tB) / 86400)
end

--- 检查卡片是否已过期，过期则重置
---@param cardId string
local function CheckExpired(cardId)
    local cd = GetCardData(cardId)
    if not cd.unlocked then return end
    local def = PrivilegeData.GetCardDef(cardId)
    if not def or not def.duration then return end -- 无 duration = 永久
    if not cd.unlockDate then
        -- 兼容旧数据：没有 unlockDate 的已解锁卡，从今天开始算
        cd.unlockDate = TodayStr()
        PrivilegeData.Save()
        return
    end
    local elapsed = DaysBetween(TodayStr(), cd.unlockDate)
    if elapsed >= def.duration then
        -- 过期重置
        print("[Privilege] " .. cardId .. " expired after " .. elapsed .. " days, resetting")
        cd.adsWatched = 0
        cd.unlocked = false
        cd.instantClaimed = false
        cd.unlockDate = nil
        cd.lastClaimDate = nil
        PrivilegeData.Save()
    end
end

function PrivilegeData.Load()
    EnsureData()
    -- 检查所有卡片是否过期
    for _, c in ipairs(PrivilegeData.CARDS) do
        if c.duration then
            CheckExpired(c.id)
        end
    end
end

function PrivilegeData.Save()
    HeroData.Save()
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 获取卡片定义
---@param cardId string
---@return table|nil
function PrivilegeData.GetCardDef(cardId)
    for _, c in ipairs(PrivilegeData.CARDS) do
        if c.id == cardId then return c end
    end
    return nil
end

--- 卡片是否已解锁（会自动检查过期）
function PrivilegeData.IsUnlocked(cardId)
    -- 福利卡默认解锁
    if cardId == "welfare" then return true end
    CheckExpired(cardId)
    local cd = GetCardData(cardId)
    return cd.unlocked == true
end

--- 已看广告数
function PrivilegeData.GetAdsWatched(cardId)
    local cd = GetCardData(cardId)
    return cd.adsWatched or 0
end

--- 重置每日广告计数（跨天时自动调用）
local function ResetDailyAdIfNeeded(cardId)
    local cd = GetCardData(cardId)
    local today = TodayStr()
    if cd.lastAdDate ~= today then
        cd.todayAdsWatched = 0
        cd.lastAdDate = today
    end
end

--- 获取今日剩余可看广告次数（无每日上限返回 -1）
function PrivilegeData.GetDailyAdsRemaining(cardId)
    local def = PrivilegeData.GetCardDef(cardId)
    if not def or not def.dailyAdLimit then return -1 end
    ResetDailyAdIfNeeded(cardId)
    local cd = GetCardData(cardId)
    return math.max(0, def.dailyAdLimit - (cd.todayAdsWatched or 0))
end

--- 今日是否已达广告上限
function PrivilegeData.IsDailyAdLimitReached(cardId)
    local remaining = PrivilegeData.GetDailyAdsRemaining(cardId)
    return remaining == 0
end

--- 能否继续看广告（未满即可，各卡独立解锁）
function PrivilegeData.CanWatchAd(cardId)
    if PrivilegeData.IsUnlocked(cardId) then return false end
    -- 检查每日上限
    if PrivilegeData.IsDailyAdLimitReached(cardId) then return false end
    return true
end

--- 观看一次广告
function PrivilegeData.RecordAdWatch(cardId)
    if not PrivilegeData.CanWatchAd(cardId) then
        return false, "无法观看"
    end
    local cd = GetCardData(cardId)
    local def = PrivilegeData.GetCardDef(cardId)
    cd.adsWatched = (cd.adsWatched or 0) + 1
    -- 更新每日广告计数
    ResetDailyAdIfNeeded(cardId)
    cd.todayAdsWatched = (cd.todayAdsWatched or 0) + 1
    if cd.adsWatched >= def.adsRequired then
        cd.unlocked = true
        cd.unlockDate = TodayStr()
    end
    PrivilegeData.Save()
    return true
end

--- 获取卡片剩余有效天数（-1 表示永久，0 表示今天最后一天）
---@param cardId string
---@return number|nil  nil=未解锁, -1=永久, 0~N=剩余天数
function PrivilegeData.GetRemainingDays(cardId)
    local cd = GetCardData(cardId)
    if not cd.unlocked then return nil end
    local def = PrivilegeData.GetCardDef(cardId)
    if not def or not def.duration then return -1 end -- 永久
    if not cd.unlockDate then return def.duration end -- 兼容旧数据
    local elapsed = DaysBetween(TodayStr(), cd.unlockDate)
    local remaining = def.duration - elapsed
    if remaining < 0 then remaining = 0 end
    return remaining
end

--- 解锁奖励是否已领取
function PrivilegeData.IsInstantClaimed(cardId)
    local cd = GetCardData(cardId)
    return cd.instantClaimed == true
end

--- 领取解锁奖励
function PrivilegeData.ClaimInstant(cardId)
    if not PrivilegeData.IsUnlocked(cardId) then return false, "未解锁" end
    local cd = GetCardData(cardId)
    if cd.instantClaimed then return false, "已领取" end
    local def = PrivilegeData.GetCardDef(cardId)
    if not def then return false, "卡片不存在" end
    local displayRewards = {}
    for _, r in ipairs(def.instant) do
        local grantType = r.rewardType or "currency"
        local grantId = r.chestId or r.currency
        Currency.GrantReward({ type = grantType, id = grantId, amount = r.amount })
        local cdef = Config.CURRENCY[r.currency]
        displayRewards[#displayRewards + 1] = {
            icon = Currency.GetImage(r.currency),
            name = r.label or (cdef and cdef.name or r.currency),
            amount = r.amount,
        }
    end
    cd.instantClaimed = true
    PrivilegeData.Save()
    return true, "解锁奖励已发放", displayRewards
end

--- 今日是否已领取每日奖励
function PrivilegeData.IsDailyClaimed(cardId)
    local cd = GetCardData(cardId)
    local today = TodayStr()
    return cd.lastClaimDate == today
end

--- 能否领取每日奖励
function PrivilegeData.CanClaimDaily(cardId)
    if not PrivilegeData.IsUnlocked(cardId) then return false end
    if PrivilegeData.IsDailyClaimed(cardId) then return false end
    return true
end

--- 领取每日奖励
function PrivilegeData.ClaimDaily(cardId)
    if not PrivilegeData.CanClaimDaily(cardId) then
        return false, "无法领取"
    end
    local def = PrivilegeData.GetCardDef(cardId)
    if not def then return false, "卡片不存在" end
    local displayRewards = {}
    local names = {}
    for _, r in ipairs(def.daily) do
        local grantType = r.rewardType or "currency"
        local grantId = r.chestId or r.currency
        Currency.GrantReward({ type = grantType, id = grantId, amount = r.amount })
        local cdef = Config.CURRENCY[r.currency]
        local name = r.label or (cdef and cdef.name or r.currency)
        names[#names + 1] = name .. "×" .. r.amount
        displayRewards[#displayRewards + 1] = {
            icon = Currency.GetImage(r.currency),
            name = name,
            amount = r.amount,
        }
    end
    local cd = GetCardData(cardId)
    cd.lastClaimDate = TodayStr()
    PrivilegeData.Save()
    return true, table.concat(names, "、"), displayRewards
end

-- ============================================================================
-- 增益查询（供 AFK / 战斗系统调用）
-- ============================================================================

--- 获取挂机时长上限加成（秒）。月卡/终身卡各+2小时，可叠加
function PrivilegeData.GetIdleExtraSeconds()
    local extra = 0
    if PrivilegeData.IsUnlocked("monthly")  then extra = extra + 2 * 3600 end
    if PrivilegeData.IsUnlocked("lifetime") then extra = extra + 2 * 3600 end
    return extra
end

--- 获取冥晶收益加成倍率。周卡/终身卡各+10%，可叠加
function PrivilegeData.GetCrystalBonusRate()
    local bonus = 0
    if PrivilegeData.IsUnlocked("weekly")   then bonus = bonus + 0.10 end
    if PrivilegeData.IsUnlocked("lifetime") then bonus = bonus + 0.10 end
    return 1.0 + bonus
end

--- 获取"收益翻倍"概率。周卡/月卡各10%，可叠加
function PrivilegeData.GetDoubleChance()
    local chance = 0
    if PrivilegeData.IsUnlocked("weekly")  then chance = chance + 0.10 end
    if PrivilegeData.IsUnlocked("monthly") then chance = chance + 0.10 end
    return chance
end

return PrivilegeData
