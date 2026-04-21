-- Game/Wave.lua
-- 暗黑塔防游戏 - 关卡制波次生成器
-- 每关 20 波，通关后进入下一关，局内状态重置

local Config = require("Game.Config")
local State = require("Game.State")
local Enemy = require("Game.Enemy")
local Currency = require("Game.Currency")

local Wave = {}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 计算全局波次号（跨关卡累计，用于怪物/词缀解锁判断）
---@param stageNum number 关卡号
---@param waveInStage number 关内波次号
---@return number
function Wave.GlobalWave(stageNum, waveInStage)
    return (stageNum - 1) * Config.WAVES_PER_STAGE + waveInStage
end

--- 获取当前关卡已解锁的角色列表（基于主题 + 角色解锁进度）
---@param stageNum number 关卡号
---@return table roleIds 已解锁的角色ID列表
---@return table roleDefs 角色ID -> 完整定义映射
local function GetUnlockedRoles(stageNum)
    local globalWave = Wave.GlobalWave(stageNum, 1)
    local roleIds = {}
    local roleDefs = {}

    for _, roleId in ipairs(Config.ROLE_IDS) do
        local role = Config.ENEMY_ROLES[roleId]
        if role then
            -- 检查解锁条件：基于 unlockOrder 对应的全局波次
            local unlockWave = Config.ROLE_UNLOCK_WAVE[role.unlockOrder] or 1
            if globalWave >= unlockWave then
                local def = Config.BuildEnemyDef(stageNum, roleId)
                if def then
                    roleIds[#roleIds + 1] = roleId
                    roleDefs[roleId] = def
                end
            end
        end
    end

    -- 保底：至少有 minion 和 infantry
    if #roleIds == 0 then
        roleIds = { "minion", "infantry" }
        for _, rid in ipairs(roleIds) do
            roleDefs[rid] = Config.BuildEnemyDef(stageNum, rid)
        end
    end

    return roleIds, roleDefs
end

--- 随机选取 n 个不重复元素
local function PickRandom(list, n)
    if #list <= n then return list end
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    local result = {}
    for i = 1, n do
        local idx = math.random(1, #copy)
        result[i] = copy[idx]
        table.remove(copy, idx)
    end
    return result
end

--- 随机选取并缩放词缀（使用新统一系统）
---@param globalWave number 等效全局波次（用于解锁判定）
---@param stageNum number 当前关卡号（用于缩放等级计算）
---@return table[] 缩放后的词缀实例列表
local function PickAffixes(globalWave, stageNum)
    local count = 1
    if globalWave >= 100 then
        count = 3
    elseif globalWave >= Config.AFFIX_WAVE_T3 then
        count = 2
    end

    local level = math.max(1, math.floor(stageNum / 10))
    return Config.PickAffixes(globalWave, count, level)
end

-- ============================================================================
-- 难度缩放
-- ============================================================================

--- 计算 HP 缩放倍率（关卡号 + 关内波次号）
local function GetHPScale(stageNum, waveInStage)
    local stageScale = Config.GetStageHPScale(stageNum)
    -- 关内波次微调
    local waveScale = 1.0 + Config.WAVE_HP_PER_WAVE * (waveInStage - 1)
    return stageScale * waveScale
end

--- 计算速度缩放倍率
local function GetSpeedScale(stageNum)
    return 1.0 + math.min(
        (stageNum - 1) * Config.STAGE_SPEED_PER_STAGE,
        Config.STAGE_SPEED_CAP - 1.0
    )
end

--- 计算 BOSS 阶数（每10关升一阶）
local function GetBossTier(stageNum)
    return math.ceil(stageNum / 10)
end

-- ============================================================================
-- 波次生成
-- ============================================================================

--- 生成普通波
local function GenerateNormalWave(stageNum, waveInStage)
    local roleIds, roleDefs = GetUnlockedRoles(stageNum)
    local typeCount = math.min(2, #roleIds)
    if stageNum >= 3 then typeCount = math.min(3, #roleIds) end
    local picked = PickRandom(roleIds, typeCount)

    local totalCount = math.min(
        math.floor(Config.WAVE_BASE_COUNT + waveInStage * Config.WAVE_COUNT_GROWTH + stageNum * 0.5),
        Config.WAVE_MAX_COUNT
    )

    local queue = {}
    local perType = math.max(1, math.floor(totalCount / #picked))
    for _, roleId in ipairs(picked) do
        local def = roleDefs[roleId]
        local count = perType
        if roleId == "minion" then count = math.floor(count * 1.5) end
        local interval = 1.0
        if def and def.speed >= 60 then interval = 0.5 end
        for j = 1, count do
            queue[#queue + 1] = {
                type = def.id,       -- 主题化的怪物ID（如 "undead_minion"）
                typeDef = def,       -- 携带完整定义，避免二次查找
                delay = interval,
                isElite = false,
                affixes = {},
            }
        end
    end

    return queue
end

--- 生成精英波
local function GenerateEliteWave(stageNum, waveInStage)
    local globalWave = Wave.GlobalWave(stageNum, waveInStage)
    local queue = GenerateNormalWave(stageNum, waveInStage)

    local roleIds, roleDefs = GetUnlockedRoles(stageNum)
    local eliteRoleId = roleIds[math.random(1, #roleIds)]
    local eliteDef = roleDefs[eliteRoleId]
    local affixes = PickAffixes(globalWave, stageNum)

    -- 精英数量随关卡增加
    local eliteCount = 1
    if stageNum >= 5 then eliteCount = 2 end
    if stageNum >= 10 then eliteCount = 3 end

    local insertPos = math.max(1, math.floor(#queue * 0.4))
    for i = 1, eliteCount do
        table.insert(queue, insertPos + i, {
            type = eliteDef.id,
            typeDef = eliteDef,
            delay = 1.5,
            isElite = true,
            affixes = affixes,
        })
    end

    return queue
end

--- 生成 BOSS 波（第20波）
local function GenerateBossWave(stageNum)
    local globalWave = Wave.GlobalWave(stageNum, Config.WAVES_PER_STAGE)
    local queue = {}

    -- 前置杂兵：从当前主题的已解锁角色中选
    local roleIds, roleDefs = GetUnlockedRoles(stageNum)
    local minionRoleId = roleIds[math.random(1, #roleIds)]
    local minionDef = roleDefs[minionRoleId]
    local minionCount = math.min(4 + stageNum, 10)
    for i = 1, minionCount do
        queue[#queue + 1] = {
            type = minionDef.id,
            typeDef = minionDef,
            delay = 0.6,
            isElite = false,
            affixes = {},
        }
    end

    -- 间隔
    queue[#queue + 1] = {
        type = "__pause",
        delay = 2.0,
    }

    -- BOSS: 使用当前关卡主题的 BOSS
    local bossDef = Config.BuildBossDef(stageNum)
    local bossTier = GetBossTier(stageNum)

    -- BOSS 词缀：阶数-1 个（缩放），上限 5
    local bossAffixes = {}
    if bossTier > 1 then
        local level = math.max(1, math.floor(stageNum / 10))
        local affixCount = math.min(bossTier - 1, 3)
        bossAffixes = Config.PickAffixes(globalWave, affixCount, level)
    end

    queue[#queue + 1] = {
        type = "__boss",
        bossDef = bossDef,       -- 直接携带 BOSS 定义
        bossTier = bossTier,
        delay = 2.0,
        isElite = false,
        affixes = bossAffixes,
    }

    -- BOSS 后增援（关卡3+）
    if stageNum >= 3 then
        queue[#queue + 1] = {
            type = "__pause",
            delay = 3.0,
        }
        local reinforceCount = math.min(2 + math.floor(stageNum / 3), 8)
        for i = 1, reinforceCount do
            local rId = roleIds[math.random(1, #roleIds)]
            local rDef = roleDefs[rId]
            queue[#queue + 1] = {
                type = rDef.id,
                typeDef = rDef,
                delay = 0.8,
                isElite = false,
                affixes = {},
            }
        end
    end

    return queue
end

--- 判断波次类型并生成
function Wave.Generate(stageNum, waveInStage)
    if waveInStage == Config.BOSS_WAVE then
        return GenerateBossWave(stageNum), "boss"
    elseif waveInStage % Config.ELITE_INTERVAL == 0 then
        return GenerateEliteWave(stageNum, waveInStage), "elite"
    else
        return GenerateNormalWave(stageNum, waveInStage), "normal"
    end
end

--- 预构建一个关卡所有波次的 spawn queue（供 BattleManager.Enter("campaign") 使用）
--- 纯计算，无状态副作用（不修改 State，不调用 Currency）
--- 每个 queue 的 entry 已嵌入 hpScale / speedScale；_waveType 存为元数据字段
---@param stageNum number 关卡号
---@return table[] waves 波次队列数组，索引 1..Config.WAVES_PER_STAGE
function Wave.BuildStageWaves(stageNum)
    local waves = {}
    for waveInStage = 1, Config.WAVES_PER_STAGE do
        local queue, waveType = Wave.Generate(stageNum, waveInStage)
        local hpScale    = GetHPScale(stageNum, waveInStage)
        local speedScale = GetSpeedScale(stageNum)
        -- 将缩放系数嵌入 entry，供 BattleManager.SpawnEntry 使用
        -- Boss entry 需额外乘 tierMult（tier^2.25 幂函数曲线），与 SpawnFromEntry 逻辑保持一致
        for _, entry in ipairs(queue) do
            if entry.type == "__boss" then
                local tierMult = (entry.bossTier or 1) ^ 2.25
                entry.hpScale = hpScale * tierMult
            else
                entry.hpScale = hpScale
            end
            entry.speedScale = speedScale
        end
        -- waveType 作为非整数字段存储（ipairs 会忽略它，不影响生成逻辑）
        queue._waveType = waveType
        waves[waveInStage] = queue
    end
    return waves
end

-- ============================================================================
-- 波次控制
-- ============================================================================

--- 开始下一波
function Wave.StartNext()
    State.currentWave = State.currentWave + 1
    -- 新战斗第一波：重置伤害统计
    if State.currentWave == 1 then
        local DamageStats = require("Game.DamageStats")
        DamageStats.Reset()
    end
    Currency.CollectDarkSoul(Config.WAVE_DARK_SOUL_BONUS)
    State.waveActive = true

    -- 播放波次开始音效
    local AudioManager = require("Game.AudioManager")
    AudioManager.PlayWaveStart()

    -- 重置波次定时器
    State.waveTimer = 0

    local stageNum = State.currentStage
    local waveInStage = State.currentWave

    -- 生成波次内容
    local queue, waveType = Wave.Generate(stageNum, waveInStage)
    State.waveSpawnQueue = queue
    State.waveSpawnIdx = 1
    State.waveSpawnTimer = 0.5
    State.waveType = waveType

    local hpScale = GetHPScale(stageNum, waveInStage)

    local enemyCount = 0
    for _, s in ipairs(queue) do
        if s.type ~= "__pause" then enemyCount = enemyCount + 1 end
    end

    -- 更新最高全局波次
    local HeroData = require("Game.HeroData")
    local globalWave = Wave.GlobalWave(stageNum, waveInStage)
    if globalWave > (HeroData.stats.bestGlobalWave or 0) then
        HeroData.stats.bestGlobalWave = globalWave
    end

    print(string.format("[Wave] Stage %d Wave %d/%d (%s) started, spawn=%d, hpScale=%.2f",
        stageNum, waveInStage, Config.WAVES_PER_STAGE, waveType, enemyCount, hpScale))
end

--- 生成单个敌人
local function SpawnFromEntry(entry, stageNum, waveInStage)
    if entry.type == "__pause" then
        return
    end

    local hpScale = GetHPScale(stageNum, waveInStage)
    local speedScale = GetSpeedScale(stageNum)
    local globalWave = Wave.GlobalWave(stageNum, waveInStage)

    if entry.type == "__boss" then
        local bossDef = entry.bossDef
        local tier = entry.bossTier
        local tierMult = tier ^ 2.25
        Enemy.CreateBoss(bossDef, globalWave, hpScale * tierMult, speedScale, entry.affixes, tier)
    elseif entry.typeDef then
        -- 新系统：直接使用携带的完整定义
        Enemy.CreateEnemyFromDef(entry.typeDef, globalWave, hpScale, speedScale, entry.isElite, entry.affixes)
    else
        -- 向后兼容：通过 ID 查找
        Enemy.CreateEnemy(entry.type, globalWave, hpScale, speedScale, entry.isElite, entry.affixes)
    end
end

--- 更新波次状态
function Wave.Update(dt)
    if not State.waveActive then return end

    local stageNum = State.currentStage
    local waveInStage = State.currentWave

    -- 生成敌人（从当前波的生成队列，索引推进替代 table.remove）
    -- 使用 while 循环：加速倍率下一帧可能需要生成多个敌人
    local queue = State.waveSpawnQueue
    local queueLen = #queue
    if State.waveSpawnIdx <= queueLen then
        State.waveSpawnTimer = State.waveSpawnTimer - dt
        while State.waveSpawnTimer <= 0 and State.waveSpawnIdx <= queueLen do
            local entry = queue[State.waveSpawnIdx]
            State.waveSpawnIdx = State.waveSpawnIdx + 1
            SpawnFromEntry(entry, stageNum, waveInStage)
            if State.waveSpawnIdx <= queueLen then
                -- 将剩余负值时间累积到下一个条目的 delay 中
                State.waveSpawnTimer = State.waveSpawnTimer + queue[State.waveSpawnIdx].delay
            else
                State.waveSpawnTimer = 0
            end
        end
    end

    local spawnDone = State.waveSpawnIdx > queueLen

    -- 非最后一波: 清完敌人立即出下一波，或 30 秒定时自动出
    if waveInStage < Config.WAVES_PER_STAGE then
        -- 当前波生成完毕 + 场上怪物全清 → 立即下一波
        if spawnDone and Enemy.GetAliveCount() == 0 then
            Wave.StartNext()
            return
        end
        -- 30秒保底定时器
        State.waveTimer = State.waveTimer + dt
        if State.waveTimer >= Config.WAVE_INTERVAL then
            Wave.StartNext()
            return
        end
    end

    -- 通关判定：最后一波的敌人全部清完 + 生成队列消费完毕
    if waveInStage >= Config.WAVES_PER_STAGE
       and spawnDone
       and Enemy.GetAliveCount() == 0 then
        State.waveActive = false
        State.phase = State.PHASE_STAGE_CLEAR
        local AudioManager = require("Game.AudioManager")
        AudioManager.PlayVictory()
        print("[Wave] === STAGE " .. stageNum .. " CLEAR! ===")
    end
end

return Wave
