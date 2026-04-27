-- Game/Config_Heroes.lua
-- 英雄养成：升星、觉醒、基础属性、元素、进阶、品质、货币、招募

local function apply(Config)

-- ============================================================================
-- 英雄养成系统（升星+觉醒，对齐咸鱼之王）
-- ============================================================================

Config.MAX_HERO_STAR = 30

Config.STAR_TIERS = {
    { name = "黄星", color = { 255, 220, 80 },  starRange = { 1, 5 } },
    { name = "紫星", color = { 180, 80, 220 },  starRange = { 6, 10 } },
    { name = "橙星", color = { 255, 160, 40 },  starRange = { 11, 15 } },
    { name = "红星", color = { 255, 50, 50 },   starRange = { 16, 20 } },
    { name = "皇冠", color = { 255, 215, 0 },   starRange = { 21, 25 } },
    { name = "紫晶", color = { 160, 100, 255 }, starRange = { 26, 30 } },
}

Config.STAR_COST_PER_TIER = { 8, 40, 80, 200, 400, 400 }

Config.STAR_NORMAL_MULT = 1.10
Config.STAR_CROWN_MULT = 1.15
Config.TIER_ADVANCE_MULT = 1.40
Config.STAR_CROWN_START = 21

-- 技能解锁等级（按技能槽位，LR 有第4技能）
Config.SKILL_UNLOCK_LEVELS = { 100, 500, 1500, 3000 }

-- ============================================================================
-- 技能缩放系统（简化版：配置值 = 30星满值，星级公式线性缩放）
-- 公式: factor = 0.10 + 0.90 * sqrt(star / 30)
-- ============================================================================

-- BOSS 战斗倒计时（秒）
Config.BOSS_TIMER_MAX = 60

-- ============================================================================
-- BOSS 平衡规则常量
-- ============================================================================
Config.BOSS_BALANCE = {
    slowEfficiency = 0.50,        -- BOSS 减速效率 ×50%
    stunDurationMult = 0.50,      -- BOSS 眩晕持续时间 ×50%
    freezeImmune = true,          -- BOSS 免疫冰冻
    executeImmune = true,         -- BOSS 免疫处决
    dotSpreadImmune = true,       -- BOSS 的 DOT 不可二次扩散
}

-- ============================================================================
-- 等级系统
-- ============================================================================
Config.MAX_LEVEL = 6000

-- ============================================================================
-- 英雄四维基础属性
-- ============================================================================
Config.HERO_BASE_STATS = {
    -- N 级
    skeleton_grunt = {
        atk = 1800, spd = 8,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    bat_minion = {
        atk = 1500, spd = 14,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    hell_hound = {
        atk = 2000, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- R 级
    skeleton_archer = {
        atk = 2800, spd = 14,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    demon_warrior = {
        atk = 3200, spd = 8,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    ghost_assassin = {
        atk = 2600, spd = 12,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    stone_golem = {
        atk = 2400, spd = 8,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- SR 级
    necromancer = {
        atk = 3000, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    inferno_flame = {
        atk = 2500, spd = 12,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    armor_breaker = {
        atk = 3200, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    frost_witch = {
        atk = 2700, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    war_drummer = {
        atk = 2200, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- SSR 级
    shadow_mage = {
        atk = 3600, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    abyss_hunter = {
        atk = 3400, spd = 12,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    plague_doctor = {
        atk = 3000, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    storm_lord = {
        atk = 3200, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- UR 级
    nature_elf = {
        atk = 3800, spd = 10,        -- atk作为固定值buff的缩放基准
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    fallen_archangel = {
        atk = 3800, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    void_dragon = {
        atk = 3600, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    crimson_night = {
        atk = 3700, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    ember_wraith = {
        atk = 3500, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- 限定 UR
    glacial_sovereign = {
        atk = 3500, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- LR 级
    fate_weaver = {
        atk = 4000, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    eternal_archfiend = {
        atk = 4500, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
    -- 主角
    leader = {
        atk = 4000, spd = 10,
        armorPen = 0, armorPenGrowth = 0,
        critRate = 0, critRateGrowth = 0,
        critDmg  = 0, critDmgGrowth  = 0,
    },
}

-- 每级成长百分比（按品质），公式: 全属性 × (1 + (level-1) × growthPct)
-- 对齐咸鱼之王量级: SSR Lv3564 ≈ 3000万攻击，LR Lv6000满配 ≈ 34亿攻击
Config.RARITY_GROWTH_PCT = {
    N    = 0.06,    -- 6%/级
    R    = 0.08,    -- 8%/级
    SR   = 0.10,    -- 10%/级
    SSR  = 0.12,    -- 12%/级
    UR   = 0.15,    -- 15%/级
    LR   = 0.18,    -- 18%/级
    none = 0.15,    -- 主角 15%/级
}

Config.LEVEL_RANGE_BONUS = 0.02

-- ============================================================================
-- 战斗公式常量
-- ============================================================================
-- 注: ENEMY_DEF_HP_RATIO / ENEMY_SCALING / THEME_ELEMENT_RESIST 已迁移至 Config_Enemies.lua

Config.BASE_CRIT_MULT = 1.50

-- SPD 攻速加成：分段线性增长（直接替代指数增长）
-- X = 总倍率 (levelMult × advMult × starMult)，Y = 攻速加成比例
-- 分段节点间线性插值，超出最后节点取上限
Config.SPD_BONUS_CURVE = {
    { 1,    0.00 },   -- 初始 → 0%
    { 3,    0.10 },   -- 倍率3 → 10%（前期收益高）
    { 10,   0.20 },   -- 倍率10 → 20%（中期递减）
    { 50,   0.27 },   -- 倍率50 → 27%（后期趋缓）
    { 200,  0.30 },   -- 倍率200+ → 30%（上限）
}
Config.SPD_BONUS_MAX = 0.30

-- ============================================================================
-- 元素系统（暗黑4风格）
-- ============================================================================
-- 5种元素定义
Config.ELEMENTS = {
    fire      = { name = "炎", color = { 255, 100, 30 },  icon = "image/element_fire.png" },
    ice       = { name = "冰", color = { 100, 200, 255 }, icon = "image/element_ice.png" },
    lightning = { name = "雷", color = { 200, 180, 255 }, icon = "image/element_lightning.png" },
    poison    = { name = "毒", color = { 100, 220, 80 },  icon = "image/element_poison.png" },
    shadow    = { name = "暗", color = { 180, 100, 255 }, icon = "image/element_shadow.png" },
}

-- 英雄元素映射（heroId → element）
Config.HERO_ELEMENT = {
    -- N 级
    skeleton_grunt  = "shadow",
    bat_minion      = "shadow",
    hell_hound      = "fire",
    -- R 级
    skeleton_archer = "shadow",
    demon_warrior   = "fire",
    ghost_assassin  = "ice",
    stone_golem     = "lightning",
    -- SR 级
    necromancer     = "shadow",
    inferno_flame   = "fire",
    armor_breaker   = "lightning",
    frost_witch     = "ice",
    war_drummer     = "fire",
    -- SSR 级
    shadow_mage     = "shadow",
    abyss_hunter    = "poison",
    plague_doctor   = "poison",
    storm_lord      = "lightning",
    -- UR 级
    nature_elf      = "poison",
    fallen_archangel = "lightning",
    void_dragon     = "shadow",
    crimson_night    = "shadow",
    ember_wraith     = "fire",
    -- 限定 UR
    glacial_sovereign = "ice",
    -- LR 级
    fate_weaver     = "fire",
    eternal_archfiend = "shadow",
    -- 主角
    leader          = "shadow",
}

Config.LEVEL_COST_CAP = 8078000

-- 进阶系统: 20阶
Config.ADVANCE_GATES = {
    { level = 100,  stones = 10,      bonus = 0.10 },
    { level = 200,  stones = 20,      bonus = 0.10 },
    { level = 300,  stones = 40,      bonus = 0.10 },
    { level = 500,  stones = 100,     bonus = 0.10 },
    { level = 700,  stones = 200,     bonus = 0.10 },
    { level = 900,  stones = 400,     bonus = 0.10 },
    { level = 1200, stones = 1000,    bonus = 0.10 },
    { level = 1500, stones = 2000,    bonus = 0.10 },
    { level = 1800, stones = 4000,    bonus = 0.10 },
    { level = 2100, stones = 6000,    bonus = 0.10 },
    { level = 2500, stones = 10000,   bonus = 0.10 },
    { level = 2900, stones = 16000,   bonus = 0.10 },
    { level = 3300, stones = 24000,   bonus = 0.10 },
    { level = 3700, stones = 36000,   bonus = 0.10 },
    { level = 4000, stones = 50000,   bonus = 0.10 },
    { level = 4300, stones = 70000,   bonus = 0.10 },
    { level = 4600, stones = 100000,  bonus = 0.10 },
    { level = 4900, stones = 150000,  bonus = 0.10 },
    { level = 5200, stones = 220000,  bonus = 0.10 },
    { level = 5500, stones = 400000,  bonus = 0.10 },
}

-- ============================================================================
-- 主角英雄定义
-- ============================================================================
Config.LEADER_HERO = {
    id = "leader",
    name = "暗影君主",
    rarity = "none",
    color = { 180, 120, 255 },
    glowColor = { 0.7, 0.45, 1.0 },
    icon = "leader",
    attackType = "single",
    baseRange = 130,
    baseSpeed = 0.9,
    special = "leader",
    faction = "shadow",
    desc = "暗影之主，统率一切暗影军团。不属于品质体系，始终拥有。",
    isLeader = true,
}

-- 英雄ID → 品质 快速查找表（必须在 TOWER_TYPES 和 LEADER_HERO 之后）
Config.HERO_RARITY = {}
for _, t in ipairs(Config.TOWER_TYPES) do
    Config.HERO_RARITY[t.id] = t.rarity
end
Config.HERO_RARITY[Config.LEADER_HERO.id] = Config.LEADER_HERO.rarity

-- ============================================================================
-- 稀有度系统（含 N/UR/LR）
-- ============================================================================
Config.RARITY = { N = 0, R = 1, SR = 2, SSR = 3, UR = 4, LR = 5 }
Config.RARITY_SUMMON_WEIGHT = { N = 12, R = 14, SR = 16, SSR = 20, UR = 20, LR = 18 }
Config.RARITY_SHARD_COST = { N = 5, R = 10, SR = 20, SSR = 30, UR = 50, LR = 80 }

-- 稀有度颜色（统一权威来源，RGBA 格式）
-- 各 UI 模块应引用此表，不要自建重复定义
Config.RARITY_COLORS = {
    N    = { 180, 180, 180, 255 },
    R    = { 100, 200, 100, 255 },
    SR   = { 120, 130, 255, 255 },
    SSR  = { 255, 200,  50, 255 },
    UR   = { 255, 160,  40, 255 },
    LR   = { 220,  40,  40, 255 },
    none = { 180, 120, 255, 255 },  -- 主角专用
}

--- 获取指定稀有度颜色（可自定义 alpha）
---@param rarity string  稀有度键 (N/R/SR/SSR/UR/LR)
---@param alpha? number  alpha 值，默认 255
---@return number[] {r, g, b, a}
function Config.GetRarityColor(rarity, alpha)
    local c = Config.RARITY_COLORS[rarity] or Config.RARITY_COLORS.N
    if alpha and alpha ~= 255 then
        return { c[1], c[2], c[3], alpha }
    end
    return c
end

-- 默认解锁英雄（新玩家初始拥有）
Config.DEFAULT_UNLOCKED = {
    "skeleton_grunt", "bat_minion", "hell_hound",   -- 3个N级
    "skeleton_archer", "demon_warrior",              -- 2个R级
}

-- 上阵系统
Config.MAX_DEPLOYED = 5       -- 最多上阵5个随从英雄（不含主角）
Config.DEFAULT_DEPLOYED = {
    "skeleton_grunt", "bat_minion", "hell_hound",   -- 3个N级
    "skeleton_archer", "demon_warrior",              -- 2个R级
}

-- ============================================================================
-- 货币体系
-- ============================================================================
Config.CURRENCY = {
    -- 战斗货币
    dark_soul       = { name = "暗魂币",   icon = "soul",     color = { 80, 150, 220 },  image = "image/currency_dark_soul.png", category = "battle" },
    -- 基础升级货币
    nether_crystal  = { name = "冥晶",     icon = "crystal",  color = { 140, 80, 200 },  image = "image/currency_nether_crystal.png",  usage = "升级", category = "basic" },
    devour_stone    = { name = "噬魂石",   icon = "stone",    color = { 60, 160, 80 },   image = "image/currency_devour_stone.png",    usage = "进阶", category = "basic" },
    forge_iron      = { name = "锻魂铁",   icon = "iron",     color = { 130, 160, 200 }, image = "image/currency_forge_iron.png",      usage = "装备", category = "basic" },
    -- 招募货币
    void_pact       = { name = "虚空契约", icon = "pact",     color = { 200, 40, 40 },   image = "image/currency_void_pact.png",      usage = "招募", category = "recruit" },
    frost_pact      = { name = "霜誓契约", icon = "fpact",    color = { 130, 210, 255 }, image = "image/currency_frost_pact.png",     usage = "限定招募", category = "recruit" },
    linyan_oath     = { name = "翎嫣之誓", icon = "oath",     color = { 100, 220, 140 }, image = "image/currency_linyan_oath_20260419133529.png", usage = "苍华极脉招募", category = "recruit" },
    -- 高级兑换货币
    shadow_essence  = { name = "暗影精粹", icon = "essence",  color = { 180, 140, 255 }, image = "image/currency_shadow_essence.png",  usage = "兑换", category = "premium" },
    shadow_orb      = { name = "幽影珠",   icon = "orb",      color = { 160, 80, 200 },  image = "image/currency_shadow_orb.png",     usage = "高级", category = "premium" },
    -- 淬炼货币
    pale_jade       = { name = "粹玉",     icon = "jade",     color = { 220, 240, 255 }, image = "image/currency_pale_jade.png", usage = "淬炼", category = "refine" },
    rainbow_jade    = { name = "封魂玉",   icon = "rjade",    color = { 255, 120, 220 }, image = "image/currency_rainbow_jade.png", usage = "锁定淬炼孔位", category = "refine" },
    -- 符文系统货币
    rift_dust       = { name = "裂隙之尘", icon = "dust",     color = { 160, 120, 200 }, image = "image/currency_rift_dust.png",    usage = "符文洗练", category = "rune" },
    rune_generic    = { name = "符文",     icon = "rune",     color = { 180, 100, 255 }, image = "image/rune_generic_20260427025545.png", usage = "深渊裂隙掉落的随机符文", category = "rune" },
    rune_seal       = { name = "符文封印", icon = "seal",     color = { 40, 200, 160 },  image = "image/currency_rune_seal.png",    usage = "洗练锁定", category = "rune" },
    abyss_crystal   = { name = "深渊结晶", icon = "acrystal", color = { 200, 60, 255 },  image = "image/currency_abyss_crystal.png", usage = "定向洗练", category = "rune" },
    -- 活动货币
    emerald_token   = { name = "翠影凭证", icon = "emerald",  color = { 100, 220, 140 }, image = "image/emerald_certificate.png", usage = "翠影秘境兑换", category = "event" },
    -- 门票/券
    trial_ticket    = { name = "试练券",   icon = "ticket",   color = { 80, 200, 220 },  image = "image/trial_ticket.png",            usage = "试练塔", category = "ticket" },
    dungeon_ticket  = { name = "资源副本门票", icon = "ticket", color = { 255, 180, 60 }, image = "image/item_dungeon_ticket.png",     usage = "进入副本", category = "ticket" },
    ad_ticket       = { name = "免广告券", icon = "adticket", color = { 100, 220, 180 }, image = "image/currency_ad_ticket.png", usage = "跳过广告", category = "ticket" },
    -- 宝箱
    wood_chest      = { name = "朽木宝箱", icon = "chest",    color = { 160, 130, 80 },  image = "image/chest_wood.png",              usage = "开启", category = "chest" },
    bronze_chest    = { name = "青铜宝箱", icon = "chest",    color = { 180, 140, 80 },  image = "image/chest_bronze.png",            usage = "开启", category = "chest" },
    gold_chest      = { name = "黄金宝箱", icon = "chest",    color = { 255, 215, 0 },   image = "image/chest_gold.png",              usage = "开启", category = "chest" },
    platinum_chest  = { name = "铂金宝箱", icon = "chest",    color = { 180, 220, 255 }, image = "image/chest_platinum.png",          usage = "开启", category = "chest" },
    diamond_chest   = { name = "钻石宝箱", icon = "chest",    color = { 255, 100, 255 }, image = "image/chest_diamond.png",           usage = "开启", category = "chest" },
    -- 碎片箱
    ur_shard_box    = { name = "万能UR碎片箱", icon = "box",  color = { 255, 200, 50 },  image = "image/icon_universal_ur_shard_box.png", usage = "选择UR碎片", category = "box" },
    random_ur_shard_box = { name = "随机UR碎片箱", icon = "box", color = { 180, 100, 255 }, image = "image/icon_random_ur_shard_box.png", usage = "随机UR碎片", category = "box" },
    r_shard_select_box   = { name = "R自选碎片礼包",   icon = "box", color = { 80, 200, 80 },   image = "image/icon_r_shard_select_box.png",   usage = "选择R碎片", category = "box" },
    r_shard_random_box   = { name = "R随机碎片礼包",   icon = "box", color = { 60, 160, 60 },   image = "image/icon_r_shard_random_box.png",   usage = "随机R碎片", category = "box" },
    sr_shard_select_box  = { name = "SR自选碎片礼包",  icon = "box", color = { 80, 140, 255 },  image = "image/icon_sr_shard_select_box.png",  usage = "选择SR碎片", category = "box" },
    sr_shard_random_box  = { name = "SR随机碎片礼包",  icon = "box", color = { 50, 100, 200 },  image = "image/icon_sr_shard_random_box.png",  usage = "随机SR碎片", category = "box" },
    ssr_shard_select_box = { name = "SSR自选碎片礼包", icon = "box", color = { 180, 80, 220 },  image = "image/icon_ssr_shard_select_box.png", usage = "选择SSR碎片", category = "box" },
    ssr_shard_random_box = { name = "SSR随机碎片礼包", icon = "box", color = { 140, 50, 180 },  image = "image/icon_ssr_shard_random_box.png", usage = "随机SSR碎片", category = "box" },
    -- 福袋/礼包
    nether_crystal_pack  = { name = "冥晶礼包",     icon = "pack",    color = { 140, 80, 200 },  image = "image/icon_nether_crystal_pack.png",  usage = "获取冥晶", category = "bag" },
    shadow_essence_bag   = { name = "暗影精粹福袋", icon = "bag",     color = { 180, 140, 255 }, image = "image/icon_shadow_essence_bag.png",   usage = "获取暗影精粹", category = "bag" },
    devour_stone_bag     = { name = "噬魂石福袋",   icon = "bag",     color = { 60, 160, 80 },   image = "image/icon_devour_stone_bag.png",    usage = "获取噬魂石", category = "bag" },
    forge_iron_bag       = { name = "锻魂铁福袋",   icon = "bag",     color = { 130, 160, 200 }, image = "image/icon_forge_iron_bag.png",      usage = "获取锻魂铁", category = "bag" },
    recruit_ticket_select_box = { name = "招募券自选包", icon = "ticket", color = { 200, 150, 255 }, image = "image/icon_recruit_ticket_select_box.png", usage = "选择招募池", category = "bag" },
    -- 遗物 & 符文箱
    random_relic_shard_box  = { name = "随机遗物碎片箱", icon = "box", color = { 255, 215, 100 }, image = "image/icon_random_relic_shard_box_20260426065816.png",  usage = "随机遗物碎片", category = "box" },
    random_mythic_rune_box  = { name = "随机神话符文箱", icon = "box", color = { 220, 40, 40 },   image = "image/icon_random_mythic_rune_box_20260426065826.png",  usage = "随机神话符文", category = "box" },
}

-- 战斗内暗魂掉落（不可被技能修改）
Config.DARK_SOUL_DROP = {
    normal = 1,
    elite  = 3,
    boss   = 10,
}

-- 击杀掉落与挂机收益统一线性体系:
--   挂机冥晶/hr = stage × 3500（每10关 +35000）
--   实战 = 2× 挂机，即每关冥晶 ≈ stage × 2335
--   dropScale = 1 + (stage-1) × stageScale，无二次项
--   stage 10 约 177 怪(普通167+精英9+BOSS1)，dropScale=1.54
--   验算: 167×floor(40×1.54)+9×floor(75×1.54)+floor(300×1.54)
--        = 167×61+9×115+462 = 10187+1035+462 = 11684 ≈ 目标11675
Config.KILL_DROP = {
    stageScale = 0.06,        -- 线性项：每关 +6%
    stageQuadratic = 0,       -- 无二次项，保持近似线性
    -- 冥晶: 所有怪物都掉（×5）
    crystal = {
        normal = 40,      -- 普通怪基础
        elite  = 75,      -- 精英怪基础
        boss   = 300,     -- BOSS 基础
    },
    -- 噬魂石: 精英和 BOSS 才掉
    stone = {
        normal = 0,
        elite  = 2,
        boss   = 6,
    },
    -- 锻魂铁: 仅 BOSS 掉
    iron = {
        normal = 0,
        elite  = 0,
        boss   = 4,
    },
}

-- 暗影精华兑换表
Config.ESSENCE_EXCHANGE = {
    { type = "universal_shard", rarity = "SSR", cost = 30, amount = 1 },
    { type = "universal_shard", rarity = "UR",  cost = 50, amount = 1 },
    { type = "universal_shard", rarity = "LR",  cost = 100, amount = 1 },
}

-- ============================================================================
-- 招募系统
-- ============================================================================
Config.RECRUIT_SINGLE_COST = 1
Config.RECRUIT_TEN_COST = 10
Config.RECRUIT_HUNDRED_COST = 90
Config.RECRUIT_PITY = 10
Config.RECRUIT_INITIAL_TOKENS = 10

Config.RECRUIT_RATES = {
    N   = 40,
    R   = 30,
    SR  = 17,
    SSR = 8,
    UR  = 3,
    LR  = 1,
}

Config.RECRUIT_FRAGMENT_DROP = {
    N   = { min = 2, max = 3 },
    R   = { min = 3, max = 5 },
    SR  = { min = 5, max = 8 },
    SSR = { min = 8, max = 15 },
    UR  = { min = 15, max = 25 },
    LR  = { min = 25, max = 40 },
}

Config.RECRUIT_POOL = {
    N   = { "skeleton_grunt", "bat_minion", "hell_hound" },
    R   = { "skeleton_archer", "demon_warrior", "ghost_assassin", "stone_golem" },
    SR  = { "necromancer", "inferno_flame", "armor_breaker", "frost_witch", "war_drummer" },
    SSR = { "shadow_mage", "abyss_hunter", "plague_doctor", "storm_lord" },
    UR  = { "fallen_archangel", "void_dragon", "crimson_night", "ember_wraith" },
    LR  = { "fate_weaver", "eternal_archfiend" },
}

-- ============================================================================
-- 限定招募池（支持多池）
-- ============================================================================
Config.LIMITED_BANNERS = {
    -- 池1：凛冬君王
    {
        id          = "glacial",
        name        = "凛冬君王",
        heroId      = "glacial_sovereign",
        avatar      = "image/avatars/avatar_glacial.png",
        artworkImage = "image/glacial_sovereign_artwork.png",
        currency    = "frost_pact",
        singleCost  = 1,
        tenCost     = 10,
        hundredCost = 90,
        pity        = 50,
        pityResetOnGet = true,
        durationDays   = 30,
        buyPrice    = 300,
        buyCurrency = "shadow_essence",
        -- startDate 使用 Config.LIMITED_BANNER_START（在 Config_Core 中定义）
        rates = {
            N   = 40,
            R   = 30,
            SR  = 17,
            SSR = 8,
            UR  = 3,
            LR  = 1,
        },
        fallbackPool = {
            N   = Config.RECRUIT_POOL.N,
            R   = Config.RECRUIT_POOL.R,
            SR  = Config.RECRUIT_POOL.SR,
            SSR = Config.RECRUIT_POOL.SSR,
            LR  = Config.RECRUIT_POOL.LR,
        },
    },
    -- 池2：苍华极脉·翎嫣（4月22日解锁）
    {
        id           = "nature",
        name         = "苍华极脉",
        heroId       = "nature_elf",
        avatar       = "image/avatars/avatar_nature_elf.png",
        artworkImage = "image/lingyan_artwork_20260419123010.png",
        bannerBg     = "image/limited_banner_bg_nature_20260419130050.png",
        currency    = "linyan_oath",
        singleCost  = 1,
        tenCost     = 10,
        hundredCost = 90,
        pity        = 50,
        pityResetOnGet = true,
        durationDays   = 30,
        buyPrice    = 300,
        buyCurrency = "shadow_essence",
        startDate   = "2026-04-22",      -- 活动起始日期
        unlockDate  = "2026-04-22",      -- 此日期前锁定，不可招募
        rates = {
            N   = 40,
            R   = 30,
            SR  = 17,
            SSR = 8,
            UR  = 3,
            LR  = 1,
        },
        fallbackPool = {
            N   = Config.RECRUIT_POOL.N,
            R   = Config.RECRUIT_POOL.R,
            SR  = Config.RECRUIT_POOL.SR,
            SSR = Config.RECRUIT_POOL.SSR,
            LR  = Config.RECRUIT_POOL.LR,
        },
    },
}
-- 向后兼容：保留单一引用
Config.LIMITED_BANNER = Config.LIMITED_BANNERS[1]

Config.SETTLE_TOKEN_BASE = 1
Config.SETTLE_TOKEN_PER_10 = 1

end

return apply
