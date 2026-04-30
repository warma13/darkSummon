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
    -- 第3层：技能标签词条 —— 精确匹配 HERO_SKILL_TAGS 的标签 id
    -- ========================================================================
    tag_affixes = {
        -- === 控制标签 ===
        {
            id    = "tag_frost_eff",
            name  = "寒霜共鸣",
            desc  = "带[寒霜]标签的技能：减速率+{v}%，持续时间+{v2}秒",
            tags  = { "frost" },
            stat  = "tagSlowRate_add",  stat2 = "tagSlowDur_add",
            minVal = 0.08, maxVal = 0.20,
            minVal2 = 0.3,  maxVal2 = 1.0,
            tier  = 3,
        },
        {
            id    = "tag_frozen_chance",
            name  = "极寒之心",
            desc  = "带[冰封]标签的技能：冰封概率+{v}%",
            tags  = { "frozen", "absolute_zero" },
            stat  = "tagFreezeChance_add",
            minVal = 0.05, maxVal = 0.15,
            tier  = 3,
        },

        -- === 物理输出标签 ===
        {
            id    = "tag_armorbreak_amp",
            name  = "锐利碎甲",
            desc  = "带[破甲]标签的技能：每层破甲效果+{v}%",
            tags  = { "armor_break", "shatter", "aftershock" },
            stat  = "tagArmorBreak_amp",
            minVal = 0.15, maxVal = 0.40,
            tier  = 3,
        },
        {
            id    = "tag_assassin_burst",
            name  = "暗影猎杀",
            desc  = "带[暗刺]标签的技能：首击伤害+{v}%",
            tags  = { "dark_stab", "lethal" },
            stat  = "tagAssassinBurst_pct",
            minVal = 0.15, maxVal = 0.40,  -- 条件词条允许偏强, 从50%→40%
            tier  = 3,
        },

        -- === 法术输出标签 ===
        {
            id    = "tag_burn_dmg",
            name  = "燎原之火",
            desc  = "带[燃烧/灼烧]标签的技能伤害+{v}%",
            tags  = { "scorch", "ignite", "prairie_fire", "searing" },
            stat  = "tagBurnDmg_pct",
            minVal = 0.12, maxVal = 0.35,  -- 覆盖4个标签过广, 从45%→35%
            tier  = 3,
        },
        {
            id    = "tag_chain_amp",
            name  = "连锁裂变",
            desc  = "带[链式]标签的技能：链式跳跃数+{v}，每跳衰减-{v2}%",
            tags  = { "dark_chain", "shadow_chain", "ember_chain" },
            stat  = "tagChainBounce_add", stat2 = "tagChainDecay_reduce",
            minVal = 1, maxVal = 2,        -- +3跳过强, 从3→2
            minVal2 = 0.03, maxVal2 = 0.10, -- 衰减减少也相应收敛
            tier  = 3,
        },
        {
            id    = "tag_dot_amp",
            name  = "蚀骨侵蚀",
            desc  = "带[DOT]标签的技能：持续伤害+{v}%，持续时间+{v2}秒",
            tags  = { "plague", "infect_spread", "ulcerate", "burn_stack" },
            stat  = "tagDotDmg_pct", stat2 = "tagDotDur_add",
            minVal = 0.15, maxVal = 0.40,
            minVal2 = 0.5,  maxVal2 = 2.0,
            tier  = 3,
        },

        -- === 暴击标签 ===
        {
            id    = "tag_infernal_crit",
            name  = "魔焰共振",
            desc  = "带[魔焰]标签的技能：每层暴击率额外+{v}%",
            tags  = { "infernal_stack" },
            stat  = "tagInfernalCrit_add",
            minVal = 0.02, maxVal = 0.06,
            tier  = 3,
        },
        {
            id    = "tag_erosion_pure",
            name  = "永恒侵蚀·真",
            desc  = "带[侵蚀]标签的技能：真伤转化率+{v}%",
            tags  = { "erosion" },
            stat  = "tagErosionPure_add",
            minVal = 0.08, maxVal = 0.20,
            tier  = 3,
        },

        -- === 辅助标签 ===
        {
            id    = "tag_buff_amp",
            name  = "战歌回响",
            desc  = "带[战歌/光环]标签的技能：增益效果+{v}%",
            tags  = { "war_song", "inspire", "hero_song", "shadow_domain", "nature_aura" },
            stat  = "tagBuffAmp_pct",
            minVal = 0.12, maxVal = 0.35,
            tier  = 3,
        },

        -- === 标记/易伤标签 ===
        {
            id    = "tag_mark_vuln",
            name  = "猎物标记",
            desc  = "带[标记]标签的技能：易伤效果+{v}%",
            tags  = { "abyss_mark", "hunt_announce", "penetrate_mark", "weakness_lock" },
            stat  = "tagMarkVuln_add",
            minVal = 0.08, maxVal = 0.25,
            tier  = 3,
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

    -- 第3层：技能标签（权重 1，稀有毕业词条）
    { id = "tag_frost_eff",       affixTier = 3, weight = 1 },
    { id = "tag_frozen_chance",   affixTier = 3, weight = 1 },
    { id = "tag_armorbreak_amp",  affixTier = 3, weight = 1 },
    { id = "tag_assassin_burst",  affixTier = 3, weight = 1 },
    { id = "tag_burn_dmg",        affixTier = 3, weight = 1 },
    { id = "tag_chain_amp",       affixTier = 3, weight = 1 },
    { id = "tag_dot_amp",         affixTier = 3, weight = 1 },
    { id = "tag_infernal_crit",   affixTier = 3, weight = 1 },
    { id = "tag_erosion_pure",    affixTier = 3, weight = 1 },
    { id = "tag_buff_amp",        affixTier = 3, weight = 1 },
    { id = "tag_mark_vuln",       affixTier = 3, weight = 1 },
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
