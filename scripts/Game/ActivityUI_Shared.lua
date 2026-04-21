-- Game/ActivityUI_Shared.lua
-- 活动页面共享常量、样式、工具函数与布局组件


return function(ctx)

local Config = require("Game.Config")
local Currency = require("Game.Currency")
local Tooltip = require("Game.Tooltip")
local FormatNum = require("Game.FormatUtil").FormatNum
local Shared = {}

-- ============================================================================
-- 样式常量
-- ============================================================================
local S = {
    bgDark      = { 18, 14, 32, 255 },
    cardBg      = { 30, 24, 50, 240 },
    cardBorder  = { 80, 60, 130, 120 },
    headerBg    = { 40, 25, 15, 250 },
    goldAccent  = { 255, 200, 50 },
    textPrimary = { 230, 220, 250, 255 },
    textSecondary = { 160, 150, 180, 200 },
    textMuted   = { 120, 110, 140, 160 },
    claimedBg   = { 40, 60, 40, 200 },
    claimedBorder = { 80, 160, 80, 180 },
    todayBg     = { 60, 40, 20, 240 },
    todayBorder = { 255, 200, 50, 200 },
    futureBg    = { 25, 20, 40, 180 },
    futureBorder = { 60, 50, 80, 100 },
    checkColor  = { 120, 200, 80, 255 },
    -- 底栏
    bottomBg    = { 22, 18, 36, 245 },
    bottomBorder = { 80, 60, 130, 100 },
}

-- 奖励类型颜色
local REWARD_COLORS = {
    shadow_essence = { 180, 140, 255 },
    devour_stone   = { 60, 160, 80 },
    forge_iron     = { 130, 160, 200 },
    ur_shard_box   = { 255, 200, 50 },
    shadow_orb     = { 160, 80, 200 },
}

-- 活动标签定义
local ACTIVITY_TABS = {
    { id = "signin",    icon = "image/icon_signin.png",       label = "签到" },
    { id = "daily",     icon = "image/icon_daily_deal.png",   label = "每日特惠" },
    { id = "cumulate",  icon = "image/icon_cumulate.png",     label = "积天好礼" },
    { id = "shop",      icon = "image/icon_fund_shop.png",    label = "基金商城" },
    { id = "vault",     icon = "image/icon_vault.png",        label = "深渊金库" },
    { id = "vip",       icon = "image/icon_vip.png",          label = "尊享" },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- FormatNum → 使用 FormatUtil.FormatNum

--- 获取奖励简短文本+颜色
local function GetRewardDisplay(reward)
    if not reward then return "?", { 150, 150, 150 } end
    if reward.type == "currency" then
        local color = REWARD_COLORS[reward.id] or { 200, 200, 200 }
        return "×" .. reward.amount, color
    elseif reward.type == "chest" then
        return "×" .. reward.amount, { 255, 200, 50 }
    elseif reward.type == "item" then
        return "×" .. reward.amount, { 255, 200, 50 }
    end
    return "?", { 150, 150, 150 }
end

-- 奖励描述（硬编码）
local REWARD_DESC = {
    shadow_essence = "珍贵精华，可在商店兑换稀有碎片与材料",
    devour_stone   = "噬魂之石，英雄进阶突破的必需材料",
    forge_iron     = "锻造原料，用于装备强化升级",
    ur_shard_box   = "开启后可任选一个UR英雄碎片",
    void_pact      = "虚空契约，用于招募强力英雄",
    nether_crystal = "冥界结晶，英雄升级的核心资源",
    bronze_chest   = "青铜宝箱，开启可获得随机奖励",
    shadow_orb     = "幽影珠，可在神秘商店兑换物品",
}

--- 获取奖励的浮窗显示信息
---@param reward table
---@return string title, string desc
local function GetRewardTooltipInfo(reward)
    if not reward then return "?", "" end
    local id = reward.id
    if reward.type == "currency" then
        local def = Config.CURRENCY[id]
        local name = (def and def.name or id) .. " ×" .. reward.amount
        return name, REWARD_DESC[id] or ""
    elseif reward.type == "chest" then
        local name = "万能UR碎片箱 ×" .. reward.amount
        return name, REWARD_DESC[id] or ""
    elseif reward.type == "item" then
        local def = Config.CURRENCY[id]
        local name = (def and def.name or id) .. " ×" .. reward.amount
        return name, REWARD_DESC[id] or "存入仓库"
    end
    return "奖励", ""
end

-- 签到总天数（与 ActivityData 一致）
local CYCLE_DAYS = 30

-- ============================================================================
-- 顶部 Banner 区域（20%）
local function CreateBanner()
    return ctx.UI.Panel {
        width = "100%",
        height = "20%",
        flexShrink = 0,
        backgroundImage = "image/activity_header_bg.png",
        backgroundSize = "cover",
        justifyContent = "center",
        alignItems = "center",
        borderBottomWidth = 2,
        borderColor = { 180, 120, 40, 150 },
        children = {
            -- 顶部标题
            ctx.UI.Label {
                text = "福利活动",
                fontSize = 26,
                fontColor = { 255, 220, 100, 255 },
                fontWeight = "bold",
            },
            ctx.UI.Label {
                text = "参与即送礼 福利领不停",
                fontSize = 12,
                fontColor = { 220, 180, 120, 200 },
                marginTop = 4,
            },
        },
    }
end

-- ============================================================================
-- 标签栏（横向滚动，15%）
-- ============================================================================

-- Tab 样式常量
local TAB_STYLE_ACTIVE = {
    bg    = { 80, 50, 20, 255 },
    border = { 255, 200, 50, 220 },
    borderW = 2,
    label = { 255, 220, 100, 255 },
    fontW = "bold",
}
local TAB_STYLE_INACTIVE = {
    bg    = { 35, 28, 55, 220 },
    border = { 70, 55, 90, 120 },
    borderW = 1,
    label = { 160, 150, 180, 200 },
    fontW = "normal",
}

--- 更新所有 Tab 高亮状态（不重建）
local function updateTabHighlight(tabBarRoot)
    for _, tab in ipairs(ACTIVITY_TABS) do
        local isActive = (ctx.currentTab == tab.id)
        local s = isActive and TAB_STYLE_ACTIVE or TAB_STYLE_INACTIVE
        local tabWidget = tabBarRoot:FindById("actTab_" .. tab.id)
        if tabWidget then
            tabWidget:SetStyle({
                backgroundColor = s.bg,
                borderColor = s.border,
                borderWidth = s.borderW,
            })
        end
        local labelWidget = tabBarRoot:FindById("actTabLabel_" .. tab.id)
        if labelWidget then
            labelWidget:SetStyle({ fontColor = s.label, fontWeight = s.fontW })
        end
    end
end

--- 单个标签图标
local function CreateTabIcon(tab, isActive)
    local s = isActive and TAB_STYLE_ACTIVE or TAB_STYLE_INACTIVE

    return ctx.UI.Panel {
        id = "actTab_" .. tab.id,
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
            if ctx.currentTab ~= tab.id then
                ctx.currentTab = tab.id
                -- 只更新高亮 + 下方内容，不重建标签栏
                if ctx.tabBarRoot then
                    updateTabHighlight(ctx.tabBarRoot)
                end
                if ctx.RefreshContent then
                    ctx.RefreshContent()
                end
            end
        end,
        children = {
            -- 上部 70%：图标
            ctx.UI.Panel {
                width = "100%", height = "70%",
                backgroundImage = tab.icon,
                backgroundFit = "cover",
                backgroundPosition = "center",
                pointerEvents = "none",
            },
            -- 下部 30%：活动名
            ctx.UI.Panel {
                width = "100%", height = "30%",
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    ctx.UI.Label {
                        id = "actTabLabel_" .. tab.id,
                        text = tab.label,
                        fontSize = 10,
                        fontColor = s.label,
                        fontWeight = s.fontW,
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

local function CreateTabBar()
    local tabIcons = {}
    for _, tab in ipairs(ACTIVITY_TABS) do
        tabIcons[#tabIcons + 1] = CreateTabIcon(tab, ctx.currentTab == tab.id)
    end

    return ctx.UI.ScrollView {
        id = "actTabScroll",
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
        children = {
            ctx.UI.Panel {
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
-- 底栏（返回 + 货币显示，15%）
-- ============================================================================

---@type function|nil  外部注入的返回回调
ctx._onBack = nil

local function CreateBottomBar()
    return ctx.UI.Panel {
        width = "100%",
        height = "13%",
        minHeight = 56,
        flexShrink = 0,
        backgroundColor = S.bottomBg,
        borderTopWidth = 1,
        borderColor = S.bottomBorder,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 10, paddingRight = 10,
        gap = 8,
        children = {
            -- 返回按钮
            ctx.UI.Button {
                text = "返回",
                fontSize = 15,
                width = 72,
                height = 40,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    if ctx._onBack then
                        ctx._onBack()
                    end
                end,
            },
            -- 弹性间距
            ctx.UI.Panel { flexGrow = 1 },
            -- 当前拥有提示
            ctx.UI.Label {
                text = "当前拥有",
                fontSize = 10,
                fontColor = S.textMuted,
            },
            require("Game.GameUI").CreateCurrencyChip(ctx.UI, "shadow_essence", "actEssenceLabel", { 180, 140, 255 }),
            require("Game.GameUI").CreateCurrencyChip(ctx.UI, "devour_stone", "actDevourLabel", { 60, 160, 80 }),
        },
    }
end

-- Export
Shared.S = S
Shared.REWARD_COLORS = REWARD_COLORS
Shared.REWARD_DESC = REWARD_DESC
Shared.ACTIVITY_TABS = ACTIVITY_TABS
Shared.CYCLE_DAYS = CYCLE_DAYS
Shared.FormatNum = FormatNum
Shared.GetRewardDisplay = GetRewardDisplay
Shared.GetRewardTooltipInfo = GetRewardTooltipInfo
Shared.CreateBanner = CreateBanner
Shared.CreateTabBar = CreateTabBar
Shared.CreateBottomBar = CreateBottomBar

return Shared
end
