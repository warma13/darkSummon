-- Game/Heroes/ghost_assassin.lua
-- 幽魂刺客：致命标记（标记目标增伤12%）

local M = {}

local Debuff = require("Game.Debuff")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

function M.OnHit(tower, target, _killed)
    local markSkill = has(tower, "lethal_mark")
    if markSkill and target.alive then
        Debuff.Apply(target, "amp_damage", {
            value    = markSkill.ampRate or 0.12,
            duration = markSkill.duration or 3.0,
        })
    end
end

return M
