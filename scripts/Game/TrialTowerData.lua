-- Game/TrialTowerData.lua
-- 试练塔数据模块：进度管理、奖励计算、敌人生成

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local SaveManager = require("Game.SaveManager")
local SaveRegistry = require("Game.SaveRegistry")

local TrialTowerData = {}

-- ============================================================================
-- 试练塔奖励配置（前 10 塔精确定义）
-- ============================================================================
local TOWER_REWARDS = {
    { stones = 5,  gold = 200 },   -- 第 1 塔
    { stones = 8,  gold = 350 },   -- 第 2 塔
    { stones = 10, gold = 450 },   -- 第 3 塔
    { stones = 12, gold = 550 },   -- 第 4 塔
    { stones = 14, gold = 650 },   -- 第 5 塔
    { stones = 16, gold = 750 },   -- 第 6 塔
    { stones = 18, gold = 850 },   -- 第 7 塔
    { stones = 20, gold = 1000 },  -- 第 8 塔
    { stones = 22, gold = 1100 },  -- 第 9 塔
    { stones = 25, gold = 1200 },  -- 第 10 塔
}

-- 每座塔通关直发招募令数量
local TOWER_CLEAR_TOKENS = 10

-- 试练券：每日补充上限、通塔奖励数量
local DAILY_TICKET_GRANT = 10
local TOWER_TICKET_REWARD = 10

---@return string  当前日期字符串 "YYYY-MM-DD"
local function TodayStr()
    return os.date("%Y-%m-%d")
end

-- ============================================================================
-- 辅助计算
-- ============================================================================

--- 全局层号 → 塔号
function TrialTowerData.GetTowerNum(floor)
    return math.ceil(floor / 10)
end

--- 全局层号 → 塔内层号 (1~10)
function TrialTowerData.GetFloorInTower(floor)
    return ((floor - 1) % 10) + 1
end

--- 获取指定塔的每层奖励
---@param towerNum number 塔号 (1-based)
---@return number stones 进阶石(噬魂石)
---@return number gold 金币(冥晶)
function TrialTowerData.GetFloorReward(towerNum)
    if towerNum <= 10 then
        local r = TOWER_REWARDS[towerNum]
        return r.stones, r.gold
    elseif towerNum <= 19 then
        local stones = 28 + (towerNum - 11) * 2
        local gold = 1400 + (towerNum - 11) * 100
        return stones, gold
    else
        local stones = 50 + (towerNum - 20) * 5
        local gold = 2500 + (towerNum - 20) * 200
        return stones, gold
    end
end

--- 获取指定塔的难度标签
function TrialTowerData.GetDifficultyLabel(towerNum)
    if towerNum <= 2 then return "入门", { 120, 200, 120 }
    elseif towerNum <= 5 then return "简单", { 100, 200, 100 }
    elseif towerNum <= 9 then return "普通", { 200, 200, 100 }
    elseif towerNum <= 10 then return "中等", { 200, 180, 80 }
    elseif towerNum <= 19 then return "困难", { 220, 130, 60 }
    else return "极难", { 220, 60, 60 }
    end
end

--- 获取指定层对应的主题（按塔号循环）
function TrialTowerData.GetTheme(floor)
    local towerNum = TrialTowerData.GetTowerNum(floor)
    local idx = ((towerNum - 1) % Config.THEME_COUNT) + 1
    return Config.THEMES[idx]
end

-- ============================================================================
-- 进度管理
-- ============================================================================

--- 获取试练塔进度数据
function TrialTowerData.GetData()
    if not HeroData.towerData then
        HeroData.towerData = {
            currentFloor  = 1,
            clearedFloors = 0,
            claimedTowers = 0,
            tickets       = DAILY_TICKET_GRANT,
            ticketDate    = TodayStr(),
        }
    end
    return HeroData.towerData
end

--- 确保每日券数据是最新的（自动补充）
function TrialTowerData.EnsureTickets()
    local data = TrialTowerData.GetData()
    local today = TodayStr()
    if data.ticketDate ~= today then
        data.ticketDate = today
        data.tickets    = DAILY_TICKET_GRANT
        HeroData.Save()
        print("[TrialTower] New day, tickets reset to " .. DAILY_TICKET_GRANT)
    end
    if data.tickets == nil then
        data.tickets = DAILY_TICKET_GRANT
    end
end

--- 获取当前剩余挑战券数量
---@return number
function TrialTowerData.GetTickets()
    TrialTowerData.EnsureTickets()
    return TrialTowerData.GetData().tickets or 0
end

--- 消耗 1 张挑战券（返回是否成功）
---@return boolean
function TrialTowerData.SpendTicket()
    TrialTowerData.EnsureTickets()
    local data = TrialTowerData.GetData()
    if (data.tickets or 0) <= 0 then return false end
    data.tickets = data.tickets - 1
    HeroData.Save()
    return true
end

--- 增加挑战券
---@param amount number
function TrialTowerData.AddTickets(amount)
    TrialTowerData.EnsureTickets()
    local data = TrialTowerData.GetData()
    data.tickets = (data.tickets or 0) + math.floor(amount)
    HeroData.Save()
    print("[TrialTower] Tickets +" .. amount .. ", total=" .. data.tickets)
end

--- 获取当前可挑战层
function TrialTowerData.GetCurrentFloor()
    return TrialTowerData.GetData().currentFloor
end

--- 获取已通关层数
function TrialTowerData.GetClearedFloors()
    return TrialTowerData.GetData().clearedFloors
end

--- 判断指定层是否已通关
function TrialTowerData.IsFloorCleared(floor)
    return floor <= TrialTowerData.GetData().clearedFloors
end

--- 判断指定层是否是当前可挑战层
function TrialTowerData.IsCurrentFloor(floor)
    return floor == TrialTowerData.GetData().currentFloor
end

--- 通关一层：发放奖励、更新进度
---@param floor number 通关的层号
---@return table rewards 奖励信息
function TrialTowerData.ClearFloor(floor)
    local data = TrialTowerData.GetData()

    -- 防止重复通关
    if floor ~= data.currentFloor then
        print("[TrialTower] Floor mismatch: expected " .. data.currentFloor .. ", got " .. floor)
        return nil
    end

    local towerNum = TrialTowerData.GetTowerNum(floor)
    local floorInTower = TrialTowerData.GetFloorInTower(floor)
    local stones, gold = TrialTowerData.GetFloorReward(towerNum)

    -- 发放每层奖励
    Currency.Add("devour_stone", stones)
    Currency.Add("nether_crystal", gold)

    local rewards = {
        floor = floor,
        towerNum = towerNum,
        floorInTower = floorInTower,
        devour_stone = stones,
        nether_crystal = gold,
        void_pact = 0,
        isTowerClear = false,
    }

    -- 更新进度
    data.clearedFloors = floor
    data.currentFloor = floor + 1

    -- 检查是否通塔（第 10 层）
    if floorInTower == 10 then
        rewards.isTowerClear    = true
        rewards.void_pact       = TOWER_CLEAR_TOKENS
        rewards.trial_ticket    = TOWER_TICKET_REWARD
        Currency.Add("void_pact", TOWER_CLEAR_TOKENS)
        TrialTowerData.AddTickets(TOWER_TICKET_REWARD)
        data.claimedTowers = towerNum
        print("[TrialTower] Tower " .. towerNum .. " cleared! Tokens +" .. TOWER_CLEAR_TOKENS .. " Tickets +" .. TOWER_TICKET_REWARD)
    end

    -- 上传试练塔排行榜
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if ok then LB.UploadTower(floor) end

    -- 保存（试炼塔通关奖励，立即云端保存）
    HeroData.Save(true)

    print("[TrialTower] Floor " .. floor .. " cleared! stones+" .. stones .. " gold+" .. gold)
    return rewards
end

-- ============================================================================
-- 敌人生成（试练塔专用）
-- 难度对标主线：每层 = 主线 10 关，即 floor N ≈ 主线第 N*10 关
-- 一塔（10层）= 主线 100 关强度
-- ============================================================================

-- 试练塔战斗参数
TrialTowerData.WAVE_COUNT       = 5    -- 每层 5 波
TrialTowerData.ENEMIES_PER_WAVE = 20   -- 每波 20 只
TrialTowerData.OVERLOAD_LIMIT   = 20   -- 超限上限 20 只

--- 试练塔层号 → 等效主线关卡号
---@param floor number 全局层号
---@return number stageEquiv
function TrialTowerData.FloorToStage(floor)
    return floor * 10
end

--- 根据等效关卡计算 HP 缩放倍率（复用主线公式）
---@param stageEquiv number
---@return number
local function CalcHPScale(stageEquiv)
    return Config.GetStageHPScale(stageEquiv)
end

--- 根据等效关卡计算速度缩放
---@param stageEquiv number
---@return number
local function CalcSpeedScale(stageEquiv)
    return math.min(1.0 + (stageEquiv - 1) * Config.STAGE_SPEED_PER_STAGE, Config.STAGE_SPEED_CAP)
end

--- 根据层号获取可用词缀池（复用主线词缀规则，用等效全局波次）
---@param floor number
---@return table[]
local function GetTowerAffixPool(floor)
    local stageEquiv = TrialTowerData.FloorToStage(floor)
    local equivWave = stageEquiv * Config.WAVES_PER_STAGE
    local pool = {}
    for _, affix in ipairs(Config.AFFIXES) do
        if affix.tier == 1 and equivWave >= Config.AFFIX_WAVE_T1 then
            pool[#pool + 1] = affix
        elseif affix.tier == 2 and equivWave >= Config.AFFIX_WAVE_T2 then
            pool[#pool + 1] = affix
        elseif affix.tier == 3 and equivWave >= Config.AFFIX_WAVE_T3 then
            pool[#pool + 1] = affix
        end
    end
    return pool
end

--- 从词缀池中随机选取
---@param pool table[]
---@param count number
---@return table[]
local function PickFromPool(pool, count)
    if #pool == 0 then return {} end
    count = math.min(count, #pool)
    -- Fisher-Yates 部分洗牌
    local copy = {}
    for i, v in ipairs(pool) do copy[i] = v end
    local result = {}
    for i = 1, count do
        local j = math.random(i, #copy)
        copy[i], copy[j] = copy[j], copy[i]
        result[#result + 1] = copy[i]
    end
    return result
end

--- 生成试练塔指定层、指定波的敌人列表
---@param floor number 全局层号
---@param wave number  波次 (1~5)
---@return table enemies 敌人定义列表（20 只）
function TrialTowerData.GenerateWaveEnemies(floor, wave)
    local towerNum = TrialTowerData.GetTowerNum(floor)
    local floorInTower = TrialTowerData.GetFloorInTower(floor)
    local isBossFloor = (floorInTower == 10)

    -- 等效主线关卡缩放
    local stageEquiv = TrialTowerData.FloorToStage(floor)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = CalcHPScale(stageEquiv)
    local spdScale = CalcSpeedScale(stageEquiv)
    -- 波次内微调：后续波怪物略强
    local waveMult  = 1.0 + (wave - 1) * 0.05

    -- 可用角色池（基于等效全局波次）
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

    -- 词缀池（精英用）
    local affixPool = GetTowerAffixPool(floor)

    local enemies = {}
    local totalCount = TrialTowerData.ENEMIES_PER_WAVE

    -- Boss 层第 5 波出 Boss
    local hasBoss = isBossFloor and (wave == TrialTowerData.WAVE_COUNT)
    local normalCount = hasBoss and (totalCount - 1) or totalCount

    -- ======== 精英配置 ========
    -- 普通层每波 2~4 只精英；Boss 层前 4 波也有精英，第 5 波(Boss波)有 1~2 只精英护卫
    local eliteCount = 0
    if isBossFloor then
        eliteCount = hasBoss and math.min(1 + math.floor(towerNum / 5), 3)
                              or math.min(2 + math.floor(towerNum / 8), 3)
    else
        -- 普通层：基础 2 只，每 5 塔 +1，上限 4
        eliteCount = math.min(2 + math.floor(towerNum / 5), 4)
    end
    local eliteAffixCount = 1
    if floor >= 30 then eliteAffixCount = 3
    elseif floor >= 15 then eliteAffixCount = 2
    end

    -- 生成普通怪
    for i = 1, normalCount do
        local roleId = availRoles[((i - 1) % #availRoles) + 1]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP  = def.baseHP * hpScale * waveMult
            def.speed   = def.speed * spdScale

            -- 标记精英（队列前段插入）
            if i <= eliteCount and #affixPool > 0 then
                def.isElite = true
                def.eliteAffixes = PickFromPool(affixPool, eliteAffixCount)
            end

            def.isDungeonEnemy = true
            enemies[#enemies + 1] = def
        end
    end

    -- Boss 层第 5 波末尾追加 Boss
    if hasBoss then
        local bossDef = Config.BuildBossDef(stageNum)
        bossDef.baseHP  = bossDef.baseHP * hpScale * waveMult
        bossDef.speed   = bossDef.speed * spdScale * 0.7  -- Boss 略慢
        bossDef.isDungeonEnemy = true
        enemies[#enemies + 1] = bossDef
    end

    return enemies
end

--- 兼容旧接口：返回全部波次的扁平敌人列表
---@param floor number
---@return table enemies
function TrialTowerData.GenerateEnemies(floor)
    local all = {}
    for w = 1, TrialTowerData.WAVE_COUNT do
        local waveEnemies = TrialTowerData.GenerateWaveEnemies(floor, w)
        for _, def in ipairs(waveEnemies) do
            all[#all + 1] = def
        end
    end
    return all
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("towerData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.towerData
    end,
    deserialize = function(saved, _saveData)
        HeroData.towerData = saved or nil
    end,
})

return TrialTowerData
