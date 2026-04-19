-- Game/RecruitData.lua
-- 招募系统逻辑（对齐咸鱼之王）
-- 招募令抽卡 → 碎片产出 → 自动解锁

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")

local RecruitData = {}

--- 获取今日日期字符串 "YYYY-MM-DD"
---@return string
local function GetTodayStr()
    return os.date("%Y-%m-%d") or ""
end

--- 是否可以免费单抽（每天一次）
---@return boolean
function RecruitData.CanFreePull()
    local rd = HeroData.recruitData
    return rd.freeDaily ~= GetTodayStr()
end

--- 是否有足够招募令
---@param count number  需要的令数
---@return boolean
function RecruitData.CanAfford(count)
    return (HeroData.currencies.void_pact or 0) >= count
end

--- 随机一个稀有度
--- LR 采用独立双阶段 roll：先判 LR（含软/硬保底加成），不中再从非 LR 池随机
---@param forcePity boolean  是否强制 SSR（十连保底）
---@param forceLR boolean    是否强制 LR（第100次硬保底）
---@param lrBonusRate number LR 软保底额外概率（第81~99次，每次 +2%）
---@return string rarity
local function RollRarity(forcePity, forceLR, lrBonusRate)
    -- 硬保底：第100次直接 LR
    if forceLR then return "LR" end

    local rates = Config.RECRUIT_RATES

    -- LR 独立 roll（基础概率 + 软保底加成，上限100%）
    local effectiveLR = math.min(100, (rates.LR or 0) + (lrBonusRate or 0))
    if math.random(1, 100) <= effectiveLR then return "LR" end

    -- 未出 LR，从非 LR 池随机（UR > SSR > SR > R > N）
    if forcePity then return "SSR" end
    local roll = math.random(1, 100)
    local cum = 0
    local order = { "UR", "SSR", "SR", "R", "N" }
    for _, r in ipairs(order) do
        cum = cum + (rates[r] or 0)
        if roll <= cum then return r end
    end
    return "N"
end

--- 随机一个英雄并发放奖励
---@param rarity string
---@return table
local function ResolveHero(rarity)
    local pool = Config.RECRUIT_POOL[rarity]
    local heroId = pool[math.random(1, #pool)]

    local heroName = heroId
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then
            heroName = td.name
            break
        end
    end

    -- 咸鱼之王机制：首次获得 → 直接解锁，重复 → 碎片
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
    }
end

--- 执行招募（单抽或十连）
---@param pullCount number  1 或 10
---@param isFree boolean  是否使用免费次数（仅单抽）
---@return boolean success
---@return table|string  results数组 或 错误信息
function RecruitData.DoPull(pullCount, isFree)
    local rd = HeroData.recruitData
    local cost = pullCount == 10 and Config.RECRUIT_TEN_COST or Config.RECRUIT_SINGLE_COST

    -- 检查消耗
    if isFree and pullCount == 1 then
        if not RecruitData.CanFreePull() then
            return false, "今日免费次数已用"
        end
    else
        if not RecruitData.CanAfford(cost) then
            return false, "虚空契约不足(需要" .. cost .. "，当前" .. (HeroData.currencies.void_pact or 0) .. ")"
        end
    end

    -- 扣除消耗
    if isFree and pullCount == 1 then
        rd.freeDaily = GetTodayStr()
    else
        HeroData.currencies.void_pact = HeroData.currencies.void_pact - cost
    end

    -- 先决定每抽的稀有度（含 LR 保底逻辑）
    local rarities = {}
    for i = 1, pullCount do
        rd.totalPulls = rd.totalPulls + 1
        rd.lrPityCount = (rd.lrPityCount or 0) + 1

        -- 硬保底：第 100 次强制 LR
        local forceLR = rd.lrPityCount >= 100
        -- 软保底：第 81~99 次每抽额外 +2% LR 概率（pull 81=+2%, pull 82=+4%, ...）
        local lrBonus = rd.lrPityCount > 80 and (rd.lrPityCount - 80) * 2 or 0

        rarities[i] = RollRarity(false, forceLR, lrBonus)

        if rarities[i] == "LR" then
            print("[RecruitData] LR obtained at pityCount=" .. rd.lrPityCount .. ", resetting")
            rd.lrPityCount = 0
        end
    end

    -- 十连保底：如果10连中没有SSR及以上，随机一个位置强制SSR
    if pullCount >= 10 then
        local hasSSR = false
        for _, r in ipairs(rarities) do
            if r == "SSR" or r == "UR" or r == "LR" then
                hasSSR = true
                break
            end
        end
        if not hasSSR then
            local idx = math.random(1, #rarities)
            rarities[idx] = "SSR"
            print("[RecruitData] 10-pull pity triggered at index " .. idx)
        end
    end

    -- 按确定的稀有度发放奖励
    local results = {}
    for i = 1, pullCount do
        results[i] = ResolveHero(rarities[i])
    end

    -- 保存（抽卡消耗货币，不可逆操作，立即云端保存）
    HeroData.Save(true)

    -- 每日任务：招募
    local ok3, DTD = pcall(require, "Game.DailyTaskData")
    if ok3 and DTD then DTD.AddProgress("recruit", pullCount) end

    print("[RecruitData] Pulled " .. pullCount .. " times")
    return true, results
end

--- 获取历史总抽数
---@return number
function RecruitData.GetTotalPulls()
    return HeroData.recruitData.totalPulls
end

-- ============================================================================
-- 每日广告领取虚空契约
-- ============================================================================

local AD_PACT_AMOUNT = 5   -- 每次领取数量
local AD_PACT_DAILY_MAX = 4 -- 每日最多领取次数

--- 重置每日广告计数（如果跨天）
local function ResetAdPactIfNeeded()
    local rd = HeroData.recruitData
    local today = GetTodayStr()
    if rd.adPactDate ~= today then
        rd.adPactCount = 0
        rd.adPactDate = today
    end
end

--- 今日已领取广告虚空契约次数
---@return number
function RecruitData.GetAdPactClaimed()
    ResetAdPactIfNeeded()
    return HeroData.recruitData.adPactCount or 0
end

--- 今日剩余广告虚空契约次数
---@return number
function RecruitData.GetAdPactRemaining()
    return AD_PACT_DAILY_MAX - RecruitData.GetAdPactClaimed()
end

--- 是否还能看广告领取
---@return boolean
function RecruitData.CanClaimAdPact()
    return RecruitData.GetAdPactRemaining() > 0
end

--- 领取广告虚空契约（看完广告后调用）
function RecruitData.ClaimAdPact()
    ResetAdPactIfNeeded()
    local rd = HeroData.recruitData
    rd.adPactCount = (rd.adPactCount or 0) + 1
    HeroData.currencies.void_pact = (HeroData.currencies.void_pact or 0) + AD_PACT_AMOUNT
    HeroData.Save()
    return AD_PACT_AMOUNT
end

--- 每次领取数量
---@return number
function RecruitData.GetAdPactAmount()
    return AD_PACT_AMOUNT
end

--- 每日上限
---@return number
function RecruitData.GetAdPactDailyMax()
    return AD_PACT_DAILY_MAX
end

return RecruitData
