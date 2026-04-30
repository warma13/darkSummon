-- Game/JoyShopUI.lua
-- 欢乐商店 UI：用欢乐币兑换物资
-- 覆盖层模式，与 ExchangeShopUI 一致

local JoyShopData   = require("Game.JoyShopData")
local Currency      = require("Game.Currency")
local Config        = require("Game.Config")
local RewardIcon    = require("Game.RewardIcon")
local RewardDisplay = require("Game.RewardDisplay")
local Toast         = require("Game.Toast")

local JoyShopUI = {}

---@type any
local UI
---@type any
local pageRoot
---@type any
local confirmLayer
local _onBack

-- 样式常量
local S = {
    bgDark     = { 18, 14, 28, 250 },
    bgCard     = { 40, 32, 60, 220 },
    border     = { 100, 80, 160, 120 },
    gold       = { 255, 215, 80 },
    joyColor   = { 255, 200, 60 },
    white      = { 240, 240, 255 },
    gray       = { 140, 130, 160 },
    red        = { 255, 80, 80 },
    green      = { 100, 255, 120 },
    greenDim   = { 60, 150, 80 },
    dimBg      = { 30, 25, 40, 180 },
}

-- 内部辅助函数前向声明（避免污染全局命名空间）
local createHeader
local createDailyStatusBar
local createShopGrid
local createItemCard
local createBottomBar
local showConfirmDialog
local showRulesDialog

-- ============================================================================
-- 公共接口
-- ============================================================================

function JoyShopUI.SetOnBack(fn)
    _onBack = fn
end

---@param uiModule any
---@return any
function JoyShopUI.CreatePage(uiModule)
    UI = uiModule
    pageRoot = UI.Panel {
        id = "joyShopPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = S.bgDark,
        children = {},
    }
    JoyShopUI.Refresh()
    return pageRoot
end

function JoyShopUI.Refresh()
    if not pageRoot then return end
    pageRoot:ClearChildren()

    -- 顶栏
    pageRoot:AddChild(createHeader())
    -- 每日任务状态栏
    pageRoot:AddChild(createDailyStatusBar())
    -- 商品网格
    pageRoot:AddChild(createShopGrid())
    -- 底栏
    pageRoot:AddChild(createBottomBar())

    -- 确认弹窗层
    confirmLayer = UI.Panel {
        id = "joyShopConfirmLayer",
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

function JoyShopUI.Remove()
    if pageRoot then
        pageRoot:Remove()
        pageRoot = nil
    end
    confirmLayer = nil
end

-- ============================================================================
-- 顶栏
-- ============================================================================

function createHeader()
    local joyAmount = Currency.Get("joy_coin")
    local joyDef = Config.CURRENCY.joy_coin

    return UI.Panel {
        width = "100%", height = 48, flexShrink = 0,
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 28, 22, 42, 250 },
        borderColor = { 80, 60, 120, 120 }, borderWidth = { bottom = 1 },
        children = {
            UI.Label {
                text = "欢乐商店",
                fontSize = 18,
                fontColor = S.gold,
                fontWeight = "bold",
                flexGrow = 1,
            },
            -- 欢乐币余额
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                paddingLeft = 10, paddingRight = 10, paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 60, 50, 20, 200 }, borderRadius = 14,
                borderWidth = 1, borderColor = { 200, 170, 60, 120 },
                children = {
                    joyDef and joyDef.image and UI.Panel {
                        width = 20, height = 20,
                        backgroundImage = joyDef.image, backgroundFit = "contain",
                    } or nil,
                    UI.Label {
                        text = tostring(joyAmount),
                        fontSize = 14, fontColor = S.joyColor, fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 每日任务状态栏
-- ============================================================================

function createDailyStatusBar()
    local firstDone = JoyShopData.IsFirstGameDone()
    local settleDone = JoyShopData.IsSettlementDone()
    local firstReward = JoyShopData.GetFirstGameRewardAmount()

    local firstIcon = firstDone and "✅" or "⬜"
    local firstText = firstDone
        and ("每日首局已完成 (+" .. firstReward .. ")")
        or ("每日首局未完成 (完成可得+" .. firstReward .. ")")
    local firstColor = firstDone and S.greenDim or S.gray

    local settleIcon = settleDone and "✅" or "⬜"
    local settleText = settleDone and "昨日排行已结算" or "昨日排行待结算"
    local settleColor = settleDone and S.greenDim or S.gray

    return UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = { 25, 20, 40, 200 },
        borderColor = { 60, 50, 90, 80 }, borderWidth = { bottom = 1 },
        gap = 4,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Label { text = firstIcon, fontSize = 13 },
                    UI.Label { text = firstText, fontSize = 12, fontColor = firstColor },
                },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Label { text = settleIcon, fontSize = 13 },
                    UI.Label { text = settleText, fontSize = 12, fontColor = settleColor },
                },
            },
        },
    }
end

-- ============================================================================
-- 商品网格
-- ============================================================================

function createShopGrid()
    local items = JoyShopData.SHOP_ITEMS
    local cards = {}
    for _, item in ipairs(items) do
        cards[#cards + 1] = createItemCard(item)
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

function createItemCard(item)
    local remaining = JoyShopData.GetRemaining(item.id)
    local soldOut = remaining == 0
    local canAfford = Currency.Has("joy_coin", item.cost)
    local borderC = soldOut and { 60, 50, 80, 100 } or S.border
    local joyDef = Config.CURRENCY.joy_coin

    local cardChildren = {}

    -- 图标
    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%", height = 70,
        justifyContent = "center", alignItems = "center",
        marginTop = 6, opacity = soldOut and 0.4 or 1.0,
        children = { RewardIcon.Create(UI, 52, item.icon, item.amount, { muted = soldOut }) },
    }

    -- 价格行
    cardChildren[#cardChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", justifyContent = "center",
        gap = 3, width = "100%", marginTop = 3,
        children = {
            joyDef and joyDef.image and UI.Panel {
                width = 14, height = 14, backgroundImage = joyDef.image, backgroundFit = "contain",
            } or nil,
            UI.Label {
                text = tostring(item.cost), fontSize = 13,
                fontColor = (not soldOut and canAfford) and S.joyColor or S.red, fontWeight = "bold",
            },
        },
    }

    -- 限购提示
    if item.dailyLimit > 0 then
        cardChildren[#cardChildren + 1] = UI.Panel {
            width = "100%", alignItems = "center", marginTop = 2,
            children = {
                UI.Label {
                    text = soldOut and "已售罄" or ("剩余" .. remaining .. "/" .. item.dailyLimit),
                    fontSize = 10, fontColor = soldOut and S.red or S.gray,
                },
            },
        }
    end

    -- 兑换按钮
    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%", alignItems = "center", marginTop = 4, marginBottom = 6,
        children = {
            UI.Button {
                text = soldOut and "售罄" or "兑换", fontSize = 12,
                width = 72, height = 28, borderRadius = 14,
                variant = soldOut and "outline" or "primary", disabled = soldOut,
                onClick = function() showConfirmDialog(item) end,
            },
        },
    }

    return UI.Panel {
        width = 110, flexDirection = "column", alignItems = "center",
        backgroundColor = soldOut and S.dimBg or S.bgCard,
        borderRadius = 8, borderWidth = 1, borderColor = borderC,
        overflow = "visible", position = "relative",
        children = cardChildren,
    }
end

-- ============================================================================
-- 底栏
-- ============================================================================

function createBottomBar()
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
            -- 奖励规则说明
            UI.Panel {
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 4, paddingBottom = 4,
                borderRadius = 8,
                backgroundColor = { 50, 40, 70, 180 },
                pointerEvents = "auto",
                onClick = function() showRulesDialog() end,
                children = {
                    UI.Label {
                        text = "奖励规则", fontSize = 12, fontColor = S.gray,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 确认弹窗
-- ============================================================================

function showConfirmDialog(item)
    if not confirmLayer or not UI then return end
    confirmLayer:ClearChildren()

    local canAfford = Currency.Has("joy_coin", item.cost)
    local joyDef = Config.CURRENCY.joy_coin

    confirmLayer:AddChild(UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 }, pointerEvents = "auto",
        onClick = function() confirmLayer:SetVisible(false) end,
    })

    confirmLayer:AddChild(UI.Panel {
        width = 220, flexDirection = "column", alignItems = "center",
        backgroundColor = { 35, 28, 55, 245 }, borderRadius = 12,
        borderWidth = 2, borderColor = { 200, 170, 60, 200 },
        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
        pointerEvents = "auto",
        children = {
            UI.Label { text = "购买确认", fontSize = 18, fontColor = S.gold, fontWeight = "bold", textAlign = "center", width = "100%" },
            UI.Panel { width = "80%", height = 1, backgroundColor = { 100, 80, 160, 100 }, marginTop = 8, marginBottom = 10 },
            UI.Label { text = "购买" .. item.name, fontSize = 13, fontColor = S.joyColor, textAlign = "center", width = "100%", marginBottom = 10 },
            -- 商品预览
            UI.Panel {
                width = 80, height = 80, justifyContent = "center", alignItems = "center",
                backgroundColor = { 50, 40, 75, 200 }, borderRadius = 8,
                borderWidth = 1, borderColor = { 100, 80, 160, 150 }, marginBottom = 14,
                children = { RewardIcon.Create(UI, 60, item.icon, item.amount, {}) },
            },
            -- 价格 + 购买按钮
            UI.Panel {
                flexDirection = "column", alignItems = "center", gap = 6, width = "100%", marginBottom = 10,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 4,
                        paddingLeft = 14, paddingRight = 14, paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 50, 45, 30, 200 }, borderRadius = 8,
                        borderWidth = 1, borderColor = canAfford and { 180, 160, 60, 150 } or { 180, 60, 60, 150 },
                        children = {
                            joyDef and joyDef.image and UI.Panel {
                                width = 18, height = 18, backgroundImage = joyDef.image, backgroundFit = "contain",
                            } or nil,
                            UI.Label { text = tostring(item.cost), fontSize = 16, fontColor = canAfford and S.gold or S.red, fontWeight = "bold" },
                        },
                    },
                    UI.Button {
                        text = "购买", fontSize = 14, width = 100, height = 36, borderRadius = 18,
                        variant = canAfford and "primary" or "outline", disabled = not canAfford,
                        onClick = function()
                            local ok, msg, rewards = JoyShopData.Purchase(item.id)
                            confirmLayer:SetVisible(false)
                            if ok then
                                if rewards and #rewards > 0 then
                                    RewardDisplay.Show(UI, pageRoot, {
                                        title = "兑换成功", rewards = rewards,
                                        onClose = function() JoyShopUI.Refresh() end,
                                    })
                                else
                                    Toast.Show(msg, S.green)
                                    JoyShopUI.Refresh()
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
-- 奖励规则弹窗
-- ============================================================================

function showRulesDialog()
    if not confirmLayer or not UI then return end
    confirmLayer:ClearChildren()

    local tiers = JoyShopData.GetRankRewardTiers()
    local firstReward = JoyShopData.GetFirstGameRewardAmount()

    local ruleLines = {}
    ruleLines[#ruleLines + 1] = UI.Label {
        text = "欢乐币获取方式", fontSize = 15, fontColor = S.gold, fontWeight = "bold",
        marginBottom = 8,
    }
    ruleLines[#ruleLines + 1] = UI.Panel {
        width = "100%", height = 1, backgroundColor = { 100, 80, 160, 80 }, marginBottom = 8,
    }
    -- 首局奖励
    ruleLines[#ruleLines + 1] = UI.Label {
        text = "每日首局完成奖励", fontSize = 13, fontColor = S.joyColor, fontWeight = "bold",
    }
    ruleLines[#ruleLines + 1] = UI.Label {
        text = "每天首次完成任一小游戏即可获得 " .. firstReward .. " 欢乐币",
        fontSize = 11, fontColor = S.gray, marginBottom = 8,
    }
    -- 排行结算
    ruleLines[#ruleLines + 1] = UI.Label {
        text = "每日排行榜结算奖励", fontSize = 13, fontColor = S.joyColor, fontWeight = "bold",
    }
    for _, tier in ipairs(tiers) do
        local rankText
        if tier.maxRank == 1 then
            rankText = "第1名"
        else
            local prevMax = 0
            for _, t2 in ipairs(tiers) do
                if t2.maxRank < tier.maxRank and t2.maxRank > prevMax then
                    prevMax = t2.maxRank
                end
            end
            rankText = "第" .. (prevMax + 1) .. "-" .. tier.maxRank .. "名"
        end
        ruleLines[#ruleLines + 1] = UI.Label {
            text = rankText .. "：" .. tier.amount .. " 欢乐币",
            fontSize = 11, fontColor = S.white,
        }
    end
    ruleLines[#ruleLines + 1] = UI.Label {
        text = "参与但未上榜：5 欢乐币",
        fontSize = 11, fontColor = S.gray, marginTop = 2,
    }

    confirmLayer:AddChild(UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 }, pointerEvents = "auto",
        onClick = function() confirmLayer:SetVisible(false) end,
    })

    confirmLayer:AddChild(UI.Panel {
        width = 260, flexDirection = "column", alignItems = "center",
        backgroundColor = { 35, 28, 55, 245 }, borderRadius = 12,
        borderWidth = 2, borderColor = { 200, 170, 60, 200 },
        paddingTop = 16, paddingBottom = 16, paddingLeft = 18, paddingRight = 18,
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%", flexDirection = "column", gap = 2,
                children = ruleLines,
            },
            UI.Button {
                text = "知道了", fontSize = 14, width = 100, height = 34, borderRadius = 17,
                variant = "primary", marginTop = 14,
                onClick = function() confirmLayer:SetVisible(false) end,
            },
        },
    })

    confirmLayer:SetVisible(true)
end

return JoyShopUI
