-- Game/BattleFlow.lua
-- 副本进出流程中心化管理
-- 将 EnterDungeonBattle / ExitDungeonBattle 从 GameUI 解耦

local BM = require("Game.BattleManager")
local HeroData = require("Game.HeroData")
local State = require("Game.State")
local Config = require("Game.Config")

local BattleFlow = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 进副本前备份的主线关卡号
local savedCampaignStage = nil

-- ============================================================================
-- UI 回调注入（由 GameUI 初始化时注册）
-- ============================================================================

---@class BattleFlowHooks
---@field switchTab fun(tab: string)       切换页签
---@field updateHUD fun()                  刷新 HUD
---@field refreshDungeon fun()             刷新副本列表
---@field doStageClear fun()               通关结算 UI
---@field doGameOver fun()                 失败结算 UI

---@type BattleFlowHooks|nil
local hooks = nil

--- 注册 UI 回调（GameUI 初始化时调用一次）
---@param h BattleFlowHooks
function BattleFlow.RegisterHooks(h)
    hooks = h
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 进入副本战斗：备份主线、切页、启动 BM
---@param config table BattleManager.Start 所需的配置
function BattleFlow.EnterDungeon(config)
    -- 备份主线当前关卡
    savedCampaignStage = (HeroData.stats.bestStage or 0) + 1
    if savedCampaignStage < 1 then savedCampaignStage = 1 end

    -- 切到战斗页
    if hooks and hooks.switchTab then
        hooks.switchTab("battle")
    end

    -- 启动战斗
    BM.Start(config)

    if hooks and hooks.updateHUD then
        hooks.updateHUD()
    end

    print("[BattleFlow] Entered dungeon battle: " .. (config.label or config.mode))

    -- hook 开服好礼 dungeon 任务进度
    local ok1, LGD = pcall(require, "Game.LaunchGiftData")
    if ok1 and LGD then LGD.AddProgress("dungeon", 1) end
    -- hook 每日任务 dungeon 进度
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD and DTD.AddProgress then DTD.AddProgress("dungeon", 1) end
end

--- 内部：真正的清理 + 恢复主线（不要直接调用，走 ExitDungeon）
local function doExitCleanup()
    BM.End()

    -- 恢复主线 campaign
    local restoreStage = savedCampaignStage or ((HeroData.stats.bestStage or 0) + 1)
    if restoreStage < 1 then restoreStage = 1 end
    savedCampaignStage = nil

    BM.Enter("campaign", {
        stageNum = restoreStage,
        onWin    = hooks and hooks.doStageClear or nil,
        onLose   = hooks and hooks.doGameOver or nil,
    })

    if hooks and hooks.switchTab then
        hooks.switchTab("dungeon")
    end
    if hooks and hooks.refreshDungeon then
        hooks.refreshDungeon()
    end
    if hooks and hooks.updateHUD then
        hooks.updateHUD()
    end

    print("[BattleFlow] Exited dungeon battle, restored campaign stage " .. restoreStage)
end

--- 退出副本战斗
--- 若有 onExit 回调，会传入 (result, continueExit)；副本展示完奖励后调 continueExit() 即可。
--- 若无 onExit，直接清理恢复主线。
function BattleFlow.ExitDungeon()
    if BM.config and BM.config.onExit then
        local onExit = BM.config.onExit
        BM.config.onExit = nil
        local LootDrop = require("Game.LootDrop")
        LootDrop.CollectAll()
        local result = {
            mode = BM.config.mode,
            wave = State.currentWave,
            totalWaves = BM.config.totalWaves,
            score = State.score,
        }
        onExit(result, doExitCleanup)
        return
    end

    doExitCleanup()
end

--- 获取备份的主线关卡号（供外部查询）
---@return number|nil
function BattleFlow.GetSavedCampaignStage()
    return savedCampaignStage
end

return BattleFlow
