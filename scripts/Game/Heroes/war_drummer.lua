-- Game/Heroes/war_drummer.lua
-- 战鼓祭司：士气鼓舞 (morale_boost) + 战鼓节拍 (war_rhythm) + 英勇战歌 (heroic_anthem)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 战鼓光环：对范围内所有友军提供攻击 + 攻速加成
---@param source table  战鼓祭司自身
---@param towers table  全部塔列表
function M.UpdateAura(source, towers)
    if source.typeDef.special ~= "support" then return end
    local morale = has(source, "morale_boost")
    local rhythm  = has(source, "war_rhythm")
    if not morale and not rhythm then return end

    local auraRange   = source.typeDef.auraRange or 80
    local auraRangeSq = auraRange * auraRange
    local atkBuff = (morale and morale.atkBuff) or source.typeDef.atkBuff or 0.10
    local spdBuff = (rhythm and rhythm.spdBuff) or source.typeDef.spdBuff or 0

    local sx, sy = source._sx, source._sy
    for _, t in ipairs(towers) do
        if t ~= source then
            local dx = t._sx - sx
            local dy = t._sy - sy
            if dx * dx + dy * dy <= auraRangeSq then
                t.auraAtkBuff = t.auraAtkBuff + atkBuff
                t.auraSpdBuff = t.auraSpdBuff + spdBuff
            end
        end
    end
end

--- 英勇战歌：主动，为全体友军提供短暂大幅攻击加成
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "heroic_anthem" then return end
    State.heroicAnthemBuff = {
        atkMult = skill.atkBuffPct or 0.25,
        timer   = skill.duration  or 5.0,
    }
    State.skillFlash = { type = "heroic_anthem", timer = 0.5, tower = tower }
end

return M
