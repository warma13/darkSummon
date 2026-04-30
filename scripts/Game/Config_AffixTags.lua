-- Game/Config_AffixTags.lua
-- 三层词条体系：角色类别(T1) / 技能类型(T2) / 技能标签(T3)
-- 嵌入符文特殊词条池 & 淬炼词条池，通过 AffixTagResolver 条件匹配生效

local function apply(Config)

-- ============================================================================
-- 三层词条定义
-- ============================================================================
Config.AFFIX_TAG_SYSTEM = {

    -- ========================================================================
    -- 第1层：角色类别词条 —— 按 HERO_ROLE 匹配
    -- ========================================================================
    role_affixes = {
        {
            id       = "role_dps_atk",
            name     = "猎手之力",
            desc     = "战士/刺客类英雄攻击力+{v}%",
            roles    = { "dps", "burst", "sniper", "crit", "boss_killer" },
            stat     = "atk_pct",
            minVal   = 0.06, maxVal = 0.18,
            tier     = 1,
        },
        {
            id       = "role_caster_dmg",
            name     = "智者之力",
            desc     = "术师类英雄技能伤害+{v}%",
            roles    = { "caster", "chain", "dot" },
            stat     = "skillDmg_pct",
            minVal   = 0.06, maxVal = 0.18,
            tier     = 1,
        },
        {
            id       = "role_control_dur",
            name     = "支配之力",
            desc     = "控制类英雄控制效果持续时间+{v}%",
            roles    = { "control", "slow", "freeze", "stun" },
            stat     = "ctrlDuration_pct",
            minVal   = 0.08, maxVal = 0.20,
            tier     = 1,
        },
        {
            id       = "role_support_eff",
            name     = "祝福之力",
            desc     = "辅助类英雄增益效果+{v}%",
            roles    = { "support", "buff", "aura" },
            stat     = "buffEffect_pct",
            minVal   = 0.08, maxVal = 0.22,
            tier     = 1,
        },
        {
            id       = "role_breaker_pen",
            name     = "碎甲之力",
            desc     = "破防类英雄穿透效果+{v}%",
            roles    = { "breaker", "armor" },
            stat     = "penEffect_pct",
            minVal   = 0.06, maxVal = 0.15,  -- 穿透乘算叠加过强, 从20%→15%
            tier     = 1,
        },
    },

    -- ========================================================================
    -- 第2层：技能类型词条 —— 按 HERO_SKILL_TAGS 的 type 字段匹配
    -- ========================================================================
    skilltype_affixes = {
        {
            id         = "stype_onhit_dmg",
            name       = "命中强化",
            desc       = "所有[命中型]技能伤害+{v}%",
            skillTypes = { "on_hit" },
            stat       = "onhitDmg_pct",
            minVal     = 0.10, maxVal = 0.25,
            tier       = 2,
        },
        {
            id         = "stype_oncrit_dmg",
            name       = "暴击专精",
            desc       = "所有[暴击触发型]技能伤害+{v}%",
            skillTypes = { "on_crit" },
            stat       = "oncritDmg_pct",
            minVal     = 0.10, maxVal = 0.25,
            tier       = 2,
        },
        {
            id         = "stype_active_cdr",
            name       = "战术精通",
            desc       = "所有[主动型]技能冷却-{v}%",
            skillTypes = { "active" },
            stat       = "activeCdr_pct",
            minVal     = 0.08, maxVal = 0.22,
            tier       = 2,
        },
        {
            id         = "stype_aura_range",
            name       = "领域扩展",
            desc       = "所有[光环型]技能范围+{v}%，效果+{v2}%",
            skillTypes = { "aura" },
            stat       = "auraRange_pct",
            stat2      = "auraEffect_pct",
            minVal     = 0.08, maxVal = 0.20,
            minVal2    = 0.05, maxVal2 = 0.12,
            tier       = 2,
        },
        {
            id         = "stype_passive_trigger",
            name       = "天赋觉醒",
            desc       = "所有[被动/条件型]技能触发率+{v}%",
            skillTypes = { "conditional", "on_kill" },
            stat       = "passiveTrigger_pct",
            minVal     = 0.12, maxVal = 0.30,
            tier       = 2,
        },
    },

    -- ========================================================================
    -- 第3层：效果类别词条 —— 按 HERO_SKILL_TAGS 的 category 字段匹配
    -- 每个类别覆盖 8-23 个标签（跨 8-15 个英雄），换英雄不废
    -- ========================================================================
    tag_affixes = {
        -- === dot：持续伤害类 (18标签, 覆盖~10英雄) ===
        {
            id         = "cat_dot_amp",
            name       = "蚀骨侵蚀",
            desc       = "[持续伤害]类技能：伤害+{v}%，持续时间+{v2}秒",
            categories = { "dot" },
            stat       = "tagDotDmg_pct",  stat2 = "tagDotDur_add",
            minVal     = 0.06, maxVal = 0.16,
            minVal2    = 0.2,  maxVal2 = 0.6,
            tier       = 3,
        },
        -- === burst：爆发伤害类 (23标签, 覆盖~15英雄) ===
        {
            id         = "cat_burst_dmg",
            name       = "致命一击",
            desc       = "[爆发伤害]类技能：伤害+{v}%",
            categories = { "burst" },
            stat       = "tagBurstDmg_pct",
            minVal     = 0.08, maxVal = 0.22,
            tier       = 3,
        },
        -- === control：控制效果类 (10标签, 覆盖~6英雄) ===
        {
            id         = "cat_control_eff",
            name       = "寒霜枷锁",
            desc       = "[控制效果]类技能：控制概率+{v}%，持续时间+{v2}秒",
            categories = { "control" },
            stat       = "tagCtrlChance_add",  stat2 = "tagCtrlDur_add",
            minVal     = 0.04, maxVal = 0.12,
            minVal2    = 0.2,  maxVal2 = 0.5,
            tier       = 3,
        },
        -- === defense_shred：削弱防御类 (10标签, 覆盖~7英雄) ===
        {
            id         = "cat_shred_amp",
            name       = "锐利碎甲",
            desc       = "[削弱防御]类技能：破甲/穿透效果+{v}%",
            categories = { "defense_shred" },
            stat       = "tagShredAmp_pct",
            minVal     = 0.06, maxVal = 0.18,
            tier       = 3,
        },
        -- === buff_aura：增益光环类 (11标签, 覆盖~5英雄) ===
        {
            id         = "cat_buff_amp",
            name       = "战歌回响",
            desc       = "[增益光环]类技能：增益效果+{v}%",
            categories = { "buff_aura" },
            stat       = "tagBuffAmp_pct",
            minVal     = 0.06, maxVal = 0.18,
            tier       = 3,
        },
        -- === on_kill：击杀触发类 (10标签, 覆盖~9英雄) ===
        {
            id         = "cat_onkill_bonus",
            name       = "猎杀本能",
            desc       = "[击杀触发]类技能：触发效果+{v}%",
            categories = { "on_kill" },
            stat       = "tagOnKillAmp_pct",
            minVal     = 0.08, maxVal = 0.22,
            tier       = 3,
        },
        -- === stack_ramp：层数叠加类 (8标签, 覆盖~7英雄) ===
        {
            id         = "cat_stack_eff",
            name       = "厚积薄发",
            desc       = "[层数叠加]类技能：每层效果+{v}%",
            categories = { "stack_ramp" },
            stat       = "tagStackAmp_pct",
            minVal     = 0.04, maxVal = 0.12,
            tier       = 3,
        },
    },
}

-- ============================================================================
-- 快速查找表：按 id 索引所有三层词条定义
-- ============================================================================
Config.AFFIX_TAG_LOOKUP = {}

for _, pool in ipairs({ "role_affixes", "skilltype_affixes", "tag_affixes" }) do
    for _, def in ipairs(Config.AFFIX_TAG_SYSTEM[pool]) do
        Config.AFFIX_TAG_LOOKUP[def.id] = def
    end
end

-- ============================================================================
-- 符文系统：三层词条注入权重
-- 用于 Config_Runes.lua 的 AFFIX_SPECIAL 扩展
-- ============================================================================
Config.AFFIX_TAG_RUNE_ENTRIES = {
    -- 第1层：角色类别（权重 5-6，容易出）
    { id = "role_dps_atk",     affixTier = 1, weight = 6 },
    { id = "role_caster_dmg",  affixTier = 1, weight = 6 },
    { id = "role_control_dur", affixTier = 1, weight = 5 },
    { id = "role_support_eff", affixTier = 1, weight = 5 },
    { id = "role_breaker_pen", affixTier = 1, weight = 5 },

    -- 第2层：技能类型（权重 2-3，较难出）
    { id = "stype_onhit_dmg",      affixTier = 2, weight = 3 },
    { id = "stype_oncrit_dmg",     affixTier = 2, weight = 3 },
    { id = "stype_active_cdr",     affixTier = 2, weight = 3 },
    { id = "stype_aura_range",     affixTier = 2, weight = 2 },
    { id = "stype_passive_trigger",affixTier = 2, weight = 2 },

    -- 第3层：效果类别（权重 1，稀有毕业词条，每条覆盖多英雄）
    { id = "cat_dot_amp",       affixTier = 3, weight = 1 },
    { id = "cat_burst_dmg",     affixTier = 3, weight = 1 },
    { id = "cat_control_eff",   affixTier = 3, weight = 1 },
    { id = "cat_shred_amp",     affixTier = 3, weight = 1 },
    { id = "cat_buff_amp",      affixTier = 3, weight = 1 },
    { id = "cat_onkill_bonus",  affixTier = 3, weight = 1 },
    { id = "cat_stack_eff",     affixTier = 3, weight = 1 },
}

-- ============================================================================
-- 淬炼系统：三层词条注入
-- 用于 Config_Meta.lua 的 TEMPER_ATTRIBUTES 扩展
-- 淬炼只出第1/2层，第3层专属符文（保证符文独特价值）
-- ============================================================================
Config.AFFIX_TAG_TEMPER_ENTRIES = {
    -- 第1层：淬炼橙色及以上品质可出
    -- maxValue 与基础词条对齐(红档≈10% DPS), 条件词条可略高
    { id = "role_dps_atk",     affixTier = 1, maxValue = 0.14, minTemperTier = "orange" },
    { id = "role_caster_dmg",  affixTier = 1, maxValue = 0.14, minTemperTier = "orange" },
    { id = "role_control_dur", affixTier = 1, maxValue = 0.15, minTemperTier = "orange" },
    { id = "role_support_eff", affixTier = 1, maxValue = 0.16, minTemperTier = "orange" },
    { id = "role_breaker_pen", affixTier = 1, maxValue = 0.12, minTemperTier = "orange" },  -- 穿透乘算, 需严控

    -- 第2层：淬炼红色品质可出
    { id = "stype_onhit_dmg",       affixTier = 2, maxValue = 0.18, minTemperTier = "red" },
    { id = "stype_oncrit_dmg",      affixTier = 2, maxValue = 0.18, minTemperTier = "red" },
    { id = "stype_active_cdr",      affixTier = 2, maxValue = 0.16, minTemperTier = "red" },
    { id = "stype_aura_range",      affixTier = 2, maxValue = 0.14, minTemperTier = "red" },
    { id = "stype_passive_trigger", affixTier = 2, maxValue = 0.20, minTemperTier = "red" },
}

-- ============================================================================
-- 装备套装：高品质套装追加词条效果
-- ============================================================================
Config.EQUIP_SET_AFFIX_BONUS = {
    -- 橙色套装(tier 4)：全角色类别 +5% 攻击（第1层泛效果）
    [4] = { allRoleAtk_pct = 0.05 },
    -- 红色套装(tier 5)：全角色类别 +8% 攻击 + 全技能类型冷却-5%
    [5] = { allRoleAtk_pct = 0.08, allSkillTypeCdr_pct = 0.05 },
}

-- ============================================================================
-- 辅助函数：按英雄 id 和标签 id 查找标签定义
-- ============================================================================
---@param heroId string 英雄类型 id
---@param tagId string 标签 id
---@return table|nil tagDef 标签定义
function Config.FindTagDef(heroId, tagId)
    local heroTags = Config.HERO_SKILL_TAGS and Config.HERO_SKILL_TAGS[heroId]
    if not heroTags then return nil end
    for _, tag in ipairs(heroTags) do
        if tag.id == tagId then return tag end
    end
    return nil
end

-- ============================================================================
-- 辅助函数：格式化词条描述
-- ============================================================================
---@param def table 词条定义
---@param value number 词条数值
---@param value2 number|nil 双数值词条的第二个值
---@return string
function Config.FormatAffixDesc(def, value, value2)
    local desc = def.desc
    if def.stat and value then
        local pct = math.floor(value * 100 + 0.5)
        desc = desc:gsub("{v}", tostring(pct))
    end
    if def.stat2 and value2 then
        if def.tier == 3 and (def.stat2:find("Dur") or def.stat2:find("dur")) then
            -- 持续时间类：保留1位小数的秒数
            desc = desc:gsub("{v2}", string.format("%.1f", value2))
        else
            local pct2 = math.floor(value2 * 100 + 0.5)
            desc = desc:gsub("{v2}", tostring(pct2))
        end
    end
    return desc
end

-- ============================================================================
-- 词条层级颜色（UI 展示用）
-- ============================================================================
Config.AFFIX_TIER_COLORS = {
    [1] = { 100, 220, 100 },   -- 绿色（第1层：角色类别）
    [2] = {  80, 160, 255 },   -- 蓝色（第2层：技能类型）
    [3] = { 200, 120, 255 },   -- 紫色（第3层：技能标签）
}

Config.AFFIX_TIER_NAMES = {
    [1] = "角色类别",
    [2] = "技能类型",
    [3] = "技能标签",
}

end -- apply

return apply
