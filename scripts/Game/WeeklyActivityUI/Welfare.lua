-- Game/WeeklyActivityUI/Welfare.lua
-- 限时福利：每日广告奖励 + 周进度里程碑（宝箱周 / 招募周 共用）

local WAD           = require("Game.WeeklyActivityData")
local WelfareData   = require("Game.WelfareData")
local Toast         = require("Game.Toast")
local RewardIconMod = require("Game.RewardIcon")
local Config        = require("Game.Config")
local RewardDisplay = require("Game.RewardDisplay")

local Welfare = {}

-- ============================================================================
-- 入口：根据周类型分发
-- ============================================================================

function Welfare.Build(ctx)
    if WAD.GetCurrentWeekType() == "recruit" then
        return Welfare._BuildRecruitContent(ctx)
    end

    local UI = ctx.GetUI()
    local container = UI.Panel { width = "100%", gap = 10 }
    container:AddChild(Welfare._BuildWelfareBanner(ctx))
    container:AddChild(Welfare._BuildDailyAdList(ctx))
    container:AddChild(Welfare._BuildWeeklyAdProgress(ctx))
    return container
end

-- ============================================================================
-- 招募周福利
-- ============================================================================

function Welfare._BuildRecruitContent(ctx)
    local UI = ctx.GetUI()
    local container = UI.Panel { width = "100%", gap = 10 }
    container:AddChild(Welfare._BuildRecruitWelfareBanner(ctx))
    container:AddChild(Welfare._BuildRecruitDailyAdList(ctx))
    container:AddChild(Welfare._BuildWeeklyAdProgress(ctx))
    return container
end

function Welfare._BuildRecruitWelfareBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local dailyCount = WelfareData.GetDailyAdCount()
    local maxCount   = WelfareData.MAX_RECRUIT_DAILY

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        overflow = "hidden",
        children = {
            UI.Panel { width = "100%", height = 3, backgroundColor = { 140, 80, 255, 255 } },
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
                                text = "免费领招募券自选包",
                                fontSize = 16, fontColor = { 200, 160, 255, 255 }, fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                backgroundColor = { 60, 40, 90, 200 },
                                borderRadius = 10,
                                children = {
                                    UI.Label {
                                        text = "今日 " .. dailyCount .. "/" .. maxCount,
                                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "i", fontSize = 11, fontColor = S.accent, fontWeight = "bold" },
                            UI.Label {
                                text = "招募券自选包可在仓库使用，选择招募池获得对应招募券",
                                fontSize = 11, fontColor = S.textDim,
                            },
                        },
                    },
                },
            },
        },
    }
end

function Welfare._BuildRecruitDailyAdList(ctx)
    local UI = ctx.GetUI()
    local container = UI.Panel { width = "100%", gap = 6 }
    for i, reward in ipairs(WelfareData.RECRUIT_DAILY_REWARDS) do
        container:AddChild(Welfare._BuildRecruitDailyAdCard(ctx, i, reward))
    end
    return container
end

function Welfare._BuildRecruitDailyAdCard(ctx, index, reward)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local claimed  = WelfareData.IsDailyClaimed(index)
    local unlocked = WelfareData.IsDailyUnlocked(index)
    local ticketColor = { 180, 130, 255, 255 }

    return UI.Panel {
        width = "100%",
        backgroundColor = claimed and { 25, 22, 35, 180 } or S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = (unlocked and not claimed) and { 140, 80, 255, 180 } or { 60, 50, 80, 100 },
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
                backgroundColor = (unlocked and not claimed) and { 140, 80, 255, 60 } or { 50, 40, 70, 150 },
                justifyContent = "center",
                alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = tostring(index),
                        fontSize = 13,
                        fontColor = (unlocked and not claimed) and ticketColor or S.textDim,
                        fontWeight = "bold",
                    },
                },
            },
            -- 券图标 + 描述
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                marginLeft = 8, marginRight = 8,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Panel {
                        width = 36, height = 36, flexShrink = 0,
                        justifyContent = "center", alignItems = "center",
                        backgroundColor = { 80, 40, 150, 120 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 140, 80, 255, 120 },
                        backgroundImage = "image/icon_recruit_ticket_select_box.png",
                        backgroundFit = "contain",
                        backgroundPosition = "center",
                        children = {},
                    },
                    UI.Panel {
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "招募券自选包 ×" .. reward.ticketAmount,
                                fontSize = 13,
                                fontColor = claimed and S.textDim or ticketColor,
                                fontWeight = "bold",
                            },
                            reward.free and UI.Label {
                                text = "免费领取",
                                fontSize = 10, fontColor = { 80, 200, 120, 200 },
                            } or UI.Label {
                                text = "观看广告解锁",
                                fontSize = 10, fontColor = S.textDim,
                            },
                        },
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
                        backgroundColor = isFree and { 60, 170, 90, 255 } or { 80, 40, 160, 255 },
                        borderWidth = 1,
                        borderColor = isFree and { 100, 220, 140, 200 } or { 160, 100, 255, 200 },
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            WelfareData.ClaimDailyReward(index, function(success, errMsg)
                                if success then
                                    ctx.Refresh()
                                    RewardDisplay.Show(ctx.GetUI(), ctx.GetPageRoot(), {
                                        title = isFree and "免费招募券自选包" or "广告招募券自选包",
                                        rewards = {
                                            {
                                                icon = "recruit_ticket_select_box",
                                                name = "招募券自选包",
                                                amount = reward.ticketAmount,
                                                borderColor = { 140, 80, 255 },
                                            },
                                        },
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
-- 宝箱周福利
-- ============================================================================

function Welfare._BuildWelfareBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local dailyCount = WelfareData.GetDailyAdCount()

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = "100%", height = 3,
                backgroundColor = { 80, 200, 120, 255 },
            },
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
                                text = "免费领宝箱",
                                fontSize = 16, fontColor = S.textTitle, fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                backgroundColor = { 60, 40, 90, 200 },
                                borderRadius = 10,
                                children = {
                                    UI.Label {
                                        text = "今日 " .. dailyCount .. "/" .. WelfareData.MAX_DAILY_ADS,
                                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = "i",
                                fontSize = 11, fontColor = S.accent, fontWeight = "bold",
                            },
                            UI.Label {
                                text = "每天领免费宝箱，解锁前一个可领取下一个（每日重置）",
                                fontSize = 11, fontColor = S.textDim,
                            },
                        },
                    },
                },
            },
        },
    }
end

function Welfare._BuildDailyAdList(ctx)
    local UI = ctx.GetUI()
    local container = UI.Panel { width = "100%", gap = 6 }
    for i, reward in ipairs(WelfareData.DAILY_AD_REWARDS) do
        container:AddChild(Welfare._BuildDailyAdCard(ctx, i, reward))
    end
    return container
end

function Welfare._BuildDailyAdCard(ctx, index, reward)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local claimed  = WelfareData.IsDailyClaimed(index)
    local unlocked = WelfareData.IsDailyUnlocked(index)
    local chestInfo = Config.CHEST_TYPES_MAP[reward.chestId]

    local chestColor  = chestInfo and chestInfo.color or { 200, 200, 200 }
    local chestBorder = chestInfo and chestInfo.borderColor or S.border

    return UI.Panel {
        width = "100%",
        backgroundColor = claimed and { 25, 22, 35, 180 } or S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = (unlocked and not claimed) and chestBorder or { 60, 50, 80, 100 },
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
                backgroundColor = (unlocked and not claimed) and { chestColor[1], chestColor[2], chestColor[3], 80 } or { 50, 40, 70, 150 },
                justifyContent = "center",
                alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = tostring(index),
                        fontSize = 13,
                        fontColor = (unlocked and not claimed) and chestColor or S.textDim,
                        fontWeight = "bold",
                    },
                },
            },
            -- 宝箱图标 + 描述
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                marginLeft = 8, marginRight = 8,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Panel {
                        width = 36, height = 36,
                        flexShrink = 0,
                        children = {
                            chestInfo and chestInfo.image and UI.Panel {
                                width = 36, height = 36,
                                backgroundImage = chestInfo.image,
                                backgroundFit = "contain",
                            } or UI.Label {
                                text = chestInfo and chestInfo.emoji or "📦",
                                fontSize = 24,
                            },
                        },
                    },
                    UI.Panel {
                        gap = 2,
                        children = {
                            UI.Label {
                                text = (chestInfo and chestInfo.name or reward.chestId) .. " ×" .. reward.amount,
                                fontSize = 13,
                                fontColor = claimed and S.textDim or chestColor,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "积分 +" .. (chestInfo and chestInfo.score or 0) * reward.amount,
                                fontSize = 10,
                                fontColor = S.textDim,
                            },
                        },
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
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
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
                        backgroundColor = isFree and { 60, 170, 90, 255 } or { 100, 70, 180, 255 },
                        borderWidth = 1,
                        borderColor = isFree and { 100, 220, 140, 200 } or { 180, 140, 255, 200 },
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            WelfareData.ClaimDailyReward(index, function(success, errMsg)
                                if success then
                                    ctx.Refresh()
                                    local chestName = chestInfo and chestInfo.name or reward.chestId
                                    local chestIcon = chestInfo and chestInfo.image or nil
                                    local rewardItems = {
                                        {
                                            icon = chestIcon or "📦",
                                            name = chestName,
                                            amount = reward.amount,
                                            borderColor = chestColor,
                                        },
                                    }
                                    RewardDisplay.Show(ctx.GetUI(), ctx.GetPageRoot(), {
                                        title = isFree and "免费奖励" or "广告奖励",
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
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
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
-- 每周广告进度里程碑（宝箱周 / 招募周共用）
-- ============================================================================

function Welfare._BuildWeeklyAdProgress(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local totalAds   = WelfareData.GetWeeklyAdTotal()
    local milestones = WelfareData.WEEKLY_MILESTONES
    local maxAds     = milestones[#milestones].threshold
    local ICON_SZ    = 24
    local CELL_SZ    = ICON_SZ + 12  -- 36
    local barH       = 6
    local pct        = maxAds > 0 and math.min(1, totalAds / maxAds) or 0

    -- 全部领取状态
    local anyCanClaim = false
    for i, m in ipairs(milestones) do
        if WelfareData.IsWeeklyClaimable(i) then
            anyCanClaim = true
            break
        end
    end

    -- 横向奖励图标行
    local iconRow = {}
    for i, m in ipairs(milestones) do
        local claimed   = WelfareData.IsWeeklyClaimed(i)
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

    -- 2:6:2 三列布局
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
                    UI.Label {
                        text = "广告",
                        fontSize = 11, fontColor = S.textDim,
                    },
                    UI.Label {
                        text = tostring(totalAds),
                        fontSize = 22, fontColor = S.textGold, fontWeight = "bold",
                    },
                },
            },
            -- 中列：图标 + 进度条 + 阈值
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
                                local ok = WelfareData.ClaimWeeklyMilestone(idx)
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

return Welfare
