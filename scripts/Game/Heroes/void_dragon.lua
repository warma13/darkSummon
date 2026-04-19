-- Game/Heroes/void_dragon.lua
-- 虚空龙王：龙息灼烧 (dragon_breath_dot) + 虚空撕裂 (void_tear) + 龙王之怒 (dragon_wrath)
local M = {}

local State = require("Game.State")
local Config = require("Game.Config")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 虚空撕裂：对 BOSS 造成额外伤害
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    local voidTear = has(tower, "void_tear")
    if voidTear and target.isBoss then
        damage = damage * (1 + (voidTear.bossExtraDmg or 0.50))
    end
    return damage
end

--- 龙息灼烧：命中后附带链式 DOT
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local dragonDot = has(tower, "dragon_breath_dot")
    if not dragonDot then return end
    if not target.alive then return end

    local Enemy  = require("Game.Enemy")
    local dotDmg = tower.attack * (dragonDot.dotAtkPct or 0.10)
    Enemy.ApplyDOT(target, dotDmg, dragonDot.dotDuration or 3.0)
end

--- 龙王之怒：主动，全场伤害 + 减速
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "dragon_wrath" then return end
    local Enemy  = require("Game.Enemy")
    local Combat = require("Game.Combat")
    local baseDmg = tower.attack * (skill.damagePct or 0.50)
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)
            if e.alive and skill.slowPct then
                local slowRate = skill.slowPct
                if e.isBoss then
                    slowRate = slowRate * (Config.BOSS_BALANCE.slowEfficiency or 0.50)
                end
                Enemy.ApplySlow(e, skill.slowDuration or 3.0, slowRate)
            end
        end
    end
    State.skillFlash = { type = "dragon_wrath", timer = 0.5, tower = tower }
end

return M
