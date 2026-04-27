-- Game/RuneData.lua
-- 深渊符文系统 — 数据与逻辑
-- 符文生成/装备/洗练/分解/属性汇总

local Config = require("Game.Config")
local RuneConfig = require("Game.Config_Runes")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local SaveRegistry = require("Game.SaveRegistry")
local InventoryData = require("Game.InventoryData")
local TodayKey = require("Game.DateUtil").TodayKey

local RuneData = {}

-- ============================================================================
-- 内部状态（运行时由 HeroData.runeData 驱动）
-- ============================================================================

--- 确保 runeData 结构存在
local function EnsureData()
    if not HeroData.runeData then
        HeroData.runeData = {
            bag = {},           -- 符文背包 [{...rune}]
            equipped = {},      -- { [heroId] = { [slotIdx] = rune } }
            bagCapacity = RuneConfig.BAG_CAPACITY,
            nextId = 1,
            abyssRift = {       -- 深渊裂隙副本进度
                dailyFreeUsed = 0,
                dailyAdUsed = 0,
                lastResetDay = "",
                bestWave = 0,           -- 最佳通关波次（扫荡用）
                lastDifficultyId = "",  -- 上次挑战难度（扫荡用）
            },
        }
    end
    -- 兼容旧存档：补齐字段
    local d = HeroData.runeData
    if not d.bag then d.bag = {} end
    if not d.equipped then d.equipped = {} end
    if not d.bagCapacity then d.bagCapacity = RuneConfig.BAG_CAPACITY end
    if not d.nextId then d.nextId = 1 end
    if not d.abyssRift then
        d.abyssRift = { dailyFreeUsed = 0, dailyAdUsed = 0, lastResetDay = "", bestWave = 0, lastDifficultyId = "" }
    end
    -- 兼容旧存档：补齐扫荡字段
    if d.abyssRift.bestWave == nil then d.abyssRift.bestWave = 0 end
    if d.abyssRift.lastDifficultyId == nil then d.abyssRift.lastDifficultyId = "" end
    return d
end

--- 生成唯一符文 ID
local function NextRuneId()
    local d = EnsureData()
    local id = d.nextId
    d.nextId = id + 1
    return id
end

-- ============================================================================
-- 随机生成
-- ============================================================================

--- 加权随机选取品质
---@param qualityMult? number  品质加成倍率(困难/噩梦提高高品质概率)
---@return table  RuneConfig.QUALITIES 中的一项
local function RollQuality(qualityMult)
    qualityMult = qualityMult or 1.0
    -- 计算调整后的权重
    local weights = {}
    local total = 0
    for i, q in ipairs(RuneConfig.QUALITIES) do
        local w = q.weight
        -- 高品质(紫+)的权重乘以 qualityMult
        if i >= 4 then
            w = w * qualityMult
        end
        weights[i] = w
        total = total + w
    end
    local r = math.random() * total
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if r <= acc then return RuneConfig.QUALITIES[i] end
    end
    return RuneConfig.QUALITIES[1]
end

--- 随机选取系列
---@return table  RuneConfig.SERIES 中的一项
local function RollSeries()
    return RuneConfig.SERIES[math.random(1, #RuneConfig.SERIES)]
end

--- 加权随机选取一条词条（避免已有的重复）
---@param existingIds table  { [affixId] = true }
---@param category? string  "base" / "special" / nil(不限)
---@return table|nil  { id, name, minVal, maxVal, unit, weight }
local function RollAffix(existingIds, category)
    local pool = {}
    local totalW = 0
    for _, entry in ipairs(RuneConfig.ALL_AFFIXES) do
        local def = entry.def
        if not existingIds[def.id] then
            if not category or entry.category == category then
                pool[#pool + 1] = def
                totalW = totalW + def.weight
            end
        end
    end
    if #pool == 0 then return nil end

    local r = math.random() * totalW
    local acc = 0
    for _, def in ipairs(pool) do
        acc = acc + def.weight
        if r <= acc then return def end
    end
    return pool[1]
end

--- 计算词条数值
---@param affixDef table  词条定义
---@param qualityDef table  品质定义
---@return number
local function CalcAffixValue(affixDef, qualityDef)
    local base = affixDef.minVal + math.random() * (affixDef.maxVal - affixDef.minVal)
    return base * qualityDef.coeff * (0.8 + math.random() * 0.4)
end

--- 生成一个符文
---@param qualityMult? number  品质加成
---@return table  rune 数据
function RuneData.Generate(qualityMult)
    local quality = RollQuality(qualityMult)
    local series = RollSeries()
    local affixCount = quality.initAffixes

    local affixes = {}
    local existingIds = {}
    -- 60/40 分配：先基础，后特殊
    local baseCount = math.ceil(affixCount * 0.6)
    local specialCount = affixCount - baseCount

    for _ = 1, baseCount do
        local def = RollAffix(existingIds, "base")
        if def then
            existingIds[def.id] = true
            affixes[#affixes + 1] = {
                id = def.id,
                name = def.name,
                value = CalcAffixValue(def, quality),
                unit = def.unit,
                locked = false,
            }
        end
    end
    for _ = 1, specialCount do
        local def = RollAffix(existingIds, "special")
        if def then
            existingIds[def.id] = true
            affixes[#affixes + 1] = {
                id = def.id,
                name = def.name,
                value = CalcAffixValue(def, quality),
                unit = def.unit,
                locked = false,
            }
        end
    end

    return {
        runeId = NextRuneId(),
        qualityId = quality.id,
        seriesId = series.id,
        affixes = affixes,
        maxAffixes = quality.maxAffixes,
    }
end

--- 生成指定品质的符文
---@param qualityId string  品质ID（如 "red" = 神话）
---@return table|nil  rune 数据，品质不存在返回 nil
function RuneData.GenerateFixedQuality(qualityId)
    local quality = RuneConfig.QUALITY_MAP[qualityId]
    if not quality then return nil end
    local series = RollSeries()
    local affixCount = quality.initAffixes

    local affixes = {}
    local existingIds = {}
    local baseCount = math.ceil(affixCount * 0.6)
    local specialCount = affixCount - baseCount

    for _ = 1, baseCount do
        local def = RollAffix(existingIds, "base")
        if def then
            existingIds[def.id] = true
            affixes[#affixes + 1] = {
                id = def.id, name = def.name,
                value = CalcAffixValue(def, quality),
                unit = def.unit, locked = false,
            }
        end
    end
    for _ = 1, specialCount do
        local def = RollAffix(existingIds, "special")
        if def then
            existingIds[def.id] = true
            affixes[#affixes + 1] = {
                id = def.id, name = def.name,
                value = CalcAffixValue(def, quality),
                unit = def.unit, locked = false,
            }
        end
    end

    return {
        runeId = NextRuneId(),
        qualityId = quality.id,
        seriesId = series.id,
        affixes = affixes,
        maxAffixes = quality.maxAffixes,
    }
end

-- ============================================================================
-- 背包管理
-- ============================================================================

--- 获取背包
---@return table[]
function RuneData.GetBag()
    return EnsureData().bag
end

--- 获取背包容量
---@return number current, number max
function RuneData.GetBagCapacity()
    local d = EnsureData()
    return #d.bag, d.bagCapacity
end

--- 添加符文到背包
---@param rune table
---@return boolean success
---@return string msg
function RuneData.AddToBag(rune)
    local d = EnsureData()
    if #d.bag >= d.bagCapacity then
        return false, "背包已满(" .. d.bagCapacity .. ")"
    end
    d.bag[#d.bag + 1] = rune
    return true, ""
end

--- 从背包移除符文
---@param runeId number
---@return table|nil  被移除的符文
function RuneData.RemoveFromBag(runeId)
    local d = EnsureData()
    for i, r in ipairs(d.bag) do
        if r.runeId == runeId then
            table.remove(d.bag, i)
            return r
        end
    end
    return nil
end

--- 在背包中查找符文
---@param runeId number
---@return table|nil
function RuneData.FindInBag(runeId)
    local d = EnsureData()
    for _, r in ipairs(d.bag) do
        if r.runeId == runeId then return r end
    end
    return nil
end

--- 扩容背包
---@return boolean, string
function RuneData.ExpandBag()
    local d = EnsureData()
    if d.bagCapacity >= RuneConfig.BAG_MAX_CAPACITY then
        return false, "已达最大容量"
    end
    if not Currency.Has("rift_dust", RuneConfig.BAG_EXPAND_COST) then
        return false, "裂隙之尘不足(需" .. RuneConfig.BAG_EXPAND_COST .. ")"
    end
    Currency.Spend("rift_dust", RuneConfig.BAG_EXPAND_COST)
    d.bagCapacity = math.min(d.bagCapacity + RuneConfig.BAG_EXPAND_AMOUNT, RuneConfig.BAG_MAX_CAPACITY)
    HeroData.Save()
    return true, "背包扩容至" .. d.bagCapacity
end

-- ============================================================================
-- 装备管理
-- ============================================================================

--- 获取英雄的符文装备
---@param heroId string
---@return table  { [slotIdx] = rune|nil }
function RuneData.GetEquipped(heroId)
    local d = EnsureData()
    if not d.equipped[heroId] then
        d.equipped[heroId] = {}
    end
    return d.equipped[heroId]
end

--- 检查槽位是否已解锁
---@param slotIdx number 1-3
---@return boolean
function RuneData.IsSlotUnlocked(slotIdx)
    local slotDef = RuneConfig.SLOT_DEFS[slotIdx]
    if not slotDef then return false end
    local bestStage = HeroData.stats.bestGlobalWave or 0
    return bestStage >= slotDef.unlockStage
end

--- 装备符文（从背包移到槽位）
---@param heroId string
---@param slotIdx number 1-3
---@param runeId number
---@return boolean, string
function RuneData.Equip(heroId, slotIdx, runeId)
    if not RuneData.IsSlotUnlocked(slotIdx) then
        return false, "槽位未解锁"
    end

    -- 从背包取出
    local rune = RuneData.RemoveFromBag(runeId)
    if not rune then
        return false, "符文不在背包中"
    end

    local d = EnsureData()
    if not d.equipped[heroId] then
        d.equipped[heroId] = {}
    end

    -- 如果槽位已有符文，放回背包
    local old = d.equipped[heroId][slotIdx]
    if old then
        d.bag[#d.bag + 1] = old
    end

    d.equipped[heroId][slotIdx] = rune
    HeroData.Save()
    return true, "装备成功"
end

--- 卸下符文（从槽位移到背包）
---@param heroId string
---@param slotIdx number
---@return boolean, string
function RuneData.Unequip(heroId, slotIdx)
    local d = EnsureData()
    local equipped = d.equipped[heroId]
    if not equipped or not equipped[slotIdx] then
        return false, "槽位无符文"
    end

    if #d.bag >= d.bagCapacity then
        return false, "背包已满"
    end

    d.bag[#d.bag + 1] = equipped[slotIdx]
    equipped[slotIdx] = nil
    HeroData.Save()
    return true, "已卸下"
end

-- ============================================================================
-- 分解
-- ============================================================================

--- 分解一个符文（从背包）
---@param runeId number
---@return boolean success
---@return string message
---@return table|nil rewards
function RuneData.Decompose(runeId)
    local rune = RuneData.RemoveFromBag(runeId)
    if not rune then
        return false, "符文不在背包中", nil
    end

    local rewards = RuneConfig.DECOMPOSE[rune.qualityId]
    if not rewards then
        return false, "未知品质", nil
    end

    -- 发放材料
    local gained = {}
    for currId, amount in pairs(rewards) do
        Currency.GrantReward({ type = "currency", id = currId, amount = amount }, "RuneDecompose")
        gained[currId] = amount
    end

    HeroData.Save()
    return true, "分解成功", gained
end

--- 批量分解（按品质过滤）
---@param maxQualityIndex number  分解 <= 此品质索引的所有符文 (1=白, 2=绿, ...)
---@return number count  分解数量
---@return table totalGained  { [currId] = amount }
function RuneData.DecomposeByQuality(maxQualityIndex)
    local d = EnsureData()
    local totalGained = {}
    local count = 0
    local keep = {}

    for _, rune in ipairs(d.bag) do
        local q = RuneConfig.QUALITY_MAP[rune.qualityId]
        if q and q.index <= maxQualityIndex then
            -- 分解
            local rewards = RuneConfig.DECOMPOSE[rune.qualityId] or {}
            for currId, amount in pairs(rewards) do
                Currency.GrantReward({ type = "currency", id = currId, amount = amount }, "RuneBatchDecompose")
                totalGained[currId] = (totalGained[currId] or 0) + amount
            end
            count = count + 1
        else
            keep[#keep + 1] = rune
        end
    end

    d.bag = keep
    if count > 0 then
        HeroData.Save()
    end
    return count, totalGained
end

-- ============================================================================
-- 洗练
-- ============================================================================

--- 基础洗练（重随所有未锁定词条）
---@param rune table  符文引用（可在背包或已装备）
---@return boolean success
---@return string msg
---@return table|nil preview  预览新词条 {affixes=[...]}
function RuneData.Reforge(rune)
    if not rune then return false, "符文不存在", nil end

    -- 计算锁定数
    local lockedCount = 0
    local totalCount = #rune.affixes
    for _, a in ipairs(rune.affixes) do
        if a.locked then lockedCount = lockedCount + 1 end
    end

    -- 至少1条可洗
    if lockedCount >= totalCount then
        return false, "至少需要1条未锁定的词条", nil
    end

    -- 检查材料
    if not Currency.Has("rift_dust", RuneConfig.REFORGE_COST_DUST) then
        return false, "裂隙之尘不足(需" .. RuneConfig.REFORGE_COST_DUST .. ")", nil
    end
    if lockedCount > 0 and not Currency.Has("rune_seal", lockedCount) then
        return false, "符文封印不足(需" .. lockedCount .. ")", nil
    end

    -- 扣费
    Currency.Spend("rift_dust", RuneConfig.REFORGE_COST_DUST)
    if lockedCount > 0 then
        Currency.Spend("rune_seal", lockedCount)
    end

    -- 生成预览：保留锁定词条，重随未锁定词条
    local quality = RuneConfig.QUALITY_MAP[rune.qualityId]
    local newAffixes = {}
    local existingIds = {}

    -- 保留锁定词条
    for _, a in ipairs(rune.affixes) do
        if a.locked then
            newAffixes[#newAffixes + 1] = {
                id = a.id, name = a.name, value = a.value,
                unit = a.unit, locked = true,
            }
            existingIds[a.id] = true
        end
    end

    -- 重随未锁定词条
    local rerollCount = totalCount - lockedCount
    for _ = 1, rerollCount do
        local def = RollAffix(existingIds)
        if def then
            existingIds[def.id] = true
            newAffixes[#newAffixes + 1] = {
                id = def.id, name = def.name,
                value = CalcAffixValue(def, quality),
                unit = def.unit, locked = false,
            }
        end
    end

    return true, "洗练完成", { affixes = newAffixes }
end

--- 确认洗练结果（替换原词条）
---@param rune table
---@param newAffixes table[]
function RuneData.ApplyReforge(rune, newAffixes)
    rune.affixes = newAffixes
    -- 解锁所有锁定（下次需重新选择锁定）
    for _, a in ipairs(rune.affixes) do
        a.locked = false
    end
    HeroData.Save(true)
end

--- 定向洗练（只从指定类别重随）
---@param rune table
---@param category string  "base" / "special"
---@return boolean, string, table|nil
function RuneData.DirectedReforge(rune, category)
    if not rune then return false, "符文不存在", nil end

    local bestStage = HeroData.stats.bestGlobalWave or 0
    if bestStage < RuneConfig.DIRECTED_UNLOCK_STAGE then
        return false, "需通关第" .. RuneConfig.DIRECTED_UNLOCK_STAGE .. "波", nil
    end

    if not Currency.Has("rift_dust", RuneConfig.DIRECTED_COST_DUST) then
        return false, "裂隙之尘不足(需" .. RuneConfig.DIRECTED_COST_DUST .. ")", nil
    end
    if not Currency.Has("abyss_crystal", RuneConfig.DIRECTED_COST_CRYSTAL) then
        return false, "深渊结晶不足(需" .. RuneConfig.DIRECTED_COST_CRYSTAL .. ")", nil
    end

    -- 计算锁定数
    local lockedCount = 0
    for _, a in ipairs(rune.affixes) do
        if a.locked then lockedCount = lockedCount + 1 end
    end
    if lockedCount > 0 and not Currency.Has("rune_seal", lockedCount) then
        return false, "符文封印不足(需" .. lockedCount .. ")", nil
    end

    Currency.Spend("rift_dust", RuneConfig.DIRECTED_COST_DUST)
    Currency.Spend("abyss_crystal", RuneConfig.DIRECTED_COST_CRYSTAL)
    if lockedCount > 0 then
        Currency.Spend("rune_seal", lockedCount)
    end

    local quality = RuneConfig.QUALITY_MAP[rune.qualityId]
    local newAffixes = {}
    local existingIds = {}

    for _, a in ipairs(rune.affixes) do
        if a.locked then
            newAffixes[#newAffixes + 1] = {
                id = a.id, name = a.name, value = a.value,
                unit = a.unit, locked = true,
            }
            existingIds[a.id] = true
        end
    end

    local rerollCount = #rune.affixes - lockedCount
    for _ = 1, rerollCount do
        local def = RollAffix(existingIds, category)
        if not def then
            def = RollAffix(existingIds) -- fallback
        end
        if def then
            existingIds[def.id] = true
            newAffixes[#newAffixes + 1] = {
                id = def.id, name = def.name,
                value = CalcAffixValue(def, quality),
                unit = def.unit, locked = false,
            }
        end
    end

    return true, "定向洗练完成", { affixes = newAffixes }
end

-- ============================================================================
-- 词条锁定切换
-- ============================================================================

--- 切换词条锁定状态
---@param rune table
---@param affixIndex number  1-based
---@return boolean, string
function RuneData.ToggleAffixLock(rune, affixIndex)
    if not rune or not rune.affixes[affixIndex] then
        return false, "词条不存在"
    end
    rune.affixes[affixIndex].locked = not rune.affixes[affixIndex].locked
    return true, rune.affixes[affixIndex].locked and "已锁定" or "已解锁"
end

-- ============================================================================
-- 属性汇总（供战力计算）
-- ============================================================================

--- 获取英雄的符文属性总加成
---@param heroId string
---@return table  { [statId] = value, ... }
function RuneData.GetTotalBonus(heroId)
    local total = {}
    local d = EnsureData()
    local equipped = d.equipped[heroId]
    if not equipped then return total end

    for slotIdx = 1, RuneConfig.MAX_SLOTS do
        local rune = equipped[slotIdx]
        if rune then
            for _, affix in ipairs(rune.affixes) do
                total[affix.id] = (total[affix.id] or 0) + affix.value
            end
        end
    end
    return total
end

--- 获取英雄的套装效果
---@param heroId string
---@return table[]  { { series=def, count=n, set2=bool, set3=bool }, ... }
function RuneData.GetSetBonuses(heroId)
    local d = EnsureData()
    local equipped = d.equipped[heroId]
    if not equipped then return {} end

    -- 统计每个系列的数量
    local counts = {}
    for slotIdx = 1, RuneConfig.MAX_SLOTS do
        local rune = equipped[slotIdx]
        if rune then
            counts[rune.seriesId] = (counts[rune.seriesId] or 0) + 1
        end
    end

    local result = {}
    for seriesId, count in pairs(counts) do
        local series = RuneConfig.SERIES_MAP[seriesId]
        if series then
            result[#result + 1] = {
                series = series,
                count = count,
                set2 = count >= 2,
                set3 = count >= 3,
            }
        end
    end
    return result
end

--- 获取英雄符文的基础属性加成（用于 Tower 属性叠加）
--- 包含套装的 stat 加成
---@param heroId string
---@return table  { atk_pct, spd_pct, critRate, critDmg, armorPen, dmgBonus, range, ... }
function RuneData.GetCombatBonus(heroId)
    local bonus = RuneData.GetTotalBonus(heroId)
    local sets = RuneData.GetSetBonuses(heroId)

    -- 套装 stat 加成
    for _, setInfo in ipairs(sets) do
        if setInfo.set2 and setInfo.series.set2.stat then
            local stat = setInfo.series.set2.stat
            bonus[stat] = (bonus[stat] or 0) + setInfo.series.set2.value
        end
        -- set3 的 stat 加成（如果有）
        if setInfo.set3 and setInfo.series.set3.stat then
            local stat = setInfo.series.set3.stat
            bonus[stat] = (bonus[stat] or 0) + setInfo.series.set3.value
        end
    end

    return bonus
end

--- 获取英雄的套装特殊效果列表（用于 Combat 触发）
---@param heroId string
---@return table[]  { { effect=string, ...params }, ... }
function RuneData.GetSetEffects(heroId)
    local sets = RuneData.GetSetBonuses(heroId)
    local effects = {}
    for _, setInfo in ipairs(sets) do
        if setInfo.set3 and setInfo.series.set3.effect then
            effects[#effects + 1] = setInfo.series.set3
        end
    end
    return effects
end

-- ============================================================================
-- 深渊裂隙副本次数管理
-- ============================================================================

--- 重置每日次数（按日期）
function RuneData.ResetDailyIfNeeded()
    local d = EnsureData()
    local today = TodayKey()
    if d.abyssRift.lastResetDay ~= today then
        d.abyssRift.dailyFreeUsed = 0
        d.abyssRift.dailyAdUsed = 0
        d.abyssRift.lastResetDay = today
    end
end

--- 获取剩余次数
---@return number free, number ad
function RuneData.GetAbyssRiftRemaining()
    RuneData.ResetDailyIfNeeded()
    local d = EnsureData()
    local freeLeft = RuneConfig.ABYSS_RIFT.dailyFree - d.abyssRift.dailyFreeUsed
    local adLeft = RuneConfig.ABYSS_RIFT.dailyAd - d.abyssRift.dailyAdUsed
    return math.max(0, freeLeft), math.max(0, adLeft)
end

--- 消耗一次副本次数
---@param isAd boolean  是否是广告次数
---@return boolean
function RuneData.UseAbyssRiftEntry(isAd)
    RuneData.ResetDailyIfNeeded()
    local d = EnsureData()
    if isAd then
        if d.abyssRift.dailyAdUsed >= RuneConfig.ABYSS_RIFT.dailyAd then
            return false
        end
        d.abyssRift.dailyAdUsed = d.abyssRift.dailyAdUsed + 1
    else
        if d.abyssRift.dailyFreeUsed >= RuneConfig.ABYSS_RIFT.dailyFree then
            return false
        end
        d.abyssRift.dailyFreeUsed = d.abyssRift.dailyFreeUsed + 1
    end
    return true
end

--- 看广告领取深渊裂隙挑战券（计入广告次数，发券到背包）
---@return boolean
function RuneData.ConsumeAdForTicket()
    RuneData.ResetDailyIfNeeded()
    local d = EnsureData()
    if d.abyssRift.dailyAdUsed >= RuneConfig.ABYSS_RIFT.dailyAd then
        return false
    end
    d.abyssRift.dailyAdUsed = d.abyssRift.dailyAdUsed + 1
    InventoryData.Add("abyss_ticket", 1)
    HeroData.Save()
    return true
end

--- 获取深渊裂隙进度数据引用（供 AbyssRiftDungeon 读写 bestWave 等）
---@return table
function RuneData.GetAbyssRiftProgress()
    local d = EnsureData()
    return d.abyssRift
end

--- 获取背包中深渊裂隙挑战券数量
---@return number
function RuneData.GetAbyssTicketCount()
    return InventoryData.GetCount("abyss_ticket")
end

--- 消耗一张深渊裂隙挑战券
---@return boolean
function RuneData.ConsumeAbyssTicket()
    if InventoryData.GetCount("abyss_ticket") <= 0 then
        return false
    end
    for i, slot in ipairs(InventoryData.items) do
        if slot.id == "abyss_ticket" then
            slot.count = slot.count - 1
            if slot.count <= 0 then
                table.remove(InventoryData.items, i)
            end
            break
        end
    end
    HeroData.Save()
    return true
end

-- ============================================================================
-- 格式化显示
-- ============================================================================

--- 格式化词条显示文本
---@param affix table  { id, name, value, unit }
---@return string  如 "+8.2% 攻击力" 或 "+15 攻击范围"
function RuneData.FormatAffix(affix)
    if affix.unit == "px" then
        return "+" .. tostring(math.floor(affix.value)) .. " " .. affix.name
    else
        return string.format("+%.1f%% %s", affix.value * 100, affix.name)
    end
end

--- 格式化词条范围 [min, max]（考虑品质系数，取最低/最高可能值）
---@param affix table
---@param qualityId string
---@return string
function RuneData.FormatAffixRange(affix, qualityId)
    local def = RuneConfig.AFFIX_MAP[affix.id]
    if not def then return "" end
    local quality = RuneConfig.QUALITY_MAP[qualityId]
    local coeff = quality and quality.coeff or 1.0
    local lo = def.minVal * coeff * 0.8
    local hi = def.maxVal * coeff * 1.4
    if affix.unit == "px" then
        return string.format("[%d, %d]", math.floor(lo), math.floor(hi))
    else
        return string.format("[%.1f%%, %.1f%%]", lo * 100, hi * 100)
    end
end

--- 获取品质信息
---@param qualityId string
---@return table
function RuneData.GetQuality(qualityId)
    return RuneConfig.QUALITY_MAP[qualityId] or RuneConfig.QUALITIES[1]
end

--- 获取系列信息
---@param seriesId string
---@return table
function RuneData.GetSeries(seriesId)
    return RuneConfig.SERIES_MAP[seriesId]
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("runeData", {
    group = "equip",
    order = 35,
    serialize = function()
        return HeroData.runeData
    end,
    deserialize = function(saved, _saveData)
        if saved then
            -- 防止空表覆盖已有数据（云存档损坏时可能返回 {}）
            if not next(saved) and HeroData.runeData and next(HeroData.runeData) then
                print("[RuneData] WARNING: received empty table, keeping existing runeData")
                return
            end
        end
        HeroData.runeData = saved or nil
    end,
})

return RuneData
