-- Game/Heroes/abyss_hunter.lua
-- 深渊猎手：猎杀本能 (hunt_instinct) + 致命弩弓 (deadly_crossbow) + 深渊之箭 (abyss_arrow)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 猎杀本能：对 BOSS 造成额外伤害
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    local hunt = has(tower, "hunt_instinct")
    if hunt and target.isBoss then
        damage = damage * (1 + hunt.bossExtraDmg)
    end
    return damage
end

--- 深渊之箭：主动，对血量最高的敌人造成百分比血量伤害
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "abyss_arrow" then return end
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
    State.skillFlash = { type = "abyss_arrow", timer = 0.5, tower = tower }
end

return M
