-- Game/BossSkills/GenericSkills.lua
-- 通用 Boss 技能实现（供无专属技能的副本使用）
-- 接口与现有 XxxBossSkills 模块对齐: Init / Update / Cleanup / IsActive

local State  = require("Game.State")
local Config = require("Game.Config")
local Debuff = require("Game.Debuff")
local Enemy  = require("Game.Enemy")

local GS = {}

-- ============================================================================
-- 状态机常量（与 EmeraldBossSkills 等对齐）
-- ============================================================================
local PHASE_IDLE     = "idle"
local PHASE_CASTING  = "casting"
local PHASE_EXECUTE  = "execute"
local PHASE_COOLDOWN = "cooldown"

-- 相位时间常量
local CAST_BUILDUP   = 0.6
local CAST_DELAY     = 0.4
local EXEC_DURATION  = 0.5
local RESULT_DISPLAY = 0.4
local COOLDOWN_DELAY = 0.3

-- ============================================================================
-- 模块状态
-- ============================================================================
local active = false
---@type table|nil
local skillState = nil

-- ============================================================================
-- 技能选择（加权随机 + CD 检查）
-- ============================================================================

local function PickNextSkill()
    if not skillState then return nil end
    local ready = {}
    for _, sk in ipairs(skillState.skillList) do
        if sk.cdTimer <= 0 then
            ready[#ready + 1] = sk
        end
    end
    if #ready == 0 then return nil end
    -- 简单均匀随机
    return ready[math.random(#ready)]
end

-- ============================================================================
-- 目标选择 —— 加权随机从 State.towers 中选 N 个
-- ============================================================================

local STAR_WEIGHTS = { 1, 2, 4, 8, 16 }

local function SelectTowers(count)
    local candidates = {}
    local totalW = 0
    for _, tower in ipairs(State.towers) do
        if not tower.shackled then
            local starIdx = math.min((tower.star or 0) + 1, #STAR_WEIGHTS)
            local w = STAR_WEIGHTS[starIdx]
            candidates[#candidates + 1] = { tower = tower, weight = w }
            totalW = totalW + w
        end
    end
    local selected = {}
    local usedSet = {}
    local n = math.min(count, #candidates)
    for _ = 1, n do
        local roll = math.random() * totalW
        local acc = 0
        for ci, c in ipairs(candidates) do
            if not usedSet[ci] then
                acc = acc + c.weight
                if roll <= acc then
                    selected[#selected + 1] = c.tower
                    usedSet[ci] = true
                    totalW = totalW - c.weight
                    break
                end
            end
        end
    end
    return selected
end

-- ============================================================================
-- 各技能 Execute 实现
-- ============================================================================

--- 1. 暗影束缚: 禁锢随机英雄
local function ExecShackle(sk)
    local cfg = sk.params
    local targets = SelectTowers(cfg.count or 2)
    for _, tower in ipairs(targets) do
        if Debuff.Apply(tower, "shackle") then
            tower.shackleTimer = cfg.duration or 3.0
            skillState.shackledTowers[#skillState.shackledTowers + 1] = {
                towerId = tower.id,
                timer   = cfg.duration or 3.0,
            }
        end
    end
    State.skillFlash = { type = "generic_shackle", timer = 0.5 }
end

--- 2. 灵魂吞噬: 全体攻击力降低
local function ExecDevour(sk)
    local cfg = sk.params
    local reduction = cfg.atkReduction or 0.25
    local duration  = cfg.duration or 5.0
    for _, tower in ipairs(State.towers) do
        -- 使用 silence debuff 的 timer 字段实现临时攻击力减益
        -- 实际通过 debuffs 表实现
        tower.debuffs = tower.debuffs or {}
        tower.debuffs[#tower.debuffs + 1] = {
            id     = "devour",
            stat   = "attack",
            value  = reduction,
            mode   = "pct",
            remain = duration,
        }
    end
    skillState.devourTimer = duration
    State.skillFlash = { type = "generic_devour", timer = 0.5 }
end

--- 3. 虚空脉冲: 随机区域 AOE 眩晕
local function ExecPulse(sk)
    local cfg = sk.params
    local stunTime = cfg.stunTime or 1.0
    -- 随机选 1 个格子作为中心
    local gridCols = Config.GRID_COLS or 5
    local gridRows = Config.HERO_ROWS or 2
    local cx = math.random(1, gridCols)
    local cy = math.random(1, gridRows)
    local radius = cfg.radius or 1

    -- 影响范围内的英雄
    for _, tower in ipairs(State.towers) do
        local col = tower.col or 0
        local row = tower.row or 0
        local dx = math.abs(col - cx)
        local dy = math.abs(row - cy)
        if dx <= radius and dy <= radius then
            Debuff.Apply(tower, "silence", { duration = stunTime })
        end
    end

    -- 记录脉冲可视化数据
    skillState.pulseEffect = {
        col    = cx,
        row    = cy,
        radius = radius,
        timer  = 1.0,
    }
    State.skillFlash = { type = "generic_pulse", timer = 0.5 }
end

--- 4. 黑暗庇护: Boss 减伤护盾
local function ExecShield(sk)
    local cfg = sk.params
    skillState.shieldActive = true
    skillState.shieldTimer  = cfg.duration or 4.0
    skillState.shieldReduction = cfg.reduction or 0.50

    -- 设置 Boss 减伤标记
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isBoss then
            e.damageReduction = (e.damageReduction or 0) + skillState.shieldReduction
            break
        end
    end
    State.skillFlash = { type = "generic_shield", timer = 0.5 }
end

--- 5. 亡灵召唤: 召唤小怪
local function ExecSummon(sk)
    local cfg = sk.params
    local count  = cfg.count or 3
    local hpMult = cfg.hpMult or 1.5
    local currentWave = State.currentWave or 1

    -- 基于当前关卡构建小怪定义
    local stageNum = State.stageNum or 1
    local baseDef = Config.BuildNormalDef(stageNum)
    if baseDef then
        baseDef.baseHP = baseDef.baseHP * hpMult
        baseDef.id = "summoned_minion"
        baseDef.name = "亡灵仆从"
        baseDef.reward = 0
        baseDef.isDungeonEnemy = true
        for _ = 1, count do
            Enemy.CreateEnemyFromDef(baseDef, currentWave, 1.0, 1.0, false, {})
        end
    end
    State.skillFlash = { type = "generic_summon", timer = 0.5 }
end

--- 6. 诅咒领域: 全体攻速降低
local function ExecCurse(sk)
    local cfg = sk.params
    local reduction = cfg.spdReduction or 0.20
    local duration  = cfg.duration or 4.0
    for _, tower in ipairs(State.towers) do
        tower.debuffs = tower.debuffs or {}
        tower.debuffs[#tower.debuffs + 1] = {
            id     = "curse",
            stat   = "speed",
            value  = reduction,
            mode   = "pct",
            remain = duration,
        }
    end
    skillState.curseTimer = duration
    State.skillFlash = { type = "generic_curse", timer = 0.5 }
end

-- 执行分发表
local EXEC_TABLE = {
    shackle = ExecShackle,
    devour  = ExecDevour,
    pulse   = ExecPulse,
    shield  = ExecShield,
    summon  = ExecSummon,
    curse   = ExecCurse,
}

-- ============================================================================
-- 状态机驱动
-- ============================================================================

local function TransitionTo(phase)
    skillState.phase = phase
    skillState.phaseTimer = 0
end

local function UpdateStateMachine(dt)
    if not skillState or not active then return end

    -- 场上没有存活 Boss 时，技能不运作（试炼塔等副本前几波是小怪）
    local hasBoss = false
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isBoss then
            hasBoss = true
            break
        end
    end
    if not hasBoss then
        -- 没有 Boss 时重置到 IDLE，避免 Boss 死后技能卡在中间状态
        if skillState.phase ~= PHASE_IDLE then
            TransitionTo(PHASE_IDLE)
            if State.genericBossSkill then
                State.genericBossSkill.casting = nil
            end
        end
        return
    end

    skillState.phaseTimer = skillState.phaseTimer + dt

    -- 更新所有技能 CD
    for _, sk in ipairs(skillState.skillList) do
        if sk.cdTimer > 0 then
            sk.cdTimer = sk.cdTimer - dt
        end
    end

    local phase = skillState.phase

    -- ======== IDLE ========
    if phase == PHASE_IDLE then
        local next = PickNextSkill()
        if next then
            skillState.currentSkill = next
            TransitionTo(PHASE_CASTING)
            -- 更新渲染状态
            State.genericBossSkill = State.genericBossSkill or {}
            State.genericBossSkill.casting = {
                phase = PHASE_CASTING,
                color = next.color,
                timer = 0,
                name  = next.name,
            }
            -- Boss 技能名横幅
            if not State.bossIntro then
                State.bossIntro = {
                    timer    = 0,
                    duration = 2.0,
                    name     = next.name,
                }
            end
        end

    -- ======== CASTING ========
    elseif phase == PHASE_CASTING then
        local t = skillState.phaseTimer
        if State.genericBossSkill and State.genericBossSkill.casting then
            State.genericBossSkill.casting.timer = t
        end
        if t >= CAST_BUILDUP + CAST_DELAY then
            TransitionTo(PHASE_EXECUTE)
        end

    -- ======== EXECUTE ========
    elseif phase == PHASE_EXECUTE then
        if skillState.phaseTimer <= 0.01 then
            -- 首帧执行技能效果
            local sk = skillState.currentSkill
            if sk then
                local fn = EXEC_TABLE[sk.id]
                if fn then fn(sk) end
                -- 重置 CD
                sk.cdTimer = sk.params.interval or 15.0
            end
        end
        if State.genericBossSkill and State.genericBossSkill.casting then
            State.genericBossSkill.casting.phase = PHASE_EXECUTE
            State.genericBossSkill.casting.timer = skillState.phaseTimer
        end
        if skillState.phaseTimer >= EXEC_DURATION + RESULT_DISPLAY then
            TransitionTo(PHASE_COOLDOWN)
            if State.genericBossSkill then
                State.genericBossSkill.casting = nil
            end
        end

    -- ======== COOLDOWN ========
    elseif phase == PHASE_COOLDOWN then
        if skillState.phaseTimer >= COOLDOWN_DELAY then
            TransitionTo(PHASE_IDLE)
            skillState.currentSkill = nil
        end
    end
end

-- ============================================================================
-- Debuff 持续管理（每帧 tick）
-- ============================================================================

local function UpdateDebuffs(dt)
    if not skillState then return end

    -- 束缚倒计时
    for i = #skillState.shackledTowers, 1, -1 do
        local s = skillState.shackledTowers[i]
        s.timer = s.timer - dt
        -- 同步到 tower
        for _, tower in ipairs(State.towers) do
            if tower.id == s.towerId then
                tower.shackleTimer = s.timer
                break
            end
        end
        if s.timer <= 0 then
            -- 移除束缚
            for _, tower in ipairs(State.towers) do
                if tower.id == s.towerId then
                    Debuff.Clear(tower, "shackle")
                    tower.shackleTimer = 0
                    break
                end
            end
            table.remove(skillState.shackledTowers, i)
        end
    end

    -- 吞噬 debuff 倒计时
    if skillState.devourTimer then
        skillState.devourTimer = skillState.devourTimer - dt
        if skillState.devourTimer <= 0 then
            -- 清除所有 devour debuff
            for _, tower in ipairs(State.towers) do
                if tower.debuffs then
                    for j = #tower.debuffs, 1, -1 do
                        if tower.debuffs[j].id == "devour" then
                            table.remove(tower.debuffs, j)
                        end
                    end
                end
            end
            skillState.devourTimer = nil
        end
    end

    -- 诅咒 debuff 倒计时
    if skillState.curseTimer then
        skillState.curseTimer = skillState.curseTimer - dt
        if skillState.curseTimer <= 0 then
            for _, tower in ipairs(State.towers) do
                if tower.debuffs then
                    for j = #tower.debuffs, 1, -1 do
                        if tower.debuffs[j].id == "curse" then
                            table.remove(tower.debuffs, j)
                        end
                    end
                end
            end
            skillState.curseTimer = nil
        end
    end

    -- 护盾倒计时
    if skillState.shieldActive then
        skillState.shieldTimer = skillState.shieldTimer - dt
        if skillState.shieldTimer <= 0 then
            -- 移除 Boss 减伤
            for _, e in ipairs(State.enemies) do
                if e.alive and e.isBoss then
                    e.damageReduction = math.max(0,
                        (e.damageReduction or 0) - skillState.shieldReduction)
                    break
                end
            end
            skillState.shieldActive = false
            skillState.shieldReduction = 0
        end
    end

    -- 脉冲效果倒计时
    if skillState.pulseEffect then
        skillState.pulseEffect.timer = skillState.pulseEffect.timer - dt
        if skillState.pulseEffect.timer <= 0 then
            skillState.pulseEffect = nil
        end
    end

    -- 更新渲染数据
    if State.genericBossSkill then
        State.genericBossSkill.shieldActive = skillState.shieldActive
        State.genericBossSkill.shieldTimer  = skillState.shieldTimer
        State.genericBossSkill.pulseEffect  = skillState.pulseEffect
        State.genericBossSkill.devourActive = skillState.devourTimer and skillState.devourTimer > 0
        State.genericBossSkill.curseActive  = skillState.curseTimer and skillState.curseTimer > 0
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化通用技能系统
---@param mechanics table { [skillId] = { interval, count, duration, ... , _id, _name, _color, _desc } }
function GS.Init(mechanics)
    if not mechanics or not next(mechanics) then
        active = false
        return
    end

    local skillList = {}
    for skillId, params in pairs(mechanics) do
        skillList[#skillList + 1] = {
            id       = params._id or skillId,
            name     = params._name or skillId,
            color    = params._color or { 200, 50, 50 },
            desc     = params._desc or "",
            params   = params,
            cdTimer  = params.interval or 15.0,  -- 初始 CD = interval（开局延迟）
        }
    end

    skillState = {
        skillList      = skillList,
        phase          = PHASE_IDLE,
        phaseTimer     = 0,
        currentSkill   = nil,
        shackledTowers = {},
        devourTimer    = nil,
        curseTimer     = nil,
        shieldActive   = false,
        shieldTimer    = 0,
        shieldReduction = 0,
        pulseEffect    = nil,
    }

    State.genericBossSkill = {}
    active = true
    print("[GenericSkills] Init OK, skills: " .. #skillList)
end

--- 每帧更新
---@param dt number
function GS.Update(dt)
    if not active then return end
    UpdateStateMachine(dt)
    UpdateDebuffs(dt)
end

--- 清理
function GS.Cleanup()
    if not active then return end

    -- 清除所有残留 debuff
    if skillState then
        for i = #skillState.shackledTowers, 1, -1 do
            local s = skillState.shackledTowers[i]
            for _, tower in ipairs(State.towers) do
                if tower.id == s.towerId then
                    Debuff.Clear(tower, "shackle")
                    tower.shackleTimer = 0
                    break
                end
            end
        end
        -- 清除 devour/curse debuffs
        for _, tower in ipairs(State.towers) do
            if tower.debuffs then
                for j = #tower.debuffs, 1, -1 do
                    local db = tower.debuffs[j]
                    if db.id == "devour" or db.id == "curse" then
                        table.remove(tower.debuffs, j)
                    end
                end
            end
        end
        -- 移除 Boss 护盾
        if skillState.shieldActive then
            for _, e in ipairs(State.enemies) do
                if e.alive and e.isBoss then
                    e.damageReduction = math.max(0,
                        (e.damageReduction or 0) - skillState.shieldReduction)
                    break
                end
            end
        end
    end

    State.genericBossSkill = nil
    skillState = nil
    active = false
    print("[GenericSkills] Cleanup")
end

--- 是否激活中
---@return boolean
function GS.IsActive()
    return active
end

--- 获取下一个将要释放的技能信息（用于 UI 预告）
---@return table|nil { name, color, cd }
function GS.GetNextSkillInfo()
    if not active or not skillState then return nil end
    local bestCd = math.huge
    local bestSk = nil
    for _, sk in ipairs(skillState.skillList) do
        if sk.cdTimer < bestCd then
            bestCd = sk.cdTimer
            bestSk = sk
        end
    end
    if bestSk then
        return {
            name  = bestSk.name,
            color = bestSk.color,
            cd    = math.max(0, bestSk.cdTimer),
        }
    end
    return nil
end

--- 获取束缚中的塔列表
---@return table[]
function GS.GetShackledTowers()
    if not skillState then return {} end
    return skillState.shackledTowers
end

return GS
