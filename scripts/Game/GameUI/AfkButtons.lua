-- Game/GameUI/AfkButtons.lua
-- 左侧功能按钮组（排行榜、每日任务、招募、挂机、活动、兑换、减负中心等）

return function(GameUI, ctx)

local DailyTaskData        = require("Game.DailyTaskData")
local LaunchGiftData       = require("Game.LaunchGiftData")
local MailboxData          = require("Game.MailboxData")
local AdReliefData         = require("Game.AdReliefData")
local FeatureGate          = require("Game.FeatureGate")

--- 创建左侧功能按钮组（招募 + 挂机）
function GameUI.CreateAfkButton()
    local btnSize = 56
    local sk = { 0, 0, 0, 255 }  -- 描边色

    --- 创建带黑边描边的文字（4方向偏移黑色 + 白色正文）
    local function outlineLabel(txt, fontSize, fc, panelId)
        local offsets = { {-1,0}, {1,0}, {0,-1}, {0,1} }
        local children = {}
        for _, o in ipairs(offsets) do
            children[#children + 1] = ctx.UI.Label {
                text = txt, fontSize = fontSize, fontColor = sk, fontWeight = "bold",
                position = "absolute", left = o[1], top = o[2],
                width = "100%", textAlign = "center",
            }
        end
        children[#children + 1] = ctx.UI.Label {
            text = txt, fontSize = fontSize, fontColor = fc, fontWeight = "bold",
            width = "100%", textAlign = "center",
        }
        return ctx.UI.Panel {
            id = panelId,
            position = "relative", width = "100%", alignItems = "center",
            children = children,
        }
    end

    -- 构建左侧按钮列表（避免 nil 空洞导致 ipairs 中断）
    local leftBtnList = {}

    -- 排行榜入口按钮
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "leaderboardBtn",
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 220, 200, 60, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            local LeaderboardUI = require("Game.LeaderboardUI")
            LeaderboardUI.Show()
        end,
        children = {
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                backgroundColor = { 40, 35, 20, 220 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    ctx.UI.Panel {
                        width = 32, height = 32,
                        backgroundImage = "image/icon_leaderboard.png",
                        backgroundFit = "contain",
                    },
                },
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = { outlineLabel("排行", 11, { 255, 220, 80 }) },
            },
        },
    }

    -- 每日任务入口按钮
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "dailyTaskBtn",
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 180, 120, 255, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            GameUI.ShowDailyTaskOverlay(true)
        end,
        children = {
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                backgroundColor = { 40, 25, 60, 220 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    ctx.UI.Panel {
                        width = 32, height = 32,
                        backgroundImage = "image/icon_dailytask.png",
                        backgroundFit = "contain",
                    },
                },
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = { outlineLabel("任务", 11, { 200, 160, 255 }) },
            },
            -- 红点
            ctx.UI.Panel {
                id = "dailyTaskRedDot",
                position = "absolute",
                top = 2, right = 2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
                visible = DailyTaskData.HasClaimable(),
            },
        },
    }

    -- 开服好礼入口按钮（仅活跃时插入，避免 nil 空洞）
    if LaunchGiftData.IsActive() then
        leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
            id = "launchGiftBtn",
            width = btnSize, height = btnSize,
            borderRadius = 10,
            borderWidth = 1,
            borderColor = { 220, 180, 60, 180 },
            overflow = "hidden",
            pointerEvents = "auto",
            onClick = function(self)
                GameUI.ShowLaunchGiftOverlay(true)
            end,
            children = {
                ctx.UI.Panel {
                    width = btnSize, height = btnSize,
                    backgroundColor = { 60, 30, 20, 220 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        ctx.UI.Panel {
                            width = 32, height = 32,
                            backgroundImage = "image/开服好礼图标.png",
                            backgroundFit = "contain",
                        },
                    },
                },
                ctx.UI.Panel {
                    position = "absolute",
                    bottom = 2, left = 0, right = 0,
                    alignItems = "center",
                    children = { outlineLabel("新人", 11, { 255, 220, 100 }) },
                },
                -- 红点
                ctx.UI.Panel {
                    id = "launchGiftRedDot",
                    position = "absolute",
                    top = 2, right = 2,
                    width = 10, height = 10,
                    borderRadius = 5,
                    backgroundColor = { 255, 60, 60, 255 },
                    visible = LaunchGiftData.HasClaimable(),
                },
            },
        }
    end

    -- 邮件入口按钮
    leftBtnList[#leftBtnList + 1] =
            ctx.UI.Panel {
                id = "mailboxBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 120, 200, 160, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowMailboxOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 20, 40, 35, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 28, height = 28,
                                backgroundImage = "image/icon_mail.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("邮件", 11, { 120, 220, 160 }) },
                    },
                    -- 红点
                    ctx.UI.Panel {
                        id = "mailboxRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = MailboxData.HasUnclaimed(),
                    },
                },
            }

    -- 招募入口按钮（通关第2关解锁）
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "recruitBtn",
        visible = FeatureGate.IsUnlocked("recruit"),
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 200, 80, 80, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            GameUI.ShowRecruitOverlay(true)
        end,
        children = {
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                backgroundImage = "image/icon_recruit.png",
                backgroundSize = "cover",
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = { outlineLabel("招募", 11, { 255, 255, 255 }) },
            },
        },
    }

    -- 挂机奖励按钮（双图标轮换，通关第10关解锁）
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "afkButton",
        visible = FeatureGate.IsUnlocked("idle"),
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 120, 80, 200, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            -- 根据当前图标阶段打开对应 tab
            GameUI._afkClickTab = (GameUI._afkIconSwitch == 1) and 2 or 1
            GameUI.ClaimAfkReward()
        end,
        children = {
            -- 图标1: 挂机收益
            ctx.UI.Panel {
                id = "afkIcon1",
                position = "absolute",
                top = 0, left = 0,
                width = btnSize, height = btnSize,
                backgroundImage = "image/icon_idle.png",
                backgroundSize = "cover",
            },
            -- 图标2: 在线好礼
            ctx.UI.Panel {
                id = "afkIcon2",
                position = "absolute",
                top = 0, left = btnSize,
                width = btnSize, height = btnSize,
                backgroundImage = "image/icon_gift.png",
                backgroundSize = "cover",
                backgroundColor = { 30, 50, 40, 220 },
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = {
                    outlineLabel("0s", 11, { 140, 220, 140 }, "afkTimeLabel"),
                },
            },
        },
    }

    -- 活动入口按钮（通关第3关解锁）
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "activityBtn",
        visible = FeatureGate.IsUnlocked("activity"),
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 220, 160, 40, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            GameUI.ShowActivityOverlay(true)
        end,
        children = {
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                backgroundImage = "image/icon_activity.png",
                backgroundSize = "cover",
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = { outlineLabel("活动", 11, { 255, 255, 255 }) },
            },
            -- 红点（初始隐藏，数据加载后由 RefreshActivityRedDot 更新）
            ctx.UI.Panel {
                id = "activityRedDot",
                position = "absolute",
                top = 2, right = 2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
                visible = false,
            },
        },
    }

    -- 兑换商店入口按钮（通关第30关解锁）
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "exchangeShopBtn",
        visible = FeatureGate.IsUnlocked("exchange"),
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 180, 140, 255, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            GameUI.ShowExchangeShopOverlay(true)
        end,
        children = {
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                backgroundColor = { 35, 25, 55, 220 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    ctx.UI.Panel {
                        width = 30, height = 30,
                        backgroundImage = "image/icon_exchange_shop.png",
                        backgroundFit = "contain",
                    },
                },
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = { outlineLabel("兑换", 11, { 180, 140, 255 }) },
            },
            -- 红点
            ctx.UI.Panel {
                id = "exchangeShopRedDot",
                position = "absolute",
                top = 2, right = 2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
                visible = false,
            },
        },
    }

    -- 减负中心入口按钮（通关第4关解锁）
    leftBtnList[#leftBtnList + 1] = ctx.UI.Panel {
        id = "adReliefBtn",
        visible = FeatureGate.IsUnlocked("ad_relief"),
        width = btnSize, height = btnSize,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 100, 220, 180, 180 },
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function(self)
            GameUI.ShowAdReliefOverlay(true)
        end,
        children = {
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                backgroundColor = { 20, 40, 40, 220 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    ctx.UI.Panel {
                        width = 30, height = 30,
                        backgroundImage = "image/currency_ad_ticket.png",
                        backgroundFit = "contain",
                    },
                },
            },
            ctx.UI.Panel {
                position = "absolute",
                bottom = 2, left = 0, right = 0,
                alignItems = "center",
                children = { outlineLabel("免广卡", 11, { 100, 220, 180 }) },
            },
            -- 红点
            ctx.UI.Panel {
                id = "adReliefRedDot",
                position = "absolute",
                top = 2, right = 2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
                visible = AdReliefData.HasClaimable(),
            },
        },
    }

    return ctx.UI.Panel {
        id = "leftSideButtons",
        position = "absolute",
        left = 6, top = "30%",
        width = btnSize,
        flexDirection = "column",
        alignItems = "center",
        gap = 8,
        pointerEvents = "box-none",
        children = leftBtnList,
    }
end

end
