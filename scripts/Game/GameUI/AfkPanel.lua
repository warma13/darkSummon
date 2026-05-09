-- Game/GameUI/AfkPanel.lua
-- 挂机收益弹窗：面板 UI、Tab 切换、奖励展示

return function(GameUI, ctx, AfkCore)

local Config         = require("Game.Config")
local Currency       = require("Game.Currency")
local HeroData       = require("Game.HeroData")
local ChestData      = require("Game.ChestData")
local Toast          = require("Game.Toast")
local RewardDisplay  = require("Game.RewardDisplay")
local PrivilegeData  = require("Game.PrivilegeData")
local DivineBlessDB  = require("Game.DivineBlessData")

-- ============================================================================
-- 劳动翻倍确认弹窗
-- ============================================================================

local _laborDoubleDialog = nil

--- 创建劳动翻倍确认弹窗（懒初始化）
local function EnsureLaborDoubleDialog()
    if _laborDoubleDialog then return end
    _laborDoubleDialog = ctx.UI.Panel {
        id = "laborDoubleConfirmDialog",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 10001,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function(self)
            -- 点遮罩 = 不翻倍直接领取
            if GameUI._laborDoubleCb then
                GameUI._laborDoubleCb(1)
                GameUI._laborDoubleCb = nil
            end
            self:SetVisible(false)
        end,
        children = {
            ctx.UI.Panel {
                width = 280,
                paddingTop = 20, paddingBottom = 20,
                paddingLeft = 20, paddingRight = 20,
                gap = 12,
                backgroundColor = { 20, 25, 50, 245 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 255, 200, 60, 200 },
                alignItems = "center",
                pointerEvents = "auto",
                children = {
                    ctx.UI.Label {
                        text = "劳动加倍",
                        fontSize = 18,
                        fontColor = { 255, 200, 60, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Label {
                        id = "laborDoubleRemainLabel",
                        text = "今日剩余翻倍次数: 0",
                        fontSize = 14,
                        fontColor = { 100, 220, 180, 200 },
                    },
                    ctx.UI.Label {
                        text = "是否消耗1次翻倍机会，将本次收益×2？",
                        fontSize = 13,
                        fontColor = { 180, 170, 200, 200 },
                        textAlign = "center",
                    },
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        backgroundColor = { 100, 70, 160, 80 },
                    },
                    ctx.UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 12,
                        children = {
                            -- 不翻倍
                            ctx.UI.Panel {
                                paddingLeft = 20, paddingRight = 20,
                                paddingTop = 10, paddingBottom = 10,
                                backgroundColor = { 60, 50, 80, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 120, 100, 160, 150 },
                                justifyContent = "center",
                                alignItems = "center",
                                onClick = function(self)
                                    if GameUI._laborDoubleCb then
                                        GameUI._laborDoubleCb(1)
                                        GameUI._laborDoubleCb = nil
                                    end
                                    _laborDoubleDialog:SetVisible(false)
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "不翻倍",
                                        fontSize = 14,
                                        fontColor = { 200, 190, 220, 255 },
                                    },
                                },
                            },
                            -- 使用翻倍
                            ctx.UI.Panel {
                                paddingLeft = 20, paddingRight = 20,
                                paddingTop = 10, paddingBottom = 10,
                                backgroundColor = { 255, 200, 60, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 255, 230, 120, 255 },
                                justifyContent = "center",
                                alignItems = "center",
                                onClick = function(self)
                                    if GameUI._laborDoubleCb then
                                        local LDD = require("Game.LaborDayData")
                                        local mult = LDD.ConsumeDouble()
                                        GameUI._laborDoubleCb(mult)
                                        GameUI._laborDoubleCb = nil
                                    end
                                    _laborDoubleDialog:SetVisible(false)
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "翻倍 ×2",
                                        fontSize = 14,
                                        fontColor = { 30, 20, 10, 255 },
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
    ctx.uiRoot:AddChild(_laborDoubleDialog)
end

--- 请求劳动翻倍决策：有翻倍次数时弹确认框，否则直接回调 mult=1
---@param callback fun(laborMult: number)
local function RequestLaborDouble(callback)
    local LDD = require("Game.LaborDayData")
    if not LDD.IsActive() or LDD.GetDoubleRemaining() <= 0 then
        callback(1)
        return
    end
    -- 有翻倍次数，弹确认框
    EnsureLaborDoubleDialog()
    -- 更新剩余次数显示
    if ctx.uiRoot then
        local lbl = ctx.uiRoot:FindById("laborDoubleRemainLabel")
        if lbl then
            lbl:SetText("今日剩余翻倍次数: " .. LDD.GetDoubleRemaining() .. "/" .. LDD.DOUBLE_DAILY_LIMIT)
        end
    end
    GameUI._laborDoubleCb = callback
    _laborDoubleDialog:SetVisible(true)
end

-- ============================================================================
-- 领取逻辑
-- ============================================================================

--- 执行实际的挂机收益领取（统一入口，laborMult 已确定）
local function DoClaimIdle(laborMult)
    local pendingRewards = GameUI._pendingIdleRewards
    if not pendingRewards then return end
    -- 安全兜底：时间回拨惩罚状态不可领取
    if pendingRewards.timeTravelPenalty then return end

    local ServerTime = require("Game.ServerTime")

    -- ================================================================
    -- 反作弊：共识钳制 + 单调性保护
    -- ================================================================

    -- 1. 必须等共识就绪
    if GameUI._afkNeedsConsensus then
        if not ServerTime.IsLBReady() then
            Toast.Show("正在验证时间，请稍后重试")
            return
        end
        -- 共识已就绪，检查合法性
        if ServerTime.IsTimeValid() == false then
            GameUI._afkStartTime = time.elapsedTime
            GameUI._afkLastDisplaySec = -1
            GameUI._afkNeedsConsensus = false
            GameUI._pendingIdleRewards = nil
            GameUI.ShowPanel("idleRewardPanel", false)
            Toast.Show("检测到时间异常，离线收益已清零")
            return
        end

        -- 2. 共识钳制：用 ConsensusClampedNow 重算离线时长（截断拨前的部分）
        --    传入 afkLastClaimDay 做双层上限（共识 + 本地存档天）
        local clampedNow = ServerTime.ConsensusClampedNow(HeroData.stats.afkLastClaimDay)
        local claimTime = HeroData.stats.afkLastClaimTime or 0
        if claimTime > 0 then
            local clampedAfkSecs = clampedNow - claimTime
            -- 重新设定计时器起点（可能比登录时算的短）
            GameUI._afkStartTime = time.elapsedTime - clampedAfkSecs
            GameUI._afkLastDisplaySec = -1
            -- 如果钳制后变成负值（claimTime 超过钳制上限）→ 债务
            if clampedAfkSecs < 0 then
                print("[DoClaimIdle] Consensus clamped: debt=" .. math.abs(clampedAfkSecs) .. "s")
                GameUI._afkNeedsConsensus = false
                GameUI._pendingIdleRewards = nil
                GameUI.ShowPanel("idleRewardPanel", false)
                Toast.Show("时间异常，需在线追平后领取")
                return
            end
            print("[DoClaimIdle] Consensus clamped: afkSecs=" .. math.floor(clampedAfkSecs / 60) .. " min")
        end

        GameUI._afkNeedsConsensus = false
    end

    -- 通用共识验证：排行榜判定为作弊 → 禁止领取
    if ServerTime.IsTimeValid() == false then
        Toast.Show("检测到时间异常，无法领取挂机收益")
        return
    end

    local pushResult, pushSuffix = AfkCore.ClaimPendingPush(laborMult)

    if pendingRewards.isOffline then
        HeroData.ClaimIdleRewards(pendingRewards, laborMult)
        -- 单调性保护：afkLastClaimTime 只升不降，afkLastClaimDay 只升不降
        local oldClaimDay = HeroData.stats.afkLastClaimDay or 0
        local newClaimTime = ServerTime.ConsensusClampedNow(oldClaimDay)
        local oldClaimTime = HeroData.stats.afkLastClaimTime or 0
        HeroData.stats.afkLastClaimTime = math.max(oldClaimTime, newClaimTime)
        -- afkLastClaimDay 基于钳制后的时间计算，不直接用共识天（防止共识被污染）
        local LAUNCH_EPOCH = ServerTime.GetLaunchEpoch()
        local newClaimDay = math.floor((math.max(oldClaimTime, newClaimTime) - LAUNCH_EPOCH) / 86400)
        newClaimDay = math.max(0, newClaimDay)
        HeroData.stats.afkLastClaimDay = math.max(oldClaimDay, newClaimDay)
        GameUI._afkStartTime = time.elapsedTime
        GameUI._afkLastDisplaySec = -1
        GameUI._pendingIdleRewards = nil
        GameUI.ShowPanel("idleRewardPanel", false)
        local rewardItems = AfkCore.BuildRewardItems(pendingRewards)
        AfkCore.AppendPushRewardItems(rewardItems, pushResult)
        if #rewardItems > 0 and ctx.uiRoot then
            RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
                title = "离线收益" .. pushSuffix,
                rewards = rewardItems,
            })
        end
    else
        local elapsed = time.elapsedTime - GameUI._afkStartTime
        if elapsed < Config.IDLE_MIN_SECONDS then
            Toast.Show("挂机不足" .. Config.IDLE_MIN_SECONDS .. "秒，无法领取")
            return
        end
        AfkCore.GrantAndShowRewards(pendingRewards, "挂机收益" .. pushSuffix, laborMult)
    end
end

--- 点击挂机按钮：打开预览弹窗（不自动发放）
function GameUI.ClaimAfkReward()
    local rewards = AfkCore.CalcAfkRewardsNow()
    -- 显示预览弹窗（不发放奖励，领取时再判断最低时长）
    GameUI.ShowIdleRewards(rewards)
end

-- ============================================================================
-- 挂机离线收益弹窗
-- ============================================================================

--- 构建 Page1 内容：挂机收益
local function BuildIdlePage1()
    return ctx.UI.Panel {
        id = "idlePage1",
        width = "100%",
        alignItems = "center",
        gap = 8,
        children = {
            ctx.UI.Label {
                id = "idleTimeLabel",
                text = "",
                fontSize = 13,
                fontColor = { 160, 150, 180, 200 },
            },
            -- 分隔线
            ctx.UI.Panel {
                width = "90%", height = 1,
                marginTop = 2, marginBottom = 2,
                backgroundColor = { 100, 70, 160, 100 },
            },
            -- 奖励行：冥晶
            ctx.UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    Currency.IconWidget(ctx.UI, "nether_crystal", 20),
                    ctx.UI.Label {
                        id = "idleCrystalLabel",
                        text = "冥晶: +0", fontSize = 15,
                        fontColor = { 140, 80, 200, 255 },
                    },
                },
            },
            -- 奖励行：噬魂石
            ctx.UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    Currency.IconWidget(ctx.UI, "devour_stone", 20),
                    ctx.UI.Label {
                        id = "idleStoneLabel",
                        text = "噬魂石: +0", fontSize = 15,
                        fontColor = { 60, 160, 80, 255 },
                    },
                },
            },
            -- 奖励行：锻魂铁
            ctx.UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    Currency.IconWidget(ctx.UI, "forge_iron", 20),
                    ctx.UI.Label {
                        id = "idleIronLabel",
                        text = "锻魂铁: +0", fontSize = 15,
                        fontColor = { 130, 160, 200, 255 },
                    },
                },
            },
            -- 宝箱掉落区域（动态填充）
            ctx.UI.Panel {
                id = "idleChestDropArea",
                width = "100%",
                alignItems = "center",
                gap = 4,
            },
            -- 离线推关区域（动态填充）
            ctx.UI.Panel {
                id = "idlePushArea",
                width = "100%",
                alignItems = "center",
                gap = 4,
            },
            -- 分隔线
            ctx.UI.Panel {
                width = "90%", height = 1,
                marginTop = 2, marginBottom = 2,
                backgroundColor = { 100, 70, 160, 100 },
            },
            -- 按钮行：领取 + 立即领取
            ctx.UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 10,
                children = {
                    -- 领取按钮
                    ctx.UI.Panel {
                        id = "idleClaimBtn",
                        paddingLeft = 24, paddingRight = 24,
                        paddingTop = 10, paddingBottom = 10,
                        backgroundColor = { 120, 80, 200, 255 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 180, 140, 255, 180 },
                        alignItems = "center",
                        justifyContent = "center",
                        onClick = function(self)
                            if not GameUI._pendingIdleRewards then return end
                            -- 时间回拨惩罚：禁止领取
                            if GameUI._pendingIdleRewards.timeTravelPenalty then
                                Toast.Show("检测到时间异常，请等待时间恢复正常")
                                return
                            end
                            -- 非在线挂机需先检查最低时长
                            if not GameUI._pendingIdleRewards.isOffline then
                                local elapsed = time.elapsedTime - GameUI._afkStartTime
                                if elapsed < Config.IDLE_MIN_SECONDS then
                                    Toast.Show("挂机不足" .. Config.IDLE_MIN_SECONDS .. "秒，无法领取")
                                    return
                                end
                            end
                            -- 弹翻倍确认（无次数时直接跳过）
                            RequestLaborDouble(DoClaimIdle)
                        end,
                        children = {
                            ctx.UI.Label {
                                text = "领取", fontSize = 16,
                                fontColor = { 255, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 立即领取按钮（看广告领满时长收益）
                    ctx.UI.Panel {
                        id = "idleAdClaimBtn",
                        paddingLeft = 16, paddingRight = 16,
                        paddingTop = 10, paddingBottom = 10,
                        backgroundColor = { 200, 160, 50 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 255, 220, 100, 180 },
                        flexDirection = "column",
                        alignItems = "center",
                        justifyContent = "center",
                        gap = 2,
                        onClick = function(self)
                            if not AfkCore.CanAfkAdClaim() then
                                Toast.Show("今日立即领取次数已用完", { 255, 100, 80 })
                                return
                            end
                            local AdHelper = require("Game.AdHelper")
                            AdHelper.ShowRewardAd(function()
                                AfkCore.RecordAfkAdClaim()
                                local maxRewards = AfkCore.CalcAfkRewardsMax()
                                AfkCore.GrantAfkRewards(maxRewards)
                                GameUI._pendingIdleRewards = nil
                                GameUI.ShowPanel("idleRewardPanel", false)
                                local rewardItems = AfkCore.BuildRewardItems(maxRewards)
                                if #rewardItems > 0 and ctx.uiRoot then
                                    RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
                                        title = "满时长挂机收益",
                                        rewards = rewardItems,
                                    })
                                end
                            end)
                        end,
                        children = {
                            ctx.UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 4,
                                children = {
                                    ctx.UI.Panel {
                                        width = 16, height = 16,
                                        backgroundImage = "image/icon_watch_ad.png",
                                        backgroundFit = "contain",
                                    },
                                    ctx.UI.Label {
                                        id = "idleAdClaimText",
                                        text = "立即领取", fontSize = 14,
                                        fontColor = { 30, 20, 10 },
                                        fontWeight = "bold",
                                    },
                                    ctx.UI.Label {
                                        id = "idleAdClaimCount",
                                        text = "", fontSize = 12,
                                        fontColor = { 60, 40, 10, 200 },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 一键领取所有可领取的里程碑奖励
local function ClaimAllMilestones()
    local elapsed = AfkCore.GetTodayOnlineSeconds()
    local claimed = AfkCore.GetTodayMilestones()
    local count = 0
    local rewardList = {}  -- 用于显示的奖励列表
    for _, ms in ipairs(AfkCore.ONLINE_MILESTONES) do
        if elapsed >= ms.threshold and not claimed[ms.key] then
            claimed[ms.key] = true
            local r = ms.reward
            Currency.GrantReward(r, "OnlineMilestone")
            count = count + 1
            -- 构建显示用奖励条目
            local def = Config.CURRENCY and Config.CURRENCY[r.id]
            local iDef = not def and Config.ITEMS and Config.ITEMS[r.id] or nil
            local icon = (def and def.image) or (iDef and iDef.image) or "?"
            local name = (def and def.name) or (iDef and iDef.name) or r.id
            rewardList[#rewardList + 1] = { icon = icon, name = name, amount = r.amount }
        end
    end
    if count > 0 then
        HeroData.Save()
        if ctx.uiRoot then
            RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
                title = "在线好礼",
                rewards = rewardList,
            })
        end
        AfkCore.RefreshMilestoneUI()
    else
        Toast.Show("暂无可领取的奖励", { 180, 160, 120 })
    end
end

--- 构建 Page2 内容：在线送好礼
local function BuildIdlePage2()
    return ctx.UI.Panel {
        id = "idlePage2",
        width = "100%",
        alignItems = "center",
        gap = 6,
        children = {
            -- 里程碑奖励区域（动态填充）
            ctx.UI.Panel {
                id = "idleMilestoneArea",
                width = "100%",
                alignItems = "center",
                gap = 4,
                paddingTop = 4, paddingBottom = 4,
            },
            -- 分隔线
            ctx.UI.Panel {
                width = "90%", height = 1,
                marginTop = 2, marginBottom = 2,
                backgroundColor = { 100, 70, 160, 100 },
            },
            -- 一键领取按钮
            ctx.UI.Panel {
                id = "milestoneClaimAllBtn",
                paddingLeft = 32, paddingRight = 32,
                paddingTop = 10, paddingBottom = 10,
                marginTop = 4,
                backgroundColor = { 80, 180, 120, 255 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 120, 220, 160, 200 },
                alignItems = "center",
                justifyContent = "center",
                pointerEvents = "auto",
                onClick = function(self)
                    ClaimAllMilestones()
                end,
                children = {
                    ctx.UI.Label {
                        text = "领取",
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255 },
                    },
                },
            },
        },
    }
end

--- 切换挂机弹窗的 tab 页（add/remove 方式）
---@param tabIndex number 1=挂机收益, 2=在线送好礼
local function SwitchIdleTab(tabIndex)
    if not ctx.uiRoot then return end
    GameUI._idleTabIndex = tabIndex

    local container = ctx.uiRoot:FindById("idleTabContent")
    if not container then return end

    -- 清空旧页面内容
    container:ClearChildren()

    -- 添加新页面
    if tabIndex == 1 then
        container:AddChild(BuildIdlePage1())
        -- 若有待显示的奖励数据，刷新文本
        GameUI._refreshIdlePage1()
    else
        container:AddChild(BuildIdlePage2())
        AfkCore.RefreshMilestoneUI()
    end

    -- tab 高亮样式
    local tab1 = ctx.uiRoot:FindById("idleTab1")
    local tab2 = ctx.uiRoot:FindById("idleTab2")
    local activeColor    = { 120, 80, 200, 255 }
    local inactiveColor  = { 50, 45, 70, 200 }
    local activeBorder   = { 180, 140, 255, 220 }
    local inactiveBorder = { 80, 60, 120, 100 }

    if tab1 then
        tab1:SetStyle({
            backgroundColor = tabIndex == 1 and activeColor or inactiveColor,
            borderColor = tabIndex == 1 and activeBorder or inactiveBorder,
        })
    end
    if tab2 then
        tab2:SetStyle({
            backgroundColor = tabIndex == 2 and activeColor or inactiveColor,
            borderColor = tabIndex == 2 and activeBorder or inactiveBorder,
        })
    end
end

--- 创建挂机收益面板（全屏遮罩 + 居中卡片 + 双 tab 页，add/remove 切换）
function GameUI.CreateIdleRewardPanel()
    GameUI._idleTabIndex = 1

    local function closePanel()
        GameUI.ShowPanel("idleRewardPanel", false)
    end

    return ctx.UI.Panel {
        id = "idleRewardPanel",
        visible = false,
        position = "absolute",
        zIndex = 200,
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        onClick = function(self) closePanel() end,
        children = {
            ctx.UI.Panel {
                width = 340,
                paddingTop = 24, paddingBottom = 24,
                paddingLeft = 24, paddingRight = 24,
                gap = 8,
                backgroundColor = { 20, 25, 50, 245 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 140, 80, 200, 200 },
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,  -- 拦截点击，防止冒泡到遮罩关闭面板
                children = {
                    -- 右上角 X 关闭按钮
                    ctx.UI.Panel {
                        position = "absolute",
                        top = 4, right = 4,
                        width = 32, height = 32,
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self) closePanel() end,
                        children = {
                            ctx.UI.Label {
                                text = "✕", fontSize = 18,
                                fontColor = { 180, 160, 200, 200 },
                            },
                        },
                    },
                    -- ===== Tab 栏 =====
                    ctx.UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 8,
                        marginBottom = 4,
                        children = {
                            ctx.UI.Panel {
                                id = "idleTab1",
                                flex = 1,
                                paddingTop = 8, paddingBottom = 8,
                                backgroundColor = { 120, 80, 200, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 180, 140, 255, 220 },
                                alignItems = "center",
                                justifyContent = "center",
                                pointerEvents = "auto",
                                onClick = function(self) SwitchIdleTab(1) end,
                                children = {
                                    ctx.UI.Label {
                                        text = "挂机收益",
                                        fontSize = 14,
                                        fontWeight = "bold",
                                        fontColor = { 255, 255, 255 },
                                    },
                                },
                            },
                            ctx.UI.Panel {
                                id = "idleTab2",
                                flex = 1,
                                paddingTop = 8, paddingBottom = 8,
                                backgroundColor = { 50, 45, 70, 200 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 80, 60, 120, 100 },
                                alignItems = "center",
                                justifyContent = "center",
                                pointerEvents = "auto",
                                onClick = function(self) SwitchIdleTab(2) end,
                                children = {
                                    ctx.UI.Label {
                                        text = "在线送好礼",
                                        fontSize = 14,
                                        fontWeight = "bold",
                                        fontColor = { 255, 255, 255 },
                                    },
                                },
                            },
                        },
                    },
                    -- ===== 页面内容容器（由 SwitchIdleTab 动态填充） =====
                    ctx.UI.Panel {
                        id = "idleTabContent",
                        width = "100%",
                        alignItems = "center",
                    },
                },
            },
        },
    }
end

--- 刷新 Page1 上的奖励数据文本（Page1 已挂载到 DOM 后调用）
function GameUI._refreshIdlePage1()
    local rewards = GameUI._pendingIdleRewards
    if not rewards or not ctx.uiRoot then return end

    local timeLabel = ctx.uiRoot:FindById("idleTimeLabel")

    -- 时间回拨惩罚：显示负数倒计时
    if rewards.timeTravelPenalty then
        local penaltySecs = rewards.penaltySeconds or 0
        local timeStr = "时间异常 -" .. AfkCore.FormatHMS(penaltySecs) .. " 后可领取"
        if timeLabel then
            timeLabel:SetText(timeStr)
            timeLabel:SetFontColor({ 255, 60, 60, 255 })
        end
    else
        local maxSecs = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds() + DivineBlessDB.GetBuffValue("idle_extra")
        local secs = rewards.seconds
        local remainSecs = math.max(0, maxSecs - secs)
        local prefix = rewards.isOffline and "离线" or "挂机"
        local timeStr = prefix .. " " .. AfkCore.FormatHMS(secs) .. "  剩余 " .. AfkCore.FormatHMS(remainSecs)
        if timeLabel then
            timeLabel:SetText(timeStr)
            timeLabel:SetFontColor({ 160, 150, 180, 200 })
        end
    end

    local crystalLabel = ctx.uiRoot:FindById("idleCrystalLabel")
    if crystalLabel then crystalLabel:SetText("冥晶: +" .. rewards.nether_crystal) end

    local stoneLabel = ctx.uiRoot:FindById("idleStoneLabel")
    if stoneLabel then stoneLabel:SetText("噬魂石: +" .. rewards.devour_stone) end

    local ironLabel = ctx.uiRoot:FindById("idleIronLabel")
    if ironLabel then ironLabel:SetText("锻魂铁: +" .. rewards.forge_iron) end

    -- 填充宝箱掉落
    local chestArea = ctx.uiRoot:FindById("idleChestDropArea")
    if chestArea then
        chestArea:ClearChildren()
        if rewards.chestDrops then
            local hasChest = false
            for id, count in pairs(rewards.chestDrops) do
                if count > 0 then
                    hasChest = true
                    local cdef = ChestData.GetChestDef(id)
                    local chestName = cdef and cdef.name or id
                    local chestColor = cdef and cdef.color or { 200, 200, 200, 255 }
                    chestArea:AddChild(ctx.UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            (cdef and cdef.image) and ctx.UI.Panel {
                                width = 20, height = 20,
                                backgroundImage = cdef.image,
                                backgroundFit = "contain",
                            } or ctx.UI.Label {
                                text = (cdef and cdef.emoji) or "📦",
                                fontSize = 16,
                            },
                            ctx.UI.Label {
                                text = chestName .. ": +" .. count,
                                fontSize = 15,
                                fontColor = chestColor,
                            },
                        },
                    })
                end
            end
            if hasChest then
                chestArea:AddChild(ctx.UI.Panel {
                    width = "90%", height = 1,
                    marginTop = 2, marginBottom = 2,
                    backgroundColor = { 100, 70, 160, 80 },
                })
            end
        end
    end

    -- 填充离线推关区域
    local pushArea = ctx.uiRoot:FindById("idlePushArea")
    if pushArea then
        pushArea:ClearChildren()
        local pushResult = GameUI._pendingOfflinePush
        if pushResult then
            local pushed = pushResult.pushed or 0
            -- 分隔线
            pushArea:AddChild(ctx.UI.Panel {
                width = "90%", height = 1,
                marginTop = 2, marginBottom = 2,
                backgroundColor = pushed > 0 and { 200, 160, 60, 120 } or { 120, 120, 140, 80 },
            })
            if pushed > 0 then
                -- 推关标题
                pushArea:AddChild(ctx.UI.Label {
                    text = "离线推关 +" .. pushed .. " 关",
                    fontSize = 15, fontWeight = "bold",
                    fontColor = { 255, 200, 60, 255 },
                })

                -- 推关额外奖励（虚空契约）
                if pushResult.stageRewards then
                    local pr = pushResult.stageRewards
                    if pr.void_pact and pr.void_pact > 0 then
                        local vpDef = Config.CURRENCY and Config.CURRENCY["void_pact"]
                        pushArea:AddChild(ctx.UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 8,
                            children = {
                                vpDef and vpDef.image and ctx.UI.Panel {
                                    width = 20, height = 20,
                                    backgroundImage = vpDef.image,
                                    backgroundFit = "contain",
                                } or ctx.UI.Label { text = "📜", fontSize = 16 },
                                ctx.UI.Label {
                                    text = (vpDef and vpDef.name or "虚空契约") .. ": +" .. pr.void_pact,
                                    fontSize = 14,
                                    fontColor = { 180, 120, 255, 255 },
                                },
                            },
                        })
                    end
                end
                -- 提示
                pushArea:AddChild(ctx.UI.Label {
                    text = "推关资源已合并到上方收益",
                    fontSize = 11,
                    fontColor = { 140, 130, 160, 160 },
                })
            else
                -- 0关：卡关提示
                pushArea:AddChild(ctx.UI.Label {
                    text = "离线推关 +0 关（卡关中）",
                    fontSize = 14,
                    fontColor = { 180, 160, 140, 200 },
                })
                pushArea:AddChild(ctx.UI.Label {
                    text = "提升阵容战力可加快推关速度",
                    fontSize = 11,
                    fontColor = { 140, 130, 160, 160 },
                })
            end
        end
    end

    -- 领取按钮：时间异常时置灰
    local claimBtn = ctx.uiRoot:FindById("idleClaimBtn")
    if claimBtn then
        if rewards.timeTravelPenalty then
            claimBtn:SetStyle({
                backgroundColor = { 60, 55, 65, 200 },
                borderColor = { 80, 75, 85, 120 },
            })
        else
            claimBtn:SetStyle({
                backgroundColor = { 120, 80, 200, 255 },
                borderColor = { 180, 140, 255, 180 },
            })
        end
    end

    -- 立即领取按钮：时间异常/离线收益时隐藏，或每日次数用完时置灰
    local adClaimBtn = ctx.uiRoot:FindById("idleAdClaimBtn")
    if adClaimBtn then
        if rewards.isOffline then
            adClaimBtn:SetVisible(false)
        else
            adClaimBtn:SetVisible(true)
            local canClaim = AfkCore.CanAfkAdClaim()
            local remaining = AfkCore.GetAfkAdRemaining()
            adClaimBtn:SetStyle({
                backgroundColor = canClaim and { 200, 160, 50 } or { 60, 55, 65, 200 },
                borderColor = canClaim and { 255, 220, 100, 180 } or { 80, 75, 85, 120 },
            })
            local adText = ctx.uiRoot:FindById("idleAdClaimText")
            if adText then
                adText:SetText(canClaim and "立即领取" or "今日已达上限")
                adText:SetFontColor(canClaim and { 30, 20, 10 } or { 120, 110, 130, 180 })
            end
            local adCount = ctx.uiRoot:FindById("idleAdClaimCount")
            if adCount then
                adCount:SetText(remaining .. "/" .. AfkCore.AFK_AD_DAILY_MAX)
                adCount:SetFontColor(canClaim and { 60, 40, 10, 200 } or { 100, 90, 100, 150 })
            end
        end
    end
end

--- 显示挂机收益弹窗
---@param rewards table  HeroData.CalcIdleRewards() 的返回值
function GameUI.ShowIdleRewards(rewards)
    if not rewards or not ctx.uiRoot then return end

    -- 暂存待领取奖励
    GameUI._pendingIdleRewards = rewards

    -- 根据点击时的图标阶段切换到对应 tab
    local targetTab = GameUI._afkClickTab or 1
    GameUI._afkClickTab = nil
    SwitchIdleTab(targetTab)

    GameUI.ShowPanel("idleRewardPanel", true)
end

end
