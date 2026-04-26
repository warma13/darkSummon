-- Game/Heroes/ember_wraith.lua
-- 烬殇：灰烬蔓延 (chain_ignite) + 烬核共振 (ember_resonance) + 焚天 (heavens_pyre)
local M = {}

local State = require("Game.State")

local AddFloatingText = State.AddFloatingText

-- 飘字颜色
local COLOR_IGNITE       = { 255, 140, 40, 255 }
local COLOR_SPREAD       = { 255, 100, 20, 255 }
local COLOR_PYRE         = { 255, 60, 10, 255 }
local COLOR_EXECUTE      = { 255, 30, 0, 255 }

-- 延迟 require 缓存
local _Enemy, _Combat, _HeroSkills
local function GetEnemy()
    if not _Enemy then _Enemy = require("Game.Enemy") end
    return _Enemy
end
local function GetCombat()
    if not _Combat then _Combat = require("Game.Combat") end
    return _Combat
end
local function GetHeroSkills()
    if not _HeroSkills then _HeroSkills = require("Game.HeroSkills") end
    return _HeroSkills
end

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

-- ============================================================================
-- 灼烧系统（存储在 enemy 上）
-- enemy.igniteStacks    : 当前灼烧层数 (0-3)
-- enemy.igniteTimer     : 灼烧剩余时间（刷新式）
-- enemy.igniteDotDmg    : 每层每秒伤害
-- enemy.igniteSource    : 来源塔引用（用于获取ATK/共振增幅）
-- enemy.igniteTickTimer : DOT tick 计时器
-- enemy._igniteSpreadDone : 死亡蔓延已处理标记
-- ============================================================================

--- 对敌人施加灼烧层数
---@param enemy table
---@param stacks number  施加层数
---@param dotDmgPerStack number  每层每秒伤害
---@param duration number  持续时间
---@param sourceTower table  来源塔
local function ApplyIgnite(enemy, stacks, dotDmgPerStack, duration, sourceTower)
    if not enemy.alive then return end
    local maxStacks = 3
    enemy.igniteStacks = math.min(
        (enemy.igniteStacks or 0) + stacks,
        maxStacks
    )
    enemy.igniteTimer = duration  -- 刷新计时
    enemy.igniteDotDmg = dotDmgPerStack
    enemy.igniteSource = sourceTower
    enemy.igniteTickTimer = enemy.igniteTickTimer or 0
end

--- 清除敌人灼烧
---@param enemy table
local function ClearIgnite(enemy)
    enemy.igniteStacks = 0
    enemy.igniteTimer = 0
    enemy.igniteDotDmg = 0
    enemy.igniteSource = nil
    enemy.igniteTickTimer = 0
end

-- ============================================================================
-- Hook: OnHit — 技能1：灰烬蔓延（攻击叠加灼烧）
-- ============================================================================

---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local ignite = has(tower, "chain_ignite")
    if not ignite then return end

    -- 对存活目标施加1层灼烧
    if target.alive then
        local atk = GetHeroSkills().GetEffectiveAttack(tower)
        local dotDmgPerStack = atk * (ignite.dotPctPerStack or 0.15)
        ApplyIgnite(target, 1, dotDmgPerStack, ignite.stackDuration or 3.0, tower)
    end
end

-- ============================================================================
-- Hook: TriggerActive — 技能3：焚天（AOE + 处决 + 爆炸）
-- ============================================================================

---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "heavens_pyre" then return end

    local HeroSkills = GetHeroSkills()
    local Combat     = GetCombat()
    local Enemy      = GetEnemy()

    local atk           = HeroSkills.GetEffectiveAttack(tower)
    local baseDmg       = atk * (skill.baseAtkPct or 6.0)
    local threshold     = skill.executeThreshold or 0.30
    local execRadius    = skill.executeRadius or 50
    local execRadiusSq  = execRadius * execRadius
    local execAoeDmg    = atk * (skill.executeAoePct or 3.0)
    local execIgnite    = skill.executeIgniteStacks or 2

    -- 获取灼烧技能参数（用于施加灼烧）
    local ignite = has(tower, "chain_ignite")
    local dotDmgPerStack = ignite and (atk * (ignite.dotPctPerStack or 0.15)) or 0
    local igniteDur      = ignite and (ignite.stackDuration or 3.0) or 3.0

    -- ── 阶段1: 对所有活着的敌人造成AOE火焰伤害 ──
    local executedPositions = {}

    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)

            -- 处决判定：受伤后仍存活 + HP<阈值 + 有灼烧层
            if e.alive and (e.igniteStacks or 0) > 0 then
                if e.hp / e.maxHP < threshold then
                    if e.isBoss then
                        -- BOSS免疫处决 → 造成额外固定伤害
                        local bossDmg = Combat.CalcFinalDamage(tower, e, baseDmg * 0.5)
                        Enemy.TakeDamage(e, bossDmg)
                    else
                        -- 小怪直接处决
                        executedPositions[#executedPositions + 1] = { x = e.x, y = e.y }
                        Enemy.TakeDamage(e, e.hp + 1)
                        AddFloatingText({
                            text     = "处决!",
                            x        = e.x + (math.random() - 0.5) * 10,
                            y        = e.y - (e.typeDef.size or 8) - 20,
                            life     = 1.0,
                            color    = COLOR_EXECUTE,
                            fontSize = 15,
                        })
                    end
                end
            end
        end
    end

    -- ── 阶段2: 处决目标爆炸 → 对周围敌人造成AOE + 施加灼烧 ──
    for _, pos in ipairs(executedPositions) do
        for _, e in ipairs(State.enemies) do
            if e.alive and not e.phaseActive then
                local dx = e.x - pos.x
                local dy = e.y - pos.y
                if dx * dx + dy * dy < execRadiusSq then
                    local explodeDmg = Combat.CalcFinalDamage(tower, e, execAoeDmg)
                    Enemy.TakeDamage(e, explodeDmg)
                    -- 施加灼烧
                    if e.alive and ignite then
                        ApplyIgnite(e, execIgnite, dotDmgPerStack, igniteDur, tower)
                    end
                end
            end
        end
    end

    -- 技能闪光 + 飘字
    State.skillFlash = { type = "heavens_pyre", timer = 0.8, tower = tower }
    AddFloatingText({
        text     = "焚天!",
        x        = tower._sx or 0,
        y        = (tower._sy or 0) - 40,
        life     = 1.5,
        color    = COLOR_PYRE,
        fontSize = 18,
    })

    print("[Heroes] heavens_pyre executed=" .. #executedPositions
        .. " total_enemies=" .. #State.enemies)
end

-- ============================================================================
-- Hook: UpdateFrame — 技能2：烬核共振（统计燃烧敌人 → 更新ATK/DOT增幅）
-- ============================================================================

---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    -- 统计场上所有灼烧中的敌人数量
    local burnCount = 0
    for _, e in ipairs(State.enemies) do
        if e.alive and (e.igniteStacks or 0) > 0 and (e.igniteTimer or 0) > 0 then
            burnCount = burnCount + 1
        end
    end

    -- 更新每个烬殇塔的共振状态
    for _, tower in ipairs(towers) do
        if tower.typeDef and tower.typeDef.id == "ember_wraith" and tower.hstate then
            local hs = tower.hstate
            local resonance = has(tower, "ember_resonance")
            if resonance then
                local capped = math.min(burnCount, resonance.maxBurns or 12)
                hs.resonanceBurnCount = capped
                hs.resonanceAtkBonus  = capped * (resonance.atkPerBurn or 0.04)
                hs.resonanceDotAmp    = capped * (resonance.dotAmpPerBurn or 0.06)
            end
        end
    end
end

-- ============================================================================
-- Hook: UpdateGlobal — 灼烧DOT tick + 死亡蔓延（灰烬蔓延连锁）
-- ============================================================================

---@param dt number
function M.UpdateGlobal(dt)
    local Enemy  = GetEnemy()
    local Combat = GetCombat()

    -- ── 阶段1: Tick 灼烧DOT ──
    for _, e in ipairs(State.enemies) do
        if e.alive and (e.igniteStacks or 0) > 0 and (e.igniteTimer or 0) > 0 then
            -- 衰减计时器
            e.igniteTimer = e.igniteTimer - dt
            if e.igniteTimer <= 0 then
                ClearIgnite(e)
            else
                -- DOT tick (每0.5秒一次，与标准DOT一致)
                e.igniteTickTimer = (e.igniteTickTimer or 0) + dt
                if e.igniteTickTimer >= 0.5 then
                    e.igniteTickTimer = e.igniteTickTimer - 0.5
                    local stacks       = e.igniteStacks or 0
                    local dmgPerStack  = e.igniteDotDmg or 0
                    local totalDmg     = stacks * dmgPerStack * 0.5  -- 0.5秒的伤害

                    -- 应用共振DOT增幅
                    local source = e.igniteSource
                    if source and source.hstate then
                        local amp = source.hstate.resonanceDotAmp or 0
                        if amp > 0 then
                            totalDmg = totalDmg * (1 + amp)
                        end
                    end

                    if totalDmg > 0 then
                        Enemy.TakeDamage(e, totalDmg)
                    end
                end
            end
        end
    end

    -- ── 阶段2: 死亡蔓延（处理所有死亡且有灼烧的敌人，含连锁） ──
    local spreadOccurred = true
    local iteration = 0
    local maxIteration = 10  -- 防止无限循环

    while spreadOccurred and iteration < maxIteration do
        spreadOccurred = false
        iteration = iteration + 1

        for _, e in ipairs(State.enemies) do
            if not e.alive
                and (e.igniteStacks or 0) > 0
                and not e._igniteSpreadDone then

                e._igniteSpreadDone = true
                spreadOccurred = true

                local source = e.igniteSource
                if not source or not source.skills then goto continue_spread end

                local ignite = has(source, "chain_ignite")
                if not ignite then goto continue_spread end

                local HeroSkills = GetHeroSkills()
                local atk        = HeroSkills.GetEffectiveAttack(source)
                local aoeDmg     = atk * (ignite.deathAoePct or 1.50)
                local radius     = ignite.deathRadius or 60
                local radiusSq   = radius * radius
                local dotDmg     = atk * (ignite.dotPctPerStack or 0.15)
                local igniteDur  = ignite.stackDuration or 3.0

                for _, e2 in ipairs(State.enemies) do
                    if e2.alive and not e2.phaseActive then
                        local dx = e2.x - e.x
                        local dy = e2.y - e.y
                        if dx * dx + dy * dy < radiusSq then
                            local finalDmg = Combat.CalcFinalDamage(source, e2, aoeDmg)
                            Enemy.TakeDamage(e2, finalDmg)

                            -- 施加1层灼烧
                            if e2.alive then
                                ApplyIgnite(e2, 1, dotDmg, igniteDur, source)
                            end

                            AddFloatingText({
                                text     = "蔓延",
                                x        = e2.x + (math.random() - 0.5) * 10,
                                y        = e2.y - (e2.typeDef.size or 8) - 16,
                                life     = 0.8,
                                color    = COLOR_SPREAD,
                                fontSize = 12,
                            })
                        end
                    end
                end

                ::continue_spread::
            end
        end
    end
end

return M
