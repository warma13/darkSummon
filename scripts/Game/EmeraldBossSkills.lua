-- Game/EmeraldBossSkills.lua
-- 翠影秘境 BOSS 技能系统：荆棘禁锢、沉寂领域、自然衰竭
-- 状态机驱动：IDLE -> CASTING -> EXECUTE -> COOLDOWN -> IDLE
-- 翎嫣专属副本：三技能分别被翎嫣的翠意庇护(免疫束缚+沉默)和自然馈赠(buff对冲)克制

local State    = require("Game.State")
local Tower    = require("Game.Tower")
local Enemy    = require("Game.Enemy")
local Debuff   = require("Game.Debuff")
local Toast    = require("Game.Toast")
local Grid     = require("Game.Grid")
local Renderer = require("Game.Renderer")

local EBS = {}

-- ============================================================================
-- 常量
-- ============================================================================

local PHASE_IDLE     = "idle"
local PHASE_CASTING  = "casting"
local PHASE_EXECUTE  = "execute"
local PHASE_COOLDOWN = "cooldown"

-- 演出时间轴（秒）
local CAST_BUILDUP   = 0.8   -- 描边+抖动阶段
local CAST_DELAY     = 0.4   -- 施法姿势保持
local EXEC_DURATION  = 0.6   -- 技能释放特效
local RESULT_DISPLAY = 0.5   -- 飘字展示
local COOLDOWN_DELAY = 0.3   -- 恢复过渡

local TOTAL_CAST     = CAST_BUILDUP + CAST_DELAY       -- 1.2s
local TOTAL_EXEC     = EXEC_DURATION + RESULT_DISPLAY   -- 1.1s
local TOTAL_STUN     = TOTAL_CAST + TOTAL_EXEC          -- 2.3s

-- 技能颜色
local SKILL_COLORS = {
    shackle = { 40, 160, 60 },    -- 深绿（荆棘）
    silence = { 140, 50, 200 },   -- 紫色（沉默）
    decay   = { 100, 140, 40 },   -- 暗黄绿（衰竭）
}

-- 技能名称
local SKILL_NAMES = {
    shackle = "荆棘禁锢",
    silence = "沉寂领域",
    decay   = "自然衰竭",
}

-- ============================================================================
-- 状态
-- ============================================================================

---@type table|nil
local skillState = nil

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取塔的屏幕坐标
---@param tower table
---@return number x, number y
local function TowerScreenPos(tower)
    return Grid.CellToScreen(tower.col, tower.row, Renderer.gridOffsetX, Renderer.gridOffsetY)
end

--- 查找存活的翠影 BOSS
---@return table|nil
local function FindBoss()
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isEmeraldDungeon and e.isBoss then
            return e
        end
    end
    return nil
end

--- 生成粒子爆发
---@param cx number 中心X
---@param cy number 中心Y
---@param color table {r,g,b}
---@param count number 粒子数
---@param spread number 扩散范围
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

--- 按星级权重选择多个塔（与 WorldBossSkills 逻辑一致）
--- 高星塔权重更高，优先被选中
---@param count number 需要选择的目标数
---@return table[] targets 被选中的塔列表
local function SelectTargetsByWeight(count)
    -- 星级权重表（0-based star → weight）
    local STAR_WEIGHTS = { 1, 2, 4, 8, 16 }

    -- 排除已被束缚的塔和翎嫣自身（support 类不选）
    local shackledSet = {}
    for _, s in ipairs(skillState.shackledTowers) do
        shackledSet[s.towerId] = true
    end

    local candidates = {}
    local totalWeight = 0
    for _, tower in ipairs(State.towers) do
        if not shackledSet[tower.id] then
            local starIdx = math.min((tower.star or 0) + 1, #STAR_WEIGHTS)
            local w = STAR_WEIGHTS[starIdx]
            candidates[#candidates + 1] = { tower = tower, weight = w }
            totalWeight = totalWeight + w
        end
    end

    if #candidates == 0 or totalWeight <= 0 then return {} end

    local selected = {}
    local selectedSet = {}
    local remaining = math.min(count, #candidates)

    for _ = 1, remaining do
        -- 加权随机选择
        local roll = math.random() * totalWeight
        local acc = 0
        for ci, c in ipairs(candidates) do
            if not selectedSet[ci] then
                acc = acc + c.weight
                if roll <= acc then
                    selected[#selected + 1] = c.tower
                    selectedSet[ci] = true
                    totalWeight = totalWeight - c.weight
                    break
                end
            end
        end
    end

    return selected
end

-- ============================================================================
-- 技能效果执行
-- ============================================================================

--- 执行荆棘禁锢（束缚高星塔）
local function ExecuteShackle(boss)
    local cfg = skillState.mechanics.shackle
    if not cfg then return end

    local targets = SelectTargetsByWeight(cfg.targets)
    local hitCount = 0

    for _, tower in ipairs(targets) do
        -- 通过 Debuff 系统施加（自动检查翎嫣翠意庇护免疫）
        if Debuff.Apply(tower, "shackle") then
            tower.shackleTimer = cfg.duration
            skillState.shackledTowers[#skillState.shackledTowers + 1] = {
                towerId = tower.id,
                timer = cfg.duration,
            }
            hitCount = hitCount + 1

            -- 飘字
            local towerName = tower.typeDef and tower.typeDef.name or "英雄"
            local sx, sy = TowerScreenPos(tower)
            State.AddFloatingText({
                text = "禁锢 " .. string.format("%.1f", cfg.duration) .. "s",
                x = sx,
                y = sy - 20,
                vx = (math.random() - 0.5) * 20,
                vy = -40 - math.random() * 15,
                life = 1.0,
                color = { SKILL_COLORS.shackle[1], SKILL_COLORS.shackle[2], SKILL_COLORS.shackle[3], 255 },
                fontSize = 12,
            })

            -- 荆棘粒子飞向目标塔
            local tx, ty = sx, sy
            for j = 1, 6 do
                local t = j / 6
                State.AddParticle({
                    x = boss.x + (tx - boss.x) * t + (math.random() - 0.5) * 10,
                    y = boss.y + (ty - boss.y) * t + (math.random() - 0.5) * 10,
                    vx = (math.random() - 0.5) * 15,
                    vy = -10 - math.random() * 15,
                    life = 0.5 + math.random() * 0.4,
                    maxLife = 0.9,
                    color = { 50 + math.random(0, 30), 140 + math.random(0, 60), 40 + math.random(0, 30) },
                    size = 2.5 + math.random() * 2,
                })
            end

            print("[EmeraldBossSkills] Shackle: " .. towerName .. " for " .. cfg.duration .. "s")
        else
            -- 免疫
            local towerName = tower.typeDef and tower.typeDef.name or "英雄"
            local ix, iy = TowerScreenPos(tower)
            State.AddFloatingText({
                text = "免疫！",
                x = ix,
                y = iy - 20,
                vx = 0, vy = -45,
                life = 0.8,
                color = { 100, 255, 160, 255 },
                fontSize = 13,
            })
            print("[EmeraldBossSkills] " .. towerName .. " immune to shackle")
        end
    end

    -- 全屏闪光
    State.skillFlash = { type = "emerald_shackle", timer = 0.5 }

    -- BOSS 周围绿色粒子
    BurstParticles(boss.x, boss.y, SKILL_COLORS.shackle, 15, 35)

    print("[EmeraldBossSkills] Shackle cast, targets=" .. cfg.targets .. " hit=" .. hitCount)
end

--- 执行沉寂领域（全场沉默）
local function ExecuteSilence(boss)
    local cfg = skillState.mechanics.silence
    if not cfg then return end

    local hitCount = 0
    for _, tower in ipairs(State.towers) do
        local sx, sy = TowerScreenPos(tower)
        if Debuff.Apply(tower, "silence", { duration = cfg.duration }) then
            hitCount = hitCount + 1
            State.AddFloatingText({
                text = "沉默 " .. string.format("%.1f", cfg.duration) .. "s",
                x = sx,
                y = sy - 20,
                vx = (math.random() - 0.5) * 30,
                vy = -40 - math.random() * 20,
                life = 1.0,
                color = { SKILL_COLORS.silence[1], SKILL_COLORS.silence[2], SKILL_COLORS.silence[3], 255 },
                fontSize = 12,
            })
        else
            -- 免疫
            State.AddFloatingText({
                text = "免疫！",
                x = sx,
                y = sy - 20,
                vx = 0, vy = -45,
                life = 0.8,
                color = { 100, 255, 160, 255 },
                fontSize = 13,
            })
        end
    end

    -- 全屏闪光
    State.skillFlash = { type = "emerald_silence", timer = 0.5 }

    -- 冲击环数据（渲染层读取）
    State.emeraldBossSkill.ringRadius = 0
    State.emeraldBossSkill.ringMaxRadius = 200
    State.emeraldBossSkill.ringTimer = 0
    State.emeraldBossSkill.ringDuration = 0.5
    State.emeraldBossSkill.ringX = boss.x
    State.emeraldBossSkill.ringY = boss.y

    -- BOSS 周围紫色粒子
    BurstParticles(boss.x, boss.y, SKILL_COLORS.silence, 15, 30)

    print("[EmeraldBossSkills] Silence cast, duration=" .. cfg.duration .. " hit=" .. hitCount)
end

--- 执行自然衰竭（攻击/攻速削弱，支持 persistent/stackable/stackMode 配置）
local function ExecuteDecay(boss)
    local cfg = skillState.mechanics.decay
    if not cfg then return end

    -- ── 默认值 ──
    local persistent = cfg.persistent ~= false            -- 默认持久
    local stackable  = cfg.stackable  ~= false            -- 默认可叠加
    local stackMode  = cfg.stackMode  or "additive"       -- 默认累加
    local dur        = persistent and math.huge or (cfg.duration or 15)

    -- ── 计算本次 debuff 数值 ──
    local newAtk = cfg.atkDebuff
    local newSpd = cfg.spdDebuff
    local totalAtk, totalSpd

    if stackable then
        if stackMode == "additive" then
            -- 累加模式：每次叠加 atkDebuff/spdDebuff，受 cap 限制
            totalAtk = math.min((skillState.decayAtkTotal or 0) + newAtk, cfg.atkCap)
            totalSpd = math.min((skillState.decaySpdTotal or 0) + newSpd, cfg.spdCap)
        elseif stackMode == "max" then
            -- 取大模式：取当前值与新值中较大者
            totalAtk = math.min(math.max(skillState.decayAtkTotal or 0, newAtk), cfg.atkCap)
            totalSpd = math.min(math.max(skillState.decaySpdTotal or 0, newSpd), cfg.spdCap)
        else  -- "refresh"
            -- 刷新模式：数值不叠加，仅刷新持续时间
            totalAtk = skillState.decayAtkTotal or newAtk
            totalSpd = skillState.decaySpdTotal or newSpd
        end
    else
        -- 不可叠加：只用首次值，后续仅刷新持续时间
        totalAtk = skillState.decayAtkTotal or newAtk
        totalSpd = skillState.decaySpdTotal or newSpd
    end

    skillState.decayAtkTotal = totalAtk
    skillState.decaySpdTotal = totalSpd

    -- ── 施加 debuff ──
    for _, tower in ipairs(State.towers) do
        Tower.ApplyDebuff(tower, "emerald_decay_atk", "attack", totalAtk, "pct", dur)
        Tower.ApplyDebuff(tower, "emerald_decay_spd", "speed",  totalSpd, "pct", dur)
        local sx, sy = TowerScreenPos(tower)
        -- 攻击削弱飘字
        State.AddFloatingText({
            text = "攻击-" .. math.floor(totalAtk * 100) .. "%",
            x = sx - 10,
            y = sy - 20,
            vx = -15 - math.random() * 10,
            vy = -40 - math.random() * 20,
            life = 1.2,
            color = { SKILL_COLORS.decay[1], SKILL_COLORS.decay[2], SKILL_COLORS.decay[3], 255 },
            fontSize = 12,
        })
        -- 攻速削弱飘字
        State.AddFloatingText({
            text = "攻速-" .. math.floor(totalSpd * 100) .. "%",
            x = sx + 10,
            y = sy - 10,
            vx = 15 + math.random() * 10,
            vy = -35 - math.random() * 20,
            life = 1.2,
            color = { 80, 120, 60, 255 },
            fontSize = 11,
        })
    end

    -- 全屏闪光
    State.skillFlash = { type = "emerald_decay", timer = 0.5 }

    -- BOSS 周围暗绿粒子
    BurstParticles(boss.x, boss.y, SKILL_COLORS.decay, 20, 40)

    -- 战场散布衰竭雾气粒子
    for i = 1, 12 do
        State.AddParticle({
            x = (Renderer and Renderer.gridOffsetX or 0) + math.random() * 300,
            y = (Renderer and Renderer.gridOffsetY or 0) + math.random() * 200,
            vx = (math.random() - 0.5) * 10,
            vy = -5 - math.random() * 10,
            life = 1.5 + math.random() * 1.0,
            maxLife = 2.5,
            color = { 90, 130, 50 },
            size = 5 + math.random() * 4,
        })
    end

    skillState.decayCastCount = (skillState.decayCastCount or 0) + 1
    print("[EmeraldBossSkills] Decay cast #" .. skillState.decayCastCount
        .. " atkDebuff=" .. totalAtk .. " spdDebuff=" .. totalSpd)
end

-- ============================================================================
-- 技能选择（优先级：沉寂领域 > 荆棘禁锢 > 自然衰竭）
-- ============================================================================

local function SelectSkill()
    local m = skillState.mechanics

    -- 沉寂领域（最高优先级）
    if m.silence and skillState.silenceCd <= 0 then
        return "silence"
    end

    -- 荆棘禁锢
    if m.shackle and skillState.shackleCd <= 0 then
        return "shackle"
    end

    -- 自然衰竭
    if m.decay and skillState.decayCd <= 0 then
        return "decay"
    end

    return nil
end

-- ============================================================================
-- 束缚管理（与 WorldBossSkills 一致的模式）
-- ============================================================================

local function RemoveShackle(towerId)
    for _, tower in ipairs(State.towers) do
        if tower.id == towerId then
            Debuff.Clear(tower, "shackle")
            tower.shackleTimer = 0
            break
        end
    end
end

local function UpdateShackleTimers(dt)
    for i = #skillState.shackledTowers, 1, -1 do
        local s = skillState.shackledTowers[i]
        s.timer = s.timer - dt
        -- 同步塔上的计时器
        for _, tower in ipairs(State.towers) do
            if tower.id == s.towerId then
                tower.shackleTimer = s.timer
                break
            end
        end
        if s.timer <= 0 then
            RemoveShackle(s.towerId)
            table.remove(skillState.shackledTowers, i)
        end
    end
end

-- ============================================================================
-- 状态机
-- ============================================================================

--- 进入 CASTING 阶段
local function EnterCasting(boss, skillId)
    skillState.activeSkill = skillId
    skillState.phase = PHASE_CASTING
    skillState.phaseTimer = 0

    -- 暂停 BOSS 移动
    boss.stunTimer = math.max(boss.stunTimer or 0, TOTAL_STUN + 0.5)

    -- 设置渲染状态（描边+抖动）
    local c = SKILL_COLORS[skillId]
    State.emeraldBossSkill = {
        type = skillId,
        phase = PHASE_CASTING,
        timer = 0,
        bossId = boss.id,
        color = c,
    }

    print("[EmeraldBossSkills] Casting: " .. SKILL_NAMES[skillId])
end

--- 进入 EXECUTE 阶段
local function EnterExecute(boss, skillId)
    skillState.phase = PHASE_EXECUTE
    skillState.phaseTimer = 0

    -- 切换精灵图到攻击帧
    boss.castingFrame = 2

    -- 更新渲染状态
    if State.emeraldBossSkill then
        State.emeraldBossSkill.phase = PHASE_EXECUTE
        State.emeraldBossSkill.timer = 0
    end

    -- 执行技能效果
    if skillId == "shackle" then
        ExecuteShackle(boss)
    elseif skillId == "silence" then
        ExecuteSilence(boss)
    elseif skillId == "decay" then
        ExecuteDecay(boss)
    end
end

--- 进入 COOLDOWN 阶段
local function EnterCooldown(boss, skillId)
    skillState.phase = PHASE_COOLDOWN
    skillState.phaseTimer = 0

    -- 清理施法帧
    boss.castingFrame = nil

    -- 设置技能 CD
    local m = skillState.mechanics
    if skillId == "shackle" and m.shackle then
        skillState.shackleCd = m.shackle.interval
    elseif skillId == "silence" and m.silence then
        skillState.silenceCd = m.silence.interval
    elseif skillId == "decay" and m.decay then
        skillState.decayCd = m.decay.interval
    end
end

--- 回到 IDLE
local function EnterIdle()
    skillState.activeSkill = nil
    skillState.phase = PHASE_IDLE
    skillState.phaseTimer = 0

    -- 清除渲染状态
    State.emeraldBossSkill = nil
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化（BattleManager.onStart 调用）
---@param mechanics table { shackle, silence, decay }
function EBS.Init(mechanics)
    if not mechanics then return end
    skillState = {
        battleTimer = 0,
        phase = PHASE_IDLE,
        activeSkill = nil,
        phaseTimer = 0,
        mechanics = mechanics,

        -- 技能 CD（首次延迟减半，让技能更快登场）
        shackleCd = mechanics.shackle and (mechanics.shackle.interval * 0.5) or 999,
        silenceCd = mechanics.silence and (mechanics.silence.interval * 0.5) or 999,
        decayCd   = mechanics.decay   and (mechanics.decay.interval   * 0.5) or 999,

        -- 束缚追踪
        shackledTowers = {},

        -- 自然衰竭累计
        decayAtkTotal = 0,
        decaySpdTotal = 0,
        decayCastCount = 0,
    }
    print("[EmeraldBossSkills] Initialized"
        .. " shackle.interval=" .. tostring(mechanics.shackle and mechanics.shackle.interval)
        .. " silence.interval=" .. tostring(mechanics.silence and mechanics.silence.interval)
        .. " decay.interval=" .. tostring(mechanics.decay and mechanics.decay.interval))
end

--- 每帧更新
---@param dt number
function EBS.Update(dt)
    if not skillState then return end

    skillState.battleTimer = skillState.battleTimer + dt

    local boss = FindBoss()
    if not boss then
        -- BOSS 尚未生成（仍在生成队列中），跳过本帧
        -- 仅当 BOSS 曾经出现过又消失时才清理（说明 BOSS 已死亡）
        if skillState.bossSpawned then
            EBS.Cleanup()
        end
        return
    end
    -- 标记 BOSS 已出场
    skillState.bossSpawned = true

    -- ======== 束缚计时器更新（独立于技能阶段） ========
    UpdateShackleTimers(dt)

    -- ======== 状态机 ========

    if skillState.phase == PHASE_IDLE then
        -- Tick CD
        skillState.shackleCd = skillState.shackleCd - dt
        skillState.silenceCd = skillState.silenceCd - dt
        skillState.decayCd   = skillState.decayCd - dt

        -- 选择技能
        local skillId = SelectSkill()
        if skillId then
            EnterCasting(boss, skillId)
        end

    elseif skillState.phase == PHASE_CASTING then
        skillState.phaseTimer = skillState.phaseTimer + dt

        -- 0.3s：触发技能名横幅
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

        -- 0.8s：切换施法帧
        if skillState.phaseTimer >= CAST_BUILDUP and not skillState.castFrameSet then
            skillState.castFrameSet = true
            boss.castingFrame = 1
        end

        -- 更新渲染计时器
        if State.emeraldBossSkill then
            State.emeraldBossSkill.timer = skillState.phaseTimer
        end

        -- CAST_BUILDUP + CAST_DELAY 后进入 EXECUTE
        if skillState.phaseTimer >= TOTAL_CAST then
            skillState.bannerShown = nil
            skillState.castFrameSet = nil
            EnterExecute(boss, skillState.activeSkill)
        end

    elseif skillState.phase == PHASE_EXECUTE then
        skillState.phaseTimer = skillState.phaseTimer + dt

        -- 更新沉默冲击环
        if State.emeraldBossSkill and State.emeraldBossSkill.ringDuration then
            State.emeraldBossSkill.ringTimer = (State.emeraldBossSkill.ringTimer or 0) + dt
            local t = State.emeraldBossSkill.ringTimer / State.emeraldBossSkill.ringDuration
            State.emeraldBossSkill.ringRadius = t * (State.emeraldBossSkill.ringMaxRadius or 200)
        end

        -- 更新渲染计时器
        if State.emeraldBossSkill then
            State.emeraldBossSkill.timer = skillState.phaseTimer
        end

        -- EXECUTE 结束 → COOLDOWN
        if skillState.phaseTimer >= TOTAL_EXEC then
            EnterCooldown(boss, skillState.activeSkill)
        end

    elseif skillState.phase == PHASE_COOLDOWN then
        skillState.phaseTimer = skillState.phaseTimer + dt

        if skillState.phaseTimer >= COOLDOWN_DELAY then
            EnterIdle()
        end
    end
end

--- 清理（战斗结束时调用）
function EBS.Cleanup()
    if not skillState then return end

    -- 解除所有束缚
    for _, s in ipairs(skillState.shackledTowers) do
        RemoveShackle(s.towerId)
    end

    -- 清除英雄塔上的衰竭 debuff
    for _, tower in ipairs(State.towers) do
        if tower.debuffs then
            local i = 1
            while i <= #tower.debuffs do
                local db = tower.debuffs[i]
                if db.id == "emerald_decay_atk" or db.id == "emerald_decay_spd" then
                    table.remove(tower.debuffs, i)
                else
                    i = i + 1
                end
            end
        end
    end

    -- 清除 BOSS 施法状态
    local boss = FindBoss()
    if boss then
        boss.castingFrame = nil
    end

    -- 清除渲染状态
    State.emeraldBossSkill = nil

    skillState = nil
    print("[EmeraldBossSkills] Cleaned up")
end

--- 是否激活
---@return boolean
function EBS.IsActive()
    return skillState ~= nil
end

--- 获取被束缚的英雄列表（供外部查询）
---@return table[] { towerId, timer }
function EBS.GetShackledTowers()
    return skillState and skillState.shackledTowers or {}
end

return EBS
