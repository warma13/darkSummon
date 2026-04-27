-- Game/Heroes/eternal_archfiend.lua
-- 永恒魔君：魔焰之力 (demon_flame) + 永恒侵蚀 (eternal_erode) + 灭世余烬 (worldfire_ember) + 深渊印记 (abyss_mark)
--
-- 被动1 魔焰之力：每次攻击+1层魔焰，持续5s，每层+8%暴击率+35%暴击伤害，最多8层
-- 被动2 永恒侵蚀：每次暴击+1层侵蚀，持续6s，每层+5%伤害加成；满层时30%伤害转真伤
-- 被动3 灭世余烬：暴击时35%概率对目标周围造成150%ATK范围伤害
-- 主动  深渊印记：标记血量最高敌人，受伤+40%，持续12s，死亡转移
local M = {}

local State = require("Game.State")

local AddFloatingText = State.AddFloatingText

-- 飘字颜色
local COLOR_ABYSS_MARK   = { 100, 0, 180, 255 }     -- 深紫（深渊印记）

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 被动2 永恒侵蚀：满层时将部分伤害转为真伤（跳过DEF和元素抗性）
--- 在 CalcFinalDamage 之前调用，为 ModifyDamage 钩子
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    local hs = tower.hstate
    if not hs then return damage end

    -- 永恒侵蚀：满层时 trueDmgConvert% 伤害转真伤
    local erode = has(tower, "eternal_erode")
    if erode and hs.erodeStacks >= (erode.maxStacks or 6) then
        local convertPct = erode.trueDmgConvert or 0.30
        -- 存储真伤基础值到 hstate，在 OnHit 中单独施加（跳过DEF/抗性）
        hs._pendingTrueBase = damage * convertPct
        -- 返回减少后的常规部分（走正常 CalcFinalDamage 流程含DEF等）
        return damage * (1 - convertPct)
    end

    return damage
end

--- 被动1 魔焰之力：攻击叠层 → 暴击加成
--- 被动2 永恒侵蚀：暴击叠层（由 Combat 传 isCrit 信息，这里通过检测 hstate 间接判断）
--- 被动3 灭世余烬：暴击AoE
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local hs = tower.hstate
    if not hs then return end

    -- ================================================================
    -- 被动1：魔焰之力 — 每次攻击叠层，提升暴击率/暴击伤害
    -- ================================================================
    local flame = has(tower, "demon_flame")
    if flame then
        local maxStacks = flame.maxStacks or 8
        hs.demonFlameStacks = math.min(hs.demonFlameStacks + 1, maxStacks)
        hs.demonFlameTimer  = flame.stackDuration or 5.0

        -- 刷新 bonusCritRate / bonusCritDmg（供 CalcFinalDamage 使用）
        local stacks = hs.demonFlameStacks
        hs.bonusCritRate = stacks * (flame.critRatePerStack or 0.08)
        hs.bonusCritDmg  = stacks * (flame.critDmgPerStack or 0.35)


    end

    -- ================================================================
    -- 真伤结算（来自 ModifyDamage 中永恒侵蚀的伤害转化部分）
    -- 这部分跳过了 DEF/元素抗性（因为没走 CalcFinalDamage），
    -- 但保留了暴击和伤害加成乘区（通过手动计算）
    -- ================================================================
    if hs._pendingTrueBase and hs._pendingTrueBase > 0 then
        local Enemy = require("Game.Enemy")
        if target.alive then
            local trueDmg = hs._pendingTrueBase
            -- 应用暴击乘区（与 CalcFinalDamage 一致）
            local HeroSkills = require("Game.HeroSkills")
            local critRate = HeroSkills.GetEffectiveCritRate(tower)
            if critRate > 0 and math.random() < critRate then
                local Tower = require("Game.Tower")
                local critDmg = Tower.GetEffectiveCritDmg(tower)
                if hs.bonusCritDmg and hs.bonusCritDmg > 0 then
                    critDmg = critDmg + hs.bonusCritDmg
                end
                local Config = require("Game.Config")
                trueDmg = trueDmg * (Config.BASE_CRIT_MULT + critDmg)
            end
            -- 应用伤害加成乘区
            local Tower2 = require("Game.Tower")
            local dmgBonus = Tower2.GetEffectiveDmgBonus(tower)
            if dmgBonus > 0 then
                trueDmg = trueDmg * (1 + dmgBonus)
            end
            Enemy.TakeDamage(target, trueDmg)
        end
        hs._pendingTrueBase = nil
    end

    -- ================================================================
    -- 深渊印记：标记目标死亡时转移
    -- ================================================================
    if killed and hs.abyssMarkTarget == target then
        M._TransferAbyssMark(tower)
    end
end

--- 暴击后回调（由 Combat.lua 在暴击时额外调用 HeroSkills.OnCritHit）
--- 被动2 永恒侵蚀：暴击叠侵蚀
--- 被动3 灭世余烬：暴击概率AoE
---@param tower table
---@param target table
---@param damage number 暴击造成的最终伤害
function M.OnCritHit(tower, target, damage)
    local hs = tower.hstate
    if not hs then return end

    -- ================================================================
    -- 被动2：永恒侵蚀 — 暴击叠层
    -- ================================================================
    local erode = has(tower, "eternal_erode")
    if erode then
        local maxStacks = erode.maxStacks or 6
        local prevStacks = hs.erodeStacks
        hs.erodeStacks = math.min(hs.erodeStacks + 1, maxStacks)
        hs.erodeTimer  = erode.stackDuration or 6.0

        -- 刷新 bonusDmgBonus（供 CalcFinalDamage 使用）
        hs.bonusDmgBonus = hs.erodeStacks * (erode.dmgBonusPerStack or 0.05)


    end

    -- ================================================================
    -- 被动3：灭世余烬 — 暴击时概率范围伤害
    -- ================================================================
    local ember = has(tower, "worldfire_ember")
    if ember and target.alive then
        local chance = ember.procChance or 0.35
        if math.random() < chance then
            local HeroSkills = require("Game.HeroSkills")
            local Combat     = require("Game.Combat")
            local Enemy      = require("Game.Enemy")

            local atk = HeroSkills.GetEffectiveAttack(tower)
            local aoeDmg = atk * (ember.aoeDamagePct or 1.50)
            local range  = ember.aoeRange or 60
            local rangeSq = range * range
            local hitCount = 0

            for _, e in ipairs(State.enemies) do
                if e.alive and e ~= target then
                    local dx = e.x - target.x
                    local dy = e.y - target.y
                    if dx * dx + dy * dy < rangeSq then
                        local finalDmg = Combat.CalcFinalDamage(tower, e, aoeDmg)
                        Enemy.TakeDamage(e, finalDmg)
                        hitCount = hitCount + 1
                    end
                end
            end

            print("[Heroes] worldfire_ember AoE hit " .. hitCount .. " enemies, dmg=" .. math.floor(aoeDmg))
        end
    end
end

--- 深渊印记：主动技能 — 标记场上血量最高敌人，施加增伤
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "abyss_mark" then return end

    local hs = tower.hstate
    if not hs then return end

    local Debuff = require("Game.Debuff")
    local Enemy  = require("Game.Enemy")

    -- 清除旧标记
    if hs.abyssMarkTarget and hs.abyssMarkTarget.alive then
        Debuff.Clear(hs.abyssMarkTarget, "amp_damage")
    end

    -- 寻找血量最高的存活敌人
    local bestHP    = 0
    local bestEnemy = nil
    for _, e in ipairs(State.enemies) do
        if e.alive and e.hp > bestHP then
            bestHP    = e.hp
            bestEnemy = e
        end
    end

    if bestEnemy then
        local ampRate  = skill.ampRate or 0.40
        local duration = skill.markDuration or 12.0

        Debuff.Apply(bestEnemy, "amp_damage", {
            value    = ampRate,
            duration = duration,
        })

        hs.abyssMarkTarget = bestEnemy
        hs.abyssMarkTimer  = duration

        -- 飘字
        AddFloatingText({
            text     = "深渊印记!",
            x        = bestEnemy.x + (math.random() - 0.5) * 10,
            y        = bestEnemy.y - (bestEnemy.typeDef.size or 8) - 24,
            life     = 1.2,
            color    = COLOR_ABYSS_MARK,
            fontSize = 15,
        })

        State.skillFlash = { type = "abyss_mark", timer = 0.6, tower = tower }

        print("[Heroes] abyss_mark on enemy " .. tostring(bestEnemy.id)
            .. " hp=" .. math.floor(bestHP) .. " amp=" .. ampRate)
    end
end

--- 标记转移：当标记目标死亡时，转移到下一个血量最高敌人
---@param tower table
function M._TransferAbyssMark(tower)
    local hs = tower.hstate
    if not hs or hs.abyssMarkTimer <= 0 then
        hs.abyssMarkTarget = nil
        return
    end

    local Debuff = require("Game.Debuff")
    local skill  = has(tower, "abyss_mark")
    if not skill then return end

    -- 寻找下一个血量最高敌人
    local bestHP    = 0
    local bestEnemy = nil
    for _, e in ipairs(State.enemies) do
        if e.alive and e.hp > bestHP then
            bestHP    = e.hp
            bestEnemy = e
        end
    end

    if bestEnemy then
        local ampRate = skill.ampRate or 0.40
        Debuff.Apply(bestEnemy, "amp_damage", {
            value    = ampRate,
            duration = hs.abyssMarkTimer,  -- 继承剩余时间
        })
        hs.abyssMarkTarget = bestEnemy

        print("[Heroes] abyss_mark transferred to enemy " .. tostring(bestEnemy.id))
    else
        hs.abyssMarkTarget = nil
        hs.abyssMarkTimer  = 0
    end
end

--- 帧更新：层数计时器衰减 + 深渊印记计时 + 标记转移检测
---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    local Debuff = require("Game.Debuff")

    for _, tower in ipairs(towers) do
        if tower.typeDef and tower.typeDef.id == "eternal_archfiend" and tower.hstate then
            local hs = tower.hstate

            -- ============================================================
            -- 魔焰之力：计时器到期后逐层衰减（每0.8秒掉1层）
            -- ============================================================
            if hs.demonFlameTimer and hs.demonFlameTimer > 0 then
                hs.demonFlameTimer = hs.demonFlameTimer - dt
                if hs.demonFlameTimer <= 0 then
                    hs.demonFlameStacks = hs.demonFlameStacks - 1
                    if hs.demonFlameStacks <= 0 then
                        hs.demonFlameStacks = 0
                        hs.demonFlameTimer  = nil
                        hs.bonusCritRate = 0
                        hs.bonusCritDmg  = 0
                    else
                        hs.demonFlameTimer = 0.8  -- 后续每0.8秒掉1层
                        local flame = has(tower, "demon_flame")
                        hs.bonusCritRate = hs.demonFlameStacks * (flame and flame.critRatePerStack or 0.08)
                        hs.bonusCritDmg  = hs.demonFlameStacks * (flame and flame.critDmgPerStack or 0.35)
                    end
                end
            end

            -- ============================================================
            -- 永恒侵蚀：计时器到期后逐层衰减（每1秒掉1层）
            -- ============================================================
            if hs.erodeTimer and hs.erodeTimer > 0 then
                hs.erodeTimer = hs.erodeTimer - dt
                if hs.erodeTimer <= 0 then
                    hs.erodeStacks = hs.erodeStacks - 1
                    if hs.erodeStacks <= 0 then
                        hs.erodeStacks = 0
                        hs.erodeTimer  = nil
                        hs.bonusDmgBonus = 0
                    else
                        hs.erodeTimer = 1.0  -- 后续每1秒掉1层
                        local erode = has(tower, "eternal_erode")
                        hs.bonusDmgBonus = hs.erodeStacks * (erode and erode.dmgBonusPerStack or 0.05)
                    end
                end
            end

            -- ============================================================
            -- 深渊印记：持续时间递减 + 标记目标死亡检测
            -- ============================================================
            if hs.abyssMarkTimer > 0 then
                hs.abyssMarkTimer = hs.abyssMarkTimer - dt

                -- 检测标记目标是否已死亡
                if hs.abyssMarkTarget and not hs.abyssMarkTarget.alive then
                    M._TransferAbyssMark(tower)
                end

                -- 时间到期，清除标记
                if hs.abyssMarkTimer <= 0 then
                    if hs.abyssMarkTarget and hs.abyssMarkTarget.alive then
                        Debuff.Clear(hs.abyssMarkTarget, "amp_damage")
                    end
                    hs.abyssMarkTarget = nil
                    hs.abyssMarkTimer  = 0
                end
            end
        end
    end
end

return M
