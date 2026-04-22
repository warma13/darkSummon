-- ============================================================================
-- Dark Merge TD - 暗黑合成塔防
-- Version 1.0
-- ============================================================================

local UI = require("urhox-libs/UI")

-- 游戏模块
local Config = require("Game.Config")
local State = require("Game.State")
local Grid = require("Game.Grid")
local Tower = require("Game.Tower")
local Enemy = require("Game.Enemy")
local Wave = require("Game.Wave")
local Combat = require("Game.Combat")
local Renderer = require("Game.Renderer")
local GameUI = require("Game.GameUI")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local AudioManager = require("Game.AudioManager")
local Toast = require("Game.Toast")
local SlotSaveSystem = require("Game.SlotSaveSystem")
local SpeedBoost = require("Game.SpeedBoostData")
-- WorldBossSkills / EmeraldBossSkills 不再在 main 中直接调用，
-- 已通过 BattleConfig.onUpdate 回调由各副本自行管理
local IdleScreen = require("Game.IdleScreen")
local MiniGameUI = require("Game.MiniGameUI")

-- NanoVG 独立上下文（用于游戏渲染，在 UI 层下面）
local vg = nil
local fontId = -1

-- Toast 专用 NanoVG 上下文（renderOrder 高于 UI，保证不被遮挡）
local toastVg = nil
local toastFontId = -1

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.TITLE
    print("=== " .. Config.TITLE .. " Starting ===")

    -- 1. 初始化 UI 系统
    InitUI()

    -- 2. 初始化 NanoVG（游戏渲染层）
    InitNanoVG()

    -- 3. 计算网格偏移（居中）
    CalculateGridOffset()

    -- 4. 初始化游戏状态
    State.Reset()

    -- 5. 初始化音频并播放 BGM（必须在 Wave.StartNext 之前）
    AudioManager.Init()
    AudioManager.PlayBGM()

    -- 6. 创建 UI
    GameUI.Init(UI)
    GameUI.CreateUI()

    -- 7. 订阅事件
    SubscribeToEvents()

    -- 8. 初始化云端存档系统（异步），完成后显示区服选择
    SlotSaveSystem.Init(function(slotMeta, isNewPlayer, err)
        if err then
            print("[Main] SlotSaveSystem init error: " .. tostring(err))
        end
        print("[Main] SlotSaveSystem ready, isNewPlayer=" .. tostring(isNewPlayer))

        -- 显示区服选择界面（传入存档元数据）
        GameUI.CreateServerSelect(function(serverId)
            StartGame(serverId)
        end, slotMeta)
        GameUI.ShowServerSelect(true)
    end)

    print("=== " .. Config.TITLE .. " Ready ===")
end

--- 开始游戏（选服后回调）—— 异步加载对应槽位存档
---@param serverId number
function StartGame(serverId)
    print("[StartGame] Loading slot " .. tostring(serverId) .. "...")

    -- 异步加载槽位（serverId 即为 slotId）
    SlotSaveSystem.LoadSlot(serverId, function(success, isNewSlot)
        if not success then
            print("[StartGame] LoadSlot failed for slot " .. tostring(serverId))
            Toast.Show("存档加载失败，请重试")
            return
        end

        print("[StartGame] Slot " .. tostring(serverId) .. " loaded, isNew=" .. tostring(isNewSlot))

        -- 云端数据已反序列化，重新加载各子模块数据（ChestData 等在 CreateUI 时过早初始化）
        local ChestData = require("Game.ChestData")
        ChestData.Load()

        -- 货币字段迁移（修复历史 bug，将错误存入 currencies 的仓库道具搬回仓库）
        Currency.EnsureFields()

        -- 从存档恢复关卡进度（bestStage + 1 = 下一关）
        local savedStage = (HeroData.stats.bestStage or 0) + 1
        if savedStage < 1 then savedStage = 1 end

        -- 统一通过 BattleManager 启动 campaign（消除双路径）
        local BM = require("Game.BattleManager")
        BM.Enter("campaign", {
            stageNum = savedStage,
            onWin  = function() GameUI.DoStageClear() end,
            onLose = function() GameUI.DoGameOver() end,
            initialDarkSoul = Config.INITIAL_DARK_SOUL,
        })

        GameUI.UpdateHUD()

        -- 挂机时长恢复：用 afkLastClaimTime 计算（包含在线+离线全部时间）
        local claimTime = HeroData.stats.afkLastClaimTime or 0
        if claimTime > 0 then
            local totalAfkSecs = os.time() - claimTime
            if totalAfkSecs > 0 then
                -- 把挂机起点往前推，使计时器包含上次领取以来的全部时长
                GameUI._afkStartTime = time.elapsedTime - totalAfkSecs
                GameUI._afkLastDisplaySec = -1
                print("[StartGame] AFK restored " .. math.floor(totalAfkSecs / 60) .. " min since last claim")
            end
        end
        HeroData.lastSaveTime = os.time()
        HeroData.Save()

        -- 同步所有排行榜分数（兜底：补传之前可能失败的上传）
        local okLB, LBSync = pcall(require, "Game.LeaderboardData")
        if okLB and LBSync.SyncAll then LBSync.SyncAll() end

        -- 初始化加速系统（从存档恢复剩余时长，扣除离线流逝）
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

        -- 存档加载后刷新红点（UI 构建在存档加载之前，需要重新评估）
        GameUI.RefreshLaunchGiftRedDot()
        GameUI.RefreshActivityRedDot()
        GameUI.RefreshVaultRedDot()
        local TabNav = require("Game.TabNav")
        TabNav.RefreshRedDots()

        -- 时装签到：刷新红点（玩家手动签到，无自动标记）
        GameUI.RefreshCostumeSignInRedDot()
    end)
end

function Stop()
    SpeedBoost.Save()
    if vg then nvgDelete(vg) end
    if toastVg then nvgDelete(toastVg) end
    UI.Shutdown()
end

-- ============================================================================
-- 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function InitNanoVG()
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
end

function CalculateGridOffset()
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

function SubscribeToEvents()
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
    -- 原来由 HeroData.Save() 直接调用 TabNav，现在改为事件驱动
    local EventBus = require("Game.EventBus")
    local TabNav = require("Game.TabNav")
    EventBus.on(EventBus.EVENT.DATA_SAVED, function()
        TabNav.RefreshRedDots()
    end)
end

--- 窗口大小变化时重新计算网格偏移
function HandleScreenMode(eventType, eventData)
    CalculateGridOffset()
    Grid.InvalidateCache()
    print("[Event] ScreenMode changed, grid offset recalculated")
end

--- 调试快捷键
function HandleKeyDown(eventType, eventData)
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
    end
end

-- ============================================================================
-- 游戏逻辑更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if MiniGameUI.isActive() then
        _YangMG_Update(eventType, eventData)
        return
    end

    local rawDt = eventData["TimeStep"]:GetFloat()

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
        -- 更新塔
        Tower.Update(dt)

        -- 更新波次（生成敌人）— campaign 现在也通过 BM 运行
        if BattleManager.IsActive() then
            BattleManager.UpdateWaves(dt)
        end

        -- 更新敌人（移动）
        Enemy.Update(dt, Renderer.gridOffsetX, Renderer.gridOffsetY)

        -- 更新战斗（攻击、弹道）
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

    -- 更新云端存档系统（自动保存、脏标记、重试队列）
    SlotSaveSystem.Update(rawDt)
end

-- ============================================================================
-- 输入处理（拖拽系统）
-- ============================================================================

--- 将屏幕坐标转为逻辑坐标
local function ScreenToLogical(rawX, rawY)
    local dpr = graphics:GetDPR()
    return rawX / dpr, rawY / dpr
end

--- 更新拖拽目标格子信息
local function UpdateDragTarget(x, y)
    local ox = Renderer.gridOffsetX
    local oy = Renderer.gridOffsetY
    State.dragX = x
    State.dragY = y
    local col, row = Grid.ScreenToCell(x, y, ox, oy)
    State.dragTargetCol = col
    State.dragTargetRow = row

    -- 判断目标是否有效（在网格内、非路径格、不是原位）
    if col < 1 or col > Config.GRID_COLS or row < 1 or row > Config.GRID_ROWS then
        State.dragValid = false
    elseif Grid.IsPathCell(col, row) then
        State.dragValid = false
    elseif col == State.dragOriginCol and row == State.dragOriginRow then
        State.dragValid = false
    else
        State.dragValid = true
    end
end

--- 判定拖拽阈值（像素）
local DRAG_THRESHOLD = 10

--- 按下开始拖拽
local function HandlePointerDown(x, y)
    -- 非战斗页禁用拖拽
    if State.activeTab ~= "battle" then return end

    if State.phase ~= State.PHASE_PLAYING and State.phase ~= State.PHASE_WAVE_READY then
        return
    end

    local ox = Renderer.gridOffsetX
    local oy = Renderer.gridOffsetY
    local col, row = Grid.ScreenToCell(x, y, ox, oy)

    -- 检查是否按在塔上
    if col >= 1 and col <= Config.GRID_COLS and row >= 1 and row <= Config.GRID_ROWS then
        local tower = State.grid[col][row]
        if tower then
            -- 记录按下，等移动超过阈值才真正开始拖拽
            State.dragging = false
            State.dragPending = true
            State.dragTower = tower
            State.dragOriginCol = col
            State.dragOriginRow = row
            State.dragStartX = x
            State.dragStartY = y
            State.dragX = x
            State.dragY = y
            State.dragTargetCol = col
            State.dragTargetRow = row
            State.dragValid = false
            return
        end
    end

    -- 点击空白区域取消选中
    State.selectedTower = nil
end

--- 移动更新拖拽位置
local function HandlePointerMove(x, y)
    if State.activeTab ~= "battle" then return end
    if not State.dragPending and not State.dragging then return end

    -- 检查是否超过拖拽阈值
    if State.dragPending and not State.dragging then
        local dx = x - (State.dragStartX or x)
        local dy = y - (State.dragStartY or y)
        if math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD then
            State.dragging = true
            State.dragPending = false
        else
            return
        end
    end

    UpdateDragTarget(x, y)
end

--- 释放结束拖拽
local function HandlePointerUp(x, y)
    if State.activeTab ~= "battle" then return end

    -- 点击（未拖动）→ 选中/取消选中英雄
    if State.dragPending and not State.dragging then
        if State.dragTower then
            -- 点击同一个英雄 → 取消选中；点击不同英雄 → 切换选中
            if State.selectedTower == State.dragTower then
                State.selectedTower = nil
            else
                State.selectedTower = State.dragTower
            end
        end
        State.dragPending = false
        State.dragTower = nil
        return
    end

    if not State.dragging then return end

    UpdateDragTarget(x, y)

    -- 执行拖拽操作
    if State.dragValid and State.dragTower then
        Tower.HandleDrop(State.dragTower, State.dragTargetCol, State.dragTargetRow)
    end

    -- 清除拖拽状态（拖拽结束不保留选中）
    State.dragging = false
    State.dragPending = false
    State.dragTower = nil
    State.selectedTower = nil
end

-- 输入去重（移动端触屏会同时触发 Touch 和 Mouse 事件）
-- 策略：一旦收到 touch 事件，永久屏蔽合成的 mouse 事件
local touchDetected = false

---@param source string "mouse" | "touch"
---@return boolean blocked 是否应被忽略
local function InputDedup(source)
    if source == "touch" then
        touchDetected = true
        return false
    end
    -- source == "mouse"：如果已检测到触摸设备，屏蔽所有鼠标事件
    return touchDetected
end

-- 鼠标事件
function HandleMouseDown(eventType, eventData)
    if MiniGameUI.isActive() then
        _YangMG_MouseDown(eventType, eventData)
        return
    end
    if InputDedup("mouse") then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerDown(x, y)
end

function HandleMouseMove(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("mouse") then return end
    if not State.dragging and not State.dragPending then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerMove(x, y)
end

function HandleMouseUp(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("mouse") then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerUp(x, y)
end

-- 触摸事件
function HandleTouchBegin(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("touch") then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerDown(x, y)
end

function HandleTouchMove(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("touch") then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerMove(x, y)
end

function HandleTouchEnd(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("touch") then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerUp(x, y)
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
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
function HandleToastRender(eventType, eventData)
    if not toastVg then return end
    if MiniGameUI.isActive() then return end
    if IdleScreen.IsActive() then return end

    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr

    nvgBeginFrame(toastVg, logW, logH, dpr)
    Toast.Draw(toastVg, logW, toastFontId)
    nvgEndFrame(toastVg)
end
