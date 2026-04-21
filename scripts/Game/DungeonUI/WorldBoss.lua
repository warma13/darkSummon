-- Game/DungeonUI/WorldBoss.lua
-- 世界BOSS详情页 UI + 挑战逻辑

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local WB = require("Game.WorldBossData")
local WorldBossSkills = require("Game.WorldBossSkills")
local Toast = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local AdHelper = require("Game.AdHelper")

local WorldBoss = {}

-- ============================================================================
-- 世界BOSS详情页
-- ============================================================================

function WorldBoss.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local data = WB.GetData()
    local bestDamage = WB.GetBestDamage()
    local remaining = WB.GetRemainingAttempts()
    local cfg = WB.CONFIG

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = 50, height = 50,
                justifyContent = "center", alignItems = "center",
                onClick = function()
                    ctx.SetView("list")
                end,
                children = {
                    UI.Label { text = "‹", fontSize = 22, fontColor = S.dim, pointerEvents = "none" },
                },
            },
            UI.Label {
                text = "世界BOSS", fontSize = 20, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
            },
            UI.Panel { flex = 1 },
            UI.Panel {
                paddingLeft = 8, paddingRight = 12,
                paddingTop = 3, paddingBottom = 3,
                children = {
                    UI.Label {
                        text = "剩余 " .. remaining .. " 次",
                        fontSize = 12,
                        fontColor = remaining > 0 and S.green or S.red,
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    -- 滚动内容
    local contentChildren = {}

    -- BOSS 信息卡
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 8,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                backgroundColor = S.cardBg,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 180, 50, 70, 80 },
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 12, paddingBottom = 12,
                children = {
                    UI.Panel {
                        flexDirection = "column", gap = 4,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 6,
                                children = {
                                    UI.Label {
                                        text = "💀", fontSize = 20, pointerEvents = "none",
                                    },
                                    UI.Label {
                                        text = "深渊主宰", fontSize = 18, fontWeight = "bold",
                                        fontColor = { 220, 80, 80 }, pointerEvents = "none",
                                    },
                                },
                            },
                            UI.Label {
                                text = "HP: 无限  |  DEF: " .. ctx.FormatNum(cfg.bossDEF) .. "（随时间增长）",
                                fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                            },
                            UI.Label {
                                text = cfg.totalDuration .. "秒 · 越打越难 · 每秒掉落" .. cfg.darkSoulDrain .. "暗魂",
                                fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column", alignItems = "flex-end", gap = 4,
                        children = {
                            UI.Label { text = "最高伤害", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                            UI.Label {
                                text = bestDamage > 0 and WB.FormatDamage(bestDamage) or "—",
                                fontSize = 16, fontWeight = "bold",
                                fontColor = bestDamage > 0 and S.gold or S.dim,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
        },
    }

    -- BOSS 技能说明
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = S.cardBg,
                borderRadius = 8,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 8, paddingBottom = 8,
                flexDirection = "column",
                gap = 6,
                children = {
                    UI.Label {
                        text = "BOSS 技能", fontSize = 13, fontWeight = "bold",
                        fontColor = S.white, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "束缚 · 每15秒束缚1名英雄5秒，低星更易被选中",
                        fontSize = 11, fontColor = { 200, 160, 80 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "召唤 · 每30秒召唤精英怪，数量逐次递增(最多5只)",
                        fontSize = 11, fontColor = { 160, 200, 80 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "销毁 · 每45秒销毁1名英雄(3秒预警)，低星易被选中",
                        fontSize = 11, fontColor = { 220, 80, 80 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "提示：合成高星英雄可降低被针对概率",
                        fontSize = 10, fontColor = S.dim, pointerEvents = "none",
                    },
                },
            },
        },
    }

    -- 奖励档位表
    local tierRows = {}
    tierRows[#tierRows + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingBottom = 4,
        children = {
            UI.Label { text = "累计伤害", fontSize = 12, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
            UI.Label { text = "霜誓契约", fontSize = 12, fontWeight = "bold", fontColor = { 130, 210, 255 }, pointerEvents = "none" },
        },
    }

    local cumReward = 0
    for i, tier in ipairs(cfg.rewardTiers) do
        local threshold = tier[1]
        local amount = tier[2]
        cumReward = cumReward + amount
        local reached = bestDamage >= threshold

        tierRows[#tierRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 3, paddingBottom = 3,
            backgroundColor = reached and { 45, 70, 45, 120 } or nil,
            borderRadius = 4,
            paddingLeft = 4, paddingRight = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label {
                            text = reached and "✓" or ("Lv." .. i),
                            fontSize = 10,
                            fontColor = reached and S.green or S.dim,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = WB.FormatDamage(threshold),
                            fontSize = 12,
                            fontColor = reached and S.green or S.white,
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 3,
                    children = {
                        Currency.IconWidget(UI, "frost_pact", 12),
                        UI.Label {
                            text = "×" .. amount .. " (累计" .. cumReward .. ")",
                            fontSize = 11,
                            fontColor = reached and { 130, 210, 255 } or S.dim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = S.cardBg,
                borderRadius = 8,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 8, paddingBottom = 8,
                flexDirection = "column",
                children = tierRows,
            },
        },
    }

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = contentChildren,
    })

    -- 底部按钮
    pageRoot:AddChild(WorldBoss._BuildChallengeButton(UI, S, ctx, remaining))
end

--- 底部挑战按钮
function WorldBoss._BuildChallengeButton(UI, S, ctx, remaining)
    local freeRemaining = WB.GetFreeRemaining()
    local adRemaining = WB.GetAdRemaining()
    local ticketCount = WB.GetTicketCount()

    local actionChildren = {
        UI.Button {
            text = "返回",
            fontSize = 14,
            width = 70, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                ctx.SetView("list")
            end,
        },
    }

    if freeRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "挑战深渊主宰",
            fontSize = 15,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                WorldBoss.OnChallenge(UI, S, ctx, false)
            end,
        }
    elseif ticketCount > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "使用挑战券 (剩" .. ticketCount .. "张)",
            fontSize = 14,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                WorldBoss.OnTicketChallenge(UI, S, ctx)
            end,
        }
    else
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "今日次数已用完",
            fontSize = 13,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "outline",
        }
    end

    -- 看广告领券
    if adRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "📺 领券(" .. adRemaining .. ")",
            fontSize = 12,
            width = 90, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                WorldBoss.OnAdGetTicket(UI, S, ctx)
            end,
        }
    end

    actionChildren[#actionChildren + 1] = UI.Button {
        text = "🏆 排行",
        fontSize = 13,
        width = 76, height = 46,
        borderRadius = 8,
        variant = "outline",
        onClick = function()
            local LeaderboardUI = require("Game.LeaderboardUI")
            LeaderboardUI.Show(3)
        end,
    }

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 10,
        flexShrink = 0,
        gap = 10,
        children = actionChildren,
    }
end

-- ============================================================================
-- 挑战逻辑
-- ============================================================================

--- 看广告领挑战券
function WorldBoss.OnAdGetTicket(UI, S, ctx)
    if WB.GetAdRemaining() <= 0 then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return
    end

    AdHelper.ShowRewardAd(function()
        WB.ConsumeAdForTicket()
        ctx.Refresh()
    end)
end

--- 使用挑战券挑战
function WorldBoss.OnTicketChallenge(UI, S, ctx)
    if not WB.ConsumeTicket() then return end
    WorldBoss.OnChallenge(UI, S, ctx, true)
end

---@param skipConsume boolean
function WorldBoss.OnChallenge(UI, S, ctx, skipConsume)
    if #HeroData.GetDeployedList() < Config.MAX_DEPLOYED then
        Toast.Show("需要上阵" .. Config.MAX_DEPLOYED .. "名英雄才能挑战", S.red)
        return
    end

    if not skipConsume then
        if not WB.ConsumeAttempt() then return end
    end

    -- 每日任务：挑战Boss副本
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("boss", 1) end

    local BM = require("Game.BattleManager")
    local GameUI = require("Game.GameUI")
    local State = require("Game.State")

    local cfg = WB.CONFIG

    local bossDef = WB.CreateWorldBossDef()
    local waves = {
        {
            {
                type = bossDef.id or "world_boss",
                typeDef = bossDef,
                delay = 0,
                isElite = false,
                affixes = {},
                prescaled = true,
            },
        },
    }

    local label = "世界BOSS · 深渊主宰"

    GameUI.EnterDungeonBattle({
        mode = "world_boss",
        waves = waves,
        totalWaves = 1,
        stageNum = 1,
        label = label,
        waveInterval = 0,
        autoAdvanceWave = false,
        bossTimerEnabled = true,
        overloadEnabled = false,
        worldBossDuration = cfg.totalDuration,
        worldBossDarkSoulDrain = cfg.darkSoulDrain,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,

        onStart = function()
            WorldBossSkills.Init()
        end,

        onWin = function(result)
            WorldBossSkills.Cleanup()
            State.worldBossActive = false
            local totalDamage = result.totalDamage or State.worldBossTotalDamage

            local rewards = WB.ClaimReward(totalDamage)
            local rewardItems = {}
            if rewards and rewards.recruit_ticket_select_box then
                local itemDef = Config.CURRENCY["recruit_ticket_select_box"]
                rewardItems[#rewardItems + 1] = {
                    icon = itemDef and itemDef.image or "image/icon_recruit_ticket_select_box.png",
                    name = itemDef and itemDef.name or "招募券自选包",
                    amount = rewards.recruit_ticket_select_box,
                    borderColor = { 200, 150, 255, 200 },
                }
            end

            local title = label .. " 通关!\n伤害: " .. WB.FormatDamage(totalDamage)

            if #rewardItems > 0 then
                local root = GameUI.GetUIRoot()
                if root then
                    RewardDisplay.Show(UI, root, {
                        title = title,
                        rewards = rewardItems,
                        onClose = function()
                            GameUI.ExitDungeonBattle()
                        end,
                    })
                    return
                end
            else
                Toast.Show("伤害: " .. WB.FormatDamage(totalDamage) .. " · 未达到奖励阈值", S.dim)
            end
            GameUI.ExitDungeonBattle()
        end,

        onExit = function(result)
            WorldBossSkills.Cleanup()
            State.worldBossActive = false
            local totalDamage = result.totalDamage or State.worldBossTotalDamage

            local rewards = WB.ClaimReward(totalDamage)
            local rewardItems = {}
            if rewards and rewards.recruit_ticket_select_box then
                local itemDef = Config.CURRENCY["recruit_ticket_select_box"]
                rewardItems[#rewardItems + 1] = {
                    icon = itemDef and itemDef.image or "image/icon_recruit_ticket_select_box.png",
                    name = itemDef and itemDef.name or "招募券自选包",
                    amount = rewards.recruit_ticket_select_box,
                    borderColor = { 200, 150, 255, 200 },
                }
            end

            if #rewardItems > 0 then
                local root = GameUI.GetUIRoot()
                if root then
                    RewardDisplay.Show(UI, root, {
                        title = label .. " 退出\n伤害: " .. WB.FormatDamage(totalDamage),
                        rewards = rewardItems,
                        onClose = function()
                            GameUI.ExitDungeonBattle()
                        end,
                    })
                    return
                end
            else
                Toast.Show("伤害: " .. WB.FormatDamage(totalDamage), S.dim)
            end
            GameUI.ExitDungeonBattle()
        end,

        onLose = function(result)
            local BM_ = require("Game.BattleManager")
            if BM_.config then BM_.config.onExit = nil end

            WorldBossSkills.Cleanup()
            State.worldBossActive = false
            local totalDamage = result.totalDamage or State.worldBossTotalDamage

            local rewards = WB.ClaimReward(totalDamage)
            local rewardItems = {}
            if rewards and rewards.recruit_ticket_select_box then
                local itemDef = Config.CURRENCY["recruit_ticket_select_box"]
                rewardItems[#rewardItems + 1] = {
                    icon = itemDef and itemDef.image or "image/icon_recruit_ticket_select_box.png",
                    name = itemDef and itemDef.name or "招募券自选包",
                    amount = rewards.recruit_ticket_select_box,
                    borderColor = { 200, 150, 255, 200 },
                }
            end

            local title = label .. " 挑战结束\n伤害: " .. WB.FormatDamage(totalDamage)

            if #rewardItems > 0 then
                local root = GameUI.GetUIRoot()
                if root then
                    RewardDisplay.Show(UI, root, {
                        title = title,
                        rewards = rewardItems,
                        onClose = function()
                            GameUI.ExitDungeonBattle()
                        end,
                    })
                    return
                end
            else
                Toast.Show("伤害: " .. WB.FormatDamage(totalDamage) .. " · 未达到奖励阈值", S.red)
            end
            GameUI.ExitDungeonBattle()
        end,
    })
end

return WorldBoss
