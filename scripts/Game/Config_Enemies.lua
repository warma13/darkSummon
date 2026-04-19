-- Game/Config_Enemies.lua
-- 怪物系统：角色、主题、构建函数、词缀、关卡参数

local function apply(Config)

-- ============================================================================
-- 怪物系统：10 角色 × 5 主题（数据驱动）
-- ============================================================================

-- 10 种角色定位（行为由角色决定，外观由主题决定）
Config.ENEMY_ROLES = {
    minion   = { baseHP = 4500,   baseDEF = 500,   speed = 85, reward = 2,  size = 9,  shape = "diamond",   unlockOrder = 1 },
    infantry = { baseHP = 12000,   baseDEF = 800,  speed = 50, reward = 4,  size = 12, shape = "circle",    unlockOrder = 1 },
    tank     = { baseHP = 45000,   baseDEF = 2000,  speed = 22, reward = 10, size = 16, shape = "square",    unlockOrder = 3 },
    assassin = { baseHP = 4800,   baseDEF = 300,   speed = 92, reward = 6,  size = 10, shape = "diamond",   unlockOrder = 3 },
    dodger   = { baseHP = 7500,   baseDEF = 600,   speed = 55, reward = 7,  size = 11, shape = "circle",    unlockOrder = 5,    passive = "dodge", dodgeChance = 0.30 },
    support  = { baseHP = 10500,   baseDEF = 1000,  speed = 40, reward = 8,  size = 13, shape = "diamond",   unlockOrder = 7 },
    splitter = { baseHP = 16500,   baseDEF = 900,  speed = 52, reward = 7,  size = 14, shape = "triangle",  unlockOrder = 9,    passive = "split", splitCount = 2, splitRole = "minion" },
    blinker  = { baseHP = 9750,   baseDEF = 700,   speed = 40, reward = 8,  size = 12, shape = "circle",    unlockOrder = 11,   passive = "blink", blinkInterval = 4.0, blinkProgress = 0.08 },
    special  = { baseHP = 22500,   baseDEF = 1500,  speed = 45, reward = 9,  size = 14, shape = "square",    unlockOrder = 13 },
}

-- 角色解锁波次（风格内相对波次，基于 unlockOrder）
Config.ROLE_UNLOCK_WAVE = {
    [1]  = 1,   -- minion, infantry
    [3]  = 11,  -- tank, assassin
    [5]  = 21,  -- dodger
    [7]  = 31,  -- support
    [9]  = 41,  -- splitter
    [11] = 51,  -- blinker
    [13] = 61,  -- special
}

-- 5 个主题风格定义
Config.THEMES = {
    -- ========== 1. 亡灵墓地 ==========
    {
        id = "undead",
        name = "亡灵墓地",
        palette = { primary = { 80, 160, 80 }, secondary = { 180, 170, 150 }, glow = { 60, 140, 60 } },
        monsters = {
            minion   = { name = "腐鼠",     color = { 130, 150, 100 }, icon = "image/mobs/undead_minion.png" },
            infantry = { name = "骷髅兵",   color = { 180, 170, 150 }, icon = "image/mobs/undead_infantry.png" },
            tank     = { name = "白骨巨人", color = { 160, 155, 140 }, icon = "image/mobs/undead_tank.png" },
            assassin = { name = "亡灵蝙蝠", color = { 140, 110, 160 }, icon = "image/mobs/undead_assassin.png" },
            dodger   = { name = "怨灵",     color = { 140, 180, 160 }, icon = "image/mobs/undead_dodger.png" },
            support  = { name = "亡灵侍僧", color = { 100, 140, 80 },  icon = "image/mobs/undead_support.png",
                         aura = { type = "speed", value = 0.20, range = 60 } },
            splitter = { name = "尸蛛",     color = { 100, 130, 90 },  icon = "image/mobs/undead_splitter.png" },
            blinker  = { name = "游魂",     color = { 160, 180, 190 }, icon = "image/mobs/undead_blinker.png" },
            special  = { name = "墓穴骑士", color = { 90, 120, 80 },   icon = "image/mobs/undead_special.png",
                         specialPassive = "regen_lost", regenLostPct = 0.05, regenInterval = 3.0 },
        },
        boss = {
            id = "bone_dragon", name = "亡灵首领",
            color = { 200, 180, 140 }, baseHP = 120000, baseDEF = 3000, speed = 25, size = 22,
            icon = "image/mobs/undead_boss.png",
            passive = "disable", disableInterval = 8.0, disableDuration = 2.0,
        },
    },
    -- ========== 2. 熔岩地狱 ==========
    {
        id = "lava",
        name = "熔岩地狱",
        palette = { primary = { 220, 80, 30 }, secondary = { 180, 100, 60 }, glow = { 240, 120, 20 } },
        monsters = {
            minion   = { name = "小火魔",   color = { 220, 80, 50 },  icon = "image/mobs/lava_minion.png" },
            infantry = { name = "熔岩蛮兵", color = { 180, 100, 60 }, icon = "image/mobs/lava_infantry.png" },
            tank     = { name = "岩浆巨人", color = { 140, 80, 40 },  icon = "image/mobs/lava_tank.png",
                         tankPassive = "slow_resist", slowResist = 0.50 },
            assassin = { name = "火焰精灵", color = { 255, 160, 40 }, icon = "image/mobs/lava_assassin.png" },
            dodger   = { name = "灰烬幽魂", color = { 160, 130, 110 }, icon = "image/mobs/lava_dodger.png", dodgeOverride = 0.25 },
            support  = { name = "地狱萨满", color = { 200, 60, 30 },  icon = "image/mobs/lava_support.png",
                         aura = { type = "slow_resist", value = 0.30, range = 60 } },
            splitter = { name = "爆炎甲虫", color = { 200, 80, 40 },  icon = "image/mobs/lava_splitter.png" },
            blinker  = { name = "瞬焰",     color = { 255, 140, 30 }, icon = "image/mobs/lava_blinker.png" },
            special  = { name = "熔岩蠕虫", color = { 160, 60, 20 },  icon = "image/mobs/lava_special.png",
                         specialPassive = "scorch", scorchAtkSpdReduce = 0.10, scorchDuration = 3.0 },
        },
        boss = {
            id = "infernal_lord", name = "熔岩首领",
            color = { 240, 60, 30 }, baseHP = 150000, baseDEF = 2500, speed = 28, size = 20,
            icon = "image/mobs/lava_boss.png",
            passive = "summon", summonInterval = 6.0, summonCount = 2,
        },
    },
    -- ========== 3. 幽暗森林 ==========
    {
        id = "forest",
        name = "幽暗森林",
        palette = { primary = { 60, 140, 60 }, secondary = { 100, 80, 140 }, glow = { 80, 180, 80 } },
        monsters = {
            minion   = { name = "毒菇精",   color = { 140, 80, 160 }, icon = "image/mobs/forest_minion.png" },
            infantry = { name = "荆棘行者", color = { 100, 130, 70 }, icon = "image/mobs/forest_infantry.png" },
            tank     = { name = "远古树人", color = { 80, 110, 60 },  icon = "image/mobs/forest_tank.png",
                         tankPassive = "regen", regenRate = 0.005 },
            assassin = { name = "暗影狐",   color = { 120, 80, 140 }, icon = "image/mobs/forest_assassin.png" },
            dodger   = { name = "迷雾蛾",   color = { 140, 160, 180 }, icon = "image/mobs/forest_dodger.png", dodgeOverride = 0.35 },
            support  = { name = "腐化德鲁伊", color = { 80, 130, 60 }, icon = "image/mobs/forest_support.png",
                         aura = { type = "hp_boost", value = 0.15, range = 60 } },
            splitter = { name = "育母蛛",   color = { 80, 120, 60 },  icon = "image/mobs/forest_splitter.png" },
            blinker  = { name = "鬼火",     color = { 100, 200, 80 }, icon = "image/mobs/forest_blinker.png" },
            special  = { name = "剧毒藤蔓", color = { 100, 60, 140 }, icon = "image/mobs/forest_special.png",
                         specialPassive = "poison_trail", trailDuration = 3.0, trailAtkReduce = 0.20 },
        },
        boss = {
            id = "forest_hydra", name = "森林首领",
            color = { 60, 140, 80 }, baseHP = 375000, baseDEF = 5000, speed = 18, size = 26,
            icon = "image/mobs/forest_boss.png",
            passive = "immune_cc",
        },
    },
    -- ========== 4. 冰霜冻土 ==========
    {
        id = "frost",
        name = "冰霜冻土",
        palette = { primary = { 100, 180, 255 }, secondary = { 200, 220, 240 }, glow = { 80, 160, 240 } },
        monsters = {
            minion   = { name = "冰晶虱",   color = { 140, 200, 240 }, icon = "image/mobs/frost_minion.png" },
            infantry = { name = "冰封战士", color = { 120, 160, 200 }, icon = "image/mobs/frost_infantry.png" },
            tank     = { name = "冰川魔像", color = { 100, 140, 200 }, icon = "image/mobs/frost_tank.png",
                         tankPassive = "ice_shield", shieldPct = 0.30 },
            assassin = { name = "雪原疾兔", color = { 220, 230, 245 }, icon = "image/mobs/frost_assassin.png" },
            dodger   = { name = "冰魄",     color = { 140, 190, 230 }, icon = "image/mobs/frost_dodger.png" },
            support  = { name = "霜歌者",   color = { 100, 160, 220 }, icon = "image/mobs/frost_support.png",
                         aura = { type = "dodge_boost", value = 0.10, range = 60 } },
            splitter = { name = "冰甲虫",   color = { 120, 170, 220 }, icon = "image/mobs/frost_splitter.png" },
            blinker  = { name = "暴风雪精灵", color = { 160, 200, 240 }, icon = "image/mobs/frost_blinker.png" },
            special  = { name = "永冻蛟",   color = { 80, 140, 200 },  icon = "image/mobs/frost_special.png",
                         specialPassive = "first_hit_armor", firstHitReduce = 0.50 },
        },
        boss = {
            id = "blizzard_king", name = "冰霜首领",
            color = { 100, 180, 255 }, baseHP = 105000, baseDEF = 2000, speed = 40, size = 18,
            icon = "image/mobs/frost_boss.png",
            passive = "phase", phaseInterval = 5.0, phaseDuration = 2.5,
        },
    },
    -- ========== 5. 虚空深渊 ==========
    {
        id = "void",
        name = "虚空深渊",
        palette = { primary = { 140, 60, 200 }, secondary = { 80, 40, 120 }, glow = { 160, 80, 255 } },
        monsters = {
            minion   = { name = "虚空虱",   color = { 120, 60, 160 }, icon = "image/mobs/void_minion.png" },
            infantry = { name = "虚空战兵", color = { 100, 60, 140 }, icon = "image/mobs/void_infantry.png" },
            tank     = { name = "深渊泰坦", color = { 80, 50, 110 },  icon = "image/mobs/void_tank.png",
                         tankPassive = "dot_immune" },
            assassin = { name = "相位潜行者", color = { 140, 80, 180 }, icon = "image/mobs/void_assassin.png" },
            dodger   = { name = "扭曲暗影", color = { 110, 70, 150 }, icon = "image/mobs/void_dodger.png", dodgeOverride = 0.35 },
            support  = { name = "虚空先驱", color = { 130, 60, 180 }, icon = "image/mobs/void_support.png",
                         aura = { type = "slow_immune", range = 60 } },
            splitter = { name = "裂隙爬行者", color = { 100, 50, 140 }, icon = "image/mobs/void_splitter.png" },
            blinker  = { name = "闪现恐魔", color = { 120, 40, 160 }, icon = "image/mobs/void_blinker.png",
                         blinkOverride = { interval = 3.0, progress = 0.10 } },
            special  = { name = "熵能织者", color = { 140, 80, 200 }, icon = "image/mobs/void_special.png",
                         specialPassive = "death_silence", silenceDuration = 2.0, silenceRange = 80 },
        },
        boss = {
            id = "void_emperor", name = "虚空首领",
            color = { 140, 60, 200 }, baseHP = 225000, baseDEF = 4000, speed = 30, size = 24,
            icon = "image/mobs/void_boss.png",
            passive = "enrage", enrageThreshold = 0.5, enrageSpeedMult = 2.0,
            enrageImmuneCC = true,  -- 狂暴后额外免控,
        },
    },
}

Config.STAGES_PER_THEME = 5   -- 每5关一个风格
Config.THEME_COUNT = #Config.THEMES

-- 角色 ID 列表（用于遍历，不含 boss）
Config.ROLE_IDS = { "minion", "infantry", "tank", "assassin", "dodger", "support", "splitter", "blinker", "special" }

--- 获取指定关卡的主题
function Config.GetTheme(stageNum)
    local idx = ((stageNum - 1) % Config.THEME_COUNT) + 1
    return Config.THEMES[idx]
end

--- 获取主题轮次（用于数值加成）
function Config.GetThemeRound(stageNum)
    return math.floor((stageNum - 1) / (Config.STAGES_PER_THEME * Config.THEME_COUNT)) + 1
end

--- 构建指定关卡+角色的完整怪物定义（运行时组合）
function Config.BuildEnemyDef(stageNum, roleId)
    local theme = Config.GetTheme(stageNum)
    local role = Config.ENEMY_ROLES[roleId]
    local skin = theme.monsters[roleId]
    if not role or not skin then return nil end

    local round = Config.GetThemeRound(stageNum)
    local roundHPMult = 1.0 + (round - 1) * 0.5
    local roundSpdMult = math.min(1.0 + (round - 1) * 0.1, 2.0)

    local def = {
        id = theme.id .. "_" .. roleId,
        name = skin.name,
        color = skin.color,
        icon = skin.icon,
        baseHP = role.baseHP * roundHPMult,
        speed = role.speed * roundSpdMult,
        reward = role.reward,
        liveCost = 1,
        size = role.size,
        shape = role.shape,
        baseDEF = role.baseDEF or 0,
        role = roleId,
        themeId = theme.id,
    }

    -- 继承角色被动
    if role.passive then
        def.passive = role.passive
        if role.passive == "dodge" then
            def.dodgeChance = skin.dodgeOverride or role.dodgeChance
        elseif role.passive == "split" then
            def.splitCount = role.splitCount
            def.splitRole = role.splitRole  -- 分裂出的角色（同主题小兵）
        elseif role.passive == "blink" then
            if skin.blinkOverride then
                def.blinkInterval = skin.blinkOverride.interval
                def.blinkProgress = skin.blinkOverride.progress
            else
                def.blinkInterval = role.blinkInterval
                def.blinkProgress = role.blinkProgress
            end
        end
    end

    -- 辅助光环
    if skin.aura then
        def.passive = "aura"
        def.aura = skin.aura
    end

    -- 坦克被动
    if skin.tankPassive then
        def.tankPassive = skin.tankPassive
        if skin.tankPassive == "slow_resist" then
            def.slowResist = skin.slowResist
        elseif skin.tankPassive == "regen" then
            def.regenRate = skin.regenRate
        elseif skin.tankPassive == "ice_shield" then
            def.shieldPct = skin.shieldPct
        elseif skin.tankPassive == "dot_immune" then
            def.dotImmune = true
        end
    end

    -- 特殊被动
    if skin.specialPassive then
        def.specialPassive = skin.specialPassive
        for k, v in pairs(skin) do
            if k ~= "name" and k ~= "color" and k ~= "specialPassive" then
                def[k] = v
            end
        end
    end

    return def
end

--- 构建指定关卡的 BOSS 定义
function Config.BuildBossDef(stageNum)
    local theme = Config.GetTheme(stageNum)
    local boss = theme.boss
    local round = Config.GetThemeRound(stageNum)
    local roundHPMult = 1.0 + (round - 1) * 0.5

    local def = {}
    for k, v in pairs(boss) do def[k] = v end
    def.baseHP = boss.baseHP * roundHPMult
    def.isBoss = true
    def.reward = 50
    def.liveCost = 3
    def.shape = "diamond"
    def.themeId = theme.id

    -- summon BOSS 的召唤物使用同主题小兵
    if boss.passive == "summon" then
        def.summonRole = "minion"
    end

    return def
end

-- 向后兼容：保留 ENEMY_TYPES 和 BOSS_TYPES（用亡灵主题填充默认值）
Config.ENEMY_TYPES = {}
Config.ENEMY_IDS = {}
for _, roleId in ipairs(Config.ROLE_IDS) do
    local def = Config.BuildEnemyDef(1, roleId)
    if def then
        Config.ENEMY_TYPES[def.id] = def
        Config.ENEMY_IDS[#Config.ENEMY_IDS + 1] = def.id
    end
end

Config.BOSS_TYPES = {}
for i = 1, Config.THEME_COUNT do
    Config.BOSS_TYPES[i] = Config.BuildBossDef(i)
end

-- ============================================================================
-- 精英词缀定义
-- ============================================================================
Config.AFFIXES = {
    { id = "tough",     name = "坚韧", tier = 1, color = { 200, 160, 80 },
      hpMult = 2.0 },
    { id = "swift",     name = "迅捷", tier = 1, color = { 80, 200, 255 },
      speedMult = 1.5 },
    { id = "regen",     name = "再生", tier = 1, color = { 80, 220, 80 },
      regenRate = 0.01 },
    { id = "berserk",   name = "狂暴", tier = 1, color = { 255, 100, 60 },
      enrageThreshold = 0.5, enrageSpeedMult = 1.8 },
    { id = "shielded",  name = "护盾", tier = 2, color = { 200, 200, 255 },
      shieldHP = 0.5 },
    { id = "stealth",   name = "隐身", tier = 2, color = { 120, 120, 160 },
      phaseInterval = 4.0, phaseDuration = 1.5 },
    { id = "vampiric",  name = "吸血", tier = 2, color = { 180, 40, 60 },
      vampRate = 0.03 },
    { id = "undying",   name = "不朽", tier = 3, color = { 255, 220, 60 },
      revive = true, reviveHPRate = 0.5 },
    { id = "void_aura", name = "虚空", tier = 3, color = { 160, 80, 255 },
      immuneCC = true },
}

Config.AFFIX_WAVE_T1 = 15
Config.AFFIX_WAVE_T2 = 35
Config.AFFIX_WAVE_T3 = 60

-- ============================================================================
-- 关卡 & 波次参数
-- ============================================================================
Config.WAVES_PER_STAGE = 20
Config.BOSS_WAVE = 20
Config.ELITE_INTERVAL = 5

-- 分段线性 HP 缩放表 —— 匹配 hero_power_mult(stage/2)
-- 每行: { fromStage, toStage, scaleFrom, scaleTo }
Config.HP_SCALE_SEGMENTS = {
    {     2,   100,       1.00,       6.88 },
    {   100,   200,       6.88,      14.17 },
    {   200,   500,      14.17,      41.10 },
    {   500,  1000,      41.10,      89.13 },
    {  1000,  1500,      89.13,     159.22 },
    {  1500,  2000,     159.22,     259.18 },
    {  2000,  3000,     259.18,     564.58 },
    {  3000,  4000,     564.58,    1002.38 },
    {  4000,  5000,    1002.38,    1516.16 },
    {  5000,  6000,    1516.16,    2201.24 },
}

--- 统一 HP 缩放函数（分段线性插值）
---@param stage number 关卡号（>=1）
---@return number 缩放倍率
function Config.GetStageHPScale(stage)
    if stage <= 1 then return 1.0 end
    local segs = Config.HP_SCALE_SEGMENTS
    for i = 1, #segs do
        local seg = segs[i]
        if stage <= seg[2] then
            local t = (stage - seg[1]) / (seg[2] - seg[1])
            return seg[3] + t * (seg[4] - seg[3])
        end
    end
    -- 超出最大分段：按最后一段斜率线性外推
    local last = segs[#segs]
    local slope = (last[4] - last[3]) / (last[2] - last[1])
    return last[4] + slope * (stage - last[2])
end

Config.STAGE_SPEED_PER_STAGE = 0.02
Config.STAGE_SPEED_CAP = 1.8

Config.WAVE_HP_PER_WAVE = 0.04
Config.WAVE_BASE_COUNT = 4
Config.WAVE_COUNT_GROWTH = 0.15
Config.WAVE_MAX_COUNT = 16

end

return apply
