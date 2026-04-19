-- Game/DamageStats.lua
-- 战斗伤害统计：记录每个塔实例的伤害、暴击、击杀数据

local DamageStats = {}

-- towerId -> { heroId, heroName, color, icon, star, totalDmg, critCount, killCount }
local _stats = {}
local _totalDmg = 0

--- 重置本场战斗统计（每次新战斗第一波开始时调用）
function DamageStats.Reset()
    _stats = {}
    _totalDmg = 0
end

--- 记录一次伤害
---@param tower table    塔实例（含 id / typeDef / star）
---@param dmg   number   实际伤害值
---@param isCrit boolean 是否暴击
---@param killed boolean 是否击杀目标
function DamageStats.Record(tower, dmg, isCrit, killed)
    if dmg <= 0 then return end
    local tid = tower.id
    if not _stats[tid] then
        _stats[tid] = {
            heroId    = tower.typeDef.id,
            heroName  = tower.typeDef.name,
            color     = tower.typeDef.color,
            icon      = tower.typeDef.icon,
            star      = tower.star,
            totalDmg  = 0,
            critCount = 0,
            killCount = 0,
        }
    end
    local s = _stats[tid]
    s.totalDmg  = s.totalDmg  + dmg
    if isCrit  then s.critCount = s.critCount + 1 end
    if killed  then s.killCount = s.killCount + 1 end
    _totalDmg = _totalDmg + dmg
end

--- 按总伤害排序后返回列表 + 全场总伤害
---@return table list      排序后的统计条目列表
---@return number totalDmg 全场总伤害
function DamageStats.GetSorted()
    local list = {}
    for _, s in pairs(_stats) do
        table.insert(list, s)
    end
    table.sort(list, function(a, b) return a.totalDmg > b.totalDmg end)
    return list, _totalDmg
end

return DamageStats
