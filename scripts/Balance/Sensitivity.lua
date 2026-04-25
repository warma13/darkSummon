------------------------------------------------------------------------
-- Sensitivity.lua  —  单变量敏感度分析 (控制变量法)
-- 固定 baseline 参数，逐一扫描各维度，输出 DPS 变化率
------------------------------------------------------------------------
local Sensitivity = {}

local HeroDPS = require "Balance.HeroDPS"
local Report  = require "Balance.Report"

------------------------------------------------------------
-- 扫描维度定义
------------------------------------------------------------

--- 默认扫描维度列表
Sensitivity.DIMENSIONS = {
    {
        name  = "等级 (level)",
        field = "level",
        range = { 1, 100, 500, 1000, 2000, 3000, 4000, 5000, 6000 },
    },
    {
        name  = "英雄星级 (star)",
        field = "star",
        range = { 0, 5, 10, 15, 20, 25, 30 },
    },
    {
        name  = "进阶 (advance)",
        field = "advanceLevel",
        range = { 0, 5, 10, 15, 20 },
    },
    {
        name  = "战斗星级 (battleStar)",
        field = "battleStar",
        range = { 1, 2, 3, 4, 5 },
    },
    {
        name  = "装备攻击 (equipAtk)",
        field = "equipAtk",
        range = { 0, 500, 1000, 2000, 5000, 10000 },
    },
    {
        name  = "暴击率 (critRate)",
        field = "equipCritRate",
        range = { 0, 0.05, 0.10, 0.20, 0.30, 0.50 },
    },
    {
        name  = "暴击伤害 (critDmg)",
        field = "equipCritDmg",
        range = { 0, 0.10, 0.30, 0.50, 1.00, 2.00 },
    },
    {
        name  = "护甲穿透 (armorPen)",
        field = "equipArmorPen",
        range = { 0, 0.05, 0.10, 0.20, 0.40, 0.60, 0.80 },  -- 百分比, 与 Combat.lua 一致
    },
    {
        name  = "伤害加成 (dmgBonus)",
        field = "equipDmgBonus",
        range = { 0, 0.05, 0.10, 0.20, 0.40, 0.80, 1.50 },
    },
    {
        name  = "元素伤害 (elemDmg)",
        field = "elemDmg",
        range = { 0, 0.05, 0.10, 0.20, 0.40, 0.80, 1.50 },
    },
    {
        name  = "攻击力% (atkPctBonus)",
        field = "atkPctBonus",
        range = { 0, 0.05, 0.10, 0.20, 0.40, 0.80, 1.50 },
    },
}

------------------------------------------------------------
-- 核心: 敏感度扫描
------------------------------------------------------------

--- 对单个维度做控制变量扫描
---@param baseline table      HeroProfile.Build 的 baseline 参数
---@param monsterParams table MonsterEHP.Calc 的参数
---@param dim table           维度定义 { name, field, range }
---@return table              { dim, rows = { {value, rawDPS, effectiveDPS, deltaRaw%, deltaEff%}, ... } }
function Sensitivity.ScanDimension(baseline, monsterParams, dim)
    local rows = {}
    local baseRawDPS, baseEffDPS

    for i, val in ipairs(dim.range) do
        -- 克隆 baseline 并覆盖当前维度
        local params = {}
        for k, v in pairs(baseline) do params[k] = v end
        params[dim.field] = val

        local result = HeroDPS.Calc(params, monsterParams)

        if i == 1 then
            baseRawDPS = result.rawDPS
            baseEffDPS = result.effectiveDPS
        end

        local deltaRaw = baseRawDPS > 0 and ((result.rawDPS / baseRawDPS - 1) * 100) or 0
        local deltaEff = baseEffDPS > 0 and ((result.effectiveDPS / baseEffDPS - 1) * 100) or 0

        rows[#rows + 1] = {
            value        = val,
            rawDPS       = result.rawDPS,
            effectiveDPS = result.effectiveDPS,
            deltaRawPct  = deltaRaw,
            deltaEffPct  = deltaEff,
        }
    end

    return {
        dim  = dim,
        rows = rows,
    }
end

--- 对所有维度做扫描
---@param baseline table
---@param monsterParams table
---@param dimensions table|nil  自定义维度列表，nil 则用默认
---@return table[]
function Sensitivity.ScanAll(baseline, monsterParams, dimensions)
    dimensions = dimensions or Sensitivity.DIMENSIONS
    local results = {}
    for _, dim in ipairs(dimensions) do
        results[#results + 1] = Sensitivity.ScanDimension(baseline, monsterParams, dim)
    end
    return results
end

------------------------------------------------------------
-- 打印敏感度报告
------------------------------------------------------------

function Sensitivity.PrintReport(results)
    Report.Header("敏感度分析 (控制变量法)")

    for _, scan in ipairs(results) do
        print("")
        print(string.format("  >>> %s <<<", scan.dim.name))

        local headers = { "值", "Raw DPS", "Eff DPS", "Δ Raw%", "Δ Eff%" }
        local colWidths = { 10, 14, 14, 10, 10 }
        local numCols = { [2] = true, [3] = true, [4] = true, [5] = true }
        local tableRows = {}

        for _, r in ipairs(scan.rows) do
            tableRows[#tableRows + 1] = {
                tostring(r.value),
                Report.FormatInt(r.rawDPS),
                Report.FormatInt(r.effectiveDPS),
                Report.Fixed(r.deltaRawPct, 1) .. "%",
                Report.Fixed(r.deltaEffPct, 1) .. "%",
            }
        end

        Report.Table(headers, tableRows, colWidths, numCols)
    end

    Report.Separator()
end

------------------------------------------------------------
-- 排名: 找出边际收益最高的维度
------------------------------------------------------------

--- 返回各维度从 min→max 的总 effectiveDPS 增幅排名
---@param results table[]  ScanAll 的结果
---@return table[]  { {name, totalGainPct}, ... } 按增幅降序
function Sensitivity.Rank(results)
    local ranks = {}
    for _, scan in ipairs(results) do
        local rows = scan.rows
        if #rows >= 2 then
            local gain = rows[#rows].deltaEffPct
            ranks[#ranks + 1] = {
                name         = scan.dim.name,
                totalGainPct = gain,
            }
        end
    end
    table.sort(ranks, function(a, b) return a.totalGainPct > b.totalGainPct end)
    return ranks
end

function Sensitivity.PrintRank(ranks)
    print("")
    print("  [ 维度总增幅排名 (从 min → max 的 Eff DPS 增幅) ]")
    local maxGain = ranks[1] and ranks[1].totalGainPct or 1
    for i, r in ipairs(ranks) do
        Report.Bar(
            string.format("#%d %s", i, r.name),
            r.totalGainPct,
            maxGain,
            30
        )
    end
end

return Sensitivity
