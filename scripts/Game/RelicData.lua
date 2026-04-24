-- Game/RelicData.lua
-- 神圣遗物数据管理（CRUD + 存档 + 掉落）
-- 模式参考 EquipData.lua: 懒初始化 + SafeTable + SaveRegistry 自注册

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")
local SafeTable = require("Game.SafeTable")
local RelicCalc = require("Game.RelicCalc")

local RelicData = {}

-- ============================================================================
-- 存档快照（SafeTable 代理）
-- ============================================================================
local relicSnapshot = nil

--- 确保 HeroData.relicData 已初始化
local function EnsureData()
    if HeroData.relicData then return end
    local data = {
        equipped = {
            power = nil,  -- { id, quality, level, star }
            heart = nil,
            eye   = nil,
            will  = nil,
        },
        shards = {
            power = 0,
            heart = 0,
            eye   = 0,
            will  = 0,
        },
        owned = {},  -- { [relicId] = quality } 已拥有的遗物及其品质
    }
    HeroData.relicData, relicSnapshot = SafeTable.CreateDeep(data)
end

--- 设置 relicData（反序列化时调用）
---@param data table|nil 明文遗物数据
function RelicData.SetData(data)
    if data then
        -- 补全旧存档缺失字段
        data.equipped = data.equipped or {}
        data.shards = data.shards or {}
        data.owned = data.owned or {}
        for _, slotId in ipairs(Config.RELIC_SLOT_IDS) do
            if data.shards[slotId] == nil then
                data.shards[slotId] = 0
            end
        end
        -- 旧存档兼容：已装备的遗物自动标记为拥有
        for _, slotId in ipairs(Config.RELIC_SLOT_IDS) do
            local eq = data.equipped[slotId]
            if eq and eq.id and not data.owned[eq.id] then
                data.owned[eq.id] = eq.quality or "green"
            end
        end
        HeroData.relicData, relicSnapshot = SafeTable.CreateDeep(data)
    else
        HeroData.relicData = nil
        relicSnapshot = nil
    end
end

--- 获取明文快照（序列化时调用）
---@return table|nil
function RelicData.GetSnapshot()
    if relicSnapshot then
        return relicSnapshot()
    end
    return HeroData.relicData
end

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 获取指定部位的装备遗物
---@param slotId string "power"/"heart"/"eye"/"will"
---@return table|nil  { id, quality, level, star }
function RelicData.GetEquipped(slotId)
    EnsureData()
    return HeroData.relicData.equipped[slotId]
end

--- 获取所有已装备遗物
---@return table { power=..., heart=..., eye=..., will=... }
function RelicData.GetAllEquipped()
    EnsureData()
    return HeroData.relicData.equipped
end

--- 检查是否装备了指定部位的指定遗物
---@param slotId string
---@param relicId string
---@return boolean
function RelicData.HasRelic(slotId, relicId)
    EnsureData()
    local r = HeroData.relicData.equipped[slotId]
    return r ~= nil and r.id == relicId
end

--- 获取指定部位碎片数量
---@param slotId string
---@return number
function RelicData.GetShards(slotId)
    EnsureData()
    return HeroData.relicData.shards[slotId] or 0
end

--- 统计已装备的红色品质遗物数量
---@return number
function RelicData.CountRedRelics()
    EnsureData()
    local count = 0
    for _, slotId in ipairs(Config.RELIC_SLOT_IDS) do
        local r = HeroData.relicData.equipped[slotId]
        if r and r.quality == "red" then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- 拥有系统
-- ============================================================================

--- 检查是否拥有指定遗物
---@param relicId string
---@return boolean
function RelicData.IsOwned(relicId)
    EnsureData()
    return HeroData.relicData.owned[relicId] ~= nil
end

--- 获取拥有遗物的品质
---@param relicId string
---@return string|nil  品质 id，未拥有返回 nil
function RelicData.GetOwnedQuality(relicId)
    EnsureData()
    return HeroData.relicData.owned[relicId] or nil
end

--- 获取指定部位已拥有的遗物列表
---@param slotId string
---@return table[]  { relicDef, quality }
function RelicData.GetOwnedBySlot(slotId)
    EnsureData()
    local result = {}
    local slotRelics = Config.RELICS_BY_SLOT[slotId] or {}
    for _, rDef in ipairs(slotRelics) do
        local q = HeroData.relicData.owned[rDef.id]
        if q then
            result[#result + 1] = { def = rDef, quality = q }
        end
    end
    return result
end

--- 处理一次遗物掉落（纯碎片模式）
--- 掉落 → 获得对应部位碎片（数量按品质）；碎片达到合成阈值时自动合成遗物
---@param drop table { slotId, relicId, quality } 由 RollDrop 生成
---@return table { slotId, shards, synthResult: table|nil }
function RelicData.ProcessDrop(drop)
    EnsureData()

    -- 按品质决定碎片数量
    local qIdx = Config.RELIC_QUALITY_INDEX[drop.quality] or 1
    local shardCount = qIdx  -- 精良1 稀有2 史诗3 传说4 神话5

    HeroData.relicData.shards[drop.slotId] = (HeroData.relicData.shards[drop.slotId] or 0) + shardCount
    print("[RelicData] Drop → +" .. shardCount .. " " .. drop.slotId .. " shards (quality=" .. drop.quality .. ")")

    -- 检查自动合成：尝试从高品质到低品质合成
    local synthResult = RelicData.TrySynthesize(drop.slotId)

    HeroData.Save()
    return {
        slotId = drop.slotId,
        shards = shardCount,
        synthResult = synthResult,  -- nil 表示未触发合成
    }
end

--- 尝试自动合成：检查指定部位碎片是否达到某个品质的合成阈值
--- 优先合成未拥有的最低品质遗物
---@param slotId string
---@return table|nil { relicId, relicName, quality, cost }
function RelicData.TrySynthesize(slotId)
    EnsureData()
    local shards = HeroData.relicData.shards[slotId] or 0
    local slotRelics = Config.RELICS_BY_SLOT[slotId] or {}

    -- 从低品质到高品质遍历，找第一个未拥有且碎片够的
    for _, rDef in ipairs(slotRelics) do
        if not HeroData.relicData.owned[rDef.id] then
            local cost = Config.RELIC_SYNTH_COST[rDef.minQuality] or 80
            if shards >= cost then
                -- 扣碎片、标记拥有
                HeroData.relicData.shards[slotId] = shards - cost
                HeroData.relicData.owned[rDef.id] = rDef.minQuality
                print("[RelicData] SYNTH " .. rDef.name .. " (" .. rDef.minQuality .. ") cost " .. cost .. " " .. slotId .. " shards")
                return {
                    relicId = rDef.id,
                    relicName = rDef.name,
                    quality = rDef.minQuality,
                    cost = cost,
                }
            end
        end
    end
    return nil
end

--- 获取遗物的缩放参数值
---@param slotId string
---@param paramKey string
---@return number  缩放后的值（未装备返回 0）
function RelicData.GetParamValue(slotId, paramKey)
    local relic = RelicData.GetEquipped(slotId)
    if not relic then return 0 end
    local def = Config.RELICS[relic.id]
    if not def or not def.params[paramKey] then return 0 end
    return RelicCalc.V(relic, def.params[paramKey])
end

-- ============================================================================
-- 装备/替换
-- ============================================================================

--- 装备一件新遗物（替换当前）
---@param slotId string
---@param relicId string
---@param quality string
---@return boolean, string
function RelicData.Equip(slotId, relicId, quality)
    EnsureData()
    local def = Config.RELICS[relicId]
    if not def then return false, "遗物不存在: " .. relicId end
    if def.slot ~= slotId then return false, "部位不匹配" end

    -- 拥有检查
    if not HeroData.relicData.owned[relicId] then
        return false, "尚未拥有此遗物"
    end

    -- 使用拥有时获得的品质
    quality = HeroData.relicData.owned[relicId]

    HeroData.relicData.equipped[slotId] = {
        id = relicId,
        quality = quality,
        level = 1,
        star = 0,
    }

    HeroData.Save()
    print("[RelicData] Equipped " .. def.name .. " (" .. quality .. ") at " .. slotId)
    return true, "装备成功"
end

--- 卸下遗物（返还碎片时使用）
---@param slotId string
---@return boolean, string
function RelicData.Unequip(slotId)
    EnsureData()
    if not HeroData.relicData.equipped[slotId] then
        return false, "该部位无遗物"
    end
    HeroData.relicData.equipped[slotId] = nil
    HeroData.Save()
    return true, "已卸下"
end

-- ============================================================================
-- 升级
-- ============================================================================

--- 升级遗物（消耗遗物精华 relic_essence）
---@param slotId string
---@return boolean, string
function RelicData.Upgrade(slotId)
    EnsureData()
    local relic = HeroData.relicData.equipped[slotId]
    if not relic then return false, "该部位无遗物" end

    local cost = RelicCalc.GetUpgradeCost(relic.level)
    local essence = HeroData.currencies.relic_essence or 0
    if essence < cost then
        return false, "遗物精华不足(需" .. cost .. ")"
    end

    HeroData.currencies.relic_essence = essence - cost
    relic.level = relic.level + 1
    HeroData.Save()
    print("[RelicData] Upgrade " .. slotId .. " to Lv." .. relic.level)
    return true, "升级成功 Lv." .. relic.level
end

--- 批量升级
---@param slotId string
---@param maxCount number 最多升多少级
---@return number upgraded, number totalCost
function RelicData.UpgradeMulti(slotId, maxCount)
    EnsureData()
    local relic = HeroData.relicData.equipped[slotId]
    if not relic then return 0, 0 end

    local upgraded = 0
    local totalCost = 0
    while upgraded < maxCount do
        local cost = RelicCalc.GetUpgradeCost(relic.level)
        local essence = HeroData.currencies.relic_essence or 0
        if essence < cost then break end
        HeroData.currencies.relic_essence = essence - cost
        relic.level = relic.level + 1
        totalCost = totalCost + cost
        upgraded = upgraded + 1
    end

    if upgraded > 0 then
        HeroData.Save()
        print("[RelicData] UpgradeMulti " .. slotId .. " +" .. upgraded .. " levels")
    end
    return upgraded, totalCost
end

-- ============================================================================
-- 升星
-- ============================================================================

--- 用碎片升星
---@param slotId string
---@return boolean, string
function RelicData.StarUp(slotId)
    EnsureData()
    local relic = HeroData.relicData.equipped[slotId]
    if not relic then return false, "该部位无遗物" end

    local shardCost = RelicCalc.GetStarUpShardCost(relic.star)
    local shards = HeroData.relicData.shards[slotId] or 0
    if shards < shardCost then
        return false, "碎片不足(需" .. shardCost .. "，当前" .. shards .. ")"
    end

    HeroData.relicData.shards[slotId] = shards - shardCost
    relic.star = relic.star + 1
    HeroData.Save()
    print("[RelicData] StarUp " .. slotId .. " to ★" .. relic.star)
    return true, "升星成功 ★" .. relic.star
end

-- ============================================================================
-- 分解（重复遗物 → 碎片）
-- ============================================================================

--- 分解一件遗物为碎片
---@param slotId string 遗物所属部位
---@param shardCount number 获得的碎片数（默认1）
---@return boolean, string
function RelicData.Decompose(slotId, shardCount)
    EnsureData()
    shardCount = shardCount or 1
    HeroData.relicData.shards[slotId] = (HeroData.relicData.shards[slotId] or 0) + shardCount
    HeroData.Save()
    print("[RelicData] Decompose +%d %s shards", shardCount, slotId)
    return true, "分解获得 " .. shardCount .. " 个碎片"
end

-- ============================================================================
-- 掉落生成
-- ============================================================================

--- 随机生成一件遗物（从指定难度的品质权重中抽取）
---@param difficulty string "normal"/"hard"/"nightmare"/"hell"
---@return table { slotId, relicId, quality }
function RelicData.RollDrop(difficulty)
    difficulty = difficulty or "normal"
    local weights = Config.RELIC_DROP_WEIGHTS[difficulty] or Config.RELIC_DROP_WEIGHTS.normal

    -- 随机部位
    local slotId = Config.RELIC_SLOT_IDS[math.random(1, #Config.RELIC_SLOT_IDS)]

    -- 随机品质（加权）
    local totalWeight = 0
    for _, w in pairs(weights) do totalWeight = totalWeight + w end
    local roll = math.random() * totalWeight
    local acc = 0
    local quality = "green"
    for _, q in ipairs(Config.RELIC_QUALITIES) do
        acc = acc + (weights[q.id] or 0)
        if roll <= acc then
            quality = q.id
            break
        end
    end

    -- 从该部位该品质及以下遗物池中随机
    local pool = {}
    local qualityIdx = Config.RELIC_QUALITY_INDEX[quality] or 1
    for _, relic in ipairs(Config.RELICS_BY_SLOT[slotId]) do
        local minIdx = Config.RELIC_QUALITY_INDEX[relic.minQuality] or 1
        if qualityIdx >= minIdx then
            pool[#pool + 1] = relic
        end
    end

    if #pool == 0 then
        -- 降级到最低品质遗物
        pool = Config.RELICS_BY_SLOT[slotId]
    end

    local chosen = pool[math.random(1, #pool)]
    return {
        slotId = slotId,
        relicId = chosen.id,
        quality = quality,
    }
end

-- ============================================================================
-- 战斗属性汇总（供 Tower 调用）
-- ============================================================================

--- 获取遗物对全体英雄的被动属性加成
--- 返回各项独立加成值（不与装备系统合并，由 Tower 单独乘算）
---@return table { atkPct, spdPct, critDmgPct, ... }
function RelicData.GetPassiveBonus()
    EnsureData()
    local bonus = {
        atkPct = 0,
        spdPct = 0,
        critDmgPct = 0,
    }

    -- 永恒意志(will·red)全局增幅系数
    local globalAmp = 0
    local willRelic = HeroData.relicData.equipped.will
    if willRelic and willRelic.id == "eternal_will" then
        globalAmp = RelicCalc.V(willRelic, Config.RELICS.eternal_will.params.globalAmplify)
    end
    local ampMult = 1 + globalAmp

    -- 心部位被动
    local heartRelic = HeroData.relicData.equipped.heart
    if heartRelic then
        local hDef = Config.RELICS[heartRelic.id]
        if hDef then
            local p = hDef.params
            if p.atkBonus then
                bonus.atkPct = bonus.atkPct + RelicCalc.V(heartRelic, p.atkBonus) * ampMult
            end
            if p.spdBonus then
                bonus.spdPct = bonus.spdPct + RelicCalc.V(heartRelic, p.spdBonus) * ampMult
            end
            if p.critDmgBonus then
                bonus.critDmgPct = bonus.critDmgPct + RelicCalc.V(heartRelic, p.critDmgBonus) * ampMult
            end
            -- 万象归一: 红色遗物额外加成
            if heartRelic.id == "unity_of_all" then
                local redCount = RelicData.CountRedRelics()
                local extraPct = p.redRelicBonusPer * redCount
                bonus.atkPct = bonus.atkPct + extraPct * ampMult
                bonus.spdPct = bonus.spdPct + extraPct * ampMult
                bonus.critDmgPct = bonus.critDmgPct + extraPct * ampMult
            end
        end
    end

    -- 力部位被动: void_pulse 攻击力加成
    local powerRelic = HeroData.relicData.equipped.power
    if powerRelic and powerRelic.id == "void_pulse" then
        local pDef = Config.RELICS.void_pulse
        bonus.atkPct = bonus.atkPct + RelicCalc.V(powerRelic, pDef.params.atkBonus) * ampMult
    end

    -- 意志部位回退: rapid_charge 无充能时→攻速；fervent_faith 无伤害技能时→攻击
    local willR = HeroData.relicData.equipped.will
    if willR then
        local wDef = Config.RELICS[willR.id]
        if wDef then
            local powerHasCharge = powerRelic and Config.RELICS[powerRelic.id]
                and Config.RELICS[powerRelic.id].hasCharge
            if willR.id == "rapid_charge" and not powerHasCharge then
                bonus.spdPct = bonus.spdPct + RelicCalc.V(willR, wDef.params.fallbackSpdBonus) * ampMult
            end
            if willR.id == "fervent_faith" and (not powerRelic or powerRelic.id == "void_pulse") then
                bonus.atkPct = bonus.atkPct + RelicCalc.V(willR, wDef.params.fallbackAtkBonus) * ampMult
            end
        end
    end

    return bonus
end

--- 获取暗影凝聚（shadow_focus）针对特定英雄的额外攻击加成
---@param tower table 塔实例
---@param isTopAtk boolean 是否为攻击力最高的英雄
---@return number 额外攻击百分比
function RelicData.GetShadowFocusBonus(tower, isTopAtk)
    EnsureData()
    local heartRelic = HeroData.relicData.equipped.heart
    if not heartRelic or heartRelic.id ~= "shadow_focus" then return 0 end

    local def = Config.RELICS.shadow_focus
    local topBonus = RelicCalc.V(heartRelic, def.params.topAtkBonus)

    -- 永恒意志增幅
    local globalAmp = 0
    local willRelic = HeroData.relicData.equipped.will
    if willRelic and willRelic.id == "eternal_will" then
        globalAmp = RelicCalc.V(willRelic, Config.RELICS.eternal_will.params.globalAmplify)
    end

    if isTopAtk then
        return topBonus * (1 + globalAmp)
    else
        return topBonus * def.params.otherAtkRatio * (1 + globalAmp)
    end
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

SaveRegistry.Register("relicData", {
    group = "meta_game",
    order = 76,  -- hatredLandData(71) 之后
    initDefault = function()
        RelicData.SetData(nil)
    end,
    serialize = function()
        return RelicData.GetSnapshot()
    end,
    deserialize = function(saved, _saveData)
        RelicData.SetData(saved)
    end,
})

return RelicData
