-- Game/GameLoop.lua
-- 游戏主循环：Update 逻辑 + NanoVG 渲染回调

local State = require("Game.State")
local Tower = require("Game.Tower")
local Enemy = require("Game.Enemy")
local Combat = require("Game.Combat")
local Renderer = require("Game.Renderer")
local GameUI = require("Game.GameUI")
local AudioManager = require("Game.AudioManager")
local Toast = require("Game.Toast")
local AchievementToast = require("Game.AchievementToast")
local AchievementData = require("Game.AchievementData")
local SlotSaveSystem = require("Game.SlotSaveSystem")
local SpeedBoost = require("Game.SpeedBoostData")
local IdleScreen = require("Game.IdleScreen")
local MiniGameUI = require("Game.MiniGameUI")
local TrialTower = require("Game.DungeonUI.TrialTower")

local GameLoop = {}

-- NanoVG 上下文（由 Bootstrap 注入）
local vg = nil
local toastVg = nil
local toastFontId = -1

--- 注入 NanoVG 上下文
function GameLoop.SetContexts(gameVg, tVg, tFontId)
    vg = gameVg
    toastVg = tVg
    toastFontId = tFontId or -1
end

-- ============================================================================
-- 游戏逻辑更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function GameLoop.HandleUpdate(eventType, eventData)
    if MiniGameUI.isActive() then
        _YangMG_Update(eventType, eventData)
        return
    end

    local rawDt = eventData["TimeStep"]:GetFloat()

    -- 将实际帧间隔传给 Renderer（替代硬编码 1/60）
    Renderer.frameDt = rawDt

    -- SlotSave 加载超时检测（延迟 require 避免循环依赖）
    local Bootstrap = require("Game.Bootstrap")
    Bootstrap.Tick(rawDt)

    -- 待机模式 UI 动画（用原始 dt）
    IdleScreen.Update(rawDt)

    -- 每帧开头：压缩所有游戏数组，消除 nil 空洞
    State.CompactArrays()

    -- 加速系统：时长始终用原始 dt 流逝
    SpeedBoost.Update(rawDt)

    -- 游戏逻辑用加速后的 dt
    local dt = rawDt * SpeedBoost.GetMultiplier()

    State.time = State.time + dt
    AudioManager.Update(dt)

    local BattleManager = require("Game.BattleManager")

    if State.phase == State.PHASE_PLAYING then
        -- ── 更新顺序约束（修改须谨慎） ──────────────────────
        -- 1) Tower.Update          — 冷却递减、debuff 衰减
        -- 2) BattleManager.UpdateWaves — 生成敌人
        -- 3) Enemy.Update          — 敌人移动、状态衰减
        -- 4) Combat.Update         — 内部顺序：
        --    4a) HeroSkills.UpdateAuras   — 清零并重算光环 buff
        --    4b) HeroSkills.UpdateGlobalBuffs — 全局 buff 衰减
        --    4c) HeroSkills.UpdateCurseDOT   — 诅咒 DOT
        --    4d) HeroSkills.UpdateFrame       — 英雄专属帧逻辑
        --         └ nature_elf.UpdateFrame: 自然之力脉冲 → 渐近线 buff
        --           （依赖 4a 已清零 auraAtkBuff/auraSpdBuff）
        --    4e) RelicEffects.Update         — 遗物充能/脉冲/灼烧
        --    4f) 塔攻击 → 弹道 → 粒子 → 飘字 → 掉落物
        -- ────────────────────────────────────────────────────

        -- 更新塔
        Tower.Update(dt)

        -- 更新波次（生成敌人）— campaign 现在也通过 BM 运行
        if BattleManager.IsActive() then
            BattleManager.UpdateWaves(dt)
        end

        -- 更新敌人（移动）
        Enemy.Update(dt, Renderer.gridOffsetX, Renderer.gridOffsetY)

        -- 更新战斗（攻击、弹道）— 内部顺序见上方注释
        Combat.Update(dt, Renderer.gridOffsetX, Renderer.gridOffsetY)

        -- BOSS 出场动画计时
        if State.bossIntro then
            State.bossIntro.timer = State.bossIntro.timer + dt
            if State.bossIntro.timer >= State.bossIntro.duration then
                State.bossIntro = nil
            end
        end

        -- 合成闪光衰减
        if State.mergeFlash > 0 then
            State.mergeFlash = State.mergeFlash - dt
        end
        if State.summonFlash > 0 then
            State.summonFlash = State.summonFlash - dt
        end
    elseif State.phase == State.PHASE_WAVE_READY then
        -- 波次准备阶段也更新塔动画
        Tower.Update(dt)
        if State.mergeFlash > 0 then
            State.mergeFlash = State.mergeFlash - dt
        end
        if State.summonFlash > 0 then
            State.summonFlash = State.summonFlash - dt
        end
    end

    -- UI 更新：传入游戏 dt（自动召唤/合成/超限等用加速 dt）
    GameUI.Update(dt)

    -- 更新提示消息
    Toast.Update(rawDt)
    AchievementToast.Update(rawDt)

    -- 成就达成检测（定时轮询）
    AchievementData.Update(rawDt)

    -- 更新云端存档系统（自动保存、脏标记、重试队列）
    SlotSaveSystem.Update(rawDt)

    -- 试练塔连续挑战倒计时（用 rawDt，独立于 GameUI.Update）
    TrialTower.UpdateCountdown(rawDt)

    -- 英雄详情面板每秒属性刷新（用 rawDt，不受加速影响）
    local HeroDetail = require("Game.HeroUI.HeroDetail")
    HeroDetail.Tick(rawDt)
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

function GameLoop.HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    if State.phase == State.PHASE_MENU then return end
    if MiniGameUI.isActive() then return end
    if IdleScreen.IsActive() then return end

    local dpr = graphics:GetDPR()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local logW = physW / dpr
    local logH = physH / dpr

    -- 模式 B: 系统逻辑分辨率 + DPR 修正
    nvgBeginFrame(vg, logW, logH, dpr)

    -- 渲染游戏画面（pcall 保护确保 nvgEndFrame 始终执行）
    local ok, err = pcall(Renderer.Render, vg, logW, logH)
    if not ok then
        print("[Render] ERROR: " .. tostring(err))
    end

    nvgEndFrame(vg)
end

--- Toast 专用渲染（renderOrder 999995，在 UI 之上）
function GameLoop.HandleToastRender(eventType, eventData)
    if not toastVg then return end
    if MiniGameUI.isActive() then return end
    if IdleScreen.IsActive() then return end

    -- 无内容时跳过整个渲染通道，减少 GPU 提交
    if Toast.IsEmpty() and AchievementToast.IsIdle() then return end

    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr

    nvgBeginFrame(toastVg, logW, logH, dpr)
    Toast.Draw(toastVg, logW, toastFontId)
    AchievementToast.Draw(toastVg, logW, toastFontId)
    nvgEndFrame(toastVg)
end

return GameLoop
