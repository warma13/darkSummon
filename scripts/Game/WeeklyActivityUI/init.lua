-- Game/WeeklyActivityUI/init.lua
-- 限时活动 UI：核心外壳（共享状态、子标签栏、路由分发）

local WAD            = require("Game.WeeklyActivityData")
local WelfareData    = require("Game.WelfareData")
local Tooltip        = require("Game.Tooltip")
local RMD            = require("Game.RecruitMilestoneData")
local BMD            = require("Game.BlackMarketData")
local DivineBlessDB  = require("Game.DivineBlessData")
local DED            = require("Game.DropEventData")

local WeeklyActivityUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

local activeTab = "weekly"
local activeSubTab = "chest"

-- 子模块（懒加载）
local ChestMilestone   = nil
local RecruitMilestone = nil
local BlackMarketUI    = nil
local Welfare          = nil
local DivineBless      = nil
local DropEventUI      = nil

-- 子标签配置（week 字段控制显示条件：nil=始终显示，"market"=仅市场周）
local ALL_SUB_TABS = {
    { id = "chest",         icon = "image/icon_cumulate.png",                          label = "宝箱达标",   week = { "chest", "recruit" } },
    { id = "black_market",  icon = "image/icon_black_market_20260426055156.png",       label = "黑市",       week = "market" },
    { id = "drop_event",    icon = "image/icon_drop_event_20260426050205.png",         label = "掉落活动",   week = "market" },
    { id = "exchange_shop", icon = "image/icon_exchange_shop_20260426053936.png",      label = "换购商店",   week = "market" },
    { id = "welfare",       icon = "image/icon_limited_welfare.png",                   label = "限时福利",   week = "chest" },
    { id = "weekend_bonus", icon = "image/icon_weekend_bonus.png",                     label = "神裔降临" },
}

--- 根据当前周类型过滤可见标签
local function GetVisibleSubTabs()
    local weekType = WAD.GetCurrentWeekType()
    local tabs = {}
    for _, tab in ipairs(ALL_SUB_TABS) do
        if not tab.week then
            tabs[#tabs + 1] = tab
        elseif type(tab.week) == "table" then
            for _, w in ipairs(tab.week) do
                if w == weekType then tabs[#tabs + 1] = tab; break end
            end
        elseif tab.week == weekType then
            tabs[#tabs + 1] = tab
        end
    end
    return tabs
end

local SUB_TAB_ACTIVE = {
    bg = { 80, 50, 20, 255 },
    border = { 255, 200, 50, 220 },
    borderW = 2,
    label = { 255, 220, 100, 255 },
    fontW = "bold",
}
local SUB_TAB_INACTIVE = {
    bg = { 35, 28, 55, 220 },
    border = { 70, 55, 90, 120 },
    borderW = 1,
    label = { 160, 150, 180, 200 },
    fontW = "normal",
}

-- 样式常量（暗紫主题）
local S = {
    bgPage     = { 12, 10, 25, 250 },
    bgHeader   = { 30, 22, 50, 240 },
    bgSection  = { 25, 20, 45, 230 },
    bgCard     = { 35, 28, 55, 220 },
    border     = { 80, 65, 120, 150 },
    borderGold = { 220, 180, 60, 200 },
    textTitle  = { 255, 220, 100, 255 },
    textWhite  = { 240, 235, 255, 255 },
    textNormal = { 220, 210, 240, 255 },
    textDim    = { 150, 140, 170, 200 },
    textGold   = { 255, 200, 60, 255 },
    textGreen  = { 100, 220, 120, 255 },
    accent     = { 180, 120, 255, 255 },
    barBg      = { 30, 20, 45, 200 },
    barFill    = { 200, 140, 60, 255 },
    red        = { 255, 80, 80, 255 },
    claimBg    = { 200, 100, 40, 255 },
    claimedBg  = { 60, 60, 60, 200 },
    tabActive  = { 180, 120, 255, 255 },
    tabInactive = { 50, 40, 70, 200 },
}

-- ============================================================================
-- Accessor（供子模块通过 ctx 访问）
-- ============================================================================

function WeeklyActivityUI.GetUI()       return UI       end
function WeeklyActivityUI.GetPageRoot() return pageRoot  end
function WeeklyActivityUI.GetS()        return S         end

-- ============================================================================
-- 公开接口
-- ============================================================================

function WeeklyActivityUI.CreatePage(uiModule)
    UI = uiModule

    -- 懒加载子模块
    if not ChestMilestone then
        ChestMilestone   = require("Game.WeeklyActivityUI.ChestMilestone")
        RecruitMilestone = require("Game.WeeklyActivityUI.RecruitMilestone")
        BlackMarketUI    = require("Game.WeeklyActivityUI.BlackMarket")
        Welfare          = require("Game.WeeklyActivityUI.Welfare")
        DivineBless      = require("Game.WeeklyActivityUI.DivineBless")
        DropEventUI      = require("Game.WeeklyActivityUI.DropEvent")
    end

    activeTab = "weekly"

    pageRoot = UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        backgroundColor = S.bgPage,
        overflow = "hidden",
        children = {
            WeeklyActivityUI._BuildHeader(),
            WeeklyActivityUI._BuildTabBar(),
            WeeklyActivityUI._BuildSubTabBar(),
            UI.ScrollView {
                id = "waContentArea",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                padding = 12,
                gap = 10,
            },
        },
    }
    -- patch：竖向滚轮也能横向滚动子标签栏
    WeeklyActivityUI._PatchSubTabWheel()
    Tooltip.Init(UI, pageRoot)
    return pageRoot
end

function WeeklyActivityUI.Refresh()
    if not pageRoot then return end
    local area = pageRoot:FindById("waContentArea")
    if not area then return end
    area:ClearChildren()

    activeTab = "weekly"
    WeeklyActivityUI._UpdateSubTabHighlight()
    WeeklyActivityUI._RenderWeeklyTab(area)

    Tooltip.Init(UI, pageRoot)
end

--- 从外部切换到指定子标签（在 ShowWeeklyActivityOverlay 之前调用）
function WeeklyActivityUI.SetSubTab(tabId)
    activeSubTab = tabId
end

-- ============================================================================
-- 顶部标题栏
-- ============================================================================

function WeeklyActivityUI._BuildHeader()
    return UI.Panel {
        width = "100%",
        paddingTop = 14, paddingBottom = 10,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = S.bgHeader,
        borderBottomWidth = 1,
        borderColor = { 100, 80, 160, 80 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Panel {
                gap = 1,
                children = {
                    UI.Label {
                        text = "限时活动",
                        fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                    },
                    UI.Label {
                        text = "参与即送礼 福利领不停",
                        fontSize = 10, fontColor = S.textDim,
                    },
                },
            },
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 60, 40, 90, 200 },
                borderRadius = 10,
                children = {
                    UI.Label {
                        id = "waTimeLeft",
                        text = "倒计时: " .. WAD.GetRemainingTimeStr(),
                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 标签栏（空桩）
-- ============================================================================

function WeeklyActivityUI._BuildTabBar()
    return UI.Panel { width = 0, height = 0 }
end

function WeeklyActivityUI._UpdateTabHighlight()
end

--- patch 子标签栏滚轮：竖向滚轮也能横向滚动（与 ActivityUI 一致）
function WeeklyActivityUI._PatchSubTabWheel()
    if not pageRoot then return end
    local tabScroll = pageRoot:FindById("waSubTabScroll")
    if tabScroll and tabScroll.ScrollBy then
        tabScroll.OnWheel = function(self, dx, dy)
            local step = 60
            local dir = 0
            if dy ~= 0 then dir = dir + (dy > 0 and -1 or 1) end
            if dx ~= 0 then dir = dir + (dx > 0 and 1 or -1) end
            if dir ~= 0 then
                self:ScrollBy(dir * step, 0)
            end
        end
    end
end

-- ============================================================================
-- 子标签栏
-- ============================================================================

--- 判断当前是否为周末
local function IsWeekend()
    local w = os.date("*t").wday
    return w == 1 or w == 7
end

--- 子标签红点判断
local SUB_TAB_RED_DOT = {
    chest = function()
        if WAD.GetCurrentWeekType() == "recruit" then
            return RMD.HasClaimable()
        end
        return WAD.HasClaimable()
    end,
    black_market  = function() return BMD.HasAffordable() end,
    drop_event    = function() return DED.HasClaimable() end,
    exchange_shop = function() return DED.HasAffordableItem() end,
    welfare       = function() return WelfareData.HasClaimable() end,
    weekend_bonus = function() return not DivineBlessDB.HasChosen() end,
}

local function GetChestTabLabel()
    return WAD.GetCurrentWeekType() == "recruit" and "招募达标" or "宝箱达标"
end

local function GetChestTabIcon()
    return WAD.GetCurrentWeekType() == "recruit"
        and "image/icon_recruit_milestone.png"
        or "image/icon_cumulate.png"
end

local function GetWelfareTabIcon()
    return WAD.GetCurrentWeekType() == "recruit"
        and "image/icon_welfare_recruit.png"
        or "image/icon_welfare_chest.png"
end

function WeeklyActivityUI._BuildSubTabBar()
    local visibleTabs = GetVisibleSubTabs()
    -- 如果当前激活标签不在可见列表中，回退到第一个
    local found = false
    for _, tab in ipairs(visibleTabs) do
        if tab.id == activeSubTab then found = true; break end
    end
    if not found and #visibleTabs > 0 then
        activeSubTab = visibleTabs[1].id
    end

    local tabIcons = {}
    for _, tab in ipairs(visibleTabs) do
        local isActive = (activeSubTab == tab.id)
        tabIcons[#tabIcons + 1] = WeeklyActivityUI._CreateSubTabIcon(tab, isActive)
    end

    return UI.ScrollView {
        id = "waSubTabScroll",
        width = "100%",
        height = "12%",
        minHeight = 70,
        flexShrink = 0,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        backgroundColor = { 28, 22, 45, 240 },
        paddingTop = 4, paddingBottom = 4,
        borderBottomWidth = 1,
        borderColor = { 70, 55, 100, 100 },
        visible = (activeTab == "weekly"),
        children = {
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                paddingLeft = 10, paddingRight = 10,
                height = "100%",
                alignItems = "stretch",
                children = tabIcons,
            },
        },
    }
end

function WeeklyActivityUI._CreateSubTabIcon(tab, isActive)
    local s = isActive and SUB_TAB_ACTIVE or SUB_TAB_INACTIVE
    local hasRed = SUB_TAB_RED_DOT[tab.id] and SUB_TAB_RED_DOT[tab.id]() or false
    local displayLabel = (tab.id == "chest") and GetChestTabLabel() or tab.label
    local displayIcon = tab.icon
    if tab.id == "chest" then
        displayIcon = GetChestTabIcon()
    elseif tab.id == "welfare" then
        displayIcon = GetWelfareTabIcon()
    end

    return UI.Panel {
        id = "waSubTab_" .. tab.id,
        height = "100%",
        aspectRatio = 1,
        flexShrink = 0,
        backgroundColor = s.bg,
        borderRadius = 10,
        borderWidth = s.borderW,
        borderColor = s.border,
        overflow = "hidden",
        flexDirection = "column",
        pointerEvents = "auto",
        onClick = function()
            if activeSubTab ~= tab.id then
                activeSubTab = tab.id
                WeeklyActivityUI._UpdateSubTabHighlight()
                WeeklyActivityUI.Refresh()
            end
        end,
        children = {
            UI.Panel {
                width = "100%", height = "70%",
                backgroundImage = displayIcon,
                backgroundFit = "cover",
                backgroundPosition = "center",
                pointerEvents = "none",
            },
            UI.Panel {
                width = "100%", height = "30%",
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        id = "waSubTabLabel_" .. tab.id,
                        text = displayLabel,
                        fontSize = 10,
                        fontColor = s.label,
                        fontWeight = s.fontW,
                        textAlign = "center",
                    },
                },
            },
            UI.Panel {
                id = "waSubTabRedDot_" .. tab.id,
                position = "absolute",
                top = 2, right = 2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
                visible = hasRed,
            },
        },
    }
end

function WeeklyActivityUI._UpdateSubTabHighlight()
    if not pageRoot then return end
    for _, tab in ipairs(GetVisibleSubTabs()) do
        local isActive = (activeSubTab == tab.id)
        local s = isActive and SUB_TAB_ACTIVE or SUB_TAB_INACTIVE
        local tabWidget = pageRoot:FindById("waSubTab_" .. tab.id)
        if tabWidget then
            tabWidget:SetStyle({
                backgroundColor = s.bg,
                borderColor = s.border,
                borderWidth = s.borderW,
            })
        end
        local labelWidget = pageRoot:FindById("waSubTabLabel_" .. tab.id)
        if labelWidget then
            labelWidget:SetStyle({ fontColor = s.label, fontWeight = s.fontW })
            if tab.id == "chest" then
                labelWidget:SetText(GetChestTabLabel())
            end
        end
        local redDot = pageRoot:FindById("waSubTabRedDot_" .. tab.id)
        if redDot then
            local hasRed = SUB_TAB_RED_DOT[tab.id] and SUB_TAB_RED_DOT[tab.id]() or false
            redDot:SetVisible(hasRed)
        end
    end
end

-- ============================================================================
-- 内容路由
-- ============================================================================

function WeeklyActivityUI._RenderWeeklyTab(area)
    local timeLabel = pageRoot:FindById("waTimeLeft")
    if timeLabel then
        timeLabel:SetText("倒计时: " .. WAD.GetRemainingTimeStr())
    end

    if activeSubTab == "chest" then
        if WAD.GetCurrentWeekType() == "recruit" then
            area:AddChild(RecruitMilestone.BuildBanner(WeeklyActivityUI))
            area:AddChild(RecruitMilestone.BuildList(WeeklyActivityUI))
        else
            area:AddChild(ChestMilestone.BuildBanner(WeeklyActivityUI))
            area:AddChild(ChestMilestone.BuildList(WeeklyActivityUI))
        end
    elseif activeSubTab == "black_market" then
        area:AddChild(BlackMarketUI.BuildBanner(WeeklyActivityUI))
        area:AddChild(BlackMarketUI.BuildList(WeeklyActivityUI))
    elseif activeSubTab == "drop_event" then
        area:AddChild(DropEventUI.BuildBanner(WeeklyActivityUI))
        area:AddChild(DropEventUI.BuildDailyDrops(WeeklyActivityUI))
        area:AddChild(DropEventUI._BuildWeeklyAdProgress(WeeklyActivityUI))
    elseif activeSubTab == "exchange_shop" then
        area:AddChild(DropEventUI.BuildShop(WeeklyActivityUI))
    elseif activeSubTab == "welfare" then
        area:AddChild(Welfare.Build(WeeklyActivityUI))
    elseif activeSubTab == "weekend_bonus" then
        area:AddChild(DivineBless.Build(WeeklyActivityUI))
    end
end

return WeeklyActivityUI
