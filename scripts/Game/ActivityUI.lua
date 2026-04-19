-- Game/ActivityUI.lua
-- 活动系统 UI - 门面模块
-- 子模块: ActivityUI_Shared, ActivityUI_SignIn, ActivityUI_DailyDeal,
--         ActivityUI_Cumulate, ActivityUI_Privilege, ActivityUI_Fund

local ActivityData          = require("Game.ActivityData")
local AccumulatedRewardData = require("Game.AccumulatedRewardData")
local Currency              = require("Game.Currency")
local Tooltip               = require("Game.Tooltip")

local ActivityUI = {}

-- 共享可变状态
local ctx = {
    UI                 = nil,
    pageRoot           = nil,
    contentArea        = nil,
    currentTab         = "signin",
    currentFundTab     = "devour_stone",
    currentPrivilegeTab = "welfare",
    _onBack            = nil,
    Refresh            = nil,   -- 下方赋值
}

-- 加载共享常量/工具
local Shared = require("Game.ActivityUI_Shared")(ctx)

-- 子模块（延迟初始化，CreatePage 中调用工厂）
local SignIn, DailyDeal, Cumulate, Privilege, Fund, Vault

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 创建活动页面
---@param uiModule any  UI 模块引用
---@return any  Panel
function ActivityUI.CreatePage(uiModule)
    ctx.UI = uiModule
    ActivityData.Load()

    -- 初始化子模块（此时 ctx.UI 已就绪）
    SignIn    = require("Game.ActivityUI_SignIn")(ctx, Shared)
    DailyDeal = require("Game.ActivityUI_DailyDeal")(ctx, Shared)
    Cumulate  = require("Game.ActivityUI_Cumulate")(ctx, Shared)
    Privilege = require("Game.ActivityUI_Privilege")(ctx, Shared)
    Fund      = require("Game.ActivityUI_Fund")(ctx, Shared)
    Vault     = require("Game.ActivityUI_Vault")(ctx, Shared)

    ctx.pageRoot = ctx.UI.Panel {
        id = "activityPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = Shared.S.bgDark,
        children = {},
    }

    ActivityUI.Refresh()
    return ctx.pageRoot
end

--- 设置返回回调
function ActivityUI.SetOnBack(fn)
    ctx._onBack = fn
end

--- 跳转到指定标签页（在 ShowActivityOverlay 前调用）
---@param tabId string  如 "vault" / "signin" / "shop" 等
function ActivityUI.SetTab(tabId)
    ctx.currentTab = tabId
end

-- 内容区容器（标签栏下方，不含标签栏）
local contentWrapper

--- patch 标签栏滚轮：竖向滚轮也能横向滚动
local function patchTabWheel(tabBar)
    local tabScroll = tabBar:FindById("actTabScroll")
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

--- 构建内容区域（标签栏下方：滚动内容 + 签到按钮 + 底栏）
local function buildContent()
    contentWrapper:ClearChildren()

    ActivityData.Load()
    ActivityData.MarkLogin()
    AccumulatedRewardData.Load()

    -- 尊享特权页、基金页、金库页不使用 ScrollView
    local isVipTab   = ctx.currentTab == "vip"
    local isFundTab  = ctx.currentTab == "shop"
    local isVaultTab = ctx.currentTab == "vault"

    if not isVipTab and not isFundTab and not isVaultTab then
        -- 普通标签页：使用 ScrollView
        ctx.contentArea = ctx.UI.ScrollView {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            flexShrink = 1,
            scrollY = true,
            scrollX = false,
            showScrollbar = false,
            backgroundColor = { 22, 18, 36, 255 },
            children = {
                ctx.UI.Panel {
                    id = "activityContentInner",
                    width = "100%",
                    flexDirection = "column",
                },
            },
        }
        contentWrapper:AddChild(ctx.contentArea)

        local inner = ctx.contentArea:FindById("activityContentInner")

        -- Tab banner 图
        local TAB_BANNERS = {
            signin   = "image/banner_signin.png",
            daily    = "image/banner_daily_deal.png",
            cumulate = "image/banner_cumulate.png",
        }
        local bannerPath = TAB_BANNERS[ctx.currentTab]
        if bannerPath then
            inner:AddChild(ctx.UI.Panel {
                width = "100%",
                height = 120,
                flexShrink = 0,
                overflow = "hidden",
                justifyContent = "center",
                borderRadius = 0,
                children = {
                    ctx.UI.Panel {
                        width = "100%",
                        aspectRatio = 1024 / 576,
                        backgroundImage = bannerPath,
                        borderRadius = 0,
                    },
                },
            })
        end

        -- 按 tab 构建内容
        local contentChildren = {}
        if ctx.currentTab == "signin" then
            contentChildren = SignIn.BuildContent()
        elseif ctx.currentTab == "daily" then
            contentChildren = DailyDeal.BuildContent()
        elseif ctx.currentTab == "cumulate" then
            contentChildren = Cumulate.BuildContent()
        else
            local tabDef = Shared.ACTIVITY_TABS[1]
            for _, t in ipairs(Shared.ACTIVITY_TABS) do
                if t.id == ctx.currentTab then tabDef = t; break end
            end
            contentChildren = Fund.BuildPlaceholderContent(tabDef)
        end
        for _, child in ipairs(contentChildren) do
            if child then inner:AddChild(child) end
        end
    elseif isFundTab then
        -- 基金页：VirtualList 自管滚动，不包裹 ScrollView
        local fundContainer = ctx.UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            flexShrink = 1,
            flexDirection = "column",
            backgroundColor = { 22, 18, 36, 255 },
        }
        contentWrapper:AddChild(fundContainer)
        local contentChildren = Fund.BuildContent()
        for _, child in ipairs(contentChildren) do
            if child then fundContainer:AddChild(child) end
        end
    elseif isVaultTab then
        -- 深渊金库：flex 列布局（固定头+三档卡片+固定底栏）
        local vaultContainer = ctx.UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            flexShrink = 1,
            flexDirection = "column",
            backgroundColor = { 22, 18, 36, 255 },
        }
        contentWrapper:AddChild(vaultContainer)
        local contentChildren = Vault.BuildContent()
        for _, child in ipairs(contentChildren) do
            if child then vaultContainer:AddChild(child) end
        end
    else
        -- 尊享特权页：直接 flex 容器，不包裹 ScrollView
        local vipContainer = ctx.UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            flexShrink = 1,
            backgroundColor = { 22, 18, 36, 255 },
        }
        contentWrapper:AddChild(vipContainer)
        local contentChildren = Privilege.BuildContent()
        for _, child in ipairs(contentChildren) do
            if child then vipContainer:AddChild(child) end
        end
    end

    -- 2) 签到按钮（仅签到页）
    if ctx.currentTab == "signin" then
        contentWrapper:AddChild(SignIn.CreateButton())
    end

    -- 3) 底栏
    contentWrapper:AddChild(Shared.CreateBottomBar())

    -- 更新货币数值
    local function updateChip(labelId, currencyId)
        local label = contentWrapper:FindById(labelId)
        if label then label:SetText(Shared.FormatNum(Currency.Get(currencyId))) end
    end
    updateChip("actEssenceLabel", "shadow_essence")
    updateChip("actDevourLabel", "devour_stone")
end

--- 完整刷新（首次进入 / 数据变更）
function ActivityUI.Refresh()
    if not ctx.pageRoot or not ctx.UI then return end
    ctx.pageRoot:ClearChildren()

    -- 1) 顶部 Banner（固定）
    ctx.pageRoot:AddChild(Shared.CreateBanner())

    -- 2) 标签栏（固定，切 Tab 只更新高亮样式）
    local tabBar = Shared.CreateTabBar()
    ctx.tabBarRoot = tabBar
    ctx.pageRoot:AddChild(tabBar)
    patchTabWheel(tabBar)

    -- 3) 内容容器（切 Tab 时只重建这部分）
    contentWrapper = ctx.UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        flexDirection = "column",
    }
    ctx.pageRoot:AddChild(contentWrapper)

    buildContent()

    -- 浮窗层
    Tooltip.Init(ctx.UI, ctx.pageRoot)
end

--- 仅刷新内容（切换 Tab 时调用，不重建 Banner 和标签栏）
function ActivityUI.RefreshContent()
    if not contentWrapper or not ctx.UI then return end
    buildContent()
end

-- 将 Refresh 注入 ctx，供子模块回调
ctx.Refresh = function() ActivityUI.Refresh() end
ctx.RefreshContent = function() ActivityUI.RefreshContent() end

return ActivityUI
