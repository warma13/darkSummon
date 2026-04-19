-- Game/Heroes/hell_hound.lua
-- 地狱犬：烈焰喷息（DOT伤害+30%）

local M = {}

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

function M.ModifyDotDamage(tower, dmg, _target)
    local flameBreath = has(tower, "flame_breath")
    if flameBreath then
        dmg = dmg * (flameBreath.dotMultiplier or 1.3)
    end
    return dmg
end

return M
