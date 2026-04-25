-- Game/Heroes/leader.lua
-- 暗影领主：暗影支配 (shadow_dominion) + 君主意志 (lord_will) + 暗影吞噬 (shadow_devour)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 暗影支配：全体友军攻击加成（全局光环）
---@param source table
---@param towers table
function M.UpdateAura(source, towers)
    local dominion = has(source, "shadow_dominion")
    if not dominion then return end
    local buff = dominion.globalAtkBuff
    for _, t in ipairs(towers) do
        t.auraAtkBuff = t.auraAtkBuff + buff
    end
end

--- 君主意志：击杀时概率缩短主动技能 CD
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    if not killed then return end
    local lordWill = has(tower, "lord_will")
    if not lordWill then return end
    if math.random() >= lordWill.chance then return end

    if tower.skillTimers then
        for skillId, _ in pairs(tower.skillTimers) do
            tower.skillTimers[skillId] = math.max(0,
                tower.skillTimers[skillId] - (lordWill.cdResetAmount or 1.0))
        end
    end
end

--- 暗影吞噬：主动，对全场敌人造成伤害
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "shadow_devour" then return end
    local Enemy  = require("Game.Enemy")
    local Combat = require("Game.Combat")
    local baseDmg = tower.attack * skill.damagePct
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)
        end
    end
    State.skillFlash = { type = "shadow_devour", timer = 0.5, tower = tower }
end

return M
