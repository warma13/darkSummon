-- Game/LimitedBannerData.lua
-- 限定招募池数据管理（保底计数、活动时间、招募逻辑）
-- 支持多个限定池，通过 bannerCfg 参数区分

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local LBD = {}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 将 "YYYY-MM-DD" 转为 os.time 时间戳（当天0点）
local function DateToTime(dateStr)
    if not dateStr then return 0 end
    local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if not y then return 0 end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

-- ============================================================================
-- 存档数据访问（按 bannerCfg.id 分槽存储）
-- ============================================================================

--- 获取指定限定池存档数据（懒初始化）
---@param bannerCfg table  Config.LIMITED_BANNERS[i]
---@return table
function LBD.GetData(bannerCfg)
    if not HeroData.limitedBanners then
        HeroData.limitedBanners = {}
    end
    local id = bannerCfg.id or "default"
    if not HeroData.limitedBanners[id] then
        HeroData.limitedBanners[id] = {}
    end
    local d = HeroData.limitedBanners[id]
    if d.pityCount == nil then d.pityCount = 0 end
    if d.totalPulls == nil then d.totalPulls = 0 end
    -- 起始时间：优先 bannerCfg.startDate，否则用全局 LIMITED_BANNER_START
    local startStr = bannerCfg.startDate or Config.LIMITED_BANNER_START
    d.startTime = DateToTime(startStr)
    return d
end

-- ============================================================================
-- 锁定状态（解锁日期前不可招募）
-- ============================================================================

--- 是否处于锁定期（unlockDate 前）
---@param bannerCfg table
---@return boolean
function LBD.IsLocked(bannerCfg)
    if not bannerCfg.unlockDate then return false end
    return os.time() < DateToTime(bannerCfg.unlockDate)
end

--- 距解锁还剩几天（仅锁定期有效）
---@param bannerCfg table
---@return number
function LBD.GetUnlockDaysRemaining(bannerCfg)
    if not bannerCfg.unlockDate then return 0 end
    local diff = DateToTime(bannerCfg.unlockDate) - os.time()
    return math.max(0, math.ceil(diff / 86400))
end

-- ============================================================================
-- 活动时间
-- ============================================================================

--- 获取限定池剩余天数（负数表示已过期）
---@param bannerCfg table
---@return number
function LBD.GetRemainingDays(bannerCfg)
    local d = LBD.GetData(bannerCfg)
    local elapsed = os.time() - d.startTime
    local totalSec = bannerCfg.durationDays * 86400
    return math.ceil((totalSec - elapsed) / 86400)
end

--- 限定池是否仍在活动期内（未锁定 且 未过期）
---@param bannerCfg table
---@return boolean
function LBD.IsActive(bannerCfg)
    if LBD.IsLocked(bannerCfg) then return false end
    return LBD.GetRemainingDays(bannerCfg) > 0
end

-- ============================================================================
-- 保底系统
-- ============================================================================

---@param bannerCfg table
---@return number
function LBD.GetPityCount(bannerCfg)
    return LBD.GetData(bannerCfg).pityCount
end

---@param bannerCfg table
---@return number
function LBD.GetPityRemaining(bannerCfg)
    return bannerCfg.pity - LBD.GetPityCount(bannerCfg)
end

---@param bannerCfg table
---@return number
function LBD.GetTotalPulls(bannerCfg)
    return LBD.GetData(bannerCfg).totalPulls
end

-- ============================================================================
-- 货币检查
-- ============================================================================

---@param bannerCfg table
---@param count number
---@return boolean
function LBD.CanAfford(bannerCfg, count)
    return (HeroData.currencies[bannerCfg.currency] or 0) >= count
end

---@param bannerCfg table
---@return number
function LBD.GetTokens(bannerCfg)
    return HeroData.currencies[bannerCfg.currency] or 0
end

-- ============================================================================
-- 每日广告领取（按池分槽）
-- ============================================================================

local AD_FROST_AMOUNT    = 5
local AD_FROST_DAILY_MAX = 4

local function GetTodayStr()
    return os.date("%Y-%m-%d") or ""
end

local function ResetAdFrostIfNeeded(bannerCfg)
    local d = LBD.GetData(bannerCfg)
    local today = GetTodayStr()
    if d.adFrostDate ~= today then
        d.adFrostCount = 0
        d.adFrostDate  = today
    end
end

---@param bannerCfg table
---@return number
function LBD.GetAdFrostClaimed(bannerCfg)
    ResetAdFrostIfNeeded(bannerCfg)
    return LBD.GetData(bannerCfg).adFrostCount or 0
end

---@param bannerCfg table
---@return number
function LBD.GetAdFrostRemaining(bannerCfg)
    return AD_FROST_DAILY_MAX - LBD.GetAdFrostClaimed(bannerCfg)
end

---@param bannerCfg table
---@return boolean
function LBD.CanClaimAdFrost(bannerCfg)
    return LBD.IsActive(bannerCfg) and LBD.GetAdFrostRemaining(bannerCfg) > 0
end

---@param bannerCfg table
---@return number gained
function LBD.ClaimAdFrost(bannerCfg)
    ResetAdFrostIfNeeded(bannerCfg)
    local d = LBD.GetData(bannerCfg)
    d.adFrostCount = (d.adFrostCount or 0) + 1
    HeroData.currencies[bannerCfg.currency] = (HeroData.currencies[bannerCfg.currency] or 0) + AD_FROST_AMOUNT
    HeroData.Save()
    return AD_FROST_AMOUNT
end

function LBD.GetAdFrostAmount()    return AD_FROST_AMOUNT    end
function LBD.GetAdFrostDailyMax()  return AD_FROST_DAILY_MAX  end

-- ============================================================================
-- 每日广告领取招募券（两个限定池共享次数上限）
-- ============================================================================

local AD_TICKET_AMOUNT    = 5
local AD_TICKET_DAILY_MAX = 4

local function ResetAdTicketIfNeeded()
    if not HeroData.limitedBanners then HeroData.limitedBanners = {} end
    local d = HeroData.limitedBanners
    local today = GetTodayStr()
    if d._adTicketDate ~= today then
        d._adTicketCount = 0
        d._adTicketDate  = today
    end
end

function LBD.GetAdTicketClaimed()
    ResetAdTicketIfNeeded()
    return HeroData.limitedBanners._adTicketCount or 0
end

function LBD.GetAdTicketRemaining()
    return AD_TICKET_DAILY_MAX - LBD.GetAdTicketClaimed()
end

---@param bannerCfg table
function LBD.CanClaimAdTicket(bannerCfg)
    -- 不要求池子处于活跃期，锁定状态下也可以领券
    return LBD.GetAdTicketRemaining() > 0
end

---@param bannerCfg table
---@return number gained
function LBD.ClaimAdTicket(bannerCfg)
    ResetAdTicketIfNeeded()
    HeroData.limitedBanners._adTicketCount = (HeroData.limitedBanners._adTicketCount or 0) + 1
    local InventoryData = require("Game.InventoryData")
    InventoryData.Add("recruit_ticket_select_box", AD_TICKET_AMOUNT)
    HeroData.Save()
    return AD_TICKET_AMOUNT
end

function LBD.GetAdTicketAmount()    return AD_TICKET_AMOUNT    end
function LBD.GetAdTicketDailyMax()  return AD_TICKET_DAILY_MAX  end

-- ============================================================================
-- 抽卡逻辑
-- ============================================================================

local function RollRarity(bannerCfg, forcePity)
    if forcePity then return "UR" end
    local rates = bannerCfg.rates
    local roll = math.random(1, 100)
    local cum  = 0
    local order = { "LR", "UR", "SSR", "SR", "R", "N" }
    for _, r in ipairs(order) do
        cum = cum + (rates[r] or 0)
        if roll <= cum then return r end
    end
    return "N"
end

local function ResolveHero(bannerCfg, rarity, _isPity)
    if rarity == "UR" then
        local heroId   = bannerCfg.heroId
        local heroName = heroId
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then heroName = td.name; break end
        end
        local isNew = not HeroData.IsUnlocked(heroId)
        local fragments = 0
        if isNew then
            HeroData.UnlockHero(heroId)
        else
            local fragRange = Config.RECRUIT_FRAGMENT_DROP[rarity]
            fragments = math.random(fragRange.min, fragRange.max)
            HeroData.AddFragments(heroId, fragments)
        end
        return { heroId = heroId, heroName = heroName, rarity = rarity,
                 fragments = fragments, isNew = isNew, isLimitedHero = true }
    end

    local pool = bannerCfg.fallbackPool[rarity]
    if not pool or #pool == 0 then
        pool = Config.RECRUIT_POOL[rarity] or { "skeleton_grunt" }
    end
    local heroId = pool[math.random(1, #pool)]
    local heroName = heroId
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then heroName = td.name; break end
    end
    local isNew = not HeroData.IsUnlocked(heroId)
    local fragments = 0
    if isNew then
        HeroData.UnlockHero(heroId)
    else
        local fragRange = Config.RECRUIT_FRAGMENT_DROP[rarity]
        fragments = math.random(fragRange.min, fragRange.max)
        HeroData.AddFragments(heroId, fragments)
    end
    return { heroId = heroId, heroName = heroName, rarity = rarity,
             fragments = fragments, isNew = isNew, isLimitedHero = false }
end

---@param bannerCfg table
---@param pullCount number  1 或 10
---@return boolean success
---@return table|string
function LBD.DoPull(bannerCfg, pullCount)
    local cost = pullCount == 10 and bannerCfg.tenCost or bannerCfg.singleCost
    local d = LBD.GetData(bannerCfg)

    if LBD.IsLocked(bannerCfg) then
        return false, "限定池尚未开放"
    end
    if not LBD.IsActive(bannerCfg) then
        return false, "限定池已结束"
    end
    if not LBD.CanAfford(bannerCfg, cost) then
        return false, bannerCfg.currency .. "不足(需要" .. cost .. "，当前" .. LBD.GetTokens(bannerCfg) .. ")"
    end

    HeroData.currencies[bannerCfg.currency] = (HeroData.currencies[bannerCfg.currency] or 0) - cost

    local rarities      = {}
    local pityTriggered = {}
    for i = 1, pullCount do
        d.totalPulls = d.totalPulls + 1
        d.pityCount  = d.pityCount  + 1
        local forcePity = (d.pityCount >= bannerCfg.pity)
        rarities[i]      = RollRarity(bannerCfg, forcePity)
        pityTriggered[i] = forcePity
        if rarities[i] == "UR" then d.pityCount = 0 end
    end

    if pullCount >= 10 then
        local hasHigh = false
        for _, r in ipairs(rarities) do
            if r == "SSR" or r == "UR" or r == "LR" then hasHigh = true; break end
        end
        if not hasHigh then
            local idx = math.random(1, #rarities)
            if rarities[idx] ~= "UR" then rarities[idx] = "SSR" end
        end
    end

    local results = {}
    for i = 1, pullCount do
        results[i] = ResolveHero(bannerCfg, rarities[i], pityTriggered[i])
    end

    HeroData.Save(true)
    print("[LimitedBannerData] pool=" .. bannerCfg.id .. " pulled=" .. pullCount .. " pity=" .. d.pityCount)
    return true, results
end

-- ============================================================================
-- SaveRegistry 自注册（迁移旧格式）
-- ============================================================================
SaveRegistry.Register("limitedBanners", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.limitedBanners
    end,
    deserialize = function(saved, _saveData)
        if not saved then
            HeroData.limitedBanners = {}
            return
        end
        -- 兼容旧格式（saved.pityCount 直接存在）
        if saved.pityCount ~= nil then
            HeroData.limitedBanners = { glacial = saved }
        else
            HeroData.limitedBanners = saved
        end
    end,
})

-- 旧 key 迁移（防止旧存档读取 limitedBanner 时报错）
SaveRegistry.Register("limitedBanner", {
    group = "meta_game",
    order = 69,
    serialize = function() return nil end,
    deserialize = function(saved, _saveData)
        if saved and saved.pityCount ~= nil then
            if not HeroData.limitedBanners then HeroData.limitedBanners = {} end
            if not HeroData.limitedBanners.glacial then
                HeroData.limitedBanners.glacial = saved
            end
        end
    end,
})

return LBD
