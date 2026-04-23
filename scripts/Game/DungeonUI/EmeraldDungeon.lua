-- Game/DungeonUI/EmeraldDungeon.lua
-- 翠影秘境·自然试炼 详情页 UI + 兑换商店 UI + 挑战逻辑

local Config           = require("Game.Config")
local EmeraldData      = require("Game.EmeraldDungeonData")
local EmeraldShop      = require("Game.EmeraldShopData")
local Toast            = require("Game.Toast")
local RewardDisplay    = require("Game.RewardDisplay")
local AdHelper         = require("Game.AdHelper")
local Currency         = require("Game.Currency")

local SweepPopup      = require("Game.SweepPopup")
local EmeraldBossSkills = require("Game.EmeraldBossSkills")
local FormatNum = require("Game.FormatUtil").FormatNum
local LeaderboardUI = require("Game.LeaderboardUI")
local LB = require("Game.LeaderboardData")

local EmeraldDungeon = {}

-- 内部视图状态："detail" | "shop"
local subView = "detail"

-- ============================================================================
-- 辅助
-- ============================================================================

-- FormatNum → 使用 FormatUtil.FormatNum

-- ============================================================================
-- 主入口
-- ============================================================================

function EmeraldDungeon.BuildDetailView(ctx)
    if subView == "shop" then
        EmeraldDungeon._BuildShopView(ctx)
    else
        EmeraldDungeon._BuildDungeonView(ctx)
    end
end

-- ============================================================================
-- 副本详情页
-- ============================================================================

function EmeraldDungeon._BuildDungeonView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local tickets = EmeraldData.GetTickets()
    local adRemaining = EmeraldData.GetAdRemaining()
    local tokenBalance = EmeraldData.GetTokenBalance()
    local remainDays = EmeraldData.GetRemainingDays()
    local isActive = EmeraldData.IsActive()

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%", height = 50,
        flexDirection = "row", alignItems = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = 50, height = 50,
                justifyContent = "center", alignItems = "center",
                onClick = function()
                    subView = "detail"
                    ctx.SetView("list")
                end,
                children = {
                    UI.Label { text = "‹", fontSize = 22, fontColor = S.dim, pointerEvents = "none" },
                },
            },
            UI.Label {
                text = "翠影秘境", fontSize = 20, fontWeight = "bold",
                fontColor = { 100, 220, 140 }, pointerEvents = "none",
            },
            UI.Panel { flex = 1 },
            -- 翠影凭证余额
            UI.Panel {
                paddingLeft = 8, paddingRight = 12,
                paddingTop = 3, paddingBottom = 3,
                flexDirection = "row", alignItems = "center", gap = 4,
                borderRadius = 12,
                backgroundColor = { 40, 80, 50, 180 },
                children = {
                    UI.Panel {
                        width = 14, height = 14,
                        backgroundImage = "image/emerald_certificate.png",
                        backgroundFit = "contain",
                        pointerEvents = "none", flexShrink = 0,
                    },
                    UI.Label {
                        text = FormatNum(tokenBalance),
                        fontSize = 13, fontWeight = "bold",
                        fontColor = { 100, 220, 140 },
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    local contentChildren = {}

    -- 活动信息卡片
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%",
        backgroundColor = { 25, 45, 35, 240 },
        borderRadius = 8, borderWidth = 1,
        borderColor = { 60, 140, 80, 80 },
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 12, paddingBottom = 12,
        flexDirection = "column", gap = 6,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                width = "100%",
                children = {
                    UI.Label {
                        text = "翠影秘境·自然试炼", fontSize = 18, fontWeight = "bold",
                        fontColor = { 100, 220, 140 }, pointerEvents = "none",
                    },
                    UI.Panel {
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 2, paddingBottom = 2,
                        borderRadius = 8,
                        backgroundColor = isActive and { 60, 140, 80, 120 } or { 140, 60, 60, 120 },
                        children = {
                            UI.Label {
                                text = isActive and ("剩余 " .. remainDays .. " 天") or "活动已结束",
                                fontSize = 11,
                                fontColor = isActive and { 120, 255, 160 } or { 255, 120, 120 },
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
            UI.Label {
                text = "通关获取翠影凭证，兑换翎嫣招募券与稀有资源",
                fontSize = 12, fontColor = S.dim, pointerEvents = "none",
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8, marginTop = 2,
                children = {
                    UI.Panel { width = 12, height = 12, backgroundImage = "image/icon_ticket.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                    UI.Label { text = " 秘境券 " .. tickets, fontSize = 11, fontColor = tickets > 0 and { 100, 220, 120 } or S.dim, pointerEvents = "none" },
                    UI.Label { text = "|", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                    UI.Panel { width = 12, height = 12, backgroundImage = "image/icon_ad_video.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                    UI.Label { text = " 可领券 " .. adRemaining .. "/" .. EmeraldData.DAILY_AD_LIMIT, fontSize = 11, fontColor = adRemaining > 0 and { 200, 180, 100 } or S.dim, pointerEvents = "none" },
                    UI.Label { text = "|", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                    UI.Label { text = "累计凭证 " .. FormatNum(EmeraldData.GetTotalTokenEarned()), fontSize = 11, fontColor = { 100, 220, 140 }, pointerEvents = "none" },
                },
            },
        },
    }

    -- 难度选择标题
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%", marginTop = 6,
        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
        children = {
            UI.Label {
                text = "选择难度", fontSize = 14, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
            },
            UI.Label {
                text = "通关奖励为翠影凭证（部分通关按比例发放）", fontSize = 10,
                fontColor = S.dim, pointerEvents = "none",
            },
        },
    }

    -- 6 个难度卡片
    for _, diff in ipairs(EmeraldData.DIFFICULTIES) do
        local unlocked = EmeraldData.IsDifficultyUnlocked(diff.id)
        local bestWaves = EmeraldData.GetBestWaves(diff.id)
        local canEnter = isActive and unlocked and tickets > 0

        -- 词缀选项
        local affixOpt = EmeraldData.GetAffixOption(diff.id)

        -- 奖励描述（带词缀加成）
        local rewardTiers = EmeraldData.GetRewardTiers(diff.id)

        -- 构建按钮（挑战 + 扫荡）
        local actionBtn
        local canSweep, sweepReason = EmeraldData.CanSweep(diff.id)
        local hasDailyChallenged = EmeraldData.HasDailyChallenged(diff.id)
        local sweepBestWaves = EmeraldData.GetBestWaves(diff.id)

        if not isActive then
            actionBtn = UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { 60, 50, 80, 180 },
                children = {
                    UI.Label { text = "已结束", fontSize = 12, fontColor = S.dim, pointerEvents = "none" },
                },
            }
        elseif not unlocked then
            actionBtn = UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { 60, 50, 80, 180 },
                children = {
                    UI.Label { text = EmeraldData.GetUnlockHint(diff.id), fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                },
            }
        else
            -- 挑战按钮
            local challengeBtn
            if canEnter then
                challengeBtn = UI.Panel {
                    paddingLeft = 10, paddingRight = 10,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 6,
                    backgroundColor = { diff.color[1], diff.color[2], diff.color[3], 200 },
                    onClick = function()
                        if EmeraldData.ConsumeTicket() then
                            EmeraldDungeon.StartBattle(UI, S, ctx, diff.id)
                        end
                    end,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 3,
                            pointerEvents = "none",
                            children = {
                                UI.Panel { width = 12, height = 12, backgroundImage = "image/icon_ticket.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                                UI.Label { text = "挑战", fontSize = 12, fontWeight = "bold", fontColor = { 255, 255, 255 }, pointerEvents = "none" },
                            },
                        },
                    },
                }
            else
                challengeBtn = UI.Panel {
                    paddingLeft = 10, paddingRight = 10,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 6,
                    backgroundColor = { 60, 50, 80, 180 },
                    children = {
                        UI.Label { text = "券不足", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                    },
                }
            end

            -- 扫荡按钮（始终显示，不可用时灰色+提示）
            local sweepBtn
            if canSweep then
                sweepBtn = UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 6,
                    backgroundColor = { 80, 60, 180, 200 },
                    onClick = function()
                        EmeraldDungeon.OnSweep(UI, S, ctx, diff)
                    end,
                    children = {
                        UI.Label { text = "扫荡", fontSize = 12, fontWeight = "bold", fontColor = { 255, 255, 255 }, pointerEvents = "none" },
                    },
                }
            else
                -- 不可扫荡 → 灰色，点击提示原因
                local tipText = (sweepBestWaves <= 0) and "需先通关" or (not hasDailyChallenged and "今日未挑战" or sweepReason)
                sweepBtn = UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 6,
                    backgroundColor = { 45, 40, 60, 180 },
                    onClick = function()
                        if sweepBestWaves <= 0 then
                            Toast.Show("需要先挑战一次才能扫荡", { 255, 200, 80 })
                        elseif not hasDailyChallenged then
                            Toast.Show("今日需先挑战一次该难度才能扫荡", { 255, 200, 80 })
                        else
                            Toast.Show(sweepReason, { 255, 200, 80 })
                        end
                    end,
                    children = {
                        UI.Label { text = "扫荡", fontSize = 12, fontColor = S.dim, pointerEvents = "none" },
                    },
                }
            end

            actionBtn = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    challengeBtn,
                    sweepBtn,
                },
            }
        end

        -- 最佳记录标签
        local bestLabel = ""
        local bestCleared = false
        if bestWaves > 0 then
            if bestWaves >= diff.waves then
                bestLabel = "已通关"
                bestCleared = true
            else
                bestLabel = "最佳 " .. bestWaves .. "/" .. diff.waves
            end
        end

        contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%",
            backgroundColor = unlocked and S.cardBg or { 25, 20, 38, 180 },
            borderRadius = 8, borderWidth = 1,
            borderColor = { diff.color[1], diff.color[2], diff.color[3], unlocked and 80 or 30 },
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 10, paddingBottom = 10,
            flexDirection = "row", alignItems = "center", justifyContent = "space-between",
            children = {
                UI.Panel {
                    flexDirection = "column", gap = 3,
                    flexShrink = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = {
                                UI.Label {
                                    text = diff.name, fontSize = 15, fontWeight = "bold",
                                    fontColor = unlocked and diff.color or S.dim,
                                    pointerEvents = "none",
                                },
                                bestLabel ~= "" and (bestCleared and UI.Panel {
                                    flexDirection = "row", alignItems = "center", gap = 2,
                                    children = {
                                        UI.Panel { width = 11, height = 11, backgroundImage = "image/icon_check_pass.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                                        UI.Label { text = bestLabel, fontSize = 10, fontColor = { 100, 220, 100 }, pointerEvents = "none" },
                                    },
                                } or UI.Label {
                                    text = bestLabel, fontSize = 10,
                                    fontColor = { 200, 180, 100 },
                                    pointerEvents = "none",
                                }) or nil,
                            },
                        },
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 2,
                            children = {
                                UI.Label {
                                    text = diff.waves .. "波 · 通关奖励 ",
                                    fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                                },
                                UI.Panel {
                                    width = 12, height = 12,
                                    backgroundImage = "image/emerald_certificate.png",
                                    backgroundFit = "contain",
                                    pointerEvents = "none", flexShrink = 0,
                                },
                                UI.Label {
                                    text = affixOpt.bonusPct > 0
                                        and tostring(math.floor(diff.tokenReward * (1 + affixOpt.bonusPct / 100)))
                                        or tostring(diff.tokenReward),
                                    fontSize = 11,
                                    fontColor = affixOpt.bonusPct > 0 and { 255, 200, 80 } or { 100, 220, 140 },
                                    pointerEvents = "none",
                                },
                                affixOpt.bonusPct > 0 and UI.Label {
                                    text = " (+" .. affixOpt.bonusPct .. "%)",
                                    fontSize = 10, fontColor = { 255, 180, 60 }, pointerEvents = "none",
                                } or nil,
                            },
                        },
                        -- 词缀难度选择行（首次通关后才显示，档位逐级解锁）
                        (unlocked and EmeraldData.IsAffixRowVisible(diff.id)) and (function()
                            local maxIdx = EmeraldData.GetMaxUnlockedAffix(diff.id)
                            local affixBtns = {}
                            for oi = 1, maxIdx do
                                local opt = EmeraldData.AFFIX_OPTIONS[oi]
                                local chosen = (oi == EmeraldData.GetAffixChoice(diff.id))
                                affixBtns[#affixBtns + 1] = UI.Panel {
                                    paddingLeft = 6, paddingRight = 6,
                                    paddingTop = 2, paddingBottom = 2,
                                    borderRadius = 4,
                                    borderWidth = chosen and 1 or 0,
                                    borderColor = chosen and { 255, 200, 80, 200 } or nil,
                                    backgroundColor = chosen
                                        and { 80, 60, 20, 200 }
                                        or { 40, 35, 55, 160 },
                                    onClick = function()
                                        EmeraldData.SetAffixChoice(diff.id, oi)
                                        ctx.Refresh()
                                    end,
                                    children = {
                                        UI.Label {
                                            text = opt.affixCount == 0 and "0 无加成" or (opt.affixCount .. "  +" .. opt.bonusPct .. "%"),
                                            fontSize = 9,
                                            fontColor = chosen
                                                and { 255, 220, 100 }
                                                or (opt.affixCount == 0 and { 160, 160, 160 } or { 180, 160, 120 }),
                                            pointerEvents = "none",
                                        },
                                    },
                                }
                            end
                            -- 在头部插入 "词缀:" 标签
                            table.insert(affixBtns, 1, UI.Label {
                                text = "词缀:", fontSize = 10, fontColor = S.dim, pointerEvents = "none",
                            })
                            return UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 1,
                                children = affixBtns,
                            }
                        end)() or nil,
                        UI.Label {
                            text = "50%→" .. rewardTiers[2].tokens .. "  75%→" .. rewardTiers[3].tokens .. "  100%→" .. rewardTiers[4].tokens,
                            fontSize = 10, fontColor = { 130, 180, 130 }, pointerEvents = "none",
                        },
                    },
                },
                actionBtn,
            },
        }
    end

    -- 特殊机制说明
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%", marginTop = 4,
        backgroundColor = { 30, 25, 45, 200 },
        borderRadius = 8, borderWidth = 1,
        borderColor = { 80, 60, 120, 60 },
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 10, paddingBottom = 10,
        flexDirection = "column", gap = 4,
        children = {
            UI.Label { text = "BOSS技能", fontSize = 13, fontWeight = "bold", fontColor = { 220, 180, 60 }, pointerEvents = "none" },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Panel { width = 24, height = 24, backgroundImage = "image/skill_nature_decay.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                    UI.Panel {
                        flexDirection = "column", gap = 1,
                        children = {
                            UI.Label { text = "自然衰竭", fontSize = 12, fontWeight = "bold", fontColor = { 160, 200, 100 }, pointerEvents = "none" },
                            UI.Label { text = "周期性施放，持久降低全体英雄攻击力与攻速", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
                        },
                    },
                },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Panel { width = 24, height = 24, backgroundImage = "image/skill_silence_domain.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                    UI.Panel {
                        flexDirection = "column", gap = 1,
                        children = {
                            UI.Label { text = "沉寂领域", fontSize = 12, fontWeight = "bold", fontColor = { 160, 120, 220 }, pointerEvents = "none" },
                            UI.Label { text = "周期性施放，全场英雄短暂沉默无法释放技能", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
                        },
                    },
                },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Panel { width = 24, height = 24, backgroundImage = "image/skill_thorn_shackle.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                    UI.Panel {
                        flexDirection = "column", gap = 1,
                        children = {
                            UI.Label { text = "荆棘禁锢", fontSize = 12, fontWeight = "bold", fontColor = { 80, 180, 120 }, pointerEvents = "none" },
                            UI.Label { text = "周期性施放，禁锢英雄使其无法攻击", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
                        },
                    },
                },
            },

        },
    }

    pageRoot:AddChild(UI.ScrollView {
        width = "100%", flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingTop = 8, paddingBottom = 16,
                paddingLeft = 12, paddingRight = 12,
                gap = 8,
                children = contentChildren,
            },
        },
    })

    -- 底部按钮栏
    local bottomChildren = {
        UI.Button {
            text = "返回", fontSize = 14,
            width = 60, height = 46,
            borderRadius = 8, variant = "outline",
            onClick = function()
                subView = "detail"
                ctx.SetView("list")
            end,
        },
        UI.Panel {
            width = 52, height = 46,
            justifyContent = "center", alignItems = "center",
            borderRadius = 8, borderWidth = 1,
            borderColor = { 100, 220, 140, 120 },
            backgroundColor = { 30, 60, 40, 200 },
            onClick = function()
                LeaderboardUI.ShowWithTabs({
                    { key = LB.KEY_EMERALD_TOKEN,    label = "资源榜", format = function(s) return LB.FormatEmeraldToken(s) end },
                    { key = LB.KEY_EMERALD_PROGRESS, label = "进度榜", format = function(s) return LB.FormatEmeraldProgress(s) end },
                }, 1)
            end,
            children = {
                UI.Label { text = "榜", fontSize = 15, fontWeight = "bold", fontColor = { 100, 220, 140 }, pointerEvents = "none" },
            },
        },
        UI.Panel {
            flex = 1, height = 46,
            flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 4,
            borderRadius = 8,
            backgroundColor = { 100, 60, 200, 255 },
            onClick = function()
                subView = "shop"
                ctx.Refresh()
            end,
            children = {
                UI.Label { text = "兑换商店 (", fontSize = 14, fontWeight = "bold", fontColor = { 255, 255, 255 }, pointerEvents = "none" },
                UI.Panel { width = 15, height = 15, backgroundImage = "image/emerald_certificate.png", backgroundFit = "contain", pointerEvents = "none", flexShrink = 0 },
                UI.Label { text = FormatNum(tokenBalance) .. ")", fontSize = 14, fontWeight = "bold", fontColor = { 255, 255, 255 }, pointerEvents = "none" },
            },
        },
    }

    -- 看广告得券按钮（右侧，始终显示）
    if adRemaining > 0 then
        bottomChildren[#bottomChildren + 1] = UI.Button {
            text = "📺 得券(" .. adRemaining .. ")",
            fontSize = 12,
            width = 90, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                AdHelper.ShowRewardAd(function()
                    local ok, msg = EmeraldData.WatchAdForTicket()
                    if ok then
                        Toast.Show(msg, { 100, 220, 140 })
                    else
                        Toast.Show(msg, { 255, 100, 100 })
                    end
                    ctx.Refresh()
                end)
            end,
        }
    else
        bottomChildren[#bottomChildren + 1] = UI.Button {
            text = "📺 已领完",
            fontSize = 12,
            width = 90, height = 46,
            borderRadius = 8,
            variant = "outline",
            fontColor = S.dim,
        }
    end

    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 10,
        flexShrink = 0, gap = 8,
        children = bottomChildren,
    })
end

-- ============================================================================
-- 兑换商店视图
-- ============================================================================

function EmeraldDungeon._BuildShopView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local tokenBalance = EmeraldData.GetTokenBalance()

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%", height = 50,
        flexDirection = "row", alignItems = "center",
        backgroundColor = { 25, 45, 35, 255 },
        flexShrink = 0,
        children = {
            UI.Panel {
                width = 50, height = 50,
                justifyContent = "center", alignItems = "center",
                onClick = function()
                    subView = "detail"
                    ctx.Refresh()
                end,
                children = {
                    UI.Label { text = "‹", fontSize = 22, fontColor = S.dim, pointerEvents = "none" },
                },
            },
            UI.Panel {
                width = 22, height = 22,
                backgroundImage = "image/emerald_certificate.png",
                backgroundFit = "contain",
                pointerEvents = "none", flexShrink = 0,
            },
            UI.Label {
                text = " 翠影兑换", fontSize = 20, fontWeight = "bold",
                fontColor = { 100, 220, 140 }, pointerEvents = "none",
            },
            UI.Panel { flex = 1 },
            UI.Panel {
                paddingLeft = 8, paddingRight = 12,
                paddingTop = 3, paddingBottom = 3,
                flexDirection = "row", alignItems = "center", gap = 4,
                borderRadius = 12,
                backgroundColor = { 40, 80, 50, 180 },
                children = {
                    UI.Panel {
                        width = 14, height = 14,
                        backgroundImage = "image/emerald_certificate.png",
                        backgroundFit = "contain",
                        pointerEvents = "none", flexShrink = 0,
                    },
                    UI.Label {
                        text = FormatNum(tokenBalance),
                        fontSize = 13, fontWeight = "bold",
                        fontColor = { 100, 220, 140 },
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    -- 商品列表
    local contentChildren = {}

    for _, cat in ipairs(EmeraldShop.CATEGORIES) do
        local items = EmeraldShop.GetItemsByCategory(cat.id)
        if #items > 0 then
            -- 分类标题
            contentChildren[#contentChildren + 1] = UI.Label {
                text = cat.name, fontSize = 14, fontWeight = "bold",
                fontColor = cat.color, pointerEvents = "none",
                marginTop = 4,
            }

            -- 商品卡片
            for _, item in ipairs(items) do
                local remaining = EmeraldShop.GetRemaining(item.id)
                local bought = EmeraldShop.GetBoughtCount(item.id)
                local canBuy = remaining > 0 and tokenBalance >= item.cost
                local soldOut = remaining == 0

                local iconWidget
                if item.image then
                    iconWidget = UI.Panel {
                        width = 28, height = 28,
                        backgroundImage = item.image,
                        backgroundFit = "cover",
                        borderRadius = 4,
                        pointerEvents = "none",
                        flexShrink = 0,
                    }
                else
                    iconWidget = Currency.IconWidget(UI, item.icon, 28)
                end

                -- 标签
                local tagWidget = nil
                if item.tag then
                    tagWidget = UI.Panel {
                        paddingLeft = 5, paddingRight = 5,
                        paddingTop = 1, paddingBottom = 1,
                        borderRadius = 4,
                        backgroundColor = { (item.tagColor or cat.color)[1], (item.tagColor or cat.color)[2], (item.tagColor or cat.color)[3], 60 },
                        children = {
                            UI.Label { text = item.tag, fontSize = 9, fontColor = item.tagColor or cat.color, pointerEvents = "none" },
                        },
                    }
                end

                contentChildren[#contentChildren + 1] = UI.Panel {
                    width = "100%",
                    backgroundColor = soldOut and { 25, 20, 38, 160 } or S.cardBg,
                    borderRadius = 8, borderWidth = 1,
                    borderColor = soldOut and { 50, 42, 65, 60 } or { 60, 140, 80, 60 },
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 10, paddingBottom = 10,
                    flexDirection = "row", alignItems = "center",
                    gap = 10,
                    children = {
                        -- 图标
                        iconWidget,
                        -- 信息
                        UI.Panel {
                            flex = 1, flexDirection = "column", gap = 2,
                            children = {
                                UI.Panel {
                                    flexDirection = "row", alignItems = "center", gap = 6,
                                    children = {
                                        UI.Label {
                                            text = item.name, fontSize = 14, fontWeight = "bold",
                                            fontColor = soldOut and S.dim or S.white,
                                            pointerEvents = "none",
                                        },
                                        tagWidget,
                                    },
                                },
                                UI.Panel {
                                    flexDirection = "row", alignItems = "center", gap = 8,
                                    children = {
                                        UI.Panel {
                                            width = 13, height = 13,
                                            backgroundImage = "image/emerald_certificate.png",
                                            backgroundFit = "contain",
                                            pointerEvents = "none", flexShrink = 0,
                                        },
                                        UI.Label {
                                            text = " " .. item.cost,
                                            fontSize = 12,
                                            fontColor = tokenBalance >= item.cost and { 100, 220, 140 } or { 220, 80, 80 },
                                            pointerEvents = "none",
                                        },
                                        UI.Label {
                                            text = "限购 " .. bought .. "/" .. item.limit,
                                            fontSize = 10,
                                            fontColor = soldOut and { 180, 80, 80 } or S.dim,
                                            pointerEvents = "none",
                                        },
                                    },
                                },
                            },
                        },
                        -- 购买按钮
                        soldOut and UI.Panel {
                            paddingLeft = 10, paddingRight = 10,
                            paddingTop = 6, paddingBottom = 6,
                            borderRadius = 6,
                            backgroundColor = { 60, 50, 80, 180 },
                            children = {
                                UI.Label { text = "已售罄", fontSize = 12, fontColor = S.dim, pointerEvents = "none" },
                            },
                        } or UI.Panel {
                            paddingLeft = 12, paddingRight = 12,
                            paddingTop = 6, paddingBottom = 6,
                            borderRadius = 6,
                            backgroundColor = canBuy and { 60, 160, 100, 220 } or { 60, 50, 80, 180 },
                            onClick = canBuy and function()
                                EmeraldDungeon._ConfirmPurchase(UI, S, ctx, item)
                            end or nil,
                            children = {
                                UI.Label {
                                    text = canBuy and "兑换" or "凭证不足",
                                    fontSize = 13, fontWeight = "bold",
                                    fontColor = canBuy and { 255, 255, 255 } or S.dim,
                                    pointerEvents = "none",
                                },
                            },
                        },
                    },
                }
            end
        end
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%", flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingTop = 8, paddingBottom = 16,
                paddingLeft = 12, paddingRight = 12,
                gap = 6,
                children = contentChildren,
            },
        },
    })

    -- 底部
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 10,
        flexShrink = 0, gap = 10,
        children = {
            UI.Button {
                text = "返回副本", fontSize = 14,
                flex = 1, height = 46,
                borderRadius = 8, variant = "outline",
                onClick = function()
                    subView = "detail"
                    ctx.Refresh()
                end,
            },
        },
    })
end

--- 购买确认弹窗
function EmeraldDungeon._ConfirmPurchase(UI, S, ctx, item)
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlayId = "emeraldShopConfirm"
    local old = root:FindById(overlayId)
    if old then root:RemoveChild(old) end

    local function close()
        local o = root:FindById(overlayId)
        if o then root:RemoveChild(o) end
    end

    root:AddChild(UI.Panel {
        id = overlayId,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function() close() end,
        children = {
            UI.Panel {
                width = 280,
                backgroundColor = S.cardBg,
                borderRadius = 12, borderWidth = 1,
                borderColor = { 60, 140, 80, 100 },
                paddingLeft = 20, paddingRight = 20,
                paddingTop = 20, paddingBottom = 20,
                flexDirection = "column", gap = 14,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "确认兑换", fontSize = 18, fontWeight = "bold",
                        fontColor = S.white, pointerEvents = "none",
                    },
                    UI.Label {
                        text = item.name, fontSize = 16,
                        fontColor = { 100, 220, 140 }, pointerEvents = "none",
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 3,
                        children = {
                            UI.Label { text = "消耗 ", fontSize = 13, fontColor = S.dim, pointerEvents = "none" },
                            UI.Panel {
                                width = 14, height = 14,
                                backgroundImage = "image/emerald_certificate.png",
                                backgroundFit = "contain",
                                pointerEvents = "none", flexShrink = 0,
                            },
                            UI.Label { text = " " .. item.cost .. " 翠影凭证", fontSize = 13, fontColor = S.dim, pointerEvents = "none" },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12,
                        children = {
                            UI.Button {
                                text = "取消", fontSize = 14,
                                width = 90, height = 38,
                                borderRadius = 8, variant = "outline",
                                onClick = function() close() end,
                            },
                            UI.Button {
                                text = "确认兑换", fontSize = 14,
                                width = 120, height = 38,
                                borderRadius = 8, variant = "primary",
                                onClick = function()
                                    close()
                                    local ok, msg, rewards = EmeraldShop.Purchase(item.id)
                                    if ok then
                                        Toast.Show(msg, { 100, 220, 140 })
                                        if rewards and #rewards > 0 then
                                            RewardDisplay.Show(UI, root, {
                                                title = "兑换成功",
                                                rewards = rewards,
                                                onClose = function()
                                                    ctx.Refresh()
                                                end,
                                            })
                                        else
                                            ctx.Refresh()
                                        end
                                    else
                                        Toast.Show(msg, { 255, 100, 100 })
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 扫荡逻辑
-- ============================================================================

function EmeraldDungeon.OnSweep(UI, S, ctx, diff)
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local bestWaves = EmeraldData.GetBestWaves(diff.id)
    if bestWaves <= 0 then
        Toast.Show("需要先挑战一次才能扫荡", { 255, 200, 80 })
        return
    end

    local tickets = EmeraldData.GetTickets()
    if tickets <= 0 then
        Toast.Show("秘境券不足", { 255, 100, 100 })
        return
    end

    local affixOpt = EmeraldData.GetAffixOption(diff.id)

    SweepPopup.Show(UI, root, S, {
        title = diff.name .. " · 连续扫荡",
        maxCount = tickets,
        sweepLabel = "最高纪录",
        sweepValue = "第 " .. bestWaves .. "/" .. diff.waves .. " 波"
            .. (affixOpt.bonusPct > 0 and ("  词缀+" .. affixOpt.bonusPct .. "%") or ""),
        previewFn = function(count)
            local tokens = EmeraldData.CalcTokenReward(bestWaves, diff.id, affixOpt.bonusPct)
            return {
                {
                    icon = "image/emerald_certificate.png",
                    name = "翠影凭证",
                    amount = tokens * count,
                    color = { 100, 220, 140 },
                },
            }
        end,
        onConfirm = function(count)
            local totalTokens = 0
            for i = 1, count do
                local ok, tokens = EmeraldData.DoSweep(diff.id, affixOpt.bonusPct)
                if ok then
                    totalTokens = totalTokens + tokens
                else
                    if i == 1 then return end  -- 第一次就失败，不显示结果
                    break
                end
            end

            -- 显示扫荡结果
            local rewardItems = {}
            if totalTokens > 0 then
                rewardItems[#rewardItems + 1] = {
                    icon = "image/emerald_certificate.png",
                    name = "翠影凭证",
                    amount = totalTokens,
                    color = { 100, 220, 140 },
                }
            end

            RewardDisplay.Show(UI, root, {
                title = diff.name .. " · 扫荡完成 ×" .. count,
                rewards = rewardItems,
                onClose = function()
                    ctx.Refresh()
                end,
            })
        end,
    })
end

-- ============================================================================
-- 战斗逻辑
-- ============================================================================

function EmeraldDungeon.StartBattle(UI, S, ctx, difficultyId)
    local GameUI = require("Game.GameUI")
    local BM = require("Game.BattleManager")
    local StateM = require("Game.State")

    local session = EmeraldData.CreateSession(difficultyId)
    if not session then return end

    local diff = session.difficulty
    local totalWaves = diff.waves

    -- 生成驻场 BOSS（开局出场，附加词缀难度）
    local bossDef = EmeraldData.GenerateBoss(difficultyId, session.affixCount)
    local bossQueue = bossDef and BM.BuildSpawnQueue({ bossDef }, 0.5) or {}

    -- 预构建所有小怪波次
    local waves = {}
    for w = 1, totalWaves do
        local enemyDefs = EmeraldData.GenerateWaveEnemies(w, difficultyId)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    -- BOSS 插入第一波队列头部（先出 BOSS，再出小怪）
    if #bossQueue > 0 then
        for i = #bossQueue, 1, -1 do
            table.insert(waves[1], 1, bossQueue[i])
        end
        -- 驻场 BOSS 从第一波就出场，但不应立即触发 BOSS 计时器
        -- 强制标记第一波为 normal，计时器将在所有小怪清完后由 BattleManager 激活
        waves[1]._waveType = "normal"
    end

    local label = "翠影秘境 · " .. diff.name

    GameUI.EnterDungeonBattle({
        mode = "emerald_dungeon",
        waves = waves,
        totalWaves = totalWaves,
        label = label,
        waveInterval = 20,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit = 60,
        bossTimerEnabled = true,  -- BOSS 计时器由 BattleManager 在全波小怪清完后激活
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
        -- BOSS 技能数据（BattleManager/Combat 可读取）
        emeraldMechanics = bossDef and bossDef.bossSkills or nil,
        onStart = function()
            local mechanics = bossDef and bossDef.bossSkills or nil
            if mechanics then
                EmeraldBossSkills.Init(mechanics)
            end
        end,
        onUpdate = function(dt)
            EmeraldBossSkills.Update(dt)
        end,
        onWin = function(result)
            EmeraldBossSkills.Cleanup()
            -- 所有波次通关
            for w = 1, totalWaves do
                session.currentWave = w
                EmeraldData.CompleteWave(session)
            end
            local endResult = EmeraldData.EndSession(session)
            EmeraldDungeon._ShowResult(UI, S, ctx, endResult, label, true)
        end,
        onLose = function(result)
            EmeraldBossSkills.Cleanup()
            -- 用 BattleManager 计算的实际通关波数（基于最早存活敌人的波次）
            local clearedWaves = result and result.clearedWave or 0
            for w = 1, clearedWaves do
                session.currentWave = w
                EmeraldData.CompleteWave(session)
            end
            local endResult = EmeraldData.EndSession(session)
            EmeraldDungeon._ShowResult(UI, S, ctx, endResult, label, false)
        end,
    })
end

--- 显示战斗结果
function EmeraldDungeon._ShowResult(UI, S, ctx, result, label, isWin)
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then
        GameUI.ExitDungeonBattle()
        return
    end

    local rewardItems = {}
    if result.tokens > 0 then
        rewardItems[#rewardItems + 1] = {
            icon = "image/emerald_certificate.png",
            name = "翠影凭证",
            amount = result.tokens,
            color = { 100, 220, 140 },
        }
    end
    if result.firstClearBonus then
        rewardItems[#rewardItems + 1] = {
            icon = "image/icon_ticket.png",
            name = "秘境券（首次通关）",
            amount = 1,
            color = { 255, 220, 80 },
        }
    end

    local ratioText = ""
    if result.ratio < 1.0 then
        ratioText = string.format("（通关 %d/%d 波，获得 %d%% 奖励）",
            result.clearedWave, result.totalWaves, math.floor(result.ratio * 100))
    end

    local title = isWin and (label .. " 通关") or (label .. " 失败")
    if ratioText ~= "" then
        title = title .. "\n" .. ratioText
    end

    RewardDisplay.Show(UI, root, {
        title = title,
        rewards = rewardItems,
        onClose = function()
            subView = "detail"
            ctx.SetView("emerald_dungeon_detail")
            GameUI.ExitDungeonBattle()
        end,
    })
end

return EmeraldDungeon
