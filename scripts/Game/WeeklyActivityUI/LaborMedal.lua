-- Game/WeeklyActivityUI/LaborMedal.lua
-- 劳动奖章收集活动 UI 子模块（里程碑 + 兑换商店）

local LMD              = require("Game.LaborMedalData")
local Currency         = require("Game.Currency")
local Toast            = require("Game.Toast")
local RewardController = require("Game.RewardController")
local RewardIcon       = require("Game.RewardIcon")

local LaborMedal = {}

--- 弹窗引用（由 BuildShop 在首次渲染时创建）
---@type UIElement|nil
local confirmLayer = nil

-- ============================================================================
-- 顶部横幅：奖章余额 + 累计进度
-- ============================================================================

function LaborMedal.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local balance   = Currency.Get("labor_medal")
    local totalEarn = LMD.GetTotalEarned()
    local isActive  = LMD.IsActive()

    -- 下一个未达标里程碑
    local nextThreshold = 0
    for _, m in ipairs(LMD.MILESTONES) do
        if totalEarn < m.threshold then
            nextThreshold = m.threshold
            break
        end
    end
    if nextThreshold == 0 then
        nextThreshold = LMD.MILESTONES[#LMD.MILESTONES].threshold
    end

    local progressPct = math.min(100, math.floor(totalEarn / nextThreshold * 100))

    return UI.Panel {
        width = "100%",
        backgroundColor = { 45, 25, 10, 240 },
        borderRadius = 10,
        borderWidth = 2,
        borderColor = { 255, 140, 40, 200 },
        overflow = "hidden",
        marginBottom = 8,
        children = {
            -- 活动配图
            UI.Panel {
                width = "100%", height = 120,
                backgroundImage = "image/banner_labor_medal.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                borderTopLeftRadius = 10,
                borderTopRightRadius = 10,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 12, paddingBottom = 14,
                paddingLeft = 16, paddingRight = 16,
                gap = 10,
                children = {
                    -- 标题 + 余额行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Panel {
                                gap = 2,
                                flexShrink = 1,
                                children = {
                                    UI.Label {
                                        text = "劳动奖章收集",
                                        fontSize = 16,
                                        fontColor = { 255, 200, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "参与玩法收集奖章，兑换限定奖励",
                                        fontSize = 10,
                                        fontColor = { 200, 170, 130, 200 },
                                    },
                                },
                            },
                            -- 余额展示
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 5, paddingBottom = 5,
                                backgroundColor = { 80, 40, 10, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 255, 160, 60, 150 },
                                children = {
                                    Currency.IconWidget(UI, "labor_medal", 18),
                                    UI.Label {
                                        text = tostring(balance),
                                        fontSize = 15,
                                        fontColor = { 255, 200, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 里程碑进度条
                    UI.Panel {
                        width = "100%", gap = 4,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                width = "100%",
                                children = {
                                    UI.Label {
                                        text = "累计获得",
                                        fontSize = 11,
                                        fontColor = { 200, 170, 130, 200 },
                                    },
                                    UI.Label {
                                        text = totalEarn .. " / " .. nextThreshold,
                                        fontSize = 11,
                                        fontColor = { 255, 180, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Panel {
                                width = "100%", height = 8,
                                backgroundColor = { 30, 15, 5, 200 },
                                borderRadius = 4,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = progressPct .. "%",
                                        height = "100%",
                                        backgroundColor = { 255, 160, 40, 255 },
                                        borderRadius = 4,
                                    },
                                },
                            },
                        },
                    },
                    -- 产出来源提示
                    LaborMedal._BuildSourceHints(UI),
                },
            },
        },
    }
end

--- 产出来源提示面板
function LaborMedal._BuildSourceHints(UI)
    local hints = {}
    for key, src in pairs(LMD.SOURCES) do
        hints[#hints + 1] = { label = src.label, amount = src.amount }
    end
    -- 按 amount 降序排列
    table.sort(hints, function(a, b) return a.amount > b.amount end)

    local items = {}
    for _, h in ipairs(hints) do
        items[#items + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            children = {
                UI.Panel {
                    width = 4, height = 4,
                    borderRadius = 2,
                    backgroundColor = { 255, 180, 80, 200 },
                    flexShrink = 0,
                },
                UI.Label {
                    text = h.label .. " +" .. h.amount,
                    fontSize = 10,
                    fontColor = { 200, 180, 140, 180 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 30, 15, 5, 180 },
        borderRadius = 6,
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        gap = 4,
        borderWidth = 1,
        borderColor = { 80, 50, 20, 120 },
        children = {
            UI.Label {
                text = "奖章获取途径",
                fontSize = 11,
                fontColor = { 255, 180, 80, 220 },
                fontWeight = "bold",
                marginBottom = 2,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 6,
                children = items,
            },
        },
    }
end

-- ============================================================================
-- 里程碑列表
-- ============================================================================

function LaborMedal.BuildMilestones(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local cards = {}
    for i = 1, #LMD.MILESTONES do
        cards[#cards + 1] = LaborMedal._BuildMilestoneCard(ctx, i)
    end

    return UI.Panel {
        width = "100%",
        gap = 4,
        marginBottom = 8,
        children = {
            UI.Label {
                text = "累计里程碑",
                fontSize = 14,
                fontColor = { 255, 200, 80, 255 },
                fontWeight = "bold",
                marginBottom = 4,
            },
            table.unpack(cards),
        },
    }
end

function LaborMedal._BuildMilestoneCard(ctx, index)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local milestone = LMD.MILESTONES[index]
    if not milestone then return UI.Panel {} end

    local canClaim, claimed, reached = LMD.GetMilestoneStatus(index)
    local totalEarn = LMD.GetTotalEarned()
    local pct = math.min(100, math.floor(totalEarn / milestone.threshold * 100))

    -- 样式
    local cardBg, borderColor, statusText, statusColor, statusBg

    if claimed then
        cardBg      = { 30, 25, 20, 180 }
        borderColor = { 60, 50, 40, 100 }
        statusText  = "已领取"
        statusColor = { 100, 200, 120, 200 }
        statusBg    = { 40, 80, 50, 180 }
    elseif canClaim then
        cardBg      = { 60, 30, 10, 240 }
        borderColor = { 255, 160, 40, 220 }
        statusText  = "可领取"
        statusColor = { 255, 220, 80, 255 }
        statusBg    = { 200, 100, 30, 240 }
    else
        cardBg      = { 35, 28, 50, 200 }
        borderColor = { 70, 55, 90, 120 }
        statusText  = totalEarn .. "/" .. milestone.threshold
        statusColor = { 160, 150, 180, 200 }
        statusBg    = { 50, 40, 65, 180 }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = cardBg,
        borderRadius = 8,
        borderWidth = canClaim and 2 or 1,
        borderColor = borderColor,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        gap = 10,
        children = {
            -- 左侧：里程碑数字
            UI.Panel {
                width = 44, height = 44,
                borderRadius = 22,
                backgroundColor = claimed and { 50, 100, 60, 200 }
                    or canClaim and { 220, 100, 30, 240 }
                    or { 50, 40, 70, 200 },
                justifyContent = "center",
                alignItems = "center",
                borderWidth = 1,
                borderColor = claimed and { 100, 180, 120, 150 }
                    or canClaim and { 255, 200, 60, 200 }
                    or { 80, 65, 120, 150 },
                children = {
                    UI.Label {
                        text = claimed and "✓" or tostring(milestone.threshold),
                        fontSize = claimed and 18 or 13,
                        fontColor = { 255, 255, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 中间：奖励描述 + 进度条
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 4,
                children = {
                    UI.Label {
                        text = milestone.desc,
                        fontSize = 11,
                        fontColor = claimed and { 120, 110, 100, 180 } or { 220, 210, 200, 240 },
                    },
                    -- 小进度条
                    (not claimed) and UI.Panel {
                        width = "100%", height = 5,
                        backgroundColor = { 20, 10, 5, 200 },
                        borderRadius = 3,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = pct .. "%",
                                height = "100%",
                                backgroundColor = canClaim and { 255, 200, 60, 255 } or { 180, 120, 60, 200 },
                                borderRadius = 3,
                            },
                        },
                    } or nil,
                },
            },
            -- 右侧：状态
            UI.Panel {
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = statusBg,
                borderRadius = 6,
                children = {
                    UI.Label {
                        text = statusText,
                        fontSize = 11,
                        fontColor = statusColor,
                        fontWeight = canClaim and "bold" or "normal",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 兑换商店
-- ============================================================================

--- 商店面板引用，用于局部刷新
---@type UIElement|nil
local shopPanelRef = nil

--- 缓存的 ctx 引用，供局部刷新使用
local shopCtx = nil

--- 构建商店标题行
local function _BuildShopTitleRow(UI, balance)
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        width = "100%",
        marginBottom = 4,
        children = {
            UI.Label {
                text = "奖章兑换",
                fontSize = 14,
                fontColor = { 255, 200, 80, 255 },
                fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    Currency.IconWidget(UI, "labor_medal", 14),
                    UI.Label {
                        text = tostring(balance),
                        fontSize = 13,
                        fontColor = { 255, 200, 80, 255 },
                        fontWeight = "bold",
                    },
                },
            },
        },
    }
end

--- 局部刷新商店面板（不刷新整页）
local function _RefreshShop()
    if not shopPanelRef or not shopCtx then return end
    local UI = shopCtx.GetUI()
    local balance = Currency.Get("labor_medal")

    shopPanelRef:ClearChildren()
    shopPanelRef:AddChild(_BuildShopTitleRow(UI, balance))

    local grid = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 8,
    }
    for _, item in ipairs(LMD.SHOP_ITEMS) do
        grid:AddChild(LaborMedal._BuildShopCard(shopCtx, item, balance))
    end
    shopPanelRef:AddChild(grid)
end

--- 显示兑换确认弹窗（含数量选择）
local function _ShowConfirmDialog(ctx, item)
    if not confirmLayer then return end
    local UI = ctx.GetUI()

    local remaining = LMD.GetRemaining(item.id)
    local balance   = Currency.Get("labor_medal")
    local maxAfford = item.cost > 0 and math.floor(balance / item.cost) or 0
    local maxQty    = math.min(remaining, maxAfford)
    if maxQty < 1 then maxQty = 1 end

    local qty = 1

    -- 刷新弹窗内容的闭包引用
    local dialogContent = nil

    local function rebuildContent()
        if not dialogContent then return end
        dialogContent:ClearChildren()

        local totalCost = item.cost * qty
        local canConfirm = qty >= 1 and qty <= remaining and balance >= totalCost

        -- 商品名称
        dialogContent:AddChild(UI.Label {
            text = item.name,
            fontSize = 16,
            fontColor = { 255, 200, 80, 255 },
            fontWeight = "bold",
            textAlign = "center",
        })

        -- 单价显示
        dialogContent:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 4,
            marginTop = 4,
            children = {
                UI.Label {
                    text = "单价",
                    fontSize = 11,
                    fontColor = { 180, 160, 140, 200 },
                },
                Currency.IconWidget(UI, "labor_medal", 14),
                UI.Label {
                    text = tostring(item.cost),
                    fontSize = 13,
                    fontColor = { 255, 200, 80, 255 },
                    fontWeight = "bold",
                },
            },
        })

        -- 数量选择器
        dialogContent:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 12,
            marginTop = 12,
            children = {
                -- 减按钮
                UI.Panel {
                    width = 36, height = 36,
                    borderRadius = 18,
                    backgroundColor = qty > 1 and { 180, 80, 30, 240 } or { 60, 50, 55, 180 },
                    justifyContent = "center",
                    alignItems = "center",
                    pointerEvents = qty > 1 and "auto" or "none",
                    onClick = qty > 1 and function()
                        qty = qty - 1
                        rebuildContent()
                    end or nil,
                    children = {
                        UI.Label {
                            text = "−",
                            fontSize = 20,
                            fontColor = { 255, 255, 255, qty > 1 and 255 or 80 },
                            fontWeight = "bold",
                        },
                    },
                },
                -- 数量
                UI.Panel {
                    width = 60, height = 40,
                    backgroundColor = { 20, 10, 5, 200 },
                    borderRadius = 8,
                    borderWidth = 1,
                    borderColor = { 255, 160, 40, 150 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = tostring(qty),
                            fontSize = 20,
                            fontColor = { 255, 220, 100, 255 },
                            fontWeight = "bold",
                        },
                    },
                },
                -- 加按钮
                UI.Panel {
                    width = 36, height = 36,
                    borderRadius = 18,
                    backgroundColor = qty < maxQty and { 180, 80, 30, 240 } or { 60, 50, 55, 180 },
                    justifyContent = "center",
                    alignItems = "center",
                    pointerEvents = qty < maxQty and "auto" or "none",
                    onClick = qty < maxQty and function()
                        qty = qty + 1
                        rebuildContent()
                    end or nil,
                    children = {
                        UI.Label {
                            text = "+",
                            fontSize = 20,
                            fontColor = { 255, 255, 255, qty < maxQty and 255 or 80 },
                            fontWeight = "bold",
                        },
                    },
                },
            },
        })

        -- 剩余可兑换
        dialogContent:AddChild(UI.Label {
            text = "剩余可兑换 " .. remaining .. " 次",
            fontSize = 10,
            fontColor = { 160, 140, 120, 180 },
            textAlign = "center",
            marginTop = 4,
        })

        -- 总价
        dialogContent:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 6,
            marginTop = 10,
            paddingTop = 8,
            borderTopWidth = 1,
            borderTopColor = { 80, 60, 40, 120 },
            width = "100%",
            children = {
                UI.Label {
                    text = "合计",
                    fontSize = 13,
                    fontColor = { 200, 180, 150, 220 },
                },
                Currency.IconWidget(UI, "labor_medal", 16),
                UI.Label {
                    text = tostring(totalCost),
                    fontSize = 16,
                    fontColor = canConfirm and { 255, 200, 80, 255 } or { 255, 80, 80, 255 },
                    fontWeight = "bold",
                },
            },
        })

        -- 按钮行
        dialogContent:AddChild(UI.Panel {
            flexDirection = "row",
            justifyContent = "center",
            gap = 12,
            marginTop = 14,
            width = "100%",
            children = {
                -- 取消
                UI.Panel {
                    width = 90, height = 36,
                    backgroundColor = { 60, 50, 55, 220 },
                    borderRadius = 8,
                    justifyContent = "center",
                    alignItems = "center",
                    onClick = function()
                        confirmLayer:SetVisible(false)
                    end,
                    children = {
                        UI.Label {
                            text = "取消",
                            fontSize = 13,
                            fontColor = { 200, 190, 180, 220 },
                        },
                    },
                },
                -- 确认兑换
                UI.Panel {
                    width = 120, height = 36,
                    backgroundColor = canConfirm and { 220, 100, 30, 240 } or { 80, 60, 50, 180 },
                    borderRadius = 8,
                    justifyContent = "center",
                    alignItems = "center",
                    pointerEvents = canConfirm and "auto" or "none",
                    onClick = canConfirm and function()
                        confirmLayer:SetVisible(false)
                        local ok, msg, rewardDefs = LMD.Purchase(item.id, qty)
                        if ok then
                            _RefreshShop()
                            local WeeklyActivityUI = require("Game.WeeklyActivityUI")
                            RewardController.ShowFromDefs(
                                WeeklyActivityUI.GetUI(),
                                WeeklyActivityUI.GetPageRoot(),
                                rewardDefs,
                                "兑换成功",
                                nil
                            )
                        else
                            Toast.Show(msg, { 255, 80, 80 })
                        end
                    end or nil,
                    children = {
                        UI.Label {
                            text = "确认兑换",
                            fontSize = 13,
                            fontColor = { 255, 255, 255, canConfirm and 255 or 100 },
                            fontWeight = "bold",
                        },
                    },
                },
            },
        })
    end

    -- 构建弹窗
    confirmLayer:ClearChildren()

    -- 半透明遮罩
    local backdrop = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 160 },
        onClick = function()
            confirmLayer:SetVisible(false)
        end,
    }
    confirmLayer:AddChild(backdrop)

    -- 对话框
    local dialog = UI.Panel {
        width = 280,
        backgroundColor = { 45, 30, 20, 250 },
        borderRadius = 14,
        borderWidth = 2,
        borderColor = { 255, 160, 40, 200 },
        paddingTop = 20, paddingBottom = 18,
        paddingLeft = 20, paddingRight = 20,
        position = "absolute",
        alignSelf = "center",
        top = "30%",
        left = "50%",
        translateX = -140,
        alignItems = "center",
    }

    dialogContent = UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 0,
    }
    dialog:AddChild(dialogContent)
    confirmLayer:AddChild(dialog)

    rebuildContent()
    confirmLayer:SetVisible(true)
end

function LaborMedal.BuildShop(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    -- 缓存 ctx 供局部刷新使用
    shopCtx = ctx

    local balance = Currency.Get("labor_medal")
    local cards = {}
    for _, item in ipairs(LMD.SHOP_ITEMS) do
        cards[#cards + 1] = LaborMedal._BuildShopCard(ctx, item, balance)
    end

    -- 在 pageRoot 上创建 confirmLayer（全屏弹窗层）
    if not confirmLayer then
        local pageRoot = ctx.GetPageRoot and ctx.GetPageRoot() or nil
        if pageRoot then
            confirmLayer = UI.Panel {
                width = "100%", height = "100%",
                position = "absolute",
                top = 0, left = 0,
                justifyContent = "center",
                alignItems = "center",
                zIndex = 999,
                visible = false,
            }
            pageRoot:AddChild(confirmLayer)
        end
    end

    local panel = UI.Panel {
        width = "100%",
        gap = 4,
        children = {
            _BuildShopTitleRow(UI, balance),
            -- 商品网格（2列）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 8,
                children = cards,
            },
        },
    }
    shopPanelRef = panel
    return panel
end

function LaborMedal._BuildShopCard(ctx, item, balance)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local remaining  = LMD.GetRemaining(item.id)
    local canBuy     = remaining > 0 and balance >= item.cost and LMD.IsActive()
    local soldOut    = remaining <= 0

    local cardBg     = soldOut and { 30, 25, 20, 150 } or canBuy and { 50, 30, 15, 230 } or { 40, 30, 50, 200 }
    local borderCol  = canBuy and { 255, 160, 40, 180 } or { 70, 55, 90, 120 }

    return UI.Panel {
        width = "48%",
        backgroundColor = cardBg,
        borderRadius = 10,
        borderWidth = canBuy and 2 or 1,
        borderColor = borderCol,
        overflow = "hidden",
        children = {
            -- 上部：商品信息
            UI.Panel {
                width = "100%",
                paddingTop = 12, paddingBottom = 8,
                paddingLeft = 10, paddingRight = 10,
                gap = 6,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = item.name,
                        fontSize = 12,
                        fontColor = soldOut and { 120, 110, 100, 150 } or { 240, 230, 220, 255 },
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                    -- 限购标签
                    UI.Label {
                        text = soldOut and "已兑完" or ("剩余 " .. remaining .. "/" .. item.limit),
                        fontSize = 10,
                        fontColor = soldOut and { 150, 80, 80, 200 } or { 180, 160, 130, 180 },
                    },
                },
            },
            -- 下部：价格 + 兑换按钮
            UI.Panel {
                width = "100%",
                paddingTop = 6, paddingBottom = 10,
                paddingLeft = 10, paddingRight = 10,
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = "90%",
                        height = 34,
                        backgroundColor = canBuy and { 220, 100, 30, 240 } or { 50, 45, 55, 180 },
                        borderRadius = 8,
                        justifyContent = "center",
                        alignItems = "center",
                        flexDirection = "row",
                        gap = 4,
                        pointerEvents = canBuy and "auto" or "none",
                        onClick = canBuy and function()
                            _ShowConfirmDialog(ctx, item)
                        end or nil,
                        children = {
                            Currency.IconWidget(UI, "labor_medal", 14),
                            UI.Label {
                                text = tostring(item.cost),
                                fontSize = 13,
                                fontColor = canBuy and { 255, 255, 255, 255 } or { 120, 110, 130, 180 },
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
        },
    }
end

return LaborMedal
