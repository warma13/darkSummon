--- OfflinePush.lua
--- 离线自动推关模块
--- 根据玩家当前阵容战斗力 vs 关卡难度，模拟离线期间能推过多少关
--- 核心公式：阵容理想 DPS（含全乘区） vs 关卡总 EHP → 单关耗时 → 离线可推关数

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
local WAVE_HP_PER_WAVE  = Config.WAVE_HP_PER_WAVE or 0.04

-- 场内合并星级：离线模拟不跑实际合并，取"理想平均星级"
local IDEAL_FIELD_STAR   = 3
-- 每种随从英雄的场内塔数（理想状态下每种约8-10个塔，取保守值）
local TOWERS_PER_HERO    = 8
-- 离线效率系数（离线战斗不如实战精准，打折处理）
local OFFLINE_EFFICIENCY = 0.65

-- 怪物角色基础 HP/DEF 加权平均
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

-- ============================================================================
-- 乘区收集：从英雄数据、装备、符文、遗物中汇总战斗乘区
-- ============================================================================

--- 收集阵容的平均战斗乘区（armorPen, dmgBonus, typeDmg, vuln, chill）
--- 这些乘区在实战中是独立相乘的，离线模拟需要把它们加回来
---@return table { armorPen, dmgBonus, typeDmg, vuln, chillAmp }
local function CollectSquadZones()
    local deployed = HeroData.deployed or {}
    if #deployed == 0 then
        return { armorPen = 0, dmgBonus = 0, typeDmg = 0, vuln = 0, chillAmp = 0 }
    end

    local ok_eq, EquipData = pcall(require, "Game.EquipData")
    local ok_rune, RuneData = pcall(require, "Game.RuneData")

    local totalArmorPen = 0
    local totalDmgBonus = 0
    local totalTypeDmg  = 0
    local totalVuln     = 0
    local hasChill      = false
    local heroCount     = 0

    for _, heroId in ipairs(deployed) do
        local hs = HeroData.GetHeroStats(heroId)
        if hs and hs.atk > 0 then
            heroCount = heroCount + 1

            -- 英雄基础 armorPen（含等级成长）
            local pen = hs.armorPen or 0

            -- 装备加成
            local eqBonus = (ok_eq and EquipData.GetTotalBonus(heroId)) or {}
            local dmgB = eqBonus.dmgBonus or 0

            -- 符文加成
            local runeBonus = (ok_rune and RuneData.GetCombatBonus(heroId)) or {}
            pen = pen + (runeBonus.armorPen or 0)
            dmgB = dmgB + (runeBonus.dmgBonus or 0)

            -- 类型伤害
            local dmgType = Config.HERO_DAMAGE_TYPE[heroId] or "physical"
            local tDmg = 0
            if dmgType == "physical" then
                tDmg = (runeBonus.physDmgBonus or 0)
            elseif dmgType == "magical" then
                tDmg = (runeBonus.magicDmgBonus or 0)
            end
            tDmg = tDmg + (runeBonus.elemMastery or 0)

            -- 符文易伤
            local vuln = runeBonus.vulnMark or 0

            -- 冰系英雄检测（有冰系英雄即可触发寒意满层增伤）
            if dmgType == "magical" then
                -- 冰系英雄：frost_witch, glacial_sovereign
                if heroId == "frost_witch" or heroId == "glacial_sovereign" then
                    hasChill = true
                end
            end

            totalArmorPen = totalArmorPen + pen
            totalDmgBonus = totalDmgBonus + dmgB
            totalTypeDmg  = totalTypeDmg + tDmg
            totalVuln     = totalVuln + vuln
        end
    end

    -- 取部署英雄的加权平均
    if heroCount > 0 then
        totalArmorPen = totalArmorPen / heroCount
        totalDmgBonus = totalDmgBonus / heroCount
        totalTypeDmg  = totalTypeDmg / heroCount
        totalVuln     = totalVuln / heroCount
    end

    -- 穿甲上限 cap
    totalArmorPen = math.min(totalArmorPen, 0.90)

    -- 寒意增伤：有冰系英雄时，离线以 70% 概率维持满层（保守估计）
    local chillAmp = hasChill and (0.50 * 0.70) or 0

    return {
        armorPen = totalArmorPen,
        dmgBonus = totalDmgBonus,
        typeDmg  = totalTypeDmg,
        vuln     = totalVuln,
        chillAmp = chillAmp,
    }
end

-- ============================================================================
-- DPS 计算（保留原逻辑，不变）
-- ============================================================================

--- 计算单个英雄塔的理论 DPS（不含光环/技能标签等战局内 buff）
--- DPS = (heroATK × fieldStarMult / speed) × 暴击期望
---@param heroId string
---@param fieldStar number 场内塔合并星级
---@return number dps
local function CalcHeroDPS(heroId, fieldStar)
    local heroStats = HeroData.GetHeroStats(heroId)
    if not heroStats or heroStats.atk <= 0 then return 0 end

    local starMult = Config.STAR_MULTIPLIER[fieldStar] or 1.0
    local typeDef = nil
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then typeDef = td; break end
    end
    if not typeDef then return 0 end

    -- 获取装备加成
    local ok, EquipData = pcall(require, "Game.EquipData")
    local equipBonus = ok and EquipData.GetTotalBonus(heroId) or {}
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

    -- 最终攻击 = (英雄ATK × 场内星级 + 装备ATK) × (1 + 百分比) × (1 + 遗物)
    local finalAtk = (heroStats.atk * starMult + equipAtk) * (1 + atkPctBonus) * (1 + relicAtkPct)
    -- 攻速 = baseSpeed / starSpeedMult / (1 + spdBonus + equipSpd + relicSpd)
    local starSpeed = Config.STAR_SPEED_MULT[fieldStar] or 1.0
    local speed = typeDef.baseSpeed / starSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + relicSpdPct)
    if speed <= 0 then speed = 0.1 end

    -- 暴击期望 = 1 + critRate × (baseCritMult + critDmg - 1)
    local critRate = math.min(1.0, (heroStats.critRate or 0) + (equipBonus.critRate or 0))
    local critDmg = (heroStats.critDmg or 0) + (equipBonus.critDmg or 0) + relicCritDmgPct
    local baseCritMult = Config.BASE_CRIT_MULT or 1.5
    local critExpected = 1.0 + critRate * (baseCritMult + critDmg - 1.0)

    -- DPS = ATK / speed × 暴击期望
    local dps = (finalAtk / speed) * critExpected

    return dps
end

--- 计算主角塔的 DPS
---@return number dps
local function CalcLeaderDPS()
    local heroId = Config.LEADER_HERO.id
    local heroStats = HeroData.GetHeroStats(heroId)
    if not heroStats or heroStats.atk <= 0 then return 0 end

    local typeDef = Config.LEADER_HERO

    local ok, EquipData = pcall(require, "Game.EquipData")
    local equipBonus = ok and EquipData.GetTotalBonus(heroId) or {}
    local equipAtk = equipBonus.atk or 0
    local atkPctBonus = equipBonus.atk_pct or 0
    local spdPctBonus = equipBonus.spd_pct or 0

    local relicAtkPct, relicSpdPct, relicCritDmgPct = 0, 0, 0
    local rok, RD = pcall(require, "Game.RelicData")
    if rok and RD and RD.GetPassiveBonus then
        local rb = RD.GetPassiveBonus()
        relicAtkPct = rb.atkPct or 0
        relicSpdPct = rb.spdPct or 0
        relicCritDmgPct = rb.critDmgPct or 0
    end

    -- 主角不走场内合并，star=1
    local finalAtk = (heroStats.atk + equipAtk) * (1 + atkPctBonus) * (1 + relicAtkPct)
    local speed = typeDef.baseSpeed / (1 + (heroStats.spdBonus or 0) + spdPctBonus + relicSpdPct)
    if speed <= 0 then speed = 0.1 end

    local critRate = math.min(1.0, (heroStats.critRate or 0) + (equipBonus.critRate or 0))
    local critDmg = (heroStats.critDmg or 0) + (equipBonus.critDmg or 0) + relicCritDmgPct
    local baseCritMult = Config.BASE_CRIT_MULT or 1.5
    local critExpected = 1.0 + critRate * (baseCritMult + critDmg - 1.0)

    local dps = (finalAtk / speed) * critExpected
    return dps
end

--- 计算阵容总理论 DPS（含全乘区加成）
---@return number totalDPS, table zones
function OP.CalcSquadDPS()
    local baseDPS = 0

    -- 主角（1个塔）
    baseDPS = baseDPS + CalcLeaderDPS()

    -- 随从英雄（每种英雄多个塔）
    local deployed = HeroData.deployed or {}
    for _, heroId in ipairs(deployed) do
        local heroDPS = CalcHeroDPS(heroId, IDEAL_FIELD_STAR)
        baseDPS = baseDPS + heroDPS * TOWERS_PER_HERO
    end

    -- 收集战斗乘区
    local zones = CollectSquadZones()

    -- 应用独立乘区到 DPS（这些在实战中是独立相乘的）
    -- dmgBonus: (1 + dmgBonus)
    -- typeDmg:  (1 + typeDmg)
    -- vuln:     (1 + vuln)
    -- chill:    (1 + chillAmp)
    -- armorPen 不在这里应用，它在 EHP 计算端降低敌方 DEF
    local zoneMult = (1 + zones.dmgBonus)
                   * (1 + zones.typeDmg)
                   * (1 + zones.vuln)
                   * (1 + zones.chillAmp)

    local effectiveDPS = baseDPS * zoneMult * OFFLINE_EFFICIENCY

    print(string.format("[OfflinePush] SquadDPS: base=%.0f, zoneMult=%.2f(dmg+%.2f typ+%.2f vuln+%.2f chill+%.2f), eff=%.0f, armorPen=%.2f",
        baseDPS, zoneMult, zones.dmgBonus, zones.typeDmg, zones.vuln, zones.chillAmp,
        effectiveDPS, zones.armorPen))

    return effectiveDPS, zones
end

-- ============================================================================
-- 关卡难度评估（EHP 计算，现在考虑 armorPen）
-- ============================================================================

--- 计算指定关卡某一波的怪物总 EHP（考虑 armorPen 后的 DEF 减伤）
---@param stageNum number
---@param wave number 1-based 波次
---@param refDamage number 参考单次伤害（用于 DEF 减伤计算）
---@param armorPen number 阵容平均穿甲率 0~0.90
---@return number totalEHP
local function CalcWaveEHP(stageNum, wave, refDamage, armorPen)
    local hpScale = DungeonScaling.CalcHPScaleWithWave(stageNum, wave)
    local defScale = DungeonScaling.CalcDEFScale(stageNum)

    -- 波次怪物数量
    local waveCount = Config.WAVE_BASE_COUNT + (stageNum - 1) * Config.WAVE_COUNT_GROWTH
    waveCount = math.min(waveCount, Config.WAVE_MAX_COUNT or 16)
    waveCount = math.max(4, math.floor(waveCount))

    -- 加权平均基础 HP 和 DEF
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

    -- 单怪 HP 和 DEF
    local monsterHP = avgBaseHP * hpScale
    local monsterDEF = avgBaseDEF * defScale

    -- ★ 应用穿甲：降低敌方 DEF
    if armorPen > 0 then
        monsterDEF = monsterDEF * (1 - armorPen)
    end
    monsterDEF = math.max(0, monsterDEF)

    -- DEF 减伤 → EHP 倍率
    -- Diminishing(DEF, damage) = damage/(damage+DEF) → 穿透率
    -- EHP = HP / 穿透率
    local defPenRate = F.Diminishing(monsterDEF, refDamage)
    local effectiveMult = 1.0
    if defPenRate > 0.01 then
        effectiveMult = 1.0 / defPenRate
    else
        effectiveMult = 100.0  -- 几乎无法穿透
    end

    local totalEHP = monsterHP * effectiveMult * waveCount
    return totalEHP
end

--- 计算 BOSS 波的 EHP（考虑 armorPen）
---@param stageNum number
---@param refDamage number
---@param armorPen number
---@return number bossEHP
local function CalcBossEHP(stageNum, refDamage, armorPen)
    local hpScale = DungeonScaling.CalcHPScaleWithWave(stageNum, WAVES_PER_STAGE)
    local defScale = DungeonScaling.CalcDEFScale(stageNum)

    -- BOSS tier
    local tier = math.ceil(stageNum / 10)
    local bossBaseHP = 150000
    local bossBaseDEF = 3000

    -- BOSS HP = baseHP × hpScale × tier^2.25
    local bossHP = bossBaseHP * hpScale * (tier ^ 2.25)

    -- BOSS DEF（应用穿甲）
    local bossDEF = bossBaseDEF * defScale
    if armorPen > 0 then
        bossDEF = bossDEF * (1 - armorPen)
    end
    bossDEF = math.max(0, bossDEF)

    -- EHP 计算
    local defPenRate = F.Diminishing(bossDEF, refDamage)
    local effectiveMult = 1.0
    if defPenRate > 0.01 then
        effectiveMult = 1.0 / defPenRate
    else
        effectiveMult = 100.0
    end

    local bossEHP = bossHP * effectiveMult
    return bossEHP
end

--- 计算指定关卡的总 EHP（所有波次 + BOSS）
---@param stageNum number
---@param refDamage number 参考单次伤害
---@param armorPen number 阵容平均穿甲率
---@return number totalEHP
function OP.CalcStageEHP(stageNum, refDamage, armorPen)
    armorPen = armorPen or 0
    local totalEHP = 0

    -- 前 WAVES_PER_STAGE-1 波普通怪
    for w = 1, WAVES_PER_STAGE - 1 do
        totalEHP = totalEHP + CalcWaveEHP(stageNum, w, refDamage, armorPen)
    end

    -- 最后一波 BOSS（BOSS + 随从小怪）
    totalEHP = totalEHP + CalcBossEHP(stageNum, refDamage, armorPen)
    -- BOSS 波的小怪
    totalEHP = totalEHP + CalcWaveEHP(stageNum, WAVES_PER_STAGE, refDamage, armorPen) * 0.3

    return totalEHP
end

--- 估算单关通关耗时
---@param stageNum number
---@param squadDPS number
---@param armorPen number
---@return number seconds 预计耗时（秒），math.huge 表示无法通关
function OP.EstimateStageClearTime(stageNum, squadDPS, armorPen)
    if squadDPS <= 0 then return math.huge end
    armorPen = armorPen or 0

    -- 参考单次伤害 = DPS × 平均攻击间隔（取 1.5 秒作为典型值）
    local refDamage = squadDPS * 1.5

    local totalEHP = OP.CalcStageEHP(stageNum, refDamage, armorPen)
    local clearTime = totalEHP / squadDPS

    -- 调试日志（只打前3关）
    if stageNum <= (HeroData.stats.bestStage or 1) + 3 then
        print(string.format("[OfflinePush] Stage %d: EHP=%.2e, DPS=%.2e, clearTime=%.1fs, limit=%ds, armorPen=%.2f, %s",
            stageNum, totalEHP, squadDPS, clearTime, BOSS_TIMER, armorPen,
            clearTime > BOSS_TIMER and "STUCK" or "OK"))
    end

    -- 如果超过 BOSS 限时，视为无法通关
    if clearTime > BOSS_TIMER then
        return math.huge
    end

    return clearTime
end

-- ============================================================================
-- 离线推关核心
-- ============================================================================

--- 计算离线期间能推过多少关
---@param offlineSeconds number 离线秒数
---@param startStage number 起始关卡（当前最高关+1）
---@return number clearedStages 推过的关数
---@return number timeUsed 实际消耗的时间
---@return number nextStageTime 下一关预计耗时（math.huge 表示卡关）
function OP.CalcOfflinePush(offlineSeconds, startStage)
    local squadDPS, zones = OP.CalcSquadDPS()
    if squadDPS <= 0 then
        return 0, 0, math.huge
    end

    local armorPen = zones.armorPen or 0
    local clearedStages = 0
    local timeUsed = 0

    local stage = startStage
    local maxStages = 100  -- 单次离线最多推100关（防止无限循环）

    while clearedStages < maxStages do
        local clearTime = OP.EstimateStageClearTime(stage, squadDPS, armorPen)
        if clearTime >= math.huge then
            break
        end

        -- 加上波次间等待时间（每波约 3-5 秒间隔）
        local totalTime = clearTime + WAVES_PER_STAGE * 3

        if timeUsed + totalTime > offlineSeconds then
            break
        end

        timeUsed = timeUsed + totalTime
        clearedStages = clearedStages + 1
        stage = stage + 1
    end

    -- 下一关耗时
    local nextStageTime = OP.EstimateStageClearTime(stage, squadDPS, armorPen)

    return clearedStages, timeUsed, nextStageTime
end

--- 完整的离线推关结算（带奖励发放）
---@return table|nil result { pushed, newBestStage, rewards, ... }
function OP.CalcOfflinePushRewards()
    local lastTime = HeroData.lastSaveTime or 0
    if lastTime <= 0 then return nil end

    local now = os.time()
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
        -- 每关通关奖励虚空契约
        if s % 5 == 0 then
            totalVoidPact = totalVoidPact + 1
        end
    end

    -- 离线推关效率系数（低于实战挂机）
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
function OP.ClaimPushRewards(result)
    if not result or result.pushed <= 0 then return end

    local Currency = require("Game.Currency")

    -- 劳动加倍
    local ok, LaborDayData = pcall(require, "Game.LaborDayData")
    local laborMult = 1
    if ok and LaborDayData and LaborDayData.ConsumeDouble then
        laborMult = LaborDayData.ConsumeDouble()
    end

    local rewards = result.stageRewards
    rewards.nether_crystal = math.floor((rewards.nether_crystal or 0) * laborMult)
    rewards.devour_stone   = math.floor((rewards.devour_stone or 0) * laborMult)
    rewards.forge_iron     = math.floor((rewards.forge_iron or 0) * laborMult)

    Currency.Add("nether_crystal", rewards.nether_crystal)
    Currency.Add("devour_stone", rewards.devour_stone)
    Currency.Add("forge_iron", rewards.forge_iron)
    if rewards.void_pact and rewards.void_pact > 0 then
        Currency.Add("void_pact", rewards.void_pact)
    end

    -- 更新 bestStage
    HeroData.stats.bestStage = result.newBestStage
    -- 更新 bestGlobalWave
    HeroData.stats.bestGlobalWave = result.newBestStage * Config.WAVES_PER_STAGE

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
    local leaderDPS = CalcLeaderDPS()
    local heroDPSList = {}
    local deployed = HeroData.deployed or {}

    for _, heroId in ipairs(deployed) do
        local dps = CalcHeroDPS(heroId, IDEAL_FIELD_STAR)
        heroDPSList[#heroDPSList + 1] = {
            heroId = heroId,
            singleDPS = dps,
            totalDPS = dps * TOWERS_PER_HERO,
        }
    end

    local baseDPS = leaderDPS
    for _, h in ipairs(heroDPSList) do
        baseDPS = baseDPS + h.totalDPS
    end

    local zones = CollectSquadZones()
    local zoneMult = (1 + zones.dmgBonus) * (1 + zones.typeDmg) * (1 + zones.vuln) * (1 + zones.chillAmp)
    local totalDPS = baseDPS * zoneMult * OFFLINE_EFFICIENCY

    return {
        totalDPS = totalDPS,
        leaderDPS = leaderDPS,
        heroDPS = heroDPSList,
        fieldStar = IDEAL_FIELD_STAR,
        efficiency = OFFLINE_EFFICIENCY,
        zones = zones,
    }
end

return OP
