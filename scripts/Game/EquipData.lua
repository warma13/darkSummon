-- Game/EquipData.lua
-- 装备系统数据与升级逻辑（对齐咸鱼之王）
-- 每个英雄4件装备(武器/铠甲/头盔/战马)，等级升级+品质突破

local Config = require("Game.Config")
local F = require("Game.FormulaLib")
local HeroData = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local EquipData = {}

--- 初始化英雄装备（新英雄默认1级绿色）
---@param heroId string
---@return table  -- { weapon={level,tierIdx}, armor=..., helmet=..., mount=... }
function EquipData.InitHeroEquip(heroId)
    local equips = {}
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        equips[slot.id] = { level = 1, tierIdx = 1 }
    end
    return equips
end

--- 获取英雄装备数据（懒初始化）
---@param heroId string
---@return table
function EquipData.GetHeroEquips(heroId)
    if not HeroData.equipData then
        HeroData.SetEquipData({})
    end
    if not HeroData.equipData[heroId] then
        HeroData.equipData[heroId] = EquipData.InitHeroEquip(heroId)
    end
    return HeroData.equipData[heroId]
end

--- 获取指定部位的装备信息
---@param heroId string
---@param slotId string  "weapon"/"armor"/"helmet"/"mount"
---@return table  { level, tierIdx, tierDef, slotDef, fullName, statBonus }
function EquipData.GetSlotInfo(heroId, slotId)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    if not e then return nil end

    local tierDef = Config.EQUIP_TIERS[e.tierIdx]
    local slotDef = nil
    for _, s in ipairs(Config.EQUIP_SLOTS) do
        if s.id == slotId then slotDef = s; break end
    end
    if not tierDef or not slotDef then return nil end

    local fullName = tierDef.names[slotId] or (tierDef.name .. slotDef.name)
    local transcendLv = e.transcendLv or 0
    local statBonus = EquipData.CalcStatBonus(slotDef.stat, e.level, tierDef.id, transcendLv)

    return {
        level = e.level,
        tierIdx = e.tierIdx,
        tierDef = tierDef,
        slotDef = slotDef,
        fullName = fullName,
        statBonus = statBonus,
        transcendLv = transcendLv,
    }
end

--- 计算装备属性加成（含超越等级）
---@param statType string  "atk"/"dmgBonus"/"critDmg"/"elemDmg"
---@param level number
---@param tierId string  "green"/"blue"/...
---@param transcendLv number|nil  超越等级
---@return number
function EquipData.CalcStatBonus(statType, level, tierId, transcendLv)
    local base = Config.EQUIP_STAT_BASE[statType] or 0.002
    local mult = Config.EQUIP_TIER_MULT[tierId] or 1.0
    local value = base * level * mult
    -- 超越加成：每超越等级 = base × redMult × TRANSCEND_STAT_RATE
    if (transcendLv or 0) > 0 then
        local redMult = Config.EQUIP_TIER_MULT["red"] or 5.0
        value = value + base * transcendLv * redMult * Config.TRANSCEND_STAT_RATE
    end
    return value
end

--- 获取当前品质段号
---@param level number
---@return number  tierIdx 1~5
function EquipData.GetTierIdxForLevel(level)
    for i = #Config.EQUIP_TIERS, 1, -1 do
        if level > Config.EQUIP_TIERS[i].unlockLevel then
            return i
        end
    end
    return 1
end

-- 装备升级费用阶梯: { fromLevel, cost }
local EQUIP_COST_STEPS = {
    { 1,    1  },   -- 1~200:    1 噬魂石/级
    { 201,  2  },   -- 201~1000: 2 噬魂石/级
    { 1001, 4  },   -- 1001~2000: 4 噬魂石/级
    { 2001, 8  },   -- 2001~3000: 8 噬魂石/级
    { 3001, 15 },   -- 3001+:    15 噬魂石/级
}

--- 获取升级费用（噬魂石）
---@param level number
---@return number
function EquipData.GetUpgradeCost(level)
    if level >= Config.EQUIP_MAX_LEVEL then return 0 end
    return F.StepFunction(EQUIP_COST_STEPS, level)
end

--- 检查是否需要突破（到达品质等级上限）
---@param heroId string
---@param slotId string
---@return boolean needBreak
---@return table|nil breakInfo  { tierIdx, nextTier, cost }
function EquipData.CheckBreakthrough(heroId, slotId)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    local tier = Config.EQUIP_TIERS[e.tierIdx]
    if not tier then return false, nil end

    if e.level >= tier.maxLevel and e.tierIdx < #Config.EQUIP_TIERS then
        local nextTier = Config.EQUIP_TIERS[e.tierIdx + 1]
        return true, {
            tierIdx = e.tierIdx + 1,
            nextTier = nextTier,
            cost = tier.breakCost,
        }
    end
    return false, nil
end

--- 升级装备（单次）
---@param heroId string
---@param slotId string
---@return boolean, string
function EquipData.Upgrade(heroId, slotId)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    local tier = Config.EQUIP_TIERS[e.tierIdx]

    -- 到达品质上限，需要突破
    if e.level >= tier.maxLevel then
        return false, "需要突破才能继续升级"
    end

    if e.level >= Config.EQUIP_MAX_LEVEL then
        return false, "已达最高等级"
    end

    -- 装备等级不能超过暗影君主等级
    local leaderLevel = HeroData.GetLeaderLevel()
    if e.level >= leaderLevel then
        return false, "装备等级已达暗影君主等级上限(Lv" .. leaderLevel .. ")"
    end

    local cost = EquipData.GetUpgradeCost(e.level)
    if (HeroData.currencies.forge_iron or 0) < cost then
        return false, "锻魂铁不足(需" .. cost .. ")"
    end

    HeroData.currencies.forge_iron = HeroData.currencies.forge_iron - cost
    e.level = e.level + 1
    HeroData.Save(true)  -- 装备强化消耗锻铁，立即云端保存
    return true, "升级成功 Lv." .. e.level
end

--- 计算最佳多级升级方案（100→50→10→1 逐档尝试）
---@param heroId string
---@param slotId string
---@return table|nil  { tier, cost, actual }
function EquipData.GetBestUpgradeTier(heroId, slotId)
    local tiers = { 100, 50, 10, 1 }
    for _, tier in ipairs(tiers) do
        local actual, cost = EquipData.CalcUpgradeCost(heroId, slotId, tier)
        if actual >= tier then
            return { tier = tier, cost = cost, actual = actual }
        end
    end
    -- 连1级都升不了
    local actual1, cost1 = EquipData.CalcUpgradeCost(heroId, slotId, 1)
    if actual1 >= 1 then
        return { tier = 1, cost = cost1, actual = 1 }
    end
    return nil
end

--- 预计算批量升级（不扣费，仅计算能升多少级、花多少钱）
---@param heroId string
---@param slotId string
---@param wantCount number  想升多少级
---@return number canUpgrade  实际可升级数
---@return number totalCost   总费用
function EquipData.CalcUpgradeCost(heroId, slotId, wantCount)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    local tier = Config.EQUIP_TIERS[e.tierIdx]
    local leaderLevel = HeroData.GetLeaderLevel()
    local iron = HeroData.currencies.forge_iron or 0

    local count = 0
    local cost = 0
    local simLevel = e.level
    local simIron = iron

    while count < wantCount do
        if simLevel >= tier.maxLevel then break end
        if simLevel >= Config.EQUIP_MAX_LEVEL then break end
        if simLevel >= leaderLevel then break end
        local c = EquipData.GetUpgradeCost(simLevel)
        if simIron < c then break end
        simIron = simIron - c
        simLevel = simLevel + 1
        cost = cost + c
        count = count + 1
    end
    return count, cost
end

--- 批量升级（升N级或升满当前品质段）
---@param heroId string
---@param slotId string
---@param maxCount number  最多升多少级（-1=升满当前段）
---@return number upgraded  实际升了多少级
---@return number totalCost 总花费
function EquipData.UpgradeMulti(heroId, slotId, maxCount)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    local tier = Config.EQUIP_TIERS[e.tierIdx]
    local upgraded = 0
    local totalCost = 0
    local leaderLevel = HeroData.GetLeaderLevel()

    if maxCount < 0 then maxCount = Config.EQUIP_MAX_LEVEL end

    while upgraded < maxCount do
        if e.level >= tier.maxLevel then break end
        if e.level >= Config.EQUIP_MAX_LEVEL then break end
        if e.level >= leaderLevel then break end

        local cost = EquipData.GetUpgradeCost(e.level)
        if (HeroData.currencies.forge_iron or 0) < cost then break end

        HeroData.currencies.forge_iron = HeroData.currencies.forge_iron - cost
        e.level = e.level + 1
        totalCost = totalCost + cost
        upgraded = upgraded + 1
    end

    if upgraded > 0 then
        -- 劳动奖章产出
        local okLM, LMD = pcall(require, "Game.LaborMedalData")
        if okLM then LMD.EarnMedals("equip_enhance") end

        HeroData.Save(true)  -- 批量强化消耗锻铁，立即云端保存
    end
    return upgraded, totalCost
end

--- 突破到下一品质
---@param heroId string
---@param slotId string
---@return boolean, string
function EquipData.Breakthrough(heroId, slotId)
    local needBreak, info = EquipData.CheckBreakthrough(heroId, slotId)
    if not needBreak then
        return false, "无需突破"
    end

    if (HeroData.currencies.forge_iron or 0) < info.cost then
        return false, "锻魂铁不足(需" .. info.cost .. "突破)"
    end

    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]

    HeroData.currencies.forge_iron = HeroData.currencies.forge_iron - info.cost
    e.tierIdx = info.tierIdx
    HeroData.Save(true)  -- 装备突破消耗锻铁，立即云端保存

    print("[EquipData] " .. heroId .. " " .. slotId .. " breakthrough to " .. info.nextTier.name)
    return true, "突破成功! " .. info.nextTier.name .. "品质"
end

--- 获取超越升级费用（锻魂铁）
---@param transcendLv number 当前超越等级
---@return number
function EquipData.GetTranscendCost(transcendLv)
    local cost = Config.TRANSCEND_COST_BASE + transcendLv * Config.TRANSCEND_COST_GROWTH
    return math.min(cost, Config.TRANSCEND_COST_MAX)
end

--- 超越升级（单次）
---@param heroId string
---@param slotId string
---@return boolean, string
function EquipData.TranscendUpgrade(heroId, slotId)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    local tier = Config.EQUIP_TIERS[e.tierIdx]

    -- 必须红色满级
    if e.tierIdx < #Config.EQUIP_TIERS or e.level < tier.maxLevel then
        return false, "需要红色品质满级才能超越"
    end

    local transcendLv = e.transcendLv or 0
    local cost = EquipData.GetTranscendCost(transcendLv)
    if (HeroData.currencies.forge_iron or 0) < cost then
        return false, "锻魂铁不足(需" .. cost .. ")"
    end

    HeroData.currencies.forge_iron = HeroData.currencies.forge_iron - cost
    e.transcendLv = transcendLv + 1
    HeroData.Save(true)
    return true, "超越成功 +" .. e.transcendLv
end

--- 批量超越升级
---@param heroId string
---@param slotId string
---@param maxCount number 最多升多少级（-1=升满）
---@return number upgraded
---@return number totalCost
function EquipData.TranscendUpgradeMulti(heroId, slotId, maxCount)
    local equips = EquipData.GetHeroEquips(heroId)
    local e = equips[slotId]
    local tier = Config.EQUIP_TIERS[e.tierIdx]

    if e.tierIdx < #Config.EQUIP_TIERS or e.level < tier.maxLevel then
        return 0, 0
    end

    if maxCount < 0 then maxCount = 999999 end
    local upgraded = 0
    local totalCost = 0

    while upgraded < maxCount do
        local transcendLv = e.transcendLv or 0
        local cost = EquipData.GetTranscendCost(transcendLv)
        if (HeroData.currencies.forge_iron or 0) < cost then break end

        HeroData.currencies.forge_iron = HeroData.currencies.forge_iron - cost
        e.transcendLv = transcendLv + 1
        totalCost = totalCost + cost
        upgraded = upgraded + 1
    end

    if upgraded > 0 then
        HeroData.Save(true)
    end
    return upgraded, totalCost
end

--- 一键升级所有部位（升到各自品质段上限，满级红色则超越）
---@param heroId string
---@return number totalUpgraded
---@return number totalCost
function EquipData.UpgradeAllSlots(heroId)
    local totalUpgraded = 0
    local totalCost = 0
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local up, cost = EquipData.UpgradeMulti(heroId, slot.id, -1)
        totalUpgraded = totalUpgraded + up
        totalCost = totalCost + cost
    end
    -- 满级红色的部位尝试超越升级
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local up, cost = EquipData.TranscendUpgradeMulti(heroId, slot.id, -1)
        totalUpgraded = totalUpgraded + up
        totalCost = totalCost + cost
    end
    return totalUpgraded, totalCost
end

--- 获取套装信息（当前品质的最低部位决定套装等级）
---@param heroId string
---@return table  { tierIdx, tierDef, isComplete, bonuses }
function EquipData.GetSetInfo(heroId)
    local equips = EquipData.GetHeroEquips(heroId)
    local minTierIdx = 999
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local e = equips[slot.id]
        if e then
            minTierIdx = math.min(minTierIdx, e.tierIdx)
        end
    end
    if minTierIdx > #Config.EQUIP_TIERS then minTierIdx = 1 end

    local tierDef = Config.EQUIP_TIERS[minTierIdx]
    -- 套装完成：4件都在此品质或更高
    local complete = true
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local e = equips[slot.id]
        if not e or e.tierIdx < minTierIdx then
            complete = false
            break
        end
    end

    return {
        tierIdx = minTierIdx,
        tierDef = tierDef,
        isComplete = complete,
        bonuses = complete and tierDef.setBonus or {},
    }
end

--- 获取装备对英雄的总属性加成
---@param heroId string
---@return table  { atk=N, dmgBonus=N, critDmg=N, elemDmg=N, atk_pct=N, ... }
function EquipData.GetTotalBonus(heroId)
    local total = { atk = 0, dmgBonus = 0, critDmg = 0, elemDmg = 0, atk_pct = 0 }
    local equips = EquipData.GetHeroEquips(heroId)

    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local e = equips[slot.id]
        if e then
            local tier = Config.EQUIP_TIERS[e.tierIdx]
            local bonus = EquipData.CalcStatBonus(slot.stat, e.level, tier.id, e.transcendLv or 0)
            -- 武器特殊处理：fmt="pct" 且 stat="atk" → 路由到 atk_pct（百分比攻击力）
            if slot.fmt == "pct" and slot.stat == "atk" then
                total["atk_pct"] = (total["atk_pct"] or 0) + bonus
            else
                total[slot.stat] = (total[slot.stat] or 0) + bonus
            end
        end
    end

    -- 套装加成（百分比）
    local setInfo = EquipData.GetSetInfo(heroId)
    if setInfo.isComplete then
        for k, v in pairs(setInfo.bonuses) do
            total[k] = (total[k] or 0) + v
        end
    end

    -- 淬炼属性加成
    local TemperData = require("Game.TemperData")
    local temperBonus = TemperData.GetTotalBonus(heroId)
    for k, v in pairs(temperBonus) do
        total[k] = (total[k] or 0) + v
    end

    -- 符文属性加成
    local ok, RuneData = pcall(require, "Game.RuneData")
    if ok then
        local runeBonus = RuneData.GetCombatBonus(heroId)
        for k, v in pairs(runeBonus) do
            total[k] = (total[k] or 0) + v
        end
    end

    return total
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
local SafeTable = require("Game.SafeTable")

SaveRegistry.Register("equipData", {
    group = "equip",
    order = 30,
    serialize = function()
        return HeroData.GetEquipSnapshot()
    end,
    deserialize = function(saved, _saveData)
        if saved then
            HeroData.SetEquipData(saved)
        else
            HeroData.equipData = nil
        end
    end,
})

return EquipData
