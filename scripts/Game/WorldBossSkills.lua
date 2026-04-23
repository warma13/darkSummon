-- Game/WorldBossSkills.lua
-- 世界BOSS技能系统：束缚、召唤精英、销毁英雄
-- 三种技能各自独立冷却，目标选择基于局内合成星级(tower.star)

local Config  = require("Game.Config")
local State   = require("Game.State")
local Tower   = require("Game.Tower")
local Enemy   = require("Game.Enemy")
local WB      = require("Game.WorldBossData")
local Toast   = require("Game.Toast")
local Debuff  = require("Game.Debuff")

local WBS = {}

-- ============================================================================
-- 技能状态
-- ============================================================================

---@class WorldBossSkillState
---@field battleTimer number     战斗计时器（从0开始累加）
---@field shackleCooldown number 束缚冷却剩余
---@field summonCooldown number  召唤冷却剩余
---@field annihilateCooldown number 销毁冷却剩余
---@field summonCount number     已召唤次数
---@field shackledTowers table   被束缚的英雄列表 { towerId, timer }
---@field annihilateWarning table|nil  销毁预警 { timer, targetTowerId }

---@type WorldBossSkillState|nil
local skillState = nil

-- ============================================================================
-- 初始化 / 重置
-- ============================================================================

--- 初始化技能系统（BattleManager.Start 时调用）
---@param difficultyLevel number|nil 难度等级
function WBS.Init(difficultyLevel)
    local cfg = WB.CONFIG
    local diffLevel = difficultyLevel or WB.GetSelectedDifficulty()
    skillState = {
        battleTimer = 0,
        difficultyLevel = diffLevel,
        shackleCooldown = WB.GetDifficultyCooldown(cfg.shackleFirstCast, diffLevel),
        summonCooldown = WB.GetDifficultyCooldown(cfg.summonFirstCast, diffLevel),
        annihilateCooldown = WB.GetDifficultyCooldown(cfg.annihilateFirstCast, diffLevel),
        summonCount = 0,
        shackledTowers = {},
        annihilateWarning = nil,
    }
    State.worldBossActive = true
    State.worldBossTotalDamage = 0
    State.worldBossWarning = nil
    print("[WorldBossSkills] Initialized with difficulty level " .. diffLevel)
end

--- 清理技能系统
function WBS.Cleanup()
    if not skillState then return end
    -- 解除所有束缚
    for _, s in ipairs(skillState.shackledTowers) do
        WBS.RemoveShackle(s.towerId)
    end
    skillState = nil
    State.worldBossActive = false
    State.worldBossWarning = nil
    print("[WorldBossSkills] Cleaned up")
end

--- 是否激活
function WBS.IsActive()
    return skillState ~= nil
end

-- ============================================================================
-- 目标选择（按星级加权随机）
-- ============================================================================

--- 按权重选择目标塔
---@param weights table  星级 → 权重映射 (index 1~5 对应 ★1~★5)
---@param excludeLeader boolean  是否排除主角
---@param excludeShackled boolean  是否排除已被束缚的
---@return table|nil tower
local function SelectTargetByWeight(weights, excludeLeader, excludeShackled)
    if not skillState then return nil end

    -- 收集被束缚的英雄ID集合
    local shackledSet = {}
    if excludeShackled then
        for _, s in ipairs(skillState.shackledTowers) do
            shackledSet[s.towerId] = true
        end
    end

    -- 构建候选列表
    local candidates = {}
    local totalWeight = 0
    for _, tower in ipairs(State.towers) do
        if not (excludeLeader and tower.isLeader)
           and not shackledSet[tower.id] then
            -- tower.star 是 0-based (0=★1, 4=★5)
            local starIdx = (tower.star or 0) + 1  -- 转 1-based
            if starIdx < 1 then starIdx = 1 end
            if starIdx > #weights then starIdx = #weights end
            local w = weights[starIdx] or 1
            if tower.isLeader then
                w = weights[#weights] or 1  -- 主角用最低权重
            end
            if w > 0 then
                candidates[#candidates + 1] = { tower = tower, weight = w }
                totalWeight = totalWeight + w
            end
        end
    end

    if #candidates == 0 or totalWeight <= 0 then return nil end

    -- 加权随机选择
    local roll = math.random() * totalWeight
    local acc = 0
    for _, c in ipairs(candidates) do
        acc = acc + c.weight
        if roll <= acc then
            return c.tower
        end
    end
    return candidates[#candidates].tower
end

-- ============================================================================
-- 束缚技能 (Shackle)
-- ============================================================================

--- 对英雄施加束缚
---@param tower table
local function ApplyShackle(tower)
    if not skillState then return end
    local cfg = WB.CONFIG

    -- 免疫检查（翎嫣翠意庇护等免疫来源通过 Debuff 系统声明，无需硬编码）
    if not Debuff.Apply(tower, "shackle") then
        local towerName = tower.typeDef and tower.typeDef.name or ("英雄#" .. tower.id)
        print("[WorldBossSkills] " .. towerName .. " 免疫束缚")
        return
    end
    tower.shackleTimer = cfg.shackleDuration

    skillState.shackledTowers[#skillState.shackledTowers + 1] = {
        towerId = tower.id,
        timer = cfg.shackleDuration,
    }

    local towerName = tower.typeDef and tower.typeDef.name or ("英雄#" .. tower.id)
    Toast.Show(towerName .. " 被束缚了！", { 200, 100, 255 })
    print("[WorldBossSkills] Shackled: " .. towerName .. " (★" .. ((tower.star or 0) + 1) .. ")")
end

--- 解除束缚
---@param towerId number
function WBS.RemoveShackle(towerId)
    for _, tower in ipairs(State.towers) do
        if tower.id == towerId then
            Debuff.Clear(tower, "shackle")
            tower.shackleTimer = 0
            break
        end
    end
end

--- 释放束缚技能
local function CastShackle()
    local cfg = WB.CONFIG
    local target = SelectTargetByWeight(cfg.shackleWeights, false, true)
    if target then
        ApplyShackle(target)
    end
    -- 重置冷却（渐进难度：CD随时间衰减 + 难度CD减少）
    local cdMult = WB.GetCDMultiplier(skillState.battleTimer)
    local baseCD = WB.GetDifficultyCooldown(cfg.shackleCooldown, skillState.difficultyLevel)
    skillState.shackleCooldown = baseCD * cdMult
end

-- ============================================================================
-- 召唤精英技能 (Summon Elite)
-- ============================================================================

--- 释放召唤精英技能
local function CastSummonElite()
    local cfg = WB.CONFIG
    skillState.summonCount = skillState.summonCount + 1
    local count = math.min(skillState.summonCount, cfg.summonMaxCount)

    -- 获取当前波次信息
    local currentWave = State.currentWave or 1
    local stageEquiv = WB.WaveToStage(currentWave)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = WB.CalcHPScale(stageEquiv)
    local spdScale = WB.CalcSpeedScale(currentWave)

    -- 主题轮换
    local themeIdx = math.floor((currentWave - 1) / 4) + 1
    if themeIdx > Config.THEME_COUNT then themeIdx = Config.THEME_COUNT end

    -- 可用角色池（排除 minion）
    local availRoles = {}
    local globalWave = stageNum * Config.WAVES_PER_STAGE
    for _, roleId in ipairs(Config.ROLE_IDS) do
        if roleId ~= "minion" then
            local role = Config.ENEMY_ROLES[roleId]
            if role then
                local unlockWave = Config.ROLE_UNLOCK_WAVE[role.unlockOrder] or 1
                if globalWave >= unlockWave then
                    availRoles[#availRoles + 1] = roleId
                end
            end
        end
    end
    if #availRoles == 0 then availRoles = { "infantry" } end

    -- 渐进难度：精英HP随时间增强
    local eliteHPMult = WB.GetEliteHPMultiplier(skillState.battleTimer)

    -- 难度倍率（应用到精英HP和DEF）
    local diffDef = WB.GetDifficultyDef(skillState.difficultyLevel)
    local diffMult = diffDef and diffDef.attrMult or 1

    for i = 1, count do
        local roleId = availRoles[math.random(#availRoles)]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale * 3.0 * eliteHPMult * diffMult  -- 精英HP x3 × 渐进倍率 × 难度倍率
            def.baseDEF = (def.baseDEF or 0) * diffMult                        -- 精英DEF × 难度倍率
            def.speed = def.speed * spdScale
            def.isElite = true
            def.isDungeonEnemy = true

            -- 词缀
            local tier = (currentWave >= 16) and 2 or 1
            local affix = nil
            local pool = {}
            for _, a in ipairs(Config.AFFIXES) do
                if a.tier == tier then pool[#pool + 1] = a end
            end
            if #pool > 0 then
                affix = pool[math.random(#pool)]
            end

            Enemy.CreateEnemyFromDef(def, currentWave, 1.0, 1.0, true, affix and { affix } or {})
        end
    end

    Toast.Show("深渊主宰召唤了" .. count .. "只精英怪！", { 255, 140, 60 })
    print("[WorldBossSkills] Summoned " .. count .. " elites (cast #" .. skillState.summonCount .. ")")

    -- 重置冷却（渐进难度：CD随时间衰减 + 难度CD减少）
    local cdMult = WB.GetCDMultiplier(skillState.battleTimer)
    local baseCD = WB.GetDifficultyCooldown(cfg.summonCooldown, skillState.difficultyLevel)
    skillState.summonCooldown = baseCD * cdMult
end

-- ============================================================================
-- 销毁英雄技能 (Annihilate)
-- ============================================================================

--- 开始销毁预警
local function StartAnnihilateWarning()
    local cfg = WB.CONFIG

    -- 检查是否只剩主角
    local nonLeaderCount = 0
    for _, tower in ipairs(State.towers) do
        if not tower.isLeader then
            nonLeaderCount = nonLeaderCount + 1
        end
    end

    -- 渐进难度：CD衰减 + 难度CD减少
    local cdMult = WB.GetCDMultiplier(skillState.battleTimer)
    local baseCD = WB.GetDifficultyCooldown(cfg.annihilateCooldown, skillState.difficultyLevel)

    if nonLeaderCount == 0 then
        -- 只剩主角，改为束缚主角
        for _, tower in ipairs(State.towers) do
            if tower.isLeader then
                ApplyShackle(tower)
                Toast.Show("深渊主宰束缚了暗影君主！", { 255, 80, 80 })
                break
            end
        end
        skillState.annihilateCooldown = baseCD * cdMult
        return
    end

    -- 选择目标（主角免疫：权重0）
    local target = SelectTargetByWeight(cfg.annihilateWeights, true, false)
    if not target then
        skillState.annihilateCooldown = baseCD * cdMult
        return
    end

    -- 设置预警
    skillState.annihilateWarning = {
        timer = cfg.annihilateWarning,
        targetTowerId = target.id,
    }
    State.worldBossWarning = {
        timer = cfg.annihilateWarning,
        targetTowerId = target.id,
    }

    Toast.Show("⚠ 深渊主宰正在凝聚毁灭之力！", { 255, 40, 40 })
    print("[WorldBossSkills] Annihilate warning! Target: tower#" .. target.id)
end

--- 执行销毁
local function ExecuteAnnihilate()
    if not skillState or not skillState.annihilateWarning then return end

    local targetId = skillState.annihilateWarning.targetTowerId
    skillState.annihilateWarning = nil
    State.worldBossWarning = nil

    -- 找到目标塔
    local targetTower = nil
    for _, tower in ipairs(State.towers) do
        if tower.id == targetId then
            targetTower = tower
            break
        end
    end

    -- 渐进难度：CD衰减 + 难度CD减少
    local cdMult = WB.GetCDMultiplier(skillState.battleTimer)
    local baseCD = WB.GetDifficultyCooldown(WB.CONFIG.annihilateCooldown, skillState.difficultyLevel)

    if not targetTower then
        -- 目标已不存在（可能被合成了）
        print("[WorldBossSkills] Annihilate target gone, skipped")
        skillState.annihilateCooldown = baseCD * cdMult
        return
    end

    -- 不能销毁主角
    if targetTower.isLeader then
        ApplyShackle(targetTower)
        skillState.annihilateCooldown = baseCD * cdMult
        return
    end

    -- 先解除束缚（如果被束缚了）
    if targetTower.shackled then
        WBS.RemoveShackle(targetTower.id)
    end

    local towerName = targetTower.typeDef and targetTower.typeDef.name or ("英雄#" .. targetTower.id)

    -- 移除塔
    Tower.Remove(targetTower)

    Toast.Show(towerName .. " 被深渊主宰销毁！", { 255, 50, 50 })
    print("[WorldBossSkills] Annihilated: " .. towerName)

    -- 重置冷却
    skillState.annihilateCooldown = baseCD * cdMult
end

-- ============================================================================
-- 主更新
-- ============================================================================

--- 每帧更新（在 BattleManager.UpdateWaves 之后调用）
---@param dt number
function WBS.Update(dt)
    if not skillState then return end
    if State.phase ~= State.PHASE_PLAYING then return end

    skillState.battleTimer = skillState.battleTimer + dt
    local elapsed = skillState.battleTimer

    -- ======== 渐进难度：实时更新Boss DEF（含难度倍率） ========
    local boss = State.worldBoss
    if boss and boss.alive then
        boss.def = WB.GetScaledDEF(elapsed, skillState.difficultyLevel)
    end

    -- 更新束缚计时
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
            WBS.RemoveShackle(s.towerId)
            table.remove(skillState.shackledTowers, i)
        end
    end

    -- 更新销毁预警
    if skillState.annihilateWarning then
        skillState.annihilateWarning.timer = skillState.annihilateWarning.timer - dt
        if State.worldBossWarning then
            State.worldBossWarning.timer = skillState.annihilateWarning.timer
        end
        if skillState.annihilateWarning.timer <= 0 then
            ExecuteAnnihilate()
            return  -- 本帧不再释放其他技能
        end
    end

    -- 技能冷却递减
    skillState.shackleCooldown = skillState.shackleCooldown - dt
    skillState.summonCooldown = skillState.summonCooldown - dt
    skillState.annihilateCooldown = skillState.annihilateCooldown - dt

    -- 按优先级释放技能（销毁 > 召唤 > 束缚）
    -- 销毁预警中不释放其他技能
    if skillState.annihilateWarning then return end

    if skillState.annihilateCooldown <= 0 then
        StartAnnihilateWarning()
    elseif skillState.summonCooldown <= 0 then
        CastSummonElite()
    elseif skillState.shackleCooldown <= 0 then
        CastShackle()
    end
end

-- ============================================================================
-- HUD 信息查询
-- ============================================================================

--- 获取战斗计时器
---@return number
function WBS.GetBattleTimer()
    return skillState and skillState.battleTimer or 0
end

--- 获取被束缚的英雄列表
---@return table shackled { towerId, timer }[]
function WBS.GetShackledTowers()
    return skillState and skillState.shackledTowers or {}
end

--- 获取销毁预警信息
---@return table|nil warning { timer, targetTowerId }
function WBS.GetAnnihilateWarning()
    return skillState and skillState.annihilateWarning or nil
end

--- 获取下次技能释放倒计时（供HUD显示）
---@return string skillName, number cooldown
function WBS.GetNextSkillInfo()
    if not skillState then return "无", 0 end
    local shackleCD = skillState.shackleCooldown
    local summonCD = skillState.summonCooldown
    local annihilateCD = skillState.annihilateCooldown

    if annihilateCD <= shackleCD and annihilateCD <= summonCD then
        return "销毁", math.max(0, annihilateCD)
    elseif summonCD <= shackleCD then
        return "召唤", math.max(0, summonCD)
    else
        return "束缚", math.max(0, shackleCD)
    end
end

--- 检查塔是否被束缚（供 Tower.Update 调用跳过攻击）
---@param tower table
---@return boolean
function WBS.IsTowerShackled(tower)
    return tower.shackled == true
end

return WBS
