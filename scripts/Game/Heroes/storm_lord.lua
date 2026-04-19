-- Game/Heroes/storm_lord.lua
-- 风暴领主：雷霆打击 (thunder_strike) + 风暴之眼 (storm_eye) + 天降雷霆 (divine_thunder)
local M = {}

local State = require("Game.State")
local Config = require("Game.Config")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 风暴之眼：增加攻击范围
---@param tower table
---@param range number
---@return number
function M.ModifyRange(tower, range)
    local stormEye = has(tower, "storm_eye")
    if stormEye then
        range = range + (stormEye.rangeBonus or 20)
    end
    return range
end

--- 天降雷霆：主动，对全场敌人造成伤害并减速
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "divine_thunder" then return end
    local Enemy  = require("Game.Enemy")
    local Combat = require("Game.Combat")
    local baseDmg = tower.attack * (skill.damagePct or 0.30)
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)
        end
    end
    -- 附带减速
    if skill.slowPct and skill.slowDuration then
        for _, e in ipairs(State.enemies) do
            if e.alive then
                local slowRate = skill.slowPct
                if e.isBoss then
                    slowRate = slowRate * (Config.BOSS_BALANCE.slowEfficiency or 0.50)
                end
                Enemy.ApplySlow(e, skill.slowDuration, slowRate)
            end
        end
    end
    State.skillFlash = { type = "divine_thunder", timer = 0.5, tower = tower }
end

return M
