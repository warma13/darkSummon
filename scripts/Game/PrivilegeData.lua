-- Game/PrivilegeData.lua
-- 双轨特权系统：
-- 1) 尊享卡（福利卡 / 周卡 / 月卡 / 终身卡）— 广告解锁，每日领奖
-- 2) 渐进式特权卡（青铜 → 红宝石）— 每天看满 20 次广告 +1 点，累计解锁

local Config   = require("Game.Config")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local TodayStr = require("Game.DateUtil").TodayStr

local PrivilegeData = {}

-- ============================================================================
-- 一、尊享卡定义（广告解锁 + 每日领取）
-- ============================================================================
PrivilegeData.CARDS = {
    {
        id          = "welfare",
        name        = "福利卡",
        adsRequired = 0,     -- 免费
        instant     = {},
        buffs       = {},
        daily       = {
            { currency = "shadow_essence", amount = 10 },
        },
    },
    {
        id          = "weekly",
        name        = "周卡",
        adsRequired = 7,
        duration    = 7,
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
        duration    = 30,
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
        dailyAdLimit = 10,
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
-- 二、渐进式特权卡定义（积分解锁 buff）
-- ============================================================================
PrivilegeData.TIER_CARDS = {
    { id = "bronze",   name = "青铜卡",   threshold = 3,   color = { 205, 127,  50 } },
    { id = "silver",   name = "白银卡",   threshold = 7,   color = { 192, 192, 192 } },
    { id = "gold",     name = "黄金卡",   threshold = 20,  color = { 255, 215,   0 } },
    { id = "platinum", name = "铂金卡",   threshold = 40,  color = { 180, 200, 220 } },
    { id = "diamond",  name = "钻石卡",   threshold = 100, color = { 100, 200, 255 } },
    { id = "ruby",     name = "红宝石卡", threshold = 200, color = { 255,  50,  80 } },
}

-- buff 索引常量
local BUFF_IDLE     = 1  -- 挂机时长（秒）
local BUFF_CRYSTAL  = 2  -- 冥晶收益加成（小数）
local BUFF_DOUBLE   = 3  -- 收益翻倍概率（小数）
local BUFF_CHEST    = 4  -- 宝箱掉率加成（小数）
local BUFF_SHARD    = 5  -- 碎片掉率加成（小数）
local BUFF_DUNGEON  = 6  -- 副本额外次数
local BUFF_ABYSS    = 7  -- 深渊裂隙额外次数
local BUFF_BOSS     = 8  -- 世界Boss额外次数

-- 各等级 buff 数值表
local TIER_BUFFS = {
    --  idle(秒)   crystal  double  chest   shard   dungeon abyss  boss
    { 1*3600, 0.05, 0.05, 0.05, 0.05, 0, 0, 0 },  -- 青铜
    { 2*3600, 0.10, 0.10, 0.10, 0.10, 1, 0, 0 },  -- 白银
    { 3*3600, 0.15, 0.15, 0.15, 0.15, 1, 1, 0 },  -- 黄金
    { 4*3600, 0.20, 0.20, 0.20, 0.25, 2, 1, 1 },  -- 铂金
    { 5*3600, 0.25, 0.25, 0.30, 0.35, 2, 2, 1 },  -- 钻石
    { 6*3600, 0.30, 0.30, 0.40, 0.50, 3, 3, 2 },  -- 红宝石
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
            adsWatched      = 0,
            unlocked        = false,
            instantClaimed  = false,
            lastClaimDate   = nil,
            unlockDate      = nil,
            todayAdsWatched = 0,
            lastAdDate      = nil,
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
    if not def or not def.duration then return end
    if not cd.unlockDate then
        cd.unlockDate = os.date("%Y-%m-%d")
        PrivilegeData.Save()
        return
    end
    local elapsed = DaysBetween(os.date("%Y-%m-%d"), cd.unlockDate)
    if elapsed >= def.duration then
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
    -- 检查尊享卡过期
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
-- 三、尊享卡 查询 / 操作
-- ============================================================================

--- 获取尊享卡定义
---@param cardId string
---@return table|nil
function PrivilegeData.GetCardDef(cardId)
    for _, c in ipairs(PrivilegeData.CARDS) do
        if c.id == cardId then return c end
    end
    return nil
end

--- 尊享卡是否已解锁（会自动检查过期）
function PrivilegeData.IsUnlocked(cardId)
    -- 福利卡默认解锁
    if cardId == "welfare" then return true end
    -- 先检查尊享卡
    local def = PrivilegeData.GetCardDef(cardId)
    if def then
        CheckExpired(cardId)
        local cd = GetCardData(cardId)
        return cd.unlocked == true
    end
    -- 再检查特权卡等级
    local pts = PrivilegeData.GetPoints()
    for _, card in ipairs(PrivilegeData.TIER_CARDS) do
        if card.id == cardId then
            return pts >= card.threshold
        end
    end
    return false
end

--- 已看广告数
function PrivilegeData.GetAdsWatched(cardId)
    local cd = GetCardData(cardId)
    return cd.adsWatched or 0
end

--- 重置每日广告计数
local function ResetDailyAdIfNeeded(cardId)
    local cd = GetCardData(cardId)
    local today = os.date("%Y-%m-%d")
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

--- 能否继续看广告
function PrivilegeData.CanWatchAd(cardId)
    if PrivilegeData.IsUnlocked(cardId) then return false end
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
    ResetDailyAdIfNeeded(cardId)
    cd.todayAdsWatched = (cd.todayAdsWatched or 0) + 1
    if cd.adsWatched >= def.adsRequired then
        cd.unlocked = true
        cd.unlockDate = os.date("%Y-%m-%d")
    end
    PrivilegeData.Save()
    return true
end

--- 获取卡片剩余有效天数（-1=永久, nil=未解锁）
---@param cardId string
---@return number|nil
function PrivilegeData.GetRemainingDays(cardId)
    local cd = GetCardData(cardId)
    if not cd.unlocked then return nil end
    local def = PrivilegeData.GetCardDef(cardId)
    if not def or not def.duration then return -1 end
    if not cd.unlockDate then return def.duration end
    local elapsed = DaysBetween(os.date("%Y-%m-%d"), cd.unlockDate)
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
    local today = os.date("%Y-%m-%d")
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
    cd.lastClaimDate = os.date("%Y-%m-%d")
    PrivilegeData.Save()
    return true, table.concat(names, "、"), displayRewards
end

-- ============================================================================
-- 四、渐进式特权卡 积分系统
-- ============================================================================

--- 获取当前累计积分
---@return number
function PrivilegeData.GetPoints()
    local data = EnsureData()
    return data.points or 0
end

--- 尝试发放每日积分（每天看满 20 次广告 → +1 点）
---@param todayAdCount number 今日已看广告次数
---@return boolean
function PrivilegeData.TryAwardDailyPoint(todayAdCount)
    if todayAdCount < 20 then return false end
    local data = EnsureData()
    local today = TodayStr()
    if data.lastPointDate == today then return false end
    data.points = (data.points or 0) + 1
    data.lastPointDate = today
    PrivilegeData.Save()
    return true
end

--- 今日是否已领取积分
---@return boolean
function PrivilegeData.IsDailyPointClaimed()
    local data = EnsureData()
    return data.lastPointDate == TodayStr()
end

-- ============================================================================
-- 五、渐进式特权卡 等级查询
-- ============================================================================

--- 获取当前已解锁的最高等级索引（0=未解锁，1~6 对应青铜~红宝石）
---@return number
function PrivilegeData.GetCurrentTierIndex()
    local pts = PrivilegeData.GetPoints()
    local tier = 0
    for i, card in ipairs(PrivilegeData.TIER_CARDS) do
        if pts >= card.threshold then tier = i end
    end
    return tier
end

--- 获取当前等级的卡片定义（未解锁返回 nil）
---@return table|nil
function PrivilegeData.GetCurrentCard()
    local idx = PrivilegeData.GetCurrentTierIndex()
    if idx == 0 then return nil end
    return PrivilegeData.TIER_CARDS[idx]
end

--- 获取下一等级的卡片定义（已满级返回 nil）
---@return table|nil
function PrivilegeData.GetNextCard()
    local idx = PrivilegeData.GetCurrentTierIndex()
    if idx >= #PrivilegeData.TIER_CARDS then return nil end
    return PrivilegeData.TIER_CARDS[idx + 1]
end

--- 获取到下一等级还差多少点
---@return number
function PrivilegeData.GetPointsToNextTier()
    local nextCard = PrivilegeData.GetNextCard()
    if not nextCard then return 0 end
    return math.max(0, nextCard.threshold - PrivilegeData.GetPoints())
end

-- ============================================================================
-- 六、Buff 查询（两套系统叠加）
-- ============================================================================

--- 内部：按索引获取特权卡等级 buff 值
---@param buffIndex number
---@return number
local function GetTierBuff(buffIndex)
    local tier = PrivilegeData.GetCurrentTierIndex()
    if tier == 0 then return 0 end
    return TIER_BUFFS[tier][buffIndex] or 0
end

--- 挂机时长加成（秒）：尊享卡（月卡+终身卡各2h）+ 特权卡等级加成
function PrivilegeData.GetIdleExtraSeconds()
    local extra = 0
    if PrivilegeData.IsUnlocked("monthly")  then extra = extra + 2 * 3600 end
    if PrivilegeData.IsUnlocked("lifetime") then extra = extra + 2 * 3600 end
    return extra + GetTierBuff(BUFF_IDLE)
end

--- 冥晶收益倍率：尊享卡（周卡+终身卡各10%）+ 特权卡等级加成
function PrivilegeData.GetCrystalBonusRate()
    local bonus = 0
    if PrivilegeData.IsUnlocked("weekly")   then bonus = bonus + 0.10 end
    if PrivilegeData.IsUnlocked("lifetime") then bonus = bonus + 0.10 end
    return 1.0 + bonus + GetTierBuff(BUFF_CRYSTAL)
end

--- 收益翻倍概率：尊享卡（周卡+月卡各10%）+ 特权卡等级加成
function PrivilegeData.GetDoubleChance()
    local chance = 0
    if PrivilegeData.IsUnlocked("weekly")  then chance = chance + 0.10 end
    if PrivilegeData.IsUnlocked("monthly") then chance = chance + 0.10 end
    return chance + GetTierBuff(BUFF_DOUBLE)
end

--- 宝箱掉率加成（仅特权卡）
function PrivilegeData.GetChestDropBonus()
    return GetTierBuff(BUFF_CHEST)
end

--- 英雄碎片掉率加成（仅特权卡）
function PrivilegeData.GetShardDropBonus()
    return GetTierBuff(BUFF_SHARD)
end

--- 资源副本额外次数（仅特权卡）
function PrivilegeData.GetDungeonExtraAttempts()
    return GetTierBuff(BUFF_DUNGEON)
end

--- 深渊裂隙额外次数（仅特权卡）
function PrivilegeData.GetAbyssRiftExtraAttempts()
    return GetTierBuff(BUFF_ABYSS)
end

--- 世界Boss额外次数（仅特权卡）
function PrivilegeData.GetWorldBossExtraAttempts()
    return GetTierBuff(BUFF_BOSS)
end

return PrivilegeData
