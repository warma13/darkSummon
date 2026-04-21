-- Game/WeeklyActivityUI.lua
-- 限时活动 UI：标签页式布局（单周活动 / 通行证）

local WAD            = require("Game.WeeklyActivityData")
local WelfareData    = require("Game.WelfareData")
local Toast          = require("Game.Toast")
local Tooltip        = require("Game.Tooltip")
local RewardIconMod  = require("Game.RewardIcon")
local Config         = require("Game.Config")
local RewardDisplay  = require("Game.RewardDisplay")
local RMD            = require("Game.RecruitMilestoneData")
local DivineBlessDB  = require("Game.DivineBlessData")

local WeeklyActivityUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

local activeTab = "weekly"  -- "weekly" | "pass"
local activeSubTab = "chest" -- "chest" | "welfare"

-- 子标签配置（单周活动下的图标标签栏）
local SUB_TABS = {
    { id = "chest",         icon = "image/icon_cumulate.png",          label = "宝箱达标" },
    { id = "welfare",       icon = "image/icon_limited_welfare.png",   label = "限时福利" },
    { id = "weekend_bonus", icon = "image/icon_weekend_bonus.png",     label = "神裔降临" },
}

-- 子标签样式
local SUB_TAB_ACTIVE = {
    bg = { 60, 40, 100, 255 },
    border = { 180, 120, 255, 200 },
    borderW = 2,
    label = { 255, 220, 100, 255 },
    fontW = "bold",
}
local SUB_TAB_INACTIVE = {
    bg = { 30, 24, 50, 200 },
    border = { 80, 65, 120, 100 },
    borderW = 1,
    label = { 160, 150, 180, 200 },
    fontW = "normal",
}

-- 样式常量（与 LaunchGiftUI 一致的暗紫主题）
local S = {
    bgPage     = { 12, 10, 25, 250 },
    bgHeader   = { 30, 22, 50, 240 },
    bgSection  = { 25, 20, 45, 230 },
    bgCard     = { 35, 28, 55, 220 },
    border     = { 80, 65, 120, 150 },
    borderGold = { 220, 180, 60, 200 },
    textTitle  = { 255, 220, 100, 255 },
    textWhite  = { 240, 235, 255, 255 },
    textNormal = { 220, 210, 240, 255 },
    textDim    = { 150, 140, 170, 200 },
    textGold   = { 255, 200, 60, 255 },
    textGreen  = { 100, 220, 120, 255 },
    accent     = { 180, 120, 255, 255 },
    barBg      = { 30, 20, 45, 200 },
    barFill    = { 200, 140, 60, 255 },
    red        = { 255, 80, 80, 255 },
    claimBg    = { 200, 100, 40, 255 },
    claimedBg  = { 60, 60, 60, 200 },
    tabActive  = { 180, 120, 255, 255 },
    tabInactive = { 50, 40, 70, 200 },
}

-- ============================================================================
-- 公开接口
-- ============================================================================

function WeeklyActivityUI.CreatePage(uiModule)
    UI = uiModule
    activeTab = "weekly"

    pageRoot = UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        backgroundColor = S.bgPage,
        overflow = "hidden",
        children = {
            WeeklyActivityUI._BuildHeader(),
            WeeklyActivityUI._BuildTabBar(),
            WeeklyActivityUI._BuildSubTabBar(),
            UI.ScrollView {
                id = "waContentArea",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                padding = 12,
                gap = 10,
            },
        },
    }
    Tooltip.Init(UI, pageRoot)
    return pageRoot
end

function WeeklyActivityUI.Refresh()
    if not pageRoot then return end
    local area = pageRoot:FindById("waContentArea")
    if not area then return end
    area:ClearChildren()

    -- 始终显示单周活动内容
    activeTab = "weekly"
    WeeklyActivityUI._UpdateSubTabHighlight()
    WeeklyActivityUI._RenderWeeklyTab(area)

    -- 重新挂载 Tooltip 浮窗层（单例模块，需在每次显示时重新绑定到当前页面）
    Tooltip.Init(UI, pageRoot)
end

--- 从外部切换到指定子标签（在 ShowWeeklyActivityOverlay 之前调用）
function WeeklyActivityUI.SetSubTab(tabId)
    activeSubTab = tabId
end

-- ============================================================================
-- 顶部标题栏
-- ============================================================================

function WeeklyActivityUI._BuildHeader()
    return UI.Panel {
        width = "100%",
        paddingTop = 14, paddingBottom = 10,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = S.bgHeader,
        borderBottomWidth = 1,
        borderColor = { 100, 80, 160, 80 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            -- 左侧：标题
            UI.Panel {
                gap = 1,
                children = {
                    UI.Label {
                        text = "限时活动",
                        fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                    },
                    UI.Label {
                        text = "参与即送礼 福利领不停",
                        fontSize = 10, fontColor = S.textDim,
                    },
                },
            },
            -- 右侧：倒计时
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 60, 40, 90, 200 },
                borderRadius = 10,
                children = {
                    UI.Label {
                        id = "waTimeLeft",
                        text = "倒计时: " .. WAD.GetRemainingTimeStr(),
                        fontSize = 12, fontColor = S.accent, fontWeight = "bold",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 标签栏
-- ============================================================================

function WeeklyActivityUI._BuildTabBar()
    -- 仅单周活动，无需标签栏，返回空占位
    return UI.Panel { width = 0, height = 0 }
end

function WeeklyActivityUI._UpdateTabHighlight()
    -- 通行证已移除，无需更新标签高亮
end

-- ============================================================================
-- 子标签栏（图标横向滑动，仅单周活动下显示）
-- ============================================================================

function WeeklyActivityUI._BuildSubTabBar()
    local tabIcons = {}
    for _, tab in ipairs(SUB_TABS) do
        local isActive = (activeSubTab == tab.id)
        tabIcons[#tabIcons + 1] = WeeklyActivityUI._CreateSubTabIcon(tab, isActive)
    end

    return UI.ScrollView {
        id = "waSubTabScroll",
        width = "100%",
        height = "12%",
        minHeight = 70,
        flexShrink = 0,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        backgroundColor = { 28, 22, 45, 240 },
        paddingTop = 4, paddingBottom = 4,
        borderBottomWidth = 1,
        borderColor = { 70, 55, 100, 100 },
        visible = (activeTab == "weekly"),
        children = {
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                paddingLeft = 10, paddingRight = 10,
                height = "100%",
                alignItems = "stretch",
                children = tabIcons,
            },
        },
    }
end

--- 判断当前是否为周末（周六/周日）
-- os.date("*t").wday: 1=周日, 2=周一, ..., 7=周六
local function IsWeekend()
    local w = os.date("*t").wday
    return w == 1 or w == 7
end

--- 子标签红点判断
local SUB_TAB_RED_DOT = {
    chest = function()
        if WAD.GetCurrentWeekType() == "recruit" then
            return RMD.HasClaimable()
        end
        return WAD.HasClaimable()
    end,
    welfare       = function() return WelfareData.HasClaimable() end,
    weekend_bonus = function() return not DivineBlessDB.HasChosen() end,
}

--- 获取"chest"子标签的动态标签名
local function GetChestTabLabel()
    return WAD.GetCurrentWeekType() == "recruit" and "招募达标" or "宝箱达标"
end

--- 获取"chest"子标签的动态图标
local function GetChestTabIcon()
    return WAD.GetCurrentWeekType() == "recruit"
        and "image/icon_recruit_milestone.png"
        or "image/icon_cumulate.png"
end

--- 获取"welfare"子标签的动态图标
local function GetWelfareTabIcon()
    return WAD.GetCurrentWeekType() == "recruit"
        and "image/icon_welfare_recruit.png"
        or "image/icon_welfare_chest.png"
end

function WeeklyActivityUI._CreateSubTabIcon(tab, isActive)
    local s = isActive and SUB_TAB_ACTIVE or SUB_TAB_INACTIVE
    local hasRed = SUB_TAB_RED_DOT[tab.id] and SUB_TAB_RED_DOT[tab.id]() or false
    -- 动态标签名（"宝箱达标" ↔ "招募达标"）
    local displayLabel = (tab.id == "chest") and GetChestTabLabel() or tab.label
    -- 动态图标
    local displayIcon = tab.icon
    if tab.id == "chest" then
        displayIcon = GetChestTabIcon()
    elseif tab.id == "welfare" then
        displayIcon = GetWelfareTabIcon()
    end

    return UI.Panel {
        id = "waSubTab_" .. tab.id,
        height = "100%",
        aspectRatio = 1,
        flexShrink = 0,
        backgroundColor = s.bg,
        borderRadius = 10,
        borderWidth = s.borderW,
        borderColor = s.border,
        overflow = "hidden",
        flexDirection = "column",
        pointerEvents = "auto",
        onClick = function()
            if activeSubTab ~= tab.id then
                activeSubTab = tab.id
                WeeklyActivityUI._UpdateSubTabHighlight()
                WeeklyActivityUI.Refresh()
            end
        end,
        children = {
            -- 上部 70%：图标
            UI.Panel {
                width = "100%", height = "70%",
                backgroundImage = displayIcon,
                backgroundFit = "cover",
                backgroundPosition = "center",
                pointerEvents = "none",
            },
            -- 下部 30%：标签名
            UI.Panel {
                width = "100%", height = "30%",
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        id = "waSubTabLabel_" .. tab.id,
                        text = displayLabel,
                        fontSize = 10,
                        fontColor = s.label,
                        fontWeight = s.fontW,
                        textAlign = "center",
                    },
                },
            },
            -- 红点
            UI.Panel {
                id = "waSubTabRedDot_" .. tab.id,
                position = "absolute",
                top = 2, right = 2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
                visible = hasRed,
            },
        },
    }
end

function WeeklyActivityUI._UpdateSubTabHighlight()
    if not pageRoot then return end
    for _, tab in ipairs(SUB_TABS) do
        local isActive = (activeSubTab == tab.id)
        local s = isActive and SUB_TAB_ACTIVE or SUB_TAB_INACTIVE
        local tabWidget = pageRoot:FindById("waSubTab_" .. tab.id)
        if tabWidget then
            tabWidget:SetStyle({
                backgroundColor = s.bg,
                borderColor = s.border,
                borderWidth = s.borderW,
            })
        end
        local labelWidget = pageRoot:FindById("waSubTabLabel_" .. tab.id)
        if labelWidget then
            labelWidget:SetStyle({ fontColor = s.label, fontWeight = s.fontW })
            -- 刷新动态标签文字
            if tab.id == "chest" then
                labelWidget:SetText(GetChestTabLabel())
            end
        end
        -- 刷新红点
        local redDot = pageRoot:FindById("waSubTabRedDot_" .. tab.id)
        if redDot then
            local hasRed = SUB_TAB_RED_DOT[tab.id] and SUB_TAB_RED_DOT[tab.id]() or false
            redDot:SetVisible(hasRed)
        end
    end
end

-- ============================================================================
-- 单周活动 Tab 内容
-- ============================================================================

function WeeklyActivityUI._RenderWeeklyTab(area)
    -- 更新倒计时
    local timeLabel = pageRoot:FindById("waTimeLeft")
    if timeLabel then
        timeLabel:SetText("倒计时: " .. WAD.GetRemainingTimeStr())
    end

    if activeSubTab == "chest" then
        if WAD.GetCurrentWeekType() == "recruit" then
            -- 招募达标
            area:AddChild(WeeklyActivityUI._BuildRecruitBanner())
            area:AddChild(WeeklyActivityUI._BuildRecruitMilestoneList())
        else
            -- 宝箱达标
            area:AddChild(WeeklyActivityUI._BuildActivityBanner())
            area:AddChild(WeeklyActivityUI._BuildMilestoneList())
        end
    elseif activeSubTab == "welfare" then
        -- 限时福利
        area:AddChild(WeeklyActivityUI._RenderWelfareContent())
    elseif activeSubTab == "weekend_bonus" then
        -- 神裔降临
        area:AddChild(WeeklyActivityUI._RenderWeekendBonusContent())
    end
end

--- 活动说明横幅
function WeeklyActivityUI._BuildActivityBanner()
    local round = WAD.GetRound()
    local score = WAD.GetRoundScore()
    local allDone = round > WAD.MAX_ROUNDS

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        overflow = "hidden",
        children = {
            -- 顶部装饰条
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
                    -- 活动标题行
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
                            -- 前往宝箱
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
                    -- 活动说明
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
                    -- 轮数与积分信息
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

function WeeklyActivityUI._BuildMilestoneList()
    local score = WAD.GetRoundScore()
    local allDone = WAD.GetRound() > WAD.MAX_ROUNDS
    local container = UI.Panel {
        width = "100%",
        gap = 8,
    }

    for i, m in ipairs(WAD.MILESTONES) do
        container:AddChild(WeeklyActivityUI._BuildMilestoneCard(i, m, score, allDone))
    end

    return container
end

function WeeklyActivityUI._BuildMilestoneCard(index, milestone, score, allDone)
    local _, claimed, reached
    if allDone then
        claimed, reached = true, true
    else
        _, claimed, reached = WAD.GetMilestoneStatus(index)
    end
    local pct = allDone and 1 or math.min(1, score / milestone.threshold)

    -- 状态标签
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

    -- 右侧奖励图标（横向滚动）
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
            -- 左侧 60%：标题 + 进度条 + 状态
            UI.Panel {
                width = "58%",
                flexShrink = 0,
                gap = 4,
                paddingRight = 8,
                children = {
                    -- 标题行
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
                    -- 进度条（全部完成时替换为文字）
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
            -- 分隔线
            UI.Panel {
                width = 1, height = "80%",
                backgroundColor = { 80, 65, 120, 80 },
                flexShrink = 0,
            },
            -- 右侧 40%：奖励图标横向滚动
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

-- ============================================================================
-- 招募达标 内容（招募周专用）
-- ============================================================================

function WeeklyActivityUI._BuildRecruitBanner()
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
            -- 顶部装饰条（紫色，与宝箱周金色区分）
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
                    -- 标题行
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
                            -- 前往招募
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
                    -- 说明
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
                    -- 轮次与进度行
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

function WeeklyActivityUI._BuildRecruitMilestoneList()
    local count   = RMD.GetRoundCount()
    local allDone = RMD.GetRound() > RMD.MAX_ROUNDS
    local container = UI.Panel { width = "100%", gap = 8 }
    for i, m in ipairs(RMD.MILESTONES) do
        container:AddChild(WeeklyActivityUI._BuildRecruitMilestoneCard(i, m, count, allDone))
    end
    return container
end

function WeeklyActivityUI._BuildRecruitMilestoneCard(index, milestone, count, allDone)
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

    -- 奖励图标
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
            -- 左侧：次数 + 进度条
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
            -- 分隔线
            UI.Panel { width = 1, height = "80%", backgroundColor = { 80, 65, 120, 80 }, flexShrink = 0 },
            -- 右侧：奖励图标
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

-- ============================================================================
-- 限时福利 内容
-- ============================================================================

function WeeklyActivityUI._RenderWelfareContent()
    if WAD.GetCurrentWeekType() == "recruit" then
        return WeeklyActivityUI._RenderRecruitWelfareContent()
    end

    local container = UI.Panel { width = "100%", gap = 10 }

    -- 每日广告宝箱说明
    container:AddChild(WeeklyActivityUI._BuildWelfareBanner())
    -- 每日广告奖励列表
    container:AddChild(WeeklyActivityUI._BuildDailyAdList())
    -- 每周广告进度条
    container:AddChild(WeeklyActivityUI._BuildWeeklyAdProgress())

    return container
end

--- 招募周：限时福利内容（招募券）
function WeeklyActivityUI._RenderRecruitWelfareContent()
    local container = UI.Panel { width = "100%", gap = 10 }
    container:AddChild(WeeklyActivityUI._BuildRecruitWelfareBanner())
    container:AddChild(WeeklyActivityUI._BuildRecruitDailyAdList())
    -- 每周广告里程碑奖励（与宝箱周共用）
    container:AddChild(WeeklyActivityUI._BuildWeeklyAdProgress())
    return container
end

--- 招募周福利说明横幅
function WeeklyActivityUI._BuildRecruitWelfareBanner()
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

--- 招募周每日奖励列表
function WeeklyActivityUI._BuildRecruitDailyAdList()
    local container = UI.Panel { width = "100%", gap = 6 }
    for i, reward in ipairs(WelfareData.RECRUIT_DAILY_REWARDS) do
        container:AddChild(WeeklyActivityUI._BuildRecruitDailyAdCard(i, reward))
    end
    return container
end

--- 单个招募券奖励卡片
function WeeklyActivityUI._BuildRecruitDailyAdCard(index, reward)
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
                    -- 券图标
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
                    -- 描述
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
                                    WeeklyActivityUI.Refresh()
                                    RewardDisplay.Show(UI, pageRoot, {
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

--- 限时福利说明横幅
function WeeklyActivityUI._BuildWelfareBanner()
    local dailyCount = WelfareData.GetDailyAdCount()

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        overflow = "hidden",
        children = {
            -- 顶部装饰条
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

--- 每日广告奖励列表
function WeeklyActivityUI._BuildDailyAdList()
    local container = UI.Panel {
        width = "100%",
        gap = 6,
    }

    for i, reward in ipairs(WelfareData.DAILY_AD_REWARDS) do
        container:AddChild(WeeklyActivityUI._BuildDailyAdCard(i, reward))
    end

    return container
end

--- 单个每日广告奖励卡片
function WeeklyActivityUI._BuildDailyAdCard(index, reward)
    local claimed = WelfareData.IsDailyClaimed(index)
    local unlocked = WelfareData.IsDailyUnlocked(index)
    local chestInfo = Config.CHEST_TYPES_MAP[reward.chestId]

    -- 宝箱颜色
    local chestColor = chestInfo and chestInfo.color or { 200, 200, 200 }
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
            -- 左侧：序号
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
            -- 中间：宝箱图标 + 描述
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                marginLeft = 8, marginRight = 8,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    -- 宝箱图标
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
                    -- 描述文字
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
            -- 右侧：按钮
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
                                    WeeklyActivityUI.Refresh()
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
                                    RewardDisplay.Show(UI, pageRoot, {
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

--- 每周广告进度里程碑（2:6:2 三列布局，与每日任务积分里程碑一致）
function WeeklyActivityUI._BuildWeeklyAdProgress()
    local totalAds = WelfareData.GetWeeklyAdTotal()
    local milestones = WelfareData.WEEKLY_MILESTONES
    local maxAds = milestones[#milestones].threshold
    local ICON_SZ = 24
    local CELL_SZ = ICON_SZ + 12  -- 36
    local barH = 6
    local pct = maxAds > 0 and math.min(1, totalAds / maxAds) or 0

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
        local claimed = WelfareData.IsWeeklyClaimed(i)
        local reached = totalAds >= m.threshold
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
                -- 可领取红点
                claimable and UI.Panel {
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
                                RewardDisplay.Show(UI, pageRoot, {
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
                                        WeeklyActivityUI.Refresh()
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
-- 神裔降临 内容（每日 3 选 1 神裔加成，周末磐古自动降临）
-- ============================================================================

-- 确认弹窗
local _divineConfirmOverlay = nil  ---@type any
local _divineConfirmEntry   = nil  ---@type DivineEntry
local _divineConfirmIndex   = nil  ---@type number

local function HideDivineConfirm()
    if _divineConfirmOverlay then
        _divineConfirmOverlay:SetVisible(false)
        -- Refresh 会 ClearChildren，overlay 会被移除；清引用以便下次重建
        if pageRoot then pcall(function() pageRoot:RemoveChild(_divineConfirmOverlay) end) end
        _divineConfirmOverlay = nil
    end
    _divineConfirmEntry = nil
    _divineConfirmIndex = nil
end

local function DoDivineConfirm()
    if not _divineConfirmEntry or not _divineConfirmIndex then return end
    local entry = _divineConfirmEntry
    local c = entry.color
    local ok, msg = DivineBlessDB.Choose(_divineConfirmIndex)
    if ok then
        Toast.Show(msg, { c[1], c[2], c[3], 255 })
        local tok, Tower = pcall(require, "Game.Tower")
        if tok then Tower.RefreshAllStats() end
    else
        Toast.Show(msg, { 255, 100, 100 })
    end
    HideDivineConfirm()
    WeeklyActivityUI.Refresh()
end

local function ShowDivineConfirm(entry, index)
    _divineConfirmEntry = entry
    _divineConfirmIndex = index
    local c = entry.color
    local themeColor = { c[1], c[2], c[3], 255 }

    if _divineConfirmOverlay then
        -- 更新已有弹窗内容
        local nameEl = _divineConfirmOverlay:FindById("dcDivineName")
        local descEl = _divineConfirmOverlay:FindById("dcDivineDesc")
        local iconEl = _divineConfirmOverlay:FindById("dcDivineIcon")
        if nameEl then nameEl:SetText(entry.name .. " · " .. entry.title) end
        if descEl then descEl:SetText(entry.desc) end
        if iconEl then iconEl:SetText(entry.domain:sub(1, 3) or "?") end
        _divineConfirmOverlay:SetVisible(true)
        return
    end

    _divineConfirmOverlay = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        zIndex = 100,
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() HideDivineConfirm() end,
        children = {
            UI.Panel {
                width = "80%",
                paddingTop = 22, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                backgroundColor = { 32, 26, 50, 252 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 90, 78, 120, 180 },
                gap = 14,
                alignItems = "center",
                onClick = function() end,  -- 阻止点击穿透
                children = {
                    UI.Label {
                        text = "确认选择祝福",
                        fontSize = 16,
                        fontColor = { 230, 225, 245, 255 },
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 110, 120 },
                    },
                    -- 神裔图标
                    UI.Panel {
                        width = 52, height = 52,
                        borderRadius = 26,
                        backgroundColor = { c[1], c[2], c[3], 35 },
                        borderWidth = 2,
                        borderColor = themeColor,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "dcDivineIcon",
                                text = entry.domain:sub(1, 3) or "?",
                                fontSize = 20,
                                fontColor = themeColor,
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 名字
                    UI.Label {
                        id = "dcDivineName",
                        text = entry.name .. " · " .. entry.title,
                        fontSize = 18,
                        fontColor = themeColor,
                        fontWeight = "bold",
                    },
                    -- 加成描述
                    UI.Label {
                        id = "dcDivineDesc",
                        text = entry.desc,
                        fontSize = 14,
                        fontColor = { 140, 255, 190, 230 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "选择后今日不可更改",
                        fontSize = 11,
                        fontColor = { 255, 180, 80, 200 },
                    },
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                paddingTop = 10, paddingBottom = 10,
                                alignItems = "center",
                                backgroundColor = { 45, 40, 62, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 75, 68, 98, 160 },
                                onClick = function() HideDivineConfirm() end,
                                children = {
                                    UI.Label {
                                        text = "取消",
                                        fontSize = 13,
                                        fontColor = { 170, 160, 190, 230 },
                                    },
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                paddingTop = 10, paddingBottom = 10,
                                alignItems = "center",
                                backgroundColor = { c[1], c[2], c[3], 200 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { c[1], c[2], c[3], 240 },
                                onClick = function() DoDivineConfirm() end,
                                children = {
                                    UI.Label {
                                        text = "确认",
                                        fontSize = 13,
                                        fontColor = { 255, 255, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    -- 挂载到 pageRoot（全屏遮罩）
    if pageRoot then
        pageRoot:AddChild(_divineConfirmOverlay)
    end
end

--- 创建一张神裔卡片
---@param entry DivineEntry
---@param index number       1-based 选项序号
---@param isActive boolean   当前是否为生效中的神裔
---@param isWeekend boolean  是否周末（周末磐古自动，不可选）
---@param hasChosen boolean  今日是否已选
local function _CreateDivineCard(entry, index, isActive, isWeekend, hasChosen)
    local c = entry.color
    local themeColor = { c[1], c[2], c[3], 255 }
    local themeBg    = { c[1], c[2], c[3], isActive and 35 or 15 }
    local themeBorder = { c[1], c[2], c[3], isActive and 200 or 80 }

    -- 按钮状态
    local btnText, btnBg, btnColor, btnEnabled
    if isActive then
        btnText = "降临中"
        btnBg = { c[1], c[2], c[3], 60 }
        btnColor = themeColor
        btnEnabled = false
    elseif isWeekend then
        btnText = "自动降临"
        btnBg = { 60, 60, 60, 200 }
        btnColor = S.textDim
        btnEnabled = false
    elseif hasChosen then
        btnText = "今日已选"
        btnBg = { 60, 60, 60, 200 }
        btnColor = S.textDim
        btnEnabled = false
    else
        btnText = "选择祝福"
        btnBg = { c[1], c[2], c[3], 180 }
        btnColor = { 255, 255, 255, 255 }
        btnEnabled = true
    end

    return UI.Panel {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        backgroundColor = themeBg,
        borderRadius = 12,
        borderWidth = isActive and 2 or 1,
        borderColor = themeBorder,
        overflow = "hidden",
        children = {
            -- 顶部主题色装饰条
            UI.Panel {
                width = "100%", height = 3,
                backgroundColor = themeColor,
            },
            -- 卡片内容
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                paddingTop = 14, paddingBottom = 12,
                paddingLeft = 10, paddingRight = 10,
                alignItems = "center",
                gap = 8,
                children = {
                    -- 神格图标圆圈
                    UI.Panel {
                        width = 44, height = 44,
                        borderRadius = 22,
                        backgroundColor = { c[1], c[2], c[3], isActive and 50 or 25 },
                        borderWidth = 2,
                        borderColor = themeBorder,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = entry.domain:sub(1, 3) or "?",
                                fontSize = 16,
                                fontColor = themeColor,
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 名字
                    UI.Label {
                        text = entry.name,
                        fontSize = 15,
                        fontColor = themeColor,
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                    -- 称号
                    UI.Label {
                        text = entry.title,
                        fontSize = 11,
                        fontColor = { c[1], c[2], c[3], 160 },
                        textAlign = "center",
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "80%", height = 1,
                        backgroundColor = { c[1], c[2], c[3], 40 },
                    },
                    -- 加成描述
                    UI.Panel {
                        width = "100%",
                        paddingLeft = 4, paddingRight = 4,
                        paddingTop = 4, paddingBottom = 4,
                        backgroundColor = { c[1], c[2], c[3], isActive and 25 or 10 },
                        borderRadius = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = entry.desc,
                                fontSize = 12,
                                fontColor = isActive and { 255, 255, 255, 255 } or S.textNormal,
                                fontWeight = "bold",
                                textAlign = "center",
                            },
                        },
                    },
                    -- 世界观短文
                    UI.Label {
                        text = entry.lore,
                        fontSize = 10,
                        fontColor = S.textDim,
                        textAlign = "center",
                        flexWrap = "wrap",
                    },
                    -- 选择按钮（推到底部）
                    UI.Panel {
                        width = "100%",
                        marginTop = "auto",
                        paddingTop = 6,
                        alignItems = "center",
                        children = {
                            UI.Button {
                                text = btnText,
                                fontSize = 13,
                                fontWeight = "bold",
                                fontColor = btnColor,
                                backgroundColor = btnBg,
                                borderRadius = 8,
                                paddingLeft = 16, paddingRight = 16,
                                paddingTop = 6, paddingBottom = 6,
                                disabled = not btnEnabled,
                                onClick = btnEnabled and function()
                                    ShowDivineConfirm(entry, index)
                                end or nil,
                            },
                        },
                    },
                },
            },
        },
    }
end

function WeeklyActivityUI._RenderWeekendBonusContent()
    local isWeekend = DivineBlessDB.IsWeekend()
    local hasChosen = DivineBlessDB.HasChosen()
    local active    = DivineBlessDB.GetActiveBlessing()
    local options   = DivineBlessDB.GetTodayOptions()

    local wdayNames = { "周日","周一","周二","周三","周四","周五","周六" }
    local todayName = wdayNames[os.date("*t").wday]

    local container = UI.Panel { width = "100%", gap = 10 }

    -- ── 状态横幅 ─────────────────────────────────────────────────
    local statusText, statusSub
    if isWeekend then
        statusText = "磐古降临中"
        statusSub = "今日 " .. todayName .. " · 冥晶收益 ×1.5 自动生效"
    elseif active then
        statusText = active.name .. " 降临中"
        statusSub = "今日 " .. todayName .. " · " .. active.desc .. " 已生效"
    else
        statusText = "今日神裔待选"
        statusSub = "今日 " .. todayName .. " · 选择一位初裔神获得全天加成"
    end

    local hasActive = (active ~= nil)
    container:AddChild(UI.Panel {
        width  = "100%",
        backgroundColor = hasActive and { 32, 12, 62, 255 } or S.bgSection,
        borderRadius = 10,
        borderWidth  = 1,
        borderColor  = hasActive and { 150, 70, 240, 180 } or S.border,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = "100%", height = 3,
                backgroundColor = hasActive
                    and { active.color[1], active.color[2], active.color[3], 255 }
                    or { 80, 70, 110, 200 },
            },
            UI.Panel {
                width = "100%",
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 14, paddingRight = 14,
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = statusText,
                        fontSize = 20,
                        fontColor = hasActive
                            and { active.color[1], active.color[2], active.color[3], 255 }
                            or S.textDim,
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                    UI.Label {
                        text = statusSub,
                        fontSize = 12,
                        fontColor = hasActive and { 140, 255, 190, 210 } or S.textDim,
                        textAlign = "center",
                    },
                },
            },
        },
    })

    -- ── 神裔选择卡片（横排 3 列） ───────────────────────────────
    local cardChildren = {}
    for i, entry in ipairs(options) do
        local isThisActive = (active ~= nil and active.id == entry.id)
        cardChildren[#cardChildren + 1] = _CreateDivineCard(entry, i, isThisActive, isWeekend, hasChosen)
    end

    container:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        children = cardChildren,
    })

    -- ── 当前生效加成卡片（已选时显示） ──────────────────────────
    if active then
        local ac = active.color
        container:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = { ac[1], ac[2], ac[3], 20 },
            borderRadius = 10,
            borderWidth  = 1,
            borderColor  = { ac[1], ac[2], ac[3], 120 },
            paddingTop = 12, paddingBottom = 12,
            paddingLeft = 14, paddingRight = 14,
            flexDirection = "row",
            alignItems = "center",
            gap = 12,
            children = {
                -- 图标
                UI.Panel {
                    width = 44, height = 44,
                    borderRadius = 22,
                    backgroundColor = { ac[1], ac[2], ac[3], 40 },
                    borderWidth = 2,
                    borderColor = { ac[1], ac[2], ac[3], 160 },
                    justifyContent = "center",
                    alignItems = "center",
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = active.domain:sub(1, 3) or "?",
                            fontSize = 18,
                            fontColor = { ac[1], ac[2], ac[3], 255 },
                            fontWeight = "bold",
                        },
                    },
                },
                -- 文字
                UI.Panel {
                    flexGrow = 1, gap = 3,
                    children = {
                        UI.Label {
                            text = active.name .. " · " .. active.title,
                            fontSize = 14,
                            fontColor = { ac[1], ac[2], ac[3], 255 },
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = active.desc .. "（今日全天生效）",
                            fontSize = 12,
                            fontColor = S.textNormal,
                        },
                    },
                },
                -- 状态标记
                UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 3, paddingBottom = 3,
                    backgroundColor = { ac[1], ac[2], ac[3], 50 },
                    borderRadius = 8,
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = "生效中",
                            fontSize = 11,
                            fontColor = S.textGreen,
                            fontWeight = "bold",
                        },
                    },
                },
            },
        })
    end

    -- ── 活动规则 ─────────────────────────────────────────────────
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth  = 1,
        borderColor  = S.border,
        paddingTop   = 12, paddingBottom = 12,
        paddingLeft  = 14, paddingRight  = 14,
        gap = 8,
        children = {
            UI.Label {
                text = "| 活动规则",
                fontSize = 15,
                fontColor = S.textTitle,
                fontWeight = "bold",
            },
            UI.Label { text = "· 周一至周五：每日随机降临 3 位初裔神，可选择 1 位获得全天加成", fontSize = 12, fontColor = S.textDim },
            UI.Label { text = "· 周六、周日：土嗣·磐古自动降临，冥晶收益 ×1.5", fontSize = 12, fontColor = S.textDim },
            UI.Label { text = "· 每日 00:00 刷新，选择后当日不可更改", fontSize = 12, fontColor = S.textDim },
            UI.Label { text = "· 加成效果与特权、装备等增益叠加计算", fontSize = 12, fontColor = S.textDim },
        },
    })

    return container
end

return WeeklyActivityUI
