-- Game/AdReliefUI.lua
-- 减负中心界面：里程碑进度、免广告券余额、加速信息

local AdReliefData = require("Game.AdReliefData")
local Config       = require("Game.Config")
local Currency     = require("Game.Currency")
local Toast        = require("Game.Toast")
local RC           = require("Game.RewardController")
local RewardIconMod = require("Game.RewardIcon")

local AdReliefUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type fun()|nil
local _onBack = nil

-- 缓存的 UI 引用
local _ticketLabel = nil
local _progressBar1 = nil   -- 第一行进度条 (0-9)
local _progressBar2 = nil   -- 第二行进度条 (9-20)
local _bonusLabel = nil
local _streakLabel = nil
local _milestoneNodes = {}  -- { btn, label }

function AdReliefUI.SetOnBack(fn)
    _onBack = fn
end

--- 刷新界面数据
local function RefreshUI()
    if not pageRoot then return end

    -- 券余额
    if _ticketLabel then
        _ticketLabel:SetText(tostring(AdReliefData.GetTickets()))
    end

    -- 今日广告进度（双进度条）
    local todayAds = AdReliefData.GetTodayAds()
    -- 第一行：0 ~ 9
    if _progressBar1 then
        local pct1 = math.min(1, todayAds / 9)
        _progressBar1:SetStyle({ width = math.floor(pct1 * 100) .. "%" })
    end
    local label1 = pageRoot:FindById("progressLabel1")
    if label1 then
        label1:SetText("今日看广告: " .. math.min(todayAds, 9) .. "/9")
    end
    -- 第二行：9 ~ 20（起点为 9）
    if _progressBar2 then
        local pct2 = math.max(0, math.min(1, (todayAds - 9) / (20 - 9)))
        _progressBar2:SetStyle({ width = math.floor(pct2 * 100) .. "%" })
    end
    local label2 = pageRoot:FindById("progressLabel2")
    if label2 then
        local cur2 = math.max(0, todayAds - 9)
        label2:SetText("进阶奖励: " .. cur2 .. "/11")
    end

    -- 加速信息
    if _bonusLabel then
        local hours = AdReliefData.GetBonusHours()
        _bonusLabel:SetText("当前: 每次广告获得 " .. hours .. "h 战斗加速时长")
    end
    if _streakLabel then
        local streak = AdReliefData.GetStreakDays()
        if streak > 0 then
            _streakLabel:SetText("已连续 " .. streak .. " 天看广告")
        else
            _streakLabel:SetText("今日看满3次开始计连续天数")
        end
    end

    -- 里程碑按钮状态（7 个里程碑）
    local milestones = AdReliefData.GetMilestones()
    for i, m in ipairs(milestones) do
        local node = _milestoneNodes[i]
        if node then
            if m.claimed then
                node.btn:SetStyle({
                    backgroundColor = { 40, 50, 40, 200 },
                    borderColor = { 60, 80, 60, 120 },
                    opacity = 0.5,
                })
                node.label:SetText("已领取")
                node.label:SetFontColor({ 100, 140, 100, 180 })
            elseif m.canClaim then
                node.btn:SetStyle({
                    backgroundColor = { 30, 60, 50, 240 },
                    borderColor = { 100, 220, 180, 255 },
                    opacity = 1,
                })
                node.label:SetText("可领取")
                node.label:SetFontColor({ 100, 220, 180, 255 })
            else
                node.btn:SetStyle({
                    backgroundColor = { 40, 40, 55, 200 },
                    borderColor = { 70, 70, 90, 150 },
                    opacity = 1,
                })
                node.label:SetText("")
                node.label:SetVisible(false)
            end
            -- 恢复可见性（从不可领变为可领取时）
            if m.claimed or m.canClaim then
                node.label:SetVisible(true)
            end
        end
    end
end

--- 创建里程碑节点（奖励图标 + 次数标签 + 领取状态）
---@param index number
---@param milestone table { threshold, rewards }
---@return any
local function CreateMilestoneNode(index, milestone)
    local threshold = milestone.threshold
    local rewards = milestone.rewards

    -- 状态标签（领取 / 已领）
    local statusLabel = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = { 140, 140, 160, 200 },
        fontWeight = "bold",
    }

    -- 奖励图标行（单个奖励时放大铺满）
    local singleReward = #rewards == 1
    local iconSize = singleReward and 48 or 30
    local iconRow = UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        gap = 3,
    }
    for _, r in ipairs(rewards) do
        iconRow:AddChild(RewardIconMod.Create(UI, iconSize, r.id, r.amount))
    end

    -- 整个里程碑容器（可点击领取）
    local btn = UI.Panel {
        minWidth = 56,
        backgroundColor = { 40, 40, 55, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 70, 70, 90, 150 },
        alignItems = "center",
        paddingTop = 6, paddingBottom = 6,
        paddingLeft = 4, paddingRight = 4,
        gap = 4,
        onClick = function(self)
            local milestones = AdReliefData.GetMilestones()
            local m = milestones[index]
            if m and m.canClaim then
                local ok, claimedRewards = AdReliefData.ClaimMilestone(index)
                if ok and claimedRewards then
                    RC.ShowCurrency(UI, pageRoot, claimedRewards[1].id, claimedRewards[1].amount, "里程碑奖励", RefreshUI)
                end
            elseif m and m.claimed then
                Toast.Show("已领取", { 160, 160, 160 })
            else
                Toast.Show("看广告达" .. threshold .. "次后可领取", { 200, 180, 100 })
            end
        end,
        children = {
            iconRow,
            statusLabel,
        },
    }

    _milestoneNodes[index] = { btn = btn, label = statusLabel }
    return UI.Panel {
        alignItems = "center",
        gap = 3,
        flexShrink = 1,
        flex = 1,
        children = {
            UI.Label {
                text = threshold .. "次",
                fontSize = 10,
                fontColor = { 160, 150, 180, 180 },
            },
            btn,
        },
    }
end

---@param uiModule any
---@return any
function AdReliefUI.CreatePage(uiModule)
    UI = uiModule
    _milestoneNodes = {}

    -- 券余额标签
    _ticketLabel = UI.Label {
        text = "0",
        fontSize = 28,
        fontColor = { 100, 220, 180, 255 },
        fontWeight = "bold",
    }

    -- 双进度条
    _progressBar1 = UI.Panel {
        width = "0%", height = "100%",
        backgroundColor = { 100, 220, 180, 200 },
        borderRadius = 4,
    }
    _progressBar2 = UI.Panel {
        width = "0%", height = "100%",
        backgroundColor = { 100, 220, 180, 200 },
        borderRadius = 4,
    }

    -- 加速信息
    _bonusLabel = UI.Label {
        text = "当前: 每次广告获得 1h 战斗加速时长",
        fontSize = 14,
        fontColor = { 255, 220, 100, 255 },
    }
    _streakLabel = UI.Label {
        text = "今日看满3次开始计连续天数",
        fontSize = 12,
        fontColor = { 160, 150, 180, 180 },
    }

    pageRoot = UI.Panel {
        id = "adReliefPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 12, 10, 24, 245 },
        flexDirection = "column",
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%", height = 48,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = { 20, 16, 36, 255 },
                children = {
                    UI.Label {
                        text = "减负中心",
                        fontSize = 20,
                        fontColor = { 220, 200, 255, 255 },
                        fontWeight = "bold",
                    },
                    -- 右上角关闭按钮
                    UI.Panel {
                        position = "absolute",
                        top = 6, right = 8,
                        width = 36, height = 36,
                        justifyContent = "center",
                        alignItems = "center",
                        onClick = function(self)
                            if _onBack then _onBack() end
                        end,
                        children = {
                            UI.Label {
                                text = "X",
                                fontSize = 18,
                                fontColor = { 180, 160, 200, 200 },
                            },
                        },
                    },
                },
            },
            -- 内容区（可滚动）
            UI.ScrollView {
                width = "100%",
                flexGrow = 1, flexShrink = 1, flexBasis = 0,
                contentContainerStyle = {
                    flexDirection = "column",
                    alignItems = "center",
                    paddingTop = 16, paddingBottom = 16,
                    paddingLeft = 16, paddingRight = 16,
                    gap = 16,
                },
                children = {
                    -- 免广告券余额区
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 25, 30, 50, 220 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 100, 220, 180, 100 },
                        paddingTop = 16, paddingBottom = 16,
                        paddingLeft = 20, paddingRight = 20,
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 12,
                        children = {
                            -- 券图标
                            Currency.IconWidget(UI, "ad_ticket", 36),
                            UI.Panel {
                                flexDirection = "column",
                                gap = 2,
                                children = {
                                    UI.Label {
                                        text = "免广告券",
                                        fontSize = 14,
                                        fontColor = { 160, 150, 180, 200 },
                                    },
                                    _ticketLabel,
                                },
                            },
                            UI.Panel { flexGrow = 1 },
                            UI.Label {
                                text = "可抵扣广告",
                                fontSize = 12,
                                fontColor = { 120, 110, 140, 150 },
                            },
                        },
                    },
                    -- 进度条区：第一行 (3, 6, 9)
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 25, 30, 50, 220 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 80, 60, 120, 100 },
                        paddingTop = 14, paddingBottom = 14,
                        paddingLeft = 16, paddingRight = 16,
                        flexDirection = "column",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "今日看广告: 0~9 次",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 200 },
                                id = "progressLabel1",
                            },
                            -- 进度条
                            UI.Panel {
                                width = "100%", height = 8,
                                backgroundColor = { 40, 35, 60, 200 },
                                borderRadius = 4,
                                overflow = "hidden",
                                children = { _progressBar1 },
                            },
                            -- 里程碑节点
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-around",
                                alignItems = "flex-start",
                                children = {
                                    CreateMilestoneNode(1, { threshold = 3,  rewards = {{ id = "ad_ticket", amount = 1 }} }),
                                    CreateMilestoneNode(2, { threshold = 6,  rewards = {{ id = "ad_ticket", amount = 1 }} }),
                                    CreateMilestoneNode(3, { threshold = 9,  rewards = {{ id = "ad_ticket", amount = 1 }} }),
                                },
                            },
                        },
                    },
                    -- 进度条区：第二行 (12, 15, 17, 20)
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 25, 30, 50, 220 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 80, 60, 120, 100 },
                        paddingTop = 14, paddingBottom = 14,
                        paddingLeft = 16, paddingRight = 16,
                        flexDirection = "column",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "看广告: 9~20 次",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 200 },
                                id = "progressLabel2",
                            },
                            -- 进度条
                            UI.Panel {
                                width = "100%", height = 8,
                                backgroundColor = { 40, 35, 60, 200 },
                                borderRadius = 4,
                                overflow = "hidden",
                                children = { _progressBar2 },
                            },
                            -- 里程碑节点
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-around",
                                alignItems = "flex-start",
                                children = {
                                    CreateMilestoneNode(4, { threshold = 12, rewards = {{ id = "ad_ticket", amount = 2 }} }),
                                    CreateMilestoneNode(5, { threshold = 15, rewards = {
                                        { id = "ad_ticket", amount = 3 }, { id = "dungeon_ticket", amount = 2 },
                                    }}),
                                    CreateMilestoneNode(6, { threshold = 17, rewards = {
                                        { id = "ad_ticket", amount = 3 }, { id = "recruit_ticket_select_box", amount = 10 },
                                    }}),
                                    CreateMilestoneNode(7, { threshold = 20, rewards = {
                                        { id = "ad_ticket", amount = 5 }, { id = "recruit_ticket_select_box", amount = 5 },
                                        { id = "platinum_chest", amount = 5 }, { id = "trial_ticket", amount = 10 },
                                        { id = "dungeon_ticket", amount = 3 },
                                    }}),
                                },
                            },
                        },
                    },
                    -- 加速信息区
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 25, 30, 50, 220 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 200, 180, 60, 80 },
                        paddingTop = 14, paddingBottom = 14,
                        paddingLeft = 20, paddingRight = 20,
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = "2倍速加成",
                                fontSize = 16,
                                fontColor = { 255, 220, 100, 255 },
                                fontWeight = "bold",
                            },
                            _bonusLabel,
                            _streakLabel,
                            -- 规则说明
                            UI.Panel {
                                width = "100%", height = 1,
                                marginTop = 4, marginBottom = 4,
                                backgroundColor = { 100, 80, 60, 60 },
                            },
                            UI.Label {
                                text = "看广告获得战斗加速时长（2倍速）",
                                fontSize = 11,
                                fontColor = { 120, 110, 130, 140 },
                            },
                            UI.Label {
                                text = "每日≥3次广告计入连续天数",
                                fontSize = 11,
                                fontColor = { 120, 110, 130, 140 },
                            },
                            UI.Label {
                                text = "连续1天: 2h/次 | 连续3天: 3h/次",
                                fontSize = 11,
                                fontColor = { 120, 110, 130, 140 },
                            },
                            UI.Label {
                                text = "中断则每天减1h，最低1h/次",
                                fontSize = 11,
                                fontColor = { 120, 110, 130, 140 },
                            },
                        },
                    },
                },
            },
            -- 底部按钮栏：左返回 + 中一键领取
            UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 16,
                paddingLeft = 16, paddingRight = 16,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Button {
                        text = "返回",
                        width = 120, height = 44,
                        fontSize = 16,
                        variant = "outline",
                        onClick = function(self)
                            if _onBack then _onBack() end
                        end,
                    },
                    UI.Button {
                        text = "一键领取",
                        width = 180, height = 44,
                        fontSize = 16,
                        variant = "primary",
                        onClick = function(self)
                            local milestones = AdReliefData.GetMilestones()
                            local claimed = 0
                            for i, m in ipairs(milestones) do
                                if m.canClaim then
                                    local ok = AdReliefData.ClaimMilestone(i)
                                    if ok then claimed = claimed + 1 end
                                end
                            end
                            if claimed > 0 then
                                Toast.Show("已领取 " .. claimed .. " 个里程碑奖励", { 100, 220, 180 })
                                RefreshUI()
                            else
                                Toast.Show("暂无可领取的奖励", { 160, 160, 160 })
                            end
                        end,
                    },
                },
            },
        },
    }

    RefreshUI()
    return pageRoot
end

--- 刷新（外部调用）
function AdReliefUI.Refresh()
    RefreshUI()
end

return AdReliefUI
