-- Game/BattleManager.lua
-- 统一战斗生命周期管理
-- 所有副本（主线、试练塔、资源副本）通过此模块启动和管理战斗

local Config = require("Game.Config")
local State = require("Game.State")
local Tower = require("Game.Tower")
local Wave = require("Game.Wave")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local Combat = require("Game.Combat")
local Enemy = require("Game.Enemy")
local LootDrop = require("Game.LootDrop")

local BattleManager = {}

-- ============================================================================
-- 战斗上下文（当前正在进行的战斗配置）
-- ============================================================================

---@class BattleConfig
---@field mode string            战斗模式: "campaign" | "trial_tower" | "resource_dungeon"
---@field waves table[]          波次列表，每个元素是一个 spawn queue
---@field totalWaves number      总波数
---@field onWin function|nil     胜利回调 function(result)
---@field onLose function|nil    失败回调 function(result)
---@field onExit function|nil    玩家主动退出回调 function(result)
---@field label string           显示标签（如 "第3关" "试练塔 第5层"）
---@field autoAdvanceWave boolean 是否自动推进波次（清完一波自动下一波）
---@field waveInterval number    波次间隔（秒），0 表示清完立即下一波
---@field bossTimerEnabled boolean 是否启用 BOSS 倒计时
---@field overloadEnabled boolean  是否启用超限判定
---@field overloadLimit number|nil 超限敌人上限（nil 则使用 Config.MAX_ENEMIES）
---@field initialDarkSoul number|nil 开局初始暗魂（nil 则使用 Config.INITIAL_DARK_SOUL）

---@type BattleConfig|nil
BattleManager.config = nil

--- 是否有战斗正在进行
---@return boolean
function BattleManager.IsActive()
    return BattleManager.config ~= nil
end

--- 获取当前战斗模式
---@return string|nil
function BattleManager.GetMode()
    return BattleManager.config and BattleManager.config.mode or nil
end

--- 获取当前战斗标签（供 HUD 显示）
---@return string
function BattleManager.GetLabel()
    if not BattleManager.config then return "" end
    local c = BattleManager.config
    local typeTag = ""
    if State.waveType == "boss" then typeTag = " BOSS"
    elseif State.waveType == "elite" then typeTag = " 精英"
    end
    return c.label .. " " .. State.currentWave .. "/" .. c.totalWaves .. typeTag
end

-- ============================================================================
-- 波次敌人队列构建工具
-- ============================================================================

--- 从敌人定义列表构建 spawn queue（副本用）
--- 每个敌人间隔 interval 秒出现
---@param enemyDefs table[]  敌人定义列表（来自 TrialTowerData/ResourceDungeonData）
---@param interval number    出怪间隔（秒）
---@return table queue       spawn queue（与 Wave.lua 格式兼容）
function BattleManager.BuildSpawnQueue(enemyDefs, interval)
    local queue = {}
    interval = interval or 0.8

    for _, def in ipairs(enemyDefs) do
        local isBoss = def.isBoss or def.isDungeonBoss
        queue[#queue + 1] = {
            type = def.id or def.typeId or "unknown",
            typeDef = def,
            delay = isBoss and 1.5 or (def.isElite and 1.2 or interval),
            isElite = def.isElite or false,
            affixes = def.bossAffixes or def.eliteAffixes or {},
            -- 标记：这是预缩放的敌人定义（HP/DEF/Speed 已由副本模块计算好）
            prescaled = true,
        }
        -- BOSS 前插入暂停
        if isBoss and #queue > 1 then
            table.insert(queue, #queue, {
                type = "__pause",
                delay = 1.5,
            })
        end
    end

    return queue
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 统一战斗入口 —— 主线关卡专用（副本继续使用 EnterDungeonBattle → BattleManager.Start）
--- 会预构建关卡所有波次队列，然后调用 BattleManager.Start。
---@param mode string      目前仅支持 "campaign"
---@param params table     { stageNum, onWin, onLose, onExit }
function BattleManager.Enter(mode, params)
    assert(mode == "campaign", "[BattleManager] Enter: 目前仅支持 mode='campaign'，实际: " .. tostring(mode))
    params = params or {}

    local stageNum = params.stageNum or 1
    local waves    = Wave.BuildStageWaves(stageNum)

    BattleManager.Start({
        mode       = "campaign",
        waves      = waves,
        totalWaves = Config.WAVES_PER_STAGE,
        stageNum   = stageNum,
        label      = "第" .. stageNum .. "关",
        onWin      = params.onWin,
        onLose     = params.onLose,
        onExit     = params.onExit,
    })
end

--- 启动一场战斗
---@param config BattleConfig
function BattleManager.Start(config)
    assert(config.waves and #config.waves > 0, "[BattleManager] waves is required")
    assert(config.totalWaves and config.totalWaves > 0, "[BattleManager] totalWaves is required")
    assert(config.mode, "[BattleManager] mode is required")

    -- 先结算残留掉落物
    LootDrop.CollectAll()

    -- 重置状态
    State.Reset()
    Combat.Reset()

    -- 保存配置
    BattleManager.config = {
        mode             = config.mode,
        waves            = config.waves,
        totalWaves       = config.totalWaves,
        onWin            = config.onWin,
        onLose           = config.onLose,
        onExit           = config.onExit,
        label            = config.label or "",
        autoAdvanceWave  = config.autoAdvanceWave ~= false,  -- 默认 true
        waveInterval     = config.waveInterval or 30,        -- 默认 30 秒
        bossTimerEnabled = config.bossTimerEnabled ~= false,  -- 默认 true
        overloadEnabled  = config.overloadEnabled ~= false,   -- 默认 true
        overloadLimit    = config.overloadLimit,                  -- nil = 使用 Config.MAX_ENEMIES
        initialDarkSoul  = config.initialDarkSoul,                 -- nil = 使用 Config.INITIAL_DARK_SOUL
        worldBossDuration     = config.worldBossDuration,          -- 世界BOSS专用时长（秒）
        worldBossDarkSoulDrain = config.worldBossDarkSoulDrain,    -- 世界BOSS每秒扣暗魂
    }

    -- 设置关卡号（用于 Combat 内部的一些逻辑）
    State.currentStage = config.stageNum or 1
    State.phase = State.PHASE_PLAYING

    -- 放置暗影君主到网格中心
    local leader = Tower.CreateLeader(5, 4)
    if leader then
        leader.spawnTime = 0.6
    end

    -- 启动第一波
    BattleManager.StartNextWave()

    -- 设置开局初始暗魂（必须在 StartNextWave 之后，因为 StartNextWave 会加波次奖励）
    HeroData.currencies.dark_soul = BattleManager.config.initialDarkSoul or Config.INITIAL_DARK_SOUL

    print("[BattleManager] Battle started: mode=" .. config.mode
        .. " waves=" .. config.totalWaves .. " label=" .. config.label)

    -- 调用 onStart 回调（在 State.Reset 之后，安全地初始化模式特有状态）
    if config.onStart then
        config.onStart()
    end
end

--- 启动下一波（使用预生成的波次队列）
function BattleManager.StartNextWave()
    local cfg = BattleManager.config
    if not cfg then return end

    State.currentWave = State.currentWave + 1

    -- 超过总波数不应该到这里
    if State.currentWave > cfg.totalWaves then return end

    Currency.CollectDarkSoul(Config.WAVE_DARK_SOUL_BONUS)
    State.waveActive = true
    State.waveTimer = 0

    -- 新波次开始时清除所有塔的减益效果
    Tower.ClearAllDebuffs()

    -- 获取当前波的 spawn queue
    local queue = cfg.waves[State.currentWave]
    if not queue then
        print("[BattleManager] Warning: no queue for wave " .. State.currentWave)
        queue = {}
    end

    State.waveSpawnQueue = queue
    State.waveSpawnIdx = 1
    State.waveSpawnTimer = 0.5

    -- 判断波次类型（优先使用 BuildStageWaves 预嵌的 _waveType 元数据）
    local waveType = queue._waveType
    if not waveType then
        local hasBoss = false
        for _, entry in ipairs(queue) do
            if entry.type == "__boss" or (entry.typeDef and (entry.typeDef.isBoss or entry.typeDef.isDungeonBoss)) then
                hasBoss = true
                break
            end
        end
        waveType = hasBoss and "boss" or "normal"
    end
    State.waveType = waveType

    local AudioManager = require("Game.AudioManager")
    AudioManager.PlayWaveStart()

    local enemyCount = 0
    for _, s in ipairs(queue) do
        if s.type ~= "__pause" then enemyCount = enemyCount + 1 end
    end

    print(string.format("[BattleManager] Wave %d/%d (%s) started, enemies=%d",
        State.currentWave, cfg.totalWaves, State.waveType, enemyCount))
end

--- 波次更新（替代 Wave.Update，用于副本战斗）
function BattleManager.UpdateWaves(dt)
    if not State.waveActive then return end

    local cfg = BattleManager.config
    if not cfg then return end

    -- 生成敌人（从 spawn queue，索引推进替代 table.remove）
    -- 使用 while 循环：加速倍率下一帧可能需要生成多个敌人
    local queue = State.waveSpawnQueue
    local queueLen = #queue
    if State.waveSpawnIdx <= queueLen then
        State.waveSpawnTimer = State.waveSpawnTimer - dt
        while State.waveSpawnTimer <= 0 and State.waveSpawnIdx <= queueLen do
            local entry = queue[State.waveSpawnIdx]
            State.waveSpawnIdx = State.waveSpawnIdx + 1
            BattleManager.SpawnEntry(entry)
            if State.waveSpawnIdx <= queueLen then
                -- 将剩余负值时间累积到下一个条目的 delay 中
                State.waveSpawnTimer = State.waveSpawnTimer + queue[State.waveSpawnIdx].delay
            else
                State.waveSpawnTimer = 0
            end
        end
    end

    local spawnDone = State.waveSpawnIdx > queueLen
    local currentWave = State.currentWave

    -- 非最后一波
    if currentWave < cfg.totalWaves then
        -- 当前波生成完毕 + 敌人全清 → 下一波
        if spawnDone and Enemy.GetAliveCount() == 0 then
            if cfg.autoAdvanceWave then
                BattleManager.StartNextWave()
                return
            end
        end

        -- 定时器自动推进
        if cfg.waveInterval > 0 then
            State.waveTimer = State.waveTimer + dt
            if State.waveTimer >= cfg.waveInterval then
                BattleManager.StartNextWave()
                return
            end
        end
    end

    -- 通关判定：最后一波敌人全清（世界BOSS模式跳过，胜利由计时器控制）
    if cfg.mode ~= "world_boss"
       and currentWave >= cfg.totalWaves
       and spawnDone then
        local aliveCount = Enemy.GetAliveCount()
        if aliveCount == 0 then
            State.waveActive = false
            State.phase = State.PHASE_STAGE_CLEAR
            local AudioManager = require("Game.AudioManager")
            AudioManager.PlayVictory()
            print("[BattleManager] === BATTLE WON! ===")
        elseif State.waveType ~= "boss" then
            -- 所有波次出完，仍有敌人存活：检查是否只剩 BOSS
            -- 如果只剩 BOSS，激活 BOSS 计时器阶段（waveType → "boss"）
            local onlyBoss = true
            for _, e in ipairs(State.enemies) do
                if e.alive and not e.isBoss then
                    onlyBoss = false
                    break
                end
            end
            if onlyBoss then
                -- 跳过Boss模式：只刷小怪，小怪清完直接判定失败
                if cfg.mode == "campaign" and State.skipBoss then
                    print("[BattleManager] skipBoss ON → minions cleared, auto-fail (skip BOSS)")
                    State.phase = State.PHASE_GAME_OVER
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayDefeat()
                    if cfg.onLose then cfg.onLose() end
                else
                    State.waveType = "boss"
                    print("[BattleManager] All minions cleared, only BOSS remains → activating BOSS timer phase")
                end
            end
        end
    end
end

--- 生成单个敌人（支持预缩放的副本敌人）
function BattleManager.SpawnEntry(entry)
    if entry.type == "__pause" then return end

    if entry.prescaled then
        -- 副本敌人：HP/DEF/Speed 已由副本模块预计算，hpScale=1, speedScale=1
        if entry.typeDef and (entry.typeDef.isBoss or entry.typeDef.isDungeonBoss) then
            Enemy.CreateBoss(entry.typeDef, State.currentWave, 1.0, 1.0, entry.affixes or {}, 1)
        else
            Enemy.CreateEnemyFromDef(entry.typeDef, State.currentWave, 1.0, 1.0, entry.isElite or false, entry.affixes or {})
        end
    elseif entry.type == "__boss" then
        -- 主线 BOSS（兼容原 Wave.lua 格式）
        local hpScale = entry.hpScale or 1.0
        local speedScale = entry.speedScale or 1.0
        Enemy.CreateBoss(entry.bossDef, State.currentWave, hpScale, speedScale, entry.affixes or {}, entry.bossTier or 1)
    elseif entry.typeDef then
        local hpScale = entry.hpScale or 1.0
        local speedScale = entry.speedScale or 1.0
        Enemy.CreateEnemyFromDef(entry.typeDef, State.currentWave, hpScale, speedScale, entry.isElite or false, entry.affixes or {})
    end
end

--- 战斗胜利处理
function BattleManager.OnWin()
    local cfg = BattleManager.config
    if not cfg then return end

    LootDrop.CollectAll()

    local result = {
        mode = cfg.mode,
        wave = State.currentWave,
        totalWaves = cfg.totalWaves,
        score = State.score,
        totalDamage = cfg.mode == "world_boss" and State.worldBossTotalDamage or nil,
    }

    if cfg.onWin then
        cfg.onWin(result)
    end

    print("[BattleManager] Win callback fired: mode=" .. cfg.mode)
end

--- 战斗失败处理
function BattleManager.OnLose()
    local cfg = BattleManager.config
    if not cfg then return end

    LootDrop.CollectAll()

    -- 计算实际通关波数：基于最早存活敌人的波次（而非定时器推进的 currentWave）
    local firstAliveWave = Enemy.GetFirstAliveWaveNum()
    local clearedWave = firstAliveWave and (firstAliveWave - 1) or State.currentWave

    local result = {
        mode = cfg.mode,
        wave = State.currentWave,
        clearedWave = clearedWave,
        totalWaves = cfg.totalWaves,
        score = State.score,
        totalDamage = cfg.mode == "world_boss" and State.worldBossTotalDamage or nil,
    }

    if cfg.onLose then
        cfg.onLose(result)
    end

    print(string.format("[BattleManager] Lose callback fired: mode=%s currentWave=%d clearedWave=%d",
        cfg.mode, State.currentWave, clearedWave))
end

--- 结束战斗，清理配置
function BattleManager.End()
    LootDrop.CollectAll()
    BattleManager.config = nil
    print("[BattleManager] Battle ended")
end

return BattleManager
