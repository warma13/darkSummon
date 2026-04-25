-- Game/Heroes/armor_breaker.lua
-- 破甲者：精准打击 (precise_strike) + 破甲叠加 (armor_stack) + 致命弱点 (fatal_weakness)
local M = {}

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 致命弱点：破甲叠满时额外伤害加成
---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    if target.armorBreakStacks then
        local stackSkill = has(tower, "armor_stack")
        if stackSkill and target.armorBreakStacks >= (stackSkill.maxStacks or 3) then
            local bonus = has(tower, "fatal_weakness")
            if bonus then
                damage = damage * (1 + bonus.fullStackBonus)
            end
        end
    end
    return damage
end

--- 精准打击：命中附加破甲层（护甲削减持续 N 秒）
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local armorBreak = has(tower, "precise_strike")
    if not armorBreak then return end
    if not target.alive then return end

    target.armorBreakStacks = (target.armorBreakStacks or 0) + 1
    local stackSkill = has(tower, "armor_stack")
    local maxStacks = (stackSkill and stackSkill.maxStacks) or 1
    target.armorBreakStacks = math.min(target.armorBreakStacks, maxStacks)
    target.armorBreakValue  = armorBreak.armorBreak
    target.armorBreakTimer  = armorBreak.armorBreakDuration or 5.0
end

return M
