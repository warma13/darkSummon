-- Game/GarbageBossSkills.lua
-- 垃圾大扫除 BOSS 技能系统 v2
-- 技能1: 垃圾堆积 — 路径生成不可移动垃圾，每个垃圾降低全英雄攻击力1%
-- 技能2: 毒雾召唤 — 召唤移动垃圾小怪 + 全英雄攻速降低10%（本局叠加）
-- 技能3: 垃圾风暴 — 随机位置降下垃圾，命中英雄降1星，可打断
-- 状态机驱动：IDLE -> CASTING -> EXECUTE -> COOLDOWN -> IDLE

local Config          = require("Game.Config")
local State           = require("Game.State")
local Tower           = require("Game.Tower")
local Enemy           = require("Game.Enemy")
local Toast           = require("Game.Toast")
local Grid            = require("Game.Grid")
local Renderer        = require("Game.Renderer")
local DungeonScaling  = require("Game.DungeonScaling")

local GBS = {}

-- ============================================================================
-- 常量
-- ============================================================================

local PHASE_IDLE     = "idle"
local PHASE_CASTING  = "casting"
local PHASE_EXECUTE  = "execute"
local PHASE_COOLDOWN = "cooldown"

-- 演出时间轴
local CAST_BUILDUP   = 0.6
local CAST_DELAY     = 0.4
local EXEC_DURATION  = 0.5
local RESULT_DISPLAY = 0.4
local COOLDOWN_DELAY = 0.3

local TOTAL_CAST     = CAST_BUILDUP + CAST_DELAY
local TOTAL_EXEC     = EXEC_DURATION + RESULT_DISPLAY

-- 技能颜色
local SKILL_COLORS = {
    garbage_pile  = { 120, 180, 40 },    -- 黄绿色（垃圾堆）
    toxic_summon  = { 100, 60, 160 },    -- 紫色（毒雾召唤）
    trash_storm   = { 200, 50, 30 },     -- 红色（垃圾风暴）
}

-- 技能名称
local SKILL_NAMES = {
    garbage_pile  = "垃圾堆积",
    toxic_summon  = "毒雾召唤",
    trash_storm   = "垃圾风暴",
}

-- ============================================================================
-- 状态
-- ============================================================================

---@type table|nil
local skillState = nil

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 查找存活的垃圾 BOSS
---@return table|nil
local function FindBoss()
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isGarbageBoss then
            return e
        end
    end
    return nil
end

--- 生成粒子爆发
local function BurstParticles(cx, cy, color, count, spread)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local spd = 20 + math.random() * 40
        State.AddParticle({
            x = cx + (math.random() - 0.5) * spread,
            y = cy + (math.random() - 0.5) * spread,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd - 15,
            life = 0.8 + math.random() * 0.6,
            maxLife = 1.4,
            color = color,
            size = 3 + math.random() * 3,
        })
    end
end

--- 获取路径上的随机位置列表（不重复）
---@param count number
---@return table[] positions { {pathIdx, col, row, x, y}, ... }
local function GetRandomPathPositions(count)
    local pathCells = Config.PATH_CELLS
    if not pathCells or #pathCells == 0 then return {} end

    -- 从路径格子中随机选取不重复的索引
    local indices = {}
    for i = 1, #pathCells do
        indices[#indices + 1] = i
    end
    -- Fisher-Yates shuffle
    for i = #indices, 2, -1 do
        local j = math.random(i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    local result = {}
    local n = math.min(count, #indices)
    for i = 1, n do
        local idx = indices[i]
        local cell = pathCells[idx]
        local col, row = cell[1], cell[2]
        local sx, sy = Grid.CellToScreen(col, row, Renderer.gridOffsetX, Renderer.gridOffsetY)
        result[#result + 1] = { pathIdx = idx, col = col, row = row, x = sx, y = sy }
    end
    return result
end

-- ============================================================================
-- 技能 1: 垃圾堆积 — 路径生成不可移动垃圾，每个降低全英雄攻击力1%
-- ============================================================================

local function ExecuteGarbagePile(boss)
    local cfg = skillState.mechanics.garbage_pile
    if not cfg then return end

    skillState.pileCastCount = (skillState.pileCastCount or 0) + 1
    local castNum = skillState.pileCastCount

    local spawnCount = cfg.spawnCount or 10

    -- 等效关卡数 = 初始 + 每次释放增加
    local eqStage = cfg.baseStage + (castNum - 1) * cfg.stageGrowth

    -- 关卡级 HP / DEF 缩放（与主线副本一致）
    local hpScale  = DungeonScaling.CalcHPScale(eqStage)

    -- 在路径上随机位置生成垃圾敌人（不移动）
    local positions = GetRandomPathPositions(spawnCount)
    local spawned = 0

    local pathLen = #(Config.PATH_CELLS or {})
    for i, pos in ipairs(positions) do
        -- 用 infantry 模板构建，但设速度为 0
        local def = Config.BuildEnemyDef(eqStage, "infantry")
        if def then
            def.name = "垃圾堆"
            def.baseHP = def.baseHP * hpScale  -- 应用关卡HP缩放
            def.stageEquiv = eqStage           -- 传递等效关卡供DEF缩放
            def.speed = 0           -- 不移动
            def.reward = 0
            def.liveCost = 0
            def.isGarbageObstacle = true
            def.isDungeonEnemy = true
            def.icon = "image/garbage_obstacle_20260501084023.png"

            local currentWave = State.currentWave or 1
            local enemy = Enemy.CreateEnemyFromDef(def, currentWave, 1.0, 1.0, false, {})

            -- 将垃圾放到路径上的随机位置（设置 progress 并更新坐标）
            if enemy and pathLen > 1 then
                enemy.progress = (pos.pathIdx - 1) / (pathLen - 1)
                enemy.x, enemy.y = Grid.GetPositionOnPath(
                    enemy.progress, Renderer.gridOffsetX, Renderer.gridOffsetY)
            end

            spawned = spawned + 1

            -- 粒子
            local px = enemy and enemy.x or pos.x
            local py = enemy and enemy.y or pos.y
            BurstParticles(px, py, SKILL_COLORS.garbage_pile, 5, 10)
        end
    end

    -- 更新场上垃圾计数（用于攻击力减益计算）
    skillState.garbageOnField = (skillState.garbageOnField or 0) + spawned

    -- 全屏闪光
    State.skillFlash = { type = "garbage_pile", timer = 0.5 }
    BurstParticles(boss.x, boss.y, SKILL_COLORS.garbage_pile, 12, 30)

    Toast.Show("垃圾堆积！生成" .. spawned .. "个垃圾，全英雄攻击力↓" .. skillState.garbageOnField .. "%",
        SKILL_COLORS.garbage_pile)
    print(string.format("[GarbageBoss] GarbagePile cast #%d spawned=%d total=%d eqStage=%d hpScale=%.1f",
        castNum, spawned, skillState.garbageOnField, eqStage, hpScale))
end

-- ============================================================================
-- 技能 2: 毒雾召唤 — 召唤移动垃圾小怪 + 全英雄攻速-10%叠加
-- ============================================================================

local function ExecuteToxicSummon(boss)
    local cfg = skillState.mechanics.toxic_summon
    if not cfg then return end

    skillState.toxicCastCount = (skillState.toxicCastCount or 0) + 1
    local castNum = skillState.toxicCastCount

    -- 等效关卡
    local eqStage = cfg.baseStage + (castNum - 1) * cfg.stageGrowth

    -- 关卡级 HP / DEF / Speed 缩放
    local hpScale  = DungeonScaling.CalcHPScale(eqStage)
    local spdScale = DungeonScaling.CalcSpeedScale(eqStage)
    local eliteHPMult = 3.0  -- 精英怪额外HP倍率

    local count = cfg.summonCount or 5
    local currentWave = State.currentWave or 1

    local availRoles = { "infantry", "tank", "assassin" }

    for i = 1, count do
        local roleId = availRoles[math.random(#availRoles)]
        local def = Config.BuildEnemyDef(eqStage, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale * eliteHPMult  -- 应用关卡HP缩放 + 精英倍率
            def.speed  = def.speed * spdScale                -- 应用关卡速度缩放
            def.stageEquiv = eqStage                         -- 传递等效关卡供DEF缩放
            def.isElite = true
            def.isDungeonEnemy = true
            Enemy.CreateEnemyFromDef(def, currentWave, 1.0, 1.0, true, {})
        end
    end

    -- 攻速降低叠加（本局永久）
    skillState.atkSpdDebuffStacks = (skillState.atkSpdDebuffStacks or 0) + 1
    local totalSpdReduction = skillState.atkSpdDebuffStacks * (cfg.spdReductionPct or 0.10)

    -- 对所有英雄施加永久攻速减益
    for _, tower in ipairs(State.towers) do
        Tower.ApplyDebuff(tower, "garbage_toxic_spd", "speed", totalSpdReduction, "pct", 99999)
    end

    -- 全屏闪光
    State.skillFlash = { type = "garbage_toxic", timer = 0.5 }
    BurstParticles(boss.x, boss.y, SKILL_COLORS.toxic_summon, 18, 35)

    Toast.Show("毒雾召唤！" .. count .. "只小怪！全英雄攻速↓" ..
        math.floor(totalSpdReduction * 100) .. "%", SKILL_COLORS.toxic_summon)
    print(string.format("[GarbageBoss] ToxicSummon cast #%d count=%d spdStacks=%d eqStage=%d hpScale=%.1f spdScale=%.2f",
        castNum, count, skillState.atkSpdDebuffStacks, eqStage, hpScale, spdScale))
end

-- ============================================================================
-- 技能 3: 垃圾风暴 — 随机位置降下垃圾，命中英雄降1星
-- ============================================================================

--- 开始垃圾风暴引导
local function StartTrashStorm(boss)
    local cfg = skillState.mechanics.trash_storm
    if not cfg then return false end

    if #State.towers == 0 then return false end

    skillState.stormCastCount = (skillState.stormCastCount or 0) + 1
    local castNum = skillState.stormCastCount

    -- 降下数量 = 初始 + 每次释放+1
    local meteorCount = (cfg.baseCount or 1) + (castNum - 1)
    local channelTime = cfg.channelTime or 1.0

    -- 韧性条
    local defDiv = cfg.toughnessDefDiv or 80000
    local minHits = cfg.toughnessMin or 15
    local toughnessHits = math.max(minHits, math.ceil((boss.def or 0) / defDiv))

    -- 随机选择目标英雄位置
    local targetTowers = {}
    local towersCopy = {}
    for _, t in ipairs(State.towers) do towersCopy[#towersCopy + 1] = t end
    -- shuffle
    for i = #towersCopy, 2, -1 do
        local j = math.random(i)
        towersCopy[i], towersCopy[j] = towersCopy[j], towersCopy[i]
    end
    local n = math.min(meteorCount, #towersCopy)
    for i = 1, n do
        targetTowers[#targetTowers + 1] = towersCopy[i]
    end

    skillState.trashStorm = {
        timer = channelTime,
        totalTime = channelTime,
        meteorCount = n,
        targets = targetTowers,
        toughness = toughnessHits,
        maxToughness = toughnessHits,
        interrupted = false,
    }

    -- 引导期间眩晕
    boss.stunTimer = math.max(boss.stunTimer or 0, channelTime + 1.0)

    -- 渲染数据
    State.garbageBossSkill = State.garbageBossSkill or {}
    State.garbageBossSkill.trashStorm = {
        targets = {},
        toughness = toughnessHits,
        maxToughness = toughnessHits,
        timer = channelTime,
        totalTime = channelTime,
    }
    for _, t in ipairs(targetTowers) do
        local sx, sy = Grid.CellToScreen(t.col, t.row, Renderer.gridOffsetX, Renderer.gridOffsetY)
        State.garbageBossSkill.trashStorm.targets[#State.garbageBossSkill.trashStorm.targets + 1] = {
            col = t.col, row = t.row, x = sx, y = sy,
        }
    end

    Toast.Show("⚠ 垃圾风暴！" .. n .. "个垃圾即将降下！集火打断！", { 255, 50, 30 })
    BurstParticles(boss.x, boss.y, SKILL_COLORS.trash_storm, 25, 40)

    print(string.format("[GarbageBoss] TrashStorm started: meteorCount=%d toughness=%d castNum=%d",
        n, toughnessHits, castNum))
    return true
end

--- 垃圾风暴引导更新
local function UpdateTrashStorm(boss, dt)
    local storm = skillState.trashStorm
    if not storm or storm.interrupted then return end

    storm.timer = storm.timer - dt

    -- 同步渲染数据
    if State.garbageBossSkill and State.garbageBossSkill.trashStorm then
        State.garbageBossSkill.trashStorm.timer = storm.timer
        State.garbageBossSkill.trashStorm.toughness = storm.toughness
    end

    -- 引导完成：降下垃圾，命中英雄降1星
    if storm.timer <= 0 then
        local demoted = 0
        local removed = 0
        for _, tower in ipairs(storm.targets) do
            -- 检查英雄是否还活着
            local alive = false
            for _, t in ipairs(State.towers) do
                if t.id == tower.id then alive = true; break end
            end
            if alive then
                local sx, sy = Grid.CellToScreen(tower.col, tower.row, Renderer.gridOffsetX, Renderer.gridOffsetY)
                BurstParticles(sx, sy, SKILL_COLORS.trash_storm, 10, 20)

                if tower.star and tower.star > 0 then
                    -- 降1星
                    tower.star = tower.star - 1
                    Tower.RecalcStats(tower)
                    demoted = demoted + 1
                    State.AddFloatingText({
                        text = tower.typeDef.name .. " ★降级！",
                        x = sx, y = sy - 20,
                        vx = (math.random() - 0.5) * 20,
                        vy = -40 - math.random() * 15,
                        life = 1.5,
                        color = { 255, 50, 30, 255 },
                        fontSize = 14,
                    })
                else
                    -- 0星英雄直接移除
                    Tower.Remove(tower)
                    removed = removed + 1
                    State.AddFloatingText({
                        text = tower.typeDef.name .. " 被摧毁！",
                        x = sx, y = sy - 20,
                        vx = (math.random() - 0.5) * 20,
                        vy = -40 - math.random() * 15,
                        life = 1.5,
                        color = { 255, 30, 30, 255 },
                        fontSize = 14,
                    })
                end
            end
        end

        -- 全屏闪光
        State.skillFlash = { type = "garbage_storm", timer = 0.5 }

        storm.interrupted = true
        boss.stunTimer = 0
        if State.garbageBossSkill then
            State.garbageBossSkill.trashStorm = nil
        end

        local msg = "垃圾风暴！"
        if demoted > 0 then msg = msg .. demoted .. "名英雄降星！" end
        if removed > 0 then msg = msg .. removed .. "名英雄被摧毁！" end
        Toast.Show(msg, SKILL_COLORS.trash_storm)
        print(string.format("[GarbageBoss] TrashStorm executed: demoted=%d removed=%d", demoted, removed))

        -- 所有英雄被毁灭
        if #State.towers == 0 then
            print("[GarbageBoss] All towers destroyed! Triggering game over.")
            Toast.Show("所有英雄已被摧毁！", { 255, 40, 40 })
            local BattleManager = require("Game.BattleManager")
            local AudioManager = require("Game.AudioManager")
            State.SetPhase(State.PHASE_GAME_OVER, "GBS.allTowersDestroyed")
            AudioManager.PlayDefeat()
            BattleManager.OnLose()
        end
    end
end

--- 对垃圾风暴韧性条造成命中
function GBS.DamageToughness()
    if not skillState or not skillState.trashStorm then return end
    if skillState.trashStorm.interrupted then return end

    skillState.trashStorm.toughness = skillState.trashStorm.toughness - 1

    if State.garbageBossSkill and State.garbageBossSkill.trashStorm then
        State.garbageBossSkill.trashStorm.toughness = skillState.trashStorm.toughness
    end

    if skillState.trashStorm.toughness <= 0 then
        skillState.trashStorm.interrupted = true
        skillState.trashStorm.toughness = 0

        local boss = FindBoss()
        if boss then boss.stunTimer = 0 end

        if State.garbageBossSkill then
            State.garbageBossSkill.trashStorm = nil
        end

        Toast.Show("垃圾风暴被打断了！", { 100, 255, 100 })
        print("[GarbageBoss] TrashStorm interrupted! Toughness broken.")
    end
end

--- 获取垃圾风暴状态（供 Renderer / Combat 查询）
---@return table|nil
function GBS.GetTrashStormState()
    if not skillState or not skillState.trashStorm then return nil end
    if skillState.trashStorm.interrupted then return nil end
    return skillState.trashStorm
end

-- ============================================================================
-- 垃圾计数更新（每帧统计场上存活的垃圾障碍物数量）
-- ============================================================================

local function UpdateGarbageCount()
    local count = 0
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isGarbageObstacle then
            count = count + 1
        end
    end
    skillState.garbageOnField = count

    -- 应用全英雄攻击力减益: 每个垃圾 -1%
    local atkReduction = count * 0.01
    if atkReduction > 0 then
        for _, tower in ipairs(State.towers) do
            Tower.ApplyDebuff(tower, "garbage_pile_atk", "attack", atkReduction, "pct", 1.0)
        end
    end
end

-- ============================================================================
-- 新英雄也受攻速减益
-- ============================================================================

local function ApplyAtkSpdDebuffToAll()
    if not skillState or not skillState.atkSpdDebuffStacks then return end
    local stacks = skillState.atkSpdDebuffStacks
    if stacks <= 0 then return end

    local cfg = skillState.mechanics.toxic_summon
    local reduction = stacks * (cfg and cfg.spdReductionPct or 0.10)

    for _, tower in ipairs(State.towers) do
        -- 检查是否已有此 debuff
        local hasDebuff = false
        if tower.debuffs then
            for _, db in ipairs(tower.debuffs) do
                if db.id == "garbage_toxic_spd" then
                    hasDebuff = true
                    break
                end
            end
        end
        if not hasDebuff then
            Tower.ApplyDebuff(tower, "garbage_toxic_spd", "speed", reduction, "pct", 99999)
        end
    end
end

-- ============================================================================
-- 技能选择（优先级：垃圾风暴 > 毒雾召唤 > 垃圾堆积）
-- ============================================================================

local function SelectSkill()
    local m = skillState.mechanics

    if m.trash_storm and skillState.trashStormCd <= 0 then
        return "trash_storm"
    end
    if m.toxic_summon and skillState.toxicSummonCd <= 0 then
        return "toxic_summon"
    end
    if m.garbage_pile and skillState.garbagePileCd <= 0 then
        return "garbage_pile"
    end

    return nil
end

-- ============================================================================
-- 状态机
-- ============================================================================

local function EnterCasting(boss, skillId)
    skillState.activeSkill = skillId
    skillState.phase = PHASE_CASTING
    skillState.phaseTimer = 0

    local stunDuration = TOTAL_CAST + TOTAL_EXEC + COOLDOWN_DELAY + 0.5
    if skillId == "trash_storm" then
        local cfg = skillState.mechanics.trash_storm
        stunDuration = TOTAL_CAST + (cfg and cfg.channelTime or 1.0) + COOLDOWN_DELAY + 0.5
    end
    boss.stunTimer = math.max(boss.stunTimer or 0, stunDuration)

    local c = SKILL_COLORS[skillId]
    State.garbageBossSkill = State.garbageBossSkill or {}
    State.garbageBossSkill.casting = {
        type = skillId,
        phase = PHASE_CASTING,
        timer = 0,
        bossId = boss.id,
        color = c,
    }

    print("[GarbageBoss] Casting: " .. SKILL_NAMES[skillId])
end

local function EnterExecute(boss, skillId)
    skillState.phase = PHASE_EXECUTE
    skillState.phaseTimer = 0

    if skillId == "toxic_summon" then
        boss.castingFrame = 2
    else
        boss.castingFrame = 1
    end

    if State.garbageBossSkill and State.garbageBossSkill.casting then
        State.garbageBossSkill.casting.phase = PHASE_EXECUTE
        State.garbageBossSkill.casting.timer = 0
    end

    if skillId == "garbage_pile" then
        ExecuteGarbagePile(boss)
    elseif skillId == "toxic_summon" then
        ExecuteToxicSummon(boss)
    elseif skillId == "trash_storm" then
        local success = StartTrashStorm(boss)
        if not success then
            print("[GarbageBoss] TrashStorm: no valid targets, skipped")
        end
    end
end

local function EnterCooldown(boss, skillId)
    skillState.phase = PHASE_COOLDOWN
    skillState.phaseTimer = 0
    boss.castingFrame = nil

    local m = skillState.mechanics
    if skillId == "garbage_pile" and m.garbage_pile then
        skillState.garbagePileCd = m.garbage_pile.interval
    elseif skillId == "toxic_summon" and m.toxic_summon then
        skillState.toxicSummonCd = m.toxic_summon.interval
    elseif skillId == "trash_storm" and m.trash_storm then
        skillState.trashStormCd = m.trash_storm.interval
    end
end

local function EnterIdle()
    skillState.activeSkill = nil
    skillState.phase = PHASE_IDLE
    skillState.phaseTimer = 0

    if State.garbageBossSkill then
        State.garbageBossSkill.casting = nil
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化
---@param mechanics table { garbage_pile, toxic_summon, trash_storm }
function GBS.Init(mechanics)
    if not mechanics then return end
    skillState = {
        battleTimer = 0,
        phase = PHASE_IDLE,
        activeSkill = nil,
        phaseTimer = 0,
        mechanics = mechanics,

        -- 技能 CD（首次延迟减半）
        garbagePileCd  = mechanics.garbage_pile  and (mechanics.garbage_pile.interval  * 0.5) or 999,
        toxicSummonCd  = mechanics.toxic_summon   and (mechanics.toxic_summon.interval   * 0.5) or 999,
        trashStormCd   = mechanics.trash_storm    and (mechanics.trash_storm.interval    * 0.5) or 999,

        -- 释放计数
        pileCastCount = 0,
        toxicCastCount = 0,
        stormCastCount = 0,

        -- 场上垃圾数
        garbageOnField = 0,

        -- 攻速减益叠加层数
        atkSpdDebuffStacks = 0,

        -- 垃圾风暴状态
        trashStorm = nil,

        bossSpawned = false,
    }

    State.garbageBossSkill = {}

    print("[GarbageBoss] Initialized"
        .. " garbage_pile.interval=" .. tostring(mechanics.garbage_pile and mechanics.garbage_pile.interval)
        .. " toxic_summon.interval=" .. tostring(mechanics.toxic_summon and mechanics.toxic_summon.interval)
        .. " trash_storm.interval=" .. tostring(mechanics.trash_storm and mechanics.trash_storm.interval))
end

--- 每帧更新
---@param dt number
function GBS.Update(dt)
    if not skillState then return end

    skillState.battleTimer = skillState.battleTimer + dt

    local boss = FindBoss()
    if not boss then
        if skillState.bossSpawned then
            GBS.Cleanup()
        end
        return
    end
    skillState.bossSpawned = true

    -- ======== 垃圾数量统计 + 攻击力减益 ========
    UpdateGarbageCount()

    -- ======== 新英雄也受攻速减益 ========
    ApplyAtkSpdDebuffToAll()

    -- ======== 垃圾风暴引导 ========
    if skillState.trashStorm and not skillState.trashStorm.interrupted then
        UpdateTrashStorm(boss, dt)
    end

    if not skillState then return end

    -- ======== 同步渲染状态 ========
    State.garbageBossSkill = State.garbageBossSkill or {}
    State.garbageBossSkill.bossX = boss.x
    State.garbageBossSkill.bossY = boss.y
    State.garbageBossSkill.bossSize = boss.typeDef and boss.typeDef.size or 22
    State.garbageBossSkill.garbageCount = skillState.garbageOnField
    State.garbageBossSkill.atkSpdStacks = skillState.atkSpdDebuffStacks

    -- ======== 状态机 ========

    if skillState.phase == PHASE_IDLE then
        if skillState.trashStorm and not skillState.trashStorm.interrupted then
            return
        end

        skillState.garbagePileCd  = skillState.garbagePileCd  - dt
        skillState.toxicSummonCd  = skillState.toxicSummonCd  - dt
        skillState.trashStormCd   = skillState.trashStormCd   - dt

        local skillId = SelectSkill()
        if skillId then
            EnterCasting(boss, skillId)
        end

    elseif skillState.phase == PHASE_CASTING then
        skillState.phaseTimer = skillState.phaseTimer + dt

        if skillState.phaseTimer >= 0.3 and not skillState.bannerShown then
            skillState.bannerShown = true
            if not State.bossIntro then
                State.bossIntro = {
                    timer = 0,
                    duration = 1.5,
                    name = SKILL_NAMES[skillState.activeSkill] or "???",
                }
            end
        end

        if skillState.phaseTimer >= CAST_BUILDUP and not skillState.castFrameSet then
            skillState.castFrameSet = true
            boss.castingFrame = 1
        end

        if State.garbageBossSkill and State.garbageBossSkill.casting then
            State.garbageBossSkill.casting.timer = skillState.phaseTimer
        end

        if skillState.phaseTimer >= TOTAL_CAST then
            skillState.bannerShown = nil
            skillState.castFrameSet = nil
            EnterExecute(boss, skillState.activeSkill)
        end

    elseif skillState.phase == PHASE_EXECUTE then
        skillState.phaseTimer = skillState.phaseTimer + dt

        if State.garbageBossSkill and State.garbageBossSkill.casting then
            State.garbageBossSkill.casting.timer = skillState.phaseTimer
        end

        if skillState.activeSkill == "trash_storm" then
            local storm = skillState.trashStorm
            if not storm or storm.interrupted then
                EnterCooldown(boss, skillState.activeSkill)
            end
        elseif skillState.phaseTimer >= TOTAL_EXEC then
            EnterCooldown(boss, skillState.activeSkill)
        end

    elseif skillState.phase == PHASE_COOLDOWN then
        skillState.phaseTimer = skillState.phaseTimer + dt
        if skillState.phaseTimer >= COOLDOWN_DELAY then
            EnterIdle()
        end
    end
end

--- 清理
function GBS.Cleanup()
    if not skillState then return end

    local boss = FindBoss()
    if boss then
        boss.castingFrame = nil
        if skillState.trashStorm and not skillState.trashStorm.interrupted then
            boss.stunTimer = 0
        end
    end

    -- 清除英雄塔上的 debuff
    for _, tower in ipairs(State.towers) do
        if tower.debuffs then
            local i = 1
            while i <= #tower.debuffs do
                local db = tower.debuffs[i]
                if db.id == "garbage_pile_atk" or db.id == "garbage_toxic_spd" then
                    table.remove(tower.debuffs, i)
                else
                    i = i + 1
                end
            end
        end
    end

    State.garbageBossSkill = nil
    skillState = nil
    print("[GarbageBoss] Cleaned up")
end

--- 是否激活
---@return boolean
function GBS.IsActive()
    return skillState ~= nil
end

--- 当英雄攻击 BOSS 时的被动回调
---@param tower table
function GBS.OnTowerHitBoss(tower)
    -- 保留接口供扩展
end

--- 获取下次技能释放倒计时
---@return string skillName, number cooldown
function GBS.GetNextSkillInfo()
    if not skillState then return "无", 0 end
    local cds = {
        { name = "垃圾风暴", cd = skillState.trashStormCd },
        { name = "毒雾召唤", cd = skillState.toxicSummonCd },
        { name = "垃圾堆积", cd = skillState.garbagePileCd },
    }
    table.sort(cds, function(a, b) return a.cd < b.cd end)
    return cds[1].name, math.max(0, cds[1].cd)
end

--- 获取场上垃圾数量
---@return number
function GBS.GetGarbageCount()
    if not skillState then return 0 end
    return skillState.garbageOnField or 0
end

--- 获取攻速减益层数
---@return number
function GBS.GetAtkSpdStacks()
    if not skillState then return 0 end
    return skillState.atkSpdDebuffStacks or 0
end

return GBS
