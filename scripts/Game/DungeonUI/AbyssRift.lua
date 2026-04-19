-- Game/DungeonUI/AbyssRift.lua
-- 深渊裂隙详情页 UI + 挑战逻辑

local Config = require("Game.Config")
local AbyssRiftData = require("Game.AbyssRiftDungeon")
local RuneConfig = require("Game.Config_Runes")
local Toast = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local AdHelper = require("Game.AdHelper")
local Currency = require("Game.Currency")

local AbyssRift = {}

-- ============================================================================
-- 深渊裂隙详情页
-- ============================================================================

function AbyssRift.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local free, ad = AbyssRiftData.GetRemaining()
    local totalRemain = free + ad

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
                text = "🌀 深渊裂隙", fontSize = 20, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
            },
            UI.Panel { flex = 1 },
            UI.Panel {
                paddingLeft = 8, paddingRight = 12,
                paddingTop = 3, paddingBottom = 3,
                children = {
                    UI.Label {
                        text = "剩余 " .. totalRemain .. " 次",
                        fontSize = 12,
                        fontColor = totalRemain > 0 and S.green or S.red,
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    -- 内容
    local contentChildren = {}

    -- 副本说明卡片
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%",
        backgroundColor = S.cardBg,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 160, 80, 220, 60 },
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 12, paddingBottom = 12,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Label {
                text = "深渊裂隙", fontSize = 18, fontWeight = "bold",
                fontColor = { 180, 120, 255 }, pointerEvents = "none",
            },
            UI.Label {
                text = AbyssRiftData.TOTAL_WAVES .. "波 × " .. AbyssRiftData.ENEMIES_PER_WAVE .. "怪  |  击败敌人掉落符文与洗练材料",
                fontSize = 12, fontColor = S.dim, pointerEvents = "none",
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6, marginTop = 4,
                children = {
                    UI.Label { text = "每日免费 " .. AbyssRiftData.DAILY_FREE .. " 次", fontSize = 11, fontColor = { 100, 200, 120 }, pointerEvents = "none" },
                    UI.Label { text = " + ", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                    UI.Label { text = "广告 " .. AbyssRiftData.DAILY_AD .. " 次", fontSize = 11, fontColor = { 200, 180, 100 }, pointerEvents = "none" },
                },
            },
        },
    }

    -- 难度选择标题
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        marginTop = 6,
        children = {
            UI.Label {
                text = "选择难度", fontSize = 14, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
            },
        },
    }

    -- 难度选择卡片
    for _, diff in ipairs(AbyssRiftData.DIFFICULTIES) do
        local est = AbyssRiftData.EstimateFullClearDrops(diff.id)
        local diffColor = diff.id == "normal" and { 120, 200, 120 }
            or diff.id == "hard" and { 200, 160, 60 }
            or { 220, 80, 80 }

        contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%",
            backgroundColor = S.cardBg,
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { diffColor[1], diffColor[2], diffColor[3], 60 },
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 10, paddingBottom = 10,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            onClick = function()
                if totalRemain <= 0 then
                    Toast.Show("今日挑战次数已用完", { 255, 200, 80 })
                    return
                end
                local ok, msg = AbyssRiftData.ConsumeEntry()
                if ok then
                    AbyssRift.StartBattle(UI, S, ctx, diff.id)
                elseif msg == "ad_required" then
                    AdHelper.ShowRewardAd(function()
                        AbyssRiftData.ConsumeAdEntry()
                        AbyssRift.StartBattle(UI, S, ctx, diff.id)
                    end)
                end
            end,
            children = {
                UI.Panel {
                    flexDirection = "column", gap = 3,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = {
                                UI.Label {
                                    text = diff.name, fontSize = 16, fontWeight = "bold",
                                    fontColor = diffColor, pointerEvents = "none",
                                },
                                UI.Label {
                                    text = "×" .. string.format("%.1f", diff.levelMult),
                                    fontSize = 12, fontColor = S.dim, pointerEvents = "none",
                                },
                            },
                        },
                        UI.Label {
                            text = "预计掉落: 尘" .. est.totalDust .. " 符文" .. string.format("%.1f", est.avgRunes) .. " 封印" .. string.format("%.1f", est.avgSeals),
                            fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 6,
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 4,
                    backgroundColor = totalRemain > 0
                        and { diffColor[1], diffColor[2], diffColor[3], 180 }
                        or { 60, 50, 80, 180 },
                    children = (free <= 0 and ad > 0) and {
                        UI.Label {
                            text = "📺", fontSize = 14,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = "挑战", fontSize = 13, fontWeight = "bold",
                            fontColor = S.white, pointerEvents = "none",
                        },
                    } or {
                        UI.Label {
                            text = totalRemain > 0 and "挑战" or "次数不足",
                            fontSize = 13, fontWeight = "bold",
                            fontColor = totalRemain > 0 and S.white or S.dim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
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

    -- 底部三栏按钮
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 10,
        flexShrink = 0,
        gap = 10,
        children = {
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
            UI.Button {
                text = "选择难度挑战",
                fontSize = 16,
                flex = 1, height = 46,
                borderRadius = 8,
                variant = "primary",
                onClick = function()
                    AbyssRift._ShowDifficultyPicker(UI, S, ctx)
                end,
            },
            UI.Button {
                text = "🏆 排行",
                fontSize = 13,
                width = 76, height = 46,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    local LeaderboardUI = require("Game.LeaderboardUI")
                    local LeaderboardData = require("Game.LeaderboardData")
                    LeaderboardUI.ShowWithTabs({
                        { key = LeaderboardData.KEY_ABYSS_NORMAL,    label = "普通", format = function(s) return LeaderboardData.FormatAbyss(s) end },
                        { key = LeaderboardData.KEY_ABYSS_HARD,      label = "困难", format = function(s) return LeaderboardData.FormatAbyss(s) end },
                        { key = LeaderboardData.KEY_ABYSS_NIGHTMARE, label = "噩梦", format = function(s) return LeaderboardData.FormatAbyss(s) end },
                    })
                end,
            },
        },
    })
end

--- 难度选择弹窗
function AbyssRift._ShowDifficultyPicker(UI, S, ctx)
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local free, ad = AbyssRiftData.GetRemaining()
    local totalRemain = free + ad

    local overlayId = "abyssDiffPicker"
    local old = root:FindById(overlayId)
    if old then root:RemoveChild(old) end

    local function closePicker()
        local o = root:FindById(overlayId)
        if o then root:RemoveChild(o) end
    end

    local diffCards = {}
    for _, diff in ipairs(AbyssRiftData.DIFFICULTIES) do
        local diffColor = diff.id == "normal" and { 120, 200, 120 }
            or diff.id == "hard" and { 200, 160, 60 }
            or { 220, 80, 80 }
        local est = AbyssRiftData.EstimateFullClearDrops(diff.id)

        diffCards[#diffCards + 1] = UI.Panel {
            width = "100%",
            backgroundColor = S.cardBg,
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { diffColor[1], diffColor[2], diffColor[3], 80 },
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 12, paddingBottom = 12,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            onClick = function()
                closePicker()
                if totalRemain <= 0 then
                    Toast.Show("今日挑战次数已用完", { 255, 200, 80 })
                    return
                end
                local ok, msg = AbyssRiftData.ConsumeEntry()
                if ok then
                    AbyssRift.StartBattle(UI, S, ctx, diff.id)
                elseif msg == "ad_required" then
                    AdHelper.ShowRewardAd(function()
                        AbyssRiftData.ConsumeAdEntry()
                        AbyssRift.StartBattle(UI, S, ctx, diff.id)
                    end)
                end
            end,
            children = {
                UI.Panel {
                    flexDirection = "column", gap = 3,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = {
                                UI.Label {
                                    text = diff.name, fontSize = 16, fontWeight = "bold",
                                    fontColor = diffColor, pointerEvents = "none",
                                },
                                UI.Label {
                                    text = "×" .. string.format("%.1f", diff.levelMult),
                                    fontSize = 12, fontColor = S.dim, pointerEvents = "none",
                                },
                            },
                        },
                        UI.Label {
                            text = "预计: 尘" .. est.totalDust .. " 符文" .. string.format("%.1f", est.avgRunes),
                            fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 6,
                    backgroundColor = totalRemain > 0
                        and { diffColor[1], diffColor[2], diffColor[3], 180 }
                        or { 60, 50, 80, 180 },
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = (free <= 0 and ad > 0) and {
                        UI.Label { text = "📺", fontSize = 14, pointerEvents = "none" },
                        UI.Label { text = "挑战", fontSize = 13, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                    } or {
                        UI.Label {
                            text = totalRemain > 0 and "挑战" or "次数不足",
                            fontSize = 13, fontWeight = "bold",
                            fontColor = totalRemain > 0 and S.white or S.dim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    root:AddChild(UI.Panel {
        id = overlayId,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function() closePicker() end,
        children = {
            UI.Panel {
                width = 320,
                backgroundColor = S.cardBg,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 160, 80, 220, 80 },
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 16, paddingBottom = 16,
                flexDirection = "column",
                gap = 10,
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "选择难度", fontSize = 18, fontWeight = "bold",
                        fontColor = S.white, pointerEvents = "none",
                        alignSelf = "center",
                    },
                    UI.Label {
                        text = "剩余 " .. totalRemain .. " 次" .. (free > 0 and ("（免费 " .. free .. "）") or ("（广告 " .. ad .. "）")),
                        fontSize = 12, fontColor = totalRemain > 0 and S.green or S.red,
                        pointerEvents = "none", alignSelf = "center",
                    },
                    table.unpack(diffCards),
                },
            },
        },
    })
end

-- ============================================================================
-- 战斗逻辑
-- ============================================================================

function AbyssRift.StartBattle(UI, S, ctx, difficultyId)
    local GameUI = require("Game.GameUI")
    local BM = require("Game.BattleManager")
    local State = require("Game.State")
    local session = AbyssRiftData.CreateSession(difficultyId)
    local totalWaves = AbyssRiftData.TOTAL_WAVES

    local waves = {}
    for w = 1, totalWaves do
        local enemyDefs = AbyssRiftData.GenerateWaveEnemies(w, difficultyId)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    local diffName = AbyssRiftData.DIFFICULTY_MAP[difficultyId]
        and AbyssRiftData.DIFFICULTY_MAP[difficultyId].name or "普通"
    local label = "深渊裂隙 · " .. diffName

    GameUI.EnterDungeonBattle({
        mode = "abyss_rift",
        waves = waves,
        totalWaves = totalWaves,
        label = label,
        waveInterval = 20,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit = 60,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
        onWin = function(result)
            for w = 1, totalWaves do
                session.currentWave = w
                AbyssRiftData.CompleteWave(session)
            end
            local endResult = AbyssRiftData.EndSession(session)
            local LeaderboardData = require("Game.LeaderboardData")
            LeaderboardData.UploadAbyss(difficultyId, totalWaves)
            local rewardItems = {}
            if endResult.totalDust > 0 then
                rewardItems[#rewardItems + 1] = { icon = Currency.GetImage("rift_dust"), name = "裂隙之尘", amount = endResult.totalDust, color = { 160, 120, 200 } }
            end
            if endResult.totalSeals > 0 then
                rewardItems[#rewardItems + 1] = { icon = Currency.GetImage("rune_seal"), name = "符文封印", amount = endResult.totalSeals, color = { 40, 200, 160 } }
            end
            -- 按系列分组显示符文（每种类型单独一条）
            local runeCounts = {}
            local runeOrder = {}
            for _, rune in ipairs(endResult.runes) do
                local sid = rune.seriesId
                if not runeCounts[sid] then
                    runeCounts[sid] = 0
                    runeOrder[#runeOrder + 1] = sid
                end
                runeCounts[sid] = runeCounts[sid] + 1
            end
            for _, sid in ipairs(runeOrder) do
                local series = RuneConfig.SERIES_MAP[sid]
                if series then
                    rewardItems[#rewardItems + 1] = {
                        icon = series.icon,
                        name = series.name .. "符文",
                        amount = runeCounts[sid],
                        color = series.color or { 220, 180, 60 },
                    }
                end
            end
            local root = GameUI.GetUIRoot()
            if root then
                RewardDisplay.Show(UI, root, {
                    title = label .. " 通关",
                    rewards = rewardItems,
                    onClose = function()
                        ctx.SetView("abyss_rift_detail")
                        GameUI.ExitDungeonBattle()
                    end,
                })
            else
                GameUI.ExitDungeonBattle()
            end
        end,
        onLose = function()
            local clearedWaves = State.currentWave or 1
            for w = 1, clearedWaves do
                session.currentWave = w
                AbyssRiftData.CompleteWave(session)
            end
            local endResult = AbyssRiftData.EndSession(session)
            if clearedWaves > 0 then
                local LeaderboardData = require("Game.LeaderboardData")
                LeaderboardData.UploadAbyss(difficultyId, clearedWaves)
            end
            local rewardItems = {}
            if endResult.totalDust > 0 then
                rewardItems[#rewardItems + 1] = { icon = Currency.GetImage("rift_dust"), name = "裂隙之尘", amount = endResult.totalDust, color = { 160, 120, 200 } }
            end
            if endResult.totalSeals > 0 then
                rewardItems[#rewardItems + 1] = { icon = Currency.GetImage("rune_seal"), name = "符文封印", amount = endResult.totalSeals, color = { 40, 200, 160 } }
            end
            -- 按系列分组显示符文
            local runeCounts = {}
            local runeOrder = {}
            for _, rune in ipairs(endResult.runes) do
                local sid = rune.seriesId
                if not runeCounts[sid] then
                    runeCounts[sid] = 0
                    runeOrder[#runeOrder + 1] = sid
                end
                runeCounts[sid] = runeCounts[sid] + 1
            end
            for _, sid in ipairs(runeOrder) do
                local series = RuneConfig.SERIES_MAP[sid]
                if series then
                    rewardItems[#rewardItems + 1] = {
                        icon = series.icon,
                        name = series.name .. "符文",
                        amount = runeCounts[sid],
                        color = series.color or { 220, 180, 60 },
                    }
                end
            end
            local root = GameUI.GetUIRoot()
            if root then
                RewardDisplay.Show(UI, root, {
                    title = label .. " 失败",
                    rewards = rewardItems,
                    onClose = function()
                        ctx.SetView("abyss_rift_detail")
                        GameUI.ExitDungeonBattle()
                    end,
                })
            else
                GameUI.ExitDungeonBattle()
            end
        end,
    })
end

return AbyssRift
