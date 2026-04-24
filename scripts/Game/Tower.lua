-- Game/Tower.lua
-- 暗黑塔防游戏 - 塔/英雄管理 + 合成逻辑
-- v2: 权重召唤、合成保类型、★4★5需3个、局外加成

local Config = require("Game.Config")
local State = require("Game.State")
local Grid = require("Game.Grid")
local HeroData = require("Game.HeroData")
local HeroSkills = require("Game.HeroSkills")
local Currency = require("Game.Currency")
local EquipData = require("Game.EquipData")
local HeroAnim = require("Game.HeroAnim")
local DivineBlessDB = require("Game.DivineBlessData")

-- 延迟 require 遗物模块（避免循环依赖）
local _RelicData, _RelicEffects
local function GetRelicData()
    if not _RelicData then
        local ok, mod = pcall(require, "Game.RelicData")
        if ok then _RelicData = mod end
    end
    return _RelicData
end
local function GetRelicEffects()
    if not _RelicEffects then
        local ok, mod = pcall(require, "Game.RelicEffects")
        if ok then _RelicEffects = mod end
    end
    return _RelicEffects
end

local Tower = {}

local nextTowerId = 1

--- 根据英雄ID找到 TOWER_TYPES 中的索引
---@param heroId string
---@return number|nil
function Tower.FindTypeIndex(heroId)
    for i, t in ipairs(Config.TOWER_TYPES) do
        if t.id == heroId then return i end
    end
    return nil
end

--- 创建一个塔实例（应用局外加成）
function Tower.Create(typeIndex, star, col, row)
    local typeDef = Config.TOWER_TYPES[typeIndex]
    if not typeDef then
        print("[Tower] ERROR: invalid typeIndex=" .. tostring(typeIndex))
        return nil
    end

    local starMult = Config.STAR_MULTIPLIER[star] or 1.0
    local starRange = Config.STAR_RANGE_BONUS[star] or 0
    local starSpeed = Config.STAR_SPEED_MULT[star] or 1.0

    -- 局外加成
    local heroId = typeDef.id
    local levelRange = HeroData.GetLevelRangeBonus(heroId)

    -- 获取英雄等级和升星信息（用于显示）
    local heroInfo = HeroData.Get(heroId)
    local heroLevel = heroInfo and heroInfo.level or 1
    local heroStar = heroInfo and heroInfo.star or 0
    local heroAwakening = heroInfo and heroInfo.awakening or 0

    -- 获取英雄完整战斗属性（含破甲/暴击/暴伤）
    local heroStats = HeroData.GetHeroStats(heroId)

    -- 获取装备加成（含淬炼+符文）
    local equipBonus = EquipData.GetTotalBonus(heroId)
    local equipAtk = equipBonus.atk or 0
    local atkPctBonus = equipBonus.atk_pct or 0
    local spdPctBonus = equipBonus.spd_pct or 0
    local rangeBonus = equipBonus.range or 0

    -- 遗物被动加成（独立乘区）
    local relicAtkPct, relicSpdPct, relicCritDmgPct = 0, 0, 0
    local RD = GetRelicData()
    if RD then
        local relicBonus = RD.GetPassiveBonus()
        relicAtkPct = relicBonus.atkPct or 0
        relicSpdPct = relicBonus.spdPct or 0
        relicCritDmgPct = relicBonus.critDmgPct or 0
    end

    local tower = {
        id = nextTowerId,
        typeIndex = typeIndex,
        typeDef = typeDef,
        star = star,
        col = col,
        row = row,
        -- 最终攻击 = (英雄ATK × 场内星级 + 装备ATK) × (1 + 百分比) × (1 + 遗物攻击加成)
        attack = (heroStats.atk * starMult + equipAtk) * (1 + atkPctBonus) * (1 + relicAtkPct),
        range = typeDef.baseRange + starRange + levelRange + rangeBonus,
        speed = typeDef.baseSpeed / starSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + relicSpdPct),
        cooldown = 0,
        target = nil,
        animTime = 0,
        spawnTime = 0,
        -- 局外信息（用于显示和技能）
        heroLevel = heroLevel,
        heroStar = heroStar,
        heroAwakening = heroAwakening,
        -- 战斗子属性（来自英雄等级成长 + 装备/符文 + 遗物被动）
        armorPen = (heroStats.armorPen or 0) + (equipBonus.armorPen or 0),
        critRate = (heroStats.critRate or 0) + (equipBonus.critRate or 0),
        critDmg = (heroStats.critDmg or 0) + (equipBonus.critDmg or 0) + relicCritDmgPct,
        dmgBonus = (heroStats.dmgBonus or 0) + (equipBonus.dmgBonus or 0),
        elemDmgBonus = heroStats.elemDmgBonus or {},
        -- 技能
        skills = {},
        skillTimers = {},
    }

    -- 装备元素伤害加成
    local heroElem = Config.HERO_ELEMENT[heroId]
    if heroElem and equipBonus.elemDmg and equipBonus.elemDmg > 0 then
        tower.elemDmgBonus[heroElem] = (tower.elemDmgBonus[heroElem] or 0) + equipBonus.elemDmg
    end

    -- 符文特殊词条
    tower.runeBonus = {
        chain      = equipBonus.chain or 0,
        slow_amp   = equipBonus.slow_amp or 0,
        dot_amp    = equipBonus.dot_amp or 0,
        cdr        = equipBonus.cdr or 0,
        killReset  = equipBonus.killReset or 0,
        vulnMark   = equipBonus.vulnMark or 0,
        elemMastery= equipBonus.elemMastery or 0,
        luckyDrop  = equipBonus.luckyDrop or 0,
    }
    local rok, RuneData = pcall(require, "Game.RuneData")
    tower.runeSetEffects = rok and RuneData.GetSetEffects(heroId) or {}

    -- 初始化技能
    HeroSkills.InitTowerSkills(tower)

    nextTowerId = nextTowerId + 1
    State.grid[col][row] = tower
    State.towers[#State.towers + 1] = tower
    HeroAnim.InitAnim(tower)   -- 初始化代码动画状态
    local tierInfo = HeroData.GetStarTierInfo(heroId)
    print("[Tower] Created " .. typeDef.name .. " ★" .. star
        .. " Lv." .. heroLevel .. " " .. tierInfo.name .. heroStar .. "星"
        .. " ATK=" .. math.floor(tower.attack)
        .. " at (" .. col .. "," .. row .. ")")
    return tower
end

--- 创建暗影君主（主角塔，使用 LEADER_HERO 定义）
function Tower.CreateLeader(col, row)
    local typeDef = Config.LEADER_HERO
    local star = 1

    local heroId = typeDef.id
    local levelRange = HeroData.GetLevelRangeBonus(heroId)

    local heroInfo = HeroData.Get(heroId)
    local heroLevel = heroInfo and heroInfo.level or 1
    local heroStar = heroInfo and heroInfo.star or 0
    local heroAwakening = heroInfo and heroInfo.awakening or 0
    local heroStats = HeroData.GetHeroStats(heroId)

    -- 获取装备加成（含淬炼+符文）
    local equipBonus = EquipData.GetTotalBonus(heroId)
    local equipAtk = equipBonus.atk or 0
    local atkPctBonus = equipBonus.atk_pct or 0
    local spdPctBonus = equipBonus.spd_pct or 0
    local rangeBonus = equipBonus.range or 0

    -- 遗物被动加成（独立乘区）
    local relicAtkPct, relicSpdPct, relicCritDmgPct = 0, 0, 0
    local RD = GetRelicData()
    if RD then
        local relicBonus = RD.GetPassiveBonus()
        relicAtkPct = relicBonus.atkPct or 0
        relicSpdPct = relicBonus.spdPct or 0
        relicCritDmgPct = relicBonus.critDmgPct or 0
    end

    local tower = {
        id = nextTowerId,
        typeIndex = -1,          -- 非常规塔，用 -1 标记
        typeDef = typeDef,
        star = star,
        col = col,
        row = row,
        isLeader = true,         -- 主角标记
        attack = (heroStats.atk + equipAtk) * (1 + atkPctBonus) * (1 + relicAtkPct),
        range = typeDef.baseRange + levelRange + rangeBonus,
        speed = typeDef.baseSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + relicSpdPct),
        cooldown = 0,
        target = nil,
        animTime = 0,
        spawnTime = 0,
        heroLevel = heroLevel,
        heroStar = heroStar,
        heroAwakening = heroAwakening,
        armorPen = (heroStats.armorPen or 0) + (equipBonus.armorPen or 0),
        critRate = (heroStats.critRate or 0) + (equipBonus.critRate or 0),
        critDmg = (heroStats.critDmg or 0) + (equipBonus.critDmg or 0) + relicCritDmgPct,
        dmgBonus = (heroStats.dmgBonus or 0) + (equipBonus.dmgBonus or 0),
        elemDmgBonus = heroStats.elemDmgBonus or {},
        skills = {},
        skillTimers = {},
        -- 攻击动画状态
        attackAnimTimer = 0,
    }

    -- 装备元素伤害加成
    local heroElem = Config.HERO_ELEMENT[heroId]
    if heroElem and equipBonus.elemDmg and equipBonus.elemDmg > 0 then
        tower.elemDmgBonus[heroElem] = (tower.elemDmgBonus[heroElem] or 0) + equipBonus.elemDmg
    end

    -- 符文特殊词条
    tower.runeBonus = {
        chain      = equipBonus.chain or 0,
        slow_amp   = equipBonus.slow_amp or 0,
        dot_amp    = equipBonus.dot_amp or 0,
        cdr        = equipBonus.cdr or 0,
        killReset  = equipBonus.killReset or 0,
        vulnMark   = equipBonus.vulnMark or 0,
        elemMastery= equipBonus.elemMastery or 0,
        luckyDrop  = equipBonus.luckyDrop or 0,
    }
    local rok, RuneData = pcall(require, "Game.RuneData")
    tower.runeSetEffects = rok and RuneData.GetSetEffects(heroId) or {}

    HeroSkills.InitTowerSkills(tower)

    nextTowerId = nextTowerId + 1
    State.grid[col][row] = tower
    State.towers[#State.towers + 1] = tower
    HeroAnim.InitAnim(tower)   -- 初始化代码动画状态
    print("[Tower] Leader 暗影君主 placed at (" .. col .. "," .. row .. ")"
        .. " Lv." .. heroLevel .. " ATK=" .. math.floor(tower.attack))
    return tower
end

--- 获取当前召唤消耗（球球英雄机制：每次+10）
---@return number
function Tower.GetSummonCost()
    return Config.SUMMON_BASE_COST + State.summonCount * Config.SUMMON_COST_INCREMENT
end

--- 检查是否可以召唤（上阵英雄数>=5 且 暗魂足够 且 有空位）
---@return boolean canSummon
---@return string|nil reason
function Tower.CanSummon()
    local deployedList = HeroData.GetDeployedList()
    if #deployedList < Config.MAX_DEPLOYED then
        return false, "需要上阵" .. Config.MAX_DEPLOYED .. "名英雄"
    end
    local cost = Tower.GetSummonCost()
    if Currency.GetDarkSouls() < cost then
        return false, "暗魂不足"
    end
    local emptyCells = Grid.GetEmptyCells()
    if #emptyCells == 0 then
        return false, "没有空位"
    end
    return true, nil
end

--- 按稀有度权重随机选择已上阵的英雄
---@return number  typeIndex
function Tower.WeightedRandomType()
    local deployedIds = HeroData.GetDeployedList()
    if #deployedIds == 0 then
        return math.random(1, #Config.TOWER_TYPES)
    end

    -- 构建权重池（只从上阵英雄中选）
    local pool = {}   -- { typeIndex, weight }
    local totalWeight = 0
    for _, heroId in ipairs(deployedIds) do
        local idx = Tower.FindTypeIndex(heroId)
        if idx then
            local rarity = Config.TOWER_TYPES[idx].rarity or "R"
            local weight = Config.RARITY_SUMMON_WEIGHT[rarity] or 40
            pool[#pool + 1] = { typeIndex = idx, weight = weight }
            totalWeight = totalWeight + weight
        end
    end

    if totalWeight == 0 then
        return math.random(1, #Config.TOWER_TYPES)
    end

    -- 加权随机
    local roll = math.random() * totalWeight
    local acc = 0
    for _, entry in ipairs(pool) do
        acc = acc + entry.weight
        if roll <= acc then
            return entry.typeIndex
        end
    end
    return pool[#pool].typeIndex
end

--- 随机召唤一个1星塔到空位（只从上阵英雄中选，消耗递增）
function Tower.Summon()
    local canSummon, reason = Tower.CanSummon()
    if not canSummon then
        print("[Tower] Cannot summon: " .. (reason or "unknown"))
        return nil, reason
    end

    local cost = Tower.GetSummonCost()
    Currency.Spend("dark_soul", cost)
    State.summonCount = State.summonCount + 1

    local emptyCells = Grid.GetEmptyCells()
    local cell = emptyCells[math.random(1, #emptyCells)]
    local typeIndex = Tower.WeightedRandomType()
    local tower = Tower.Create(typeIndex, 1, cell.col, cell.row)
    if tower then
        tower.spawnTime = 0.5
        State.summonFlash = 0.3
        local AudioManager = require("Game.AudioManager")
        AudioManager.PlayDeploy()
        -- 开服好礼任务追踪
        local ok, LGD = pcall(require, "Game.LaunchGiftData")
        if ok and LGD then LGD.AddProgress("summon", 1) end
        -- 每日任务追踪
        local ok2, DTD = pcall(require, "Game.DailyTaskData")
        if ok2 and DTD then DTD.AddProgress("summon", 1) end

    end
    print("[Tower] Summon #" .. State.summonCount .. " cost=" .. cost .. " next=" .. Tower.GetSummonCost())
    return tower
end

-- ============================================================================
-- Debuff 系统：敌人词缀周期性削弱英雄塔属性
-- ============================================================================

--- 给塔施加一个减益效果
---@param tower table 塔实例
---@param debuffId string 词缀ID（如 "atk_down"）
---@param stat string 目标属性名（"attack","speed","critRate"等）
---@param value number 削弱幅度（百分比或固定值）
---@param mode string "pct"=百分比乘算 | "flat"=固定值减算
---@param duration number 持续秒数
function Tower.ApplyDebuff(tower, debuffId, stat, value, mode, duration)
    if not tower.debuffs then tower.debuffs = {} end
    -- 同ID覆盖（刷新持续时间，取更强值）
    for _, db in ipairs(tower.debuffs) do
        if db.id == debuffId then
            db.value = math.max(db.value, value)
            db.remain = duration
            return
        end
    end
    tower.debuffs[#tower.debuffs + 1] = {
        id = debuffId, stat = stat, value = value, mode = mode, remain = duration,
    }
end

--- 更新塔身上所有 debuff 计时（在 Tower.Update 中每帧调用）
local function TickDebuffs(tower, dt)
    if not tower.debuffs then return end
    local i = 1
    while i <= #tower.debuffs do
        tower.debuffs[i].remain = tower.debuffs[i].remain - dt
        if tower.debuffs[i].remain <= 0 then
            table.remove(tower.debuffs, i)
        else
            i = i + 1
        end
    end
end

--- 获取被 debuff 修正后的有效属性值
--- 调用方：Combat 计算伤害时使用 Tower.GetEffective*(tower) 而非直接读 tower.attack
---@param tower table
---@param statName string  属性名
---@param baseValue number 原始值
---@return number 修正后的值
function Tower.GetEffectiveStat(tower, statName, baseValue)
    if not tower.debuffs then return baseValue end
    local result = baseValue
    for _, db in ipairs(tower.debuffs) do
        if db.stat == statName then
            if db.mode == "pct" then
                result = result * (1 - db.value)   -- 百分比削弱
            else
                result = result - db.value          -- 固定值削弱
            end
        end
    end
    return math.max(0, result)
end

--- 便捷：获取有效攻击力（含 debuff + 遗物战斗增伤）
function Tower.GetEffectiveAttack(tower)
    local base = Tower.GetEffectiveStat(tower, "attack", tower.attack)
    -- 遗物施法后增伤 buff（独立乘区）
    local RE = GetRelicEffects()
    if RE then
        local dmgBuff = RE.GetDamageBuff()
        if dmgBuff > 0 then
            base = base * (1 + dmgBuff)
        end
    end
    return base
end

--- 便捷：获取有效攻速（值越大越慢，debuff 增加间隔，遗物增速减少间隔）
function Tower.GetEffectiveSpeed(tower)
    local slowMult = 1.0
    if tower.debuffs then
        for _, db in ipairs(tower.debuffs) do
            if db.stat == "speed" then
                slowMult = slowMult + db.value  -- speed debuff 增加攻击间隔
            end
        end
    end
    local result = tower.speed * slowMult
    -- 遗物施法后增速 buff（缩短攻击间隔）
    local RE = GetRelicEffects()
    if RE then
        local spdBuff = RE.GetSpeedBuff()
        if spdBuff > 0 then
            result = result / (1 + spdBuff)
        end
    end
    return result
end

--- 便捷：获取有效暴击率
function Tower.GetEffectiveCritRate(tower)
    return Tower.GetEffectiveStat(tower, "critRate", tower.critRate or 0)
end

--- 便捷：获取有效暴击伤害
function Tower.GetEffectiveCritDmg(tower)
    return Tower.GetEffectiveStat(tower, "critDmg", tower.critDmg or 0)
end

--- 便捷：获取有效穿甲
function Tower.GetEffectiveArmorPen(tower)
    return Tower.GetEffectiveStat(tower, "armorPen", tower.armorPen or 0)
end

--- 便捷：获取有效伤害加成
function Tower.GetEffectiveDmgBonus(tower)
    return Tower.GetEffectiveStat(tower, "dmgBonus", tower.dmgBonus or 0)
end

--- 检查塔是否有指定 debuff
function Tower.HasDebuff(tower, debuffId)
    if not tower.debuffs then return false end
    for _, db in ipairs(tower.debuffs) do
        if db.id == debuffId then return true end
    end
    return false
end

--- 清除塔身上所有 debuff（波次开始时调用）
--- persistent debuff（remain == math.huge）不会被清除，仅在 BOSS 死亡时由技能系统显式清理
function Tower.ClearDebuffs(tower)
    if not tower.debuffs then return end
    local i = 1
    while i <= #tower.debuffs do
        if tower.debuffs[i].remain == math.huge then
            i = i + 1  -- 跳过持久 debuff
        else
            table.remove(tower.debuffs, i)
        end
    end
    if #tower.debuffs == 0 then tower.debuffs = nil end
end

--- 清除所有塔的 debuff（保留 persistent）
function Tower.ClearAllDebuffs()
    for _, tower in ipairs(State.towers) do
        Tower.ClearDebuffs(tower)
    end
end

--- 强制清除所有 debuff（包括 persistent，BOSS 死亡时使用）
function Tower.ForceClearAllDebuffs()
    for _, tower in ipairs(State.towers) do
        tower.debuffs = nil
    end
end

--- 重新计算塔的战斗属性（星级变化后调用）
function Tower.RecalcStats(tower)
    local typeDef = tower.typeDef
    local star = tower.star
    local heroId = typeDef.id

    local starMult = Config.STAR_MULTIPLIER[star] or 1.0
    local starRange = Config.STAR_RANGE_BONUS[star] or 0
    local starSpeed = Config.STAR_SPEED_MULT[star] or 1.0

    local levelRange = HeroData.GetLevelRangeBonus(heroId)
    local heroStats = HeroData.GetHeroStats(heroId)
    local equipBonus = EquipData.GetTotalBonus(heroId)
    local equipAtk = equipBonus.atk or 0
    local atkPctBonus = equipBonus.atk_pct or 0
    local spdPctBonus = equipBonus.spd_pct or 0
    local rangeBonus = equipBonus.range or 0

    tower.attack = (heroStats.atk * starMult + equipAtk) * (1 + atkPctBonus)
    tower.range = typeDef.baseRange + starRange + levelRange + rangeBonus
    tower.speed = typeDef.baseSpeed / starSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus)

    print("[Tower] RecalcStats " .. typeDef.name .. " ★" .. star .. " ATK=" .. math.floor(tower.attack))
end

--- 移除一个塔
function Tower.Remove(tower)
    State.grid[tower.col][tower.row] = nil
    for i = #State.towers, 1, -1 do
        if State.towers[i].id == tower.id then
            table.remove(State.towers, i)
            State.MarkDirty()
            break
        end
    end
end

--- 查找可以合成的配对塔（相同类型+星级，且数量足够）
function Tower.FindMergePartner(tower)
    for _, t in ipairs(State.towers) do
        if t.id ~= tower.id
            and t.typeIndex == tower.typeIndex
            and t.star == tower.star
            and t.star < Config.MAX_STAR then
            return t
        end
    end
    return nil
end

--- 检查两个塔是否可以合成（同类型+同星级）
---@param tower table  被拖拽的塔
---@param targetTower table  目标塔
---@return boolean
function Tower.CanMerge(tower, targetTower)
    -- 暗影君主不参与合成
    if tower.isLeader or targetTower.isLeader then return false end
    if tower.typeIndex ~= targetTower.typeIndex then return false end
    if tower.star ~= targetTower.star then return false end
    if tower.star >= Config.MAX_STAR then return false end

    return true
end

--- 合成塔（结果随机变为一个上阵英雄）
function Tower.Merge(tower1, tower2)
    if not Tower.CanMerge(tower1, tower2) then
        print("[Tower] Cannot merge: conditions not met")
        return nil
    end

    local oldStar = tower1.star
    local newStar = oldStar + 1
    local newTypeIndex = Tower.WeightedRandomType()  -- 随机变为上阵英雄
    local col, row = tower2.col, tower2.row

    -- 记录闪光位置
    State.mergeFlashPos = { col = col, row = row }
    State.mergeFlash = 0.5

    -- 移除参与合成的两个塔
    Tower.Remove(tower1)
    Tower.Remove(tower2)

    -- 创建新塔
    local newTower = Tower.Create(newTypeIndex, newStar, col, row)
    if newTower then
        newTower.spawnTime = 0.6
    end

    local AudioManager = require("Game.AudioManager")
    AudioManager.PlayMerge()
    -- 开服好礼任务追踪
    local ok, LGD = pcall(require, "Game.LaunchGiftData")
    if ok and LGD then LGD.AddProgress("merge", 1) end
    -- 每日任务追踪
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("merge", 1) end
    print("[Tower] Merged into " .. Config.TOWER_TYPES[newTypeIndex].name .. " ★" .. newStar)
    return newTower
end

--- 选中/取消选中塔
function Tower.Select(tower)
    if State.selectedTower and State.selectedTower.id == tower.id then
        State.selectedTower = nil
        print("[Tower] Deselected")
        return
    end

    if State.selectedTower then
        local sel = State.selectedTower
        if Tower.CanMerge(sel, tower) then
            Tower.Merge(sel, tower)
            State.selectedTower = nil
            return
        end
    end

    State.selectedTower = tower
    print("[Tower] Selected " .. tower.typeDef.name .. " ★" .. tower.star)
end

--- 将塔移动到新位置（空格子）
function Tower.MoveTo(tower, newCol, newRow)
    State.grid[tower.col][tower.row] = nil
    tower.col = newCol
    tower.row = newRow
    State.grid[newCol][newRow] = tower
    print("[Tower] Moved " .. tower.typeDef.name .. " to (" .. newCol .. "," .. newRow .. ")")
end

--- 交换两个塔的位置
function Tower.Swap(tower1, tower2)
    local c1, r1 = tower1.col, tower1.row
    local c2, r2 = tower2.col, tower2.row
    State.grid[c1][r1] = tower2
    State.grid[c2][r2] = tower1
    tower1.col, tower1.row = c2, r2
    tower2.col, tower2.row = c1, r1
    print("[Tower] Swapped " .. tower1.typeDef.name .. " <-> " .. tower2.typeDef.name)
end

--- 处理拖拽释放：移动、交换或合成
function Tower.HandleDrop(draggedTower, targetCol, targetRow)
    if targetCol == State.dragOriginCol and targetRow == State.dragOriginRow then
        return
    end
    if targetCol < 1 or targetCol > Config.GRID_COLS
        or targetRow < 1 or targetRow > Config.GRID_ROWS then
        return
    end
    if Grid.IsPathCell(targetCol, targetRow) then
        return
    end

    local targetTower = State.grid[targetCol][targetRow]
    if targetTower then
        if Tower.CanMerge(draggedTower, targetTower) then
            Tower.Merge(draggedTower, targetTower)
        else
            Tower.Swap(draggedTower, targetTower)
        end
    else
        Tower.MoveTo(draggedTower, targetCol, targetRow)
    end
end

--- 刷新所有在场塔的属性（从英雄页返回战斗页时调用）
function Tower.RefreshAllStats()
    for _, tower in ipairs(State.towers) do
        local typeDef = tower.typeDef
        local heroId = typeDef.id
        local starMult = Config.STAR_MULTIPLIER[tower.star] or 1.0
        local starRange = Config.STAR_RANGE_BONUS[tower.star] or 0
        local starSpeed = Config.STAR_SPEED_MULT[tower.star] or 1.0
        local levelRange = HeroData.GetLevelRangeBonus(heroId)

        -- 获取英雄完整属性（ATK 已含等级/进阶/升星）
        local heroStats = HeroData.GetHeroStats(heroId)

        -- 获取装备加成（含淬炼+符文）
        local equipBonus = EquipData.GetTotalBonus(heroId)
        local equipAtk = equipBonus.atk or 0
        local atkPctBonus = equipBonus.atk_pct or 0  -- 符文百分比攻击力
        local spdPctBonus = equipBonus.spd_pct or 0  -- 符文百分比攻速
        local rangeBonus = equipBonus.range or 0      -- 符文攻击范围

        -- 神裔降临加成
        local divineAtkPct = DivineBlessDB.GetBuffValue("atk_pct")
        local divineSpdPct = DivineBlessDB.GetBuffValue("spd_pct")

        -- 遗物被动加成（独立乘区）
        local relicAtkPct, relicSpdPct, relicCritDmgPct = 0, 0, 0
        local RD = GetRelicData()
        if RD then
            local relicBonus = RD.GetPassiveBonus()
            relicAtkPct = relicBonus.atkPct or 0
            relicSpdPct = relicBonus.spdPct or 0
            relicCritDmgPct = relicBonus.critDmgPct or 0
        end

        if tower.isLeader then
            tower.attack = (heroStats.atk + equipAtk) * (1 + atkPctBonus + divineAtkPct) * (1 + relicAtkPct)
            tower.range = typeDef.baseRange + levelRange + rangeBonus
            tower.speed = typeDef.baseSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + divineSpdPct + relicSpdPct)
        else
            tower.attack = (heroStats.atk * starMult + equipAtk) * (1 + atkPctBonus + divineAtkPct) * (1 + relicAtkPct)
            tower.range = typeDef.baseRange + starRange + levelRange + rangeBonus
            tower.speed = typeDef.baseSpeed / starSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + divineSpdPct + relicSpdPct)
        end

        -- 更新英雄信息
        local heroInfo = HeroData.Get(heroId)
        tower.heroLevel = heroInfo and heroInfo.level or 1
        tower.heroStar = heroInfo and heroInfo.star or 0
        tower.heroAwakening = heroInfo and heroInfo.awakening or 0

        tower.armorPen = (heroStats.armorPen or 0) + (equipBonus.armorPen or 0)
        tower.critRate = (heroStats.critRate or 0) + (equipBonus.critRate or 0) + DivineBlessDB.GetBuffValue("crit_pct")
        tower.critDmg = (heroStats.critDmg or 0) + (equipBonus.critDmg or 0) + relicCritDmgPct
        tower.dmgBonus = (heroStats.dmgBonus or 0) + (equipBonus.dmgBonus or 0)
        tower.elemDmgBonus = heroStats.elemDmgBonus or {}
        -- 装备元素伤害加成：加到英雄对应元素上
        local heroElem = Config.HERO_ELEMENT[heroId]
        if heroElem and equipBonus.elemDmg and equipBonus.elemDmg > 0 then
            tower.elemDmgBonus[heroElem] = (tower.elemDmgBonus[heroElem] or 0) + equipBonus.elemDmg
        end

        -- 符文特殊词条（供 Combat/HeroSkills 读取）
        tower.runeBonus = {
            chain      = equipBonus.chain or 0,       -- 连锁概率
            slow_amp   = equipBonus.slow_amp or 0,    -- 减速强化
            dot_amp    = equipBonus.dot_amp or 0,     -- DOT强化
            cdr        = equipBonus.cdr or 0,         -- 技能冷却缩减
            killReset  = equipBonus.killReset or 0,   -- 击杀回复
            vulnMark   = equipBonus.vulnMark or 0,    -- 易伤标记
            elemMastery= equipBonus.elemMastery or 0, -- 元素精通
            luckyDrop  = equipBonus.luckyDrop or 0,   -- 幸运掉落
        }
        -- 符文套装特殊效果（3件套触发效果）
        local rok, RuneData = pcall(require, "Game.RuneData")
        tower.runeSetEffects = rok and RuneData.GetSetEffects(heroId) or {}

        -- 刷新技能
        HeroSkills.InitTowerSkills(tower)
    end
    print("[Tower] RefreshAllStats: " .. #State.towers .. " towers updated")
end

--- 更新所有塔（冷却、动画、技能CD）
function Tower.Update(dt)
    for _, tower in ipairs(State.towers) do
        tower.animTime = tower.animTime + dt
        if tower.spawnTime > 0 then
            tower.spawnTime = tower.spawnTime - dt
        end
        if tower.cooldown > 0 then
            tower.cooldown = tower.cooldown - dt
        end
        -- 沉默计时器递减（death_silence / disable 被动施加）
        if tower.silenceTimer and tower.silenceTimer > 0 then
            tower.silenceTimer = tower.silenceTimer - dt
        end
        -- 灼烧减速计时器递减（scorch 被动施加）
        if tower.scorchTimer and tower.scorchTimer > 0 then
            tower.scorchTimer = tower.scorchTimer - dt
        end
        -- 攻击动画衰减（所有有精灵图的塔都需要）
        if tower.attackAnimTimer and tower.attackAnimTimer > 0 then
            tower.attackAnimTimer = tower.attackAnimTimer - dt
        end
        -- 更新主动技能冷却
        HeroSkills.UpdateActive(tower, dt)
        -- 更新 debuff 计时
        TickDebuffs(tower, dt)
    end
    -- 更新英雄代码动画（呼吸/攻击压缩弹出）
    HeroAnim.Update(dt, State.towers)
end

-- ============================================================================
-- 自动布阵：根据攻击范围和敌人位置重排塔的位置
-- 短程塔 → 靠近路径/敌人；远程塔 → 后排
-- ============================================================================
function Tower.AutoDeploy(gridOffsetX, gridOffsetY)
    local towers = State.towers
    if #towers < 2 then return false end

    -- 收集 BOSS 技能危险区域（毁灭践踏 3x3 / 终焉毁灭 NxN）
    local dangerZones = {}  -- { {col, row, radius} }
    local bossSkill = State.hatredBossSkill
    if bossSkill then
        if bossSkill.starCrush then
            dangerZones[#dangerZones + 1] = {
                col = bossSkill.starCrush.centerCol,
                row = bossSkill.starCrush.centerRow,
                radius = 1,  -- 3x3 → 切比雪夫半径 1
            }
        end
        if bossSkill.destruction then
            dangerZones[#dangerZones + 1] = {
                col = bossSkill.destruction.centerCol,
                row = bossSkill.destruction.centerRow,
                radius = bossSkill.destruction.radius or 1,
            }
        end
    end

    --- 判断格子是否在危险区内
    local function IsInDanger(c, r)
        for _, zone in ipairs(dangerZones) do
            if math.max(math.abs(c - zone.col), math.abs(r - zone.row)) <= zone.radius then
                return true
            end
        end
        return false
    end

    -- 收集所有可放置格子，计算评分
    local cells = {}
    for c = 1, Config.GRID_COLS do
        for r = 1, Config.GRID_ROWS do
            if not Grid.IsPathCell(c, r) then
                local sx, sy = Grid.CellToScreen(c, r, gridOffsetX, gridOffsetY)
                -- 到最近路径格的距离
                local minDist2 = math.huge
                for _, pc in ipairs(Config.PATH_CELLS) do
                    local px, py = Grid.CellToScreen(pc[1], pc[2], gridOffsetX, gridOffsetY)
                    local d = (sx - px) ^ 2 + (sy - py) ^ 2
                    if d < minDist2 then minDist2 = d end
                end
                -- 附近敌人密度（使用平滑衰减，避免只有最近格子拿到极高分）
                local enemyScore = 0
                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        local d = math.sqrt((sx - e.x) ^ 2 + (sy - e.y) ^ 2)
                        if d < 400 then
                            enemyScore = enemyScore + (400 - d) / 400
                        end
                    end
                end
                cells[#cells + 1] = {
                    col = c, row = r,
                    pathDist = math.sqrt(minDist2),
                    enemyScore = enemyScore,
                    danger = IsInDanger(c, r),
                }
            end
        end
    end

    -- 对 enemyScore 做归一化，避免敌人集中时单个格子分数爆炸
    local maxES = 0
    for _, cell in ipairs(cells) do
        if cell.enemyScore > maxES then maxES = cell.enemyScore end
    end

    -- 综合评分：靠近路径 + 靠近敌人（归一化后的敌人分数，上限与路径分同量级）
    for _, cell in ipairs(cells) do
        local normEnemy = (maxES > 0) and (cell.enemyScore / maxES * 500) or 0
        cell.score = 1000 / (cell.pathDist + 1) + normEnemy
    end

    -- 将格子分为安全区和危险区，各自按评分降序
    local safeCells = {}
    local dangerCells = {}
    for _, cell in ipairs(cells) do
        if cell.danger then
            dangerCells[#dangerCells + 1] = cell
        else
            safeCells[#safeCells + 1] = cell
        end
    end
    table.sort(safeCells, function(a, b) return a.score > b.score end)
    table.sort(dangerCells, function(a, b) return a.score > b.score end)

    -- 有危险区时：按攻击力降序（高攻优先安全区）；无危险区：按范围升序（短程优先好位）
    local sorted = {}
    for _, t in ipairs(towers) do sorted[#sorted + 1] = t end
    if #dangerZones > 0 then
        -- 高攻英雄优先分到安全格子
        table.sort(sorted, function(a, b) return a.attack > b.attack end)
    else
        table.sort(sorted, function(a, b) return a.range < b.range end)
    end

    -- 分配：优先安全格子，安全格子用完再用危险格子
    local finalCells = {}
    local si, di = 1, 1
    for _ = 1, #sorted do
        if si <= #safeCells then
            finalCells[#finalCells + 1] = safeCells[si]
            si = si + 1
        elseif di <= #dangerCells then
            finalCells[#finalCells + 1] = dangerCells[di]
            di = di + 1
        end
    end

    -- 检查是否有任何塔需要移动
    local anyChange = false
    for i, tower in ipairs(sorted) do
        if i <= #finalCells then
            if tower.col ~= finalCells[i].col or tower.row ~= finalCells[i].row then
                anyChange = true
                break
            end
        end
    end
    if not anyChange then return false end

    -- 清除所有塔的格子占据
    for _, t in ipairs(sorted) do
        State.grid[t.col][t.row] = nil
    end

    -- 分配：第 i 个塔 → 第 i 个格子（高攻→安全，低攻→危险/剩余）
    for i, tower in ipairs(sorted) do
        if i <= #finalCells then
            tower.col = finalCells[i].col
            tower.row = finalCells[i].row
            State.grid[finalCells[i].col][finalCells[i].row] = tower
        end
    end

    return true
end

return Tower
