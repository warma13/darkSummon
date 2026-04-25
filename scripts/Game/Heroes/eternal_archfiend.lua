-- Game/Heroes/eternal_archfiend.lua
-- 永恒魔君：魔君打击 (archfiend_strike) + 永恒之力 (eternal_power) + 灭世之炎 (worldfire) + 终焉审判 (final_judgment)
local M = {}

local State = require("Game.State")
local Config = require("Game.Config")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 永恒之力：击杀叠层提升本次攻击伤害
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    if tower.killAtkStacks and tower.killAtkStacks > 0 then
        local eternal = has(tower, "eternal_power")
        if eternal then
            damage = damage * (1 + tower.killAtkStacks * eternal.killAtkBonus)
        end
    end
    return damage
end

--- 永恒之力：击杀叠层；终焉审判：对低血量目标处决
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    -- 永恒之力：击杀叠层（每波重置）
    if killed then
        local eternal = has(tower, "eternal_power")
        if eternal then
            tower.killAtkStacks = math.min(
                (tower.killAtkStacks or 0) + 1,
                math.floor(eternal.maxBonus / eternal.killAtkBonus)
            )
        end
    end

    -- 终焉审判：HP 低于阈值时处决（BOSS 免疫→固定伤害）
    local judgment = has(tower, "final_judgment")
    if judgment and target.alive then
        local threshold = judgment.executeThreshold
        if target.hp / target.maxHP < threshold then
            local Enemy = require("Game.Enemy")
            if target.isBoss then
                if Config.BOSS_BALANCE.executeImmune then
                    local Combat  = require("Game.Combat")
                    local baseDmg = tower.attack * judgment.bossFixedAtkMult
                    local finalDmg = Combat.CalcFinalDamage(tower, target, baseDmg)
                    Enemy.TakeDamage(target, finalDmg)
                end
            else
                Enemy.TakeDamage(target, target.hp + 1)
            end
        end
    end
end

--- 灭世之炎：主动，对血量最高敌人造成百分比血量伤害
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "worldfire" then return end
    local Enemy  = require("Game.Enemy")
    local Combat = require("Game.Combat")

    local bestHP    = 0
    local bestEnemy = nil
    for _, e in ipairs(State.enemies) do
        if e.alive and e.hp > bestHP then
            bestHP    = e.hp
            bestEnemy = e
        end
    end
    if bestEnemy then
        local baseDmg = bestEnemy.hp * skill.hpPct
        if bestEnemy.isBoss and skill.bossAtkCap then
            baseDmg = math.min(baseDmg, tower.attack * skill.bossAtkCap)
        end
        local finalDmg = Combat.CalcFinalDamage(tower, bestEnemy, baseDmg)
        Enemy.TakeDamage(bestEnemy, finalDmg)
    end
    State.skillFlash = { type = "worldfire", timer = 0.5, tower = tower }
end

return M
