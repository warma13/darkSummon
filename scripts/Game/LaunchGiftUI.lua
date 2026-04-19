-- Game/LaunchGiftUI.lua
-- 开服好礼 UI（全屏页面，参考咸鱼之王布局）

local LaunchGiftData = require("Game.LaunchGiftData")
local Toast          = require("Game.Toast")
local Tooltip        = require("Game.Tooltip")
local RewardIconMod  = require("Game.RewardIcon")
local TaskCard       = require("Game.TaskCard")
local RC             = require("Game.RewardController")

local LaunchGiftUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

-- 样式常量
local S = {
    bgPage     = { 12, 10, 25, 250 },
    bgSection  = { 25, 20, 45, 230 },
    bgCard     = { 30, 24, 50, 220 },
    bgDone     = { 30, 40, 30, 200 },
    bgBar      = { 40, 30, 60, 200 },
    bgBarTask  = { 50, 38, 70, 200 },
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
    claimBtnBg = { 180, 80, 40, 255 },
}

--- 创建进度条
local function ProgressBar(current, total, fillColor, height)
    height = height or 10
    fillColor = fillColor or S.barFill
    local pct = total > 0 and math.min(1, current / total) or 0
    return UI.Panel {
        width = "100%", height = height,
        backgroundColor = S.bgBar,
        borderRadius = height / 2,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = math.floor(pct * 100) .. "%",
                height = "100%",
                backgroundColor = fillColor,
                borderRadius = height / 2,
            },
        },
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 创建全屏页面内容（不含返回键和 overlay 壳，由 GameUI 包装）
function LaunchGiftUI.CreatePage(uiModule)
    UI = uiModule
    pageRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = S.bgPage,
        children = {
            -- 顶部标题栏
            LaunchGiftUI._BuildHeader(),
            -- 可滚动内容区
            UI.ScrollView {
                id = "lgContentArea",
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
function LaunchGiftUI.Refresh()
    if not pageRoot then return end
    local area = pageRoot:FindById("lgContentArea")
    if not area then return end
    area:ClearChildren()

    -- 1) 积分里程碑区
    area:AddChild(LaunchGiftUI._BuildMilestoneSection())
    -- 2) 每日免费招募
    area:AddChild(LaunchGiftUI._BuildDailyPulls())
    -- 3) 每日任务
    area:AddChild(LaunchGiftUI._BuildDailyTasks())

    -- 更新标题栏信息
    local dayLabel = pageRoot:FindById("lgDaysLeft")
    if dayLabel then
        dayLabel:SetText("剩余 " .. LaunchGiftData.GetRemainingDays() .. " 天")
    end
end

-- ============================================================================
-- 顶部标题栏
-- ============================================================================

function LaunchGiftUI._BuildHeader()
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
                        backgroundImage = "image/开服好礼图标.png",
                        backgroundFit = "contain",
                    },
                    UI.Panel {
                        gap = 1,
                        children = {
                            UI.Label {
                                text = "开服好礼",
                                fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                            },
                            UI.Label {
                                text = "参与即送礼 福利领不停",
                                fontSize = 10, fontColor = S.textDim,
                            },
                        },
                    },
                },
            },
            -- 右侧剩余天数
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 60, 40, 90, 200 },
                borderRadius = 10,
                children = {
                    UI.Label {
                        id = "lgDaysLeft",
                        text = "剩余 7 天",
                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 积分里程碑区（2:6:2 三列布局）
-- 左列：上"积分" 下积分数字
-- 中列：上奖励图标行 下进度条+阈值
-- 右列：全部领取
-- ============================================================================

function LaunchGiftUI._BuildMilestoneSection()
    local totalPts = LaunchGiftData.GetTotalPoints()
    local milestones = LaunchGiftData.MILESTONES
    local maxThr = milestones[#milestones].threshold
    local ICON_SZ = 24  -- 图标图片尺寸（缩小以适应屏幕宽度）
    local CELL_SZ = ICON_SZ + 12  -- RewardIcon 外框 = 36

    -- ======== 全部领取状态 ========
    local anyCanClaim = false
    for i = 1, #milestones do
        local canClaim = LaunchGiftData.GetMilestoneStatus(i)
        if canClaim then anyCanClaim = true; break end
    end

    -- ======== 横向奖励图标行（使用 RewardIcon 模块）========
    local iconRow = {}
    for i, m in ipairs(milestones) do
        local canClaim, claimed, reached = LaunchGiftData.GetMilestoneStatus(i)
        local reward = m.rewards[1]
        local milestoneIdx = i

        -- RewardIcon.Create 自带图片+数量角标+点击弹 Tooltip（描述来自内置 REWARD_DESC）
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
                -- 可领取红点（不拦截点击）
                canClaim and UI.Panel {
                    position = "absolute", top = -3, right = -3,
                    width = 8, height = 8, borderRadius = 4,
                    backgroundColor = S.red, zIndex = 3,
                    pointerEvents = "none",
                } or nil,
                -- 已领取 ✓ 覆盖（不拦截点击，让 Tooltip 可用）
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

    -- ======== 进度条 + 阈值标签 ========
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

    -- ======== 主布局：2:6:2 横向三列 ========
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
            -- ====== 左列：积分标签 + 数字 ======
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
            -- ====== 中列：奖励图标 + 进度条+阈值 ======
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                width = "100%",
                gap = 4,
                children = {
                    -- 奖励图标行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = iconRow,
                    },
                    -- 进度条
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
                    -- 阈值标签行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = thresholdLabels,
                    },
                },
            },
            -- ====== 右列：全部领取 ======
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
                            local allRewardDefs = {}
                            for idx = 1, #milestones do
                                local ok, _, rewardDefs = LaunchGiftData.ClaimMilestone(idx)
                                if ok and rewardDefs then
                                    for _, rd in ipairs(rewardDefs) do
                                        allRewardDefs[#allRewardDefs + 1] = rd
                                    end
                                end
                            end
                            if #allRewardDefs > 0 then
                                RC.ShowFromDefs(UI, pageRoot, allRewardDefs, "里程碑奖励",
                                    function() LaunchGiftUI.Refresh() end)
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
-- 每日免费招募
-- ============================================================================

function LaunchGiftUI._BuildDailyPulls()
    local claimed = LaunchGiftData.HasClaimedDailyPulls()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        padding = 10,
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = claimed and S.border or S.borderGold,
        children = {
            -- 左侧：图标 + 文字
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 10,
                flexShrink = 1,
                children = {
                    RewardIconMod.Create(UI, 36, "void_pact", LaunchGiftData.DAILY_FREE_PULLS),
                    UI.Label {
                        text = "每日免费招募",
                        fontSize = 15, fontColor = S.textWhite, fontWeight = "bold",
                    },
                },
            },
            -- 右侧：领取按钮
            UI.Button {
                text = claimed and "已领取" or "领取",
                fontSize = 14,
                width = 72, height = 34,
                borderRadius = 8,
                variant = claimed and "outline" or "primary",
                disabled = claimed,
                onClick = function()
                    local ok, msg, rewardDef = LaunchGiftData.ClaimDailyPulls()
                    if ok and rewardDef then
                        RC.ShowFromDefs(UI, pageRoot, { rewardDef }, "每日免费招募",
                            function() LaunchGiftUI.Refresh() end)
                    else
                        Toast.Show(msg, S.red)
                    end
                end,
            },
        },
    }
end

-- ============================================================================
-- 每日任务
-- ============================================================================

function LaunchGiftUI._BuildDailyTasks()
    local taskChildren = {}

    for _, taskDef in ipairs(LaunchGiftData.DAILY_TASKS) do
        local current, target, claimed = LaunchGiftData.GetTaskProgress(taskDef.id)
        local taskId = taskDef.id

        taskChildren[#taskChildren + 1] = TaskCard.Create(UI, {
            desc = taskDef.desc,
            current = current,
            target = target,
            claimed = claimed,
            rewardLabel = "积分",
            rewardValue = "+" .. taskDef.points,
            rewardColor = S.accent,
            buttonRight = true,
            onClaim = function()
                local ok, msg = LaunchGiftData.ClaimTask(taskId)
                Toast.Show(msg, ok and S.textGreen or S.red)
                if ok then LaunchGiftUI.Refresh() end
            end,
        })
    end

    -- 构建 children 列表（避免 table.unpack 陷阱）
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
                    text = "| 七天任务",
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

    -- 整个任务区
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

return LaunchGiftUI
