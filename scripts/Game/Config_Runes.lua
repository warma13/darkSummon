-- Game/Config_Runes.lua
-- 深渊符文系统 — 配置定义
-- 符文系列/品质/词条池/套装效果/洗练参数

local RuneConfig = {}

-- ============================================================================
-- 符文品质（6个等级）
-- ============================================================================

RuneConfig.QUALITIES = {
    { id = "white",  name = "普通", color = {180,180,180}, initAffixes = 1, maxAffixes = 2, weight = 40, coeff = 0.60 },
    { id = "green",  name = "精良", color = { 80,200, 80}, initAffixes = 2, maxAffixes = 3, weight = 30, coeff = 0.75 },
    { id = "blue",   name = "稀有", color = { 80,140,255}, initAffixes = 2, maxAffixes = 3, weight = 18, coeff = 0.85 },
    { id = "purple", name = "史诗", color = {180, 80,255}, initAffixes = 3, maxAffixes = 4, weight =  8, coeff = 1.00 },
    { id = "orange", name = "传说", color = {255,160, 40}, initAffixes = 3, maxAffixes = 4, weight =  3, coeff = 1.15 },
    { id = "red",    name = "神话", color = {255, 50, 50}, initAffixes = 4, maxAffixes = 4, weight =  1, coeff = 1.35 },
}

--- 按 ID 查品质
RuneConfig.QUALITY_MAP = {}
for i, q in ipairs(RuneConfig.QUALITIES) do
    q.index = i
    RuneConfig.QUALITY_MAP[q.id] = q
end

-- ============================================================================
-- 符文系列（6个系列，含套装效果）
-- ============================================================================

RuneConfig.SERIES = {
    {
        id = "flame",
        name = "烈焰",
        emoji = "🔥",
        icon = "image/rune_flame.png",
        tagColor = {255,100,40},
        set2 = { desc = "攻击力 +8%",                    stat = "atk_pct",    value = 0.08 },
        set3 = { desc = "攻击附带灼烧DOT(2%攻击力/3秒)", effect = "burn_dot", dotPct = 0.02, dotDur = 3.0 },
    },
    {
        id = "frost",
        name = "寒霜",
        emoji = "🧊",
        icon = "image/rune_frost.png",
        tagColor = {100,180,255},
        set2 = { desc = "攻速 +12%",                      stat = "spd_pct",    value = 0.12 },
        set3 = { desc = "攻击15%概率冻结敌人1秒",          effect = "freeze",   chance = 0.15, dur = 1.0 },
    },
    {
        id = "thunder",
        name = "雷霆",
        emoji = "⚡",
        icon = "image/rune_thunder.png",
        tagColor = {200,180,60},
        set2 = { desc = "暴击率 +10%",                     stat = "critRate",   value = 0.10 },
        set3 = { desc = "暴击时对周围造成30%溅射伤害",      effect = "crit_splash", splashPct = 0.30 },
    },
    {
        id = "shadow",
        name = "暗影",
        emoji = "🌑",
        icon = "image/rune_shadow.png",
        tagColor = {160,80,200},
        set2 = { desc = "伤害加成 +10%",                   stat = "dmgBonus",   value = 0.10 },
        set3 = { desc = "击杀时15%概率双倍暗魂",           effect = "double_soul", chance = 0.15 },
    },
    {
        id = "undead",
        name = "亡灵",
        emoji = "💀",
        icon = "image/rune_undead.png",
        tagColor = {140,180,140},
        set2 = { desc = "穿甲 +8%",                        stat = "armorPen",   value = 0.08 },
        set3 = { desc = "每次攻击叠层，5层触发真实伤害",    effect = "curse_stack", stackMax = 5, dmgPct = 0.20 },
    },
    {
        id = "bastion",
        name = "铁壁",
        emoji = "🛡️",
        icon = "image/rune_bastion.png",
        tagColor = {180,180,200},
        set2 = { desc = "所有英雄攻击力 +3%",              stat = "global_atk_pct", value = 0.03 },
        set3 = { desc = "致命伤害时10%概率免疫(30秒冷却)",  effect = "fatal_immune", chance = 0.10, cooldown = 30.0 },
    },
}

--- 按 ID 查系列
RuneConfig.SERIES_MAP = {}
for _, s in ipairs(RuneConfig.SERIES) do
    RuneConfig.SERIES_MAP[s.id] = s
end

-- ============================================================================
-- 词条池
-- ============================================================================

--- 基础属性词条（权重60%）
RuneConfig.AFFIX_BASE = {
    { id = "atk_pct",    name = "攻击力",   minVal = 0.03, maxVal = 0.15, unit = "%",  weight = 10 },
    { id = "spd_pct",    name = "攻击速度", minVal = 0.03, maxVal = 0.12, unit = "%",  weight = 10 },
    { id = "critRate",   name = "暴击率",   minVal = 0.02, maxVal = 0.10, unit = "%",  weight = 10 },
    { id = "critDmg",    name = "暴击伤害", minVal = 0.05, maxVal = 0.25, unit = "%",  weight = 10 },
    { id = "armorPen",   name = "穿甲",     minVal = 0.02, maxVal = 0.10, unit = "%",  weight = 8  },
    { id = "dmgBonus",   name = "伤害加成", minVal = 0.03, maxVal = 0.12, unit = "%",  weight = 8  },
    { id = "range",      name = "攻击范围", minVal = 5,    maxVal = 20,   unit = "px", weight = 4  },
}

--- 特殊效果词条（权重40%）
RuneConfig.AFFIX_SPECIAL = {
    { id = "chain",      name = "连锁概率",   minVal = 0.05, maxVal = 0.20, unit = "%",  weight = 8 },
    { id = "slow_amp",   name = "减速强化",   minVal = 0.05, maxVal = 0.15, unit = "%",  weight = 7 },
    { id = "dot_amp",    name = "DOT强化",     minVal = 0.10, maxVal = 0.30, unit = "%",  weight = 7 },
    { id = "cdr",        name = "技能冷却缩减", minVal = 0.03, maxVal = 0.10, unit = "%", weight = 6 },
    { id = "killReset",  name = "击杀回复",   minVal = 0.01, maxVal = 0.05, unit = "%",  weight = 5 },
    { id = "vulnMark",   name = "易伤标记",   minVal = 0.03, maxVal = 0.08, unit = "%",  weight = 5 },
    { id = "elemMastery",name = "元素精通",   minVal = 0.05, maxVal = 0.15, unit = "%",  weight = 4 },
    { id = "luckyDrop",  name = "幸运掉落",   minVal = 0.02, maxVal = 0.08, unit = "%",  weight = 4 },
}

--- 合并词条池（供洗练使用）
RuneConfig.ALL_AFFIXES = {}
for _, a in ipairs(RuneConfig.AFFIX_BASE) do
    RuneConfig.ALL_AFFIXES[#RuneConfig.ALL_AFFIXES + 1] = { def = a, category = "base" }
end
for _, a in ipairs(RuneConfig.AFFIX_SPECIAL) do
    RuneConfig.ALL_AFFIXES[#RuneConfig.ALL_AFFIXES + 1] = { def = a, category = "special" }
end

-- 按 ID 查词条定义
RuneConfig.AFFIX_MAP = {}
for _, entry in ipairs(RuneConfig.ALL_AFFIXES) do
    RuneConfig.AFFIX_MAP[entry.def.id] = entry.def
end

-- 预计算总权重
RuneConfig._totalBaseWeight = 0
for _, a in ipairs(RuneConfig.AFFIX_BASE) do
    RuneConfig._totalBaseWeight = RuneConfig._totalBaseWeight + a.weight
end
RuneConfig._totalSpecialWeight = 0
for _, a in ipairs(RuneConfig.AFFIX_SPECIAL) do
    RuneConfig._totalSpecialWeight = RuneConfig._totalSpecialWeight + a.weight
end
RuneConfig._totalAffixWeight = RuneConfig._totalBaseWeight + RuneConfig._totalSpecialWeight

-- ============================================================================
-- 符文槽位（每英雄3个）
-- ============================================================================

RuneConfig.MAX_SLOTS = 3

RuneConfig.SLOT_DEFS = {
    { id = 1, name = "源力核心", unlockStage = 20  },  -- 第1章
    { id = 2, name = "意志铭刻", unlockStage = 200  },  -- 第10章
    { id = 3, name = "深渊之印", unlockStage = 400  },  -- 第20章
}

-- ============================================================================
-- 洗练参数
-- ============================================================================

RuneConfig.REFORGE_COST_DUST   = 30     -- 基础洗练：裂隙之尘
RuneConfig.REFORGE_COST_SEAL   = 1      -- 每条锁定词条消耗符文封印
RuneConfig.DIRECTED_COST_DUST  = 80     -- 定向洗练：裂隙之尘
RuneConfig.DIRECTED_COST_CRYSTAL = 1    -- 定向洗练：深渊结晶
RuneConfig.DIRECTED_UNLOCK_STAGE = 600  -- 定向洗练解锁关卡(第30章)
RuneConfig.UPGRADE_COST_DUST   = 100    -- 词条升品：裂隙之尘
RuneConfig.UPGRADE_COST_CRYSTAL = 3     -- 词条升品：深渊结晶
RuneConfig.UPGRADE_UNLOCK_STAGE = 800   -- 词条升品解锁关卡(第40章)

--- 词条升品成功率（按当前词条品质），失败则降低一级（最低白色）
RuneConfig.UPGRADE_SUCCESS_RATE_BY_QUALITY = {
    white  = 1.00,  -- 白→绿 100%
    green  = 0.80,  -- 绿→蓝 80%
    blue   = 0.50,  -- 蓝→紫 50%
    purple = 0.25,  -- 紫→橙 25%
    orange = 0.10,  -- 橙→红 10%
    -- red 已是最高品质，无法升品
}

-- ============================================================================
-- 背包参数
-- ============================================================================

RuneConfig.BAG_CAPACITY = 50            -- 初始容量
RuneConfig.BAG_MAX_CAPACITY = 100       -- 最大容量
RuneConfig.BAG_EXPAND_COST = 500        -- 每次扩容消耗裂隙之尘
RuneConfig.BAG_EXPAND_AMOUNT = 10       -- 每次扩容增加

-- ============================================================================
-- 分解产出
-- ============================================================================

RuneConfig.DECOMPOSE = {
    white  = { rift_dust = 5 },
    green  = { rift_dust = 10 },
    blue   = { rift_dust = 20 },
    purple = { rift_dust = 40,  rune_seal = 1 },
    orange = { rift_dust = 60,  rune_seal = 2, abyss_crystal = 1 },
    red    = { rift_dust = 100, rune_seal = 3, abyss_crystal = 3 },
}

-- ============================================================================
-- 深渊裂隙副本参数
-- ============================================================================

RuneConfig.ABYSS_RIFT = {
    unlockStage    = 20,          -- 解锁关卡(主线第20关)
    dailyFree      = 1,           -- 每日免费次数
    dailyAd        = 2,           -- 每日广告次数
    totalWaves     = 15,          -- 总波数
    enemiesPerWave = 25,          -- 每波敌人数
    baseStage      = 5,           -- 第1波等效关卡（固定起点）
    finalStage     = 6000,        -- 第15波等效关卡（指数增长终点）
}

RuneConfig.ABYSS_DIFFICULTY = {
    { id = "normal",   name = "普通", levelMult = 0.8, qualityMult = 1.0, dustRange = {3, 5}  },
    { id = "hard",     name = "困难", levelMult = 1.2, qualityMult = 1.5, dustRange = {6, 10} },
    { id = "nightmare",name = "噩梦", levelMult = 1.8, qualityMult = 2.0, dustRange = {10,15} },
}

--- 波次掉落规则
RuneConfig.ABYSS_WAVE_DROPS = {
    -- 普通波 (1-4, 6-9, 11-14)
    normal = { dustMin = 1, dustMax = 2, runeChance = 0, sealChance = 0 },
    -- 精英波 (5, 10)
    elite5  = { dustMin = 3, dustMax = 3, runeChance = 0.10, sealChance = 0.10, sealMin = 1, sealMax = 1 },
    elite10 = { dustMin = 5, dustMax = 5, runeChance = 0.20, sealChance = 0.15, sealMin = 1, sealMax = 1 },
    -- BOSS波 (15)
    boss    = { dustMin = 8, dustMax = 12, runeChance = 1.00, sealChance = 0.20, sealMin = 1, sealMax = 2 },
}

--- 获取波次掉落类型
---@param wave number 1-15
---@return string key  "normal" / "elite5" / "elite10" / "boss"
function RuneConfig.GetWaveDropType(wave)
    if wave == 15 then return "boss" end
    if wave == 10 then return "elite10" end
    if wave == 5  then return "elite5" end
    return "normal"
end

-- ============================================================================
-- 货币定义（新增3种）
-- ============================================================================

RuneConfig.CURRENCIES = {
    rift_dust      = { name = "裂隙之尘",   color = {160,120,200}, usage = "符文洗练" },
    rune_seal      = { name = "符文封印",   color = { 40,200,160}, usage = "洗练锁定" },
    abyss_crystal  = { name = "深渊结晶",   color = {200, 60,255}, usage = "定向洗练" },
}

return RuneConfig
