-- Game/CollectibleData.lua
-- 武器收集系统：通过资源副本获取不同武器道具，收集数量线性提升战斗能力
-- 37 种武器分布在 6 个资源副本中，每种武器拥有独特的加成类型
-- 加成维度覆盖：基础属性 / runeBonus / 战斗特效 / 穿透减抗 / 攻速射程 / 掉落运气 等 30+ 种
-- 每次副本通关随机掉落该副本 2~3 种武器

local HeroData = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local M = {}

-- ============================================================================
-- 能力类别定义（UI 分组用）
-- ============================================================================

M.CATEGORIES = {
    { key = "chain",    label = "链式伤害", color = { 100, 180, 255 }, emoji = "⛓️"  },
    { key = "aoe",      label = "范围伤害", color = { 255, 140, 60 },  emoji = "💥"  },
    { key = "single",   label = "单体伤害", color = { 220, 80, 80 },   emoji = "🎯"  },
    { key = "control",  label = "控制能力", color = { 180, 120, 255 }, emoji = "🕸️"  },
    { key = "buff",     label = "增益能力", color = { 80, 200, 100 },  emoji = "✨"  },
    { key = "skill",    label = "技能伤害", color = { 255, 80, 60 },   emoji = "🔮"  },
    { key = "pen",      label = "破甲穿透", color = { 200, 160, 60 },  emoji = "🛡️"  },
    { key = "crit",     label = "暴击强化", color = { 255, 200, 50 },  emoji = "⚡"  },
    { key = "onkill",   label = "击杀奖励", color = { 160, 60, 200 },  emoji = "💀"  },
    { key = "attack",   label = "攻击强化", color = { 255, 100, 100 }, emoji = "⚔️"  },
}

-- 按 key 索引
M.CATEGORY_MAP = {}
for _, cat in ipairs(M.CATEGORIES) do
    M.CATEGORY_MAP[cat.key] = cat
end

-- ============================================================================
-- 加成类型注册（30+ 种独立加成）
-- ============================================================================
-- layer 说明加成的注入层:
--   "rune"     → 叠加到 tower.runeBonus 对应字段
--   "stat"     → 叠加到 tower 基础属性 (critRate/critDmg/dmgBonus/physDmgBonus 等)
--   "collect"  → 专属收集加成，注入 tower.collectBonus 由各系统读取
-- ============================================================================

---@class StatType
---@field key string         唯一key
---@field label string       中文名
---@field layer string       注入层: "rune" | "stat" | "collect"
---@field field string       目标字段名（在 runeBonus/tower/collectBonus 上）
---@field format string      显示格式 "pct" | "flat"
---@field desc string        效果说明

M.STAT_TYPES = {
    -- ── runeBonus 层（8 种）──────────────────────────────────
    { key = "chain",        label = "链式弹射伤害",   layer = "rune",    field = "chain",       format = "pct", desc = "链式攻击额外弹射伤害" },
    { key = "slow_amp",     label = "减速效果增幅",   layer = "rune",    field = "slow_amp",    format = "pct", desc = "所有减速效果强度提升" },
    { key = "dot_amp",      label = "持续伤害增幅",   layer = "rune",    field = "dot_amp",     format = "pct", desc = "灼烧/中毒等持续伤害提升" },
    { key = "cdr",          label = "冷却缩减",       layer = "rune",    field = "cdr",         format = "pct", desc = "技能冷却时间缩短" },
    { key = "killReset",    label = "击杀重置概率",   layer = "rune",    field = "killReset",   format = "pct", desc = "击杀敌人后重置攻击间隔" },
    { key = "vulnMark",     label = "易伤标记强度",   layer = "rune",    field = "vulnMark",    format = "pct", desc = "独立乘区易伤增伤" },
    { key = "elemMastery",  label = "元素精通",       layer = "rune",    field = "elemMastery", format = "pct", desc = "物理/魔法属性伤害提升" },
    { key = "luckyDrop",    label = "幸运掉落",       layer = "rune",    field = "luckyDrop",   format = "pct", desc = "提升战利品掉落品质" },

    -- ── 基础属性层（6 种）────────────────────────────────────
    { key = "critRate",     label = "暴击率",         layer = "stat",    field = "critRate",      format = "pct", desc = "攻击暴击概率提升" },
    { key = "critDmg",      label = "暴击伤害",       layer = "stat",    field = "critDmg",       format = "pct", desc = "暴击伤害倍率提升" },
    { key = "dmgBonus",     label = "通用伤害加成",   layer = "stat",    field = "dmgBonus",      format = "pct", desc = "所有攻击伤害提升" },
    { key = "physDmgBonus", label = "物理伤害加成",   layer = "stat",    field = "physDmgBonus",  format = "pct", desc = "物理系英雄伤害提升" },
    { key = "magicDmgBonus",label = "魔法伤害加成",   layer = "stat",    field = "magicDmgBonus", format = "pct", desc = "魔法系英雄伤害提升" },
    { key = "armorPen",     label = "护甲穿透",       layer = "stat",    field = "armorPen",      format = "pct", desc = "无视敌方物理防御" },

    -- ── 收集专属层（18 种，注入 collectBonus）────────────────
    { key = "magicPen",     label = "法术穿透",       layer = "collect", field = "magicPen",      format = "pct", desc = "无视敌方魔法抗性" },
    { key = "atkPct",       label = "攻击力百分比",   layer = "collect", field = "atkPct",        format = "pct", desc = "全体英雄攻击力百分比提升" },
    { key = "spdPct",       label = "攻击速度加成",   layer = "collect", field = "spdPct",        format = "pct", desc = "全体英雄攻击速度提升" },
    { key = "rangePct",     label = "攻击范围加成",   layer = "collect", field = "rangePct",      format = "pct", desc = "全体英雄攻击范围提升" },
    { key = "bossExtraDmg", label = "对Boss额外伤害", layer = "collect", field = "bossExtraDmg",  format = "pct", desc = "对Boss造成更多伤害" },
    { key = "stunChance",   label = "眩晕概率加成",   layer = "collect", field = "stunChance",    format = "pct", desc = "控制技能眩晕概率提升" },
    { key = "stunDuration", label = "眩晕持续加成",   layer = "collect", field = "stunDuration",  format = "pct", desc = "眩晕效果持续时间延长" },
    { key = "dotDuration",  label = "持续伤害延长",   layer = "collect", field = "dotDuration",   format = "pct", desc = "灼烧/中毒持续时间延长" },
    { key = "slowDuration", label = "减速持续加成",   layer = "collect", field = "slowDuration",  format = "pct", desc = "减速效果持续时间延长" },
    { key = "armorBreakAmp",label = "破甲效果增幅",   layer = "collect", field = "armorBreakAmp", format = "pct", desc = "破甲/碎甲减防效果增强" },
    { key = "ampDmgBonus",  label = "增伤标记强度",   layer = "collect", field = "ampDmgBonus",   format = "pct", desc = "增伤标记(amp_damage)效果提升" },
    { key = "chillAmp",     label = "冰冻增伤强度",   layer = "collect", field = "chillAmp",      format = "pct", desc = "满层寒冰时额外伤害提升" },
    { key = "critSplash",   label = "暴击溅射伤害",   layer = "collect", field = "critSplash",    format = "pct", desc = "暴击时对周围敌人溅射伤害" },
    { key = "multiShot",    label = "多重射击概率",   layer = "collect", field = "multiShot",     format = "pct", desc = "额外发射一枚投射物的概率" },
    { key = "auraBuff",     label = "光环效果增幅",   layer = "collect", field = "auraBuff",      format = "pct", desc = "英雄光环加成效果提升" },
    { key = "onKillSpdBurst", label = "击杀加速",     layer = "collect", field = "onKillSpdBurst",format = "pct", desc = "击杀后短暂提升攻击速度" },
    { key = "waveAtkScale", label = "波次攻击叠加",   layer = "collect", field = "waveAtkScale",  format = "pct", desc = "每过一波获得永久攻击加成" },
    { key = "defReducePct", label = "防御削减增幅",   layer = "collect", field = "defReducePct",  format = "pct", desc = "减防类debuff效果提升" },
}

-- 按 key 索引
M.STAT_TYPE_MAP = {}
for _, st in ipairs(M.STAT_TYPES) do
    M.STAT_TYPE_MAP[st.key] = st
end

-- ============================================================================
-- 武器道具定义（37 种，每种一个独特 statKey）
-- ============================================================================

---@class CollectibleDef
---@field id string         道具ID
---@field name string       显示名
---@field emoji string      图标
---@field color number[]    主题色 {r, g, b}
---@field category string   能力类别 key
---@field statKey string    加成属性 key（对应 STAT_TYPES.key）
---@field perItem number    每个道具提供的加成量
---@field dungeonKey string 对应的副本 key
---@field desc string       道具描述

M.ITEM_DEFS = {
    -- ================================================================
    -- 冥晶矿洞 (crystal) — 冰霜/水晶主题，6 种
    -- 主题：冰冻控制 / 减速 / 寒冰增伤
    -- ================================================================
    {
        id = "frost_longbow", name = "寒冰长弓", emoji = "🏹",
        color = { 100, 200, 255 }, category = "chain",
        statKey = "chain", perItem = 0.003, dungeonKey = "crystal",
        desc = "凝结冥晶之力的长弓，箭矢在敌群中弹射不息",
    },
    {
        id = "frostblade_swords", name = "霜锋双剑", emoji = "⚔️",
        color = { 160, 220, 255 }, category = "control",
        statKey = "slow_amp", perItem = 0.002, dungeonKey = "crystal",
        desc = "霜雪淬炼的双剑，斩击大幅减缓敌人行动",
    },
    {
        id = "ice_spike_dagger", name = "冰刺短刀", emoji = "🗡️",
        color = { 120, 180, 240 }, category = "control",
        statKey = "slowDuration", perItem = 0.003, dungeonKey = "crystal",
        desc = "锐利的冰刺短刀，冰冻效果持续更久",
    },
    {
        id = "ice_soul_tome", name = "冰魄之书", emoji = "📘",
        color = { 100, 160, 220 }, category = "skill",
        statKey = "chillAmp", perItem = 0.002, dungeonKey = "crystal",
        desc = "记载冰魄秘术的古籍，满层寒冰时爆发更强伤害",
    },
    {
        id = "frozen_amulet", name = "极寒护符", emoji = "💠",
        color = { 80, 180, 240 }, category = "control",
        statKey = "stunDuration", perItem = 0.003, dungeonKey = "crystal",
        desc = "极寒之力凝结的护符，延长冰冻眩晕时间",
    },
    {
        id = "ice_crystal_staff", name = "冰晶法杖", emoji = "❄️",
        color = { 140, 200, 255 }, category = "single",
        statKey = "magicDmgBonus", perItem = 0.001, dungeonKey = "crystal",
        desc = "冥晶凝结的法杖，强化所有魔法系英雄伤害",
    },

    -- ================================================================
    -- 噬魂深渊 (stone) — 暗影/灵魂主题，6 种
    -- 主题：暗影debuff / 易伤 / 击杀效果
    -- ================================================================
    {
        id = "soul_greatsword", name = "噬魂巨剑", emoji = "🗡️",
        color = { 80, 60, 140 }, category = "single",
        statKey = "dmgBonus", perItem = 0.0012, dungeonKey = "stone",
        desc = "吞噬灵魂的巨剑，每一击蕴含毁灭之力",
    },
    {
        id = "dark_lance", name = "暗噬长枪", emoji = "🔱",
        color = { 100, 70, 160 }, category = "pen",
        statKey = "vulnMark", perItem = 0.0015, dungeonKey = "stone",
        desc = "深渊锻造的长枪，贯穿后留下独立乘区易伤印记",
    },
    {
        id = "soul_hunter_bow", name = "灵魂猎弓", emoji = "🏹",
        color = { 120, 80, 180 }, category = "onkill",
        statKey = "killReset", perItem = 0.001, dungeonKey = "stone",
        desc = "猎取灵魂的暗弓，击杀敌人后瞬间重置攻击",
    },
    {
        id = "abyss_scepter", name = "深渊权杖", emoji = "🪄",
        color = { 90, 60, 150 }, category = "skill",
        statKey = "ampDmgBonus", perItem = 0.002, dungeonKey = "stone",
        desc = "深渊之力凝聚的权杖，增伤标记效果更强",
    },
    {
        id = "soul_reaver_blade", name = "夺魂短刃", emoji = "⚔️",
        color = { 140, 100, 200 }, category = "onkill",
        statKey = "onKillSpdBurst", perItem = 0.002, dungeonKey = "stone",
        desc = "夺取灵魂的利刃，击杀后短暂爆发攻速",
    },
    {
        id = "shadow_shield", name = "暗影战盾", emoji = "🛡️",
        color = { 80, 50, 130 }, category = "pen",
        statKey = "defReducePct", perItem = 0.002, dungeonKey = "stone",
        desc = "暗影附魔的战盾，所有减防debuff效果增强",
    },

    -- ================================================================
    -- 锻魂熔炉 (iron) — 烈焰/锻造主题，6 种
    -- 主题：灼烧DOT / 物理强化 / 暴击
    -- ================================================================
    {
        id = "flame_blade", name = "烈焰刀", emoji = "🔥",
        color = { 255, 120, 40 }, category = "aoe",
        statKey = "dot_amp", perItem = 0.0025, dungeonKey = "iron",
        desc = "熔炉中淬炼的烈刃，灼烧伤害大幅提升",
    },
    {
        id = "lava_battleaxe", name = "熔岩战斧", emoji = "🪓",
        color = { 230, 100, 30 }, category = "aoe",
        statKey = "dotDuration", perItem = 0.003, dungeonKey = "iron",
        desc = "熔岩锻造的战斧，灼烧持续更久",
    },
    {
        id = "flame_forged_bow", name = "炎铸战弓", emoji = "🏹",
        color = { 255, 160, 60 }, category = "crit",
        statKey = "critDmg", perItem = 0.0006, dungeonKey = "iron",
        desc = "烈焰淬炼的战弓，暴击引爆火焰之力",
    },
    {
        id = "forged_warhammer", name = "锻铁战锤", emoji = "🔨",
        color = { 200, 140, 50 }, category = "pen",
        statKey = "armorPen", perItem = 0.001, dungeonKey = "iron",
        desc = "重锤一击粉碎护甲，无视大量物理防御",
    },
    {
        id = "flame_staff", name = "烈焰法杖", emoji = "🔥",
        color = { 255, 80, 30 }, category = "single",
        statKey = "physDmgBonus", perItem = 0.001, dungeonKey = "iron",
        desc = "熔炉之火凝聚的法杖，强化所有物理系英雄伤害",
    },
    {
        id = "scorching_bracers", name = "灼热护腕", emoji = "🔶",
        color = { 220, 140, 40 }, category = "crit",
        statKey = "critSplash", perItem = 0.002, dungeonKey = "iron",
        desc = "灼热铁矿锻造的护腕，暴击时火花溅射周围敌人",
    },

    -- ================================================================
    -- 宝箱秘境 (chest) — 神秘/幻影主题，7 种
    -- 主题：多重射击 / 掉落运气 / 范围控制
    -- ================================================================
    {
        id = "shadow_dagger", name = "暗影匕首", emoji = "🗡️",
        color = { 160, 100, 220 }, category = "control",
        statKey = "stunChance", perItem = 0.002, dungeonKey = "chest",
        desc = "暗影之力附魔的匕首，攻击有概率眩晕敌人",
    },
    {
        id = "phantom_bow", name = "幻影弓", emoji = "🏹",
        color = { 180, 130, 240 }, category = "attack",
        statKey = "multiShot", perItem = 0.002, dungeonKey = "chest",
        desc = "幻影之力赋予的弓，有概率射出第二支箭矢",
    },
    {
        id = "mystic_scepter", name = "秘境权杖", emoji = "🪄",
        color = { 200, 160, 255 }, category = "skill",
        statKey = "cdr", perItem = 0.0015, dungeonKey = "chest",
        desc = "秘境深处发现的权杖，蕴含加速时间之力",
    },
    {
        id = "ghost_sword", name = "幽灵之剑", emoji = "⚔️",
        color = { 170, 140, 230 }, category = "crit",
        statKey = "critRate", perItem = 0.0004, dungeonKey = "chest",
        desc = "幽灵附身的魔剑，每一击都直指要害",
    },
    {
        id = "cursed_axe", name = "诅咒战斧", emoji = "🪓",
        color = { 140, 80, 200 }, category = "pen",
        statKey = "armorBreakAmp", perItem = 0.002, dungeonKey = "chest",
        desc = "被诅咒的战斧，破甲碎甲效果大幅增强",
    },
    {
        id = "fate_dice", name = "命运骰子", emoji = "🎲",
        color = { 200, 180, 255 }, category = "onkill",
        statKey = "luckyDrop", perItem = 0.0015, dungeonKey = "chest",
        desc = "命运女神的骰子，提升战利品掉落运气",
    },
    {
        id = "mystic_compass", name = "神秘罗盘", emoji = "🧭",
        color = { 220, 200, 255 }, category = "attack",
        statKey = "rangePct", perItem = 0.002, dungeonKey = "chest",
        desc = "指向远方的罗盘，增加英雄攻击范围",
    },

    -- ================================================================
    -- 秘典藏书阁 (skill_book) — 自然/智慧主题，6 种
    -- 主题：元素精通 / 光环增幅 / 波次成长
    -- ================================================================
    {
        id = "nature_staff", name = "自然法杖", emoji = "🌿",
        color = { 60, 180, 80 }, category = "buff",
        statKey = "elemMastery", perItem = 0.0025, dungeonKey = "skill_book",
        desc = "藏书阁秘典所化的法杖，精通万物元素",
    },
    {
        id = "wisdom_tome", name = "智慧之书", emoji = "📖",
        color = { 80, 160, 100 }, category = "buff",
        statKey = "auraBuff", perItem = 0.002, dungeonKey = "skill_book",
        desc = "记载古老智慧的典籍，强化英雄光环效果",
    },
    {
        id = "vine_bow", name = "藤蔓弓", emoji = "🏹",
        color = { 100, 200, 80 }, category = "attack",
        statKey = "spdPct", perItem = 0.001, dungeonKey = "skill_book",
        desc = "自然藤蔓编织的弓，提升全体英雄攻速",
    },
    {
        id = "rune_dagger", name = "符文匕首", emoji = "🗡️",
        color = { 120, 200, 120 }, category = "attack",
        statKey = "atkPct", perItem = 0.001, dungeonKey = "skill_book",
        desc = "刻满符文的匕首，符文之力增幅全体攻击",
    },
    {
        id = "ancient_scepter", name = "古木权杖", emoji = "🪵",
        color = { 140, 180, 80 }, category = "buff",
        statKey = "waveAtkScale", perItem = 0.0005, dungeonKey = "skill_book",
        desc = "千年古木化成的权杖，每过一波战斗永久提升攻击",
    },
    {
        id = "sage_amulet", name = "贤者护符", emoji = "📿",
        color = { 80, 180, 120 }, category = "pen",
        statKey = "magicPen", perItem = 0.001, dungeonKey = "skill_book",
        desc = "贤者遗留的护符，无视敌方魔法抗性",
    },

    -- ================================================================
    -- 淬魂试炼 (temper) — 灵魂/淬炼主题，6 种
    -- 主题：对Boss强化 / 攻击强化 / 终极伤害
    -- ================================================================
    {
        id = "tempered_sword", name = "淬魂剑", emoji = "⚔️",
        color = { 120, 80, 200 }, category = "attack",
        statKey = "bossExtraDmg", perItem = 0.002, dungeonKey = "temper",
        desc = "灵魂淬炼的利剑，对Boss造成额外伤害",
    },
    {
        id = "soulflame_staff", name = "魂焰法杖", emoji = "🔮",
        color = { 140, 60, 220 }, category = "skill",
        statKey = "cdr", perItem = 0.0018, dungeonKey = "temper",
        desc = "灵魂之火凝聚的法杖，大幅加速术法释放",
    },
    {
        id = "purgatory_axe", name = "炼狱战斧", emoji = "🪓",
        color = { 180, 60, 180 }, category = "aoe",
        statKey = "armorBreakAmp", perItem = 0.0025, dungeonKey = "temper",
        desc = "炼狱之火淬炼的战斧，碎甲效果极大增强",
    },
    {
        id = "purifying_bow", name = "净魂弓", emoji = "🏹",
        color = { 160, 100, 240 }, category = "chain",
        statKey = "chain", perItem = 0.003, dungeonKey = "temper",
        desc = "净化灵魂的圣弓，箭矢净化连锁一切邪恶",
    },
    {
        id = "soul_dagger", name = "灵魂匕首", emoji = "🗡️",
        color = { 100, 60, 200 }, category = "onkill",
        statKey = "killReset", perItem = 0.0015, dungeonKey = "temper",
        desc = "收割灵魂的匕首，击杀后瞬间恢复攻击",
    },
    {
        id = "tempered_shield", name = "淬炼护盾", emoji = "🛡️",
        color = { 140, 100, 220 }, category = "buff",
        statKey = "elemMastery", perItem = 0.002, dungeonKey = "temper",
        desc = "灵魂淬炼的护盾，增幅全元素精通",
    },
}

-- ============================================================================
-- 索引构建
-- ============================================================================

-- 按 id 索引
M.ITEM_MAP = {}
for _, def in ipairs(M.ITEM_DEFS) do
    M.ITEM_MAP[def.id] = def
end

-- 按 dungeonKey 索引（一个副本 → 多个道具）
M.DUNGEON_ITEMS = {}
for _, def in ipairs(M.ITEM_DEFS) do
    if not M.DUNGEON_ITEMS[def.dungeonKey] then
        M.DUNGEON_ITEMS[def.dungeonKey] = {}
    end
    local list = M.DUNGEON_ITEMS[def.dungeonKey]
    list[#list + 1] = def
end

-- 按 category 索引（一个类别 → 多个道具）
M.CATEGORY_ITEMS = {}
for _, def in ipairs(M.ITEM_DEFS) do
    if not M.CATEGORY_ITEMS[def.category] then
        M.CATEGORY_ITEMS[def.category] = {}
    end
    local list = M.CATEGORY_ITEMS[def.category]
    list[#list + 1] = def
end

-- 按 statKey 索引（一种加成 → 多个道具，少数重复加成共享同一 key）
M.STAT_ITEMS = {}
for _, def in ipairs(M.ITEM_DEFS) do
    if not M.STAT_ITEMS[def.statKey] then
        M.STAT_ITEMS[def.statKey] = {}
    end
    local list = M.STAT_ITEMS[def.statKey]
    list[#list + 1] = def
end

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 获取收集持久化数据（惰性初始化）
---@return table  { [itemId] = count }
function M.GetData()
    if not HeroData.collectibles then
        HeroData.collectibles = {}
        for _, def in ipairs(M.ITEM_DEFS) do
            HeroData.collectibles[def.id] = 0
        end
    end
    -- 兼容旧存档：补齐新增道具
    for _, def in ipairs(M.ITEM_DEFS) do
        if HeroData.collectibles[def.id] == nil then
            HeroData.collectibles[def.id] = 0
        end
    end
    return HeroData.collectibles
end

--- 获取某种道具的数量
---@param itemId string
---@return number
function M.GetCount(itemId)
    local data = M.GetData()
    return data[itemId] or 0
end

--- 增加道具数量
---@param itemId string
---@param amount number
function M.Add(itemId, amount)
    if amount <= 0 then return end
    local data = M.GetData()
    data[itemId] = (data[itemId] or 0) + amount
    local def = M.ITEM_MAP[itemId]
    local name = def and def.name or itemId
    print("[Collectible] +" .. amount .. " " .. name .. " → total=" .. data[itemId])
end

-- ============================================================================
-- 掉落计算
-- ============================================================================

--- 难度等级对应的掉落倍率
local DIFF_DROP_MULT = { 1.0, 1.5, 2.0, 2.5, 3.0 }

--- 计算副本通关道具掉落
--- 每次通关从该副本道具池中随机选 2~3 种，各掉落一定数量
---@param dungeonKey string  副本 key
---@param clearedWave number 通关波次
---@param diffLevel number   难度等级(0~4)
---@return table drops  { { id=string, name=string, amount=number, def=CollectibleDef } }
function M.CalcDungeonDrop(dungeonKey, clearedWave, diffLevel)
    local pool = M.DUNGEON_ITEMS[dungeonKey]
    if not pool or #pool == 0 then return {} end

    diffLevel = diffLevel or 0
    local diffMult = DIFF_DROP_MULT[diffLevel + 1] or 1.0

    -- 总掉落量基础公式
    local totalBase = math.floor((3 + clearedWave * 0.5) * diffMult)
    totalBase = math.max(2, totalBase)

    -- 随机选 2~3 种道具（高难度/高波次可选更多）
    local pickCount = 2
    if clearedWave >= 10 or diffLevel >= 2 then pickCount = 3 end
    pickCount = math.min(pickCount, #pool)

    -- Fisher-Yates 洗牌取前 N 个
    local indices = {}
    for i = 1, #pool do indices[i] = i end
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    -- 分配掉落量：均分 + 随机浮动
    local drops = {}
    local baseEach = math.floor(totalBase / pickCount)
    local remainder = totalBase - baseEach * pickCount

    for p = 1, pickCount do
        local idx = indices[p]
        local def = pool[idx]
        local amount = baseEach
        -- 余量随机分配
        if remainder > 0 then
            amount = amount + 1
            remainder = remainder - 1
        end
        -- ±20% 随机浮动
        local variance = math.max(1, math.floor(amount * 0.2))
        amount = amount + math.random(-variance, variance)
        amount = math.max(1, amount)

        drops[#drops + 1] = {
            id     = def.id,
            name   = def.name,
            amount = amount,
            def    = def,
        }
    end

    return drops
end

-- ============================================================================
-- 加成计算（供 Tower.BuildTowerStats 调用）
-- ============================================================================

--- 获取收集道具提供的全部属性加成，按注入层分类返回
---@return table runeAdd     runeBonus 叠加项 { chain=0.01, slow_amp=0.005, ... }
---@return table statAdd     tower 基础属性叠加项 { critRate=0.002, armorPen=0.01, ... }
---@return table collectAdd  收集专属加成项 { magicPen=0.01, atkPct=0.02, bossExtraDmg=0.03, ... }
function M.GetBonus()
    local data = M.GetData()
    local runeAdd = {}
    local statAdd = {}
    local collectAdd = {}

    for _, def in ipairs(M.ITEM_DEFS) do
        local count = data[def.id] or 0
        if count > 0 then
            local st = M.STAT_TYPE_MAP[def.statKey]
            if st then
                local bonus = count * def.perItem
                if st.layer == "rune" then
                    runeAdd[st.field] = (runeAdd[st.field] or 0) + bonus
                elseif st.layer == "stat" then
                    statAdd[st.field] = (statAdd[st.field] or 0) + bonus
                else -- "collect"
                    collectAdd[st.field] = (collectAdd[st.field] or 0) + bonus
                end
            end
        end
    end
    return runeAdd, statAdd, collectAdd
end

--- 获取按加成类型汇总的加成值（便于快速查询单个加成总量）
---@return table bonusMap  { [statKey] = totalBonusValue }
function M.GetBonusMap()
    local data = M.GetData()
    local map = {}
    for _, def in ipairs(M.ITEM_DEFS) do
        local count = data[def.id] or 0
        if count > 0 then
            map[def.statKey] = (map[def.statKey] or 0) + count * def.perItem
        end
    end
    return map
end

--- 获取按能力类别汇总的加成（供 UI 展示）
---@return table[] list { { category, items = { {def, count, bonus, statType} } } }
function M.GetCategoryDetail()
    local data = M.GetData()
    local result = {}

    for _, cat in ipairs(M.CATEGORIES) do
        local items = M.CATEGORY_ITEMS[cat.key]
        if items and #items > 0 then
            local entry = {
                category = cat,
                items    = {},
            }
            for _, def in ipairs(items) do
                local count = data[def.id] or 0
                local bonus = count * def.perItem
                local st = M.STAT_TYPE_MAP[def.statKey]
                entry.items[#entry.items + 1] = {
                    def      = def,
                    count    = count,
                    bonus    = bonus,
                    statType = st,
                }
            end
            result[#result + 1] = entry
        end
    end
    return result
end

--- 获取收集明细（平铺列表，供简单 UI 展示）
---@return table[] list { { def, count, bonus, bonusPct, statType } }
function M.GetDetailList()
    local data = M.GetData()
    local list = {}
    for _, def in ipairs(M.ITEM_DEFS) do
        local count = data[def.id] or 0
        local bonus = count * def.perItem
        local st = M.STAT_TYPE_MAP[def.statKey]
        list[#list + 1] = {
            def      = def,
            count    = count,
            bonus    = bonus,
            bonusPct = string.format("%.1f%%", bonus * 100),
            statType = st,
        }
    end
    return list
end

--- 获取总收集数量（供 UI 概览展示）
---@return number total, number types
function M.GetTotalStats()
    local data = M.GetData()
    local total = 0
    local types = 0
    for _, def in ipairs(M.ITEM_DEFS) do
        local count = data[def.id] or 0
        total = total + count
        if count > 0 then types = types + 1 end
    end
    return total, types
end

--- 获取某副本的收集进度
---@param dungeonKey string
---@return number collected 已收集种类数
---@return number totalTypes 该副本总道具种类
---@return number totalCount 该副本总收集数量
function M.GetDungeonProgress(dungeonKey)
    local pool = M.DUNGEON_ITEMS[dungeonKey]
    if not pool then return 0, 0, 0 end
    local data = M.GetData()
    local collected, totalCount = 0, 0
    for _, def in ipairs(pool) do
        local count = data[def.id] or 0
        totalCount = totalCount + count
        if count > 0 then collected = collected + 1 end
    end
    return collected, #pool, totalCount
end

--- 获取加成类型统计信息（不同 statKey 的种类数）
---@return number uniqueStatCount 独立加成类型数
function M.GetUniqueStatCount()
    local seen = {}
    for _, def in ipairs(M.ITEM_DEFS) do
        seen[def.statKey] = true
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    return n
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

SaveRegistry.Register("collectibles", {
    group = "meta_game",
    order = 56,
    initDefault = function()
        HeroData.collectibles = nil  -- GetData() 惰性初始化
    end,
    serialize = function()
        local data = M.GetData()
        local saved = {}
        for id, count in pairs(data) do
            if count > 0 then
                saved[id] = count
            end
        end
        return saved
    end,
    deserialize = function(saved, _saveData)
        if saved and next(saved) then
            HeroData.collectibles = {}
            -- 加载所有已定义道具
            for _, def in ipairs(M.ITEM_DEFS) do
                HeroData.collectibles[def.id] = saved[def.id] or 0
            end
            -- 兼容旧魂晶存档迁移（sc_* → 对应新道具第一个）
            local MIGRATE_MAP = {
                sc_atk     = "frost_longbow",
                sc_crit    = "soul_greatsword",
                sc_pen     = "flame_blade",
                sc_critdmg = "shadow_dagger",
                sc_dmg     = "nature_staff",
                sc_spd     = "soulflame_staff",
            }
            for oldId, newId in pairs(MIGRATE_MAP) do
                if saved[oldId] and saved[oldId] > 0 then
                    HeroData.collectibles[newId] = (HeroData.collectibles[newId] or 0) + saved[oldId]
                    print("[CollectibleData] Migrated " .. oldId .. "=" .. saved[oldId] .. " → " .. newId)
                end
            end
            -- 保留未识别的旧 ID 数据（可能是未来新增道具的存档）
            for id, count in pairs(saved) do
                if count > 0 and not M.ITEM_MAP[id] and not MIGRATE_MAP[id] then
                    HeroData.collectibles[id] = count
                end
            end
            local totalStr = ""
            for _, def in ipairs(M.ITEM_DEFS) do
                if (HeroData.collectibles[def.id] or 0) > 0 then
                    totalStr = totalStr .. def.name .. "=" .. HeroData.collectibles[def.id] .. " "
                end
            end
            print("[CollectibleData] Deserialized: " .. (totalStr ~= "" and totalStr or "empty"))
        else
            HeroData.collectibles = nil
            print("[CollectibleData] Deserialized: no saved data")
        end
    end,
})

return M
