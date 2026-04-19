-- Game/LimitedBannerData.lua
-- 限定招募池数据管理（保底计数、活动时间、招募逻辑）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local LBD = {}

-- ============================================================================
-- 存档字段初始化（挂在 HeroData 上统一存取）
-- ============================================================================

--- 将 "YYYY-MM-DD" 转为 os.time 时间戳（当天0点）
local function DateToTime(dateStr)
    local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if not y then return 0 end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- 获取限定池存档数据（懒初始化）
---@return table
function LBD.GetData()
    if not HeroData.limitedBanner then
        HeroData.limitedBanner = {}
    end
    local d = HeroData.limitedBanner
    -- 默认字段
    if d.pityCount == nil then d.pityCount = 0 end
    if d.totalPulls == nil then d.totalPulls = 0 end
    -- 限定池起始时间固定，不存储（或覆盖旧值）
    d.startTime = DateToTime(Config.LIMITED_BANNER_START)
    return d
end

-- ============================================================================
-- 活动时间
-- ============================================================================

--- 获取限定池剩余天数
---@return number  剩余天数（<0 表示已过期）
function LBD.GetRemainingDays()
    local d = LBD.GetData()
    local banner = Config.LIMITED_BANNER
    local elapsed = os.time() - d.startTime
    local totalSec = banner.durationDays * 86400
    local remaining = totalSec - elapsed
    return math.ceil(remaining / 86400)
end

--- 限定池是否仍在活动期内
---@return boolean
function LBD.IsActive()
    return LBD.GetRemainingDays() > 0
end

-- ============================================================================
-- 保底系统
-- ============================================================================

--- 获取当前保底计数（距上次获得限定英雄）
---@return number
function LBD.GetPityCount()
    return LBD.GetData().pityCount
end

--- 获取距保底还差多少抽
---@return number
function LBD.GetPityRemaining()
    local banner = Config.LIMITED_BANNER
    return banner.pity - LBD.GetData().pityCount
end

--- 获取总抽数
---@return number
function LBD.GetTotalPulls()
    return LBD.GetData().totalPulls
end

-- ============================================================================
-- 货币检查
-- ============================================================================

--- 是否有足够的限定招募券
---@param count number
---@return boolean
function LBD.CanAfford(count)
    local banner = Config.LIMITED_BANNER
    return (HeroData.currencies[banner.currency] or 0) >= count
end

--- 获取当前限定招募券数量
---@return number
function LBD.GetTokens()
    local banner = Config.LIMITED_BANNER
    return HeroData.currencies[banner.currency] or 0
end

-- ============================================================================
-- 每日广告领取霜誓契约
-- ============================================================================

local AD_FROST_AMOUNT = 5    -- 每次领取数量
local AD_FROST_DAILY_MAX = 4 -- 每日最多领取次数

--- 获取今日日期字符串
---@return string
local function GetTodayStr()
    return os.date("%Y-%m-%d") or ""
end

--- 重置每日广告计数（跨天时）
local function ResetAdFrostIfNeeded()
    local d = LBD.GetData()
    local today = GetTodayStr()
    if d.adFrostDate ~= today then
        d.adFrostCount = 0
        d.adFrostDate = today
    end
end

--- 今日已领取次数
---@return number
function LBD.GetAdFrostClaimed()
    ResetAdFrostIfNeeded()
    return LBD.GetData().adFrostCount or 0
end

--- 今日剩余次数
---@return number
function LBD.GetAdFrostRemaining()
    return AD_FROST_DAILY_MAX - LBD.GetAdFrostClaimed()
end

--- 是否还能看广告领取
---@return boolean
function LBD.CanClaimAdFrost()
    return LBD.IsActive() and LBD.GetAdFrostRemaining() > 0
end

--- 领取广告霜誓契约（看完广告后调用）
---@return number gained 实际获得数量
function LBD.ClaimAdFrost()
    ResetAdFrostIfNeeded()
    local d = LBD.GetData()
    d.adFrostCount = (d.adFrostCount or 0) + 1
    local banner = Config.LIMITED_BANNER
    HeroData.currencies[banner.currency] = (HeroData.currencies[banner.currency] or 0) + AD_FROST_AMOUNT
    HeroData.Save()
    return AD_FROST_AMOUNT
end

--- 每次领取数量
---@return number
function LBD.GetAdFrostAmount()
    return AD_FROST_AMOUNT
end

--- 每日上限
---@return number
function LBD.GetAdFrostDailyMax()
    return AD_FROST_DAILY_MAX
end

-- ============================================================================
-- 抽卡逻辑
-- ============================================================================

--- 随机稀有度（限定池）
---@param forcePity boolean  是否强制出限定英雄
---@return string rarity
local function RollRarity(forcePity)
    if forcePity then return "UR" end
    local rates = Config.LIMITED_BANNER.rates
    local roll = math.random(1, 100)
    local cum = 0
    -- 按 LR > UR > SSR > SR > R > N 顺序判定
    local order = { "LR", "UR", "SSR", "SR", "R", "N" }
    for _, r in ipairs(order) do
        cum = cum + (rates[r] or 0)
        if roll <= cum then
            return r
        end
    end
    return "N"
end

--- 解析单次抽取结果
---@param rarity string
---@param isPity boolean  是否为保底触发
---@return table result
local function ResolveHero(rarity, isPity)
    local banner = Config.LIMITED_BANNER

    -- UR 品质 → 必定是限定英雄
    if rarity == "UR" then
        local heroId = banner.heroId
        local heroName = heroId
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then
                heroName = td.name
                break
            end
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

        return {
            heroId = heroId,
            heroName = heroName,
            rarity = rarity,
            fragments = fragments,
            isNew = isNew,
            isLimitedHero = true,
        }
    end

    -- 非 UR → 从 fallbackPool 中随机
    local pool = banner.fallbackPool[rarity]
    if not pool or #pool == 0 then
        pool = Config.RECRUIT_POOL[rarity] or { "skeleton_grunt" }
    end
    local heroId = pool[math.random(1, #pool)]

    local heroName = heroId
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then
            heroName = td.name
            break
        end
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

    return {
        heroId = heroId,
        heroName = heroName,
        rarity = rarity,
        fragments = fragments,
        isNew = isNew,
        isLimitedHero = false,
    }
end

--- 执行限定池招募
---@param pullCount number  1 或 10
---@return boolean success
---@return table|string results 或错误信息
function LBD.DoPull(pullCount)
    local banner = Config.LIMITED_BANNER
    local cost = pullCount == 10 and banner.tenCost or banner.singleCost
    local d = LBD.GetData()

    -- 活动期检查
    if not LBD.IsActive() then
        return false, "限定池已结束"
    end

    -- 货币检查
    if not LBD.CanAfford(cost) then
        return false, "霜誓契约不足(需要" .. cost .. "，当前" .. LBD.GetTokens() .. ")"
    end

    -- 扣除消耗
    HeroData.currencies[banner.currency] = (HeroData.currencies[banner.currency] or 0) - cost

    -- 决定每抽稀有度
    local rarities = {}
    local pityTriggered = {}
    for i = 1, pullCount do
        d.totalPulls = d.totalPulls + 1
        d.pityCount = d.pityCount + 1

        -- 保底判定：达到保底次数强制出 UR
        local forcePity = (d.pityCount >= banner.pity)
        rarities[i] = RollRarity(forcePity)
        pityTriggered[i] = forcePity

        -- 如果出了 UR（不论是否保底），重置保底计数
        if rarities[i] == "UR" then
            d.pityCount = 0
        end
    end

    -- 十连保底：至少一个 SSR 及以上
    if pullCount >= 10 then
        local hasHigh = false
        for _, r in ipairs(rarities) do
            if r == "SSR" or r == "UR" or r == "LR" then
                hasHigh = true
                break
            end
        end
        if not hasHigh then
            local idx = math.random(1, #rarities)
            -- 避免覆盖 UR 位
            if rarities[idx] ~= "UR" then
                rarities[idx] = "SSR"
            end
        end
    end

    -- 发放奖励
    local results = {}
    for i = 1, pullCount do
        results[i] = ResolveHero(rarities[i], pityTriggered[i])
    end

    HeroData.Save(true)  -- 限定抽卡消耗货币，不可逆操作，立即云端保存
    print("[LimitedBannerData] Pulled " .. pullCount .. " times, pity=" .. d.pityCount)
    return true, results
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("limitedBanner", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.limitedBanner
    end,
    deserialize = function(saved, _saveData)
        HeroData.limitedBanner = saved or nil
    end,
})

return LBD
