-- Game/TranscendDungeon.lua
-- 超越副本（20波）— 支持多种资源副本的超越挑战
-- 核心设计：自平衡经济，产出与消耗随超越等级同步线性增长
--
-- 机制：
--   1. 20波挑战，每波等效关卡 = 玩家当前阶段 + 波次×增长步长
--   2. 每波掉落 = f(等效关卡)，与超越费用同阶线性增长
--   3. 玩家能打的波数大致固定 → 每次副本获得≈固定级数的升级资源
--   4. 不会膨胀：收入和消耗都与超越等级线性挂钩，比值恒定

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local State = require("Game.State")
local Toast = require("Game.Toast")
local SaveRegistry = require("Game.SaveRegistry")
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen = require("Game.WaveGenerator")
local LaborDayData = require("Game.LaborDayData")
local WorldTier = require("Game.WorldTier")
local EquipData = require("Game.EquipData")
local TodayStr = require("Game.DateUtil").TodayStr

local TD = {}

-- ============================================================================
-- 常量配置
-- ============================================================================

TD.CONFIG = {
    -- 波次
    enemiesPerWave   = 20,       -- 每波怪物数
    bossHPMult       = 5.0,      -- BOSS HP 倍率
    bossInterval     = 5,        -- 每5波出BOSS

    -- 等效关卡计算
    stageBase        = 200,      -- 起始关卡偏移（实际 = 玩家当前关 + 此值）
    stagePerWave     = 229,      -- 每波等效关卡增长（20波总偏移≈4550，与原30波一致）

    -- 解锁条件
    unlockStage      = 100,      -- 主线通关100关解锁
}

-- ============================================================================
-- 各副本超越定义
-- ============================================================================

---@class TranscendDef
---@field name string
---@field emoji string
---@field rewardCurrency string
---@field perWaveBase number       每波基础掉落
---@field perWaveScale number      每等效关卡的掉落系数
---@field accentColor number[]
---@field desc string

TD.TRANSCEND_DEFS = {
    iron = {
        name           = "锻魂熔炉·超越",
        emoji          = "🔥",
        rewardCurrency = "forge_iron",
        perWaveBase    = 20,
        perWaveScale   = 0.75,
        accentColor    = { 200, 120, 40 },
        desc           = "超越熔炉，锻造至上之力",
    },
    crystal = {
        name           = "冥晶矿洞·超越",
        emoji          = "💎",
        rewardCurrency = "nether_crystal",
        perWaveBase    = 10000,
        perWaveScale   = 1182,
        accentColor    = { 140, 80, 200 },
        desc           = "超越矿洞，掠夺无尽冥晶",
    },
    stone = {
        name           = "噬魂深渊·超越",
        emoji          = "🪨",
        rewardCurrency = "devour_stone",
        perWaveBase    = 30,
        perWaveScale   = 1.47,
        accentColor    = { 60, 180, 80 },
        desc           = "超越深渊，汲取噬魂之力",
    },
    chest = {
        name           = "宝箱秘境·超越",
        emoji          = "📦",
        rewardCurrency = "chest",
        perWaveBase    = 1,
        perWaveScale   = 0,
        accentColor    = { 220, 160, 40 },
        desc           = "超越秘境，开启终极宝箱",
    },
}

-- 支持超越的副本 key 列表
TD.TRANSCEND_KEYS = { "iron", "crystal", "stone", "chest" }

-- 兼容旧代码：保留 DUNGEON_DEF
TD.DUNGEON_DEF = {
    key         = "transcend_forge",
    name        = "锻魂熔炉·超越",
    emoji       = "🔥",
    desc        = "超越熔炉，锻造至上之力",
    accentColor = { 200, 120, 40, 255 },
}

-- ============================================================================
-- 宝箱超越每波奖励定义（20波分段）
-- ============================================================================

TD.TRANSCEND_CHEST_WAVE_REWARDS = {
    -- 超越宝箱20波奖励
    -- 炼狱20波全通(×3) ≈ 朽木48 青铜3 黄金9 铂金3 = 63
    -- 超越20波全通   ≈ 朽木27 青铜4 黄金8 铂金6 = 45 → 总数少但高品质更多
    -- 第1组 W1-W5：朽木为主
    [1]  = { id = "wood",     count = 4 },
    [2]  = { id = "wood",     count = 4 },
    [3]  = { id = "wood",     count = 4 },
    [4]  = { id = "wood",     count = 3 },
    [5]  = { id = "bronze",   count = 1 },
    -- 第2组 W6-W10：朽木+青铜过渡
    [6]  = { id = "wood",     count = 3 },
    [7]  = { id = "wood",     count = 3 },
    [8]  = { id = "bronze",   count = 1 },
    [9]  = { id = "bronze",   count = 1 },
    [10] = { id = "gold",     count = 1 },
    -- 第3组 W11-W15：黄金为主
    [11] = { id = "wood",     count = 3 },
    [12] = { id = "wood",     count = 3 },
    [13] = { id = "bronze",   count = 1 },
    [14] = { id = "gold",     count = 2 },
    [15] = { id = "platinum", count = 1 },
    -- 第4组 W16-W20：终极奖励
    [16] = { id = "wood",     count = 3 },
    [17] = { id = "gold",     count = 2 },
    [18] = { id = "gold",     count = 2 },
    [19] = { id = "platinum", count = 2 },
    [20] = { id = "platinum", count = 3 },
}

--- 获取宝箱超越某波的奖励定义
---@param wave number 1~20
---@return table|nil  { id = "wood", count = 1 }
function TD.GetTranscendChestWaveReward(wave)
    return TD.TRANSCEND_CHEST_WAVE_REWARDS[wave]
end

-- ============================================================================
-- 解锁
-- ============================================================================

function TD.IsUnlocked()
    return (State.currentStage or 1) >= TD.CONFIG.unlockStage
end

function TD.GetUnlockStage()
    return TD.CONFIG.unlockStage
end

-- ============================================================================
-- 进度管理（多副本）
-- ============================================================================

--- 初始化/获取超越副本存档数据
---@return table
function TD.GetData()
    if not HeroData.transcendDungeonData then
        HeroData.transcendDungeonData = {
            bestWave = {},
            totalRewardEarned = {},
            lastResetDate = TodayStr(),
        }
        for _, k in ipairs(TD.TRANSCEND_KEYS) do
            HeroData.transcendDungeonData.bestWave[k] = 0
            HeroData.transcendDungeonData.totalRewardEarned[k] = 0
        end
    end
    local data = HeroData.transcendDungeonData

    -- 兼容旧存档：bestWave 是 number 时迁移
    if type(data.bestWave) == "number" then
        local oldBest = data.bestWave
        data.bestWave = {}
        for _, k in ipairs(TD.TRANSCEND_KEYS) do
            data.bestWave[k] = 0
        end
        data.bestWave.iron = oldBest
    end

    -- 兼容：确保所有 key 存在
    if type(data.bestWave) ~= "table" then data.bestWave = {} end
    for _, k in ipairs(TD.TRANSCEND_KEYS) do
        if data.bestWave[k] == nil then data.bestWave[k] = 0 end
    end

    -- 兼容旧存档：totalIronEarned → totalRewardEarned
    if not data.totalRewardEarned then
        data.totalRewardEarned = {}
        data.totalRewardEarned.iron = data.totalIronEarned or 0
        for _, k in ipairs(TD.TRANSCEND_KEYS) do
            if data.totalRewardEarned[k] == nil then data.totalRewardEarned[k] = 0 end
        end
    end
    for _, k in ipairs(TD.TRANSCEND_KEYS) do
        if data.totalRewardEarned[k] == nil then data.totalRewardEarned[k] = 0 end
    end

    return data
end

-- ============================================================================
-- 次数管理 — 代理到 ResourceDungeonData（超越与普通副本共享次数）
-- ============================================================================

local RD -- lazy require
local function getRD()
    if not RD then RD = require("Game.ResourceDungeonData") end
    return RD
end

local InventoryData -- lazy require
local function getInventory()
    if not InventoryData then InventoryData = require("Game.InventoryData") end
    return InventoryData
end

--- 获取剩余免费次数（代理到 RD）
---@param dungeonKey? string 默认 "iron"
---@return number
function TD.GetFreeRemaining(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    return getRD().GetFreeRemaining(dungeonKey)
end

--- 获取剩余广告领券次数（代理到 RD）
---@param dungeonKey? string 默认 "iron"
---@return number
function TD.GetAdRemaining(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    return getRD().GetAdRemaining(dungeonKey)
end

--- 获取挑战券数量（代理到 RD）
---@param dungeonKey? string 默认 "iron"
---@return number
function TD.GetTicketCount(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local total = getRD().GetTotalTicketCount(dungeonKey)
    return total
end

--- 获取总可用次数
---@param dungeonKey? string 默认 "iron"
---@return number
function TD.GetTotalAvailable(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    return TD.GetFreeRemaining(dungeonKey) + TD.GetTicketCount(dungeonKey)
end

--- 消耗免费次数（代理到 RD）
---@param dungeonKey? string 默认 "iron"
---@return boolean
function TD.ConsumeEntry(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    return getRD().ConsumeAttempt(dungeonKey)
end

--- 消耗挑战券（代理到 RD）
---@param dungeonKey? string 默认 "iron"
---@return boolean
function TD.ConsumeTicket(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    return getRD().ConsumeDungeonTicket(dungeonKey)
end

--- 看广告领券（代理到 RD + 发券）
---@param dungeonKey? string 默认 "iron"
---@return boolean
function TD.ConsumeAdForTicket(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local rd = getRD()
    if not rd.ConsumeAdAttempt(dungeonKey) then return false end
    local ticketId = rd.DUNGEON_TICKET_MAP[dungeonKey]
    if ticketId then
        getInventory().Add(ticketId, 1)
        local ticketDef = getInventory().ITEM_DEFS and getInventory().ITEM_DEFS[ticketId]
        local ticketName = ticketDef and ticketDef.name or "挑战券"
        Toast.Show("获得 " .. ticketName .. " ×1", { 80, 220, 120 })
    end
    HeroData.Save()
    return true
end

--- 获取最佳波次
---@param dungeonKey? string 默认 "iron"
---@return number
function TD.GetBestWave(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local data = TD.GetData()
    return data.bestWave[dungeonKey] or 0
end

--- 获取记录最佳波次时的玩家关卡
---@param dungeonKey? string 默认 "iron"
---@return number 0 表示无记录
function TD.GetBestWaveStage(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local data = TD.GetData()
    if not data.bestWaveStage then return 0 end
    return data.bestWaveStage[dungeonKey] or 0
end

--- 超越难度随关卡增长，关卡提高过多时扫荡记录已过时，需重新挑战
TD.RECHALLENGE_STAGE_GAP = 1000

--- 是否需要重新挑战（当前关卡比记录时提高超过阈值）
---@param dungeonKey? string 默认 "iron"
---@return boolean needsRechallenge
---@return number stageGap 当前关卡与记录关卡的差距
function TD.NeedsRechallenge(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local bestWave = TD.GetBestWave(dungeonKey)
    if bestWave <= 0 then return false, 0 end  -- 没有记录，不存在"需要重新打"
    local recordedStage = TD.GetBestWaveStage(dungeonKey)
    if recordedStage <= 0 then return false, 0 end  -- 旧存档无记录，不限制
    local currentStage = State.currentStage or 1
    local gap = currentStage - recordedStage
    return gap > TD.RECHALLENGE_STAGE_GAP, gap
end

-- ============================================================================
-- 玩家超越等级（用于锚定起始难度）
-- ============================================================================

--- 获取当前主英雄的平均超越等级
---@return number
function TD.GetAvgTranscendLv()
    local heroes = HeroData.GetTeam and HeroData.GetTeam() or {}
    local total, count = 0, 0
    for _, heroId in ipairs(heroes) do
        local equips = EquipData.GetHeroEquips(heroId)
        if equips then
            for _, slot in ipairs(Config.EQUIP_SLOTS) do
                local e = equips[slot.id]
                if e then
                    total = total + (e.transcendLv or 0)
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return 0 end
    return math.floor(total / count)
end

-- ============================================================================
-- 等效关卡计算
-- ============================================================================

--- 计算某波次的等效关卡
---@param wave number 波次编号(1-based)
---@param snapshotStage? number 快照的玩家关卡
---@return number stageEquiv
function TD.WaveToStage(wave, snapshotStage)
    local playerStage = snapshotStage or State.currentStage or 1
    local cfg = TD.CONFIG
    return playerStage + cfg.stageBase + (wave - 1) * cfg.stagePerWave
end

-- ============================================================================
-- 掉落计算（自平衡核心）— 泛化多副本
-- ============================================================================

--- 计算单波奖励掉落（泛化版）
---@param wave number
---@param snapshotStage? number
---@param dungeonKey? string 默认 "iron"
---@return number amount
function TD.CalcWaveReward(wave, snapshotStage, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local tdef = TD.TRANSCEND_DEFS[dungeonKey]
    if not tdef then return 0 end

    -- 宝箱副本特殊处理：返回宝箱数量
    if tdef.rewardCurrency == "chest" then
        local cr = TD.TRANSCEND_CHEST_WAVE_REWARDS[wave]
        local wtMult = WorldTier.GetRewardMult()
        return cr and math.floor(cr.count * wtMult) or 0
    end

    local stageEquiv = TD.WaveToStage(wave, snapshotStage)
    local base = tdef.perWaveBase + tdef.perWaveScale * stageEquiv
    local wtMult = WorldTier.GetRewardMult()
    return math.floor(base * wtMult)
end

--- 预估打到某波能获得的总奖励
---@param maxWave number
---@param snapshotStage? number
---@param dungeonKey? string 默认 "iron"
---@return number
function TD.EstimateTotalReward(maxWave, snapshotStage, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local total = 0
    for w = 1, maxWave do
        total = total + TD.CalcWaveReward(w, snapshotStage, dungeonKey)
    end
    return total
end

--- 计算宝箱超越总奖励（按宝箱类型汇总）
---@param maxWave number
---@return table chests {id=count}
function TD.EstimateTotalChestReward(maxWave)
    local chests = {}
    local wtMult = WorldTier.GetRewardMult()
    for w = 1, maxWave do
        local cr = TD.TRANSCEND_CHEST_WAVE_REWARDS[w]
        if cr then
            chests[cr.id] = (chests[cr.id] or 0) + math.floor(cr.count * wtMult)
        end
    end
    return chests
end

-- 兼容旧调用
TD.CalcWaveIron = function(wave, snapshotStage)
    return TD.CalcWaveReward(wave, snapshotStage, "iron")
end
TD.EstimateTotalIron = function(maxWave, snapshotStage)
    return TD.EstimateTotalReward(maxWave, snapshotStage, "iron")
end

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

function TD.GetWaveType(wave)
    if wave % TD.CONFIG.bossInterval == 0 then
        return "boss"
    elseif wave % TD.CONFIG.bossInterval == (TD.CONFIG.bossInterval - 1) then
        return "elite"
    else
        return "normal"
    end
end

function TD.GetWaveLabel(wave)
    local wtype = TD.GetWaveType(wave)
    if wtype == "boss" then
        return "BOSS", { 255, 60, 60 }
    elseif wtype == "elite" then
        return "精英", { 255, 180, 40 }
    else
        return "普通", { 160, 160, 160 }
    end
end

function TD.GenerateWaveEnemies(wave, snapshotStage)
    local stageEquiv = TD.WaveToStage(wave, snapshotStage)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = DungeonScaling.CalcHPScale(stageEquiv)
    local spdScale = DungeonScaling.CalcSpeedScale(stageEquiv)
    local waveType = TD.GetWaveType(wave)

    local cfg = TD.CONFIG
    local tags = { isTranscendForge = true }
    local normalCount = (waveType == "boss") and (cfg.enemiesPerWave - 1) or cfg.enemiesPerWave

    local enemies = WaveGen.GenerateBatch(stageNum, normalCount, hpScale, spdScale, tags)

    if waveType == "boss" then
        local bossDef = WaveGen.CreateBoss(stageNum, hpScale, spdScale, cfg.bossHPMult, 0.6, tags)
        if bossDef then
            enemies[#enemies + 1] = bossDef
        end
    elseif waveType == "elite" then
        WaveGen.MarkElitesTail(enemies, 3, 2.5, 0.8)
    end

    return enemies
end

-- ============================================================================
-- 会话管理（多副本）
-- ============================================================================

--- 创建超越会话
---@param dungeonKey? string 默认 "iron"
---@return table|nil session
function TD.CreateSession(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    if not TD.IsUnlocked() then
        Toast.Show("主线通关" .. TD.CONFIG.unlockStage .. "关解锁", { 255, 200, 80 })
        return nil
    end

    local tdef = TD.TRANSCEND_DEFS[dungeonKey]
    if not tdef then return nil end

    -- 快照玩家当前关卡
    local snapStage = State.currentStage or 1
    print(string.format("[Transcend:%s] CreateSession playerStage=%d", dungeonKey, snapStage))

    return {
        dungeonKey  = dungeonKey,
        currentWave = 0,
        totalReward = 0,
        waveRewards = {},
        cleared     = false,
        playerStage = snapStage,
    }
end

function TD.AdvanceWave(session)
    session.currentWave = session.currentWave + 1
    return TD.GenerateWaveEnemies(session.currentWave, session.playerStage)
end

--- 完成一波，累计奖励
---@param session table
---@return number reward
function TD.CompleteWave(session)
    local dk = session.dungeonKey or "iron"
    local reward = TD.CalcWaveReward(session.currentWave, session.playerStage, dk)
    session.waveRewards[session.currentWave] = reward
    session.totalReward = session.totalReward + reward
    return reward
end

-- ============================================================================
-- 结算（多副本）
-- ============================================================================

--- 结束超越会话，发放奖励
---@param session table
---@return table result
function TD.EndSession(session)
    local dk = session.dungeonKey or "iron"
    local tdef = TD.TRANSCEND_DEFS[dk]
    local data = TD.GetData()

    -- 更新最佳波次 & 记录挑战时的关卡数
    if session.currentWave > (data.bestWave[dk] or 0) then
        data.bestWave[dk] = session.currentWave
    end
    -- 始终更新挑战时关卡快照（用于扫荡门槛判断）
    if not data.bestWaveStage then data.bestWaveStage = {} end
    data.bestWaveStage[dk] = session.playerStage

    local totalReward = session.totalReward

    -- 劳动加倍
    local laborMult = LaborDayData.ConsumeDouble()
    totalReward = math.floor(totalReward * laborMult)

    -- 构建 rewardDefs
    local rewardDefs = {}

    if tdef and tdef.rewardCurrency == "chest" then
        -- 宝箱副本：按类型发放宝箱
        local chests = {}
        local wtMult = WorldTier.GetRewardMult()
        for w = 1, session.currentWave do
            local cr = TD.TRANSCEND_CHEST_WAVE_REWARDS[w]
            if cr then
                chests[cr.id] = (chests[cr.id] or 0) + math.floor(cr.count * wtMult * laborMult)
            end
        end
        for chestId, count in pairs(chests) do
            if count > 0 then
                Currency.GrantReward({ type = "chest", id = chestId, amount = count }, "Transcend:" .. dk)
                rewardDefs[#rewardDefs + 1] = { type = "chest", id = chestId, amount = count }
            end
        end
    else
        -- 货币副本：发放对应货币
        local currId = tdef and tdef.rewardCurrency or "forge_iron"
        if totalReward > 0 then
            Currency.GrantReward({ type = "currency", id = currId, amount = totalReward }, "Transcend:" .. dk)
            rewardDefs[#rewardDefs + 1] = { type = "currency", id = currId, amount = totalReward }
        end
    end

    -- 累计统计
    data.totalRewardEarned[dk] = (data.totalRewardEarned[dk] or 0) + totalReward

    -- 劳动奖章
    local okLM, LMD = pcall(require, "Game.LaborMedalData")
    if okLM then LMD.EarnMedals("transcend_forge") end

    HeroData.Save(true)

    local result = {
        totalReward = totalReward,
        clearedWave = session.currentWave,
        rewardDefs  = rewardDefs,
        dungeonKey  = dk,
    }

    print(string.format("[Transcend:%s] EndSession wave=%d reward=%d bestWave=%d",
        dk, session.currentWave, totalReward, data.bestWave[dk] or 0))

    return result
end

-- ============================================================================
-- 战斗配置构建（多副本）
-- ============================================================================

--- 构建超越战斗配置
---@param dungeonKey? string 默认 "iron"
---@return table|nil config, table|nil session
function TD.BuildBattleConfig(dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local BM = require("Game.BattleManager")
    local tdef = TD.TRANSCEND_DEFS[dungeonKey]
    if not tdef then return nil, nil end

    local session = TD.CreateSession(dungeonKey)
    if not session then return nil, nil end

    local snapStage = session.playerStage
    local TOTAL = 20
    local waves = {}
    for w = 1, TOTAL do
        local enemyDefs = TD.GenerateWaveEnemies(w, snapStage)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    local config = {
        mode = "transcend_" .. dungeonKey,
        waves = waves,
        totalWaves = TOTAL,
        label = tdef.name,
        waveInterval = 15,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit = 20,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
        stageNum = snapStage,
    }

    print(string.format("[Transcend:%s] BuildBattleConfig snapStage=%d wave1Stage=%d wave20Stage=%d",
        dungeonKey, snapStage, TD.WaveToStage(1, snapStage), TD.WaveToStage(20, snapStage)))

    return config, session
end

-- ============================================================================
-- SaveRegistry
-- ============================================================================

SaveRegistry.Register("transcendDungeonData", {
    group = "meta_game",
    order = 75,
    serialize = function()
        return HeroData.transcendDungeonData
    end,
    deserialize = function(saved, _saveData)
        if saved then
            -- 兼容旧存档：bestWave 是 number
            if type(saved.bestWave) == "number" then
                local oldBest = saved.bestWave
                saved.bestWave = {}
                for _, k in ipairs(TD.TRANSCEND_KEYS) do
                    saved.bestWave[k] = 0
                end
                saved.bestWave.iron = oldBest
            end
            -- 兼容旧存档：todayAttempts 是 number（旧版字段，已废弃，次数现在走 RD）
            -- 兼容旧存档：totalIronEarned → totalRewardEarned
            if not saved.totalRewardEarned then
                saved.totalRewardEarned = {}
                saved.totalRewardEarned.iron = saved.totalIronEarned or 0
            end
            HeroData.transcendDungeonData = saved
        else
            HeroData.transcendDungeonData = nil
        end
    end,
})

return TD
