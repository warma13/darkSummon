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
        shards = {},  -- { [relicId] = count } 每件遗物独立碎片
        owned = {},  -- { [relicId] = quality } 已拥有的遗物及其品质
        progress = {},  -- { [relicId] = { level, star } } 遗物升级进度（换装时保留）
    }
    HeroData.relicData, relicSnapshot = SafeTable.CreateDeep(data)
end

--- 设置 relicData（反序列化时调用）
---@param data table|nil 明文遗物数据
function RelicData.SetData(data)
    if data then
        -- 防止空表覆盖已有数据（云存档损坏时可能返回 {}）
        local hasContent = (data.equipped and next(data.equipped))
            or (data.owned and next(data.owned))
            or (data.shards and next(data.shards))
            or (data.progress and next(data.progress))
        if not hasContent and HeroData.relicData and next(HeroData.relicData) then
            print("[RelicData] WARNING: SetData received empty data, keeping existing relicData")
            return
        end
        -- 补全旧存档缺失字段
        data.equipped = data.equipped or {}
        data.shards = data.shards or {}
        data.owned = data.owned or {}
        data.progress = data.progress or {}
        -- 旧存档兼容：从已装备遗物中恢复 progress
        for _, sid in ipairs(Config.RELIC_SLOT_IDS) do
            local eq = data.equipped[sid]
            if eq and eq.id and ((eq.level or 1) > 1 or (eq.star or 0) > 0) then
                if not data.progress[eq.id] then
                    data.progress[eq.id] = { level = eq.level or 1, star = eq.star or 0 }
                end
            end
        end
        -- 旧存档迁移：部位碎片 → 遗物碎片
        -- 检测旧格式（shards key 为 slotId 如 "power"/"heart"）
        local needMigrate = false
        for _, slotId in ipairs(Config.RELIC_SLOT_IDS) do
            if data.shards[slotId] and type(data.shards[slotId]) == "number" and data.shards[slotId] > 0 then
                needMigrate = true
                break
            end
        end
        if needMigrate then
            local oldShards = {}
            for _, slotId in ipairs(Config.RELIC_SLOT_IDS) do
                oldShards[slotId] = data.shards[slotId] or 0
                data.shards[slotId] = nil  -- 清除旧 key
            end
            -- 将部位碎片平均分配给该部位下未拥有的遗物
            for slotId, count in pairs(oldShards) do
                if count > 0 then
                    local slotRelics = Config.RELICS_BY_SLOT[slotId] or {}
                    local unowned = {}
                    for _, rDef in ipairs(slotRelics) do
                        if not data.owned[rDef.id] then
                            unowned[#unowned + 1] = rDef.id
                        end
                    end
                    if #unowned > 0 then
                        local perRelic = math.floor(count / #unowned)
                        local remainder = count - perRelic * #unowned
                        for i, relicId in ipairs(unowned) do
                            data.shards[relicId] = (data.shards[relicId] or 0) + perRelic + (i == 1 and remainder or 0)
                        end
                    else
                        -- 全部已拥有，分配给第一个遗物
                        local firstRelic = (Config.RELICS_BY_SLOT[slotId] or {})[1]
                        if firstRelic then
                            data.shards[firstRelic.id] = (data.shards[firstRelic.id] or 0) + count
                        end
                    end
                end
            end
            print("[RelicData] Migrated old slot-shards to per-relic shards")
        end
        -- 旧存档兼容：已装备的遗物自动标记为拥有
        for _, slotId in ipairs(Config.RELIC_SLOT_IDS) do
            local eq = data.equipped[slotId]
            if eq and eq.id and not data.owned[eq.id] then
                data.owned[eq.id] = eq.quality or "green"
            end
        end
        HeroData.relicData, relicSnapshot = SafeTable.CreateDeep(data)

        -- 一次性迁移：碎片足够但未拥有的遗物自动合成（只跑一次）
        if not data.shardSynthMigrated then
            local synthCount = 0
            for relicId, _ in pairs(Config.RELICS) do
                local result = RelicData.TrySynthesize(relicId)
                if result then
                    synthCount = synthCount + 1
                end
            end
            HeroData.relicData.shardSynthMigrated = true
            if synthCount > 0 then
                print("[RelicData] Migration: auto-synthesized " .. synthCount .. " relics from existing shards")
            end
        end
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

--- 获取指定遗物的碎片数量
---@param relicId string 遗物 id（如 "judgment_spear"）
---@return number
function RelicData.GetShards(relicId)
    EnsureData()
    return HeroData.relicData.shards[relicId] or 0
end

--- 获取遗物的升级进度（已装备/未装备通用）
---@param relicId string
---@return number level, number star
function RelicData.GetProgress(relicId)
    EnsureData()
    -- 优先从装备槽读取（装备中的遗物是最新数据）
    for _, sid in ipairs(Config.RELIC_SLOT_IDS) do
        local eq = HeroData.relicData.equipped[sid]
        if eq and eq.id == relicId then
            return eq.level or 1, eq.star or 0
        end
    end
    -- 未装备：从 progress 读取
    local saved = HeroData.relicData.progress[relicId]
    if saved then
        return saved.level or 1, saved.star or 0
    end
    return 1, 0
end

--- 获取指定部位下所有遗物的碎片总数
---@param slotId string "power"/"heart"/"eye"/"will"
---@return number
function RelicData.GetSlotShards(slotId)
    EnsureData()
    local total = 0
    local slotRelics = Config.RELICS_BY_SLOT[slotId] or {}
    for _, rDef in ipairs(slotRelics) do
        total = total + (HeroData.relicData.shards[rDef.id] or 0)
    end
    return total
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

--- 处理一次遗物掉落（per-relic 碎片模式）
--- 掉落 → 获得具体遗物碎片（数量按品质）；碎片达到合成阈值时自动合成遗物
---@param drop table { slotId, relicId, quality } 由 RollDrop 生成
---@return table { slotId, relicId, relicName, shards, synthResult: table|nil }
function RelicData.ProcessDrop(drop)
    EnsureData()

    -- 按品质决定碎片数量
    local qIdx = Config.RELIC_QUALITY_INDEX[drop.quality] or 1
    local shardCount = qIdx  -- 精良1 稀有2 史诗3 传说4 神话5

    -- 给具体遗物加碎片
    HeroData.relicData.shards[drop.relicId] = (HeroData.relicData.shards[drop.relicId] or 0) + shardCount
    local relicDef = Config.RELICS[drop.relicId]
    local relicName = relicDef and relicDef.name or drop.relicId
    print("[RelicData] Drop → +" .. shardCount .. " " .. relicName .. " shards (quality=" .. drop.quality .. ")")

    -- 检查自动合成：该遗物碎片是否达到合成阈值
    local synthResult = RelicData.TrySynthesize(drop.relicId)

    HeroData.Save()
    return {
        slotId = drop.slotId,
        relicId = drop.relicId,
        relicName = relicName,
        shards = shardCount,
        synthResult = synthResult,  -- nil 表示未触发合成
    }
end

--- 尝试自动合成：检查指定遗物碎片是否达到合成阈值
--- 碎片足够且未拥有时自动合成
---@param relicId string 遗物 id
---@return table|nil { relicId, relicName, quality, cost }
function RelicData.TrySynthesize(relicId)
    EnsureData()
    -- 已拥有则不合成
    if HeroData.relicData.owned[relicId] then return nil end

    local rDef = Config.RELICS[relicId]
    if not rDef then return nil end

    local shards = HeroData.relicData.shards[relicId] or 0
    local cost = Config.RELIC_SYNTH_COST[rDef.minQuality] or 80

    if shards >= cost then
        -- 扣碎片、标记拥有
        HeroData.relicData.shards[relicId] = shards - cost
        HeroData.relicData.owned[relicId] = rDef.minQuality
        print("[RelicData] SYNTH " .. rDef.name .. " (" .. rDef.minQuality .. ") cost " .. cost .. " " .. relicId .. " shards")
        return {
            relicId = rDef.id,
            relicName = rDef.name,
            quality = rDef.minQuality,
            cost = cost,
        }
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

    -- 保存当前槽位旧遗物的升级进度（如果有）
    local oldRelic = HeroData.relicData.equipped[slotId]
    if oldRelic and oldRelic.id then
        HeroData.relicData.progress[oldRelic.id] = {
            level = oldRelic.level or 1,
            star = oldRelic.star or 0,
        }
    end

    -- 从 progress 恢复新遗物的升级进度（如果曾经升级过）
    local saved = HeroData.relicData.progress[relicId]
    local restoredLevel = (saved and saved.level) or 1
    local restoredStar = (saved and saved.star) or 0

    HeroData.relicData.equipped[slotId] = {
        id = relicId,
        quality = quality,
        level = restoredLevel,
        star = restoredStar,
    }

    HeroData.Save()
    print("[RelicData] Equipped " .. def.name .. " (" .. quality .. ") Lv." .. restoredLevel .. " ★" .. restoredStar .. " at " .. slotId)
    return true, "装备成功"
end

--- 卸下遗物（返还碎片时使用）
---@param slotId string
---@return boolean, string
function RelicData.Unequip(slotId)
    EnsureData()
    local relic = HeroData.relicData.equipped[slotId]
    if not relic then
        return false, "该部位无遗物"
    end
    -- 卸下前保存升级进度
    if relic.id then
        HeroData.relicData.progress[relic.id] = {
            level = relic.level or 1,
            star = relic.star or 0,
        }
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
    -- 同步更新 progress 保底记录
    HeroData.relicData.progress[relic.id] = { level = relic.level, star = relic.star or 0 }
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
        -- 同步更新 progress 保底记录
        HeroData.relicData.progress[relic.id] = { level = relic.level, star = relic.star or 0 }
        HeroData.Save()
        print("[RelicData] UpgradeMulti " .. slotId .. " +" .. upgraded .. " levels")
    end
    return upgraded, totalCost
end

-- ============================================================================
-- 升星
-- ============================================================================

--- 用碎片升星（消耗该遗物自身的碎片）
---@param slotId string 部位 id
---@return boolean, string
function RelicData.StarUp(slotId)
    EnsureData()
    local relic = HeroData.relicData.equipped[slotId]
    if not relic then return false, "该部位无遗物" end

    local relicId = relic.id
    local shardCost = RelicCalc.GetStarUpShardCost(relic.star)
    local shards = HeroData.relicData.shards[relicId] or 0
    if shards < shardCost then
        return false, "碎片不足(需" .. shardCost .. "，当前" .. shards .. ")"
    end

    HeroData.relicData.shards[relicId] = shards - shardCost
    relic.star = relic.star + 1
    -- 同步更新 progress 保底记录
    HeroData.relicData.progress[relicId] = { level = relic.level or 1, star = relic.star }
    HeroData.Save()
    print("[RelicData] StarUp " .. relicId .. " to ★" .. relic.star)
    return true, "升星成功 ★" .. relic.star
end

--- 按遗物 ID 升级（支持未装备遗物，操作 progress 表）
---@param relicId string
---@return boolean, string
function RelicData.UpgradeByRelicId(relicId)
    EnsureData()
    if not RelicData.IsOwned(relicId) then return false, "未拥有该遗物" end

    -- 如果该遗物正装备着，委托给原有按槽位的 Upgrade
    for _, sid in ipairs(Config.RELIC_SLOT_IDS) do
        local eq = HeroData.relicData.equipped[sid]
        if eq and eq.id == relicId then
            return RelicData.Upgrade(sid)
        end
    end

    -- 未装备：操作 progress
    local prog = HeroData.relicData.progress[relicId] or { level = 1, star = 0 }
    local cost = RelicCalc.GetUpgradeCost(prog.level)
    local essence = HeroData.currencies.relic_essence or 0
    if essence < cost then
        return false, "遗物精华不足(需" .. cost .. ")"
    end

    HeroData.currencies.relic_essence = essence - cost
    prog.level = prog.level + 1
    HeroData.relicData.progress[relicId] = prog
    HeroData.Save()
    print("[RelicData] UpgradeByRelicId " .. relicId .. " to Lv." .. prog.level)
    return true, "升级成功 Lv." .. prog.level
end

--- 按遗物 ID 升星（支持未装备遗物，操作 progress 表）
---@param relicId string
---@return boolean, string
function RelicData.StarUpByRelicId(relicId)
    EnsureData()
    if not RelicData.IsOwned(relicId) then return false, "未拥有该遗物" end

    -- 如果该遗物正装备着，委托给原有按槽位的 StarUp
    for _, sid in ipairs(Config.RELIC_SLOT_IDS) do
        local eq = HeroData.relicData.equipped[sid]
        if eq and eq.id == relicId then
            return RelicData.StarUp(sid)
        end
    end

    -- 未装备：操作 progress
    local prog = HeroData.relicData.progress[relicId] or { level = 1, star = 0 }
    local shardCost = RelicCalc.GetStarUpShardCost(prog.star)
    local shards = HeroData.relicData.shards[relicId] or 0
    if shards < shardCost then
        return false, "碎片不足(需" .. shardCost .. "，当前" .. shards .. ")"
    end

    HeroData.relicData.shards[relicId] = shards - shardCost
    prog.star = prog.star + 1
    HeroData.relicData.progress[relicId] = prog
    HeroData.Save()
    print("[RelicData] StarUpByRelicId " .. relicId .. " to ★" .. prog.star)
    return true, "升星成功 ★" .. prog.star
end

-- ============================================================================
-- 分解（重复遗物 → 碎片）
-- ============================================================================

--- 增加指定遗物的碎片（分解/奖励通用）
---@param relicId string 遗物 id
---@param shardCount number 获得的碎片数（默认1）
---@return boolean, string
function RelicData.Decompose(relicId, shardCount)
    EnsureData()
    shardCount = shardCount or 1
    HeroData.relicData.shards[relicId] = (HeroData.relicData.shards[relicId] or 0) + shardCount

    -- 碎片增加后检查自动合成
    local synthResult = RelicData.TrySynthesize(relicId)

    HeroData.Save()
    local relicDef = Config.RELICS[relicId]
    local name = relicDef and relicDef.name or relicId
    print("[RelicData] Decompose +" .. shardCount .. " " .. name .. " shards")
    if synthResult then
        return true, "分解获得 " .. shardCount .. " 个" .. name .. "碎片，并合成了 " .. synthResult.relicName
    end
    return true, "分解获得 " .. shardCount .. " 个" .. name .. "碎片"
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
        local ewDef = Config.RELICS.eternal_will
        globalAmp = RelicCalc.V(willRelic, ewDef.params.globalAmplify)
        -- 星级效果：增幅提高（渐进值）
        if ewDef.starEffect and ewDef.starEffect.type == "amplifyAdd" then
            globalAmp = globalAmp + RelicCalc.StarValue(willRelic.star, ewDef.starEffect)
        end
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
            -- 星级效果：critDmg (生命洪流)
            if hDef.starEffect and hDef.starEffect.type == "critDmg" then
                bonus.critDmgPct = bonus.critDmgPct + RelicCalc.StarValue(heartRelic.star, hDef.starEffect)
            end
            -- 星级效果：critRate (战意之核)
            if hDef.starEffect and hDef.starEffect.type == "critRate" then
                bonus.critRatePct = (bonus.critRatePct or 0) + RelicCalc.StarValue(heartRelic.star, hDef.starEffect)
            end
            -- 万象归一: 红色遗物额外加成
            if heartRelic.id == "unity_of_all" then
                local redCount = RelicData.CountRedRelics()
                local extraPct = p.redRelicBonusPer * redCount
                -- 星级效果：redBonus 提高每件神话遗物的加成
                if hDef.starEffect and hDef.starEffect.type == "redBonus" then
                    extraPct = extraPct + RelicCalc.StarValue(heartRelic.star, hDef.starEffect) * redCount
                end
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
                local fbAtk = RelicCalc.V(willR, wDef.params.fallbackAtkBonus)
                if wDef.starEffect and wDef.starEffect.type == "fallbackAdd" then
                    fbAtk = fbAtk + RelicCalc.StarValue(willR.star, wDef.starEffect)
                end
                bonus.atkPct = bonus.atkPct + fbAtk * ampMult
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

    -- 永恒意志增幅（含星级 amplifyAdd）
    local globalAmp = 0
    local willRelic = HeroData.relicData.equipped.will
    if willRelic and willRelic.id == "eternal_will" then
        local ewDef = Config.RELICS.eternal_will
        globalAmp = RelicCalc.V(willRelic, ewDef.params.globalAmplify)
        if ewDef.starEffect and ewDef.starEffect.type == "amplifyAdd" then
            globalAmp = globalAmp + RelicCalc.StarValue(willRelic.star, ewDef.starEffect)
        end
    end

    if isTopAtk then
        return topBonus * (1 + globalAmp)
    else
        -- 星级效果：shareRatio 提高其余英雄分配比
        local ratio = def.params.otherAtkRatio
        if def.starEffect and def.starEffect.type == "shareRatio" then
            ratio = ratio + RelicCalc.StarValue(heartRelic.star, def.starEffect)
        end
        return topBonus * ratio * (1 + globalAmp)
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
