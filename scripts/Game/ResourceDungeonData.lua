-- Game/ResourceDungeonData.lua
-- 资源副本数据模块：4 种资源副本，每副本 20 波 × 20 怪，每波末尾 BOSS
-- 难度对标主线：第 1 波 ≈ 主线第 10 关，第 20 波 ≈ 主线第 6000 关

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")
local TodayStr = require("Game.DateUtil").TodayStr

local RD = {}

-- ============================================================================
-- 副本定义
-- ============================================================================

---@class ResourceDungeonDef
---@field key string
---@field name string
---@field emoji string
---@field desc string
---@field accentColor number[]
---@field rewardCurrency string        主要奖励货币 ID
---@field bonusCurrency string|nil     次要奖励货币 ID

RD.DUNGEON_DEFS = {
    {
        key            = "crystal",
        name           = "冥晶矿洞",
        emoji          = "💎",
        desc           = "击败守卫，掠夺冥晶矿脉",
        accentColor    = { 140, 80, 200, 255 },
        rewardCurrency = "nether_crystal",
        bonusCurrency  = nil,
        cover          = "image/dungeon_crystal_mine.png",
    },
    {
        key            = "stone",
        name           = "噬魂深渊",
        emoji          = "🪨",
        desc           = "深渊之中蕴含噬魂之力",
        accentColor    = { 60, 180, 80, 255 },
        rewardCurrency = "devour_stone",
        bonusCurrency  = nil,
        cover          = "image/dungeon_soul_abyss.png",
    },
    {
        key            = "iron",
        name           = "锻魂熔炉",
        emoji          = "⚒",
        desc           = "烈焰锻炉，精炼锻魂铁",
        accentColor    = { 180, 140, 80, 255 },
        rewardCurrency = "forge_iron",
        bonusCurrency  = nil,
        cover          = "image/dungeon_forge.png",
    },
    {
        key            = "chest",
        name           = "宝箱秘境",
        emoji          = "📦",
        desc           = "击败Boss，开启神秘宝箱",
        accentColor    = { 220, 160, 40, 255 },
        rewardCurrency = "chest",   -- 特殊：奖励宝箱而非货币
        bonusCurrency  = nil,
        cover          = "image/dungeon_treasure.png",
    },
}

-- 按 key 索引
RD.DUNGEON_MAP = {}
for _, def in ipairs(RD.DUNGEON_DEFS) do
    RD.DUNGEON_MAP[def.key] = def
end

-- 副本 key → 专属挑战券物品 ID
RD.DUNGEON_TICKET_MAP = {
    crystal = "dungeon_ticket_crystal",
    stone   = "dungeon_ticket_stone",
    iron    = "dungeon_ticket_iron",
    chest   = "dungeon_ticket_chest",
}

-- ============================================================================
-- 波次参数
-- ============================================================================
RD.TOTAL_WAVES     = 20     -- 总波数
RD.ENEMIES_PER_WAVE = 20    -- 每波怪物数（含末尾 Boss）
RD.BOSS_HP_MULT    = 5.0    -- Boss HP = 该波普通怪 × 5

-- ============================================================================
-- 难度等级定义
-- ============================================================================
RD.DIFFICULTY_LEVELS = {
    { level = 0, label = "普通",  statMult = 1,     rewardMult = 1 },
    { level = 1, label = "困难",  statMult = 10,    rewardMult = 2 },
    { level = 2, label = "噩梦",  statMult = 100,   rewardMult = 3 },
    { level = 3, label = "地狱",  statMult = 1000,  rewardMult = 4 },
    { level = 4, label = "炼狱",  statMult = 10000, rewardMult = 5 },
}

--- 根据 level 返回难度定义
---@param level number
---@return table
function RD.GetDifficultyDef(level)
    for _, d in ipairs(RD.DIFFICULTY_LEVELS) do
        if d.level == level then return d end
    end
    return RD.DIFFICULTY_LEVELS[1]  -- fallback 普通
end

-- ============================================================================
-- 难度缩放公式
-- 目标：wave 1 ≈ 主线第 10 关，wave 20 ≈ 主线第 6000 关
--
-- 副本波次映射: wave w → 等效关卡 s(w)
--   s(w) = 10 * (6000/10)^((w-1)/19) = 10 * 600^((w-1)/19)
-- 这样 s(1)=10, s(20)=6000，中间对数平滑插值
-- ============================================================================

--- 副本第 w 波对应的等效主线关卡号
---@param wave number 1~20
---@return number stageEquiv
function RD.WaveToStage(wave)
    -- s(w) = 10 * 600^((w-1)/19)
    local t = (wave - 1) / (RD.TOTAL_WAVES - 1)
    return 10 * (600 ^ t)
end

--- 根据等效关卡计算 HP 缩放倍率（复用主线公式）
---@param stageEquiv number 等效关卡号（可以是小数）
---@return number
function RD.CalcHPScale(stageEquiv)
    return Config.GetStageHPScale(stageEquiv)
end

--- 根据等效关卡计算速度缩放
---@param stageEquiv number
---@return number
function RD.CalcSpeedScale(stageEquiv)
    return math.min(1.0 + (stageEquiv - 1) * Config.STAGE_SPEED_PER_STAGE, Config.STAGE_SPEED_CAP)
end

-- ============================================================================
-- 奖励公式
-- ============================================================================

--- 分段指数插值：在锚点之间做对数线性插值，精确匹配设计文档目标值
--- 锚点格式: { {wave, value}, ... }
---@param wave number
---@param knots table
---@return number
local function LogInterp(wave, knots)
    -- 边界
    if wave <= knots[1][1] then return knots[1][2] end
    if wave >= knots[#knots][1] then return knots[#knots][2] end
    -- 查找区间
    for i = 1, #knots - 1 do
        local w1, v1 = knots[i][1], knots[i][2]
        local w2, v2 = knots[i + 1][1], knots[i + 1][2]
        if wave >= w1 and wave <= w2 then
            local t = (wave - w1) / (w2 - w1)
            return v1 * (v2 / v1) ^ t
        end
    end
    return knots[#knots][2]
end

--- 各副本奖励曲线锚点（定义分布形状，实际数值由 FULL_CLEAR_TARGET 缩放）
--- 锚点来自数值设计文档，作为相对分布权重使用
local REWARD_KNOTS = {
    nether_crystal = { {1, 50}, {5, 157}, {10, 632}, {15, 2529}, {20, 4000} },
    devour_stone   = { {1, 3},  {5, 9},   {10, 37},  {15, 151},  {20, 240} },
    forge_iron     = { {1, 3},  {5, 9},   {10, 37},  {15, 151},  {20, 240} },
}

--- 各锚点的基础全通关累计值（LogInterp 20波求和）
local BASE_FULL_CLEAR = {
    nether_crystal = 13098,
    devour_stone   = 784,
    forge_iron     = 784,
}

--- 各副本全通关目标总奖励（固定值）
--- 冥晶：后期升级封顶消耗 808万 的一半 = 400万
local FULL_CLEAR_TARGET = {
    nether_crystal = 4000000,   -- 400万冥晶
    devour_stone   = 5000,      -- 5000噬魂石
    forge_iron     = 2500,      -- 2500锻魂铁
}

--- 宝箱秘境每波奖励定义（每5波一组：前4波朽木宝箱×1，第5波为阶段性奖励）
local CHEST_WAVE_REWARDS = {
    -- 第 1 组 (w1-w5)
    [1] = { id = "wood",     count = 1 },
    [2] = { id = "wood",     count = 1 },
    [3] = { id = "wood",     count = 1 },
    [4] = { id = "wood",     count = 1 },
    [5] = { id = "bronze",   count = 1 },
    -- 第 2 组 (w6-w10)
    [6]  = { id = "wood",    count = 1 },
    [7]  = { id = "wood",    count = 1 },
    [8]  = { id = "wood",    count = 1 },
    [9]  = { id = "wood",    count = 1 },
    [10] = { id = "gold",    count = 1 },
    -- 第 3 组 (w11-w15)
    [11] = { id = "wood",    count = 1 },
    [12] = { id = "wood",    count = 1 },
    [13] = { id = "wood",    count = 1 },
    [14] = { id = "wood",    count = 1 },
    [15] = { id = "gold",    count = 2 },
    -- 第 4 组 (w16-w20)
    [16] = { id = "wood",    count = 1 },
    [17] = { id = "wood",    count = 1 },
    [18] = { id = "wood",    count = 1 },
    [19] = { id = "wood",    count = 1 },
    [20] = { id = "platinum", count = 1 },
}

--- 获取宝箱副本某波的奖励定义
---@param wave number 1~20
---@return table|nil  { id = "wood", count = 1 }
function RD.GetChestWaveReward(wave)
    return CHEST_WAVE_REWARDS[wave]
end

--- 每波主要奖励数量（按锚点曲线分布，总量 = FULL_CLEAR_TARGET）
--- 宝箱副本返回该波宝箱数量（具体类型用 GetChestWaveReward 查询）
---@param dungeonKey string
---@param wave number 1~20
---@param diffLevel number|nil 难度等级（默认0），影响奖励倍率
---@return number amount
function RD.GetWaveReward(dungeonKey, wave, diffLevel)
    local def = RD.DUNGEON_MAP[dungeonKey]
    if not def then return 0 end

    local diffDef = RD.GetDifficultyDef(diffLevel or 0)
    local rewardMult = diffDef.rewardMult or 1

    if def.rewardCurrency == "chest" then
        local cr = CHEST_WAVE_REWARDS[wave]
        return cr and (cr.count * rewardMult) or 0
    end

    local currId = def.rewardCurrency
    local knots = REWARD_KNOTS[currId]
    if not knots then return 0 end

    local base = LogInterp(wave, knots)
    local baseFull = BASE_FULL_CLEAR[currId] or 1
    local target = FULL_CLEAR_TARGET[currId] or baseFull
    return math.floor(base * target / baseFull * rewardMult)
end

--- 计算通关到第 maxWave 波的总奖励
---@param dungeonKey string
---@param maxWave number 打到第几波
---@param diffLevel number|nil 难度等级（默认0）
---@return table rewards {currencyId = amount} 或 {chests = {chestId=count}}
function RD.CalcTotalRewards(dungeonKey, maxWave, diffLevel)
    local def = RD.DUNGEON_MAP[dungeonKey]
    if not def then return {} end

    local diffDef = RD.GetDifficultyDef(diffLevel or 0)
    local rewardMult = diffDef.rewardMult or 1

    if def.rewardCurrency == "chest" then
        local chests = {}  -- chestId -> count
        for w = 1, maxWave do
            local cr = CHEST_WAVE_REWARDS[w]
            if cr then
                chests[cr.id] = (chests[cr.id] or 0) + cr.count * rewardMult
            end
        end
        return { chests = chests }
    end

    local total = 0
    for w = 1, maxWave do
        total = total + RD.GetWaveReward(dungeonKey, w, diffLevel)
    end
    return { [def.rewardCurrency] = total }
end

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

--- 生成指定副本、指定波次的敌人列表
---@param dungeonKey string 副本 key
---@param wave number 1~20
---@param diffLevel number|nil 难度等级（默认0）
---@return table enemies 敌人定义列表
function RD.GenerateWaveEnemies(dungeonKey, wave, diffLevel)
    local stageEquiv = RD.WaveToStage(wave)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = RD.CalcHPScale(stageEquiv)
    local spdScale = RD.CalcSpeedScale(stageEquiv)

    -- 难度倍率：影响 HP
    local diffDef = RD.GetDifficultyDef(diffLevel or 0)
    local statMult = diffDef.statMult or 1

    -- 获取该等效关卡的主题
    local themeIdx = ((stageNum - 1) % Config.THEME_COUNT) + 1
    local round = math.floor((stageNum - 1) / Config.THEME_COUNT) + 1
    local roundHPMult = 1.0 + (round - 1) * 0.5

    -- 可用角色池
    local globalWave = stageNum * Config.WAVES_PER_STAGE
    local availRoles = {}
    for _, roleId in ipairs(Config.ROLE_IDS) do
        local role = Config.ENEMY_ROLES[roleId]
        if role then
            local unlockWave = Config.ROLE_UNLOCK_WAVE[role.unlockOrder] or 1
            if globalWave >= unlockWave then
                availRoles[#availRoles + 1] = roleId
            end
        end
    end
    if #availRoles == 0 then
        availRoles = { "minion", "infantry" }
    end

    local enemies = {}
    local normalCount = RD.ENEMIES_PER_WAVE - 1  -- 前 19 个普通怪

    for i = 1, normalCount do
        local roleId = availRoles[((i - 1) % #availRoles) + 1]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale * statMult
            def.speed = def.speed * spdScale
            def.isDungeonEnemy = true
            enemies[#enemies + 1] = def
        end
    end

    -- 第 20 个是 Boss
    local bossDef = Config.BuildBossDef(stageNum)
    if bossDef then
        -- Boss HP = 普通怪基准 × BOSS_HP_MULT × hpScale × 难度倍率
        bossDef.baseHP = bossDef.baseHP * hpScale * RD.BOSS_HP_MULT * statMult
        bossDef.speed = bossDef.speed * spdScale * 0.7  -- Boss 略慢
        bossDef.isDungeonEnemy = true
        bossDef.isDungeonBoss = true
        enemies[#enemies + 1] = bossDef
    end

    return enemies
end

-- ============================================================================
-- 进度管理
-- ============================================================================

--- 获取资源副本进度数据
---@return table
function RD.GetData()
    if not HeroData.resourceDungeon then
        HeroData.resourceDungeon = {
            -- 每种副本的最高通关波数
            bestWave = {
                crystal = 0,
                stone   = 0,
                iron    = 0,
                chest   = 0,
            },
            -- 今日已挑战次数（每日重置）
            todayAttempts = {
                crystal = 0,
                stone   = 0,
                iron    = 0,
                chest   = 0,
            },
            -- 今日已用广告续次次数（每日重置）
            todayAdAttempts = {
                crystal = 0,
                stone   = 0,
                iron    = 0,
                chest   = 0,
            },
            lastResetDate = TodayStr(),
            selectedDifficulty = 0,
            clearedDifficulties = {},
            bestWaveDiff = {},
        }
    end

    -- 兼容旧存档：补充 bestWaveDiff
    if not HeroData.resourceDungeon.bestWaveDiff then
        HeroData.resourceDungeon.bestWaveDiff = {}
    end

    -- 兼容旧存档：补充 selectedDifficulty / clearedDifficulties
    if HeroData.resourceDungeon.selectedDifficulty == nil then
        HeroData.resourceDungeon.selectedDifficulty = 0
    end
    if not HeroData.resourceDungeon.clearedDifficulties then
        HeroData.resourceDungeon.clearedDifficulties = {}
    end

    -- 兼容旧存档：补充 todayAdAttempts
    if not HeroData.resourceDungeon.todayAdAttempts then
        HeroData.resourceDungeon.todayAdAttempts = {
            crystal = 0, stone = 0, iron = 0, chest = 0,
        }
    end

    -- 每日重置检查
    local today = TodayStr()
    if HeroData.resourceDungeon.lastResetDate ~= today then
        for k, _ in pairs(HeroData.resourceDungeon.todayAttempts) do
            HeroData.resourceDungeon.todayAttempts[k] = 0
        end
        for k, _ in pairs(HeroData.resourceDungeon.todayAdAttempts) do
            HeroData.resourceDungeon.todayAdAttempts[k] = 0
        end
        HeroData.resourceDungeon.lastResetDate = today
    end

    return HeroData.resourceDungeon
end

--- 每日挑战次数上限
RD.FREE_ATTEMPTS     = 1   -- 每日免费次数
RD.AD_EXTRA_ATTEMPTS = 3   -- 每日广告领券上限

--- 获取剩余挑战次数（免费剩余 + 挑战券）
---@param dungeonKey string
---@return number
function RD.GetRemainingAttempts(dungeonKey)
    local free = RD.GetFreeRemaining(dungeonKey)
    local tickets = RD.GetTotalTicketCount(dungeonKey)
    return free + tickets
end

--- 获取剩余免费次数
---@param dungeonKey string
---@return number
function RD.GetFreeRemaining(dungeonKey)
    local data = RD.GetData()
    local used = data.todayAttempts[dungeonKey] or 0
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("dungeon_attempt")
    return math.max(0, RD.FREE_ATTEMPTS + bonusAttempt - used)
end

--- 获取剩余广告续次次数
---@param dungeonKey string
---@return number
function RD.GetAdRemaining(dungeonKey)
    local data = RD.GetData()
    local adUsed = data.todayAdAttempts and data.todayAdAttempts[dungeonKey] or 0
    return math.max(0, RD.AD_EXTRA_ATTEMPTS - adUsed)
end

--- 获取最高通关波数（按难度分别记录）
---@param dungeonKey string
---@param diffLevel number|nil 难度等级（默认为当前选择难度）
---@return number
function RD.GetBestWave(dungeonKey, diffLevel)
    local data = RD.GetData()
    if diffLevel == nil then
        diffLevel = data.selectedDifficulty or 0
    end
    -- 难度0 使用旧字段兼容（bestWave[dungeonKey]）
    if diffLevel == 0 then
        return data.bestWave[dungeonKey] or 0
    end
    -- 难度1+ 使用 bestWaveDiff[diffLevel][dungeonKey]
    local bwd = data.bestWaveDiff
    if not bwd then return 0 end
    local dk = tostring(diffLevel)
    if not bwd[dk] then return 0 end
    return bwd[dk][dungeonKey] or 0
end

-- ============================================================================
-- 难度系统 API
-- ============================================================================

--- 获取当前选择的难度等级
---@return number
function RD.GetSelectedDifficulty()
    local data = RD.GetData()
    return data.selectedDifficulty or 0
end

--- 设置当前难度等级（需已解锁）
---@param level number
function RD.SetSelectedDifficulty(level)
    local data = RD.GetData()
    if not RD.IsDifficultyUnlocked(level) then return end
    data.selectedDifficulty = level
    HeroData.Save()
end

--- 判断难度是否已解锁
---@param level number
---@return boolean
function RD.IsDifficultyUnlocked(level)
    if level == 0 then return true end  -- 难度0默认解锁
    local data = RD.GetData()
    local cleared = data.clearedDifficulties or {}
    -- 找到前一个难度等级
    local prevLevel = nil
    for i, d in ipairs(RD.DIFFICULTY_LEVELS) do
        if d.level == level then
            if i > 1 then prevLevel = RD.DIFFICULTY_LEVELS[i - 1].level end
            break
        end
    end
    if prevLevel == nil then return true end  -- 没有前置难度
    -- 兼容：旧存档可能用 string key，新存档用 number key（DeepNormalizeIntKeys 会转为 number）
    return cleared[prevLevel] == true or cleared[tostring(prevLevel)] == true
end

--- 标记某难度已通关（解锁下一难度）
---@param level number
function RD.MarkDifficultyCleared(level)
    local data = RD.GetData()
    if not data.clearedDifficulties then
        data.clearedDifficulties = {}
    end
    data.clearedDifficulties[level] = true
    HeroData.Save()
    print("[ResourceDungeon] Difficulty " .. level .. " cleared, next unlocked")
end

--- 消耗每日免费挑战次数（进入副本时调用）
---@param dungeonKey string
---@return boolean success
function RD.ConsumeAttempt(dungeonKey)
    local data = RD.GetData()
    local used = data.todayAttempts[dungeonKey] or 0
    -- 免费次数 + 神裔降临加成（券挑战走 ConsumeDungeonTicket，不走这里）
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("dungeon_attempt")
    if used >= RD.FREE_ATTEMPTS + bonusAttempt then
        Toast.Show("免费次数已用完，可使用挑战券继续", { 255, 200, 80 })
        return false
    end
    data.todayAttempts[dungeonKey] = used + 1
    HeroData.Save()
    return true
end

--- 消耗广告领券次数（观看广告后调用，仅计广告次数，不影响免费挑战次数）
---@param dungeonKey string
---@return boolean success
function RD.ConsumeAdAttempt(dungeonKey)
    local data = RD.GetData()
    local adUsed = data.todayAdAttempts[dungeonKey] or 0
    if adUsed >= RD.AD_EXTRA_ATTEMPTS then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return false
    end
    data.todayAdAttempts[dungeonKey] = adUsed + 1
    HeroData.Save()
    return true
end

--- 获取指定副本的专属挑战券数量
---@param dungeonKey string
---@return number
function RD.GetDungeonTicketCount(dungeonKey)
    local InventoryData = require("Game.InventoryData")
    local ticketId = RD.DUNGEON_TICKET_MAP[dungeonKey]
    if not ticketId then return 0 end
    return InventoryData.GetCount(ticketId)
end

--- 获取指定副本可用的总挑战券数量（专属 + 通用）
---@param dungeonKey string
---@return number total, number specific, number generic
function RD.GetTotalTicketCount(dungeonKey)
    local InventoryData = require("Game.InventoryData")
    local specific = RD.GetDungeonTicketCount(dungeonKey)
    local generic = InventoryData.GetCount("dungeon_ticket")
    return specific + generic, specific, generic
end

--- 消耗一张挑战券（优先专属券，不足则用通用券）
---@param dungeonKey string
---@return boolean success
function RD.ConsumeDungeonTicket(dungeonKey)
    local InventoryData = require("Game.InventoryData")
    local ticketId = RD.DUNGEON_TICKET_MAP[dungeonKey]

    -- 优先消耗专属券
    if ticketId and InventoryData.GetCount(ticketId) > 0 then
        for i, slot in ipairs(InventoryData.items) do
            if slot.id == ticketId then
                slot.count = slot.count - 1
                if slot.count <= 0 then
                    table.remove(InventoryData.items, i)
                end
                break
            end
        end
        InventoryData.Save()
        return true
    end

    -- 其次消耗通用券
    if InventoryData.GetCount("dungeon_ticket") > 0 then
        for i, slot in ipairs(InventoryData.items) do
            if slot.id == "dungeon_ticket" then
                slot.count = slot.count - 1
                if slot.count <= 0 then
                    table.remove(InventoryData.items, i)
                end
                break
            end
        end
        InventoryData.Save()
        return true
    end

    Toast.Show("挑战券不足", { 255, 200, 80 })
    return false
end

--- 兼容旧接口：消耗通用门票
---@return boolean success
function RD.ConsumeTicket()
    local InventoryData = require("Game.InventoryData")
    local count = InventoryData.GetCount("dungeon_ticket")
    if count <= 0 then
        Toast.Show("门票不足", { 255, 200, 80 })
        return false
    end
    for i, slot in ipairs(InventoryData.items) do
        if slot.id == "dungeon_ticket" then
            slot.count = slot.count - 1
            if slot.count <= 0 then
                table.remove(InventoryData.items, i)
            end
            break
        end
    end
    InventoryData.Save()
    return true
end

--- 挑战结算：记录本次打到第几波、发放奖励（纯结算，次数/门票已在入场时扣除）
---@param dungeonKey string
---@param clearedWave number 本次最高通关波数 (1~20)
---@param diffLevel number|nil 难度等级（默认0）
---@return table|nil rewards
function RD.ClaimReward(dungeonKey, clearedWave, diffLevel)
    diffLevel = diffLevel or 0
    local data = RD.GetData()
    local def = RD.DUNGEON_MAP[dungeonKey]
    if not def then return nil end

    -- 更新最高纪录（按难度分别记录）
    if diffLevel == 0 then
        if clearedWave > (data.bestWave[dungeonKey] or 0) then
            data.bestWave[dungeonKey] = clearedWave
        end
    else
        if not data.bestWaveDiff then data.bestWaveDiff = {} end
        local dk = tostring(diffLevel)
        if not data.bestWaveDiff[dk] then data.bestWaveDiff[dk] = {} end
        if clearedWave > (data.bestWaveDiff[dk][dungeonKey] or 0) then
            data.bestWaveDiff[dk][dungeonKey] = clearedWave
        end
    end

    -- 全通 20 波时标记该难度通关（解锁下一难度）
    if clearedWave >= RD.TOTAL_WAVES then
        RD.MarkDifficultyCleared(diffLevel)
    end

    -- 计算并发放奖励
    local rewards = RD.CalcTotalRewards(dungeonKey, clearedWave, diffLevel)

    if def.rewardCurrency == "chest" then
        -- 宝箱副本：按类型发放宝箱
        local chests = rewards.chests or {}
        for chestId, count in pairs(chests) do
            if count > 0 then
                Currency.GrantReward({ type = "chest", id = chestId, amount = count }, "ResourceDungeon")
            end
        end
    else
        -- 货币副本：发放对应货币
        for currId, amount in pairs(rewards) do
            Currency.GrantReward({ type = "currency", id = currId, amount = amount }, "ResourceDungeon")
        end
    end

    -- 上传资源副本排行榜（取难度0的最高波次，因为高难度必须先通关普通）
    local ok, LBMod = pcall(require, "Game.LeaderboardData")
    if ok then
        local maxWave = 0
        for _, d in ipairs(RD.DUNGEON_DEFS) do
            local w = RD.GetBestWave(d.key, 0)
            if w > maxWave then maxWave = w end
        end
        if maxWave > 0 then LBMod.UploadDungeon(maxWave) end
    end

    HeroData.Save(true)  -- 副本通关奖励，立即云端保存

    print("[ResourceDungeon] " .. dungeonKey .. " cleared wave " .. clearedWave
        .. " attempts=" .. data.todayAttempts[dungeonKey])

    return rewards
end

-- ============================================================================
-- 难度预览（供 UI 显示）
-- ============================================================================

--- 获取指定波次的难度描述
---@param wave number
---@return string label, number[] color
function RD.GetWaveDifficulty(wave)
    if wave <= 3 then      return "简单",   { 120, 200, 120 }
    elseif wave <= 7 then  return "普通",   { 200, 200, 100 }
    elseif wave <= 12 then return "困难",   { 220, 160, 60 }
    elseif wave <= 17 then return "噩梦",   { 220, 80, 60 }
    else                   return "地狱",   { 200, 40, 40 }
    end
end

--- 获取指定波次的等效主线信息
---@param wave number
---@return string
function RD.GetWaveEquivInfo(wave)
    local s = RD.WaveToStage(wave)
    local gw = math.floor(s) * Config.WAVES_PER_STAGE
    return "≈主线" .. gw .. "波"
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
local SaveRegistry = require("Game.SaveRegistry")

SaveRegistry.Register("resourceDungeon", {
    group = "meta_game",
    order = 55,
    initDefault = function()
        HeroData.resourceDungeon = nil   -- GetData() 会在首次访问时惰性初始化
    end,
    serialize = function()
        local data = RD.GetData()  -- 确保已初始化
        return {
            bestWave            = data.bestWave,
            bestWaveDiff        = data.bestWaveDiff,
            todayAttempts       = data.todayAttempts,
            todayAdAttempts     = data.todayAdAttempts,
            lastResetDate       = data.lastResetDate,
            selectedDifficulty  = data.selectedDifficulty,
            clearedDifficulties = data.clearedDifficulties,
        }
    end,
    deserialize = function(saved, _saveData)
        if saved and saved.bestWave then
            HeroData.resourceDungeon = {
                bestWave            = saved.bestWave or {},
                bestWaveDiff        = saved.bestWaveDiff or {},
                todayAttempts       = saved.todayAttempts or {},
                todayAdAttempts     = saved.todayAdAttempts or {},
                lastResetDate       = saved.lastResetDate or TodayStr(),
                selectedDifficulty  = saved.selectedDifficulty or 0,
                clearedDifficulties = saved.clearedDifficulties or {},
            }
            -- 确保四种副本的 key 都存在
            for _, def in ipairs(RD.DUNGEON_DEFS) do
                local k = def.key
                if not HeroData.resourceDungeon.bestWave[k] then
                    HeroData.resourceDungeon.bestWave[k] = 0
                end
                if not HeroData.resourceDungeon.todayAttempts[k] then
                    HeroData.resourceDungeon.todayAttempts[k] = 0
                end
                if not HeroData.resourceDungeon.todayAdAttempts[k] then
                    HeroData.resourceDungeon.todayAdAttempts[k] = 0
                end
            end
            print("[ResourceDungeonData] Deserialized OK: bestWave=" ..
                (HeroData.resourceDungeon.bestWave.crystal or 0) .. "/" ..
                (HeroData.resourceDungeon.bestWave.stone or 0) .. "/" ..
                (HeroData.resourceDungeon.bestWave.iron or 0) .. "/" ..
                (HeroData.resourceDungeon.bestWave.chest or 0))
        else
            HeroData.resourceDungeon = nil  -- GetData() 惰性初始化
            print("[ResourceDungeonData] Deserialized: no saved data, will lazy-init")
        end
    end,
})

return RD
