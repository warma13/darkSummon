-- Game/PrivilegeData.lua
-- 渐进式特权系统：青铜 → 白银 → 黄金 → 铂金 → 钻石 → 红宝石
-- 每天看满 20 次广告获得 1 点，累计点数永久解锁对应等级
-- 只有当前最高等级生效，解锁即永久

local HeroData = require("Game.HeroData")
local TodayStr = require("Game.DateUtil").TodayStr

local PrivilegeData = {}

-- ============================================================================
-- 卡片定义（6 级）
-- ============================================================================
PrivilegeData.CARDS = {
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

-- 各等级 buff 数值表（按上面索引顺序）
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

function PrivilegeData.Load()
    EnsureData()
    PrivilegeData._MigrateAdPoints()
end

--- 一次性迁移：老玩家首次登录时，将历史广告总次数 / 20 补入特权点数
function PrivilegeData._MigrateAdPoints()
    local data = EnsureData()
    if data._adPointsMigrated then return end

    local ok, AdTracker = pcall(require, "Game.AdTracker")
    if not ok or not AdTracker then
        return  -- AdTracker 尚未加载，下次再试
    end

    local totalAds = AdTracker.GetTotalCount()
    if totalAds <= 0 then
        -- 新玩家无需迁移，直接标记完成
        data._adPointsMigrated = true
        PrivilegeData.Save()
        return
    end

    local bonus = math.min(math.floor(totalAds / 20), 10)
    if bonus > 0 then
        data.points = (data.points or 0) + bonus
        print("[PrivilegeData] Migration: totalAds=" .. totalAds ..
              " → bonus points=" .. bonus ..
              " → new total=" .. data.points)
    end

    data._adPointsMigrated = true
    PrivilegeData.Save()
end

function PrivilegeData.Save()
    HeroData.Save()
end

-- ============================================================================
-- 积分系统
-- ============================================================================

--- 获取当前累计积分
---@return number
function PrivilegeData.GetPoints()
    local data = EnsureData()
    return data.points or 0
end

--- 尝试发放每日积分（每天看满 20 次广告 → +1 点）
--- 成功返回 true，已领过或未达标返回 false
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
-- 等级查询
-- ============================================================================

--- 获取当前已解锁的最高等级索引（0=未解锁，1~6 对应青铜~红宝石）
---@return number
function PrivilegeData.GetCurrentTierIndex()
    local pts = PrivilegeData.GetPoints()
    local tier = 0
    for i, card in ipairs(PrivilegeData.CARDS) do
        if pts >= card.threshold then tier = i end
    end
    return tier
end

--- 获取当前等级的卡片定义（未解锁返回 nil）
---@return table|nil
function PrivilegeData.GetCurrentCard()
    local idx = PrivilegeData.GetCurrentTierIndex()
    if idx == 0 then return nil end
    return PrivilegeData.CARDS[idx]
end

--- 获取下一等级的卡片定义（已满级返回 nil）
---@return table|nil
function PrivilegeData.GetNextCard()
    local idx = PrivilegeData.GetCurrentTierIndex()
    if idx >= #PrivilegeData.CARDS then return nil end
    return PrivilegeData.CARDS[idx + 1]
end

--- 获取到下一等级还差多少点
---@return number  差值（已满级返回 0）
function PrivilegeData.GetPointsToNextTier()
    local nextCard = PrivilegeData.GetNextCard()
    if not nextCard then return 0 end
    return math.max(0, nextCard.threshold - PrivilegeData.GetPoints())
end

--- 检查指定卡 id 是否已解锁
---@param cardId string
---@return boolean
function PrivilegeData.IsUnlocked(cardId)
    local pts = PrivilegeData.GetPoints()
    for _, card in ipairs(PrivilegeData.CARDS) do
        if card.id == cardId then
            return pts >= card.threshold
        end
    end
    return false
end

-- ============================================================================
-- Buff 查询（供 AFK / 战斗系统调用）
-- ============================================================================

--- 内部：按索引获取当前等级的 buff 值
---@param buffIndex number
---@return number
local function GetTierBuff(buffIndex)
    local tier = PrivilegeData.GetCurrentTierIndex()
    if tier == 0 then return 0 end
    return TIER_BUFFS[tier][buffIndex] or 0
end

--- 挂机时长加成（秒）
function PrivilegeData.GetIdleExtraSeconds()
    return GetTierBuff(BUFF_IDLE)
end

--- 冥晶收益倍率（1.0 + 加成）
function PrivilegeData.GetCrystalBonusRate()
    return 1.0 + GetTierBuff(BUFF_CRYSTAL)
end

--- 收益翻倍概率
function PrivilegeData.GetDoubleChance()
    return GetTierBuff(BUFF_DOUBLE)
end

--- 宝箱掉率加成
function PrivilegeData.GetChestDropBonus()
    return GetTierBuff(BUFF_CHEST)
end

--- 英雄碎片掉率加成
function PrivilegeData.GetShardDropBonus()
    return GetTierBuff(BUFF_SHARD)
end

--- 资源副本额外次数
function PrivilegeData.GetDungeonExtraAttempts()
    return GetTierBuff(BUFF_DUNGEON)
end

--- 深渊裂隙额外次数
function PrivilegeData.GetAbyssRiftExtraAttempts()
    return GetTierBuff(BUFF_ABYSS)
end

--- 世界Boss额外次数
function PrivilegeData.GetWorldBossExtraAttempts()
    return GetTierBuff(BUFF_BOSS)
end

-- ============================================================================
-- 兼容旧接口（ActivityUI_Privilege 等外部调用）
-- ============================================================================

--- 兼容：获取"已观看广告数" → 返回积分
function PrivilegeData.GetAdsWatched()
    return PrivilegeData.GetPoints()
end

--- 兼容：能否看广告 → 总是 false（新系统通过减负中心积分）
function PrivilegeData.CanWatchAd()
    return false
end

--- 兼容：记录广告观看 → 空操作
function PrivilegeData.RecordAdWatch()
    return false
end

--- 兼容：获取卡片定义
function PrivilegeData.GetCardDef(cardId)
    for _, c in ipairs(PrivilegeData.CARDS) do
        if c.id == cardId then return c end
    end
    return nil
end

--- 兼容：剩余天数 → 永久返回 -1
function PrivilegeData.GetRemainingDays(cardId)
    if PrivilegeData.IsUnlocked(cardId) then return -1 end
    return nil
end

--- 兼容：每日奖励相关 → 新系统不再有每日领取
function PrivilegeData.IsDailyClaimed() return true end
function PrivilegeData.CanClaimDaily() return false end
function PrivilegeData.ClaimDaily() return false end
function PrivilegeData.IsInstantClaimed() return true end
function PrivilegeData.ClaimInstant() return false end

return PrivilegeData
