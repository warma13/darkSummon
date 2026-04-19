-- Game/TemperData.lua
-- 装备淬炼系统 — 数据与逻辑
-- 红色满级(Lv.4000)后消耗白玉为装备附加随机属性词条

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")

local TemperData = {}

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

--- 随机选取属性
---@return table  Config.TEMPER_ATTRIBUTES 中的一项
local function RollAttribute()
    local idx = math.random(1, #Config.TEMPER_ATTRIBUTES)
    return Config.TEMPER_ATTRIBUTES[idx]
end

--- 计算淬炼属性值
--- "攻击力"词条在各部位加成该部位自身属性，值 = 1级基础值 × 档位倍率
--- 其他属性直接用 maxValue × 档位倍率比例
---@param attrDef table  属性定义
---@param tierDef table  档位定义
---@param slotId string  部位ID
---@return number value  属性数值
---@return string statKey  实际作用的属性key（"atk"词条在不同部位映射不同属性）
local function CalcTemperValue(attrDef, tierDef, slotId)
    local mult = tierDef.valueMin + math.random() * (tierDef.valueMax - tierDef.valueMin)

    if attrDef.id == "atk" then
        -- "攻击力"词条: 加成该部位自身属性的1级基础值 × 档位倍率
        local slotDef = GetSlotDef(slotId)
        if not slotDef then return 0, "atk" end
        local base = Config.EQUIP_STAT_BASE[slotDef.stat] or 10
        local value = base * mult
        -- 武器(atk)取整，其他百分比属性保留精度
        if slotDef.stat == "atk" then
            value = math.floor(value + 0.5)
        end
        return value, slotDef.stat
    else
        -- 通用属性: maxValue × 档位比例
        -- 将 valueMin~valueMax (0.5~1.5) 映射到属性值范围
        -- 实际值 = maxValue × (mult / 1.5) 使红档上限 = maxValue
        local value = attrDef.maxValue * (mult / 1.5)
        return value, attrDef.id
    end
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

    -- 检查等级
    if e.level < Config.TEMPER_UNLOCK_LEVEL then
        return false, "装备需达到Lv." .. Config.TEMPER_UNLOCK_LEVEL
    end

    -- 检查品质（必须红色=tierIdx 5）
    if e.tierIdx < #Config.EQUIP_TIERS then
        return false, "装备需达到红色品质"
    end

    -- 检查主线关卡
    local bestStage = HeroData.bestStage or 0
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

--- 执行一次淬炼
---@param heroId string
---@param slotId string
---@return boolean success  是否操作成功（不是淬炼是否成功）
---@return string msg
---@return table|nil result  { hit=bool, slotIdx, attrDef, tierDef, value, statKey }
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

    -- 判定成功/失败
    local hit = math.random() < Config.TEMPER_SUCCESS_RATE
    if not hit then
        HeroData.Save()
        return true, "淬炼失败，属性未变化", { hit = false }
    end

    -- 淬炼成功：随机选一个未锁定的孔位刷新
    local unlockedSlots = TemperData.GetUnlockedSlotCount(temper)
    local candidates = {}
    for i = 1, unlockedSlots do
        local s = temper.slots[i]
        if not s or not s.locked then
            candidates[#candidates + 1] = i
        end
    end

    if #candidates == 0 then
        -- 所有孔位都锁了（理论上不应该，因为费用已扣）
        HeroData.Save()
        return true, "所有孔位已锁定", { hit = true }
    end

    -- 随机选目标孔位
    local targetIdx = candidates[math.random(1, #candidates)]

    -- 随机属性和档位
    local attrDef = RollAttribute()
    local tierDef = RollTier()
    local value, statKey = CalcTemperValue(attrDef, tierDef, slotId)

    -- 写入孔位
    temper.slots[targetIdx] = {
        attrId = attrDef.id,
        attrName = attrDef.name,
        statKey = statKey,      -- 实际作用的属性key
        value = value,
        tierId = tierDef.id,
        tierName = tierDef.name,
        tierColor = tierDef.color,
        locked = false,
    }

    HeroData.Save(true)  -- 淬炼成功消耗货币，立即云端保存
    return true, "淬炼成功!", {
        hit = true,
        slotIdx = targetIdx,
        attrDef = attrDef,
        tierDef = tierDef,
        value = value,
        statKey = statKey,
    }
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
            result[slot.statKey] = (result[slot.statKey] or 0) + slot.value
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
    end
    return total
end

-- ============================================================================
-- 格式化显示
-- ============================================================================

--- 格式化淬炼属性值
---@param slot table  孔位数据 { attrId, statKey, value, tierId, ... }
---@param slotId string  部位ID
---@return string  如 "+12 攻击" 或 "+0.15% 暴击率"
function TemperData.FormatSlotValue(slot, slotId)
    if not slot then return "" end

    -- "攻击力"词条在不同部位显示不同属性名
    local displayName = slot.attrName or slot.attrId
    if slot.attrId == "atk" then
        local slotDef = GetSlotDef(slotId)
        if slotDef then
            displayName = slotDef.statName
        end
    end

    -- 武器的攻击力是固定值，其他都是百分比
    if slot.statKey == "atk" then
        return "+" .. tostring(math.floor(slot.value)) .. " " .. displayName
    else
        return string.format("+%.2f%% %s", slot.value * 100, displayName)
    end
end

return TemperData
