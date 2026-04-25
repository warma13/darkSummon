-- Game/Heroes/necromancer.lua
-- 死灵术士：深度冻结 (deep_freeze) + 诅咒标记 (curse_mark) + 灵魂锁链 (soul_chain)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 深度冻结：将减速率提升至 45%
---@param tower table
---@param rate number
---@param target table|nil
---@return number
function M.ModifySlowRate(tower, rate, target)
    local deepFreeze = has(tower, "deep_freeze")
    if deepFreeze then return deepFreeze.newSlowRate end
    return rate
end

--- 灵魂锁链：减速扩散给周围敌人
---@param tower table
---@param target table
---@param slowDuration number
---@param slowRate number
function M.HandleSlowSpread(tower, target, slowDuration, slowRate)
    local chain = has(tower, "soul_chain")
    if not chain then return end

    local Enemy = require("Game.Enemy")
    local spreadCount = 0
    local maxTargets = chain.chainMaxTargets or 2
    local chainRange = chain.chainRange or 40

    for _, e in ipairs(State.enemies) do
        if e.alive and e ~= target and spreadCount < maxTargets then
            local dx = e.x - target.x
            local dy = e.y - target.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < chainRange and not e.slowSpread then
                Enemy.ApplySlow(e, slowDuration, slowRate)
                e.slowSpread = true
                spreadCount = spreadCount + 1
            end
        end
    end
end

--- 诅咒标记：被减速敌人每帧受 ATK×pct 伤害（全局帧更新）
---@param dt number
function M.UpdateGlobal(dt)
    local curseTowers = nil
    for _, tower in ipairs(State.towers) do
        local curse = has(tower, "curse_mark")
        if curse then
            if not curseTowers then curseTowers = {} end
            curseTowers[#curseTowers + 1] = {
                tower = tower,
                pct   = curse.curseDmgAtkPct,
            }
        end
    end
    if not curseTowers then return end

    local Enemy = require("Game.Enemy")
    for _, e in ipairs(State.enemies) do
        if e.alive and e.slowTimer and e.slowTimer > 0 then
            for _, ct in ipairs(curseTowers) do
                local dmg = ct.tower.attack * ct.pct * dt
                Enemy.TakeDamage(e, dmg)
            end
        end
    end
end

return M
