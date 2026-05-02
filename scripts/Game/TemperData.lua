-- Game/TemperData.lua
-- 装备淬炼系统 — 数据与逻辑
-- 红色满级(Lv.4000)后消耗白玉为装备附加随机属性词条

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")

local TemperData = {}

--- 精度因子：SafeTable 使用 math.floor() 截断浮点数，
--- 因此将属性值乘以此因子存为整数，读取/显示时再除回来。
local VALUE_SCALE = 1000000

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取部位定义
---@param slotId string
---@return table|nil
local function GetSlotDef(slotId)
    for _, s in ipairs(Config.EQUIP_SLOTS) do
        if s.id == slotId then return s end
    end
    return nil
end

--- 加权随机选取档位
---@return table  Config.TEMPER_TIERS 中的一项
local function RollTier()
    local r = math.random()
    local acc = 0
    for _, t in ipairs(Config.TEMPER_TIERS) do
        acc = acc + t.chance
        if r <= acc then return t end
    end
    return Config.TEMPER_TIERS[1]
end

--- 淬炼品质等级映射（数值越大品质越高）
local TEMPER_TIER_ORDER = {
    white = 1, green = 2, blue = 3, purple = 4, orange = 5, red = 6,
}

--- 随机选取属性（根据当前品质档位过滤三层词条，排除已占用词条）
---@param tierId string  当前淬炼档位 id（"white"~"red"）
---@param excludeIds table|nil  已占用的属性 id 集合 { [id]=true, ... }
---@return table  Config.TEMPER_ATTRIBUTES 中的一项
local function RollAttribute(tierId, excludeIds)
    local tierLv = TEMPER_TIER_ORDER[tierId] or 1
    -- 构建当前品质可用的属性池（排除已占用词条）
    local pool = {}
    for _, attr in ipairs(Config.TEMPER_ATTRIBUTES) do
        -- 排重：跳过已占用的词条
        if excludeIds and excludeIds[attr.id] then
            -- skip
        elseif attr.minTemperTier then
            -- 三层词条：需要品质达标才可出现
            local reqLv = TEMPER_TIER_ORDER[attr.minTemperTier] or 99
            if tierLv >= reqLv then
                pool[#pool + 1] = attr
            end
        else
            -- 原有词条：无品质限制，始终可出
            pool[#pool + 1] = attr
        end
    end
    if #pool == 0 then pool = Config.TEMPER_ATTRIBUTES end
    local idx = math.random(1, #pool)
    return pool[idx]
end

--- 计算淬炼属性值
--- 所有属性统一使用 maxValue × 档位比例 计算
---@param attrDef table  属性定义
---@param tierDef table  档位定义
---@param slotId string  部位ID（保留参数兼容性）
---@return number value  属性数值（×VALUE_SCALE 整数）
---@return string statKey  实际作用的属性key
local function CalcTemperValue(attrDef, tierDef, slotId)
    local mult = tierDef.valueMin + math.random() * (tierDef.valueMax - tierDef.valueMin)
    -- 通用公式: maxValue × (mult / 1.5)，使红档上限 = maxValue
    local value = attrDef.maxValue * (mult / 1.5)
    -- 乘以精度因子存为整数，避免 SafeTable 的 math.floor 截断
    return math.floor(value * VALUE_SCALE + 0.5), attrDef.id
end

-- ============================================================================
-- 数据存取
-- ============================================================================

--- 获取装备的淬炼数据（懒初始化）
---@param heroId string
---@param slotId string
---@return table|nil  nil表示未解锁
function TemperData.GetTemper(heroId, slotId)
    local equips = HeroData.equipData and HeroData.equipData[heroId]
    if not equips then return nil end
    local e = equips[slotId]
    if not e then return nil end
    return e.tempering
end

--- 获取已解锁的孔位数
---@param temper table  淬炼数据
---@return number
function TemperData.GetUnlockedSlotCount(temper)
    if not temper then return 0 end
    local count = 0
    for i = 1, Config.TEMPER_MAX_SLOTS do
        local threshold = Config.TEMPER_SLOT_UNLOCK[i] or 999999
        if temper.totalAttempts >= threshold then
            count = count + 1
        else
            break
        end
    end
    return count
end

--- 检查装备是否可以开启淬炼
---@param heroId string
---@param slotId string
---@return boolean canUnlock
---@return string reason
function TemperData.CanUnlock(heroId, slotId)
    local equips = HeroData.equipData and HeroData.equipData[heroId]
    if not equips or not equips[slotId] then
        return false, "装备不存在"
    end

    local e = equips[slotId]

    -- 已解锁
    if e.tempering then
        return false, "淬炼已解锁"
    end

    if e.level < Config.TEMPER_UNLOCK_LEVEL then
        return false, "装备需达到Lv." .. Config.TEMPER_UNLOCK_LEVEL
    end
    if e.tierIdx < #Config.EQUIP_TIERS then
        return false, "装备需达到红色品质"
    end
    local bestStage = (HeroData.stats and HeroData.stats.bestStage) or 0
    if bestStage < Config.TEMPER_UNLOCK_STAGE then
        return false, "需通过第" .. Config.TEMPER_UNLOCK_STAGE .. "关"
    end

    -- 检查暗影精粹
    if not Currency.Has("shadow_essence", Config.TEMPER_UNLOCK_COST) then
        return false, "暗影精粹不足(需" .. Config.TEMPER_UNLOCK_COST .. ")"
    end

    return true, ""
end

--- 解锁淬炼
---@param heroId string
---@param slotId string
---@return boolean, string
function TemperData.Unlock(heroId, slotId)
    local canUnlock, reason = TemperData.CanUnlock(heroId, slotId)
    if not canUnlock then
        return false, reason
    end

    -- 扣费
    Currency.Spend("shadow_essence", Config.TEMPER_UNLOCK_COST)

    -- 初始化淬炼数据
    local equips = HeroData.equipData[heroId]
    if not equips or not equips[slotId] then
        return false, "装备不存在"
    end
    equips[slotId].tempering = {
        unlocked = true,
        totalAttempts = 0,
        slots = {},
    }

    HeroData.Save(true)  -- 淬炼解锁消耗货币，立即云端保存
    print("[TemperData] Unlocked tempering: " .. heroId .. "/" .. slotId)
    return true, "淬炼已解锁!"
end

-- ============================================================================
-- 淬炼核心逻辑
-- ============================================================================

--- 执行一次淬炼（一次刷新所有未锁定孔位，100%成功）
---@param heroId string
---@param slotId string
---@return boolean success  是否操作成功
---@return string msg
---@return table|nil result  { refreshed = { {slotIdx, attrDef, tierDef, value, statKey}, ... } }
function TemperData.DoTemper(heroId, slotId)
    local temper = TemperData.GetTemper(heroId, slotId)
    if not temper then
        return false, "淬炼未解锁", nil
    end

    -- 计算锁定孔位数
    local lockedCount = 0
    for _, slot in pairs(temper.slots) do
        if slot.locked then lockedCount = lockedCount + 1 end
    end

    -- 找出所有已解锁且未锁定的孔位
    local unlockedSlots = TemperData.GetUnlockedSlotCount(temper)
    local candidates = {}
    for i = 1, unlockedSlots do
        local s = temper.slots[i]
        if not s or not s.locked then
            candidates[#candidates + 1] = i
        end
    end

    if #candidates == 0 then
        return false, "所有孔位已锁定，请先解锁至少一个词条", nil
    end

    -- 计算费用
    local jadeCost = Config.TEMPER_COST_JADE
    local rainbowCost = lockedCount  -- 锁N个孔位额外消耗N彩玉

    -- 检查货币
    if not Currency.Has("pale_jade", jadeCost) then
        return false, "白玉不足(需" .. jadeCost .. ")", nil
    end
    if rainbowCost > 0 and not Currency.Has("rainbow_jade", rainbowCost) then
        return false, "彩玉不足(需" .. rainbowCost .. ")", nil
    end

    -- 扣费
    Currency.Spend("pale_jade", jadeCost)
    if rainbowCost > 0 then
        Currency.Spend("rainbow_jade", rainbowCost)
    end

    -- 累计次数+1
    temper.totalAttempts = temper.totalAttempts + 1

    -- 刷新所有未锁定孔位（100%成功，同步刷新，完全排重）
    -- 收集已锁定孔位的词条 id 作为排除集
    local usedIds = {}
    for i = 1, unlockedSlots do
        local s = temper.slots[i]
        if s and s.locked and s.attrId then
            usedIds[s.attrId] = true
        end
    end

    local refreshed = {}
    for _, idx in ipairs(candidates) do
        local tierDef = RollTier()
        local attrDef = RollAttribute(tierDef.id, usedIds)
        usedIds[attrDef.id] = true  -- 本次 roll 结果也加入排除集
        local value, statKey = CalcTemperValue(attrDef, tierDef, slotId)

        temper.slots[idx] = {
            attrId = attrDef.id,
            attrName = attrDef.name,
            statKey = statKey,
            value = value,
            tierId = tierDef.id,
            tierName = tierDef.name,
            tierColor = tierDef.color,
            locked = false,
        }

        refreshed[#refreshed + 1] = {
            slotIdx = idx,
            attrDef = attrDef,
            tierDef = tierDef,
            value = value,
            statKey = statKey,
        }
    end

    HeroData.Save()
    return true, "淬炼完成!", { refreshed = refreshed }
end

-- ============================================================================
-- 孔位锁定
-- ============================================================================

--- 切换孔位锁定状态
---@param heroId string
---@param slotId string
---@param slotIdx number  孔位编号 1~5
---@return boolean, string
function TemperData.ToggleLock(heroId, slotId, slotIdx)
    local temper = TemperData.GetTemper(heroId, slotId)
    if not temper then
        return false, "淬炼未解锁"
    end

    local slot = temper.slots[slotIdx]
    if not slot then
        return false, "该孔位尚无属性"
    end

    -- 如果是要锁定（当前未锁定），检查锁定上限
    if not slot.locked then
        local unlockedSlots = TemperData.GetUnlockedSlotCount(temper)
        local lockedCount = 0
        local attrCount = 0
        for i = 1, unlockedSlots do
            if temper.slots[i] then
                attrCount = attrCount + 1
                if temper.slots[i].locked then
                    lockedCount = lockedCount + 1
                end
            end
        end
        -- 至少保留 1 个未锁定词条可供刷新
        if lockedCount >= attrCount - 1 then
            return false, "至少保留一个未锁定词条"
        end
    end

    -- 切换锁定
    slot.locked = not slot.locked
    HeroData.Save()

    if slot.locked then
        return true, "已锁定孔位" .. slotIdx
    else
        return true, "已解锁孔位" .. slotIdx
    end
end

-- ============================================================================
-- 属性汇总（供战力计算使用）
-- ============================================================================

--- 获取指定装备的淬炼属性汇总
---@param heroId string
---@param slotId string
---@return table  { statKey = totalValue, ... }
function TemperData.GetSlotBonus(heroId, slotId)
    local result = {}
    local temper = TemperData.GetTemper(heroId, slotId)
    if not temper then return result end

    for _, slot in pairs(temper.slots) do
        if slot and slot.statKey and slot.value then
            -- 还原缩放后的整数为实际浮点值
            result[slot.statKey] = (result[slot.statKey] or 0) + (slot.value / VALUE_SCALE)
        end
    end
    return result
end

--- 获取英雄所有装备的淬炼属性总和
---@param heroId string
---@return table  { atk=N, critRate=N, ... }
function TemperData.GetTotalBonus(heroId)
    local total = {}
    for _, slotDef in ipairs(Config.EQUIP_SLOTS) do
        local bonus = TemperData.GetSlotBonus(heroId, slotDef.id)
        for k, v in pairs(bonus) do
            total[k] = (total[k] or 0) + v
        end
        -- 淬炼主属性加成：每次淬炼 +1% 的每级基础成长
        local mainBonus = TemperData.GetTemperMainStatBonus(heroId, slotDef.id)
        if mainBonus > 0 then
            total[slotDef.stat] = (total[slotDef.stat] or 0) + mainBonus
        end
    end
    return total
end

--- 获取英雄所有装备上的三层词条列表（供 AffixTagResolver 消费）
--- 只返回 isTagAffix 标记的词条，格式: { {id, value}, ... }
---@param heroId string
---@return table[]
function TemperData.GetTemperStats(heroId)
    local result = {}
    for _, slotDef in ipairs(Config.EQUIP_SLOTS) do
        local temper = TemperData.GetTemper(heroId, slotDef.id)
        if temper then
            for _, slot in pairs(temper.slots) do
                if slot and slot.attrId then
                    -- 检查对应属性定义是否为三层词条
                    for _, attr in ipairs(Config.TEMPER_ATTRIBUTES) do
                        if attr.id == slot.attrId and attr.isTagAffix then
                            result[#result + 1] = {
                                id    = slot.attrId,
                                value = slot.value / VALUE_SCALE,
                            }
                            break
                        end
                    end
                end
            end
        end
    end
    return result
end

--- 获取淬炼对装备主属性的额外加成
--- 每次淬炼 +1% 的每级基础成长（EQUIP_STAT_BASE × 0.01 × 淬炼次数）
---@param heroId string
---@param slotId string
---@return number  实际加成值（百分比形式，如 0.0006 = 0.06%）
function TemperData.GetTemperMainStatBonus(heroId, slotId)
    local temper = TemperData.GetTemper(heroId, slotId)
    if not temper or temper.totalAttempts == 0 then return 0 end
    local slotDef = GetSlotDef(slotId)
    if not slotDef then return 0 end
    local base = Config.EQUIP_STAT_BASE[slotDef.stat] or 0.002
    return base * 0.01 * temper.totalAttempts
end

-- ============================================================================
-- 格式化显示
-- ============================================================================

--- 格式化淬炼属性值
---@param slot table  孔位数据 { attrId, statKey, value, tierId, ... }
---@param slotId string  部位ID
---@return string  如 "+12.0% 攻击力" 或 "+15.0% 暴击率"
function TemperData.FormatSlotValue(slot, slotId)
    if not slot then return "" end

    local displayName = slot.attrName or slot.attrId
    -- 从 SafeTable 读出的是缩放后的整数，需除以 VALUE_SCALE 还原
    local realValue = slot.value / VALUE_SCALE
    -- 所有属性均为百分比
    return string.format("+%.1f%% %s", realValue * 100, displayName)
end

--- 计算词条品质百分比（当前值占最大值的比例）
---@param slot table  孔位数据
---@param slotId string  部位ID
---@return number  0~100 的百分比
function TemperData.GetSlotQuality(slot, slotId)
    if not slot or not slot.value then return 0 end
    local realValue = slot.value / VALUE_SCALE

    -- 通用逻辑：最大值 = attrDef.maxValue（红档上限 mult=1.5 → maxValue×1.5/1.5=maxValue）
    for _, attr in ipairs(Config.TEMPER_ATTRIBUTES) do
        if attr.id == slot.attrId then
            if attr.maxValue <= 0 then return 0 end
            return math.floor(realValue / attr.maxValue * 100 + 0.5)
        end
    end
    return 0
end

return TemperData
