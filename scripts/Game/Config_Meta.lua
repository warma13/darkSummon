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
        { id = "demon_flame",    name = "魔焰之力", desc = "每次攻击获得1层魔焰,持续5秒,每层+8%暴击率+35%暴击伤害,最多8层",
          type = "passive",
          maxStacks = 8, stackDuration = 5.0,
          critRatePerStack = 0.08, critDmgPerStack = 0.35,
          buildDesc = function(f) return "每次攻击获得1层魔焰,持续" .. I(5, f) .. "秒,每层+" .. P(0.08, f) .. "暴击率+" .. P(0.35, f) .. "暴击伤害,最多" .. I(8, f) .. "层" end },
        { id = "eternal_erode",  name = "永恒侵蚀", desc = "每次暴击获得1层侵蚀,持续6秒,每层+5%伤害加成;满6层时30%伤害转化为真伤",
          type = "passive",
          maxStacks = 6, stackDuration = 6.0,
          dmgBonusPerStack = 0.05, trueDmgConvert = 0.30,
          buildDesc = function(f) return "暴击获得侵蚀,每层+" .. P(0.05, f) .. "伤害加成,满" .. I(6, f) .. "层时" .. P(0.30, f) .. "伤害转真伤" end },
        { id = "worldfire_ember", name = "灭世余烬", desc = "暴击时35%概率对目标周围敌人造成150%攻击力范围伤害",
          type = "passive",
          procChance = 0.35, aoeDamagePct = 1.50, aoeRange = 60,
          buildDesc = function(f) return "暴击时" .. P(0.35, f) .. "概率造成" .. P(1.50, f) .. "攻击力范围伤害" end },
        { id = "abyss_mark",     name = "深渊印记", desc = "标记场上生命值最高的敌人,使其受到伤害+40%,持续12秒;目标死亡时转移至下一个血量最高敌人",
          type = "active", interval = 15,
          ampRate = 0.40, markDuration = 12.0,
          buildDesc = function(f) return "标记血量最高敌人,受伤+" .. P(0.40, f) .. ",持续" .. I(12, f) .. "秒,死亡转移" end },
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
-- 技能标签升级消耗（技能书）
-- [稀有度] = { [tier2消耗], [tier3消耗] }
-- ============================================================================
Config.SKILL_BOOK_COST = {
    N   = { { skill_book_1 = 3 },   nil },
    R   = { { skill_book_1 = 5 },   { skill_book_1 = 10, skill_book_2 = 5 } },
    SR  = { { skill_book_1 = 10 },  { skill_book_2 = 15, skill_book_3 = 5 } },
    SSR = { { skill_book_1 = 15, skill_book_2 = 5 },  { skill_book_2 = 30, skill_book_3 = 10 } },
    UR  = { { skill_book_2 = 20, skill_book_3 = 10 }, { skill_book_3 = 40 } },
    LR  = { { skill_book_2 = 40, skill_book_3 = 20 }, { skill_book_3 = 80 } },
}

-- ============================================================================
-- 英雄技能标签系统（多层可升级标签，替代单一 special 字段）
-- type: on_hit / on_crit / on_kill / aura / active / conditional
-- tier: 当前等级（0=未解锁）  maxTier: 最高等级
-- unlock: { star=N } 或 { advance=N } 解锁条件
-- requires: { "tagId" } 前置标签依赖
-- effects: { [tier] = { 属性表 + desc } }
-- ============================================================================
Config.HERO_SKILL_TAGS = {

    -- ================================================================
    -- N 级：1 基础标签 + 1 解锁标签
    -- ================================================================

    skeleton_grunt = {
        {
            id = "tenacity", name = "坚韧", type = "passive",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { atkSpdBonus = 0.20, desc = "攻速+20%" },
                [2] = { atkSpdBonus = 0.30, desc = "攻速+30%" },
            },
        },
        {
            id = "bone_spike", name = "骨刺", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            effects = {
                [1] = { physVuln = 0.10, duration = 3.0, desc = "攻击使目标额外受到物理伤害+10%，持续3秒" },
                [2] = { physVuln = 0.15, duration = 4.0, desc = "攻击使目标额外受到物理伤害+15%，持续4秒" },
            },
        },
    },

    bat_minion = {
        {
            id = "vampire_instinct", name = "吸血本能", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.30, slowRate = 0.25, slowDuration = 1.0, desc = "攻击30%概率减速目标25%，持续1秒" },
                [2] = { chance = 0.40, slowRate = 0.30, slowDuration = 1.0, desc = "攻击40%概率减速目标30%，持续1秒" },
            },
        },
        {
            id = "bloodlust", name = "嗜血", type = "on_kill",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            effects = {
                [1] = { atkSpdBurst = 0.50, burstDuration = 3.0, desc = "击杀后攻速+50%，持续3秒" },
                [2] = { atkSpdBurst = 0.80, burstDuration = 3.0, desc = "击杀后攻速+80%，持续3秒" },
            },
        },
    },

    hell_hound = {
        {
            id = "scorch", name = "灼烧", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { dotMultiplier = 1.5, desc = "持续灼烧伤害提升50%" },
                [2] = { dotMultiplier = 2.0, desc = "持续灼烧伤害提升100%" },
            },
        },
        {
            id = "searing", name = "炽热", type = "on_hit",
            tier = 0, maxTier = 3,
            unlock = { advance = 6 },
            requires = { "scorch" },
            effects = {
                [1] = { resReduce = 5,  duration = 3.0, desc = "灼烧目标魔抗降低5，持续3秒" },
                [2] = { resReduce = 10, duration = 4.0, desc = "灼烧目标魔抗降低10，持续4秒" },
                [3] = { resReduce = 15, duration = 5.0, desc = "灼烧目标魔抗降低15，持续5秒" },
            },
        },
    },

    -- ================================================================
    -- R 级：2 基础标签 + 1 解锁标签
    -- ================================================================

    skeleton_archer = {
        {
            id = "multi_shot", name = "连射", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.30, desc = "30%概率连射2箭" },
                [2] = { chance = 0.40, desc = "40%概率连射2箭" },
            },
        },
        {
            id = "pierce_mark", name = "穿透标记", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { bonusDmg = 0.20, duration = 3.0, desc = "命中使目标受伤+20%，持续3秒" },
                [2] = { bonusDmg = 0.25, duration = 3.0, desc = "命中使目标受伤+25%，持续3秒" },
            },
        },
        {
            id = "weakness_shot", name = "弱点射击", type = "conditional",
            tier = 0, maxTier = 2,
            unlock = { star = 10 },
            requires = { "pierce_mark" },
            effects = {
                [1] = { critOnMaxMark = true, desc = "标记满时下一击暴击率100%" },
                [2] = { critOnMaxMark = true, critDmgBonus = 0.50, desc = "标记满时下一击必暴且暴伤+50%" },
            },
        },
    },

    demon_warrior = {
        {
            id = "hunt_instinct", name = "猎杀本能", type = "passive",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { bossExtraDmg = 0.30, desc = "对首领额外伤害+30%" },
                [2] = { bossExtraDmg = 0.50, desc = "对首领额外伤害+50%" },
            },
        },
        {
            id = "battle_fury", name = "战意", type = "passive",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { bonusPerWave = 0.015, maxBonus = 0.30, desc = "攻速随波次+1.5%/波，最多+30%" },
                [2] = { bonusPerWave = 0.015, maxBonus = 0.50, desc = "攻速随波次+1.5%/波，最多+50%" },
            },
        },
        {
            id = "execute", name = "斩杀", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 10 },
            effects = {
                [1] = { threshold = 0.20, dmgMult = 2.0, desc = "目标血量低于20%时伤害翻倍" },
                [2] = { threshold = 0.30, dmgMult = 2.0, desc = "目标血量低于30%时伤害翻倍" },
            },
        },
    },

    ghost_assassin = {
        {
            id = "shadow_stab", name = "暗刺", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { firstHitMult = 2.0, desc = "首次攻击目标伤害×2" },
                [2] = { firstHitMult = 2.5, desc = "首次攻击目标伤害×2.5" },
            },
        },
        {
            id = "lethal_mark", name = "致命标记", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { ampRate = 0.15, duration = 3.0, desc = "标记增伤15%，持续3秒" },
                [2] = { ampRate = 0.20, duration = 3.0, desc = "标记增伤20%，持续3秒，对所有友方生效" },
            },
        },
        {
            id = "fatal_pierce", name = "致命穿刺", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 10 },
            requires = { "shadow_stab" },
            effects = {
                [1] = { armorIgnore = 0.30, desc = "暗刺命中忽视30%物防" },
                [2] = { armorIgnore = 0.50, desc = "暗刺命中忽视50%物防" },
            },
        },
    },

    stone_golem = {
        {
            id = "quake", name = "震击", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { slowRate = 0.25, aoe = false, desc = "减速目标25%" },
                [2] = { slowRate = 0.30, aoe = true, splashRange = 30, desc = "减速目标及周围30%，并溅射" },
            },
        },
        {
            id = "rock_splash", name = "碎石溅射", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.40, splashRange = 30, desc = "40%概率溅射周围敌人" },
                [2] = { chance = 0.50, splashRange = 40, desc = "50%概率溅射周围敌人" },
            },
        },
        {
            id = "fissure", name = "地裂", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 10 },
            requires = { "quake" },
            effects = {
                [1] = { physVuln = 0.10, duration = 3.0, desc = "被减速目标受物理伤害+10%，持续3秒" },
                [2] = { physVuln = 0.15, duration = 4.0, desc = "被减速目标受物理伤害+15%，持续4秒" },
            },
        },
    },

    -- ================================================================
    -- SR 级：2 基础标签 + 2 解锁标签
    -- ================================================================

    necromancer = {
        {
            id = "dark_chain", name = "暗能链", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { slowRate = 0.35, desc = "链式攻击减速35%" },
                [2] = { slowRate = 0.45, desc = "链式攻击减速45%" },
            },
        },
        {
            id = "soul_drain", name = "灵魂汲取", type = "on_kill",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { cdReduce = 1.0, desc = "击杀缩短主动技能1秒CD" },
                [2] = { cdReduce = 2.0, desc = "击杀缩短主动技能2秒CD" },
            },
        },
        {
            id = "soul_burst", name = "魂爆", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "dark_chain" },
            effects = {
                [1] = { chainEndAoe = true, aoeDmgPct = 0.50, aoeRange = 40, desc = "链式终点产生范围爆炸，造成50%ATK伤害" },
                [2] = { chainEndAoe = true, aoeDmgPct = 0.80, aoeRange = 50, desc = "链式终点产生范围爆炸，造成80%ATK伤害" },
            },
        },
        {
            id = "death_whisper", name = "亡者低语", type = "aura",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            effects = {
                [1] = { resReduce = 8,  auraRange = 100, desc = "光环降低周围敌人8点魔抗" },
                [2] = { resReduce = 15, auraRange = 120, desc = "光环降低周围敌人15点魔抗" },
            },
        },
    },

    inferno_flame = {
        {
            id = "blaze", name = "烈焰", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { dotMultiplier = 2.0, desc = "灼烧伤害提升100%" },
                [2] = { dotMultiplier = 3.0, desc = "灼烧伤害提升200%" },
            },
        },
        {
            id = "ignite", name = "引燃", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.30, burnDuration = 2.0, desc = "30%概率额外引燃2秒" },
                [2] = { chance = 0.50, burnDuration = 3.0, desc = "50%概率额外引燃3秒" },
            },
        },
        {
            id = "wildfire", name = "燎原", type = "on_kill",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "ignite" },
            effects = {
                [1] = { spreadRange = 40, spreadTargets = 2, desc = "灼烧目标死亡时传播给周围2个敌人" },
                [2] = { spreadRange = 50, spreadTargets = 3, desc = "灼烧目标死亡时传播给周围3个敌人" },
            },
        },
        {
            id = "scald", name = "炙烤", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            requires = { "blaze" },
            effects = {
                [1] = { defReduce = 0.10, duration = 3.0, desc = "灼烧目标物防降低10%，持续3秒" },
                [2] = { defReduce = 0.15, duration = 4.0, desc = "灼烧目标物防降低15%，持续4秒" },
            },
        },
    },

    armor_breaker = {
        {
            id = "sunder", name = "破甲", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { armorBreak = 0.15, maxStacks = 3, duration = 5.0, desc = "叠加破甲15%，最多3层，持续5秒" },
                [2] = { armorBreak = 0.20, maxStacks = 3, duration = 5.0, desc = "叠加破甲20%，最多3层，持续5秒" },
            },
        },
        {
            id = "heavy_blow", name = "重击", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { everyN = 4, trueDmgPct = 0.50, desc = "每4次攻击追加50%ATK真实伤害" },
                [2] = { everyN = 3, trueDmgPct = 0.80, desc = "每3次攻击追加80%ATK真实伤害" },
            },
        },
        {
            id = "shatter", name = "粉碎", type = "conditional",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "sunder" },
            effects = {
                [1] = { fullStackDefZero = true, desc = "破甲满层时目标DEF归零" },
                [2] = { fullStackDefZero = true, bonusDmg = 0.20, desc = "破甲满层DEF归零且受伤+20%" },
            },
        },
        {
            id = "aftershock", name = "余震", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            requires = { "sunder" },
            effects = {
                [1] = { spreadRange = 30, spreadRatio = 0.50, desc = "破甲效果扩散到周围（50%效力）" },
                [2] = { spreadRange = 40, spreadRatio = 0.80, desc = "破甲效果扩散到周围（80%效力）" },
            },
        },
    },

    frost_witch = {
        {
            id = "frost", name = "寒霜", type = "on_hit",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            effects = {
                [1] = { slowRate = 0.25, duration = 1.5, desc = "攻击减速目标25%，持续1.5秒" },
                [2] = { slowRate = 0.35, duration = 2.0, desc = "攻击减速目标35%，持续2秒" },
                [3] = { slowRate = 0.45, duration = 2.5, aoe = true, desc = "攻击减速目标及周围45%，持续2.5秒" },
            },
        },
        {
            id = "brittle", name = "霜冻脆弱", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "frost" },
            effects = {
                [1] = { defReduce = 0.10, duration = 3.0, desc = "被减速的敌人额外降低10%物防，持续3秒" },
                [2] = { defReduce = 0.20, resReduce = 0.10, duration = 4.0, desc = "被减速的敌人降低20%物防和10%魔抗，持续4秒" },
            },
        },
        {
            id = "frozen", name = "冰封", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            requires = { "frost" },
            effects = {
                [1] = { freezeChance = 0.08, freezeDuration = 1.0, bonusDmg = 0.30, desc = "攻击8%概率冰封1秒（受伤+30%）" },
                [2] = { freezeChance = 0.15, freezeDuration = 1.5, bonusDmg = 0.50, desc = "攻击15%概率冰封1.5秒（受伤+50%）" },
            },
        },
        {
            id = "blizzard", name = "暴风雪", type = "active",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            effects = {
                [1] = { interval = 25, slowPct = 0.40, duration = 3.0, desc = "每25秒全屏减速40%持续3秒" },
                [2] = { interval = 20, slowPct = 0.50, duration = 3.0, desc = "每20秒全屏减速50%持续3秒" },
            },
        },
    },

    war_drummer = {
        {
            id = "war_song", name = "战歌", type = "aura",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { atkBuff = 0.15, auraRange = 80, desc = "光环攻击加成15%" },
                [2] = { atkBuff = 0.25, auraRange = 100, desc = "光环攻击加成25%" },
            },
        },
        {
            id = "rhythm", name = "激励", type = "aura",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { spdBuff = 0.10, desc = "光环攻速+10%" },
                [2] = { spdBuff = 0.15, desc = "光环攻速+15%" },
            },
        },
        {
            id = "hero_song", name = "英雄之歌", type = "aura",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            effects = {
                [1] = { critRateBuff = 0.10, auraRange = 80, desc = "光环暴击率+10%" },
                [2] = { critRateBuff = 0.20, auraRange = 100, desc = "光环暴击率+20%" },
            },
        },
        {
            id = "war_cry", name = "战争怒号", type = "active",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            effects = {
                [1] = { interval = 30, atkBuffPct = 0.40, duration = 5.0, desc = "每30秒全体攻击+40%持续5秒" },
                [2] = { interval = 25, atkBuffPct = 0.50, duration = 8.0, desc = "每25秒全体攻击+50%持续8秒" },
            },
        },
    },

    -- ================================================================
    -- SSR 级：2 基础标签 + 2 解锁标签
    -- ================================================================

    shadow_mage = {
        {
            id = "shadow_chain", name = "暗影链", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.35, ignoreShield = true, desc = "攻击35%概率无视护盾" },
                [2] = { chance = 0.45, ignoreShield = true, desc = "攻击45%概率无视护盾" },
            },
        },
        {
            id = "shadow_mark", name = "暗蚀", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { maxStacks = 3, dmgPerStack = 0.10, desc = "命中叠暗影印记，每层+10%受伤，最多3层" },
                [2] = { maxStacks = 5, dmgPerStack = 0.10, desc = "命中叠暗影印记，每层+10%受伤，最多5层" },
            },
        },
        {
            id = "shadow_burst", name = "暗影爆发", type = "conditional",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "shadow_mark" },
            effects = {
                [1] = { atMaxStacks = true, trueDmgPct = 1.50, desc = "印记满层引爆造成150%ATK真实伤害" },
                [2] = { atMaxStacks = true, trueDmgPct = 2.00, resShred = 10, desc = "印记满层引爆200%ATK真伤并降低区域10魔抗" },
            },
        },
        {
            id = "void_tear", name = "虚空撕裂", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            requires = { "shadow_burst" },
            effects = {
                [1] = { postBurstResShred = 15, duration = 4.0, desc = "爆发后区域魔抗降低15，持续4秒" },
                [2] = { postBurstResShred = 25, duration = 5.0, desc = "爆发后区域魔抗降低25，持续5秒" },
            },
        },
    },

    abyss_hunter = {
        {
            id = "abyss_shot", name = "深渊射击", type = "passive",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { bossExtraDmg = 0.50, desc = "对首领额外伤害+50%" },
                [2] = { bossExtraDmg = 0.65, desc = "对首领额外伤害+65%" },
            },
        },
        {
            id = "focus_fire", name = "弱点锁定", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { dmgIncPerHit = 0.03, maxStacks = 10, desc = "连续攻击同目标每次+3%伤害，最多10层" },
                [2] = { dmgIncPerHit = 0.05, maxStacks = 10, desc = "连续攻击同目标每次+5%伤害，最多10层" },
            },
        },
        {
            id = "penetrate", name = "贯穿", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            effects = {
                [1] = { pierce = true, pierceDmgPct = 0.60, desc = "攻击穿透第一目标命中后方（60%伤害）" },
                [2] = { pierce = true, pierceDmgPct = 0.80, desc = "攻击穿透第一目标命中后方（80%伤害）" },
            },
        },
        {
            id = "hunt_decree", name = "猎杀宣告", type = "active",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            effects = {
                [1] = { interval = 15, vulnRate = 0.20, duration = 8.0, desc = "标记目标受所有伤害+20%，持续8秒" },
                [2] = { interval = 12, vulnRate = 0.30, duration = 10.0, desc = "标记目标受所有伤害+30%，持续10秒" },
            },
        },
    },

    plague_doctor = {
        {
            id = "plague", name = "瘟疫", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { dotAtkPct = 0.10, dotDuration = 3.0, desc = "附带每秒ATK×10%法术DOT，持续3秒" },
                [2] = { dotAtkPct = 0.15, dotDuration = 4.0, desc = "附带每秒ATK×15%法术DOT，持续4秒" },
            },
        },
        {
            id = "infection", name = "感染扩散", type = "on_kill",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { spreadRange = 30, spreadTargets = 2, spreadRatio = 0.70, desc = "DOT目标死亡时将70%DOT传播给周围2个敌人" },
                [2] = { spreadRange = 40, spreadTargets = 2, spreadRatio = 0.90, desc = "DOT目标死亡时将90%DOT传播给周围2个敌人" },
            },
        },
        {
            id = "festering", name = "溃烂", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "plague" },
            effects = {
                [1] = { magicVuln = 0.15, duration = 3.0, desc = "DOT期间目标受法伤+15%" },
                [2] = { magicVuln = 0.20, duration = 4.0, desc = "DOT期间目标受法伤+20%" },
            },
        },
        {
            id = "miasma_zone", name = "毒雾领域", type = "aura",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            effects = {
                [1] = { auraDotPct = 0.05, auraRange = 80, desc = "周围敌人持续受ATK×5%法术伤害" },
                [2] = { auraDotPct = 0.08, auraRange = 100, desc = "周围敌人持续受ATK×8%法术伤害" },
            },
        },
    },

    storm_lord = {
        {
            id = "thunder", name = "雷击", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { stunChance = 0.25, stunDuration = 0.8, desc = "攻击25%概率眩晕0.8秒" },
                [2] = { stunChance = 0.40, stunDuration = 1.0, desc = "攻击40%概率眩晕1秒" },
            },
        },
        {
            id = "charge", name = "感电", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { maxStacks = 3, dmgPerStack = 0.08, desc = "命中叠感电层，每层受伤+8%，最多3层" },
                [2] = { maxStacks = 5, dmgPerStack = 0.08, desc = "命中叠感电层，每层受伤+8%，最多5层" },
            },
        },
        {
            id = "lightning_storm", name = "雷暴", type = "conditional",
            tier = 0, maxTier = 2,
            unlock = { advance = 6 },
            requires = { "charge" },
            effects = {
                [1] = { atMaxStacks = true, burstDmgPct = 2.0, aoeRange = 50, desc = "满层引爆全伤200%ATK范围伤害" },
                [2] = { atMaxStacks = true, burstDmgPct = 3.0, aoeRange = 60, desc = "满层引爆300%ATK范围伤害" },
            },
        },
        {
            id = "overload", name = "超载", type = "conditional",
            tier = 0, maxTier = 2,
            unlock = { star = 15 },
            requires = { "lightning_storm" },
            effects = {
                [1] = { postBurstSlowImmuneLift = true, duration = 3.0, desc = "雷暴后区域内敌人减速免疫失效3秒" },
                [2] = { postBurstSlowImmuneLift = true, duration = 5.0, resShred = 10, desc = "雷暴后减速免疫失效5秒且魔抗-10" },
            },
        },
    },

    -- ================================================================
    -- UR 级：3 基础标签 + 1 解锁标签
    -- ================================================================

    glacial_sovereign = {
        {
            id = "arctic_chill", name = "极寒", type = "aura",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            effects = {
                [1] = { chillPerSec = 1, slowPerStack = 0.10, maxStacks = 5, duration = 5.0, desc = "每秒施加1层寒意，每层减速10%，最多5层" },
                [2] = { chillPerSec = 1, slowPerStack = 0.15, maxStacks = 5, duration = 5.0, desc = "每秒施加1层寒意，每层减速15%，最多5层" },
                [3] = { chillPerSec = 1, slowPerStack = 0.20, maxStacks = 5, duration = 5.0, desc = "每秒施加1层寒意，每层减速20%，最多5层" },
            },
        },
        {
            id = "ice_coffin", name = "冰晶棺", type = "conditional",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { atMaxChill = true, dmgAmp = 0.50, desc = "满5层寒意受伤+50%" },
                [2] = { atMaxChill = true, dmgAmp = 0.95, desc = "满5层寒意受伤+95%" },
            },
        },
        {
            id = "absolute_zero", name = "绝对零度", type = "conditional",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { globalChillThreshold = 80, applyAll = 3, desc = "累积80层全局寒意时，全屏施加3层" },
                [2] = { globalChillThreshold = 50, applyAll = 5, desc = "累积50层全局寒意时，全屏施加5层" },
            },
        },
        {
            id = "winter_domain", name = "寒冬领域", type = "aura",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { globalSlowAura = 0.10, desc = "全场敌人移速降低10%" },
                [2] = { globalSlowAura = 0.20, desc = "全场敌人移速降低20%" },
            },
        },
    },

    fallen_archangel = {
        {
            id = "holy_slash", name = "圣光斩", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { ampRate = 0.40, ampDuration = 4.0, desc = "标记增伤40%，持续4秒" },
                [2] = { ampRate = 0.65, ampDuration = 5.0, desc = "标记增伤65%，持续5秒" },
            },
        },
        {
            id = "judgment", name = "审判", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { stunChance = 0.10, stunDuration = 1.0, desc = "攻击10%概率眩晕1秒" },
                [2] = { stunChance = 0.15, stunDuration = 1.5, desc = "攻击15%概率眩晕1.5秒" },
            },
        },
        {
            id = "divine_wrath", name = "天罚", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { lowHpThreshold = 0.30, trueDmgPct = 1.0, desc = "对血量低于30%的目标追加100%ATK真实伤害" },
                [2] = { lowHpThreshold = 0.40, trueDmgPct = 1.5, desc = "对血量低于40%的目标追加150%ATK真实伤害" },
            },
        },
        {
            id = "fallen_glory", name = "堕落光辉", type = "on_kill",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { guaranteedCrit = true, critDmgBonus = 0.50, desc = "击杀后下一击必暴，暴伤+50%" },
                [2] = { guaranteedCrit = true, critDmgBonus = 1.00, desc = "击杀后下一击必暴，暴伤+100%" },
            },
        },
    },

    void_dragon = {
        {
            id = "void_breath", name = "虚空吐息", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { dotAtkPct = 0.30, dotDuration = 3.0, desc = "链式攻击附带每秒ATK×30%法伤DOT，3秒" },
                [2] = { dotAtkPct = 0.45, dotDuration = 3.0, desc = "链式攻击附带每秒ATK×45%法伤DOT，3秒" },
            },
        },
        {
            id = "spatial_warp", name = "空间畸变", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { slowRate = 0.20, resReduce = 10, duration = 3.0, desc = "命中减速20%并降低10魔抗，3秒" },
                [2] = { slowRate = 0.30, resReduce = 15, duration = 4.0, desc = "命中减速30%并降低15魔抗，4秒" },
            },
        },
        {
            id = "dimension_collapse", name = "维度崩塌", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { pullChance = 0.15, pullDistance = 30, desc = "15%概率将目标拉回30像素" },
                [2] = { pullChance = 0.25, pullDistance = 50, desc = "25%概率将目标拉回50像素" },
            },
        },
        {
            id = "annihilate", name = "湮灭", type = "on_hit",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { executeThreshold = 0.05, desc = "血量低于5%的目标即死（Boss无效）" },
                [2] = { executeThreshold = 0.10, bossCap = 0.03, desc = "血量低于10%即死；Boss低于3%时生效" },
            },
        },
    },

    nature_elf = {
        {
            id = "nature_aura", name = "自然光环", type = "aura",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            starScale = true,
            effects = {
                [1] = { atkBuff = 0.30, spdBuff = 0.15, auraRange = 120, desc = "光环攻击+30%，攻速+15%" },
                [2] = { atkBuff = 0.60, spdBuff = 0.30, auraRange = 140, desc = "光环攻击+60%，攻速+30%" },
                [3] = { atkBuff = 1.15, spdBuff = 0.75, atkRatio = 0.19, auraRange = 140, desc = "光环攻击+115%，攻速+75%，固定攻击+翎嫣ATK×19%" },
            },
        },
        {
            id = "life_spring", name = "生命源泉", type = "on_kill",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { extraDropChance = 0.10, desc = "击杀10%概率额外掉落" },
                [2] = { extraDropChance = 0.20, desc = "击杀20%概率额外掉落" },
            },
        },
        {
            id = "wilds_call", name = "自然怒吼", type = "active",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            starScale = true,
            effects = {
                [1] = { interval = 25, force = 30, wreathAtkBonus = 0.40, wreathDuration = 8.0, desc = "每25秒为全体提供30点自然之力和鲜花环（+40%ATK，8秒）" },
                [2] = { interval = 20, force = 55, wreathAtkBonus = 0.75, wreathDuration = 10.0, desc = "每20秒为全体提供55点自然之力和鲜花环（+75%ATK，10秒）" },
            },
        },
        {
            id = "wither", name = "万物凋零", type = "aura",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { defReduce = 0.10, auraRange = 120, desc = "光环降低周围敌人10%DEF" },
                [2] = { defReduce = 0.15, auraRange = 140, desc = "光环降低周围敌人15%DEF" },
            },
        },
    },

    crimson_night = {
        {
            id = "blood_blade", name = "血刃", type = "on_hit",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            starScale = true,
            effects = {
                [1] = { maxStacks = 3, stackDuration = 4.0, burstAtkPct = 1.50, desc = "叠加暗影印记，满3层引爆ATK×150%" },
                [2] = { maxStacks = 4, stackDuration = 4.0, burstAtkPct = 2.50, armorIgnore = 0.20, desc = "满4层引爆ATK×250%，无视20%护甲" },
                [3] = { maxStacks = 5, stackDuration = 4.0, burstAtkPct = 3.80, armorIgnore = 0.38, desc = "满5层引爆ATK×380%，无视38%护甲" },
            },
        },
        {
            id = "blood_eye", name = "绯瞳锁定", type = "on_hit",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            starScale = true,
            effects = {
                [1] = { critRatePerHit = 0.04, maxCritStacks = 5, critDmgBonus = 0.50, desc = "每层+4%暴击（最多5层），暴伤+50%" },
                [2] = { critRatePerHit = 0.05, maxCritStacks = 8, critDmgBonus = 0.70, desc = "每层+5%暴击（最多8层），暴伤+70%" },
                [3] = { critRatePerHit = 0.06, maxCritStacks = 10, critDmgBonus = 0.95, desc = "每层+6%暴击（最多10层），暴伤+95%" },
            },
        },
        {
            id = "blood_pact", name = "血契", type = "passive",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { atkPerMark = 0.03, desc = "每层暗影印记+3%攻击力" },
                [2] = { atkPerMark = 0.05, desc = "每层暗影印记+5%攻击力" },
            },
        },
        {
            id = "crimson_eclipse", name = "绯红月蚀", type = "active",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            starScale = true,
            effects = {
                [1] = { interval = 18, detonateAll = true, teamSpdBuff = 0.30, buffDuration = 5.0, desc = "全场引爆暗影印记+全队攻速+30%持续5秒" },
                [2] = { interval = 14, detonateAll = true, teamSpdBuff = 0.50, buffDuration = 8.0, desc = "全场引爆暗影印记+全队攻速+50%持续8秒" },
            },
        },
    },

    ember_wraith = {
        {
            id = "ember_ignite", name = "余烬点燃", type = "on_hit",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            starScale = true,
            effects = {
                [1] = { maxStacks = 2, dotPctPerStack = 0.10, desc = "叠加灼烧（最多2层），每层每秒ATK×10%" },
                [2] = { maxStacks = 3, dotPctPerStack = 0.12, desc = "叠加灼烧（最多3层），每层每秒ATK×12%" },
                [3] = { maxStacks = 3, dotPctPerStack = 0.15, deathAoePct = 1.50, deathRadius = 60, desc = "叠加灼烧（最多3层），每层每秒ATK×15%；死亡蔓延ATK×150%" },
            },
        },
        {
            id = "ember_resonance", name = "烬核共振", type = "passive",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            starScale = true,
            effects = {
                [1] = { atkPerBurn = 0.03, dotAmpPerBurn = 0.04, maxBurns = 8, desc = "每个灼烧敌人+3%ATK和+4%DOT加成，最多8层" },
                [2] = { atkPerBurn = 0.04, dotAmpPerBurn = 0.06, maxBurns = 12, desc = "每个灼烧敌人+4%ATK和+6%DOT加成，最多12层" },
            },
        },
        {
            id = "burn_out", name = "灰飞烟灭", type = "on_kill",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { deathExplosionPct = 1.00, explosionRange = 50, desc = "灼烧致死时爆炸ATK×100%法伤" },
                [2] = { deathExplosionPct = 1.50, explosionRange = 60, reIgnite = 1, desc = "灼烧致死爆炸ATK×150%法伤并重新点燃1层" },
            },
        },
        {
            id = "flame_echo", name = "烈焰回响", type = "conditional",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            requires = { "burn_out" },
            effects = {
                [1] = { chainReaction = true, maxChain = 2, desc = "爆炸再次点燃的目标死亡时可再次爆炸（最多连锁2次）" },
                [2] = { chainReaction = true, maxChain = 3, chainDmgAmp = 0.20, desc = "连锁爆炸最多3次，每次伤害+20%" },
            },
        },
    },

    -- ================================================================
    -- LR 级：3 基础标签 + 1 解锁标签
    -- ================================================================

    fate_weaver = {
        {
            id = "fate_thread", name = "命运丝线", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { linkDmgShare = 0.20, maxLinks = 3, desc = "链接最多3个目标，分享20%受到的伤害" },
                [2] = { linkDmgShare = 0.30, maxLinks = 5, desc = "链接最多5个目标，分享30%受到的伤害" },
            },
        },
        {
            id = "causality", name = "因果律", type = "aura",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { doubleDmgChance = 0.50, desc = "全体友方50%概率双倍伤害" },
                [2] = { doubleDmgChance = 0.70, desc = "全体友方70%概率双倍伤害" },
            },
        },
        {
            id = "fate_entangle", name = "命运纠缠", type = "on_hit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { linkedSlow = 0.20, desc = "链接目标移速降低20%" },
                [2] = { linkedSlow = 0.30, linkedResShred = 10, desc = "链接目标移速降低30%且魔抗-10" },
            },
        },
        {
            id = "final_weave", name = "终焉编织", type = "active",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { interval = 25, trueDmgToLinked = 2.0, desc = "每25秒对所有链接目标造成200%ATK真实伤害" },
                [2] = { interval = 20, trueDmgToLinked = 3.0, resetCd = true, desc = "每20秒300%ATK真伤并重置全体友方CD" },
            },
        },
    },

    eternal_archfiend = {
        {
            id = "infernal_stack", name = "魔焰之力", type = "on_hit",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            effects = {
                [1] = { maxStacks = 5,  critPerStack = 0.05, critDmgPerStack = 0.20, stackDuration = 5.0, desc = "每层+5%暴击+20%暴伤，最多5层" },
                [2] = { maxStacks = 8,  critPerStack = 0.06, critDmgPerStack = 0.25, stackDuration = 5.0, desc = "每层+6%暴击+25%暴伤，最多8层" },
                [3] = { maxStacks = 10, critPerStack = 0.08, critDmgPerStack = 0.35, stackDuration = 5.0, desc = "每层+8%暴击+35%暴伤，最多10层" },
            },
        },
        {
            id = "erosion", name = "永恒侵蚀", type = "on_crit",
            tier = 1, maxTier = 3,
            unlock = { star = 0 },
            requires = { "infernal_stack" },
            effects = {
                [1] = { maxStacks = 4, dmgBonusPerStack = 0.05, stackDuration = 6.0, desc = "暴击+1层侵蚀，每层+5%伤害，最多4层" },
                [2] = { maxStacks = 6, dmgBonusPerStack = 0.05, pureConvertAtMax = 0.20, stackDuration = 6.0, desc = "每层+5%伤害，满6层20%伤害转真伤" },
                [3] = { maxStacks = 6, dmgBonusPerStack = 0.06, pureConvertAtMax = 0.35, stackDuration = 6.0, desc = "每层+6%伤害，满6层35%伤害转真伤" },
            },
        },
        {
            id = "armageddon", name = "灭世余烬", type = "on_crit",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.30, aoeDmgScale = 1.5, aoeRange = 50, desc = "暴击30%概率范围150%ATK伤害" },
                [2] = { chance = 0.40, aoeDmgScale = 2.0, aoeRange = 60, ignoreRes = true, desc = "暴击40%概率范围200%ATK伤害（无视魔抗）" },
            },
        },
        {
            id = "abyss_mark", name = "深渊印记", type = "active",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { interval = 20, vulnRate = 0.30, duration = 10.0, desc = "标记血量最高敌人，受伤+30%，10秒" },
                [2] = { interval = 15, vulnRate = 0.50, duration = 12.0, spreadOnKill = true, desc = "受伤+50%，12秒，死亡时传播" },
            },
        },
    },

    -- ================================================================
    -- 特殊
    -- ================================================================

    leader = {
        {
            id = "shadow_dominion", name = "暗影支配", type = "aura",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { globalAtkBuff = 0.15, desc = "全体友方塔攻击+15%" },
                [2] = { globalAtkBuff = 0.20, desc = "全体友方塔攻击+20%" },
            },
        },
        {
            id = "lord_will", name = "君主意志", type = "on_kill",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { chance = 0.15, cdResetAmount = 1.0, desc = "击杀15%概率缩短主动技能1秒CD" },
                [2] = { chance = 0.20, cdResetAmount = 1.0, desc = "击杀20%概率缩短主动技能1秒CD" },
            },
        },
        {
            id = "shadow_devour", name = "暗影吞噬", type = "active",
            tier = 1, maxTier = 2,
            unlock = { star = 0 },
            effects = {
                [1] = { interval = 12, damagePct = 0.80, desc = "每12秒全屏80%ATK伤害" },
                [2] = { interval = 10, damagePct = 1.05, desc = "每10秒全屏105%ATK伤害" },
            },
        },
        {
            id = "absolute_rule", name = "绝对统治", type = "aura",
            tier = 0, maxTier = 2,
            unlock = { advance = 11 },
            effects = {
                [1] = { globalCritBuff = 0.10, desc = "全体友方暴击率+10%" },
                [2] = { globalCritBuff = 0.15, desc = "全体友方暴击率+15%" },
            },
        },
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
    { id = "mount",  name = "战马", emoji = "🐴", stat = "typeDmg",  statName = "类型伤害",   fmt = "pct" },
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
    typeDmg  = 0.002,  -- 每级+0.2%类型伤害（物理/法术）
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
-- 平衡目标：每条红档满值总 DPS 贡献 ≈ 8-12%
-- 计算依据：红档上限 = maxValue, DPS贡献 = maxValue × 每1%DPS贡献率
Config.TEMPER_ATTRIBUTES = {
    { id = "atk",           name = "攻击力",     maxValue = 0.15,  fmt = "pct" },  -- 15%×0.71=10.7% DPS
    { id = "spd",           name = "攻速",       maxValue = 0.15,  fmt = "pct" },  -- 15%×0.6 = 9.0% DPS
    { id = "critRate",      name = "暴击率",     maxValue = 0.15,  fmt = "pct" },  -- 15%×0.69=10.4% DPS
    { id = "critDmg",       name = "暴击伤害",   maxValue = 0.35,  fmt = "pct" },  -- 35%×0.30=10.5% DPS
    { id = "armorPen",      name = "破甲",       maxValue = 0.08,  fmt = "pct" },  -- 8% ×1.3 =10.4% DPS
    { id = "dmgBonus",      name = "伤害加成",   maxValue = 0.14,  fmt = "pct" },  -- 14%×0.76=10.6% DPS
    { id = "skillDmg",      name = "技能伤害",   maxValue = 0.18,  fmt = "pct" },  -- 技能专属, ~dmgBonus同区
    { id = "ctrlHit",       name = "控制命中",   maxValue = 0.20,  fmt = "pct" },  -- 功能性词条, 不直接增伤
    { id = "physDmg",       name = "物理伤害",   maxValue = 0.14,  fmt = "pct" },  -- 14%×0.78=10.9% DPS(类型限制)
    { id = "magicDmg",      name = "法术伤害",   maxValue = 0.14,  fmt = "pct" },  -- 14%×0.78=10.9% DPS(类型限制)
    { id = "magicPen",      name = "法术穿透",   maxValue = 0.06,  fmt = "pct" },  -- 6% ×1.7 =10.2% DPS(类型限制)
    { id = "dotDmg",        name = "持续伤害",   maxValue = 0.18,  fmt = "pct" },  -- DOT专属, 同skillDmg
    { id = "bossDmg",       name = "对首领伤害", maxValue = 0.18,  fmt = "pct" },  -- Boss专属, 同skillDmg
}

-- 三层词条注入（T1/T2，T3 专属符文）
if Config.AFFIX_TAG_TEMPER_ENTRIES and Config.AFFIX_TAG_LOOKUP then
    for _, entry in ipairs(Config.AFFIX_TAG_TEMPER_ENTRIES) do
        local def = Config.AFFIX_TAG_LOOKUP[entry.id]
        if def then
            Config.TEMPER_ATTRIBUTES[#Config.TEMPER_ATTRIBUTES + 1] = {
                id            = def.id,
                name          = def.name,
                maxValue      = entry.maxValue,
                fmt           = "pct",
                -- 额外字段：标记为三层词条
                affixTier     = entry.affixTier,
                isTagAffix    = true,
                minTemperTier = entry.minTemperTier,  -- "orange" / "red"
            }
        end
    end
end

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
