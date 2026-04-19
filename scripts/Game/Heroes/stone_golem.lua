-- Game/Heroes/stone_golem.lua
-- 石头魔像：沉重一击 (heavy_strike) + 碎石溅射 (rock_splash)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 沉重一击：将减速率提升至 30%
---@param tower table
---@param rate number
---@param target table|nil
---@return number
function M.ModifySlowRate(tower, rate, target)
    local heavy = has(tower, "heavy_strike")
    if heavy then return heavy.newSlowRate or 0.30 end
    return rate
end

--- 碎石溅射：命中后 20% 概率对周围敌人施加减速
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local splash = has(tower, "rock_splash")
    if not splash then return end
    if not target.alive then return end
    if math.random() >= (splash.chance or 0.20) then return end

    local Enemy = require("Game.Enemy")
    local splashRange = splash.splashRange or 40
    local splashRangeSq = splashRange * splashRange
    local dur = splash.slowDuration or 1.5
    local rate = splash.slowRate or 0.25

    for _, e in ipairs(State.enemies) do
        if e.alive and e ~= target then
            local dx = e.x - target.x
            local dy = e.y - target.y
            if dx * dx + dy * dy <= splashRangeSq then
                if e.isBoss then
                    Enemy.ApplySlow(e, dur, rate * 0.50)
                else
                    Enemy.ApplySlow(e, dur, rate)
                end
            end
        end
    end
end

return M
