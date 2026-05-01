-- Game/TrialTowerData.lua
-- 试练塔数据模块：进度管理、奖励计算、敌人生成

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local SaveManager = require("Game.SaveManager")
local SaveRegistry = require("Game.SaveRegistry")
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen = require("Game.WaveGenerator")


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

--- 虚空契约：每层奖励（对数曲线，与主线等价 stage = towerNum * 10）
---@param towerNum number 塔号
---@return number perFloor 每层产出
local function CalcFloorVoidPact(towerNum)
    return math.floor(2 * math.log(towerNum * 10 + 1))
end

--- 虚空契约：通塔奖励 = 10 层的总和（使塔总收益 = 2 倍等价主线）
---@param towerNum number 塔号
---@return number clearBonus 通塔奖励
local function CalcTowerClearVoidPact(towerNum)
    return CalcFloorVoidPact(towerNum) * 10
end

-- 试练券：每日补充上限、通塔奖励数量
local DAILY_TICKET_GRANT = 10
local TOWER_TICKET_REWARD = 10

local TodayStr = require("Game.DateUtil").TodayStr

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
        -- 神裔降临：试练塔挑战次数加成
        local DivineBlessDB = require("Game.DivineBlessData")
        local bonusTicket = DivineBlessDB.GetBuffValue("trial_ticket")
        local dailyMin = DAILY_TICKET_GRANT + bonusTicket
        local cur = data.tickets or 0
        if cur < dailyMin then
            data.tickets = dailyMin
            print("[TrialTower] New day, tickets topped up to " .. dailyMin .. " (was " .. cur .. ", bonus " .. bonusTicket .. ")")
        else
            print("[TrialTower] New day, tickets kept at " .. cur .. " (>= daily " .. dailyMin .. ")")
        end
        HeroData.Save()
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

    -- 发放每层奖励（统一走 GrantReward）
    Currency.GrantReward({ type = "currency", id = "devour_stone", amount = stones }, "TrialTower")
    Currency.GrantReward({ type = "currency", id = "nether_crystal", amount = gold }, "TrialTower")

    -- 每层发放虚空契约（对数曲线）
    local floorPact = CalcFloorVoidPact(towerNum)
    if floorPact > 0 then
        Currency.GrantReward({ type = "currency", id = "void_pact", amount = floorPact }, "TrialTower")
    end

    -- 标准化奖励定义（供 RewardController 展示）
    local rewardDefs = {
        { type = "currency", id = "devour_stone",   amount = stones },
        { type = "currency", id = "nether_crystal",  amount = gold },
    }
    if floorPact > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "void_pact", amount = floorPact }
    end

    local rewards = {
        floor = floor,
        towerNum = towerNum,
        floorInTower = floorInTower,
        devour_stone = stones,
        nether_crystal = gold,
        void_pact = floorPact,
        isTowerClear = false,
        rewardDefs = rewardDefs,
    }

    -- 更新进度
    data.clearedFloors = floor
    data.currentFloor = floor + 1

    -- 检查是否通塔（第 10 层）
    if floorInTower == 10 then
        local clearPact = CalcTowerClearVoidPact(towerNum)
        rewards.isTowerClear    = true
        rewards.void_pact       = rewards.void_pact + clearPact
        rewards.tower_clear_pact = clearPact
        rewards.trial_ticket    = TOWER_TICKET_REWARD
        Currency.GrantReward({ type = "currency", id = "void_pact", amount = clearPact }, "TrialTowerClear")
        TrialTowerData.AddTickets(TOWER_TICKET_REWARD)
        data.claimedTowers = towerNum
        -- 通塔额外奖励追加到 rewardDefs
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "void_pact", amount = clearPact }
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "trial_ticket", amount = TOWER_TICKET_REWARD }
        print("[TrialTower] Tower " .. towerNum .. " cleared! FloorPact +" .. floorPact .. " ClearPact +" .. clearPact .. " Tickets +" .. TOWER_TICKET_REWARD)
    end

    -- 上传试练塔排行榜
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if ok then LB.UploadTower(floor) end

    -- 劳动奖章产出
    local okLM, LMD = pcall(require, "Game.LaborMedalData")
    if okLM then LMD.EarnMedals("trial_tower") end

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
TrialTowerData.OVERLOAD_LIMIT   = 10   -- 超限上限 10 只（收紧，接近主线的 7）

--- 试练塔层号 → 等效主线关卡号
---@param floor number 全局层号
---@return number stageEquiv
function TrialTowerData.FloorToStage(floor)
    return floor * 10
end

-- HP/Speed 缩放统一使用 DungeonScaling 模块
local CalcHPScale    = DungeonScaling.CalcHPScale
local CalcSpeedScale = DungeonScaling.CalcSpeedScale

--- 试练塔词缀抽取（使用新的统一缩放系统）
--- level = floor（试练塔1层 = 主线10关，与 Config.PickAffixes 的 level 语义一致）
---@param floor number 全局层号
---@param count number 词缀数量
---@return table[] 缩放后的词缀实例列表
local function PickTowerAffixes(floor, count)
    local stageEquiv = TrialTowerData.FloorToStage(floor)
    local equivWave = stageEquiv * Config.WAVES_PER_STAGE
    local level = floor  -- 试练塔 floor 直接作为缩放等级
    return Config.PickAffixes(equivWave, count, level)
end

--- 生成试练塔指定层、指定波的敌人列表
---@param floor number 全局层号
---@param wave number  波次 (1~5)
---@return table enemies 敌人定义列表（20 只）
function TrialTowerData.GenerateWaveEnemies(floor, wave)
    local towerNum = TrialTowerData.GetTowerNum(floor)
    local floorInTower = TrialTowerData.GetFloorInTower(floor)
    local isBossFloor = true  -- 每层最后一波都出 BOSS

    -- 等效主线关卡缩放
    local stageEquiv = TrialTowerData.FloorToStage(floor)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = CalcHPScale(stageEquiv)
    local spdScale = CalcSpeedScale(stageEquiv)
    -- 波次内微调：后续波怪物略强
    local waveMult  = 1.0 + (wave - 1) * 0.05

    -- 可用角色池
    local availRoles = WaveGen.BuildRolePool(stageNum)

    -- Boss 层第 5 波出 Boss
    local hasBoss = isBossFloor and (wave == TrialTowerData.WAVE_COUNT)
    local totalCount = TrialTowerData.ENEMIES_PER_WAVE
    local normalCount = hasBoss and (totalCount - 1) or totalCount

    -- 生成普通怪（waveMult 为波次内微调）
    local enemies = WaveGen.GenerateBatch(stageNum, normalCount, hpScale * waveMult, spdScale, nil, availRoles)

    -- ======== 精英配置（前插模式） ========
    local eliteCount = 0
    if hasBoss then
        eliteCount = math.min(2 + math.floor(towerNum / 3), 4)
    else
        eliteCount = math.min(3 + math.floor(towerNum / 3), 8)
    end
    WaveGen.MarkElitesFront(enemies, eliteCount, 2.5, 1.3)

    -- Boss 层第 5 波末尾追加 Boss
    if hasBoss then
        local bossDef = WaveGen.CreateBoss(stageNum, hpScale * waveMult, spdScale, 1, 0.7)
        enemies[#enemies + 1] = bossDef
    end

    return enemies
end

--- 获取每层虚空契约奖励（对数曲线）
---@param towerNum number 塔号
---@return number
function TrialTowerData.GetFloorVoidPact(towerNum)
    return CalcFloorVoidPact(towerNum)
end

--- 获取通塔虚空契约奖励
---@param towerNum number 塔号
---@return number
function TrialTowerData.GetTowerClearVoidPact(towerNum)
    return CalcTowerClearVoidPact(towerNum)
end

--- 获取通塔试练券奖励数量
---@return number
function TrialTowerData.GetTowerTicketReward()
    return TOWER_TICKET_REWARD
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
-- 战斗配置构建（静态部分，不含 UI 回调）
-- ============================================================================

--- 构建试练塔战斗配置（纯数据，无 UI 依赖）
---@param floor number 当前全局层数
---@return table config BattleManager 所需的静态配置
function TrialTowerData.BuildBattleConfig(floor)
    local BM = require("Game.BattleManager")
    local towerNum     = TrialTowerData.GetTowerNum(floor)
    local floorInTower = TrialTowerData.GetFloorInTower(floor)
    local label        = "试练塔 " .. towerNum .. "-" .. floorInTower

    local waves = {}
    for w = 1, TrialTowerData.WAVE_COUNT do
        waves[w] = BM.BuildSpawnQueue(TrialTowerData.GenerateWaveEnemies(floor, w), 0.5)
    end

    return {
        mode             = "trial_tower",
        waves            = waves,
        totalWaves       = TrialTowerData.WAVE_COUNT,
        stageNum         = towerNum,
        label            = label,
        waveInterval     = 25,
        autoAdvanceWave  = true,
        bossTimerEnabled = true,
        overloadEnabled  = true,
        overloadLimit    = TrialTowerData.OVERLOAD_LIMIT,
        initialDarkSoul  = Config.INITIAL_DARK_SOUL,
    }
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
