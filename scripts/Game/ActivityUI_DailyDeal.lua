-- Game/ActivityUI_DailyDeal.lua
-- 每日特惠页内容构建

return function(ctx, Shared)

local DailyDealData = require("Game.DailyDealData")
local Currency      = require("Game.Currency")
local Toast         = require("Game.Toast")
local Config        = require("Game.Config")
local RewardIcon    = require("Game.RewardIcon")
local RewardDisplay = require("Game.RewardDisplay")
local AdTracker     = require("Game.AdTracker")

local S                   = Shared.S
local FormatNum           = Shared.FormatNum
local GetRewardDisplay    = Shared.GetRewardDisplay

local Mod = {}

-- ============================================================================
-- 每日特惠内容页
-- ============================================================================

--- 创建奖励行（免费礼包或广告奖励）
---@param label string       奖励名称
---@param desc string        奖励描述
---@param iconId string|nil  货币 id（用于图标）
---@param claimed boolean    是否已领取
---@param canClaim boolean   是否可领取
---@param onClaim function   领取回调
---@return any widget
local function CreateDealRow(label, desc, iconId, claimed, canClaim, onClaim)
    local iconWidget
    if iconId then
        iconWidget = Currency.IconWidget(ctx.UI, iconId, 28)
    else
        iconWidget = ctx.UI.Panel { width = 28, height = 28, backgroundImage = "image/icon_free_gift.png", backgroundFit = "contain" }
    end

    local btnChildren, btnBg, btnBorder
    if claimed then
        btnChildren = { ctx.UI.Label { text = "已领取", fontSize = 13, fontColor = { 120, 115, 125, 180 }, fontWeight = "bold" } }
        btnBg = { 50, 45, 55, 200 }
        btnBorder = { 70, 65, 75, 120 }
    elseif canClaim then
        btnChildren = {
            ctx.UI.Panel { width = 16, height = 16, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain", marginRight = 4 },
            ctx.UI.Label { text = "观看", fontSize = 13, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
        }
        btnBg = { 100, 70, 180, 255 }
        btnBorder = { 180, 140, 255, 200 }
    else
        btnChildren = { ctx.UI.Panel { width = 20, height = 20, backgroundImage = "image/icon_lock.png", backgroundFit = "contain" } }
        btnBg = { 45, 40, 55, 200 }
        btnBorder = { 65, 60, 75, 120 }
    end

    return ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        marginBottom = 6,
        backgroundColor = { 28, 22, 42, 230 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        children = {
            -- 图标
            ctx.UI.Panel {
                width = 44, height = 44,
                borderRadius = 8,
                backgroundColor = { 45, 35, 65, 255 },
                borderWidth = 1,
                borderColor = { 90, 70, 130, 150 },
                justifyContent = "center",
                alignItems = "center",
                marginRight = 10,
                children = { iconWidget },
            },
            -- 文字区
            ctx.UI.Panel {
                flex = 1,
                flexDirection = "column",
                gap = 2,
                children = {
                    ctx.UI.Label {
                        text = label,
                        fontSize = 14,
                        fontColor = { 240, 230, 255, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Label {
                        text = desc,
                        fontSize = 11,
                        fontColor = { 160, 145, 180, 200 },
                    },
                },
            },
            -- 领取按钮
            ctx.UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 8, paddingBottom = 8,
                borderRadius = 8,
                backgroundColor = btnBg,
                borderWidth = 1,
                borderColor = btnBorder,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                onClick = (not claimed and canClaim) and function()
                    onClaim()
                end or nil,
                children = btnChildren,
            },
        },
    }
end

--- 构建每日特惠内容
local function BuildDailyDealContent()
    DailyDealData.Load()

    local children = {}

    -- 标题栏
    children[#children + 1] = ctx.UI.Panel {
        width = "100%",
        alignItems = "center",
        paddingTop = 12, paddingBottom = 8,
        children = {
            ctx.UI.Label {
                text = "每日特惠礼包",
                fontSize = 18,
                fontColor = { 255, 200, 80, 255 },
                fontWeight = "bold",
            },
            ctx.UI.Label {
                text = "每日0点刷新",
                fontSize = 11,
                fontColor = { 140, 130, 160, 160 },
                marginTop = 4,
            },
        },
    }

    -- 分割线
    children[#children + 1] = ctx.UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 80, 60, 120, 80 },
        alignSelf = "center",
        marginBottom = 8,
    }

    -- ① 免费礼包
    local freeClaimed = DailyDealData.IsFreeClaimed()
    local freeDesc = "暗影精粹×66 + 噬魂石×50"
    children[#children + 1] = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        marginBottom = 6,
        backgroundColor = freeClaimed
            and { 28, 22, 42, 230 }
            or { 35, 25, 55, 240 },
        borderRadius = 10,
        borderWidth = freeClaimed and 1 or 2,
        borderColor = freeClaimed
            and { 70, 55, 100, 120 }
            or { 255, 200, 60, 180 },
        children = {
            -- 图标
            ctx.UI.Panel {
                width = 44, height = 44,
                borderRadius = 8,
                backgroundColor = { 55, 40, 80, 255 },
                borderWidth = 1,
                borderColor = { 255, 200, 60, 150 },
                justifyContent = "center",
                alignItems = "center",
                marginRight = 10,
                children = {
                    ctx.UI.Panel { width = 28, height = 28, backgroundImage = "image/icon_free_gift.png", backgroundFit = "contain" },
                },
            },
            -- 文字 + 奖励图标
            ctx.UI.Panel {
                flex = 1,
                flexDirection = "column",
                gap = 4,
                children = {
                    ctx.UI.Label {
                        text = "免费礼包",
                        fontSize = 15,
                        fontColor = { 255, 220, 80, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel {
                        flexDirection = "row",
                        height = 40,
                        gap = 6,
                        children = (function()
                            local icons = {}
                            for _, item in ipairs(DailyDealData.FREE_PACK) do
                                icons[#icons + 1] = ctx.UI.Panel {
                                    height = "100%",
                                    aspectRatio = 1,
                                    children = {
                                        RewardIcon.Create(ctx.UI, "100%", item.id, item.amount, {
                                            muted = freeClaimed,
                                        }),
                                    },
                                }
                            end
                            return icons
                        end)(),
                    },
                },
            },
            -- 按钮
            ctx.UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 8, paddingBottom = 8,
                borderRadius = 8,
                backgroundColor = freeClaimed
                    and { 50, 45, 55, 200 }
                    or { 220, 160, 30, 255 },
                borderWidth = 1,
                borderColor = freeClaimed
                    and { 70, 65, 75, 120 }
                    or { 255, 220, 80, 200 },
                justifyContent = "center",
                alignItems = "center",
                onClick = (not freeClaimed) and function()
                    local ok, msg, claimedRewards = DailyDealData.ClaimFree()
                    if ok and claimedRewards then
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayChestOpen()
                        local displayRewards = {}
                        for _, r in ipairs(claimedRewards) do
                            local cdef = Config.CURRENCY[r.id]
                            displayRewards[#displayRewards + 1] = {
                                icon = Currency.GetImage(r.id),
                                name = (cdef and cdef.name) or r.id,
                                amount = r.amount,
                            }
                        end
                        RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                            title = "免费礼包",
                            rewards = displayRewards,
                            onClose = function()
                                ctx.RefreshContent()
                            end,
                        })
                    else
                        Toast.Show(msg or "领取失败", { 255, 100, 80 })
                        ctx.RefreshContent()
                    end
                end or nil,
                children = {
                    ctx.UI.Label {
                        text = freeClaimed and "已领取" or "免费领取",
                        fontSize = 13,
                        fontColor = freeClaimed
                            and { 120, 115, 125, 180 }
                            or { 40, 30, 10, 255 },
                        fontWeight = "bold",
                    },
                },
            },
        },
    }

    -- 分割线 + 广告奖励标题
    children[#children + 1] = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 6,
        gap = 8,
        children = {
            ctx.UI.Panel {
                flex = 1, height = 1,
                backgroundColor = { 80, 60, 120, 60 },
            },
            ctx.UI.Label {
                text = "额外奖励",
                fontSize = 12,
                fontColor = { 140, 120, 180, 180 },
            },
            ctx.UI.Panel {
                flex = 1, height = 1,
                backgroundColor = { 80, 60, 120, 60 },
            },
        },
    }

    -- ② 广告奖励列表（每个广告位一次观看领取全部）
    for i, reward in ipairs(DailyDealData.AD_REWARDS) do
        local claimed = DailyDealData.IsAdClaimed(i)
        local canClaim = DailyDealData.CanClaimAd(i)

        -- 构建奖励图标横向排列（flex=1 + aspectRatio=1 铺满）
        local rewardIcons = {}
        for _, item in ipairs(reward.items) do
            local amt = tonumber(string.match(item.text, "×(%d+)")) or 1
            rewardIcons[#rewardIcons + 1] = ctx.UI.Panel {
                height = "100%",
                aspectRatio = 1,
                children = {
                    RewardIcon.Create(ctx.UI, "100%", item.icon, amt, {
                        muted = claimed,
                    }),
                },
            }
        end

        -- 按钮样式
        local btnChildren, btnBg, btnBorder
        if claimed then
            btnChildren = { ctx.UI.Label { text = "已领取", fontSize = 13, fontColor = { 120, 115, 125, 180 }, fontWeight = "bold" } }
            btnBg = { 50, 45, 55, 200 }
            btnBorder = { 70, 65, 75, 120 }
        elseif canClaim then
            btnChildren = {
                ctx.UI.Panel { width = 16, height = 16, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain", marginRight = 4 },
                ctx.UI.Label { text = "观看", fontSize = 13, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
            }
            btnBg = { 100, 70, 180, 255 }
            btnBorder = { 180, 140, 255, 200 }
        else
            btnChildren = { ctx.UI.Panel { width = 20, height = 20, backgroundImage = "image/icon_lock.png", backgroundFit = "contain" } }
            btnBg = { 45, 40, 55, 200 }
            btnBorder = { 65, 60, 75, 120 }
        end

        children[#children + 1] = ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingTop = 10, paddingBottom = 10,
            paddingLeft = 12, paddingRight = 12,
            marginBottom = 6,
            backgroundColor = { 28, 22, 42, 230 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = { 70, 55, 100, 120 },
            children = {
                -- 左侧：奖励图标横向排列
                ctx.UI.Panel {
                    flex = 1,
                    flexDirection = "row",
                    height = 40,
                    gap = 6,
                    alignItems = "center",
                    children = rewardIcons,
                },
                -- 右侧：领取按钮
                ctx.UI.Panel {
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 8, paddingBottom = 8,
                    borderRadius = 8,
                    backgroundColor = btnBg,
                    borderWidth = 1,
                    borderColor = btnBorder,
                    justifyContent = "center",
                    alignItems = "center",
                    onClick = (canClaim) and function()
                        local AdHelper = require("Game.AdHelper")
                        AdHelper.ShowRewardAd(function()
                            local ok, msg, claimedRewards = DailyDealData.ClaimAd(i)
                            if ok and claimedRewards then
                                local AudioManager = require("Game.AudioManager")
                                AudioManager.PlayChestOpen()
                                local displayRewards = {}
                                for _, r in ipairs(claimedRewards) do
                                    local cdef = Config.CURRENCY[r.id]
                                    displayRewards[#displayRewards + 1] = {
                                        icon = Currency.GetImage(r.id),
                                        name = r.name or (cdef and cdef.name) or r.id,
                                        amount = r.amount,
                                    }
                                end
                                RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                                    title = reward.label,
                                    rewards = displayRewards,
                                    onClose = function()
                                        ctx.RefreshContent()
                                    end,
                                })
                            else
                                Toast.Show(msg or "领取失败", { 255, 100, 80 })
                                ctx.RefreshContent()
                            end
                        end)
                    end or nil,
                    flexDirection = "row",
                    children = btnChildren,
                },
            },
        }
    end

    return children
end

-- ============================================================================
-- 积天好礼内容页
-- ============================================================================

Mod.BuildContent = BuildDailyDealContent

return Mod
end
