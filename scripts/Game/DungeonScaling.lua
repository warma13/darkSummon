--- DungeonScaling.lua
--- 统一的战斗数值缩放模块，消除各 Data 文件中重复的缩放公式
--- 所有副本和主线战役共用此模块计算 HP/Speed 缩放

local Config = require "Game.Config"

local DS = {}

local mmin = math.min
local mmax = math.max
local mfloor = math.floor

------------------------------------------------------------------------
-- HP 缩放
------------------------------------------------------------------------

--- 基础 HP 缩放（基于等效关卡数）
--- 适用于：TrialTower、ResourceDungeon、EmeraldDungeon、WorldBoss、AbyssRift
---@param stageEquiv number 等效关卡数
---@return number
function DS.CalcHPScale(stageEquiv)
    return Config.GetStageHPScale(stageEquiv)
end

--- 带波次内微调的 HP 缩放（主线战役专用）
--- 同一关卡内后续波次的 HP 会逐步提升
---@param stageNum number 关卡编号
---@param waveInStage number 关卡内第几波（1-based）
---@return number
function DS.CalcHPScaleWithWave(stageNum, waveInStage)
    local stageScale = Config.GetStageHPScale(stageNum)
    local waveScale = 1.0 + Config.WAVE_HP_PER_WAVE * (waveInStage - 1)
    return stageScale * waveScale
end

------------------------------------------------------------------------
-- DEF 缩放（独立于 HP，追踪英雄 ATK 成长）
------------------------------------------------------------------------

--- DEF 缩放（基于等效关卡数，独立于 HP 缩放）
--- 适用于：所有副本和主线战役
---@param stageEquiv number 等效关卡数
---@return number
function DS.CalcDEFScale(stageEquiv)
    return Config.GetStageDEFScale(stageEquiv)
end

------------------------------------------------------------------------
-- 速度缩放
------------------------------------------------------------------------

--- 标准速度缩放（基于等效关卡数）
--- 适用于：TrialTower、ResourceDungeon、EmeraldDungeon、AbyssRift、主线战役
---@param stageEquiv number 等效关卡数
---@return number
function DS.CalcSpeedScale(stageEquiv)
    return mmin(
        1.0 + (stageEquiv - 1) * Config.STAGE_SPEED_PER_STAGE,
        Config.STAGE_SPEED_CAP
    )
end

--- WorldBoss 专用速度缩放（使用独立参数）
--- WorldBoss 的速度缩放基于波次而非等效关卡，且有独立的步长和上限
---@param wave number 波次编号
---@param stepPerWave number? 每波步长（默认 0.02）
---@param cap number? 速度上限（默认 1.8）
---@return number
function DS.CalcSpeedScaleCustom(wave, stepPerWave, cap)
    stepPerWave = stepPerWave or Config.STAGE_SPEED_PER_STAGE
    cap = cap or Config.STAGE_SPEED_CAP
    return mmin(1.0 + (wave - 1) * stepPerWave, cap)
end

return DS
