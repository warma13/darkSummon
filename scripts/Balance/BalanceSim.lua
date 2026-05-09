------------------------------------------------------------------------
-- BalanceSim.lua  —  离线平衡模拟器 入口 & 编排器
-- 用法: require("Balance.BalanceSim").Run()
-- updated: dual tierMult (Boss + Minion)
------------------------------------------------------------------------
local BalanceSim = {}

local HeroProfile    = require "Balance.HeroProfile"
local MonsterEHP     = require "Balance.MonsterEHP"
local HeroDPS        = require "Balance.HeroDPS"
local Sensitivity    = require "Balance.Sensitivity"
local Report         = require "Balance.Report"
local RelicAnalysis  = require "Balance.RelicAnalysis"
local CrimsonMoonAnalysis = require "Balance.CrimsonMoonAnalysis"

local Config   = require "Game.Config"
local Balance  = Config.Balance

------------------------------------------------------------
-- 预设基准参数
------------------------------------------------------------

--- 中期基准英雄参数
local function midGameBaseline(heroId)
    -- 中期基准: 武器已改为pct, equipAtk(flat)=0
    -- 武器贡献约0.10 (与其他装备属性对齐)
    return {
        heroId       = heroId or "shadow_mage",
        level        = 1000,
        star         = 10,
        advanceLevel = 5,
        battleStar   = 3,
        equipAtk     = 0,            -- 武器已改为pct，flat=0
        atkPctBonus  = 0.10 + 0.10,  -- 符文等0.10 + 武器pct 0.10
        relicAtkPct  = 0.10,
        relicSpdPct  = 0.05,
        relicCritDmgPct = 0.10,
        equipArmorPen  = 0.10,   -- 百分比 (符文+遗物+天赋, 与 Combat.lua 一致)
        equipCritRate  = 0.10,
        equipCritDmg   = 0.20,
        equipDmgBonus  = 0.10,
        spdPctBonus  = 0,
        elemDmg      = 0.10,
        elemMastery  = 0,
        isLeader     = false,
    }
end

--- 中期基准怪物参数
local function midGameMonster()
    return {
        stageNum    = 1000,
        waveInStage = 1,
        roleId      = "minion",
    }
end

------------------------------------------------------------
-- 报告 1: 六稀有度基准对比
------------------------------------------------------------

function BalanceSim.ReportRarityComparison()
    Report.Header("报告 1: 六稀有度基准对比 (Lv1000, ★10, Adv5, B★3)")

    local rarities = { "N", "R", "SR", "SSR", "UR", "LR" }
    -- 为每种稀有度选一个代表英雄
    local repHeroes = {}
    local heroByRarity = {}
    for heroId, rarity in pairs(Config.HERO_RARITY or {}) do
        if not heroByRarity[rarity] then
            heroByRarity[rarity] = heroId
        end
    end

    local headers = { "稀有度", "英雄", "finalAtk", "间隔(s)", "Raw DPS", "Eff DPS", "Kill(s)", "PowerMult" }
    local colWidths = { 8, 20, 12, 8, 12, 12, 8, 12 }
    local numCols = { [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
    local rows = {}

    for _, rarity in ipairs(rarities) do
        local heroId = heroByRarity[rarity]
        if heroId then
            local params = midGameBaseline(heroId)
            local result = HeroDPS.Calc(params, midGameMonster())
            local pm = HeroProfile.PowerMult(params.level, params.star, params.advanceLevel, rarity)

            rows[#rows + 1] = {
                rarity,
                heroId,
                Report.FormatInt(result.profile.finalAtk),
                Report.Fixed(result.profile.attackInterval, 3),
                Report.FormatInt(result.rawDPS),
                Report.FormatInt(result.effectiveDPS),
                Report.Fixed(result.killTime, 2),
                Report.Fixed(pm, 2),
            }
        end
    end

    Report.Table(headers, rows, colWidths, numCols)

    -- 交叉验证
    print("")
    print("  [ 交叉验证: PowerMult vs Config_Balance.ExpectedHeroPowerMult ]")
    if Balance.ExpectedHeroPowerMult then
        for _, rarity in ipairs(rarities) do
            local pm1 = HeroProfile.PowerMult(1000, 10, 5, rarity)
            local pm2 = Balance.ExpectedHeroPowerMult(1000, 10, 5, rarity)
            local match = math.abs(pm1 - pm2) < 0.01 and "OK" or "MISMATCH!"
            print(string.format("    %s: sim=%.4f  cfg=%.4f  [%s]", rarity, pm1, pm2, match))
        end
    else
        print("    (Config_Balance.ExpectedHeroPowerMult 不可用, 跳过)")
    end
end

------------------------------------------------------------
-- 报告 2: DPS vs EHP 曲线 (每 500 关采样)
------------------------------------------------------------

function BalanceSim.ReportDPSvsEHP()
    Report.Header("报告 2: 典型英雄 DPS vs 关卡 EHP 曲线")

    local heroId = "shadow_mage"
    local stages = { 1, 100, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000 }

    -- 英雄属性随关卡"成长" (模拟玩家养成进度)
    local function heroParamsAtStage(stage)
        local progress = math.min(1.0, (stage - 1) / 5999)  -- 0~1 线性进度
        -- 武器已改为百分比（EQUIP_STAT_BASE.atk=0.002, 满级4000×红色5.0=40%）
        -- 武器份额 progress*0.40 合并到 atkPctBonus，equipAtk(flat)=0
        return {
            heroId       = heroId,
            level        = math.floor(1 + progress * 5999),
            star         = math.floor(progress * 30),
            advanceLevel = math.floor(progress * 20),
            battleStar   = math.min(5, 1 + math.floor(progress * 5)),
            equipAtk     = 0,                       -- 武器已改为pct，flat=0
            atkPctBonus  = progress * 0.30 + progress * 0.40,  -- 符文0.30 + 武器pct 0.40
            relicAtkPct  = progress * 0.20,
            relicSpdPct  = progress * 0.10,
            relicCritDmgPct = progress * 0.30,
            equipArmorPen  = math.min(0.80, progress * 0.60),  -- 百分比, 最高 ~60% (符文+遗物+天赋)
            equipCritRate  = math.min(0.50, progress * 0.50),
            equipCritDmg   = progress * 1.50,
            equipDmgBonus  = progress * 0.40,
            elemDmg      = progress * 0.30,
            elemMastery  = progress * 0.10,
            isLeader     = false,
        }
    end

    local headers = { "关卡", "Lv", "★", "Raw DPS", "Eff DPS", "怪物 EHP", "DPS/EHP", "Kill(s)" }
    local colWidths = { 6, 6, 4, 14, 14, 16, 10, 8 }
    local numCols = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
    local rows = {}

    for _, stage in ipairs(stages) do
        local hp = heroParamsAtStage(stage)
        local result = HeroDPS.Calc(hp, { stageNum = stage, waveInStage = 1, roleId = "minion" })

        rows[#rows + 1] = {
            stage,
            hp.level,
            hp.star,
            Report.FormatInt(result.rawDPS),
            Report.FormatInt(result.effectiveDPS),
            Report.FormatInt(result.monster.effectiveHP),
            Report.Fixed(result.dpsEhpRatio, 4),
            Report.Fixed(result.killTime, 2),
        }
    end

    Report.Table(headers, rows, colWidths, numCols)
end

------------------------------------------------------------
-- 报告 3: 成长系统敏感度分析
------------------------------------------------------------

function BalanceSim.ReportSensitivity()
    local baseline = midGameBaseline("shadow_mage")
    local monster  = midGameMonster()

    local results = Sensitivity.ScanAll(baseline, monster)

    Sensitivity.PrintReport(results)

    local ranks = Sensitivity.Rank(results)
    Sensitivity.PrintRank(ranks)
end

------------------------------------------------------------
-- 报告 5: 怪物角色 EHP 对比
------------------------------------------------------------

function BalanceSim.ReportMonsterRoles()
    Report.Header("报告 5: 怪物角色 EHP 对比 (关卡 1000, wave 1)")

    local roleIds = {}
    for roleId, _ in pairs(Config.ENEMY_ROLES or {}) do
        roleIds[#roleIds + 1] = roleId
    end
    table.sort(roleIds)

    local heroParams = midGameBaseline("shadow_mage")

    local headers = { "角色", "baseHP", "baseDEF", "Raw HP", "Raw DEF", "EHP", "DEF占比" }
    local colWidths = { 12, 10, 10, 14, 10, 16, 10 }
    local numCols = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true }
    local rows = {}
    local maxEHP = 0

    local results = {}
    for _, roleId in ipairs(roleIds) do
        local role = Config.ENEMY_ROLES[roleId]
        local result = HeroDPS.Calc(heroParams, {
            stageNum = 1000, waveInStage = 1, roleId = roleId,
        })
        results[#results + 1] = { roleId = roleId, role = role, result = result }
        if result.monster.effectiveHP > maxEHP then
            maxEHP = result.monster.effectiveHP
        end
    end

    -- 按 EHP 降序
    table.sort(results, function(a, b) return a.result.monster.effectiveHP > b.result.monster.effectiveHP end)

    for _, r in ipairs(results) do
        local m = r.result.monster
        local defContrib = m.defFactor > 0 and ((m.defFactor - 1) / m.defFactor * 100) or 0

        rows[#rows + 1] = {
            r.roleId,
            Report.FormatInt(r.role.baseHP),
            Report.FormatInt(r.role.baseDEF or 0),
            Report.FormatInt(m.rawHP),
            Report.FormatInt(m.rawDEF),
            Report.FormatInt(m.effectiveHP),
            Report.Fixed(defContrib, 1) .. "%",
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    -- 条形图
    print("")
    print("  [ EHP 条形图 ]")
    for _, r in ipairs(results) do
        Report.Bar(r.roleId, r.result.monster.effectiveHP, maxEHP, 40)
    end

    Report.Separator()
end

------------------------------------------------------------
-- 报告 6: Boss vs 小怪 HP 分析 + tierMult 敏感度
------------------------------------------------------------

function BalanceSim.ReportBossAnalysis()
    local curBossExp   = Config.BOSS_TIER_EXPONENT   or 1.50
    local curMinionExp = Config.MINION_TIER_EXPONENT or 1.00
    Report.Header(string.format("报告 6: Boss vs 小怪 HP 分析 (Boss^%.2f / Minion^%.2f)", curBossExp, curMinionExp))

    local FormatUtil = require "Game.FormatUtil"

    -- ---- 6a. Boss 原始 HP 曲线 + Boss/Minion 比值 ----
    local stages = { 100, 500, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000 }

    print("")
    print("  [ 6a. Boss 原始 HP 曲线 & Boss/Minion 比值 ]")
    print("")

    local headers = { "关卡", "Boss层级", "tierMult", "小怪HP", "Boss HP", "Boss/小怪" }
    local colWidths = { 6, 8, 14, 14, 16, 14 }
    local numCols = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }
    local rows = {}

    for _, stage in ipairs(stages) do
        local minionHP = MonsterEHP.RawHP(stage, "minion", 1)
        local bossHP, detail = MonsterEHP.BossRawHP(stage)
        local ratio = bossHP / math.max(1, minionHP)

        rows[#rows + 1] = {
            stage,
            detail.bossTier,
            FormatUtil.FormatNumber(detail.tierMult),
            FormatUtil.FormatNumber(minionHP),
            FormatUtil.FormatNumber(bossHP),
            FormatUtil.FormatNumber(ratio) .. "x",
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    -- ---- 6b. Boss EHP vs 英雄 DPS (能不能打得过) ----
    print("")
    print("  [ 6b. Boss EHP vs 英雄 DPS (击杀时间) ]")
    print("")

    -- 复用 ReportDPSvsEHP 的英雄成长函数
    local function heroParamsAtStage(stage)
        local progress = math.min(1.0, (stage - 1) / 9999)
        return {
            heroId       = "shadow_mage",
            level        = math.floor(1 + progress * 5999),
            star         = math.floor(progress * 30),
            advanceLevel = math.floor(progress * 20),
            battleStar   = math.min(5, 1 + math.floor(progress * 5)),
            equipAtk     = 0,
            atkPctBonus  = progress * 0.30 + progress * 0.40,
            relicAtkPct  = progress * 0.20,
            relicSpdPct  = progress * 0.10,
            relicCritDmgPct = progress * 0.30,
            equipArmorPen  = math.min(0.80, progress * 0.60),
            equipCritRate  = math.min(0.50, progress * 0.50),
            equipCritDmg   = progress * 1.50,
            equipDmgBonus  = progress * 0.40,
            elemDmg      = progress * 0.30,
            elemMastery  = progress * 0.10,
            isLeader     = false,
        }
    end

    local headers2 = { "关卡", "英雄DPS", "小怪EHP", "小怪Kill(s)", "BossEHP", "Boss Kill(s)", "Boss/小怪Kill" }
    local colWidths2 = { 6, 14, 16, 12, 18, 14, 14 }
    local numCols2 = { [1]=true, [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true }
    local rows2 = {}

    for _, stage in ipairs(stages) do
        local hp = heroParamsAtStage(stage)
        local profile = HeroProfile.Build(hp)
        local rawDPS = profile.finalAtk / profile.attackInterval

        -- 小怪 EHP
        local minionResult = MonsterEHP.Calc({
            stageNum = stage, waveInStage = 1, roleId = "minion",
            heroDamage = profile.finalAtk,
            armorPen   = profile.armorPen,
            critRate   = profile.critRate,
            critDmg    = profile.critDmg,
            dmgBonus   = profile.dmgBonus,
            elemDmg    = profile.elemDmg,
            elemMastery = profile.elemMastery,
        })

        -- Boss EHP
        local bossResult = MonsterEHP.BossCalc({
            stageNum = stage,
            heroDamage = profile.finalAtk,
            armorPen   = profile.armorPen,
            critRate   = profile.critRate,
            critDmg    = profile.critDmg,
            dmgBonus   = profile.dmgBonus,
            elemDmg    = profile.elemDmg,
            elemMastery = profile.elemMastery,
        })

        local minionKill = minionResult.effectiveHP / rawDPS
        local bossKill = bossResult.effectiveHP / rawDPS
        local killRatio = bossKill / math.max(0.001, minionKill)

        rows2[#rows2 + 1] = {
            stage,
            FormatUtil.FormatNumber(rawDPS),
            FormatUtil.FormatNumber(minionResult.effectiveHP),
            Report.Fixed(minionKill, 1) .. "s",
            FormatUtil.FormatNumber(bossResult.effectiveHP),
            FormatUtil.FormatNumber(bossKill) .. "s",
            FormatUtil.FormatNumber(killRatio) .. "x",
        }
    end

    Report.Table(headers2, rows2, colWidths2, numCols2)

    -- ---- 6c. tierMult 指数敏感度分析 ----
    print("")
    print("  [ 6c. tierMult 指数敏感度分析 ]")
    print(string.format("  当前配置值: Boss=%.2f, Minion=%.2f, 差值=%.2f", curBossExp, curMinionExp, curBossExp - curMinionExp))
    print("  对比 Boss 指数: 0.50, 0.75, 1.00, 1.50, 2.25 (Minion 指数固定)")
    print("")

    local exponents = { 0.50, 0.75, 1.00, 1.50, 2.25 }
    local sampleStages = { 100, 500, 1000, 2000, 5000, 10000 }

    -- 表头: 关卡 + 每个指数的 Boss HP
    local headers3 = { "关卡" }
    for _, exp in ipairs(exponents) do
        local label = string.format("^%.2f", exp)
        if math.abs(exp - curBossExp) < 0.001 then label = label .. " *" end
        headers3[#headers3 + 1] = label
    end
    local colWidths3 = { 6 }
    local numCols3 = { [1] = true }
    for i = 1, #exponents do
        colWidths3[#colWidths3 + 1] = 16
        numCols3[i + 1] = true
    end
    local rows3 = {}

    for _, stage in ipairs(sampleStages) do
        local row = { stage }
        for _, exp in ipairs(exponents) do
            local bossHP = MonsterEHP.BossRawHP(stage, exp)
            row[#row + 1] = FormatUtil.FormatNumber(bossHP)
        end
        rows3[#rows3 + 1] = row
    end

    Report.Table(headers3, rows3, colWidths3, numCols3)

    -- Boss/Minion 比值随指数变化
    print("")
    print("  [ 6d. Boss/Minion HP 比值 随指数变化 ]")
    print("")

    local headers4 = { "关卡" }
    for _, exp in ipairs(exponents) do
        local label = string.format("^%.2f", exp)
        if math.abs(exp - curBossExp) < 0.001 then label = label .. " *" end
        headers4[#headers4 + 1] = label
    end
    local colWidths4 = { 6 }
    local numCols4 = { [1] = true }
    for i = 1, #exponents do
        colWidths4[#colWidths4 + 1] = 14
        numCols4[i + 1] = true
    end
    local rows4 = {}

    for _, stage in ipairs(sampleStages) do
        local minionHP = MonsterEHP.RawHP(stage, "minion", 1)
        local row = { stage }
        for _, exp in ipairs(exponents) do
            local bossHP = MonsterEHP.BossRawHP(stage, exp)
            local ratio = bossHP / math.max(1, minionHP)
            row[#row + 1] = FormatUtil.FormatNumber(ratio) .. "x"
        end
        rows4[#rows4 + 1] = row
    end

    Report.Table(headers4, rows4, colWidths4, numCols4)

    -- ---- 总结 ----
    print("")
    print("  [ 分析总结 ]")
    print("")
    print(string.format("  1. Boss 和小怪均有 tierMult: Boss^%.2f / Minion^%.2f", curBossExp, curMinionExp))
    print(string.format("  2. Boss/小怪 HP 比值 (差值指数 %.2f)：", curBossExp - curMinionExp))
    local ratio1k = MonsterEHP.BossRawHP(1000) / math.max(1, MonsterEHP.RawHP(1000, "minion", 1))
    local ratio5k = MonsterEHP.BossRawHP(5000) / math.max(1, MonsterEHP.RawHP(5000, "minion", 1))
    local ratio10k = MonsterEHP.BossRawHP(10000) / math.max(1, MonsterEHP.RawHP(10000, "minion", 1))
    print(string.format("     关卡 1000: Boss/小怪 = %s", FormatUtil.FormatNumber(ratio1k)))
    print(string.format("     关卡 5000: Boss/小怪 = %s", FormatUtil.FormatNumber(ratio5k)))
    print(string.format("     关卡10000: Boss/小怪 = %s", FormatUtil.FormatNumber(ratio10k)))
    local diffExp = curBossExp - curMinionExp
    local fluctuation = math.floor(ratio10k / math.max(1, ratio1k) + 0.5)
    print(string.format("  3. 差值指数 %.2f → 比值波动约 %dx", diffExp, fluctuation))
    if fluctuation <= 100 then
        print("     ✓ 波动可控，Boss/小怪平衡稳定")
    else
        print("     ⚠ 波动较大，建议缩小 Boss/Minion 指数差值")
    end

    Report.Separator()
end

------------------------------------------------------------
-- 入口: 运行所有报告
------------------------------------------------------------

function BalanceSim.Run()
    print("")
    print("================================================================")
    print("  暗黑塔防 - 离线平衡模拟器 v1.0")
    print("================================================================")
    print("")

    BalanceSim.ReportRarityComparison()
    BalanceSim.ReportDPSvsEHP()
    BalanceSim.ReportSensitivity()
    BalanceSim.ReportMonsterRoles()
    BalanceSim.ReportBossAnalysis()

    -- 遗物数值分析 (报告 7~12)
    RelicAnalysis.Run()

    -- 弦月专项分析 (报告 A~H)
    CrimsonMoonAnalysis.Run()

    print("")
    print("================================================================")
    print("  模拟完成")
    print("================================================================")
end

return BalanceSim
