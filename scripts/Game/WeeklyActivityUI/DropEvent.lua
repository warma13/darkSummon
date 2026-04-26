-- Game/WeeklyActivityUI/DropEvent.lua
-- 掉落活动 UI：每日看广告领取 + 换购商店 + 周进度条
-- 结构参考限时福利（Welfare.lua）

local DED           = require("Game.DropEventData")
local RewardIconMod = require("Game.RewardIcon")
local FormatNumber  = require("Game.FormatUtil").FormatNumber
local Toast         = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local Currency      = require("Game.Currency")

local DropEvent = {}
local PURCHASE_POPUP_ID = "dropEventPurchasePopup"

-- ============================================================================
-- 入口
-- ============================================================================

function DropEvent.Build(ctx)
    local UI = ctx.GetUI()
    local container = UI.Panel { width = "100%", gap = 10 }
    container:AddChild(DropEvent._BuildBanner(ctx))
    container:AddChild(DropEvent._BuildDailyAdList(ctx))
    container:AddChild(DropEvent._BuildWeeklyAdProgress(ctx))
    container:AddChild(DropEvent._BuildShop(ctx))
    return container
end

-- ============================================================================
-- 顶部横幅
-- ============================================================================

function DropEvent._BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local tokens     = DED.GetTokens()
    local dailyCount = DED.GetDailyAdCount()

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        overflow = "hidden",
        children = {
            UI.Panel { width = "100%", height = 3, backgroundColor = { 100, 180, 255, 255 } },
            UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 14, paddingRight = 14,
                gap = 6,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "掉落活动",
                                fontSize = 16, fontColor = { 100, 200, 255, 255 }, fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                backgroundColor = { 40, 30, 60, 200 },
                                borderRadius = 10,
                                children = {
                                    UI.Label {
                                        text = "今日 " .. dailyCount .. "/" .. DED.MAX_DAILY,
                                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 碎片余额
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                backgroundColor = { 40, 30, 60, 200 },
                                borderRadius = 8,
                                children = {
                                    UI.Label {
                                        text = DED.TOKEN_NAME .. ":",
                                        fontSize = 12, fontColor = { 180, 220, 255, 200 },
                                    },
                                    UI.Label {
                                        text = FormatNumber(tokens),
                                        fontSize = 14, fontColor = { 100, 220, 255, 255 }, fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 说明
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "i", fontSize = 11, fontColor = S.accent, fontWeight = "bold" },
                            UI.Label {
                                text = "每天领取掉落奖励，暗烬碎片可在下方换购商店兑换物品",
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
-- 每日掉落列表（11份看广告）
-- ============================================================================

function DropEvent._BuildDailyAdList(ctx)
    local UI = ctx.GetUI()
    local container = UI.Panel { width = "100%", gap = 6 }
    for i, reward in ipairs(DED.DAILY_REWARDS) do
        container:AddChild(DropEvent._BuildDailyAdCard(ctx, i, reward))
    end
    return container
end

function DropEvent._BuildDailyAdCard(ctx, index, reward)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local claimed  = DED.IsDailyClaimed(index)
    local unlocked = DED.IsDailyUnlocked(index)
    local accentColor = { 100, 200, 255, 255 }

    return UI.Panel {
        width = "100%",
        backgroundColor = claimed and { 25, 22, 35, 180 } or S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = (unlocked and not claimed) and { 100, 180, 255, 180 } or { 60, 50, 80, 100 },
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "row",
        alignItems = "center",
        opacity = claimed and 0.6 or (unlocked and 1.0 or 0.5),
        children = {
            -- 序号
            UI.Panel {
                width = 28, height = 28,
                borderRadius = 14,
                backgroundColor = (unlocked and not claimed) and { 60, 120, 200, 80 } or { 50, 40, 70, 150 },
                justifyContent = "center",
                alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = tostring(index),
                        fontSize = 13,
                        fontColor = (unlocked and not claimed) and accentColor or S.textDim,
                        fontWeight = "bold",
                    },
                },
            },
            -- 奖励描述
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                marginLeft = 8, marginRight = 8,
                gap = 2,
                children = {
                    -- 暗烬碎片
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = DED.TOKEN_NAME .. " ×" .. reward.token,
                                fontSize = 13,
                                fontColor = claimed and S.textDim or accentColor,
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 暗影精粹
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = "暗影精粹 ×" .. FormatNumber(reward.essence),
                                fontSize = 11,
                                fontColor = claimed and S.textDim or { 200, 160, 255, 255 },
                            },
                        },
                    },
                    -- 免费/广告标签
                    reward.free and UI.Label {
                        text = "免费领取",
                        fontSize = 10, fontColor = { 80, 200, 120, 200 },
                    } or UI.Label {
                        text = "观看广告解锁",
                        fontSize = 10, fontColor = S.textDim,
                    },
                },
            },
            -- 按钮
            (function()
                if claimed then
                    return UI.Panel {
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 6, paddingBottom = 6,
                        borderRadius = 6,
                        backgroundColor = { 50, 45, 55, 200 },
                        borderWidth = 1,
                        borderColor = { 70, 65, 75, 120 },
                        children = {
                            UI.Label { text = "已领取", fontSize = 12, fontColor = { 120, 115, 125, 180 }, fontWeight = "bold" },
                        },
                    }
                elseif unlocked then
                    local isFree = reward.free
                    return UI.Panel {
                        paddingLeft = 10, paddingRight = 12,
                        paddingTop = 6, paddingBottom = 6,
                        borderRadius = 6,
                        backgroundColor = isFree and { 60, 170, 90, 255 } or { 80, 120, 200, 255 },
                        borderWidth = 1,
                        borderColor = isFree and { 100, 220, 140, 200 } or { 120, 160, 255, 200 },
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            DED.ClaimDailyReward(index, function(success, errMsg)
                                if success then
                                    ctx.Refresh()
                                    local rewardItems = {}
                                    if reward.token > 0 then
                                        rewardItems[#rewardItems + 1] = {
                                            icon = "image/icon_dark_ember_shard_20260426050206.png",
                                            name = DED.TOKEN_NAME,
                                            amount = reward.token,
                                            borderColor = { 100, 180, 255 },
                                        }
                                    end
                                    if reward.essence > 0 then
                                        rewardItems[#rewardItems + 1] = {
                                            icon = "image/currency_shadow_essence.png",
                                            name = "暗影精粹",
                                            amount = reward.essence,
                                            borderColor = { 160, 100, 255 },
                                        }
                                    end
                                    RewardDisplay.Show(ctx.GetUI(), ctx.GetPageRoot(), {
                                        title = isFree and "免费掉落" or "广告掉落",
                                        rewards = rewardItems,
                                    })
                                else
                                    Toast.Show(errMsg or "领取失败", "error")
                                end
                            end)
                        end,
                        children = isFree and {
                            UI.Label { text = "领取", fontSize = 12, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
                        } or {
                            UI.Panel { width = 16, height = 16, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain", marginRight = 4 },
                            UI.Label { text = "观看", fontSize = 12, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
                        },
                    }
                else
                    return UI.Panel {
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 6, paddingBottom = 6,
                        borderRadius = 6,
                        backgroundColor = { 45, 40, 55, 200 },
                        borderWidth = 1,
                        borderColor = { 65, 60, 75, 120 },
                        children = {
                            UI.Label { text = "未解锁", fontSize = 12, fontColor = { 120, 115, 125, 180 }, fontWeight = "bold" },
                        },
                    }
                end
            end)(),
        },
    }
end

-- ============================================================================
-- 每周广告进度条
-- ============================================================================

function DropEvent._BuildWeeklyAdProgress(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local totalAds   = DED.GetWeeklyAdTotal()
    local milestones = DED.WEEKLY_MILESTONES
    local maxAds     = milestones[#milestones].threshold
    local CELL_SZ    = 36
    local barH       = 6
    local pct        = maxAds > 0 and math.min(1, totalAds / maxAds) or 0

    local anyCanClaim = false
    for i = 1, #milestones do
        if DED.IsWeeklyClaimable(i) then
            anyCanClaim = true
            break
        end
    end

    -- 横向奖励图标行
    local iconRow = {}
    for i, m in ipairs(milestones) do
        local claimed   = DED.IsWeeklyClaimed(i)
        local reached   = totalAds >= m.threshold
        local claimable = reached and not claimed

        local icon = RewardIconMod.Create(UI, CELL_SZ, "shadow_essence", m.rewardAmount, {
            muted = claimed,
        })

        iconRow[#iconRow + 1] = UI.Panel {
            width = CELL_SZ, height = CELL_SZ,
            flexShrink = 0,
            overflow = "visible",
            opacity = claimed and 0.35 or (reached and 1.0 or 0.5),
            children = {
                icon,
                claimable and UI.Panel {
                    position = "absolute", top = -3, right = -3,
                    width = 8, height = 8, borderRadius = 4,
                    backgroundColor = S.red, zIndex = 3,
                    pointerEvents = "none",
                } or nil,
                claimed and UI.Panel {
                    position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
                    justifyContent = "center", alignItems = "center",
                    zIndex = 2,
                    backgroundColor = { 0, 0, 0, 100 },
                    borderRadius = 6,
                    pointerEvents = "none",
                    children = {
                        UI.Label { text = "\u{2713}", fontSize = 16, fontColor = S.textGreen, fontWeight = "bold" },
                    },
                } or nil,
            },
        }
    end

    -- 阈值标签
    local thresholdLabels = {}
    for _, m in ipairs(milestones) do
        thresholdLabels[#thresholdLabels + 1] = UI.Label {
            text = tostring(m.threshold),
            fontSize = 9,
            fontColor = (totalAds >= m.threshold) and S.textGold or S.textDim,
            textAlign = "center",
            flexGrow = 1,
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        padding = 10,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            -- 左列：累计广告次数
            UI.Panel {
                width = 50,
                flexShrink = 0,
                alignItems = "center",
                justifyContent = "center",
                gap = 2,
                children = {
                    UI.Label { text = "广告", fontSize = 11, fontColor = S.textDim },
                    UI.Label {
                        text = tostring(totalAds),
                        fontSize = 22, fontColor = S.textGold, fontWeight = "bold",
                    },
                },
            },
            -- 中列
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                width = "100%",
                gap = 4,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = iconRow,
                    },
                    UI.Panel {
                        width = "100%", height = barH,
                        backgroundColor = S.barBg,
                        borderRadius = barH / 2,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(pct * 100) .. "%",
                                height = "100%",
                                backgroundColor = S.tabActive,
                                borderRadius = barH / 2,
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = thresholdLabels,
                    },
                },
            },
            -- 右列：全部领取
            UI.Panel {
                width = 50,
                flexShrink = 0,
                alignItems = "center",
                justifyContent = "center",
                children = {
                    UI.Panel {
                        width = 48, height = 44,
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = anyCanClaim and S.accent or { 80, 65, 120, 120 },
                        backgroundColor = anyCanClaim and { 120, 60, 200, 200 } or { 40, 30, 60, 150 },
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 1,
                        pointerEvents = "auto",
                        opacity = anyCanClaim and 1.0 or 0.5,
                        onClick = function()
                            if not anyCanClaim then
                                Toast.Show("没有可领取的奖励", "warning")
                                return
                            end
                            local totalAmount = 0
                            for idx = 1, #milestones do
                                local ok = DED.ClaimWeeklyMilestone(idx)
                                if ok then
                                    totalAmount = totalAmount + milestones[idx].rewardAmount
                                end
                            end
                            if totalAmount > 0 then
                                RewardDisplay.Show(ctx.GetUI(), ctx.GetPageRoot(), {
                                    title = "广告进度奖励",
                                    rewards = {
                                        {
                                            icon = "image/currency_shadow_essence.png",
                                            name = "暗影精粹",
                                            amount = totalAmount,
                                            borderColor = { 160, 100, 255 },
                                        },
                                    },
                                    onClose = function()
                                        ctx.Refresh()
                                    end,
                                })
                            end
                        end,
                        children = {
                            UI.Label { text = "全部", fontSize = 11, fontColor = S.textWhite, textAlign = "center" },
                            UI.Label { text = "领取", fontSize = 11, fontColor = S.textWhite, textAlign = "center" },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 换购商店
-- ============================================================================

function DropEvent._BuildShop(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local tokens = DED.GetTokens()

    local container = UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        gap = 8,
    }

    -- 标题
    container:AddChild(UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        width = "100%",
        children = {
            UI.Label {
                text = "换购商店",
                fontSize = 14, fontColor = { 255, 200, 80, 255 }, fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Label {
                        text = DED.TOKEN_NAME .. "余额:",
                        fontSize = 11, fontColor = S.textDim,
                    },
                    UI.Label {
                        text = FormatNumber(tokens),
                        fontSize = 13, fontColor = { 100, 220, 255, 255 }, fontWeight = "bold",
                    },
                },
            },
        },
    })

    -- 商品列表
    for i, item in ipairs(DED.SHOP_ITEMS) do
        container:AddChild(DropEvent._BuildShopCard(ctx, i, item, tokens))
    end

    return container
end

function DropEvent._BuildShopCard(ctx, index, item, tokens)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local bought  = DED.GetPurchaseCount(item.id)
    local soldOut = item.limit > 0 and bought >= item.limit
    local canAfford = tokens >= item.cost
    local canBuy  = not soldOut and canAfford

    local limitText = ""
    if item.limit > 0 then
        limitText = bought .. "/" .. item.limit
    end

    -- 奖励图标
    local rewardIcons = UI.Panel { flexDirection = "row", gap = 4, pointerEvents = "auto" }
    for _, reward in ipairs(item.rewards) do
        local iconId = reward.id
        if reward.type == "chest" then iconId = reward.id .. "_chest" end
        local icon = RewardIconMod.Create(UI, 38, iconId, reward.amount, { muted = soldOut })
        rewardIcons:AddChild(icon)
    end

    local btnBg, btnTextColor
    if soldOut then
        btnBg = S.claimedBg or { 50, 45, 55, 200 }
        btnTextColor = S.textDim
    elseif canBuy then
        btnBg = { 60, 140, 200, 240 }
        btnTextColor = { 255, 255, 255, 255 }
    else
        btnBg = { 60, 50, 80, 200 }
        btnTextColor = { 150, 140, 170, 180 }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = soldOut and { 60, 60, 60, 100 } or (canBuy and { 100, 180, 255, 180 } or S.border),
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "row",
        alignItems = "center",
        opacity = soldOut and 0.5 or 1.0,
        children = {
            -- 左侧：名称 + 限购
            UI.Panel {
                flexShrink = 0,
                gap = 3,
                paddingRight = 6,
                children = {
                    UI.Label {
                        text = item.name,
                        fontSize = 13,
                        fontColor = soldOut and S.textDim or (S.textWhite or { 255, 255, 255 }),
                        fontWeight = "bold",
                    },
                    item.limit > 0 and UI.Label {
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
            -- 右侧：购买按钮（含价格）
            UI.Panel { width = 1, height = "80%", backgroundColor = { 80, 65, 120, 80 }, flexShrink = 0 },
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
                    DropEvent._ShowPurchasePopup(ctx, index, item)
                end or nil,
                children = soldOut and {
                    UI.Label {
                        text = "售罄",
                        fontSize = 12,
                        fontColor = btnTextColor,
                        fontWeight = "bold",
                    },
                } or {
                    UI.Label {
                        text = FormatNumber(item.cost),
                        fontSize = 12,
                        fontColor = canAfford and { 100, 220, 255, 255 } or { 255, 100, 100, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "换购",
                        fontSize = 10,
                        fontColor = btnTextColor,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 换购数量选择弹窗
-- ============================================================================

function DropEvent._ShowPurchasePopup(ctx, shopIndex, item)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()
    local root = ctx.GetPageRoot()

    local maxCount = DED.GetMaxPurchasable(shopIndex)
    if maxCount <= 0 then
        Toast.Show("无法购买", { 255, 120, 120 })
        return
    end

    -- 限购1的商品直接购买，不弹窗
    if item.limit == 1 then
        local ok, msg = DED.PurchaseShopItem(shopIndex, 1)
        if ok then ctx.Refresh() else Toast.Show(msg, { 255, 120, 120 }) end
        return
    end

    local selectedCount = 1

    local function rebuild()
        local old = root:FindById(PURCHASE_POPUP_ID)
        if old then root:RemoveChild(old) end

        local totalCost = item.cost * selectedCount

        -- 奖励预览
        local previewRows = {}
        for _, reward in ipairs(item.rewards) do
            local iconId = reward.id
            if reward.type == "chest" then iconId = reward.id .. "_chest" end
            local totalAmount = reward.amount * selectedCount
            previewRows[#previewRows + 1] = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    RewardIconMod.Create(UI, 30, iconId, totalAmount),
                },
            }
        end

        -- 数量选择器
        local countSelector = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 16,
            paddingTop = 6, paddingBottom = 6,
            children = {
                -- 减少按钮
                UI.Panel {
                    width = 36, height = 36,
                    justifyContent = "center", alignItems = "center",
                    borderRadius = 18,
                    backgroundColor = selectedCount > 1 and { 80, 80, 120, 200 } or { 40, 40, 50, 120 },
                    pointerEvents = "auto",
                    onClick = selectedCount > 1 and function()
                        selectedCount = selectedCount - 1
                        rebuild()
                    end or nil,
                    children = {
                        UI.Label {
                            text = "−", fontSize = 20, fontWeight = "bold",
                            fontColor = selectedCount > 1 and { 255, 255, 255 } or S.textDim,
                            pointerEvents = "none",
                        },
                    },
                },
                -- 当前数量
                UI.Label {
                    text = tostring(selectedCount),
                    fontSize = 28, fontWeight = "bold",
                    fontColor = { 255, 255, 255 },
                    pointerEvents = "none",
                    width = 50, textAlign = "center",
                },
                -- 增加按钮
                UI.Panel {
                    width = 36, height = 36,
                    justifyContent = "center", alignItems = "center",
                    borderRadius = 18,
                    backgroundColor = selectedCount < maxCount and { 80, 80, 120, 200 } or { 40, 40, 50, 120 },
                    pointerEvents = "auto",
                    onClick = selectedCount < maxCount and function()
                        selectedCount = selectedCount + 1
                        rebuild()
                    end or nil,
                    children = {
                        UI.Label {
                            text = "+", fontSize = 20, fontWeight = "bold",
                            fontColor = selectedCount < maxCount and { 255, 255, 255 } or S.textDim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }

        -- 快捷按钮
        local quickButtons = {}
        local quickVals = { 1, 5, 10, maxCount }
        local seen = {}
        for _, v in ipairs(quickVals) do
            if v >= 1 and v <= maxCount and not seen[v] then
                seen[v] = true
                local isActive = (selectedCount == v)
                quickButtons[#quickButtons + 1] = UI.Panel {
                    paddingLeft = 10, paddingRight = 10,
                    paddingTop = 3, paddingBottom = 3,
                    borderRadius = 10,
                    backgroundColor = isActive and { 80, 120, 200, 220 } or { 50, 45, 65, 150 },
                    borderWidth = isActive and 1 or 0,
                    borderColor = isActive and { 100, 160, 255, 200 } or nil,
                    pointerEvents = "auto",
                    onClick = function()
                        selectedCount = v
                        rebuild()
                    end,
                    children = {
                        UI.Label {
                            text = v == maxCount and v > 10 and ("全部" .. v) or tostring(v),
                            fontSize = 11,
                            fontColor = isActive and { 255, 255, 255 } or S.textDim,
                            pointerEvents = "none",
                        },
                    },
                }
            end
        end

        local quickRow = #quickButtons > 1 and UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 8,
            children = quickButtons,
        } or nil

        -- 弹窗主体内容
        local popupChildren = {
            -- 标题
            UI.Label {
                text = item.name,
                fontSize = 16, fontWeight = "bold",
                fontColor = { 255, 255, 255 },
                alignSelf = "center",
                pointerEvents = "none",
            },
            -- 分割线
            UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 80, 100, 80 }, marginTop = 2 },
            -- 选择数量标签
            UI.Label {
                text = "选择兑换数量",
                fontSize = 12, fontColor = S.textDim,
                alignSelf = "center",
                pointerEvents = "none",
            },
            countSelector,
        }

        if quickRow then
            popupChildren[#popupChildren + 1] = quickRow
        end

        -- 奖励预览
        if #previewRows > 0 then
            popupChildren[#popupChildren + 1] = UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 80, 100, 80 }, marginTop = 4 }
            popupChildren[#popupChildren + 1] = UI.Label {
                text = "预计获得",
                fontSize = 12, fontColor = S.textDim,
                alignSelf = "center",
                pointerEvents = "none",
            }
            popupChildren[#popupChildren + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                flexWrap = "wrap",
                gap = 6,
                paddingTop = 4,
                children = previewRows,
            }
        end

        -- 消耗提示
        popupChildren[#popupChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            gap = 4,
            marginTop = 6,
            children = {
                UI.Label {
                    text = "消耗",
                    fontSize = 11, fontColor = S.textDim,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = FormatNumber(totalCost),
                    fontSize = 13, fontWeight = "bold",
                    fontColor = DED.GetTokens() >= totalCost and { 100, 220, 255, 255 } or { 255, 100, 100, 255 },
                    pointerEvents = "none",
                },
                UI.Label {
                    text = DED.TOKEN_NAME,
                    fontSize = 11, fontColor = S.textDim,
                    pointerEvents = "none",
                },
            },
        }

        -- 按钮行
        popupChildren[#popupChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 16,
            marginTop = 8,
            children = {
                -- 取消
                UI.Panel {
                    width = 90, height = 36,
                    borderRadius = 8,
                    borderWidth = 1,
                    borderColor = { 100, 90, 130, 150 },
                    backgroundColor = { 50, 45, 65, 200 },
                    justifyContent = "center", alignItems = "center",
                    pointerEvents = "auto",
                    onClick = function()
                        local p = root:FindById(PURCHASE_POPUP_ID)
                        if p then root:RemoveChild(p) end
                    end,
                    children = {
                        UI.Label {
                            text = "取消", fontSize = 13,
                            fontColor = { 180, 170, 200, 220 },
                            pointerEvents = "none",
                        },
                    },
                },
                -- 确认换购
                UI.Panel {
                    width = 120, height = 36,
                    borderRadius = 8,
                    backgroundColor = { 60, 140, 200, 240 },
                    justifyContent = "center", alignItems = "center",
                    pointerEvents = "auto",
                    onClick = function()
                        local p = root:FindById(PURCHASE_POPUP_ID)
                        if p then root:RemoveChild(p) end
                        local ok, msg = DED.PurchaseShopItem(shopIndex, selectedCount)
                        if ok then
                            ctx.Refresh()
                        else
                            Toast.Show(msg, { 255, 120, 120 })
                        end
                    end,
                    children = {
                        UI.Label {
                            text = "换购 ×" .. selectedCount, fontSize = 13,
                            fontColor = { 255, 255, 255 }, fontWeight = "bold",
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }

        -- 遮罩 + 弹窗
        root:AddChild(UI.Panel {
            id = PURCHASE_POPUP_ID,
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center", alignItems = "center",
            pointerEvents = "auto",
            onClick = function()
                local p = root:FindById(PURCHASE_POPUP_ID)
                if p then root:RemoveChild(p) end
            end,
            children = {
                UI.Panel {
                    width = 300,
                    backgroundColor = { 30, 25, 45, 245 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = { 100, 140, 220, 120 },
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 14, paddingBottom = 14,
                    gap = 6,
                    pointerEvents = "auto",
                    onClick = function() end, -- 阻止冒泡关闭
                    children = popupChildren,
                },
            },
        })
    end

    rebuild()
end

-- ============================================================================
-- 兼容旧入口
-- ============================================================================

DropEvent.BuildBanner    = DropEvent._BuildBanner
DropEvent.BuildDailyDrops = function(ctx) return DropEvent._BuildDailyAdList(ctx) end
DropEvent.BuildShop      = DropEvent._BuildShop

return DropEvent
