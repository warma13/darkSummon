-- Game/MineDungeonData.lua
-- 网格探索：多层体力制翻牌探索
-- 5×4 = 20 格/层，体力制翻牌，钥匙解锁下一层
-- 资源格：随机 1 种奖励 + 劳动勋章
-- 敌人格：击败后获得更多奖励
-- 钥匙格：翻开解锁下一层

local Config         = require("Game.Config")
local Currency       = require("Game.Currency")
local HeroData       = require("Game.HeroData")
local SaveRegistry   = require("Game.SaveRegistry")
local Toast          = require("Game.Toast")
local DateUtil       = require("Game.DateUtil")
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen        = require("Game.WaveGenerator")
local State          = require("Game.State")

local MDD = {}

-- ============================================================================
-- 常量
-- ============================================================================

local GRID_ROWS       = 4
local GRID_COLS       = 5
local TOTAL_CELLS     = GRID_ROWS * GRID_COLS  -- 20

-- 体力系统（5倍版：满100点，每次消耗5点，每720秒恢复1点→约2小时恢复满）
local MAX_STAMINA        = 100
local STAMINA_INTERVAL   = 720     -- 每 720 秒恢复 1 点 (100×720=72000秒≈20小时恢复满)
local FLIP_COST          = 5

-- 多层系统
local MAX_LAYER          = 10
local RESOURCE_COUNT     = 12      -- 每层 12 个资源格
local ENEMY_COUNT        = 7       -- 每层 7 个敌人格
local KEY_COUNT          = 1       -- 每层 1 个钥匙格

-- 敌人/Boss
local BOSS_HP_MULT       = 5.0
local BOSS_SPEED_FACTOR  = 0.65
local ENEMY_REWARD_MULT  = 1.8     -- 敌人奖励 = 资源格 × 1.8

-- 活动时间（与劳动奖章共享）
local START_DATE, END_DATE
do
    local ok, LDD = pcall(require, "Game.LaborDayData")
    if ok then
        START_DATE = LDD.START_DATE
        END_DATE   = LDD.END_DATE
    else
        START_DATE = "2026-04-30"
        END_DATE   = "2026-05-08"
    end
end

-- 导出常量
MDD.START_DATE       = START_DATE
MDD.END_DATE         = END_DATE
MDD.GRID_ROWS        = GRID_ROWS
MDD.GRID_COLS        = GRID_COLS
MDD.TOTAL_CELLS      = TOTAL_CELLS
MDD.MAX_STAMINA      = MAX_STAMINA
MDD.MAX_LAYER        = MAX_LAYER
MDD.FLIP_COST        = FLIP_COST
MDD.STAMINA_INTERVAL = STAMINA_INTERVAL
MDD.ENEMY_REWARD_MULT = ENEMY_REWARD_MULT
MDD.RESOURCE_COUNT   = RESOURCE_COUNT
MDD.ENEMY_COUNT      = ENEMY_COUNT
MDD.KEY_COUNT        = KEY_COUNT

-- ============================================================================
-- 层级难度配置
-- ============================================================================

--- 根据层数获取等效关卡和敌人数
---@param layer number 1-10
---@return number stageBase, number enemyCount
local function LayerConfig(layer)
    local stageBase  = 400 + (layer - 1) * 400   -- 层1=400, 层10=4000（翻倍）
    local enemyCount = 12 + layer * 2             -- 层1=14, 层10=32
    return stageBase, enemyCount
end

-- ============================================================================
-- 奖励池（加权随机）
-- ============================================================================

-- 奖励类型权重表
local REWARD_WEIGHTS = {
    { type = "idle_income",          weight = 30 },  -- 挂机1小时资源
    { type = "shadow_essence",       weight = 20 },  -- 暗影精粹
    { type = "abyss_crystal",        weight = 15 },  -- 深渊结晶
    { type = "mythic_rune_box",      weight = 5  },  -- 神话符文箱
    { type = "pale_jade",            weight = 15 },  -- 粹玉
    { type = "shadow_orb",           weight = 15 },  -- 幽影珠
}

-- 总权重
local TOTAL_WEIGHT = 0
for _, w in ipairs(REWARD_WEIGHTS) do TOTAL_WEIGHT = TOTAL_WEIGHT + w.weight end

--- 按权重随机选择奖励类型
---@return string rewardType
local function PickRewardType()
    local roll = math.random(1, TOTAL_WEIGHT)
    local acc = 0
    for _, w in ipairs(REWARD_WEIGHTS) do
        acc = acc + w.weight
        if roll <= acc then
            return w.type
        end
    end
    return "idle_income"  -- fallback
end

--- 计算玩家挂机 1 小时的基础资源
---@return number crystal, number stone, number iron
local function CalcIdleOneHour()
    local stage = (HeroData.stats and HeroData.stats.bestStage) or 1
    local crystalPerStage, stonePerStage, ironPerStage = Config.EstimateStageDrop(stage)
    -- 1小时 = 3600s / 600s * 0.5 = 3 关
    local stagesPerHour = (3600 / Config.IDLE_STAGE_SECONDS) * Config.IDLE_RATE
    local crystal = math.floor(crystalPerStage * stagesPerHour)
    local stone   = math.floor(stonePerStage * stagesPerHour)
    local iron    = math.floor(ironPerStage * stagesPerHour)
    return math.max(100, crystal), math.max(10, stone), math.max(5, iron)
end

--- 暗影精粹随机 128-1288（600+仅8%）
---@return number
local function RollShadowEssence()
    local roll = math.random(1, 100)
    if roll <= 8 then
        return math.random(600, 1288)
    elseif roll <= 30 then
        return math.random(300, 599)
    elseif roll <= 65 then
        return math.random(200, 299)
    else
        return math.random(128, 199)
    end
end

--- 深渊结晶 1-10（多=低概率）
---@return number
local function RollAbyssCrystal()
    local roll = math.random(1, 100)
    if roll <= 2 then
        return math.random(8, 10)
    elseif roll <= 8 then
        return math.random(6, 7)
    elseif roll <= 20 then
        return math.random(4, 5)
    elseif roll <= 50 then
        return math.random(2, 3)
    else
        return 1
    end
end

--- 粹玉 100-10000（多=低概率）
---@return number
local function RollPaleJade()
    local roll = math.random(1, 100)
    if roll <= 1 then
        return math.random(5000, 10000)
    elseif roll <= 5 then
        return math.random(2000, 4999)
    elseif roll <= 15 then
        return math.random(1000, 1999)
    elseif roll <= 35 then
        return math.random(500, 999)
    elseif roll <= 65 then
        return math.random(200, 499)
    else
        return math.random(100, 199)
    end
end

--- 幽影珠 1-5
---@return number
local function RollShadowOrb()
    local roll = math.random(1, 100)
    if roll <= 5 then
        return 5
    elseif roll <= 15 then
        return 4
    elseif roll <= 30 then
        return 3
    elseif roll <= 55 then
        return 2
    else
        return 1
    end
end

--- 根据奖励类型生成具体奖励列表
---@param rewardType string
---@param layer number
---@param isEnemy boolean
---@return table[] rewards { { type, id, amount }, ... }
local function GenerateRewards(rewardType, layer, isEnemy)
    local mult = isEnemy and ENEMY_REWARD_MULT or 1.0
    local rewards = {}

    if rewardType == "idle_income" then
        local crystal, stone, iron = CalcIdleOneHour()
        rewards[#rewards + 1] = { type = "currency", id = "nether_crystal", amount = math.floor(crystal * mult) }
        rewards[#rewards + 1] = { type = "currency", id = "forge_iron",     amount = math.floor(iron * mult) }
        rewards[#rewards + 1] = { type = "currency", id = "devour_stone",   amount = math.floor(stone * mult) }
    elseif rewardType == "shadow_essence" then
        local amount = RollShadowEssence()
        rewards[#rewards + 1] = { type = "currency", id = "shadow_essence", amount = math.floor(amount * mult) }
    elseif rewardType == "abyss_crystal" then
        local amount = RollAbyssCrystal()
        rewards[#rewards + 1] = { type = "currency", id = "abyss_crystal",  amount = math.floor(amount * mult) }
    elseif rewardType == "mythic_rune_box" then
        rewards[#rewards + 1] = { type = "item", id = "random_mythic_rune_box", amount = 1 }
    elseif rewardType == "pale_jade" then
        local amount = RollPaleJade()
        rewards[#rewards + 1] = { type = "currency", id = "pale_jade",      amount = math.floor(amount * mult) }
    elseif rewardType == "shadow_orb" then
        local amount = RollShadowOrb()
        rewards[#rewards + 1] = { type = "currency", id = "shadow_orb",     amount = math.floor(amount * mult) }
    end

    -- 附带劳动勋章（3-10，随层数递增）
    local medalMin = 3 + math.floor((layer - 1) * 0.5)
    local medalMax = 6 + layer
    local medalAmount = math.random(medalMin, medalMax)
    if isEnemy then medalAmount = math.floor(medalAmount * 1.5) end
    rewards[#rewards + 1] = { type = "currency", id = "labor_medal", amount = medalAmount }

    return rewards
end

--- 钥匙格奖励（少量）
---@param layer number
---@return table[] rewards
local function GenerateKeyRewards(layer)
    return {
        { type = "currency", id = "labor_medal",     amount = 5 + layer * 2 },
        { type = "currency", id = "shadow_essence",  amount = math.random(50, 150) },
    }
end

-- ============================================================================
-- 活动状态
-- ============================================================================

function MDD.IsActive()
    local today = DateUtil.TodayStr()
    return today >= START_DATE and today <= END_DATE
end

function MDD.IsExpired()
    return DateUtil.TodayStr() > END_DATE
end

-- ============================================================================
-- 体力系统
-- ============================================================================

local function EnsureData()
    if not HeroData.mineDungeonData then
        HeroData.mineDungeonData = {
            stamina          = MAX_STAMINA,
            lastStaminaTime  = os.time(),
            unlockedLayer    = 1,
            bestRevealed     = 0,
            totalRuns        = 0,
        }
    end
    -- 兼容旧存档
    if HeroData.mineDungeonData.stamina == nil then
        HeroData.mineDungeonData.stamina = MAX_STAMINA
        HeroData.mineDungeonData.lastStaminaTime = os.time()
    end
    if HeroData.mineDungeonData.unlockedLayer == nil then
        HeroData.mineDungeonData.unlockedLayer = 1
    end
end

--- 刷新体力（根据经过时间恢复）
local function RefreshStamina()
    EnsureData()
    local data = HeroData.mineDungeonData
    if data.stamina >= MAX_STAMINA then
        data.lastStaminaTime = os.time()
        return
    end

    local now = os.time()
    local elapsed = now - (data.lastStaminaTime or now)
    if elapsed <= 0 then return end

    local recovered = math.floor(elapsed / STAMINA_INTERVAL)
    if recovered > 0 then
        data.stamina = math.min(MAX_STAMINA, data.stamina + recovered)
        data.lastStaminaTime = (data.lastStaminaTime or now) + recovered * STAMINA_INTERVAL
        if data.stamina >= MAX_STAMINA then
            data.lastStaminaTime = now
        end
    end
end

--- 测试ID体力覆盖（调试用）
local TEST_STAMINA_OVERRIDES = {
    [1779057459] = 10000,
}

--- 获取当前体力
---@return number current, number max
function MDD.GetStamina()
    -- 测试ID覆盖
    local uid = clientCloud and clientCloud.userId
    if uid and TEST_STAMINA_OVERRIDES[uid] then
        return TEST_STAMINA_OVERRIDES[uid], TEST_STAMINA_OVERRIDES[uid]
    end
    RefreshStamina()
    return HeroData.mineDungeonData.stamina, MAX_STAMINA
end

--- 获取下一点恢复倒计时（秒）
---@return number secondsLeft, boolean isFull
function MDD.GetStaminaRecoveryInfo()
    -- 测试ID始终显示满
    local uid = clientCloud and clientCloud.userId
    if uid and TEST_STAMINA_OVERRIDES[uid] then
        return 0, true
    end
    RefreshStamina()
    local data = HeroData.mineDungeonData
    if data.stamina >= MAX_STAMINA then
        return 0, true
    end
    local elapsed = os.time() - (data.lastStaminaTime or os.time())
    local remaining = math.max(0, STAMINA_INTERVAL - elapsed)
    return remaining, false
end

--- 消耗体力
---@return boolean ok, string? msg
function MDD.ConsumeStamina()
    -- 测试ID无限体力
    local uid = clientCloud and clientCloud.userId
    if uid and TEST_STAMINA_OVERRIDES[uid] then
        return true
    end
    RefreshStamina()
    local data = HeroData.mineDungeonData
    if data.stamina < FLIP_COST then
        return false, "体力不足"
    end
    data.stamina = data.stamina - FLIP_COST
    if data.stamina < MAX_STAMINA and data.stamina == (MAX_STAMINA - FLIP_COST) then
        -- 刚从满状态消耗，记录恢复起始时间
        data.lastStaminaTime = os.time()
    end
    return true
end

-- ============================================================================
-- 多层系统
-- ============================================================================

--- 获取已解锁层数
---@return number
function MDD.GetUnlockedLayer()
    EnsureData()
    return math.min(HeroData.mineDungeonData.unlockedLayer or 1, MAX_LAYER)
end

--- 解锁下一层
---@return number newLayer
function MDD.UnlockNextLayer()
    EnsureData()
    local current = HeroData.mineDungeonData.unlockedLayer or 1
    if current < MAX_LAYER then
        HeroData.mineDungeonData.unlockedLayer = current + 1
        HeroData.Save(true)
        print("[MineDungeon] UnlockNextLayer: " .. (current + 1))
    end
    return HeroData.mineDungeonData.unlockedLayer
end

function MDD.GetBestRevealed()
    EnsureData()
    return HeroData.mineDungeonData.bestRevealed or 0
end

function MDD.GetTotalRuns()
    EnsureData()
    return HeroData.mineDungeonData.totalRuns or 0
end

-- ============================================================================
-- 网格生成
-- ============================================================================

--- Fisher-Yates 洗牌
local function ShuffleArray(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

--- 生成指定层的 20 格网格
---@param layer number 层数 1-10
---@return table[] cells { index, cellType, rewardType, rewards, revealed, collected, enemyReady }
function MDD.GenerateLayerGrid(layer)
    -- 1) 创建格子类型列表
    local allCells = {}

    for i = 1, RESOURCE_COUNT do
        allCells[#allCells + 1] = { cellType = "resource" }
    end
    for i = 1, ENEMY_COUNT do
        allCells[#allCells + 1] = { cellType = "enemy" }
    end
    for i = 1, KEY_COUNT do
        allCells[#allCells + 1] = { cellType = "key" }
    end

    -- 2) 随机打乱
    ShuffleArray(allCells)

    -- 3) 生成奖励并赋予索引
    for i, cell in ipairs(allCells) do
        cell.index      = i
        cell.revealed   = false
        cell.collected  = false
        cell.enemyReady = false  -- 敌人格翻开后等待玩家点击

        if cell.cellType == "resource" then
            cell.rewardType = PickRewardType()
            cell.rewards = GenerateRewards(cell.rewardType, layer, false)
        elseif cell.cellType == "enemy" then
            cell.rewardType = PickRewardType()
            cell.rewards = GenerateRewards(cell.rewardType, layer, true)
        elseif cell.cellType == "key" then
            cell.rewardType = "key"
            cell.rewards = GenerateKeyRewards(layer)
        end
    end

    return allCells
end

-- ============================================================================
-- 战斗配置构建
-- ============================================================================

--- 构建战斗配置
---@param cell table 格子数据
---@param layer number 当前层数
---@return table config
function MDD.BuildBattleConfig(cell, layer)
    local BM = require("Game.BattleManager")
    local stageBase, enemyCount = LayerConfig(layer)
    local stageNum = math.max(1, math.floor(stageBase))
    local hpScale  = DungeonScaling.CalcHPScale(stageBase)
    local spdScale = DungeonScaling.CalcSpeedScale(stageBase)
    local tags     = { isMineDungeon = true }

    -- 高层出 Boss
    local isBoss = layer >= 5
    local count  = isBoss and (enemyCount - 1) or enemyCount
    local enemies = WaveGen.GenerateBatch(stageNum, count, hpScale, spdScale, tags)

    if isBoss then
        local bossDef = WaveGen.CreateBoss(stageNum, hpScale, spdScale, BOSS_HP_MULT, BOSS_SPEED_FACTOR, tags)
        if bossDef then
            enemies[#enemies + 1] = bossDef
        end
    end

    local spawnQueue = BM.BuildSpawnQueue(enemies, 0.6)
    local label = string.format("网格探索 · 第%d层", layer)

    return {
        mode            = "mine_dungeon",
        waves           = { spawnQueue },
        totalWaves      = 1,
        label           = label,
        waveInterval    = 0,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit   = 50,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
    }
end

-- ============================================================================
-- 会话管理
-- ============================================================================

---@class MineDungeonSession
---@field layer number             当前层
---@field cells table[]            20 个格子
---@field revealedCount number     已翻开数
---@field accumulatedRewards table  累计奖励 { [currencyId] = amount }
---@field accumulatedItems table    累计道具 { [itemId] = amount }
---@field keyFound boolean         是否找到钥匙

---@type MineDungeonSession|nil
local activeSession = nil

--- 将当前会话持久化到 HeroData（每次翻格子后调用）
local function SaveSessionToData()
    if not activeSession then return end
    EnsureData()
    -- 序列化会话核心状态
    local saved = {
        layer         = activeSession.layer,
        revealedCount = activeSession.revealedCount,
        keyFound      = activeSession.keyFound,
        cells         = {},
    }
    for i, cell in ipairs(activeSession.cells) do
        saved.cells[i] = {
            index      = cell.index,
            cellType   = cell.cellType,
            rewardType = cell.rewardType,
            rewards    = cell.rewards,
            revealed   = cell.revealed,
            collected  = cell.collected,
            enemyReady = cell.enemyReady,
        }
    end
    HeroData.mineDungeonData.savedSession = saved
    HeroData.Save(true)
end

--- 从 HeroData 恢复已保存的会话
---@return MineDungeonSession|nil
local function LoadSessionFromData()
    EnsureData()
    local saved = HeroData.mineDungeonData.savedSession
    if not saved or not saved.cells or #saved.cells ~= TOTAL_CELLS then
        return nil
    end
    local session = {
        layer         = saved.layer,
        cells         = saved.cells,
        revealedCount = saved.revealedCount or 0,
        keyFound      = saved.keyFound or false,
    }
    return session
end

--- 清除持久化的会话数据
local function ClearSavedSession()
    EnsureData()
    HeroData.mineDungeonData.savedSession = nil
    HeroData.Save(true)
end

--- 创建或恢复指定层的探索会话
---@param layer number
---@return MineDungeonSession|nil session, string msg
function MDD.CreateSession(layer)
    if not MDD.IsActive() then
        return nil, "活动未开放"
    end

    layer = layer or 1
    if layer > MDD.GetUnlockedLayer() then
        return nil, "该层未解锁"
    end

    EnsureData()

    -- 尝试恢复已保存的同层会话
    local saved = LoadSessionFromData()
    if saved and saved.layer == layer then
        activeSession = saved
        print("[MineDungeon] ResumeSession layer=" .. layer
            .. " revealed=" .. saved.revealedCount .. "/" .. TOTAL_CELLS)
        return activeSession, ""
    end

    -- 没有可恢复的，创建新会话
    ClearSavedSession()
    HeroData.mineDungeonData.totalRuns = (HeroData.mineDungeonData.totalRuns or 0) + 1

    activeSession = {
        layer         = layer,
        cells         = MDD.GenerateLayerGrid(layer),
        revealedCount = 0,
        keyFound      = false,
    }

    -- 立即持久化新会话
    SaveSessionToData()

    print("[MineDungeon] CreateSession layer=" .. layer)
    return activeSession, ""
end

function MDD.GetSession()
    return activeSession
end

--- 翻开指定格子（消耗体力）
---@param index number 格子索引 1-20
---@return table|nil cell, string? errMsg
function MDD.RevealCell(index)
    if not activeSession then return nil, "无探索会话" end
    local cell = activeSession.cells[index]
    if not cell then return nil, "格子不存在" end
    if cell.revealed then return nil, "已翻开" end

    -- 消耗体力
    local ok, msg = MDD.ConsumeStamina()
    if not ok then return nil, msg end

    cell.revealed = true
    activeSession.revealedCount = activeSession.revealedCount + 1

    -- 劳动奖章产出（首次翻格子时触发，每日一次）
    local okLM, LMD = pcall(require, "Game.LaborMedalData")
    if okLM and LMD.EarnMedals then
        LMD.EarnMedals("mine_dungeon")
    end

    -- 敌人格：标记等待玩家点击
    if cell.cellType == "enemy" then
        cell.enemyReady = true
    end

    print(string.format("[MineDungeon] RevealCell #%d type=%s revealed=%d/%d stamina=%d",
        index, cell.cellType, activeSession.revealedCount, TOTAL_CELLS, MDD.GetStamina()))

    -- 持久化会话状态
    SaveSessionToData()
    return cell
end

--- 收集指定格子的奖励（即时发放到玩家账户）
---@param index number
function MDD.CollectCellRewards(index)
    if not activeSession then return end
    local cell = activeSession.cells[index]
    if not cell or cell.collected then return end

    cell.collected = true

    -- 即时发放奖励
    if cell.rewards and #cell.rewards > 0 then
        Currency.GrantRewards(cell.rewards, "MineDungeon")
    end

    -- 钥匙格
    if cell.cellType == "key" then
        activeSession.keyFound = true
        local currentLayer = activeSession.layer
        if currentLayer >= MDD.GetUnlockedLayer() and currentLayer < MAX_LAYER then
            MDD.UnlockNextLayer()
        end
    end

    -- 持久化会话状态
    SaveSessionToData()

    print(string.format("[MineDungeon] CollectCellRewards #%d type=%s (即时发放)", index, cell.cellType))
end

--- 是否全部翻完
function MDD.IsAllRevealed()
    if not activeSession then return false end
    return activeSession.revealedCount >= TOTAL_CELLS
end

--- 暂停会话（"返回"按钮）：保留持久化数据，仅释放内存引用
--- 下次进入同层时会自动恢复
function MDD.SuspendSession()
    if not activeSession then return end
    -- 确保最新状态已持久化
    SaveSessionToData()
    print(string.format("[MineDungeon] SuspendSession layer=%d revealed=%d/%d",
        activeSession.layer, activeSession.revealedCount, TOTAL_CELLS))
    activeSession = nil
end

--- 检查是否有已保存的会话
---@return number|nil savedLayer 已保存的层数，nil 表示无存档
function MDD.GetSavedSessionLayer()
    EnsureData()
    local saved = HeroData.mineDungeonData.savedSession
    if saved and saved.cells and #saved.cells == TOTAL_CELLS then
        return saved.layer
    end
    return nil
end

--- 结束会话（奖励已在翻格子时即时发放，此处只做清理）
--- 仅在"进入下一层"或"最终通关"时调用
---@param reason string "clear" | "exit"
---@return table result
function MDD.EndSession(reason)
    if not activeSession then
        return { bestRevealed = 0 }
    end

    EnsureData()
    local revealed = activeSession.revealedCount
    if revealed > (HeroData.mineDungeonData.bestRevealed or 0) then
        HeroData.mineDungeonData.bestRevealed = revealed
    end

    local result = {
        bestRevealed  = MDD.GetBestRevealed(),
        revealedCount = revealed,
        keyFound      = activeSession.keyFound,
        layer         = activeSession.layer,
        reason        = reason,
    }

    print(string.format("[MineDungeon] EndSession reason=%s layer=%d revealed=%d/%d",
        reason, activeSession.layer, revealed, TOTAL_CELLS))

    -- 清除持久化数据和内存会话
    ClearSavedSession()
    activeSession = nil
    return result
end

-- ============================================================================
-- 展示辅助
-- ============================================================================

--- 获取格子类型的展示信息
---@param cellType string "resource" | "enemy" | "key"
---@return string emoji, string label, number[] color
function MDD.GetCellDisplay(cellType)
    if cellType == "resource" then
        return "💎", "资源", { 80, 200, 255, 255 }
    elseif cellType == "key" then
        return "🔑", "钥匙", { 255, 230, 50, 255 }
    else
        return "⚔️", "敌人", { 255, 80, 60, 255 }
    end
end

--- 获取奖励类型的展示信息
---@param rewardType string
---@return string emoji, string name, number[] color
function MDD.GetRewardTypeDisplay(rewardType)
    if rewardType == "idle_income" then
        return "📦", "挂机资源", { 180, 220, 255, 255 }
    elseif rewardType == "shadow_essence" then
        return "🌑", "暗影精粹", { 180, 120, 255, 255 }
    elseif rewardType == "abyss_crystal" then
        return "💠", "深渊结晶", { 100, 180, 255, 255 }
    elseif rewardType == "mythic_rune_box" then
        return "📜", "符文箱", { 255, 200, 60, 255 }
    elseif rewardType == "pale_jade" then
        return "💚", "粹玉", { 140, 255, 180, 255 }
    elseif rewardType == "shadow_orb" then
        return "🔮", "幽影珠", { 200, 100, 255, 255 }
    elseif rewardType == "key" then
        return "🔑", "层钥匙", { 255, 230, 50, 255 }
    else
        return "❓", "未知", { 200, 200, 200, 255 }
    end
end

--- 获取层级标签
---@param layer number
---@return string label, number[] color
function MDD.GetLayerDisplay(layer)
    if layer >= 8 then
        return "第" .. layer .. "层", { 255, 80, 60, 255 }
    elseif layer >= 5 then
        return "第" .. layer .. "层", { 255, 180, 40, 255 }
    elseif layer >= 3 then
        return "第" .. layer .. "层", { 200, 200, 60, 255 }
    else
        return "第" .. layer .. "层", { 120, 220, 160, 255 }
    end
end

-- ============================================================================
-- 持久化
-- ============================================================================

SaveRegistry.Register("mineDungeonData", {
    group = "meta_game",
    order = 250,

    initDefault = function()
        HeroData.mineDungeonData = {
            stamina          = MAX_STAMINA,
            lastStaminaTime  = os.time(),
            unlockedLayer    = 1,
            bestRevealed     = 0,
            totalRuns        = 0,
        }
    end,

    serialize = function()
        return HeroData.mineDungeonData
    end,

    deserialize = function(saved)
        if saved then
            HeroData.mineDungeonData = saved
            -- 向下兼容
            if saved.bestFloor and not saved.bestRevealed then
                HeroData.mineDungeonData.bestRevealed = saved.bestFloor
            end
            if saved.stamina == nil then
                HeroData.mineDungeonData.stamina = MAX_STAMINA
                HeroData.mineDungeonData.lastStaminaTime = os.time()
            end
            if saved.unlockedLayer == nil then
                HeroData.mineDungeonData.unlockedLayer = 1
            end
        else
            HeroData.mineDungeonData = {
                stamina          = MAX_STAMINA,
                lastStaminaTime  = os.time(),
                unlockedLayer    = 1,
                bestRevealed     = 0,
                totalRuns        = 0,
            }
        end
    end,

    validate = function()
        EnsureData()
    end,
})

-- ============================================================================
-- 副本定义
-- ============================================================================

MDD.DUNGEON_DEF = {
    key         = "mine_dungeon",
    name        = "网格探索",
    emoji       = "⛏️",
    desc        = "翻开格子，发现宝藏或迎战敌人",
    accentColor = { 200, 160, 60, 255 },
}

return MDD
