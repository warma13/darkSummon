-- Game/ActivityUI_Fund.lua
-- 基金商城页 + 占位页内容构建

return function(ctx, Shared)

local Config    = require("Game.Config")
local FundData  = require("Game.FundData")
local Currency  = require("Game.Currency")
local Toast     = require("Game.Toast")
local AdTracker = require("Game.AdTracker")
local RC        = require("Game.RewardController")

local S              = Shared.S
local FormatNum      = Shared.FormatNum
local REWARD_COLORS  = Shared.REWARD_COLORS

local Mod = {}

-- ============================================================================
-- 基金商城内容页
-- ============================================================================

local function BuildFundContent()
    FundData.Load()

    local fund
    for _, f in ipairs(FundData.FUNDS) do
        if f.id == ctx.currentFundTab then fund = f; break end
    end
    if not fund then fund = FundData.FUNDS[1] end

    -- ---- 子标签栏：噬魂石基金 | 锻魂铁基金 ----
    local subTabs = {}
    for _, f in ipairs(FundData.FUNDS) do
        local isActive = f.id == ctx.currentFundTab
        subTabs[#subTabs + 1] = ctx.UI.Panel {
            flex = 1,
            paddingTop = 8, paddingBottom = 8,
            alignItems = "center",
            backgroundColor = isActive and { 50, 35, 70, 240 } or { 25, 20, 40, 180 },
            borderBottomWidth = isActive and 2 or 0,
            borderColor = S.goldAccent,
            onClick = function()
                ctx.currentFundTab = f.id
                ctx.RefreshContent()
            end,
            children = {
                ctx.UI.Label {
                    text = f.name,
                    fontSize = 13,
                    fontColor = isActive and S.goldAccent or S.textSecondary,
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end

    local subTabBar = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexShrink = 0,
        children = subTabs,
    }

    -- ---- 基金卡片头 ----
    local totalReward = FundData.GetTotalReward(fund)
    local claimedCount = FundData.GetClaimedCount(fund.id)
    local currDef = Config.CURRENCY[fund.currency]
    local currName = currDef and currDef.name or fund.currency

    local headerCard = ctx.UI.Panel {
        width = "100%",
        paddingTop = 14, paddingBottom = 14,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = { 35, 28, 55, 240 },
        borderBottomWidth = 1,
        borderColor = { 60, 50, 80, 100 },
        flexShrink = 0,
        gap = 6,
        children = {
            ctx.UI.Label {
                text = fund.name,
                fontSize = 16,
                fontColor = S.textPrimary,
                fontWeight = "bold",
            },
            ctx.UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    ctx.UI.Label { text = "累计可获得", fontSize = 11, fontColor = S.textSecondary },
                    Currency.IconWidget(ctx.UI, fund.currency, 16),
                    ctx.UI.Label {
                        text = FormatNum(totalReward),
                        fontSize = 16,
                        fontColor = S.goldAccent,
                        fontWeight = "bold",
                    },
                },
            },
            ctx.UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    ctx.UI.Label { text = "ℹ", fontSize = 10, fontColor = S.textMuted },
                    ctx.UI.Label {
                        text = "观看广告解锁基金任务权限",
                        fontSize = 10,
                        fontColor = S.textMuted,
                    },
                },
            },
        },
    }

    -- ---- 里程碑列表（VirtualList 扁平化数据） ----
    local maxStage = FundData.GetMaxStage()
    local fundId = ctx.currentFundTab

    -- 构建扁平化数据：组头 + 里程碑行混合
    local flatData = {}
    for g = 1, FundData.TOTAL_GROUPS do
        local startIdx = (g - 1) * FundData.GROUP_SIZE + 1
        local endIdx = math.min(g * FundData.GROUP_SIZE, FundData.TOTAL_MILESTONES)
        -- 组头条目
        flatData[#flatData + 1] = {
            kind = "group_header",
            group = g,
        }
        -- 里程碑条目
        for idx = startIdx, endIdx do
            flatData[#flatData + 1] = {
                kind = "milestone",
                milestoneIndex = idx,
                stage = FundData.STAGES[idx],
                group = g,
            }
        end
    end

    local FUND_ROW_H = 80

    -- createItem: 通用行模板
    local function createFundItem()
        local item = ctx.UI.Panel {
            width = "100%",
            height = FUND_ROW_H,
        }
        -- === 组头层（absolute 叠放，避免隐藏时仍占布局空间） ===
        local ghPanel = ctx.UI.Panel {
            id = "ghPanel",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = { 30, 25, 48, 200 },
            borderTopWidth = 1,
            borderColor = { 70, 55, 100, 80 },
        }
        local ghTitle = ctx.UI.Label { id = "ghTitle", text = "", fontSize = 11, fontColor = S.textMuted, fontWeight = "bold" }
        local ghRight = ctx.UI.Panel { id = "ghRight", flexDirection = "row", alignItems = "center", gap = 6 }
        ghPanel:AddChild(ghTitle)
        ghPanel:AddChild(ghRight)
        item:AddChild(ghPanel)

        -- === 里程碑层（absolute 叠放，避免隐藏时仍占布局空间） ===
        local msPanel = ctx.UI.Panel {
            id = "msPanel",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 6, paddingBottom = 6,
            gap = 3,
        }
        -- 上行：关卡标签 + 按钮
        local msTopRow = ctx.UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
        }
        local msStageLabel = ctx.UI.Label { id = "msStage", text = "", fontSize = 11 }
        local msHint = ctx.UI.Label { id = "msHint", text = "ℹ 任务已完成即可领取奖励", fontSize = 8, fontColor = S.textMuted }
        local msTopLeft = ctx.UI.Panel { flexDirection = "row", alignItems = "center", gap = 4 }
        msTopLeft:AddChild(msStageLabel)
        msTopLeft:AddChild(msHint)
        local msBtn = ctx.UI.Panel {
            id = "msBtn",
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 4, paddingBottom = 4,
            borderRadius = 8,
            pointerEvents = "auto",
        }
        local msBtnLabel = ctx.UI.Label { id = "msBtnLabel", text = "", fontSize = 10 }
        local msBtnIcon = ctx.UI.Panel { id = "msBtnIcon", width = 18, height = 18, backgroundImage = "image/icon_lock.png", backgroundFit = "contain" }
        msBtn:AddChild(msBtnLabel)
        msBtn:AddChild(msBtnIcon)
        msTopRow:AddChild(msTopLeft)
        msTopRow:AddChild(msBtn)
        msPanel:AddChild(msTopRow)

        -- 下行：进度条 + 奖励
        local msBotRow = ctx.UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", gap = 6,
        }
        local msBarOuter = ctx.UI.Panel {
            flex = 1, height = 16,
            backgroundColor = { 15, 12, 25, 200 },
            borderRadius = 8, overflow = "hidden",
        }
        local msBarFill = ctx.UI.Panel { id = "msBarFill", width = "0%", height = "100%", borderRadius = 8 }
        local msBarText = ctx.UI.Panel {
            position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
            justifyContent = "center", alignItems = "center",
        }
        local msBarLabel = ctx.UI.Label { id = "msBarLabel", text = "", fontSize = 9, fontColor = { 255, 255, 255, 200 } }
        msBarText:AddChild(msBarLabel)
        msBarOuter:AddChild(msBarFill)
        msBarOuter:AddChild(msBarText)

        local msReward = ctx.UI.Panel { id = "msReward", flexDirection = "row", alignItems = "center", gap = 2, flexShrink = 0 }
        msBotRow:AddChild(msBarOuter)
        msBotRow:AddChild(msReward)
        msPanel:AddChild(msBotRow)
        item:AddChild(msPanel)

        -- 缓存引用
        item._ghPanel = ghPanel
        item._ghTitle = ghTitle
        item._ghRight = ghRight
        item._msPanel = msPanel
        item._msStageLabel = msStageLabel
        item._msBtn = msBtn
        item._msBtnLabel = msBtnLabel
        item._msBtnIcon = msBtnIcon
        item._msBarFill = msBarFill
        item._msBarLabel = msBarLabel
        item._msReward = msReward

        return item
    end

    -- 局部刷新：只重绑 VirtualList 可见项，不重建页面
    local vlist  -- forward declaration, assigned after VirtualList creation
    local function refreshFundList()
        if vlist then vlist:Refresh() end
    end

    -- bindItem: 根据 kind 绑定不同的数据
    local function bindFundItem(widget, data, index)
        if data.kind == "group_header" then
            widget._ghPanel:SetVisible(true)
            widget._msPanel:SetVisible(false)

            local g = data.group
            local groupUnlocked = FundData.IsGroupUnlocked(fundId, g)
            local canWatch = FundData.CanWatchAd(fundId, g)
            local adsWatched = FundData.GetGroupAds(fundId, g)

            widget._ghTitle:SetText("— 第" .. g .. "组 —")
            widget._ghTitle:SetStyle({ fontColor = groupUnlocked and S.checkColor or S.textMuted })

            widget._ghRight:ClearChildren()
            if groupUnlocked then
                widget._ghRight:AddChild(ctx.UI.Label { text = "已解锁 ✓", fontSize = 10, fontColor = S.checkColor })
            elseif canWatch then
                widget._ghRight:AddChild(ctx.UI.Label { text = adsWatched .. "/" .. FundData.ADS_PER_GROUP, fontSize = 10, fontColor = S.goldAccent })
                local adBtn = ctx.UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 3, paddingBottom = 3,
                    backgroundColor = { 100, 70, 180, 255 },
                    borderRadius = 8,
                    flexDirection = "row", alignItems = "center",
                    pointerEvents = "auto",
                    onClick = function()
                        local AdHelper = require("Game.AdHelper")
                        AdHelper.ShowRewardAd(function()
                            FundData.RecordAdWatch(fundId, g)
                            refreshFundList()
                        end)
                    end,
                    children = {
                        ctx.UI.Panel { width = 14, height = 14, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain", marginRight = 3 },
                        ctx.UI.Label { text = "观看", fontSize = 10, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
                    },
                }
                widget._ghRight:AddChild(adBtn)
            else
                widget._ghRight:AddChild(ctx.UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        ctx.UI.Panel { width = 14, height = 14, backgroundImage = "image/icon_lock.png", backgroundFit = "contain" },
                        ctx.UI.Label { text = "需先解锁上一组", fontSize = 10, fontColor = S.textMuted },
                    },
                })
            end

        else -- milestone
            widget._ghPanel:SetVisible(false)
            widget._msPanel:SetVisible(true)

            local idx = data.milestoneIndex
            local stage = data.stage
            local claimed = FundData.IsClaimed(fundId, idx)
            local canClaim = FundData.CanClaim(fundId, idx)
            local reached = maxStage >= stage
            local progress = math.min(maxStage / stage, 1.0)
            local progressPct = math.floor(progress * 100)

            -- 背景交替色
            widget._msPanel:SetStyle({
                backgroundColor = (idx % 2 == 0) and { 22, 18, 36, 200 } or { 26, 22, 42, 200 },
            })

            -- 关卡标签
            widget._msStageLabel:SetText("通关第" .. stage .. "关")
            widget._msStageLabel:SetStyle({
                fontColor = reached and S.textPrimary or S.textMuted,
                fontWeight = reached and "bold" or "normal",
            })

            -- 按钮
            widget._msBtnLabel:SetVisible(true)
            widget._msBtnIcon:SetVisible(false)
            if claimed then
                widget._msBtn:SetStyle({ backgroundColor = { 50, 45, 55, 200 }, borderWidth = 0 })
                widget._msBtnLabel:SetText("已领取")
                widget._msBtnLabel:SetStyle({ fontColor = S.textMuted, fontWeight = "normal" })
                widget._msBtn.props.onClick = nil
            elseif canClaim then
                widget._msBtn:SetStyle({
                    backgroundColor = { 40, 120, 60, 255 },
                    borderWidth = 1, borderColor = { 80, 200, 100, 200 },
                })
                widget._msBtnLabel:SetText("领取")
                widget._msBtnLabel:SetStyle({ fontColor = { 255, 255, 255 }, fontWeight = "bold" })
                widget._msBtn.props.onClick = function()
                    local ok, msg, rewardDef = FundData.Claim(fundId, idx)
                    if ok then
                        local success, AudioManager = pcall(require, "Game.AudioManager")
                        if success and AudioManager then AudioManager.PlayChestOpen() end
                        RC.ShowCurrency(ctx.UI, ctx.pageRoot,
                            rewardDef.id, rewardDef.amount, "基金奖励",
                            function() refreshFundList() end)
                    else
                        Toast.Show(msg, { 255, 100, 80 })
                        refreshFundList()
                    end
                end
            else
                widget._msBtn:SetStyle({ backgroundColor = { 45, 40, 55, 200 }, borderWidth = 0 })
                widget._msBtnLabel:SetVisible(false)
                widget._msBtnIcon:SetVisible(true)
                widget._msBtn.props.onClick = nil
            end

            -- 进度条
            widget._msBarFill:SetStyle({
                width = progressPct .. "%",
                backgroundColor = reached and { 80, 180, 80, 255 } or { 100, 70, 180, 255 },
            })
            widget._msBarLabel:SetText(math.min(maxStage, stage) .. "/" .. stage)

            -- 奖励
            widget._msReward:ClearChildren()
            widget._msReward:AddChild(Currency.IconWidget(ctx.UI, fund.currency, 16))
            widget._msReward:AddChild(ctx.UI.Label {
                text = "×" .. FundData.GetMilestoneReward(fund, idx),
                fontSize = 11,
                fontColor = claimed and S.textMuted or S.goldAccent,
                fontWeight = "bold",
            })
        end
    end

    local listPanel = ctx.UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        flexBasis = 0,
    }
    vlist = ctx.UI.VirtualList {
        width = "100%",
        height = "100%",
        data = flatData,
        itemHeight = FUND_ROW_H,
        itemGap = 0,
        poolBuffer = 5,
        createItem = createFundItem,
        bindItem = bindFundItem,
    }
    listPanel:AddChild(vlist)

    return { subTabBar, headerCard, listPanel }
end

-- ============================================================================
-- 占位内容页（其他标签暂未实现）
-- ============================================================================

local function BuildPlaceholderContent(tabDef)
    return {
        ctx.UI.Panel {
            width = "100%",
            flex = 1,
            justifyContent = "center",
            alignItems = "center",
            gap = 12,
            children = {
                ctx.UI.Label {
                    text = tabDef.emoji,
                    fontSize = 48,
                },
                ctx.UI.Label {
                    text = tabDef.label,
                    fontSize = 20,
                    fontColor = S.textPrimary,
                    fontWeight = "bold",
                },
                ctx.UI.Label {
                    text = "即将开放，敬请期待",
                    fontSize = 13,
                    fontColor = S.textMuted,
                },
            },
        },
    }
end


Mod.BuildContent = BuildFundContent
Mod.BuildPlaceholderContent = BuildPlaceholderContent

return Mod
end
