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

local GameUI = {}

---@type any
local UI = nil
---@type any
local uiRoot = nil

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

--- 格式化大数字（万/亿）
local function FormatNum(n)
    if n >= 100000000 then return string.format("%.1f亿", n / 100000000) end
    if n >= 10000 then return string.format("%.1f万", n / 10000) end
    return tostring(math.floor(n))
end
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

    -- ======== 英雄信息面板（已有脏标记逻辑，仅换用缓存引用） ========
    if refs.heroInfoPanel then
        local sel = State.selectedTower
        if sel then
            local needUpdate = (sel.id ~= ctx.lastInfoTowerId) or (sel.star ~= ctx.lastInfoTowerStar)
            if needUpdate then
                ctx.lastInfoTowerId = sel.id
                ctx.lastInfoTowerStar = sel.star
                refs.heroInfoPanel:ClearChildren()
                local content = GameUI.BuildHeroInfoContent(sel)
                for _, child in ipairs(content) do
                    if child then
                        refs.heroInfoPanel:AddChild(child)
                    end
                end
            end
            refs.heroInfoPanel:SetVisible(true)
        else
            if ctx.lastInfoTowerId then
                ctx.lastInfoTowerId = nil
                ctx.lastInfoTowerStar = nil
                refs.heroInfoPanel:ClearChildren()
            end
            refs.heroInfoPanel:SetVisible(false)
        end
    end

    -- ======== 退出副本按钮 ========
    if refs.exitDungeonBtn then
        local BM = require("Game.BattleManager")
        refs.exitDungeonBtn:SetVisible(BM.IsActive())
    end

    -- ======== 自动按钮状态（仅状态变化时更新） ========
    if refs.autoSummonBtn then
        local unlocked = AutoPlay.IsUnlockedToday("autoSummon")
        local st = unlocked and (AutoPlay.autoSummon and "on" or "off") or "locked"
        if st ~= hudCache.autoSummonState then
            hudCache.autoSummonState = st
            if st == "locked" then
                refs.autoSummonBtn:SetText("自动召唤 ▶")
                refs.autoSummonBtn:SetStyle({ backgroundColor = { 80, 60, 40, 200 }, fontColor = { 255, 200, 100, 255 } })
            elseif st == "on" then
                refs.autoSummonBtn:SetText("自动召唤:开")
                refs.autoSummonBtn:SetStyle({ backgroundColor = { 100, 60, 200, 255 }, fontColor = { 255, 255, 255, 255 } })
            else
                refs.autoSummonBtn:SetText("自动召唤:关")
                refs.autoSummonBtn:SetStyle({ backgroundColor = { 60, 50, 80, 200 }, fontColor = { 180, 160, 220, 255 } })
            end
        end
    end

    if refs.autoMergeBtn then
        local unlocked = AutoPlay.IsUnlockedToday("autoMerge")
        local st = unlocked and (AutoPlay.autoMerge and "on" or "off") or "locked"
        if st ~= hudCache.autoMergeState then
            hudCache.autoMergeState = st
            if st == "locked" then
                refs.autoMergeBtn:SetText("自动合成 ▶")
                refs.autoMergeBtn:SetStyle({ backgroundColor = { 80, 60, 40, 200 }, fontColor = { 255, 200, 100, 255 } })
            elseif st == "on" then
                refs.autoMergeBtn:SetText("自动合成:开")
                refs.autoMergeBtn:SetStyle({ backgroundColor = { 100, 60, 200, 255 }, fontColor = { 255, 255, 255, 255 } })
            else
                refs.autoMergeBtn:SetText("自动合成:关")
                refs.autoMergeBtn:SetStyle({ backgroundColor = { 60, 50, 80, 200 }, fontColor = { 180, 160, 220, 255 } })
            end
        end
    end

    if refs.autoDeployBtn then
        local unlocked = AutoPlay.IsUnlockedToday("autoDeploy")
        local st = unlocked and (AutoPlay.autoDeploy and "on" or "off") or "locked"
        if st ~= hudCache.autoDeployState then
            hudCache.autoDeployState = st
            if st == "locked" then
                refs.autoDeployBtn:SetText("自动布阵 ▶")
                refs.autoDeployBtn:SetStyle({ backgroundColor = { 80, 60, 40, 200 }, fontColor = { 255, 200, 100, 255 } })
            elseif st == "on" then
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
            GameUI.CreateIdleRewardPanel(),
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

--- 创建游戏 UI（多页架构）
function GameUI.CreateUI()
    -- ChestData.Load() 移至 StartGame() 中存档加载完成后调用
    -- 此处不应在存档就绪前初始化业务数据

    local battlePage = GameUI.CreateBattlePage()
    local heroPage = HeroUI.CreatePage(UI)
    local equipPage = EquipUI.CreatePage(UI)
    local chestPage = ChestUI.CreatePage(UI)
    local dungeonPage = DungeonUI.CreatePage(UI)

    uiRoot = TabNav.Create(UI, {
        hero = heroPage,
        equip = equipPage,
        battle = battlePage,
        dungeon = dungeonPage,
        chest = chestPage,
    }, OnTabSwitch)

    ctx.uiRoot = uiRoot
    GameUI.InvalidateHudCache()

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
        text = "v1.0.26",
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

    UI.SetRoot(uiRoot)
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

        -- 销毁旧的区服选择浮层
        if GameUI._serverSelectPage then
            GameUI._serverSelectPage:SetVisible(false)
            GameUI._serverSelectPage = nil
        end

        -- 重新获取最新元数据并创建区服选择
        local freshMeta = SlotSave.GetMeta()
        GameUI.CreateServerSelect(function(serverId)
            StartGame(serverId)  -- 全局函数，定义在 main.lua
        end, freshMeta)
        GameUI.ShowServerSelect(true)

        -- 切到战斗标签页（确保返回后看到的是战斗页）
        TabNav.SwitchTo("battle")
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
    local overlay = UI.Panel {
        id = "mailboxOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = {
            content,
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 120,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 20,
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
                            GameUI.ShowMailboxOverlay(false)
                        end,
                    },
                    UI.Button {
                        id = "mailClaimAllBtn",
                        text = "一键领取",
                        fontSize = 20,
                        width = 120,
                        height = 54,
                        borderRadius = 8,
                        variant = "primary",
                        onClick = function()
                            local MailboxData = require("Game.MailboxData")
                            local count = MailboxData.ClaimAll()
                            if count > 0 then
                                Toast.Show("已领取 " .. count .. " 封邮件")
                                MailboxUI.Refresh()
                                GameUI.UpdateHUD()
                            else
                                Toast.Show("没有可领取的邮件")
                            end
                        end,
                    },
                },
            },
        },
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
    local Enemy = require("Game.Enemy")
    local BM = require("Game.BattleManager")
    local isBMActive = BM.IsActive()

    if State.phase == State.PHASE_PLAYING then
        -- 超限判定（BattleManager 模式下根据配置决定是否启用）
        local overloadEnabled = true
        if isBMActive and not BM.config.overloadEnabled then
            overloadEnabled = false
        end

        if overloadEnabled then
            local aliveCount = Enemy.GetAliveCount()
            local maxEnemies = (isBMActive and BM.config.overloadLimit) or Config.MAX_ENEMIES
            if aliveCount > maxEnemies then
                if not State.overloading then
                    State.overloading = true
                    State.overloadTimer = 0
                    print("[GameUI] Overload started! enemies=" .. aliveCount)
                end
                State.overloadTimer = State.overloadTimer + dt
                if State.overloadTimer >= Config.OVERLOAD_COUNTDOWN then
                    State.phase = State.PHASE_GAME_OVER
                    State.overloading = false
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayDefeat()
                    print("[GameUI] Overload timeout! Game over.")
                    if isBMActive then
                        BM.OnLose()
                    else
                        GameUI.DoGameOver()
                    end
                    return
                end
            else
                if State.overloading then
                    print("[GameUI] Overload cleared, enemies=" .. aliveCount)
                end
                State.overloading = false
                State.overloadTimer = 0
            end
        end
    end

    if State.phase == State.PHASE_PLAYING then
        -- BOSS 倒计时
        local bossTimerEnabled = true
        if isBMActive and not BM.config.bossTimerEnabled then
            bossTimerEnabled = false
        end

        if bossTimerEnabled then
            local isWorldBoss = isBMActive and BM.config.mode == "world_boss"
            local bossMaxTimer = (isWorldBoss and BM.config.worldBossDuration) or Config.BOSS_TIMER_MAX

            if State.waveType == "boss" and not State.bossActive then
                for _, e in ipairs(State.enemies) do
                    if e.alive and e.isBoss then
                        State.bossActive = true
                        State.bossTimer = bossMaxTimer
                        State.bossTimerMax = bossMaxTimer
                        print("[GameUI] BOSS fight started! Timer=" .. bossMaxTimer .. "s")
                        break
                    end
                end
            end

            if State.bossActive then
                local bossAlive = false
                for _, e in ipairs(State.enemies) do
                    if e.alive and e.isBoss then
                        bossAlive = true
                        break
                    end
                end

                if not bossAlive then
                    State.bossActive = false
                    State.bossTimer = 0
                    print("[GameUI] BOSS defeated! Timer stopped.")
                else
                    -- 世界BOSS每秒掉落暗魂（可视掉落物 + 磁吸飞行）
                    if isWorldBoss and BM.config.worldBossDarkSoulDrain then
                        -- 找到 boss 屏幕坐标
                        local bossX, bossY = nil, nil
                        for _, e in ipairs(State.enemies) do
                            if e.alive and e.isBoss then
                                bossX, bossY = e.x, e.y
                                break
                            end
                        end
                        if bossX then
                            State.worldBossDrainAcc = (State.worldBossDrainAcc or 0) + dt
                            while State.worldBossDrainAcc >= 1.0 do
                                State.worldBossDrainAcc = State.worldBossDrainAcc - 1.0
                                local LootDrop = require("Game.LootDrop")
                                LootDrop.Spawn("dark_soul", BM.config.worldBossDarkSoulDrain, bossX, bossY)
                            end
                        end
                    end

                    State.bossTimer = State.bossTimer - dt
                    if State.bossTimer <= 0 then
                        State.bossTimer = 0
                        State.bossActive = false

                        if isWorldBoss then
                            -- 世界BOSS到时 → 结算（算通关）
                            State.phase = State.PHASE_STAGE_CLEAR
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayVictory()
                            print("[GameUI] World BOSS timer up! Settling damage.")
                            if isBMActive then
                                BM.OnWin()
                            end
                        else
                            -- 普通BOSS超时 → 失败
                            State.phase = State.PHASE_GAME_OVER
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayDefeat()
                            print("[GameUI] BOSS timer expired! Game over.")
                            if isBMActive then
                                BM.OnLose()
                            else
                                GameUI.DoGameOver()
                            end
                        end
                        return
                    end
                end
            end
        end
    else
        if State.bossActive then
            State.bossActive = false
            State.bossTimer = 0
        end
    end

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

    -- 通关判定
    if State.phase == State.PHASE_STAGE_CLEAR and not State.settleRewards then
        if isBMActive then
            State.settleRewards = true  -- 防止下一帧重复调用 OnWin（重复结算奖励）
            BM.OnWin()
            return
        else
            GameUI.DoStageClear()
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

--- 保存主线战斗状态（进副本前备份，出来后恢复）
local savedCampaignStage = nil

--- 进入副本战斗：切换到战斗页面，启动 BattleManager
---@param config table BattleManager.Start 所需的配置
function GameUI.EnterDungeonBattle(config)
    local BM = require("Game.BattleManager")

    -- 备份主线当前关卡
    savedCampaignStage = (HeroData.stats.bestStage or 0) + 1
    if savedCampaignStage < 1 then savedCampaignStage = 1 end

    -- 切到战斗页
    TabNav.SwitchTo("battle")

    -- 启动战斗
    BM.Start(config)

    GameUI.UpdateHUD()
    print("[GameUI] Entered dungeon battle: " .. (config.label or config.mode))

    -- hook 开服好礼 dungeon 任务进度
    local ok1, LGD = pcall(require, "Game.LaunchGiftData")
    if ok1 and LGD then LGD.AddProgress("dungeon", 1) end
    -- hook 每日任务 dungeon 进度
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD and DTD.AddProgress then DTD.AddProgress("dungeon", 1) end
end

--- 退出副本战斗：清理 BattleManager，由 afterExit 决定下一步进哪个战斗
--- @param afterExit function|nil  function(restoreStage) 由调用方控制下一步；nil 时默认恢复主线
function GameUI.ExitDungeonBattle(afterExit)
    local BM = require("Game.BattleManager")

    -- 如果有 onExit 回调，先触发提前结算（回调内部会再次调用本函数完成真正退出）
    if BM.config and BM.config.onExit then
        local onExit = BM.config.onExit
        BM.config.onExit = nil  -- 清除防止递归
        local LootDrop = require("Game.LootDrop")
        LootDrop.CollectAll()
        local result = {
            mode = BM.config.mode,
            wave = State.currentWave,
            totalWaves = BM.config.totalWaves,
            score = State.score,
        }
        onExit(result)
        return
    end

    BM.End()

    -- 计算恢复关卡号（供 afterExit 或默认路径使用）
    local restoreStage = savedCampaignStage or ((HeroData.stats.bestStage or 0) + 1)
    if restoreStage < 1 then restoreStage = 1 end
    savedCampaignStage = nil

    if afterExit then
        -- 由调用方决定下一步进哪个战斗
        afterExit(restoreStage)
    else
        -- 默认：恢复主线战斗，切回副本页
        BM.Enter("campaign", {
            stageNum = restoreStage,
            onWin    = function() GameUI.DoStageClear() end,
            onLose   = function() GameUI.DoGameOver() end,
        })
        TabNav.SwitchTo("dungeon")
        DungeonUI.Refresh()
        GameUI.UpdateHUD()
        print("[GameUI] Exited dungeon battle, restored campaign stage " .. restoreStage)
    end
end

return GameUI
