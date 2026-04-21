-- Game/DailyTaskUI.lua
-- 每日任务 + 成就 UI（标签栏切换，独立全屏页面）

local DailyTaskData   = require("Game.DailyTaskData")
local WPD             = require("Game.WeeklyPointsData")
local AchievementData = require("Game.AchievementData")
local HeroData        = require("Game.HeroData")
local Toast           = require("Game.Toast")
local Tooltip         = require("Game.Tooltip")
local RewardIconMod   = require("Game.RewardIcon")
local TaskCard        = require("Game.TaskCard")
local ChestData       = require("Game.ChestData")
local TodayKey        = require("Game.DateUtil").TodayKey

local DailyTaskUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

--- 当前选中标签  "daily" | "achieve"
local activeTab = "daily"

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
            -- 顶部标题栏 + 标签栏
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

    -- 刷新标题栏（含标签状态）
    local headerContainer = pageRoot:FindById("dtHeaderContainer")
    if headerContainer then
        headerContainer:ClearChildren()
        headerContainer:AddChild(DailyTaskUI._BuildHeaderContent())
    end

    -- 刷新内容区
    local area = pageRoot:FindById("dtContentArea")
    if not area then return end
    area:ClearChildren()

    if activeTab == "daily" then
        DailyTaskData.EnsureData()
        -- 1) 周积分里程碑区（在上）
        area:AddChild(DailyTaskUI._BuildWeeklyMilestoneSection())
        -- 2) 每日积分里程碑区
        area:AddChild(DailyTaskUI._BuildMilestoneSection())
        -- 3) 每日任务列表
        area:AddChild(DailyTaskUI._BuildDailyTasks())
    elseif activeTab == "achieve" then
        area:AddChild(DailyTaskUI._BuildAchievementSection())
        -- 首次打开时异步获取排行榜排名，获取后刷新一次（不重复拉取）
        if not DailyTaskUI._ranksFetched then
            DailyTaskUI._ranksFetched = true
            AchievementData.FetchRanks(function()
                if activeTab == "achieve" and pageRoot then
                    DailyTaskUI.Refresh()
                end
            end)
        end
    end
end

-- ============================================================================
-- 顶部标题栏 + 标签栏
-- ============================================================================

function DailyTaskUI._BuildHeader()
    return UI.Panel {
        id = "dtHeaderContainer",
        width = "100%",
        flexShrink = 0,
        children = {
            DailyTaskUI._BuildHeaderContent(),
        },
    }
end

function DailyTaskUI._BuildHeaderContent()
    local completed, total = DailyTaskData.GetCompletedCount()
    local hasAchieveClaim = AchievementData.HasClaimable()

    return UI.Panel {
        width = "100%",
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                paddingTop = 14, paddingBottom = 8,
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = { 30, 22, 50, 240 },
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
                            UI.Label {
                                text = "每日任务",
                                fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                            },
                        },
                    },
                    -- 右侧完成度（仅每日任务 tab 显示）
                    activeTab == "daily" and UI.Panel {
                        paddingLeft = 10, paddingRight = 10,
                        paddingTop = 4, paddingBottom = 4,
                        backgroundColor = completed >= total
                            and { 50, 90, 50, 200 }
                            or  { 60, 40, 90, 200 },
                        borderRadius = 10,
                        children = {
                            UI.Label {
                                text = "已完成 " .. completed .. "/" .. total,
                                fontSize = 12,
                                fontColor = completed >= total
                                    and S.textGreen
                                    or  S.accent,
                                fontWeight = "bold",
                            },
                        },
                    } or nil,
                },
            },
            -- 标签栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                backgroundColor = { 20, 16, 38, 240 },
                borderBottomWidth = 1,
                borderColor = { 80, 65, 120, 80 },
                children = {
                    DailyTaskUI._BuildTab("daily", "每日任务", false),
                    DailyTaskUI._BuildTab("achieve", "成就", hasAchieveClaim),
                },
            },
        },
    }
end

--- 构建单个标签
---@param tabId string
---@param label string
---@param hasRedDot boolean
function DailyTaskUI._BuildTab(tabId, label, hasRedDot)
    local isActive = (activeTab == tabId)
    return UI.Panel {
        flexGrow = 1,
        height = 40,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = isActive and { 40, 30, 65, 255 } or { 20, 16, 38, 0 },
        borderBottomWidth = isActive and 2 or 0,
        borderColor = isActive and S.accent or { 0, 0, 0, 0 },
        pointerEvents = "auto",
        overflow = "visible",
        onClick = function()
            if activeTab ~= tabId then
                activeTab = tabId
                DailyTaskUI.Refresh()
            end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = 14,
                fontColor = isActive and S.textWhite or S.textDim,
                fontWeight = isActive and "bold" or "normal",
            },
            -- 红点
            hasRedDot and UI.Panel {
                position = "absolute", top = 6, right = "30%",
                width = 8, height = 8, borderRadius = 4,
                backgroundColor = S.red, zIndex = 3,
                pointerEvents = "none",
            } or nil,
        },
    }
end

-- ============================================================================
-- 成就页：关卡里程碑 + 暗影君主升级（每行只显示当前一个，领完刷新下一个）
-- ============================================================================

--- 通用里程碑行构建
---@param opts { badge:string, desc:string, current:number, target:number, rewardId:string, rewardAmt:number, canClaim:boolean, reached:boolean, onClaim:function, progress?:string }
local function _BuildMilestoneRow(opts)
    local pct = math.min(1, opts.current / math.max(1, opts.target))
    local progressText = opts.progress or (math.min(opts.current, opts.target) .. "/" .. opts.target)
    if opts.progress then pct = opts.reached and 1 or 0 end
    local icon = RewardIconMod.Create(UI, 36, opts.rewardId, opts.rewardAmt, opts.iconOpts or {})

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = opts.canClaim and S.borderGold or S.border,
        padding = 10,
        gap = 10,
        children = {
            -- 左侧标识
            UI.Panel {
                width = 44, height = 44,
                borderRadius = 22,
                backgroundColor = opts.reached and { 60, 45, 100, 255 } or { 35, 28, 55, 255 },
                borderWidth = 1,
                borderColor = opts.reached and S.accent or { 60, 50, 80, 150 },
                justifyContent = "center",
                alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = opts.badge,
                        fontSize = #opts.badge >= 4 and 11 or (#opts.badge == 3 and 13 or 16),
                        fontWeight = "bold",
                        whiteSpace = "nowrap",
                        fontColor = opts.reached and S.textGold or S.textDim,
                    },
                },
            },
            -- 中间描述 + 进度条
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 4,
                children = {
                    UI.Label {
                        text = opts.desc,
                        fontSize = 13, fontColor = S.textNormal, fontWeight = "bold",
                    },
                    UI.Panel {
                        width = "100%", height = 6,
                        backgroundColor = S.bgBar,
                        borderRadius = 3,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(pct * 100) .. "%",
                                height = "100%",
                                backgroundColor = S.barFill,
                                borderRadius = 3,
                            },
                        },
                    },
                    UI.Label {
                        text = progressText,
                        fontSize = 10, fontColor = S.textDim,
                    },
                },
            },
            -- 右侧奖励图标
            UI.Panel {
                width = 36, height = 36,
                flexShrink = 0,
                children = { icon },
            },
            -- 领取按钮
            UI.Panel {
                width = 56, height = 32,
                flexShrink = 0,
                borderRadius = 6,
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                backgroundColor = opts.canClaim and { 120, 60, 200, 220 } or { 40, 30, 60, 150 },
                borderWidth = 1,
                borderColor = opts.canClaim and S.accent or { 60, 50, 80, 100 },
                opacity = opts.canClaim and 1.0 or 0.5,
                onClick = opts.canClaim and opts.onClaim or nil,
                children = {
                    UI.Label {
                        text = opts.canClaim and "领取" or "未达成",
                        fontSize = 11,
                        fontColor = opts.canClaim and S.textWhite or S.textDim,
                    },
                },
            },
        },
    }
end

--- 格式化大数字
local function _FormatNum(n)
    if n >= 10000000 then return math.floor(n / 10000000) .. "kw"
    elseif n >= 10000 then return math.floor(n / 10000) .. "w"
    else return tostring(n) end
end

function DailyTaskUI._BuildAchievementSection()
    -- 1) 关卡成就行
    local stageTarget, stageCanClaim, stageReached = AchievementData.GetCurrentStageMilestone()
    local bestStage = HeroData.stats and HeroData.stats.bestStage or 0
    local stageRow = _BuildMilestoneRow({
        badge    = tostring(stageTarget),
        desc     = "通关第" .. stageTarget .. "关",
        current  = bestStage,
        target   = stageTarget,
        rewardId = "shadow_essence",
        rewardAmt = 50,
        canClaim = stageCanClaim,
        reached  = stageReached,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimStage(stageTarget)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 2) 暗影君主升级行
    local lvTarget, lvCanClaim, lvReached, lvReward = AchievementData.GetCurrentLevelMilestone()
    local curLevel = AchievementData.GetLeaderLevel()
    local levelRow = _BuildMilestoneRow({
        badge    = tostring(lvTarget),
        desc     = "暗影君主达到" .. lvTarget .. "级",
        current  = curLevel,
        target   = lvTarget,
        rewardId = "nether_crystal",
        rewardAmt = lvReward,
        canClaim = lvCanClaim,
        reached  = lvReached,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimLevel(lvTarget)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 3) 累积登录行
    local loginDays, loginCanClaim, loginReached, loginReward = AchievementData.GetCurrentLoginMilestone()
    local totalDays = AchievementData.GetTotalLoginDays()
    local loginRow = _BuildMilestoneRow({
        badge    = loginDays .. "天",
        desc     = "累积登录" .. loginDays .. "天",
        current  = totalDays,
        target   = loginDays,
        rewardId = "shadow_essence",
        rewardAmt = loginReward,
        canClaim = loginCanClaim,
        reached  = loginReached,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimLogin(loginDays)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 4) 主线排行榜名次行
    local crTarget, crCanClaim, crReached, crReward = AchievementData.GetCurrentCampaignRankMilestone()
    local campaignRank, towerRank = AchievementData.GetCachedRanks()
    local campaignRow = _BuildMilestoneRow({
        badge    = "前" .. crTarget,
        desc     = "主线排名前" .. crTarget,
        current  = campaignRank and campaignRank or 0,
        target   = crTarget,
        progress = campaignRank and ("第" .. campaignRank .. "名") or "未上榜",
        rewardId = "shadow_essence",
        rewardAmt = crReward,
        canClaim = crCanClaim,
        reached  = crReached,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimCampaignRank(crTarget)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 5) 试练塔排行榜名次行
    local trTarget, trCanClaim, trReached, trReward = AchievementData.GetCurrentTowerRankMilestone()
    local towerRow = _BuildMilestoneRow({
        badge    = "前" .. trTarget,
        desc     = "试练塔排名前" .. trTarget,
        current  = towerRank and towerRank or 0,
        target   = trTarget,
        progress = towerRank and ("第" .. towerRank .. "名") or "未上榜",
        rewardId = "shadow_essence",
        rewardAmt = trReward,
        canClaim = trCanClaim,
        reached  = trReached,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimTowerRank(trTarget)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 6) 开启宝箱次数行
    local chTarget, chCanClaim, chReached, chRewardId, chRewardAmt = AchievementData.GetCurrentChestMilestone()
    local totalChest = AchievementData.GetTotalChestOpened()
    local chestDef = ChestData.GetChestDef(chRewardId)
    local chestIconOpts = {}
    if chestDef then
        chestIconOpts.image = chestDef.image
        chestIconOpts.label = chestDef.name
    end
    local chestRow = _BuildMilestoneRow({
        badge    = _FormatNum(chTarget),
        desc     = "累计开启" .. chTarget .. "次宝箱",
        current  = totalChest,
        target   = chTarget,
        rewardId = chRewardId,
        rewardAmt = chRewardAmt,
        canClaim = chCanClaim,
        reached  = chReached,
        iconOpts = chestIconOpts,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimChest(chTarget)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 7) 累积招募次数行
    local rcTarget, rcCanClaim, rcReached, rcReward = AchievementData.GetCurrentRecruitMilestone()
    local totalRecruit = AchievementData.GetTotalRecruitCount()
    local recruitRow = _BuildMilestoneRow({
        badge    = _FormatNum(rcTarget),
        desc     = "累计招募" .. rcTarget .. "次",
        current  = totalRecruit,
        target   = rcTarget,
        rewardId = "shadow_essence",
        rewardAmt = rcReward,
        canClaim = rcCanClaim,
        reached  = rcReached,
        onClaim  = function()
            local ok, msg = AchievementData.ClaimRecruit(rcTarget)
            Toast.Show(msg, ok and S.textGreen or S.red)
            if ok then DailyTaskUI.Refresh() end
        end,
    })

    -- 动态构建 children，避免 nil 空洞导致 ipairs 截断
    local rows = {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            marginBottom = 2,
            gap = 6,
            children = {
                UI.Label {
                    text = "| 成就",
                    fontSize = 15, fontColor = S.textTitle, fontWeight = "bold",
                },
                UI.Label {
                    text = "达成目标领取奖励",
                    fontSize = 10, fontColor = S.textDim,
                },
            },
        },
        stageRow,
        levelRow,
        loginRow,
    }
    -- 排行榜名次成就 2026-04-21 起解锁
    if TodayKey() >= "20260421" then
        rows[#rows + 1] = campaignRow
        rows[#rows + 1] = towerRow
    end
    rows[#rows + 1] = chestRow
    rows[#rows + 1] = recruitRow

    return UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = S.border,
        padding = 10,
        gap = 8,
        children = rows,
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
                canClaim and UI.Panel {
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
            -- 中列
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
-- 周积分里程碑区
-- ============================================================================

function DailyTaskUI._BuildWeeklyMilestoneSection()
    local totalPts   = WPD.GetPoints()
    local milestones = WPD.MILESTONES
    local maxThr     = milestones[#milestones].threshold
    local ICON_SZ    = 24
    local CELL_SZ    = ICON_SZ + 12  -- 36

    local bgWeekly  = { 35, 30, 18, 230 }
    local borderW   = { 160, 130, 50, 150 }
    local barFillW  = { 200, 160, 40, 255 }
    local textWeekT = { 255, 215, 60, 255 }
    local textWeekD = { 160, 145, 100, 200 }
    local textWeekV = { 255, 230, 100, 255 }
    local btnActive = { 160, 115, 20, 200 }
    local btnInact  = { 60, 50, 20, 150 }

    local anyCanClaim = WPD.HasClaimable()

    local iconRow = {}
    for i, m in ipairs(milestones) do
        local canClaim, claimed, reached = WPD.GetMilestoneStatus(i)
        local reward = m.rewards[1]
        local milestoneIdx = i

        local iconOpts = { muted = claimed }
        if reward.type == "chest" then
            local cdef = ChestData.GetChestDef(reward.id)
            if cdef then
                iconOpts.image = cdef.image
                iconOpts.label = cdef.name
            end
        end
        local icon = RewardIconMod.Create(UI, CELL_SZ, reward.id, reward.amount, iconOpts)

        iconRow[#iconRow + 1] = UI.Panel {
            width = CELL_SZ, height = CELL_SZ,
            flexShrink = 0,
            overflow = "visible",
            opacity = claimed and 0.35 or (reached and 1.0 or 0.5),
            pointerEvents = "auto",
            onClick = function()
                local ok, msg = WPD.ClaimMilestone(milestoneIdx)
                Toast.Show(msg, ok and S.textGreen or S.red)
                if ok then DailyTaskUI.Refresh() end
            end,
            children = {
                icon,
                canClaim and UI.Panel {
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

    local barH = 6
    local pct = maxThr > 0 and math.min(1, totalPts / maxThr) or 0

    local thresholdLabels = {}
    for _, m in ipairs(milestones) do
        thresholdLabels[#thresholdLabels + 1] = UI.Label {
            text = tostring(m.threshold),
            fontSize = 9,
            fontColor = (totalPts >= m.threshold) and textWeekT or textWeekD,
            textAlign = "center",
            flexGrow = 1,
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = bgWeekly,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = borderW,
        padding = 10,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Panel {
                width = 50,
                flexShrink = 0,
                alignItems = "center",
                justifyContent = "center",
                gap = 2,
                children = {
                    UI.Label { text = "本周", fontSize = 10, fontColor = textWeekD },
                    UI.Label { text = tostring(totalPts), fontSize = 22, fontColor = textWeekV, fontWeight = "bold" },
                    UI.Label { text = "积分", fontSize = 10, fontColor = textWeekD },
                },
            },
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
                        backgroundColor = { 60, 50, 20, 200 },
                        borderRadius = barH / 2,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(pct * 100) .. "%",
                                height = "100%",
                                backgroundColor = barFillW,
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
                        borderColor = anyCanClaim and borderW or { 80, 65, 30, 100 },
                        backgroundColor = anyCanClaim and btnActive or btnInact,
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
                                local ok = WPD.ClaimMilestone(idx)
                                if ok then claimed = true end
                            end
                            if claimed then
                                Toast.Show("周里程碑奖励已领取", S.textGreen)
                                DailyTaskUI.Refresh()
                            else
                                Toast.Show("没有可领取的奖励", S.textDim)
                            end
                        end,
                        children = {
                            UI.Label { text = "全部", fontSize = 11, fontColor = { 255, 230, 150, 255 }, textAlign = "center" },
                            UI.Label { text = "领取", fontSize = 11, fontColor = { 255, 230, 150, 255 }, textAlign = "center" },
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

    local sectionChildren = {
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
