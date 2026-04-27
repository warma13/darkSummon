-- Game/Config_Meta.lua
-- 技能定义、阵营羁绊、结算、挂机、配色、路径、宝箱、装备

local function apply(Config)

-- ============================================================================
-- 英雄技能定义（全部 21 个英雄 + 主角）
-- ============================================================================
--- 辅助：格式化百分比（乘以f后取整），v 是满星值（0~1范围的比率）
---@param v number 满星比率值（如 0.05 表示 5%）
---@param f number 星级缩放因子（0.10~1.00）
---@return string 如 "5%", "3%"
local function P(v, f)
    local r = v * f * 100
    if r == math.floor(r) then return string.format("%d%%", r) end
    return string.format("%.1f%%", r)
end

--- 辅助：格式化倍率（乘以f后取整），v 是满星倍率值（如 2.0 表示 200%）
---@param v number 满星倍率
---@param f number 星级缩放因子
---@return string 如 "200%", "52%"
local function M(v, f)
    local r = v * f * 100
    if r == math.floor(r) then return string.format("%d%%", r) end
    return string.format("%.1f%%", r)
end

--- 辅助：格式化小数百分比（保留1位小数），v 是满星比率值
---@param v number
---@param f number
---@return string 如 "0.5%", "3.2%"
local function PD(v, f)
    local r = v * f * 100
    if r % 1 == 0 then return string.format("%d%%", r) end
    return string.format("%.1f%%", r)
end

--- 辅助：格式化整数乘数，v 是满星乘数值（如 8 表示 ATK×8）
---@param v number
---@param f number
---@return string 如 "8", "2"
local function I(v, f) return tostring(math.floor(v * f + 0.5)) end

Config.HERO_SKILLS = {
    -- ====================================================================
    -- 功率预算体系（等比公比2）
    -- N=1 → R=2 → SR=4 → SSR=8 → UR=16 → LR=32
    -- 每个品质的总等效DPS贡献是前一品质的2倍
    -- ====================================================================

    -- ====================================================================
    -- N 级（30星满值）— 功率预算 1×
    -- 1个被动，效果简单。同品质总收益大致相当。
    -- skeleton_grunt: 纯攻速 → 30%攻速（约+37.5%DPS）
    -- bat_minion:     概率减速 → 40%×30%减速（控制向，DPS贡献约30%）
    -- hell_hound:     DOT倍率 → 2.0倍DOT（+100%DOT DPS）
    -- ====================================================================
    skeleton_grunt = {
        { id = "undead_tenacity", name = "亡灵韧性", desc = "攻速+30%",
          type = "passive", atkSpdBonus = 0.30,
          buildDesc = function(f) return "攻速+" .. P(0.30, f) end },
    },
    bat_minion = {
        { id = "vampire_instinct", name = "吸血本能", desc = "攻击40%概率减速目标30%持续1秒",
          type = "passive", chance = 0.40, slowRate = 0.30, slowDuration = 1.0,
          buildDesc = function(f) return "攻击" .. P(0.40, f) .. "概率减速目标" .. P(0.30, f) .. "持续1秒" end },
    },
    hell_hound = {
        { id = "flame_breath", name = "烈焰喷息", desc = "持续灼烧伤害提升100%",
          type = "passive", dotMultiplier = 2.0,
          buildDesc = function(f) return "持续灼烧伤害提升" .. P(1.0, f) end },
    },
    -- ====================================================================
    -- R 级（30星满值）— 功率预算 2×
    -- 2个被动，组合效果。总收益约为N级的2倍。
    -- skeleton_archer: 连射+增伤 → 40%连射+25%增伤（期望DPS+35%）
    -- demon_warrior:   燃地+波次攻速 → 1.5%/波最多50%（平均+25%攻速）
    -- ghost_assassin:  标记增伤+背刺 → 20%增伤+25%双倍（期望DPS+45%）
    -- stone_golem:     减速+溅射 → 30%减速+50%溅射概率（控制向）
    -- ====================================================================
    skeleton_archer = {
        { id = "multi_shot",     name = "连射", desc = "40%概率连射2箭",
          type = "passive", chance = 0.40,
          buildDesc = function(f) return P(0.40, f) .. "概率连射2箭" end },
        { id = "weak_mark",      name = "弱点标记", desc = "目标受伤+25%持续3秒",
          type = "passive", bonusDmg = 0.25, duration = 3.0,
          buildDesc = function(f) return "目标受伤+" .. P(0.25, f) .. "持续3秒" end },
    },
    demon_warrior = {
        { id = "burning_ground", name = "燃烧大地", desc = "范围攻击留下燃烧地面，持续2秒",
          type = "passive", burnDuration = 2.0 },
        { id = "demon_fury",     name = "恶魔之怒", desc = "攻速随波次+1.5%/波,最多+50%,每波重置",
          type = "passive", bonusPerWave = 0.015, maxBonus = 0.50,
          buildDesc = function(f) return "攻速随波次+" .. PD(0.015, f) .. "/波,最多+" .. P(0.50, f) .. ",每波重置" end },
    },
    ghost_assassin = {
        { id = "lethal_mark",    name = "致命标记", desc = "标记增伤提升至20%,对所有友方生效",
          type = "passive", ampRate = 0.20,
          buildDesc = function(f) return "标记增伤提升至" .. P(0.20, f) .. ",对所有友方生效" end },
        { id = "backstab",       name = "背刺", desc = "对已标记目标25%概率双倍伤害",
          type = "passive", chance = 0.25,
          buildDesc = function(f) return "对已标记目标" .. P(0.25, f) .. "概率双倍伤害" end },
    },
    stone_golem = {
        { id = "heavy_strike",   name = "沉重一击", desc = "减速提升至30%",
          type = "passive", newSlowRate = 0.30,
          buildDesc = function(f) return "减速提升至" .. P(0.30, f) end },
        { id = "rock_splash",    name = "碎石溅射", desc = "50%概率减速周围小范围内其他敌人",
          type = "passive", chance = 0.50, splashRange = 30,
          buildDesc = function(f) return P(0.50, f) .. "概率减速周围小范围内其他敌人" end },
    },
    -- ====================================================================
    -- SR 级（30星满值）— 功率预算 4×
    -- 2-3被动 + 0-1主动。总收益约为R级的2倍。
    -- necromancer:   减速45% + 诅咒DOT ATK×15% + 扩散（控制+持续伤害）
    -- inferno_flame: DOT×3.0 + 蔓延 + BOSS ATK×800%（DOT专精，BOSS杀手）
    -- armor_breaker: 破甲20% × 3层 + 满层+35%受伤（减防辅助）
    -- frost_witch:   减速35% + 20%冰冻 + 主动全屏减速50%（控制专精）
    -- war_drummer:   攻击光环25% + 攻速15% + 主动全体+40%（辅助专精）
    -- ====================================================================
    necromancer = {
        { id = "deep_freeze",    name = "深度冻结", desc = "减速提升至45%",
          type = "passive", newSlowRate = 0.45,
          buildDesc = function(f) return "减速提升至" .. P(0.45, f) end },
        { id = "curse_mark",     name = "诅咒标记", desc = "被减速的敌人每秒受到攻击力×15%的诅咒伤害",
          type = "passive", curseDmgAtkPct = 0.15,
          buildDesc = function(f) return "被减速的敌人每秒受到攻击力×" .. P(0.15, f) .. "的诅咒伤害" end },
        { id = "soul_chain",     name = "灵魂锁链", desc = "减速效果扩散至周围小范围内最多2个敌人，不会二次扩散",
          type = "passive", chainRange = 40, chainMaxTargets = 2 },
    },
    inferno_flame = {
        { id = "enhanced_burn",  name = "强化灼烧", desc = "持续灼烧伤害提升200%",
          type = "passive", dotMultiplier = 3.0,
          buildDesc = function(f) return "持续灼烧伤害提升" .. P(2.0, f) end },
        { id = "fire_spread",    name = "火焰蔓延", desc = "灼烧中的敌人死亡时，将剩余灼烧传递给周围敌人",
          type = "passive" },
        { id = "nirvana_flame",  name = "涅槃之炎", desc = "对首领单位的持续灼烧改为每秒造成攻击力×800%伤害",
          type = "passive", bossAtkPct = 8.0,
          buildDesc = function(f) return "对首领的持续灼烧改为每秒攻击力×" .. M(8.0, f) .. "伤害" end },
    },
    armor_breaker = {
        { id = "precise_strike", name = "精准打击", desc = "护甲削减提升至20%",
          type = "passive", armorBreak = 0.20,
          buildDesc = function(f) return "护甲削减提升至" .. P(0.20, f) end },
        { id = "armor_stack",    name = "破甲叠加", desc = "最多叠加3层",
          type = "passive", maxStacks = 3 },
        { id = "fatal_weakness", name = "致命弱点", desc = "满层目标额外受到35%伤害",
          type = "passive", fullStackBonus = 0.35,
          buildDesc = function(f) return "满层目标额外受到" .. P(0.35, f) .. "伤害" end },
    },
    frost_witch = {
        { id = "extreme_cold",   name = "极寒之触", desc = "减速提升至35%",
          type = "passive", newSlowRate = 0.35,
          buildDesc = function(f) return "减速提升至" .. P(0.35, f) end },
        { id = "freeze_chance",  name = "冰冻概率", desc = "20%概率冰冻敌人1.5秒；首领免疫冰冻，改为减速50%",
          type = "passive", chance = 0.20, freezeDuration = 1.5, bossFallbackSlow = 0.50,
          buildDesc = function(f) return P(0.20, f) .. "概率冰冻敌人1.5秒；首领免疫冰冻，改为减速" .. P(0.50, f) end },
        { id = "blizzard",       name = "暴风雪", desc = "每20秒全屏减速50%持续3秒",
          type = "active", interval = 20, slowPct = 0.50, duration = 3.0,
          buildDesc = function(f) return "每20秒全屏减速" .. P(0.50, f) .. "持续3秒" end },
    },
    war_drummer = {
        { id = "morale_boost",   name = "鼓舞士气", desc = "光环攻击加成提升至25%",
          type = "passive", atkBuff = 0.25,
          buildDesc = function(f) return "光环攻击加成提升至" .. P(0.25, f) end },
        { id = "war_rhythm",     name = "战吼节奏", desc = "光环额外+15%攻速",
          type = "passive", spdBuff = 0.15,
          buildDesc = function(f) return "光环额外+" .. P(0.15, f) .. "攻速" end },
        { id = "heroic_anthem",  name = "英勇战歌", desc = "每30秒全体塔攻击+40%持续5秒",
          type = "active", interval = 30, atkBuffPct = 0.40, duration = 5.0,
          buildDesc = function(f) return "每30秒全体塔攻击+" .. P(0.40, f) .. "持续5秒" end },
    },
    -- ====================================================================
    -- SSR 级（30星满值）— 功率预算 8×
    -- 2-3被动 + 1主动。总收益约为SR级的2倍。
    -- shadow_mage:   45%无视护盾 + 击杀+65%×3层 + 主动全屏105%ATK（爆发向）
    -- abyss_hunter:  BOSS额外65% + 暴击40%/105% + 主动25%HP（BOSS专精）
    -- plague_doctor: 减甲13% + 扩散90% + 主动引爆DOT×650%（DOT辅助）
    -- storm_lord:    眩晕40% + 范围+40 + 主动全屏80%ATK+减速（控制+爆发）
    -- ====================================================================
    shadow_mage = {
        { id = "shadow_pierce",  name = "暗影穿透", desc = "攻击45%概率无视护盾",
          type = "passive", chance = 0.45, maxChance = 0.85,
          buildDesc = function(f) return "攻击" .. P(0.45, f) .. "概率无视护盾" end },
        { id = "soul_reap",      name = "灵魂收割", desc = "击杀后下次攻击+65%,叠3层,攻击后清零",
          type = "passive", killDmgBonus = 0.65, maxStacks = 3,
          buildDesc = function(f) return "击杀后下次攻击+" .. P(0.65, f) .. ",叠3层,攻击后清零" end },
        { id = "void_storm",     name = "虚空风暴", desc = "每15秒全屏105%攻击力伤害",
          type = "active", interval = 15, damagePct = 1.05,
          buildDesc = function(f) return "每15秒全屏" .. P(1.05, f) .. "攻击力伤害" end },
    },
    abyss_hunter = {
        { id = "hunt_instinct",  name = "猎杀本能", desc = "对首领单位额外伤害提升至65%",
          type = "passive", bossExtraDmg = 0.65,
          buildDesc = function(f) return "对首领额外伤害提升至" .. P(0.65, f) end },
        { id = "deadly_crossbow", name = "致命猎弩", desc = "暴击率+40%,暴击伤害+105%",
          type = "passive", critRate = 0.40, critDmg = 1.05,
          buildDesc = function(f) return "暴击率+" .. P(0.40, f) .. ",暴击伤害+" .. P(1.05, f) end },
        { id = "abyss_arrow",    name = "深渊之箭", desc = "每12秒对生命值最高的敌人造成其最大生命值25%的伤害；对首领伤害上限为攻击力×16",
          type = "active", interval = 12, hpPct = 0.25, bossAtkCap = 16,
          buildDesc = function(f) return "每12秒对生命值最高的敌人造成其最大生命值" .. P(0.25, f) .. "的伤害；对首领上限攻击力×" .. I(16, f) end },
    },
    plague_doctor = {
        { id = "toxic_miasma",   name = "剧毒瘴气", desc = "受到持续伤害的敌人护甲抵抗降低13%",
          type = "passive", armorReduce = 0.13,
          buildDesc = function(f) return "受到持续伤害的敌人护甲抵抗降低" .. P(0.13, f) end },
        { id = "infection_spread", name = "感染扩散", desc = "受到持续伤害的目标死亡时，将90%的持续伤害感染给周围小范围内最多2个敌人，不会二次扩散",
          type = "passive", spreadRange = 30, spreadMaxTargets = 2, spreadRatio = 0.90,
          buildDesc = function(f) return "持续伤害目标死亡时，将" .. P(0.90, f) .. "的伤害感染给周围最多2个敌人，不会二次扩散" end },
        { id = "plague_burst",   name = "瘟疫爆发", desc = "每18秒引爆全场所有持续伤害效果，造成剩余持续伤害650%的即时伤害",
          type = "active", interval = 18, burstMult = 6.5,
          buildDesc = function(f) return "每18秒引爆全场持续伤害，造成剩余伤害" .. M(6.5, f) .. "的即时伤害" end },
    },
    storm_lord = {
        { id = "thunder_strike", name = "雷鸣一击", desc = "眩晕概率提升至40%",
          type = "passive", stunChance = 0.40,
          buildDesc = function(f) return "眩晕概率提升至" .. P(0.40, f) end },
        { id = "storm_eye",      name = "风暴之眼", desc = "攻击范围提升40",
          type = "passive", rangeBonus = 40 },
        { id = "divine_thunder", name = "天降雷霆", desc = "每22秒全屏80%攻击力伤害并减速65%持续2秒",
          type = "active", interval = 22, damagePct = 0.80, slowPct = 0.65, slowDuration = 2.0,
          buildDesc = function(f) return "每22秒全屏" .. P(0.80, f) .. "攻击力伤害并减速" .. P(0.65, f) .. "持续2秒" end },
    },
    -- ====================================================================
    -- UR 级限定（30星满值）— 功率预算 16×
    -- glacial_sovereign: 独特寒意机制，满层增伤95%，数值不走NUMERIC_KEYS缩放
    -- ====================================================================
    glacial_sovereign = {
        { id = "piercing_chill",    name = "凌冽寒意", desc = "每秒对范围内敌人施加1层寒意,每层减速20%,最多5层,持续5秒;满5层受伤+95%",
          type = "passive",
          buildDesc = function(f) return "每秒对范围内敌人施加1层寒意,每层减速" .. P(0.20, f) .. ",最多5层,持续5秒;满5层受伤+" .. P(0.95, f) end },
        { id = "frost_strike",      name = "霜寒之击", desc = "普通攻击附带1层寒意",
          type = "passive" },
        { id = "glacial_eruption",  name = "冰川爆发", desc = "每累积50层全局寒意,对全屏敌人施加5层寒意",
          type = "passive", chillGlobalThreshold = 50, chillApplyAll = 5 },
    },
    -- ====================================================================
    -- UR 级（30星满值）— 功率预算 16×
    -- 2-3被动 + 1主动。总收益约为SSR级的2倍。
    -- fallen_archangel: 增伤65% + 暴击光环45% + 主动全屏225%ATK（辅助+爆发）
    -- void_dragon:      DOT ATK×45% + BOSS额外95% + 主动全屏280%ATK（DOT+BOSS+爆发）
    -- nature_elf/crimson_night: starScale=true，自管缩放
    -- ====================================================================
    fallen_archangel = {
        { id = "divine_judgment_light", name = "神罚之光", desc = "标记增伤提升至65%",
          type = "passive", ampRate = 0.65,
          buildDesc = function(f) return "标记增伤提升至" .. P(0.65, f) end },
        { id = "angel_judgment",  name = "天使审判", desc = "每15秒全屏225%攻击力伤害",
          type = "active", interval = 15, damagePct = 2.25,
          buildDesc = function(f) return "每15秒全屏" .. P(2.25, f) .. "攻击力伤害" end },
        { id = "fallen_glory",   name = "堕落荣光", desc = "散发堕落光环，范围内友方暴击率+45%",
          type = "passive", auraRange = 100, critRateBuff = 0.45,
          buildDesc = function(f) return "散发堕落光环，范围内友方暴击率+" .. P(0.45, f) end },
    },
    void_dragon = {
        { id = "dragon_breath_dot", name = "龙息灼烧", desc = "链式攻击附带每秒攻击力×45%的灼烧伤害，持续3秒",
          type = "passive", dotAtkPct = 0.45, dotDuration = 3.0,
          buildDesc = function(f) return "链式攻击附带每秒攻击力×" .. P(0.45, f) .. "的灼烧伤害，持续3秒" end },
        { id = "void_tear",      name = "虚空撕裂", desc = "对首领单位额外伤害提升至95%",
          type = "passive", bossExtraDmg = 0.95,
          buildDesc = function(f) return "对首领额外伤害提升至" .. P(0.95, f) end },
        { id = "dragon_wrath",   name = "龙王之怒", desc = "每12秒全屏280%攻击力伤害并减速55%持续3秒",
          type = "active", interval = 12, damagePct = 2.80, slowPct = 0.55, slowDuration = 3.0,
          buildDesc = function(f) return "每12秒全屏" .. P(2.80, f) .. "攻击力伤害并减速" .. P(0.55, f) .. "持续3秒" end },
    },
    -- ====================================================================
    -- LR 级（30星满值）— 功率预算 32×
    -- 3-4被动 + 1主动。总收益约为UR级的2倍。顶级定位。
    -- fate_weaver:      治愈削减85% + 70%双倍伤害 + 暴击溅射230% + 主动重置CD
    -- eternal_archfiend: 暴击80%/440% + 击杀+9%最多175% + 处决30% + 主动70%HP
    -- ====================================================================
    fate_weaver = {
        { id = "fate_thread",    name = "命运之线", desc = "光环降低敌人受治愈效果85%",
          type = "passive", healReduction = 0.85,
          buildDesc = function(f) return "光环降低敌人受治愈效果" .. P(0.85, f) end },
        { id = "causality",      name = "因果律", desc = "全体友方塔70%概率双倍伤害",
          type = "passive", doubleDmgChance = 0.70,
          buildDesc = function(f) return "全体友方塔" .. P(0.70, f) .. "概率双倍伤害" end },
        { id = "fate_finale",    name = "命运终章", desc = "友方致命一击时,溅射230%伤害给周围敌人",
          type = "passive", critSplashPct = 2.30,
          buildDesc = function(f) return "友方致命一击时,溅射" .. P(2.30, f) .. "伤害给周围敌人" end },
        { id = "time_weave",     name = "时间编织", desc = "每25秒重置全体友方塔技能CD",
          type = "active", interval = 25 },
    },
    eternal_archfiend = {
        { id = "archfiend_strike", name = "魔君一击", desc = "暴击率+80%,暴击伤害+440%",
          type = "passive", critRate = 0.80, critDmg = 4.40,
          buildDesc = function(f) return "暴击率+" .. P(0.80, f) .. ",暴击伤害+" .. P(4.40, f) end },
        { id = "eternal_power",  name = "永恒之力", desc = "击杀+9%攻击,最多+175%,每波重置",
          type = "passive", killAtkBonus = 0.09, maxBonus = 1.75,
          buildDesc = function(f) return "击杀+" .. PD(0.09, f) .. "攻击,最多+" .. P(1.75, f) .. ",每波重置" end },
        { id = "final_judgment", name = "终焉审判", desc = "生命值低于30%的敌人直接处决；首领免疫处决，改为造成攻击力×44的固定伤害",
          type = "passive", executeThreshold = 0.30, bossFixedAtkMult = 44,
          buildDesc = function(f) return "生命值低于" .. P(0.30, f) .. "的敌人直接处决；首领免疫，改为攻击力×" .. I(44, f) .. "固定伤害" end },
        { id = "worldfire",      name = "灭世之炎", desc = "每10秒对生命值最高的敌人造成其当前生命值70%的伤害；对首领伤害上限为攻击力×44",
          type = "active", interval = 10, hpPct = 0.70, bossAtkCap = 44,
          buildDesc = function(f) return "每10秒对生命值最高的敌人造成其当前生命值" .. P(0.70, f) .. "的伤害；对首领上限攻击力×" .. I(44, f) end },
    },
    -- 主角（按SSR级功率预算 8×）
    leader = {
        { id = "shadow_dominion", name = "暗影支配", desc = "全体友方塔攻击+20%",
          type = "passive", globalAtkBuff = 0.20,
          buildDesc = function(f) return "全体友方塔攻击+" .. P(0.20, f) end },
        { id = "lord_will",      name = "君主意志", desc = "击杀敌人时20%概率缩短主动技能1秒冷却时间",
          type = "passive", chance = 0.20, cdResetAmount = 1.0,
          buildDesc = function(f) return "击杀时" .. P(0.20, f) .. "概率缩短主动技能1秒冷却" end },
        { id = "shadow_devour",  name = "暗影吞噬", desc = "每10秒全屏105%攻击力伤害",
          type = "active", interval = 10, damagePct = 1.05,
          buildDesc = function(f) return "每10秒全屏" .. P(1.05, f) .. "攻击力伤害" end },
    },
    ember_wraith = {
        { id = "chain_ignite",    name = "灰烬蔓延",
          desc = "攻击叠加灼烧（最多3层，持续3秒），每层每秒造成攻击力×15%的火焰伤害；灼烧中的敌人死亡时，向周围敌人造成攻击力×150%的火焰伤害并施加1层灼烧",
          type = "passive",
          maxStacks = 3, stackDuration = 3.0,
          dotPctPerStack = 0.15,
          deathAoePct = 1.50, deathRadius = 60,
          starScale = true,
          buildDesc = function(f)
              return "攻击叠加灼烧（最多3层，持续3秒），每层每秒攻击力×" .. P(0.15, f) .. "火焰伤害；死亡蔓延攻击力×" .. M(1.50, f) .. "火焰伤害"
          end },
        { id = "ember_resonance", name = "烬核共振",
          desc = "场上每个灼烧中的敌人为烬殇提供+4%攻击力和+6%持续伤害加成，最多叠加12层",
          type = "passive",
          atkPerBurn = 0.04, dotAmpPerBurn = 0.06,
          maxBurns = 12,
          starScale = true,
          buildDesc = function(f)
              return "每个灼烧敌人+" .. PD(0.04, f) .. "攻击力和+" .. PD(0.06, f) .. "持续伤害加成，最多12层"
          end },
        { id = "heavens_pyre",    name = "焚天",
          desc = "对范围内所有敌人造成攻击力×600%的火焰伤害；生命值低于30%且正在灼烧的敌人直接处决，被处决者爆炸对周围造成攻击力×300%火焰伤害并施加2层灼烧（冷却16秒）",
          type = "active", interval = 16,
          baseAtkPct = 6.0,
          executeThreshold = 0.30,
          executeAoePct = 3.0,
          executeRadius = 50,
          executeIgniteStacks = 2,
          starScale = true,
          buildDesc = function(f)
              return "范围攻击力×" .. M(6.0, f) .. "火焰伤害；生命值低于30%的灼烧敌人处决，爆炸攻击力×" .. M(3.0, f) .. "火焰伤害"
          end },
    },
    nature_elf = {
        { id = "nature_gift",    name = "自然馈赠", desc = "每3秒为范围内英雄注入3点自然之力（持续8秒），自然之力越多越接近上限：攻击+115%、攻速+75%，并额外获得翎嫣攻击力×19%的固定攻击加成",
          type = "passive", starScale = true,
          buildDesc = function(f)
              local atkPct = math.floor(115 * f + 0.5)
              local spdPct = math.floor(75 * f + 0.5)
              local ratPct = math.floor(19 * f * 10 + 0.5) / 10
              local ratStr = ratPct % 1 == 0 and string.format("%d", ratPct) or string.format("%.1f", ratPct)
              return string.format(
                  "每3秒为范围内英雄注入3点自然之力（持续8秒），自然之力越多越接近上限：攻击+%d%%、攻速+%d%%，并额外获得翎嫣攻击力×%s%%的固定攻击加成",
                  atkPct, spdPct, ratStr)
          end },
        { id = "verdant_ward",   name = "翠意庇护", desc = "当英雄自然之力≥20时触发翠意状态，持续5秒内免疫沉默、禁锢等负面效果，内置20秒冷却",
          type = "passive" },
        { id = "wilds_call",     name = "绿野之呼", desc = "每20秒自动为所有英雄提供55点自然之力，并为攻击力最高且未持有鲜花环的英雄赠送鲜花环（+75%攻击力，持续10秒，每个英雄最多1个）",
          type = "active", interval = 20, starScale = true,
          buildDesc = function(f)
              local force     = math.floor(55 * f)
              local wreathPct = math.floor(75 * f + 0.5)
              return string.format(
                  "每20秒自动为所有英雄提供%d点自然之力，并为攻击力最高且未持有鲜花环的英雄赠送鲜花环（+%d%%攻击力，持续10秒，每个英雄最多1个）",
                  force, wreathPct)
          end },
    },
    crimson_night = {
        { id = "shadow_needle",  name = "暗影之针",
          desc = "普攻叠加暗影印记（最多5层，持续4秒）；满5层触发穿刺爆发，造成攻击力×380%的暗影伤害，无视38%护甲",
          type = "passive",
          maxStacks = 5, stackDuration = 4.0,
          burstAtkPct = 3.80, armorIgnore = 0.38,
          starScale = true,
          buildDesc = function(f) return "普攻叠加暗影印记（最多5层，持续4秒）；满5层穿刺爆发，造成攻击力×" .. M(3.80, f) .. "暗影伤害，无视" .. P(0.38, f) .. "护甲" end },
        { id = "blood_eye",      name = "绯瞳锁定",
          desc = "攻击获得绯瞳,每层+6%暴击率(最多+60%),暴击伤害+95%;4秒未攻击则绯瞳消失",
          type = "passive",
          critRatePerHit = 0.06, maxCritStacks = 10,
          critDmgBonus = 0.95,
          decayDuration = 4.0,
          starScale = true,
          buildDesc = function(f)
              local perHit = PD(0.06, f)
              local maxCrit = P(0.06 * 10, f)
              local critDmg = P(0.95, f)
              return "攻击获得绯瞳,每层+" .. perHit .. "暴击率(最多+" .. maxCrit .. "),暴击伤害+" .. critDmg .. ";4秒未攻击则绯瞳消失"
          end },
        { id = "abyss_strike",   name = "深渊一刺",
          desc = "对当前目标造成攻击力×1520%的暗影伤害，必定暴击；每层绯瞳额外+190%攻击力伤害并消耗全部绯瞳；击杀时保留一半绯瞳层数（冷却14秒）",
          type = "active", interval = 14,
          baseAtkPct = 15.20, stackBonusPct = 1.90,
          guaranteedCrit = true,
          starScale = true,
          buildDesc = function(f) return "对当前目标造成攻击力×" .. M(15.20, f) .. "暗影伤害，必定暴击；每层绯瞳额外+" .. M(1.90, f) .. "攻击力伤害并消耗绯瞳；击杀保留一半层数" end },
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
    -- 冥晶: 挂机/hr = s*17500, 每关 = s*17500/3 ≈ s*5825 (×5)
    local crystal = math.floor(s * 5825)
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
        -- 掉落: 3分钟挂机收益（冥晶+噬魂石+锻魂铁）
        idleMinutes = 3,     -- 按挂机收益计算，3分钟
        drops = {
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
    { id = "weapon", name = "武器", emoji = "⚔", stat = "atk",      statName = "攻击",       fmt = "pct" },
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
    atk      = 0.002,  -- 每级+0.2%攻击（百分比，与dmgBonus对齐）
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
