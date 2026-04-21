-- Game/RecruitUI/init.lua
-- 招募页面 UI 入口（常驻池 + 限定池标签切换）
-- require("Game.RecruitUI") 会自动加载此文件

local Config    = require("Game.Config")
local NormalPool = require("Game.RecruitUI.NormalPool")
local LimitedPool = require("Game.RecruitUI.LimitedPool")
local GachaResult = require("Game.RecruitUI.GachaResult")

local RecruitUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

-- 当前标签页（"normal" 常驻池 / "limited" 限定池）
local currentTab = "normal"

-- 当前选中的限定池索引（对应 Config.LIMITED_BANNERS）
local limitedBannerIdx = 1

-- 返回回调（由 GameUI 设置）
local onBackCallback = nil

-- 稀有度颜色（引用 Config 统一定义）
local RARITY_COLORS = Config.RARITY_COLORS

-- 稀有度背景颜色（暗色调）
local RARITY_BG = {
    N   = { 35, 35, 30, 200 },
    R   = { 30, 50, 30, 200 },
    SR  = { 35, 25, 55, 200 },
    SSR = { 50, 40, 15, 200 },
    UR  = { 50, 45, 10, 200 },
    LR  = { 50, 15, 15, 200 },
}

--- 设置返回回调
function RecruitUI.SetOnBack(cb)
    onBackCallback = cb
end

--- 创建招募页面
---@param uiModule any
---@return any
function RecruitUI.CreatePage(uiModule)
    UI = uiModule

    pageRoot = UI.Panel {
        id = "recruitPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 15, 12, 25, 255 },
        children = {},
    }

    RecruitUI.Refresh()
    return pageRoot
end

--- 刷新页面内容
function RecruitUI.Refresh()
    if not pageRoot or not UI then return end
    pageRoot:ClearChildren()

    if currentTab == "limited" then
        RecruitUI.RefreshLimited()
    else
        RecruitUI.RefreshNormal()
    end
end

--- 刷新常驻池内容
function RecruitUI.RefreshNormal()
    -- 切换到常驻池时停止限定池立绘动画
    LimitedPool.StopArtworkAnim()
    -- 顶部招募令显示
    pageRoot:AddChild(NormalPool.CreateTokenBar(UI))
    -- 池子横幅
    pageRoot:AddChild(NormalPool.CreatePoolBanner(UI,
        function() NormalPool.ShowAdPactDialog(UI, pageRoot, RecruitUI.Refresh) end,
        function() NormalPool.ShowDetailPopup(UI, pageRoot, RARITY_COLORS, RARITY_BG) end
    ))
    -- 底部按钮区
    pageRoot:AddChild(NormalPool.CreateButtonArea(UI, pageRoot, RARITY_COLORS, currentTab, RecruitUI.Refresh))
    -- 标签栏 + 返回
    pageRoot:AddChild(RecruitUI.CreateTabBar())
end

--- 刷新限定池内容
function RecruitUI.RefreshLimited()
    local bannerCfg = Config.LIMITED_BANNERS[limitedBannerIdx]
        or Config.LIMITED_BANNERS[1]

    -- 顶部货币栏
    pageRoot:AddChild(LimitedPool.CreateTokenBar(UI, bannerCfg))
    -- 横幅
    pageRoot:AddChild(LimitedPool.CreateBanner(UI, bannerCfg,
        function() LimitedPool.ShowAdFrostDialog(UI, pageRoot, bannerCfg, RecruitUI.Refresh) end,
        function() LimitedPool.ShowAdTicketDialog(UI, pageRoot, bannerCfg, RecruitUI.Refresh) end,
        function() LimitedPool.ShowDetailPopup(UI, pageRoot, bannerCfg, RARITY_COLORS, RARITY_BG) end
    ))
    -- 按钮区
    pageRoot:AddChild(LimitedPool.CreateButtonArea(UI, bannerCfg, pageRoot, RARITY_COLORS, currentTab, RecruitUI.Refresh))
    -- 标签栏 + 返回
    pageRoot:AddChild(RecruitUI.CreateTabBar())
end

-- ============================================================================
-- 标签栏 + 返回按钮
-- ============================================================================

--- 创建标签栏：[返回] [常驻池] [凛冬君王] [苍华极脉] ...
function RecruitUI.CreateTabBar()
    local LBD = require("Game.LimitedBannerData")

    -- 常驻池是否选中
    local normalActive = (currentTab == "normal")

    local children = {
        -- 返回按钮
        UI.Panel {
            width = 72, height = 44,
            borderRadius = 8,
            backgroundColor = { 50, 40, 70, 255 },
            borderWidth = 1,
            borderColor = { 120, 90, 160, 180 },
            justifyContent = "center",
            alignItems = "center",
            flexShrink = 0,
            onClick = function(self)
                if onBackCallback then onBackCallback() end
            end,
            children = {
                UI.Label {
                    text = "返回",
                    fontSize = 15,
                    fontColor = { 200, 180, 240, 255 },
                    fontWeight = "bold",
                },
            },
        },
        -- 常驻池
        UI.Panel {
            flex = 1, height = 44,
            borderRadius = 8,
            backgroundColor = normalActive and { 100, 70, 180, 255 } or { 40, 35, 55, 200 },
            borderWidth = 1,
            borderColor = normalActive and { 180, 140, 255, 200 } or { 60, 50, 80, 100 },
            justifyContent = "center",
            alignItems = "center",
            onClick = function(self)
                if currentTab ~= "normal" then
                    currentTab = "normal"
                    RecruitUI.Refresh()
                end
            end,
            children = {
                UI.Label {
                    text = "常驻池",
                    fontSize = 15,
                    fontColor = normalActive and { 255, 255, 255, 255 } or { 150, 140, 170, 200 },
                    fontWeight = "bold",
                },
            },
        },
    }

    -- 每个限定池直接作为独立标签
    for i, bc in ipairs(Config.LIMITED_BANNERS) do
        local isActive = (currentTab == "limited" and limitedBannerIdx == i)
        local isLocked = LBD.IsLocked(bc)
        local poolName = bc.name or bc.heroId

        -- 主题色
        local tc = { 130, 210, 255 }
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == bc.heroId then tc = td.color; break end
        end

        children[#children + 1] = UI.Panel {
            flex = 1, height = 44,
            borderRadius = 8,
            backgroundColor = isActive
                and { math.floor(tc[1] * 0.3), math.floor(tc[2] * 0.3), math.floor(tc[3] * 0.3), 255 }
                or  { 40, 35, 55, 200 },
            borderWidth = isActive and 2 or 1,
            borderColor = isActive
                and { tc[1], tc[2], tc[3], 220 }
                or  { 60, 50, 80, 100 },
            justifyContent = "center",
            alignItems = "center",
            gap = 2,
            onClick = function()
                currentTab        = "limited"
                limitedBannerIdx  = i
                RecruitUI.Refresh()
            end,
            children = {
                UI.Label {
                    text = (isLocked and "🔒 " or "") .. poolName,
                    fontSize = 14,
                    fontColor = isActive
                        and { tc[1], tc[2], tc[3], 255 }
                        or  { 150, 140, 170, 200 },
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        paddingTop = 8, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 20, 16, 32, 230 },
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        flexShrink = 0,
        children = children,
    }
end

return RecruitUI
