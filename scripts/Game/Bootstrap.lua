-- Game/Bootstrap.lua
-- 初始化、生命周期、StartGame、事件订阅、调试快捷键

local UI = require("urhox-libs/UI")

local Config = require("Game.Config")
local State = require("Game.State")
local Grid = require("Game.Grid")
local Renderer = require("Game.Renderer")
local GameUI = require("Game.GameUI")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local AudioManager = require("Game.AudioManager")
local Toast = require("Game.Toast")
local AchievementToast = require("Game.AchievementToast")
local AchievementData = require("Game.AchievementData")
local SlotSaveSystem = require("Game.SlotSaveSystem")
local SpeedBoost = require("Game.SpeedBoostData")
local MiniGameUI = require("Game.MiniGameUI")

local InputHandler = require("Game.InputHandler")
local GameLoop = require("Game.GameLoop")

local Bootstrap = {}

-- NanoVG 上下文
local vg = nil
local fontId = -1
local toastVg = nil
local toastFontId = -1

-- StartGame 加载超时保护
local STARTGAME_TIMEOUT = 30   -- LoadSlot 回调最大等待时间（秒）
local startGameTimer = -1      -- -1 表示未激活
local startGameTimedOut = false -- 超时标记，防止回调再处理

-- ============================================================================
-- 初始化子系统
-- ============================================================================

local function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

local function InitNanoVG()
    vg = nvgCreate(1)
    if not vg then
        print("[ERROR] Failed to create NanoVG context!")
        return
    end
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontId == -1 then
        print("[ERROR] Failed to load font!")
    end
    Renderer.vg = vg
    Renderer.fontId = fontId
    print("[Init] NanoVG context created, fontId=" .. fontId)

    -- Toast 专用上下文：renderOrder 999995，高于 UI(999990)，低于 VirtualControls(999999)
    toastVg = nvgCreate(1)
    if toastVg then
        nvgSetRenderOrder(toastVg, 999995)
        toastFontId = nvgCreateFont(toastVg, "sans", "Fonts/MiSans-Regular.ttf")
        print("[Init] Toast NanoVG context created, renderOrder=999995, fontId=" .. toastFontId)
    else
        print("[ERROR] Failed to create Toast NanoVG context!")
    end

    -- 注入渲染上下文到 GameLoop
    GameLoop.SetContexts(vg, toastVg, toastFontId)
end

local function CalculateGridOffset()
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local gridW = Config.GRID_COLS * Config.CELL_SIZE
    local gridH = Config.GRID_ROWS * Config.CELL_SIZE
    Renderer.gridOffsetX = (screenW - gridW) * 0.5
    Renderer.gridOffsetY = (screenH - gridH) * 0.5
    print("[Init] Grid offset: " .. Renderer.gridOffsetX .. ", " .. Renderer.gridOffsetY)
    print("[Init] Screen: " .. screenW .. "x" .. screenH .. " DPR=" .. dpr)
end

local function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")

    -- NanoVG 游戏渲染（在 UI 之下）
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")

    -- Toast 渲染（在 UI 之上）
    if toastVg then
        SubscribeToEvent(toastVg, "NanoVGRender", "HandleToastRender")
    end

    -- 业务事件：存档完成 → 刷新标签栏红点
    local EventBus = require("Game.EventBus")
    local TabNav = require("Game.TabNav")
    EventBus.on(EventBus.EVENT.DATA_SAVED, function()
        TabNav.RefreshRedDots()
    end)
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Bootstrap.Start()
    graphics.windowTitle = Config.TITLE

    print("=== " .. Config.TITLE .. " Starting ===")

    -- 1. 初始化 UI 系统
    InitUI()

    -- 2. 初始化 NanoVG（游戏渲染层）
    InitNanoVG()

    -- 3. 初始化输入模块
    InputHandler.Init(UI)

    -- 4. 计算网格偏移（居中）
    CalculateGridOffset()

    -- 5. 初始化游戏状态
    State.Reset()

    -- 6. 初始化音频并播放 BGM
    AudioManager.Init()
    AudioManager.PlayBGM()

    -- 7. 初始化 UI 系统，但只创建预加载根容器（不创建游戏页面）
    GameUI.Init(UI)
    GameUI.CreatePreGameRoot()

    -- 8. 订阅事件
    SubscribeToEvents()

    -- 9. 先显示区服选择界面（loading 状态），再异步加载云存档
    local ServerSelectUI = require("Game.ServerSelectUI")

    GameUI.CreateServerSelect(function(serverId)
        StartGame(serverId)
    end, nil)  -- meta=nil, 初始 loading 状态
    GameUI.ShowServerSelect(true)

    -- 超时检测状态（模块级，由 Bootstrap.Tick 驱动）
    local SLOT_TIMEOUT_FIRST = 3    -- 首次加载超时（秒）
    local SLOT_TIMEOUT_RETRY = 10   -- 重试加载超时（秒）
    Bootstrap._slotInitDone  = false
    Bootstrap._slotTimer     = 0
    Bootstrap._slotTimeout   = SLOT_TIMEOUT_FIRST
    local isFirstLoad = true

    -- 加载存档（首次 + 重试共用）
    local function doSlotInit()
        Bootstrap._slotInitDone = false
        Bootstrap._slotTimer    = 0
        Bootstrap._slotTimeout  = isFirstLoad and SLOT_TIMEOUT_FIRST or SLOT_TIMEOUT_RETRY
        isFirstLoad = false
        ServerSelectUI.SetLoadState("loading")
        print("[Main] SlotSaveSystem.Init starting...")

        SlotSaveSystem.Init(function(meta, isNewPlayer, err)
            Bootstrap._slotInitDone = true
            if err then
                print("[Main] SlotSaveSystem init error: " .. tostring(err))
                ServerSelectUI.SetLoadState("error", "存档加载失败: " .. tostring(err))
                return
            end
            print("[Main] SlotSaveSystem ready, isNewPlayer=" .. tostring(isNewPlayer))
            ServerSelectUI.UpdateSlotMeta(meta)
            ServerSelectUI.SetLoadState("ready")
        end)
    end

    -- 重试回调
    ServerSelectUI.SetRetryCallback(function()
        print("[Main] Retry SlotSaveSystem.Init...")
        doSlotInit()
    end)

    -- 启动首次加载
    doSlotInit()

    print("=== " .. Config.TITLE .. " Ready ===")
end

--- 每帧调用：检测 SlotSave 加载超时 + StartGame 超时
function Bootstrap.Tick(dt)
    -- SlotSaveSystem.Init 超时检测
    if not Bootstrap._slotInitDone and Bootstrap._slotTimeout then
        Bootstrap._slotTimer = Bootstrap._slotTimer + dt
        if Bootstrap._slotTimer >= Bootstrap._slotTimeout then
            Bootstrap._slotInitDone = true  -- 防止重复触发
            print("[Main] SlotSaveSystem init timeout after " .. Bootstrap._slotTimeout .. "s")
            local ServerSelectUI = require("Game.ServerSelectUI")
            ServerSelectUI.SetLoadState("error", "存档加载超时，请重试")
        end
    end

    -- StartGame LoadSlot 超时检测
    if startGameTimer >= 0 then
        startGameTimer = startGameTimer + dt
        if startGameTimer >= STARTGAME_TIMEOUT then
            startGameTimer = -1
            startGameTimedOut = true
            print("[StartGame] LoadSlot timed out after " .. STARTGAME_TIMEOUT .. "s, returning to server select")
            GameUI.HideLoading()
            Toast.Show("加载超时，请重试")
            GameUI.ShowServerSelect(true)
        end
    end
end

function Bootstrap.Stop()
    SpeedBoost.Save()
    if vg then nvgDelete(vg) end
    if toastVg then nvgDelete(toastVg) end
    UI.Shutdown()
end

-- ============================================================================
-- StartGame（选服后回调）
-- ============================================================================

---@param serverId number
function StartGame(serverId)
    print("[StartGame] Loading slot " .. tostring(serverId) .. "...")

    -- 显示加载提示，避免黑屏
    GameUI.ShowLoading("加载中")

    -- 超时保护：启动计时器
    startGameTimer = 0
    startGameTimedOut = false

    -- 异步加载槽位（serverId 即为 slotId）
    SlotSaveSystem.LoadSlot(serverId, function(success, isNewSlot)
        -- 如果已超时并处理过，忽略迟到的回调
        if startGameTimedOut then
            print("[StartGame] Callback arrived after timeout, ignoring")
            return
        end
        startGameTimer = -1  -- 取消超时计时器
        GameUI.HideLoading()

        if not success then
            print("[StartGame] LoadSlot failed for slot " .. tostring(serverId))
            Toast.Show("存档加载失败，请重试")
            GameUI.ShowServerSelect(true)
            return
        end

        print("[StartGame] Slot " .. tostring(serverId) .. " loaded, isNew=" .. tostring(isNewSlot))

        -- 存档加载成功后才创建完整游戏 UI
        GameUI.CreateUI()

        -- 云端数据已反序列化，重新加载各子模块数据
        local ChestData = require("Game.ChestData")
        ChestData.Load()

        -- 货币字段迁移
        Currency.EnsureFields()

        -- 从存档恢复关卡进度
        local savedStage = (HeroData.stats.bestStage or 0) + 1
        if savedStage < 1 then savedStage = 1 end

        -- 通过 BattleManager 启动 campaign
        local BM = require("Game.BattleManager")
        BM.Enter("campaign", {
            stageNum = savedStage,
            onWin  = function() GameUI.DoStageClear() end,
            onLose = function() GameUI.DoGameOver() end,
            initialDarkSoul = Config.INITIAL_DARK_SOUL,
        })

        GameUI.UpdateHUD()

        -- 挂机时长恢复
        local claimTime = HeroData.stats.afkLastClaimTime or 0
        if claimTime > 0 then
            local totalAfkSecs = os.time() - claimTime
            if totalAfkSecs > 0 then
                GameUI._afkStartTime = time.elapsedTime - totalAfkSecs
                GameUI._afkLastDisplaySec = -1
                print("[StartGame] AFK restored " .. math.floor(totalAfkSecs / 60) .. " min since last claim")
            end
        else
            -- 从未领取过挂机收益（新存档），初始化基准时间为当前时间
            HeroData.stats.afkLastClaimTime = os.time()
            print("[StartGame] AFK initialized afkLastClaimTime for new save")
        end
        -- 离线推关：在 lastSaveTime 重置之前计算
        do
            local okOP, OfflinePush = pcall(require, "Game.OfflinePush")
            if okOP and OfflinePush and OfflinePush.CalcOfflinePushRewards then
                local pushResult = OfflinePush.CalcOfflinePushRewards()
                if pushResult then
                    GameUI._pendingOfflinePush = pushResult
                    print("[StartGame] OfflinePush: pushed " .. (pushResult.pushed or 0)
                        .. " stages, bestStage " .. (pushResult.oldBestStage or 0)
                        .. " → " .. (pushResult.newBestStage or 0))
                else
                    print("[StartGame] OfflinePush: skipped (too short or no save)")
                end
            end
        end

        HeroData.lastSaveTime = os.time()
        HeroData.Save()

        -- 同步所有排行榜分数
        local okLB, LBSync = pcall(require, "Game.LeaderboardData")
        if okLB and LBSync.SyncAll then LBSync.SyncAll() end

        -- 初始化加速系统
        SpeedBoost.Init()

        -- 低关卡玩家每日免费解锁自动功能 + x2 加速
        local newbieStageLimit = 5
        if State.currentStage <= newbieStageLimit then
            local AutoPlayM = require("Game.AutoPlay")
            if not AutoPlayM.IsUnlockedToday("autoSummon") then
                AutoPlayM.RecordAdUnlock("autoSummon")
            end
            if not AutoPlayM.IsUnlockedToday("autoMerge") then
                AutoPlayM.RecordAdUnlock("autoMerge")
            end
            if not AutoPlayM.IsUnlockedToday("autoDeploy") then
                AutoPlayM.RecordAdUnlock("autoDeploy")
            end
            if SpeedBoost.remaining < 3600 then
                SpeedBoost.remaining = 3600
                SpeedBoost.enabled = true
                SpeedBoost.Save()
                HeroData.Save()
            end
            print("[StartGame] Newbie daily grant (stage=" .. State.currentStage .. "): auto features + 1h x2")
        end

        -- 存档加载后刷新红点
        GameUI.RefreshLaunchGiftRedDot()
        GameUI.RefreshActivityRedDot()
        GameUI.RefreshVaultRedDot()
        local TabNav = require("Game.TabNav")
        TabNav.RefreshRedDots()

        GameUI.RefreshCostumeSignInRedDot()
    end)
end

-- ============================================================================
-- 调试快捷键
-- ============================================================================

function Bootstrap.HandleKeyDown(eventType, eventData)
    if MiniGameUI.isActive() then
        _YangMG_KeyDown(eventType, eventData)
        return
    end
    local key = eventData["Key"]:GetInt()

    local AdDashboardUI = require("Game.AdDashboardUI")

    -- F：管理员广告数据面板
    if key == KEY_F then
        AdDashboardUI.Toggle()
    end

    -- F8：立即胜利当前试练塔战斗 + 获得10000暗魂（仅管理员）
    if key == KEY_F8 and AdDashboardUI.IsAdmin() then
        Currency.CollectDarkSoul(10000)
        print("[Debug] F8 - +10000 暗魂，当前=" .. Currency.GetDarkSouls())

        local BM = require("Game.BattleManager")
        if BM.IsActive() and BM.GetMode() == "trial_tower" then
            print("[Debug] F8 - ForceWin trial_tower")
            BM.OnWin()
        else
            print("[Debug] F8 - 当前无试练塔战斗，已忽略 (mode=" .. tostring(BM.GetMode()) .. ")")
        end

        -- 调试：直接激活当日免广卡
        local AdReliefData = require("Game.AdReliefData")
        local ToastDbg = require("Game.Toast")
        if AdReliefData.IsAdFreeToday() then
            print("[Debug] F8 - 免广卡已激活，跳过")
            ToastDbg.Show("调试: 免广卡已激活", { 100, 200, 255 })
        else
            local heroStats = require("Game.HeroData").stats
            if heroStats.adRelief then
                heroStats.adRelief.todayAds = 20
                heroStats.adRelief.lastAdDate = require("Game.DateUtil").TodayStr()
                require("Game.HeroData").Save()
                print("[Debug] F8 - 免广卡已激活 (todayAds=20)")
                ToastDbg.Show("调试: 免广卡已激活，广告将自动跳过", { 100, 220, 180 })
            end
        end

        -- 测试成就弹出动画
        local testNames = { "永夜不息", "初露锋芒", "百战老兵", "暗影收割者", "虚空征服者" }
        local testDescs = { "单日在线24小时", "完成首次战斗", "累计战斗100次", "击败1000个敌人", "通关虚空裂隙" }
        local ri = math.random(1, #testNames)
        AchievementToast.Show(testNames[ri], testDescs[ri])
        print("[Debug] F8 - 测试成就弹出: " .. testNames[ri])
    end

    -- F9：离线平衡模拟器
    if key == KEY_F9 then
        print("[Debug] F9 - 运行平衡模拟器...")
        local ok, err = pcall(function()
            local BalanceSim = require("Balance.BalanceSim")
            BalanceSim.Run()
        end)
        if not ok then
            print("[Debug] BalanceSim error: " .. tostring(err))
        end
    end
end

--- 窗口大小变化时重新计算网格偏移
function Bootstrap.HandleScreenMode(eventType, eventData)
    CalculateGridOffset()
    Grid.InvalidateCache()
    print("[Event] ScreenMode changed, grid offset recalculated")
end

return Bootstrap
