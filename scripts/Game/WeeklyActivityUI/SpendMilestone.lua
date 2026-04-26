-- Game/WeeklyActivityUI/SpendMilestone.lua
-- 消费达标：横幅 + 里程碑卡片列表（累积消费暗影精粹）

local SMD           = require("Game.SpendMilestoneData")
local RewardIconMod = require("Game.RewardIcon")

local SpendMilestone = {}

-- ============================================================================
-- 消费说明横幅
-- ============================================================================

function SpendMilestone.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local round   = SMD.GetRound()
    local count   = SMD.GetRoundCount()
    local allDone = round > SMD.MAX_ROUNDS

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
                backgroundColor = { 180, 100, 255, 255 },
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
                                text = "消费达标奖励",
                                fontSize = 16, fontColor = { 200, 160, 255, 255 }, fontWeight = "bold",
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "i", fontSize = 11, fontColor = S.accent, fontWeight = "bold" },
                            UI.Label {
                                text = "消费暗影精粹累积数量，达标自动发送奖励到邮件",
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
                                        text = allDone and "已完成" or (round .. "/" .. SMD.MAX_ROUNDS),
                                        fontSize = 14, fontColor = { 180, 140, 255, 255 }, fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                text = allDone and "全部轮次已完成" or ("本轮: " .. count .. "/" .. SMD.ROUND_MAX),
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

function SpendMilestone.BuildList(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local count   = SMD.GetRoundCount()
    local allDone = SMD.GetRound() > SMD.MAX_ROUNDS
    local container = UI.Panel { width = "100%", gap = 8 }
    for i, m in ipairs(SMD.MILESTONES) do
        container:AddChild(SpendMilestone._BuildCard(UI, S, i, m, count, allDone))
    end
    return container
end

function SpendMilestone._BuildCard(UI, S, index, milestone, count, allDone)
    local _, claimed, reached
    if allDone then
        claimed, reached = true, true
    else
        _, claimed, reached = SMD.GetMilestoneStatus(index)
    end
    local pct = allDone and 1 or math.min(1, count / milestone.threshold)

    local statusText, statusColor
    if claimed then
        statusText  = "已发放"
        statusColor = S.textDim
    elseif reached then
        statusText  = "已达成"
        statusColor = S.textGreen
    else
        statusText  = math.min(count, milestone.threshold) .. "/" .. milestone.threshold
        statusColor = S.textDim
    end

    local rewardIcons = UI.Panel { flexDirection = "row", gap = 4, pointerEvents = "auto" }
    for _, reward in ipairs(milestone.rewards) do
        local iconId = reward.id
        if reward.type == "chest" then iconId = reward.id .. "_chest" end
        local icon = RewardIconMod.Create(UI, 38, iconId, reward.amount, { muted = claimed })
        rewardIcons:AddChild(icon)
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = claimed and { 60, 60, 60, 100 } or (reached and { 180, 100, 255, 200 } or S.border),
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
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = milestone.threshold,
                                fontSize = 14,
                                fontColor = claimed and S.textDim or { 200, 160, 255, 255 },
                                fontWeight = "bold",
                            },
                            UI.Label { text = statusText, fontSize = 11, fontColor = statusColor },
                        },
                    },
                    UI.Panel {
                        width = "100%", height = 6,
                        backgroundColor = S.barBg,
                        borderRadius = 3,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(pct * 100) .. "%",
                                height = "100%",
                                backgroundColor = claimed and { 80, 80, 80, 200 } or { 180, 100, 255, 255 },
                                borderRadius = 3,
                            },
                        },
                    },
                },
            },
            UI.Panel { width = 1, height = "80%", backgroundColor = { 80, 65, 120, 80 }, flexShrink = 0 },
            UI.ScrollView {
                flexGrow = 1, flexShrink = 1,
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

return SpendMilestone
