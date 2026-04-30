-- Game/WeeklyActivityUI/init.lua
-- 限时活动 UI：核心外壳（共享状态、子标签栏、路由分发）

local WAD            = require("Game.WeeklyActivityData")
local WelfareData    = require("Game.WelfareData")
local Tooltip        = require("Game.Tooltip")
local RMD            = require("Game.RecruitMilestoneData")
local BMD            = require("Game.BlackMarketData")
local DivineBlessDB  = require("Game.DivineBlessData")
local DED            = require("Game.DropEventData")
local LaborDayData   = require("Game.LaborDayData")
local LaborMedalData = require("Game.LaborMedalData")

local WeeklyActivityUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

local activeTab = "limited"   -- "limited" = 限时活动, "weekly" = 每周活动
local activeSubTab = "chest"
local activeLimitedSubTab = "double" -- "double" = 劳动加倍, "signin" = 劳动节签到

-- 限时活动子标签配置（图标，无文字）
local LIMITED_SUB_TABS = {
    { id = "double",  icon = "image/banner_labor_day_double_20260430095938.png" },
    { id = "signin",  icon = "image/banner_labor_day_signin_20260430095907.png" },
    { id = "medal",   icon = "image/banner_labor_medal.png" },
    { id = "mine",    icon = "image/banner_mine_dungeon.png" },
}

-- 子模块（懒加载）
local ChestMilestone   = nil
local RecruitMilestone = nil
local BlackMarketUI    = nil
local Welfare          = nil
local DivineBless      = nil
local DropEventUI      = nil
local LaborDayUI       = nil
local LaborMedalUI     = nil
local MineDungeonUI    = nil

-- 子标签配置（week 字段控制显示条件：nil=始终显示，"market"=仅市场周）
local ALL_SUB_TABS = {
    { id = "chest",         icon = "image/icon_cumulate.png",                          label = "宝箱达标",   week = { "chest", "recruit" } },
    { id = "black_market",  icon = "image/icon_black_market_20260426055156.png",       label = "黑市",       week = "market" },
    { id = "drop_event",    icon = "image/icon_drop_event_20260426050205.png",         label = "掉落活动",   week = "market" },
    { id = "exchange_shop", icon = "image/icon_exchange_shop_20260426053936.png",      label = "换购商店",   week = "market" },
    { id = "welfare",       icon = "image/icon_limited_welfare.png",                   label = "限时福利",   week = { "chest", "recruit" } },
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
        LaborDayUI       = require("Game.WeeklyActivityUI.LaborDay")
        LaborMedalUI    = require("Game.WeeklyActivityUI.LaborMedal")
        MineDungeonUI   = require("Game.WeeklyActivityUI.MineDungeon")
    end

    -- 默认打开限时活动（如果有活动）；否则打开每周活动
    activeTab = LaborDayData.IsActive() and "limited" or "weekly"

    pageRoot = UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        backgroundColor = S.bgPage,
        overflow = "hidden",
        children = {
            WeeklyActivityUI._BuildHeader(),
            WeeklyActivityUI._BuildTabBar(),
            UI.Panel { id = "waSubTabContainer", width = "100%", flexShrink = 0 },
            UI.ScrollView {
                id = "waContentArea",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                padding = 12,
                gap = 10,
            },
        },
    }
    Tooltip.Init(UI, pageRoot)
    WeeklyActivityUI.Refresh()
    return pageRoot
end

function WeeklyActivityUI.Refresh()
    if not pageRoot then return end
    local area = pageRoot:FindById("waContentArea")
    if not area then return end
    area:ClearChildren()

    WeeklyActivityUI._UpdateTabHighlight()

    -- 子标签栏：动态重建（避免隐藏仍占空间）
    local subTabContainer = pageRoot:FindById("waSubTabContainer")
    if subTabContainer then
        subTabContainer:ClearChildren()
        if activeTab == "weekly" then
            subTabContainer:AddChild(WeeklyActivityUI._BuildSubTabBar())
            WeeklyActivityUI._PatchSubTabWheel()
        elseif activeTab == "limited" then
            subTabContainer:AddChild(WeeklyActivityUI._BuildLimitedSubTabBar())
        end
    end

    -- 标题和倒计时更新
    local titleLabel = pageRoot:FindById("waHeaderTitle")
    local subtitleLabel = pageRoot:FindById("waHeaderSubtitle")
    local timeLabel = pageRoot:FindById("waTimeLeft")

    if activeTab == "limited" then
        if titleLabel then titleLabel:SetText("限时活动") end
        if subtitleLabel then subtitleLabel:SetText("劳动节限定 签到拿好礼") end
        if timeLabel then timeLabel:SetText("剩余: " .. LaborDayData.GetRemainingTimeStr()) end
        WeeklyActivityUI._RenderLimitedTab(area)
    else
        if titleLabel then titleLabel:SetText("每周活动") end
        if subtitleLabel then subtitleLabel:SetText("参与即送礼 福利领不停") end
        if timeLabel then timeLabel:SetText("倒计时: " .. WAD.GetRemainingTimeStr()) end
        WeeklyActivityUI._UpdateSubTabHighlight()
        WeeklyActivityUI._RenderWeeklyTab(area)
    end

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
    local initTitle = (activeTab == "limited") and "限时活动" or "每周活动"
    local initSubtitle = (activeTab == "limited") and "劳动节限定 签到拿好礼" or "参与即送礼 福利领不停"
    local initTime = (activeTab == "limited")
        and ("剩余: " .. LaborDayData.GetRemainingTimeStr())
        or ("倒计时: " .. WAD.GetRemainingTimeStr())

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
                        id = "waHeaderTitle",
                        text = initTitle,
                        fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                    },
                    UI.Label {
                        id = "waHeaderSubtitle",
                        text = initSubtitle,
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
                        text = initTime,
                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 一级标签栏：限时活动 / 每周活动
-- ============================================================================

local TOP_TAB_DEFS = {
    { id = "limited", label = "限时活动" },
    { id = "weekly",  label = "每周活动" },
}

function WeeklyActivityUI._BuildTabBar()
    local tabs = {}
    for _, def in ipairs(TOP_TAB_DEFS) do
        local isActive = (activeTab == def.id)
        local hasRed = false
        if def.id == "limited" then
            hasRed = LaborDayData.HasClaimable() or LaborMedalData.HasClaimable()
        end
        tabs[#tabs + 1] = UI.Panel {
            id = "waTopTab_" .. def.id,
            flexGrow = 1,
            height = 38,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = isActive and { 50, 35, 80, 255 } or { 20, 16, 35, 200 },
            borderBottomWidth = isActive and 3 or 0,
            borderColor = isActive and { 220, 160, 60, 255 } or { 0, 0, 0, 0 },
            pointerEvents = "auto",
            onClick = function()
                if activeTab ~= def.id then
                    activeTab = def.id
                    WeeklyActivityUI.Refresh()
                end
            end,
            children = {
                UI.Label {
                    id = "waTopTabLabel_" .. def.id,
                    text = def.label,
                    fontSize = 14,
                    fontColor = isActive and { 255, 220, 100, 255 } or { 150, 140, 170, 200 },
                    fontWeight = isActive and "bold" or "normal",
                },
                -- 红点
                (hasRed and UI.Panel {
                    id = "waTopTabRedDot_" .. def.id,
                    position = "absolute",
                    top = 6, right = "30%",
                    width = 8, height = 8,
                    borderRadius = 4,
                    backgroundColor = { 255, 60, 60, 255 },
                } or nil),
            },
        }
    end

    return UI.Panel {
        id = "waTopTabBar",
        width = "100%",
        flexDirection = "row",
        flexShrink = 0,
        backgroundColor = { 20, 16, 35, 240 },
        borderBottomWidth = 1,
        borderColor = { 60, 50, 90, 100 },
        children = tabs,
    }
end

function WeeklyActivityUI._UpdateTabHighlight()
    if not pageRoot then return end
    for _, def in ipairs(TOP_TAB_DEFS) do
        local isActive = (activeTab == def.id)
        local tabW = pageRoot:FindById("waTopTab_" .. def.id)
        if tabW then
            tabW:SetStyle({
                backgroundColor = isActive and { 50, 35, 80, 255 } or { 20, 16, 35, 200 },
                borderBottomWidth = isActive and 3 or 0,
                borderColor = isActive and { 220, 160, 60, 255 } or { 0, 0, 0, 0 },
            })
        end
        local labelW = pageRoot:FindById("waTopTabLabel_" .. def.id)
        if labelW then
            labelW:SetStyle({
                fontColor = isActive and { 255, 220, 100, 255 } or { 150, 140, 170, 200 },
                fontWeight = isActive and "bold" or "normal",
            })
        end
    end
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
        height = 80,
        flexShrink = 0,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        backgroundColor = { 28, 22, 45, 240 },
        paddingTop = 4, paddingBottom = 4,
        borderBottomWidth = 1,
        borderColor = { 70, 55, 100, 100 },
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

-- ============================================================================
-- 限时活动子标签栏（纯图标，无文字）
-- ============================================================================

function WeeklyActivityUI._BuildLimitedSubTabBar()
    local icons = {}
    for _, tab in ipairs(LIMITED_SUB_TABS) do
        local isActive = (activeLimitedSubTab == tab.id)
        icons[#icons + 1] = WeeklyActivityUI._CreateLimitedSubTabIcon(tab, isActive)
    end

    return UI.Panel {
        id = "waLimitedSubTabBar",
        width = "100%",
        flexShrink = 0,
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 8,
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6, paddingBottom = 6,
        backgroundColor = { 28, 22, 45, 240 },
        borderBottomWidth = 1,
        borderColor = { 70, 55, 100, 100 },
        children = icons,
    }
end

function WeeklyActivityUI._CreateLimitedSubTabIcon(tab, isActive)
    return UI.Panel {
        id = "waLtdTab_" .. tab.id,
        width = "48%",
        flexGrow = 0, flexShrink = 0,
        height = 64,
        borderRadius = 10,
        borderWidth = isActive and 2 or 1,
        borderColor = isActive and { 255, 200, 50, 220 } or { 70, 55, 90, 120 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function()
            if activeLimitedSubTab ~= tab.id then
                activeLimitedSubTab = tab.id
                WeeklyActivityUI._UpdateLimitedSubTabHighlight()
                WeeklyActivityUI.Refresh()
            end
        end,
        children = {
            UI.Panel {
                width = "100%", height = "100%",
                backgroundImage = tab.icon,
                backgroundFit = "cover",
                backgroundPosition = "center",
                pointerEvents = "none",
                borderRadius = 10,
            },
        },
    }
end

function WeeklyActivityUI._UpdateLimitedSubTabHighlight()
    if not pageRoot then return end
    for _, tab in ipairs(LIMITED_SUB_TABS) do
        local isActive = (activeLimitedSubTab == tab.id)
        local widget = pageRoot:FindById("waLtdTab_" .. tab.id)
        if widget then
            widget:SetStyle({
                borderWidth = isActive and 2 or 1,
                borderColor = isActive and { 255, 200, 50, 220 } or { 70, 55, 90, 120 },
            })
        end
    end
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

-- ============================================================================
-- 限时活动内容路由（劳动节签到等）
-- ============================================================================

function WeeklyActivityUI._RenderLimitedTab(area)
    WeeklyActivityUI._UpdateLimitedSubTabHighlight()

    if activeLimitedSubTab == "double" then
        -- 劳动加倍页
        area:AddChild(WeeklyActivityUI._BuildDoubleRewardBanner())
    elseif activeLimitedSubTab == "signin" then
        -- 劳动节签到页
        if LaborDayUI then
            area:AddChild(LaborDayUI.BuildBanner(WeeklyActivityUI))
            area:AddChild(LaborDayUI.BuildSignButton(WeeklyActivityUI))
            area:AddChild(LaborDayUI.BuildList(WeeklyActivityUI))
        end
    elseif activeLimitedSubTab == "medal" then
        -- 劳动奖章收集页
        if LaborMedalUI then
            area:AddChild(LaborMedalUI.BuildBanner(WeeklyActivityUI))
            area:AddChild(LaborMedalUI.BuildMilestones(WeeklyActivityUI))
            area:AddChild(LaborMedalUI.BuildShop(WeeklyActivityUI))
        end
    elseif activeLimitedSubTab == "mine" then
        -- 矿洞寻宝页
        if MineDungeonUI then
            area:AddChild(MineDungeonUI.BuildBanner(WeeklyActivityUI))
        end
    end
end

--- 劳动加倍横幅
function WeeklyActivityUI._BuildDoubleRewardBanner()
    local remaining = LaborDayData.GetRemainingTimeStr()
    local doubleLeft = LaborDayData.GetDoubleRemaining()
    local doubleUsed = LaborDayData.GetDoubleUsed()
    local limit = LaborDayData.DOUBLE_DAILY_LIMIT

    -- 适用场景列表
    local DOUBLE_SCENES = {
        { label = "挂机收益领取", desc = "每次领取消耗1次" },
        { label = "资源副本结算", desc = "每次通关消耗1次" },
        { label = "憎恨之地结算", desc = "每次通关消耗1次" },
        { label = "深渊裂隙结算", desc = "每次通关消耗1次" },
        { label = "翡翠秘境结算", desc = "每次通关/扫荡消耗1次" },
        { label = "世界BOSS结算", desc = "每次挑战消耗1次" },
    }

    -- 构造适用场景子项
    local sceneItems = {}
    for i, sc in ipairs(DOUBLE_SCENES) do
        sceneItems[#sceneItems + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            width = "100%",
            children = {
                UI.Panel {
                    width = 5, height = 5,
                    borderRadius = 3,
                    backgroundColor = { 100, 200, 255, 200 },
                    flexShrink = 0,
                },
                UI.Label {
                    text = sc.label,
                    fontSize = 12,
                    fontColor = { 220, 230, 255, 255 },
                    flexShrink = 0,
                },
                UI.Label {
                    text = sc.desc,
                    fontSize = 10,
                    fontColor = { 130, 160, 190, 180 },
                    flexShrink = 1,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 20, 40, 60, 240 },
        borderRadius = 10,
        borderWidth = 2,
        borderColor = { 60, 180, 255, 200 },
        overflow = "hidden",
        marginBottom = 8,
        children = {
            -- 活动配图
            UI.Panel {
                width = "100%", height = 120,
                backgroundImage = "image/banner_labor_day_double_20260430095938.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                borderTopLeftRadius = 10,
                borderTopRightRadius = 10,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 14, paddingBottom = 14,
                paddingLeft = 16, paddingRight = 16,
                gap = 10,
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        width = "100%",
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 10,
                                flexShrink = 1,
                                children = {
                                    UI.Panel {
                                        width = 42, height = 42,
                                        borderRadius = 21,
                                        backgroundColor = { 40, 120, 200, 240 },
                                        justifyContent = "center",
                                        alignItems = "center",
                                        borderWidth = 2,
                                        borderColor = { 100, 200, 255, 200 },
                                        children = {
                                            UI.Label {
                                                text = "x2",
                                                fontSize = 18,
                                                fontColor = { 255, 240, 100, 255 },
                                                fontWeight = "bold",
                                            },
                                        },
                                    },
                                    UI.Panel {
                                        gap = 3,
                                        flexShrink = 1,
                                        children = {
                                            UI.Label {
                                                text = "劳动加倍 · 副本收益翻倍",
                                                fontSize = 15,
                                                fontColor = { 100, 220, 255, 255 },
                                                fontWeight = "bold",
                                            },
                                            UI.Label {
                                                text = "每日 " .. limit .. " 次，副本/挂机结算 ×2",
                                                fontSize = 11,
                                                fontColor = { 160, 200, 230, 200 },
                                            },
                                        },
                                    },
                                },
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 5, paddingBottom = 5,
                                backgroundColor = { 30, 80, 140, 200 },
                                borderRadius = 8,
                                children = {
                                    UI.Label {
                                        text = "剩余: " .. remaining,
                                        fontSize = 11,
                                        fontColor = { 100, 200, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 今日翻倍次数进度条
                    UI.Panel {
                        width = "100%",
                        gap = 6,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                width = "100%",
                                children = {
                                    UI.Label {
                                        text = "今日翻倍次数",
                                        fontSize = 12,
                                        fontColor = { 160, 200, 230, 220 },
                                    },
                                    UI.Label {
                                        text = doubleUsed .. " / " .. limit,
                                        fontSize = 12,
                                        fontColor = doubleLeft > 0
                                            and { 100, 255, 150, 255 }
                                            or  { 255, 120, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            -- 进度条
                            UI.Panel {
                                width = "100%", height = 8,
                                backgroundColor = { 15, 30, 50, 200 },
                                borderRadius = 4,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = math.floor(doubleUsed / limit * 100) .. "%",
                                        height = "100%",
                                        backgroundColor = doubleLeft > 0
                                            and { 60, 180, 255, 255 }
                                            or  { 255, 100, 60, 255 },
                                        borderRadius = 4,
                                    },
                                },
                            },
                        },
                    },
                    -- 适用范围说明
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 15, 25, 45, 200 },
                        borderRadius = 8,
                        paddingTop = 10, paddingBottom = 10,
                        paddingLeft = 12, paddingRight = 12,
                        gap = 6,
                        borderWidth = 1,
                        borderColor = { 50, 80, 120, 120 },
                        children = {
                            UI.Label {
                                text = "适用范围（每次结算消耗1次翻倍机会）",
                                fontSize = 12,
                                fontColor = { 100, 200, 255, 240 },
                                fontWeight = "bold",
                                marginBottom = 2,
                            },
                            table.unpack(sceneItems),
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 每周活动内容路由
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
