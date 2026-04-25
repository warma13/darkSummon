-- Game/Heroes/inferno_flame.lua
-- 烈焰使者：强化灼烧 (enhanced_burn) + 火焰蔓延 (fire_spread) + 涅槃之炎 (nirvana_flame)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 强化灼烧 + 涅槃之炎：提升 DOT 伤害；对 BOSS 改为 ATK×pct
---@param tower table
---@param dmg number
---@param target table|nil
---@return number
function M.ModifyDotDamage(tower, dmg, target)
    local enhanced = has(tower, "enhanced_burn")
    if enhanced then
        dmg = dmg * enhanced.dotMultiplier
    end
    local nirvana = has(tower, "nirvana_flame")
    if nirvana and target and target.isBoss then
        local bossAtk = tower.attack * nirvana.bossAtkPct
        if bossAtk > dmg then dmg = bossAtk end
    end
    return dmg
end

--- 火焰蔓延：击杀携带 DOT 的目标时，将剩余 DOT 传递给最近的敌人
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    if not killed then return end
    local fireSpread = has(tower, "fire_spread")
    if not fireSpread then return end
    if not (target.dotTimer and target.dotTimer > 0) then return end

    local Enemy = require("Game.Enemy")
    local bestDist = 60
    local bestEnemy = nil
    for _, e in ipairs(State.enemies) do
        if e.alive and e ~= target then
            local dx = e.x - target.x
            local dy = e.y - target.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < bestDist then
                bestDist = dist
                bestEnemy = e
            end
        end
    end
    if bestEnemy then
        local Config = require("Game.Config")
        if not (bestEnemy.isBoss and Config.BOSS_BALANCE.dotSpreadImmune) then
            Enemy.ApplyDOT(bestEnemy, target.dotDamage or 0, target.dotTimer)
        end
    end
end

return M
