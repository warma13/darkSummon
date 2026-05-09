-- Game/HeroUI/HeroDetail/init.lua
-- 英雄详情面板 - 主控模块
-- 拆分自原 HeroDetail.lua (3573 行)，管理标签路由、面板生命周期和模块状态

local Config     = require("Game.Config")
local HeroData   = require("Game.HeroData")
local Toast      = require("Game.Toast")

-- 子模块（延迟 require 避免循环依赖由 Lua cache 天然解决）
local StatEngine = require("Game.HeroUI.HeroDetail.StatEngine")
local InfoTab    = require("Game.HeroUI.HeroDetail.InfoTab")
local EquipTab   = require("Game.HeroUI.HeroDetail.EquipTab")
local CostumeTab = require("Game.HeroUI.HeroDetail.CostumeTab")
local TitleTab   = require("Game.HeroUI.HeroDetail.TitleTab")
local RelicTab   = require("Game.HeroUI.HeroDetail.RelicTab")

local HeroDetail = {}

-- ============================================================================
-- 模块级状态
-- ============================================================================

---@type string|nil
local detailHeroId = nil
---@type string
local detailTab = "info"

---@type any
local detailContentContainer = nil

--- 遗物标签页状态
local selectedRelicSlot = "power"
local selectedRelicView = nil

--- header 战力 Label 引用
---@type any
local headerPowerLabel = nil

--- 每秒属性自动刷新
local detailRefreshAccum = 0
local detailRefreshCallback = nil

--- 英雄标签页定义（普通英雄）
local DETAIL_TABS = {
    { key = "info",    label = "信息" },
    { key = "equip",   label = "装备" },
    { key = "starup",  label = "升星" },
    { key = "skin",    label = "皮肤" },
}

--- 主角专属标签页
local LEADER_TABS = {
    { key = "info",    label = "信息" },
    { key = "costume", label = "时装" },
    { key = "title",   label = "称号" },
    { key = "relic",   label = "遗物" },
}

-- ============================================================================
-- 公共接口
-- ============================================================================

function HeroDetail.GetCurrentHeroId()
    return detailHeroId
end

function HeroDetail.OnPageClear()
    HeroDetail.StopAutoRefresh()
    detailContentContainer = nil
    detailHeroId = nil
    headerPowerLabel = nil
    selectedRelicSlot = "power"
    selectedRelicView = nil
end

-- ============================================================================
-- 每秒属性自动刷新（由 GameLoop.HandleUpdate 驱动）
-- ============================================================================

local DETAIL_REFRESH_INTERVAL = 1.0

function HeroDetail.Tick(dt)
    if not detailRefreshCallback then return end
    detailRefreshAccum = detailRefreshAccum + dt
    if detailRefreshAccum >= DETAIL_REFRESH_INTERVAL then
        detailRefreshAccum = detailRefreshAccum - DETAIL_REFRESH_INTERVAL
        detailRefreshCallback()
    end
end

function HeroDetail.StartAutoRefresh(refreshFn)
    detailRefreshCallback = refreshFn
    detailRefreshAccum = 0
end

function HeroDetail.StopAutoRefresh()
    detailRefreshCallback = nil
    detailRefreshAccum = 0
end

local function ShowToast(msg) Toast.Show(msg) end

-- ============================================================================
-- 标签页路由
-- ============================================================================

--- 遗物标签页的 state 代理（让 RelicTab 读写模块级变量）
local function MakeRelicState()
    return {
        selectedRelicSlot = selectedRelicSlot,
        selectedRelicView = selectedRelicView,
        setSlot = function(v) selectedRelicSlot = v end,
        setView = function(v) selectedRelicView = v end,
    }
end

--- 刷新详情面板内容区域
local function RefreshDetailContent(ctx, heroId, heroDef)
    if not detailContentContainer then return end
    detailContentContainer:ClearChildren()

    local content
    if detailTab == "info" then
        content = InfoTab.Build(ctx, heroId, heroDef)
    elseif detailTab == "equip" then
        content = EquipTab.BuildEquip(ctx, heroId, heroDef)
    elseif detailTab == "starup" then
        content = EquipTab.BuildStarUp(ctx, heroId, heroDef)
    elseif detailTab == "skin" then
        content = EquipTab.BuildSkin(ctx, heroId, heroDef)
    elseif detailTab == "costume" then
        content = CostumeTab.Build(ctx, heroId)
    elseif detailTab == "title" then
        content = TitleTab.Build(ctx, heroId)
    elseif detailTab == "relic" then
        content = RelicTab.Build(ctx, heroId, MakeRelicState())
    end

    if content then
        detailContentContainer:AddChild(content)
    end
end

-- ============================================================================
-- ShowHeroDetail
-- ============================================================================

function HeroDetail.ShowHeroDetail(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local pageRoot = ctx.GetPageRoot()
    local FormatBigNum = ctx.FormatBigNum
    local CreateStarRows = ctx.CreateStarRows
    local HeroCardMod = require("Game.HeroUI.HeroCard")

    -- 查找英雄定义
    local heroDef = nil
    if Config.LEADER_HERO.id == heroId then
        heroDef = Config.LEADER_HERO
    else
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then heroDef = td; break end
        end
    end
    if not heroDef then return end

    -- 保持标签状态
    if detailHeroId ~= heroId then
        detailTab = "info"
    end
    detailHeroId = heroId

    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false
    local level = (h and h.level) or 1
    local rarity = heroDef.rarity or "R"
    local rarityColor = ctx.GetRarityColor(rarity)
    local rarityBorder = ctx.GetRarityBorderColor(rarity)
    local tierInfo = HeroData.GetStarTierInfo(heroId)
    local stats = StatEngine.ComputeFullStats(heroId)
    local power = stats.power
    local HeroAvatar = require("Game.HeroAvatar")

    -- 星级显示
    local starChildren = {}
    if isUnlocked and tierInfo.starInTier > 0 then
        local starRows = CreateStarRows(tierInfo.starInTier, tierInfo.color)
        for _, row in ipairs(starRows) do
            starChildren[#starChildren + 1] = row
        end
    end

    -- 英雄切换列表
    local isLeader = (heroDef.isLeader == true)
    local allHeroList = HeroCardMod.GetSortedHeroes(ctx)
    local currentHeroIdx = 1
    for i, hd in ipairs(allHeroList) do
        if hd.id == heroId then currentHeroIdx = i; break end
    end

    -- ========== 顶部：大头像展示 + 品质/名字 + 左右切换 ==========
    local elemId = Config.HERO_ELEMENT[heroId]
    local elemDef = elemId and Config.ELEMENTS[elemId]

    local topChildren = {}

    if rarity ~= "none" then
        topChildren[#topChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Label { text = rarity, fontSize = 16, fontColor = rarityBorder, fontWeight = "bold" },
            },
        }
    end

    topChildren[#topChildren + 1] = UI.Label { text = heroDef.name, fontSize = 18, fontColor = S.white, fontWeight = "bold" }

    local elemStarChildren = {}
    if elemDef then
        local DMG_SHORT = { physical = "物", magical = "法", pure = "真" }
        local shortLabel = DMG_SHORT[elemId] or "?"
        elemStarChildren[#elemStarChildren + 1] = UI.Panel {
            width = 16, height = 16,
            borderRadius = 8,
            backgroundColor = { elemDef.color[1], elemDef.color[2], elemDef.color[3], 200 },
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = shortLabel,
                    fontSize = 9,
                    fontColor = { 255, 255, 255, 240 },
                    fontWeight = "bold",
                },
            },
        }
    end
    if #starChildren > 0 then
        elemStarChildren[#elemStarChildren + 1] = UI.Panel {
            flexDirection = "row", gap = 1, alignItems = "center",
            children = starChildren,
        }
    end
    topChildren[#topChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        height = 18,
        children = elemStarChildren,
    }

    topChildren[#topChildren + 1] = UI.Panel {
        width = 100, height = 100,
        children = {
            HeroAvatar.Create(heroId, {
                preset = "icon",
                fit = "contain",
                borderRadius = 12,
                isUnlocked = isUnlocked,
                borderColor = rarityBorder,
                opacity = isUnlocked and 1.0 or 0.5,
            }),
        },
    }

    if isUnlocked then
        headerPowerLabel = UI.Label { text = "战力:" .. FormatBigNum(power), fontSize = 12, fontColor = S.powerYellow }
        topChildren[#topChildren + 1] = UI.Panel {
            flexDirection = "row", gap = 10, alignItems = "center",
            children = {
                UI.Label { text = "Lv." .. level, fontSize = 14, fontColor = S.gold, fontWeight = "bold" },
                headerPowerLabel,
            },
        }
    else
        headerPowerLabel = nil
        topChildren[#topChildren + 1] = UI.Label { text = "未解锁", fontSize = 13, fontColor = S.dimLocked }
    end

    -- 左右箭头（主角不显示）
    if not isLeader then
        topChildren[#topChildren + 1] = UI.Panel {
            position = "absolute",
            left = 6, top = "50%",
            marginTop = -18,
            width = 36, height = 36,
            borderRadius = 18,
            backgroundColor = { 60, 45, 35, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function(self)
                local prevIdx = currentHeroIdx - 1
                if prevIdx < 1 then prevIdx = #allHeroList end
                detailHeroId = allHeroList[prevIdx].id
                HeroDetail.ShowHeroDetail(ctx, allHeroList[prevIdx].id)
            end,
            children = {
                UI.Label { text = "<", fontSize = 20, fontColor = { 200, 180, 160, 220 }, fontWeight = "bold" },
            },
        }

        topChildren[#topChildren + 1] = UI.Panel {
            position = "absolute",
            right = 6, top = "50%",
            marginTop = -18,
            width = 36, height = 36,
            borderRadius = 18,
            backgroundColor = { 60, 45, 35, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function(self)
                local nextIdx = currentHeroIdx + 1
                if nextIdx > #allHeroList then nextIdx = 1 end
                detailHeroId = allHeroList[nextIdx].id
                HeroDetail.ShowHeroDetail(ctx, allHeroList[nextIdx].id)
            end,
            children = {
                UI.Label { text = ">", fontSize = 20, fontColor = { 200, 180, 160, 220 }, fontWeight = "bold" },
            },
        }
    end

    local topSection = UI.Panel {
        width = "100%",
        flex = 4,
        alignItems = "center",
        justifyContent = "center",
        gap = 4,
        children = topChildren,
    }

    -- ========== 标签栏 ==========
    local visibleTabs = isLeader and LEADER_TABS or DETAIL_TABS
    local tabItems = {}
    for _, tabDef in ipairs(visibleTabs) do
        local isActive = (tabDef.key == detailTab)
        tabItems[#tabItems + 1] = UI.Panel {
            flex = 1,
            paddingTop = 8, paddingBottom = 8,
            alignItems = "center", justifyContent = "center",
            backgroundColor = isActive and { 80, 60, 45, 255 } or { 0, 0, 0, 0 },
            borderBottomWidth = isActive and 2 or 0,
            borderBottomColor = S.gold,
            onClick = function(self)
                detailTab = tabDef.key
                HeroDetail.ShowHeroDetail(ctx, heroId)
            end,
            children = {
                UI.Label {
                    text = tabDef.label,
                    fontSize = 13,
                    fontColor = isActive and S.gold or S.dim,
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end

    local tabBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexShrink = 0,
        backgroundColor = { 50, 36, 26, 240 },
        borderBottomWidth = 1,
        borderBottomColor = { 75, 55, 38, 100 },
    }
    for _, item in ipairs(tabItems) do
        tabBar:AddChild(item)
    end

    -- ========== 内容区域 ==========
    detailContentContainer = UI.Panel {
        width = "100%",
        paddingLeft = 10, paddingRight = 10,
        paddingTop = 6, paddingBottom = 10,
        pointerEvents = "auto",
    }

    local contentScroll = UI.ScrollView {
        flexGrow = 1, flexBasis = 0,
        scrollY = true,
        width = "100%",
        pointerEvents = "auto",
        children = { detailContentContainer },
    }

    local bottomSection = UI.Panel {
        width = "100%",
        flex = 6,
        flexDirection = "column",
        children = {
            tabBar,
            contentScroll,
        },
    }

    -- ========== 底部按钮栏 ==========
    local leftSlot = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                paddingLeft = 10, paddingRight = 14,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 16,
                backgroundColor = { 80, 60, 45, 220 },
                onClick = function(self)
                    HeroDetail.HideHeroDetail(ctx)
                end,
                children = {
                    UI.Label { text = "<", fontSize = 14, fontColor = { 200, 180, 160, 220 }, fontWeight = "bold" },
                    UI.Label { text = "返回", fontSize = 13, fontColor = { 200, 180, 160, 220 } },
                },
            },
        },
    }

    -- 中 slot：合成按钮
    local centerSlot = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
    }
    if not isUnlocked and not isLeader then
        local fragments = (h and h.fragments) or 0
        local unlockCost = Config.RARITY_SHARD_COST[rarity] or 10
        local canCompose = fragments >= unlockCost
        local bgColor = canCompose and { 60, 160, 120, 240 } or { 60, 55, 65, 200 }
        local textColor = canCompose and { 255, 255, 255, 255 } or { 120, 110, 130, 180 }
        centerSlot = UI.Panel {
            flexGrow = 1, flexBasis = 0,
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "center",
                    gap = 4,
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 16,
                    backgroundColor = bgColor,
                    onClick = function(self)
                        local hNow = HeroData.Get(heroId)
                        local frags = (hNow and hNow.fragments) or 0
                        local cost = Config.RARITY_SHARD_COST[rarity] or 10
                        if frags < cost then
                            Toast.Show("碎片不足 (" .. frags .. "/" .. cost .. ")", { 200, 160, 100 })
                            return
                        end
                        hNow.fragments = hNow.fragments - cost
                        HeroData.UnlockHero(heroId)
                        HeroData.Save()
                        Toast.Show(heroDef.name .. " 合成成功!", { 100, 255, 180 })
                        HeroDetail.ShowHeroDetail(ctx, heroId, heroDef)
                    end,
                    children = {
                        UI.Label { text = "合成", fontSize = 13, fontColor = textColor, fontWeight = "bold" },
                    },
                },
            },
        }
    end

    -- 右 slot：重生按钮
    local rightSlot = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        justifyContent = "flex-end",
        alignItems = "center",
    }
    if isUnlocked and not isLeader then
        local refund = HeroData.CalcRebirthRefund(heroId)
        if refund then
            rightSlot = UI.Panel {
                flexGrow = 1, flexBasis = 0,
                flexDirection = "row",
                justifyContent = "flex-end",
                alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 6, paddingBottom = 6,
                        borderRadius = 16,
                        backgroundColor = { 120, 50, 50, 220 },
                        onClick = function(self)
                            RelicTab.ShowRebirthConfirm(ctx, heroId)
                        end,
                        children = {
                            UI.Panel {
                                width = 16, height = 16,
                                backgroundImage = "image/icon_rebirth.png",
                                backgroundFit = "contain",
                            },
                            UI.Label { text = "重生", fontSize = 13, fontColor = { 255, 220, 180 }, fontWeight = "bold" },
                        },
                    },
                },
            }
        end
    end

    local bottomBar = UI.Panel {
        width = "100%",
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 6,
        children = { leftSlot, centerSlot, rightSlot },
    }

    -- ========== 组装面板 ==========
    local detailPanel = UI.Panel {
        position = "absolute",
        top = 5, left = 5, right = 5, bottom = 5,
        backgroundColor = S.popupBg,
        borderRadius = 12,
        borderWidth = 2,
        borderColor = rarityBorder,
        flexDirection = "column",
        overflow = "hidden",
        children = { topSection, bottomSection, bottomBar },
    }

    -- 填充内容
    RefreshDetailContent(ctx, heroId, heroDef)

    -- 轻量刷新回调
    ctx._refreshTab = function()
        RefreshDetailContent(ctx, heroId, heroDef)
        if headerPowerLabel then
            local freshStats = StatEngine.GetRuntimeStats(heroId)
            headerPowerLabel:SetText("战力:" .. FormatBigNum(freshStats.power))
        end
    end

    -- 每秒增量刷新属性值
    local function incrementalStatRefresh()
        if not detailContentContainer then return end
        if detailTab ~= "info" then return end

        local rtStats = StatEngine.GetRuntimeStats(heroId)

        local panel = detailContentContainer:FindById("detail_stat_panel")
        if not panel then return end

        local atkLabel = panel:FindById("detail_atk")
        if atkLabel then atkLabel:SetText(StatEngine.FormatStatValue(rtStats.atk)) end

        local spdLabel = panel:FindById("detail_spd")
        if spdLabel then spdLabel:SetText(StatEngine.FormatStatValue(rtStats.atkSpeedDisplay)) end

        local critLabel = panel:FindById("detail_critRate")
        if critLabel then critLabel:SetText(StatEngine.FormatStatValue(rtStats.critRate, "pct")) end

        local critDmgLabel = panel:FindById("detail_critDmg")
        if critDmgLabel then critDmgLabel:SetText(StatEngine.FormatStatValue(rtStats.critDmg, "pct")) end

        local apLabel = panel:FindById("detail_pen")
        if apLabel then apLabel:SetText(StatEngine.FormatStatValue(rtStats.penValue or 0, "pct")) end

        local dmgLabel = panel:FindById("detail_dmgBonus")
        if dmgLabel then dmgLabel:SetText(StatEngine.FormatStatValue(rtStats.dmgBonus or 0, "pct")) end

        local elemLabel = panel:FindById("detail_elemDmg")
        if elemLabel then
            local dmgTypeId = Config.HERO_DAMAGE_TYPE[heroId]
            local elemBonus = rtStats.elemDmgBonus and rtStats.elemDmgBonus[dmgTypeId] or 0
            elemLabel:SetText(StatEngine.FormatStatValue(elemBonus, "pct"))
        end

        if headerPowerLabel then
            headerPowerLabel:SetText("战力:" .. FormatBigNum(rtStats.power))
        end
    end

    HeroDetail.StartAutoRefresh(incrementalStatRefresh)

    -- 半透明遮罩
    local oldOverlay = ctx.GetHeroDetailOverlay()
    if oldOverlay then
        pageRoot:RemoveChild(oldOverlay)
    end
    local overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 200,
        backgroundColor = { 0, 0, 0, 180 },
        children = { detailPanel },
    }
    ctx.SetHeroDetailOverlay(overlay)
    pageRoot:AddChild(overlay)
end

-- ============================================================================
-- HideHeroDetail
-- ============================================================================

function HeroDetail.HideHeroDetail(ctx)
    HeroDetail.StopAutoRefresh()
    local overlay = ctx.GetHeroDetailOverlay()
    if overlay then
        local pageRoot = ctx.GetPageRoot()
        pageRoot:RemoveChild(overlay)
        ctx.SetHeroDetailOverlay(nil)
        detailContentContainer = nil
        detailHeroId = nil
        headerPowerLabel = nil
        ctx.Refresh()
    end
end

return HeroDetail
