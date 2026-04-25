-- Game/Heroes/demon_warrior.lua
-- 恶魔战士：恶魔之怒（随波次加速）

local State = require("Game.State")

local M = {}

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

function M.ModifyAttackSpeed(tower, speed)
    local fury = has(tower, "demon_fury")
    if fury then
        local bonus = math.min(
            State.currentWave * fury.bonusPerWave,
            fury.maxBonus
        )
        speed = speed / (1 + bonus)
    end
    return speed
end

return M
