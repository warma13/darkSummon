-- Game/DungeonUI/AbyssRift.lua
-- 深渊裂隙详情页 UI + 挑战逻辑

local Config = require("Game.Config")
local AbyssRiftData = require("Game.AbyssRiftDungeon")
local RuneConfig = require("Game.Config_Runes")
local Toast = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local RC = require("Game.RewardController")
local AdHelper = require("Game.AdHelper")
local Currency = require("Game.Currency")
local SweepPopup = require("Game.SweepPopup")

local AbyssRift = {}

-- ============================================================================
-- 深渊裂隙详情页
-- ============================================================================

function AbyssRift.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local free, ad = AbyssRiftData.GetRemaining()
    local ticketCount = AbyssRiftData.GetTicketCount()
    local canEnter = free > 0 or ticketCount > 0

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
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label {
                        text = "免费 " .. free,
                        fontSize = 12,
                        fontColor = free > 0 and S.green or S.dim,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "🎫 " .. ticketCount,
                        fontSize = 12,
                        fontColor = ticketCount > 0 and { 200, 180, 100 } or S.dim,
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
                    UI.Label { text = " | ", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                    UI.Label { text = "🎫 挑战券 " .. ticketCount .. " 张", fontSize = 11, fontColor = { 200, 180, 100 }, pointerEvents = "none" },
                    UI.Label { text = " | ", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                    UI.Label { text = "📺 领券 " .. ad .. "/" .. AbyssRiftData.DAILY_AD, fontSize = 11, fontColor = { 180, 160, 120 }, pointerEvents = "none" },
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

        -- 构建右侧按钮组
        local actionButtons = {}

        if free > 0 then
            -- 有免费次数：直接挑战
            actionButtons[#actionButtons + 1] = UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 180 },
                onClick = function()
                    local ok = AbyssRiftData.ConsumeEntry()
                    if ok then
                        AbyssRift.StartBattle(UI, S, ctx, diff.id)
                    end
                end,
                children = {
                    UI.Label { text = "挑战", fontSize = 13, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                },
            }
        elseif ticketCount > 0 then
            -- 有券：用券挑战
            actionButtons[#actionButtons + 1] = UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 180 },
                onClick = function()
                    if AbyssRiftData.ConsumeTicket() then
                        AbyssRift.StartBattle(UI, S, ctx, diff.id)
                    end
                end,
                children = {
                    UI.Label { text = "🎫 使用挑战券", fontSize = 12, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                },
            }
        else
            -- 无免费也无券
            actionButtons[#actionButtons + 1] = UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { 60, 50, 80, 180 },
                children = {
                    UI.Label { text = "次数不足", fontSize = 13, fontWeight = "bold", fontColor = S.dim, pointerEvents = "none" },
                },
            }
        end

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
            children = {
                UI.Panel {
                    flexDirection = "column", gap = 3,
                    flexShrink = 1,
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
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = actionButtons,
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
            -- 扫荡按钮（始终显示，不可用时点击弹提示）
            UI.Button {
                text = "扫荡",
                fontSize = 13,
                width = 70, height = 46,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    AbyssRift.OnSweep(UI, S, ctx)
                end,
            },
            ad > 0 and UI.Button {
                text = "📺 领券(" .. ad .. ")",
                fontSize = 13,
                width = 100, height = 46,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    AdHelper.ShowRewardAd(function()
                        AbyssRiftData.ConsumeAdForTicket()
                        ctx.Refresh()
                    end)
                end,
            } or nil,
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
    local ticketCount = AbyssRiftData.GetTicketCount()
    local canEnter = free > 0 or ticketCount > 0

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

        -- 构建按钮组
        local pickerButtons = {}

        if free > 0 then
            pickerButtons[#pickerButtons + 1] = UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 180 },
                onClick = function()
                    closePicker()
                    local ok = AbyssRiftData.ConsumeEntry()
                    if ok then
                        AbyssRift.StartBattle(UI, S, ctx, diff.id)
                    end
                end,
                children = {
                    UI.Label { text = "挑战", fontSize = 13, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                },
            }
        elseif ticketCount > 0 then
            pickerButtons[#pickerButtons + 1] = UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 180 },
                onClick = function()
                    closePicker()
                    if AbyssRiftData.ConsumeTicket() then
                        AbyssRift.StartBattle(UI, S, ctx, diff.id)
                    end
                end,
                children = {
                    UI.Label { text = "🎫 使用挑战券", fontSize = 12, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                },
            }
        else
            pickerButtons[#pickerButtons + 1] = UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 6,
                backgroundColor = { 60, 50, 80, 180 },
                children = {
                    UI.Label { text = "次数不足", fontSize = 13, fontWeight = "bold", fontColor = S.dim, pointerEvents = "none" },
                },
            }
        end

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
            children = {
                UI.Panel {
                    flexDirection = "column", gap = 3,
                    flexShrink = 1,
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
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = pickerButtons,
                },
            },
        }
    end

    -- 构建弹窗内容
    local pickerContent = {
        UI.Label {
            text = "选择难度", fontSize = 18, fontWeight = "bold",
            fontColor = S.white, pointerEvents = "none",
            alignSelf = "center",
        },
        UI.Label {
            text = "免费 " .. free .. "  🎫 挑战券 " .. ticketCount,
            fontSize = 12, fontColor = canEnter and S.green or S.dim,
            pointerEvents = "none", alignSelf = "center",
        },
    }
    for _, card in ipairs(diffCards) do
        pickerContent[#pickerContent + 1] = card
    end
    -- 底部领券按钮
    if ad > 0 then
        pickerContent[#pickerContent + 1] = UI.Panel {
            width = "100%",
            paddingTop = 4,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Panel {
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 8, paddingBottom = 8,
                    borderRadius = 8,
                    backgroundColor = { 120, 100, 60, 200 },
                    flexDirection = "row", alignItems = "center", gap = 6,
                    onClick = function()
                        closePicker()
                        AdHelper.ShowRewardAd(function()
                            AbyssRiftData.ConsumeAdForTicket()
                            ctx.Refresh()
                        end)
                    end,
                    children = {
                        UI.Label { text = "📺 领券(" .. ad .. "/" .. AbyssRiftData.DAILY_AD .. ")", fontSize = 13, fontWeight = "bold", fontColor = { 255, 220, 120 }, pointerEvents = "none" },
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
                children = pickerContent,
            },
        },
    })
end

-- ============================================================================
-- 战斗逻辑
-- ============================================================================

function AbyssRift.StartBattle(UI, S, ctx, difficultyId)
    local GameUI = require("Game.GameUI")
    local State = require("Game.State")

    local config, session = AbyssRiftData.BuildBattleConfig(difficultyId)
    if not config then return end

    local label = config.label
    local totalWaves = config.totalWaves

    config.onWin = function(result)
        for w = 1, totalWaves do
            session.currentWave = w
            AbyssRiftData.CompleteWave(session)
        end
        local endResult = AbyssRiftData.EndSession(session)
        local LeaderboardData = require("Game.LeaderboardData")
        LeaderboardData.UploadAbyss(difficultyId, totalWaves)
        local root = GameUI.GetUIRoot()
        if root then
            RC.ShowFromDefs(UI, root, endResult.rewardDefs, label .. " 通关", function()
                ctx.SetView("abyss_rift_detail")
                GameUI.ExitDungeonBattle()
            end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    config.onLose = function()
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
        local root = GameUI.GetUIRoot()
        if root then
            RC.ShowFromDefs(UI, root, endResult.rewardDefs, label .. " 失败", function()
                ctx.SetView("abyss_rift_detail")
                GameUI.ExitDungeonBattle()
            end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    GameUI.EnterDungeonBattle(config)
end

-- ============================================================================
-- 扫荡逻辑
-- ============================================================================

function AbyssRift.OnSweep(UI, S, ctx)
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local bestWave = AbyssRiftData.GetBestWave()
    local lastDiff = AbyssRiftData.GetLastDifficultyId()
    if bestWave <= 0 or lastDiff == "" then
        Toast.Show("请先挑战一次深渊裂隙", { 255, 200, 80 })
        return
    end

    local ticketCount = AbyssRiftData.GetTicketCount()
    if ticketCount <= 0 then
        Toast.Show("挑战券不足", { 255, 200, 80 })
        return
    end

    local diffDef = AbyssRiftData.DIFFICULTY_MAP[lastDiff]
    local diffName = diffDef and diffDef.name or lastDiff

    SweepPopup.Show(UI, root, S, {
        title = "深渊裂隙 · " .. diffName .. " 扫荡",
        maxCount = ticketCount,
        sweepLabel = "波次",
        sweepValue = bestWave .. "/" .. AbyssRiftData.TOTAL_WAVES,
        previewFn = function(count)
            -- 使用 EstimateFullClearDrops 预估单次掉落，乘以次数
            local est = AbyssRiftData.EstimateFullClearDrops(lastDiff)
            -- 按实际通关波次比例缩放（bestWave/totalWaves）
            local ratio = bestWave / AbyssRiftData.TOTAL_WAVES
            local dustPer = math.floor(est.totalDust * ratio)
            local sealsPer = est.avgSeals * ratio
            local runesPer = est.avgRunes * ratio
            local items = {}
            if dustPer > 0 then
                items[#items + 1] = {
                    icon = Currency.GetImage("rift_dust"),
                    name = "裂隙之尘",
                    amount = "~" .. (dustPer * count),
                    color = { 160, 120, 200 },
                }
            end
            if sealsPer > 0 then
                items[#items + 1] = {
                    icon = Currency.GetImage("rune_seal"),
                    name = "符文封印",
                    amount = "~" .. string.format("%.0f", sealsPer * count),
                    color = { 40, 200, 160 },
                }
            end
            if runesPer > 0 then
                items[#items + 1] = {
                    icon = "🔮",
                    name = "符文",
                    amount = "~" .. string.format("%.1f", runesPer * count),
                    color = { 220, 180, 60 },
                }
            end
            return items
        end,
        onConfirm = function(count)
            local totalDust = 0
            local totalSeals = 0
            local allRunes = {}
            local successCount = 0

            for i = 1, count do
                if AbyssRiftData.GetTicketCount() <= 0 then break end
                if not AbyssRiftData.ConsumeTicket() then break end
                local result = AbyssRiftData.ClaimReward(bestWave, lastDiff)
                totalDust = totalDust + (result.totalDust or 0)
                totalSeals = totalSeals + (result.totalSeals or 0)
                for _, rune in ipairs(result.runes or {}) do
                    allRunes[#allRunes + 1] = rune
                end
                successCount = successCount + 1
            end

            if successCount <= 0 then
                Toast.Show("扫荡失败", { 255, 100, 100 })
                return
            end

            -- 构建奖励展示
            local rewardItems = {}
            if totalDust > 0 then
                rewardItems[#rewardItems + 1] = {
                    icon = Currency.GetImage("rift_dust"),
                    name = "裂隙之尘",
                    amount = totalDust,
                    color = { 160, 120, 200 },
                }
            end
            if totalSeals > 0 then
                rewardItems[#rewardItems + 1] = {
                    icon = Currency.GetImage("rune_seal"),
                    name = "符文封印",
                    amount = totalSeals,
                    color = { 40, 200, 160 },
                }
            end
            -- 按系列分组显示符文
            local runeCounts = {}
            local runeOrder = {}
            for _, rune in ipairs(allRunes) do
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

            RewardDisplay.Show(UI, root, {
                title = "深渊裂隙扫荡 ×" .. successCount,
                rewards = rewardItems,
                onClose = function()
                    ctx.Refresh()
                end,
            })
        end,
    })
end

return AbyssRift
