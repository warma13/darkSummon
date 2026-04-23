-- Game/AdReliefUI.lua
-- 减负中心界面：里程碑进度、免广告券余额、加速信息

local AdReliefData   = require("Game.AdReliefData")
local Config         = require("Game.Config")
local Currency       = require("Game.Currency")
local Toast          = require("Game.Toast")
local RC             = require("Game.RewardController")
local RewardIconMod  = require("Game.RewardIcon")
local PrivilegeData  = require("Game.PrivilegeData")

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

-- 特权卡罗马数字符号
local PRIV_CARD_SYMBOLS = { "I", "II", "III", "IV", "V", "VI" }

-- 特权加成区（左右切换）
local _privilegeIdx = 1
local _privTitle = nil
local _privStatus = nil
local _privValLabels = {}
local _privNameLabels = {}

local PRIV_BUFF_LABELS = { "挂机时长", "冥晶收益", "收益翻倍", "宝箱掉率", "碎片掉率", "副本次数", "深渊裂隙", "世界Boss" }
-- 6 级渐进式特权卡加成值（青铜 → 红宝石）
local PRIV_CARD_VALS = {
    { "+1h", "+5%",  "5%",  "+5%",  "+5%",  "+0", "+0", "+0" },  -- 青铜
    { "+2h", "+10%", "10%", "+10%", "+10%", "+1", "+0", "+0" },  -- 白银
    { "+3h", "+15%", "15%", "+15%", "+15%", "+1", "+1", "+0" },  -- 黄金
    { "+4h", "+20%", "20%", "+20%", "+25%", "+2", "+1", "+1" },  -- 铂金
    { "+5h", "+25%", "25%", "+30%", "+35%", "+2", "+2", "+1" },  -- 钻石
    { "+6h", "+30%", "30%", "+40%", "+50%", "+3", "+3", "+2" },  -- 红宝石
}

-- 进度条 UI 引用
local _progressBarPriv = nil
local _progressLabelPriv = nil

function AdReliefUI.SetOnBack(fn)
    _onBack = fn
end

--- 刷新特权加成面板（按当前 _privilegeIdx 更新内容）
local function RefreshPrivilegePanel()
    local cards = PrivilegeData.TIER_CARDS
    local idx = _privilegeIdx
    local card = cards[idx]
    if not card then return end

    local currentTier = PrivilegeData.GetCurrentTierIndex()
    local pts = PrivilegeData.GetPoints()
    local unlocked = (idx <= currentTier)

    -- 标题：显示卡名 + 颜色 + 等级符号
    if _privTitle then
        local c = card.color or { 200, 200, 200 }
        local symbol = PRIV_CARD_SYMBOLS[idx] or ""
        _privTitle:SetText("特权加成 - " .. card.name)
        _privTitle:SetFontColor({ c[1], c[2], c[3], 255 })
    end

    -- 顶部装饰条颜色跟随卡片
    if pageRoot then
        local topBar = pageRoot:FindById("privTopBar")
        if topBar then
            local c = card.color or { 200, 200, 200 }
            topBar:SetStyle({ backgroundColor = { c[1], c[2], c[3], 200 } })
        end
    end

    -- 解锁状态
    if _privStatus then
        if unlocked then
            if idx == currentTier then
                _privStatus:SetText("当前等级（已解锁）")
            else
                _privStatus:SetText("已解锁")
            end
            _privStatus:SetFontColor({ 100, 220, 180, 255 })
        else
            local need = card.threshold - pts
            _privStatus:SetText("还需 " .. need .. " 点解锁（当前 " .. pts .. "/" .. card.threshold .. "）")
            _privStatus:SetFontColor({ 160, 150, 180, 180 })
        end
    end

    -- 进度条（总体积分进度）
    if _progressBarPriv then
        local maxThreshold = cards[#cards].threshold
        local pct = math.min(1, pts / maxThreshold)
        _progressBarPriv:SetStyle({ width = math.floor(pct * 100) .. "%" })
    end
    if _progressLabelPriv then
        local maxThreshold = cards[#cards].threshold
        _progressLabelPriv:SetText("总积分: " .. pts .. "/" .. maxThreshold .. "  (每天看满20次广告 = 1点)")
    end

    -- buff 值
    local vals = PRIV_CARD_VALS[idx]
    if vals then
        for i = 1, 8 do
            local v = vals[i] or "+0"
            local isActive = v ~= "+0" and v ~= "0%"
            if _privValLabels[i] then
                _privValLabels[i]:SetText(v)
                if unlocked then
                    _privValLabels[i]:SetFontColor(isActive and { 100, 220, 180, 255 } or { 80, 70, 90, 120 })
                else
                    _privValLabels[i]:SetFontColor(isActive and { 180, 170, 200, 160 } or { 80, 70, 90, 100 })
                end
            end
            if _privNameLabels[i] then
                if unlocked then
                    _privNameLabels[i]:SetFontColor(isActive and { 200, 190, 220, 255 } or { 120, 110, 130, 140 })
                else
                    _privNameLabels[i]:SetFontColor(isActive and { 160, 150, 180, 160 } or { 120, 110, 130, 120 })
                end
            end
        end
    end
end

--- 刷新界面数据
local function RefreshUI()
    if not pageRoot then return end

    -- 券余额（历史存量，无新来源）
    local tickets = AdReliefData.GetTickets()
    if _ticketLabel then
        _ticketLabel:SetText(tostring(tickets))
    end
    local ticketRow = pageRoot:FindById("ticketBalanceRow")
    if ticketRow then
        ticketRow:SetVisible(tickets > 0)
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

    -- 免广卡状态
    local adFreeStatus = pageRoot:FindById("adFreeStatus")
    local adFreeDesc = pageRoot:FindById("adFreeDesc")
    if adFreeStatus and adFreeDesc then
        if AdReliefData.IsAdFreeToday() then
            adFreeStatus:SetText("已激活")
            adFreeStatus:SetFontColor({ 100, 255, 160, 255 })
            adFreeDesc:SetText("今日免广卡已生效，所有广告自动跳过")
        else
            local cur, target = AdReliefData.GetAdFreeProgress()
            adFreeStatus:SetText(cur .. "/" .. target)
            adFreeStatus:SetFontColor({ 255, 220, 100, 200 })
            adFreeDesc:SetText("每日看满" .. target .. "次广告，当天免看所有广告")
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

    -- 尝试发放每日特权积分（打开减负中心时检查）
    PrivilegeData.TryAwardDailyPoint(todayAds)

    -- 特权加成面板
    RefreshPrivilegePanel()
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

--- 创建特权加成面板（支持左右切换 6 级特权卡 + 积分进度条）
local function CreatePrivilegePanel()
    -- 默认显示当前等级或下一等级
    local curTier = PrivilegeData.GetCurrentTierIndex()
    _privilegeIdx = math.max(1, curTier > 0 and curTier or 1)
    _privValLabels = {}
    _privNameLabels = {}

    _privTitle = UI.Label {
        text = "特权加成",
        fontSize = 17,
        fontColor = { 255, 220, 100, 255 },
        fontWeight = "bold",
        flexShrink = 1,
    }

    _privStatus = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 160, 150, 180, 180 },
    }

    -- 积分进度条
    _progressBarPriv = UI.Panel {
        width = "0%", height = "100%",
        backgroundColor = { 255, 200, 60, 220 },
        borderRadius = 5,
    }
    _progressLabelPriv = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = { 160, 150, 180, 180 },
    }

    -- 等级节点指示器（6 个带标签的小圆点）
    local tierDots = {}
    for i, card in ipairs(PrivilegeData.TIER_CARDS) do
        local c = card.color
        local isUnlocked = (i <= curTier)
        local dotBg = isUnlocked and { c[1], c[2], c[3], 255 } or { 50, 45, 65, 180 }
        local dotBorder = isUnlocked and { c[1], c[2], c[3], 180 } or { 70, 65, 90, 120 }
        tierDots[#tierDots + 1] = UI.Panel {
            width = 14, height = 14,
            borderRadius = 7,
            backgroundColor = dotBg,
            borderWidth = isUnlocked and 2 or 1,
            borderColor = dotBorder,
            marginLeft = (i == 1) and 0 or 6,
            justifyContent = "center",
            alignItems = "center",
            children = isUnlocked and {
                UI.Label {
                    text = "✓",
                    fontSize = 8,
                    fontColor = { 255, 255, 255, 255 },
                    fontWeight = "bold",
                },
            } or {},
        }
    end

    -- 8 项 buff 网格（带交替背景）
    local gridChildren = {}
    for i = 1, 8 do
        local nameLabel = UI.Label {
            text = PRIV_BUFF_LABELS[i],
            fontSize = 13,
            fontColor = { 120, 110, 130, 140 },
        }
        local valLabel = UI.Label {
            text = "+0",
            fontSize = 14,
            fontWeight = "bold",
            fontColor = { 80, 70, 90, 120 },
        }
        _privNameLabels[i] = nameLabel
        _privValLabels[i] = valLabel

        local rowBg = (i % 2 == 1) and { 35, 30, 55, 100 } or { 25, 22, 42, 60 }
        gridChildren[#gridChildren + 1] = UI.Panel {
            width = "48%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 5, paddingBottom = 5,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = rowBg,
            borderRadius = 6,
            children = { nameLabel, valLabel },
        }
    end

    local n = #PrivilegeData.TIER_CARDS
    local panel = UI.Panel {
        width = "100%",
        backgroundColor = { 20, 18, 38, 240 },
        borderRadius = 14,
        borderWidth = 1.5,
        borderColor = { 180, 150, 80, 100 },
        paddingTop = 0, paddingBottom = 16,
        paddingLeft = 0, paddingRight = 0,
        flexDirection = "column",
        gap = 0,
        overflow = "hidden",
        children = {
            -- 顶部装饰条（卡片颜色渐变带）
            UI.Panel {
                id = "privTopBar",
                width = "100%", height = 4,
                backgroundColor = { 205, 127, 50, 200 },
            },
            -- 卡面主体区
            UI.Panel {
                width = "100%",
                paddingTop = 12, paddingBottom = 10,
                paddingLeft = 16, paddingRight = 16,
                flexDirection = "column",
                gap = 8,
                children = {
                    -- 标题行：[<]  特权加成 - XX卡  [>]
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Panel {
                                width = 30, height = 30,
                                justifyContent = "center", alignItems = "center",
                                borderRadius = 15,
                                backgroundColor = { 50, 40, 70, 200 },
                                borderWidth = 1,
                                borderColor = { 100, 80, 140, 150 },
                                onClick = function()
                                    _privilegeIdx = _privilegeIdx - 1
                                    if _privilegeIdx < 1 then _privilegeIdx = n end
                                    RefreshPrivilegePanel()
                                end,
                                children = {
                                    UI.Label { text = "<", fontSize = 16, fontColor = { 220, 200, 255, 255 }, fontWeight = "bold" },
                                },
                            },
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1,
                                alignItems = "center",
                                children = { _privTitle },
                            },
                            UI.Panel {
                                width = 30, height = 30,
                                justifyContent = "center", alignItems = "center",
                                borderRadius = 15,
                                backgroundColor = { 50, 40, 70, 200 },
                                borderWidth = 1,
                                borderColor = { 100, 80, 140, 150 },
                                onClick = function()
                                    _privilegeIdx = _privilegeIdx + 1
                                    if _privilegeIdx > n then _privilegeIdx = 1 end
                                    RefreshPrivilegePanel()
                                end,
                                children = {
                                    UI.Label { text = ">", fontSize = 16, fontColor = { 220, 200, 255, 255 }, fontWeight = "bold" },
                                },
                            },
                        },
                    },
                    -- 解锁状态
                    _privStatus,
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 120, 100, 80, 50 },
                    },
                    -- buff 网格
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "space-between",
                        gap = 4,
                        children = gridChildren,
                    },
                },
            },
            -- 底部区：进度条 + 等级圆点
            UI.Panel {
                width = "100%",
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 8,
                flexDirection = "column",
                gap = 6,
                backgroundColor = { 15, 12, 28, 200 },
                children = {
                    -- 积分进度条
                    UI.Panel {
                        width = "100%", height = 10,
                        backgroundColor = { 40, 35, 60, 200 },
                        borderRadius = 5,
                        overflow = "hidden",
                        children = { _progressBarPriv },
                    },
                    _progressLabelPriv,
                    -- 等级节点指示器
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        paddingTop = 2, paddingBottom = 6,
                        children = tierDots,
                    },
                    -- 提示
                    UI.Label {
                        text = "每天看满20次广告获得1点，累计解锁更高等级特权",
                        fontSize = 10,
                        fontColor = { 100, 90, 120, 130 },
                        textAlign = "center",
                        width = "100%",
                        paddingBottom = 4,
                    },
                },
            },
        },
    }

    RefreshPrivilegePanel()
    return panel
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
                    -- 免广卡状态区
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 25, 30, 50, 220 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 100, 220, 180, 100 },
                        paddingTop = 16, paddingBottom = 16,
                        paddingLeft = 20, paddingRight = 20,
                        flexDirection = "column",
                        gap = 8,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 8,
                                children = {
                                    UI.Label {
                                        text = "免广卡",
                                        fontSize = 18,
                                        fontColor = { 255, 220, 100, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Panel { flexGrow = 1 },
                                    UI.Label {
                                        id = "adFreeStatus",
                                        text = "",
                                        fontSize = 13,
                                        fontColor = { 100, 220, 180, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                id = "adFreeDesc",
                                text = "每日看满20次广告，当天免看所有广告",
                                fontSize = 12,
                                fontColor = { 160, 150, 180, 180 },
                            },
                            -- 免广券余额（小字显示，仅历史存量时显示）
                            UI.Panel {
                                id = "ticketBalanceRow",
                                width = "100%",
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                children = {
                                    Currency.IconWidget(UI, "ad_ticket", 20),
                                    UI.Label {
                                        text = "免广告券",
                                        fontSize = 12,
                                        fontColor = { 140, 130, 160, 180 },
                                    },
                                    _ticketLabel,
                                    UI.Panel { flexGrow = 1 },
                                    UI.Label {
                                        text = "历史存量",
                                        fontSize = 10,
                                        fontColor = { 100, 90, 120, 120 },
                                    },
                                },
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
                                    CreateMilestoneNode(1, { threshold = 3,  rewards = {{ id = "nether_crystal_pack", amount = 1 }} }),
                                    CreateMilestoneNode(2, { threshold = 6,  rewards = {{ id = "dungeon_ticket", amount = 1 }} }),
                                    CreateMilestoneNode(3, { threshold = 9,  rewards = {{ id = "nether_crystal_pack", amount = 4 }} }),
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
                                    CreateMilestoneNode(4, { threshold = 12, rewards = {
                                        { id = "shadow_essence_bag", amount = 2 }, { id = "dungeon_ticket", amount = 1 },
                                    }}),
                                    CreateMilestoneNode(5, { threshold = 15, rewards = {
                                        { id = "devour_stone", amount = 3000 }, { id = "dungeon_ticket", amount = 2 },
                                    }}),
                                    CreateMilestoneNode(6, { threshold = 17, rewards = {
                                        { id = "trial_ticket", amount = 3 }, { id = "recruit_ticket_select_box", amount = 10 },
                                    }}),
                                    CreateMilestoneNode(7, { threshold = 20, rewards = {
                                        { id = "boss_ticket", amount = 1 }, { id = "shadow_essence_bag", amount = 2 },
                                        { id = "nether_crystal_pack", amount = 4 }, { id = "recruit_ticket_select_box", amount = 20 },
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
                    -- 特权加成区（左右切换）
                    CreatePrivilegePanel(),
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
