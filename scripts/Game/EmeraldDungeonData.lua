-- Game/EmeraldDungeonData.lua
-- 翠影秘境·自然试炼 — 限时活动副本数据与战斗逻辑
-- 30天限时活动，6级难度，秘境券入场（每日赠2张+看广告领4张），掉落翠影凭证
-- 特殊机制：荆棘禁锢(束缚高星塔)、沉寂领域(全场沉默)、自然衰竭(叠加削弱ATK/SPD)
-- 翎嫣专属副本：三技能分别被翎嫣的翠意庇护(免疫束缚+沉默)和自然馈赠(buff对冲)克制

local Config   = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local State    = require("Game.State")
local Toast    = require("Game.Toast")
local SaveRegistry = require("Game.SaveRegistry")
local TodayKey = require("Game.DateUtil").TodayKey
local DungeonScaling = require("Game.DungeonScaling")

local Emerald = {}

-- ============================================================================
-- 常量
-- ============================================================================

--- 活动持续天数
local EVENT_DURATION_DAYS = 30

--- 每日赠送秘境券数量（免费挑战次数）
local DAILY_FREE_TICKETS = 2
--- 每次看广告获得秘境券数量
local AD_TICKET_REWARD = 1
--- 每日广告领券上限（免费次数的两倍）
local DAILY_AD_LIMIT = 4

--- 北京时间偏移 (UTC+8)
local CST_OFFSET = 8 * 3600

--- 活动解锁时间：今天 0 点北京时间（纯算术，不依赖服务器时区）
local function calcUnlockTime()
    local now = os.time()
    local beijingNow = now + CST_OFFSET
    local todayMidnight = now - (beijingNow % 86400)
    return todayMidnight
end
local EVENT_UNLOCK_TIME = calcUnlockTime()

--- BOSS HP 倍率
local BOSS_HP_MULT = 6.0

-- ============================================================================
-- 词缀难度选项（BOSS 额外词缀 → 奖励加成）
-- ============================================================================

--- 4 档词缀难度：词缀数 → 奖励加成百分比
Emerald.AFFIX_OPTIONS = {
    { affixCount = 0, bonusPct = 0,  label = "无词缀" },
    { affixCount = 1, bonusPct = 10, label = "1词缀" },
    { affixCount = 3, bonusPct = 20, label = "3词缀" },
    { affixCount = 7, bonusPct = 30, label = "7词缀" },
}

--- 每个 tier 的当前词缀选择索引（1-based，运行时状态不存档）
local _affixChoice = {}

--- 翠影凭证货币 ID
local CURRENCY_ID = "emerald_token"

-- ============================================================================
-- 6 级难度定义（映射到主线关卡等效）
-- ============================================================================

--- 主线解锁门槛（仅第一关需要）
local UNLOCK_MAIN_STAGE = 10

Emerald.DIFFICULTIES = {
    { id = "tier1", name = "翠影·初试", tier = 1, stageEquiv = 10,   waves = 15, enemiesPerWave = 20, tokenReward = 180,  color = { 120, 200, 120 } },
    { id = "tier2", name = "翠影·磨砺", tier = 2, stageEquiv = 50,   waves = 15, enemiesPerWave = 20, tokenReward = 280,  color = { 100, 180, 220 } },
    { id = "tier3", name = "翠影·试炼", tier = 3, stageEquiv = 100,  waves = 15, enemiesPerWave = 22, tokenReward = 400,  color = { 200, 180, 60 } },
    { id = "tier4", name = "翠影·淬炼", tier = 4, stageEquiv = 500,  waves = 20, enemiesPerWave = 25, tokenReward = 560,  color = { 220, 140, 60 } },
    { id = "tier5", name = "翠影·极境", tier = 5, stageEquiv = 1000, waves = 20, enemiesPerWave = 25, tokenReward = 720,  color = { 220, 80, 80 } },
    { id = "tier6", name = "翠影·天罚", tier = 6, stageEquiv = 2000, waves = 20, enemiesPerWave = 28, tokenReward = 950,  color = { 200, 60, 255 } },
}

--- 按 ID 查难度
Emerald.DIFFICULTY_MAP = {}
for _, d in ipairs(Emerald.DIFFICULTIES) do
    Emerald.DIFFICULTY_MAP[d.id] = d
end

-- ============================================================================
-- 部分通关奖励比例
-- ============================================================================

--- 根据通关波次比例计算凭证奖励比例
---@param clearedWaves number 实际通关波数
---@param totalWaves number 总波数
---@return number ratio 0.0 / 0.3 / 0.6 / 1.0
local function CalcRewardRatio(clearedWaves, totalWaves)
    local pct = clearedWaves / totalWaves
    if pct >= 1.0 then return 1.0 end
    if pct >= 0.75 then return 0.6 end
    if pct >= 0.50 then return 0.3 end
    return 0.0
end

-- ============================================================================
-- 词缀难度选择接口
-- ============================================================================

--- 获取指定 tier 当前选择的词缀档位索引（1-based，自动钳位到已解锁范围）
---@param tierId string e.g. "tier1"
---@return number index 1-4
function Emerald.GetAffixChoice(tierId)
    local choice = _affixChoice[tierId] or 1
    -- 钳位：不能选超过已解锁范围的档位
    local maxIdx = Emerald.GetMaxUnlockedAffix(tierId)
    if maxIdx > 0 and choice > maxIdx then
        choice = maxIdx
        _affixChoice[tierId] = choice
    end
    return choice
end

--- 设置指定 tier 的词缀档位
---@param tierId string
---@param index number 1-4
function Emerald.SetAffixChoice(tierId, index)
    _affixChoice[tierId] = math.max(1, math.min(#Emerald.AFFIX_OPTIONS, index))
end

--- 切换到下一个词缀档位（循环）
---@param tierId string
---@return number newIndex
function Emerald.CycleAffixChoice(tierId)
    local cur = Emerald.GetAffixChoice(tierId)
    local next = (cur % #Emerald.AFFIX_OPTIONS) + 1
    Emerald.SetAffixChoice(tierId, next)
    return next
end

--- 获取指定 tier 当前词缀选项数据
---@param tierId string
---@return table { affixCount, bonusPct, label }
function Emerald.GetAffixOption(tierId)
    local idx = Emerald.GetAffixChoice(tierId)
    return Emerald.AFFIX_OPTIONS[idx]
end

-- ============================================================================
-- 副本定义（供 DungeonUI 使用）
-- ============================================================================

Emerald.DUNGEON_DEF = {
    key         = "emerald_dungeon",
    name        = "翠影秘境",
    emoji       = "🌿",
    desc        = "限时活动：通关获取翠影凭证，兑换翎嫣招募券与稀有资源",
    accentColor = { 60, 180, 100, 255 },
    cover       = nil, -- 使用默认样式
}

-- ============================================================================
-- 特殊机制数据
-- ============================================================================

--- 荆棘禁锢参数（按星级权重选塔，施加束缚）
--- 翎嫣克制：翠意庇护免疫束缚
Emerald.THORN_SHACKLE = {
    { tier = 1, interval = 30, targets = 1, duration = 2.0 },
    { tier = 2, interval = 26, targets = 1, duration = 2.5 },
    { tier = 3, interval = 22, targets = 2, duration = 3.0 },
    { tier = 4, interval = 18, targets = 2, duration = 3.5 },
    { tier = 5, interval = 15, targets = 2, duration = 4.0 },
    { tier = 6, interval = 12, targets = 3, duration = 4.5 },
}

--- 沉寂领域参数（全场沉默）
--- 翎嫣克制：翠意庇护免疫沉默
Emerald.SILENCE_DOMAIN = {
    { tier = 1, interval = 45, duration = 1.5 },
    { tier = 2, interval = 40, duration = 2.0 },
    { tier = 3, interval = 35, duration = 2.5 },
    { tier = 4, interval = 30, duration = 3.0 },
    { tier = 5, interval = 25, duration = 3.5 },
    { tier = 6, interval = 20, duration = 4.0 },
}

--- 自然衰竭参数（攻击/攻速削弱）
--- 翎嫣克制：自然馈赠的攻击/攻速buff直接对冲
---
--- 配置字段说明：
---   persistent : boolean  -- true=本局持久（跨波次不清除），false=有持续时间
---   duration   : number   -- 非持久时每次施加的持续秒数（persistent=true 时忽略）
---   stackable  : boolean  -- true=多次施放叠加，false=只施加一次（后续刷新持续时间）
---   stackMode  : string   -- 叠加算法：
---                            "additive"  = 每次累加 atkDebuff/spdDebuff（直到 cap）
---                            "max"       = 取当前值与新值中较大者
---                            "refresh"   = 不叠加数值，仅刷新持续时间
Emerald.NATURE_DECAY = {
    { tier = 1, interval = 40, atkDebuff = 0.05, spdDebuff = 0.03, atkCap = 0.20, spdCap = 0.12,
      persistent = true, stackable = true, stackMode = "additive" },
    { tier = 2, interval = 35, atkDebuff = 0.07, spdDebuff = 0.05, atkCap = 0.28, spdCap = 0.18,
      persistent = true, stackable = true, stackMode = "additive" },
    { tier = 3, interval = 30, atkDebuff = 0.10, spdDebuff = 0.07, atkCap = 0.35, spdCap = 0.22,
      persistent = true, stackable = true, stackMode = "additive" },
    { tier = 4, interval = 25, atkDebuff = 0.12, spdDebuff = 0.09, atkCap = 0.42, spdCap = 0.27,
      persistent = true, stackable = true, stackMode = "additive" },
    { tier = 5, interval = 22, atkDebuff = 0.14, spdDebuff = 0.11, atkCap = 0.50, spdCap = 0.30,
      persistent = true, stackable = true, stackMode = "additive" },
    { tier = 6, interval = 18, atkDebuff = 0.16, spdDebuff = 0.13, atkCap = 0.60, spdCap = 0.35,
      persistent = true, stackable = true, stackMode = "additive" },
}

--- 获取指定难度等级的特殊机制参数
---@param tier number 1-6
---@return table shackle, table silence, table decay
function Emerald.GetMechanics(tier)
    tier = math.max(1, math.min(6, tier))
    return Emerald.THORN_SHACKLE[tier], Emerald.SILENCE_DOMAIN[tier], Emerald.NATURE_DECAY[tier]
end

-- ============================================================================
-- 活动时间管理
-- ============================================================================

--- 获取活动数据（懒初始化）
---@return table
local function getData()
    if not HeroData.emeraldDungeon then
        HeroData.emeraldDungeon = {
            startTime = 0,    -- 活动开始时间戳
            active = false,   -- 是否激活
            day = "",         -- 今日日期 key
            tickets = 0,      -- 当前秘境券数量
            adWatched = 0,    -- 今日已看广告次数
            totalRuns = 0,    -- 活动期间总挑战次数
            bestWaves = {},   -- 各难度最佳通关波数 { tier1=15, tier2=10, ... }
            affixCleared = {},-- 各难度已通关的最高词缀档位索引 { tier1=1, tier2=2, ... }
            tokenEarned = 0,  -- 累计获取凭证数
        }
    end
    return HeroData.emeraldDungeon
end

--- 检查词缀选择行是否应显示（该 tier 已首次通关）
---@param tierId string
---@return boolean
function Emerald.IsAffixRowVisible(tierId)
    local diff = Emerald.DIFFICULTY_MAP[tierId]
    if not diff then return false end
    local data = getData()
    local best = (data.bestWaves and data.bestWaves[tierId]) or 0
    return best >= diff.waves  -- 全波通关才显示词缀行
end

--- 检查指定词缀档位是否已解锁
--- 档位 1（0词缀）：首次通关即解锁
--- 档位 N（N>1）：需通关档位 N-1 才解锁
---@param tierId string
---@param affixIndex number 1-based
---@return boolean
function Emerald.IsAffixOptionUnlocked(tierId, affixIndex)
    if affixIndex <= 1 then
        -- 档位1（无词缀）：只要该行可见即已解锁
        return Emerald.IsAffixRowVisible(tierId)
    end
    -- 档位 N：需要已通关档位 N-1
    local data = getData()
    if not data.affixCleared then return false end
    local cleared = data.affixCleared[tierId] or 0
    return cleared >= (affixIndex - 1)
end

--- 获取该 tier 已解锁的最高词缀档位索引
---@param tierId string
---@return number maxIndex
function Emerald.GetMaxUnlockedAffix(tierId)
    if not Emerald.IsAffixRowVisible(tierId) then return 0 end
    local data = getData()
    local cleared = (data.affixCleared and data.affixCleared[tierId]) or 0
    -- 行可见说明已用0词缀通关过，基线至少为1（兼容旧存档）
    if cleared < 1 then cleared = 1 end
    -- cleared=1 → 档位1,2可用; cleared=2 → 档位1,2,3可用; ...
    return math.min(cleared + 1, #Emerald.AFFIX_OPTIONS)
end

--- 获取今日日期字符串
---@return string
local function getTodayKey()
    return TodayKey()
end

--- 确保每日重置
local function ensureDailyReset()
    local data = getData()
    local today = getTodayKey()
    if data.day ~= today then
        data.day = today
        data.adWatched = 0
        data.todayChallenged = {}  -- 每日重置已挑战难度记录
        -- 每日赠送秘境券
        data.tickets = (data.tickets or 0) + DAILY_FREE_TICKETS
    end
    -- 兼容旧存档：确保 todayChallenged 字段存在
    if not data.todayChallenged then
        data.todayChallenged = {}
    end
end

--- 激活活动（首次进入或管理员触发）
function Emerald.ActivateEvent()
    local data = getData()
    if not data.active then
        data.startTime = os.time()
        data.active = true
        data.day = getTodayKey()
        data.tickets = DAILY_FREE_TICKETS
        data.adWatched = 0
        data.totalRuns = 0
        data.bestWaves = {}
        data.tokenEarned = 0
        print("[EmeraldDungeon] Event activated at " .. os.date("%Y-%m-%d %H:%M:%S", data.startTime))
    end
end

--- 检查活动是否已到解锁时间
---@return boolean
function Emerald.IsTimeUnlocked()
    return os.time() >= EVENT_UNLOCK_TIME
end

--- 获取距离解锁的剩余秒数
---@return number 剩余秒数（已解锁则返回 0）
function Emerald.GetUnlockRemainingSec()
    return math.max(0, EVENT_UNLOCK_TIME - os.time())
end

--- 获取解锁时间的可读字符串
---@return string
function Emerald.GetUnlockTimeStr()
    return os.date("!%m月%d日 %H:%M", EVENT_UNLOCK_TIME + CST_OFFSET)
end

--- 检查活动是否在有效期内
---@return boolean
function Emerald.IsActive()
    -- 未到解锁时间，活动不可用
    if not Emerald.IsTimeUnlocked() then
        return false
    end
    local data = getData()
    if not data.active then
        -- 到达解锁时间后自动激活
        Emerald.ActivateEvent()
    end
    -- 检查是否超过活动持续天数
    local elapsed = os.time() - data.startTime
    if elapsed > EVENT_DURATION_DAYS * 86400 then
        return false
    end
    return true
end

--- 获取活动剩余天数
---@return number
function Emerald.GetRemainingDays()
    local data = getData()
    if not data.active then return EVENT_DURATION_DAYS end
    local elapsed = os.time() - data.startTime
    local remaining = EVENT_DURATION_DAYS - math.floor(elapsed / 86400)
    return math.max(0, remaining)
end

-- ============================================================================
-- 解锁检测
-- ============================================================================

--- ⚠️ 测试开关：true = 全部难度解锁，正式上线前改回 false
local DEBUG_UNLOCK_ALL = false

--- 检查指定难度是否已解锁
--- tier1: 主线通关第 UNLOCK_MAIN_STAGE 关
--- tier2+: 通关前一级难度（bestWaves >= totalWaves）
---@param difficultyId string
---@return boolean
function Emerald.IsDifficultyUnlocked(difficultyId)
    if DEBUG_UNLOCK_ALL then return true end

    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return false end

    -- 第一关：主线进度门槛
    if diff.tier == 1 then
        local currentStage = State.currentStage or 1
        return currentStage >= UNLOCK_MAIN_STAGE
    end

    -- 后续关：需通关前一级
    local prevId = "tier" .. (diff.tier - 1)
    local prevDiff = Emerald.DIFFICULTY_MAP[prevId]
    if not prevDiff then return false end
    local data = getData()
    local bestWaves = (data.bestWaves and data.bestWaves[prevId]) or 0
    return bestWaves >= prevDiff.waves  -- 全部波次通关
end

--- 获取解锁提示文本
---@param difficultyId string
---@return string
function Emerald.GetUnlockHint(difficultyId)
    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return "" end
    if diff.tier == 1 then
        return "通关主线第" .. UNLOCK_MAIN_STAGE .. "关解锁"
    end
    local prevId = "tier" .. (diff.tier - 1)
    local prevDiff = Emerald.DIFFICULTY_MAP[prevId]
    if prevDiff then
        return "通关「" .. prevDiff.name .. "」解锁"
    end
    return ""
end

--- 检查副本整体是否已解锁（最低难度的要求）
---@return boolean
function Emerald.IsUnlocked()
    return true -- 翠影秘境对所有玩家开放，但高难度需要通关进度
end

-- ============================================================================
-- 秘境券管理
-- ============================================================================

--- 获取当前秘境券数量
---@return number
function Emerald.GetTickets()
    ensureDailyReset()
    local data = getData()
    return data.tickets or 0
end

--- 消耗一张秘境券（入场）
---@return boolean success
function Emerald.ConsumeTicket()
    ensureDailyReset()
    local data = getData()
    if (data.tickets or 0) >= 1 then
        data.tickets = data.tickets - 1
        return true
    end
    return false
end

--- 看广告领取秘境券
---@return boolean success, string msg
function Emerald.WatchAdForTicket()
    ensureDailyReset()
    local data = getData()
    if (data.adWatched or 0) >= DAILY_AD_LIMIT then
        return false, "今日广告次数已用完"
    end
    data.adWatched = (data.adWatched or 0) + 1
    data.tickets = (data.tickets or 0) + AD_TICKET_REWARD
    return true, "获得 " .. AD_TICKET_REWARD .. " 张秘境券"
end

--- 增加秘境券（管理员/兑换码用）
---@param amount number
function Emerald.AddTickets(amount)
    ensureDailyReset()
    local data = getData()
    data.tickets = (data.tickets or 0) + amount
end

--- 获取今日剩余广告次数
---@return number
function Emerald.GetAdRemaining()
    ensureDailyReset()
    local data = getData()
    return math.max(0, DAILY_AD_LIMIT - (data.adWatched or 0))
end

-- ============================================================================
-- 难度缩放
-- ============================================================================

--- 将副本波次映射到等效关卡
---@param wave number
---@param difficultyId string
---@return number stageEquiv
function Emerald.WaveToStage(wave, difficultyId)
    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return 1 end

    -- 波次内线性递增：wave 1 = 基础关卡×0.8, 最后一波 = 基础关卡×1.2
    local t = (wave - 1) / math.max(1, diff.waves - 1)
    local stageEquiv = diff.stageEquiv * (0.8 + 0.4 * t)
    return math.max(1, math.floor(stageEquiv))
end

-- HP/Speed 缩放统一使用 DungeonScaling 模块
Emerald.CalcHPScale    = DungeonScaling.CalcHPScale
Emerald.CalcSpeedScale = DungeonScaling.CalcSpeedScale

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

--- 获取波次类型（BOSS 已驻场，波次只有普通/精英）
---@param wave number
---@param totalWaves number
---@return string "normal"/"elite"
function Emerald.GetWaveType(wave, totalWaves)
    if wave % 5 == 0 then return "elite" end
    return "normal"
end

--- 获取波次标签
---@param wave number
---@param totalWaves number
---@return string label, number[] color
function Emerald.GetWaveLabel(wave, totalWaves)
    local wtype = Emerald.GetWaveType(wave, totalWaves)
    if wtype == "elite" then
        return "精英", { 255, 180, 40 }
    else
        return "普通", { 160, 160, 160 }
    end
end

--- 生成指定波次的小怪列表（BOSS 不在波次中，由 GenerateBoss 单独生成）
--- 使用森林(forest)和虚空(void)主题
---@param wave number
---@param difficultyId string
---@return table[] enemies
function Emerald.GenerateWaveEnemies(wave, difficultyId)
    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return {} end

    local stageEquiv = Emerald.WaveToStage(wave, difficultyId)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = Emerald.CalcHPScale(stageEquiv)
    local spdScale = Emerald.CalcSpeedScale(stageEquiv)
    local waveType = Emerald.GetWaveType(wave, diff.waves)

    -- 使用森林(3)和虚空(5)主题交替
    local themeIdx = (wave % 2 == 1) and 3 or 5
    if themeIdx > Config.THEME_COUNT then themeIdx = Config.THEME_COUNT end

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

    -- 生成普通怪
    for i = 1, diff.enemiesPerWave do
        local roleId = availRoles[((i - 1) % #availRoles) + 1]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale
            def.speed = def.speed * spdScale
            def.isDungeonEnemy = true
            def.isEmeraldDungeon = true
            def.themeIdx = themeIdx
            enemies[#enemies + 1] = def
        end
    end

    -- 精英波：强化最后2-3个怪
    if waveType == "elite" then
        local eliteCount = diff.tier >= 4 and 3 or 2
        for i = math.max(1, #enemies - eliteCount + 1), #enemies do
            if enemies[i] then
                enemies[i].baseHP = enemies[i].baseHP * 2.5
                enemies[i].speed = enemies[i].speed * 0.8
                enemies[i].isElite = true
            end
        end
    end

    return enemies
end

--- 生成驻场 BOSS 定义（开局出场，全程驻场，携带三技能）
---@param difficultyId string
---@param extraAffixCount? number 额外词缀数量（来自词缀难度选择），默认 0
---@return table bossDef
function Emerald.GenerateBoss(difficultyId, extraAffixCount)
    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return nil end

    local stageEquiv = diff.stageEquiv
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = Emerald.CalcHPScale(stageEquiv)
    local spdScale = Emerald.CalcSpeedScale(stageEquiv)

    local themeIdx = 3 -- 森林主题

    local bossDef = Config.BuildBossDef(stageNum)
    if not bossDef then return nil end

    bossDef.baseHP = bossDef.baseHP * hpScale * BOSS_HP_MULT
    bossDef.speed = bossDef.speed * spdScale * 0.6
    bossDef.id = "emerald_guardian"
    bossDef.name = "翠影守护者"
    bossDef.isDungeonEnemy = true
    bossDef.isDungeonBoss = true
    bossDef.isEmeraldDungeon = true
    bossDef.persistentBoss = true   -- 标记为驻场 BOSS
    bossDef.themeIdx = themeIdx
    bossDef.spriteSheet = "emerald_boss"  -- 使用翠影秘境专属精灵图

    -- 携带三技能（荆棘禁锢 + 沉寂领域 + 自然衰竭）
    local shackle, silence, decay = Emerald.GetMechanics(diff.tier)
    bossDef.bossSkills = {
        shackle = shackle,
        silence = silence,
        decay   = decay,
    }

    -- 额外词缀（来自词缀难度选择）
    extraAffixCount = extraAffixCount or 0
    if extraAffixCount > 0 then
        local level = math.max(1, math.floor(stageNum / 10))
        local globalWave = stageNum * Config.WAVES_PER_STAGE
        local affixes = Config.PickAffixes(globalWave, extraAffixCount, level)
        bossDef.affixes = affixes
    end

    return bossDef
end

-- ============================================================================
-- 奖励计算
-- ============================================================================

--- 计算通关奖励（翠影凭证）
---@param clearedWaves number 实际通过波数
---@param difficultyId string
---@param affixBonusPct? number 词缀加成百分比（0/10/20/30），默认 0
---@return number tokens 获得的翠影凭证
function Emerald.CalcTokenReward(clearedWaves, difficultyId, affixBonusPct)
    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return 0 end

    local ratio = CalcRewardRatio(clearedWaves, diff.waves)
    local bonus = 1 + (affixBonusPct or 0) / 100
    return math.floor(diff.tokenReward * ratio * bonus)
end

--- 获取部分通关奖励描述
---@param difficultyId string
---@return table[] 各档位奖励 { pct, ratio, tokens }
function Emerald.GetRewardTiers(difficultyId)
    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then return {} end
    return {
        { pct = "< 50%",   ratio = 0,   tokens = 0 },
        { pct = "≥ 50%",   ratio = 0.3, tokens = math.floor(diff.tokenReward * 0.3) },
        { pct = "≥ 75%",   ratio = 0.6, tokens = math.floor(diff.tokenReward * 0.6) },
        { pct = "100%",    ratio = 1.0, tokens = diff.tokenReward },
    }
end

-- ============================================================================
-- 副本状态（供战斗循环使用）
-- ============================================================================

--- 创建一次副本实例
---@param difficultyId string
---@return table|nil session
function Emerald.CreateSession(difficultyId)
    if not Emerald.IsActive() then
        Toast.Show("活动已结束", { 255, 200, 80 })
        return nil
    end

    local diff = Emerald.DIFFICULTY_MAP[difficultyId]
    if not diff then
        Toast.Show("未知难度", { 255, 100, 100 })
        return nil
    end

    if not Emerald.IsDifficultyUnlocked(difficultyId) then
        Toast.Show(Emerald.GetUnlockHint(difficultyId), { 255, 200, 80 })
        return nil
    end

    -- 记录当前词缀选择
    local affixOpt = Emerald.GetAffixOption(difficultyId)

    return {
        difficultyId = difficultyId,
        difficulty = diff,
        currentWave = 0,
        totalWaves = diff.waves,
        enemiesPerWave = diff.enemiesPerWave,
        cleared = false,
        tokenReward = 0,
        affixCount = affixOpt.affixCount,
        affixBonusPct = affixOpt.bonusPct,
    }
end

--- 推进到下一波
---@param session table
---@return table|nil enemies
function Emerald.AdvanceWave(session)
    if session.currentWave >= session.totalWaves then
        session.cleared = true
        return nil
    end
    session.currentWave = session.currentWave + 1
    return Emerald.GenerateWaveEnemies(session.currentWave, session.difficultyId)
end

--- 标记当波完成
---@param session table
function Emerald.CompleteWave(session)
    if session.currentWave >= session.totalWaves then
        session.cleared = true
    end
end

--- 结束副本，发放奖励
---@param session table
---@return table result
function Emerald.EndSession(session)
    local tokens = Emerald.CalcTokenReward(session.currentWave, session.difficultyId, session.affixBonusPct)
    session.tokenReward = tokens

    -- 发放翠影凭证
    if tokens > 0 then
        Currency.GrantReward({ type = "currency", id = CURRENCY_ID, amount = tokens }, "EmeraldDungeon")
    end

    -- 更新统计
    local data = getData()
    data.totalRuns = data.totalRuns + 1
    data.tokenEarned = data.tokenEarned + tokens

    -- 标记今日已挑战该难度（扫荡前提）
    ensureDailyReset()
    if not data.todayChallenged then data.todayChallenged = {} end
    data.todayChallenged[session.difficultyId] = true

    -- 更新最佳记录
    local bestKey = session.difficultyId
    local prevBest = data.bestWaves[bestKey] or 0
    local isFirstClear = session.cleared and prevBest < session.totalWaves
    if session.currentWave > prevBest then
        data.bestWaves[bestKey] = session.currentWave
    end

    -- 记录词缀通关进度（全波通关时，更新该 tier 已通关的最高词缀档位）
    if session.cleared then
        if not data.affixCleared then data.affixCleared = {} end
        -- 找出本次使用的词缀档位索引
        local usedAffixIdx = 1
        for i, opt in ipairs(Emerald.AFFIX_OPTIONS) do
            if opt.affixCount == (session.affixCount or 0) then
                usedAffixIdx = i
                break
            end
        end
        local prev = data.affixCleared[session.difficultyId] or 0
        if usedAffixIdx > prev then
            data.affixCleared[session.difficultyId] = usedAffixIdx
        end
    end

    -- 首次通关奖励：赠送1张秘境券
    local firstClearBonus = false
    if isFirstClear then
        data.tickets = (data.tickets or 0) + 1
        firstClearBonus = true
        print("[EmeraldDungeon] First clear " .. bestKey .. " → +1 ticket bonus")
    end

    -- 上报排行榜
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if ok then
        LB.UploadEmeraldToken(data.tokenEarned)
        local bestTier, bestWaveForLB = Emerald.GetBestProgress()
        if bestTier > 0 then
            LB.UploadEmeraldProgress(bestTier, bestWaveForLB)
        end
    end

    -- 保存
    HeroData.Save(true)

    local diff = session.difficulty
    local ratio = CalcRewardRatio(session.currentWave, session.totalWaves)

    -- 构建 rewardDefs 供 RewardController 统一展示
    local rewardDefs = {}
    if tokens > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = CURRENCY_ID, amount = tokens }
    end
    if firstClearBonus then
        rewardDefs[#rewardDefs + 1] = {
            type = "item", id = "emerald_ticket", amount = 1,
            displayName = "秘境券（首次通关）", displayIcon = "image/icon_ticket.png",
        }
    end

    local result = {
        tokens = tokens,
        clearedWave = session.currentWave,
        totalWaves = session.totalWaves,
        difficultyId = session.difficultyId,
        difficultyName = diff.name,
        ratio = ratio,
        isFullClear = session.cleared,
        firstClearBonus = firstClearBonus,
        rewardDefs = rewardDefs,
    }

    print(string.format("[EmeraldDungeon] EndSession wave %d/%d (diff=%s) tokens=%d ratio=%.0f%%",
        session.currentWave, session.totalWaves, session.difficultyId,
        tokens, ratio * 100))

    return result
end

-- ============================================================================
-- 统计查询
-- ============================================================================

--- 获取指定难度最佳通关波数
---@param difficultyId string
---@return number
function Emerald.GetBestWaves(difficultyId)
    local data = getData()
    return data.bestWaves[difficultyId] or 0
end

--- 获取活动期间累计获取凭证
---@return number
function Emerald.GetTotalTokenEarned()
    local data = getData()
    return data.tokenEarned or 0
end

--- 获取活动期间总挑战次数
---@return number
function Emerald.GetTotalRuns()
    local data = getData()
    return data.totalRuns or 0
end

--- 获取当前翠影凭证余额
---@return number
function Emerald.GetTokenBalance()
    return Currency.Get(CURRENCY_ID)
end

-- ============================================================================
-- 扫荡系统
-- ============================================================================

--- 检查今日是否已挑战过指定难度（扫荡前提条件）
---@param difficultyId string
---@return boolean
function Emerald.HasDailyChallenged(difficultyId)
    ensureDailyReset()
    local data = getData()
    if not data.todayChallenged then return false end
    return data.todayChallenged[difficultyId] == true
end

--- 检查指定难度是否可扫荡
--- 条件：活动中 + 已解锁 + 今日已挑战 + 有最佳记录 + 有秘境券
---@param difficultyId string
---@return boolean canSweep, string reason
function Emerald.CanSweep(difficultyId)
    if not Emerald.IsActive() then
        return false, "活动已结束"
    end
    if not Emerald.IsDifficultyUnlocked(difficultyId) then
        return false, "未解锁"
    end
    if not Emerald.HasDailyChallenged(difficultyId) then
        return false, "今日需先挑战一次"
    end
    local bestWaves = Emerald.GetBestWaves(difficultyId)
    if bestWaves <= 0 then
        return false, "需要先挑战一次"
    end
    if Emerald.GetTickets() <= 0 then
        return false, "秘境券不足"
    end
    return true, ""
end

--- 执行一次扫荡（消耗秘境券，按最佳记录发放奖励）
---@param difficultyId string
---@param affixBonusPct? number 词缀加成百分比，默认 0
---@return boolean success, number tokens
function Emerald.DoSweep(difficultyId, affixBonusPct)
    local canSweep, reason = Emerald.CanSweep(difficultyId)
    if not canSweep then
        Toast.Show(reason, { 255, 100, 100 })
        return false, 0
    end

    if not Emerald.ConsumeTicket() then
        Toast.Show("秘境券不足", { 255, 100, 100 })
        return false, 0
    end

    local bestWaves = Emerald.GetBestWaves(difficultyId)
    local tokens = Emerald.CalcTokenReward(bestWaves, difficultyId, affixBonusPct or 0)

    -- 发放翠影凭证
    if tokens > 0 then
        Currency.GrantReward({ type = "currency", id = CURRENCY_ID, amount = tokens }, "EmeraldSweep")
    end

    -- 更新统计
    local data = getData()
    data.totalRuns = data.totalRuns + 1
    data.tokenEarned = data.tokenEarned + tokens

    -- 上报排行榜
    local ok, LBM = pcall(require, "Game.LeaderboardData")
    if ok then
        LBM.UploadEmeraldToken(data.tokenEarned)
    end

    -- 保存
    HeroData.Save(true)

    print(string.format("[EmeraldDungeon] Sweep diff=%s bestWaves=%d tokens=%d affix=%d%%",
        difficultyId, bestWaves, tokens, affixBonusPct or 0))

    return true, tokens
end

--- 获取最高通关进度（最高难度 tier + 该 tier 最佳波次）
---@return number bestTier, number bestWave
function Emerald.GetBestProgress()
    local data = getData()
    local bestTier = 0
    local bestWave = 0
    for _, diff in ipairs(Emerald.DIFFICULTIES) do
        local waves = (data.bestWaves and data.bestWaves[diff.id]) or 0
        if waves > 0 then
            -- 更高 tier 总是优于更低 tier
            -- 同 tier 取更高波次
            if diff.tier > bestTier or (diff.tier == bestTier and waves > bestWave) then
                bestTier = diff.tier
                bestWave = waves
            end
        end
    end
    return bestTier, bestWave
end

-- ============================================================================
-- 导出常量
-- ============================================================================

Emerald.CURRENCY_ID = CURRENCY_ID
Emerald.DAILY_FREE_TICKETS = DAILY_FREE_TICKETS
Emerald.AD_TICKET_REWARD = AD_TICKET_REWARD
Emerald.DAILY_AD_LIMIT = DAILY_AD_LIMIT
Emerald.EVENT_DURATION_DAYS = EVENT_DURATION_DAYS

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================

-- ============================================================================
-- 战斗配置构建（静态部分，不含 UI 回调）
-- ============================================================================

--- 构建翠影秘境战斗配置（纯数据，无 UI 依赖）
---@param difficultyId string 难度 ID
---@return table|nil config 静态配置（含 emeraldMechanics）
---@return table|nil session 会话对象
---@return table|nil bossDef BOSS定义（含 bossSkills）
function Emerald.BuildBattleConfig(difficultyId)
    local BM = require("Game.BattleManager")

    local session = Emerald.CreateSession(difficultyId)
    if not session then return nil, nil, nil end

    local diff = session.difficulty
    local totalWaves = diff.waves

    -- 生成驻场 BOSS
    local bossDef = Emerald.GenerateBoss(difficultyId, session.affixCount)
    local bossQueue = bossDef and BM.BuildSpawnQueue({ bossDef }, 0.5) or {}

    -- 预构建所有小怪波次
    local waves = {}
    for w = 1, totalWaves do
        local enemyDefs = Emerald.GenerateWaveEnemies(w, difficultyId)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    -- BOSS 插入第一波队列头部
    if #bossQueue > 0 then
        for i = #bossQueue, 1, -1 do
            table.insert(waves[1], 1, bossQueue[i])
        end
        waves[1]._waveType = "normal"
    end

    local label = "翠影秘境 · " .. diff.name

    local config = {
        mode = "emerald_dungeon",
        waves = waves,
        totalWaves = totalWaves,
        label = label,
        waveInterval = 20,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit = 60,
        bossTimerEnabled = true,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
        emeraldMechanics = bossDef and bossDef.bossSkills or nil,
    }

    return config, session, bossDef
end

-- ============================================================================
-- SaveRegistry
-- ============================================================================
SaveRegistry.Register("emeraldDungeon", {
    group = "meta_game",
    order = 85,
    initDefault = function()
        HeroData.emeraldDungeon = nil
    end,
    serialize = function()
        return HeroData.emeraldDungeon
    end,
    deserialize = function(saved, _saveData)
        HeroData.emeraldDungeon = saved or nil
    end,
})

return Emerald
