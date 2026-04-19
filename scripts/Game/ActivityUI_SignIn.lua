-- Game/ActivityUI_SignIn.lua
-- 签到页内容构建

return function(ctx, Shared)

local ActivityData   = require("Game.ActivityData")
local Currency       = require("Game.Currency")
local Toast          = require("Game.Toast")
local Tooltip        = require("Game.Tooltip")
local Config         = require("Game.Config")
local RewardIcon     = require("Game.RewardIcon")
local RewardDisplay  = require("Game.RewardDisplay")

local S                   = Shared.S
local CYCLE_DAYS          = Shared.CYCLE_DAYS
local FormatNum           = Shared.FormatNum
local GetRewardDisplay    = Shared.GetRewardDisplay
local GetRewardTooltipInfo = Shared.GetRewardTooltipInfo

local Mod = {}

-- ============================================================================
-- 签到内容页
-- ============================================================================

--- 构建签到网格内容（仅网格，不含按钮）
local function BuildSignInContent()
    local totalDays = ActivityData.GetTotalDays()
    local claimedCount = ActivityData.GetClaimedCount()

    -- ---- 签到信息头 ----
    local headerPanel = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 10, paddingBottom = 6,
        flexShrink = 0,
        children = {
            ctx.UI.Panel {
                flexDirection = "column",
                gap = 2,
                children = {
                    ctx.UI.Label {
                        text = "每日登录奖励",
                        fontSize = 16,
                        fontColor = S.textPrimary,
                        fontWeight = "bold",
                    },
                    ctx.UI.Label {
                        text = "签到天数:",
                        fontSize = 11,
                        fontColor = S.textSecondary,
                    },
                    ctx.UI.Label {
                        text = "剩余 " .. ActivityData.GetRemainingDays() .. " 天",
                        fontSize = 11,
                        fontColor = { 200, 170, 80, 220 },
                    },
                },
            },
            ctx.UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 40, 60, 30, 220 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 160, 80, 100 },
                children = {
                    ctx.UI.Label {
                        text = totalDays .. "/" .. CYCLE_DAYS,
                        fontSize = 16,
                        fontColor = S.checkColor,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }

    -- ---- 签到网格（固定30格，每行5格，共6行） ----
    local totalRows = CYCLE_DAYS / 5  -- 30/5 = 6
    local gridRows = {}
    for row = 0, totalRows - 1 do
        local cols = {}
        for col = 0, 4 do
            local day = row * 5 + col + 1

            local reward = ActivityData.GetDayReward(day)
            local claimed = ActivityData.IsDayClaimed(day)           -- day <= claimedCount
            local unclaimed = ActivityData.IsDayUnclaimed(day)       -- claimedCount < day <= totalLogins
            local isNext = (day == claimedCount + 1 and day <= totalDays)  -- 下一个待领取

            local bg, border
            if claimed then
                bg = S.claimedBg; border = S.claimedBorder
            elseif unclaimed then
                bg = S.todayBg; border = S.todayBorder      -- 已登录未领取，高亮
            else
                bg = S.futureBg; border = S.futureBorder     -- 未来
            end

            local shortText, rewardColor = GetRewardDisplay(reward)

            -- 卡片子项：顶部天数 → 中间 RewardIcon → 底部数字
            local rewardCurrId = reward and reward.id or "shadow_essence"
            local rewardAmount = reward and reward.amount or 0
            local cdef = reward and Config.CURRENCY[rewardCurrId]

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
                            text = day .. "日",
                            fontSize = 9,
                            fontColor = claimed and S.checkColor or (unclaimed and S.goldAccent or S.textMuted),
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
                borderWidth = claimed and 1 or (unclaimed and 2 or 1),
                borderColor = border,
                flexDirection = "column",
                alignItems = "stretch",
                overflow = "visible",
                pointerEvents = "auto",
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

    local gridContainer = ctx.UI.Panel {
        width = "100%",
        flexDirection = "column",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        gap = 4,
    }
    for _, r in ipairs(gridRows) do
        gridContainer:AddChild(r)
    end

    return { headerPanel, gridContainer }
end

--- 创建固定签到按钮栏（不随内容滚动）
local function CreateSignInButton()
    local unclaimed = ActivityData.GetUnclaimedCount()

    local btnText, btnEnabled
    if unclaimed > 1 then
        -- 有之前未领的奖励
        btnText = "领取全部"
        btnEnabled = true
    elseif unclaimed == 1 then
        -- 只有今天这一天待领
        btnText = "签到"
        btnEnabled = true
    else
        -- 全部已领取
        btnText = "已签到"
        btnEnabled = false
    end

    return ctx.UI.Panel {
        width = "100%",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 8, paddingBottom = 8,
        flexShrink = 0,
        backgroundColor = { 22, 18, 36, 245 },
        borderTopWidth = 1,
        borderColor = { 70, 55, 100, 80 },
        children = {
            ctx.UI.Button {
                text = btnText,
                width = "100%",
                height = 44,
                fontSize = 16,
                borderRadius = 10,
                variant = btnEnabled and "primary" or "outline",
                fontWeight = "bold",
                onClick = btnEnabled and function()
                    local ok, msg, claimedRewards
                    if unclaimed > 1 then
                        ok, msg, claimedRewards = ActivityData.ClaimAll()
                    else
                        ok, msg, claimedRewards = ActivityData.SignIn()
                    end
                    if ok then
                        -- 构建 RewardDisplay 数据
                        local rewards = {}
                        if claimedRewards and #claimedRewards > 0 then
                            for _, r in ipairs(claimedRewards) do
                                local rDef = Config.CURRENCY[r.id]
                                rewards[#rewards + 1] = {
                                    icon = Currency.GetImage(r.id),
                                    name = rDef and rDef.name or r.id,
                                    amount = r.amount,
                                }
                            end
                        end
                        if #rewards > 0 then
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayChestOpen()
                            RewardDisplay.Show(ctx.UI, ctx.pageRoot, {
                                title = "签到奖励",
                                rewards = rewards,
                                onClose = function()
                                    ctx.RefreshContent()
                                end,
                            })
                        else
                            Toast.Show("领取成功: " .. msg, { 100, 220, 80 })
                            ctx.RefreshContent()
                        end
                    else
                        Toast.Show(msg, { 255, 200, 80 })
                    end
                end or nil,
            },
        },
    }
end

Mod.BuildContent = BuildSignInContent
Mod.CreateButton = CreateSignInButton

return Mod
end
