-- Game/Heroes/crimson_moon.lua
-- 弦月：蚀月之链 (eclipse_chain) + 血月共鸣 (blood_resonance)
--       + 绯红新月 (crimson_crescent) + 月蚀领域 (eclipse_domain)
--
-- 被动1 蚀月之链：连锁弹跳命中叠加蚀月印记(最多5层)，每层+4%魔法增伤，满层触发月蚀爆发
-- 被动2 血月共鸣：爆发时减魔抗15%，每命中+6%攻速(最多5层)，击杀刷新攻击
-- 主动  绯红新月：全屏350%ATK伤害+3层印记，血月觉醒6s(+25%ATK,连锁+2)
-- 被动3 月蚀领域：领域内魔法增伤+12%，击杀+3%永久ATK，累计30%触发满月(纯伤5s)

local M = {}

local State = require("Game.State")

local AddFloatingText = State.AddFloatingText

-- 飘字颜色
local COLOR_ECLIPSE_BURST = { 220, 40, 80, 255 }     -- 暗红（月蚀爆发）
local COLOR_FULL_MOON     = { 255, 255, 255, 255 }    -- 纯白（满月）
local COLOR_RESONANCE     = { 180, 60, 120, 255 }     -- 紫红（血月觉醒）

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

-- ============================================================================
-- 被动1+3：伤害修正 — 月蚀领域增伤 + 觉醒ATK + 灵魂ATK + 满月纯伤标记
-- ============================================================================

---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    local hs = tower.hstate
    if not hs then return damage end

    -- 月蚀领域：领域内魔法增伤
    local domain = has(tower, "eclipse_domain")
    if domain then
        damage = damage * (1 + (domain.fieldAmp or 0.12))
    end

    -- 血月觉醒：ATK 加成
    if hs.isAwakened and hs.awakenAtkBuff > 0 then
        damage = damage * (1 + hs.awakenAtkBuff)
    end

    -- 灵魂 ATK 加成（击杀永久累积）
    if hs.soulAtkBonus > 0 then
        damage = damage * (1 + hs.soulAtkBonus)
    end

    -- 满月状态：标记为纯粹伤害（由 Combat 处理跳过魔抗）
    if hs.fullMoonActive then
        hs._isPureDamage = true
    end

    return damage
end

-- ============================================================================
-- 被动2：攻速修正 — 血月共鸣攻速叠加
-- ============================================================================

---@param tower table
---@param speed number
---@return number
function M.ModifyAttackSpeed(tower, speed)
    local hs = tower.hstate
    if not hs then return speed end

    if hs.resonanceStacks > 0 and hs.resonanceTimer > 0 then
        local resonance = has(tower, "blood_resonance")
        local spdPerStack = resonance and resonance.spdBuffPerStack or 0.06
        speed = speed / (1 + hs.resonanceStacks * spdPerStack)
    end

    return speed
end

-- ============================================================================
-- 被动1：命中触发 — 蚀月印记叠加 + 满层爆发 + 击杀处理
-- ============================================================================

---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local hs = tower.hstate
    if not hs then return end

    -- ================================================================
    -- 蚀月之链：叠加印记
    -- ================================================================
    local eclipse = has(tower, "eclipse_chain")
    if eclipse and target.alive then
        if not hs.eclipseMarks then hs.eclipseMarks = {} end
        local targetId = target.id or tostring(target)
        local mark = hs.eclipseMarks[targetId]
        if not mark then
            mark = { stacks = 0, timer = 8.0 }
            hs.eclipseMarks[targetId] = mark
        end

        -- 觉醒期间每次叠2层，否则1层
        local addStacks = hs.isAwakened and 2 or 1
        local maxStacks = eclipse.maxStacks or 5
        local prevStacks = mark.stacks
        mark.stacks = math.min(mark.stacks + addStacks, maxStacks)
        mark.timer = eclipse.stackDuration or 8.0

        -- 施加每层魔法增伤（magicVuln 被 HeroSkills.ModifyDamage 读取）
        local dmgAmp = eclipse.dmgAmpPerStack or 0.04
        target.magicVuln = mark.stacks * dmgAmp
        target.magicVulnTimer = eclipse.stackDuration or 8.0

        -- 满层触发月蚀爆发
        if prevStacks < maxStacks and mark.stacks >= maxStacks then
            M._TriggerEclipseBurst(tower, target, eclipse)
        end
    end

    -- ================================================================
    -- 月蚀领域：击杀累积灵魂攻击力
    -- ================================================================
    if killed then
        local domain = has(tower, "eclipse_domain")
        if domain then
            local soulAtk = (domain.soulAtkPerKill or 0.03) + (hs.soulAtkPerKillBonus or 0)
            local soulCap = domain.soulCap or 0.30
            hs.soulAtkBonus = math.min(hs.soulAtkBonus + soulAtk, soulCap)
            hs.totalKills = (hs.totalKills or 0) + 1

            -- 达到上限触发满月
            if not hs.fullMoonActive and hs.soulAtkBonus >= soulCap then
                hs.fullMoonActive = true
                hs.fullMoonTimer = (domain.fullMoonDuration or 5.0) + (hs.fullMoonDurationBonus or 0)

                AddFloatingText({
                    text     = "满月!",
                    x        = tower._sx or 0,
                    y        = (tower._sy or 0) - 30,
                    life     = 1.5,
                    color    = COLOR_FULL_MOON,
                    fontSize = 18,
                })
                State.skillFlash = { type = "full_moon", timer = 0.8, tower = tower }
                print("[Heroes] crimson_moon FULL MOON activated! soulAtkBonus=" .. hs.soulAtkBonus)

                -- 满月激活全屏纯伤（月蚀天象 Tier 3）
                if (hs.fullMoonAoePct or 0) > 0 then
                    local Enemy      = require("Game.Enemy")
                    local HeroSkills = require("Game.HeroSkills")
                    local atk = HeroSkills.GetEffectiveAttack(tower)
                    local burstDmg = atk * hs.fullMoonAoePct
                    for _, e in ipairs(State.enemies) do
                        if e.alive then
                            Enemy.TakeDamage(e, burstDmg)  -- 纯伤，无视防御
                        end
                    end
                    AddFloatingText({
                        text     = "满月爆发!",
                        x        = tower._sx or 0,
                        y        = (tower._sy or 0) - 45,
                        life     = 1.2,
                        color    = COLOR_FULL_MOON,
                        fontSize = 16,
                    })
                end
            end
        end

        -- 血月共鸣：击杀刷新攻击间隔（等于额外攻击一次）
        local resonance = has(tower, "blood_resonance")
        if resonance then
            tower.attackTimer = 0
        end

        -- 清理已死亡目标的印记
        if hs.eclipseMarks then
            local targetId = target.id or tostring(target)
            hs.eclipseMarks[targetId] = nil
        end
    end
end

-- ============================================================================
-- 内部：月蚀爆发 — 满层印记触发 AoE + 血月共鸣效果
-- ============================================================================

---@param tower table
---@param target table
---@param eclipse table  eclipse_chain 技能定义
function M._TriggerEclipseBurst(tower, target, eclipse)
    local hs = tower.hstate
    local Combat     = require("Game.Combat")
    local Enemy      = require("Game.Enemy")
    local HeroSkills = require("Game.HeroSkills")

    local atk = HeroSkills.GetEffectiveAttack(tower)
    local burstPct = eclipse.burstAtkPct or 1.80
    local baseDmg  = atk * burstPct
    local burstRange = eclipse.burstRange or 60
    local rangeSq    = burstRange * burstRange

    -- 对爆发目标造成伤害
    if target.alive then
        local finalDmg = Combat.CalcFinalDamage(tower, target, baseDmg)
        Enemy.TakeDamage(target, finalDmg)
    end

    -- 溅射周围敌人
    local hitCount = 0
    for _, e in ipairs(State.enemies) do
        if e.alive and e ~= target then
            local dx = e.x - target.x
            local dy = e.y - target.y
            if dx * dx + dy * dy < rangeSq then
                local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
                Enemy.TakeDamage(e, finalDmg)
                hitCount = hitCount + 1
            end
        end
    end

    -- 重置印记层数
    local targetId = target.id or tostring(target)
    if hs.eclipseMarks and hs.eclipseMarks[targetId] then
        hs.eclipseMarks[targetId].stacks = 0
    end
    target.magicVuln = 0

    -- 飘字
    AddFloatingText({
        text     = "月蚀爆发!",
        x        = target.x + (math.random() - 0.5) * 10,
        y        = target.y - (target.typeDef and target.typeDef.size or 8) - 24,
        life     = 1.2,
        color    = COLOR_ECLIPSE_BURST,
        fontSize = 15,
    })

    hs.totalBursts = (hs.totalBursts or 0) + 1

    -- ================================================================
    -- 血月共鸣：爆发触发减魔抗 + 攻速叠加
    -- ================================================================
    local resonance = has(tower, "blood_resonance")
    if resonance then
        -- 降低目标魔抗
        local resReduce = resonance.resReduce or 0.15
        target.tagResReduce = (target.tagResReduce or 0) + resReduce
        target.tagResReduceTimer = resonance.resReduceDuration or 3.0

        -- 攻速叠加（爆发命中数 = 1目标 + AoE命中数）
        local totalHits = 1 + hitCount
        local maxStacks = resonance.spdMaxStacks or 5
        hs.resonanceStacks = math.min(hs.resonanceStacks + totalHits, maxStacks)
        hs.resonanceTimer  = resonance.spdBuffDuration or 4.0
    end

    print("[Heroes] eclipse_burst hit " .. (1 + hitCount) .. " enemies, burstDmg=" .. math.floor(baseDmg))
end

-- ============================================================================
-- 主动技能：绯红新月 — 全屏 AoE + 施加印记 + 血月觉醒
-- ============================================================================

---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "crimson_crescent" then return end

    local hs = tower.hstate
    if not hs then return end

    local Combat     = require("Game.Combat")
    local Enemy      = require("Game.Enemy")
    local HeroSkills = require("Game.HeroSkills")

    -- 全屏 AoE 伤害
    local atk = HeroSkills.GetEffectiveAttack(tower)
    local dmgMult = skill.dmgAtkPct or 3.50
    local baseDmg = atk * dmgMult

    local hitCount = 0
    for _, e in ipairs(State.enemies) do
        if e.alive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)
            hitCount = hitCount + 1

            -- 施加 3 层蚀月印记
            if not hs.eclipseMarks then hs.eclipseMarks = {} end
            local targetId = e.id or tostring(e)
            local mark = hs.eclipseMarks[targetId]
            if not mark then
                mark = { stacks = 0, timer = 8.0 }
                hs.eclipseMarks[targetId] = mark
            end
            local eclipse = has(tower, "eclipse_chain")
            local maxStacks = eclipse and eclipse.maxStacks or 5
            local addMarks = skill.markStacks or 3
            mark.stacks = math.min(mark.stacks + addMarks, maxStacks)
            mark.timer = eclipse and eclipse.stackDuration or 8.0

            -- 施加魔法增伤
            local dmgAmp = eclipse and eclipse.dmgAmpPerStack or 0.04
            e.magicVuln = mark.stacks * dmgAmp
            e.magicVulnTimer = eclipse and eclipse.stackDuration or 8.0
        end
    end

    -- 进入血月觉醒状态
    hs.isAwakened   = true
    hs.awakenTimer  = skill.awakenDuration or 6.0
    hs.awakenAtkBuff = skill.awakenAtkBuff or 0.25

    State.skillFlash = { type = "crimson_crescent", timer = 0.6, tower = tower }

    AddFloatingText({
        text     = "血月觉醒!",
        x        = tower._sx or 0,
        y        = (tower._sy or 0) - 30,
        life     = 1.5,
        color    = COLOR_RESONANCE,
        fontSize = 16,
    })

    print("[Heroes] crimson_crescent hit " .. hitCount .. " enemies, awakened for " .. hs.awakenTimer .. "s")
end

-- ============================================================================
-- 帧更新：计时器衰减（觉醒、共鸣攻速、满月、印记）
-- ============================================================================

---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    for _, tower in ipairs(towers) do
        if tower.typeDef and tower.typeDef.id == "crimson_moon" and tower.hstate then
            local hs = tower.hstate

            -- ============================================================
            -- 血月觉醒：持续时间递减
            -- ============================================================
            if hs.isAwakened and hs.awakenTimer > 0 then
                hs.awakenTimer = hs.awakenTimer - dt
                if hs.awakenTimer <= 0 then
                    hs.isAwakened    = false
                    hs.awakenTimer   = 0
                    hs.awakenAtkBuff = 0
                end
            end

            -- ============================================================
            -- 血月共鸣：攻速 buff 持续时间递减
            -- ============================================================
            if hs.resonanceTimer > 0 then
                hs.resonanceTimer = hs.resonanceTimer - dt
                if hs.resonanceTimer <= 0 then
                    hs.resonanceStacks = 0
                    hs.resonanceTimer  = 0
                end
            end

            -- ============================================================
            -- 满月状态：持续时间递减
            -- ============================================================
            if hs.fullMoonActive and hs.fullMoonTimer > 0 then
                hs.fullMoonTimer = hs.fullMoonTimer - dt
                if hs.fullMoonTimer <= 0 then
                    hs.fullMoonActive = false
                    hs.fullMoonTimer  = 0
                    hs._isPureDamage  = false
                end
            end

            -- ============================================================
            -- 蚀月印记：计时器到期后逐层衰减
            -- ============================================================
            if hs.eclipseMarks then
                for targetId, mark in pairs(hs.eclipseMarks) do
                    mark.timer = mark.timer - dt
                    if mark.timer <= 0 then
                        mark.stacks = mark.stacks - 1
                        if mark.stacks <= 0 then
                            hs.eclipseMarks[targetId] = nil
                        else
                            mark.timer = 1.0  -- 后续每1秒掉1层
                        end
                    end
                end
            end
        end
    end
end

return M
