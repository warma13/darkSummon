-- Game/Heroes/skeleton_grunt.lua
-- 骷髅长矛兵：亡灵韧性（攻速加成）

local M = {}

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

function M.ModifyAttackSpeed(tower, speed)
    local tenacity = has(tower, "undead_tenacity")
    if tenacity then
        speed = speed / (1 + (tenacity.atkSpdBonus or 0.05))
    end
    return speed
end

return M
