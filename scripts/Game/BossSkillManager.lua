-- Game/BossSkillManager.lua
-- Boss 技能统一管理器
-- 职责：根据副本 mode 自动选择专属模块或通用技能，提供统一 Init/Update/Cleanup 接口
-- 使用适配器模式：对已有专属模块做透传，对新副本使用 GenericSkills

local Config_BossSkills = require("Game.Config_BossSkills")
local State             = require("Game.State")

local BSM = {}

-- 当前激活的技能模块实例（适配后的统一接口）
---@type table|nil
local currentModule = nil
-- 当前副本 mode
local currentMode = nil

-- ============================================================================
-- 适配器：将现有专属模块包装为统一接口
-- ============================================================================

--- 为专属技能模块创建适配器
---@param modulePath string require 路径
---@param mode string 副本 mode
---@return table adapter { Init, Update, Cleanup, IsActive, ... }
local function CreateDedicatedAdapter(modulePath, mode)
    local mod = require(modulePath)
    -- 专属模块已有统一接口 (Init/Update/Cleanup/IsActive)，直接透传
    return {
        type   = "dedicated",
        mode   = mode,
        module = mod,
        Init = function(params)
            mod.Init(params)
        end,
        Update = function(dt)
            mod.Update(dt)
        end,
        Cleanup = function()
            mod.Cleanup()
        end,
        IsActive = function()
            return mod.IsActive()
        end,
        -- 透传查询接口（按需使用，nil 安全）
        GetNextSkillInfo   = mod.GetNextSkillInfo,
        GetShackledTowers  = mod.GetShackledTowers,
        DamageToughness    = mod.DamageToughness,
        OnTowerHitBoss     = mod.OnTowerHitBoss,
        RemoveShackle      = mod.RemoveShackle,
        IsTowerShackled    = mod.IsTowerShackled,
        GetBattleTimer     = mod.GetBattleTimer,
        GetAnnihilateWarning = mod.GetAnnihilateWarning,
        -- Hatred 专属
        DamageDestructionToughness = mod.DamageDestructionToughness,
        GetDestructionState = mod.GetDestructionState,
        IsTauntActive = mod.IsTauntActive,
        GetStarCrushState = mod.GetStarCrushState,
        GetFortressState = mod.GetFortressState,
        -- Garbage 专属
        GetTrashStormState = mod.GetTrashStormState,
        GetGarbageCount = mod.GetGarbageCount,
        GetAtkSpdStacks = mod.GetAtkSpdStacks,
    }
end

--- 为通用技能创建适配器
---@param mode string 副本 mode
---@return table adapter
local function CreateGenericAdapter(mode)
    local GenericSkills = require("Game.BossSkills.GenericSkills")
    return {
        type   = "generic",
        mode   = mode,
        module = GenericSkills,
        Init = function(params)
            GenericSkills.Init(params)
        end,
        Update = function(dt)
            GenericSkills.Update(dt)
        end,
        Cleanup = function()
            GenericSkills.Cleanup()
        end,
        IsActive = function()
            return GenericSkills.IsActive()
        end,
        GetNextSkillInfo  = function() return GenericSkills.GetNextSkillInfo() end,
        GetShackledTowers = function() return GenericSkills.GetShackledTowers() end,
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化 Boss 技能（由各副本 DungeonUI 在 config.onStart 中调用）
---@param mode string 副本模式标识 (如 "trial_tower", "world_boss")
---@param params any   传给技能模块的初始化参数
---                     - 专属模块：原始参数（如 mechanics table / difficultyLevel）
---                     - 通用技能：由 Config_BossSkills.BuildGenericMechanics 生成
function BSM.Init(mode, params)
    -- 先清理旧的
    BSM.Cleanup()

    local entry = Config_BossSkills.Get(mode)
    if not entry then
        print("[BossSkillManager] 未注册的副本模式: " .. tostring(mode))
        return
    end

    currentMode = mode

    if entry.skillModule then
        -- 专属模块
        currentModule = CreateDedicatedAdapter(entry.skillModule, mode)
        currentModule.Init(params)
    else
        -- 通用技能
        currentModule = CreateGenericAdapter(mode)
        currentModule.Init(params)
    end

    print("[BossSkillManager] Init: " .. mode .. " (" .. (currentModule.type) .. ")")
end

--- 便捷初始化：自动构建通用技能参数
--- 仅适用于通用技能副本，专属模块副本请直接用 BSM.Init(mode, params)
---@param mode string 副本模式标识
---@param scaleParam number 传给 scaleFn 的难度参数
function BSM.InitGeneric(mode, scaleParam)
    local mechanics = Config_BossSkills.BuildGenericMechanics(mode, scaleParam)
    BSM.Init(mode, mechanics)
end

--- 每帧更新
---@param dt number
function BSM.Update(dt)
    if currentModule then
        currentModule.Update(dt)
    end
end

--- 清理
function BSM.Cleanup()
    if currentModule then
        currentModule.Cleanup()
        currentModule = nil
    end
    currentMode = nil
end

--- 是否有技能模块激活中
---@return boolean
function BSM.IsActive()
    return currentModule ~= nil and currentModule.IsActive()
end

--- 获取当前副本模式
---@return string|nil
function BSM.GetCurrentMode()
    return currentMode
end

--- 获取当前适配器类型 ("dedicated" | "generic" | nil)
---@return string|nil
function BSM.GetModuleType()
    return currentModule and currentModule.type or nil
end

-- ============================================================================
-- 查询接口透传（nil 安全）
-- ============================================================================

--- 获取下一个技能预告
---@return table|nil
function BSM.GetNextSkillInfo()
    if currentModule and currentModule.GetNextSkillInfo then
        return currentModule.GetNextSkillInfo()
    end
    return nil
end

--- 获取被束缚的塔列表
---@return table[]
function BSM.GetShackledTowers()
    if currentModule and currentModule.GetShackledTowers then
        return currentModule.GetShackledTowers()
    end
    return {}
end

--- 对韧性条造成伤害（仅支持有韧性机制的模块）
function BSM.DamageToughness()
    if currentModule and currentModule.DamageToughness then
        currentModule.DamageToughness()
    end
end

--- 塔命中 Boss 事件（仅支持相关模块）
---@param tower table
function BSM.OnTowerHitBoss(tower)
    if currentModule and currentModule.OnTowerHitBoss then
        currentModule.OnTowerHitBoss(tower)
    end
end

--- 移除指定塔的束缚（仅支持相关模块）
---@param towerId any
function BSM.RemoveShackle(towerId)
    if currentModule and currentModule.RemoveShackle then
        currentModule.RemoveShackle(towerId)
    end
end

--- 查询塔是否被束缚（仅支持相关模块）
---@param tower table
---@return boolean
function BSM.IsTowerShackled(tower)
    if currentModule and currentModule.IsTowerShackled then
        return currentModule.IsTowerShackled(tower)
    end
    return false
end

return BSM
