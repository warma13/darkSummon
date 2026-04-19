-- Game/ActivityUI_DailyTask.lua
-- 活动系统 - 每日任务子页面
-- 工厂模式：return function(ctx, Shared) ... return Mod end

return function(ctx, Shared)

local DailyTaskData = require("Game.DailyTaskData")
local TaskCard      = require("Game.TaskCard")
local Toast         = require("Game.Toast")
local Config        = require("Game.Config")

local S = Shared.S

local Mod = {}

--- 构建内容区域
---@return table children
function Mod.BuildContent()
    DailyTaskData.EnsureData()

    local children = {}

    -- 完成度摘要
    local completed, total = DailyTaskData.GetCompletedCount()
    children[#children + 1] = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 12, paddingBottom = 6,
        children = {
            ctx.UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    ctx.UI.Label {
                        text = "| 每日任务",
                        fontSize = 16,
                        fontColor = { 255, 220, 100, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel {
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 2, paddingBottom = 2,
                        backgroundColor = completed >= total
                            and { 60, 120, 60, 200 }
                            or { 60, 40, 90, 200 },
                        borderRadius = 8,
                        children = {
                            ctx.UI.Label {
                                text = completed .. "/" .. total,
                                fontSize = 11,
                                fontColor = completed >= total
                                    and { 100, 220, 120, 255 }
                                    or { 180, 160, 220, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
            ctx.UI.Label {
                text = "00:00 重置",
                fontSize = 10,
                fontColor = S.textMuted or { 120, 110, 140, 160 },
            },
        },
    }

    -- 任务卡列表
    local taskListChildren = {}
    for _, taskDef in ipairs(DailyTaskData.DAILY_TASKS) do
        local current, target, claimed = DailyTaskData.GetTaskProgress(taskDef.id)
        local taskId = taskDef.id

        -- 获取奖励显示文本
        local reward = taskDef.rewards[1]
        local currDef = Config.CURRENCY[reward.id]
        local rewardName = currDef and currDef.name or reward.id
        local rewardColor = currDef and currDef.color or { 200, 200, 200 }

        taskListChildren[#taskListChildren + 1] = TaskCard.Create(ctx.UI, {
            desc = taskDef.desc,
            current = current,
            target = target,
            claimed = claimed,
            rewardLabel = rewardName,
            rewardValue = "x" .. reward.amount,
            rewardColor = rewardColor,
            onClaim = function()
                local ok, msg = DailyTaskData.ClaimTask(taskId)
                Toast.Show(msg, ok and { 100, 220, 120, 255 } or { 255, 80, 80, 255 })
                if ok and ctx.RefreshContent then
                    ctx.RefreshContent()
                end
            end,
        })
    end

    children[#children + 1] = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingBottom = 12,
        gap = 8,
        children = taskListChildren,
    }

    return children
end

return Mod

end
