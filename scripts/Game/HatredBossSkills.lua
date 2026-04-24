-- Game/HatredBossSkills.lua
-- 憎恨之躯 BOSS 技能系统
-- 技能组：召唤精英、护盾+防御翻倍、嘲讽（攻速叠层降低）、3x3锁定降星（带韧性条可打断）
-- 状态机驱动：IDLE -> CASTING -> EXECUTE -> COOLDOWN -> IDLE

local Config   = require("Game.Config")
local State    = require("Game.State")
local Tower    = require("Game.Tower")
local Enemy    = require("Game.Enemy")
local Debuff   = require("Game.Debuff")
local Toast    = require("Game.Toast")
local Grid     = require("Game.Grid")
local Renderer = require("Game.Renderer")

local HBS = {}

-- ============================================================================
-- 常量
-- ============================================================================

local PHASE_IDLE     = "idle"
local PHASE_CASTING  = "casting"
local PHASE_EXECUTE  = "execute"
local PHASE_COOLDOWN = "cooldown"

-- 演出时间轴
local CAST_BUILDUP   = 0.6   -- 蓄力阶段
local CAST_DELAY     = 0.4   -- 施法姿势保持
local EXEC_DURATION  = 0.5   -- 技能释放特效
local RESULT_DISPLAY = 0.4   -- 飘字展示
local COOLDOWN_DELAY = 0.3   -- 恢复过渡

local TOTAL_CAST     = CAST_BUILDUP + CAST_DELAY
local TOTAL_EXEC     = EXEC_DURATION + RESULT_DISPLAY
local TOTAL_STUN     = TOTAL_CAST + TOTAL_EXEC

-- 技能颜色
local SKILL_COLORS = {
    summon      = { 255, 140, 60 },   -- 橙色（召唤）
    fortress    = { 80, 160, 255 },   -- 蓝色（护盾+防御）
    taunt       = { 200, 40, 40 },    -- 深红（嘲讽）
    star_crush  = { 180, 40, 220 },   -- 紫红（降星锁定）
    destruction = { 255, 20, 20 },    -- 纯红（毁灭）
}

-- 技能名称
local SKILL_NAMES = {
    summon      = "深渊召唤",
    fortress    = "憎恨壁垒",
    taunt       = "怨恨嘲讽",
    star_crush  = "毁灭践踏",
    destruction = "终焉毁灭",
}

-- ============================================================================
-- 状态
-- ============================================================================

---@type table|nil
local skillState = nil

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- 英雄放置区域（内部 6×5，排除外圈路径）
local PLACE_MIN_COL, PLACE_MAX_COL = 2, 7
local PLACE_MIN_ROW, PLACE_MAX_ROW = 2, 6

--- 获取塔的屏幕坐标
local function TowerScreenPos(tower)
    return Grid.CellToScreen(tower.col, tower.row, Renderer.gridOffsetX, Renderer.gridOffsetY)
end

--- 查找存活的憎恨之躯 BOSS
---@return table|nil
local function FindBoss()
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isHatredBoss then
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

--- 按星级权重选择目标塔
---@param count number 选择数量
---@param excludeIds table|nil 排除的 tower id 集合
---@return table[] targets
local function SelectTargetsByWeight(count, excludeIds)
    local STAR_WEIGHTS = { 1, 2, 4, 8, 16 }
    excludeIds = excludeIds or {}

    local candidates = {}
    local totalWeight = 0
    for _, tower in ipairs(State.towers) do
        if not excludeIds[tower.id] then
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

--- 收集 3x3 区域内的塔
---@param centerCol number 中心格列
---@param centerRow number 中心格行
---@return table[] towers 区域内的塔列表
local function GetTowersInArea(centerCol, centerRow)
    local result = {}
    for _, tower in ipairs(State.towers) do
        local dc = math.abs(tower.col - centerCol)
        local dr = math.abs(tower.row - centerRow)
        if dc <= 1 and dr <= 1 then
            result[#result + 1] = tower
        end
    end
    return result
end

-- ============================================================================
-- 技能 1: 深渊召唤 — 召唤精英怪
-- ============================================================================

local function ExecuteSummon(boss)
    local cfg = skillState.mechanics.summon
    if not cfg then return end

    skillState.summonCastCount = (skillState.summonCastCount or 0) + 1
    local castNum = skillState.summonCastCount
    local baseCount = cfg.baseCount or 1
    local count = math.min(baseCount + castNum - 1, cfg.maxCount or 10)

    -- 指数属性增长：每次召唤 statGrowth^(castNum-1) 倍
    local growth = cfg.statGrowth or 1.5
    local statMult = growth ^ (castNum - 1)

    -- 获取当前波次信息
    local currentWave = State.currentWave or 1
    local stageNum = math.max(1, math.floor(currentWave / Config.WAVES_PER_STAGE) + 1)

    -- 可用角色池
    local availRoles = { "infantry", "tank", "assassin" }

    -- 精英HP倍率
    local eliteHPMult = cfg.hpMult or 3.0
    local hpScale = cfg.hpScale or 1.0

    for i = 1, count do
        local roleId = availRoles[math.random(#availRoles)]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale * eliteHPMult * statMult
            def.baseDEF = (def.baseDEF or 0) * statMult
            def.speed = math.max(15, (def.speed or 50) + castNum * 2)
            def.isElite = true
            def.isDungeonEnemy = true

            -- 随机词缀
            local pool = {}
            for _, a in ipairs(Config.AFFIXES) do
                if a.tier <= 2 then pool[#pool + 1] = a end
            end
            local affix = #pool > 0 and pool[math.random(#pool)] or nil

            Enemy.CreateEnemyFromDef(def, currentWave, 1.0, 1.0, true, affix and { affix } or {})
        end
    end

    -- 全屏闪光
    State.skillFlash = { type = "hatred_summon", timer = 0.5 }

    -- BOSS 周围粒子
    BurstParticles(boss.x, boss.y, SKILL_COLORS.summon, 15, 35)

    Toast.Show("憎恨之躯召唤了" .. count .. "只精英怪！", SKILL_COLORS.summon)
    print(string.format("[HatredBoss] Summon cast #%d count=%d statMult=%.1f", castNum, count, statMult))
end

-- ============================================================================
-- 技能 2: 憎恨壁垒 — 获得护盾 + 防御翻倍
-- ============================================================================

local function ExecuteFortress(boss)
    local cfg = skillState.mechanics.fortress
    if not cfg then return end

    -- 防御永久翻倍（可无限叠加）
    local defMult = cfg.defMult or 2.0
    skillState.fortressCastCount = (skillState.fortressCastCount or 0) + 1
    boss.def = (boss.def or boss.baseDEF or 0) * defMult
    skillState.fortressActive = true

    -- 生成护盾（初始值随释放次数翻倍）
    local baseShield = cfg.baseShield or 2000
    local castCount = skillState.fortressCastCount
    local shieldHP = baseShield * (2 ^ (castCount - 1))
    boss.shield = (boss.shield or 0) + shieldHP

    -- 全屏闪光
    State.skillFlash = { type = "hatred_fortress", timer = 0.5 }

    -- BOSS 周围蓝色粒子
    BurstParticles(boss.x, boss.y, SKILL_COLORS.fortress, 20, 30)

    local stackCount = skillState.fortressCastCount
    Toast.Show("憎恨之躯获得护盾，防御×" .. defMult .. "（第" .. stackCount .. "层）", SKILL_COLORS.fortress)
    print(string.format("[HatredBoss] Fortress: shield=%.0f def=%.0f stacks=%d",
        shieldHP, boss.def, stackCount))
end

-- ============================================================================
-- 技能 3: 怨恨嘲讽 — 攻击它的英雄攻速降低，叠层持续降低
-- ============================================================================

local function ExecuteTaunt(boss)
    local cfg = skillState.mechanics.taunt
    if not cfg then return end

    local duration = cfg.duration or 10.0
    skillState.tauntActive = true
    skillState.tauntTimer = duration
    skillState.tauntStacks = {}  -- towerId → { stacks, lastHitTime }

    -- 全屏闪光
    State.skillFlash = { type = "hatred_taunt", timer = 0.5 }

    -- BOSS 周围红色粒子
    BurstParticles(boss.x, boss.y, SKILL_COLORS.taunt, 15, 30)

    Toast.Show("憎恨之躯释放了嘲讽，攻击它将降低攻速！", SKILL_COLORS.taunt)
    print("[HatredBoss] Taunt active for " .. duration .. "s")
end

--- 嘲讽被动：当英雄攻击 BOSS 时叠加攻速减益
--- 在 Combat 伤害结算后调用
---@param tower table 攻击的英雄塔
function HBS.OnTowerHitBoss(tower)
    if not skillState or not skillState.tauntActive then return end

    local cfg = skillState.mechanics.taunt
    if not cfg then return end

    local maxStacks = cfg.maxStacks or 5
    local spdPerStack = cfg.spdPerStack or 0.08  -- 每层降速 8%
    local stackDuration = cfg.stackDuration or 6.0

    local id = tower.id
    if not skillState.tauntStacks[id] then
        skillState.tauntStacks[id] = { stacks = 0 }
    end

    local info = skillState.tauntStacks[id]
    if info.stacks < maxStacks then
        info.stacks = info.stacks + 1
    end
    info.timer = stackDuration  -- 刷新持续时间

    -- 应用攻速 debuff（覆盖模式，而不是叠加多个独立 debuff）
    local totalReduction = info.stacks * spdPerStack
    Tower.ApplyDebuff(tower, "hatred_taunt_spd", "speed", totalReduction, "pct", stackDuration)

    -- 飘字（每 2 层提示一次，减少视觉噪音）
    if info.stacks % 2 == 1 or info.stacks == maxStacks then
        local sx, sy = TowerScreenPos(tower)
        State.AddFloatingText({
            text = "攻速-" .. math.floor(totalReduction * 100) .. "%",
            x = sx,
            y = sy - 20,
            vx = (math.random() - 0.5) * 20,
            vy = -35 - math.random() * 15,
            life = 0.8,
            color = { SKILL_COLORS.taunt[1], SKILL_COLORS.taunt[2], SKILL_COLORS.taunt[3], 255 },
            fontSize = 11,
        })
    end
end

-- ============================================================================
-- 技能 4: 毁灭践踏 — 3x3范围锁定，3秒后降星，带韧性条可打断
-- ============================================================================

--- 开始毁灭践踏预警
local function StartStarCrush(boss)
    local cfg = skillState.mechanics.star_crush
    if not cfg then return end

    -- 选择目标：优先高星英雄所在的3x3区域
    local targets = SelectTargetsByWeight(1, {})
    if #targets == 0 then return false end

    local center = targets[1]
    -- 约束中心使 3×3 范围不超出放置区域
    local centerCol = math.max(PLACE_MIN_COL + 1, math.min(PLACE_MAX_COL - 1, center.col))
    local centerRow = math.max(PLACE_MIN_ROW + 1, math.min(PLACE_MAX_ROW - 1, center.row))

    -- 检查区域内有多少塔
    local areaTowers = GetTowersInArea(centerCol, centerRow)
    if #areaTowers == 0 then return false end

    -- 韧性条与 BOSS 当前防御成正比（同终焉毁灭）
    local defDiv = cfg.toughnessDefDiv or 100000
    local minHits = cfg.toughnessMin or 20
    local toughnessHits = math.max(minHits, math.ceil((boss.def or 0) / defDiv))

    -- 设置锁定状态
    skillState.starCrush = {
        timer = cfg.channelTime or 3.0,         -- 吟唱时间
        totalTime = cfg.channelTime or 3.0,
        centerCol = centerCol,
        centerRow = centerRow,
        toughness = toughnessHits,               -- 韧性条当前值（剩余次数）
        maxToughness = toughnessHits,            -- 韧性条最大值（总需次数）
        interrupted = false,                      -- 是否被打断
        starReduction = cfg.starReduction or 1,   -- 降星数
    }

    -- BOSS 停止移动（设置眩晕以阻止移动）
    boss.stunTimer = math.max(boss.stunTimer or 0, (cfg.channelTime or 3.0) + 1.0)

    -- 设置渲染数据供 Renderer 读取
    State.hatredBossSkill = State.hatredBossSkill or {}
    State.hatredBossSkill.starCrush = {
        centerCol = centerCol,
        centerRow = centerRow,
        timer = cfg.channelTime or 3.0,
        totalTime = cfg.channelTime or 3.0,
        toughness = toughnessHits,
        maxToughness = toughnessHits,
    }

    -- 提示
    Toast.Show("⚠ 憎恨之躯正在凝聚毁灭之力！", { 255, 40, 40 })

    -- 区域高亮粒子
    local cx, cy = Grid.CellToScreen(centerCol, centerRow, Renderer.gridOffsetX, Renderer.gridOffsetY)
    BurstParticles(cx, cy, SKILL_COLORS.star_crush, 20, Config.CELL_SIZE * 1.5)

    print(string.format("[HatredBoss] StarCrush warning: center=(%d,%d) towers=%d toughnessHits=%d",
        centerCol, centerRow, #areaTowers, toughnessHits))

    return true
end

--- 对韧性条造成命中（英雄攻击 BOSS 时调用，每次攻击计 1 次）
function HBS.DamageToughness()
    if not skillState or not skillState.starCrush then return end
    if skillState.starCrush.interrupted then return end

    skillState.starCrush.toughness = skillState.starCrush.toughness - 1

    -- 同步渲染数据
    if State.hatredBossSkill and State.hatredBossSkill.starCrush then
        State.hatredBossSkill.starCrush.toughness = skillState.starCrush.toughness
    end

    -- 韧性条被打空 → 打断
    if skillState.starCrush.toughness <= 0 then
        skillState.starCrush.interrupted = true
        skillState.starCrush.toughness = 0

        -- 恢复 BOSS 移动
        local boss = FindBoss()
        if boss then
            boss.stunTimer = 0
        end

        -- 清除渲染数据
        if State.hatredBossSkill then
            State.hatredBossSkill.starCrush = nil
        end

        Toast.Show("憎恨之躯的吟唱被打断了！", { 100, 255, 100 })
        print("[HatredBoss] StarCrush interrupted! Toughness broken.")
    end
end

--- 执行毁灭践踏（韧性条未打断，吟唱完成）
local function ExecuteStarCrush(boss)
    local crush = skillState.starCrush
    if not crush or crush.interrupted then return end

    -- 引导完成，切到攻击帧
    boss.castingFrame = 2

    local centerCol = crush.centerCol
    local centerRow = crush.centerRow
    local reduction = crush.starReduction or 1

    -- 收集区域内的塔
    local areaTowers = GetTowersInArea(centerCol, centerRow)

    local hitCount = 0
    for _, tower in ipairs(areaTowers) do
        if tower.star > 1 then
            local oldStar = tower.star
            tower.star = math.max(1, tower.star - reduction)
            Tower.RecalcStats(tower)
            hitCount = hitCount + 1

            -- 飘字
            local sx, sy = TowerScreenPos(tower)
            State.AddFloatingText({
                text = tower.typeDef.name .. " ★-" .. reduction,
                x = sx,
                y = sy - 20,
                vx = (math.random() - 0.5) * 20,
                vy = -40 - math.random() * 15,
                life = 1.2,
                color = { SKILL_COLORS.star_crush[1], SKILL_COLORS.star_crush[2], SKILL_COLORS.star_crush[3], 255 },
                fontSize = 13,
            })

            print("[HatredBoss] StarCrush hit: " .. tower.typeDef.name
                .. " " .. oldStar .. "★ → " .. tower.star .. "★")
        end
    end

    -- 全屏闪光
    State.skillFlash = { type = "hatred_star_crush", timer = 0.6 }

    -- 区域爆炸粒子
    local cx, cy = Grid.CellToScreen(centerCol, centerRow, Renderer.gridOffsetX, Renderer.gridOffsetY)
    BurstParticles(cx, cy, SKILL_COLORS.star_crush, 30, Config.CELL_SIZE * 2)

    if hitCount > 0 then
        Toast.Show("毁灭践踏！" .. hitCount .. "名英雄被降星！", SKILL_COLORS.star_crush)
    else
        Toast.Show("毁灭践踏落空了！", { 150, 150, 150 })
    end

    -- 清除渲染数据
    if State.hatredBossSkill then
        State.hatredBossSkill.starCrush = nil
    end

    skillState.starCrush = nil
    print("[HatredBoss] StarCrush executed, hit=" .. hitCount)
end

-- ============================================================================
-- 技能 5: 终焉毁灭 — 扩散销毁英雄，带韧性条可打断
-- ============================================================================

--- 收集范围内的塔（曼哈顿距离或切比雪夫距离判定）
---@param centerCol number 中心格列
---@param centerRow number 中心格行
---@param radius number 格子半径
---@return table[] towers 范围内的塔列表
local function GetTowersInRadius(centerCol, centerRow, radius)
    local result = {}
    for _, tower in ipairs(State.towers) do
        local dc = math.abs(tower.col - centerCol)
        local dr = math.abs(tower.row - centerRow)
        if math.max(dc, dr) <= radius then
            result[#result + 1] = tower
        end
    end
    return result
end

--- 约束中心范围，使 center ± radius 完全落在放置区域内
---@param radius number 切比雪夫半径
---@return number minC, number maxC, number minR, number maxR
local function GetClampedCenterRange(radius)
    local minC = PLACE_MIN_COL + radius
    local maxC = PLACE_MAX_COL - radius
    local minR = PLACE_MIN_ROW + radius
    local maxR = PLACE_MAX_ROW - radius
    -- 半径超出放置区域时，取中点
    if minC > maxC then
        local mid = math.floor((PLACE_MIN_COL + PLACE_MAX_COL) / 2)
        minC, maxC = mid, mid
    end
    if minR > maxR then
        local mid = math.floor((PLACE_MIN_ROW + PLACE_MAX_ROW) / 2)
        minR, maxR = mid, mid
    end
    return minC, maxC, minR, maxR
end

--- 选择毁灭区域中心（覆盖英雄最多的位置，确保范围不超出放置区域）
---@param radius number 切比雪夫半径
---@return number centerCol, number centerRow
local function SelectDestructionCenter(radius)
    local minC, maxC, minR, maxR = GetClampedCenterRange(radius)
    local bestCol, bestRow, bestCount = minC, minR, 0
    for c = minC, maxC do
        for r = minR, maxR do
            local count = 0
            for _, tower in ipairs(State.towers) do
                if math.max(math.abs(tower.col - c), math.abs(tower.row - r)) <= radius then
                    count = count + 1
                end
            end
            if count > bestCount then
                bestCount = count
                bestCol, bestRow = c, r
            end
        end
    end
    return bestCol, bestRow
end

--- 开始毁灭引导（固定区域，大小随成功释放次数增长）
local function StartDestruction(boss)
    local cfg = skillState.mechanics.destruction
    if not cfg then return false end

    -- 半径随成功释放次数增长
    local successCount = skillState.destructionSuccessCount or 0
    local baseRadius = cfg.baseRadius or 1
    local growth = cfg.radiusGrowth or 1
    local maxR = cfg.maxRadius or 3
    local radius = math.min(baseRadius + successCount * growth, maxR)

    -- 选择覆盖英雄最多的中心位置
    local centerCol, centerRow = SelectDestructionCenter(radius)

    -- 检查区域内是否有英雄
    local towersInRange = GetTowersInRadius(centerCol, centerRow, radius)
    if #towersInRange == 0 then return false end

    -- 韧性条与 BOSS 当前防御成正比
    local defDiv = cfg.toughnessDefDiv or 100000
    local minHits = cfg.toughnessMin or 20
    local toughnessHits = math.max(minHits, math.ceil((boss.def or 0) / defDiv))

    local channelTime = cfg.channelTime or 5.0

    skillState.destruction = {
        timer = channelTime,             -- 引导倒计时
        totalTime = channelTime,
        centerCol = centerCol,
        centerRow = centerRow,
        radius = radius,                 -- 本次毁灭半径（固定）
        toughness = toughnessHits,
        maxToughness = toughnessHits,
        interrupted = false,
    }

    -- 引导期间眩晕
    boss.stunTimer = math.max(boss.stunTimer or 0, channelTime + 1.0)

    -- 渲染数据
    State.hatredBossSkill = State.hatredBossSkill or {}
    State.hatredBossSkill.destruction = {
        centerCol = centerCol,
        centerRow = centerRow,
        radius = radius,
        toughness = toughnessHits,
        maxToughness = toughnessHits,
        timer = channelTime,
        totalTime = channelTime,
    }

    local areaStr = string.format("%dx%d", radius * 2 + 1, radius * 2 + 1)
    Toast.Show("⚠ 终焉毁灭！" .. areaStr .. "区域即将被摧毁！", { 255, 20, 20 })
    BurstParticles(boss.x, boss.y, SKILL_COLORS.destruction, 25, 40)

    print(string.format("[HatredBoss] Destruction started: center=(%d,%d) radius=%d toughness=%d successCount=%d",
        centerCol, centerRow, radius, toughnessHits, successCount))
    return true
end

--- 毁灭引导更新（每帧调用）
local function UpdateDestruction(boss, dt)
    local dest = skillState.destruction
    if not dest or dest.interrupted then return end

    dest.timer = dest.timer - dt

    -- 同步渲染数据
    if State.hatredBossSkill and State.hatredBossSkill.destruction then
        State.hatredBossSkill.destruction.timer = dest.timer
        State.hatredBossSkill.destruction.toughness = dest.toughness
    end

    -- 引导完成：执行毁灭
    if dest.timer <= 0 then
        local towersInRange = GetTowersInRadius(dest.centerCol, dest.centerRow, dest.radius)
        local destroyed = 0
        for _, tower in ipairs(towersInRange) do
            -- 飘字
            local sx, sy = TowerScreenPos(tower)
            State.AddFloatingText({
                text = tower.typeDef.name .. " 被毁灭！",
                x = sx,
                y = sy - 20,
                vx = (math.random() - 0.5) * 20,
                vy = -40 - math.random() * 15,
                life = 1.5,
                color = { 255, 20, 20, 255 },
                fontSize = 14,
            })

            -- 粒子效果
            BurstParticles(sx, sy, SKILL_COLORS.destruction, 10, 20)

            -- 移除英雄
            Tower.Remove(tower)
            destroyed = destroyed + 1
        end

        -- 成功释放：增加计数，下次半径更大
        skillState.destructionSuccessCount = (skillState.destructionSuccessCount or 0) + 1

        -- 全屏闪光
        State.skillFlash = { type = "hatred_destruction", timer = 0.5 }

        -- 标记结束
        dest.interrupted = true
        boss.stunTimer = 0
        if State.hatredBossSkill then
            State.hatredBossSkill.destruction = nil
        end

        Toast.Show("终焉毁灭！" .. destroyed .. "名英雄被摧毁！", SKILL_COLORS.destruction)
        print(string.format("[HatredBoss] Destruction executed: destroyed=%d nextSuccessCount=%d",
            destroyed, skillState.destructionSuccessCount))

        -- 所有英雄被毁灭 → 直接结束游戏
        if #State.towers == 0 then
            print("[HatredBoss] All towers destroyed! Triggering game over.")
            Toast.Show("所有英雄已被摧毁！", { 255, 40, 40 })
            local BattleManager = require("Game.BattleManager")
            local AudioManager = require("Game.AudioManager")
            State.SetPhase(State.PHASE_GAME_OVER, "HBS.allTowersDestroyed")
            AudioManager.PlayDefeat()
            BattleManager.OnLose()
        end
    end
end

--- 对毁灭韧性条造成命中
function HBS.DamageDestructionToughness()
    if not skillState or not skillState.destruction then return end
    if skillState.destruction.interrupted then return end

    skillState.destruction.toughness = skillState.destruction.toughness - 1

    -- 同步渲染数据
    if State.hatredBossSkill and State.hatredBossSkill.destruction then
        State.hatredBossSkill.destruction.toughness = skillState.destruction.toughness
    end

    -- 韧性被打空 → 打断毁灭
    if skillState.destruction.toughness <= 0 then
        skillState.destruction.interrupted = true
        skillState.destruction.toughness = 0

        local boss = FindBoss()
        if boss then
            boss.stunTimer = 0
        end

        if State.hatredBossSkill then
            State.hatredBossSkill.destruction = nil
        end

        Toast.Show("毁灭引导被打断了！", { 100, 255, 100 })
        print("[HatredBoss] Destruction interrupted! Toughness broken.")
    end
end

--- 获取毁灭状态（供 Renderer / Combat 查询）
---@return table|nil
function HBS.GetDestructionState()
    if not skillState or not skillState.destruction then return nil end
    if skillState.destruction.interrupted then return nil end
    return skillState.destruction
end

-- ============================================================================
-- 技能选择（优先级：终焉毁灭 > 毁灭践踏 > 憎恨壁垒 > 深渊召唤 > 怨恨嘲讽）
-- ============================================================================

local function SelectSkill()
    local m = skillState.mechanics

    -- 终焉毁灭（最高优先级，终极技能）
    if m.destruction and skillState.destructionCd <= 0 then
        return "destruction"
    end

    -- 毁灭践踏（次高优先级）
    if m.star_crush and skillState.starCrushCd <= 0 then
        return "star_crush"
    end

    -- 憎恨壁垒
    if m.fortress and skillState.fortressCd <= 0 then
        return "fortress"
    end

    -- 深渊召唤
    if m.summon and skillState.summonCd <= 0 then
        return "summon"
    end

    -- 怨恨嘲讽
    if m.taunt and skillState.tauntCd <= 0 then
        return "taunt"
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

    -- 暂停 BOSS 移动（引导类技能需要额外的引导时间）
    local stunDuration = TOTAL_STUN + 0.5
    if skillId == "star_crush" then
        local cfg = skillState.mechanics.star_crush
        stunDuration = TOTAL_CAST + (cfg and cfg.channelTime or 3.0) + COOLDOWN_DELAY + 0.5
    elseif skillId == "destruction" then
        local cfg = skillState.mechanics.destruction
        stunDuration = TOTAL_CAST + (cfg and cfg.channelTime or 5.0) + COOLDOWN_DELAY + 0.5
    end
    boss.stunTimer = math.max(boss.stunTimer or 0, stunDuration)

    -- 设置渲染状态
    local c = SKILL_COLORS[skillId]
    State.hatredBossSkill = State.hatredBossSkill or {}
    State.hatredBossSkill.casting = {
        type = skillId,
        phase = PHASE_CASTING,
        timer = 0,
        bossId = boss.id,
        color = c,
    }

    print("[HatredBoss] Casting: " .. SKILL_NAMES[skillId])
end

local function EnterExecute(boss, skillId)
    skillState.phase = PHASE_EXECUTE
    skillState.phaseTimer = 0

    -- 攻击类技能用攻击帧，增益/引导类技能保持施法帧
    if skillId == "summon" then
        boss.castingFrame = 2   -- 召唤：攻击姿势
    elseif skillId == "star_crush" or skillId == "destruction" then
        boss.castingFrame = 1   -- 引导类：引导期间保持施法帧
    else
        boss.castingFrame = 1   -- 壁垒/嘲讽：增益技能只用施法帧
    end

    if State.hatredBossSkill and State.hatredBossSkill.casting then
        State.hatredBossSkill.casting.phase = PHASE_EXECUTE
        State.hatredBossSkill.casting.timer = 0
    end

    -- 执行技能效果
    if skillId == "summon" then
        ExecuteSummon(boss)
    elseif skillId == "fortress" then
        ExecuteFortress(boss)
    elseif skillId == "taunt" then
        ExecuteTaunt(boss)
    elseif skillId == "star_crush" then
        -- 毁灭践踏进入吟唱阶段（不在这里执行，通过 Update 管理）
        local success = StartStarCrush(boss)
        if not success then
            print("[HatredBoss] StarCrush: no valid targets, skipped")
        end
    elseif skillId == "destruction" then
        -- 终焉毁灭进入引导阶段（通过 Update 管理扩散）
        local success = StartDestruction(boss)
        if not success then
            print("[HatredBoss] Destruction: failed to start, skipped")
        end
    end
end

local function EnterCooldown(boss, skillId)
    skillState.phase = PHASE_COOLDOWN
    skillState.phaseTimer = 0

    boss.castingFrame = nil

    local m = skillState.mechanics
    if skillId == "summon" and m.summon then
        skillState.summonCd = m.summon.interval
    elseif skillId == "fortress" and m.fortress then
        skillState.fortressCd = m.fortress.interval
    elseif skillId == "taunt" and m.taunt then
        skillState.tauntCd = m.taunt.interval
    elseif skillId == "star_crush" and m.star_crush then
        skillState.starCrushCd = m.star_crush.interval
    elseif skillId == "destruction" and m.destruction then
        skillState.destructionCd = m.destruction.interval
    end
end

local function EnterIdle()
    skillState.activeSkill = nil
    skillState.phase = PHASE_IDLE
    skillState.phaseTimer = 0

    if State.hatredBossSkill then
        State.hatredBossSkill.casting = nil
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化（副本 onStart 调用）
---@param mechanics table { summon, fortress, taunt, star_crush }
function HBS.Init(mechanics)
    if not mechanics then return end
    skillState = {
        battleTimer = 0,
        phase = PHASE_IDLE,
        activeSkill = nil,
        phaseTimer = 0,
        mechanics = mechanics,

        -- 技能 CD（首次延迟减半）
        summonCd       = mechanics.summon       and (mechanics.summon.interval       * 0.5) or 999,
        fortressCd     = mechanics.fortress     and (mechanics.fortress.interval     * 0.5) or 999,
        tauntCd        = mechanics.taunt        and (mechanics.taunt.interval        * 0.5) or 999,
        starCrushCd    = mechanics.star_crush   and (mechanics.star_crush.interval   * 0.5) or 999,
        destructionCd  = mechanics.destruction  and (mechanics.destruction.interval  * 0.5) or 999,

        -- 召唤计数
        summonCastCount = 0,

        -- 壁垒状态
        fortressActive = false,
        fortressCastCount = 0,

        -- 嘲讽状态
        tauntActive = false,
        tauntTimer = 0,
        tauntStacks = {},

        -- 毁灭践踏状态
        starCrush = nil,

        -- 终焉毁灭状态
        destruction = nil,
        destructionSuccessCount = 0,

        -- BOSS 是否已出场
        bossSpawned = false,
    }

    State.hatredBossSkill = {}

    print("[HatredBoss] Initialized"
        .. " summon.interval=" .. tostring(mechanics.summon and mechanics.summon.interval)
        .. " fortress.interval=" .. tostring(mechanics.fortress and mechanics.fortress.interval)
        .. " taunt.interval=" .. tostring(mechanics.taunt and mechanics.taunt.interval)
        .. " star_crush.interval=" .. tostring(mechanics.star_crush and mechanics.star_crush.interval)
        .. " destruction.interval=" .. tostring(mechanics.destruction and mechanics.destruction.interval))
end

--- 每帧更新
---@param dt number
function HBS.Update(dt)
    if not skillState then return end

    skillState.battleTimer = skillState.battleTimer + dt

    local boss = FindBoss()
    if not boss then
        if skillState.bossSpawned then
            HBS.Cleanup()
        end
        return
    end
    skillState.bossSpawned = true

    -- ======== 壁垒：永久生效，无需倒计时管理 ========

    -- ======== 嘲讽持续时间管理 ========
    if skillState.tauntActive then
        skillState.tauntTimer = skillState.tauntTimer - dt
        if skillState.tauntTimer <= 0 then
            skillState.tauntActive = false
            skillState.tauntStacks = {}
            print("[HatredBoss] Taunt expired")
        else
            -- 更新每个塔的嘲讽层数计时
            for id, info in pairs(skillState.tauntStacks) do
                if info.timer then
                    info.timer = info.timer - dt
                    if info.timer <= 0 then
                        -- 层数过期，清除
                        skillState.tauntStacks[id] = nil
                    end
                end
            end
        end
    end

    -- ======== 毁灭践踏吟唱管理（独立于状态机） ========
    if skillState.starCrush and not skillState.starCrush.interrupted then
        skillState.starCrush.timer = skillState.starCrush.timer - dt

        -- 同步渲染数据
        if State.hatredBossSkill and State.hatredBossSkill.starCrush then
            State.hatredBossSkill.starCrush.timer = skillState.starCrush.timer
        end

        if skillState.starCrush.timer <= 0 then
            -- 吟唱完成，执行降星
            ExecuteStarCrush(boss)
            if not skillState then return end
        end
    end

    -- ======== 终焉毁灭引导管理（独立于状态机） ========
    if skillState.destruction and not skillState.destruction.interrupted then
        UpdateDestruction(boss, dt)
    end

    -- UpdateDestruction/ExecuteStarCrush 可能触发游戏结束 → Cleanup 置空 skillState
    if not skillState then return end

    -- ======== 同步渲染状态 ========
    State.hatredBossSkill = State.hatredBossSkill or {}
    State.hatredBossSkill.tauntActive = skillState.tauntActive
    State.hatredBossSkill.fortressActive = skillState.fortressActive
    State.hatredBossSkill.bossX = boss.x
    State.hatredBossSkill.bossY = boss.y
    State.hatredBossSkill.bossSize = boss.typeDef and boss.typeDef.size or 22

    -- ======== 状态机 ========

    if skillState.phase == PHASE_IDLE then
        -- 如果正在引导（毁灭践踏或终焉毁灭），不释放其他技能
        if skillState.starCrush and not skillState.starCrush.interrupted then
            return
        end
        if skillState.destruction and not skillState.destruction.interrupted then
            return
        end

        -- Tick CD
        skillState.summonCd      = skillState.summonCd - dt
        skillState.fortressCd    = skillState.fortressCd - dt
        skillState.tauntCd       = skillState.tauntCd - dt
        skillState.starCrushCd   = skillState.starCrushCd - dt
        skillState.destructionCd = skillState.destructionCd - dt

        local skillId = SelectSkill()
        if skillId then
            EnterCasting(boss, skillId)
        end

    elseif skillState.phase == PHASE_CASTING then
        skillState.phaseTimer = skillState.phaseTimer + dt

        -- 触发技能名横幅
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

        -- 切换施法帧
        if skillState.phaseTimer >= CAST_BUILDUP and not skillState.castFrameSet then
            skillState.castFrameSet = true
            boss.castingFrame = 1
        end

        -- 更新渲染计时器
        if State.hatredBossSkill and State.hatredBossSkill.casting then
            State.hatredBossSkill.casting.timer = skillState.phaseTimer
        end

        -- 进入 EXECUTE
        if skillState.phaseTimer >= TOTAL_CAST then
            skillState.bannerShown = nil
            skillState.castFrameSet = nil
            EnterExecute(boss, skillState.activeSkill)
        end

    elseif skillState.phase == PHASE_EXECUTE then
        skillState.phaseTimer = skillState.phaseTimer + dt

        if State.hatredBossSkill and State.hatredBossSkill.casting then
            State.hatredBossSkill.casting.timer = skillState.phaseTimer
        end

        -- 引导类技能：等待引导完成或被打断才进入冷却
        if skillState.activeSkill == "star_crush" then
            local crush = skillState.starCrush
            if not crush or crush.interrupted or crush.timer <= 0 then
                EnterCooldown(boss, skillState.activeSkill)
            end
        elseif skillState.activeSkill == "destruction" then
            local dest = skillState.destruction
            if not dest or dest.interrupted then
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
function HBS.Cleanup()
    if not skillState then return end

    -- 清除 BOSS 施法帧和眩晕（壁垒防御为永久叠加，不恢复）
    local boss = FindBoss()
    if boss then
        boss.castingFrame = nil
        -- 如果毁灭引导中被清理，恢复移动
        if skillState.destruction and not skillState.destruction.interrupted then
            boss.stunTimer = 0
        end
    end

    -- 清除英雄塔上的嘲讽 debuff
    for _, tower in ipairs(State.towers) do
        if tower.debuffs then
            local i = 1
            while i <= #tower.debuffs do
                local db = tower.debuffs[i]
                if db.id == "hatred_taunt_spd" then
                    table.remove(tower.debuffs, i)
                else
                    i = i + 1
                end
            end
        end
    end

    -- 清除渲染状态
    State.hatredBossSkill = nil

    skillState = nil
    print("[HatredBoss] Cleaned up")
end

--- 是否激活
---@return boolean
function HBS.IsActive()
    return skillState ~= nil
end

--- 是否嘲讽激活（供 Combat 模块查询）
---@return boolean
function HBS.IsTauntActive()
    return skillState ~= nil and skillState.tauntActive == true
end

--- 是否正在吟唱毁灭践踏（供 HUD 显示）
---@return table|nil { timer, totalTime, centerCol, centerRow, toughness, maxToughness }
function HBS.GetStarCrushState()
    if not skillState or not skillState.starCrush then return nil end
    if skillState.starCrush.interrupted then return nil end
    return skillState.starCrush
end

--- 获取壁垒状态（供 HUD 显示护盾）
---@return boolean active, number stacks
function HBS.GetFortressState()
    if not skillState then return false, 0 end
    return skillState.fortressActive, skillState.fortressCastCount or 0
end

--- 获取下次技能释放倒计时
---@return string skillName, number cooldown
function HBS.GetNextSkillInfo()
    if not skillState then return "无", 0 end
    local cds = {
        { name = "终焉毁灭", cd = skillState.destructionCd },
        { name = "毁灭践踏", cd = skillState.starCrushCd },
        { name = "憎恨壁垒", cd = skillState.fortressCd },
        { name = "深渊召唤", cd = skillState.summonCd },
        { name = "怨恨嘲讽", cd = skillState.tauntCd },
    }
    table.sort(cds, function(a, b) return a.cd < b.cd end)
    return cds[1].name, math.max(0, cds[1].cd)
end

return HBS
