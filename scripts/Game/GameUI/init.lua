-- Game/GameUI/init.lua
-- 暗黑塔防游戏 - UI 面板（门面模块）
-- 子模块: GameUI/Widgets, GameUI/Panels, GameUI/Stage, GameUI/Afk

local Config = require("Game.Config")
local EventBus = require("Game.EventBus")
local State = require("Game.State")
local AutoPlay = require("Game.AutoPlay")
local Tower = require("Game.Tower")
local Wave = require("Game.Wave")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local TabNav = require("Game.TabNav")
local HeroUI = require("Game.HeroUI")
local RecruitUI = require("Game.RecruitUI")
local FormatNum = require("Game.FormatUtil").FormatNum
local ChestUI = require("Game.ChestUI")
local ChestData = require("Game.ChestData")
local EquipUI = require("Game.EquipUI")
local EquipData = require("Game.EquipData")
local DungeonUI = require("Game.DungeonUI")
local ActivityUI = require("Game.ActivityUI")
local ActivityData = require("Game.ActivityData")
local LaunchGiftUI = require("Game.LaunchGiftUI")
local WeeklyActivityUI = require("Game.WeeklyActivityUI")
local MailboxUI = require("Game.MailboxUI")
local DailyTaskUI = require("Game.DailyTaskUI")
local LeaderboardUI = require("Game.LeaderboardUI")
local SpeedBoost = require("Game.SpeedBoostData")
local Toast = require("Game.Toast")
local ServerSelectUI = require("Game.ServerSelectUI")
local ExchangeShopUI = require("Game.ExchangeShopUI")
local AdReliefUI     = require("Game.AdReliefUI")
local AdReliefData   = require("Game.AdReliefData")
local AdHelper       = require("Game.AdHelper")
local CostumeSignInUI   = require("Game.CostumeSignInUI")
local CostumeSignInData = require("Game.CostumeSignInData")
local AdDashboardUI  = require("Game.AdDashboardUI")
local MiniGameUI     = require("Game.MiniGameUI")

local GameUI = {}

---@type any
local UI = nil
---@type any
local uiRoot = nil
---@type any
local tabNavRoot = nil  -- TabNav 根面板引用，用于 ReturnToServerSelect 时清理

-- 共享上下文
local ctx = {
    UI = nil,       -- 延迟设置
    uiRoot = nil,   -- 延迟设置
    lastInfoTowerId = nil,
    lastInfoTowerStar = nil,
}

-- ========== HUD 缓存（避免每帧 FindById + 无变化 SetText） ==========
local hudCache = {
    -- 缓存 FindById 结果（UI 重建时清空）
    refs = nil,
    -- 缓存上次设置的值（值不变时跳过 SetText/SetStyle）
    darkSouls = nil,
    crystal = nil,
    essence = nil,
    waveText = nil,
    summonCost = nil,
    canSummon = nil,
    -- 自动按钮状态缓存
    autoSummonState = nil,
    autoMergeState = nil,
    autoDeployState = nil,
    speedState = nil,
    speedText = nil,
}

--- 获取缓存的 UI 引用（首次或重建后查找一次）
local function GetHudRefs()
    if hudCache.refs and uiRoot then return hudCache.refs end
    if not uiRoot then return nil end
    hudCache.refs = {
        bottomGoldLabel  = uiRoot:FindById("bottomGoldLabel"),
        hudCrystalLabel  = uiRoot:FindById("hudCrystalLabel"),
        hudEssenceLabel  = uiRoot:FindById("hudEssenceLabel"),
        waveLabel        = uiRoot:FindById("waveLabel"),
        summonBtn        = uiRoot:FindById("summonBtn"),
        summonCostLabel  = uiRoot:FindById("summonCostLabel"),
        heroInfoPanel    = uiRoot:FindById("heroInfoPanel"),
        autoSummonBtn    = uiRoot:FindById("autoSummonBtn"),
        autoMergeBtn     = uiRoot:FindById("autoMergeBtn"),
        autoDeployBtn    = uiRoot:FindById("autoDeployBtn"),
        speedBoostBtn    = uiRoot:FindById("speedBoostBtn"),
        speedBoostLabel  = uiRoot:FindById("speedBoostLabel"),
        exitDungeonBtn   = uiRoot:FindById("exitDungeonBtn"),
        skipBossBtn      = uiRoot:FindById("skipBossBtn"),
        skipBossLabel    = uiRoot:FindById("skipBossLabel"),
    }
    return hudCache.refs
end

--- 清除 HUD 缓存（UI 重建时调用）
function GameUI.InvalidateHudCache()
    hudCache.refs = nil
    hudCache.darkSouls = nil
    hudCache.crystal = nil
    hudCache.essence = nil
    hudCache.waveText = nil
    hudCache.summonCost = nil
    hudCache.canSummon = nil
    hudCache.autoSummonState = nil
    hudCache.autoMergeState = nil
    hudCache.autoDeployState = nil
    hudCache.speedState = nil
    hudCache.speedText = nil
end

-- FormatNum → 使用 FormatUtil.FormatNum
ctx.FormatNum = FormatNum

function GameUI.Init(uiModule)
    UI = uiModule
    ctx.UI = uiModule

    -- 货币变化 → 自动刷新 HUD 货币栏
    -- 只有 HUD 关心的 3 种货币才触发刷新，其他货币变化（碎片/装备材料等）跳过
    local HUD_CURRENCIES = { dark_soul = true, nether_crystal = true, shadow_essence = true }
    EventBus.on(EventBus.EVENT.CURRENCY_CHANGED, function(data)
        if data and not HUD_CURRENCIES[data.type] then return end
        GameUI.UpdateHUD()
    end)

    -- 注册 BattleFlow UI 回调
    local BattleFlow = require("Game.BattleFlow")
    BattleFlow.RegisterHooks({
        switchTab      = function(tab) TabNav.SwitchTo(tab) end,
        updateHUD      = function() GameUI.UpdateHUD() end,
        refreshDungeon = function() DungeonUI.Refresh() end,
        doStageClear   = function() GameUI.DoStageClear() end,
        doGameOver     = function() GameUI.DoGameOver() end,
    })
end

-- 加载子模块
require("Game.GameUI.Widgets")(GameUI, ctx)
require("Game.GameUI.Panels")(GameUI, ctx)
require("Game.GameUI.Stage")(GameUI, ctx)
require("Game.GameUI.Afk")(GameUI, ctx)

--- 更新 HUD 上的文本（缓存引用 + 值比对，跳过无变化的 SetText/SetStyle）
function GameUI.UpdateHUD()
    if not uiRoot then return end

    local refs = GetHudRefs()
    if not refs then return end

    -- ======== 货币文本（仅值变化时更新） ========
    local darkSouls = Currency.GetDarkSouls()
    if darkSouls ~= hudCache.darkSouls then
        hudCache.darkSouls = darkSouls
        if refs.bottomGoldLabel then refs.bottomGoldLabel:SetText(tostring(darkSouls)) end
    end

    local crystal = Currency.Get("nether_crystal")
    if crystal ~= hudCache.crystal then
        hudCache.crystal = crystal
        if refs.hudCrystalLabel then refs.hudCrystalLabel:SetText(FormatNum(crystal)) end
    end

    local essence = Currency.Get("shadow_essence")
    if essence ~= hudCache.essence then
        hudCache.essence = essence
        if refs.hudEssenceLabel then refs.hudEssenceLabel:SetText(FormatNum(essence)) end
    end

    -- ======== 波次标签（仅文本变化时更新） ========
    if refs.waveLabel then
        local waveText
        local BM = require("Game.BattleManager")
        if BM.IsActive() then
            waveText = BM.GetLabel()
        else
            local typeTag = ""
            if State.waveType == "boss" then typeTag = " BOSS"
            elseif State.waveType == "elite" then typeTag = " 精英"
            end
            waveText = State.currentStage .. "-" .. State.currentWave .. typeTag
        end
        if waveText ~= hudCache.waveText then
            hudCache.waveText = waveText
            refs.waveLabel:SetText(waveText)
        end
    end

    -- ======== 召唤按钮（仅状态变化时更新） ========
    if refs.summonBtn then
        local canSummon = Tower.CanSummon()
        if canSummon ~= hudCache.canSummon then
            hudCache.canSummon = canSummon
            if canSummon then
                refs.summonBtn:SetStyle({ backgroundColor = { 100, 60, 200, 255 } })
            else
                refs.summonBtn:SetStyle({ backgroundColor = { 60, 40, 80, 200 } })
            end
        end
    end

    if refs.summonCostLabel then
        local cost = Tower.GetSummonCost()
        if cost ~= hudCache.summonCost then
            hudCache.summonCost = cost
            refs.summonCostLabel:SetText(tostring(cost))
        end
    end

    -- ======== 英雄信息面板（切换/升星重建结构，同一英雄只增量更新数值） ========
    if refs.heroInfoPanel then
        local sel = State.selectedTower
        if sel then
            local switched = (sel.id ~= ctx.lastInfoTowerId) or (sel.star ~= ctx.lastInfoTowerStar)
            if switched then
                -- 英雄切换或升星：完全重建面板
                ctx.lastInfoTowerId = sel.id
                ctx.lastInfoTowerStar = sel.star
                refs.heroInfoPanel:ClearChildren()
                local content = GameUI.BuildHeroInfoContent(sel)
                for _, child in ipairs(content) do
                    if child then
                        refs.heroInfoPanel:AddChild(child)
                    end
                end
            else
                -- 同一英雄：只增量更新动态数值（攻击/攻速/暴击等）
                local now = os.clock()
                local elapsed = now - (ctx.heroInfoLastTime or 0)
                if elapsed >= 0.3 then
                    ctx.heroInfoLastTime = now
                    GameUI.UpdateHeroInfoValues(sel, refs.heroInfoPanel)
                end
            end
            refs.heroInfoPanel:SetVisible(true)
        else
            if ctx.lastInfoTowerId then
                ctx.lastInfoTowerId = nil
                ctx.lastInfoTowerStar = nil
                ctx.heroInfoLastTime = nil
                refs.heroInfoPanel:ClearChildren()
            end
            refs.heroInfoPanel:SetVisible(false)
        end
    end

    -- ======== 退出副本按钮（仅副本模式显示，主线不显示） ========
    if refs.exitDungeonBtn then
        local BM = require("Game.BattleManager")
        local showExit = BM.IsActive() and BM.GetMode() ~= "campaign"
        refs.exitDungeonBtn:SetVisible(showExit)
    end

    -- ======== 自动按钮状态（仅状态变化时更新） ========
    if refs.autoSummonBtn then
        local st = AutoPlay.autoSummon and "on" or "off"
        if st ~= hudCache.autoSummonState then
            hudCache.autoSummonState = st
            if st == "on" then
                refs.autoSummonBtn:SetText("自动召唤:开")
                refs.autoSummonBtn:SetStyle({ backgroundColor = { 100, 60, 200, 255 }, fontColor = { 255, 255, 255, 255 } })
            else
                refs.autoSummonBtn:SetText("自动召唤:关")
                refs.autoSummonBtn:SetStyle({ backgroundColor = { 60, 50, 80, 200 }, fontColor = { 180, 160, 220, 255 } })
            end
        end
    end

    if refs.autoMergeBtn then
        local st = AutoPlay.autoMerge and "on" or "off"
        if st ~= hudCache.autoMergeState then
            hudCache.autoMergeState = st
            if st == "on" then
                refs.autoMergeBtn:SetText("自动合成:开")
                refs.autoMergeBtn:SetStyle({ backgroundColor = { 100, 60, 200, 255 }, fontColor = { 255, 255, 255, 255 } })
            else
                refs.autoMergeBtn:SetText("自动合成:关")
                refs.autoMergeBtn:SetStyle({ backgroundColor = { 60, 50, 80, 200 }, fontColor = { 180, 160, 220, 255 } })
            end
        end
    end

    if refs.autoDeployBtn then
        local st = AutoPlay.autoDeploy and "on" or "off"
        if st ~= hudCache.autoDeployState then
            hudCache.autoDeployState = st
            if st == "on" then
                refs.autoDeployBtn:SetText("自动布阵:开")
                refs.autoDeployBtn:SetStyle({ backgroundColor = { 60, 160, 100, 255 }, fontColor = { 255, 255, 255, 255 } })
            else
                refs.autoDeployBtn:SetText("自动布阵:关")
                refs.autoDeployBtn:SetStyle({ backgroundColor = { 60, 50, 80, 200 }, fontColor = { 180, 160, 220, 255 } })
            end
        end
    end

    -- ======== 加速按钮（仅状态/文本变化时更新） ========
    if refs.speedBoostBtn then
        local active = SpeedBoost.enabled and SpeedBoost.remaining > 0
        local st = active and "on" or "off"
        if st ~= hudCache.speedState then
            hudCache.speedState = st
            if active then
                refs.speedBoostBtn:SetStyle({ backgroundColor = { 200, 120, 40, 255 }, borderColor = { 255, 200, 60, 220 } })
            else
                refs.speedBoostBtn:SetStyle({ backgroundColor = { 60, 50, 80, 200 }, borderColor = { 200, 160, 60, 180 } })
            end
        end
        if refs.speedBoostLabel then
            local spdText = active and ("x2 " .. SpeedBoost.FormatRemaining()) or "x2"
            if spdText ~= hudCache.speedText then
                hudCache.speedText = spdText
                refs.speedBoostLabel:SetText(spdText)
            end
        end
    end

    -- ======== 挑战Boss按钮（仅主线模式显示） ========
    if refs.skipBossBtn then
        local BM2 = require("Game.BattleManager")
        local isCampaign = (not BM2.IsActive()) or BM2.GetMode() == "campaign"
        refs.skipBossBtn:SetVisible(isCampaign)
        local st = State.skipBoss and "off" or "on"
        if st ~= hudCache.skipBossState then
            hudCache.skipBossState = st
            if State.skipBoss then
                -- 跳过Boss（关闭挑战）
                refs.skipBossBtn:SetStyle({ backgroundColor = { 50, 50, 50, 200 }, borderColor = { 120, 120, 120, 160 } })
            else
                -- 挑战Boss（开启）
                refs.skipBossBtn:SetStyle({ backgroundColor = { 160, 30, 30, 220 }, borderColor = { 220, 60, 60, 200 } })
            end
            if refs.skipBossLabel then
                refs.skipBossLabel:SetText(State.skipBoss and "挑战Boss:关" or "挑战Boss:开")
                refs.skipBossLabel:SetStyle({
                    fontColor = State.skipBoss and { 160, 160, 160, 255 } or { 255, 200, 200, 255 },
                })
            end
        end
    end
end

-- 获取空位（代理函数）
function Tower.GetEmptyCells()
    local Grid = require("Game.Grid")
    return Grid.GetEmptyCells()
end

--- 创建战斗页内容
function GameUI.CreateBattlePage()
    return UI.Panel {
        id = "battlePage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "box-none",
        children = {
            GameUI.CreateHUD(),
            GameUI.CreateCurrencyDisplay(),
            GameUI.CreateHeroInfoPanel(),
            GameUI.CreateBottomBar(),
            GameUI.CreateWaveReadyPanel(),
            GameUI.CreateGameOverPanel(),
            GameUI.CreateStageClearPanel(),
            GameUI.CreateAfkButton(),
            GameUI.CreateMenuPanel(),
            -- 战报按钮（在x2加速上方）
            UI.Panel {
                id = "damageStatsBtn",
                position = "absolute",
                right = 12, bottom = 154,
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 120, 90, 180, 160 },
                backgroundColor = { 30, 22, 50, 210 },
                pointerEvents = "auto",
                alignItems = "center",
                onClick = function(self)
                    GameUI.ShowDamageStatsPanel(true)
                end,
                children = {
                    UI.Label {
                        text = "战报",
                        fontSize = 11,
                        fontColor = { 200, 170, 240, 255 },
                    },
                },
            },
            -- x2 加速按钮（独立定位，在自动召唤上方）
            UI.Panel {
                id = "speedBoostBtn",
                position = "absolute",
                right = 12, bottom = 114,
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 200, 160, 60, 180 },
                backgroundColor = { 60, 50, 80, 200 },
                pointerEvents = "auto",
                alignItems = "center",
                onClick = function(self)
                    GameUI.ShowSpeedBoostDialog(true)
                end,
                children = {
                    UI.Label {
                        id = "speedBoostLabel",
                        text = "x2",
                        fontSize = 11,
                        fontColor = { 200, 160, 80, 255 },
                        fontWeight = "bold",
                    },
                },
            },
        }
    }
end

--- 标签切换回调
local function OnTabSwitch(fromKey, toKey)
    if toKey == "battle" then Tower.RefreshAllStats() end
    if toKey == "hero" then HeroUI.Refresh() end
    if toKey == "equip" then EquipUI.Refresh() end
    if toKey == "chest" then ChestUI.Refresh() end
    if toKey == "dungeon" then DungeonUI.Refresh() end
end

--- 创建预加载根容器（仅承载 ServerSelect，不创建游戏页面）
function GameUI.CreatePreGameRoot()
    uiRoot = UI.Panel {
        id = "preGameRoot",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
    }
    ctx.uiRoot = uiRoot
    UI.SetRoot(uiRoot)
    print("[GameUI] PreGameRoot created (no game tabs)")
end

--- 清理 CreateUI 创建的所有子节点（ReturnToServerSelect 时调用）
local function CleanupGameUI()
    -- 移除 tabNavRoot
    if tabNavRoot then
        uiRoot:RemoveChild(tabNavRoot)
        tabNavRoot = nil
    end
    -- 移除所有 overlay 引用
    local overlayKeys = {
        "_idleRewardPanel", "_recruitPage", "_activityPage",
        "_launchGiftPage", "_weeklyActivityPage", "_mailboxPage",
        "_dailyTaskPage", "_leaderboardPage", "_exchangeShopPage",
        "_adReliefPage", "_costumeSignInPage", "_miniGamePage",
        "_adDashboardPage", "_speedBoostDialog", "_adTicketConfirmDialog",
        "_userIdWrap", "_versionWrap",
    }
    for _, key in ipairs(overlayKeys) do
        if GameUI[key] then
            uiRoot:RemoveChild(GameUI[key])
            GameUI[key] = nil
        end
    end
    print("[GameUI] CleanupGameUI: old nodes removed")
end

--- 创建游戏 UI（多页架构）—— 在存档加载成功后调用
function GameUI.CreateUI()
    -- 如果已经创建过，先清理旧节点（防止 ReturnToServerSelect 后重复创建）
    if tabNavRoot then
        CleanupGameUI()
    end

    local battlePage = GameUI.CreateBattlePage()
    local heroPage = HeroUI.CreatePage(UI)
    local equipPage = EquipUI.CreatePage(UI)
    local chestPage = ChestUI.CreatePage(UI)
    local dungeonPage = DungeonUI.CreatePage(UI)

    tabNavRoot = TabNav.Create(UI, {
        hero = heroPage,
        equip = equipPage,
        battle = battlePage,
        dungeon = dungeonPage,
        chest = chestPage,
    }, OnTabSwitch)

    -- 将 TabNav 根面板插入已有的 uiRoot（而非替换），
    -- 这样 ServerSelect 等已添加到 uiRoot 的浮层继续有效
    uiRoot:AddChild(tabNavRoot)

    GameUI.InvalidateHudCache()

    -- 挂机收益弹窗：放在 uiRoot 层级，确保遮罩覆盖右侧按钮
    GameUI._idleRewardPanel = GameUI.CreateIdleRewardPanel()
    uiRoot:AddChild(GameUI._idleRewardPanel)

    GameUI._recruitPage = GameUI.CreateRecruitOverlay()
    uiRoot:AddChild(GameUI._recruitPage)

    GameUI._activityPage = GameUI.CreateActivityOverlay()
    uiRoot:AddChild(GameUI._activityPage)

    GameUI._launchGiftPage = GameUI.CreateLaunchGiftOverlay()
    uiRoot:AddChild(GameUI._launchGiftPage)

    GameUI._weeklyActivityPage = GameUI.CreateWeeklyActivityOverlay()
    uiRoot:AddChild(GameUI._weeklyActivityPage)

    GameUI._mailboxPage = GameUI.CreateMailboxOverlay()
    uiRoot:AddChild(GameUI._mailboxPage)

    GameUI._dailyTaskPage = GameUI.CreateDailyTaskOverlay()
    uiRoot:AddChild(GameUI._dailyTaskPage)

    GameUI._leaderboardPage = LeaderboardUI.CreateOverlay(UI)
    uiRoot:AddChild(GameUI._leaderboardPage)

    GameUI._exchangeShopPage = GameUI.CreateExchangeShopOverlay()
    uiRoot:AddChild(GameUI._exchangeShopPage)

    GameUI._adReliefPage = GameUI.CreateAdReliefOverlay()
    uiRoot:AddChild(GameUI._adReliefPage)

    GameUI._costumeSignInPage = GameUI.CreateCostumeSignInOverlay()
    uiRoot:AddChild(GameUI._costumeSignInPage)

    GameUI._miniGamePage = GameUI.CreateMiniGameOverlay()
    uiRoot:AddChild(GameUI._miniGamePage)

    GameUI._adDashboardPage = AdDashboardUI.CreateOverlay(UI)
    uiRoot:AddChild(GameUI._adDashboardPage)

    GameUI._speedBoostDialog = GameUI.CreateSpeedBoostDialog()
    uiRoot:AddChild(GameUI._speedBoostDialog)

    -- 免广告券确认弹窗放在所有 overlay 之后，确保 z-order 最高
    GameUI._adTicketConfirmDialog = GameUI.CreateAdTicketConfirmDialog()
    uiRoot:AddChild(GameUI._adTicketConfirmDialog)

    -- 注册免广告券弹窗处理器到 AdHelper
    AdHelper.SetTicketConfirmHandler(function(onConfirm)
        GameUI.ShowAdTicketConfirm(onConfirm)
    end)

    -- 右上角固定显示用户ID（保存引用，供 z-order 重排使用）
    local userIdLabel = UI.Label {
        id = "fixedUserId",
        text = clientCloud and ("ID: " .. tostring(clientCloud.userId)) or "",
        fontSize = 10,
        fontColor = { 180, 180, 200, 150 },
    }
    GameUI._userIdWrap = UI.Panel {
        position = "absolute",
        top = 4, right = 8,
        pointerEvents = "none",
        children = { userIdLabel },
    }
    uiRoot:AddChild(GameUI._userIdWrap)

    -- 左下角固定显示版本号（放在 TabBar 上方，避免被遮挡）
    local versionLabel = UI.Label {
        id = "fixedVersion",
        text = "v1.0.63",
        fontSize = 10,
        fontColor = { 160, 160, 180, 130 },
    }
    GameUI._versionWrap = UI.Panel {
        position = "absolute",
        bottom = TabNav.GetBarHeight() + 4, left = 8,
        pointerEvents = "none",
        children = { versionLabel },
    }
    uiRoot:AddChild(GameUI._versionWrap)

    -- uiRoot 已在 CreatePreGameRoot() 中设为 UI root，无需再次调用 UI.SetRoot
    -- 将 ServerSelect 重新添加到最上层（确保在 TabNav 和所有 overlay 之上）
    if GameUI._serverSelectPage then
        uiRoot:AddChild(GameUI._serverSelectPage)
    end

    return uiRoot
end

--- 创建区服选择浮层（由 main.lua 调用）
---@param onStart function  选服后开始游戏回调 function(serverId)
---@param slotMeta table|nil  存档元数据（来自 SlotSaveSystem）
function GameUI.CreateServerSelect(onStart, slotMeta)
    GameUI._serverSelectPage = ServerSelectUI.CreatePage(UI, function(serverId)
        GameUI.ShowServerSelect(false)
        if onStart then onStart(serverId) end
    end, slotMeta)
    uiRoot:AddChild(GameUI._serverSelectPage)

    -- 重新添加版本号和用户ID标签，确保始终在最上层（不被 serverSelectPage 遮挡）
    if GameUI._userIdWrap then uiRoot:AddChild(GameUI._userIdWrap) end
    if GameUI._versionWrap then uiRoot:AddChild(GameUI._versionWrap) end
end

--- 显示/隐藏区服选择界面
function GameUI.ShowServerSelect(show)
    if GameUI._serverSelectPage then
        GameUI._serverSelectPage:SetVisible(show)
    end
    -- 区服选择期间隐藏底部标签栏
    TabNav.SetBarVisible(not show)
end

--- 返回区服选择：保存并卸载当前槽位，重置游戏状态，显示区服选择
function GameUI.ReturnToServerSelect()
    local SlotSave = require("Game.SlotSaveSystem")
    local LootDrop = require("Game.LootDrop")
    local Combat   = require("Game.Combat")

    -- 先收集残留掉落物，防止丢失奖励
    LootDrop.CollectAll()

    -- 保存并卸载当前槽位（异步）
    SlotSave.SaveAndUnload(function(success)
        -- 重置游戏状态
        State.Reset()
        Combat.Reset()

        -- 清理旧的游戏 UI 节点（tabNavRoot + 所有 overlay），防止重入时累积
        CleanupGameUI()

        -- 销毁旧的区服选择浮层
        if GameUI._serverSelectPage then
            uiRoot:RemoveChild(GameUI._serverSelectPage)
            GameUI._serverSelectPage = nil
        end

        -- 重新获取最新元数据并创建区服选择
        local freshMeta = SlotSave.GetMeta()
        GameUI.CreateServerSelect(function(serverId)
            StartGame(serverId)  -- 全局函数，定义在 main.lua
        end, freshMeta)
        GameUI.ShowServerSelect(true)

        -- 重置 activeTab，确保下次进入时从战斗页开始
        State.activeTab = "battle"
    end)
end

--- 获取 UI 根节点（供外部模块挂载弹窗）
function GameUI.GetUIRoot()
    return uiRoot
end

--- 创建招募页浮层
function GameUI.CreateRecruitOverlay()
    -- 返回按钮由 RecruitUI 内部标签栏管理
    RecruitUI.SetOnBack(function()
        GameUI.ShowRecruitOverlay(false)
    end)

    local recruitContent = RecruitUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "recruitOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = {
            recruitContent,
        },
    }
    return overlay
end

function GameUI.ShowRecruitOverlay(show)
    if GameUI._recruitPage then
        GameUI._recruitPage:SetVisible(show)
        if show then RecruitUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
end

function GameUI.CreateActivityOverlay()
    ActivityUI.SetOnBack(function()
        GameUI.ShowActivityOverlay(false)
    end)

    local activityContent = ActivityUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "activityOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = { activityContent },
    }
    return overlay
end

function GameUI.ShowActivityOverlay(show)
    if GameUI._activityPage then
        GameUI._activityPage:SetVisible(show)
        if show then ActivityUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
    -- 关闭时刷新红点
    if not show then
        GameUI.RefreshActivityRedDot()
        GameUI.RefreshVaultRedDot()
    end
end

--- 直接打开活动页并跳到深渊金库标签
function GameUI.ShowVaultOverlay()
    ActivityUI.SetTab("vault")
    GameUI.ShowActivityOverlay(true)
end

--- 刷新金库入口红点
function GameUI.RefreshVaultRedDot()
    if not uiRoot then return end
    local VD = require("Game.VaultData")
    VD.Load()
    VD.Settle()
    local redDot = uiRoot:FindById("vaultRedDot")
    if redDot then redDot:SetVisible(VD.HasPending()) end
end

function GameUI.RefreshActivityRedDot()
    if not uiRoot then return end
    local AD  = require("Game.ActivityData")
    local ARD = require("Game.AccumulatedRewardData")
    local DDD = require("Game.DailyDealData")
    local redDot = uiRoot:FindById("activityRedDot")
    if redDot then
        redDot:SetVisible(AD.HasUnclaimedReward() or ARD.HasUnclaimed() or DDD.HasUnclaimed())
    end
end

-- ============================================================================
-- 兑换商店 Overlay
-- ============================================================================

function GameUI.CreateExchangeShopOverlay()
    ExchangeShopUI.SetOnBack(function()
        GameUI.ShowExchangeShopOverlay(false)
    end)
    local content = ExchangeShopUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "exchangeShopOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = { content },
    }
    return overlay
end

function GameUI.ShowExchangeShopOverlay(show)
    if GameUI._exchangeShopPage then
        GameUI._exchangeShopPage:SetVisible(show)
        if show then ExchangeShopUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
    -- 关闭时刷新红点
    if not show then GameUI.RefreshExchangeShopRedDot() end
end

function GameUI.RefreshExchangeShopRedDot()
    if not uiRoot then return end
    local ESD = require("Game.ExchangeShopData")
    local redDot = uiRoot:FindById("exchangeShopRedDot")
    if redDot then redDot:SetVisible(ESD.HasAvailable()) end
end

-- ============================================================================
-- 减负中心 Overlay
-- ============================================================================

function GameUI.CreateAdReliefOverlay()
    AdReliefUI.SetOnBack(function()
        GameUI.ShowAdReliefOverlay(false)
    end)
    local content = AdReliefUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "adReliefOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = { content },
    }
    return overlay
end

function GameUI.ShowAdReliefOverlay(show)
    if GameUI._adReliefPage then
        GameUI._adReliefPage:SetVisible(show)
        if show then AdReliefUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
    -- 关闭时刷新红点
    if not show then GameUI.RefreshAdReliefRedDot() end
end

function GameUI.RefreshAdReliefRedDot()
    if not uiRoot then return end
    local redDot = uiRoot:FindById("adReliefRedDot")
    if redDot then redDot:SetVisible(AdReliefData.HasClaimable()) end
end

-- ============================================================================
-- 时装签到 Overlay
-- ============================================================================

function GameUI.CreateCostumeSignInOverlay()
    CostumeSignInUI.SetOnBack(function()
        GameUI.ShowCostumeSignInOverlay(false)
    end)
    local content = CostumeSignInUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "costumeSignInOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = { content },
    }
    return overlay
end

function GameUI.ShowCostumeSignInOverlay(show)
    if GameUI._costumeSignInPage then
        GameUI._costumeSignInPage:SetVisible(show)
        if show then
            CostumeSignInUI.Refresh()
        end
    end
    TabNav.SetBarVisible(not show)
    if not show then GameUI.RefreshCostumeSignInRedDot() end
end


-- ============================================================================
-- 小游戏 Overlay
-- ============================================================================

function GameUI.CreateMiniGameOverlay()
    MiniGameUI.SetOnBack(function()
        GameUI.ShowMiniGameOverlay(false)
    end)
    -- 小游戏启动时隐藏所有宿主 UI
    MiniGameUI.SetOnGameStart(function()
        if uiRoot then uiRoot:SetVisible(false) end
    end)
    -- 小游戏结束时恢复宿主 UI 并回到小游戏列表
    MiniGameUI.SetOnGameEnd(function(result)
        if uiRoot then uiRoot:SetVisible(true) end
        -- 回到小游戏列表页（overlay 已经是打开状态）
        MiniGameUI.Refresh()
    end)
    local content = MiniGameUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "miniGameOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = { content },
    }
    return overlay
end

function GameUI.ShowMiniGameOverlay(show)
    if GameUI._miniGamePage then
        GameUI._miniGamePage:SetVisible(show)
        if show then
            MiniGameUI.Refresh()
        end
    end
    TabNav.SetBarVisible(not show)
end

function GameUI.RefreshCostumeSignInRedDot()
    if not uiRoot then return end
    local active = CostumeSignInData.IsEventActive()
    -- 刷新入口按钮可见性（存档加载后才能确定活动状态）
    local btn = uiRoot:FindById("costumeSignInBtn")
    if btn then btn:SetVisible(active) end
    -- 刷新红点
    local redDot = uiRoot:FindById("costumeSignInRedDot")
    if redDot then redDot:SetVisible(active and CostumeSignInData.HasClaimable()) end
end

-- ============================================================================
-- 免广告券确认弹窗
-- ============================================================================

--- 当前弹窗回调
---@type fun(useTicket:boolean)|nil
GameUI._adTicketConfirmCb = nil

function GameUI.CreateAdTicketConfirmDialog()
    return UI.Panel {
        id = "adTicketConfirmDialog",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 10000,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function(self)
            -- 点遮罩关闭弹窗（不触发任何操作）
            GameUI._adTicketConfirmCb = nil
            self:SetVisible(false)
        end,
        children = {
            UI.Panel {
                width = 260,
                paddingTop = 20, paddingBottom = 20,
                paddingLeft = 20, paddingRight = 20,
                gap = 12,
                backgroundColor = { 20, 25, 50, 245 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 100, 220, 180, 200 },
                alignItems = "center",
                pointerEvents = "auto",
                children = {
                    -- 右上角关闭按钮
                    UI.Panel {
                        position = "absolute",
                        top = 6, right = 6,
                        width = 28, height = 28,
                        borderRadius = 14,
                        justifyContent = "center",
                        alignItems = "center",
                        onClick = function(self)
                            GameUI._adTicketConfirmCb = nil
                            GameUI._adTicketConfirmDialog:SetVisible(false)
                        end,
                        children = {
                            UI.Label {
                                text = "X",
                                fontSize = 16,
                                fontColor = { 180, 170, 200, 200 },
                            },
                        },
                    },
                    UI.Label {
                        text = "使用免广告券?",
                        fontSize = 18,
                        fontColor = { 220, 200, 255, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        id = "adTicketConfirmCount",
                        text = "剩余: 0张",
                        fontSize = 14,
                        fontColor = { 100, 220, 180, 200 },
                    },
                    UI.Label {
                        text = "使用1张免广告券可跳过本次广告",
                        fontSize = 12,
                        fontColor = { 160, 150, 180, 180 },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "90%", height = 1,
                        backgroundColor = { 100, 70, 160, 80 },
                    },
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 12,
                        children = {
                            -- 看广告
                            UI.Panel {
                                paddingLeft = 20, paddingRight = 20,
                                paddingTop = 10, paddingBottom = 10,
                                backgroundColor = { 60, 50, 80, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 120, 100, 160, 150 },
                                justifyContent = "center",
                                alignItems = "center",
                                onClick = function(self)
                                    if GameUI._adTicketConfirmCb then
                                        GameUI._adTicketConfirmCb(false)
                                        GameUI._adTicketConfirmCb = nil
                                    end
                                    GameUI._adTicketConfirmDialog:SetVisible(false)
                                end,
                                children = {
                                    UI.Label {
                                        text = "看广告",
                                        fontSize = 14,
                                        fontColor = { 200, 190, 220, 255 },
                                    },
                                },
                            },
                            -- 使用券
                            UI.Panel {
                                paddingLeft = 20, paddingRight = 20,
                                paddingTop = 10, paddingBottom = 10,
                                backgroundColor = { 100, 220, 180, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 140, 255, 200, 255 },
                                justifyContent = "center",
                                alignItems = "center",
                                onClick = function(self)
                                    if GameUI._adTicketConfirmCb then
                                        GameUI._adTicketConfirmCb(true)
                                        GameUI._adTicketConfirmCb = nil
                                    end
                                    GameUI._adTicketConfirmDialog:SetVisible(false)
                                end,
                                children = {
                                    UI.Label {
                                        text = "使用券",
                                        fontSize = 14,
                                        fontColor = { 10, 40, 30, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 显示免广告券确认弹窗
---@param onConfirm fun(useTicket:boolean)
function GameUI.ShowAdTicketConfirm(onConfirm)
    GameUI._adTicketConfirmCb = onConfirm
    -- 更新券数量显示
    if uiRoot then
        local countLabel = uiRoot:FindById("adTicketConfirmCount")
        if countLabel then
            countLabel:SetText("剩余: " .. AdReliefData.GetTickets() .. "张")
        end
    end
    if GameUI._adTicketConfirmDialog then
        GameUI._adTicketConfirmDialog:SetVisible(true)
    end
end

function GameUI.CreateLaunchGiftOverlay()
    local content = LaunchGiftUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "launchGiftOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = {
            content,
            -- 左下角返回键（与 RecruitOverlay 一致）
            UI.Panel {
                position = "absolute",
                left = 8, bottom = 120,
                pointerEvents = "auto",
                children = {
                    UI.Button {
                        text = "返回",
                        fontSize = 20,
                        width = 90,
                        height = 54,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function()
                            GameUI.ShowLaunchGiftOverlay(false)
                        end,
                    },
                },
            },
        },
    }
    return overlay
end

function GameUI.ShowLaunchGiftOverlay(show)
    if GameUI._launchGiftPage then
        GameUI._launchGiftPage:SetVisible(show)
        if show then LaunchGiftUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
    -- 关闭时刷新红点
    if not show and uiRoot then
        local LaunchGiftData = require("Game.LaunchGiftData")
        local redDot = uiRoot:FindById("launchGiftRedDot")
        if redDot then redDot:SetVisible(LaunchGiftData.HasClaimable()) end
    end
end

--- 刷新好礼按钮红点（存档加载后调用）
function GameUI.RefreshLaunchGiftRedDot()
    if not uiRoot then return end
    local LaunchGiftData = require("Game.LaunchGiftData")
    local redDot = uiRoot:FindById("launchGiftRedDot")
    if redDot then redDot:SetVisible(LaunchGiftData.HasClaimable()) end
    -- 同时刷新按钮可见性（活动可能已过期）
    local btn = uiRoot:FindById("launchGiftBtn")
    if btn then
        local active = LaunchGiftData.IsActive()
        btn:SetVisible(active)
        -- 用 YGDisplayNone 彻底从布局中移除，避免留空位
        YGNodeStyleSetDisplay(btn.node, active and YGDisplayFlex or YGDisplayNone)
    end
end

-- ============================================================================
-- 单周活动 Overlay
-- ============================================================================

function GameUI.CreateWeeklyActivityOverlay()
    local content = WeeklyActivityUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "weeklyActivityOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 12, 10, 25, 250 },
        pointerEvents = "auto",
        visible = false,
        children = {
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                overflow = "hidden",
                pointerEvents = "box-none",
                children = { content },
            },
            UI.Panel {
                width = "100%",
                height = 60,
                flexShrink = 0,
                paddingTop = 8, paddingBottom = 8,
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = { 12, 10, 25, 250 },
                borderTopWidth = 1,
                borderColor = { 80, 60, 120, 60 },
                justifyContent = "center",
                pointerEvents = "auto",
                children = {
                    UI.Button {
                        text = "返回",
                        fontSize = 16,
                        width = "100%",
                        height = 44,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function()
                            GameUI.ShowWeeklyActivityOverlay(false)
                        end,
                    },
                },
            },
        },
    }
    return overlay
end

function GameUI.ShowWeeklyActivityOverlay(show)
    if GameUI._weeklyActivityPage then
        GameUI._weeklyActivityPage:SetVisible(show)
        if show then WeeklyActivityUI.Refresh() end
    end
    -- 显示时隐藏底部标签栏，关闭时恢复
    TabNav.SetBarVisible(not show)
    if not show and uiRoot then
        local WAD = require("Game.WeeklyActivityData")
        local WD  = require("Game.WelfareData")
        local redDot = uiRoot:FindById("weeklyActivityRedDot")
        if redDot then redDot:SetVisible(WAD.HasClaimable() or WD.HasClaimable()) end
    end
end

function GameUI.RefreshWeeklyActivityRedDot()
    if not uiRoot then return end
    local WAD = require("Game.WeeklyActivityData")
    local WD  = require("Game.WelfareData")
    local redDot = uiRoot:FindById("weeklyActivityRedDot")
    if redDot then redDot:SetVisible(WAD.HasClaimable() or WD.HasClaimable()) end
end

-- ============================================================================
-- 邮件 Overlay
-- ============================================================================

function GameUI.CreateMailboxOverlay()
    local content = MailboxUI.CreatePage(UI)
    -- 将关闭回调和 HUD 刷新传给 MailboxUI，由它统一管理底部按钮
    MailboxUI.SetCallbacks({
        onClose = function() GameUI.ShowMailboxOverlay(false) end,
        onClaimAll = function()
            local MailboxData2 = require("Game.MailboxData")
            local count = MailboxData2.ClaimAll()
            if count > 0 then
                Toast.Show("已领取 " .. count .. " 封邮件")
                MailboxUI.Refresh()
                GameUI.UpdateHUD()
            else
                Toast.Show("没有可领取的邮件")
            end
        end,
    })

    local overlay = UI.Panel {
        id = "mailboxOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = { content },
    }
    return overlay
end

function GameUI.ShowMailboxOverlay(show)
    if GameUI._mailboxPage then
        GameUI._mailboxPage:SetVisible(show)
        if show then MailboxUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
    if not show and uiRoot then
        local MailboxData = require("Game.MailboxData")
        local redDot = uiRoot:FindById("mailboxRedDot")
        if redDot then redDot:SetVisible(MailboxData.HasUnclaimed()) end
    end
end

function GameUI.RefreshMailboxRedDot()
    if not uiRoot then return end
    local MailboxData = require("Game.MailboxData")
    local redDot = uiRoot:FindById("mailboxRedDot")
    if redDot then redDot:SetVisible(MailboxData.HasUnclaimed()) end
end

-- ============================================================================
-- 每日任务 Overlay
-- ============================================================================

function GameUI.CreateDailyTaskOverlay()
    local content = DailyTaskUI.CreatePage(UI)
    local overlay = UI.Panel {
        id = "dailyTaskOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        visible = false,
        children = {
            -- 内容区占满剩余高度
            UI.Panel {
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                overflow = "hidden",
                children = { content },
            },
            -- 底部返回键行
            UI.Panel {
                width = "100%",
                height = 54,
                flexShrink = 0,
                backgroundColor = { 15, 12, 30, 240 },
                borderTopWidth = 1,
                borderColor = { 80, 65, 120, 100 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "返回",
                        fontSize = 16,
                        width = 120,
                        height = 38,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function()
                            GameUI.ShowDailyTaskOverlay(false)
                        end,
                    },
                },
            },
        },
    }
    return overlay
end

function GameUI.ShowDailyTaskOverlay(show)
    if GameUI._dailyTaskPage then
        GameUI._dailyTaskPage:SetVisible(show)
        if show then DailyTaskUI.Refresh() end
    end
    TabNav.SetBarVisible(not show)
    -- 关闭时刷新红点
    if not show and uiRoot then
        local DTD = require("Game.DailyTaskData")
        local redDot = uiRoot:FindById("dailyTaskRedDot")
        if redDot then redDot:SetVisible(DTD.HasClaimable()) end
    end
end

--- 刷新每日任务按钮红点（存档加载后调用）
function GameUI.RefreshDailyTaskRedDot()
    if not uiRoot then return end
    local DTD = require("Game.DailyTaskData")
    local redDot = uiRoot:FindById("dailyTaskRedDot")
    if redDot then redDot:SetVisible(DTD.HasClaimable()) end
end

-- ============================================================================
-- 加速弹窗
-- ============================================================================

--- 创建加速弹窗浮层
function GameUI.CreateSpeedBoostDialog()
    local overlay = UI.Panel {
        id = "speedBoostOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        pointerEvents = "auto",
        onClick = function(self)
            GameUI.ShowSpeedBoostDialog(false)
        end,
        children = {
            -- 弹窗卡片
            UI.Panel {
                width = 300,
                backgroundColor = { 30, 24, 50, 245 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 200, 150, 60, 180 },
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                gap = 14,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,  -- 阻止穿透关闭
                children = {
                    -- 标题
                    UI.Label {
                        text = "⚡ 战斗加速 x2",
                        fontSize = 18,
                        fontColor = { 255, 200, 60, 255 },
                        fontWeight = "bold",
                    },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 200, 150, 60, 60 } },
                    -- 当前状态
                    UI.Panel {
                        width = "100%",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "sbDialogStatus",
                                text = "当前：未加速",
                                fontSize = 13,
                                fontColor = { 180, 170, 200, 220 },
                            },
                            UI.Label {
                                id = "sbDialogRemaining",
                                text = "",
                                fontSize = 15,
                                fontColor = { 255, 200, 60, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 说明
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 50, 40, 70, 150 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        children = {
                            UI.Label {
                                text = "看广告获得加速时间",
                                fontSize = 12,
                                fontColor = { 200, 190, 220, 200 },
                            },
                        },
                    },
                    -- 开关加速按钮
                    UI.Button {
                        id = "sbToggleBtn",
                        text = "关闭加速",
                        fontSize = 13,
                        variant = "outline",
                        width = "100%",
                        height = 34,
                        borderRadius = 8,
                        visible = false,
                        onClick = function(self)
                            SpeedBoost.enabled = not SpeedBoost.enabled
                            GameUI.RefreshSpeedBoostDialog()
                            GameUI.UpdateHUD()
                        end,
                    },
                    -- 看广告按钮
                    UI.Button {
                        id = "sbWatchAdBtn",
                        text = "▶ 看广告加速",
                        fontSize = 14,
                        fontWeight = "bold",
                        variant = "primary",
                        width = "100%",
                        height = 42,
                        borderRadius = 8,
                        onClick = function(self)
                            if not SpeedBoost.CanWatchAd() then
                                Toast.Show("今日次数已用完", { 255, 100, 100 })
                                return
                            end
                            AdHelper.ShowRewardAd(function()
                                SpeedBoost.OnAdWatched()
                                GameUI.RefreshSpeedBoostDialog()
                                GameUI.UpdateHUD()
                                Toast.Show("+1小时加速！", { 255, 200, 60 })
                            end)
                        end,
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        fontSize = 13,
                        variant = "outline",
                        width = "100%",
                        height = 34,
                        borderRadius = 8,
                        onClick = function(self)
                            GameUI.ShowSpeedBoostDialog(false)
                        end,
                    },
                },
            },
        },
    }
    return overlay
end

--- 刷新弹窗内容
function GameUI.RefreshSpeedBoostDialog()
    if not uiRoot then return end
    local statusLabel = uiRoot:FindById("sbDialogStatus")
    local remainLabel = uiRoot:FindById("sbDialogRemaining")
    local watchBtn = uiRoot:FindById("sbWatchAdBtn")

    if statusLabel then
        if SpeedBoost.enabled and SpeedBoost.remaining > 0 then
            statusLabel:SetText("当前：x2 加速中")
        else
            statusLabel:SetText("当前：未加速")
        end
    end
    if remainLabel then
        if SpeedBoost.remaining > 0 then
            remainLabel:SetText("剩余时间：" .. SpeedBoost.FormatRemaining())
        else
            remainLabel:SetText("")
        end
    end
    if watchBtn then
        if SpeedBoost.CanWatchAd() then
            watchBtn:SetText("▶ 看广告加速")
            watchBtn:SetStyle({ backgroundColor = { 200, 120, 40, 255 } })
        else
            watchBtn:SetText("今日次数已用完")
            watchBtn:SetStyle({ backgroundColor = { 80, 60, 60, 200 } })
        end
    end
    local toggleBtn = uiRoot:FindById("sbToggleBtn")
    if toggleBtn then
        if SpeedBoost.remaining > 0 then
            toggleBtn:SetVisible(true)
            if SpeedBoost.enabled then
                toggleBtn:SetText("关闭加速")
            else
                toggleBtn:SetText("开启加速")
            end
        else
            toggleBtn:SetVisible(false)
        end
    end
end

--- 显示/隐藏加速弹窗
function GameUI.ShowSpeedBoostDialog(show)
    if GameUI._speedBoostDialog then
        GameUI._speedBoostDialog:SetVisible(show)
        if show then GameUI.RefreshSpeedBoostDialog() end
    end
end

--- 主更新循环
function GameUI.Update(dt)
    -- 注：超限判定 + BOSS 倒计时 + 通关桥接已迁移到 BattleManager.UpdateWaves

    -- 自动召唤/合成定时触发
    if State.phase == State.PHASE_PLAYING or State.phase == State.PHASE_WAVE_READY then
        local AUTO_INTERVAL = 0.4  -- 每 0.4 秒触发一次

        -- 跨天自动关闭（昨天解锁的今天失效）
        if AutoPlay.autoSummon and not AutoPlay.IsUnlockedToday("autoSummon") then
            AutoPlay.autoSummon = false
            GameUI.UpdateHUD()
        end
        if AutoPlay.autoMerge and not AutoPlay.IsUnlockedToday("autoMerge") then
            AutoPlay.autoMerge = false
            GameUI.UpdateHUD()
        end
        if AutoPlay.autoDeploy and not AutoPlay.IsUnlockedToday("autoDeploy") then
            AutoPlay.autoDeploy = false
            GameUI.UpdateHUD()
        end

        if AutoPlay.autoSummon then
            AutoPlay.autoSummonTimer = AutoPlay.autoSummonTimer + dt
            if AutoPlay.autoSummonTimer >= AUTO_INTERVAL then
                AutoPlay.autoSummonTimer = 0
                local t = Tower.Summon()
                if t then
                    -- UpdateHUD 由 Tower.Summon()→Currency.Spend("dark_soul") 触发 EventBus 自动调用
                end
            end
        end

        if AutoPlay.autoMerge then
            AutoPlay.autoMergeTimer = AutoPlay.autoMergeTimer + dt
            if AutoPlay.autoMergeTimer >= AUTO_INTERVAL then
                AutoPlay.autoMergeTimer = 0
                GameUI.AutoMerge()
            end
        end

        -- 自动布阵（每3秒重排一次，间隔较长因为移动位置比较明显）
        local DEPLOY_INTERVAL = 3.0
        if AutoPlay.autoDeploy then
            AutoPlay.autoDeployTimer = AutoPlay.autoDeployTimer + dt
            if AutoPlay.autoDeployTimer >= DEPLOY_INTERVAL then
                AutoPlay.autoDeployTimer = 0
                local Renderer = require("Game.Renderer")
                local moved = Tower.AutoDeploy(Renderer.gridOffsetX, Renderer.gridOffsetY)
                if moved then
                    print("[GameUI] Auto-deploy repositioned towers")
                end
            end
        end
    end

    GameUI.UpdateHUD()
    GameUI.UpdateAfkTimer()
    EquipUI.Update(dt)
    -- 时装签到预览动画
    if GameUI._costumeSignInPage and GameUI._costumeSignInPage:IsVisible() then
        CostumeSignInUI.Update(dt)
    end

    -- 战报浮窗实时刷新（1秒一次，标记为刷新以跳过动画）
    if ctx.uiRoot then
        local ov = ctx.uiRoot:FindById("damageStatsOverlay")
        if ov then
            GameUI._dmgRefreshTimer = (GameUI._dmgRefreshTimer or 0) + dt
            if GameUI._dmgRefreshTimer >= 1.0 then
                GameUI._dmgRefreshTimer = 0
                GameUI._dmgIsRefresh = true
                GameUI.ShowDamageStatsPanel(true)
                GameUI._dmgIsRefresh = false
            end
        else
            GameUI._dmgRefreshTimer = 0
        end
    end

    -- 战报面板滑入动画（easing: exponential decay）
    if GameUI._dmgAnimating then
        local offset = GameUI._dmgSlideOffset or 300
        offset = math.max(0, offset - (offset * 10 + 80) * dt)
        GameUI._dmgSlideOffset = offset
        local card = ctx.uiRoot and ctx.uiRoot:FindById("dmgStatsCard")
        if card then
            card:SetStyle({ right = -offset })
            if offset < 0.5 then
                card:SetStyle({ right = 0 })
                GameUI._dmgAnimating = false
            end
        else
            GameUI._dmgAnimating = false
        end
    end
end

-- ============================================================================
-- 副本战斗入口/出口
-- ============================================================================

--- 进入副本战斗（代理到 BattleFlow）
---@param config table BattleManager.Start 所需的配置
function GameUI.EnterDungeonBattle(config)
    local BattleFlow = require("Game.BattleFlow")
    BattleFlow.EnterDungeon(config)
end

--- 退出副本战斗（代理到 BattleFlow）
function GameUI.ExitDungeonBattle()
    local BattleFlow = require("Game.BattleFlow")
    BattleFlow.ExitDungeon()
end

return GameUI
