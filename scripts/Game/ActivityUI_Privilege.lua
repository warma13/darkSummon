-- Game/ActivityUI_Privilege.lua
-- 尊享特权页内容构建

return function(ctx, Shared)

local Config        = require("Game.Config")
local PrivilegeData = require("Game.PrivilegeData")
local Currency      = require("Game.Currency")
local Toast         = require("Game.Toast")
local Tooltip       = require("Game.Tooltip")
local AdTracker     = require("Game.AdTracker")

local S                    = Shared.S
local FormatNum            = Shared.FormatNum
local GetRewardTooltipInfo = Shared.GetRewardTooltipInfo
local REWARD_COLORS        = Shared.REWARD_COLORS
local REWARD_DESC          = Shared.REWARD_DESC

local RewardIcon    = require("Game.RewardIcon")
local RewardDisplay = require("Game.RewardDisplay")

local Mod = {}

-- ============================================================================
-- 尊享特权内容页
-- ============================================================================

local function BuildPrivilegeContent()
    PrivilegeData.Load()

    -- 当前选中的卡定义
    local card
    for _, c in ipairs(PrivilegeData.CARDS) do
        if c.id == ctx.currentPrivilegeTab then card = c; break end
    end
    if not card then card = PrivilegeData.CARDS[1] end

    local unlocked = PrivilegeData.IsUnlocked(card.id)
    local adsWatched = PrivilegeData.GetAdsWatched(card.id)
    local canWatch = PrivilegeData.CanWatchAd(card.id)
    local dailyClaimed = PrivilegeData.IsDailyClaimed(card.id)
    local canClaimDaily = PrivilegeData.CanClaimDaily(card.id)
    local instantClaimed = PrivilegeData.IsInstantClaimed(card.id)

    -- ---- 子标签栏 ----
    -- 按截图顺序：终身卡 | 月卡 | 周卡 | 福利卡
    local tabOrder = { "lifetime", "monthly", "weekly", "welfare" }
    local subTabs = {}
    for _, cid in ipairs(tabOrder) do
        local def = PrivilegeData.GetCardDef(cid)
        if def then
            local isActive = cid == ctx.currentPrivilegeTab
            local isUnlocked = PrivilegeData.IsUnlocked(cid)
            subTabs[#subTabs + 1] = ctx.UI.Panel {
                flex = 1,
                height = 36,
                alignItems = "center",
                justifyContent = "center",
                backgroundColor = isActive and { 50, 35, 70, 240 } or { 25, 20, 40, 180 },
                borderBottomWidth = isActive and 2 or 0,
                borderColor = S.goldAccent,
                onClick = function()
                    ctx.currentPrivilegeTab = cid
                    ctx.RefreshContent()
                end,
                children = {
                    ctx.UI.Label {
                        text = def.name,
                        fontSize = 13,
                        fontColor = isActive and S.goldAccent or (isUnlocked and S.checkColor or S.textSecondary),
                        fontWeight = isActive and "bold" or "normal",
                    },
                },
            }
        end
    end

    local subTabBar = ctx.UI.Panel {
        width = "100%",
        height = 36,
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "stretch",
        children = subTabs,
    }

    -- ---- 卡片主体区域 ----
    local cardChildren = {}
    local lockOverlay = nil  -- 未解锁时的覆盖层内容

    -- 解锁状态 / 广告进度
    if not unlocked and card.adsRequired > 0 then
        -- 未解锁：显示广告进度 + 观看按钮
        local progress = adsWatched / card.adsRequired
        local dailyLimitReached = PrivilegeData.IsDailyAdLimitReached(card.id)
        local dailyRemaining = PrivilegeData.GetDailyAdsRemaining(card.id)

        -- 命令式构建 children，避免 nil 截断表
        local lockChildren = {}
        lockChildren[#lockChildren + 1] = ctx.UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                ctx.UI.Panel { width = 22, height = 22, backgroundImage = "image/icon_lock.png", backgroundFit = "contain" },
                ctx.UI.Label { text = card.name, fontSize = 18, fontColor = S.textMuted, fontWeight = "bold" },
            },
        }
        lockChildren[#lockChildren + 1] = ctx.UI.Panel {
            width = "80%", height = 18,
            backgroundColor = { 20, 15, 35 },
            borderRadius = 9,
            overflow = "hidden",
            children = {
                ctx.UI.Panel {
                    width = math.floor(progress * 100) .. "%",
                    height = "100%",
                    backgroundColor = S.goldAccent,
                    borderRadius = 9,
                },
            },
        }
        lockChildren[#lockChildren + 1] = ctx.UI.Label {
            text = "广告进度 " .. adsWatched .. "/" .. card.adsRequired,
            fontSize = 12,
            fontColor = S.textSecondary,
        }
        -- 每日上限提示（仅有 dailyAdLimit 的卡片显示）
        if dailyRemaining >= 0 then
            lockChildren[#lockChildren + 1] = ctx.UI.Label {
                text = "今日剩余 " .. dailyRemaining .. "/" .. (card.dailyAdLimit or 0) .. " 次",
                fontSize = 11,
                fontColor = dailyLimitReached and { 255, 80, 80 } or S.textSecondary,
            }
        end
        if dailyLimitReached then
            -- 达到每日上限：按钮置灰
            lockChildren[#lockChildren + 1] = ctx.UI.Panel {
                paddingLeft = 28, paddingRight = 28,
                paddingTop = 10, paddingBottom = 10,
                backgroundColor = { 80, 70, 90, 200 },
                borderRadius = 8,
                flexDirection = "row",
                alignItems = "center",
                children = {
                    ctx.UI.Panel { width = 18, height = 18, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain", marginRight = 4, opacity = 0.4 },
                    ctx.UI.Label { text = "今日已达上限", fontSize = 14, fontColor = S.textMuted, fontWeight = "bold" },
                },
            }
        elseif canWatch then
            lockChildren[#lockChildren + 1] = ctx.UI.Panel {
                paddingLeft = 28, paddingRight = 28,
                paddingTop = 10, paddingBottom = 10,
                backgroundColor = { 200, 160, 50 },
                borderRadius = 8,
                flexDirection = "row",
                alignItems = "center",
                onClick = function()
                    local AdHelper = require("Game.AdHelper")
                    AdHelper.ShowRewardAd(function()
                        PrivilegeData.RecordAdWatch(card.id)
                        if PrivilegeData.IsUnlocked(card.id) then
                            local ok, msg, rewards = PrivilegeData.ClaimInstant(card.id)
                            if ok and rewards and #rewards > 0 then
                                RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                                    title = card.name .. " 已解锁！",
                                    rewards = rewards,
                                    onClose = function()
                                        ctx.RefreshContent()
                                    end,
                                })
                            else
                                Toast.Show("🎉 " .. card.name .. " 已解锁！")
                                ctx.RefreshContent()
                            end
                        else
                            Toast.Show("广告 +1（" .. (adsWatched + 1) .. "/" .. card.adsRequired .. "）")
                            ctx.RefreshContent()
                        end
                    end)
                end,
                children = {
                    ctx.UI.Panel { width = 18, height = 18, backgroundImage = "image/icon_watch_ad.png", backgroundFit = "contain", marginRight = 4 },
                    ctx.UI.Label { text = "观看广告", fontSize = 14, fontColor = { 30, 20, 10 }, fontWeight = "bold" },
                },
            }
        end

        -- lockOverlay 将在 cardPanel 构建后绝对定位添加
        ---@type table
        lockOverlay = lockChildren
    end

    -- ---- 解锁立得奖励（一行：标签居左，奖励图标居右） ----
    if #card.instant > 0 then
        local instantIcons = {}
        for _, r in ipairs(card.instant) do
            instantIcons[#instantIcons + 1] = RewardIcon.Create(ctx.UI, 44, r.currency, r.amount, {
                muted = instantClaimed,
                label = r.label,
            })
        end
        -- 左侧标签子元素
        local leftChildren = {
            ctx.UI.Label {
                text = "解锁立得",
                fontSize = 13,
                fontColor = S.textSecondary,
                fontWeight = "bold",
            },
        }
        if instantClaimed then
            leftChildren[#leftChildren + 1] = ctx.UI.Label {
                text = "（已领取）",
                fontSize = 11,
                fontColor = S.textMuted,
            }
        end
        cardChildren[#cardChildren + 1] = ctx.UI.Panel {
            width = "100%",
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 8, paddingBottom = 8,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            backgroundColor = { 35, 28, 55, 200 },
            borderBottomWidth = 1,
            borderColor = { 60, 50, 80, 100 },
            children = {
                -- 左侧：标签
                ctx.UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = leftChildren,
                },
                -- 右侧：奖励图标
                ctx.UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = instantIcons,
                },
            },
        }
    end

    -- ---- 被动增益 ----
    if #card.buffs > 0 then
        local buffLabels = {}
        for _, b in ipairs(card.buffs) do
            buffLabels[#buffLabels + 1] = ctx.UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    ctx.UI.Label { text = "⚡", fontSize = 12 },
                    ctx.UI.Label {
                        text = b,
                        fontSize = 12,
                        fontColor = unlocked and { 120, 220, 160 } or S.textMuted,
                    },
                },
            }
        end
        cardChildren[#cardChildren + 1] = ctx.UI.Panel {
            width = "100%",
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 8, paddingBottom = 8,
            backgroundColor = { 30, 25, 48, 200 },
            borderBottomWidth = 1,
            borderColor = { 60, 50, 80, 100 },
            gap = 6,
            children = {
                ctx.UI.Label {
                    text = card.buffLabel or "增益",
                    fontSize = 13,
                    fontColor = S.textSecondary,
                    fontWeight = "bold",
                },
                table.unpack(buffLabels),
            },
        }
    end

    -- ---- 领取按钮状态 ----
    local btnText, btnBg, btnClickable
    if not unlocked and card.adsRequired > 0 then
        btnText = "未解锁"
        btnBg = { 60, 50, 70, 200 }
        btnClickable = false
    elseif dailyClaimed then
        btnText = "今日已领"
        btnBg = { 60, 50, 70, 200 }
        btnClickable = false
    else
        btnText = "领取"
        btnBg = { 200, 160, 50 }
        btnClickable = true
    end

    -- ---- 每日可领：奖励图标 ----
    local dailyIcons = {}
    for _, r in ipairs(card.daily) do
        dailyIcons[#dailyIcons + 1] = RewardIcon.Create(ctx.UI, 48, r.currency, r.amount, {
            label = r.label,
        })
    end

    -- ---- 中间层：解锁立得 + 增益（有内容时 flex=3）----
    local hasInfo = #cardChildren > 0
    local infoPanel = hasInfo and ctx.UI.Panel {
        width = "100%",
        flex = 3,
        backgroundColor = { 25, 20, 45, 220 },
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        children = cardChildren,
    } or nil

    -- ---- 下层：卡片背景图 + 锁定/名称 + 领取区（流式布局撑满） ----
    -- 上部区域：背景图 + 卡片名/锁定信息
    local topChildren = {}
    if lockOverlay then
        -- 未解锁：锁图标 + 广告进度 + 观看按钮
        for _, child in ipairs(lockOverlay) do
            topChildren[#topChildren + 1] = child
        end
    else
        -- 已解锁 / 免费福利卡：卡片名 + 剩余天数
        local nameIcon = "image/icon_free_gift.png"
        local remaining = PrivilegeData.GetRemainingDays(card.id)
        topChildren[#topChildren + 1] = ctx.UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                ctx.UI.Panel { width = 24, height = 24, backgroundImage = nameIcon, backgroundFit = "contain" },
                ctx.UI.Label {
                    text = card.name,
                    fontSize = 20,
                    fontColor = S.goldAccent,
                    fontWeight = "bold",
                },
            },
        }
        if remaining and remaining >= 0 then
            local remainColor = remaining <= 1 and { 255, 80, 80, 255 } or { 180, 220, 140, 230 }
            topChildren[#topChildren + 1] = ctx.UI.Label {
                text = "剩余 " .. remaining .. " 天",
                fontSize = 12,
                fontColor = remainColor,
            }
        end
    end

    -- 非福利卡加深色遮罩，让文字更清晰
    local needOverlay = card.id ~= "welfare"
    local topAreaChildren
    if needOverlay then
        topAreaChildren = {
            ctx.UI.Panel {
                position = "absolute",
                left = 0, top = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 140 },
            },
            ctx.UI.Panel {
                width = "100%",
                flexGrow = 1,
                justifyContent = "center",
                alignItems = "center",
                gap = 12,
                children = topChildren,
            },
        }
    else
        topAreaChildren = topChildren
    end

    local topArea = ctx.UI.Panel {
        width = "100%",
        flexGrow = 1,
        backgroundImage = "image/privilege_card_bg.png",
        backgroundFit = "cover",
        backgroundPosition = "center",
        justifyContent = "center",
        alignItems = "center",
        gap = needOverlay and 0 or 12,
        children = topAreaChildren,
    }

    -- 底部区域：每日可领 + 奖励图标 + 领取按钮
    local bottomArea = ctx.UI.Panel {
        width = "100%",
        backgroundColor = { 15, 10, 30, 200 },
        borderTopWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        alignItems = "center",
        paddingTop = 10, paddingBottom = 12,
        gap = 8,
        children = {
            -- "每日可领" 标签
            ctx.UI.Label {
                text = "每日可领",
                fontSize = 14,
                fontColor = S.textSecondary,
                fontWeight = "bold",
            },
            -- 奖励图标行
            ctx.UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                gap = 10,
                children = dailyIcons,
            },
            -- 领取按钮
            ctx.UI.Panel {
                paddingLeft = 48, paddingRight = 48,
                paddingTop = 10, paddingBottom = 10,
                backgroundColor = btnBg,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = btnClickable and { 255, 220, 100, 180 } or { 80, 70, 90, 100 },
                alignItems = "center",
                onClick = btnClickable and function()
                    local ok, msg, rewards = PrivilegeData.ClaimDaily(card.id)
                    if ok and rewards and #rewards > 0 then
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayChestOpen()
                        RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                            title = card.name .. " · 每日奖励",
                            rewards = rewards,
                            onClose = function()
                                ctx.RefreshContent()
                            end,
                        })
                    elseif ok then
                        Toast.Show("领取成功：" .. msg)
                        ctx.RefreshContent()
                    else
                        Toast.Show(msg or "领取失败")
                    end
                end or nil,
                children = {
                    ctx.UI.Label {
                        text = btnText,
                        fontSize = 16,
                        fontColor = btnClickable and { 30, 20, 10 } or S.textMuted,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }

    local cardPanel = ctx.UI.Panel {
        width = "100%",
        flexGrow = hasInfo and 6 or 9,
        flexBasis = 0,
        flexShrink = 1,
        backgroundColor = { 25, 20, 45, 220 },
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        children = { topArea, bottomArea },
    }

    -- 直接返回 flex 子元素，父容器 flexGrow=1 撑满可用空间
    local children = {}
    children[#children + 1] = subTabBar
    if infoPanel then
        children[#children + 1] = infoPanel
    end
    children[#children + 1] = cardPanel

    return children
end


Mod.BuildContent = BuildPrivilegeContent

return Mod
end
