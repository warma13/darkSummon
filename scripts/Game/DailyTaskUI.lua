-- Game/DailyTaskUI.lua
-- 每日任务 UI（独立全屏页面，参考 LaunchGiftUI 布局）

local DailyTaskData  = require("Game.DailyTaskData")
local Toast          = require("Game.Toast")
local Tooltip        = require("Game.Tooltip")
local RewardIconMod  = require("Game.RewardIcon")
local TaskCard       = require("Game.TaskCard")

local DailyTaskUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

-- 样式常量（复用暗黑风格）
local S = {
    bgPage     = { 12, 10, 25, 250 },
    bgSection  = { 25, 20, 45, 230 },
    bgCard     = { 30, 24, 50, 220 },
    bgDone     = { 30, 40, 30, 200 },
    bgBar      = { 40, 30, 60, 200 },
    border     = { 80, 65, 120, 150 },
    borderGold = { 220, 180, 60, 200 },
    textTitle  = { 255, 220, 100, 255 },
    textWhite  = { 240, 235, 255, 255 },
    textNormal = { 220, 210, 240, 255 },
    textDim    = { 150, 140, 170, 200 },
    textGreen  = { 100, 220, 120, 255 },
    textGold   = { 255, 200, 60, 255 },
    accent     = { 180, 120, 255, 255 },
    barFill    = { 160, 100, 240, 255 },
    barGreen   = { 80, 180, 80, 255 },
    red        = { 255, 80, 80, 255 },
}

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 创建全屏页面内容（不含返回键和 overlay 壳，由 GameUI 包装）
function DailyTaskUI.CreatePage(uiModule)
    UI = uiModule
    pageRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = S.bgPage,
        children = {
            -- 顶部标题栏
            DailyTaskUI._BuildHeader(),
            -- 可滚动内容区
            UI.ScrollView {
                id = "dtContentArea",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                padding = 12,
                gap = 12,
            },
        },
    }
    -- 初始化 Tooltip 浮窗层
    Tooltip.Init(UI, pageRoot)
    return pageRoot
end

--- 刷新内容
function DailyTaskUI.Refresh()
    if not pageRoot then return end
    local area = pageRoot:FindById("dtContentArea")
    if not area then return end
    area:ClearChildren()

    DailyTaskData.EnsureData()

    -- 1) 积分里程碑区
    area:AddChild(DailyTaskUI._BuildMilestoneSection())
    -- 2) 每日任务列表
    area:AddChild(DailyTaskUI._BuildDailyTasks())
end

-- ============================================================================
-- 顶部标题栏
-- ============================================================================

function DailyTaskUI._BuildHeader()
    local completed, total = DailyTaskData.GetCompletedCount()
    return UI.Panel {
        width = "100%",
        paddingTop = 14, paddingBottom = 10,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = { 30, 22, 50, 240 },
        borderBottomWidth = 1,
        borderColor = { 100, 80, 160, 80 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            -- 左侧标题
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Panel {
                        width = 28, height = 28,
                        backgroundImage = "image/icon_dailytask.png",
                        backgroundFit = "contain",
                    },
                    UI.Panel {
                        gap = 1,
                        children = {
                            UI.Label {
                                text = "每日任务",
                                fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                            },
                            UI.Label {
                                text = "完成任务获取积分 兑换丰厚奖励",
                                fontSize = 10, fontColor = S.textDim,
                            },
                        },
                    },
                },
            },
            -- 右侧完成度
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = completed >= total
                    and { 50, 90, 50, 200 }
                    or  { 60, 40, 90, 200 },
                borderRadius = 10,
                children = {
                    UI.Label {
                        id = "dtCompletionLabel",
                        text = "已完成 " .. completed .. "/" .. total,
                        fontSize = 12,
                        fontColor = completed >= total
                            and S.textGreen
                            or  S.accent,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 积分里程碑区（与 LaunchGiftUI 一致的 2:6:2 三列布局）
-- ============================================================================

function DailyTaskUI._BuildMilestoneSection()
    local totalPts = DailyTaskData.GetTotalPoints()
    local milestones = DailyTaskData.MILESTONES
    local maxThr = milestones[#milestones].threshold
    local ICON_SZ = 24
    local CELL_SZ = ICON_SZ + 12  -- 36

    -- 全部领取状态
    local anyCanClaim = false
    for i = 1, #milestones do
        local canClaim = DailyTaskData.GetMilestoneStatus(i)
        if canClaim then anyCanClaim = true; break end
    end

    -- 横向奖励图标行
    local iconRow = {}
    for i, m in ipairs(milestones) do
        local canClaim, claimed, reached = DailyTaskData.GetMilestoneStatus(i)
        local reward = m.rewards[1]
        local milestoneIdx = i

        local icon = RewardIconMod.Create(UI, CELL_SZ, reward.id, reward.amount, {
            muted = claimed,
        })

        iconRow[#iconRow + 1] = UI.Panel {
            width = CELL_SZ, height = CELL_SZ,
            flexShrink = 0,
            overflow = "visible",
            opacity = claimed and 0.35 or (reached and 1.0 or 0.5),
            children = {
                icon,
                -- 可领取红点
                canClaim and UI.Panel {
                    position = "absolute", top = -3, right = -3,
                    width = 8, height = 8, borderRadius = 4,
                    backgroundColor = S.red, zIndex = 3,
                    pointerEvents = "none",
                } or nil,
                -- 已领取 ✓
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

    -- 进度条
    local barH = 6
    local pct = maxThr > 0 and math.min(1, totalPts / maxThr) or 0

    local thresholdLabels = {}
    for _, m in ipairs(milestones) do
        thresholdLabels[#thresholdLabels + 1] = UI.Label {
            text = tostring(m.threshold),
            fontSize = 9,
            fontColor = (totalPts >= m.threshold) and S.textGold or S.textDim,
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
            -- 左列：积分
            UI.Panel {
                width = 50,
                flexShrink = 0,
                alignItems = "center",
                justifyContent = "center",
                gap = 2,
                children = {
                    UI.Label {
                        text = "积分",
                        fontSize = 11, fontColor = S.textDim,
                    },
                    UI.Label {
                        text = tostring(totalPts),
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
                        backgroundColor = S.bgBar,
                        borderRadius = barH / 2,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(pct * 100) .. "%",
                                height = "100%",
                                backgroundColor = S.barFill,
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
                                Toast.Show("没有可领取的奖励", S.textDim)
                                return
                            end
                            local claimed = false
                            for idx = 1, #milestones do
                                local ok = DailyTaskData.ClaimMilestone(idx)
                                if ok then claimed = true end
                            end
                            if claimed then
                                Toast.Show("里程碑奖励已领取", S.textGreen)
                                DailyTaskUI.Refresh()
                            else
                                Toast.Show("没有可领取的奖励", S.textDim)
                            end
                        end,
                        children = {
                            UI.Label { text = "全部", fontSize = 11, fontColor = { 240, 235, 255, 255 }, textAlign = "center" },
                            UI.Label { text = "领取", fontSize = 11, fontColor = { 240, 235, 255, 255 }, textAlign = "center" },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 每日任务列表
-- ============================================================================

function DailyTaskUI._BuildDailyTasks()
    local taskChildren = {}

    for _, taskDef in ipairs(DailyTaskData.DAILY_TASKS) do
        local current, target, claimed = DailyTaskData.GetTaskProgress(taskDef.id)
        local taskId = taskDef.id

        taskChildren[#taskChildren + 1] = TaskCard.Create(UI, {
            desc = taskDef.desc,
            current = current,
            target = target,
            claimed = claimed,
            rewardLabel = "积分",
            rewardValue = "+" .. taskDef.points,
            rewardColor = S.textGold,
            buttonRight = true,
            onClaim = function()
                local ok, msg = DailyTaskData.ClaimTask(taskId)
                Toast.Show(msg, ok and S.textGreen or S.red)
                if ok then DailyTaskUI.Refresh() end
            end,
        })
    end

    -- 构建 children 列表
    local sectionChildren = {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginBottom = 2,
            children = {
                UI.Label {
                    text = "| 每日任务",
                    fontSize = 15, fontColor = S.textTitle, fontWeight = "bold",
                },
                UI.Label {
                    text = "00:00后重置",
                    fontSize = 10, fontColor = S.textDim,
                },
            },
        },
    }
    for _, child in ipairs(taskChildren) do
        sectionChildren[#sectionChildren + 1] = child
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        padding = 10,
        gap = 8,
        children = sectionChildren,
    }
end

return DailyTaskUI
