-- Game/ExchangeShopUI.lua
-- 兑换商店 UI：标签页切换 精粹商店 / 符文商店
-- 覆盖层模式，与 ActivityUI / RecruitUI 一致

local ExchangeShopData = require("Game.ExchangeShopData")
local RuneShopData     = require("Game.RuneShopData")
local RuneData         = require("Game.RuneData")
local RuneConfig       = require("Game.Config_Runes")
local Currency         = require("Game.Currency")
local Config           = require("Game.Config")
local RewardIcon       = require("Game.RewardIcon")
local RewardDisplay    = require("Game.RewardDisplay")
local Toast            = require("Game.Toast")
local Tooltip          = require("Game.Tooltip")

local ExchangeShopUI = {}

---@type any
local UI
---@type any
local pageRoot
---@type any
local confirmLayer  -- 确认弹窗层
local _onBack
local activeTab = "essence"  -- "essence" / "rune"

-- 样式常量
local S = {
    bgDark     = { 18, 14, 28, 250 },
    bgCard     = { 40, 32, 60, 220 },
    bgCardHov  = { 55, 45, 80, 220 },
    border     = { 100, 80, 160, 120 },
    borderGold = { 220, 180, 60, 200 },
    purple     = { 180, 140, 255 },
    gold       = { 255, 220, 80 },
    white      = { 240, 240, 255 },
    gray       = { 140, 130, 160 },
    red        = { 255, 80, 80 },
    green      = { 100, 255, 120 },
    essenceColor = { 180, 140, 255 },
    dustColor    = { 160, 120, 200 },
    sealColor    = { 40, 200, 160 },
    crystalColor = { 200, 60, 255 },
}

-- ============================================================================
-- 公共接口
-- ============================================================================

function ExchangeShopUI.SetOnBack(fn)
    _onBack = fn
end

---@param uiModule any
---@return any
function ExchangeShopUI.CreatePage(uiModule)
    UI = uiModule
    pageRoot = UI.Panel {
        id = "exchangeShopPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = S.bgDark,
        children = {},
    }
    ExchangeShopUI.Refresh()
    return pageRoot
end

function ExchangeShopUI.Refresh()
    if not pageRoot then return end
    pageRoot:ClearChildren()

    -- 顶栏（标题 + 货币余额）
    pageRoot:AddChild(createHeader())
    -- 标签栏
    pageRoot:AddChild(createTabBar())

    -- 内容区
    if activeTab == "essence" then
        pageRoot:AddChild(createEssenceShopGrid())
        pageRoot:AddChild(createEssenceBottomBar())
    else
        pageRoot:AddChild(createRuneShopContent())
        pageRoot:AddChild(createRuneBottomBar())
    end

    -- 初始化 Tooltip 浮窗层
    Tooltip.Init(UI, pageRoot)

    -- 确认弹窗层（始终在最上层）
    confirmLayer = UI.Panel {
        id = "exchangeConfirmLayer",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        zIndex = 100,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
    }
    pageRoot:AddChild(confirmLayer)
end

-- ============================================================================
-- 标题栏
-- ============================================================================

function createHeader()
    local children = {
        UI.Label {
            text = activeTab == "essence" and "兑换商店" or "符文商店",
            fontSize = 18,
            fontColor = S.gold,
            fontWeight = "bold",
            flexGrow = 1,
        },
    }

    if activeTab == "essence" then
        -- 暗影精粹余额
        local essenceAmount = Currency.Get("shadow_essence")
        local essenceDef = Config.CURRENCY.shadow_essence
        children[#children + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            paddingLeft = 10, paddingRight = 10, paddingTop = 4, paddingBottom = 4,
            backgroundColor = { 50, 40, 70, 200 }, borderRadius = 14,
            borderWidth = 1, borderColor = { 140, 100, 200, 120 },
            children = {
                essenceDef and essenceDef.image and UI.Panel {
                    width = 20, height = 20,
                    backgroundImage = essenceDef.image, backgroundFit = "contain",
                } or nil,
                UI.Label { text = tostring(essenceAmount), fontSize = 14, fontColor = S.essenceColor, fontWeight = "bold" },
            },
        }
    end
    -- 符文货币移到底部栏显示

    return UI.Panel {
        width = "100%", height = 48, flexShrink = 0,
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 28, 22, 42, 250 },
        borderColor = { 80, 60, 120, 120 }, borderWidth = { bottom = 1 },
        children = children,
    }
end

-- ============================================================================
-- 标签栏
-- ============================================================================

function createTabBar()
    local tabs = {
        { id = "essence", label = "精粹商店" },
        { id = "rune",    label = "符文商店" },
    }
    local tabChildren = {}
    for _, t in ipairs(tabs) do
        local isActive = (activeTab == t.id)
        tabChildren[#tabChildren + 1] = UI.Panel {
            flex = 1, height = 36,
            justifyContent = "center", alignItems = "center",
            backgroundColor = isActive and { 60, 45, 100, 255 } or { 30, 24, 48, 200 },
            borderWidth = { bottom = isActive and 2 or 0 },
            borderColor = isActive and S.gold or { 0, 0, 0, 0 },
            pointerEvents = "auto",
            onClick = function()
                if activeTab ~= t.id then
                    activeTab = t.id
                    ExchangeShopUI.Refresh()
                end
            end,
            children = {
                UI.Label {
                    text = t.label,
                    fontSize = 14,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and S.gold or S.gray,
                },
            },
        }
    end
    return UI.Panel {
        width = "100%", height = 36, flexShrink = 0,
        flexDirection = "row",
        backgroundColor = { 28, 22, 42, 250 },
        children = tabChildren,
    }
end

-- ============================================================================
-- 精粹商店（原有逻辑）
-- ============================================================================

function createEssenceShopGrid()
    local items = ExchangeShopData.SHOP_ITEMS
    local cards = {}
    for _, item in ipairs(items) do
        cards[#cards + 1] = createEssenceItemCard(item)
    end
    return UI.ScrollView {
        width = "100%", flexGrow = 1, flexShrink = 1,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap",
                justifyContent = "center",
                paddingTop = 10, paddingBottom = 20, paddingLeft = 8, paddingRight = 8,
                gap = 10,
                children = cards,
            },
        },
    }
end

function createEssenceItemCard(item)
    local remaining = ExchangeShopData.GetRemaining(item.id)
    local soldOut = remaining == 0
    local canAfford = Currency.Has("shadow_essence", item.cost)
    local borderC = soldOut and { 60, 50, 80, 100 } or S.border

    local cardChildren = {}

    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%", height = 70,
        justifyContent = "center", alignItems = "center",
        marginTop = 6, opacity = soldOut and 0.4 or 1.0,
        children = { RewardIcon.Create(UI, 52, item.icon, item.amount, { muted = soldOut }) },
    }

    local essenceDef = Config.CURRENCY.shadow_essence
    cardChildren[#cardChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", justifyContent = "center",
        gap = 3, width = "100%", marginTop = 3,
        children = {
            essenceDef and essenceDef.image and UI.Panel {
                width = 14, height = 14, backgroundImage = essenceDef.image, backgroundFit = "contain",
            } or nil,
            UI.Label {
                text = tostring(item.cost), fontSize = 13,
                fontColor = (not soldOut and canAfford) and S.essenceColor or S.red, fontWeight = "bold",
            },
        },
    }

    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%", alignItems = "center", marginTop = 4, marginBottom = 6,
        children = {
            UI.Button {
                text = soldOut and "售罄" or "兑换", fontSize = 12,
                width = 72, height = 28, borderRadius = 14,
                variant = soldOut and "outline" or "primary", disabled = soldOut,
                onClick = function() showEssenceConfirmDialog(item) end,
            },
        },
    }

    if item.discount and not soldOut then
        cardChildren[#cardChildren + 1] = UI.Panel {
            position = "absolute", top = -4, left = -4,
            backgroundColor = { 255, 60, 60, 230 }, borderRadius = 4,
            paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2,
            children = {
                UI.Label { text = item.discount, fontSize = 10, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
            },
        }
    end

    return UI.Panel {
        width = 110, flexDirection = "column", alignItems = "center",
        backgroundColor = soldOut and { 30, 25, 40, 180 } or S.bgCard,
        borderRadius = 8, borderWidth = 1, borderColor = borderC,
        overflow = "visible", position = "relative",
        children = cardChildren,
    }
end

function createEssenceBottomBar()
    local MAX_AD_REFRESH = 10
    local refreshUsed = ExchangeShopData.GetTodayRefreshCount()
    local refreshLeft = MAX_AD_REFRESH - refreshUsed
    return UI.Panel {
        width = "100%", height = 50, flexShrink = 0,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 28, 22, 42, 250 },
        borderColor = { 80, 60, 120, 120 }, borderWidth = { top = 1 },
        children = {
            UI.Button {
                text = "返回", fontSize = 15, width = 80, height = 36,
                borderRadius = 8, variant = "outline",
                onClick = function() if _onBack then _onBack() end end,
            },
            UI.Panel { flexGrow = 1 },
            UI.Button {
                fontSize = 14, paddingLeft = 14, paddingRight = 14, height = 36,
                borderRadius = 8,
                variant = refreshLeft > 0 and "primary" or "outline",
                disabled = refreshLeft <= 0,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel { width = 16, height = 16, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain" },
                            UI.Label {
                                text = refreshLeft > 0
                                    and ("刷新(" .. refreshLeft .. "/" .. MAX_AD_REFRESH .. ")")
                                    or ("刷新(0/" .. MAX_AD_REFRESH .. ")"),
                                fontSize = 14, fontColor = { 255, 255, 255 },
                            },
                        },
                    },
                },
                onClick = function()
                    if refreshLeft <= 0 then Toast.Show("今日刷新次数已用完"); return end
                    local AdHelper = require("Game.AdHelper")
                    AdHelper.ShowRewardAd(function()
                        ExchangeShopData.RecordRefresh()
                        ExchangeShopData.ResetPurchases()
                        ExchangeShopUI.Refresh()
                        Toast.Show("商店已刷新！")
                    end)
                end,
            },
        },
    }
end

-- ============================================================================
-- 精粹商店确认弹窗
-- ============================================================================

function showEssenceConfirmDialog(item)
    if not confirmLayer or not UI then return end
    confirmLayer:ClearChildren()

    local canAfford = Currency.Has("shadow_essence", item.cost)
    local essenceDef = Config.CURRENCY.shadow_essence

    confirmLayer:AddChild(UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 }, pointerEvents = "auto",
        onClick = function() confirmLayer:SetVisible(false) end,
    })

    confirmLayer:AddChild(UI.Panel {
        width = 220, flexDirection = "column", alignItems = "center",
        backgroundColor = { 35, 28, 55, 245 }, borderRadius = 12,
        borderWidth = 2, borderColor = { 120, 90, 180, 200 },
        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
        pointerEvents = "auto",
        children = {
            UI.Label { text = "购买", fontSize = 18, fontColor = S.gold, fontWeight = "bold", textAlign = "center", width = "100%" },
            UI.Panel { width = "80%", height = 1, backgroundColor = { 100, 80, 160, 100 }, marginTop = 8, marginBottom = 10 },
            UI.Label { text = "购买" .. item.name, fontSize = 13, fontColor = S.essenceColor, textAlign = "center", width = "100%", marginBottom = 10 },
            UI.Panel {
                width = 80, height = 80, justifyContent = "center", alignItems = "center",
                backgroundColor = { 50, 40, 75, 200 }, borderRadius = 8,
                borderWidth = 1, borderColor = { 100, 80, 160, 150 }, marginBottom = 14,
                children = { RewardIcon.Create(UI, 60, item.icon, item.amount, {}) },
            },
            UI.Panel {
                flexDirection = "column", alignItems = "center", gap = 6, width = "100%", marginBottom = 10,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 4,
                        paddingLeft = 14, paddingRight = 14, paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 50, 45, 30, 200 }, borderRadius = 8,
                        borderWidth = 1, borderColor = canAfford and { 180, 160, 60, 150 } or { 180, 60, 60, 150 },
                        children = {
                            essenceDef and essenceDef.image and UI.Panel {
                                width = 18, height = 18, backgroundImage = essenceDef.image, backgroundFit = "contain",
                            } or nil,
                            UI.Label { text = tostring(item.cost), fontSize = 16, fontColor = canAfford and S.gold or S.red, fontWeight = "bold" },
                        },
                    },
                    UI.Button {
                        text = "购买", fontSize = 14, width = 100, height = 36, borderRadius = 18,
                        variant = canAfford and "primary" or "outline", disabled = not canAfford,
                        onClick = function()
                            local ok, msg, rewards = ExchangeShopData.Purchase(item.id)
                            confirmLayer:SetVisible(false)
                            if ok then
                                if rewards and #rewards > 0 then
                                    RewardDisplay.Show(UI, pageRoot, {
                                        title = "兑换成功", rewards = rewards,
                                        onClose = function() ExchangeShopUI.Refresh() end,
                                    })
                                else
                                    Toast.Show(msg, S.green)
                                    ExchangeShopUI.Refresh()
                                end
                            else
                                Toast.Show(msg, S.red)
                            end
                        end,
                    },
                },
            },
            UI.Panel {
                width = 40, height = 40, borderRadius = 20,
                backgroundColor = { 180, 40, 40, 220 }, borderWidth = 2, borderColor = { 220, 80, 80, 200 },
                justifyContent = "center", alignItems = "center", marginTop = 4,
                pointerEvents = "auto",
                onClick = function() confirmLayer:SetVisible(false) end,
                children = { UI.Label { text = "✕", fontSize = 18, fontColor = { 255, 255, 255 }, fontWeight = "bold", textAlign = "center" } },
            },
        },
    })

    confirmLayer:SetVisible(true)
end

-- ============================================================================
-- 符文商店内容
-- ============================================================================

function createRuneShopContent()
    -- 按品质排序（高→低），品质相同保持原序
    local items = RuneShopData.GetItems()
    local sorted = {}
    for i, item in ipairs(items) do
        sorted[#sorted + 1] = { item = item, origIndex = i }
    end
    table.sort(sorted, function(a, b)
        local qa = RuneConfig.QUALITY_MAP[a.item.rune.qualityId]
        local qb = RuneConfig.QUALITY_MAP[b.item.rune.qualityId]
        local ia = qa and qa.index or 0
        local ib = qb and qb.index or 0
        if ia ~= ib then return ia > ib end
        return a.origIndex < b.origIndex
    end)
    local cards = {}
    for _, entry in ipairs(sorted) do
        cards[#cards + 1] = createRuneCard(entry.item, entry.origIndex)
    end
    return UI.ScrollView {
        width = "100%", flexGrow = 1, flexShrink = 1,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap",
                justifyContent = "center",
                paddingTop = 10, paddingBottom = 20, paddingLeft = 8, paddingRight = 8,
                gap = 10,
                children = cards,
            },
        },
    }
end

function createRuneCard(item, index)
    local rune = item.rune
    local bought = item.bought
    local quality = RuneConfig.QUALITY_MAP[rune.qualityId]
    local series = RuneConfig.SERIES_MAP[rune.seriesId]
    local price = RuneShopData.GetPrice(rune.qualityId)
    local canAfford = not bought and RuneShopData.CanAfford(rune.qualityId)
    local qColor = quality and quality.color or { 180, 180, 180 }
    local borderC = bought and { 60, 50, 80, 100 } or { qColor[1], qColor[2], qColor[3], 150 }

    -- 词条预览（显示全部，最多4条）
    local affixTexts = {}
    for j = 1, #rune.affixes do
        local a = rune.affixes[j]
        local valStr
        if a.unit == "%" then
            valStr = a.name .. "+" .. string.format("%.1f%%", a.value * 100)
        else
            valStr = a.name .. "+" .. string.format("%.0f", a.value)
        end
        affixTexts[#affixTexts + 1] = UI.Label {
            text = valStr, fontSize = 9,
            fontColor = bought and { 100, 90, 120 } or { 180, 170, 200 },
            textAlign = "center", width = "100%",
        }
    end

    -- 价格行
    local priceChildren = {}
    local dustDef = Config.CURRENCY.rift_dust
    local dustEnough = Currency.Has("rift_dust", price.dust)
    priceChildren[#priceChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 2,
        children = {
            dustDef and dustDef.image and UI.Panel {
                width = 12, height = 12, backgroundImage = dustDef.image, backgroundFit = "contain",
            } or nil,
            UI.Label {
                text = tostring(price.dust), fontSize = 11,
                fontColor = (not bought and dustEnough) and S.dustColor or S.red, fontWeight = "bold",
            },
        },
    }
    if price.seal > 0 then
        local sealDef = Config.CURRENCY.rune_seal
        local sealEnough = Currency.Has("rune_seal", price.seal)
        priceChildren[#priceChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 1,
            children = {
                sealDef and sealDef.image and UI.Panel {
                    width = 12, height = 12, backgroundImage = sealDef.image, backgroundFit = "contain",
                } or nil,
                UI.Label {
                    text = tostring(price.seal), fontSize = 11,
                    fontColor = (not bought and sealEnough) and S.sealColor or S.red, fontWeight = "bold",
                },
            },
        }
    end
    if price.crystal > 0 then
        local crystalDef = Config.CURRENCY.abyss_crystal
        local crystalEnough = Currency.Has("abyss_crystal", price.crystal)
        priceChildren[#priceChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 1,
            children = {
                crystalDef and crystalDef.image and UI.Panel {
                    width = 12, height = 12, backgroundImage = crystalDef.image, backgroundFit = "contain",
                } or nil,
                UI.Label {
                    text = tostring(price.crystal), fontSize = 11,
                    fontColor = (not bought and crystalEnough) and S.crystalColor or S.red, fontWeight = "bold",
                },
            },
        }
    end

    return UI.Panel {
        width = 110, height = 200, flexDirection = "column",
        backgroundColor = bought and { 30, 25, 40, 180 } or S.bgCard,
        borderRadius = 8, borderWidth = 1, borderColor = borderC,
        overflow = "visible", position = "relative",
        children = {
            -- 上半部分：图标 + 名称 + 词条（自然高度）
            UI.Panel {
                width = "100%", height = 56,
                justifyContent = "center", alignItems = "center",
                marginTop = 6, opacity = bought and 0.35 or 1.0,
                children = {
                    series and series.icon and UI.Panel {
                        width = 40, height = 40,
                        backgroundImage = series.icon, backgroundFit = "contain",
                    } or UI.Label {
                        text = series and series.emoji or "?",
                        fontSize = 28, textAlign = "center",
                    },
                },
            },
            UI.Panel {
                width = "100%", alignItems = "center",
                opacity = bought and 0.35 or 1.0,
                children = {
                    UI.Label {
                        text = (quality and quality.name or "?") .. "·" .. (series and series.name or "?"),
                        fontSize = 11, fontWeight = "bold",
                        fontColor = { qColor[1], qColor[2], qColor[3], 255 },
                    },
                },
            },
            UI.Panel {
                width = "100%", height = 64, alignItems = "center",
                paddingLeft = 4, paddingRight = 4, marginTop = 2,
                opacity = bought and 0.35 or 1.0, flexShrink = 0,
                children = affixTexts,
            },
            -- 弹性填充，将价格和按钮推到底部
            UI.Panel { flexGrow = 1 },
            -- 价格行（底部对齐）
            UI.Panel {
                flexDirection = "row", alignItems = "center", justifyContent = "center",
                gap = 4, width = "100%",
                children = priceChildren,
            },
            -- 兑换按钮（底部）
            UI.Panel {
                width = "100%", alignItems = "center", marginTop = 4, marginBottom = 6,
                children = {
                    UI.Button {
                        text = bought and "已购买" or "兑换", fontSize = 12,
                        width = 72, height = 28, borderRadius = 14,
                        variant = bought and "outline" or "primary",
                        disabled = bought,
                        onClick = function()
                            if not bought then showRuneConfirmDialog(item, index) end
                        end,
                    },
                },
            },
        },
    }
end

function createRuneBottomBar()
    -- 右侧货币余额
    local currencyWidgets = {}
    local currencies = {
        { id = "rift_dust",     name = "尘", color = S.dustColor,    desc = "通关深渊副本掉落，用于符文商店兑换和洗练" },
        { id = "rune_seal",     name = "封", color = S.sealColor,    desc = "深渊副本高层掉落，用于兑换高品质符文和锁定洗练" },
        { id = "abyss_crystal", name = "晶", color = S.crystalColor, desc = "深渊副本稀有掉落，用于兑换传说/神话符文和定向洗练" },
    }
    for _, c in ipairs(currencies) do
        local amt = Currency.Get(c.id)
        local cDef = Config.CURRENCY[c.id]
        local fullName = cDef and cDef.name or c.name
        local tipDesc = c.desc
        currencyWidgets[#currencyWidgets + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2,
            paddingLeft = 5, paddingRight = 5, paddingTop = 3, paddingBottom = 3,
            backgroundColor = { 50, 40, 70, 200 }, borderRadius = 10,
            borderWidth = 1, borderColor = { c.color[1], c.color[2], c.color[3], 100 },
            pointerEvents = "auto",
            onClick = function(self)
                Tooltip.Show({
                    title = fullName .. "  ×" .. amt,
                    desc = tipDesc,
                    anchor = self,
                    titleColor = { c.color[1], c.color[2], c.color[3], 255 },
                })
            end,
            children = {
                cDef and cDef.image and UI.Panel {
                    width = 14, height = 14, backgroundImage = cDef.image, backgroundFit = "contain",
                } or UI.Label { text = c.name, fontSize = 10, fontColor = c.color },
                UI.Label { text = tostring(amt), fontSize = 12, fontColor = c.color, fontWeight = "bold" },
            },
        }
    end

    return UI.Panel {
        width = "100%", height = 50, flexShrink = 0,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 28, 22, 42, 250 },
        borderColor = { 80, 60, 120, 120 }, borderWidth = { top = 1 },
        children = {
            UI.Button {
                text = "返回", fontSize = 15, width = 80, height = 36,
                borderRadius = 8, variant = "outline",
                onClick = function() if _onBack then _onBack() end end,
            },
            UI.Panel { flexGrow = 1 },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = currencyWidgets,
            },
        },
    }
end

-- ============================================================================
-- 符文商店确认弹窗
-- ============================================================================

function showRuneConfirmDialog(item, index)
    if not confirmLayer or not UI then return end
    confirmLayer:ClearChildren()

    local rune = item.rune
    local quality = RuneData.GetQuality(rune.qualityId)
    local series = RuneData.GetSeries(rune.seriesId)
    local price = RuneShopData.GetPrice(rune.qualityId)
    local canAfford = RuneShopData.CanAfford(rune.qualityId)
    local qColor = quality.color
    local curCount, cap = RuneData.GetBagCapacity()
    local bagFull = curCount >= cap

    -- === 词条列表（复用 RuneUI 的 FormatAffix 风格）===
    local affixChildren = {}
    for _, affix in ipairs(rune.affixes) do
        affixChildren[#affixChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 2, paddingBottom = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label {
                            text = RuneData.FormatAffix(affix),
                            fontSize = 13, fontColor = { 220, 210, 240, 255 },
                        },
                        UI.Label {
                            text = RuneData.FormatAffixRange(affix, rune.qualityId),
                            fontSize = 10, fontColor = { 140, 130, 160, 180 },
                        },
                    },
                },
            },
        }
    end

    -- === 套装效果（复用 RuneUI 风格）===
    local setChildren = {}
    if series then
        setChildren[#setChildren + 1] = UI.Panel {
            width = "100%", paddingTop = 4,
            borderTopWidth = 1, borderColor = { 60, 50, 90, 100 },
            gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        series.icon and UI.Panel {
                            width = 16, height = 16,
                            backgroundImage = series.icon, backgroundFit = "contain",
                            pointerEvents = "none",
                        } or UI.Label { text = series.emoji or "", fontSize = 11, fontColor = series.tagColor },
                        UI.Label {
                            text = series.name .. "套装效果",
                            fontSize = 11, fontColor = series.tagColor,
                        },
                    },
                },
                series.set2 and UI.Label {
                    text = "2件: " .. series.set2.desc,
                    fontSize = 10, fontColor = { 180, 170, 200, 200 },
                } or nil,
                series.set3 and UI.Label {
                    text = "3件: " .. series.set3.desc,
                    fontSize = 10, fontColor = { 180, 170, 200, 200 },
                } or nil,
            },
        }
    end

    -- === 消耗明细 ===
    local costChildren = {}
    local function addCostRow(currId, amount)
        if amount <= 0 then return end
        local cDef = Config.CURRENCY[currId]
        local owned = Currency.Get(currId)
        local enough = owned >= amount
        costChildren[#costChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            paddingTop = 1, paddingBottom = 1,
            children = {
                cDef and cDef.image and UI.Panel {
                    width = 14, height = 14, backgroundImage = cDef.image, backgroundFit = "contain",
                } or nil,
                UI.Label {
                    text = (cDef and cDef.name or currId) .. " " .. amount,
                    fontSize = 12, fontColor = enough and { 200, 190, 220 } or S.red, fontWeight = "bold",
                },
                UI.Label { text = "(" .. owned .. ")", fontSize = 10, fontColor = S.gray },
            },
        }
    end
    addCostRow("rift_dust", price.dust)
    addCostRow("rune_seal", price.seal)
    addCostRow("abyss_crystal", price.crystal)

    -- === 遮罩 ===
    confirmLayer:AddChild(UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 }, pointerEvents = "auto",
        onClick = function() confirmLayer:SetVisible(false) end,
    })

    -- === 弹窗主体（RuneUI 同风格）===
    confirmLayer:AddChild(UI.Panel {
        width = "90%",
        flexDirection = "column",
        backgroundColor = { 30, 24, 50, 240 },
        borderRadius = 12,
        borderWidth = 1,
        borderColor = { qColor[1], qColor[2], qColor[3], 150 },
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 10,
        gap = 4,
        pointerEvents = "auto",
        onClick = function() end,  -- 阻止穿透关闭
        children = {
            -- 标题行（图标 + 名称 + 品质标签 + 关闭按钮）
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            series and series.icon and UI.Panel {
                                width = 28, height = 28,
                                backgroundImage = series.icon, backgroundFit = "contain",
                                pointerEvents = "none",
                            } or UI.Label { text = series and series.emoji or "", fontSize = 20 },
                            UI.Label {
                                text = (series and series.name or "") .. "符文",
                                fontSize = 16, fontColor = qColor, fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = { qColor[1], qColor[2], qColor[3], 200 },
                                borderRadius = 4,
                                children = {
                                    UI.Label {
                                        text = quality.name,
                                        fontSize = 10, fontColor = { 20, 16, 32, 255 },
                                    },
                                },
                            },
                        },
                    },
                    UI.Button {
                        text = "✕", fontSize = 14, variant = "ghost",
                        width = 28, height = 28,
                        onClick = function() confirmLayer:SetVisible(false) end,
                    },
                },
            },
            -- 词条
            UI.Panel {
                width = "100%", flexDirection = "column", gap = 2,
                paddingTop = 4, paddingBottom = 4, flexShrink = 0,
                children = affixChildren,
            },
            -- 套装效果
            UI.Panel {
                width = "100%", flexDirection = "column", gap = 2, flexShrink = 0,
                children = setChildren,
            },
            -- 消耗分隔线
            UI.Panel {
                width = "100%", paddingTop = 4,
                borderTopWidth = 1, borderColor = { 60, 50, 90, 100 },
                gap = 2, flexShrink = 0,
                children = {
                    UI.Label { text = "兑换消耗", fontSize = 11, fontColor = S.gray, marginBottom = 2 },
                    UI.Panel {
                        width = "100%", flexDirection = "column", gap = 1,
                        children = costChildren,
                    },
                    bagFull and UI.Label {
                        text = "背包已满(" .. cap .. ")",
                        fontSize = 11, fontColor = S.red, marginTop = 4,
                    } or nil,
                },
            },
            -- 操作按钮
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 8,
                paddingTop = 8, flexShrink = 0,
                children = {
                    UI.Button {
                        text = "取消", fontSize = 12, variant = "outline",
                        flex = 1, height = 36,
                        onClick = function() confirmLayer:SetVisible(false) end,
                    },
                    UI.Button {
                        text = "兑换", fontSize = 12,
                        variant = (canAfford and not bagFull) and "primary" or "outline",
                        disabled = not canAfford or bagFull,
                        flex = 1, height = 36,
                        onClick = function()
                            local ok, msg = RuneShopData.Purchase(index)
                            confirmLayer:SetVisible(false)
                            if ok then
                                -- 通过奖励弹窗展示获得的符文
                                local rune = item.rune
                                local quality = RuneData.GetQuality(rune.qualityId)
                                local series = RuneData.GetSeries(rune.seriesId)
                                local qName = quality and quality.name or "?"
                                local sName = series and series.name or "?"
                                local qColor = quality and quality.color or {255,255,255}
                                RewardDisplay.Show(UI, pageRoot, {
                                    title = "兑换成功",
                                    rewards = {
                                        {
                                            icon = series and series.icon or "🔮",
                                            name = qName .. sName .. "符文",
                                            amount = 1,
                                            borderColor = {qColor[1], qColor[2], qColor[3], 255},
                                        },
                                    },
                                    onClose = function() ExchangeShopUI.Refresh() end,
                                })
                            else
                                Toast.Show(msg, S.red)
                                ExchangeShopUI.Refresh()
                            end
                        end,
                    },
                },
            },
        },
    })

    confirmLayer:SetVisible(true)
end

return ExchangeShopUI
