-- Game/Heroes/fate_weaver.lua
-- 命运织者：命运之线 (fate_thread) + 时间编织 (time_weave) + 因果律 (causality) + 命运终章 (fate_finale)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 命运之线 + 因果律：全局光环（每帧刷新 State 标记）
---@param source table
---@param towers table
function M.UpdateAura(source, towers)
    -- 命运之线：全局降低敌人治愈
    local fateThread = has(source, "fate_thread")
    if fateThread then
        State.healReduction = math.max(State.healReduction or 0, fateThread.healReduction)
    end
    -- 因果律：全体友方概率双倍伤害
    local causality = has(source, "causality")
    if causality then
        State.causalityActive = true
        State.causalityChance = math.max(State.causalityChance or 0, causality.doubleDmgChance)
    end
end

--- 时间编织：主动，重置全体友方塔主动技能 CD
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "time_weave" then return end
    for _, t in ipairs(State.towers) do
        if t.skillTimers then
            for sId, _ in pairs(t.skillTimers) do
                if sId ~= "time_weave" then
                    t.skillTimers[sId] = 0
                end
            end
        end
    end
    State.skillFlash = { type = "time_weave", timer = 0.5, tower = tower }
end

return M
