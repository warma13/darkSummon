------------------------------------------------------------------------
-- CrimsonMoonAnalysis.lua  —  弦月 (crimson_moon) 专项数值分析
-- 量化弦月的链式攻击、蚀月爆发、血月共鸣、觉醒态、月蚀领域
-- 各机制对 DPS 的理论贡献，并与同稀有度英雄对比
------------------------------------------------------------------------
local CMA = {}

local HeroProfile = require "Balance.HeroProfile"
local HeroDPS     = require "Balance.HeroDPS"
local MonsterEHP  = require "Balance.MonsterEHP"
local Report      = require "Balance.Report"
local Config      = require "Game.Config"
local Balance     = Config.Balance

------------------------------------------------------------------------
-- 弦月机制参数 (从 Config_Core + Config_Meta 提取)
------------------------------------------------------------------------
local P = {
    -- 基础
    baseAtk       = 4300,
    baseSpeed     = 0.85,     -- 攻击间隔（秒）
    chainCount    = 4,
    chainDecay    = 0.85,

    -- 被动1: 蚀月之链
    maxStacks     = 5,
    stackDuration = 8.0,
    dmgAmpPerStack = 0.04,    -- 每层 +4% 魔法增伤
    burstAtkPct   = 1.80,     -- 爆发倍率
    burstRange    = 60,

    -- 被动2: 血月共鸣
    resReduce          = 0.15,    -- 爆发时减魔抗
    resReduceDuration  = 3.0,
    spdPerStack        = 0.06,    -- 每层 +6% 攻速
    spdMaxStacks       = 5,
    spdDuration        = 4.0,

    -- 主动: 绯红新月
    activeCooldown     = 10.0,
    crescentDmgPct     = 3.50,    -- 全屏 350% ATK
    crescentMarks      = 3,       -- 施加 3 层印记
    awakenDuration     = 6.0,     -- 觉醒持续
    awakenAtkBuff      = 0.25,    -- 觉醒 +25% ATK
    awakenChainBonus   = 2,       -- 觉醒连锁 +2

    -- 被动3: 月蚀领域
    fieldAmp           = 0.12,    -- 领域内 +12% 魔法增伤
    soulAtkPerKill     = 0.03,    -- 每击杀 +3% ATK
    soulCap            = 0.30,    -- 上限 30%
    fullMoonDuration   = 5.0,     -- 满月持续
}

------------------------------------------------------------------------
-- 辅助: 中期基准参数（与 BalanceSim 一致）
------------------------------------------------------------------------
local function midGameBaseline(heroId)
    return {
        heroId       = heroId or "crimson_moon",
        level        = 1000,
        star         = 10,
        advanceLevel = 5,
        battleStar   = 3,
        equipAtk     = 0,
        atkPctBonus  = 0.10 + 0.10,
        relicAtkPct  = 0.10,
        relicSpdPct  = 0.05,
        relicCritDmgPct = 0.10,
        equipArmorPen  = 0.10,
        equipCritRate  = 0.10,
        equipCritDmg   = 0.20,
        equipDmgBonus  = 0.10,
        spdPctBonus  = 0,
        elemDmg      = 0.10,
        elemMastery  = 0,
        isLeader     = false,
    }
end

local function midGameMonster()
    return { stageNum = 1000, waveInStage = 1, roleId = "minion" }
end

------------------------------------------------------------------------
-- 报告 A: 链式攻击有效 DPS 乘数
------------------------------------------------------------------------
function CMA.ReportChainDPS()
    Report.Header("弦月分析 A: 链式攻击有效 DPS 乘数")

    -- 链式攻击: 主目标 100%, 后续每次 ×decay
    -- 总伤害 = 1 + decay + decay^2 + ... + decay^(n-1)
    -- 等比数列求和 = (1 - decay^n) / (1 - decay)

    local scenarios = {
        { name = "普通 (4链)", chains = P.chainCount, decay = P.chainDecay },
        { name = "觉醒 (6链)", chains = P.chainCount + P.awakenChainBonus, decay = P.chainDecay },
    }

    local headers = { "场景", "链数", "衰减", "总倍率", "等效DPS乘数", "vs单体" }
    local colWidths = { 14, 6, 8, 10, 14, 10 }
    local numCols = { [2]=true, [3]=true, [4]=true, [5]=true, [6]=true }
    local rows = {}

    for _, sc in ipairs(scenarios) do
        local totalMult = 0
        for i = 0, sc.chains - 1 do
            totalMult = totalMult + sc.decay ^ i
        end
        rows[#rows + 1] = {
            sc.name,
            sc.chains,
            Report.Fixed(sc.decay, 2),
            Report.Fixed(totalMult, 3),
            Report.Fixed(totalMult, 3) .. "x",
            Report.Fixed(totalMult, 2) .. "x",
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    -- 按链数变化图
    print("")
    print("  [ 链数 vs 总 DPS 乘数 (decay=" .. P.chainDecay .. ") ]")
    local maxMult = 0
    local chainData = {}
    for n = 1, 8 do
        local m = 0
        for i = 0, n - 1 do m = m + P.chainDecay ^ i end
        chainData[n] = m
        if m > maxMult then maxMult = m end
    end
    for n = 1, 8 do
        local label = n .. "链"
        if n == P.chainCount then label = label .. " *普通" end
        if n == P.chainCount + P.awakenChainBonus then label = label .. " *觉醒" end
        Report.Bar(label, chainData[n], maxMult, 30)
    end

    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 B: 蚀月爆发 DPS 循环分析
------------------------------------------------------------------------
function CMA.ReportEclipseCycle()
    Report.Header("弦月分析 B: 蚀月爆发循环 DPS")

    local params = midGameBaseline("crimson_moon")
    local profile = HeroProfile.Build(params)
    local atk = profile.finalAtk
    local interval = profile.attackInterval

    -- 普通状态: 每次攻击命中 1 目标（主链命中叠 1 层）
    -- 需要 5 次攻击叠满 5 层 → 触发爆发
    -- 觉醒状态: 每次叠 2 层 → 3 次攻击叠满

    local normalAttacksToFull = math.ceil(P.maxStacks / 1)
    local awakenAttacksToFull = math.ceil(P.maxStacks / 2)

    -- 循环时间 = 叠满所需攻击次数 × 攻击间隔
    local normalCycleTime = normalAttacksToFull * interval
    local awakenCycleTime = awakenAttacksToFull * interval

    -- 循环内总伤害 = 普攻伤害(含链) + 爆发伤害
    -- 普攻总链数伤害 per hit
    local chainMult = 0
    for i = 0, P.chainCount - 1 do
        chainMult = chainMult + P.chainDecay ^ i
    end
    local awakenChainMult = 0
    for i = 0, (P.chainCount + P.awakenChainBonus) - 1 do
        awakenChainMult = awakenChainMult + P.chainDecay ^ i
    end

    -- 蚀月增伤平均加成（叠加过程中: 0→1→2→3→4→5 层，平均 2.5 层的增伤）
    local avgMarkDmgAmp = 0
    for s = 0, P.maxStacks - 1 do
        avgMarkDmgAmp = avgMarkDmgAmp + s * P.dmgAmpPerStack
    end
    avgMarkDmgAmp = avgMarkDmgAmp / P.maxStacks  -- 平均每次攻击时的叠加增伤

    -- 普通循环
    local normalAutoTotal = normalAttacksToFull * atk * chainMult * (1 + avgMarkDmgAmp)
    local normalBurstDmg  = atk * P.burstAtkPct  -- 单目标爆发
    local normalCycleDmg  = normalAutoTotal + normalBurstDmg
    local normalCycleDPS  = normalCycleDmg / normalCycleTime

    -- 觉醒循环
    local awakenAtk = atk * (1 + P.awakenAtkBuff)
    local awakenAutoTotal = awakenAttacksToFull * awakenAtk * awakenChainMult * (1 + avgMarkDmgAmp)
    local awakenBurstDmg  = awakenAtk * P.burstAtkPct
    local awakenCycleDmg  = awakenAutoTotal + awakenBurstDmg
    local awakenCycleDPS  = awakenCycleDmg / awakenCycleTime

    -- 纯普攻 DPS（无机制）
    local pureAutoDPS = atk * chainMult / interval

    print(string.format("  英雄: crimson_moon  Lv%d ★%d Adv%d B★%d",
        params.level, params.star, params.advanceLevel, params.battleStar))
    print(string.format("  finalAtk = %s  attackInterval = %.3fs",
        Report.FormatInt(atk), interval))
    print("")

    local headers = { "状态", "叠满攻击数", "循环时间(s)", "普攻总伤", "爆发伤", "循环DPS", "vs纯普攻" }
    local colWidths = { 10, 12, 12, 14, 12, 14, 10 }
    local numCols = { [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true }
    local rows = {
        {
            "普通",
            normalAttacksToFull,
            Report.Fixed(normalCycleTime, 2),
            Report.FormatInt(normalAutoTotal),
            Report.FormatInt(normalBurstDmg),
            Report.FormatInt(normalCycleDPS),
            Report.Fixed(normalCycleDPS / pureAutoDPS, 2) .. "x",
        },
        {
            "觉醒",
            awakenAttacksToFull,
            Report.Fixed(awakenCycleTime, 2),
            Report.FormatInt(awakenAutoTotal),
            Report.FormatInt(awakenBurstDmg),
            Report.FormatInt(awakenCycleDPS),
            Report.Fixed(awakenCycleDPS / pureAutoDPS, 2) .. "x",
        },
        {
            "纯普攻",
            "-",
            "-",
            "-",
            "-",
            Report.FormatInt(pureAutoDPS),
            "1.00x",
        },
    }

    Report.Table(headers, rows, colWidths, numCols)
    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 C: 血月共鸣攻速贡献
------------------------------------------------------------------------
function CMA.ReportResonanceSpeed()
    Report.Header("弦月分析 C: 血月共鸣攻速贡献")

    local params = midGameBaseline("crimson_moon")
    local profile = HeroProfile.Build(params)
    local baseInterval = profile.attackInterval

    print(string.format("  基础攻击间隔: %.3fs (含星级/遗物速度加成)", baseInterval))
    print(string.format("  共鸣每层攻速: +%.0f%%, 最大 %d 层, 持续 %.1fs",
        P.spdPerStack * 100, P.spdMaxStacks, P.spdDuration))
    print("")

    local headers = { "共鸣层数", "攻速加成", "修正间隔(s)", "DPS倍率" }
    local colWidths = { 10, 10, 14, 10 }
    local numCols = { [1]=true, [2]=true, [3]=true, [4]=true }
    local rows = {}

    for stacks = 0, P.spdMaxStacks do
        local spdBuff = stacks * P.spdPerStack
        -- ModifyAttackSpeed: speed = speed / (1 + stacks * spdPerStack)
        local modifiedInterval = baseInterval / (1 + spdBuff)
        local dpsMult = baseInterval / modifiedInterval

        rows[#rows + 1] = {
            stacks,
            Report.Fixed(spdBuff * 100, 0) .. "%",
            Report.Fixed(modifiedInterval, 3),
            Report.Fixed(dpsMult, 3) .. "x",
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    -- 实战加权平均估算
    -- 爆发后获得层数（假设爆发平均命中 3 个敌人 → 3 层攻速）
    -- 持续 4s，循环约 4.25s → 平均约 70% 时间有 3 层
    local avgStacks = 3
    local uptimeRatio = P.spdDuration / (P.maxStacks * baseInterval + 0.5) -- 爆发间隔 ~4.25s
    uptimeRatio = math.min(1.0, uptimeRatio)
    local avgSpdBuff = avgStacks * P.spdPerStack * uptimeRatio
    local avgDpsMult = 1 + avgSpdBuff  -- 近似

    print("")
    print(string.format("  [ 实战估算 ] 假设爆发平均命中 %d 个敌人 → %d 层攻速", avgStacks, avgStacks))
    print(string.format("  攻速 buff 覆盖率 ≈ %.0f%%, 平均 DPS 倍率 ≈ %.3fx", uptimeRatio * 100, avgDpsMult))

    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 D: 月蚀领域 — 灵魂 ATK 积累与满月触发
------------------------------------------------------------------------
function CMA.ReportDomainScaling()
    Report.Header("弦月分析 D: 月蚀领域灵魂 ATK 积累")

    local params = midGameBaseline("crimson_moon")
    local profile = HeroProfile.Build(params)
    local atk = profile.finalAtk

    print(string.format("  领域魔法增伤: +%.0f%%", P.fieldAmp * 100))
    print(string.format("  每击杀永久 ATK: +%.0f%% (上限 %.0f%%)", P.soulAtkPerKill * 100, P.soulCap * 100))
    print(string.format("  满月条件: 灵魂 ATK 达上限 → 纯伤 %.1fs", P.fullMoonDuration))
    print("")

    local killsToMax = math.ceil(P.soulCap / P.soulAtkPerKill)

    local headers = { "击杀数", "灵魂ATK%", "等效ATK", "ATK增幅", "满月?" }
    local colWidths = { 8, 12, 14, 10, 8 }
    local numCols = { [1]=true, [2]=true, [3]=true, [4]=true }
    local rows = {}

    local sampleKills = { 0, 1, 2, 3, 5, 7, 10, killsToMax }
    for _, k in ipairs(sampleKills) do
        local soulPct = math.min(k * P.soulAtkPerKill, P.soulCap)
        local effAtk = math.floor(atk * (1 + soulPct))
        local fullMoon = soulPct >= P.soulCap and "是" or "—"

        rows[#rows + 1] = {
            k,
            Report.Fixed(soulPct * 100, 0) .. "%",
            Report.FormatInt(effAtk),
            Report.Fixed(soulPct, 2) .. "x",
            fullMoon,
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    print("")
    print(string.format("  需要 %d 次击杀达到灵魂 ATK 上限 %.0f%%", killsToMax, P.soulCap * 100))
    print(string.format("  满月状态: %.1fs 内所有攻击为纯伤（忽略防御和魔抗）", P.fullMoonDuration))

    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 E: 主动技能绯红新月价值
------------------------------------------------------------------------
function CMA.ReportActiveSkill()
    Report.Header("弦月分析 E: 绯红新月 (主动技能) 价值量化")

    local params = midGameBaseline("crimson_moon")
    local profile = HeroProfile.Build(params)
    local atk = profile.finalAtk
    local interval = profile.attackInterval

    -- 链式乘数
    local chainMult = 0
    for i = 0, P.chainCount - 1 do
        chainMult = chainMult + P.chainDecay ^ i
    end
    local pureAutoDPS = atk * chainMult / interval

    -- 绯红新月: 350% ATK 全屏伤害
    local crescentDmg = atk * P.crescentDmgPct

    -- 等效多少秒的普攻 DPS
    local crescentEquivSeconds = crescentDmg / pureAutoDPS

    -- 觉醒 6s 增益: ATK +25%, 链+2
    local awakenChainMult = 0
    for i = 0, (P.chainCount + P.awakenChainBonus) - 1 do
        awakenChainMult = awakenChainMult + P.chainDecay ^ i
    end
    local awakenDPS = atk * (1 + P.awakenAtkBuff) * awakenChainMult / interval
    local awakenExtraDPS = awakenDPS - pureAutoDPS
    local awakenTotalGain = awakenExtraDPS * P.awakenDuration

    -- 每 CD 周期总增益
    local totalCycleGain = crescentDmg + awakenTotalGain
    local avgDPSBoost = totalCycleGain / P.activeCooldown

    print(string.format("  finalAtk = %s, 基础链式 DPS = %s",
        Report.FormatInt(atk), Report.FormatInt(pureAutoDPS)))
    print(string.format("  绯红新月: %s%% ATK 全屏 = %s 伤害 (≈ %.1fs 普攻)",
        Report.Fixed(P.crescentDmgPct * 100, 0), Report.FormatInt(crescentDmg), crescentEquivSeconds))
    print("")

    local headers = { "来源", "总伤害/增益", "等效时间(s)", "分摊DPS" }
    local colWidths = { 18, 16, 14, 14 }
    local numCols = { [2]=true, [3]=true, [4]=true }
    local rows = {
        {
            "新月直伤 (350%)",
            Report.FormatInt(crescentDmg),
            Report.Fixed(crescentEquivSeconds, 2),
            Report.FormatInt(crescentDmg / P.activeCooldown),
        },
        {
            "觉醒增益 (6s)",
            Report.FormatInt(awakenTotalGain),
            Report.Fixed(awakenTotalGain / pureAutoDPS, 2),
            Report.FormatInt(awakenTotalGain / P.activeCooldown),
        },
        {
            "【合计/10s CD】",
            Report.FormatInt(totalCycleGain),
            Report.Fixed(totalCycleGain / pureAutoDPS, 2),
            Report.FormatInt(avgDPSBoost),
        },
    }

    Report.Table(headers, rows, colWidths, numCols)

    local boostPct = avgDPSBoost / pureAutoDPS * 100
    print("")
    print(string.format("  主动技能平均 DPS 提升: +%s (%.1f%%)", Report.FormatInt(avgDPSBoost), boostPct))

    -- 施加 3 层印记价值
    print("")
    print("  [ 附加价值: 全屏 3 层蚀月印记 ]")
    print(string.format("  3 层 → +%.0f%% 魔法增伤 × 所有后续伤害", 3 * P.dmgAmpPerStack * 100))
    print(string.format("  加速满层爆发 → 省 %d 次普攻 (≈ %.1fs)",
        3, 3 * interval))

    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 F: 同稀有度 LR 英雄 DPS 对比
------------------------------------------------------------------------
function CMA.ReportLRComparison()
    Report.Header("弦月分析 F: LR 稀有度英雄 DPS 对比")

    local lrHeroes = { "fate_weaver", "eternal_archfiend", "crimson_moon" }

    local headers = { "英雄", "ATK", "间隔(s)", "Raw DPS", "Eff DPS", "Kill(s)" }
    local colWidths = { 20, 12, 8, 14, 14, 8 }
    local numCols = { [2]=true, [3]=true, [4]=true, [5]=true, [6]=true }
    local rows = {}

    for _, heroId in ipairs(lrHeroes) do
        local params = midGameBaseline(heroId)
        local result = HeroDPS.Calc(params, midGameMonster())

        rows[#rows + 1] = {
            heroId,
            Report.FormatInt(result.profile.finalAtk),
            Report.Fixed(result.profile.attackInterval, 3),
            Report.FormatInt(result.rawDPS),
            Report.FormatInt(result.effectiveDPS),
            Report.Fixed(result.killTime, 2),
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    print("")
    print("  注: 以上为基础面板 DPS (不含被动/主动技能加成)")
    print("  弦月的真实输出需叠加蚀月爆发 + 血月共鸣 + 觉醒态 + 月蚀领域")

    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 G: 综合有效 DPS 估算 (含全部机制)
------------------------------------------------------------------------
function CMA.ReportComprehensiveDPS()
    Report.Header("弦月分析 G: 综合有效 DPS 估算 (含全部机制)")

    local params = midGameBaseline("crimson_moon")
    local profile = HeroProfile.Build(params)
    local atk = profile.finalAtk
    local interval = profile.attackInterval

    -- 1. 基础链式 DPS
    local chainMult = 0
    for i = 0, P.chainCount - 1 do
        chainMult = chainMult + P.chainDecay ^ i
    end
    local baseDPS = atk * chainMult / interval

    -- 2. 月蚀领域: +12% 全程增伤
    local domainDPS = baseDPS * (1 + P.fieldAmp)

    -- 3. 蚀月印记平均增伤 (叠层过程 0→5, 均匀分布平均 2 层)
    local avgMarkAmp = (0 + 1 + 2 + 3 + 4) / 5 * P.dmgAmpPerStack  -- 平均 2 层 = 0.08
    local markDPS = domainDPS * (1 + avgMarkAmp)

    -- 4. 蚀月爆发 DPS 贡献 (每 5 次攻击爆发一次)
    local burstDmg = atk * P.burstAtkPct
    local burstCycleTime = P.maxStacks * interval  -- 5 × 0.85s = 4.25s
    local burstDPSContrib = burstDmg / burstCycleTime

    -- 5. 血月共鸣攻速 (爆发平均命中 3 个 → 3 层, 持续 4s / 循环 ~4.25s ≈ 94% uptime)
    local resonanceUptime = math.min(1.0, P.spdDuration / burstCycleTime)
    local avgResonanceStacks = 3
    local resonanceSpdMult = 1 + avgResonanceStacks * P.spdPerStack * resonanceUptime

    -- 6. 血月共鸣减魔抗 (爆发时 -15%, 持续 3s / 循环 ~4.25s ≈ 71% uptime)
    local resReduceUptime = math.min(1.0, P.resReduceDuration / burstCycleTime)
    local resReduceAmp = 1 + P.resReduce * resReduceUptime

    -- 7. 主动: 绯红新月 DPS 分摊
    local awakenChainMult = 0
    for i = 0, (P.chainCount + P.awakenChainBonus) - 1 do
        awakenChainMult = awakenChainMult + P.chainDecay ^ i
    end
    local crescentDirectDPS = atk * P.crescentDmgPct / P.activeCooldown
    local awakenDPS = atk * (1 + P.awakenAtkBuff) * awakenChainMult / interval
    local awakenExtraDPS = (awakenDPS - baseDPS) * P.awakenDuration / P.activeCooldown

    -- 8. 灵魂 ATK (假设中期平均 15% = 上限的一半)
    local avgSoulPct = P.soulCap * 0.5
    local soulMult = 1 + avgSoulPct

    -- 综合 DPS
    local autoDPS = (markDPS * resonanceSpdMult * resReduceAmp * soulMult) + burstDPSContrib
    local totalDPS = autoDPS + crescentDirectDPS + awakenExtraDPS

    -- 基线: 无任何技能的裸 chain DPS
    local nakedDPS = baseDPS

    print(string.format("  英雄: crimson_moon  Lv%d ★%d Adv%d B★%d",
        params.level, params.star, params.advanceLevel, params.battleStar))
    print(string.format("  finalAtk = %s  interval = %.3fs  chainMult = %.3f",
        Report.FormatInt(atk), interval, chainMult))
    print("")

    local headers = { "增伤层", "DPS 贡献", "乘数/占比", "说明" }
    local colWidths = { 18, 14, 12, 40 }
    local numCols = { [2]=true }
    local rows = {
        { "裸链式 DPS",
            Report.FormatInt(nakedDPS), "基准",
            string.format("ATK×%.2f / %.3fs", chainMult, interval) },
        { "月蚀领域 +12%",
            Report.FormatInt(domainDPS - baseDPS), Report.Fixed(1 + P.fieldAmp, 2) .. "x",
            "领域内全程魔法增伤" },
        { "蚀月印记 ~8%",
            Report.FormatInt(markDPS - domainDPS), Report.Fixed(1 + avgMarkAmp, 3) .. "x",
            string.format("平均 %.1f 层 × %.0f%%/层", (0+1+2+3+4)/5, P.dmgAmpPerStack*100) },
        { "蚀月爆发 180%",
            Report.FormatInt(burstDPSContrib), Report.Fixed(burstDPSContrib/nakedDPS*100, 1) .. "%",
            string.format("每 %.1fs 爆发一次", burstCycleTime) },
        { "共鸣攻速",
            "-", Report.Fixed(resonanceSpdMult, 3) .. "x",
            string.format("≈%d层 × %.0f%% × %.0f%%覆盖", avgResonanceStacks, P.spdPerStack*100, resonanceUptime*100) },
        { "共鸣减魔抗",
            "-", Report.Fixed(resReduceAmp, 3) .. "x",
            string.format("-%.0f%% × %.0f%%覆盖", P.resReduce*100, resReduceUptime*100) },
        { "灵魂ATK (avg)",
            "-", Report.Fixed(soulMult, 2) .. "x",
            string.format("平均 %.0f%% (上限 %.0f%%)", avgSoulPct*100, P.soulCap*100) },
        { "新月直伤",
            Report.FormatInt(crescentDirectDPS), Report.Fixed(crescentDirectDPS/nakedDPS*100, 1) .. "%",
            string.format("%.0f%%ATK / %ds CD", P.crescentDmgPct*100, P.activeCooldown) },
        { "觉醒增益",
            Report.FormatInt(awakenExtraDPS), Report.Fixed(awakenExtraDPS/nakedDPS*100, 1) .. "%",
            string.format("+%.0f%%ATK +%d链 × %.0fs / %ds CD", P.awakenAtkBuff*100, P.awakenChainBonus, P.awakenDuration, P.activeCooldown) },
    }

    Report.Table(headers, rows, colWidths, numCols)

    print("")
    print(string.format("  ══════════════════════════════════════════"))
    print(string.format("  综合有效 DPS ≈ %s", Report.FormatInt(totalDPS)))
    print(string.format("  裸链式  DPS   = %s", Report.FormatInt(nakedDPS)))
    print(string.format("  技能总增幅    = %.2fx (%.0f%%)", totalDPS / nakedDPS, (totalDPS / nakedDPS - 1) * 100))
    print(string.format("  ══════════════════════════════════════════"))

    -- 与 shadow_mage (基线 SSR) 对比
    local smParams = midGameBaseline("shadow_mage")
    local smResult = HeroDPS.Calc(smParams, midGameMonster())
    print("")
    print(string.format("  [ 对比: shadow_mage (SSR 基线) Raw DPS = %s ]", Report.FormatInt(smResult.rawDPS)))
    print(string.format("  弦月综合 DPS / shadow_mage Raw DPS = %.2fx", totalDPS / smResult.rawDPS))

    Report.Separator()
end

------------------------------------------------------------------------
-- 报告 H: DPS vs 关卡 EHP 曲线 (弦月成长)
------------------------------------------------------------------------
function CMA.ReportProgressionCurve()
    Report.Header("弦月分析 H: DPS vs EHP 成长曲线")

    local stages = { 1, 100, 500, 1000, 1500, 2000, 3000, 4000, 5000, 6000 }

    local function heroParamsAtStage(stage, heroId)
        local progress = math.min(1.0, (stage - 1) / 5999)
        return {
            heroId       = heroId,
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

    local headers = { "关卡", "Lv", "弦月DPS", "暗法DPS", "弦月/暗法", "怪物EHP", "弦月Kill(s)" }
    local colWidths = { 6, 6, 14, 14, 12, 16, 12 }
    local numCols = { [1]=true, [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true }
    local rows = {}

    for _, stage in ipairs(stages) do
        local cmParams = heroParamsAtStage(stage, "crimson_moon")
        local smParams = heroParamsAtStage(stage, "shadow_mage")
        local cmResult = HeroDPS.Calc(cmParams, { stageNum = stage, waveInStage = 1, roleId = "minion" })
        local smResult = HeroDPS.Calc(smParams, { stageNum = stage, waveInStage = 1, roleId = "minion" })

        rows[#rows + 1] = {
            stage,
            cmParams.level,
            Report.FormatInt(cmResult.effectiveDPS),
            Report.FormatInt(smResult.effectiveDPS),
            Report.Fixed(cmResult.effectiveDPS / math.max(1, smResult.effectiveDPS), 2) .. "x",
            Report.FormatInt(cmResult.monster.effectiveHP),
            Report.Fixed(cmResult.killTime, 2),
        }
    end

    Report.Table(headers, rows, colWidths, numCols)

    print("")
    print("  注: 以上为面板 DPS 对比 (不含被动技能), 弦月真实输出需 ×技能增幅")

    Report.Separator()
end

------------------------------------------------------------------------
-- 入口
------------------------------------------------------------------------

function CMA.Run()
    print("")
    print("================================================================")
    print("  弦月 (crimson_moon) 专项数值分析")
    print("================================================================")

    CMA.ReportChainDPS()
    CMA.ReportEclipseCycle()
    CMA.ReportResonanceSpeed()
    CMA.ReportDomainScaling()
    CMA.ReportActiveSkill()
    CMA.ReportLRComparison()
    CMA.ReportComprehensiveDPS()
    CMA.ReportProgressionCurve()

    print("")
    print("================================================================")
    print("  弦月分析完成")
    print("================================================================")
end

return CMA
