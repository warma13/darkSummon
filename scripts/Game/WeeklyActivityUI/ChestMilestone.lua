-- Game/WeeklyActivityUI/ChestMilestone.lua
-- 宝箱达标：横幅 + 里程碑卡片列表

local WAD           = require("Game.WeeklyActivityData")
local RewardIconMod = require("Game.RewardIcon")

local ChestMilestone = {}

-- ============================================================================
-- 活动说明横幅
-- ============================================================================

function ChestMilestone.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local round   = WAD.GetRound()
    local score   = WAD.GetRoundScore()
    local allDone = round > WAD.MAX_ROUNDS

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
                backgroundColor = S.tabActive,
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
                                text = "宝箱达标奖励",
                                fontSize = 16, fontColor = S.textTitle, fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                backgroundColor = { 160, 100, 40, 220 },
                                borderRadius = 10,
                                pointerEvents = "auto",
                                onClick = function(self)
                                    local TabNav = require("Game.TabNav")
                                    TabNav.SwitchTo("chest")
                                    local GameUI = require("Game.GameUI")
                                    GameUI.ShowWeeklyActivityOverlay(false)
                                end,
                                children = {
                                    UI.Label {
                                        text = "前往宝箱",
                                        fontSize = 11, fontColor = S.textWhite, fontWeight = "bold",
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
                                text = "开启宝箱累积积分，达标领取丰厚奖励",
                                fontSize = 11, fontColor = S.textDim,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        width = "100%",
                        marginTop = 2,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    UI.Label {
                                        text = "当前轮数",
                                        fontSize = 12, fontColor = S.textNormal,
                                    },
                                    UI.Label {
                                        id = "waRoundLabel",
                                        text = round <= WAD.MAX_ROUNDS and (round .. "/" .. WAD.MAX_ROUNDS) or "已完成",
                                        fontSize = 14, fontColor = S.textGold, fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                text = allDone and "全部轮次已完成" or ("累计积分: " .. score),
                                fontSize = 12,
                                fontColor = allDone and S.textGreen or S.textDim,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 里程碑列表
-- ============================================================================

function ChestMilestone.BuildList(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local score   = WAD.GetRoundScore()
    local allDone = WAD.GetRound() > WAD.MAX_ROUNDS
    local container = UI.Panel { width = "100%", gap = 8 }

    for i, m in ipairs(WAD.MILESTONES) do
        container:AddChild(ChestMilestone._BuildCard(UI, S, i, m, score, allDone))
    end

    return container
end

function ChestMilestone._BuildCard(UI, S, index, milestone, score, allDone)
    local _, claimed, reached
    if allDone then
        claimed, reached = true, true
    else
        _, claimed, reached = WAD.GetMilestoneStatus(index)
    end
    local pct = allDone and 1 or math.min(1, score / milestone.threshold)

    local statusText, statusColor
    if allDone then
        statusText = "已完成"
        statusColor = S.textGreen
    elseif claimed then
        statusText = "已发放"
        statusColor = S.textDim
    elseif reached then
        statusText = "已达成"
        statusColor = S.textGreen
    else
        statusText = math.min(score, milestone.threshold) .. "/" .. milestone.threshold
        statusColor = S.textDim
    end

    local rewardIcons = UI.Panel {
        flexDirection = "row",
        gap = 4,
        pointerEvents = "auto",
    }
    for _, reward in ipairs(milestone.rewards) do
        local iconId = reward.id
        if reward.type == "chest" then
            iconId = reward.id .. "_chest"
        end
        local icon = RewardIconMod.Create(UI, 38, iconId, reward.amount, {
            muted = claimed,
        })
        rewardIcons:AddChild(icon)
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = claimed and { 60, 60, 60, 100 } or (reached and S.borderGold or S.border),
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 0,
        flexDirection = "row",
        alignItems = "center",
        opacity = claimed and 0.6 or 1.0,
        children = {
            UI.Panel {
                width = "58%",
                flexShrink = 0,
                gap = 4,
                paddingRight = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = milestone.threshold .. "积分",
                                fontSize = 14, fontColor = claimed and S.textDim or S.textTitle,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = statusText,
                                fontSize = 11, fontColor = statusColor,
                            },
                        },
                    },
                    allDone and UI.Label {
                        text = "全部奖励已发放",
                        fontSize = 10,
                        fontColor = S.textGreen,
                    } or UI.Panel {
                        width = "100%", height = 6,
                        backgroundColor = S.barBg,
                        borderRadius = 3,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(pct * 100) .. "%",
                                height = "100%",
                                backgroundColor = claimed and { 80, 80, 80, 200 } or S.barFill,
                                borderRadius = 3,
                            },
                        },
                    },
                },
            },
            UI.Panel {
                width = 1, height = "80%",
                backgroundColor = { 80, 65, 120, 80 },
                flexShrink = 0,
            },
            UI.ScrollView {
                flexGrow = 1,
                flexShrink = 1,
                height = 50,
                scrollDirection = "horizontal",
                paddingLeft = 6, paddingRight = 6,
                flexDirection = "row",
                alignItems = "center",
                children = { rewardIcons },
            },
        },
    }
end

return ChestMilestone
