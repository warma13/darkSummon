-- Game/Heroes/frost_witch.lua
-- 霜冻女巫：极寒之触 (extreme_cold) + 冰冻概率 (freeze_chance) + 暴风雪 (blizzard)
local M = {}

local State  = require("Game.State")
local Config = require("Game.Config")
local Debuff = require("Game.Debuff")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 极寒之触：将减速率提升至 35%
---@param tower table
---@param rate number
---@param target table|nil
---@return number
function M.ModifySlowRate(tower, rate, target)
    local extremeCold = has(tower, "extreme_cold")
    if extremeCold then return extremeCold.newSlowRate or 0.35 end
    return rate
end

--- 冰冻概率：命中后概率冰冻（BOSS 降级为减速）
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local freeze = has(tower, "freeze_chance")
    if not freeze then return end
    if not target.alive then return end
    if math.random() >= (freeze.chance or 0.10) then return end

    local Enemy = require("Game.Enemy")
    if target.isBoss then
        if Config.BOSS_BALANCE.freezeImmune then
            Enemy.ApplySlow(target, freeze.freezeDuration or 1.5,
                (freeze.bossFallbackSlow or 0.50) * (Config.BOSS_BALANCE.slowEfficiency or 0.50))
        end
    else
        Enemy.ApplySlow(target, freeze.freezeDuration or 1.5, 1.0)
        if Debuff.Apply(target, "frozen", { duration = freeze.freezeDuration or 1.5 }) then
            State.AddFloatingText({
                text     = "冰冻",
                x        = target.x + (math.random() - 0.5) * 10,
                y        = target.y - (target.typeDef.size or 8) - 16,
                life     = 0.6,
                color    = { 100, 180, 255, 255 },
                fontSize = 12,
            })
        end
    end
end

--- 暴风雪：主动，对全场敌人施加大幅减速
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "blizzard" then return end
    local Enemy = require("Game.Enemy")
    for _, e in ipairs(State.enemies) do
        if e.alive then
            local slowRate = skill.slowPct or 0.40
            if e.isBoss then
                slowRate = slowRate * (Config.BOSS_BALANCE.slowEfficiency or 0.50)
            end
            Enemy.ApplySlow(e, skill.duration or 3.0, slowRate)
        end
    end
    State.skillFlash = { type = "blizzard", timer = 0.5, tower = tower }
end

return M
