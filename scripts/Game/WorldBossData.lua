-- Game/WorldBossData.lua
-- 世界BOSS数据模块：BOSS不可击杀，20波小怪，按累计伤害发放霜誓契约奖励
-- 全服统一难度，不随主线进度缩放

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")
local SaveRegistry = require("Game.SaveRegistry")
local InventoryData = require("Game.InventoryData")
local TodayStr = require("Game.DateUtil").TodayStr
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen = require("Game.WaveGenerator")

local WB = {}

-- ============================================================================
-- 难度等级配置
-- ============================================================================

--- 难度等级定义
--- level: 难度编号（显示用）
--- label: 难度名称
--- attrMult: 全属性倍率（DEF、精英怪HP/DEF等，仅影响战斗难度）
--- scoreMult: 排行榜分数倍率（原始伤害 × scoreMult = 加权分数）
--- cdReduction: 技能冷却减少秒数
--- darkSoulBonus: 每秒额外暗魂掉落
--- rewardBonuses: 每个奖励档位额外增加的券数（长度=rewardTiers数量，总计+5）
WB.DIFFICULTY_LEVELS = {
    { level = 0, label = "普通",   attrMult = 1,             scoreMult = 1,   cdReduction = 0, darkSoulBonus = 0,
      rewardBonuses = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },  -- 总计+0
    { level = 1, label = "困难",   attrMult = 100,           scoreMult = 5,   cdReduction = 1, darkSoulBonus = 10,
      rewardBonuses = { 0, 0, 1, 0, 1, 0, 1, 0, 1, 1 } },  -- 总计+5
    { level = 3, label = "噩梦",   attrMult = 100000,        scoreMult = 25,  cdReduction = 3, darkSoulBonus = 20,
      rewardBonuses = { 0, 1, 1, 1, 1, 1, 1, 1, 1, 2 } },  -- 总计+10
    { level = 9, label = "地狱",   attrMult = 10000000000,   scoreMult = 100, cdReduction = 9, darkSoulBonus = 30,
      rewardBonuses = { 1, 1, 1, 1, 2, 2, 2, 2, 2, 1 } },  -- 总计+15
}

--- 获取难度配置（按level索引）
---@param level number 难度编号 0/1/3/9
---@return table|nil
function WB.GetDifficultyDef(level)
    for _, d in ipairs(WB.DIFFICULTY_LEVELS) do
        if d.level == level then return d end
    end
    return WB.DIFFICULTY_LEVELS[1]  -- fallback 普通
end

--- 获取当前选择的难度等级
---@return number level
function WB.GetSelectedDifficulty()
    local data = WB.GetData()
    return data.selectedDifficulty or 0
end

--- 设置当前选择的难度等级
---@param level number
function WB.SetSelectedDifficulty(level)
    local data = WB.GetData()
    -- 检查是否已解锁
    if not WB.IsDifficultyUnlocked(level) then return end
    data.selectedDifficulty = level
    HeroData.Save()
end

--- 检查某个难度是否已解锁
---@param level number
---@return boolean
function WB.IsDifficultyUnlocked(level)
    if level == 0 then return true end  -- 难度0默认解锁
    local data = WB.GetData()
    local cleared = data.clearedDifficulties or {}
    -- 找到前一个难度
    local prevLevel = nil
    for i, d in ipairs(WB.DIFFICULTY_LEVELS) do
        if d.level == level then
            if i > 1 then prevLevel = WB.DIFFICULTY_LEVELS[i - 1].level end
            break
        end
    end
    if prevLevel == nil then return true end  -- 没有前置难度
    -- 兼容：旧存档可能用 string key，新存档用 number key（DeepNormalizeIntKeys 会转为 number）
    return cleared[prevLevel] == true or cleared[tostring(prevLevel)] == true
end

--- 标记某个难度已通关
---@param level number
function WB.MarkDifficultyCleared(level)
    local data = WB.GetData()
    if not data.clearedDifficulties then
        data.clearedDifficulties = {}
    end
    data.clearedDifficulties[level] = true
    HeroData.Save()
end

--- 获取指定难度下的奖励档位表（每档加上对应的 rewardBonuses）
---@param level number|nil 难度等级，nil则用当前选择的
---@return table adjustedTiers { threshold, amount }[]
function WB.GetAdjustedRewardTiers(level)
    level = level or WB.GetSelectedDifficulty()
    local diff = WB.GetDifficultyDef(level)
    local bonuses = diff and diff.rewardBonuses or {}
    local result = {}
    for i, tier in ipairs(WB.CONFIG.rewardTiers) do
        local bonus = bonuses[i] or 0
        result[#result + 1] = { tier[1], tier[2] + bonus }
    end
    return result
end

-- ============================================================================
-- 配置常量
-- ============================================================================

WB.CONFIG = {
    -- BOSS 属性（全服统一）
    bossHP = math.maxinteger,
    bossDEF = 1000000,          -- 初始DEF（100万）
    bossSpeed = 12,
    bossSize = 28,

    -- 战斗时长
    totalDuration = 60,         -- 60秒总时长
    darkSoulDrain = 50,         -- BOSS每秒掉落暗魂数

    -- ========== 渐进难度（越打越难） ==========
    -- DEF 随时间指数增长: bossDEF × (1 + defGrowthRate)^(elapsed / defGrowthInterval)
    -- 0s=100万, 60s≈320万, 120s≈1000万, 180s≈3200万, 240s≈1亿, 300s≈3.2亿
    defGrowthRate = 0.20,       -- 每个周期增长20%
    defGrowthInterval = 5,      -- 每5秒增长一次

    -- 技能CD衰减: cooldown × max(cdMinMult, 1 - cdDecayRate × elapsed)
    -- 300秒时: shackle 15→7.5s, summon 30→15s, annihilate 45→22.5s
    cdDecayRate = 1/600,        -- 每秒衰减 1/600（300秒时衰减50%）
    cdMinMult = 0.5,            -- CD最低降至原来的50%

    -- 精英HP随时间增强: eliteHP × (1 + eliteHPGrowth × elapsed)
    eliteHPGrowthRate = 0.01,   -- 每秒+1%，300秒时精英HP ×4

    -- 束缚技能
    shackleCooldown = 15,
    shackleFirstCast = 20,
    shackleDuration = 5,
    shackleWeights = { 5, 4, 3, 2, 1 },  -- ★1~★5

    -- 召唤精英技能
    summonCooldown = 30,
    summonFirstCast = 30,
    summonMaxCount = 5,

    -- 销毁技能
    annihilateCooldown = 45,
    annihilateFirstCast = 60,
    annihilateWarning = 3,
    annihilateWeights = { 6, 4, 2, 1, 0.5 },  -- ★1~★5

    -- 奖励档位 { 伤害阈值, 霜誓契约数量 }
    rewardTiers = {
        { 5000000,         1 },  -- 500万
        { 10000000,        1 },  -- 1000万
        { 50000000,        1 },  -- 5000万
        { 250000000,       1 },  -- 2.5亿
        { 500000000,       2 },  -- 5亿
        { 1000000000,      2 },  -- 10亿
        { 2500000000,      2 },  -- 25亿
        { 5000000000,      4 },  -- 50亿
        { 10000000000,     4 },  -- 100亿
        { 25000000000,     4 },  -- 250亿
    },
}

-- ============================================================================
-- 每日次数
-- ============================================================================
WB.DAILY_ATTEMPTS    = 4
WB.FREE_ATTEMPTS     = 1
WB.AD_EXTRA_ATTEMPTS = 3

-- ============================================================================
-- BOSS 定义
-- ============================================================================

--- 创建世界BOSS定义（独立于主题系统的固定BOSS）
---@return table bossDef
function WB.CreateWorldBossDef()
    local cfg = WB.CONFIG
    return {
        id = "world_boss_abyss_lord",
        name = "深渊主宰",
        color = { 180, 30, 50 },
        icon = nil,  -- 使用精灵图渲染，不走单张图片
        spriteSheet = "world_boss",  -- 精灵图名称（在 Renderer_Utils 中注册）
        baseHP = cfg.bossHP,
        baseDEF = cfg.bossDEF,
        speed = cfg.bossSpeed,
        size = cfg.bossSize,
        shape = "diamond",
        reward = 0,
        liveCost = 0,       -- 世界BOSS不占超限名额
        isBoss = true,
        isWorldBoss = true,
        themeId = "void",
        -- BOSS 平衡规则
        passive = nil,       -- 技能由 WorldBossSkills 模块管理
    }
end

-- ============================================================================
-- 渐进难度：动态DEF / CD衰减 / 精英增强
-- ============================================================================

--- 计算当前战斗时间对应的动态DEF（支持难度倍率）
---@param elapsed number 战斗已过秒数
---@param difficultyLevel number|nil 难度等级（nil使用当前选择的）
---@return number currentDEF
function WB.GetScaledDEF(elapsed, difficultyLevel)
    local cfg = WB.CONFIG
    local periods = math.floor(elapsed / cfg.defGrowthInterval)
    local baseDEF = cfg.bossDEF * (1 + cfg.defGrowthRate) ^ periods
    -- 应用难度倍率
    local diff = WB.GetDifficultyDef(difficultyLevel or WB.GetSelectedDifficulty())
    local mult = diff and diff.attrMult or 1
    return math.floor(baseDEF * mult)
end

--- 计算技能CD衰减倍率（越久CD越短）
---@param elapsed number 战斗已过秒数
---@return number cdMult  0.5 ~ 1.0
function WB.GetCDMultiplier(elapsed)
    local cfg = WB.CONFIG
    return math.max(cfg.cdMinMult, 1 - cfg.cdDecayRate * elapsed)
end

--- 获取难度调整后的技能冷却时间
---@param baseCooldown number 基础冷却时间
---@param difficultyLevel number|nil 难度等级
---@return number adjustedCD
function WB.GetDifficultyCooldown(baseCooldown, difficultyLevel)
    local diff = WB.GetDifficultyDef(difficultyLevel or WB.GetSelectedDifficulty())
    local reduction = diff and diff.cdReduction or 0
    return math.max(1, baseCooldown - reduction)  -- 最低1秒CD
end

--- 计算精英怪HP增强倍率
---@param elapsed number 战斗已过秒数
---@return number hpMult  1.0 ~ 4.0
function WB.GetEliteHPMultiplier(elapsed)
    local cfg = WB.CONFIG
    return 1 + cfg.eliteHPGrowthRate * elapsed
end

-- ============================================================================
-- 难度缩放（全服统一）
-- ============================================================================

--- 计算某波的等效关卡号
---@param wave number 1~20
---@return number stageEquiv
function WB.WaveToStage(wave)
    local cfg = WB.CONFIG
    local base = cfg.baseStageEquiv or 5
    local scale = cfg.waveScaleRate or 0.15
    return base * (1 + (wave - 1) * scale)
end

-- HP/Speed 缩放统一使用 DungeonScaling 模块
WB.CalcHPScale    = DungeonScaling.CalcHPScale
WB.CalcSpeedScale = DungeonScaling.CalcSpeedScale

-- ============================================================================
-- 主题轮换
-- ============================================================================

--- 获取某波对应的主题索引 (1-based)
---@param wave number 1~20
---@return number themeIdx
local function GetWaveThemeIndex(wave)
    -- 1~4=1, 5~8=2, 9~12=3, 13~16=4, 17~20=5
    return math.floor((wave - 1) / 4) + 1
end

-- ============================================================================
-- 词缀系统
-- ============================================================================

--- 从池中随机选择词缀
---@param tier number 词缀阶级 1/2/3
---@return table|nil affix
local function GetRandomAffix(tier)
    local pool = {}
    for _, affix in ipairs(Config.AFFIXES) do
        if affix.tier == tier then
            pool[#pool + 1] = affix
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

--- 获取某波的词缀精英数量
---@param wave number
---@return number t1Count, number t2Count, number t3Count
local function GetWaveAffixCounts(wave)
    if wave <= 5 then
        return 0, 0, 0
    elseif wave <= 10 then
        return 1, 0, 0
    elseif wave <= 15 then
        return 2, 1, 0
    else
        return 0, 3, 1
    end
end

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

--- 生成指定波次的小怪列表（不含世界BOSS本身）
---@param wave number 1~20
---@return table enemies 敌人定义列表
function WB.GenerateWaveEnemies(wave)
    local stageEquiv = WB.WaveToStage(wave)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = WB.CalcHPScale(stageEquiv)
    local spdScale = WB.CalcSpeedScale(wave)

    -- 主题轮换
    local themeIdx = GetWaveThemeIndex(wave)
    if themeIdx > Config.THEME_COUNT then themeIdx = Config.THEME_COUNT end
    local theme = Config.THEMES[themeIdx]

    -- 可用角色池
    local availRoles = WaveGen.BuildRolePool(stageNum)

    -- 基础敌人
    local count = WB.CONFIG.enemiesPerWave
    local enemies = WaveGen.GenerateBatch(stageNum, count, hpScale, spdScale, nil, availRoles)

    -- 词缀精英（世界 Boss 特有：按 tier 分配词缀）
    local t1Count, t2Count, t3Count = GetWaveAffixCounts(wave)
    local totalElites = t1Count + t2Count + t3Count
    for i = 1, math.min(totalElites, #enemies) do
        enemies[i].isElite = true
        local tier
        if i <= t3Count then
            tier = 3
        elseif i <= t3Count + t2Count then
            tier = 2
        else
            tier = 1
        end
        local affix = GetRandomAffix(tier)
        if affix then
            enemies[i].eliteAffixes = { affix }
        end
    end

    return enemies
end

-- ============================================================================
-- 进度管理
-- ============================================================================

--- 获取世界BOSS进度数据（懒初始化 + 每日重置）
---@return table
function WB.GetData()
    if not HeroData.worldBossData then
        HeroData.worldBossData = {
            bestDamage = 0,
            todayAttempts = 0,
            todayAdAttempts = 0,
            lastResetDate = TodayStr(),
            totalAttempts = 0,
            selectedDifficulty = 0,
            clearedDifficulties = {},
        }
    end
    -- 兼容旧存档：补充新字段
    if HeroData.worldBossData.selectedDifficulty == nil then
        HeroData.worldBossData.selectedDifficulty = 0
    end
    if HeroData.worldBossData.clearedDifficulties == nil then
        HeroData.worldBossData.clearedDifficulties = {}
    end
    -- v3 迁移：重置旧的加权分数（旧版用 attrMult 计算，数值极大，不适用于 v3 的 scoreMult）
    if not HeroData.worldBossData.scoreMultMigrated then
        HeroData.worldBossData.bestWeightedDamage = HeroData.worldBossData.bestDamage or 0
        HeroData.worldBossData.bestWeightedDifficulty = 0
        HeroData.worldBossData.bestDailyWeightedDamage = 0
        HeroData.worldBossData.bestDailyWeightedDifficulty = 0
        HeroData.worldBossData.scoreMultMigrated = true
    end

    -- 每日重置
    local today = TodayStr()
    if HeroData.worldBossData.lastResetDate ~= today then
        HeroData.worldBossData.todayAttempts = 0
        HeroData.worldBossData.todayAdAttempts = 0
        HeroData.worldBossData.bestDailyDamage = 0
        HeroData.worldBossData.bestDailyWeightedDamage = 0
        HeroData.worldBossData.bestDailyWeightedDifficulty = 0
        HeroData.worldBossData.bestDailyDiffDamage = {}  -- 清理按难度每日最高
        HeroData.worldBossData.lastResetDate = today
    end

    return HeroData.worldBossData
end

--- 获取每日总次数上限（含神裔降临加成）
---@return number
function WB.GetMaxAttempts()
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("boss_attempt")
    return WB.DAILY_ATTEMPTS + bonusAttempt
end

--- 获取每日剩余免费+广告次数（含神裔降临加成）
---@return number
function WB.GetRemainingAttempts()
    local data = WB.GetData()
    return math.max(0, WB.GetMaxAttempts() - data.todayAttempts)
end

--- 获取总可用挑战次数（每日剩余 + 挑战券），用于顶部"剩余 X 次"显示
---@return number
function WB.GetTotalAvailable()
    return WB.GetRemainingAttempts() + WB.GetTicketCount()
end

--- 获取剩余免费次数
---@return number
function WB.GetFreeRemaining()
    local data = WB.GetData()
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("boss_attempt")
    return math.max(0, WB.FREE_ATTEMPTS + bonusAttempt - data.todayAttempts)
end

--- 获取剩余广告次数
---@return number
function WB.GetAdRemaining()
    local data = WB.GetData()
    return math.max(0, WB.AD_EXTRA_ATTEMPTS - (data.todayAdAttempts or 0))
end

--- 获取最高伤害
---@return number
function WB.GetBestDamage(difficultyLevel)
    local data = WB.GetData()
    -- 按难度独立记录
    if difficultyLevel ~= nil and data.bestDiffDamage then
        return data.bestDiffDamage[difficultyLevel] or data.bestDiffDamage[tostring(difficultyLevel)] or 0
    end
    -- 未指定难度：返回当前选择难度的最高伤害
    local sel = data.selectedDifficulty or 0
    if data.bestDiffDamage then
        local v = data.bestDiffDamage[sel] or data.bestDiffDamage[tostring(sel)] or 0
        if v > 0 then return v end
    end
    -- 兼容旧存档：旧数据只有全局 bestDamage，归入难度 0
    return sel == 0 and (data.bestDamage or 0) or 0
end

--- 消耗免费次数
---@return boolean
function WB.ConsumeAttempt()
    local data = WB.GetData()
    if data.todayAttempts >= WB.GetMaxAttempts() then
        Toast.Show("今日挑战次数已用完", { 255, 200, 80 })
        return false
    end
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("boss_attempt")
    if data.todayAttempts >= WB.FREE_ATTEMPTS + bonusAttempt then
        Toast.Show("免费次数已用完，请观看广告继续", { 255, 200, 80 })
        return false
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    HeroData.Save()
    return true
end

--- 消耗广告领券次数（看完广告后调用，发一张 boss_ticket 到背包）
---@return boolean
function WB.ConsumeAdForTicket()
    local data = WB.GetData()
    local adUsed = data.todayAdAttempts or 0
    if adUsed >= WB.AD_EXTRA_ATTEMPTS then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return false
    end
    data.todayAdAttempts = adUsed + 1
    InventoryData.Add("boss_ticket", 1)
    Toast.Show("获得 深渊主宰挑战券 ×1", { 80, 220, 120 })
    HeroData.Save()
    return true
end

--- 获取背包中 Boss 挑战券数量
---@return number
function WB.GetTicketCount()
    return InventoryData.GetCount("boss_ticket")
end

--- 消耗一张 Boss 挑战券进入挑战
---@return boolean
function WB.ConsumeTicket()
    if InventoryData.GetCount("boss_ticket") <= 0 then
        Toast.Show("挑战券不足", { 255, 200, 80 })
        return false
    end
    local data = WB.GetData()
    -- 扣券
    for i, slot in ipairs(InventoryData.items) do
        if slot.id == "boss_ticket" then
            slot.count = slot.count - 1
            if slot.count <= 0 then
                table.remove(InventoryData.items, i)
            end
            break
        end
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    HeroData.Save()
    return true
end

-- ============================================================================
-- 奖励结算
-- ============================================================================

--- 计算累计伤害可获得的奖励（支持难度加成）
---@param totalDamage number
---@param difficultyLevel number|nil 难度等级（nil使用当前选择的）
---@return number total 招募券自选包总数
function WB.CalcRewards(totalDamage, difficultyLevel)
    local tiers = WB.GetAdjustedRewardTiers(difficultyLevel)
    local total = 0
    for _, tier in ipairs(tiers) do
        if totalDamage >= tier[1] then
            total = total + tier[2]
        end
    end
    return total
end

--- 结算奖励（战斗结束时调用）
---@param totalDamage number 本场对BOSS累计伤害
---@param difficultyLevel number|nil 难度等级（nil使用当前选择的）
---@return table|nil rewards { recruit_ticket_select_box = amount }
function WB.ClaimReward(totalDamage, difficultyLevel)
    difficultyLevel = difficultyLevel or WB.GetSelectedDifficulty()
    local data = WB.GetData()

    -- 更新最高纪录（按难度独立记录）
    if not data.bestDiffDamage then data.bestDiffDamage = {} end
    local prevBestDiff = data.bestDiffDamage[difficultyLevel] or 0
    if totalDamage > prevBestDiff then
        data.bestDiffDamage[difficultyLevel] = totalDamage
    end
    -- 兼容：同时更新全局 bestDamage（取所有难度最大值）
    if totalDamage > (data.bestDamage or 0) then
        data.bestDamage = totalDamage
    end

    -- 标记该难度已通关（必须达到最高奖励档位才算通关，解锁下一个难度）
    local maxThreshold = WB.CONFIG.rewardTiers[#WB.CONFIG.rewardTiers][1]  -- 250亿
    if totalDamage >= maxThreshold then
        WB.MarkDifficultyCleared(difficultyLevel)
    end

    -- 计算奖励（招募券自选包，含难度加成）
    local frostPact = WB.CalcRewards(totalDamage, difficultyLevel)
    if frostPact > 0 then
        InventoryData.Add("recruit_ticket_select_box", frostPact)
    end

    -- 计算加权伤害（原始伤害 × 分数倍率），用于排行榜
    -- 注意：用 scoreMult（分数倍率）而非 attrMult（属性倍率），避免天文数字
    local diffDef = WB.GetDifficultyDef(difficultyLevel)
    local scoreMult = diffDef and diffDef.scoreMult or 1
    local weightedDamage = totalDamage * scoreMult

    -- 更新最高加权伤害（历史总榜用）
    local bestWeighted = data.bestWeightedDamage or 0
    if weightedDamage > bestWeighted then
        data.bestWeightedDamage = weightedDamage
        data.bestWeightedDifficulty = difficultyLevel
    end

    -- 更新当日最高加权伤害
    local bestDailyWeighted = data.bestDailyWeightedDamage or 0
    if weightedDamage > bestDailyWeighted then
        data.bestDailyWeightedDamage = weightedDamage
        data.bestDailyWeightedDifficulty = difficultyLevel
    end

    -- 上传排行榜（历史总榜 + 每日榜 + 按难度每日榜）
    local ok, LBMod = pcall(require, "Game.LeaderboardData")
    if ok then
        if LBMod.UploadWorldBoss then
            LBMod.UploadWorldBoss(data.bestWeightedDamage, data.bestWeightedDifficulty)
        end
        if LBMod.UploadWorldBossDaily and weightedDamage > bestDailyWeighted then
            LBMod.UploadWorldBossDaily(data.bestDailyWeightedDamage, data.bestDailyWeightedDifficulty)
        end
        -- 按难度独立每日排行榜（原始伤害，同难度内排序）
        -- 记录每难度当日最高原始伤害
        if not data.bestDailyDiffDamage then data.bestDailyDiffDamage = {} end
        local diffKey = tostring(difficultyLevel)
        local prevBest = data.bestDailyDiffDamage[diffKey] or 0
        if totalDamage > prevBest then
            data.bestDailyDiffDamage[diffKey] = totalDamage
            if LBMod.UploadWorldBossDiffDaily then
                LBMod.UploadWorldBossDiffDaily(totalDamage, difficultyLevel)
            end
        end
    end

    HeroData.Save(true)

    print("[WorldBoss] Claimed reward: damage=" .. totalDamage
        .. " weighted=" .. weightedDamage
        .. " diff=" .. difficultyLevel
        .. " recruit_ticket_select_box=" .. frostPact
        .. " bestWeighted=" .. (data.bestWeightedDamage or 0))

    local result = { recruit_ticket_select_box = frostPact, rewardDefs = {} }
    if frostPact > 0 then
        result.rewardDefs[#result.rewardDefs + 1] = { type = "item", id = "recruit_ticket_select_box", amount = frostPact }
    end
    return result
end

-- ============================================================================
-- 伤害格式化
-- ============================================================================

--- 格式化伤害数值为可读字符串
---@param damage number
---@return string
function WB.FormatDamage(damage)
    if not damage or damage ~= damage or damage == math.huge or damage == -math.huge then
        return "0"
    end
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

-- ============================================================================
-- 战斗配置构建（静态部分，不含 UI 回调）
-- ============================================================================

--- 构建世界BOSS战斗配置（纯数据，无 UI 依赖）
---@param challengeDifficulty number 选择的难度等级
---@return table config 静态配置
---@return table bossDef BOSS定义（含 bossSkills，供 BossSkills 模块使用）
function WB.BuildBattleConfig(challengeDifficulty)
    local cfg = WB.CONFIG
    local diffDef = WB.GetDifficultyDef(challengeDifficulty)

    local bossDef = WB.CreateWorldBossDef()
    bossDef.baseDEF = (bossDef.baseDEF or cfg.bossDEF) * diffDef.attrMult

    local waves = {
        {
            {
                type = bossDef.id or "world_boss",
                typeDef = bossDef,
                delay = 0,
                isElite = false,
                affixes = {},
                prescaled = true,
            },
        },
    }

    local label = "世界BOSS · 深渊主宰" .. (challengeDifficulty > 0 and (" [" .. diffDef.label .. "]") or "")

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
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("worldBossData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.worldBossData
    end,
    deserialize = function(saved, _saveData)
        HeroData.worldBossData = saved or nil
    end,
})

return WB
