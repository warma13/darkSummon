-- Game/WeeklyActivityUI/RecruitMilestone.lua
-- 招募达标：横幅 + 里程碑卡片列表（招募周专用）

local RMD           = require("Game.RecruitMilestoneData")
local RewardIconMod = require("Game.RewardIcon")

local RecruitMilestone = {}

-- ============================================================================
-- 招募说明横幅
-- ============================================================================

function RecruitMilestone.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local round   = RMD.GetRound()
    local count   = RMD.GetRoundCount()
    local allDone = round > RMD.MAX_ROUNDS

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
                backgroundColor = { 140, 80, 255, 255 },
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
                                text = "招募达标奖励",
                                fontSize = 16, fontColor = { 200, 160, 255, 255 }, fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                backgroundColor = { 80, 40, 160, 220 },
                                borderRadius = 10,
                                pointerEvents = "auto",
                                onClick = function()
                                    local GameUI = require("Game.GameUI")
                                    GameUI.ShowWeeklyActivityOverlay(false)
                                    GameUI.ShowRecruitOverlay(true)
                                end,
                                children = {
                                    UI.Label {
                                        text = "去招募",
                                        fontSize = 11, fontColor = S.textWhite, fontWeight = "bold",
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
                                text = "使用招募券召唤英雄累积次数，达标自动发送奖励到邮件",
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
                                        text = allDone and "已完成" or (round .. "/" .. RMD.MAX_ROUNDS),
                                        fontSize = 14, fontColor = { 180, 140, 255, 255 }, fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                text = allDone and "全部轮次已完成" or ("本轮: " .. count .. "/" .. RMD.ROUND_MAX .. " 次"),
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

function RecruitMilestone.BuildList(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local count   = RMD.GetRoundCount()
    local allDone = RMD.GetRound() > RMD.MAX_ROUNDS
    local container = UI.Panel { width = "100%", gap = 8 }
    for i, m in ipairs(RMD.MILESTONES) do
        container:AddChild(RecruitMilestone._BuildCard(UI, S, i, m, count, allDone))
    end
    return container
end

function RecruitMilestone._BuildCard(UI, S, index, milestone, count, allDone)
    local _, claimed, reached
    if allDone then
        claimed, reached = true, true
    else
        _, claimed, reached = RMD.GetMilestoneStatus(index)
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
        borderColor = claimed and { 60, 60, 60, 100 } or (reached and { 140, 80, 255, 200 } or S.border),
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
                                text = milestone.threshold .. "次",
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
                                backgroundColor = claimed and { 80, 80, 80, 200 } or { 140, 80, 255, 255 },
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

return RecruitMilestone
