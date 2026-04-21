-- Game/Config_Meta.lua
-- 技能定义、阵营羁绊、结算、挂机、配色、路径、宝箱、装备

local function apply(Config)

-- ============================================================================
-- 英雄技能定义（全部 21 个英雄 + 主角）
-- ============================================================================
Config.HERO_SKILLS = {
    -- N 级
    skeleton_grunt = {
        { id = "undead_tenacity", name = "亡灵韧性", desc = "攻速+5%",
          type = "passive", atkSpdBonus = 0.05 },
    },
    bat_minion = {
        { id = "vampire_instinct", name = "吸血本能", desc = "攻击10%概率减速目标10%持续1秒",
          type = "passive", chance = 0.10, slowRate = 0.10, slowDuration = 1.0 },
    },
    hell_hound = {
        { id = "flame_breath", name = "烈焰喷息", desc = "DOT伤害+30%",
          type = "passive", dotMultiplier = 1.3 },
    },
    -- R 级
    skeleton_archer = {
        { id = "multi_shot",     name = "连射", desc = "20%概率连射2箭",
          type = "passive", chance = 0.20 },
        { id = "weak_mark",      name = "弱点标记", desc = "目标受伤+10%持续3秒",
          type = "passive", bonusDmg = 0.10, duration = 3.0 },
    },
    demon_warrior = {
        { id = "burning_ground", name = "燃烧大地", desc = "AOE留下燃烧地面2秒",
          type = "passive", burnDuration = 2.0 },
        { id = "demon_fury",     name = "恶魔之怒", desc = "攻速随波次+0.5%/波,最多+25%,每波重置",
          type = "passive", bonusPerWave = 0.005, maxBonus = 0.25 },
    },
    ghost_assassin = {
        { id = "lethal_mark",    name = "致命标记", desc = "标记增伤提升至12%,对所有友方生效",
          type = "passive", ampRate = 0.12 },
        { id = "backstab",       name = "背刺", desc = "对已标记目标15%概率双倍伤害",
          type = "passive", chance = 0.15 },
    },
    stone_golem = {
        { id = "heavy_strike",   name = "沉重一击", desc = "减速提升至30%",
          type = "passive", newSlowRate = 0.30 },
        { id = "rock_splash",    name = "碎石溅射", desc = "20%概率减速周围30px内其他敌人",
          type = "passive", chance = 0.20, splashRange = 30 },
    },
    -- SR 级
    necromancer = {
        { id = "deep_freeze",    name = "深度冻结", desc = "减速提升至45%",
          type = "passive", newSlowRate = 0.45 },
        { id = "curse_mark",     name = "诅咒标记", desc = "被减速敌人每秒受ATK×5%伤害",
          type = "passive", curseDmgAtkPct = 0.05 },
        { id = "soul_chain",     name = "灵魂锁链", desc = "减速扩散至40px内最多2敌人,不二次扩散",
          type = "passive", chainRange = 40, chainMaxTargets = 2 },
    },
    inferno_flame = {
        { id = "enhanced_burn",  name = "强化灼烧", desc = "DOT伤害+50%",
          type = "passive", dotMultiplier = 1.5 },
        { id = "fire_spread",    name = "火焰蔓延", desc = "DOT目标死亡传递剩余DOT",
          type = "passive" },
        { id = "nirvana_flame",  name = "涅槃之炎", desc = "对BOSS DOT改为ATK×300%每秒",
          type = "passive", bossAtkPct = 3.0 },
    },
    armor_breaker = {
        { id = "precise_strike", name = "精准打击", desc = "护甲削减提升至12%",
          type = "passive", armorBreak = 0.12 },
        { id = "armor_stack",    name = "破甲叠加", desc = "最多叠加3层",
          type = "passive", maxStacks = 3 },
        { id = "fatal_weakness", name = "致命弱点", desc = "满层目标额外受到20%伤害",
          type = "passive", fullStackBonus = 0.20 },
    },
    frost_witch = {
        { id = "extreme_cold",   name = "极寒之触", desc = "减速提升至35%",
          type = "passive", newSlowRate = 0.35 },
        { id = "freeze_chance",  name = "冰冻概率", desc = "10%概率冰冻1.5秒;BOSS免疫改减速50%",
          type = "passive", chance = 0.10, freezeDuration = 1.5, bossFallbackSlow = 0.50 },
        { id = "blizzard",       name = "暴风雪", desc = "每20秒全屏减速40%持续3秒",
          type = "active", interval = 20, slowPct = 0.40, duration = 3.0 },
    },
    war_drummer = {
        { id = "morale_boost",   name = "鼓舞士气", desc = "光环攻击加成提升至15%",
          type = "passive", atkBuff = 0.15 },
        { id = "war_rhythm",     name = "战吼节奏", desc = "光环额外+10%攻速",
          type = "passive", spdBuff = 0.10 },
        { id = "heroic_anthem",  name = "英勇战歌", desc = "每30秒全体塔攻击+25%持续5秒",
          type = "active", interval = 30, atkBuffPct = 0.25, duration = 5.0 },
    },
    -- SSR 级
    shadow_mage = {
        { id = "shadow_pierce",  name = "暗影穿透", desc = "攻击15%概率无视护盾",
          type = "passive", chance = 0.15, maxChance = 0.75 },
        { id = "soul_reap",      name = "灵魂收割", desc = "击杀后下次攻击+30%,叠3层,攻击后清零",
          type = "passive", killDmgBonus = 0.30, maxStacks = 3 },
        { id = "void_storm",     name = "虚空风暴", desc = "每15秒全屏30%攻击力伤害",
          type = "active", interval = 15, damagePct = 0.30 },
    },
    abyss_hunter = {
        { id = "hunt_instinct",  name = "猎杀本能", desc = "对BOSS额外伤害提升至50%",
          type = "passive", bossExtraDmg = 0.50 },
        { id = "deadly_crossbow", name = "致命猎弩", desc = "暴击率+15%,暴击伤害+30%",
          type = "passive", critRate = 0.15, critDmg = 0.30 },
        { id = "abyss_arrow",    name = "深渊之箭", desc = "每12秒对最高血量敌人造成8%最大HP,BOSS上限ATK×8",
          type = "active", interval = 12, hpPct = 0.08, bossAtkCap = 8 },
    },
    plague_doctor = {
        { id = "toxic_miasma",   name = "剧毒瘴气", desc = "DOT期间敌人护甲抵抗-5%",
          type = "passive", armorReduce = 0.05 },
        { id = "infection_spread", name = "感染扩散", desc = "DOT目标30px内最多2敌人感染50%DOT,不二次扩散",
          type = "passive", spreadRange = 30, spreadMaxTargets = 2, spreadRatio = 0.50 },
        { id = "plague_burst",   name = "瘟疫爆发", desc = "每18秒引爆全部DOT,造成剩余DOT 200%即时伤害",
          type = "active", interval = 18, burstMult = 2.0 },
    },
    storm_lord = {
        { id = "thunder_strike", name = "雷鸣一击", desc = "眩晕概率提升至15%",
          type = "passive", stunChance = 0.15 },
        { id = "storm_eye",      name = "风暴之眼", desc = "攻击范围+20px",
          type = "passive", rangeBonus = 20 },
        { id = "divine_thunder", name = "天降雷霆", desc = "每22秒全屏25%攻击力伤害并减速50%持续2秒",
          type = "active", interval = 22, damagePct = 0.25, slowPct = 0.50, slowDuration = 2.0 },
    },
    -- UR 级（限定）
    glacial_sovereign = {
        { id = "piercing_chill",    name = "凌冽寒意", desc = "每秒对范围内敌人施加1层寒意,每层减速10%,最多5层,持续5秒;满5层受伤+50%",
          type = "passive" },
        { id = "frost_strike",      name = "霜寒之击", desc = "普通攻击附带1层寒意",
          type = "passive" },
        { id = "glacial_eruption",  name = "冰川爆发", desc = "每累积100层全局寒意,对全屏敌人施加5层寒意",
          type = "passive", chillGlobalThreshold = 100, chillApplyAll = 5 },
    },
    -- UR 级
    fallen_archangel = {
        { id = "divine_judgment_light", name = "神罚之光", desc = "标记增伤提升至20%",
          type = "passive", ampRate = 0.20 },
        { id = "angel_judgment",  name = "天使审判", desc = "每15秒全屏35%攻击力伤害",
          type = "active", interval = 15, damagePct = 0.35 },
        { id = "fallen_glory",   name = "堕落荣光", desc = "光环:100px内友方暴击率+12%",
          type = "passive", auraRange = 100, critRateBuff = 0.12 },
    },
    void_dragon = {
        { id = "dragon_breath_dot", name = "龙息灼烧", desc = "链式攻击附带ATK×10%/秒DOT,持续3秒",
          type = "passive", dotAtkPct = 0.10, dotDuration = 3.0 },
        { id = "void_tear",      name = "虚空撕裂", desc = "对BOSS额外伤害提升至40%",
          type = "passive", bossExtraDmg = 0.40 },
        { id = "dragon_wrath",   name = "龙王之怒", desc = "每12秒全屏50%攻击力伤害并减速30%持续3秒",
          type = "active", interval = 12, damagePct = 0.50, slowPct = 0.30, slowDuration = 3.0 },
    },
    -- LR 级
    fate_weaver = {
        { id = "fate_thread",    name = "命运之线", desc = "光环降低敌人受治愈效果30%",
          type = "passive", healReduction = 0.30 },
        { id = "time_weave",     name = "时间编织", desc = "每25秒重置全体友方塔技能CD",
          type = "active", interval = 25 },
        { id = "causality",      name = "因果律", desc = "全体友方塔15%概率双倍伤害",
          type = "passive", doubleDmgChance = 0.15 },
        { id = "fate_finale",    name = "命运终章", desc = "友方致命一击时,溅射50%伤害给周围敌人",
          type = "passive", critSplashPct = 0.50 },
    },
    eternal_archfiend = {
        { id = "archfiend_strike", name = "魔君一击", desc = "暴击率+20%,暴击伤害+50%",
          type = "passive", critRate = 0.20, critDmg = 0.50 },
        { id = "eternal_power",  name = "永恒之力", desc = "击杀+1%攻击,最多+50%,每波重置",
          type = "passive", killAtkBonus = 0.01, maxBonus = 0.50 },
        { id = "worldfire",      name = "灭世之炎", desc = "每10秒对最高血量敌人造成当前HP 10%,BOSS上限ATK×10",
          type = "active", interval = 10, hpPct = 0.10, bossAtkCap = 10 },
        { id = "final_judgment", name = "终焉审判", desc = "HP<15%处决;BOSS免疫,改为ATK×15固定伤害",
          type = "passive", executeThreshold = 0.15, bossFixedAtkMult = 15 },
    },
    -- 主角
    leader = {
        { id = "shadow_dominion", name = "暗影支配", desc = "全体友方塔攻击+5%",
          type = "passive", globalAtkBuff = 0.05 },
        { id = "lord_will",      name = "君主意志", desc = "击杀时8%概率重置主动技能1秒CD",
          type = "passive", chance = 0.08, cdResetAmount = 1.0 },
        { id = "shadow_devour",  name = "暗影吞噬", desc = "每10秒全屏40%攻击力伤害",
          type = "active", interval = 10, damagePct = 0.40 },
    },
    nature_elf = {
        { id = "nature_gift",    name = "自然馈赠", desc = "每3秒为范围内英雄注入3点自然之力（持续8秒），自然之力越多越接近上限：攻击+60%、攻速+40%，并额外获得翎嫣ATK×10%的固定攻击加成",
          type = "passive", starScale = true },
        { id = "verdant_ward",   name = "翠意庇护", desc = "当英雄自然之力≥20时触发翠意状态，持续5秒内免疫沉默、禁锢等负面效果，内置20秒冷却",
          type = "passive" },
        { id = "wilds_call",     name = "绿野之呼", desc = "每20秒自动为所有英雄提供30点自然之力，并为攻击力最高且未持有鲜花环的英雄赠送鲜花环（+40%攻击力，持续10秒，每个英雄最多1个）",
          type = "active", interval = 20, starScale = true },
    },
}

-- ============================================================================
-- 阵营与羁绊系统
-- ============================================================================
Config.FACTIONS = {
    undead    = { name = "亡灵", color = { 80, 180, 80 } },
    demon     = { name = "恶魔", color = { 220, 60, 60 } },
    elemental = { name = "元素", color = { 80, 180, 255 } },
    human     = { name = "人类", color = { 220, 200, 80 } },
    shadow    = { name = "暗影", color = { 200, 160, 255 } },
}

Config.FACTION_BONDS = {
    { type = "same_faction", count = 2, effects = { atkMult = 0.08 } },
    { type = "same_faction", count = 3, effects = { atkMult = 0.15, spdMult = 0.08 } },
    { type = "same_faction", count = 4, effects = { atkMult = 0.25, spdMult = 0.15 } },
}

Config.FACTION_SPECIAL_4 = {
    undead    = { id = "undead_curse",   name = "亡灵诅咒", deathAoePct = 0.05 },
    demon     = { id = "demon_frenzy",  name = "恶魔狂热", killAtkSpd = 0.02, maxStacks = 15 },
    elemental = { id = "elem_resonance", name = "元素共鸣", effectDurationMult = 1.4 },
    human     = { id = "human_alliance", name = "人类联盟", rangeBonus = 20, critRate = 0.08 },
}

Config.CROSS_BONDS = {
    { id = "death_legion", name = "死亡军团",
      require = { undead = 2, demon = 2 },
      effects = { critRate = 0.10 } },
    { id = "nature_force", name = "自然之力",
      require = { elemental = 2, human = 2 },
      effects = { atkMult = 0.12, slowBonus = 0.15 } },
    { id = "shadow_council", name = "暗影议会",
      require = { shadow = 1, undead = 2, demon = 1 },
      effects = { leaderAtkMult = 0.20, leaderCdReduce = 3.0 } },
    { id = "five_factions", name = "五族共存",
      requireDistinct = 4,
      effects = { atkMult = 0.10, spdMult = 0.10, rangeBonus = 10 } },
}

-- 神裔降临：周末冥晶加成倍率（1.0 = 无加成）
Config.WEEKEND_CRYSTAL_MULTI = 1.5

-- 结算奖励
Config.SETTLE_BASE_GOLD = 80
Config.SETTLE_STAGE_GOLD = 15
Config.SETTLE_FRAGMENT_BASE = 2
Config.SETTLE_FRAGMENT_PER_5 = 1
Config.SETTLE_DIAMOND_INTERVAL = 5
Config.SETTLE_DIAMOND_AMOUNT = 5
Config.SETTLE_STONE_PER_5 = 1

-- ============================================================================
-- 挂机离线收益（咸鱼之王风格）
-- ============================================================================
Config.IDLE_MAX_SECONDS = 4 * 3600          -- 最大累计时长: 4小时
Config.IDLE_MIN_SECONDS = 10                -- 最小领取阈值: 10秒
Config.IDLE_STAGE_SECONDS = 600             -- 一关平均战斗时长(秒): 20波×30秒
Config.IDLE_RATE = 0.5                      -- 挂机效率系数(50%，低于实战)

--- 估算指定关卡一关的战斗掉落总量（线性公式）
--- 挂机1小时冥晶 = stage × 3500（每10关 +35000），挂机过关数/小时 = 3
--- 实战 = 2× 挂机（IDLE_RATE = 0.5）
---@param stageNum number 关卡数
---@return number crystal, number stone, number iron
function Config.EstimateStageDrop(stageNum)
    local s = math.max(1, stageNum)
    -- 冥晶: 挂机/hr = s*3500, 每关 = s*3500/3 ≈ s*1165
    local crystal = math.floor(s * 1165)
    -- 噬魂石: 挂机/hr ≈ s*6
    local stone = math.floor(s * 2)
    -- 锻魂铁: 挂机/hr ≈ s*3
    local iron = math.floor(s * 1)
    return crystal, stone, iron
end

-- 挂机宝箱掉落（按时长阶梯，可叠加）
Config.IDLE_CHEST_DROPS = {
    { minHours = 2, chests = { wood = 2 } },                -- ≥2h: 2个朽木
    { minHours = 4, chests = { bronze = 1 } },              -- ≥4h: 额外1个青铜
}
-- 挂机随机宝箱（每小时判定一次，概率掉落）
Config.IDLE_CHEST_RANDOM = {
    { id = "gold",     chancePerHour = 0.50 },  -- 每小时50%概率掉1个黄金
    { id = "platinum", chancePerHour = 0.50 },  -- 每小时50%概率掉1个铂金
}
-- 挂机随机碎片（每小时判定一次，概率掉落）
Config.IDLE_FRAGMENT_RANDOM = {
    { id = "sr_shard_random_box",  chancePerHour = 0.80 },  -- 每小时80%概率掉SR随机碎片箱
    { id = "ssr_shard_random_box", chancePerHour = 0.50 },  -- 每小时50%概率掉SSR随机碎片箱
    { id = "random_ur_shard_box",  chancePerHour = 0.50 },  -- 每小时50%概率掉随机UR碎片箱
}

-- ============================================================================
-- 暗黑风格配色
-- ============================================================================
Config.COLORS = {
    bg = { 15, 12, 25, 255 },
    bgGrad = { 25, 18, 40, 255 },
    gridLine = { 50, 40, 70, 255 },
    gridCell = { 25, 20, 40, 255 },
    gridCellHover = { 40, 30, 60, 255 },
    pathColor = { 40, 35, 50, 255 },
    pathBorder = { 60, 50, 80, 255 },
    textPrimary = { 220, 215, 230, 255 },
    textSecondary = { 150, 140, 170, 200 },
    textGold = { 255, 215, 80, 255 },
    textDamage = { 255, 80, 60, 255 },
    hpBarBg = { 40, 30, 50, 200 },
    hpBarFill = { 200, 40, 40, 255 },
    hpBarBoss = { 255, 60, 30, 255 },
    gold = { 255, 200, 50, 255 },
    panelBg = { 20, 16, 32, 230 },
    panelBorder = { 70, 55, 100, 150 },
    buttonBg = { 80, 50, 140, 255 },
    buttonHover = { 100, 65, 170, 255 },
    starColor = { 255, 220, 80, 255 },
}

Config.TAB_COLORS = {
    active = { 140, 100, 220, 255 },
    inactive = { 120, 110, 140, 200 },
    bg = { 20, 16, 32, 240 },
    border = { 70, 55, 100, 120 },
}

Config.BLOOM = {
    innerAlpha = 0.4,
    midAlpha = 0.5,
    outerAlpha = 0.1,
    size = 2.0,
}

-- ============================================================================
-- 路径定义
-- ============================================================================
Config.PATH_WAYPOINTS = {
    { x = 0.5,  y = 0.5 },
    { x = 7.5,  y = 0.5 },
    { x = 7.5,  y = 6.5 },
    { x = 0.5,  y = 6.5 },
}

Config.PATH_LOOP = true

Config.PATH_CELLS = {
    -- 顶行 (row 1)
    { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 }, { 7, 1 }, { 8, 1 },
    -- 底行 (row 7)
    { 1, 7 }, { 2, 7 }, { 3, 7 }, { 4, 7 }, { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 },
    -- 左列 (col 1, rows 2-6)
    { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 }, { 1, 6 },
    -- 右列 (col 8, rows 2-6)
    { 8, 2 }, { 8, 3 }, { 8, 4 }, { 8, 5 }, { 8, 6 },
}

-- ============================================================================
-- 宝箱系统（对齐咸鱼之王）
-- 5种品质：朽木→青铜→黄金→铂金→钻石
-- 通关/挂机获得，开箱获得货币+碎片
-- ============================================================================

Config.CHEST_TYPES = {
    {
        id = "wood",
        name = "朽木宝箱",
        emoji = "🪵",
        image = "image/chest_wood.png",
        color = { 160, 130, 80 },
        bgColor = { 50, 40, 25, 220 },
        borderColor = { 120, 95, 50, 200 },
        score = 1,           -- 开箱积分
        -- 掉落: 冥晶为主
        drops = {
            { type = "nether_crystal", min = 20, max = 50, chance = 1.0 },
            { type = "fragment_random", rarity = "N", min = 1, max = 2, chance = 0.05 },
        },
    },
    {
        id = "bronze",
        name = "青铜宝箱",
        emoji = "🥉",
        image = "image/chest_bronze.png",
        color = { 180, 140, 100 },
        bgColor = { 45, 35, 25, 220 },
        borderColor = { 160, 120, 70, 200 },
        score = 10,
        drops = {
            { type = "forge_iron", min = 5, max = 15, chance = 1.0 },
            { type = "fragment_random", rarity = "R", min = 1, max = 3, chance = 0.07 },
            { type = "fragment_random", rarity = "SR", min = 1, max = 2, chance = 0.03 },
        },
    },
    {
        id = "gold",
        name = "黄金宝箱",
        emoji = "🥇",
        image = "image/chest_gold.png",
        color = { 255, 215, 0 },
        bgColor = { 50, 40, 15, 220 },
        borderColor = { 200, 170, 40, 200 },
        score = 20,
        drops = {
            { type = "devour_stone", min = 15, max = 40, chance = 1.0 },
            { type = "fragment_random", rarity = "SR", min = 2, max = 4, chance = 0.20 },
            { type = "fragment_random", rarity = "SSR", min = 1, max = 2, chance = 0.03 },
        },
    },
    {
        id = "platinum",
        name = "铂金宝箱",
        emoji = "💎",
        image = "image/chest_platinum.png",
        color = { 180, 220, 255 },
        bgColor = { 25, 35, 50, 220 },
        borderColor = { 120, 170, 220, 200 },
        score = 50,
        drops = {
            { type = "devour_stone", min = 30, max = 80, chance = 1.0 },
            { type = "fragment_random", rarity = "SR", min = 3, max = 5, chance = 1.0 },
            { type = "fragment_random", rarity = "SSR", min = 2, max = 4, chance = 0.10 },
        },
    },
    {
        id = "diamond",
        name = "钻石宝箱",
        emoji = "👑",
        image = "image/chest_diamond.png",
        color = { 255, 100, 255 },
        bgColor = { 45, 20, 50, 220 },
        borderColor = { 200, 80, 220, 200 },
        score = 100,
        drops = {
            { type = "shadow_essence", min = 10, max = 30, chance = 1.0 },
            { type = "fragment_random", rarity = "SSR", min = 3, max = 6, chance = 1.0 },
            { type = "fragment_random", rarity = "UR", min = 1, max = 3, chance = 0.33 },
        },
    },
}

-- 按 id 查找的 map
Config.CHEST_TYPES_MAP = {}
for _, ct in ipairs(Config.CHEST_TYPES) do
    Config.CHEST_TYPES_MAP[ct.id] = ct
end

-- 积分里程碑（间隔制，循环）
-- delta = 距上一个里程碑的间隔积分, reward = 奖励宝箱
Config.CHEST_SCORE_MILESTONES = {
    { delta = 10,  reward = "bronze"   },  -- 累计 10
    { delta = 20,  reward = "bronze"   },  -- 累计 30
    { delta = 30,  reward = "gold"     },  -- 累计 60
    { delta = 40,  reward = "platinum" },  -- 累计 100
    { delta = 80,  reward = "platinum" },  -- 累计 180
    { delta = 100, reward = "platinum" },  -- 累计 280
    { delta = 70,  reward = "gold"     },  -- 累计 350
    { delta = 50,  reward = "platinum" },  -- 累计 400
    { delta = 100, reward = "diamond"  },  -- 累计 500
}
Config.CHEST_SCORE_CYCLE = 500  -- 一轮总积分（循环重置）

-- 通关宝箱掉落
Config.CHEST_STAGE_DROP = {
    perStage = { wood = 3 },           -- 每关通关获得
    per5Stage = { bronze = 1 },        -- 每5关额外获得
    per10Stage = { gold = 1 },         -- 每10关额外获得
}

-- 新玩家初始宝箱
Config.CHEST_INITIAL = {}

-- ============================================================================
-- 装备系统（对齐咸鱼之王）
-- 4个部位: 武器(攻击)、铠甲(血量)、头盔(防御)、战马(血量)
-- 5种品质: 绿→蓝→紫→橙→红，到达指定等级突破
-- 升级消耗噬魂石(devour_stone)
-- ============================================================================

-- 装备部位定义
Config.EQUIP_SLOTS = {
    { id = "weapon", name = "武器", emoji = "⚔", stat = "atk",      statName = "攻击",       fmt = "flat" },
    { id = "armor",  name = "铠甲", emoji = "🛡", stat = "dmgBonus", statName = "伤害加成",   fmt = "pct" },
    { id = "helmet", name = "头盔", emoji = "⛑", stat = "critDmg",  statName = "暴击伤害",   fmt = "pct" },
    { id = "mount",  name = "战马", emoji = "🐴", stat = "elemDmg",  statName = "元素伤害",   fmt = "pct" },
}

-- 装备品质体系（对齐咸鱼之王）
Config.EQUIP_TIERS = {
    {
        id = "green", name = "腐骨", color = { 100, 200, 100 },
        bgColor = { 30, 50, 30, 220 }, borderColor = { 80, 160, 80, 200 },
        maxLevel = 200, unlockLevel = 0,
        breakCost = 200,  -- 绿→蓝 200锻魂铁
        setBonus = { atk_pct = 0.05 },  -- 套装: +5%攻击
        names = { weapon = "腐骨短刃", armor = "腐骨皮甲", helmet = "腐骨面罩", mount = "亡骸幽马" },
    },
    {
        id = "blue", name = "冥铁", color = { 80, 150, 255 },
        bgColor = { 25, 35, 55, 220 }, borderColor = { 60, 120, 220, 200 },
        maxLevel = 1000, unlockLevel = 200,
        breakCost = 1000,  -- 蓝→紫 1000锻魂铁
        setBonus = { atk_pct = 0.10 },  -- 套装: +10%攻击
        names = { weapon = "冥铁阔剑", armor = "冥铁锁甲", helmet = "冥铁角盔", mount = "幽蓝噩马" },
    },
    {
        id = "purple", name = "噬魂", color = { 180, 100, 255 },
        bgColor = { 40, 25, 55, 220 }, borderColor = { 150, 80, 220, 200 },
        maxLevel = 2000, unlockLevel = 1000,
        breakCost = 2700,  -- 紫→橙 2700锻魂铁
        setBonus = { atk_pct = 0.15 },  -- 套装: +15%攻击
        names = { weapon = "噬魂弯刀", armor = "噬魂胸甲", helmet = "噬魂冠冕", mount = "暗影梦魇" },
    },
    {
        id = "orange", name = "渊狱", color = { 255, 180, 50 },
        bgColor = { 50, 40, 20, 220 }, borderColor = { 220, 160, 40, 200 },
        maxLevel = 3000, unlockLevel = 2000,
        breakCost = 8000,  -- 橙→红 8000锻魂铁
        setBonus = { atk_pct = 0.25 },  -- 套装: +25%攻击
        names = { weapon = "渊狱裁决", armor = "渊狱重铠", helmet = "渊狱魔冠", mount = "炼狱焰驹" },
    },
    {
        id = "red", name = "灭世", color = { 220, 50, 50 },
        bgColor = { 50, 20, 20, 220 }, borderColor = { 200, 60, 60, 200 },
        maxLevel = 4000, unlockLevel = 3000,
        breakCost = 0,  -- 红色最终品质，无需突破（淬炼通过暗影精粹解锁）
        setBonus = { atk_pct = 0.40 },  -- 套装: +40%攻击
        names = { weapon = "灭世魔剑", armor = "灭世血铠", helmet = "灭世骨冠", mount = "虚空亡骑" },
    },
}

Config.EQUIP_MAX_LEVEL = 4000

-- 装备升级费用（噬魂石）: 分段公式
-- 1~200:    1/级
-- 201~1000: 2/级
-- 1001~2000: 4/级
-- 2001~3000: 8/级
-- 3001~4000: 15/级

-- 每级属性成长（基础值 × 等级倍率）
Config.EQUIP_STAT_BASE = {
    atk     = 12,      -- 每级+12攻击（整数）
    dmgBonus = 0.002,  -- 每级+0.2%伤害加成
    critDmg  = 0.003,  -- 每级+0.3%暴击伤害
    elemDmg  = 0.002,  -- 每级+0.2%元素伤害
}

-- 品质倍率（高品质基础加成更高）
Config.EQUIP_TIER_MULT = {
    green  = 1.0,
    blue   = 1.5,
    purple = 2.0,
    orange = 3.0,
    red    = 5.0,
}

-- ============================================================================
-- 装备淬炼系统
-- 红色满级(Lv.4000)后开启，消耗白玉随机附加属性词条
-- ============================================================================

-- 淬炼解锁条件
Config.TEMPER_UNLOCK_STAGE = 3001       -- 主线关卡 >= 3001
Config.TEMPER_UNLOCK_LEVEL = 4000       -- 装备等级 = 4000（红色满级）
Config.TEMPER_UNLOCK_COST = 2000        -- 暗影精粹解锁费用（按件）
Config.TEMPER_COST_JADE = 100           -- 每次淬炼消耗白玉
Config.TEMPER_SUCCESS_RATE = 0.40       -- 淬炼成功率 40%
Config.TEMPER_MAX_SLOTS = 5             -- 最大孔位数

-- 孔位解锁条件（累计淬炼次数）
Config.TEMPER_SLOT_UNLOCK = { 0, 10, 100, 1000, 10000 }

-- 淬炼属性池（13种进攻属性）
Config.TEMPER_ATTRIBUTES = {
    { id = "atk",           name = "攻击力",     maxValue = 0.10,  fmt = "pct" },
    { id = "spd",           name = "攻速",       maxValue = 0.10,  fmt = "pct" },
    { id = "critRate",      name = "暴击率",     maxValue = 0.20,  fmt = "pct" },
    { id = "critDmg",       name = "暴击伤害",   maxValue = 0.30,  fmt = "pct" },
    { id = "armorPen",      name = "破甲",       maxValue = 0.20,  fmt = "pct" },
    { id = "dmgBonus",      name = "伤害加成",   maxValue = 0.15,  fmt = "pct" },
    { id = "skillDmg",      name = "技能伤害",   maxValue = 0.20,  fmt = "pct" },
    { id = "ctrlHit",       name = "控制命中",   maxValue = 0.20,  fmt = "pct" },
    { id = "elemFire",      name = "火元素伤害", maxValue = 0.25,  fmt = "pct" },
    { id = "elemIce",       name = "冰元素伤害", maxValue = 0.25,  fmt = "pct" },
    { id = "elemShadow",    name = "暗影伤害",   maxValue = 0.25,  fmt = "pct" },
    { id = "elemPoison",    name = "毒元素伤害", maxValue = 0.25,  fmt = "pct" },
    { id = "elemLightning", name = "雷元素伤害", maxValue = 0.25,  fmt = "pct" },
}

-- 档位定义（白/绿/蓝/紫/橙/红）
Config.TEMPER_TIERS = {
    { id = "white",  name = "白", color = { 200, 200, 200 }, chance = 0.650, valueMin = 0.50, valueMax = 0.80 },
    { id = "green",  name = "绿", color = { 100, 200, 100 }, chance = 0.200, valueMin = 0.60, valueMax = 0.90 },
    { id = "blue",   name = "蓝", color = { 80, 150, 255 },  chance = 0.110, valueMin = 0.70, valueMax = 1.00 },
    { id = "purple", name = "紫", color = { 180, 100, 255 }, chance = 0.024, valueMin = 0.80, valueMax = 1.10 },
    { id = "orange", name = "橙", color = { 255, 180, 50 },  chance = 0.012, valueMin = 0.90, valueMax = 1.30 },
    { id = "red",    name = "红", color = { 220, 50, 50 },   chance = 0.004, valueMin = 1.30, valueMax = 1.50 },
}
-- valueMin/valueMax: 乘以部位1级基础值的倍率（取代设计文档中"50%~150%"的笼统范围）

end

return apply
