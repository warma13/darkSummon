-- Game/HatredLandData.lua
-- 憎恨之地数据模块：挑战憎恨化身BOSS，按累计伤害发放奖励

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
    { level = 0, label = "普通",   attrMult = 1,           scoreMult = 1,   cdReduction = 0, darkSoulBonus = 0,  rewardMult = 1 },
    { level = 1, label = "困难",   attrMult = 100,         scoreMult = 5,   cdReduction = 1, darkSoulBonus = 10, rewardMult = 2 },
    { level = 3, label = "噩梦",   attrMult = 100000,      scoreMult = 25,  cdReduction = 3, darkSoulBonus = 20, rewardMult = 4 },
    { level = 9, label = "地狱",   attrMult = 10000000000, scoreMult = 100, cdReduction = 9, darkSoulBonus = 30, rewardMult = 8 },
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

--- 公式计算奖励预览采样点（用于 UI 显示）
--- 返回 { {damage, essence, shards}, ... }
function HL.GetRewardSamplePoints(level)
    local sampleDamages = HL.REWARD_SAMPLE_DAMAGES
    local result = {}
    for _, dmg in ipairs(sampleDamages) do
        local calc = HL.CalcRewardsRaw(dmg, level)
        result[#result + 1] = { dmg, calc.essence, calc.shards }
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

    --- 奖励公式参数 (幂函数 + 边际递减)
    --- essence = floor(essenceScale * (damage / essenceBase) ^ essenceExp * rewardMult)
    --- shards  = max(1, floor(essence / shardsPerEssence))
    rewardFormula = {
        essenceScale = 5,           -- 基础系数
        essenceBase  = 1000000,     -- 归一化基准（百万）
        essenceExp   = 0.4,         -- 指数 <1 → 边际递减
        minDamage    = 10000000,    -- 最低伤害门槛（千万）
        shardsPerEssence = 300,     -- 每 300 精华产出 1 碎片
    },
}

--- UI 预览采样伤害点
HL.REWARD_SAMPLE_DAMAGES = {
    50000000,           -- 5000万
    500000000,          -- 5亿
    5000000000,         -- 50亿
    50000000000,        -- 500亿
    500000000000,       -- 5000亿
    5000000000000,      -- 5兆
    50000000000000,     -- 50兆
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
    bossDef.baseHP = math.huge
    bossDef.baseDEF = cfg.bossDEF
    bossDef.speed = 12
    bossDef.size = 28
    bossDef.reward = 0
    bossDef.liveCost = 0
    bossDef.isWorldBoss = true   -- 走世界BOSS流程
    bossDef.isHatredBoss = true
    bossDef.themeId = "void"
    bossDef.spriteSheet = "hatred_boss"  -- 使用憎恨化身专属精灵图
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

--- 公式计算奖励（内部，不含难度倍率）
--- @param totalDamage number
--- @return {essence: number, shards: number}
function HL.CalcRewardsBase(totalDamage)
    local f = HL.CONFIG.rewardFormula
    if totalDamage < f.minDamage then
        return { essence = 0, shards = 0 }
    end
    local rawEssence = f.essenceScale * (totalDamage / f.essenceBase) ^ f.essenceExp
    local essence = math.floor(rawEssence)
    local shards = math.max(1, math.floor(essence / f.shardsPerEssence))
    return { essence = essence, shards = shards }
end

--- 公式计算奖励（含难度倍率），用于指定伤害值预览
function HL.CalcRewardsRaw(totalDamage, difficultyLevel)
    local base = HL.CalcRewardsBase(totalDamage)
    if base.essence == 0 then return base end
    local diff = HL.GetDifficultyDef(difficultyLevel or 0)
    local mult = diff and diff.rewardMult or 1
    return {
        essence = math.floor(base.essence * mult),
        shards = math.max(1, math.floor(base.essence * mult / HL.CONFIG.rewardFormula.shardsPerEssence)),
    }
end

--- 计算奖励总量: 返回 { essence=总精华, shards=总碎片 }
function HL.CalcRewards(totalDamage, difficultyLevel)
    return HL.CalcRewardsRaw(totalDamage, difficultyLevel)
end

-- 难度等级 → 掉落权重 key 的映射
local DIFF_TO_DROP_KEY = {
    [0] = "normal",
    [1] = "hard",
    [3] = "nightmare",
    [9] = "hell",
}

function HL.ClaimReward(totalDamage, difficultyLevel)
    difficultyLevel = difficultyLevel or HL.GetSelectedDifficulty()
    local data = HL.GetData()

    if not data.bestDiffDamage then data.bestDiffDamage = {} end
    local prevBestDiff = data.bestDiffDamage[difficultyLevel]
        or data.bestDiffDamage[tostring(difficultyLevel)] or 0
    if totalDamage > prevBestDiff then
        data.bestDiffDamage[difficultyLevel] = totalDamage
    end
    if totalDamage > (data.bestDamage or 0) then
        data.bestDamage = totalDamage
    end

    local maxSample = HL.REWARD_SAMPLE_DAMAGES[#HL.REWARD_SAMPLE_DAMAGES]
    if totalDamage >= maxSample then
        HL.MarkDifficultyCleared(difficultyLevel)
    end

    local calc = HL.CalcRewards(totalDamage, difficultyLevel)
    local hasReward = calc.essence > 0 or calc.shards > 0

    -- 发放遗物精华
    if calc.essence > 0 then
        HeroData.currencies.relic_essence = (HeroData.currencies.relic_essence or 0) + calc.essence
    end

    -- 发放随机遗物碎片（per-relic 模式）
    local RelicData = require("Game.RelicData")
    local shardDetail = {}  -- { [relicId] = count }
    if calc.shards > 0 then
        -- 构建全遗物池
        local allRelicIds = {}
        for _, slot in ipairs(Config.RELIC_SLOT_IDS) do
            for _, rDef in ipairs(Config.RELICS_BY_SLOT[slot] or {}) do
                allRelicIds[#allRelicIds + 1] = rDef.id
            end
        end
        for i = 1, calc.shards do
            local relicId = allRelicIds[math.random(1, #allRelicIds)]
            shardDetail[relicId] = (shardDetail[relicId] or 0) + 1
        end
        for relicId, count in pairs(shardDetail) do
            RelicData.Decompose(relicId, count)
        end
    end

    -- 遗物碎片掉落：需达到伤害门槛才触发
    local relicDropResult = nil
    if hasReward then
        local dropKey = DIFF_TO_DROP_KEY[difficultyLevel] or "normal"
        local drop = RelicData.RollDrop(dropKey)
        relicDropResult = RelicData.ProcessDrop(drop)
    end

    HeroData.Save(true)

    -- 排行榜上传（按难度每日榜）
    local ok_lb, LBMod = pcall(require, "Game.LeaderboardData")
    if ok_lb and LBMod.UploadHatredLandDiffDaily then
        LBMod.UploadHatredLandDiffDaily(totalDamage, difficultyLevel)
    end

    if hasReward then
        local synInfo = ""
        if relicDropResult and relicDropResult.synthResult then
            synInfo = " SYNTH=" .. relicDropResult.synthResult.relicName
        end
        print("[HatredLand] Claimed reward: damage=" .. totalDamage
            .. " diff=" .. difficultyLevel
            .. " essence=" .. calc.essence .. " shards=" .. calc.shards
            .. " relicShards=+" .. (relicDropResult and relicDropResult.shards or 0)
            .. synInfo)
    end

    if not hasReward then return nil end

    -- 构建 rewardDefs 供 RewardController 统一展示
    local rewardDefs = {}
    if calc.essence > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "relic_essence", amount = calc.essence }
    end
    for relicId, count in pairs(shardDetail) do
        rewardDefs[#rewardDefs + 1] = { type = "relic_shard", id = relicId, amount = count }
    end
    if relicDropResult then
        if relicDropResult.shards and relicDropResult.shards > 0 then
            rewardDefs[#rewardDefs + 1] = { type = "relic_shard", id = relicDropResult.relicId, amount = relicDropResult.shards }
        end
        if relicDropResult.synthResult then
            local sr = relicDropResult.synthResult
            local qColor = Config.RELIC_QUALITY_COLOR[sr.quality] or { 180, 180, 180 }
            rewardDefs[#rewardDefs + 1] = {
                type = "synth_result",
                id = sr.relicId or "",
                amount = 1,
                displayName = "合成: " .. sr.relicName .. " (" .. (Config.RELIC_QUALITY_NAME[sr.quality] or "?") .. ")",
                displayIcon = "",
                borderColor = { qColor[1], qColor[2], qColor[3], 200 },
            }
        end
    end

    return {
        essence = calc.essence,
        shards = calc.shards,
        shardDetail = shardDetail,
        relicDrop = relicDropResult,
        rewardDefs = rewardDefs,
    }
end

-- ============================================================================
-- 战斗配置构建（静态部分，不含 UI 回调）
-- ============================================================================

--- 构建憎恨之地战斗配置（纯数据，无 UI 依赖）
---@param challengeDifficulty number 选择的难度等级
---@return table config 静态配置
---@return table bossDef BOSS定义（含 bossSkills，供 BossSkills 模块使用）
function HL.BuildBattleConfig(challengeDifficulty)
    local cfg = HL.CONFIG
    local diffDef = HL.GetDifficultyDef(challengeDifficulty)

    local bossDef = HL.CreateBossDef()
    bossDef.baseDEF = (bossDef.baseDEF or cfg.bossDEF) * diffDef.attrMult

    local waves = {
        {
            {
                type = bossDef.id or "hatred_body",
                typeDef = bossDef,
                delay = 0,
                isElite = false,
                affixes = {},
                prescaled = true,
            },
        },
    }

    local label = "憎恨之地 · 憎恨化身" .. (challengeDifficulty > 0 and (" [" .. diffDef.label .. "]") or "")

    local config = {
        mode = "world_boss",
        waves = waves,
        totalWaves = 1,
        stageNum = 1,
        label = label,
        waveInterval = 0,
        autoAdvanceWave = false,
        bossTimerEnabled = true,
        overloadEnabled = false,
        worldBossDuration = cfg.totalDuration,
        worldBossDarkSoulDrain = cfg.darkSoulDrain + diffDef.darkSoulBonus,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
    }

    return config, bossDef
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
