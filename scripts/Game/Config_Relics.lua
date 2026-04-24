-- Game/Config_Relics.lua
-- 神圣遗物系统静态配置
-- 品质体系、遗物定义、升级/升星费用、掉落权重

local function apply(Config)

-- ============================================================================
-- 品质体系
-- ============================================================================

Config.RELIC_QUALITIES = {
    { id = "green",  name = "精良", color = {100, 200, 100}, mult = 1.0 },
    { id = "blue",   name = "稀有", color = {80, 150, 255},  mult = 1.8 },
    { id = "purple", name = "史诗", color = {180, 100, 255}, mult = 3.0 },
    { id = "orange", name = "传说", color = {255, 180, 50},  mult = 5.0 },
    { id = "red",    name = "神话", color = {220, 40, 40},   mult = 8.0 },
}

--- 品质倍率映射（relicId → mult）
Config.RELIC_QUALITY_MULT = {}
--- 品质名称映射
Config.RELIC_QUALITY_NAME = {}
--- 品质颜色映射
Config.RELIC_QUALITY_COLOR = {}
--- 品质索引映射（id → 1~5）
Config.RELIC_QUALITY_INDEX = {}

for i, q in ipairs(Config.RELIC_QUALITIES) do
    Config.RELIC_QUALITY_MULT[q.id] = q.mult
    Config.RELIC_QUALITY_NAME[q.id] = q.name
    Config.RELIC_QUALITY_COLOR[q.id] = q.color
    Config.RELIC_QUALITY_INDEX[q.id] = i
end

-- ============================================================================
-- 部位定义
-- ============================================================================

Config.RELIC_SLOTS = {
    { id = "power", name = "神之力", icon = "image/relic_slot_power_20260424084412.png" },
    { id = "heart", name = "神之心", icon = "image/relic_slot_heart_20260424084409.png" },
    { id = "eye",   name = "神之眼", icon = "image/relic_slot_eye_20260424084411.png" },
    { id = "will",  name = "神之意志", icon = "image/relic_slot_will_20260424084413.png" },
}

Config.RELIC_SLOT_IDS = { "power", "heart", "eye", "will" }

-- 碎片资源ID映射（已废弃，保留兼容旧存档迁移）
Config.RELIC_SHARD_IDS = {
    power = "power_shard",
    heart = "heart_shard",
    eye   = "eye_shard",
    will  = "will_shard",
}

-- 碎片模式：per-relic（每件遗物独立碎片）
-- shards 存储结构: { [relicId] = count, ... }
Config.RELIC_SHARD_MODE = "per_relic"

-- ============================================================================
-- 遗物定义（4 部位 × 5 遗物 = 20 件）
-- ============================================================================
-- minQuality: 最低掉落品质
-- slot: 所属部位
-- params: 基础参数值（green Lv1 ★0 基准，运行时通过 V() 缩放）
-- hasCharge: 是否使用充能机制
-- linkSlot / linkRelic: 跨部位联动条件

Config.RELICS = {
    -- ==================== 神之力 (power) ====================
    judgment_spear = {
        id = "judgment_spear",
        name = "裁决之矛",
        desc = "充能满后，基于最强英雄攻击力造成{damageMult}倍伤害并额外穿透{armorPenBonus}护甲",
        slot = "power",
        minQuality = "green",
        hasCharge = true,
        params = {
            damageMult = 2.50,
            armorPenBonus = 0.15,
            armorPenCap = 0.80,
        },
        starEffect = { type = "chargeReduce", max = 15, halfStar = 4, desc = "★充能需求-{v}" },
    },
    void_pulse = {
        id = "void_pulse",
        name = "虚空脉冲",
        desc = "全体英雄攻击力+{atkBonus}；每{pulseInterval}秒释放脉冲，基于全体英雄平均攻击力造成{pulseDamageMult}倍伤害",
        slot = "power",
        minQuality = "blue",
        hasCharge = false,
        params = {
            atkBonus = 0.08,
            pulseInterval = 10.0,
            pulseDamageMult = 0.50,
        },
        starEffect = { type = "intervalReduce", max = 3.0, halfStar = 3, desc = "★脉冲间隔-{v}秒" },
    },
    annihilation_storm = {
        id = "annihilation_storm",
        name = "湮灭风暴",
        desc = "充能满后释放风暴，基于最强英雄攻击力造成{damageMult}倍范围伤害",
        slot = "power",
        minQuality = "purple",
        hasCharge = true,
        params = {
            damageMult = 1.80,
        },
        starEffect = { type = "chargeReduce", max = 15, halfStar = 4, desc = "★充能需求-{v}" },
    },
    fate_reaper = {
        id = "fate_reaper",
        name = "命运收割",
        desc = "充能满后收割目标：生命值低于{executeThreshold}时直接斩杀，否则基于最强英雄攻击力造成{nonExecuteDmg}倍伤害",
        slot = "power",
        minQuality = "orange",
        hasCharge = true,
        params = {
            executeThreshold = 0.10,
            executeCap = 0.35,
            nonExecuteDmg = 3.00,
        },
        starEffect = { type = "chargeReduce", max = 15, halfStar = 4, desc = "★充能需求-{v}" },
    },
    end_light = {
        id = "end_light",
        name = "终焉之光",
        desc = "充能满后释放终焉之光，基于最强英雄攻击力造成{trueDamageMult}倍真实伤害，并附加{burnTotalMult}倍灼烧（{burnDuration}秒{burnTicks}跳）",
        slot = "power",
        minQuality = "red",
        hasCharge = true,
        params = {
            trueDamageMult = 4.00,
            burnTotalMult = 1.20,
            burnDuration = 3.0,
            burnTicks = 6,
        },
        starEffect = { type = "chargeReduce", max = 15, halfStar = 4, desc = "★充能需求-{v}" },
    },

    -- ==================== 神之心 (heart) ====================
    life_torrent = {
        id = "life_torrent",
        name = "生命洪流",
        desc = "生命之力涌动，全体英雄攻击力+{atkBonus}",
        slot = "heart",
        minQuality = "green",
        hasCharge = false,
        params = {
            atkBonus = 0.10,
        },
        starEffect = { type = "critDmg", max = 0.20, halfStar = 4, desc = "★暴击伤害+{v}" },
    },
    war_core = {
        id = "war_core",
        name = "战意之核",
        desc = "战意激发，全体英雄攻击速度+{spdBonus}",
        slot = "heart",
        minQuality = "blue",
        hasCharge = false,
        params = {
            spdBonus = 0.08,
        },
        starEffect = { type = "critRate", max = 0.10, halfStar = 4, desc = "★暴击率+{v}" },
    },
    shadow_focus = {
        id = "shadow_focus",
        name = "暗影凝聚",
        desc = "暗影聚焦于攻击力最高的英雄，额外攻击+{topAtkBonus}；其余英雄获得其{otherAtkRatio}加成",
        slot = "heart",
        minQuality = "purple",
        hasCharge = false,
        params = {
            topAtkBonus = 0.15,
            otherAtkRatio = 1/3,
        },
        starEffect = { type = "shareRatio", max = 0.30, halfStar = 3, desc = "★分配比+{v}" },
    },
    immortal_flame = {
        id = "immortal_flame",
        name = "不灭圣焰",
        desc = "全体英雄攻击力+{atkBonus}；力部位技能释放后，全体攻速+{postCastSpdBonus}持续{postCastDuration}秒",
        slot = "heart",
        minQuality = "orange",
        hasCharge = false,
        params = {
            atkBonus = 0.12,
            postCastSpdBonus = 0.15,
            postCastDuration = 3.0,
        },
        starEffect = { type = "durationAdd", max = 5.0, halfStar = 4, desc = "★持续+{v}秒" },
    },
    unity_of_all = {
        id = "unity_of_all",
        name = "万象归一",
        desc = "全体攻击+{atkBonus}、攻速+{spdBonus}、暴伤+{critDmgBonus}；每装备一件神话品质遗物额外全属性+{redRelicBonusPer}",
        slot = "heart",
        minQuality = "red",
        hasCharge = false,
        params = {
            atkBonus = 0.10,
            spdBonus = 0.08,
            critDmgBonus = 0.15,
            redRelicBonusPer = 0.03,
        },
        starEffect = { type = "redBonus", max = 0.08, halfStar = 3, desc = "★神话加成+{v}" },
    },

    -- ==================== 神之眼 (eye) ====================
    insight = {
        id = "insight",
        name = "洞察之瞳",
        desc = "每{markInterval}秒标记一个敌人，被标记目标受到的伤害+{markDmgBonus}，持续{markDuration}秒",
        slot = "eye",
        minQuality = "green",
        hasCharge = false,
        params = {
            markInterval = 8.0,
            markDmgBonus = 0.10,
            markDuration = 5.0,
        },
        starEffect = { type = "durationAdd", max = 5.0, halfStar = 4, desc = "★标记持续+{v}秒" },
    },
    weakness_break = {
        id = "weakness_break",
        name = "弱点瓦解",
        desc = "标记目标防御降低{defReduce}；无其他标记时每{autoMarkInterval}秒自动标记生命最高的敌人",
        slot = "eye",
        minQuality = "blue",
        hasCharge = false,
        params = {
            defReduce = 0.10,
            autoMarkInterval = 8.0,
        },
        starEffect = { type = "intervalReduce", max = 3.0, halfStar = 3, desc = "★标记间隔-{v}秒" },
    },
    chain_mark = {
        id = "chain_mark",
        name = "连锁印记",
        desc = "标记目标被击杀时，印记会传递给附近的敌人；被标记目标受到的伤害+{markDmgBonus}",
        slot = "eye",
        minQuality = "purple",
        hasCharge = false,
        params = {
            markDmgBonus = 0.08,
        },
        starEffect = { type = "spreadCount", max = 3, halfStar = 2, desc = "★传递次数+{v}" },
    },
    causality_eye = {
        id = "causality_eye",
        name = "因果之瞳",
        desc = "被标记的敌人死亡时发生因果爆炸，对周围敌人造成其最大生命值×{deathExplosionPct}的伤害",
        slot = "eye",
        minQuality = "orange",
        hasCharge = false,
        params = {
            deathExplosionPct = 0.08,
        },
        starEffect = { type = "explosionRange", max = 0.5, halfStar = 3, desc = "★爆炸范围+{v}" },
    },
    omniscient_eye = {
        id = "omniscient_eye",
        name = "全知之眼",
        desc = "同时标记{markCount}个敌人，标记目标受伤+{markDmgBonus}；每个存活标记为全体英雄攻击+{markAtkBonusPer}",
        slot = "eye",
        minQuality = "red",
        hasCharge = false,
        params = {
            markCount = 3,
            markDmgBonus = 0.12,
            markAtkBonusPer = 0.02,
        },
        starEffect = { type = "markCount", max = 3, halfStar = 5, desc = "★标记数+{v}" },
    },

    -- ==================== 神之意志 (will) ====================
    fervent_faith = {
        id = "fervent_faith",
        name = "狂热信念",
        desc = "力部位技能伤害+{powerDmgBonus}；若力部位无伤害技能则改为全体攻击+{fallbackAtkBonus}",
        slot = "will",
        minQuality = "green",
        hasCharge = false,
        params = {
            powerDmgBonus = 0.15,
            fallbackAtkBonus = 0.075,
        },
        starEffect = { type = "fallbackAdd", max = 0.05, halfStar = 3, desc = "★后备攻击+{v}" },
    },
    rapid_charge = {
        id = "rapid_charge",
        name = "急速充能",
        desc = "力部位充能需求减少{chargeReduce}次；若力部位无充能机制则改为全体攻速+{fallbackSpdBonus}",
        slot = "will",
        minQuality = "blue",
        hasCharge = false,
        params = {
            chargeReduce = 15,
            fallbackSpdBonus = 0.08,
        },
        starEffect = { type = "chargeReduce", max = 10, halfStar = 3, desc = "★额外充能-{v}" },
    },
    overload_burst = {
        id = "overload_burst",
        name = "超载爆发",
        desc = "力部位技能释放后，全体英雄伤害+{postCastDmgBonus}持续{postCastDuration}秒",
        slot = "will",
        minQuality = "purple",
        hasCharge = false,
        params = {
            postCastDmgBonus = 0.20,
            postCastDuration = 5.0,
        },
        starEffect = { type = "durationAdd", max = 5.0, halfStar = 4, desc = "★持续+{v}秒" },
    },
    double_cast = {
        id = "double_cast",
        name = "双重释放",
        desc = "力部位技能有{doubleCastChance}概率触发二次释放，第二次造成{secondCastMult}倍伤害（概率上限{doubleCastCap}）",
        slot = "will",
        minQuality = "orange",
        hasCharge = false,
        params = {
            doubleCastChance = 0.20,
            secondCastMult = 0.50,
            doubleCastCap = 0.80,
        },
        starEffect = { type = "chanceAdd", max = 0.25, halfStar = 4, desc = "★触发概率+{v}" },
    },
    eternal_will = {
        id = "eternal_will",
        name = "永恒意志",
        desc = "永恒意志增幅所有其他遗物的数值效果+{globalAmplify}",
        slot = "will",
        minQuality = "red",
        hasCharge = false,
        params = {
            globalAmplify = 0.10,
        },
        starEffect = { type = "amplifyAdd", max = 0.15, halfStar = 3, desc = "★增幅+{v}" },
    },
}

-- 按部位索引遗物列表（方便掉落查询）
Config.RELICS_BY_SLOT = { power = {}, heart = {}, eye = {}, will = {} }
for _, relic in pairs(Config.RELICS) do
    local list = Config.RELICS_BY_SLOT[relic.slot]
    if list then
        list[#list + 1] = relic
    end
end

-- ============================================================================
-- 升级费用: cost(lv) = floor(80 * 1.08^(lv-1))
-- ============================================================================

Config.RELIC_UPGRADE_BASE_COST = 80
Config.RELIC_UPGRADE_COST_RATE = 1.08

-- ============================================================================
-- 升星碎片费用: shards(star) = floor(5 * 1.25^(star-1))
-- ============================================================================

Config.RELIC_STAR_BASE_SHARDS = 5
Config.RELIC_STAR_SHARD_RATE = 1.25

-- ============================================================================
-- 充能系统
-- ============================================================================

Config.RELIC_CHARGE_MAX = 100          -- 基础充能上限
Config.RELIC_CHARGE_MIN = 20           -- 充能下限保护
Config.RELIC_CHARGE_PER_ATTACK = 1     -- 普攻充能
Config.RELIC_CHARGE_PER_CRIT = 2       -- 暴击充能
Config.RELIC_CHARGE_PER_KILL = 3       -- 击杀充能
Config.RELIC_CHARGE_GLOBAL_CD = 1.0    -- 释放后全局冷却(秒)
Config.RELIC_CHARGE_STAR_REDUCE = 1    -- 每星减少充能上限基础值

-- ============================================================================
-- 掉落权重（按难度）
-- ============================================================================

Config.RELIC_DROP_WEIGHTS = {
    normal    = { green = 50, blue = 28, purple = 15, orange = 6,  red = 1 },
    hard      = { green = 40, blue = 33, purple = 18, orange = 8,  red = 1 },
    nightmare = { green = 30, blue = 36, purple = 21, orange = 10, red = 3 },
    hell      = { green = 20, blue = 38, purple = 25, orange = 12, red = 5 },
}

-- 合成阈值：碎片达到该数量时自动合成为对应品质遗物
Config.RELIC_SYNTH_COST = {
    green  = 30,   -- 精良
    blue   = 50,   -- 稀有
    purple = 80,   -- 史诗
    orange = 120,  -- 传说
    red    = 200,  -- 神话
}

-- 难度精华倍率
Config.RELIC_ESSENCE_MULTIPLIER = {
    normal = 1.0,
    hard = 1.5,
    nightmare = 2.0,
    hell = 3.0,
}

-- ============================================================================
-- 伤害飘字颜色
-- ============================================================================

Config.RELIC_DMG_COLORS = {
    normal   = { 255, 215, 0 },       -- 金色（遗物普通伤害）
    trueDmg  = { 255, 255, 255 },     -- 白色（真实伤害）
    burn     = { 255, 100, 30 },      -- 橙红（灼烧）
    execute  = { 220, 40, 40 },       -- 红色（斩杀）
    pulse    = { 180, 100, 255 },     -- 紫色（脉冲）
}

-- ============================================================================
-- 货币注册（供 Currency.IconWidget 使用）
-- ============================================================================

Config.CURRENCY = Config.CURRENCY or {}
Config.CURRENCY.relic_essence = {
    name = "遗物精华", icon = "essence",
    color = { 255, 215, 100 },
    image = "image/currency_relic_essence.png",
    usage = "遗物升级", category = "relic",
}

end

return apply
