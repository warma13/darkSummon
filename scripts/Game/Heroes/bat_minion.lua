-- Game/Heroes/bat_minion.lua
-- 蝙蝠爪牙：吸血本能（命中概率减速）

local M = {}

local _Enemy
local function GetEnemy()
    if not _Enemy then _Enemy = require("Game.Enemy") end
    return _Enemy
end

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

function M.OnHit(tower, target, killed)
    local vampInst = has(tower, "vampire_instinct")
    if vampInst and target.alive then
        if math.random() < (vampInst.chance or 0.10) then
            GetEnemy().ApplySlow(target, vampInst.slowDuration or 1.0, vampInst.slowRate or 0.10)
        end
    end
end

return M
