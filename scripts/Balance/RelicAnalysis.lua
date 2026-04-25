------------------------------------------------------------------------
-- RelicAnalysis.lua  —  遗物数值分析模块
-- 逐件分析 20 件遗物的属性/技能/升级收益/搭配对比
-- 用法: require("Balance.RelicAnalysis").Run(heroParams, monsterParams)
------------------------------------------------------------------------
local RelicAnalysis = {}

local Config     = require "Game.Config"
local RelicCalc  = require "Game.RelicCalc"
local HeroDPS    = require "Balance.HeroDPS"
local HeroProfile = require "Balance.HeroProfile"
local Report     = require "Balance.Report"

------------------------------------------------------------
-- 工具: 模拟遗物对象
------------------------------------------------------------

--- 创建模拟遗物数据
---@param relicId string
---@param quality string  "green"/"blue"/"purple"/"orange"/"red"
---@param level number
---@param star number
---@return table { id, quality, level, star }
local function makeRelic(relicId, quality, level, star)
    return { id = relicId, quality = quality, level = level or 1, star = star or 0 }
end

--- 获取遗物被动加成（独立于 RelicData，纯计算）
--- 模拟 RelicData.GetPassiveBonus 但接受任意遗物组合
---@param equipped table { power=relic|nil, heart=relic|nil, eye=relic|nil, will=relic|nil }
---@return table { atkPct, spdPct, critDmgPct }
local function calcPassiveBonus(equipped)
    local bonus = { atkPct = 0, spdPct = 0, critDmgPct = 0 }

    -- 永恒意志全局增幅
    local globalAmp = 0
    local willR = equipped.will
    if willR and willR.id == "eternal_will" then
        local ewDef = Config.RELICS.eternal_will
        globalAmp = RelicCalc.V(willR, ewDef.params.globalAmplify)
        if ewDef.starEffect and ewDef.starEffect.type == "amplifyAdd" then
            globalAmp = globalAmp + RelicCalc.StarValue(willR.star, ewDef.starEffect)
        end
    end
    local ampMult = 1 + globalAmp

    -- 心部位被动
    local heartR = equipped.heart
    if heartR then
        local hDef = Config.RELICS[heartR.id]
        if hDef then
            local p = hDef.params
            if p.atkBonus then
                bonus.atkPct = bonus.atkPct + RelicCalc.V(heartR, p.atkBonus) * ampMult
            end
            if p.spdBonus then
                bonus.spdPct = bonus.spdPct + RelicCalc.V(heartR, p.spdBonus) * ampMult
            end
            if p.critDmgBonus then
                bonus.critDmgPct = bonus.critDmgPct + RelicCalc.V(heartR, p.critDmgBonus) * ampMult
            end
            -- 星级 critDmg
            if hDef.starEffect and hDef.starEffect.type == "critDmg" then
                bonus.critDmgPct = bonus.critDmgPct + RelicCalc.StarValue(heartR.star, hDef.starEffect)
            end
            -- 星级 critRate
            if hDef.starEffect and hDef.starEffect.type == "critRate" then
                bonus.critRatePct = (bonus.critRatePct or 0) + RelicCalc.StarValue(heartR.star, hDef.starEffect)
            end
            -- 万象归一红色遗物加成
            if heartR.id == "unity_of_all" then
                local redCount = 0
                for _, slot in pairs(equipped) do
                    if slot and slot.quality == "red" then redCount = redCount + 1 end
                end
                local extraPct = p.redRelicBonusPer * redCount
                if hDef.starEffect and hDef.starEffect.type == "redBonus" then
                    extraPct = extraPct + RelicCalc.StarValue(heartR.star, hDef.starEffect) * redCount
                end
                bonus.atkPct = bonus.atkPct + extraPct * ampMult
                bonus.spdPct = bonus.spdPct + extraPct * ampMult
                bonus.critDmgPct = bonus.critDmgPct + extraPct * ampMult
            end
        end
    end

    -- 力部位被动: void_pulse 攻击力加成
    local powerR = equipped.power
    if powerR and powerR.id == "void_pulse" then
        local pDef = Config.RELICS.void_pulse
        bonus.atkPct = bonus.atkPct + RelicCalc.V(powerR, pDef.params.atkBonus) * ampMult
    end

    -- 意志部位回退
    if willR then
        local wDef = Config.RELICS[willR.id]
        if wDef then
            local powerHasCharge = powerR and Config.RELICS[powerR.id]
                and Config.RELICS[powerR.id].hasCharge
            if willR.id == "rapid_charge" and not powerHasCharge then
                bonus.spdPct = bonus.spdPct + RelicCalc.V(willR, wDef.params.fallbackSpdBonus) * ampMult
            end
            if willR.id == "fervent_faith" and (not powerR or powerR.id == "void_pulse") then
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

--- 将遗物被动加成注入到英雄参数中，返回修改后的副本
---@param heroParams table
---@param bonus table { atkPct, spdPct, critDmgPct }
---@return table
local function applyBonus(heroParams, bonus)
    local p = {}
    for k, v in pairs(heroParams) do p[k] = v end
    p.relicAtkPct = bonus.atkPct
    p.relicSpdPct = bonus.spdPct
    p.relicCritDmgPct = bonus.critDmgPct
    return p
end

------------------------------------------------------------
-- 报告 6: 遗物被动属性总览
------------------------------------------------------------

function RelicAnalysis.ReportPassiveOverview(heroParams, monsterParams)
    Report.Header("报告 6: 遗物被动属性总览 (单件独立效果)")

    local qualities = { "green", "blue", "purple", "orange", "red" }
    local qualityNames = { green = "精良", blue = "稀有", purple = "史诗", orange = "传说", red = "神话" }
    local testLevels = { { lv = 1, star = 0 }, { lv = 10, star = 3 }, { lv = 20, star = 5 } }

    -- 基准 DPS（无遗物）
    local baseParams = applyBonus(heroParams, { atkPct = 0, spdPct = 0, critDmgPct = 0 })
    local baseResult = HeroDPS.Calc(baseParams, monsterParams)
    local baseDPS = baseResult.effectiveDPS

    print(string.format("  基准 DPS (无遗物): %s", Report.FormatInt(baseDPS)))
    print("")

    -- 按部位遍历
    for _, slotDef in ipairs(Config.RELIC_SLOTS) do
        local slotId = slotDef.id
        print(string.format("\n  ═══ %s (%s) ═══", slotDef.name, slotId))

        local slotRelics = Config.RELICS_BY_SLOT[slotId] or {}
        table.sort(slotRelics, function(a, b)
            return (Config.RELIC_QUALITY_INDEX[a.minQuality] or 0)
                 < (Config.RELIC_QUALITY_INDEX[b.minQuality] or 0)
        end)

        local headers = { "遗物", "品质", "Lv/★", "攻击%", "速度%", "暴伤%", "Eff DPS", "ΔDPS%" }
        local colWidths = { 14, 6, 8, 8, 8, 8, 14, 8 }
        local numCols = { [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
        local rows = {}

        for _, rDef in ipairs(slotRelics) do
            -- 使用该遗物的最低品质
            local q = rDef.minQuality
            for _, tl in ipairs(testLevels) do
                local relic = makeRelic(rDef.id, q, tl.lv, tl.star)
                local equipped = { [slotId] = relic }
                local bonus = calcPassiveBonus(equipped)

                local hp = applyBonus(heroParams, bonus)
                local result = HeroDPS.Calc(hp, monsterParams)
                local dpsGain = baseDPS > 0 and ((result.effectiveDPS / baseDPS - 1) * 100) or 0

                rows[#rows + 1] = {
                    rDef.name,
                    qualityNames[q] or q,
                    string.format("L%d★%d", tl.lv, tl.star),
                    Report.Fixed(bonus.atkPct * 100, 1),
                    Report.Fixed(bonus.spdPct * 100, 1),
                    Report.Fixed(bonus.critDmgPct * 100, 1),
                    Report.FormatInt(result.effectiveDPS),
                    Report.Fixed(dpsGain, 1),
                }
            end
        end

        Report.Table(headers, rows, colWidths, numCols)
    end

    Report.Separator()
end

------------------------------------------------------------
-- 报告 7: 力部位技能伤害模拟
------------------------------------------------------------

function RelicAnalysis.ReportPowerSkillDPS(heroParams, monsterParams)
    Report.Header("报告 7: 力部位技能伤害模拟 (单次释放)")

    -- 构建英雄属性快照获取 finalAtk
    local profile = HeroProfile.Build(heroParams)
    local topAtk = profile.finalAtk

    print(string.format("  基准最强英雄 ATK: %s", Report.FormatInt(topAtk)))
    print("")

    local qualities = { "green", "blue", "purple", "orange", "red" }
    local qualityNames = { green = "精良", blue = "稀有", purple = "史诗", orange = "传说", red = "神话" }
    local testLevels = { { lv = 1, star = 0 }, { lv = 10, star = 3 }, { lv = 20, star = 5 } }

    local powerRelics = Config.RELICS_BY_SLOT.power or {}
    table.sort(powerRelics, function(a, b)
        return (Config.RELIC_QUALITY_INDEX[a.minQuality] or 0)
             < (Config.RELIC_QUALITY_INDEX[b.minQuality] or 0)
    end)

    local headers = { "遗物", "品质", "Lv/★", "类型", "倍率", "单击伤害", "充能上限", "DPS等效" }
    local colWidths = { 12, 6, 8, 8, 8, 14, 8, 14 }
    local numCols = { [5] = true, [6] = true, [7] = true, [8] = true }
    local rows = {}

    for _, rDef in ipairs(powerRelics) do
        local q = rDef.minQuality
        for _, tl in ipairs(testLevels) do
            local relic = makeRelic(rDef.id, q, tl.lv, tl.star)
            local p = rDef.params

            local dmgType = rDef.hasCharge and "充能" or "被动"
            local totalDmg = 0
            local mult = 0

            if rDef.id == "judgment_spear" then
                mult = RelicCalc.V(relic, p.damageMult)
                totalDmg = topAtk * mult
            elseif rDef.id == "void_pulse" then
                mult = RelicCalc.V(relic, p.pulseDamageMult)
                totalDmg = topAtk * mult  -- 基于全体平均，简化为 topAtk
            elseif rDef.id == "annihilation_storm" then
                mult = RelicCalc.V(relic, p.damageMult)
                totalDmg = topAtk * mult
            elseif rDef.id == "fate_reaper" then
                mult = RelicCalc.V(relic, p.nonExecuteDmg)
                totalDmg = topAtk * mult  -- 非斩杀情况
            elseif rDef.id == "end_light" then
                local trueMult = RelicCalc.V(relic, p.trueDamageMult)
                local burnMult = RelicCalc.V(relic, p.burnTotalMult)
                mult = trueMult + burnMult
                totalDmg = topAtk * mult
            end

            -- 充能上限（含星级减少）
            local chargeMax = Config.RELIC_CHARGE_MAX
            if rDef.hasCharge then
                chargeMax = RelicCalc.GetEffectiveChargeMax(relic, 0)
            end

            -- DPS 等效：假设攻速 1.0s，1次攻击 = 1 充能
            -- 释放周期 ≈ chargeMax 秒 → DPS = totalDmg / chargeMax
            local dpsEquiv = 0
            if rDef.hasCharge then
                dpsEquiv = chargeMax > 0 and (totalDmg / chargeMax) or 0
            else
                -- void_pulse 按间隔计算
                local interval = RelicCalc.V(relic, p.pulseInterval or 10)
                -- 星级减少间隔
                if rDef.starEffect and rDef.starEffect.type == "intervalReduce" then
                    interval = interval - RelicCalc.StarValue(relic.star, rDef.starEffect)
                end
                interval = math.max(1, interval)
                dpsEquiv = totalDmg / interval
            end

            rows[#rows + 1] = {
                rDef.name,
                qualityNames[q] or q,
                string.format("L%d★%d", tl.lv, tl.star),
                dmgType,
                Report.Fixed(mult, 2),
                Report.FormatInt(totalDmg),
                rDef.hasCharge and tostring(chargeMax) or "-",
                Report.FormatInt(dpsEquiv),
            }
        end
    end

    Report.Table(headers, rows, colWidths, numCols)
    Report.Separator()
end

------------------------------------------------------------
-- 报告 8: 品质对比 (同一遗物不同品质)
------------------------------------------------------------

function RelicAnalysis.ReportQualityScaling(heroParams, monsterParams)
    Report.Header("报告 8: 品质缩放对比 (Lv10 ★3)")

    local qualities = { "green", "blue", "purple", "orange", "red" }
    local qualityNames = { green = "精良", blue = "稀有", purple = "史诗", orange = "传说", red = "神话" }

    -- 基准
    local baseParams = applyBonus(heroParams, { atkPct = 0, spdPct = 0, critDmgPct = 0 })
    local baseResult = HeroDPS.Calc(baseParams, monsterParams)
    local baseDPS = baseResult.effectiveDPS

    -- 选几个代表性遗物
    local testRelics = {
        { id = "life_torrent",  slot = "heart", name = "生命洪流 (心)" },
        { id = "unity_of_all",  slot = "heart", name = "万象归一 (心)" },
        { id = "void_pulse",    slot = "power", name = "虚空脉冲 (力)" },
    }

    for _, tr in ipairs(testRelics) do
        print(string.format("\n  >>> %s <<<", tr.name))

        local headers = { "品质", "倍率", "攻击%", "速度%", "暴伤%", "Eff DPS", "ΔDPS%" }
        local colWidths = { 8, 8, 8, 8, 8, 14, 8 }
        local numCols = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true }
        local rows = {}

        for _, q in ipairs(qualities) do
            local relic = makeRelic(tr.id, q, 10, 3)
            local equipped = { [tr.slot] = relic }
            local bonus = calcPassiveBonus(equipped)

            local hp = applyBonus(heroParams, bonus)
            local result = HeroDPS.Calc(hp, monsterParams)
            local dpsGain = baseDPS > 0 and ((result.effectiveDPS / baseDPS - 1) * 100) or 0

            local qMult = Config.RELIC_QUALITY_MULT[q] or 1

            rows[#rows + 1] = {
                qualityNames[q],
                Report.Fixed(qMult, 1),
                Report.Fixed(bonus.atkPct * 100, 1),
                Report.Fixed(bonus.spdPct * 100, 1),
                Report.Fixed(bonus.critDmgPct * 100, 1),
                Report.FormatInt(result.effectiveDPS),
                Report.Fixed(dpsGain, 1),
            }
        end

        Report.Table(headers, rows, colWidths, numCols)
    end

    Report.Separator()
end

------------------------------------------------------------
-- 报告 9: 升级收益曲线 (等级 1→30)
------------------------------------------------------------

function RelicAnalysis.ReportUpgradeCurve()
    Report.Header("报告 9: 升级/升星投资收益")

    print("  ── 升级费用曲线 (遗物精华) ──")
    local headers1 = { "等级", "单次费用", "累计费用", "数值加成" }
    local colWidths1 = { 6, 10, 12, 10 }
    local numCols1 = { [1] = true, [2] = true, [3] = true, [4] = true }
    local rows1 = {}
    local cumCost = 0
    local sampleLevels = { 1, 5, 10, 15, 20, 25, 30, 40, 50 }

    for _, lv in ipairs(sampleLevels) do
        -- 累计费用
        local totalCost = 0
        for l = 1, lv - 1 do
            totalCost = totalCost + RelicCalc.GetUpgradeCost(l)
        end
        local lvCost = RelicCalc.GetUpgradeCost(lv)
        local lvMult = 1 + (lv - 1) * 0.05

        rows1[#rows1 + 1] = {
            lv,
            Report.FormatInt(lvCost),
            Report.FormatInt(totalCost),
            Report.Fixed(lvMult, 2) .. "x",
        }
    end
    Report.Table(headers1, rows1, colWidths1, numCols1)

    print("")
    print("  ── 升星碎片费用 ──")
    local headers2 = { "目标★", "碎片费用", "累计碎片", "示例效果" }
    local colWidths2 = { 8, 10, 10, 30 }
    local numCols2 = { [1] = true, [2] = true, [3] = true }
    local rows2 = {}
    local cumShards = 0

    -- 使用 chargeReduce 类型示例 (max=15, halfStar=4)
    local exStarEffect = { type = "chargeReduce", max = 15, halfStar = 4 }

    for star = 1, 10 do
        local cost = RelicCalc.GetStarUpShardCost(star - 1)
        cumShards = cumShards + cost
        local sv = RelicCalc.StarValue(star, exStarEffect)

        rows2[#rows2 + 1] = {
            "★" .. star,
            cost,
            cumShards,
            string.format("充能减少 %.1f (max=15)", sv),
        }
    end
    Report.Table(headers2, rows2, colWidths2, numCols2)

    Report.Separator()
end

------------------------------------------------------------
-- 报告 10: 最优搭配模拟
------------------------------------------------------------

function RelicAnalysis.ReportOptimalCombo(heroParams, monsterParams)
    Report.Header("报告 10: 四部位最优搭配对比")

    -- 基准
    local baseParams = applyBonus(heroParams, { atkPct = 0, spdPct = 0, critDmgPct = 0 })
    local baseResult = HeroDPS.Calc(baseParams, monsterParams)
    local baseDPS = baseResult.effectiveDPS

    -- 测试配置: 神话品质 Lv20 ★5
    local testQ = "red"
    local testLv = 20
    local testStar = 5

    -- 每部位收集可选遗物
    local slotOptions = {}
    for _, slotDef in ipairs(Config.RELIC_SLOTS) do
        local sid = slotDef.id
        slotOptions[sid] = {}
        for _, rDef in ipairs(Config.RELICS_BY_SLOT[sid] or {}) do
            slotOptions[sid][#slotOptions[sid] + 1] = rDef.id
        end
    end

    -- 穷举一些典型搭配（全组合 5^4=625 太多，取每部位 top 选项）
    -- 先固定 心/眼/意志 = 最高品质遗物，扫描力部位
    local bestCombos = {}

    -- 为每个部位单独评估最佳遗物
    for _, slotDef in ipairs(Config.RELIC_SLOTS) do
        local sid = slotDef.id
        print(string.format("\n  ═══ %s (%s) - 红色品质 Lv%d ★%d ═══", slotDef.name, sid, testLv, testStar))

        local headers = { "遗物", "攻击%", "速度%", "暴伤%", "Eff DPS", "ΔDPS%" }
        local colWidths = { 14, 8, 8, 8, 14, 8 }
        local numCols = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }
        local rows = {}

        local slotBest = { dps = 0, relicId = nil }

        for _, relicId in ipairs(slotOptions[sid]) do
            local relic = makeRelic(relicId, testQ, testLv, testStar)
            local equipped = { [sid] = relic }
            local bonus = calcPassiveBonus(equipped)

            local hp = applyBonus(heroParams, bonus)
            local result = HeroDPS.Calc(hp, monsterParams)
            local dpsGain = baseDPS > 0 and ((result.effectiveDPS / baseDPS - 1) * 100) or 0

            local rDef = Config.RELICS[relicId]
            rows[#rows + 1] = {
                rDef.name,
                Report.Fixed(bonus.atkPct * 100, 1),
                Report.Fixed(bonus.spdPct * 100, 1),
                Report.Fixed(bonus.critDmgPct * 100, 1),
                Report.FormatInt(result.effectiveDPS),
                Report.Fixed(dpsGain, 1),
            }

            if result.effectiveDPS > slotBest.dps then
                slotBest.dps = result.effectiveDPS
                slotBest.relicId = relicId
            end
        end

        Report.Table(headers, rows, colWidths, numCols)
        bestCombos[sid] = slotBest.relicId
    end

    -- 综合最佳搭配
    print("\n  ═══ 综合最佳搭配 (纯被动 DPS) ═══")
    local bestEquipped = {}
    for sid, relicId in pairs(bestCombos) do
        if relicId then
            bestEquipped[sid] = makeRelic(relicId, testQ, testLv, testStar)
        end
    end
    local bestBonus = calcPassiveBonus(bestEquipped)
    local bestHP = applyBonus(heroParams, bestBonus)
    local bestResult = HeroDPS.Calc(bestHP, monsterParams)
    local bestGain = baseDPS > 0 and ((bestResult.effectiveDPS / baseDPS - 1) * 100) or 0

    print(string.format("  力: %s", bestCombos.power and Config.RELICS[bestCombos.power].name or "无"))
    print(string.format("  心: %s", bestCombos.heart and Config.RELICS[bestCombos.heart].name or "无"))
    print(string.format("  眼: %s", bestCombos.eye and Config.RELICS[bestCombos.eye].name or "无"))
    print(string.format("  志: %s", bestCombos.will and Config.RELICS[bestCombos.will].name or "无"))
    print(string.format("  总被动: 攻击+%.1f%% 速度+%.1f%% 暴伤+%.1f%%",
        bestBonus.atkPct * 100, bestBonus.spdPct * 100, bestBonus.critDmgPct * 100))
    print(string.format("  Eff DPS: %s (ΔDPS: +%.1f%%)", Report.FormatInt(bestResult.effectiveDPS), bestGain))

    Report.Separator()
end

------------------------------------------------------------
-- 报告 11: 意志部位联动分析
------------------------------------------------------------

function RelicAnalysis.ReportWillSynergy(heroParams, monsterParams)
    Report.Header("报告 11: 意志部位 × 力部位联动分析")

    local baseParams = applyBonus(heroParams, { atkPct = 0, spdPct = 0, critDmgPct = 0 })
    local baseResult = HeroDPS.Calc(baseParams, monsterParams)
    local baseDPS = baseResult.effectiveDPS

    local testQ = "red"
    local testLv = 20
    local testStar = 5

    local powerRelics = Config.RELICS_BY_SLOT.power or {}
    local willRelics = Config.RELICS_BY_SLOT.will or {}

    local headers = { "力部位", "意志部位", "攻击%", "速度%", "Eff DPS", "ΔDPS%" }
    local colWidths = { 12, 12, 8, 8, 14, 8 }
    local numCols = { [3] = true, [4] = true, [5] = true, [6] = true }
    local rows = {}

    for _, pDef in ipairs(powerRelics) do
        for _, wDef in ipairs(willRelics) do
            local pRelic = makeRelic(pDef.id, testQ, testLv, testStar)
            local wRelic = makeRelic(wDef.id, testQ, testLv, testStar)
            local equipped = { power = pRelic, will = wRelic }
            local bonus = calcPassiveBonus(equipped)

            local hp = applyBonus(heroParams, bonus)
            local result = HeroDPS.Calc(hp, monsterParams)
            local dpsGain = baseDPS > 0 and ((result.effectiveDPS / baseDPS - 1) * 100) or 0

            rows[#rows + 1] = {
                pDef.name,
                wDef.name,
                Report.Fixed(bonus.atkPct * 100, 1),
                Report.Fixed(bonus.spdPct * 100, 1),
                Report.FormatInt(result.effectiveDPS),
                Report.Fixed(dpsGain, 1),
            }
        end
    end

    Report.Table(headers, rows, colWidths, numCols)
    Report.Separator()
end

------------------------------------------------------------
-- 入口: 运行所有遗物分析
------------------------------------------------------------

--- 运行完整遗物分析
---@param heroParams table|nil  自定义英雄参数（nil 则使用中期基准）
---@param monsterParams table|nil
function RelicAnalysis.Run(heroParams, monsterParams)
    -- 默认中期基准
    heroParams = heroParams or {
        heroId       = "shadow_mage",
        level        = 1000,
        star         = 10,
        advanceLevel = 5,
        battleStar   = 3,
        equipAtk     = 0,
        atkPctBonus  = 0.10 + 0.10,
        relicAtkPct  = 0,   -- 清零，由遗物模拟注入
        relicSpdPct  = 0,
        relicCritDmgPct = 0,
        equipArmorPen  = 0.10,
        equipCritRate  = 0.10,
        equipCritDmg   = 0.20,
        equipDmgBonus  = 0.10,
        spdPctBonus  = 0,
        elemDmg      = 0.10,
        elemMastery  = 0,
        isLeader     = false,
    }
    monsterParams = monsterParams or {
        stageNum    = 1000,
        waveInStage = 1,
        roleId      = "minion",
    }

    print("")
    print("================================================================")
    print("  暗黑塔防 - 遗物数值分析 v1.0")
    print("================================================================")
    print("")

    RelicAnalysis.ReportPassiveOverview(heroParams, monsterParams)
    RelicAnalysis.ReportPowerSkillDPS(heroParams, monsterParams)
    RelicAnalysis.ReportQualityScaling(heroParams, monsterParams)
    RelicAnalysis.ReportUpgradeCurve()
    RelicAnalysis.ReportOptimalCombo(heroParams, monsterParams)
    RelicAnalysis.ReportWillSynergy(heroParams, monsterParams)

    print("")
    print("================================================================")
    print("  遗物分析完成")
    print("================================================================")
end

return RelicAnalysis
