-- Game/ExchangeShopUI.lua
-- 兑换商店 UI：用暗影精粹兑换宝箱、契约券、材料、碎片箱
-- 覆盖层模式，与 ActivityUI / RecruitUI 一致

local ExchangeShopData = require("Game.ExchangeShopData")
local Currency         = require("Game.Currency")
local Config           = require("Game.Config")
local RewardIcon       = require("Game.RewardIcon")
local RewardDisplay    = require("Game.RewardDisplay")
local Toast            = require("Game.Toast")

local ExchangeShopUI = {}

---@type any
local UI
---@type any
local pageRoot
---@type any
local confirmLayer  -- 确认弹窗层
local _onBack

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

    -- 顶栏
    pageRoot:AddChild(createHeader())
    -- 商品网格
    pageRoot:AddChild(createShopGrid())

    -- 底部栏：返回 + 刷新
    local MAX_AD_REFRESH = 10
    local refreshUsed = ExchangeShopData.GetTodayRefreshCount()
    local refreshLeft = MAX_AD_REFRESH - refreshUsed
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 28, 22, 42, 250 },
        borderColor = { 80, 60, 120, 120 },
        borderWidth = { top = 1 },
        children = {
            UI.Button {
                text = "返回",
                fontSize = 15,
                width = 80, height = 36,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    if _onBack then _onBack() end
                end,
            },
            UI.Panel { flexGrow = 1 },
            UI.Button {
                fontSize = 14,
                paddingLeft = 14, paddingRight = 14,
                height = 36,
                borderRadius = 8,
                variant = refreshLeft > 0 and "primary" or "outline",
                disabled = refreshLeft <= 0,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Panel { width = 16, height = 16, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain" },
                            UI.Label {
                                text = refreshLeft > 0
                                    and ("刷新(" .. refreshLeft .. "/" .. MAX_AD_REFRESH .. ")")
                                    or ("刷新(0/" .. MAX_AD_REFRESH .. ")"),
                                fontSize = 14,
                                fontColor = { 255, 255, 255 },
                            },
                        },
                    },
                },
                onClick = function()
                    if refreshLeft <= 0 then
                        Toast.Show("今日刷新次数已用完")
                        return
                    end
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
    })

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
-- 确认弹窗
-- ============================================================================

local function showConfirmDialog(item)
    if not confirmLayer or not UI then return end
    confirmLayer:ClearChildren()

    local canAfford = Currency.Has("shadow_essence", item.cost)
    local essenceDef = Config.CURRENCY.shadow_essence

    -- 半透明遮罩
    confirmLayer:AddChild(UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function()
            confirmLayer:SetVisible(false)
        end,
    })

    -- 弹窗卡片
    confirmLayer:AddChild(UI.Panel {
        width = 220,
        flexDirection = "column",
        alignItems = "center",
        backgroundColor = { 35, 28, 55, 245 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { 120, 90, 180, 200 },
        paddingTop = 14, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        pointerEvents = "auto",
        children = {
            -- 标题
            UI.Label {
                text = "购买",
                fontSize = 18,
                fontColor = S.gold,
                fontWeight = "bold",
                textAlign = "center",
                width = "100%",
            },
            -- 分隔线
            UI.Panel {
                width = "80%",
                height = 1,
                backgroundColor = { 100, 80, 160, 100 },
                marginTop = 8,
                marginBottom = 10,
            },
            -- 商品名称
            UI.Label {
                text = "购买" .. item.name,
                fontSize = 13,
                fontColor = S.essenceColor,
                textAlign = "center",
                width = "100%",
                marginBottom = 10,
            },
            -- 奖励图标（RewardIcon）
            UI.Panel {
                width = 80,
                height = 80,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 50, 40, 75, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 100, 80, 160, 150 },
                marginBottom = 14,
                children = {
                    RewardIcon.Create(UI, 60, item.icon, item.amount, {}),
                },
            },
            -- 价格 + 购买按钮
            UI.Panel {
                flexDirection = "column",
                alignItems = "center",
                gap = 6,
                width = "100%",
                marginBottom = 10,
                children = {
                    -- 价格行
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        gap = 4,
                        paddingLeft = 14, paddingRight = 14,
                        paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 50, 45, 30, 200 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = canAfford and { 180, 160, 60, 150 } or { 180, 60, 60, 150 },
                        children = {
                            essenceDef and essenceDef.image and UI.Panel {
                                width = 18, height = 18,
                                backgroundImage = essenceDef.image,
                                backgroundFit = "contain",
                            } or nil,
                            UI.Label {
                                text = tostring(item.cost),
                                fontSize = 16,
                                fontColor = canAfford and S.gold or S.red,
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 购买按钮
                    UI.Button {
                        text = "购买",
                        fontSize = 14,
                        width = 100, height = 36,
                        borderRadius = 18,
                        variant = canAfford and "primary" or "outline",
                        disabled = not canAfford,
                        onClick = function()
                            local ok, msg, rewards = ExchangeShopData.Purchase(item.id)
                            confirmLayer:SetVisible(false)
                            if ok then
                                if rewards and #rewards > 0 then
                                    RewardDisplay.Show(UI, pageRoot, {
                                        title = "兑换成功",
                                        rewards = rewards,
                                        onClose = function()
                                            ExchangeShopUI.Refresh()
                                        end,
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
            -- 关闭按钮
            UI.Panel {
                width = 40, height = 40,
                borderRadius = 20,
                backgroundColor = { 180, 40, 40, 220 },
                borderWidth = 2,
                borderColor = { 220, 80, 80, 200 },
                justifyContent = "center",
                alignItems = "center",
                marginTop = 4,
                pointerEvents = "auto",
                onClick = function()
                    confirmLayer:SetVisible(false)
                end,
                children = {
                    UI.Label {
                        text = "✕",
                        fontSize = 18,
                        fontColor = { 255, 255, 255 },
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                },
            },
        },
    })

    confirmLayer:SetVisible(true)
end

-- ============================================================================
-- 内部 UI 构建
-- ============================================================================

function createHeader()
    local essenceAmount = Currency.Get("shadow_essence")
    local essenceDef = Config.CURRENCY.shadow_essence

    return UI.Panel {
        width = "100%",
        height = 52,
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 28, 22, 42, 250 },
        borderColor = { 80, 60, 120, 120 },
        borderWidth = { bottom = 1 },
        children = {
            -- 标题
            UI.Label {
                text = "精粹兑换商店",
                fontSize = 18,
                fontColor = S.gold,
                fontWeight = "bold",
                flexGrow = 1,
            },
            -- 暗影精粹余额
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 50, 40, 70, 200 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 140, 100, 200, 120 },
                children = {
                    essenceDef and essenceDef.image and UI.Panel {
                        width = 20, height = 20,
                        backgroundImage = essenceDef.image,
                        backgroundFit = "contain",
                    } or nil,
                    UI.Label {
                        id = "shopEssenceLabel",
                        text = tostring(essenceAmount),
                        fontSize = 14,
                        fontColor = S.essenceColor,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }
end

function createShopGrid()
    local items = ExchangeShopData.SHOP_ITEMS
    local cards = {}

    for _, item in ipairs(items) do
        cards[#cards + 1] = createItemCard(item)
    end

    return UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "center",
                paddingTop = 10, paddingBottom = 20,
                paddingLeft = 8, paddingRight = 8,
                gap = 10,
                children = cards,
            },
        },
    }
end

function createItemCard(item)
    local remaining = ExchangeShopData.GetRemaining(item.id)
    local soldOut = remaining == 0
    local canAfford = Currency.Has("shadow_essence", item.cost)

    local borderC = soldOut and { 60, 50, 80, 100 } or S.border

    local cardChildren = {}

    -- 图标区域（RewardIcon：图片 + 数量角标）
    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%",
        height = 70,
        justifyContent = "center",
        alignItems = "center",
        marginTop = 6,
        opacity = soldOut and 0.4 or 1.0,
        children = {
            RewardIcon.Create(UI, 52, item.icon, item.amount, {
                muted = soldOut,
            }),
        },
    }

    -- 价格行
    local essenceDef = Config.CURRENCY.shadow_essence
    cardChildren[#cardChildren + 1] = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 3,
        width = "100%",
        marginTop = 3,
        children = {
            essenceDef and essenceDef.image and UI.Panel {
                width = 14, height = 14,
                backgroundImage = essenceDef.image,
                backgroundFit = "contain",
            } or nil,
            UI.Label {
                text = tostring(item.cost),
                fontSize = 13,
                fontColor = (not soldOut and canAfford) and S.essenceColor or S.red,
                fontWeight = "bold",
            },
        },
    }

    -- 兑换按钮
    local btnText = soldOut and "售罄" or "兑换"
    local btnDisabled = soldOut

    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%",
        alignItems = "center",
        marginTop = 4, marginBottom = 6,
        children = {
            UI.Button {
                text = btnText,
                fontSize = 12,
                width = 72, height = 28,
                borderRadius = 14,
                variant = btnDisabled and "outline" or "primary",
                disabled = btnDisabled,
                onClick = function()
                    -- 弹出确认弹窗，不直接购买
                    showConfirmDialog(item)
                end,
            },
        },
    }

    -- 折扣角标
    if item.discount and not soldOut then
        cardChildren[#cardChildren + 1] = UI.Panel {
            position = "absolute",
            top = -4, left = -4,
            backgroundColor = { 255, 60, 60, 230 },
            borderRadius = 4,
            paddingLeft = 5, paddingRight = 5,
            paddingTop = 2, paddingBottom = 2,
            children = {
                UI.Label {
                    text = item.discount,
                    fontSize = 10,
                    fontColor = { 255, 255, 255 },
                    fontWeight = "bold",
                },
            },
        }
    end

    return UI.Panel {
        width = 110,
        flexDirection = "column",
        alignItems = "center",
        backgroundColor = soldOut and { 30, 25, 40, 180 } or S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = borderC,
        overflow = "visible",
        position = "relative",
        children = cardChildren,
    }
end

return ExchangeShopUI
