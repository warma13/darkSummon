--- OfflinePush.lua
--- 离线自动推关模块（v2: 模拟战斗）
--- 为每个上阵英雄构建虚拟塔，模拟实际攻击 Boss 的战斗过程
--- 普通波保留简化 EHP 计算，Boss 波走完整伤害模拟

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local DungeonScaling = require("Game.DungeonScaling")
local F = require("Game.FormulaLib")

local OP = {}

-- ============================================================================
-- 常量
-- ============================================================================
local BOSS_TIMER        = 300     -- BOSS 限时 (秒)
local WAVES_PER_STAGE   = Config.WAVES_PER_STAGE or 10

-- 场内合并星级：离线模拟不跑实际合并，取"理想平均星级"
local IDEAL_FIELD_STAR   = 3
-- 每种随从英雄的场内塔数
local TOWERS_PER_HERO    = 8

-- 模拟参数
local SIM_DT             = 0.1    -- 模拟步进（秒）
local WAVE_INTERVAL      = 3.0    -- 波次间隔（秒）

-- ============================================================================
-- 虚拟塔构建：复用 Tower.Create 的属性计算方式，无视觉/网格依赖
-- ============================================================================

--- 构建单个英雄的虚拟塔（轻量结构体）
---@param heroId string
---@param fieldStar number 场内星级
---@return table|nil virtualTower { attack, speed, armorPen, critRate, critDmg, dmgBonus, physDmgBonus, magicDmgBonus, magicPen, runeBonus, typeDef, hstate }
local function BuildVirtualTower(heroId, fieldStar)
    local heroStats = HeroData.GetHeroStats(heroId)
    if not heroStats or heroStats.atk <= 0 then return nil end

    local typeDef = nil
    -- 主角
    if heroId == Config.LEADER_HERO.id then
        typeDef = Config.LEADER_HERO
    else
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then typeDef = td; break end
        end
    end
    if not typeDef then return nil end

    local starMult = (heroId == Config.LEADER_HERO.id) and 1.0 or (Config.STAR_MULTIPLIER[fieldStar] or 1.0)
    local starSpeed = (heroId == Config.LEADER_HERO.id) and 1.0 or (Config.STAR_SPEED_MULT[fieldStar] or 1.0)

    -- 装备加成
    local ok_eq, EquipData = pcall(require, "Game.EquipData")
    local equipBonus = (ok_eq and EquipData and EquipData.GetTotalBonus) and EquipData.GetTotalBonus(heroId) or {}
    local equipAtk = equipBonus.atk or 0
    local atkPctBonus = equipBonus.atk_pct or 0
    local spdPctBonus = equipBonus.spd_pct or 0

    -- 遗物加成
    local relicAtkPct, relicSpdPct, relicCritDmgPct = 0, 0, 0
    local rok, RD = pcall(require, "Game.RelicData")
    if rok and RD and RD.GetPassiveBonus then
        local rb = RD.GetPassiveBonus()
        relicAtkPct = rb.atkPct or 0
        relicSpdPct = rb.spdPct or 0
        relicCritDmgPct = rb.critDmgPct or 0
    end

    -- 图鉴加成
    local cok, CodexData = pcall(require, "Game.CodexData")
    local codexAtkPct = (cok and CodexData and CodexData.GetTotalBonus) and CodexData.GetTotalBonus() or 0

    -- 神裔降临加成（与 Tower.BuildTowerStats 一致）
    local dok, DivineBlessDB = pcall(require, "Game.DivineBlessData")
    local divineAtkPct = (dok and DivineBlessDB and DivineBlessDB.GetBuffValue) and DivineBlessDB.GetBuffValue("atk_pct") or 0
    local divineSpdPct = (dok and DivineBlessDB and DivineBlessDB.GetBuffValue) and DivineBlessDB.GetBuffValue("spd_pct") or 0
    local divineCritPct = (dok and DivineBlessDB and DivineBlessDB.GetBuffValue) and DivineBlessDB.GetBuffValue("crit_pct") or 0

    -- 符文加成
    local ok_rune, RuneData = pcall(require, "Game.RuneData")
    local runeBonus = (ok_rune and RuneData and RuneData.GetCombatBonus) and RuneData.GetCombatBonus(heroId) or {}

    -- 最终攻击 = (英雄ATK × 场内星级 + 装备ATK) × (1 + 百分比 + 神赐百分比) × (1 + 遗物) × (1 + 图鉴)
    local finalAtk = (heroStats.atk * starMult + equipAtk) * (1 + atkPctBonus + divineAtkPct) * (1 + relicAtkPct) * (1 + codexAtkPct)
    -- 攻速（含神裔加速）
    local speed = typeDef.baseSpeed / starSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + divineSpdPct + relicSpdPct)
    if speed <= 0 then speed = 0.1 end

    -- 战斗子属性
    local armorPen = (heroStats.armorPen or 0) + (equipBonus.armorPen or 0) + (runeBonus.armorPen or 0)
    local critRate = math.min(1.0, (heroStats.critRate or 0) + (equipBonus.critRate or 0) + (runeBonus.critRate or 0) + divineCritPct)
    local critDmg = (heroStats.critDmg or 0) + (equipBonus.critDmg or 0) + relicCritDmgPct + (runeBonus.critDmg or 0)
    local dmgBonus = (heroStats.dmgBonus or 0) + (equipBonus.dmgBonus or 0) + (runeBonus.dmgBonus or 0)
    local physDmgBonus = (equipBonus.physDmg or 0) + (runeBonus.physDmgBonus or 0)
    local magicDmgBonus = (equipBonus.magicDmg or 0) + (runeBonus.magicDmgBonus or 0)
    local magicPen = equipBonus.magicPen or 0

    return {
        attack = finalAtk,
        speed = speed,
        cooldown = 0,
        armorPen = armorPen,
        critRate = critRate,
        critDmg = critDmg,
        dmgBonus = dmgBonus,
        physDmgBonus = physDmgBonus,
        magicDmgBonus = magicDmgBonus,
        magicPen = magicPen,
        typeDef = typeDef,
        heroId = heroId,
        -- 符文特殊词条
        runeBonus = {
            elemMastery = runeBonus.elemMastery or 0,
            vulnMark = runeBonus.vulnMark or 0,
            chain = runeBonus.chain or 0,
        },
        -- 简化：无 hstate（英雄模块额外效果忽略）
        hstate = nil,
    }
end

--- 构建全阵容的虚拟塔列表
---@return table[] virtualTowers
local function BuildSquadTowers()
    local towers = {}

    -- 主角（1 个塔）
    local leaderTower = BuildVirtualTower(Config.LEADER_HERO.id, 1)
    if leaderTower then
        towers[#towers + 1] = leaderTower
    end

    -- 随从英雄（每种 TOWERS_PER_HERO 个）
    local deployed = HeroData.deployed or {}
    for _, heroId in ipairs(deployed) do
        for i = 1, TOWERS_PER_HERO do
            local t = BuildVirtualTower(heroId, IDEAL_FIELD_STAR)
            if t then
                -- 同型塔共享属性，但独立冷却（错开攻击节奏）
                t.cooldown = (i - 1) * (t.speed / TOWERS_PER_HERO)
                towers[#towers + 1] = t
            end
        end
    end

    return towers
end

-- ============================================================================
-- Boss 构建：使用实际 Config 数据 + DungeonScaling 缩放
-- ============================================================================

--- 构建指定关卡的 Boss 数据（用于模拟）
---@param stageNum number
---@return table boss { hp, maxHP, def, res, scaling }
local function BuildStageBoss(stageNum)
    local bossDef = Config.BuildBossDef(stageNum)
    local hpScale = DungeonScaling.CalcHPScaleWithWave(stageNum, WAVES_PER_STAGE)
    local defScale = DungeonScaling.CalcDEFScale(stageNum)

    -- 关卡等级缩放（ENEMY_SCALING 各乘区减免）
    local scaling = {}
    if Config.ENEMY_SCALING then
        scaling.critDmgReduce   = F.Piecewise4(Config.ENEMY_SCALING.critDmgReduce, stageNum)
        scaling.dmgBonusReduce  = F.Piecewise4(Config.ENEMY_SCALING.dmgBonusReduce, stageNum)
        scaling.typeDmgReduce   = F.Piecewise4(Config.ENEMY_SCALING.typeDmgReduce, stageNum)
        scaling.armorPenResist  = F.Piecewise4(Config.ENEMY_SCALING.armorPenResist, stageNum)
    else
        scaling.critDmgReduce  = 0
        scaling.dmgBonusReduce = 0
        scaling.typeDmgReduce  = 0
        scaling.armorPenResist = 0
    end

    -- 主题防御配置
    local theme = Config.GetTheme(stageNum)
    local profile = Config.THEME_DEFENSE_PROFILE[theme.id] or { defMult = 1.0, resMult = 1.0 }

    local bossHP = bossDef.baseHP * hpScale
    local bossDEF = (bossDef.baseDEF or 3000) * (profile.defMult or 1.0) * defScale
    local bossRES = bossDef.baseRES or 30

    return {
        hp = bossHP,
        maxHP = bossHP,
        def = bossDEF,
        res = bossRES,
        passive = bossDef.passive,
        themeId = theme.id,
        -- ENEMY_SCALING 减免
        critDmgReduce = scaling.critDmgReduce,
        dmgBonusReduce = scaling.dmgBonusReduce,
        typeDmgReduce = scaling.typeDmgReduce,
        armorPenResist = scaling.armorPenResist,
        -- 破甲叠层（模拟中不应用，简化处理）
        armorBreakStacks = nil,
        armorBreakValue = nil,
        -- 寒意叠层（简化：假设冰系英雄能维持 5 层）
        chillStacks = 0,
        isBoss = true,
    }
end

-- ============================================================================
-- 伤害计算：复刻 Combat.CalcFinalDamage 的乘区系统（无视觉效果）
-- ============================================================================

--- 模拟单次攻击的伤害（复刻 Combat.CalcFinalDamage 逻辑）
---@param tower table 虚拟塔
---@param boss table Boss 数据
---@return number finalDamage
local function SimCalcDamage(tower, boss)
    local damage = tower.attack
    local dmgType = Config.HERO_DAMAGE_TYPE[tower.heroId] or "physical"

    local final = damage

    -- [防御乘区]
    if dmgType == "physical" then
        local enemyDEF = boss.def or 0
        local armorPen = tower.armorPen or 0
        local penResist = boss.armorPenResist or 0
        if penResist > 0 then
            armorPen = armorPen * (1 - penResist)
        end
        if armorPen > 0 then
            enemyDEF = enemyDEF * (1 - math.min(armorPen, 0.90))
        end
        enemyDEF = math.max(0, enemyDEF)
        local defMult = F.Diminishing(enemyDEF, damage)
        final = final * defMult
    elseif dmgType == "magical" then
        local res = boss.res or 0
        local mPen = tower.magicPen or 0
        if mPen > 0 then
            res = res - mPen * 100
        end
        res = math.max(0, math.min(100, res))
        final = final * (1.0 - res / 100)
    end
    -- pure: 不减伤

    -- [暴击乘区]
    local critRate = tower.critRate or 0
    if critRate > 0 and math.random() < critRate then
        local critDmg = tower.critDmg or 0
        local critReduce = boss.critDmgReduce or 0
        if critReduce > 0 then
            critDmg = critDmg * (1 - critReduce)
        end
        local critMult = (Config.BASE_CRIT_MULT or 1.5) + critDmg
        final = final * critMult
    end

    -- [伤害加成乘区]
    do
        local db = tower.dmgBonus or 0
        local dbReduce = boss.dmgBonusReduce or 0
        if dbReduce > 0 then
            db = db * (1 - dbReduce)
        end
        if db > 0 then
            final = final * (1.0 + db)
        end
    end

    -- [类型伤害乘区]
    do
        local typeDmgBonus = 0
        if dmgType == "physical" then
            typeDmgBonus = tower.physDmgBonus or 0
        elseif dmgType == "magical" then
            typeDmgBonus = tower.magicDmgBonus or 0
        end
        if tower.runeBonus and tower.runeBonus.elemMastery and tower.runeBonus.elemMastery > 0 then
            typeDmgBonus = typeDmgBonus + tower.runeBonus.elemMastery
        end
        local typeReduce = boss.typeDmgReduce or 0
        if typeReduce > 0 then
            typeDmgBonus = typeDmgBonus * (1 - typeReduce)
        end
        if typeDmgBonus > 0 then
            final = final * (1.0 + typeDmgBonus)
        end
    end

    -- [寒意增伤乘区]
    if boss.chillStacks and boss.chillStacks >= 5 then
        local chillAmp = tower.typeDef.chillDmgAmpAtMax or 0.50
        final = final * (1.0 + chillAmp)
    end

    -- [易伤标记乘区]
    if tower.runeBonus and tower.runeBonus.vulnMark and tower.runeBonus.vulnMark > 0 then
        final = final * (1.0 + tower.runeBonus.vulnMark)
    end

    if final < 0 or final ~= final then final = 0 end
    return final
end

-- ============================================================================
-- Boss 战斗模拟
-- ============================================================================

--- 检测阵容是否有冰系英雄（用于寒意满层判定）
---@param towers table[] 虚拟塔列表
---@return boolean
local function HasChillHero(towers)
    for _, t in ipairs(towers) do
        if t.heroId == "frost_witch" or t.heroId == "glacial_sovereign" then
            return true
        end
    end
    return false
end

--- 模拟阵容 vs Boss 战斗，返回击杀耗时
--- 如果超过 BOSS_TIMER 未击杀，返回 math.huge
---@param towers table[] 虚拟塔列表
---@param boss table Boss 数据
---@return number seconds 击杀耗时
local function SimulateBossFight(towers, boss)
    if #towers == 0 then return math.huge end
    if boss.hp <= 0 then return 0 end

    -- 冰系英雄：模拟中假设 3 秒后维持寒意满层（保守估计）
    local hasChill = HasChillHero(towers)
    local chillActivateTime = 3.0

    -- 重置冷却（错开攻击节奏，在 BuildSquadTowers 中已设置）
    local time = 0

    -- Boss 被动效果简化处理
    -- disable: 每 8 秒沉默 2 秒（所有塔暂停攻击）
    local disableInterval = (boss.passive == "disable") and 8.0 or math.huge
    local disableDuration = 2.0
    local nextDisable = disableInterval
    local disableEndTime = 0

    -- phase: 每损失 25% HP 无敌 3 秒
    local phaseThresholds = {}
    if boss.passive == "phase" then
        for i = 1, 3 do
            phaseThresholds[i] = boss.maxHP * (1.0 - i * 0.25)
        end
    end
    local phaseIdx = 1
    local phaseEndTime = 0

    -- enrage: HP 低于 30% 时攻击力翻倍（对离线推关无影响，Boss 不攻击塔）
    -- summon: 召唤小兵（离线简化为 Boss HP +15%）
    if boss.passive == "summon" then
        boss.hp = boss.hp * 1.15
    end
    -- immune_cc: 无控制效果（对纯输出模拟无影响）

    while time < BOSS_TIMER do
        -- 寒意激活
        if hasChill and time >= chillActivateTime then
            boss.chillStacks = 5
        end

        -- Boss disable 被动
        if time >= nextDisable and time < nextDisable + disableDuration then
            -- 沉默期间跳过攻击
            if time + SIM_DT >= nextDisable + disableDuration then
                disableEndTime = nextDisable + disableDuration
                nextDisable = nextDisable + disableInterval + disableDuration
            end
            time = time + SIM_DT
            -- 更新冷却（沉默期间冷却仍然递减）
            for _, t in ipairs(towers) do
                t.cooldown = math.max(0, t.cooldown - SIM_DT)
            end
            goto continue
        end

        -- Boss phase 无敌
        if phaseEndTime > time then
            time = time + SIM_DT
            for _, t in ipairs(towers) do
                t.cooldown = math.max(0, t.cooldown - SIM_DT)
            end
            goto continue
        end

        -- 模拟每个塔的攻击
        for _, t in ipairs(towers) do
            t.cooldown = t.cooldown - SIM_DT
            if t.cooldown <= 0 then
                -- 攻击
                local dmg = SimCalcDamage(t, boss)

                -- 链式攻击额外伤害（简化：对 Boss 追加 30% 伤害）
                if t.typeDef.attackType == "chain" then
                    dmg = dmg * 1.3
                -- AOE 攻击对 Boss 单体命中，无额外加成
                end

                boss.hp = boss.hp - dmg

                -- 重置冷却
                t.cooldown = t.cooldown + t.speed
                if t.cooldown < 0 then t.cooldown = 0 end

                if boss.hp <= 0 then
                    return time
                end
            end
        end

        -- 检查 phase 触发
        if boss.passive == "phase" and phaseIdx <= #phaseThresholds then
            if boss.hp <= phaseThresholds[phaseIdx] then
                phaseEndTime = time + 3.0
                phaseIdx = phaseIdx + 1
            end
        end

        time = time + SIM_DT
        ::continue::
    end

    return math.huge  -- 超时未击杀
end

-- ============================================================================
-- 普通波简化 EHP 计算（保留原逻辑，用于非 Boss 波）
-- ============================================================================

-- 怪物角色基础 HP/DEF 加权平均（普通波简化用）
local ROLE_WEIGHTS = {
    minion   = 3.0,
    infantry = 2.0,
    tank     = 0.8,
    assassin = 1.0,
    dodger   = 0.5,
    support  = 0.5,
    splitter = 0.5,
    blinker  = 0.4,
    special  = 0.3,
}

--- 计算阵容的理论 DPS（用于普通波简化计算）
---@param towers table[] 虚拟塔列表
---@return number dps
local function CalcSquadTheoreticalDPS(towers)
    local baseDPS = 0
    for _, t in ipairs(towers) do
        -- DPS = ATK / speed × 暴击期望
        local critRate = t.critRate or 0
        local critDmg = t.critDmg or 0
        local baseCritMult = Config.BASE_CRIT_MULT or 1.5
        local critExpected = 1.0 + critRate * (baseCritMult + critDmg - 1.0)
        local dps = (t.attack / t.speed) * critExpected

        -- 乘区（简化：直接乘到 DPS）
        local dmgB = t.dmgBonus or 0
        if dmgB > 0 then dps = dps * (1 + dmgB) end

        local dmgType = Config.HERO_DAMAGE_TYPE[t.heroId] or "physical"
        local typeDmgB = 0
        if dmgType == "physical" then
            typeDmgB = t.physDmgBonus or 0
        elseif dmgType == "magical" then
            typeDmgB = t.magicDmgBonus or 0
        end
        if t.runeBonus and t.runeBonus.elemMastery then
            typeDmgB = typeDmgB + t.runeBonus.elemMastery
        end
        if typeDmgB > 0 then dps = dps * (1 + typeDmgB) end

        if t.runeBonus and t.runeBonus.vulnMark and t.runeBonus.vulnMark > 0 then
            dps = dps * (1 + t.runeBonus.vulnMark)
        end

        baseDPS = baseDPS + dps
    end
    return baseDPS
end

--- 计算普通波的平均穿甲率
---@param towers table[]
---@return number
local function CalcSquadAvgArmorPen(towers)
    if #towers == 0 then return 0 end
    local total = 0
    for _, t in ipairs(towers) do
        total = total + (t.armorPen or 0)
    end
    return math.min(total / #towers, 0.90)
end

-- ============================================================================
-- 阵容 vs Boss 有效 DPS（解析式，用期望值代替随机模拟）
-- ============================================================================

--- 计算阵容对指定 Boss 的有效 DPS（期望值，非模拟）
--- 复刻 SimCalcDamage 的全部 7 乘区，但用期望值代替随机暴击
---@param towers table[] 虚拟塔列表
---@param boss table Boss 数据
---@return number effectiveDPS 阵容对该 Boss 的每秒有效伤害
local function CalcEffectiveDPSvsBoss(towers, boss)
    if #towers == 0 then return 0 end

    -- 冰系英雄：假设寒意满层（挂机推关中保守假设成立）
    local hasChill = HasChillHero(towers)

    local totalDPS = 0
    for _, t in ipairs(towers) do
        local damage = t.attack
        local dmgType = Config.HERO_DAMAGE_TYPE[t.heroId] or "physical"
        local final = damage

        -- [防御乘区]
        if dmgType == "physical" then
            local enemyDEF = boss.def or 0
            local armorPen = t.armorPen or 0
            local penResist = boss.armorPenResist or 0
            if penResist > 0 then
                armorPen = armorPen * (1 - penResist)
            end
            if armorPen > 0 then
                enemyDEF = enemyDEF * (1 - math.min(armorPen, 0.90))
            end
            enemyDEF = math.max(0, enemyDEF)
            local defMult = F.Diminishing(enemyDEF, damage)
            final = final * defMult
        elseif dmgType == "magical" then
            local res = boss.res or 0
            local mPen = t.magicPen or 0
            if mPen > 0 then
                res = res - mPen * 100
            end
            res = math.max(0, math.min(100, res))
            final = final * (1.0 - res / 100)
        end
        -- pure: 不减伤

        -- [暴击乘区] — 期望值
        local critRate = t.critRate or 0
        local critDmg = t.critDmg or 0
        local critReduce = boss.critDmgReduce or 0
        if critReduce > 0 then
            critDmg = critDmg * (1 - critReduce)
        end
        local baseCritMult = (Config.BASE_CRIT_MULT or 1.5) + critDmg
        local critExpected = 1.0 + critRate * (baseCritMult - 1.0)
        final = final * critExpected

        -- [伤害加成乘区]
        do
            local db = t.dmgBonus or 0
            local dbReduce = boss.dmgBonusReduce or 0
            if dbReduce > 0 then
                db = db * (1 - dbReduce)
            end
            if db > 0 then
                final = final * (1.0 + db)
            end
        end

        -- [类型伤害乘区]
        do
            local typeDmgBonus = 0
            if dmgType == "physical" then
                typeDmgBonus = t.physDmgBonus or 0
            elseif dmgType == "magical" then
                typeDmgBonus = t.magicDmgBonus or 0
            end
            if t.runeBonus and t.runeBonus.elemMastery and t.runeBonus.elemMastery > 0 then
                typeDmgBonus = typeDmgBonus + t.runeBonus.elemMastery
            end
            local typeReduce = boss.typeDmgReduce or 0
            if typeReduce > 0 then
                typeDmgBonus = typeDmgBonus * (1 - typeReduce)
            end
            if typeDmgBonus > 0 then
                final = final * (1.0 + typeDmgBonus)
            end
        end

        -- [寒意增伤乘区]
        if hasChill then
            local chillAmp = t.typeDef.chillDmgAmpAtMax or 0.50
            final = final * (1.0 + chillAmp)
        end

        -- [易伤标记乘区]
        if t.runeBonus and t.runeBonus.vulnMark and t.runeBonus.vulnMark > 0 then
            final = final * (1.0 + t.runeBonus.vulnMark)
        end

        -- 链式攻击加成
        if t.typeDef.attackType == "chain" then
            final = final * 1.3
        end

        if final < 0 or final ~= final then final = 0 end

        -- DPS = 单次伤害 / 攻击间隔
        local dps = final / t.speed
        totalDPS = totalDPS + dps
    end

    return totalDPS
end

--- 计算指定波次的普通怪 EHP（保留原逻辑）
---@param stageNum number
---@param wave number
---@param refDamage number
---@param armorPen number
---@return number
local function CalcWaveEHP(stageNum, wave, refDamage, armorPen)
    local hpScale = DungeonScaling.CalcHPScaleWithWave(stageNum, wave)
    local defScale = DungeonScaling.CalcDEFScale(stageNum)

    local waveCount = Config.WAVE_BASE_COUNT + (stageNum - 1) * Config.WAVE_COUNT_GROWTH
    waveCount = math.min(waveCount, Config.WAVE_MAX_COUNT or 16)
    waveCount = math.max(4, math.floor(waveCount))

    local totalWeight = 0
    local avgBaseHP = 0
    local avgBaseDEF = 0
    for roleId, weight in pairs(ROLE_WEIGHTS) do
        local role = Config.ENEMY_ROLES[roleId]
        if role then
            avgBaseHP = avgBaseHP + role.baseHP * weight
            avgBaseDEF = avgBaseDEF + role.baseDEF * weight
            totalWeight = totalWeight + weight
        end
    end
    if totalWeight > 0 then
        avgBaseHP = avgBaseHP / totalWeight
        avgBaseDEF = avgBaseDEF / totalWeight
    else
        avgBaseHP = 10000
        avgBaseDEF = 800
    end

    local monsterHP = avgBaseHP * hpScale
    local monsterDEF = avgBaseDEF * defScale
    if armorPen > 0 then
        monsterDEF = monsterDEF * (1 - armorPen)
    end
    monsterDEF = math.max(0, monsterDEF)

    local defPenRate = F.Diminishing(monsterDEF, refDamage)
    local effectiveMult = 1.0
    if defPenRate > 0.01 then
        effectiveMult = 1.0 / defPenRate
    else
        effectiveMult = 100.0
    end

    return monsterHP * effectiveMult * waveCount
end

-- ============================================================================
-- 普通波超限检查（v5 新增）
-- 超限机制：场上怪物 > MAX_ENEMIES 持续 OVERLOAD_COUNTDOWN 秒则失败
-- ============================================================================

--- 计算单只普通怪的平均 EHP（不含 waveCount 乘算）
---@param stageNum number
---@param wave number
---@param refDamage number
---@param armorPen number
---@return number singleEHP
local function CalcSingleEnemyEHP(stageNum, wave, refDamage, armorPen)
    local hpScale = DungeonScaling.CalcHPScaleWithWave(stageNum, wave)
    local defScale = DungeonScaling.CalcDEFScale(stageNum)

    local totalWeight = 0
    local avgBaseHP = 0
    local avgBaseDEF = 0
    for roleId, weight in pairs(ROLE_WEIGHTS) do
        local role = Config.ENEMY_ROLES[roleId]
        if role then
            avgBaseHP = avgBaseHP + role.baseHP * weight
            avgBaseDEF = avgBaseDEF + role.baseDEF * weight
            totalWeight = totalWeight + weight
        end
    end
    if totalWeight > 0 then
        avgBaseHP = avgBaseHP / totalWeight
        avgBaseDEF = avgBaseDEF / totalWeight
    else
        avgBaseHP = 10000
        avgBaseDEF = 800
    end

    local monsterHP = avgBaseHP * hpScale
    local monsterDEF = avgBaseDEF * defScale
    if armorPen > 0 then
        monsterDEF = monsterDEF * (1 - armorPen)
    end
    monsterDEF = math.max(0, monsterDEF)

    local defPenRate = F.Diminishing(monsterDEF, refDamage)
    local effectiveMult = 1.0
    if defPenRate > 0.01 then
        effectiveMult = 1.0 / defPenRate
    else
        effectiveMult = 100.0
    end

    return monsterHP * effectiveMult
end

--- 计算指定关卡波次的实际出怪数量（复刻 Wave.lua GenerateNormalWave 公式）
---@param stageNum number
---@param waveInStage number
---@return number
local function CalcWaveEnemyCount(stageNum, waveInStage)
    local count = math.floor(Config.WAVE_BASE_COUNT + waveInStage * Config.WAVE_COUNT_GROWTH + stageNum * 0.5)
    count = math.min(count, Config.WAVE_MAX_COUNT or 16)
    return math.max(4, count)
end

--- 检查阵容能否在指定关卡的普通波次中避免超限失败
--- 模型：击杀吞吐率 vs 出怪速率，若怪物堆积超过阈值且持续超过倒计时则失败
---@param stageNum number 关卡号
---@param squadDPS number 阵容理论 DPS
---@param armorPen number 平均穿甲率
---@return boolean canSurvive 是否能通过普通波次
local function CanSurviveNormalWaves(stageNum, squadDPS, armorPen)
    if squadDPS <= 0 then return false end

    local refDamage = squadDPS * 1.5
    local maxEnemies = Config.MAX_ENEMIES or 7
    local overloadCD = Config.OVERLOAD_COUNTDOWN or 10
    -- 普通波平均出怪间隔（普通怪 1.0s，快速怪 0.5s，保守取 0.8s）
    local avgSpawnInterval = 0.8

    for w = 1, WAVES_PER_STAGE - 1 do
        local totalCount = CalcWaveEnemyCount(stageNum, w)
        local singleEHP = CalcSingleEnemyEHP(stageNum, w, refDamage, armorPen)

        -- 击杀吞吐率（只/秒）：DPS 总输出 / 单只 EHP
        local killRate = squadDPS / singleEHP
        -- 出怪速率（只/秒）
        local spawnRate = 1.0 / avgSpawnInterval

        if killRate < spawnRate then
            -- 怪物堆积速率
            local accumRate = spawnRate - killRate
            -- 堆积到超限阈值所需时间
            local timeToOverload = maxEnemies / accumRate
            -- 出怪总时长
            local spawnDuration = totalCount * avgSpawnInterval
            -- 如果在出怪结束前就超限并持续超过倒计时 → 失败
            if timeToOverload + overloadCD < spawnDuration then
                return false
            end
        end
    end

    return true
end

-- ============================================================================
-- 关卡通关评估（混合模式：普通波 EHP + Boss 波模拟）
-- ============================================================================

--- 估算单关通关耗时（普通波用 DPS/EHP，Boss 波用模拟）
---@param stageNum number
---@param towers table[] 虚拟塔列表
---@param squadDPS number 阵容理论 DPS
---@param armorPen number 平均穿甲
---@return number seconds 预计耗时，math.huge 表示无法通关
function OP.EstimateStageClearTime(stageNum, towers, squadDPS, armorPen)
    if squadDPS <= 0 or #towers == 0 then return math.huge end

    -- 超限检查：普通波 DPS 不足则无法通关
    if not CanSurviveNormalWaves(stageNum, squadDPS, armorPen) then
        return math.huge
    end

    local refDamage = squadDPS * 1.5
    local normalWaveTime = 0

    -- 前 WAVES_PER_STAGE-1 波普通怪（简化 EHP/DPS）
    for w = 1, WAVES_PER_STAGE - 1 do
        local ehp = CalcWaveEHP(stageNum, w, refDamage, armorPen)
        normalWaveTime = normalWaveTime + ehp / squadDPS
    end

    -- Boss 波：构建 Boss，运行模拟
    local boss = BuildStageBoss(stageNum)
    -- 重置塔冷却（模拟 Boss 波开始时）
    for i, t in ipairs(towers) do
        t.cooldown = (i - 1) % 8 * (t.speed / 8)
    end
    local bossTime = SimulateBossFight(towers, boss)

    if bossTime >= math.huge then
        return math.huge
    end

    local totalTime = normalWaveTime + bossTime

    -- 调试日志（只打前 3 关）
    if stageNum <= (HeroData.stats.bestStage or 1) + 3 then
        print(string.format("[OfflinePush] Stage %d: waveTime=%.1fs, bossHP=%.2e, bossTime=%.1fs, total=%.1fs, %s",
            stageNum, normalWaveTime, boss.maxHP, bossTime, totalTime,
            totalTime > BOSS_TIMER and "STUCK" or "OK"))
    end

    if totalTime > BOSS_TIMER then
        return math.huge
    end

    return totalTime
end

-- ============================================================================
-- 离线推关核心
-- ============================================================================

--- 计算离线期间能推过多少关
---@param offlineSeconds number 离线秒数
---@param startStage number 起始关卡（当前最高关+1）
---@return number clearedStages
---@return number timeUsed
---@return number nextStageTime
function OP.CalcOfflinePush(offlineSeconds, startStage)
    -- 构建虚拟塔阵容（只构建一次）
    local towers = BuildSquadTowers()
    if #towers == 0 then
        return 0, 0, math.huge
    end

    -- ========================================================================
    -- v5: 在 v4 基础上新增普通波超限检查
    -- v4 修复：逐关模拟，每关重新构建 Boss，碰到打不过的就停
    -- v5 修复：普通波加入超限判定，DPS 不足以维持清怪速率时视为卡关
    -- ========================================================================
    local MAX_PUSH_STAGES = 100
    local waveOverhead = (WAVES_PER_STAGE - 1) * WAVE_INTERVAL  -- 27秒

    -- 预计算阵容理论 DPS 和穿甲（普通波超限检查用，塔不变所以只算一次）
    local squadDPS = CalcSquadTheoreticalDPS(towers)
    local armorPen = CalcSquadAvgArmorPen(towers)

    local stages = 0
    local timeUsed = 0
    local lastClearTime = math.huge

    for i = 0, MAX_PUSH_STAGES - 1 do
        local stageNum = startStage + i

        -- 超限检查：普通波击杀吞吐率不足 → 怪物堆积超限 → 卡关
        if not CanSurviveNormalWaves(stageNum, squadDPS, armorPen) then
            print(string.format("[OfflinePush] Stage %d: normal wave overload (DPS insufficient to clear), STUCK", stageNum))
            break
        end

        local boss = BuildStageBoss(stageNum)
        local effectiveDPS = CalcEffectiveDPSvsBoss(towers, boss)

        if effectiveDPS <= 0 then break end

        -- Boss 击杀时间
        local bossKillTime = boss.hp / effectiveDPS

        -- Boss 被动惩罚
        if boss.passive == "disable" then
            bossKillTime = bossKillTime / 0.80
        end
        if boss.passive == "phase" then
            bossKillTime = bossKillTime + 9.0
        end
        if boss.passive == "summon" then
            bossKillTime = bossKillTime * 1.15
        end

        -- 打不过（超过 Boss 限时）→ 停
        if bossKillTime > BOSS_TIMER then
            lastClearTime = bossKillTime
            break
        end

        -- 本关通关耗时
        local clearTime = math.max(bossKillTime + waveOverhead, 30.0)

        -- 离线时间不够 → 停
        if timeUsed + clearTime > offlineSeconds then
            lastClearTime = clearTime
            break
        end

        stages = stages + 1
        timeUsed = timeUsed + clearTime
        lastClearTime = clearTime
    end

    print(string.format("[OfflinePush] v5: stages=%d, timeUsed=%.0fs/%ds, lastClear=%.1fs, squadDPS=%.2e",
        stages, timeUsed, offlineSeconds, lastClearTime, squadDPS))

    return stages, timeUsed, lastClearTime
end

--- 计算阵容总理论 DPS（向后兼容旧接口）
---@return number totalDPS, table zones
function OP.CalcSquadDPS()
    local towers = BuildSquadTowers()
    local dps = CalcSquadTheoreticalDPS(towers)
    local armorPen = CalcSquadAvgArmorPen(towers)

    return dps, { armorPen = armorPen, dmgBonus = 0, typeDmg = 0, vuln = 0, chillAmp = 0 }
end

--- 计算指定关卡的总 EHP（向后兼容）
function OP.CalcStageEHP(stageNum, refDamage, armorPen)
    armorPen = armorPen or 0
    local totalEHP = 0
    for w = 1, WAVES_PER_STAGE - 1 do
        totalEHP = totalEHP + CalcWaveEHP(stageNum, w, refDamage, armorPen)
    end
    -- Boss EHP 粗估（使用 BuildStageBoss 的 HP 作为基础）
    local boss = BuildStageBoss(stageNum)
    totalEHP = totalEHP + boss.hp
    return totalEHP
end

-- ============================================================================
-- 奖励结算（保持不变）
-- ============================================================================

--- 完整的离线推关结算（带奖励发放）
---@return table|nil result { pushed, newBestStage, rewards, ... }
function OP.CalcOfflinePushRewards()
    local lastTime = HeroData.lastSaveTime or 0
    if lastTime <= 0 then return nil end

    local ServerTime = require("Game.ServerTime")
    local now = ServerTime.Now()
    local elapsed = now - lastTime
    if elapsed < Config.IDLE_MIN_SECONDS then return nil end

    -- 时间上限（与挂机收益共用配置）
    local PrivilegeData = require("Game.PrivilegeData")
    local maxSeconds = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds()
    local ok2, DivineBlessDB = pcall(require, "Game.DivineBlessData")
    if ok2 and DivineBlessDB and DivineBlessDB.GetBuffValue then
        maxSeconds = maxSeconds + DivineBlessDB.GetBuffValue("idle_extra")
    end
    local capped = math.min(elapsed, maxSeconds)

    -- 当前最高关
    local bestStage = HeroData.stats.bestStage or 1
    if bestStage < 1 then bestStage = 1 end

    -- 离线推关（从 bestStage+1 开始）
    local pushed, timeUsed, nextTime = OP.CalcOfflinePush(capped, bestStage + 1)

    if pushed <= 0 then
        return {
            pushed = 0,
            newBestStage = bestStage,
            oldBestStage = bestStage,
            offlineSeconds = capped,
            nextStageTime = nextTime,
            stageRewards = {},
        }
    end

    -- 计算推关奖励（每关的掉落）
    local totalCrystal = 0
    local totalStone = 0
    local totalIron = 0
    local totalVoidPact = 0

    for s = bestStage + 1, bestStage + pushed do
        local crystal, stone, iron = Config.EstimateStageDrop(s)
        totalCrystal = totalCrystal + crystal
        totalStone = totalStone + stone
        totalIron = totalIron + iron
        if s % 5 == 0 then
            totalVoidPact = totalVoidPact + 1
        end
    end

    totalCrystal = math.floor(totalCrystal * Config.IDLE_RATE)
    totalStone = math.floor(totalStone * Config.IDLE_RATE)
    totalIron = math.floor(totalIron * Config.IDLE_RATE)

    return {
        pushed = pushed,
        newBestStage = bestStage + pushed,
        oldBestStage = bestStage,
        offlineSeconds = capped,
        timeUsed = timeUsed,
        nextStageTime = nextTime,
        stageRewards = {
            nether_crystal = totalCrystal,
            devour_stone = totalStone,
            forge_iron = totalIron,
            void_pact = totalVoidPact,
        },
    }
end

--- 领取离线推关奖励（更新 bestStage 并发放资源）
---@param result table CalcOfflinePushRewards 的返回值
---@param laborMult? number 外部已消耗的劳动倍率，传入则不再自行消耗（避免同一次领取双重扣次数）
function OP.ClaimPushRewards(result, laborMult)
    if not result or result.pushed <= 0 then return end

    local Currency = require("Game.Currency")
    local PrivilegeData = require("Game.PrivilegeData")

    -- 劳动加倍：优先使用外部传入的倍率，否则自行消耗
    if not laborMult then
        local ok, LaborDayData = pcall(require, "Game.LaborDayData")
        laborMult = 1
        if ok and LaborDayData and LaborDayData.ConsumeDouble then
            laborMult = LaborDayData.ConsumeDouble()
        end
    end

    local rewards = result.stageRewards
    rewards.nether_crystal = math.floor((rewards.nether_crystal or 0) * laborMult)
    rewards.devour_stone   = math.floor((rewards.devour_stone or 0) * laborMult)
    rewards.forge_iron     = math.floor((rewards.forge_iron or 0) * laborMult)

    -- 特权增益：冥晶加成
    local crystalRate = PrivilegeData.GetCrystalBonusRate()
    if crystalRate > 1.0 then
        rewards.nether_crystal = math.floor(rewards.nether_crystal * crystalRate)
    end

    -- 特权增益：概率翻倍全部收益
    local doubleChance = PrivilegeData.GetDoubleChance()
    if doubleChance > 0 and math.random() < doubleChance then
        rewards.nether_crystal = rewards.nether_crystal * 2
        rewards.devour_stone   = rewards.devour_stone * 2
        rewards.forge_iron     = rewards.forge_iron * 2
        print("[OfflinePush] Privilege double triggered!")
    end

    Currency.Add("nether_crystal", rewards.nether_crystal)
    Currency.Add("devour_stone", rewards.devour_stone)
    Currency.Add("forge_iron", rewards.forge_iron)
    if rewards.void_pact and rewards.void_pact > 0 then
        Currency.Add("void_pact", rewards.void_pact)
    end

    -- 更新 bestStage（单调递增保护：绝不允许回退）
    local oldBest = HeroData.stats.bestStage or 0
    if result.newBestStage > oldBest then
        HeroData.stats.bestStage = result.newBestStage
        HeroData.stats.bestGlobalWave = result.newBestStage * Config.WAVES_PER_STAGE
    elseif result.newBestStage < oldBest then
        print("[OfflinePush] !! SAFETY: rejected bestStage rollback "
            .. oldBest .. " → " .. result.newBestStage .. ", keeping " .. oldBest)
    end

    -- 排行榜上传
    local lok, LB = pcall(require, "Game.LeaderboardData")
    if lok and LB and LB.UploadCampaign then
        LB.UploadCampaign(HeroData.stats.bestGlobalWave)
    end

    -- 劳动勋章
    local mok, LMD = pcall(require, "Game.LaborMedalData")
    if mok and LMD and LMD.EarnMedals then
        LMD.EarnMedals("offline_push", result.pushed)
    end

    HeroData.Save()
    print("[OfflinePush] Claimed: pushed=" .. result.pushed
        .. " newBest=" .. result.newBestStage
        .. " crystal=" .. rewards.nether_crystal
        .. " stone=" .. rewards.devour_stone
        .. " iron=" .. rewards.forge_iron)
end

--- 获取阵容战力摘要（供 UI 显示）
---@return table { totalDPS, leaderDPS, heroDPS[], fieldStar, zones }
function OP.GetSquadSummary()
    local towers = BuildSquadTowers()

    -- 分类统计
    local leaderDPS = 0
    local heroDPSMap = {}  -- heroId -> totalDPS
    local heroDPSSingle = {} -- heroId -> singleDPS

    for _, t in ipairs(towers) do
        local critRate = t.critRate or 0
        local critDmg = t.critDmg or 0
        local baseCritMult = Config.BASE_CRIT_MULT or 1.5
        local critExpected = 1.0 + critRate * (baseCritMult + critDmg - 1.0)
        local dps = (t.attack / t.speed) * critExpected

        if t.heroId == Config.LEADER_HERO.id then
            leaderDPS = leaderDPS + dps
        else
            heroDPSMap[t.heroId] = (heroDPSMap[t.heroId] or 0) + dps
            if not heroDPSSingle[t.heroId] then
                heroDPSSingle[t.heroId] = dps
            end
        end
    end

    local heroDPSList = {}
    local deployed = HeroData.deployed or {}
    for _, heroId in ipairs(deployed) do
        heroDPSList[#heroDPSList + 1] = {
            heroId = heroId,
            singleDPS = heroDPSSingle[heroId] or 0,
            totalDPS = heroDPSMap[heroId] or 0,
        }
    end

    local totalDPS = leaderDPS
    for _, h in ipairs(heroDPSList) do
        totalDPS = totalDPS + h.totalDPS
    end

    local armorPen = CalcSquadAvgArmorPen(towers)

    return {
        totalDPS = totalDPS,
        leaderDPS = leaderDPS,
        heroDPS = heroDPSList,
        fieldStar = IDEAL_FIELD_STAR,
        towersPerHero = TOWERS_PER_HERO,
        towerCount = #towers,
        zones = { armorPen = armorPen },
    }
end

return OP
