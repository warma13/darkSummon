-- Game/TrainingDummyData.lua
-- 木桩副本数据模块：构建无限血木桩 Boss 的战斗配置

local Config         = require("Game.Config")
local HeroData       = require("Game.HeroData")
local F              = require("Game.FormulaLib")
local DungeonScaling = require("Game.DungeonScaling")

local TD = {}

-- ============================================================================
-- 木桩预设
-- ============================================================================

TD.PRESETS = {
    {
        key  = "standard",
        name = "标准木桩",
        desc = "中等防御，无被动",
        def  = 5000,
        res  = 30,
    },
    {
        key  = "high_def",
        name = "重甲木桩",
        desc = "高物防低魔抗",
        def  = 20000,
        res  = 10,
    },
    {
        key  = "high_res",
        name = "魔抗木桩",
        desc = "高魔抗低物防",
        def  = 2000,
        res  = 65,
    },
    {
        key  = "current_boss",
        name = "当前Boss",
        desc = "模拟当前关卡Boss",
        def  = 0,
        res  = 0,
        dynamic = true,
    },
    {
        key  = "custom",
        name = "自定义",
        desc = "自由设定参数",
        def  = 5000,
        res  = 30,
        isCustom = true,
    },
}

-- ============================================================================
-- 运行时状态
-- ============================================================================
local _selectedPreset = 1
local _customParams = {
    def = 5000,
    res = 30,
    critDmgReduce   = 0,   -- UI 显示 0-90 整数
    dmgBonusReduce  = 0,
    typeDmgReduce   = 0,
    armorPenResist  = 0,
}

-- 当前Boss模式：是否使用真实血量（false = 无限血）
local _useBossHP = false

-- 模拟时长设定（秒）
local _simDuration = 120

-- 历史记录（本次会话内）
local _history = {}

-- ============================================================================
-- 接口
-- ============================================================================

function TD.GetPresets()        return TD.PRESETS end
function TD.GetSelectedIndex()  return _selectedPreset end
function TD.SetSelectedIndex(i) _selectedPreset = math.max(1, math.min(i, #TD.PRESETS)) end
function TD.GetCustomParams()   return _customParams end
function TD.GetSimDuration()    return _simDuration end
function TD.SetSimDuration(d)   _simDuration = math.max(10, math.min(d, 300)) end
function TD.GetUseBossHP()      return _useBossHP end
function TD.SetUseBossHP(v)     _useBossHP = (v == true) end
function TD.GetHistory()        return _history end

function TD.SetCustomParam(key, value)
    if _customParams[key] ~= nil then
        _customParams[key] = value
    end
end

--- 记录一条历史
function TD.RecordHistory(totalDamage, duration, label)
    local dps = duration > 0 and (totalDamage / duration) or 0
    local deployed = HeroData.deployed or {}
    local names = {}
    for _, heroId in ipairs(deployed) do
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then names[#names + 1] = td.name; break end
        end
    end
    _history[#_history + 1] = {
        time     = os.time(),
        preset   = label or "木桩",
        dps      = dps,
        totalDmg = totalDamage,
        duration = duration,
        heroes   = table.concat(names, ","),
    }
    while #_history > 20 do
        table.remove(_history, 1)
    end
end

-- ============================================================================
-- 构建木桩敌人定义
-- ============================================================================

--- 创建木桩 enemyDef（用于 BattleManager 的 waves）
---@return table enemyDef, string label
function TD.BuildDummyDef()
    local preset = TD.PRESETS[_selectedPreset]
    if not preset then preset = TD.PRESETS[1] end

    local DUMMY_HP = math.huge   -- 真·无限血（渲染已兼容 math.huge）
    local DUMMY_ICON = "image/dungeon_training_dummy.png"
    local label = preset.name

    -- ── 当前 Boss 模式 ──
    if preset.dynamic then
        local bestStage = (HeroData.stats and HeroData.stats.bestStage) or 1
        local stageNum = bestStage + 1
        local bossDef = Config.BuildBossDef(stageNum)
        local defScale = DungeonScaling.CalcDEFScale(stageNum)
        local theme = Config.GetTheme(stageNum)
        local profile = Config.THEME_DEFENSE_PROFILE[theme.id] or { defMult = 1.0, resMult = 1.0 }

        local scaling = {}
        if Config.ENEMY_SCALING then
            scaling.critDmgReduce  = F.Piecewise4(Config.ENEMY_SCALING.critDmgReduce, stageNum)
            scaling.dmgBonusReduce = F.Piecewise4(Config.ENEMY_SCALING.dmgBonusReduce, stageNum)
            scaling.typeDmgReduce  = F.Piecewise4(Config.ENEMY_SCALING.typeDmgReduce, stageNum)
            scaling.armorPenResist = F.Piecewise4(Config.ENEMY_SCALING.armorPenResist, stageNum)
        else
            scaling.critDmgReduce  = 0
            scaling.dmgBonusReduce = 0
            scaling.typeDmgReduce  = 0
            scaling.armorPenResist = 0
        end

        label = string.format("第%d关 %s Boss", stageNum, theme.name or "")

        -- 真实血量：使用 Boss baseHP * HP 缩放
        local bossRealHP = (bossDef.baseHP or 10000) * DungeonScaling.CalcHPScale(stageNum)
        local useHP = (_useBossHP and bossRealHP) or DUMMY_HP

        return {
            id       = "training_dummy",
            name     = "木桩 · " .. label,
            icon     = DUMMY_ICON,
            color    = { 180, 60, 60 },
            baseHP   = useHP,
            baseDEF  = (bossDef.baseDEF or 3000) * (profile.defMult or 1.0) * defScale,
            baseRES  = bossDef.baseRES or 30,
            speed    = 0,         -- 不移动
            size     = 14,
            shape    = "square",
            reward   = 0,
            liveCost = 0,
            isBoss   = true,
            isWorldBoss = true,   -- 复用世界 Boss 伤害追踪
            themeId  = "void",
            passive  = bossDef.passive,
            critDmgReduce  = scaling.critDmgReduce,
            dmgBonusReduce = scaling.dmgBonusReduce,
            typeDmgReduce  = scaling.typeDmgReduce,
            armorPenResist = scaling.armorPenResist,
        }, label
    end

    -- ── 自定义模式 ──
    if preset.isCustom then
        return {
            id       = "training_dummy",
            name     = "自定义木桩",
            icon     = DUMMY_ICON,
            color    = { 180, 60, 60 },
            baseHP   = DUMMY_HP,
            baseDEF  = _customParams.def,
            baseRES  = _customParams.res,
            speed    = 0,
            size     = 14,
            shape    = "square",
            reward   = 0,
            liveCost = 0,
            isBoss   = true,
            isWorldBoss = true,
            themeId  = "void",
            passive  = nil,
            critDmgReduce  = (_customParams.critDmgReduce  or 0) / 100,
            dmgBonusReduce = (_customParams.dmgBonusReduce or 0) / 100,
            typeDmgReduce  = (_customParams.typeDmgReduce  or 0) / 100,
            armorPenResist = (_customParams.armorPenResist or 0) / 100,
        }, "自定义木桩"
    end

    -- ── 预设模式 ──
    return {
        id       = "training_dummy",
        name     = "木桩 · " .. preset.name,
        icon     = DUMMY_ICON,
        color    = { 180, 60, 60 },
        baseHP   = DUMMY_HP,
        baseDEF  = preset.def,
        baseRES  = preset.res,
        speed    = 0,
        size     = 14,
        shape    = "square",
        reward   = 0,
        liveCost = 0,
        isBoss   = true,
        isWorldBoss = true,
        themeId  = "void",
        passive  = nil,
        critDmgReduce  = 0,
        dmgBonusReduce = 0,
        typeDmgReduce  = 0,
        armorPenResist = 0,
    }, label
end

-- ============================================================================
-- 构建战斗配置（world_boss 模式）
-- ============================================================================

--- 构建木桩战斗配置
---@return table config  用于 GameUI.EnterDungeonBattle()
---@return string label  木桩名称
function TD.BuildBattleConfig()
    local dummyDef, label = TD.BuildDummyDef()
    local duration = _simDuration

    local waves = {
        {
            {
                type      = "training_dummy",
                typeDef   = dummyDef,
                delay     = 0,
                isElite   = false,
                affixes   = {},
                prescaled = true,   -- HP/DEF 已经设好
            },
        },
    }

    local config = {
        mode             = "world_boss",      -- 复用世界 Boss 计时/伤害追踪
        waves            = waves,
        totalWaves       = 1,
        stageNum         = 1,
        label            = "木桩训练 · " .. label,
        waveInterval     = 0,
        autoAdvanceWave  = false,
        bossTimerEnabled = true,
        overloadEnabled  = false,
        worldBossDuration       = duration,
        worldBossDarkSoulDrain  = 0,          -- 不掉暗魂
        initialDarkSoul  = 1000000,   -- 木桩模式给充足暗魂（100万）
    }

    return config, label
end

-- ============================================================================
-- 实时调控 API（战斗中调用）
-- ============================================================================

--- 初始化木桩调控状态（onStart 回调中调用）
function TD.InitPanel(dummyDef)
    local State = require("Game.State")
    local initDEF = (dummyDef.baseDEF or 0) + 0.0  -- 强制 float 避免整数溢出
    local initRES = (dummyDef.baseRES or 0) + 0.0
    State.trainingDummy = {
        curDEF   = initDEF,   -- 当前实际 DEF（float）
        curRES   = initRES,   -- 当前实际 RES（float）
        initDEF  = initDEF,   -- 初始 DEF，用于按钮颜色判断
        initRES  = initRES,
        movingEnabled = false,
        dummyDef = dummyDef,
        baseSpeed = dummyDef.speed or 0,
    }
end

--- 切换敌人运动
function TD.ToggleMoving()
    local State = require("Game.State")
    local td = State.trainingDummy
    if not td then return end
    td.movingEnabled = not td.movingEnabled
    local newSpeed = td.movingEnabled and 40 or 0
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isWorldBoss then
            e.speed = newSpeed
            e.baseSpeed = newSpeed
        end
    end
end

--- DEF ×1024（curDEF=0 时从 1024 起步）
function TD.BoostDEF()
    local State = require("Game.State")
    local td = State.trainingDummy
    if not td then return end
    if td.curDEF < 1.0 then td.curDEF = 1.0 end
    td.curDEF = td.curDEF * 1024.0
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isWorldBoss then
            e.def = td.curDEF
        end
    end
end

--- RES ×1024（木桩模式不设上限，方便测试极端情况）
function TD.BoostRES()
    local State = require("Game.State")
    local td = State.trainingDummy
    if not td then return end
    if td.curRES < 1.0 then td.curRES = 1.0 end
    td.curRES = td.curRES * 1024.0
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isWorldBoss then
            e.res = td.curRES
        end
    end
end

--- 重置 DEF/RES 为初始值
function TD.Reset()
    local State = require("Game.State")
    local td = State.trainingDummy
    if not td then return end
    td.curDEF = td.initDEF
    td.curRES = td.initRES
    for _, e in ipairs(State.enemies) do
        if e.alive and e.isWorldBoss then
            e.def = td.curDEF
            e.res = td.curRES
        end
    end
end

--- 清空所有木桩
function TD.ClearAll()
    local State = require("Game.State")
    for i = #State.enemies, 1, -1 do
        local e = State.enemies[i]
        if e.alive and e.isWorldBoss then
            e.alive = false
            e.hp = 0
        end
    end
end

--- 再生成一个木桩
function TD.SpawnAnother()
    local State = require("Game.State")
    local Enemy = require("Game.Enemy")
    local td = State.trainingDummy
    if not td or not td.dummyDef then return end

    local def = {}
    for k, v in pairs(td.dummyDef) do def[k] = v end
    def.baseDEF = td.curDEF
    def.baseRES = td.curRES
    def.speed   = td.movingEnabled and 40 or 0

    Enemy.CreateBoss(def, State.currentWave, 1.0, 1.0, {}, 1)
end

return TD
