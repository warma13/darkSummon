-- Game/WeeklyActivityUI/LaborDay.lua
-- 劳动节限时签到活动 UI 子模块

local LDD = require("Game.LaborDayData")

local LaborDay = {}

-- ============================================================================
-- 顶部横幅
-- ============================================================================

function LaborDay.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local signedCount = LDD.GetSignedCount()
    local remaining   = LDD.GetRemainingTimeStr()
    local isActive    = LDD.IsActive()

    return UI.Panel {
        width = "100%",
        backgroundColor = { 40, 20, 20, 230 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 220, 60, 60, 150 },
        overflow = "hidden",
        children = {
            -- 活动配图
            UI.Panel {
                width = "100%", height = 120,
                backgroundImage = "image/banner_labor_day_signin_20260430095907.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                borderTopLeftRadius = 10,
                borderTopRightRadius = 10,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 12, paddingBottom = 12,
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
                            UI.Panel {
                                gap = 2,
                                children = {
                                    UI.Label {
                                        text = "🎉 劳动节签到",
                                        fontSize = 16, fontColor = { 255, 220, 100, 255 }, fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "每天登录签到，连续7天拿大奖！",
                                        fontSize = 10, fontColor = { 200, 180, 160, 200 },
                                    },
                                },
                            },
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                backgroundColor = { 60, 20, 20, 200 },
                                borderRadius = 10,
                                children = {
                                    UI.Label {
                                        text = isActive and ("剩余: " .. remaining) or "已结束",
                                        fontSize = 11, fontColor = { 255, 120, 80, 255 }, fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 进度条
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1,
                                height = 8,
                                backgroundColor = { 30, 15, 15, 200 },
                                borderRadius = 4,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = math.floor(signedCount / LDD.TOTAL_DAYS * 100) .. "%",
                                        height = "100%",
                                        backgroundColor = { 220, 80, 60, 255 },
                                        borderRadius = 4,
                                    },
                                },
                            },
                            UI.Label {
                                text = signedCount .. "/" .. LDD.TOTAL_DAYS,
                                fontSize = 12, fontColor = { 255, 200, 100, 255 }, fontWeight = "bold",
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 签到按钮
-- ============================================================================

function LaborDay.BuildSignButton(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local canSign    = LDD.IsActive() and not LDD.HasSignedToday()
    local hasSigned  = LDD.HasSignedToday()

    local btnText    = hasSigned and "今日已签到 ✓" or (LDD.IsActive() and "立即签到" or "活动已结束")
    local btnBg      = canSign and { 220, 80, 60, 255 } or { 60, 50, 50, 200 }
    local btnColor   = canSign and { 255, 255, 255, 255 } or { 140, 130, 130, 200 }

    return UI.Panel {
        width = "100%",
        paddingTop = 6, paddingBottom = 6,
        alignItems = "center",
        children = {
            UI.Panel {
                width = "80%",
                height = 44,
                backgroundColor = btnBg,
                borderRadius = 10,
                borderWidth = canSign and 1 or 0,
                borderColor = { 255, 120, 80, 200 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onClick = canSign and function()
                    if LDD.SignIn() then
                        -- 刷新页面
                        local WeeklyActivityUI = require("Game.WeeklyActivityUI")
                        WeeklyActivityUI.Refresh()
                    end
                end or nil,
                children = {
                    UI.Label {
                        text = btnText,
                        fontSize = 16, fontColor = btnColor, fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 签到日历列表（7天）
-- ============================================================================

function LaborDay.BuildList(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local cards = {}
    for i = 1, LDD.TOTAL_DAYS do
        cards[#cards + 1] = LaborDay._BuildDayCard(ctx, i)
    end

    return UI.Panel {
        width = "100%",
        gap = 8,
        children = cards,
    }
end

--- 单天签到卡片
function LaborDay._BuildDayCard(ctx, dayIndex)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local reward = LDD.REWARDS[dayIndex]
    if not reward then return UI.Panel {} end

    local status = LDD.GetDayStatus(dayIndex)
    local isFinal = (dayIndex == LDD.TOTAL_DAYS)

    -- 样式
    local cardBg, borderColor, labelColor, statusText, statusColor

    if status == "claimed" then
        cardBg      = { 35, 30, 30, 180 }
        borderColor = { 60, 55, 55, 100 }
        labelColor  = { 120, 110, 110, 180 }
        statusText  = "已领取"
        statusColor = { 100, 200, 120, 200 }
    elseif status == "available" then
        cardBg      = isFinal and { 60, 25, 25, 240 } or { 50, 25, 20, 230 }
        borderColor = { 255, 120, 60, 200 }
        labelColor  = { 255, 240, 220, 255 }
        statusText  = "可领取"
        statusColor = { 255, 200, 60, 255 }
    elseif status == "missed" then
        cardBg      = { 30, 25, 25, 150 }
        borderColor = { 50, 45, 45, 100 }
        labelColor  = { 100, 90, 90, 150 }
        statusText  = "已过期"
        statusColor = { 150, 80, 80, 200 }
    else -- locked
        cardBg      = { 35, 28, 50, 200 }
        borderColor = { 70, 55, 90, 120 }
        labelColor  = { 180, 170, 200, 220 }
        statusText  = "第" .. dayIndex .. "天"
        statusColor = S.textDim
    end

    local dayLabel = isFinal and ("第" .. dayIndex .. "天 🎁 终极大奖") or ("第" .. dayIndex .. "天")

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = cardBg,
        borderRadius = 10,
        borderWidth = (status == "available") and 2 or 1,
        borderColor = borderColor,
        paddingTop = 12, paddingBottom = 12,
        paddingLeft = 14, paddingRight = 14,
        gap = 10,
        children = {
            -- 左侧：天数标签
            UI.Panel {
                width = 50,
                height = 50,
                borderRadius = 25,
                backgroundColor = (status == "claimed") and { 50, 120, 60, 200 }
                    or (status == "available") and { 220, 80, 60, 240 }
                    or { 50, 40, 70, 200 },
                justifyContent = "center",
                alignItems = "center",
                borderWidth = isFinal and 2 or 0,
                borderColor = { 255, 200, 60, 200 },
                children = {
                    UI.Label {
                        text = (status == "claimed") and "✓" or tostring(dayIndex),
                        fontSize = (status == "claimed") and 20 or 18,
                        fontColor = { 255, 255, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 中间：奖励信息
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 3,
                children = {
                    UI.Label {
                        text = dayLabel,
                        fontSize = 13,
                        fontColor = (status == "available") and { 255, 200, 60, 255 } or labelColor,
                        fontWeight = (isFinal or status == "available") and "bold" or "normal",
                    },
                    UI.Label {
                        text = reward.label,
                        fontSize = 12,
                        fontColor = labelColor,
                    },
                },
            },
            -- 右侧：状态
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                backgroundColor = (status == "claimed") and { 40, 90, 50, 180 }
                    or (status == "available") and { 200, 80, 40, 240 }
                    or { 40, 35, 55, 150 },
                borderRadius = 6,
                children = {
                    UI.Label {
                        text = statusText,
                        fontSize = 12,
                        fontColor = statusColor,
                        fontWeight = (status == "available") and "bold" or "normal",
                    },
                },
            },
        },
    }
end

return LaborDay
