-- Game/AdReliefUI.lua
-- 减负中心界面：里程碑进度、免广告券余额、加速信息

local AdReliefData = require("Game.AdReliefData")
local Config       = require("Game.Config")
local Currency     = require("Game.Currency")
local Toast        = require("Game.Toast")
local RC           = require("Game.RewardController")

local AdReliefUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type fun()|nil
local _onBack = nil

-- 缓存的 UI 引用
local _ticketLabel = nil
local _progressBar = nil
local _progressLabel = nil
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

    -- 今日广告进度
    local todayAds = AdReliefData.GetTodayAds()
    local maxAds = 9  -- 3个里程碑 * 3次
    if _progressLabel then
        _progressLabel:SetText("今日看广告: " .. todayAds .. "/" .. maxAds)
    end
    if _progressBar then
        local pct = math.min(1, todayAds / maxAds)
        _progressBar:SetStyle({ width = math.floor(pct * 100) .. "%" })
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

    -- 里程碑按钮状态
    local milestones = AdReliefData.GetMilestones()
    for i, m in ipairs(milestones) do
        local node = _milestoneNodes[i]
        if node then
            if m.claimed then
                node.btn:SetStyle({
                    backgroundColor = { 40, 50, 40, 200 },
                    borderColor = { 60, 80, 60, 120 },
                })
                node.label:SetText("已领取")
                node.label:SetFontColor({ 100, 140, 100, 180 })
            elseif m.canClaim then
                node.btn:SetStyle({
                    backgroundColor = { 100, 220, 180, 255 },
                    borderColor = { 140, 255, 200, 255 },
                })
                node.label:SetText("领取")
                node.label:SetFontColor({ 10, 40, 30, 255 })
            else
                node.btn:SetStyle({
                    backgroundColor = { 40, 40, 55, 200 },
                    borderColor = { 70, 70, 90, 150 },
                })
                node.label:SetText(todayAds .. "/" .. m.threshold)
                node.label:SetFontColor({ 140, 140, 160, 200 })
            end
        end
    end
end

--- 创建里程碑节点
---@param index number
---@param threshold number
---@return any
local function CreateMilestoneNode(index, threshold)
    local btnLabel = UI.Label {
        text = "0/" .. threshold,
        fontSize = 13,
        fontColor = { 140, 140, 160, 200 },
        fontWeight = "bold",
    }

    local btn = UI.Panel {
        width = 64, height = 56,
        backgroundColor = { 40, 40, 55, 200 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 70, 70, 90, 150 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            local milestones = AdReliefData.GetMilestones()
            local m = milestones[index]
            if m and m.canClaim then
                local ok = AdReliefData.ClaimMilestone(index)
                if ok then
                    RC.ShowCurrency(UI, pageRoot, "ad_ticket", 1, "里程碑奖励", RefreshUI)
                end
            elseif m and m.claimed then
                Toast.Show("已领取", { 160, 160, 160 })
            else
                Toast.Show("看广告达" .. threshold .. "次后可领取", { 200, 180, 100 })
            end
        end,
        children = {
            -- 券图标（简化为文字）
            UI.Label {
                text = "x1",
                fontSize = 11,
                fontColor = { 100, 220, 180, 200 },
            },
            btnLabel,
        },
    }

    _milestoneNodes[index] = { btn = btn, label = btnLabel }
    return UI.Panel {
        alignItems = "center",
        gap = 4,
        children = {
            UI.Label {
                text = threshold .. "次",
                fontSize = 11,
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

    -- 进度条
    _progressBar = UI.Panel {
        width = "0%", height = "100%",
        backgroundColor = { 100, 220, 180, 200 },
        borderRadius = 4,
    }

    _progressLabel = UI.Label {
        text = "今日看广告: 0/9",
        fontSize = 12,
        fontColor = { 180, 170, 200, 200 },
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
            -- 内容区
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexDirection = "column",
                alignItems = "center",
                paddingTop = 20, paddingBottom = 20,
                paddingLeft = 16, paddingRight = 16,
                gap = 16,
                children = {
                    -- 免广告券余额区
                    UI.Panel {
                        width = "100%",
                        maxWidth = 320,
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
                    -- 进度条区
                    UI.Panel {
                        width = "100%",
                        maxWidth = 320,
                        backgroundColor = { 25, 30, 50, 220 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 80, 60, 120, 100 },
                        paddingTop = 14, paddingBottom = 14,
                        paddingLeft = 20, paddingRight = 20,
                        flexDirection = "column",
                        gap = 10,
                        children = {
                            _progressLabel,
                            -- 进度条底
                            UI.Panel {
                                width = "100%", height = 10,
                                backgroundColor = { 40, 35, 60, 200 },
                                borderRadius = 5,
                                overflow = "hidden",
                                children = {
                                    _progressBar,
                                },
                            },
                            -- 里程碑节点
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-around",
                                alignItems = "flex-start",
                                children = {
                                    CreateMilestoneNode(1, 3),
                                    CreateMilestoneNode(2, 6),
                                    CreateMilestoneNode(3, 9),
                                },
                            },
                        },
                    },
                    -- 加速信息区
                    UI.Panel {
                        width = "100%",
                        maxWidth = 320,
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
            -- 底部返回按钮
            UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 16,
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "返回",
                        width = 280, height = 44,
                        fontSize = 16,
                        variant = "primary",
                        onClick = function(self)
                            if _onBack then _onBack() end
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
