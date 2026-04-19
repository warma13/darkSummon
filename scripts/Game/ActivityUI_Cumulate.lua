-- Game/ActivityUI_Cumulate.lua
-- 积天好礼页内容构建

return function(ctx, Shared)

local AccumulatedRewardData = require("Game.AccumulatedRewardData")
local Currency              = require("Game.Currency")
local Config                = require("Game.Config")
local Toast                 = require("Game.Toast")
local Tooltip               = require("Game.Tooltip")
local RewardIcon            = require("Game.RewardIcon")
local RewardDisplay         = require("Game.RewardDisplay")

local S                    = Shared.S
local REWARD_COLORS        = Shared.REWARD_COLORS
local FormatNum            = Shared.FormatNum
local GetRewardDisplay     = Shared.GetRewardDisplay
local GetRewardTooltipInfo = Shared.GetRewardTooltipInfo

local Mod = {}

-- ============================================================================
-- 积天好礼内容页
-- ============================================================================

local function BuildCumulateContent()
    -- 确保数据已加载
    if not AccumulatedRewardData.data then
        AccumulatedRewardData.Load()
    end
    -- 同步今日广告数
    AccumulatedRewardData.SyncFromDailyDeal()

    local accDays, todayAdCount, todayDone = AccumulatedRewardData.GetProgress()
    local rewards = AccumulatedRewardData.REWARDS
    local cycleLen = AccumulatedRewardData.CYCLE_LENGTH
    local adsNeeded = AccumulatedRewardData.ADS_PER_DAY

    -- ---- 顶部进度信息 ----
    local progressText = todayDone
        and ("今日已达标 ✓  累积 " .. accDays .. "/" .. cycleLen .. " 天")
        or ("今日广告 " .. todayAdCount .. "/" .. adsNeeded .. "  累积 " .. accDays .. "/" .. cycleLen .. " 天")

    local headerPanel = ctx.UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 10, paddingBottom = 8,
        paddingLeft = 14, paddingRight = 14,
        gap = 4,
        flexShrink = 0,
        children = {
            ctx.UI.Label {
                text = "积天好礼",
                fontSize = 16,
                fontColor = S.textPrimary,
                fontWeight = "bold",
            },
            ctx.UI.Label {
                text = "每日观看3个广告累积1天，集满领取丰厚奖励",
                fontSize = 10,
                fontColor = S.textSecondary,
            },
            ctx.UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = todayDone and { 40, 60, 30, 220 } or { 50, 35, 20, 220 },
                borderRadius = 10,
                borderWidth = 1,
                borderColor = todayDone and { 80, 160, 80, 150 } or { 180, 140, 60, 150 },
                children = {
                    ctx.UI.Label {
                        text = progressText,
                        fontSize = 12,
                        fontColor = todayDone and S.checkColor or S.goldAccent,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }

    -- ---- 奖励网格（5列3行 = 15格） ----
    local gridRows = {}
    for row = 0, 2 do
        local cols = {}
        for col = 0, 4 do
            local dayIndex = row * 5 + col + 1
            local reward = rewards[dayIndex]
            if not reward then break end

            local claimed = AccumulatedRewardData.IsClaimed(dayIndex)
            local canClaim = AccumulatedRewardData.CanClaim(dayIndex)
            local reached = accDays >= dayIndex  -- 已达到但可能未领取

            -- 背景和边框颜色
            local bg, border
            if claimed then
                bg = S.claimedBg; border = S.claimedBorder
            elseif canClaim then
                bg = S.todayBg; border = S.todayBorder
            elseif reached then
                bg = { 50, 35, 20, 220 }; border = { 180, 140, 60, 150 }
            else
                bg = S.futureBg; border = S.futureBorder
            end

            -- 卡片子项：顶部天数 → 中间 RewardIcon
            local rewardCurrId = reward.currency
            local rewardAmount = reward.amount

            local cellChildren = {
                -- 顶部：天数标签
                ctx.UI.Panel {
                    width = "100%",
                    alignItems = "center",
                    paddingTop = 3, paddingBottom = 2,
                    backgroundColor = { 0, 0, 0, 80 },
                    borderRadius = 0,
                    flexShrink = 0,
                    children = {
                        ctx.UI.Label {
                            text = dayIndex .. "天",
                            fontSize = 9,
                            fontColor = claimed and S.checkColor or (canClaim and S.goldAccent or S.textMuted),
                            fontWeight = "bold",
                        },
                    },
                },
                -- 下方：RewardIcon 直接填充剩余空间
                RewardIcon.Create(ctx.UI, "100%", rewardCurrId, rewardAmount, {
                    muted = claimed,
                    flexGrow = 1,
                    backgroundColor = { 15, 12, 28, 200 },
                }),
            }

            -- 已领取遮罩
            if claimed then
                cellChildren[#cellChildren + 1] = ctx.UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    backgroundColor = { 0, 0, 0, 120 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        ctx.UI.Label { text = "✓", fontSize = 22, fontColor = S.checkColor },
                    },
                }
            end

            cols[#cols + 1] = ctx.UI.Panel {
                flex = 1,
                aspectRatio = 1,
                backgroundColor = bg,
                borderRadius = 0,
                borderWidth = canClaim and 2 or 1,
                borderColor = border,
                flexDirection = "column",
                alignItems = "stretch",
                overflow = "visible",
                onClick = canClaim and function(self)
                    local ok, msg, claimedReward = AccumulatedRewardData.Claim(dayIndex)
                    if ok and claimedReward then
                        local cdef = Config.CURRENCY[claimedReward.id]
                        local displayRewards = {
                            {
                                icon = Currency.GetImage(claimedReward.id),
                                name = cdef and cdef.name or claimedReward.id,
                                amount = claimedReward.amount,
                            },
                        }
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayChestOpen()
                        RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                            title = "积天好礼",
                            rewards = displayRewards,
                            onClose = function()
                                ctx.RefreshContent()
                            end,
                        })
                    elseif ok then
                        Toast.Show("领取成功: " .. msg, { 120, 200, 80 })
                        ctx.RefreshContent()
                    else
                        Toast.Show(msg, { 255, 100, 80 })
                    end
                end or nil,
                children = cellChildren,
            }
        end

        gridRows[#gridRows + 1] = ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = cols,
        }
    end

    local gridPanel = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 8,
        gap = 4,
        children = gridRows,
    }

    -- ---- 底部领取按钮 ----
    -- 找到第一个可领取的天数
    local nextClaimDay = nil
    for i = 1, cycleLen do
        if AccumulatedRewardData.CanClaim(i) then
            nextClaimDay = i
            break
        end
    end

    local btnText, btnBg, btnClickable, btnBorderCol
    if nextClaimDay then
        local r = rewards[nextClaimDay]
        btnText = "领取第" .. nextClaimDay .. "天奖励"
        btnBg = { 200, 160, 50 }
        btnClickable = true
        btnBorderCol = { 255, 220, 100, 180 }
    else
        btnText = "暂无可领取"
        btnBg = { 60, 50, 70, 200 }
        btnClickable = false
        btnBorderCol = { 80, 70, 90, 100 }
    end

    local claimBtn = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 24, paddingRight = 24,
        paddingBottom = 8,
        flexShrink = 0,
        children = {
            ctx.UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 10,
                backgroundColor = btnBg,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = btnBorderCol,
                alignItems = "center",
                onClick = btnClickable and function()
                    local ok, msg, claimedReward = AccumulatedRewardData.Claim(nextClaimDay)
                    if ok and claimedReward then
                        local cdef = Config.CURRENCY[claimedReward.id]
                        local displayRewards = {
                            {
                                icon = Currency.GetImage(claimedReward.id),
                                name = cdef and cdef.name or claimedReward.id,
                                amount = claimedReward.amount,
                            },
                        }
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayChestOpen()
                        RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                            title = "积天好礼 · 第" .. nextClaimDay .. "天",
                            rewards = displayRewards,
                            onClose = function()
                                ctx.RefreshContent()
                            end,
                        })
                    elseif ok then
                        Toast.Show("领取成功: " .. msg, { 120, 200, 80 })
                        ctx.RefreshContent()
                    else
                        Toast.Show(msg, { 255, 100, 80 })
                    end
                end or nil,
                children = {
                    ctx.UI.Label {
                        text = btnText,
                        fontSize = 15,
                        fontColor = btnClickable and { 30, 20, 10 } or S.textMuted,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }

    return { headerPanel, gridPanel, claimBtn }
end

-- ============================================================================
-- 可复用奖励图标组件（带右下角数量 + 点击浮窗）
-- ============================================================================

Mod.BuildContent = BuildCumulateContent

return Mod
end
