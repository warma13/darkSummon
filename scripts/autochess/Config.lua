-- autochess/Config.lua
-- 自走棋副本：常量、英雄池、羁绊、经济参数

local C = {}

-- ============================================================================
-- 棋盘（TFT 六边形交错布局）
-- ============================================================================
C.BOARD_COLS    = 7
C.BOARD_ROWS    = 8   -- 上4行敌方(1-4)，下4行玩家(5-8)
C.BENCH_SIZE    = 9
C.ENEMY_ROW_MAX = 4   -- 敌方占 row 1-4
C.PLAYER_ROW_MIN = 5  -- 玩家占 row 5-8
C.HEX_STAGGER   = true -- 标记为六边形交错棋盘

-- ============================================================================
-- 经济
-- ============================================================================
C.START_GOLD     = 10
C.START_HP       = 100
C.INTEREST_RATE  = 10  -- 每10金币1利息
C.MAX_INTEREST   = 5
C.REROLL_COST    = 2
C.TOTAL_ROUNDS   = 10
C.WIN_BONUS      = 1   -- 胜利奖励 +1 金币

-- TFT 式基础工资：前几回合递增，之后固定 5
C.ROUND_INCOME = {
    [1] = 2,   -- 第1回合
    [2] = 2,   -- 第2回合
    [3] = 3,   -- 第3回合
    [4] = 4,   -- 第4回合
    -- 第5回合及以后 → 5（见 Board.GetBaseIncome）
}
C.BASE_INCOME_MAX = 5  -- 第5回合及以后的固定基础工资

-- TFT 式连胜/连败奖金
C.STREAK_BONUS = {
    [0] = 0,
    [1] = 0,
    [2] = 1,  -- 2~3连 +1
    [3] = 1,
    [4] = 2,  -- 4连 +2
    [5] = 3,  -- 5连及以上 +3（上限）
}

C.PREP_TIME = 30  -- 准备阶段秒数

-- ============================================================================
-- 等级系统（TFT 式）
-- level = 上场棋子上限; xpReq = 升级所需经验; 买经验 4 金 → 4 经验
-- ============================================================================
C.BUY_XP_COST   = 4   -- 花费金币
C.BUY_XP_AMOUNT = 4   -- 获得经验
C.MAX_LEVEL     = 9
C.ROUND_FREE_XP = 2   -- 每回合免费经验

--- level → { xpReq, boardSlots }  (TFT 标准：满级9个上场位)
C.LEVEL_TABLE = {
    [1] = { xpReq = 2,  slots = 1 },
    [2] = { xpReq = 2,  slots = 2 },
    [3] = { xpReq = 6,  slots = 3 },
    [4] = { xpReq = 10, slots = 4 },
    [5] = { xpReq = 20, slots = 5 },
    [6] = { xpReq = 36, slots = 6 },
    [7] = { xpReq = 48, slots = 7 },
    [8] = { xpReq = 72, slots = 8 },
    [9] = { xpReq = 0,  slots = 9 },  -- 满级无需经验
}

-- ============================================================================
-- 星级
-- ============================================================================
C.MAX_STAR = 3
C.MERGE_COUNT = 3  -- 3合1
C.STAR_HP_MULT  = { [1] = 1.0, [2] = 2.0,  [3] = 4.0  }
C.STAR_ATK_MULT = { [1] = 1.0, [2] = 1.8,  [3] = 3.2  }
C.STAR_DEF_MULT = { [1] = 1.0, [2] = 1.5,  [3] = 2.5  }

-- ============================================================================
-- 阵营
-- ============================================================================
C.FACTIONS = {
    undead    = { name = "亡灵", color = { 140, 200, 180 } },
    demon     = { name = "恶魔", color = { 220,  80,  80 } },
    elemental = { name = "元素", color = { 100, 180, 255 } },
    human     = { name = "人类", color = { 240, 210, 100 } },
}

-- ============================================================================
-- 羁绊效果
-- ============================================================================
-- 阵营英雄分布：
-- undead(6):  skeleton_grunt, skeleton_archer, ghost_assassin, necromancer, shadow_mage, crimson_night
-- demon(6):   bat_minion, hell_hound, demon_warrior, abyss_hunter, void_dragon, eternal_archfiend
-- elemental(6): stone_golem, inferno_flame, frost_witch, storm_lord, ember_wraith, fate_weaver
-- human(3):   armor_breaker, war_drummer, plague_doctor, fallen_archangel
C.SYNERGIES = {
    undead = {
        { count = 2, desc = "+15%攻击",  atkPct = 0.15 },
        { count = 4, desc = "+30%攻击",  atkPct = 0.30 },
        { count = 6, desc = "+50%攻击",  atkPct = 0.50 },
    },
    demon = {
        { count = 2, desc = "+10%攻速",  spdPct = 0.10 },
        { count = 4, desc = "+25%攻速",  spdPct = 0.25 },
        { count = 6, desc = "+40%攻速",  spdPct = 0.40 },
    },
    elemental = {
        { count = 2, desc = "+20防御",   defFlat = 20 },
        { count = 4, desc = "+40防御",   defFlat = 40 },
        { count = 6, desc = "+60防御",   defFlat = 60 },
    },
    human = {
        { count = 2, desc = "+100血量",  hpFlat = 100 },
        { count = 3, desc = "+250血量",  hpFlat = 250 },
        { count = 4, desc = "+400血量",  hpFlat = 400 },
    },
}

-- ============================================================================
-- 英雄池（21 个，复用主游戏 Config_Core 的全部英雄）
-- 费用按品质映射：N→1费, R→2费, SR→3费, SSR→4费, UR/LR→5费
-- ============================================================================
C.HEROES = {
    -- ========== 1费 · N级（3个） ==========
    {
        id = "skeleton_grunt", name = "骷髅小兵", cost = 1,
        faction = "undead", atkType = "single",
        color = { 180, 170, 140 },
        hp = 400, atk = 28, atkSpeed = 1.0, range = 2, def = 5,
    },
    {
        id = "bat_minion", name = "蝙蝠仆从", cost = 1,
        faction = "demon", atkType = "single",
        color = { 140, 120, 160 },
        hp = 350, atk = 24, atkSpeed = 1.5, range = 2, def = 3,
    },
    {
        id = "hell_hound", name = "地狱犬", cost = 1,
        faction = "demon", atkType = "aoe",
        color = { 200, 100, 50 },
        hp = 380, atk = 30, atkSpeed = 1.0, range = 2, def = 4,
    },
    -- ========== 2费 · R级（4个） ==========
    {
        id = "skeleton_archer", name = "骷髅弓手", cost = 2,
        faction = "undead", atkType = "single",
        color = { 80, 200, 80 },
        hp = 420, atk = 40, atkSpeed = 1.2, range = 3, def = 4,
    },
    {
        id = "demon_warrior", name = "恶魔战士", cost = 2,
        faction = "demon", atkType = "aoe",
        color = { 220, 60, 60 },
        hp = 480, atk = 42, atkSpeed = 0.9, range = 2, def = 7,
    },
    {
        id = "ghost_assassin", name = "幽魂刺客", cost = 2,
        faction = "undead", atkType = "single",
        color = { 100, 180, 200 },
        hp = 380, atk = 38, atkSpeed = 1.3, range = 2, def = 3,
    },
    {
        id = "stone_golem", name = "石像兵", cost = 2,
        faction = "elemental", atkType = "single",
        color = { 160, 150, 130 },
        hp = 550, atk = 28, atkSpeed = 0.8, range = 2, def = 10,
    },
    -- ========== 3费 · SR级（5个） ==========
    {
        id = "necromancer", name = "死灵术士", cost = 3,
        faction = "undead", atkType = "single",
        color = { 60, 200, 200 },
        hp = 450, atk = 48, atkSpeed = 1.0, range = 3, def = 5,
    },
    {
        id = "inferno_flame", name = "炼狱火焰", cost = 3,
        faction = "elemental", atkType = "aoe",
        color = { 240, 150, 30 },
        hp = 420, atk = 52, atkSpeed = 0.9, range = 2, def = 5,
    },
    {
        id = "armor_breaker", name = "破甲骑士", cost = 3,
        faction = "human", atkType = "single",
        color = { 200, 180, 100 },
        hp = 500, atk = 50, atkSpeed = 0.9, range = 2, def = 8,
    },
    {
        id = "frost_witch", name = "冰霜女巫", cost = 3,
        faction = "elemental", atkType = "chain",
        color = { 120, 180, 255 },
        hp = 400, atk = 44, atkSpeed = 1.0, range = 3, def = 4,
    },
    {
        id = "war_drummer", name = "战鼓祭司", cost = 3,
        faction = "human", atkType = "support",
        color = { 220, 180, 80 },
        hp = 520, atk = 18, atkSpeed = 0.4, range = 5, def = 8,
    },
    -- ========== 4费 · SSR级（4个） ==========
    {
        id = "shadow_mage", name = "暗影法师", cost = 4,
        faction = "undead", atkType = "single",
        color = { 160, 80, 220 },
        hp = 520, atk = 68, atkSpeed = 1.0, range = 3, def = 6,
    },
    {
        id = "abyss_hunter", name = "深渊猎手", cost = 4,
        faction = "demon", atkType = "single",
        color = { 180, 50, 90 },
        hp = 500, atk = 72, atkSpeed = 1.1, range = 3, def = 5,
    },
    {
        id = "plague_doctor", name = "瘟疫博士", cost = 4,
        faction = "human", atkType = "aoe",
        color = { 100, 180, 60 },
        hp = 480, atk = 58, atkSpeed = 1.0, range = 2, def = 7,
    },
    {
        id = "storm_lord", name = "暴风领主", cost = 4,
        faction = "elemental", atkType = "aoe",
        color = { 80, 140, 255 },
        hp = 540, atk = 62, atkSpeed = 1.0, range = 3, def = 6,
    },
    -- ========== 5费 · UR+LR级（6个） ==========
    {
        id = "fallen_archangel", name = "堕天使长", cost = 5,
        faction = "human", atkType = "aoe",
        color = { 255, 215, 60 },
        hp = 700, atk = 80, atkSpeed = 1.0, range = 3, def = 10,
    },
    {
        id = "void_dragon", name = "虚空龙王", cost = 5,
        faction = "demon", atkType = "chain",
        color = { 255, 200, 50 },
        hp = 680, atk = 85, atkSpeed = 0.9, range = 3, def = 9,
    },
    {
        id = "crimson_night", name = "绯夜", cost = 5,
        faction = "undead", atkType = "single",
        color = { 200, 50, 80 },
        hp = 600, atk = 92, atkSpeed = 1.1, range = 2, def = 7,
    },
    {
        id = "ember_wraith", name = "烬殇", cost = 5,
        faction = "elemental", atkType = "aoe",
        color = { 255, 120, 30 },
        hp = 650, atk = 88, atkSpeed = 1.0, range = 2, def = 8,
    },
    {
        id = "fate_weaver", name = "命运织者", cost = 5,
        faction = "elemental", atkType = "support",
        color = { 220, 40, 40 },
        hp = 750, atk = 20, atkSpeed = 0.3, range = 5, def = 12,
    },
    {
        id = "eternal_archfiend", name = "永恒魔君", cost = 5,
        faction = "demon", atkType = "single",
        color = { 200, 20, 20 },
        hp = 680, atk = 95, atkSpeed = 0.9, range = 2, def = 10,
    },
}

-- 按 id 索引
C.HERO_BY_ID = {}
for _, h in ipairs(C.HEROES) do
    C.HERO_BY_ID[h.id] = h
end

-- ============================================================================
-- 精灵图映射（复用主游戏 SpriteSheet）
-- key = 自走棋 heroId, value = 主游戏 SpriteSheet 注册名
-- 帧定义：0=idle, 1=attack, 2=projectile（大多数英雄）
-- ============================================================================
C.SPRITE_MAP = {
    -- N级 (1费)
    skeleton_grunt    = "grunt",
    bat_minion        = "bat_m",
    hell_hound        = "hound",
    -- R级 (2费)
    skeleton_archer   = "archer",
    demon_warrior     = "demon",
    ghost_assassin    = "assassin",
    stone_golem       = "golem",
    -- SR级 (3费)
    necromancer       = "necro",
    inferno_flame     = "flame",
    armor_breaker     = "knight",
    frost_witch       = "witch",
    war_drummer       = "drummer",
    -- SSR级 (4费)
    shadow_mage       = "mage",
    abyss_hunter      = "hunter",
    plague_doctor     = "plague",
    storm_lord        = "storm",
    -- UR/LR级 (5费)
    fallen_archangel  = "archangel",
    void_dragon       = "dragon",
    crimson_night     = "crimson_night",
    ember_wraith      = "ember_wraith",
    fate_weaver       = "weaver",
    eternal_archfiend = "archfiend",
}

-- 商店出率权重（按费用，1~5费）
C.SHOP_WEIGHTS = { [1] = 40, [2] = 30, [3] = 18, [4] = 9, [5] = 3 }
C.SHOP_SLOTS   = 5

-- ============================================================================
-- PVE 波次难度
-- ============================================================================
C.WAVES = {
    { count = 2, maxStar = 1, costs = { 1 } },          -- 回合1
    { count = 3, maxStar = 1, costs = { 1 } },          -- 回合2
    { count = 3, maxStar = 1, costs = { 1, 2 } },       -- 回合3
    { count = 4, maxStar = 1, costs = { 1, 2 } },       -- 回合4
    { count = 4, maxStar = 1, costs = { 1, 2, 3 } },    -- 回合5
    { count = 5, maxStar = 2, costs = { 2, 3 } },       -- 回合6
    { count = 5, maxStar = 2, costs = { 2, 3, 4 } },    -- 回合7
    { count = 6, maxStar = 2, costs = { 2, 3, 4 } },    -- 回合8
    { count = 6, maxStar = 2, costs = { 3, 4, 5 } },    -- 回合9
    { count = 6, maxStar = 3, costs = { 3, 4, 5 } },    -- 回合10
}

-- 品质颜色（按费用 1~5，对齐主游戏 RARITY_COLORS）
C.COST_COLORS = {
    [1] = { 180, 180, 180 },  -- N  灰色
    [2] = { 100, 200, 100 },  -- R  绿色
    [3] = { 120, 130, 255 },  -- SR 蓝色
    [4] = { 255, 200,  50 },  -- SSR 金色
    [5] = { 255, 160,  40 },  -- UR/LR 橙色
}

-- 费用对应的品质名称（商店卡片显示用）
C.COST_RARITY_NAME = {
    [1] = "N",
    [2] = "R",
    [3] = "SR",
    [4] = "SSR",
    [5] = "UR",
}

-- ============================================================================
-- 配色
-- ============================================================================
C.COLORS = {
    bg1        = {  15,  12,  25, 255 },
    bg2        = {  25,  18,  40, 255 },
    hudBg      = {  28,  20,  45, 240 },
    shopBg     = {  22,  16,  38, 240 },
    boardEnemy = {  40,  25,  30, 180 },
    boardPlayer= {  25,  30,  45, 180 },
    cellBorder = {  60,  50,  80, 120 },
    benchBg    = {  30,  24,  48, 200 },
    white      = { 245, 238, 225, 255 },
    gold       = { 255, 215,  80, 255 },
    red        = { 240,  70,  70, 255 },
    green      = { 120, 220, 100, 255 },
    dim        = { 150, 140, 160, 200 },
    selected   = { 255, 220, 100, 180 },
    hpBar      = { 100, 220,  80, 255 },
    hpBarBg    = {  40,  35,  50, 200 },
    hpBarEnemy = { 220,  80,  80, 255 },
    star       = { 255, 215,  80, 255 },
}

-- ============================================================================
-- 六边形工具函数
-- ============================================================================

--- 偶数行(2,4,6,8)向右偏移半格（offset coordinates, even-r layout）
--- 返回6个邻居 {col, row} 的列表
function C.HexNeighbors(col, row)
    -- even-r: 偶数行右移
    if row % 2 == 0 then
        return {
            { col + 1, row     },  -- 右
            { col,     row     - 1 },  -- 右上（偶数行无偏移→同列即右上）
            { col - 1, row - 1 },  -- 左上
            { col - 1, row     },  -- 左
            { col - 1, row + 1 },  -- 左下
            { col,     row + 1 },  -- 右下
        }
    else
        return {
            { col + 1, row     },  -- 右
            { col + 1, row - 1 },  -- 右上
            { col,     row - 1 },  -- 左上
            { col - 1, row     },  -- 左
            { col,     row + 1 },  -- 左下
            { col + 1, row + 1 },  -- 右下
        }
    end
end

--- 六边形距离（offset 坐标 → cube 坐标 → 曼哈顿距离 / 2）
function C.HexDist(c1, r1, c2, r2)
    -- offset (even-r) → cube
    local function toCube(col, row)
        local x = col - math.floor(row / 2)
        local z = row
        local y = -x - z
        return x, y, z
    end
    local x1, y1, z1 = toCube(c1, r1)
    local x2, y2, z2 = toCube(c2, r2)
    return math.max(math.abs(x1 - x2), math.abs(y1 - y2), math.abs(z1 - z2))
end

--- 检查坐标是否在棋盘范围内
function C.InBoard(col, row)
    return col >= 1 and col <= C.BOARD_COLS and row >= 1 and row <= C.BOARD_ROWS
end

return C
