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
--- 平衡：单条红品最大值 × coeff(1.35) 的 DPS 贡献 ≈ 5-8%
RuneConfig.AFFIX_BASE = {
    { id = "atk_pct",    name = "攻击力",   minVal = 0.02, maxVal = 0.08, unit = "%",  weight = 10 },  -- 8%×0.71=5.7% DPS
    { id = "spd_pct",    name = "攻击速度", minVal = 0.02, maxVal = 0.08, unit = "%",  weight = 10 },  -- 8%×0.6 =4.8% DPS
    { id = "critRate",   name = "暴击率",   minVal = 0.02, maxVal = 0.08, unit = "%",  weight = 10 },  -- 8%×0.69=5.5% DPS
    { id = "critDmg",    name = "暴击伤害", minVal = 0.04, maxVal = 0.18, unit = "%",  weight = 10 },  -- 18%×0.30=5.4% DPS
    { id = "armorPen",   name = "穿甲",     minVal = 0.01, maxVal = 0.05, unit = "%",  weight = 8  },  -- 5%×1.3 =6.5% DPS
    { id = "dmgBonus",   name = "伤害加成", minVal = 0.02, maxVal = 0.08, unit = "%",  weight = 8  },  -- 8%×0.76=6.1% DPS
    { id = "range",      name = "攻击范围", minVal = 5,    maxVal = 15,   unit = "px", weight = 4  },  -- 功能性
}

--- 特殊效果词条（权重40%）
--- vulnMark 独立乘区无敌方抵抗, 每1%≈1.0% DPS, 需严格控制
RuneConfig.AFFIX_SPECIAL = {
    { id = "chain",      name = "连锁概率",   minVal = 0.03, maxVal = 0.12, unit = "%",  weight = 8 },  -- 功能性, 适度削减
    { id = "slow_amp",   name = "减速强化",   minVal = 0.03, maxVal = 0.12, unit = "%",  weight = 7 },  -- 功能性
    { id = "dot_amp",    name = "DOT强化",     minVal = 0.05, maxVal = 0.20, unit = "%",  weight = 7 },  -- DOT专属
    { id = "cdr",        name = "技能冷却缩减", minVal = 0.02, maxVal = 0.08, unit = "%", weight = 6 },  -- 功能性
    { id = "killReset",  name = "击杀回复",   minVal = 0.01, maxVal = 0.05, unit = "%",  weight = 5 },  -- 功能性
    { id = "vulnMark",   name = "易伤标记",   minVal = 0.02, maxVal = 0.06, unit = "%",  weight = 5 },  -- 6%×1.0=6.0% DPS
    { id = "elemMastery",name = "元素精通",   minVal = 0.03, maxVal = 0.10, unit = "%",  weight = 4 },  -- typeDmg区
    { id = "luckyDrop",  name = "幸运掉落",   minVal = 0.02, maxVal = 0.08, unit = "%",  weight = 4 },  -- 经济性
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
RuneConfig.AFFIX_CATEGORY = {}   -- id -> "base" / "special"
for _, entry in ipairs(RuneConfig.ALL_AFFIXES) do
    RuneConfig.AFFIX_MAP[entry.def.id] = entry.def
    RuneConfig.AFFIX_CATEGORY[entry.def.id] = entry.category
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
    { id = 1, name = "源力核心", unlockStage = 50  },  -- 主线第50关(匹配深渊裂隙解锁)
    { id = 2, name = "意志铭刻", unlockStage = 80  },  -- 主线第80关
    { id = 3, name = "深渊之印", unlockStage = 120 },  -- 主线第120关
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
    unlockStage    = 50,          -- 解锁关卡(主线第50关)
    dailyFree      = 1,           -- 每日免费次数
    dailyAd        = 2,           -- 每日广告次数
    totalWaves     = 15,          -- 总波数
    enemiesPerWave = 25,          -- 每波敌人数
    baseStage      = 500,         -- 第1波等效关卡
    finalStage     = 6000,        -- 第15波等效关卡
}

-- 三档难度：梯度平滑（×1 → ×5 → ×20），避免断层
RuneConfig.ABYSS_DIFFICULTY = {
    { id = "normal",    name = "普通", levelMult = 1,  qualityMult = 1.0, dustRange = {3, 5},   dropChanceMult = 1.0 },
    { id = "hard",      name = "困难", levelMult = 5,  qualityMult = 1.8, dustRange = {8, 14},  dropChanceMult = 1.3 },
    { id = "nightmare", name = "噩梦", levelMult = 20, qualityMult = 3.5, dustRange = {16, 26}, dropChanceMult = 1.8 },
}

--- 波次掉落规则
--- 波次节奏：1-2普通 → 3精英 → 4-6普通 → 7精英 → 8-9普通 → 10精英+ → 11-12普通 → 13精英++ → 14普通 → 15BOSS
RuneConfig.ABYSS_WAVE_DROPS = {
    -- 普通波：小量尘 + 低概率符文（让每波都有惊喜感）
    normal  = { dustMin = 1, dustMax = 3, runeChance = 0.05, sealChance = 0 },
    -- 精英波 wave 3：初次精英，小惊喜
    elite3  = { dustMin = 3, dustMax = 5, runeChance = 0.15, sealChance = 0.05, sealMin = 1, sealMax = 1 },
    -- 精英波 wave 7：中期节点
    elite7  = { dustMin = 4, dustMax = 6, runeChance = 0.25, sealChance = 0.10, sealMin = 1, sealMax = 1 },
    -- 精英+ wave 10：后期强精英
    elite10 = { dustMin = 5, dustMax = 8, runeChance = 0.40, sealChance = 0.15, sealMin = 1, sealMax = 1 },
    -- 精英++ wave 13：BOSS 前哨
    elite13 = { dustMin = 6, dustMax = 10, runeChance = 0.50, sealChance = 0.15, sealMin = 1, sealMax = 1 },
    -- BOSS wave 15：保底符文 + 高奖励
    boss    = { dustMin = 8, dustMax = 15, runeChance = 1.00, sealChance = 0.30, sealMin = 1, sealMax = 2 },
}

--- 获取波次掉落类型
---@param wave number 1-15
---@return string key
function RuneConfig.GetWaveDropType(wave)
    if wave == 15 then return "boss" end
    if wave == 13 then return "elite13" end
    if wave == 10 then return "elite10" end
    if wave == 7  then return "elite7" end
    if wave == 3  then return "elite3" end
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

-- ============================================================================
-- 三层词条注入（来自 Config_AffixTags 的角色/技能/标签词条）
-- ============================================================================
do
    local Config = require("Game.Config")
    if Config.AFFIX_TAG_RUNE_ENTRIES and Config.AFFIX_TAG_LOOKUP then
        for _, entry in ipairs(Config.AFFIX_TAG_RUNE_ENTRIES) do
            local def = Config.AFFIX_TAG_LOOKUP[entry.id]
            if def then
                local affixDef = {
                    id      = def.id,
                    name    = def.name,
                    minVal  = def.minVal,
                    maxVal  = def.maxVal,
                    unit    = "%",
                    weight  = entry.weight,
                    -- 额外字段：标记为三层词条
                    affixTier = entry.affixTier,
                    isTagAffix = true,
                }
                RuneConfig.ALL_AFFIXES[#RuneConfig.ALL_AFFIXES + 1] = {
                    def = affixDef, category = "tag_t" .. entry.affixTier,
                }
                RuneConfig.AFFIX_MAP[def.id] = affixDef
                RuneConfig.AFFIX_CATEGORY[def.id] = "tag_t" .. entry.affixTier
            end
        end
        -- 重算总权重（含新注入词条）
        local tw = 0
        for _, e in ipairs(RuneConfig.ALL_AFFIXES) do
            tw = tw + e.def.weight
        end
        RuneConfig._totalAffixWeight = tw
    end
end

return RuneConfig
