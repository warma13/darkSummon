-- Game/MineDungeonData.lua
-- 矿洞寻宝：劳动节限时副本数据模块
-- 10 层矿洞探索，每层随机遭遇"矿脉"(安全资源)或"怪物"(战斗)
-- 第 5/10 层固定 Boss；战斗失败仅获得 50% 已累积奖励
-- 每日 3 次入场机会，与劳动奖章活动共享活动期

local Config         = require("Game.Config")
local Currency       = require("Game.Currency")
local HeroData       = require("Game.HeroData")
local SaveRegistry   = require("Game.SaveRegistry")
local Toast          = require("Game.Toast")
local DateUtil       = require("Game.DateUtil")
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen        = require("Game.WaveGenerator")
local State          = require("Game.State")

local MDD = {}

-- ============================================================================
-- 常量
-- ============================================================================

local MAX_FLOORS      = 10        -- 最大层数
local BOSS_FLOORS     = { [5] = true, [10] = true }
local DAILY_ENTRIES   = 3         -- 每日进入次数
local ENEMIES_PER_WAVE = 20       -- 每层战斗怪物数
local BOSS_HP_MULT    = 5.0       -- Boss HP 倍率
local BOSS_SPEED_FACTOR = 0.65    -- Boss 速度因子
local FAIL_REWARD_RATIO = 0.5     -- 战斗失败只给 50% 累积奖励
local ORE_CHANCE_BASE = 0.55      -- 基础矿脉概率（非Boss层）

-- 活动时间（与劳动奖章共享）
local START_DATE, END_DATE
do
    local ok, LDD = pcall(require, "Game.LaborDayData")
    if ok then
        START_DATE = LDD.START_DATE  -- "2026-05-01"
        END_DATE   = LDD.END_DATE    -- "2026-05-07"
    else
        START_DATE = "2026-05-01"
        END_DATE   = "2026-05-07"
    end
end

MDD.START_DATE   = START_DATE
MDD.END_DATE     = END_DATE
MDD.MAX_FLOORS   = MAX_FLOORS
MDD.DAILY_ENTRIES = DAILY_ENTRIES

-- ============================================================================
-- 层级配置（难度随深度递增）
-- ============================================================================

---@class FloorTier
---@field floors number[]  该档覆盖的层号
---@field oreChance number 遇到矿脉的概率（非Boss层）
---@field stageBase number 等效基础关卡
---@field stageStep number 每层增加的等效关卡
---@field enemyCount number 每层怪物数

local FLOOR_TIERS = {
    { floors = {1, 2, 3},   oreChance = 0.60, stageBase = 300,  stageStep = 80,  enemyCount = 15 },
    { floors = {4, 5},      oreChance = 0.45, stageBase = 600,  stageStep = 100, enemyCount = 18 },
    { floors = {6, 7, 8},   oreChance = 0.40, stageBase = 1000, stageStep = 150, enemyCount = 22 },
    { floors = {9, 10},     oreChance = 0.30, stageBase = 1800, stageStep = 200, enemyCount = 25 },
}

--- 层号 → tier 映射（预计算）
local floorTierMap = {}
for _, tier in ipairs(FLOOR_TIERS) do
    for _, f in ipairs(tier.floors) do
        floorTierMap[f] = tier
    end
end

--- 获取层级的等效关卡
---@param floor number 层号 1-10
---@return number stageEquiv
local function FloorToStage(floor)
    local tier = floorTierMap[floor] or FLOOR_TIERS[1]
    local offset = floor - tier.floors[1]
    return tier.stageBase + tier.stageStep * offset
end

-- ============================================================================
-- 奖励表
-- ============================================================================

--- 矿脉奖励（按层深递增）
local ORE_REWARDS = {
    -- floor 1-3: 基础矿石
    { floors = {1, 2, 3}, rewards = {
        { type = "currency", id = "nether_crystal", min = 800,  max = 1500 },
        { type = "currency", id = "forge_iron",     min = 300,  max = 600 },
        { type = "currency", id = "labor_medal",    min = 3,    max = 5 },
    }},
    -- floor 4-5: 中级矿石
    { floors = {4, 5}, rewards = {
        { type = "currency", id = "nether_crystal", min = 1500, max = 3000 },
        { type = "currency", id = "forge_iron",     min = 500,  max = 1000 },
        { type = "currency", id = "devour_stone",   min = 200,  max = 500 },
        { type = "currency", id = "labor_medal",    min = 5,    max = 8 },
    }},
    -- floor 6-8: 高级矿石
    { floors = {6, 7, 8}, rewards = {
        { type = "currency", id = "nether_crystal", min = 3000, max = 5000 },
        { type = "currency", id = "forge_iron",     min = 800,  max = 1500 },
        { type = "currency", id = "shadow_essence", min = 100,  max = 300 },
        { type = "currency", id = "labor_medal",    min = 8,    max = 12 },
    }},
    -- floor 9-10: 珍稀矿石
    { floors = {9, 10}, rewards = {
        { type = "currency", id = "nether_crystal", min = 5000, max = 8000 },
        { type = "currency", id = "forge_iron",     min = 1200, max = 2000 },
        { type = "currency", id = "shadow_essence", min = 200,  max = 500 },
        { type = "currency", id = "void_pact",      min = 50,   max = 100 },
        { type = "currency", id = "labor_medal",    min = 12,   max = 18 },
    }},
}

--- 层号 → 矿脉奖励映射
local oreRewardMap = {}
for _, group in ipairs(ORE_REWARDS) do
    for _, f in ipairs(group.floors) do
        oreRewardMap[f] = group.rewards
    end
end

--- 怪物击败奖励（按层深递增，比矿脉略多）
local MONSTER_REWARDS = {
    { floors = {1, 2, 3}, rewards = {
        { type = "currency", id = "nether_crystal", min = 1200, max = 2200 },
        { type = "currency", id = "forge_iron",     min = 500,  max = 900 },
        { type = "currency", id = "labor_medal",    min = 5,    max = 8 },
    }},
    { floors = {4, 5}, rewards = {
        { type = "currency", id = "nether_crystal", min = 2500, max = 4500 },
        { type = "currency", id = "forge_iron",     min = 800,  max = 1500 },
        { type = "currency", id = "devour_stone",   min = 400,  max = 800 },
        { type = "currency", id = "labor_medal",    min = 8,    max = 12 },
    }},
    { floors = {6, 7, 8}, rewards = {
        { type = "currency", id = "nether_crystal", min = 4500, max = 7000 },
        { type = "currency", id = "forge_iron",     min = 1200, max = 2000 },
        { type = "currency", id = "shadow_essence", min = 200,  max = 500 },
        { type = "currency", id = "labor_medal",    min = 12,   max = 16 },
    }},
    { floors = {9, 10}, rewards = {
        { type = "currency", id = "nether_crystal", min = 7000, max = 12000 },
        { type = "currency", id = "forge_iron",     min = 1800, max = 3000 },
        { type = "currency", id = "shadow_essence", min = 400,  max = 800 },
        { type = "currency", id = "void_pact",      min = 80,   max = 150 },
        { type = "currency", id = "labor_medal",    min = 18,   max = 25 },
    }},
}

local monsterRewardMap = {}
for _, group in ipairs(MONSTER_REWARDS) do
    for _, f in ipairs(group.floors) do
        monsterRewardMap[f] = group.rewards
    end
end

--- Boss 击败额外奖励（叠加在怪物奖励之上）
local BOSS_BONUS = {
    [5]  = {
        { type = "currency", id = "void_pact",      min = 100, max = 200 },
        { type = "currency", id = "shadow_essence",  min = 300, max = 500 },
        { type = "currency", id = "labor_medal",     min = 15,  max = 20 },
    },
    [10] = {
        { type = "currency", id = "void_pact",      min = 200, max = 400 },
        { type = "currency", id = "shadow_essence",  min = 500, max = 800 },
        { type = "currency", id = "pale_jade",       min = 50,  max = 100 },
        { type = "currency", id = "labor_medal",     min = 25,  max = 35 },
    },
}

-- ============================================================================
-- 活动状态
-- ============================================================================

--- 活动是否正在进行
---@return boolean
function MDD.IsActive()
    local today = DateUtil.TodayStr()
    return today >= START_DATE and today <= END_DATE
end

--- 活动是否已结束
---@return boolean
function MDD.IsExpired()
    return DateUtil.TodayStr() > END_DATE
end

-- ============================================================================
-- 次数管理
-- ============================================================================

--- 确保数据字段存在
local function EnsureData()
    if not HeroData.mineDungeonData then
        HeroData.mineDungeonData = {
            lastDate       = "",
            usedToday      = 0,
            bestFloor      = 0,
            totalRuns      = 0,
        }
    end
    -- 日重置
    local today = DateUtil.TodayStr()
    if HeroData.mineDungeonData.lastDate ~= today then
        HeroData.mineDungeonData.lastDate  = today
        HeroData.mineDungeonData.usedToday = 0
    end
end

--- 获取今日剩余次数
---@return number
function MDD.GetRemaining()
    EnsureData()
    return math.max(0, DAILY_ENTRIES - HeroData.mineDungeonData.usedToday)
end

--- 消耗一次进入机会
---@return boolean ok
---@return string msg
function MDD.ConsumeEntry()
    if not MDD.IsActive() then
        return false, "活动未开放"
    end
    EnsureData()
    if HeroData.mineDungeonData.usedToday >= DAILY_ENTRIES then
        return false, "今日次数已用完"
    end
    HeroData.mineDungeonData.usedToday = HeroData.mineDungeonData.usedToday + 1
    HeroData.mineDungeonData.totalRuns = (HeroData.mineDungeonData.totalRuns or 0) + 1
    return true, ""
end

--- 获取历史最高层
---@return number
function MDD.GetBestFloor()
    EnsureData()
    return HeroData.mineDungeonData.bestFloor or 0
end

--- 获取总探索次数
---@return number
function MDD.GetTotalRuns()
    EnsureData()
    return HeroData.mineDungeonData.totalRuns or 0
end

-- ============================================================================
-- 层遭遇生成
-- ============================================================================

--- 判断层是否为 Boss 层
---@param floor number
---@return boolean
function MDD.IsBossFloor(floor)
    return BOSS_FLOORS[floor] == true
end

--- 随机 roll 奖励列表
---@param rewardDefs table[] 奖励模板
---@return table[] rolledRewards { type, id, amount }
local function RollRewards(rewardDefs)
    local result = {}
    for _, def in ipairs(rewardDefs) do
        local amount = math.random(def.min, def.max)
        result[#result + 1] = {
            type   = def.type,
            id     = def.id,
            amount = amount,
        }
    end
    return result
end

--- 生成指定层的遭遇
---@param floor number 层号 1-10
---@return table encounter { floor, encounterType, rewards, enemyDefs? }
function MDD.GenerateFloor(floor)
    local isBoss = MDD.IsBossFloor(floor)

    -- Boss 层固定为战斗
    if isBoss then
        local monsterDefs = monsterRewardMap[floor] or {}
        local bossBonusDefs = BOSS_BONUS[floor] or {}
        local rewards = RollRewards(monsterDefs)
        local bonusRewards = RollRewards(bossBonusDefs)
        for _, r in ipairs(bonusRewards) do
            rewards[#rewards + 1] = r
        end
        return {
            floor         = floor,
            encounterType = "boss",
            rewards       = rewards,
        }
    end

    -- 非Boss层：随机矿脉或怪物
    local tier = floorTierMap[floor] or FLOOR_TIERS[1]
    local isOre = math.random() < tier.oreChance

    if isOre then
        local oreDefs = oreRewardMap[floor] or {}
        return {
            floor         = floor,
            encounterType = "ore",
            rewards       = RollRewards(oreDefs),
        }
    else
        local monsterDefs = monsterRewardMap[floor] or {}
        return {
            floor         = floor,
            encounterType = "monster",
            rewards       = RollRewards(monsterDefs),
        }
    end
end

-- ============================================================================
-- 战斗配置构建（monster/boss 层用）
-- ============================================================================

--- 生成指定层的敌人定义列表
---@param floor number
---@param isBoss boolean
---@return table[] enemyDefs
function MDD.GenerateEnemyDefs(floor, isBoss)
    local stageEquiv = FloorToStage(floor)
    local stageNum   = math.max(1, math.floor(stageEquiv))
    local hpScale    = DungeonScaling.CalcHPScale(stageEquiv)
    local spdScale   = DungeonScaling.CalcSpeedScale(stageEquiv)
    local tier       = floorTierMap[floor] or FLOOR_TIERS[1]
    local tags       = { isMineDungeon = true }

    local count = isBoss and (tier.enemyCount - 1) or tier.enemyCount
    local enemies = WaveGen.GenerateBatch(stageNum, count, hpScale, spdScale, tags)

    if isBoss then
        local bossDef = WaveGen.CreateBoss(stageNum, hpScale, spdScale, BOSS_HP_MULT, BOSS_SPEED_FACTOR, tags)
        if bossDef then
            enemies[#enemies + 1] = bossDef
        end
    end

    return enemies
end

--- 构建 BattleManager 所需的战斗配置（纯数据，不含回调）
---@param floor number
---@param encounter table GenerateFloor 返回的遭遇数据
---@return table config BattleManager.Start 所需的配置
function MDD.BuildBattleConfig(floor, encounter)
    local BM = require("Game.BattleManager")
    local isBoss = encounter.encounterType == "boss"
    local enemyDefs = MDD.GenerateEnemyDefs(floor, isBoss)
    local spawnQueue = BM.BuildSpawnQueue(enemyDefs, 0.6)

    local label = isBoss
        and string.format("矿洞寻宝 · 第%d层 BOSS", floor)
        or  string.format("矿洞寻宝 · 第%d层", floor)

    return {
        mode            = "mine_dungeon",
        waves           = { spawnQueue },
        totalWaves      = 1,
        label           = label,
        waveInterval    = 0,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit   = 50,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
    }
end

-- ============================================================================
-- 会话管理（一次完整的矿洞探索）
-- ============================================================================

---@class MineDungeonSession
---@field currentFloor number      当前所在层
---@field maxFloor number          最大层数
---@field encounters table[]       每层遭遇数据
---@field accumulatedRewards table  累计奖励 { [currencyId] = amount }
---@field rewardDefs table[]       结算用奖励列表
---@field completed boolean        是否完成（主动退出或全部通关）
---@field failed boolean           最近一次战斗是否失败

--- 当前活跃会话
---@type MineDungeonSession|nil
local activeSession = nil

--- 创建新会话
---@return MineDungeonSession|nil session
---@return string msg
function MDD.CreateSession()
    if not MDD.IsActive() then
        return nil, "活动未开放"
    end

    local ok, msg = MDD.ConsumeEntry()
    if not ok then
        return nil, msg
    end

    activeSession = {
        currentFloor       = 0,
        maxFloor           = MAX_FLOORS,
        encounters         = {},
        accumulatedRewards = {},
        rewardDefs         = {},
        completed          = false,
        failed             = false,
    }

    print("[MineDungeon] CreateSession, remaining=" .. MDD.GetRemaining())
    return activeSession, ""
end

--- 获取当前会话
---@return MineDungeonSession|nil
function MDD.GetSession()
    return activeSession
end

--- 推进到下一层并生成遭遇
---@return table|nil encounter
function MDD.AdvanceFloor()
    if not activeSession then return nil end
    if activeSession.currentFloor >= MAX_FLOORS then
        activeSession.completed = true
        return nil
    end

    activeSession.currentFloor = activeSession.currentFloor + 1
    local floor = activeSession.currentFloor
    local encounter = MDD.GenerateFloor(floor)
    activeSession.encounters[floor] = encounter
    activeSession.failed = false

    print(string.format("[MineDungeon] AdvanceFloor → %d, type=%s", floor, encounter.encounterType))
    return encounter
end

--- 将遭遇奖励加入累积（矿脉直接领取 / 战斗胜利后调用）
---@param encounter table
function MDD.CollectRewards(encounter)
    if not activeSession or not encounter or not encounter.rewards then return end

    for _, r in ipairs(encounter.rewards) do
        if r.type == "currency" and r.id and r.amount then
            local key = r.id
            activeSession.accumulatedRewards[key] = (activeSession.accumulatedRewards[key] or 0) + r.amount
        end
    end

    print(string.format("[MineDungeon] CollectRewards floor=%d", encounter.floor or 0))
end

--- 标记战斗失败
function MDD.MarkBattleFailed()
    if activeSession then
        activeSession.failed = true
    end
end

--- 结束会话，发放奖励
---@param reason string "clear" | "exit" | "fail"
---@return table result { rewardDefs, ratio, bestFloor }
function MDD.EndSession(reason)
    if not activeSession then
        return { rewardDefs = {}, ratio = 0, bestFloor = 0 }
    end

    local ratio = 1.0
    if reason == "fail" then
        ratio = FAIL_REWARD_RATIO
    end

    -- 构建最终奖励列表
    local rewardDefs = {}
    for currencyId, totalAmount in pairs(activeSession.accumulatedRewards) do
        local finalAmount = math.floor(totalAmount * ratio)
        if finalAmount > 0 then
            rewardDefs[#rewardDefs + 1] = {
                type   = "currency",
                id     = currencyId,
                amount = finalAmount,
            }
        end
    end

    -- 发放奖励
    Currency.GrantRewards(rewardDefs, "MineDungeon")

    -- 更新最佳层数
    EnsureData()
    local reachedFloor = activeSession.currentFloor
    if reachedFloor > (HeroData.mineDungeonData.bestFloor or 0) then
        HeroData.mineDungeonData.bestFloor = reachedFloor
    end

    -- 劳动奖章额外产出
    local okLM, LMD = pcall(require, "Game.LaborMedalData")
    if okLM and LMD.EarnMedals then
        LMD.EarnMedals("mine_dungeon")
    end

    -- 保存
    HeroData.Save(true)

    local result = {
        rewardDefs   = rewardDefs,
        ratio        = ratio,
        bestFloor    = MDD.GetBestFloor(),
        reachedFloor = reachedFloor,
        reason       = reason,
    }

    print(string.format("[MineDungeon] EndSession reason=%s floor=%d ratio=%.1f rewards=%d",
        reason, reachedFloor, ratio, #rewardDefs))

    activeSession = nil
    return result
end

--- 获取矿洞层的展示信息
---@param floor number
---@return string label, number[] color
function MDD.GetFloorLabel(floor)
    if MDD.IsBossFloor(floor) then
        return string.format("第%d层 (BOSS)", floor), { 255, 60, 60, 255 }
    elseif floor >= 9 then
        return string.format("第%d层 (深层)", floor), { 255, 160, 40, 255 }
    elseif floor >= 6 then
        return string.format("第%d层 (中层)", floor), { 200, 180, 60, 255 }
    else
        return string.format("第%d层 (浅层)", floor), { 120, 200, 120, 255 }
    end
end

--- 获取遭遇类型展示
---@param encounterType string "ore" | "monster" | "boss"
---@return string emoji, string label, number[] color
function MDD.GetEncounterDisplay(encounterType)
    if encounterType == "ore" then
        return "💎", "矿脉", { 80, 200, 255, 255 }
    elseif encounterType == "boss" then
        return "💀", "Boss", { 255, 60, 60, 255 }
    else
        return "⚔️", "怪物", { 255, 180, 40, 255 }
    end
end

-- ============================================================================
-- 持久化（SaveRegistry 自注册）
-- ============================================================================

SaveRegistry.Register("mineDungeonData", {
    group = "meta_game",
    order = 250,

    initDefault = function()
        HeroData.mineDungeonData = {
            lastDate  = "",
            usedToday = 0,
            bestFloor = 0,
            totalRuns = 0,
        }
    end,

    serialize = function()
        return HeroData.mineDungeonData
    end,

    deserialize = function(saved)
        if saved then
            HeroData.mineDungeonData = saved
        else
            HeroData.mineDungeonData = {
                lastDate  = "",
                usedToday = 0,
                bestFloor = 0,
                totalRuns = 0,
            }
        end
    end,

    validate = function()
        EnsureData()
    end,
})

-- ============================================================================
-- 副本定义（供 UI 使用）
-- ============================================================================

MDD.DUNGEON_DEF = {
    key         = "mine_dungeon",
    name        = "矿洞寻宝",
    emoji       = "⛏️",
    desc        = "深入矿洞探索，挖掘珍稀矿石与战利品",
    accentColor = { 200, 160, 60, 255 },
}

-- 导出常量
MDD.FAIL_REWARD_RATIO = FAIL_REWARD_RATIO
MDD.BOSS_FLOORS_SET   = BOSS_FLOORS

return MDD
