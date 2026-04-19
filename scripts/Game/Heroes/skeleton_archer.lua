-- Game/Heroes/skeleton_archer.lua
-- 骷髅弓手：连射（20%概率），弱点标记（目标增伤10%）

local M = {}

local Debuff = require("Game.Debuff")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

function M.ShouldMultiShot(tower)
    local multi = has(tower, "multi_shot")
    if multi then
        return math.random() < (multi.chance or 0.20)
    end
    return false
end

function M.OnHit(tower, target, _killed)
    local markSkill = has(tower, "weak_mark")
    if markSkill and target.alive then
        Debuff.Apply(target, "amp_damage", {
            value    = markSkill.bonusDmg or 0.10,
            duration = markSkill.duration or 3.0,
        })
    end
end

return M
