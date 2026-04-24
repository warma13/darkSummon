-- Game/HatredLandData.lua
-- 憎恨之地数据模块：挑战憎恨之躯BOSS，按累计伤害发放奖励

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")
local SaveRegistry = require("Game.SaveRegistry")
local InventoryData = require("Game.InventoryData")
local TodayStr = require("Game.DateUtil").TodayStr

local HL = {}

-- ============================================================================
-- 难度等级配置
-- ============================================================================

HL.DIFFICULTY_LEVELS = {
    { level = 0, label = "普通",   attrMult = 1,           scoreMult = 1,   cdReduction = 0, darkSoulBonus = 0,
      rewardBonuses = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
    { level = 1, label = "困难",   attrMult = 100,         scoreMult = 5,   cdReduction = 1, darkSoulBonus = 10,
      rewardBonuses = { 0, 0, 1, 0, 1, 0, 1, 0, 1, 1 } },
    { level = 3, label = "噩梦",   attrMult = 100000,      scoreMult = 25,  cdReduction = 3, darkSoulBonus = 20,
      rewardBonuses = { 0, 1, 1, 1, 1, 1, 1, 1, 1, 2 } },
    { level = 9, label = "地狱",   attrMult = 10000000000, scoreMult = 100, cdReduction = 9, darkSoulBonus = 30,
      rewardBonuses = { 1, 1, 1, 1, 2, 2, 2, 2, 2, 1 } },
}

function HL.GetDifficultyDef(level)
    for _, d in ipairs(HL.DIFFICULTY_LEVELS) do
        if d.level == level then return d end
    end
    return HL.DIFFICULTY_LEVELS[1]
end

function HL.GetSelectedDifficulty()
    local data = HL.GetData()
    return data.selectedDifficulty or 0
end

function HL.SetSelectedDifficulty(level)
    local data = HL.GetData()
    if not HL.IsDifficultyUnlocked(level) then return end
    data.selectedDifficulty = level
    HeroData.Save()
end

function HL.IsDifficultyUnlocked(level)
    if level == 0 then return true end
    local data = HL.GetData()
    local cleared = data.clearedDifficulties or {}
    local prevLevel = nil
    for i, d in ipairs(HL.DIFFICULTY_LEVELS) do
        if d.level == level then
            if i > 1 then prevLevel = HL.DIFFICULTY_LEVELS[i - 1].level end
            break
        end
    end
    if prevLevel == nil then return true end
    return cleared[prevLevel] == true or cleared[tostring(prevLevel)] == true
end

function HL.MarkDifficultyCleared(level)
    local data = HL.GetData()
    if not data.clearedDifficulties then data.clearedDifficulties = {} end
    data.clearedDifficulties[level] = true
    HeroData.Save()
end

function HL.GetAdjustedRewardTiers(level)
    level = level or HL.GetSelectedDifficulty()
    local diff = HL.GetDifficultyDef(level)
    local bonuses = diff and diff.rewardBonuses or {}
    local result = {}
    for i, tier in ipairs(HL.CONFIG.rewardTiers) do
        local bonus = bonuses[i] or 0
        result[#result + 1] = { tier[1], tier[2] + bonus }
    end
    return result
end

-- ============================================================================
-- 配置常量
-- ============================================================================

HL.CONFIG = {
    bossDEF = 800000,
    totalDuration = 999999,
    darkSoulDrain = 50,

    defGrowthRate = 0.18,
    defGrowthInterval = 5,
    cdDecayRate = 1/600,
    cdMinMult = 0.5,

    rewardTiers = {
        { 5000000,         1 },
        { 10000000,        1 },
        { 50000000,        1 },
        { 250000000,       1 },
        { 500000000,       2 },
        { 1000000000,      2 },
        { 2500000000,      2 },
        { 5000000000,      4 },
        { 10000000000,     4 },
        { 25000000000,     4 },
    },
}

HL.DAILY_ATTEMPTS    = 4
HL.FREE_ATTEMPTS     = 1
HL.AD_EXTRA_ATTEMPTS = 3

-- ============================================================================
-- BOSS 定义
-- ============================================================================

function HL.CreateBossDef()
    local cfg = HL.CONFIG
    local bossDef = Config.BuildHatredBoss(1, 1.0)
    -- 覆盖为无限HP
    bossDef.baseHP = math.maxinteger
    bossDef.baseDEF = cfg.bossDEF
    bossDef.speed = 12
    bossDef.size = 28
    bossDef.reward = 0
    bossDef.liveCost = 0
    bossDef.isWorldBoss = true   -- 走世界BOSS流程
    bossDef.isHatredBoss = true
    bossDef.themeId = "void"
    bossDef.spriteSheet = "hatred_boss"  -- 使用憎恨之躯专属精灵图
    return bossDef
end

-- ============================================================================
-- 渐进难度
-- ============================================================================

function HL.GetScaledDEF(elapsed, difficultyLevel)
    local cfg = HL.CONFIG
    local periods = math.floor(elapsed / cfg.defGrowthInterval)
    local baseDEF = cfg.bossDEF * (1 + cfg.defGrowthRate) ^ periods
    local diff = HL.GetDifficultyDef(difficultyLevel or HL.GetSelectedDifficulty())
    return math.floor(baseDEF * (diff and diff.attrMult or 1))
end

function HL.GetCDMultiplier(elapsed)
    local cfg = HL.CONFIG
    return math.max(cfg.cdMinMult, 1 - cfg.cdDecayRate * elapsed)
end

-- ============================================================================
-- 进度管理
-- ============================================================================

function HL.GetData()
    if not HeroData.hatredLandData then
        HeroData.hatredLandData = {
            bestDamage = 0,
            todayAttempts = 0,
            todayAdAttempts = 0,
            lastResetDate = TodayStr(),
            totalAttempts = 0,
            selectedDifficulty = 0,
            clearedDifficulties = {},
            bestDiffDamage = {},
        }
    end
    if HeroData.hatredLandData.selectedDifficulty == nil then
        HeroData.hatredLandData.selectedDifficulty = 0
    end
    if HeroData.hatredLandData.clearedDifficulties == nil then
        HeroData.hatredLandData.clearedDifficulties = {}
    end
    if HeroData.hatredLandData.bestDiffDamage == nil then
        HeroData.hatredLandData.bestDiffDamage = {}
    end

    local today = TodayStr()
    if HeroData.hatredLandData.lastResetDate ~= today then
        HeroData.hatredLandData.todayAttempts = 0
        HeroData.hatredLandData.todayAdAttempts = 0
        HeroData.hatredLandData.lastResetDate = today
    end

    -- 一次性迁移：补偿因 ITEM_DEFS 缺失导致领券未入包的情况
    if not HeroData.hatredLandData._ticketFixApplied then
        local adClaimed = HeroData.hatredLandData.todayAdAttempts or 0
        local currentTickets = InventoryData.GetCount("hatred_ticket")
        -- adClaimed 次广告已看但券没进背包（当时 Add 被 ITEM_DEFS 拦截）
        -- 实际持有的券比应有的少，补差额
        local owed = adClaimed - currentTickets
        if owed > 0 then
            InventoryData.Add("hatred_ticket", owed)
            Toast.Show("补偿 憎恨之地挑战券 ×" .. owed, { 80, 220, 120 })
        end
        HeroData.hatredLandData._ticketFixApplied = true
        HeroData.Save()
    end

    return HeroData.hatredLandData
end

function HL.GetRemainingAttempts()
    local data = HL.GetData()
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("boss_attempt")
    return math.max(0, HL.DAILY_ATTEMPTS + bonusAttempt - data.todayAttempts)
end

function HL.GetFreeRemaining()
    local data = HL.GetData()
    return math.max(0, HL.FREE_ATTEMPTS - data.todayAttempts)
end

function HL.GetAdRemaining()
    local data = HL.GetData()
    return math.max(0, HL.AD_EXTRA_ATTEMPTS - (data.todayAdAttempts or 0))
end

function HL.GetBestDamage(difficultyLevel)
    local data = HL.GetData()
    if difficultyLevel ~= nil and data.bestDiffDamage then
        return data.bestDiffDamage[difficultyLevel] or data.bestDiffDamage[tostring(difficultyLevel)] or 0
    end
    local sel = data.selectedDifficulty or 0
    if data.bestDiffDamage then
        local v = data.bestDiffDamage[sel] or data.bestDiffDamage[tostring(sel)] or 0
        if v > 0 then return v end
    end
    return sel == 0 and (data.bestDamage or 0) or 0
end

function HL.GetTicketCount()
    return InventoryData.GetCount("hatred_ticket")
end

function HL.ConsumeAttempt()
    local data = HL.GetData()
    if data.todayAttempts >= HL.DAILY_ATTEMPTS then
        Toast.Show("今日挑战次数已用完", { 255, 200, 80 })
        return false
    end
    if data.todayAttempts >= HL.FREE_ATTEMPTS then
        Toast.Show("免费次数已用完，请观看广告继续", { 255, 200, 80 })
        return false
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    HeroData.Save()
    return true
end

function HL.ConsumeAdForTicket()
    local data = HL.GetData()
    local adUsed = data.todayAdAttempts or 0
    if adUsed >= HL.AD_EXTRA_ATTEMPTS then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return false
    end
    data.todayAdAttempts = adUsed + 1
    InventoryData.Add("hatred_ticket", 1)
    Toast.Show("获得 憎恨之地挑战券 ×1", { 80, 220, 120 })
    HeroData.Save()
    return true
end

function HL.ConsumeTicket()
    if InventoryData.GetCount("hatred_ticket") <= 0 then
        Toast.Show("挑战券不足", { 255, 200, 80 })
        return false
    end
    local data = HL.GetData()
    for i, slot in ipairs(InventoryData.items) do
        if slot.id == "hatred_ticket" then
            slot.count = slot.count - 1
            if slot.count <= 0 then table.remove(InventoryData.items, i) end
            break
        end
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    HeroData.Save()
    return true
end

-- ============================================================================
-- 奖励
-- ============================================================================

function HL.FormatDamage(damage)
    if damage >= 10000000000000000 then
        return string.format("%.1f京", damage / 10000000000000000)
    elseif damage >= 1000000000000 then
        return string.format("%.1f兆", damage / 1000000000000)
    elseif damage >= 100000000 then
        return string.format("%.1f亿", damage / 100000000)
    elseif damage >= 10000 then
        return string.format("%.0f万", damage / 10000)
    else
        return tostring(math.floor(damage))
    end
end

function HL.CalcRewards(totalDamage, difficultyLevel)
    local tiers = HL.GetAdjustedRewardTiers(difficultyLevel)
    local total = 0
    for _, tier in ipairs(tiers) do
        if totalDamage >= tier[1] then total = total + tier[2] end
    end
    return total
end

function HL.ClaimReward(totalDamage, difficultyLevel)
    difficultyLevel = difficultyLevel or HL.GetSelectedDifficulty()
    local data = HL.GetData()

    if not data.bestDiffDamage then data.bestDiffDamage = {} end
    local prevBestDiff = data.bestDiffDamage[difficultyLevel] or 0
    if totalDamage > prevBestDiff then
        data.bestDiffDamage[difficultyLevel] = totalDamage
    end
    if totalDamage > (data.bestDamage or 0) then
        data.bestDamage = totalDamage
    end

    local maxThreshold = HL.CONFIG.rewardTiers[#HL.CONFIG.rewardTiers][1]
    if totalDamage >= maxThreshold then
        HL.MarkDifficultyCleared(difficultyLevel)
    end

    local frostPact = HL.CalcRewards(totalDamage, difficultyLevel)
    if frostPact > 0 then
        InventoryData.Add("recruit_ticket_select_box", frostPact)
    end

    HeroData.Save(true)

    print("[HatredLand] Claimed reward: damage=" .. totalDamage
        .. " diff=" .. difficultyLevel
        .. " recruit_ticket_select_box=" .. frostPact)

    return frostPact > 0 and { recruit_ticket_select_box = frostPact } or nil
end

-- ============================================================================
-- SaveRegistry
-- ============================================================================
SaveRegistry.Register("hatredLandData", {
    group = "meta_game",
    order = 71,
    serialize = function()
        return HeroData.hatredLandData
    end,
    deserialize = function(saved, _saveData)
        HeroData.hatredLandData = saved or nil
    end,
})

return HL
