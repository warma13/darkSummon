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
---@field onUpdate function|nil     每帧更新回调 function(dt)，用于副本特有逻辑（如世界BOSS技能）
---@field initialDarkSoul number|nil 开局初始暗魂（nil 则保持当前暗魂不覆盖）

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
            affixes = def.affixes or def.bossAffixes or def.eliteAffixes or {},
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
    BattleManager._settled = false

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
        onUpdate         = config.onUpdate,                        -- 副本特有每帧回调
        initialDarkSoul  = config.initialDarkSoul,                 -- nil = 保持当前暗魂不覆盖
        worldBossDuration     = config.worldBossDuration,          -- 世界BOSS专用时长（秒）
        worldBossDarkSoulDrain = config.worldBossDarkSoulDrain,    -- 世界BOSS每秒扣暗魂
    }

    -- 设置关卡号（用于 Combat 内部的一些逻辑）
    State.currentStage = config.stageNum or 1
    State.SetPhase(State.PHASE_PLAYING, "BM.Start")

    -- 放置暗影君主到网格中心
    local leader = Tower.CreateLeader(5, 4)
    if leader then
        leader.spawnTime = 0.6
    end

    -- 启动第一波
    BattleManager.StartNextWave()

    -- 设置开局初始暗魂（必须在 StartNextWave 之后，因为 StartNextWave 会加波次奖励）
    -- nil 表示不覆盖（如 campaign 从存档恢复时保留当前暗魂）
    if BattleManager.config.initialDarkSoul ~= nil then
        HeroData.currencies.dark_soul = BattleManager.config.initialDarkSoul
    end

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

    -- 新战斗第一波：重置伤害统计
    if State.currentWave == 1 then
        local DamageStats = require("Game.DamageStats")
        DamageStats.Reset()
    end

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

    -- campaign 模式下更新最高全局波次
    if cfg.mode == "campaign" then
        local globalWave = Wave.GlobalWave(State.currentStage, State.currentWave)
        if globalWave > (HeroData.stats.bestGlobalWave or 0) then
            HeroData.stats.bestGlobalWave = globalWave
        end
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

        -- skipBoss 模式：小怪全清后重刷同一关（不打BOSS、不进入下一关）
        if cfg.mode == "campaign" and State.skipBoss then
            -- 检查是否只剩 BOSS 或全部清完
            local aliveCount = Enemy.GetAliveCount()
            local onlyBossLeft = false
            if aliveCount > 0 then
                onlyBossLeft = true
                for _, e in ipairs(State.enemies) do
                    if e.alive and not e.isBoss then
                        onlyBossLeft = false
                        break
                    end
                end
            end
            if aliveCount == 0 or onlyBossLeft then
                -- 清除残留BOSS
                if onlyBossLeft then
                    for _, e in ipairs(State.enemies) do
                        if e.alive and e.isBoss then
                            e.alive = false
                            e.hp = 0
                        end
                    end
                end
                -- 重置波次，从第一波重新开始同一关
                print("[BattleManager] skipBoss ON → restarting stage from wave 1")
                State.currentWave = 0
                BattleManager._settled = false
                BattleManager.StartNextWave()
                return
            end
        else
            -- 正常模式：通关判定
            local aliveCount = Enemy.GetAliveCount()
            if aliveCount == 0 then
                State.waveActive = false
                State.SetPhase(State.PHASE_STAGE_CLEAR, "BM.lastWaveClear")
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
                    State.waveType = "boss"
                    print("[BattleManager] All minions cleared, only BOSS remains → activating BOSS timer phase")
                end
            end
        end
    end

    -- ========================================================================
    -- 以下逻辑从 GameUI.Update 迁移，统一由 BM 管理
    -- ========================================================================

    -- ── 超限判定 ──
    if State.phase == State.PHASE_PLAYING and cfg.overloadEnabled then
        local aliveCount = Enemy.GetAliveCount()
        local maxEnemies = cfg.overloadLimit or Config.MAX_ENEMIES
        if aliveCount > maxEnemies then
            if not State.overloading then
                State.overloading = true
                State.overloadTimer = 0
                print("[BattleManager] Overload started! enemies=" .. aliveCount)
            end
            State.overloadTimer = State.overloadTimer + dt
            if State.overloadTimer >= Config.OVERLOAD_COUNTDOWN then
                State.SetPhase(State.PHASE_GAME_OVER, "BM.overload")
                State.overloading = false
                local AudioManager = require("Game.AudioManager")
                AudioManager.PlayDefeat()
                print("[BattleManager] Overload timeout! Game over.")
                BattleManager.OnLose()
                return
            end
        else
            if State.overloading then
                print("[BattleManager] Overload cleared, enemies=" .. aliveCount)
            end
            State.overloading = false
            State.overloadTimer = 0
        end
    end

    -- ── BOSS 倒计时 ──
    if State.phase == State.PHASE_PLAYING and cfg.bossTimerEnabled then
        local isWorldBoss = cfg.mode == "world_boss"
        local bossMaxTimer = (isWorldBoss and cfg.worldBossDuration) or Config.BOSS_TIMER_MAX

        -- BOSS 激活检测
        if State.waveType == "boss" and not State.bossActive then
            for _, e in ipairs(State.enemies) do
                if e.alive and e.isBoss then
                    State.bossActive = true
                    State.bossTimer = bossMaxTimer
                    State.bossTimerMax = bossMaxTimer
                    local bossName = e.typeDef and e.typeDef.name or "BOSS"
                    State.bossIntro = { timer = 0, duration = 2.0, name = bossName }
                    print("[BattleManager] BOSS fight started! Timer=" .. bossMaxTimer .. "s")
                    break
                end
            end
        end

        if State.bossActive then
            local bossAlive = false
            for _, e in ipairs(State.enemies) do
                if e.alive and e.isBoss then
                    bossAlive = true
                    break
                end
            end

            if not bossAlive then
                State.bossActive = false
                State.bossTimer = 0
                print("[BattleManager] BOSS defeated! Timer stopped.")
            else
                -- 世界BOSS每秒掉落暗魂
                if isWorldBoss and cfg.worldBossDarkSoulDrain then
                    local bossX, bossY = nil, nil
                    for _, e in ipairs(State.enemies) do
                        if e.alive and e.isBoss then
                            bossX, bossY = e.x, e.y
                            break
                        end
                    end
                    if bossX then
                        State.worldBossDrainAcc = (State.worldBossDrainAcc or 0) + dt
                        while State.worldBossDrainAcc >= 1.0 do
                            State.worldBossDrainAcc = State.worldBossDrainAcc - 1.0
                            LootDrop.Spawn("dark_soul", cfg.worldBossDarkSoulDrain, bossX, bossY)
                        end
                    end
                end

                State.bossTimer = State.bossTimer - dt
                if State.bossTimer <= 0 then
                    State.bossTimer = 0
                    State.bossActive = false

                    if isWorldBoss then
                        -- 世界BOSS到时 → 结算（算通关）
                        State.SetPhase(State.PHASE_STAGE_CLEAR, "BM.worldBossTimeout")
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayVictory()
                        print("[BattleManager] World BOSS timer up! Settling damage.")
                        BattleManager.OnWin()
                    else
                        -- 普通BOSS超时 → 失败
                        State.SetPhase(State.PHASE_GAME_OVER, "BM.bossTimeout")
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayDefeat()
                        print("[BattleManager] BOSS timer expired! Game over.")
                        BattleManager.OnLose()
                    end
                    return
                end
            end
        end
    else
        -- 非 PLAYING 阶段或 bossTimer 未启用：清理 boss 状态
        if State.bossActive then
            State.bossActive = false
            State.bossTimer = 0
        end
    end

    -- ── 通关桥接（STAGE_CLEAR → OnWin） ──
    if State.phase == State.PHASE_STAGE_CLEAR and not State.settleRewards then
        State.settleRewards = true
        BattleManager.OnWin()
        return
    end

    -- ── 副本特有每帧逻辑（如世界BOSS技能、翡翠BOSS技能） ──
    if cfg.onUpdate then
        cfg.onUpdate(dt)
    end
end

--- 生成单个敌人（支持预缩放的副本敌人）
function BattleManager.SpawnEntry(entry)
    if entry.type == "__pause" then return end

    -- skipBoss：跳过BOSS生成（campaign 模式下关闭挑战Boss时，不刷BOSS）
    local cfg = BattleManager.config
    if cfg and cfg.mode == "campaign" and State.skipBoss then
        local isBoss = entry.type == "__boss"
            or (entry.typeDef and (entry.typeDef.isBoss or entry.typeDef.isDungeonBoss))
        if isBoss then
            print("[BattleManager] skipBoss ON → skipping BOSS spawn")
            return
        end
    end

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

--- 战斗胜利处理（_settled 防重入，一场战斗只结算一次）
function BattleManager.OnWin()
    local cfg = BattleManager.config
    if not cfg or BattleManager._settled then return end
    BattleManager._settled = true

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

--- 战斗失败处理（_settled 防重入，一场战斗只结算一次）
function BattleManager.OnLose()
    local cfg = BattleManager.config
    if not cfg or BattleManager._settled then return end
    BattleManager._settled = true

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
