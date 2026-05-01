-- Game/WeeklyActivityUI/GarbageBoss.lua
-- 垃圾大扫除副本 UI（限时活动子页面）
-- 入口横幅 + 里程碑奖励列表 + 挑战逻辑

local GB                = require("Game.GarbageBossData")
local GarbageBossSkills = require("Game.GarbageBossSkills")
local Currency          = require("Game.Currency")
local HeroData          = require("Game.HeroData")
local Config            = require("Game.Config")
local Toast             = require("Game.Toast")
local RC                = require("Game.RewardController")

local RewardDisplay     = require("Game.RewardDisplay")

local LB              = require("Game.LeaderboardData")

local GarbageBossUI = {}
local _isChallenging = false   -- 战斗期间锁定，防止重复挑战

-- ============================================================================
-- 入口横幅（BuildBanner）
-- ============================================================================

function GarbageBossUI.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local isActive     = GB.IsActive()
    local remaining    = GB.GetRemainingAttempts()
    local totalDmg     = GB.GetTotalDamage()        -- 个人累计
    local serverTotal  = GB.GetServerTotalDamage()   -- 全服累计
    local bestDmg      = GB.GetBestDamage()
    local hasFought    = GB.HasFought()
    local milestones   = GB.GetMilestones()

    -- 触发全服数据异步拉取（带缓存，不会频繁请求）
    GB.FetchServerTotal()

    -- 计算已领 / 已达标 / 总数
    local claimedCount, reachedCount = 0, 0
    for _, m in ipairs(milestones) do
        if m.claimed  then claimedCount = claimedCount + 1 end
        if m.reached  then reachedCount = reachedCount + 1 end
    end
    local totalTiers = #milestones

    return UI.Panel {
        width = "100%",
        backgroundColor = { 30, 45, 25, 240 },
        borderRadius = 10,
        borderWidth = 2,
        borderColor = { 120, 180, 60, 200 },
        overflow = "hidden",
        marginBottom = 8,
        children = {
            -- 活动配图
            UI.Panel {
                width = "100%", height = 120,
                backgroundImage = "image/banner_garbage_boss_20260501064756.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                borderTopLeftRadius = 10,
                borderTopRightRadius = 10,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 12, paddingBottom = 14,
                paddingLeft = 16, paddingRight = 16,
                gap = 10,
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Panel {
                                gap = 2,
                                flexShrink = 1,
                                children = {
                                    UI.Label {
                                        text = "垃圾大扫除",
                                        fontSize = 16,
                                        fontColor = { 140, 220, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "击败垃圾山大王，冲击伤害里程碑",
                                        fontSize = 10,
                                        fontColor = { 180, 200, 150, 200 },
                                    },
                                },
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 5, paddingBottom = 5,
                                backgroundColor = { 50, 70, 20, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 120, 180, 60, 150 },
                                children = {
                                    UI.Label {
                                        text = "剩余: " .. remaining .. "/" .. (GB.DAILY_ATTEMPTS + (GB.GetData().bonusAttempts or 0)),
                                        fontSize = 12,
                                        fontColor = remaining > 0
                                            and { 100, 255, 150, 255 }
                                            or  { 255, 120, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 伤害统计 + 挑战按钮
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Panel {
                                gap = 2,
                                children = {
                                    UI.Label {
                                        text = "全服累计: " .. GB.FormatDamage(serverTotal),
                                        fontSize = 13,
                                        fontColor = { 255, 180, 60, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "个人累计: " .. GB.FormatDamage(totalDmg),
                                        fontSize = 10,
                                        fontColor = { 200, 200, 160, 200 },
                                    },
                                    UI.Label {
                                        text = "最高单次: " .. (bestDmg > 0 and GB.FormatDamage(bestDmg) or "---"),
                                        fontSize = 10,
                                        fontColor = { 180, 170, 140, 180 },
                                    },
                                },
                            },
                            UI.Button {
                                text = _isChallenging and "战斗中..."
                                    or (isActive
                                        and (remaining > 0 and "挑战" or "今日已完成")
                                        or "活动未开放"),
                                fontSize = 13,
                                height = 34,
                                paddingLeft = 16, paddingRight = 16,
                                borderRadius = 8,
                                variant = (isActive and remaining > 0 and not _isChallenging) and "primary" or "outline",
                                disabled = not isActive or remaining <= 0 or _isChallenging,
                                onClick = function()
                                    GarbageBossUI._OnChallenge(ctx)
                                end,
                            },
                        },
                    },
                    -- 里程碑进度
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 15, 25, 10, 200 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        gap = 4,
                        borderWidth = 1,
                        borderColor = { 80, 120, 40, 100 },
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                width = "100%",
                                children = {
                                    UI.Label {
                                        text = "里程碑进度",
                                        fontSize = 11,
                                        fontColor = { 140, 220, 80, 240 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = reachedCount .. "/" .. totalTiers .. " 达成"
                                            .. (claimedCount > 0 and ("  " .. claimedCount .. " 已领") or ""),
                                        fontSize = 10,
                                        fontColor = { 200, 200, 160, 200 },
                                    },
                                },
                            },
                            -- 进度条
                            UI.Panel {
                                width = "100%", height = 6,
                                backgroundColor = { 20, 30, 15, 200 },
                                borderRadius = 3,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = totalTiers > 0 and (math.floor(reachedCount / totalTiers * 100) .. "%") or "0%",
                                        height = "100%",
                                        backgroundColor = { 120, 200, 60, 255 },
                                        borderRadius = 3,
                                    },
                                },
                            },
                        },
                    },
                    -- 规则
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 15, 25, 10, 200 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        gap = 4,
                        borderWidth = 1,
                        borderColor = { 80, 120, 40, 100 },
                        children = {
                            UI.Label {
                                text = "规则说明",
                                fontSize = 11,
                                fontColor = { 200, 180, 80, 240 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "- 每日可挑战 " .. GB.DAILY_ATTEMPTS .. " 次，每次 " .. GB.CONFIG.totalDuration .. " 秒",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "- 全服玩家累计伤害达到里程碑，所有参与者均可领取",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "- 至少挑战一次才能领取里程碑奖励",
                                fontSize = 10, fontColor = { 255, 200, 80, 200 },
                            },
                            UI.Label {
                                text = "- ①垃圾堆积：每5秒生成10个垃圾，每个垃圾降全英雄攻击力1%",
                                fontSize = 10, fontColor = { 255, 160, 80, 200 },
                            },
                            UI.Label {
                                text = "- ②毒雾召唤：每10秒召唤小怪，全英雄攻速-10%（本局叠加）",
                                fontSize = 10, fontColor = { 255, 160, 80, 200 },
                            },
                            UI.Label {
                                text = "- ③垃圾风暴：每15秒降下垃圾，命中英雄降1星（集火可打断）",
                                fontSize = 10, fontColor = { 255, 160, 80, 200 },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 里程碑奖励列表
-- ============================================================================

function GarbageBossUI.BuildMilestones(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local milestones = GB.GetMilestones()
    local hasFought  = GB.HasFought()

    local rows = {}
    for _, m in ipairs(milestones) do
        -- 奖励条目
        local rewardItems = {}
        for _, r in ipairs(m.rewards) do
            local info = Currency.GetInfo(r.id)
            local name = info and info.name or r.id
            rewardItems[#rewardItems + 1] = UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 3,
                children = {
                    Currency.IconWidget(UI, r.id, 14),
                    UI.Label {
                        text = name .. " x" .. r.amount,
                        fontSize = 10,
                        fontColor = m.reached and { 220, 215, 200, 240 } or { 140, 135, 120, 160 },
                    },
                },
            }
        end

        -- 状态标签
        local statusText, statusColor
        if m.claimed then
            statusText = "已领取"
            statusColor = { 120, 120, 120, 200 }
        elseif m.reached and hasFought then
            statusText = "可领取"
            statusColor = { 100, 255, 100, 255 }
        elseif m.reached and not hasFought then
            statusText = "需挑战"
            statusColor = { 255, 200, 80, 220 }
        else
            statusText = "未达成"
            statusColor = { 140, 130, 110, 160 }
        end

        local tierIndex = m.index

        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = m.claimed and { 30, 35, 25, 120 }
                or (m.reached and { 40, 55, 25, 200 } or { 25, 30, 20, 180 }),
            borderRadius = 6,
            borderWidth = 1,
            borderColor = m.reached and not m.claimed
                and { 120, 200, 60, 180 }
                or { 60, 70, 40, 80 },
            children = {
                -- 左侧：阈值 + 奖励
                UI.Panel {
                    flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label {
                            text = GB.FormatDamage(m.threshold),
                            fontSize = 13,
                            fontColor = m.reached and { 255, 220, 100, 255 } or { 160, 150, 120, 180 },
                            fontWeight = m.reached and "bold" or "normal",
                        },
                        UI.Panel {
                            flexDirection = "row",
                            flexWrap = "wrap",
                            gap = 6,
                            children = rewardItems,
                        },
                    },
                },
                -- 右侧：状态/领取按钮
                (m.reached and hasFought and not m.claimed)
                    and UI.Button {
                        text = "领取",
                        fontSize = 11,
                        height = 28,
                        paddingLeft = 12, paddingRight = 12,
                        borderRadius = 6,
                        variant = "primary",
                        onClick = function()
                            if GB.ClaimMilestone(tierIndex) then
                                -- 构建 RewardDisplay 数据
                                local displayRewards = {}
                                for _, r in ipairs(m.rewards) do
                                    local info = Currency.GetInfo(r.id)
                                    displayRewards[#displayRewards + 1] = {
                                        icon  = r.id,
                                        name  = info and info.name or r.id,
                                        amount = r.amount,
                                    }
                                end
                                -- 先刷新页面
                                local WeeklyActivityUI = require("Game.WeeklyActivityUI")
                                WeeklyActivityUI.Refresh()
                                -- 再弹出奖励展示
                                RewardDisplay.Show(ctx.GetUI(), ctx.GetPageRoot(), {
                                    title = "里程碑奖励",
                                    rewards = displayRewards,
                                })
                            end
                        end,
                    }
                    or UI.Label {
                        text = statusText,
                        fontSize = 11,
                        fontColor = statusColor,
                        fontWeight = (m.reached and not m.claimed) and "bold" or "normal",
                    },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 25, 35, 18, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 80, 120, 40, 120 },
        paddingTop = 12, paddingBottom = 12,
        paddingLeft = 12, paddingRight = 12,
        gap = 6,
        children = {
            -- 标题行：左标题 + 右排行榜按钮
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                marginBottom = 4,
                children = {
                    UI.Label {
                        text = "伤害里程碑奖励",
                        fontSize = 14,
                        fontColor = { 140, 220, 80, 255 },
                        fontWeight = "bold",
                    },
                    UI.Button {
                        text = "排行榜",
                        fontSize = 11,
                        height = 26,
                        paddingLeft = 10, paddingRight = 10,
                        borderRadius = 6,
                        variant = "outline",
                        onClick = function()
                            local LeaderboardUI = require("Game.LeaderboardUI")
                            LeaderboardUI.ShowWithTabs({
                                {
                                    key    = LB.KEY_GARBAGE_BOSS,
                                    label  = "大扫除",
                                    format = function(s) return LB.FormatGarbageBoss(s) end,
                                },
                            }, 1)
                        end,
                    },
                },
            },
            table.unpack(rows),
        },
    }
end

-- ============================================================================
-- 挑战逻辑
-- ============================================================================

function GarbageBossUI._OnChallenge(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    if _isChallenging then
        Toast.Show("战斗进行中，请勿重复挑战", { 255, 200, 80 })
        return
    end

    if not GB.IsActive() then
        Toast.Show("活动未开放", { 255, 200, 80 })
        return
    end

    if #HeroData.GetDeployedList() < Config.MAX_DEPLOYED then
        Toast.Show("需要上阵" .. Config.MAX_DEPLOYED .. "名英雄才能挑战", { 255, 80, 80 })
        return
    end

    if not GB.ConsumeAttempt() then return end

    _isChallenging = true

    -- 日常任务
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("boss", 1) end

    local GameUI = require("Game.GameUI")
    local State  = require("Game.State")

    -- 关闭活动页面，进入战斗
    GameUI.ShowWeeklyActivityOverlay(false)

    local config, bossDef = GB.BuildBattleConfig()
    local label = config.label

    local function handleResult(result, isExit, continueExit)
        _isChallenging = false
        GarbageBossSkills.Cleanup()
        State.worldBossActive = false

        local sessionDamage = result.totalDamage or State.worldBossTotalDamage or 0
        local newMilestones = GB.SettleBattle(sessionDamage)

        local title = label .. (isExit and " 退出" or " 挑战结束")
            .. "\n本次伤害: " .. GB.FormatDamage(sessionDamage)
            .. "\n累计伤害: " .. GB.FormatDamage(GB.GetTotalDamage())

        local exitFn = continueExit or function() GameUI.ExitDungeonBattle() end

        -- 展示新达成的里程碑提示
        if #newMilestones > 0 then
            local milestoneTexts = {}
            for _, nm in ipairs(newMilestones) do
                milestoneTexts[#milestoneTexts + 1] = GB.FormatDamage(nm.threshold)
            end
            title = title .. "\n新达成里程碑: " .. table.concat(milestoneTexts, ", ")
        end

        Toast.Show(title, { 140, 220, 80 })
        exitFn()
    end

    config.onStart = function()
        State.worldBossActive = true
        GarbageBossSkills.Init(bossDef.bossSkills)
    end
    config.onUpdate = function(dt)
        GarbageBossSkills.Update(dt)
    end

    config.onWin  = function(result) handleResult(result, false) end
    config.onExit = function(result, continueExit) handleResult(result, true, continueExit) end
    config.onLose = function(result) handleResult(result, false) end

    GameUI.EnterDungeonBattle(config)
end

return GarbageBossUI
