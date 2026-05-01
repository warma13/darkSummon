-- Game/GarbageBossData.lua
-- 垃圾大扫除副本数据模块
-- 劳动节限时活动：无限HP垃圾Boss，个人累计伤害里程碑奖励
-- 每日3次，60秒限时，活动持续与劳动节相同

local Config         = require("Game.Config")
local HeroData       = require("Game.HeroData")
local Currency       = require("Game.Currency")
local Toast          = require("Game.Toast")
local SaveRegistry   = require("Game.SaveRegistry")
local InventoryData  = require("Game.InventoryData")
local TodayStr       = require("Game.DateUtil").TodayStr
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen        = require("Game.WaveGenerator")
local LaborDayData   = require("Game.LaborDayData")

local LB = require("Game.LeaderboardData")

local GB = {}

-- ============================================================================
-- 全服总伤害缓存
-- ============================================================================

local _serverTotalCache = {
    value    = 0,       -- 全服累计伤害
    fetchTime = 0,      -- 上次获取时间戳
    fetching  = false,  -- 是否正在请求中
}
local SERVER_CACHE_TTL = 60  -- 缓存有效期（秒）

-- ============================================================================
-- 活动时间（与劳动节共享）
-- ============================================================================

local START_DATE, END_DATE
do
    local ok, LDD = pcall(require, "Game.LaborDayData")
    if ok then
        START_DATE = LDD.START_DATE
        END_DATE   = LDD.END_DATE
    else
        START_DATE = "2026-04-30"
        END_DATE   = "2026-05-08"
    end
end

GB.START_DATE = START_DATE
GB.END_DATE   = END_DATE

-- ============================================================================
-- 配置常量
-- ============================================================================

GB.CONFIG = {
    -- BOSS 属性
    bossHP    = math.huge,      -- 无限HP，不可击杀
    bossDEF   = 500000,         -- 初始DEF（50万，比世界Boss低一档）
    bossSpeed = 10,
    bossSize  = 30,

    -- 战斗时长
    totalDuration   = 60,       -- 60秒
    darkSoulDrain   = 40,       -- 每秒掉落暗魂

    -- 渐进难度
    defGrowthRate     = 0.15,   -- 每周期DEF增长15%
    defGrowthInterval = 5,      -- 每5秒一个周期
    cdDecayRate       = 1/600,
    cdMinMult         = 0.5,

    -- 伤害里程碑奖励 { 伤害阈值, 奖励定义列表 }
    -- 10档等比递增：1万京(1e20) ~ 10亿垓(1e29)，每档×10
    rewardTiers = {
        { 1e20,                      -- 1万京
          { { type = "currency", id = "shadow_essence",  amount = 1000 },
            { type = "currency", id = "labor_medal",     amount = 2 } } },
        { 1e21,                      -- 10万京
          { { type = "currency", id = "shadow_essence",  amount = 2000 },
            { type = "currency", id = "labor_medal",     amount = 4 } } },
        { 1e22,                      -- 100万京
          { { type = "item",     id = "recruit_ticket_select_box", amount = 10 },
            { type = "currency", id = "labor_medal",     amount = 6 } } },
        { 1e23,                      -- 1000万京
          { { type = "item",     id = "recruit_ticket_select_box", amount = 20 },
            { type = "currency", id = "labor_medal",     amount = 10 } } },
        { 1e24,                      -- 1亿京
          { { type = "currency", id = "abyss_crystal",   amount = 4 },
            { type = "currency", id = "labor_medal",     amount = 16 } } },
        { 1e25,                      -- 10亿京
          { { type = "item",     id = "random_mythic_rune_box", amount = 1 },
            { type = "currency", id = "labor_medal",     amount = 20 } } },
        { 1e26,                      -- 100亿京
          { { type = "item",     id = "recruit_ticket_select_box", amount = 40 },
            { type = "item",     id = "random_mythic_rune_box", amount = 2 },
            { type = "currency", id = "labor_medal",     amount = 30 } } },
        { 1e27,                      -- 1000亿京
          { { type = "currency", id = "abyss_crystal",   amount = 10 },
            { type = "item",     id = "recruit_ticket_select_box", amount = 60 },
            { type = "currency", id = "labor_medal",     amount = 40 } } },
        { 1e28,                      -- 1万亿京
          { { type = "item",     id = "recruit_ticket_select_box", amount = 100 },
            { type = "currency", id = "abyss_crystal",   amount = 20 },
            { type = "currency", id = "labor_medal",     amount = 60 } } },
        { 1e29,                      -- 10万亿京
          { { type = "item",     id = "recruit_ticket_select_box", amount = 160 },
            { type = "item",     id = "random_mythic_rune_box", amount = 4 },
            { type = "currency", id = "abyss_crystal",   amount = 40 },
            { type = "currency", id = "labor_medal",     amount = 100 } } },
    },
}

-- ============================================================================
-- 每日次数
-- ============================================================================

GB.DAILY_ATTEMPTS = 3

-- ============================================================================
-- 活动状态
-- ============================================================================

local DateUtil = require("Game.DateUtil")

function GB.IsActive()
    local today = DateUtil.TodayStr()
    return today >= START_DATE and today <= END_DATE
end

function GB.IsExpired()
    return DateUtil.TodayStr() > END_DATE
end

--- 获取活动剩余时间字符串
---@return string
function GB.GetRemainingTimeStr()
    if not GB.IsActive() then return "已结束" end
    local y, m, d = END_DATE:match("(%d+)-(%d+)-(%d+)")
    local endTs = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 }) + 86400
    local remainSec = math.max(0, endTs - os.time())
    local days = math.floor(remainSec / 86400)
    local hours = math.floor((remainSec % 86400) / 3600)
    return days .. "天" .. string.format("%02d", hours) .. "小时"
end

-- ============================================================================
-- BOSS 定义
-- ============================================================================

--- 创建垃圾Boss定义
---@return table bossDef
function GB.CreateBossDef()
    local cfg = GB.CONFIG
    return {
        id = "garbage_boss",
        name = "垃圾山大王",
        color = { 80, 140, 50 },
        icon = nil,
        spriteSheet = "garbage_boss",
        baseHP = cfg.bossHP,
        baseDEF = cfg.bossDEF,
        speed = cfg.bossSpeed,
        size = cfg.bossSize,
        shape = "diamond",
        reward = 0,
        liveCost = 0,
        isBoss = true,
        isWorldBoss = true,
        isGarbageBoss = true,
        themeId = "forest",
        passive = nil,

        -- Boss 技能机制配置（供 GarbageBossSkills.Init 使用）
        bossSkills = {
            -- 技能1: 垃圾堆积 — 路径生成不可移动垃圾，每个垃圾降全英雄攻击力1%
            garbage_pile = {
                interval    = 5,         -- CD 5秒
                spawnCount  = 10,        -- 每次生成10个垃圾
                baseStage   = 2000,      -- 初始等效2000关
                stageGrowth = 2000,      -- 每次释放+2000关
            },
            -- 技能2: 毒雾召唤 — 召唤移动垃圾小怪 + 全英雄攻速-10%（本局叠加）
            toxic_summon = {
                interval       = 10,      -- CD 10秒
                summonCount    = 5,       -- 每次召唤5只
                baseStage      = 2000,    -- 初始等效2000关
                stageGrowth    = 2000,    -- 每次释放+2000关
                spdReductionPct = 0.10,   -- 每次降低攻速10%
            },
            -- 技能3: 垃圾风暴 — 随机位置降下垃圾，命中英雄降1星（可打断）
            trash_storm = {
                interval        = 15,      -- CD 15秒
                channelTime     = 1.0,     -- 引导1秒
                baseCount       = 1,       -- 初始1个陨石
                toughnessDefDiv = 80000,   -- 韧性 = DEF / 80000
                toughnessMin    = 15,      -- 最低韧性15次
            },
        },
    }
end

-- ============================================================================
-- 渐进难度
-- ============================================================================

--- 计算动态DEF
---@param elapsed number
---@return number
function GB.GetScaledDEF(elapsed)
    local cfg = GB.CONFIG
    local periods = math.floor(elapsed / cfg.defGrowthInterval)
    return math.floor(cfg.bossDEF * (1 + cfg.defGrowthRate) ^ periods)
end

--- 计算技能CD衰减倍率
---@param elapsed number
---@return number
function GB.GetCDMultiplier(elapsed)
    local cfg = GB.CONFIG
    return math.max(cfg.cdMinMult, 1 - cfg.cdDecayRate * elapsed)
end

-- ============================================================================
-- 进度管理
-- ============================================================================

--- 获取垃圾Boss进度数据（懒初始化 + 每日重置）
---@return table
function GB.GetData()
    if not HeroData.garbageBossData then
        HeroData.garbageBossData = {
            totalDamage    = 0,     -- 个人累计总伤害
            bestDamage     = 0,     -- 单次最高伤害
            todayAttempts  = 0,     -- 今日已用次数
            bonusAttempts  = 0,     -- 额外赠送次数（不受每日重置影响）
            lastResetDate  = TodayStr(),
            totalAttempts  = 0,     -- 历史总挑战次数
            claimedTiers   = {},    -- 已领取的里程碑索引 { [1]=true, [2]=true }
            hasFought      = false, -- 是否至少打过一次
        }
    end

    -- 每日重置
    local today = TodayStr()
    if HeroData.garbageBossData.lastResetDate ~= today then
        HeroData.garbageBossData.todayAttempts = 0
        HeroData.garbageBossData.lastResetDate = today
    end

    return HeroData.garbageBossData
end

--- 获取每日剩余次数（含额外赠送次数）
---@return number
function GB.GetRemainingAttempts()
    local data = GB.GetData()
    local bonus = data.bonusAttempts or 0
    return math.max(0, GB.DAILY_ATTEMPTS + bonus - data.todayAttempts)
end

--- 消耗一次挑战次数
---@return boolean
function GB.ConsumeAttempt()
    local data = GB.GetData()
    local bonus = data.bonusAttempts or 0
    local totalAllowed = GB.DAILY_ATTEMPTS + bonus
    if data.todayAttempts >= totalAllowed then
        Toast.Show("挑战次数已用完", { 255, 200, 80 })
        return false
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    data.hasFought = true
    -- 如果超过基础次数，扣减额外次数
    if data.todayAttempts > GB.DAILY_ATTEMPTS then
        data.bonusAttempts = math.max(0, bonus - 1)
    end
    HeroData.Save()
    return true
end

--- 添加额外挑战次数（不受每日重置影响）
---@param amount number
function GB.AddBonusAttempts(amount)
    local data = GB.GetData()
    data.bonusAttempts = (data.bonusAttempts or 0) + amount
    HeroData.Save()
    Toast.Show("获得垃圾Boss额外挑战次数 ×" .. amount, { 100, 220, 80 })
end

--- 获取个人累计总伤害
---@return number
function GB.GetTotalDamage()
    local data = GB.GetData()
    return data.totalDamage or 0
end

--- 获取单次最高伤害
---@return number
function GB.GetBestDamage()
    local data = GB.GetData()
    return data.bestDamage or 0
end

-- ============================================================================
-- 全服总伤害
-- ============================================================================

--- 获取全服累计总伤害（缓存值，异步刷新）
---@return number
function GB.GetServerTotalDamage()
    return _serverTotalCache.value
end

--- 异步获取全服累计总伤害（从排行榜拉取前100名求和，带缓存）
--- 调用后通过 GB.GetServerTotalDamage() 获取结果
---@param callback function|nil 可选回调 (totalDamage)
function GB.FetchServerTotal(callback)
    local now = os.time()
    -- 缓存有效，直接返回
    if (now - _serverTotalCache.fetchTime) < SERVER_CACHE_TTL and _serverTotalCache.value > 0 then
        if callback then callback(_serverTotalCache.value) end
        return
    end
    -- 正在请求中，避免重复
    if _serverTotalCache.fetching then
        if callback then callback(_serverTotalCache.value) end
        return
    end

    if not clientCloud then
        if callback then callback(0) end
        return
    end

    _serverTotalCache.fetching = true
    local key = LB.KEY_GARBAGE_BOSS

    clientCloud:GetRankList(key, 0, 100, {
        ok = function(rankList)
            local totalDmg = 0
            for _, item in ipairs(rankList) do
                local scoreVal = 0
                if item.iscore then
                    local v = item.iscore[key]
                    if v and type(v) == "number" and v > 0 then
                        scoreVal = v
                    end
                end
                -- 回退：取 iscore 中最大值
                if scoreVal == 0 and item.iscore then
                    pcall(function()
                        for _, v in pairs(item.iscore) do
                            if type(v) == "number" and v > scoreVal then
                                scoreVal = v
                            end
                        end
                    end)
                end
                if scoreVal > 0 then
                    local dmg = LB.DecodeBossScore(scoreVal)
                    totalDmg = totalDmg + dmg
                end
            end
            _serverTotalCache.value = totalDmg
            _serverTotalCache.fetchTime = os.time()
            _serverTotalCache.fetching = false
            print("[GarbageBoss] Server total damage fetched: " .. GB.FormatDamage(totalDmg)
                .. " (from " .. #rankList .. " players)")
            if callback then callback(totalDmg) end
        end,
        error = function(code, reason)
            _serverTotalCache.fetching = false
            print("[GarbageBoss] Server total fetch FAILED: " .. tostring(code) .. " " .. tostring(reason))
            if callback then callback(_serverTotalCache.value) end
        end,
    })
end

--- 是否至少打过一次
---@return boolean
function GB.HasFought()
    local data = GB.GetData()
    return data.hasFought == true
end

-- ============================================================================
-- 里程碑奖励
-- ============================================================================

--- 获取里程碑状态列表（基于全服累计伤害判定）
---@return table[] { threshold, rewards, reached, claimed }
function GB.GetMilestones()
    local data = GB.GetData()
    local serverTotal = GB.GetServerTotalDamage()
    local result = {}
    for i, tier in ipairs(GB.CONFIG.rewardTiers) do
        result[#result + 1] = {
            index     = i,
            threshold = tier[1],
            rewards   = tier[2],
            reached   = serverTotal >= tier[1],
            claimed   = data.claimedTiers[i] == true,
        }
    end
    return result
end

--- 领取指定里程碑奖励
---@param tierIndex number 1-10
---@return boolean success
function GB.ClaimMilestone(tierIndex)
    local data = GB.GetData()
    if not data.hasFought then
        Toast.Show("需要至少打一次才能领取", { 255, 200, 80 })
        return false
    end

    local tier = GB.CONFIG.rewardTiers[tierIndex]
    if not tier then return false end

    local serverTotal = GB.GetServerTotalDamage()
    if serverTotal < tier[1] then
        Toast.Show("全服累计伤害未达标", { 255, 200, 80 })
        return false
    end

    if data.claimedTiers[tierIndex] then
        Toast.Show("已领取", { 200, 200, 200 })
        return false
    end

    data.claimedTiers[tierIndex] = true

    -- 劳动加倍
    local laborMult = LaborDayData.ConsumeDouble()

    -- 发放奖励（劳动加倍对数量生效）
    local rewards = tier[2]
    if laborMult > 1 then
        local doubled = {}
        for i, r in ipairs(rewards) do
            doubled[i] = { type = r.type, id = r.id, amount = math.floor(r.amount * laborMult) }
        end
        Currency.GrantRewards(doubled, "GarbageBoss")
    else
        Currency.GrantRewards(rewards, "GarbageBoss")
    end

    -- 劳动奖章
    local okLM, LMD = pcall(require, "Game.LaborMedalData")
    if okLM then LMD.EarnMedals("garbage_boss") end

    HeroData.Save(true)
    Toast.Show("里程碑奖励已领取！", { 100, 255, 100 })
    return true
end

--- 是否有可领取的里程碑（红点判断，基于全服总伤害）
---@return boolean
function GB.HasClaimable()
    if not GB.IsActive() then return false end
    local data = GB.GetData()
    if not data.hasFought then return false end
    local serverTotal = GB.GetServerTotalDamage()
    for i, tier in ipairs(GB.CONFIG.rewardTiers) do
        if serverTotal >= tier[1] and not data.claimedTiers[i] then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 伤害格式化
-- ============================================================================

--- 格式化伤害数值
---@param damage number
---@return string
function GB.FormatDamage(damage)
    if not damage or damage ~= damage or damage == math.huge or damage == -math.huge then
        return "0"
    end
    if damage >= 1e20 then
        return string.format("%.1f垓", damage / 1e20)
    elseif damage >= 1e16 then
        return string.format("%.1f京", damage / 1e16)
    elseif damage >= 1e12 then
        return string.format("%.1f兆", damage / 1e12)
    elseif damage >= 1e8 then
        return string.format("%.1f亿", damage / 1e8)
    elseif damage >= 1e4 then
        return string.format("%.0f万", damage / 1e4)
    else
        return tostring(math.floor(damage))
    end
end

-- ============================================================================
-- 战斗结算
-- ============================================================================

--- 战斗结算（累加伤害，更新最高纪录）
---@param sessionDamage number 本场伤害
---@return table rewardDefs 本场触发的新里程碑奖励（仅展示用，不自动发放）
function GB.SettleBattle(sessionDamage)
    local data = GB.GetData()
    local prevTotal = data.totalDamage or 0

    -- 累计伤害
    data.totalDamage = prevTotal + sessionDamage

    -- 更新最高纪录
    if sessionDamage > (data.bestDamage or 0) then
        data.bestDamage = sessionDamage
    end

    -- 劳动加倍在 ClaimMilestone 中处理（领取里程碑奖励时消耗双倍机会）

    -- 劳动奖章
    local okLM, LMD = pcall(require, "Game.LaborMedalData")
    if okLM then LMD.EarnMedals("garbage_boss") end

    HeroData.Save(true)

    -- 上传个人累计伤害到排行榜
    LB.UploadGarbageBoss(data.totalDamage)

    -- 刷新全服总伤害缓存（强制失效，下次访问时重新拉取）
    _serverTotalCache.fetchTime = 0

    -- 返回本场新达成的里程碑（供UI展示，基于全服总伤害）
    -- 注意：此时全服数据尚未刷新，用旧缓存+本场伤害估算
    local estimatedServerTotal = _serverTotalCache.value + sessionDamage
    local newMilestones = {}
    for i, tier in ipairs(GB.CONFIG.rewardTiers) do
        local prevServerEst = estimatedServerTotal - sessionDamage
        if prevServerEst < tier[1] and estimatedServerTotal >= tier[1] then
            newMilestones[#newMilestones + 1] = {
                index     = i,
                threshold = tier[1],
                rewards   = tier[2],
            }
        end
    end

    print("[GarbageBoss] SettleBattle: session=" .. GB.FormatDamage(sessionDamage)
        .. " total=" .. GB.FormatDamage(data.totalDamage)
        .. " best=" .. GB.FormatDamage(data.bestDamage)
        .. " newMilestones=" .. #newMilestones)

    return newMilestones
end

-- ============================================================================
-- 战斗配置构建
-- ============================================================================

--- 构建垃圾Boss战斗配置（纯数据，无UI依赖）
---@return table config, table bossDef
function GB.BuildBattleConfig()
    local cfg = GB.CONFIG
    local bossDef = GB.CreateBossDef()

    local waves = {
        {
            {
                type = bossDef.id or "garbage_boss",
                typeDef = bossDef,
                delay = 0,
                isElite = false,
                affixes = {},
                prescaled = true,
            },
        },
    }

    local config = {
        mode = "world_boss",
        waves = waves,
        totalWaves = 1,
        stageNum = 1,
        label = "垃圾大扫除 · 垃圾山大王",
        waveInterval = 0,
        autoAdvanceWave = false,
        bossTimerEnabled = true,
        overloadEnabled = false,
        worldBossDuration = cfg.totalDuration,
        worldBossDarkSoulDrain = cfg.darkSoulDrain,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
    }

    return config, bossDef
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

SaveRegistry.Register("garbageBossData", {
    group = "meta_game",
    order = 251,
    serialize = function()
        return HeroData.garbageBossData
    end,
    deserialize = function(saved, _saveData)
        HeroData.garbageBossData = saved or nil
    end,
})

return GB
