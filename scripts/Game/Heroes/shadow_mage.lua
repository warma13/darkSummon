-- Game/Heroes/shadow_mage.lua
-- 暗影法师：暗影穿透 (shadow_pierce) + 灵魂收割 (soul_reap) + 虚空风暴 (void_storm)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 暗影穿透：概率无视护盾；灵魂收割：消耗击杀叠层提升伤害
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    -- 暗影穿透
    local pierce = has(tower, "shadow_pierce")
    if pierce and target.shield and target.shield > 0 then
        if math.random() < pierce.chance then
            target.piercedThisHit = true
        end
    end
    -- 灵魂收割叠层消耗
    local hs = tower.hstate
    if hs and hs.soulReapStacks > 0 then
        local reap = has(tower, "soul_reap")
        if reap then
            damage = damage * (1 + hs.soulReapStacks * reap.killDmgBonus)
            hs.soulReapStacks = 0
        end
    end
    return damage
end

--- 灵魂收割：击杀时叠层（下次攻击消耗）
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    if not killed then return end
    local reap = has(tower, "soul_reap")
    if reap and tower.hstate then
        tower.hstate.soulReapStacks = math.min(
            tower.hstate.soulReapStacks + 1,
            reap.maxStacks or 3
        )
    end
end

--- 虚空风暴：主动，对全场敌人造成大范围伤害
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "void_storm" then return end
    local Enemy  = require("Game.Enemy")
    local Combat = require("Game.Combat")
    local baseDmg = tower.attack * skill.damagePct
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)
        end
    end
    State.skillFlash = { type = "void_storm", timer = 0.5, tower = tower }
end

return M
