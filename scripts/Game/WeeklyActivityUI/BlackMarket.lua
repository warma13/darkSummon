-- Game/WeeklyActivityUI/BlackMarket.lua
-- 黑市商店 UI：限量礼包列表（金色/琥珀主题）

local BMD           = require("Game.BlackMarketData")
local Currency      = require("Game.Currency")
local RewardIconMod = require("Game.RewardIcon")
local RewardDisplay = require("Game.RewardDisplay")
local FormatNumber  = require("Game.FormatUtil").FormatNumber

local Toast         = require("Game.Toast")

local BlackMarket = {}

local CONFIRM_POPUP_ID = "bmConfirmPopup"

-- ============================================================================
-- 顶部横幅：黑市说明 + 暗影精粹余额
-- ============================================================================

function BlackMarket.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local tokens = Currency.Get("shadow_essence")

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 180, 140, 60, 150 },
        overflow = "hidden",
        children = {
            -- 顶部金色条
            UI.Panel {
                width = "100%", height = 3,
                backgroundColor = { 220, 180, 60, 255 },
            },
            UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 14, paddingRight = 14,
                gap = 6,
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "黑市商店",
                                fontSize = 16, fontColor = { 220, 180, 60, 255 }, fontWeight = "bold",
                            },
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                backgroundColor = { 40, 30, 20, 200 },
                                borderRadius = 8,
                                children = {
                                    UI.Label {
                                        text = "暗影精粹:",
                                        fontSize = 12, fontColor = { 200, 180, 120, 200 },
                                    },
                                    UI.Label {
                                        text = FormatNumber(tokens),
                                        fontSize = 14, fontColor = { 255, 220, 100, 255 }, fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 说明
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "i", fontSize = 11, fontColor = { 220, 180, 60, 255 }, fontWeight = "bold" },
                            UI.Label {
                                text = "限量礼包，暗影精粹兑换，先到先得",
                                fontSize = 11, fontColor = S.textDim,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 礼包列表
-- ============================================================================

function BlackMarket.BuildList(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local tokens = Currency.Get("shadow_essence")

    local container = UI.Panel { width = "100%", gap = 8 }
    for i, pkg in ipairs(BMD.PACKAGES) do
        container:AddChild(BlackMarket._BuildCard(UI, S, i, pkg, tokens))
    end
    return container
end

function BlackMarket._BuildCard(UI, S, index, pkg, tokens)
    local bought  = BMD.GetPurchaseCount(pkg.id)
    local soldOut = pkg.limit > 0 and bought >= pkg.limit
    local isFree  = pkg.cost == 0
    local canAfford = tokens >= pkg.cost
    local canBuy    = not soldOut and canAfford

    -- 限购文字
    local limitText = ""
    if pkg.limit > 0 then
        limitText = bought .. "/" .. pkg.limit
    end

    -- 奖励图标
    local rewardIcons = UI.Panel { flexDirection = "row", gap = 4, flexWrap = "wrap", pointerEvents = "auto" }
    for _, reward in ipairs(pkg.rewards) do
        local iconId = reward.id
        if reward.type == "chest" then iconId = reward.id .. "_chest" end
        local icon = RewardIconMod.Create(UI, 36, iconId, reward.amount, { muted = soldOut })
        rewardIcons:AddChild(icon)
    end

    -- 按钮颜色
    local btnBg, btnTextColor
    if soldOut then
        btnBg = S.claimedBg
        btnTextColor = S.textDim
    elseif isFree then
        btnBg = { 60, 160, 100, 240 }
        btnTextColor = { 255, 255, 255, 255 }
    elseif canBuy then
        btnBg = { 180, 140, 50, 240 }
        btnTextColor = { 255, 255, 255, 255 }
    else
        btnBg = { 60, 50, 40, 200 }
        btnTextColor = { 150, 140, 120, 180 }
    end

    -- 边框颜色
    local borderColor = soldOut and { 60, 60, 60, 100 }
        or (isFree and { 100, 200, 120, 200 }
        or (canBuy and { 200, 160, 60, 180 } or S.border))

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = borderColor,
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "row",
        alignItems = "center",
        opacity = soldOut and 0.5 or 1.0,
        children = {
            -- 左侧：名称 + 标签 + 限购
            UI.Panel {
                flexShrink = 0,
                gap = 3,
                paddingRight = 6,
                children = {
                    -- 名称行 + 标签
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = pkg.name,
                                fontSize = 13,
                                fontColor = soldOut and S.textDim or S.textWhite,
                                fontWeight = "bold",
                            },
                            pkg.tag and UI.Panel {
                                paddingLeft = 4, paddingRight = 4,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = isFree and { 60, 160, 100, 200 } or { 200, 140, 40, 200 },
                                borderRadius = 4,
                                children = {
                                    UI.Label {
                                        text = pkg.tag,
                                        fontSize = 9,
                                        fontColor = { 255, 255, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            } or nil,
                        },
                    },
                    -- 限购
                    pkg.limit > 0 and UI.Label {
                        text = "限" .. limitText,
                        fontSize = 10,
                        fontColor = soldOut and { 255, 100, 100, 200 } or { 200, 180, 100, 200 },
                    } or nil,
                },
            },
            -- 中间：奖励图标
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                paddingLeft = 4, paddingRight = 4,
                flexDirection = "row",
                alignItems = "center",
                flexWrap = "wrap",
                gap = 4,
                children = { rewardIcons },
            },
            -- 分隔线
            UI.Panel { width = 1, height = "80%", backgroundColor = { 80, 65, 50, 80 }, flexShrink = 0 },
            -- 购买按钮（含价格）
            UI.Panel {
                minWidth = 56,
                flexShrink = 0,
                marginLeft = 8,
                backgroundColor = btnBg,
                borderRadius = 6,
                justifyContent = "center",
                alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 4, paddingBottom = 4,
                gap = 1,
                pointerEvents = "auto",
                onClick = canBuy and function()
                    BlackMarket._ShowConfirmPopup(UI, S, index, pkg)
                end or nil,
                children = soldOut and {
                    UI.Label {
                        text = "售罄",
                        fontSize = 12,
                        fontColor = btnTextColor,
                        fontWeight = "bold",
                    },
                } or isFree and {
                    UI.Label {
                        text = "领取",
                        fontSize = 12,
                        fontColor = btnTextColor,
                        fontWeight = "bold",
                    },
                } or {
                    UI.Label {
                        text = FormatNumber(pkg.cost),
                        fontSize = 12,
                        fontColor = canAfford and { 255, 220, 100, 255 } or { 255, 100, 100, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "购买",
                        fontSize = 10,
                        fontColor = btnTextColor,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 购买确认弹窗
-- ============================================================================

function BlackMarket._ShowConfirmPopup(UI, S, index, pkg)
    local root = require("Game.WeeklyActivityUI").GetPageRoot()
    if not root then return end

    -- 移除已有弹窗
    local old = root:FindById(CONFIRM_POPUP_ID)
    if old then old:Remove() end

    local isFree = pkg.cost == 0
    local tokens = Currency.Get("shadow_essence")
    local canAfford = tokens >= pkg.cost

    -- 奖励图标
    local rewardIcons = {}
    for _, reward in ipairs(pkg.rewards) do
        local iconId = reward.id
        if reward.type == "chest" then iconId = reward.id .. "_chest" end
        rewardIcons[#rewardIcons + 1] = RewardIconMod.Create(UI, 48, iconId, reward.amount)
    end

    local popup = UI.Panel {
        id = CONFIRM_POPUP_ID,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        children = {
            -- 遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 160 },
                pointerEvents = "auto",
                onClick = function()
                    local p = root:FindById(CONFIRM_POPUP_ID)
                    if p then p:Remove() end
                end,
            },
            -- 弹窗内容
            (function()
                local cardChildren = {
                    -- 顶部金色条
                    UI.Panel { width = "100%", height = 3, backgroundColor = { 220, 180, 60, 255 } },
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        paddingTop = 14, paddingBottom = 8,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label {
                                text = isFree and "确认领取" or "确认购买",
                                fontSize = 16, fontColor = { 220, 180, 60, 255 }, fontWeight = "bold",
                            },
                        },
                    },
                    -- 礼包名称
                    UI.Panel {
                        width = "100%",
                        justifyContent = "center", alignItems = "center",
                        paddingBottom = 10,
                        children = {
                            UI.Label {
                                text = pkg.name,
                                fontSize = 14, fontColor = S.textWhite, fontWeight = "bold",
                            },
                        },
                    },
                    -- 分隔线
                    UI.Panel { width = "90%", height = 1, backgroundColor = { 80, 65, 100, 100 }, alignSelf = "center" },
                    -- 奖励内容
                    UI.Panel {
                        width = "100%",
                        paddingTop = 12, paddingBottom = 12,
                        justifyContent = "center", alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label { text = "包含奖励", fontSize = 11, fontColor = S.textDim },
                            UI.Panel {
                                flexDirection = "row", gap = 6, flexWrap = "wrap",
                                justifyContent = "center",
                                children = rewardIcons,
                            },
                        },
                    },
                }
                -- 价格（仅非免费时）
                if not isFree then
                    cardChildren[#cardChildren + 1] = UI.Panel {
                        width = "100%",
                        justifyContent = "center", alignItems = "center",
                        paddingBottom = 10,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    UI.Label { text = "消耗:", fontSize = 12, fontColor = S.textDim },
                                    UI.Label {
                                        text = "暗影精粹 " .. FormatNumber(pkg.cost),
                                        fontSize = 13,
                                        fontColor = canAfford and { 255, 220, 100, 255 } or { 255, 100, 100, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    }
                end
                -- 按钮行
                cardChildren[#cardChildren + 1] = UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    paddingLeft = 16, paddingRight = 16,
                    paddingBottom = 14,
                    gap = 12,
                    children = {
                        -- 取消
                        UI.Panel {
                            flexGrow = 1,
                            backgroundColor = { 60, 50, 80, 220 },
                            borderRadius = 8,
                            paddingTop = 10, paddingBottom = 10,
                            justifyContent = "center", alignItems = "center",
                            pointerEvents = "auto",
                            onClick = function()
                                local p = root:FindById(CONFIRM_POPUP_ID)
                                if p then p:Remove() end
                            end,
                            children = {
                                UI.Label { text = "取消", fontSize = 13, fontColor = S.textDim, fontWeight = "bold" },
                            },
                        },
                        -- 确认
                        UI.Panel {
                            flexGrow = 1,
                            backgroundColor = isFree and { 60, 160, 100, 240 } or { 180, 140, 50, 240 },
                            borderRadius = 8,
                            paddingTop = 10, paddingBottom = 10,
                            justifyContent = "center", alignItems = "center",
                            pointerEvents = "auto",
                            onClick = function()
                                local p = root:FindById(CONFIRM_POPUP_ID)
                                if p then p:Remove() end

                                local ok, msg, rewards = BMD.Purchase(index)
                                if ok then
                                    local WAU = require("Game.WeeklyActivityUI")
                                    if rewards and #rewards > 0 then
                                        RewardDisplay.Show(UI, root, {
                                            title = "购买成功",
                                            rewards = rewards,
                                            onClose = function() WAU.Refresh() end,
                                        })
                                    else
                                        Toast.Show(msg, { 220, 180, 80 })
                                        WAU.Refresh()
                                    end
                                else
                                    Toast.Show(msg, { 255, 120, 120 })
                                end
                            end,
                            children = {
                                UI.Label {
                                    text = isFree and "确认领取" or "确认购买",
                                    fontSize = 13, fontColor = { 255, 255, 255 }, fontWeight = "bold",
                                },
                            },
                        },
                    },
                }

                return UI.Panel {
                    width = "80%",
                    maxWidth = 320,
                    backgroundColor = { 30, 24, 50, 250 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = { 200, 160, 60, 200 },
                    overflow = "hidden",
                    pointerEvents = "auto",
                    children = cardChildren,
                }
            end)(),
        },
    }

    root:AddChild(popup)
end

return BlackMarket
