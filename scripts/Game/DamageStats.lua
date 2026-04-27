-- Game/DamageStats.lua
-- 战斗伤害统计：记录每个塔实例的伤害、暴击、击杀数据

local DamageStats = {}

-- towerId -> { heroId, heroName, color, icon, star, totalDmg, critCount, killCount, bossDmg, bossCritCount, bossKillCount }
local _stats = {}
local _totalDmg = 0
local _totalBossDmg = 0

-- 缓存机制：避免 GetSorted 每次调用都重建排序列表
local _dirty = true                -- Record/Reset 时置 true
local _cachedAll = {}              -- 缓存：全部伤害排序列表
local _cachedBoss = {}             -- 缓存：Boss 伤害排序列表
local _cachedAllTotal = 0
local _cachedBossTotal = 0

local _sortFunc = function(a, b) return a.totalDmg > b.totalDmg end

--- 重置本场战斗统计（每次新战斗第一波开始时调用）
function DamageStats.Reset()
    _stats = {}
    _totalDmg = 0
    _totalBossDmg = 0
    _dirty = true
    -- 清空缓存列表（复用 table）
    for i = #_cachedAll, 1, -1 do _cachedAll[i] = nil end
    for i = #_cachedBoss, 1, -1 do _cachedBoss[i] = nil end
end

--- 记录一次伤害
---@param tower table    塔实例（含 id / typeDef / star）
---@param dmg   number   实际伤害值
---@param isCrit boolean 是否暴击
---@param killed boolean 是否击杀目标
---@param isBoss? boolean 目标是否为 Boss
function DamageStats.Record(tower, dmg, isCrit, killed, isBoss)
    if not dmg or dmg <= 0 or dmg ~= dmg or dmg == math.huge then return end
    _dirty = true
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
            bossDmg      = 0,
            bossCritCount = 0,
            bossKillCount = 0,
        }
    end
    local s = _stats[tid]
    s.totalDmg  = s.totalDmg  + dmg
    if isCrit  then s.critCount = s.critCount + 1 end
    if killed  then s.killCount = s.killCount + 1 end
    _totalDmg = _totalDmg + dmg
    if isBoss then
        s.bossDmg = s.bossDmg + dmg
        if isCrit  then s.bossCritCount = s.bossCritCount + 1 end
        if killed  then s.bossKillCount = s.bossKillCount + 1 end
        _totalBossDmg = _totalBossDmg + dmg
    end
end

--- 获取 Boss 总伤害（轻量级，适合每帧调用）
---@return number
function DamageStats.GetTotalBossDmg()
    return _totalBossDmg
end

--- 按总伤害排序后返回列表 + 全场总伤害
--- 使用脏标记缓存：仅在数据变化后才重建排序列表
---@param bossOnly? boolean 仅返回 Boss 伤害数据
---@return table list      排序后的统计条目列表
---@return number totalDmg 全场总伤害
function DamageStats.GetSorted(bossOnly)
    if not _dirty then
        -- 缓存命中：直接返回
        if bossOnly then
            return _cachedBoss, _cachedBossTotal
        else
            return _cachedAll, _cachedAllTotal
        end
    end
    -- 重建两个缓存列表
    _dirty = false

    -- 清空并复用已有 table
    local listAll = _cachedAll
    local listBoss = _cachedBoss
    for i = #listAll, 1, -1 do listAll[i] = nil end
    for i = #listBoss, 1, -1 do listBoss[i] = nil end

    for _, s in pairs(_stats) do
        listAll[#listAll + 1] = s
        if s.bossDmg > 0 then
            -- Boss 列表需要字段映射（totalDmg → bossDmg）
            listBoss[#listBoss + 1] = {
                heroId    = s.heroId,
                heroName  = s.heroName,
                color     = s.color,
                icon      = s.icon,
                star      = s.star,
                totalDmg  = s.bossDmg,
                critCount = s.bossCritCount,
                killCount = s.bossKillCount,
            }
        end
    end

    table.sort(listAll, _sortFunc)
    table.sort(listBoss, _sortFunc)

    _cachedAllTotal = _totalDmg
    _cachedBossTotal = _totalBossDmg

    if bossOnly then
        return _cachedBoss, _cachedBossTotal
    else
        return _cachedAll, _cachedAllTotal
    end
end

return DamageStats
