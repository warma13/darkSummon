-- Game/Heroes/fallen_archangel.lua
-- 堕落大天使：神罚之光 (divine_judgment_light) + 天使审判 (angel_judgment) + 堕落荣光 (fallen_glory)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 神罚之光：对带有增伤标记的目标追加伤害（通过 target.ampDamage 传递，与标记系统共用）
--- 注意：ampDamage 已在调度器 ModifyDamage 共享层处理，此处无需重复
--- 堕落荣光：范围内友军暴击率光环
---@param source table  大天使自身
---@param towers table  全部塔列表
function M.UpdateAura(source, towers)
    local glory = has(source, "fallen_glory")
    if not glory then return end

    local auraRange   = glory.auraRange or 100
    local auraRangeSq = auraRange * auraRange
    local critBuff    = glory.critRateBuff or 0.12
    local sx, sy      = source._sx, source._sy

    for _, t in ipairs(towers) do
        if t ~= source then
            local dx = t._sx - sx
            local dy = t._sy - sy
            if dx * dx + dy * dy <= auraRangeSq then
                t.auraCritRateBuff = t.auraCritRateBuff + critBuff
            end
        end
    end
end

--- 天使审判：主动，对全场敌人造成伤害
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "angel_judgment" then return end
    local Enemy  = require("Game.Enemy")
    local Combat = require("Game.Combat")
    local baseDmg = tower.attack * (skill.damagePct or 0.30)
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg = Combat.CalcFinalDamage(tower, e, baseDmg)
            Enemy.TakeDamage(e, finalDmg)
        end
    end
    State.skillFlash = { type = "angel_judgment", timer = 0.5, tower = tower }
end

return M
