-- Game/Config_Enemies.lua
-- 怪物系统：角色、主题、构建函数、词缀、关卡参数

local F = require("Game.FormulaLib")

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

-- BuildEnemyDef / BuildBossDef 缓存（Phase 3 优化）
-- 原型缓存: key = stageNum * 16 + roleIdx，value = 原型 table
-- 返回浅拷贝以防调用者修改
local _enemyDefCache = {}
local _bossDefCache = {}      -- stageNum → 原型 table
local _roleIdxMap = {}        -- roleId → 数字索引（避免字符串拼接）
do
    local roles = { "minion", "infantry", "tank", "assassin", "dodger", "support", "splitter", "blinker", "special" }
    for i, rid in ipairs(roles) do _roleIdxMap[rid] = i end
end

local function _shallowCopy(src)
    local dst = {}
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

--- 构建指定关卡+角色的完整怪物定义（运行时组合，带缓存）
function Config.BuildEnemyDef(stageNum, roleId)
    -- 缓存查找：同 stageNum+roleId 返回浅拷贝
    local ridx = _roleIdxMap[roleId]
    if ridx then
        local cacheKey = stageNum * 16 + ridx
        local proto = _enemyDefCache[cacheKey]
        if proto then return _shallowCopy(proto) end
    end

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

    -- 缓存原型，返回浅拷贝
    if ridx then
        _enemyDefCache[stageNum * 16 + ridx] = def
        return _shallowCopy(def)
    end
    return def
end

--- 构建指定关卡的 BOSS 定义（带缓存）
function Config.BuildBossDef(stageNum)
    -- 缓存查找
    local proto = _bossDefCache[stageNum]
    if proto then return _shallowCopy(proto) end

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

    -- 缓存原型，返回浅拷贝
    _bossDefCache[stageNum] = def
    return _shallowCopy(def)
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
-- 精英词缀定义（分类 + 强度缩放）
-- ============================================================================
-- 词缀分两大类：
--   "defense"  防御类 — 增强怪物生存能力
--   "buff"     增益类 — 敌人自身增强（加速/隐身/免控）
--   "debuff"   减益类 — 周期削弱英雄塔（降攻/降暴击/降星/毁灭）
--     debuff 词缀额外字段: targeting = "single"|"group"|"area"
-- 每个词缀有 tier (1/2/3) 和 category ("defense"/"buff"/"debuff")
-- scale(level) 函数返回缩放后的词缀实例（level = 等效关卡号 / 10）
-- level 大约对应：主线 stageNum/10，试练塔 floor（因为 1 floor = 10 stage）

Config.AFFIX_DEFS = {
    -- ==================== 防御类 (defense) ====================
    -- T1: 坚韧 — HP 倍率，随等级增长
    {
        id = "tough", name = "坚韧", tier = 1, category = "defense",
        color = { 200, 160, 80 },
        scale = function(lvl)
            return { hpMult = 1.5 + lvl * 0.03 }  -- 1.5x ~ 4.5x @lvl100
        end,
    },
    -- T1: 再生 — 每秒恢复 maxHP 百分比
    {
        id = "regen", name = "再生", tier = 1, category = "defense",
        color = { 80, 220, 80 },
        scale = function(lvl)
            return { regenRate = 0.008 + lvl * 0.0003 }  -- 0.8% ~ 3.8%/s
        end,
    },
    -- T2: 护盾 — 按 maxHP 百分比生成护盾
    {
        id = "shielded", name = "护盾", tier = 2, category = "defense",
        color = { 200, 200, 255 },
        scale = function(lvl)
            return { shieldHP = 0.3 + lvl * 0.005 }  -- 30% ~ 80% maxHP
        end,
    },
    -- T2: 铁壁 — 每隔 N 秒增加防御值
    {
        id = "iron_wall", name = "铁壁", tier = 2, category = "defense",
        color = { 160, 160, 180 },
        scale = function(lvl)
            return {
                ironWallInterval = math.max(3.0, 6.0 - lvl * 0.02),  -- 6s → 3s
                ironWallDefPct   = 0.10 + lvl * 0.003,               -- +10% ~ +40% baseDEF per tick
            }
        end,
    },
    -- T2: 回春 — 每隔 N 秒恢复已损失生命值百分比
    {
        id = "rejuvenate", name = "回春", tier = 2, category = "defense",
        color = { 100, 220, 160 },
        scale = function(lvl)
            return {
                rejuvInterval = math.max(2.0, 5.0 - lvl * 0.02),  -- 5s → 2s
                rejuvPct      = 0.05 + lvl * 0.002,               -- 5% ~ 25% lost HP per tick
            }
        end,
    },
    -- T3: 不朽 — 首次死亡复活
    {
        id = "undying", name = "不朽", tier = 3, category = "defense",
        color = { 255, 220, 60 },
        scale = function(lvl)
            return { revive = true, reviveHPRate = math.min(0.3 + lvl * 0.005, 0.8) }  -- 30% ~ 80%
        end,
    },

    -- ==================== 增益类 buff（敌人自身增强） ====================
    -- T1: 迅捷 — 移速倍率
    {
        id = "swift", name = "迅捷", tier = 1, category = "buff",
        color = { 80, 200, 255 },
        scale = function(lvl)
            return { speedMult = math.min(1.8, 1.3 + lvl * 0.005) }  -- 1.3x → 1.8x 封顶
        end,
    },
    -- T1: 狂暴 — 低血量时加速
    {
        id = "berserk", name = "狂暴", tier = 1, category = "buff",
        color = { 255, 100, 60 },
        scale = function(lvl)
            return {
                enrageThreshold = 0.5,
                enrageSpeedMult = 1.5 + lvl * 0.008,  -- 1.5x ~ 2.3x
            }
        end,
    },
    -- T2: 隐身 — 周期性隐身无敌
    {
        id = "stealth", name = "隐身", tier = 2, category = "buff",
        color = { 120, 120, 160 },
        scale = function(lvl)
            return {
                phaseInterval = math.max(4.0, 6.0 - lvl * 0.02),  -- 6s → 4s 封底
                phaseDuration = math.min(1.0 + lvl * 0.005, 2.0),  -- 1s → 2s 封顶（最高50%隐身率）
            }
        end,
    },
    -- T3: 虚空 — 免疫所有控制效果
    {
        id = "void_aura", name = "虚空", tier = 3, category = "buff",
        color = { 160, 80, 255 },
        scale = function(lvl)
            return { immuneCC = true }
        end,
    },

    -- ==================== 减益类 debuff（周期削弱英雄塔） ====================
    -- targeting: "single"=随机1个, "group"=全体, "area"=敌人附近范围
    -- debuffDuration: 减益持续秒数

    -- T1: 降攻击 — 周期降低英雄攻击力
    {
        id = "atk_down", name = "降攻击", tier = 1, category = "debuff",
        color = { 255, 140, 80 }, targeting = "single",
        scale = function(lvl)
            return {
                debuffInterval = math.max(5.0, 10.0 - lvl * 0.03),  -- 10s → 5s
                debuffDuration = 4.0,
                debuffStat = "attack", debuffPct = math.min(0.35, 0.10 + lvl * 0.002),  -- -10% → -35%
            }
        end,
    },
    -- T1: 降攻速 — 周期降低英雄攻击速度
    {
        id = "spd_down", name = "降攻速", tier = 1, category = "debuff",
        color = { 100, 180, 255 }, targeting = "single",
        scale = function(lvl)
            return {
                debuffInterval = math.max(5.0, 10.0 - lvl * 0.03),
                debuffDuration = 4.0,
                debuffStat = "speed", debuffPct = math.min(0.35, 0.10 + lvl * 0.002),  -- +10% → +35% 攻击间隔
            }
        end,
    },
    -- T2: 降暴击 — 周期降低英雄暴击率（范围）
    {
        id = "crit_down", name = "降暴击", tier = 2, category = "debuff",
        color = { 255, 100, 100 }, targeting = "area",
        scale = function(lvl)
            return {
                debuffInterval = math.max(6.0, 12.0 - lvl * 0.04),
                debuffDuration = 5.0, debuffRadius = 120,
                debuffStat = "critRate", debuffFlat = math.min(0.30, 0.08 + lvl * 0.002),  -- -8% → -30%
            }
        end,
    },
    -- T2: 降爆伤 — 周期降低英雄暴击伤害（范围）
    {
        id = "critdmg_down", name = "降爆伤", tier = 2, category = "debuff",
        color = { 220, 80, 120 }, targeting = "area",
        scale = function(lvl)
            return {
                debuffInterval = math.max(6.0, 12.0 - lvl * 0.04),
                debuffDuration = 5.0, debuffRadius = 120,
                debuffStat = "critDmg", debuffFlat = math.min(0.50, 0.15 + lvl * 0.003),  -- -15% → -50%
            }
        end,
    },
    -- T2: 降星 — 每隔 N 秒随机降低一个英雄塔 1 星（单体直接效果）
    {
        id = "star_drain", name = "降星", tier = 2, category = "debuff",
        color = { 200, 80, 200 }, targeting = "single",
        scale = function(lvl)
            return {
                starDrainInterval = math.max(5.0, 12.0 - lvl * 0.05),  -- 12s → 5s
            }
        end,
    },
    -- T3: 降穿甲 — 周期降低英雄穿甲率（群体）
    {
        id = "pen_down", name = "降穿甲", tier = 3, category = "debuff",
        color = { 200, 160, 80 }, targeting = "group",
        scale = function(lvl)
            return {
                debuffInterval = math.max(8.0, 15.0 - lvl * 0.05),
                debuffDuration = 5.0,
                debuffStat = "armorPen", debuffFlat = math.min(0.25, 0.05 + lvl * 0.002),  -- -5% → -25%
            }
        end,
    },
    -- T3: 降元素 — 周期降低英雄元素伤害（群体）
    {
        id = "elem_down", name = "降元素", tier = 3, category = "debuff",
        color = { 80, 200, 160 }, targeting = "group",
        scale = function(lvl)
            return {
                debuffInterval = math.max(8.0, 15.0 - lvl * 0.05),
                debuffDuration = 5.0,
                debuffStat = "dmgBonus", debuffFlat = math.min(0.30, 0.08 + lvl * 0.002),  -- -8% → -30%
            }
        end,
    },
    -- T3: 毁灭 — 每隔 N 秒销毁一个随机英雄塔（单体直接效果）
    {
        id = "annihilate", name = "毁灭", tier = 3, category = "debuff",
        color = { 255, 40, 40 }, targeting = "single",
        scale = function(lvl)
            return {
                annihilateInterval = math.max(8.0, 20.0 - lvl * 0.08),  -- 20s → 8s
            }
        end,
    },
}

-- 构建快速查找表
Config.AFFIX_BY_ID = {}
for _, def in ipairs(Config.AFFIX_DEFS) do
    Config.AFFIX_BY_ID[def.id] = def
end

-- 向后兼容：旧 AFFIXES 表（不含 scale 结果，仅定义引用）
Config.AFFIXES = Config.AFFIX_DEFS

-- 词缀解锁阈值（等效全局波次）
Config.AFFIX_WAVE_T1 = 15
Config.AFFIX_WAVE_T2 = 35
Config.AFFIX_WAVE_T3 = 60

--- 缩放词缀：根据 level 生成带具体数值的词缀实例
--- level 约等于 stageNum/10（主线）或 floor（试练塔）
---@param affixDef table 词缀定义（来自 AFFIX_DEFS）
---@param level number 难度等级
---@return table 带具体数值字段的词缀实例
function Config.ScaleAffix(affixDef, level)
    local instance = {
        id       = affixDef.id,
        name     = affixDef.name,
        tier     = affixDef.tier,
        category = affixDef.category,
        color    = affixDef.color,
    }
    if affixDef.scale then
        local scaled = affixDef.scale(level)
        for k, v in pairs(scaled) do
            instance[k] = v
        end
    end
    return instance
end

--- 获取指定等效全局波次可用的词缀池
---@param globalWave number 等效全局波次
---@return table[] 可用词缀定义列表
function Config.GetAffixPool(globalWave)
    local pool = {}
    for _, def in ipairs(Config.AFFIX_DEFS) do
        if def.tier == 1 and globalWave >= Config.AFFIX_WAVE_T1 then
            pool[#pool + 1] = def
        elseif def.tier == 2 and globalWave >= Config.AFFIX_WAVE_T2 then
            pool[#pool + 1] = def
        elseif def.tier == 3 and globalWave >= Config.AFFIX_WAVE_T3 then
            pool[#pool + 1] = def
        end
    end
    return pool
end

--- 从词缀池中随机选取并缩放
---@param globalWave number 等效全局波次（用于解锁判定）
---@param count number 选取数量
---@param level number 缩放等级（stageNum/10 或 floor）
---@return table[] 缩放后的词缀实例列表
function Config.PickAffixes(globalWave, count, level)
    local pool = Config.GetAffixPool(globalWave)
    if #pool == 0 then return {} end
    count = math.min(count, #pool)
    -- Fisher-Yates 部分洗牌
    local copy = {}
    for i, v in ipairs(pool) do copy[i] = v end
    local result = {}
    for i = 1, count do
        local j = math.random(i, #copy)
        copy[i], copy[j] = copy[j], copy[i]
        result[#result + 1] = Config.ScaleAffix(copy[i], level)
    end
    return result
end

-- ============================================================================
-- 怪物防御属性（随关卡成长）
-- ============================================================================

-- 敌人 DEF 独立缩放表（与 HP 解耦）
-- DEF 缩放表: heroParamsAtStage 精确校准，defFactor=1.25 (DEF 贡献 ~20%)
-- 基准: SSR shadow_mage(baseAtk=3600), minion(baseDEF=500)
-- 每行: { fromStage, toStage, scaleFrom, scaleTo }
Config.DEF_SCALE_SEGMENTS = {
    {     1,   100,          1.8,             24 },
    {   100,   500,           24,            165 },
    {   500,  1000,          165,            543 },
    {  1000,  1500,          543,         3750.0 },
    {  1500,  2000,       3750.0,         8240.0 },
    {  2000,  2500,       8240.0,        58700.0 },
    {  2500,  3000,      58700.0,       105000.0 },
    {  3000,  3500,     105000.0,       312000.0 },
    {  3500,  4000,     312000.0,      1300000.0 },
    {  4000,  4500,    1300000.0,      3690000.0 },
    {  4500,  5000,    3690000.0,     16230000.0 },
    {  5000,  5500,   16230000.0,     51760000.0 },
    {  5500,  6000,   51760000.0,    117040000.0 },
}

--- 统一 DEF 缩放函数（分段线性插值，与 HP 独立）
---@param stage number 关卡号（>=1）
---@return number 缩放倍率
function Config.GetStageDEFScale(stage)
    if stage <= 1 then return 1.0 end
    return F.Piecewise4(Config.DEF_SCALE_SEGMENTS, stage)
end

-- 向后兼容: 保留旧常量供外部引用（不再用于实际 DEF 计算）
Config.ENEMY_DEF_HP_RATIO = 0.10

-- 怪物随关卡成长的防御属性（对抗英雄各乘区膨胀）
-- 分段线性插值，格式: { stageFrom, stageTo, valueFrom, valueTo }
Config.ENEMY_SCALING = {
    -- 暴击伤害减免: 降低英雄暴击乘区（0 = 不减免, 0.20 = 暴击伤害打8折）
    critDmgReduce = {
        {    1,   500,   0.00,  0.00 },   -- 前期不减免
        {  500,  1500,   0.00,  0.05 },   -- 中期缓慢增长
        { 1500,  3000,   0.05,  0.10 },   -- 中后期轻微
        { 3000,  5000,   0.10,  0.15 },
        { 5000,  6000,   0.15,  0.20 },   -- 终局：暴击伤害打8折
    },
    -- 伤害加成减免: 降低英雄 dmgBonus 乘区（0 = 不减免, 0.15 = 伤害加成打85折）
    dmgBonusReduce = {
        {    1,   500,   0.00,  0.00 },
        {  500,  1500,   0.00,  0.05 },
        { 1500,  3000,   0.05,  0.08 },
        { 3000,  5000,   0.08,  0.12 },
        { 5000,  6000,   0.12,  0.15 },   -- 终局：伤害加成打85折
    },
    -- 元素伤害减免: 降低英雄 elemDmg 乘区（叠加在主题抗性之上）
    elemDmgReduce = {
        {    1,   500,   0.00,  0.00 },
        {  500,  1500,   0.00,  0.03 },
        { 1500,  3000,   0.03,  0.06 },
        { 3000,  5000,   0.06,  0.10 },
        { 5000,  6000,   0.10,  0.15 },   -- 终局：元素伤害打85折
    },
    -- 穿甲抵抗: 降低英雄穿甲有效率（0.15 = 英雄穿甲生效85%）
    armorPenResist = {
        {    1,   500,   0.00,  0.00 },
        {  500,  2000,   0.00,  0.05 },
        { 2000,  4000,   0.05,  0.10 },
        { 4000,  6000,   0.10,  0.15 },   -- 终局：穿甲生效85%
    },
}

-- 怪物主题元素抗性（themeId → { element = resistance }）
-- 正值 = 抗性（减伤），负值 = 弱点（增伤）
Config.THEME_ELEMENT_RESIST = {
    undead = {
        fire = -0.25,       -- 亡灵怕火
        ice = 0.10,
        lightning = 0.0,
        poison = 0.30,      -- 亡灵抗毒
        shadow = 0.20,      -- 亡灵亲和暗
    },
    lava = {
        fire = 0.50,        -- 熔岩极抗火
        ice = -0.30,        -- 熔岩怕冰
        lightning = 0.0,
        poison = -0.10,
        shadow = 0.0,
    },
    forest = {
        fire = -0.30,       -- 森林怕火
        ice = 0.0,
        lightning = -0.10,
        poison = 0.40,      -- 森林抗毒
        shadow = -0.15,
    },
    frost = {
        fire = -0.25,       -- 冰霜怕火
        ice = 0.50,         -- 冰霜极抗冰
        lightning = -0.20,  -- 冰霜怕雷
        poison = 0.0,
        shadow = 0.0,
    },
    void = {
        fire = 0.0,
        ice = 0.0,
        lightning = -0.15,
        poison = -0.20,
        shadow = 0.40,      -- 虚空极抗暗
    },
}

-- ============================================================================
-- 关卡 & 波次参数
-- ============================================================================
Config.WAVES_PER_STAGE = 10
Config.BOSS_WAVE = 10
Config.ELITE_INTERVAL = 3

-- HP 缩放表: heroParamsAtStage 精确校准，killTime = 2+8√progress (2s → 10s)
-- 基准: SSR shadow_mage, minion(baseHP=4500), defFactor≈1.25
-- 每行: { fromStage, toStage, scaleFrom, scaleTo }
Config.HP_SCALE_SEGMENTS = {
    {     1,   100,         1.02,          7.5 },
    {   100,   500,          7.5,           19 },
    {   500,  1000,           19,           41 },
    {  1000,  1500,           41,          256 },
    {  1500,  2000,          256,          490 },
    {  2000,  2500,          490,         3610 },
    {  2500,  3000,         3610,         6110 },
    {  3000,  3500,         6110,        17300 },
    {  3500,  4000,        17300,        81300 },
    {  4000,  4500,        81300,       226000 },
    {  4500,  5000,       226000,      1140000 },
    {  5000,  5500,      1140000,      3500000 },
    {  5500,  6000,      3500000,      7660000 },
}

--- 统一 HP 缩放函数（分段线性插值）
---@param stage number 关卡号（>=1）
---@return number 缩放倍率
function Config.GetStageHPScale(stage)
    if stage <= 1 then return 1.0 end
    return F.Piecewise4(Config.HP_SCALE_SEGMENTS, stage)
end

Config.STAGE_SPEED_PER_STAGE = 0.02
Config.STAGE_SPEED_CAP = 1.8

Config.WAVE_HP_PER_WAVE = 0.04
Config.WAVE_BASE_COUNT = 4
Config.WAVE_COUNT_GROWTH = 0.15
Config.WAVE_MAX_COUNT = 16

-- ============================================================================
-- 深渊 BOSS：憎恨化身（独立定义，供无尽深渊/副本系统使用）
-- ============================================================================

Config.HATRED_BOSS = {
    id = "hatred_body",
    name = "憎恨化身",
    color = { 180, 40, 60 },
    baseHP = math.huge,
    baseDEF = 80,
    speed = 18,
    size = 26,
    icon = "image/mobs/hatred_boss.png",
    passive = "immune_cc",

    -- 技能组配置（传入 HatredBossSkills.Init）
    bossSkills = {
        summon = {
            interval = 20.0,
            maxCount = 10,            -- 最多召唤10个
            baseCount = 1,            -- 首次召唤1个，每次+1
            hpMult = 3.0,
            hpScale = 1.0,
            statGrowth = 1.5,         -- 每次召唤属性指数增长倍率
        },
        fortress = {
            interval = 25.0,
            baseShield = 2000,        -- 初始护盾值，每次释放翻倍
            defMult = 2.0,
            permanent = true,         -- 永久生效，可无限叠加
        },
        taunt = {
            interval = 15.0,
            duration = 10.0,
            maxStacks = 5,
            spdPerStack = 0.08,
            stackDuration = 6.0,
        },
        star_crush = {
            interval = 30.0,
            channelTime = 3.0,
            toughnessDefDiv = 100000, -- 韧性次数 = ceil(boss.def / 此值)，与防御成正比
            toughnessMin = 20,        -- 最低韧性次数
            starReduction = 1,
        },
        destruction = {
            interval = 45.0,          -- 释放间隔
            channelTime = 5.0,        -- 引导时间，未打断则执行毁灭
            baseRadius = 1,           -- 初始半径（3x3）
            radiusGrowth = 1,         -- 每次成功释放 +1 半径
            maxRadius = 3,            -- 最大半径（覆盖5x6英雄棋盘）
            toughnessDefDiv = 100000, -- 韧性次数 = ceil(boss.def / 此值)，与防御成正比
            toughnessMin = 20,        -- 最低韧性次数
        },
    },
}

--- 构建憎恨化身 BOSS 定义（带数值缩放）
---@param wave number 当前波次
---@param hpScale? number HP 缩放倍率（默认 1.0）
---@return table bossDef
function Config.BuildHatredBoss(wave, hpScale)
    hpScale = hpScale or 1.0

    local src = Config.HATRED_BOSS
    local def = {}
    for k, v in pairs(src) do
        if k ~= "bossSkills" then
            def[k] = v
        end
    end

    def.baseHP = src.baseHP * hpScale
    def.isBoss = true
    def.isHatredBoss = true
    def.reward = 50
    def.liveCost = 3
    def.shape = "diamond"

    -- 深拷贝技能配置
    local skills = {}
    for sk, cfg in pairs(src.bossSkills) do
        local c = {}
        for ck, cv in pairs(cfg) do c[ck] = cv end
        skills[sk] = c
    end
    def.bossSkills = skills

    return def
end

end

return apply
