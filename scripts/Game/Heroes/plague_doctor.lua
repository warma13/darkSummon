-- Game/Heroes/plague_doctor.lua
-- 瘟疫术士：剧毒瘴气 (toxic_miasma) + 感染扩散 (infection_spread) + 瘟疫爆发 (plague_burst)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 剧毒瘴气：DOT 期间降低目标护甲抵抗（标记给 Combat 处理）
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    local toxic = has(tower, "toxic_miasma")
    if toxic and target.dotTimer and target.dotTimer > 0 then
        target.armorReduceFromDot = toxic.armorReduce or 0.05
    end
    return damage
end

--- 感染扩散：命中携带 DOT 的目标时，将 DOT 扩散给附近敌人
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local spread = has(tower, "infection_spread")
    if not spread then return end
    if not target.alive then return end
    if not (target.dotTimer and target.dotTimer > 0) then return end
    if target.dotSpread then return end  -- 不二次扩散

    local Enemy = require("Game.Enemy")
    local Config = require("Game.Config")
    local spreadRange   = spread.spreadRange or 30
    local spreadRangeSq = spreadRange * spreadRange
    local spreadCount   = 0
    local maxTargets    = spread.spreadMaxTargets or 2

    for _, e in ipairs(State.enemies) do
        if e.alive and e ~= target and spreadCount < maxTargets then
            local dx = e.x - target.x
            local dy = e.y - target.y
            if dx * dx + dy * dy < spreadRangeSq then
                if not (target.isBoss and Config.BOSS_BALANCE.dotSpreadImmune) then
                    local spreadDmg = (target.dotDamage or 0) * (spread.spreadRatio or 0.50)
                    Enemy.ApplyDOT(e, spreadDmg, target.dotTimer)
                    e.dotSpread = true
                    spreadCount = spreadCount + 1
                end
            end
        end
    end
end

--- 瘟疫爆发：主动，引爆全场所有 DOT 并清除
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "plague_burst" then return end
    local Enemy = require("Game.Enemy")
    for _, e in ipairs(State.enemies) do
        if e.alive and e.dotTimer and e.dotTimer > 0 then
            local burstDmg = (e.dotDamage or 0) * e.dotTimer * (skill.burstMult or 2.0)
            Enemy.TakeDamage(e, burstDmg)
            e.dotTimer = 0
        end
    end
    State.skillFlash = { type = "plague_burst", timer = 0.5, tower = tower }
end

return M
