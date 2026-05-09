-- Game/DungeonUI/ResourceDungeon.lua
-- 资源副本列表 + 详情页 + 挑战逻辑

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local RD = require("Game.ResourceDungeonData")
local InventoryData = require("Game.InventoryData")
local Toast = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local RC = require("Game.RewardController")
local AdHelper = require("Game.AdHelper")
local SweepPopup = require("Game.SweepPopup")
local TFData = require("Game.TranscendDungeon")
local BossSkillManager = require("Game.BossSkillManager")

local ResourceDungeon = {}

-- 严格点击判定（拖动不触发）
local _tapPressX, _tapPressY = 0, 0
local TAP_THRESHOLD = 10

-- 超越模式（锻魂熔炉）视图状态
local _transcendMode = false

-- ============================================================================
-- 二级页面：资源副本列表
-- ============================================================================

function ResourceDungeon.BuildListView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        justifyContent = "center",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Label {
                text = "资源副本",
                fontSize = 20,
                fontWeight = "bold",
                fontColor = S.white,
                textAlign = "center",
                pointerEvents = "none",
            },
        },
    })

    -- 4 种资源副本卡片
    local cards = {}
    for _, def in ipairs(RD.DUNGEON_DEFS) do
        cards[#cards + 1] = ResourceDungeon._BuildCard(UI, S, ctx, def)
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 12, paddingRight = 12,
                gap = 10,
                children = cards,
            },
        },
    })

    -- 底部返回按钮
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexShrink = 0,
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6, paddingBottom = 10,
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
        },
    })
end

--- 资源副本卡片
function ResourceDungeon._BuildCard(UI, S, ctx, def)
    local remaining = RD.GetRemainingAttempts(def.key)
    local canChallenge = remaining > 0
    local adRemaining = RD.GetAdRemaining(def.key)

    local currDef = Config.CURRENCY[def.rewardCurrency]
    local freeRem = RD.GetFreeRemaining(def.key)

    local badgeBg, badgeColor
    if canChallenge then
        badgeBg = { 80, 180, 80, 40 }
        badgeColor = S.green
    elseif adRemaining > 0 then
        badgeBg = { 220, 180, 40, 40 }
        badgeColor = S.gold
    else
        badgeBg = { 200, 60, 60, 40 }
        badgeColor = S.red
    end

    local rewardChildren = {}
    if def.rewardCurrency == "chest" then
        rewardChildren = {
            UI.Panel {
                width = 13, height = 13,
                backgroundImage = "image/tab_chest.png",
                backgroundFit = "contain",
                pointerEvents = "none",
                flexShrink = 0,
            },
            UI.Label {
                text = "宝箱", fontSize = 11,
                fontColor = S.gold, pointerEvents = "none",
            },
        }
    elseif def.rewardCurrency == "skill_book" then
        local BOOK_COLORS = {
            { 120, 200, 100 }, { 80, 140, 220 }, { 220, 80, 80 },
        }
        local BOOK_LABELS = { "初", "中", "高" }
        rewardChildren = {}
        for bi = 1, 3 do
            local bc = BOOK_COLORS[bi]
            rewardChildren[#rewardChildren + 1] = UI.Panel {
                width = 13, height = 13, borderRadius = 3,
                backgroundColor = { bc[1], bc[2], bc[3], 200 },
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none", flexShrink = 0,
                children = {
                    UI.Label { text = BOOK_LABELS[bi], fontSize = 8,
                        fontColor = {255,255,255,240}, pointerEvents = "none" },
                },
            }
        end
        rewardChildren[#rewardChildren + 1] = UI.Label {
            text = "技能书", fontSize = 11,
            fontColor = { 120, 200, 100 }, pointerEvents = "none",
        }
    elseif currDef then
        rewardChildren = {
            Currency.IconWidget(UI, def.rewardCurrency, 13),
            UI.Label {
                text = currDef.name, fontSize = 11,
                fontColor = currDef.color or S.dim, pointerEvents = "none",
            },
        }
        -- 有次要货币时额外显示
        if def.bonusCurrency then
            local bonusCd = Config.CURRENCY[def.bonusCurrency]
            if bonusCd then
                rewardChildren[#rewardChildren + 1] = UI.Label {
                    text = "+", fontSize = 10, fontColor = S.dim, pointerEvents = "none",
                }
                rewardChildren[#rewardChildren + 1] = Currency.IconWidget(UI, def.bonusCurrency, 13)
                rewardChildren[#rewardChildren + 1] = UI.Label {
                    text = bonusCd.name, fontSize = 11,
                    fontColor = bonusCd.color or S.dim, pointerEvents = "none",
                }
            end
        end
    end

    return UI.Panel {
        width = "100%",
        aspectRatio = 3,
        flexDirection = "column",
        backgroundColor = canChallenge and S.cardBg or { 25, 20, 38, 180 },
        backgroundImage = def.cover,
        backgroundFit = def.cover and "cover" or nil,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { def.accentColor[1], def.accentColor[2], def.accentColor[3], canChallenge and 120 or 60 },
        overflow = "hidden",
        onPointerDown = function(event)
            _tapPressX = event.x
            _tapPressY = event.y
        end,
        onPointerUp = function(event)
            local dx = event.x - _tapPressX
            local dy = event.y - _tapPressY
            if dx * dx + dy * dy <= TAP_THRESHOLD * TAP_THRESHOLD then
                ctx.SetView("resource_detail", def.key)
            end
        end,
        children = {
            UI.Panel {
                width = "100%",
                flex = 1,
                flexDirection = "column",
                justifyContent = "flex-start",
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 14, paddingBottom = 14,
                backgroundColor = def.cover and { 15, 12, 25, 140 } or nil,
                gap = 6,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = def.name, fontSize = 17, fontWeight = "bold",
                                fontColor = canChallenge and S.white or S.dim,
                                pointerEvents = "none",
                            },
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                borderRadius = 10,
                                backgroundColor = badgeBg,
                                children = {
                                    UI.Label {
                                        text = freeRem > 0
                                            and ("免费 " .. freeRem .. "/" .. RD.FREE_ATTEMPTS)
                                            or  (remaining > 0 and ("券" .. remaining)
                                                or (adRemaining > 0 and ("可领券" .. adRemaining) or "已用完")),
                                        fontSize = 11, fontColor = badgeColor,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    },
                    UI.Label {
                        text = def.desc, fontSize = 12, fontColor = S.dim, pointerEvents = "none",
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = rewardChildren,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 三级页面：具体副本详情
-- ============================================================================

function ResourceDungeon.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()
    local currentResourceKey = ctx.GetCurrentResourceKey()

    local def = RD.DUNGEON_MAP[currentResourceKey]
    if not def then
        ctx.SetView("resource_list")
        return
    end

    local selectedDiffEarly = RD.GetSelectedDifficulty()
    local bestWave = RD.GetBestWave(def.key, selectedDiffEarly)
    local remaining = RD.GetRemainingAttempts(def.key)
    local totalTickets, specificTickets, genericTickets = RD.GetTotalTicketCount(def.key)

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Panel { width = 12 },
            UI.Label {
                text = def.name, fontSize = 20, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
            },
            UI.Panel { flex = 1 },
            totalTickets > 0 and UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                paddingRight = 4,
                gap = 3,
                children = {
                    UI.Panel {
                        width = 14, height = 14,
                        backgroundImage = "image/item_dungeon_ticket.png",
                        backgroundFit = "contain",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = specificTickets > 0
                            and (genericTickets > 0
                                and ("专属" .. specificTickets .. " 通用" .. genericTickets)
                                or  ("专属×" .. specificTickets))
                            or  ("通用×" .. genericTickets),
                        fontSize = 10,
                        fontColor = S.gold,
                        pointerEvents = "none",
                    },
                },
            } or nil,
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

    -- 当前选中的难度
    local selectedDiff = RD.GetSelectedDifficulty()

    -- 滚动内容
    local contentChildren = {}

    if _transcendMode == def.key then
        -- 超越模式：专属内容
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildTranscendInfoCard(UI, S, ctx, def.key)
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildDifficultySelector(UI, S, ctx, selectedDiff, def)
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildTranscendWaveGrid(UI, S, ctx, def.key)
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildTranscendRewardPreview(UI, S, ctx, def.key)
    else
        -- 普通模式
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildInfoCard(UI, S, def, bestWave)
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildDifficultySelector(UI, S, ctx, selectedDiff, def)
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildWaveGrid(UI, S, ctx, def, bestWave)
        contentChildren[#contentChildren + 1] = ResourceDungeon._BuildRewardPreview(UI, S, ctx, def, selectedDiff)
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = contentChildren,
    })

    -- 底部按钮
    if _transcendMode == def.key then
        pageRoot:AddChild(ResourceDungeon._BuildTranscendChallengeButton(UI, S, ctx, def.key))
    else
        pageRoot:AddChild(ResourceDungeon._BuildChallengeButton(UI, S, ctx, def, remaining))
    end
end

--- 信息卡
function ResourceDungeon._BuildInfoCard(UI, S, def, bestWave)
    local diffLabel, diffColor
    if bestWave == 0 then
        diffLabel, diffColor = "未挑战", S.dim
    else
        diffLabel, diffColor = RD.GetWaveDifficulty(bestWave)
    end

    return UI.Panel {
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
                borderColor = { def.accentColor[1], def.accentColor[2], def.accentColor[3], 80 },
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 12, paddingBottom = 12,
                children = {
                    UI.Panel {
                        flexDirection = "column", gap = 4,
                        children = {
                            UI.Label {
                                text = def.name, fontSize = 18, fontWeight = "bold",
                                fontColor = def.accentColor, pointerEvents = "none",
                            },
                            UI.Label {
                                text = (def.totalWaves or RD.TOTAL_WAVES) .. "波 × " .. RD.ENEMIES_PER_WAVE .. "怪 · 每波末尾Boss",
                                fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column", alignItems = "flex-end", gap = 4,
                        children = {
                            UI.Label { text = "最高纪录", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                            UI.Label {
                                text = bestWave > 0 and ("第 " .. bestWave .. " 波") or "—",
                                fontSize = 16, fontWeight = "bold",
                                fontColor = bestWave > 0 and S.gold or S.dim,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 难度选择器
function ResourceDungeon._BuildDifficultySelector(UI, S, ctx, selectedDiff, def)
    local diffButtons = {}
    local diffColors = {
        [0] = { 120, 180, 120 },
        [1] = { 200, 180, 80 },
        [2] = { 220, 140, 60 },
        [3] = { 220, 60, 60 },
        [4] = { 180, 40, 180 },
    }

    for _, d in ipairs(RD.DIFFICULTY_LEVELS) do
        local isSelected = (d.level == selectedDiff)
        local isUnlocked = RD.IsDifficultyUnlocked(d.level)
        local diffLevel = d.level
        local color = diffColors[d.level] or S.dim

        local isNormalSelected = isSelected and not _transcendMode
        diffButtons[#diffButtons + 1] = UI.Panel {
            flex = 1,
            height = 40,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = isNormalSelected and { color[1], color[2], color[3], 60 } or { 30, 30, 40, 120 },
            borderRadius = 6,
            borderWidth = isNormalSelected and 2 or 1,
            borderColor = isNormalSelected and color or { 60, 60, 70, 100 },
            opacity = isUnlocked and 1.0 or 0.4,
            onClick = isUnlocked and function()
                _transcendMode = false
                RD.SetSelectedDifficulty(diffLevel)
                ctx.Refresh()
            end or function()
                local tw = (def and def.totalWaves) or RD.TOTAL_WAVES
                Toast.Show("需要先通关「" .. RD.GetDifficultyDef(diffLevel - 1).label .. "」难度全" .. tw .. "波", { 255, 200, 80 })
            end,
            children = {
                UI.Label {
                    text = d.label,
                    fontSize = 12, fontWeight = isSelected and "bold" or "normal",
                    fontColor = isSelected and color or (isUnlocked and S.white or S.dim),
                    pointerEvents = "none",
                },
                UI.Label {
                    text = isUnlocked and ("×" .. d.rewardMult .. "奖励") or "🔒",
                    fontSize = 9,
                    fontColor = isSelected and color or S.dim,
                    pointerEvents = "none",
                },
            },
        }
    end

    -- 支持超越的副本：追加"超越"选项
    if def and TFData.TRANSCEND_DEFS[def.key] then
        local tfDef = TFData.TRANSCEND_DEFS[def.key]
        local tfUnlocked = TFData.IsUnlocked()
        local tfColor = tfDef.accentColor
        local tfBest = tfUnlocked and TFData.GetBestWave(def.key) or 0
        local subText = not tfUnlocked and "未解锁"
            or (tfBest > 0 and (tfBest .. "波") or "挑战")
        local tfSelected = (_transcendMode == def.key) and tfUnlocked
        local capturedKey = def.key

        diffButtons[#diffButtons + 1] = UI.Panel {
            flex = 1,
            height = 40,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = tfSelected and { tfColor[1], tfColor[2], tfColor[3], 60 } or { 30, 30, 40, 120 },
            borderRadius = 6,
            borderWidth = tfSelected and 2 or 1,
            borderColor = tfSelected and tfColor or { 60, 60, 70, 100 },
            opacity = tfUnlocked and 1.0 or 0.4,
            onClick = function()
                if not tfUnlocked then
                    Toast.Show("主线第" .. TFData.CONFIG.unlockStage .. "关解锁超越模式", { 255, 200, 80 })
                    return
                end
                _transcendMode = capturedKey
                ctx.Refresh()
            end,
            children = {
                UI.Label {
                    text = "超越",
                    fontSize = 12, fontWeight = tfSelected and "bold" or "normal",
                    fontColor = tfUnlocked and tfColor or S.dim,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = subText,
                    fontSize = 9,
                    fontColor = tfUnlocked and tfColor or S.dim,
                    pointerEvents = "none",
                },
            },
        }
    end

    -- 描述文本
    local descText
    if def and _transcendMode == def.key then
        local tfDef = TFData.TRANSCEND_DEFS[def.key]
        local tfBest = TFData.GetBestWave(def.key)
        descText = (tfDef and tfDef.name or "超越") .. " · 20波 × 20怪 · 难度随主线递增"
            .. (tfBest > 0 and ("  最高第" .. tfBest .. "波") or "")
    else
        local diff = RD.GetDifficultyDef(selectedDiff)
        if selectedDiff == 0 then
            descText = "原始难度，适合入门挑战"
        else
            local multStr
            if diff.statMult >= 10000 then
                multStr = string.format("%.0f万", diff.statMult / 10000)
            else
                multStr = tostring(diff.statMult)
            end
            descText = "怪物血量/防御×" .. multStr .. "  奖励×" .. diff.rewardMult
        end
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = S.cardBg,
                borderRadius = 8,
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 8, paddingBottom = 8,
                flexDirection = "column",
                gap = 6,
                children = {
                    UI.Label {
                        text = "难度选择", fontSize = 13, fontWeight = "bold",
                        fontColor = S.white, pointerEvents = "none",
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 6,
                        children = diffButtons,
                    },
                    UI.Label {
                        text = descText,
                        fontSize = 10, fontColor = S.dim, pointerEvents = "none",
                    },
                },
            },
        },
    }
end

--- 波次网格
function ResourceDungeon._BuildWaveGrid(UI, S, ctx, def, bestWave)
    local totalW = def.totalWaves or RD.TOTAL_WAVES
    local cols = 5
    local numRows = math.ceil(totalW / cols)
    local rows = {}
    for row = 1, numRows do
        local cells = {}
        for col = 1, cols do
            local wave = (row - 1) * cols + col
            if wave > totalW then break end
            cells[#cells + 1] = ResourceDungeon._BuildWaveCell(UI, S, ctx, def, wave, bestWave)
        end
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 5,
            children = cells,
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexDirection = "column",
        gap = 5,
        flexShrink = 0,
        children = rows,
    }
end

--- 单个波次格子
function ResourceDungeon._BuildWaveCell(UI, S, ctx, def, wave, bestWave)
    local isCleared = wave <= bestWave
    local isNext = wave == bestWave + 1
    local isBossWave = (wave % 5 == 0)

    local bg, border, textColor
    if isCleared then
        bg = S.clearedBg
        border = S.clearedBorder
        textColor = S.green
    elseif isNext then
        bg = { def.accentColor[1], def.accentColor[2], def.accentColor[3], 80 }
        border = def.accentColor
        textColor = S.white
    else
        bg = S.lockedBg
        border = S.lockedBorder
        textColor = S.dim
    end

    local reward = RD.GetWaveReward(def.key, wave)
    local rewardText = ""
    ---@type table|nil
    local chestReward = nil
    ---@type string|nil
    local chestImage = nil
    ---@type table|nil
    local skillBookReward = nil
    if def.rewardCurrency == "chest" then
        chestReward = RD.GetChestWaveReward(wave)
        if chestReward then
            local ct = Config.CHEST_TYPES_MAP[chestReward.id]
            chestImage = ct and ct.image
        end
    elseif def.rewardCurrency == "skill_book" then
        skillBookReward = RD.GetSkillBookWaveReward(wave)
    elseif reward > 0 then
        rewardText = "+" .. ctx.FormatNum(reward)
    end

    local bottomChild
    if isCleared then
        bottomChild = UI.Label {
            text = "✓", fontSize = 9,
            fontColor = S.green, pointerEvents = "none",
        }
    elseif chestReward and chestImage then
        local countLabel = chestReward.count > 1 and ("×" .. chestReward.count) or nil
        bottomChild = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 1,
            children = {
                UI.Panel {
                    width = 16, height = 16,
                    backgroundImage = chestImage,
                    backgroundScaleMode = "aspectFit",
                },
                countLabel and UI.Label {
                    text = countLabel, fontSize = 8,
                    fontColor = S.gold, pointerEvents = "none",
                } or nil,
            },
        }
    elseif skillBookReward and skillBookReward.count > 0 then
        local sbCd = Config.CURRENCY[skillBookReward.id]
        local sbColor = sbCd and sbCd.color or {180,180,180}
        bottomChild = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 1,
            children = {
                UI.Panel {
                    width = 16, height = 16, borderRadius = 4,
                    backgroundColor = { sbColor[1], sbColor[2], sbColor[3], 200 },
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = sbCd and sbCd.name and sbCd.name:sub(1,3) or "书",
                            fontSize = 7, fontColor = {255,255,255,240}, pointerEvents = "none" },
                    },
                },
                UI.Label {
                    text = "+" .. skillBookReward.count, fontSize = 8,
                    fontColor = def.accentColor, pointerEvents = "none",
                },
            },
        }
    elseif def.key == "temper" and isBossWave then
        -- 淬魂试炼 Boss 波：显示主奖励 + 封魂玉
        local bonusR = RD.GetTemperBonusReward(wave)
        local bonusCd = bonusR and Config.CURRENCY[bonusR.id]
        bottomChild = UI.Panel {
            flexDirection = "column", alignItems = "center", gap = 0,
            children = {
                UI.Label {
                    text = rewardText, fontSize = 8,
                    fontColor = def.accentColor, pointerEvents = "none",
                },
                bonusR and UI.Label {
                    text = (bonusCd and bonusCd.emoji or "🌈") .. "×" .. bonusR.count,
                    fontSize = 8,
                    fontColor = bonusCd and bonusCd.color or { 180, 120, 255 },
                    pointerEvents = "none",
                } or nil,
            },
        }
    else
        bottomChild = UI.Label {
            text = rewardText, fontSize = 9,
            fontColor = def.rewardCurrency == "chest" and S.gold or def.accentColor,
            pointerEvents = "none",
        }
    end

    return UI.Panel {
        flex = 1,
        height = 52,
        maxWidth = 62,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = bg,
        borderRadius = 6,
        borderWidth = isNext and 2 or 1,
        borderColor = border,
        gap = 1,
        children = {
            UI.Label {
                text = isBossWave and ("W" .. wave .. "★") or ("W" .. wave),
                fontSize = isBossWave and 10 or 11,
                fontWeight = (isNext or isBossWave) and "bold" or "normal",
                fontColor = textColor,
                pointerEvents = "none",
            },
            bottomChild,
        },
    }
end

--- 奖励预览
function ResourceDungeon._BuildRewardPreview(UI, S, ctx, def, selectedDiff)
    selectedDiff = selectedDiff or 0
    local diffDef = RD.GetDifficultyDef(selectedDiff)
    local totalW = def.totalWaves or RD.TOTAL_WAVES
    local milestones
    if totalW <= 10 then
        milestones = { 3, 5, 7, 10 }
    else
        milestones = { 5, 10, 15, 20 }
    end
    local items = {}

    for _, w in ipairs(milestones) do
        local reward = RD.GetWaveReward(def.key, w, selectedDiff)
        local diffLabel, diffColor = RD.GetWaveDifficulty(w)
        local rewardText = ""
        local rewardImage = nil
        if def.rewardCurrency == "chest" then
            local cr = RD.GetChestWaveReward(w)
            if cr then
                local ct = Config.CHEST_TYPES_MAP[cr.id]
                local count = cr.count * diffDef.rewardMult
                rewardText = (ct and ct.name or cr.id) .. " ×" .. count
                rewardImage = ct and ct.image
            end
        elseif def.rewardCurrency == "skill_book" then
            local sbr = RD.GetSkillBookWaveReward(w)
            if sbr and sbr.count > 0 then
                local cd = Config.CURRENCY[sbr.id]
                local count = sbr.count * diffDef.rewardMult
                rewardText = (cd and cd.name or sbr.id) .. " ×" .. count
                rewardImage = cd and cd.image
            end
        else
            local currDef = Config.CURRENCY[def.rewardCurrency]
            local name = currDef and currDef.name or def.rewardCurrency
            rewardText = name .. " +" .. ctx.FormatNum(reward)
            -- 淬魂试炼 Boss 波额外显示封魂玉
            if def.key == "temper" then
                local bonusAmt = RD.GetTemperBonusWaveReward(w, selectedDiff)
                if bonusAmt > 0 then
                    local bonusCd = Config.CURRENCY["rainbow_jade"]
                    local bonusName = bonusCd and bonusCd.name or "封魂玉"
                    rewardText = rewardText .. "  " .. bonusName .. " ×" .. bonusAmt
                end
            end
        end

        items[#items + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 4, paddingBottom = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label {
                            text = "第" .. w .. "波", fontSize = 12,
                            fontWeight = "bold", fontColor = S.white, pointerEvents = "none",
                        },
                        UI.Panel {
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 50 },
                            children = {
                                UI.Label {
                                    text = diffLabel, fontSize = 9,
                                    fontColor = diffColor, pointerEvents = "none",
                                },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        rewardImage and UI.Panel {
                            width = 18, height = 18,
                            backgroundImage = rewardImage,
                            backgroundScaleMode = "aspectFit",
                        } or nil,
                        UI.Label {
                            text = rewardText, fontSize = 11,
                            fontColor = def.accentColor, pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    -- 总计
    local totalRewards = RD.CalcTotalRewards(def.key, totalW, selectedDiff)
    local totalText
    if def.rewardCurrency == "chest" then
        local c = totalRewards.chests or {}
        local parts = {}
        for _, ctDef in ipairs(Config.CHEST_TYPES) do
            if c[ctDef.id] and c[ctDef.id] > 0 then
                parts[#parts + 1] = ctDef.name .. "×" .. c[ctDef.id]
            end
        end
        totalText = table.concat(parts, " ")
    elseif def.rewardCurrency == "skill_book" then
        local sb = totalRewards.skill_books or {}
        local SB_ORD = { "skill_book_1", "skill_book_2", "skill_book_3" }
        totalText = nil  -- 使用图片面板代替文本
        ---@type table
        totalBookChildren = {}
        for _, bid in ipairs(SB_ORD) do
            if sb[bid] and sb[bid] > 0 then
                local cd = Config.CURRENCY[bid]
                totalBookChildren[#totalBookChildren + 1] = UI.Panel {
                    width = 14, height = 14,
                    backgroundImage = cd and cd.image or ("image/currency_" .. bid .. ".png"),
                    backgroundScaleMode = "aspectFit",
                }
                totalBookChildren[#totalBookChildren + 1] = UI.Label {
                    text = tostring(sb[bid]), fontSize = 11,
                    fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
                    marginRight = 4,
                }
            end
        end
    else
        local total = totalRewards[def.rewardCurrency] or 0
        local currDef = Config.CURRENCY[def.rewardCurrency]
        totalText = (currDef and currDef.name or "") .. " " .. ctx.FormatNum(total)
        -- 淬魂试炼额外显示封魂玉总计
        if def.key == "temper" and totalRewards["rainbow_jade"] and totalRewards["rainbow_jade"] > 0 then
            local bonusCd = Config.CURRENCY["rainbow_jade"]
            local bonusName = bonusCd and bonusCd.name or "封魂玉"
            totalText = totalText .. "  " .. bonusName .. " ×" .. totalRewards["rainbow_jade"]
        end
    end

    items[#items + 1] = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 100, 70, 160, 60 },
        marginTop = 2,
    }
    items[#items + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingTop = 4,
        children = {
            UI.Label {
                text = "全通关总计", fontSize = 12,
                fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
            },
            totalText and UI.Label {
                text = totalText, fontSize = 12,
                fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
            } or UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                children = totalBookChildren,
            },
        },
    }

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 8,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = S.cardBg,
                borderRadius = 8,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 8, paddingBottom = 8,
                flexDirection = "column",
                children = items,
            },
        },
    }
end

--- 底部按钮
function ResourceDungeon._BuildChallengeButton(UI, S, ctx, def, remaining)
    local freeRemaining = RD.GetFreeRemaining(def.key)
    local adRemaining   = RD.GetAdRemaining(def.key)
    local totalTickets  = RD.GetTotalTicketCount(def.key)

    local actionChildren = {
        UI.Button {
            text = "返回",
            fontSize = 14,
            width = 70, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                ctx.SetView("resource_list")
            end,
        },
    }

    -- 挑战按钮：免费 → 券 → 已用完
    if freeRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "免费挑战 " .. def.name,
            fontSize = 15,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                ResourceDungeon.OnChallenge(UI, S, ctx, def.key, false)
            end,
        }
    elseif totalTickets > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "使用挑战券 (余" .. totalTickets .. "张)",
            fontSize = 14,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                ResourceDungeon.OnChallenge(UI, S, ctx, def.key, true)
            end,
        }
    else
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "次数已用完",
            fontSize = 13,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "outline",
        }
    end

    -- 扫荡按钮（始终显示，不可用时点击弹提示）
    actionChildren[#actionChildren + 1] = UI.Button {
        text = "🔄 扫荡",
        fontSize = 13,
        width = 80, height = 46,
        borderRadius = 8,
        variant = "outline",
        onClick = function()
            ResourceDungeon.OnSweep(UI, S, ctx, def)
        end,
    }

    -- 看广告得券按钮（右侧）
    if adRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "📺 得券(" .. adRemaining .. ")",
            fontSize = 12,
            width = 90, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                ResourceDungeon.OnAdGetTicket(UI, S, ctx, def.key)
            end,
        }
    else
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "📺 已领完",
            fontSize = 12,
            width = 90, height = 46,
            borderRadius = 8,
            variant = "outline",
            fontColor = S.dim,
        }
    end

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

--- 看广告获得专属副本挑战券
function ResourceDungeon.OnAdGetTicket(UI, S, ctx, dungeonKey)
    local def = RD.DUNGEON_MAP[dungeonKey]
    if not def then return end

    if RD.GetAdRemaining(dungeonKey) <= 0 then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return
    end

    AdHelper.ShowRewardAd(function()
        if not RD.ConsumeAdAttempt(dungeonKey) then return end
        local ticketId = RD.DUNGEON_TICKET_MAP[dungeonKey]
        if ticketId then
            InventoryData.Add(ticketId, 1)
            local ticketDef = InventoryData.ITEM_DEFS[ticketId]
            local ticketName = ticketDef and ticketDef.name or "挑战券"
            Toast.Show("获得 " .. ticketName .. " ×1", { 80, 220, 120 })
        end
        -- 刷新当前页面
        ctx.SetView("resource_detail", dungeonKey)
    end)
end

function ResourceDungeon.OnChallenge(UI, S, ctx, dungeonKey, useTicket, skipConsume)
    local def = RD.DUNGEON_MAP[dungeonKey]
    if not def then return end

    if #HeroData.GetDeployedList() < Config.MAX_DEPLOYED then
        Toast.Show("需要上阵" .. Config.MAX_DEPLOYED .. "名英雄才能挑战", S.red)
        return
    end

    if not skipConsume then
        if useTicket then
            if not RD.ConsumeDungeonTicket(dungeonKey) then return end
        else
            if not RD.ConsumeAttempt(dungeonKey) then return end
        end
    end

    local GameUI = require("Game.GameUI")

    local diffLevel = RD.GetSelectedDifficulty()
    local config = RD.BuildBattleConfig(dungeonKey, diffLevel)
    if not config then return end

    local label = config.label
    local totalWaves = config.totalWaves

    -- Boss 技能（通用技能，根据难度等级缩放）
    local bossMode = dungeonKey == "temper" and "temper_trial" or "resource_dungeon"
    config.onStart = function()
        BossSkillManager.InitGeneric(bossMode, diffLevel)
    end
    config.onUpdate = function(dt)
        BossSkillManager.Update(dt)
    end

    config.onWin = function(result)
        local rewards = RD.ClaimReward(dungeonKey, totalWaves, diffLevel)
        local defs = rewards and rewards.rewardDefs or {}
        if #defs > 0 then
            local root = GameUI.GetUIRoot()
            if root then
                RC.ShowFromDefs(UI, root, defs, label .. " 全部通关!", function()
                    GameUI.ExitDungeonBattle()
                end)
                return
            end
        end
        GameUI.ExitDungeonBattle()
    end

    config.onExit = function(result, continueExit)
        local clearedWave = math.max(0, result.wave - 1)
        if clearedWave > 0 then
            local rewards = RD.ClaimReward(dungeonKey, clearedWave, diffLevel)
            local defs = rewards and rewards.rewardDefs or {}
            if #defs > 0 then
                local root = GameUI.GetUIRoot()
                if root then
                    RC.ShowFromDefs(UI, root, defs, label .. " 提前退出 (第" .. clearedWave .. "波)", continueExit)
                    return
                end
            end
        else
            Toast.Show(label .. " 提前退出，无奖励", S.red)
        end
        continueExit()
    end

    config.onLose = function(result)
        local clearedWave = math.max(0, result.wave - 1)
        if clearedWave > 0 then
            local rewards = RD.ClaimReward(dungeonKey, clearedWave, diffLevel)
            local defs = rewards and rewards.rewardDefs or {}
            if #defs > 0 then
                local root = GameUI.GetUIRoot()
                if root then
                    RC.ShowFromDefs(UI, root, defs, label .. " 第" .. clearedWave .. "波失败", function()
                        GameUI.ExitDungeonBattle()
                    end)
                    return
                end
            end
        else
            Toast.Show(label .. " 挑战失败", S.red)
        end
        GameUI.ExitDungeonBattle()
    end

    GameUI.EnterDungeonBattle(config)
end

-- ============================================================================
-- 扫荡逻辑
-- ============================================================================

function ResourceDungeon.OnSweep(UI, S, ctx, def)
    local diffLevel = RD.GetSelectedDifficulty()
    local diffDef = RD.GetDifficultyDef(diffLevel)
    local diffSuffix = diffLevel > 0 and (" [" .. diffDef.label .. "]") or ""

    local bestWave = RD.GetBestWave(def.key, diffLevel)
    if bestWave <= 0 then
        Toast.Show("当前难度下需要先挑战一次才能扫荡", { 255, 200, 80 })
        return
    end

    local freeLeft = RD.GetFreeRemaining(def.key)
    local totalTickets = RD.GetTotalTicketCount(def.key)
    local totalAvailable = freeLeft + totalTickets
    if totalAvailable <= 0 then
        Toast.Show("次数不足（无免费次数或挑战券）", { 255, 200, 80 })
        return
    end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local capturedFreeLeft = freeLeft
    SweepPopup.Show(UI, root, S, {
        title = def.name .. diffSuffix .. " · 连续扫荡",
        maxCount = totalAvailable,
        sweepLabel = "最高纪录",
        sweepValue = "第 " .. bestWave .. " 波" .. (diffLevel > 0 and ("  奖励×" .. diffDef.rewardMult) or ""),
        costFn = function(count)
            local free = math.min(count, capturedFreeLeft)
            local ticket = count - free
            if free > 0 and ticket > 0 then
                return "免费 " .. free .. " 次 + 挑战券 " .. ticket .. " 张"
            elseif free > 0 then
                return "免费 " .. free .. " 次（不消耗挑战券）"
            else
                return "消耗 " .. ticket .. " 张挑战券"
            end
        end,
        previewFn = function(count)
            local rewards = RD.CalcTotalRewards(def.key, bestWave, diffLevel)
            local items = {}
            if def.rewardCurrency == "chest" then
                local chests = rewards.chests or {}
                for _, ctDef in ipairs(Config.CHEST_TYPES) do
                    if chests[ctDef.id] and chests[ctDef.id] > 0 then
                        items[#items + 1] = {
                            icon = ctDef.image or "📦",
                            name = ctDef.name,
                            amount = chests[ctDef.id] * count,
                            color = S.gold,
                        }
                    end
                end
            elseif def.rewardCurrency == "skill_book" then
                local sb = rewards.skill_books or {}
                local SB_ORD = { "skill_book_1", "skill_book_2", "skill_book_3" }
                for _, bid in ipairs(SB_ORD) do
                    if sb[bid] and sb[bid] > 0 then
                        local cd = Config.CURRENCY[bid]
                        items[#items + 1] = {
                            icon = cd and cd.image or "📕",
                            name = cd and cd.name or bid,
                            amount = sb[bid] * count,
                            color = cd and cd.color or def.accentColor,
                        }
                    end
                end
            else
                -- 遍历所有货币（含淬魂试炼的 rainbow_jade 等额外掉落）
                for currId, amount in pairs(rewards) do
                    if amount > 0 then
                        local currDef = Config.CURRENCY[currId]
                        items[#items + 1] = {
                            icon = currDef and currDef.image or "💰",
                            name = currDef and currDef.name or currId,
                            amount = amount * count,
                            color = currDef and currDef.color or def.accentColor,
                        }
                    end
                end
            end
            return items
        end,
        onConfirm = function(count)
            -- 执行扫荡：优先消耗免费次数，再消耗挑战券
            local successCount = 0

            for i = 1, count do
                local curFree = RD.GetFreeRemaining(def.key)
                if curFree > 0 then
                    if not RD.ConsumeAttempt(def.key) then break end
                else
                    if not RD.ConsumeDungeonTicket(def.key) then
                        Toast.Show("挑战券不足，已扫荡 " .. successCount .. " 次", { 255, 200, 80 })
                        break
                    end
                end
                local rewards = RD.ClaimReward(def.key, bestWave, diffLevel)
                successCount = successCount + 1
            end

            -- 汇总显示奖励（只需展示总计）
            if successCount > 0 then
                local totalRewards = RD.CalcTotalRewards(def.key, bestWave, diffLevel)
                local rewardItems = {}
                if def.rewardCurrency == "chest" then
                    local chests = totalRewards.chests or {}
                    for _, ctDef in ipairs(Config.CHEST_TYPES) do
                        if chests[ctDef.id] and chests[ctDef.id] > 0 then
                            rewardItems[#rewardItems + 1] = {
                                icon = ctDef.image or "📦",
                                name = ctDef.name,
                                amount = chests[ctDef.id] * successCount,
                                borderColor = ctDef.borderColor or nil,
                            }
                        end
                    end
                elseif def.rewardCurrency == "skill_book" then
                    local sb = totalRewards.skill_books or {}
                    local SB_ORD = { "skill_book_1", "skill_book_2", "skill_book_3" }
                    for _, bid in ipairs(SB_ORD) do
                        if sb[bid] and sb[bid] > 0 then
                            local cd = Config.CURRENCY[bid]
                            rewardItems[#rewardItems + 1] = {
                                icon = cd and cd.image or "📕",
                                name = cd and cd.name or bid,
                                amount = sb[bid] * successCount,
                                color = cd and cd.color or nil,
                            }
                        end
                    end
                else
                    -- 遍历所有货币（含淬魂试炼的 rainbow_jade 等额外掉落）
                    for currId, amount in pairs(totalRewards) do
                        amount = amount * successCount
                        if amount > 0 then
                            local currDef = Config.CURRENCY[currId]
                            rewardItems[#rewardItems + 1] = {
                                icon = currDef and currDef.image or "💰",
                                name = currDef and currDef.name or currId,
                                amount = amount,
                            }
                        end
                    end
                end

                if #rewardItems > 0 then
                    RewardDisplay.Show(UI, root, {
                        title = def.name .. diffSuffix .. " 扫荡 ×" .. successCount .. " 完成！",
                        rewards = rewardItems,
                        onClose = function()
                            ctx.SetView("resource_detail", def.key)
                        end,
                    })
                else
                    Toast.Show("扫荡完成 ×" .. successCount, S.green)
                    ctx.SetView("resource_detail", def.key)
                end
            end
        end,
    })
end

-- ============================================================================
-- 超越模式专属 UI
-- ============================================================================

--- 超越模式信息卡（次数共用对应副本，标题栏已显示剩余次数）
function ResourceDungeon._BuildTranscendInfoCard(UI, S, ctx, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local tfDef = TFData.TRANSCEND_DEFS[dungeonKey]
    local tfBest = TFData.GetBestWave(dungeonKey)
    local acColor = tfDef.accentColor
    local rewardCurrDef = Config.CURRENCY[tfDef.rewardCurrency]
    local rewardName = rewardCurrDef and rewardCurrDef.name or tfDef.rewardCurrency

    return UI.Panel {
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
                borderColor = { acColor[1], acColor[2], acColor[3], 80 },
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 12, paddingBottom = 12,
                children = {
                    UI.Panel {
                        flexDirection = "column", gap = 4,
                        children = {
                            UI.Label {
                                text = tfDef.name, fontSize = 18, fontWeight = "bold",
                                fontColor = acColor, pointerEvents = "none",
                            },
                            UI.Label {
                                text = "20波 × 20怪 · 每5波Boss · 掉落" .. rewardName,
                                fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column", alignItems = "flex-end", gap = 4,
                        children = (function()
                            local needsRC = TFData.NeedsRechallenge(dungeonKey)
                            local items = {
                                UI.Label { text = "最高纪录", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                                UI.Label {
                                    text = tfBest > 0 and ("第 " .. tfBest .. " 波") or "—",
                                    fontSize = 16, fontWeight = "bold",
                                    fontColor = tfBest > 0 and (needsRC and S.dim or S.gold) or S.dim,
                                    pointerEvents = "none",
                                },
                            }
                            if needsRC then
                                items[#items + 1] = UI.Label {
                                    text = "记录已过期", fontSize = 10,
                                    fontColor = { 255, 120, 80 }, pointerEvents = "none",
                                }
                            end
                            return items
                        end)(),
                    },
                },
            },
        },
    }
end

--- 超越模式 20 波网格（4行×5列）
function ResourceDungeon._BuildTranscendWaveGrid(UI, S, ctx, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local tfDef = TFData.TRANSCEND_DEFS[dungeonKey]
    local tfBest = TFData.GetBestWave(dungeonKey)
    local acColor = tfDef.accentColor
    local isChest = tfDef.rewardCurrency == "chest"
    local rows = {}
    for row = 1, 4 do
        local cells = {}
        for col = 1, 5 do
            local wave = (row - 1) * 5 + col
            local isCleared = wave <= tfBest
            local isNext = wave == tfBest + 1
            local isBoss = (wave % TFData.CONFIG.bossInterval == 0)
            local wLabel, wColor = TFData.GetWaveLabel(wave)

            local bg, border, textColor
            if isCleared then
                bg = S.clearedBg or { 40, 80, 40, 120 }
                border = S.clearedBorder or { 60, 140, 60, 160 }
                textColor = S.green
            elseif isNext then
                bg = { acColor[1], acColor[2], acColor[3], 80 }
                border = acColor
                textColor = S.white
            else
                bg = S.lockedBg or { 30, 30, 40, 120 }
                border = S.lockedBorder or { 50, 50, 60, 100 }
                textColor = S.dim
            end

            -- 波次奖励显示
            local bottomChild
            if isCleared then
                bottomChild = UI.Label {
                    text = "✓", fontSize = 9,
                    fontColor = S.green, pointerEvents = "none",
                }
            elseif isChest then
                local cr = TFData.GetTranscendChestWaveReward(wave)
                if cr then
                    local ct = Config.CHEST_TYPES_MAP and Config.CHEST_TYPES_MAP[cr.id]
                    local chestImage = ct and ct.image
                    local countLabel = cr.count > 1 and ("×" .. cr.count) or nil
                    bottomChild = UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 1,
                        children = {
                            chestImage and UI.Panel {
                                width = 16, height = 16,
                                backgroundImage = chestImage,
                                backgroundScaleMode = "aspectFit",
                            } or UI.Label {
                                text = "📦", fontSize = 9, pointerEvents = "none",
                            },
                            countLabel and UI.Label {
                                text = countLabel, fontSize = 8,
                                fontColor = S.gold, pointerEvents = "none",
                            } or nil,
                        },
                    }
                else
                    bottomChild = UI.Label {
                        text = "—", fontSize = 8,
                        fontColor = S.dim, pointerEvents = "none",
                    }
                end
            else
                local reward = TFData.CalcWaveReward(wave, nil, dungeonKey)
                bottomChild = UI.Label {
                    text = "+" .. ctx.FormatNum(reward), fontSize = 8,
                    fontColor = isBoss and S.gold or acColor,
                    pointerEvents = "none",
                }
            end

            cells[#cells + 1] = UI.Panel {
                flex = 1,
                height = 52,
                maxWidth = 62,
                flexDirection = "column",
                alignItems = "center",
                justifyContent = "center",
                backgroundColor = bg,
                borderRadius = 6,
                borderWidth = isNext and 2 or 1,
                borderColor = border,
                gap = 1,
                children = {
                    UI.Label {
                        text = isBoss and ("W" .. wave .. "★") or ("W" .. wave),
                        fontSize = isBoss and 10 or 11,
                        fontWeight = (isNext or isBoss) and "bold" or "normal",
                        fontColor = textColor,
                        pointerEvents = "none",
                    },
                    bottomChild,
                },
            }
        end
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 5,
            children = cells,
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexDirection = "column",
        gap = 5,
        flexShrink = 0,
        children = rows,
    }
end

--- 超越模式里程碑奖励预览
function ResourceDungeon._BuildTranscendRewardPreview(UI, S, ctx, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local tfDef = TFData.TRANSCEND_DEFS[dungeonKey]
    local acColor = tfDef.accentColor
    local isChest = tfDef.rewardCurrency == "chest"
    local milestones = { 5, 10, 15, 20 }
    local items = {}
    local rewardCurrDef = Config.CURRENCY[tfDef.rewardCurrency]
    local rewardName = rewardCurrDef and rewardCurrDef.name or tfDef.rewardCurrency

    for _, w in ipairs(milestones) do
        local wLabel, wColor = TFData.GetWaveLabel(w)

        -- 右侧奖励显示
        local rewardChildren = {}
        if isChest then
            local chests = TFData.EstimateTotalChestReward(w)
            for _, ctDef in ipairs(Config.CHEST_TYPES) do
                if chests[ctDef.id] and chests[ctDef.id] > 0 then
                    rewardChildren[#rewardChildren + 1] = UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 2,
                        children = {
                            ctDef.image and UI.Panel {
                                width = 16, height = 16,
                                backgroundImage = ctDef.image,
                                backgroundScaleMode = "aspectFit",
                            } or nil,
                            UI.Label {
                                text = ctDef.name .. "×" .. chests[ctDef.id], fontSize = 10,
                                fontColor = S.gold, pointerEvents = "none",
                            },
                        },
                    }
                end
            end
        else
            local totalReward = TFData.EstimateTotalReward(w, nil, dungeonKey)
            if rewardCurrDef and rewardCurrDef.image then
                rewardChildren[#rewardChildren + 1] = UI.Panel {
                    width = 18, height = 18,
                    backgroundImage = rewardCurrDef.image,
                    backgroundScaleMode = "aspectFit",
                }
            end
            rewardChildren[#rewardChildren + 1] = UI.Label {
                text = rewardName .. " +" .. ctx.FormatNum(totalReward), fontSize = 11,
                fontColor = acColor, pointerEvents = "none",
            }
        end

        items[#items + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 4, paddingBottom = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label {
                            text = "第" .. w .. "波", fontSize = 12,
                            fontWeight = "bold", fontColor = S.white, pointerEvents = "none",
                        },
                        UI.Panel {
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { wColor[1], wColor[2], wColor[3], 50 },
                            children = {
                                UI.Label {
                                    text = wLabel, fontSize = 9,
                                    fontColor = wColor, pointerEvents = "none",
                                },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = rewardChildren,
                },
            },
        }
    end

    -- 总计
    local totalSummaryChild
    if isChest then
        local chests = TFData.EstimateTotalChestReward(20)
        local parts = {}
        for _, ctDef in ipairs(Config.CHEST_TYPES) do
            if chests[ctDef.id] and chests[ctDef.id] > 0 then
                parts[#parts + 1] = ctDef.name .. "×" .. chests[ctDef.id]
            end
        end
        totalSummaryChild = UI.Label {
            text = table.concat(parts, " "), fontSize = 12,
            fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
        }
    else
        local totalAll = TFData.EstimateTotalReward(20, nil, dungeonKey)
        totalSummaryChild = UI.Label {
            text = rewardName .. " " .. ctx.FormatNum(totalAll), fontSize = 12,
            fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
        }
    end

    items[#items + 1] = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { acColor[1], acColor[2], acColor[3], 60 },
        marginTop = 2,
    }
    items[#items + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingTop = 4,
        children = {
            UI.Label {
                text = "全通关总计", fontSize = 12,
                fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
            },
            totalSummaryChild,
        },
    }

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 8,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = S.cardBg,
                borderRadius = 8,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 8, paddingBottom = 8,
                flexDirection = "column",
                children = items,
            },
        },
    }
end

--- 超越模式底部按钮（次数/券共用对应副本）
function ResourceDungeon._BuildTranscendChallengeButton(UI, S, ctx, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local tfDef = TFData.TRANSCEND_DEFS[dungeonKey]
    local freeRemaining = RD.GetFreeRemaining(dungeonKey)
    local adRemaining   = RD.GetAdRemaining(dungeonKey)
    local totalTickets  = RD.GetTotalTicketCount(dungeonKey)
    local shortName = tfDef and tfDef.name or "超越"

    local actionChildren = {
        UI.Button {
            text = "返回",
            fontSize = 14,
            width = 70, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                ctx.SetView("resource_list")
            end,
        },
    }

    -- 挑战按钮：免费 → 券 → 已用完
    if freeRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "免费挑战",
            fontSize = 14,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                ResourceDungeon.OnTranscendChallenge(UI, S, ctx, dungeonKey)
            end,
        }
    elseif totalTickets > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "使用挑战券 (余" .. totalTickets .. "张)",
            fontSize = 14,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                ResourceDungeon.OnTranscendChallenge(UI, S, ctx, dungeonKey)
            end,
        }
    else
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "次数已用完",
            fontSize = 13,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "outline",
        }
    end

    -- 扫荡按钮
    actionChildren[#actionChildren + 1] = UI.Button {
        text = "扫荡",
        fontSize = 13,
        width = 80, height = 46,
        borderRadius = 8,
        variant = "outline",
        onClick = function()
            ResourceDungeon.OnTranscendSweep(UI, S, ctx, dungeonKey)
        end,
    }

    -- 看广告得券（共用对应副本）
    if adRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "得券(" .. adRemaining .. ")",
            fontSize = 12,
            width = 80, height = 46,
            borderRadius = 8,
            variant = "outline",
            onClick = function()
                ResourceDungeon.OnAdGetTicket(UI, S, ctx, dungeonKey)
            end,
        }
    else
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "已领完",
            fontSize = 12,
            width = 80, height = 46,
            borderRadius = 8,
            variant = "outline",
            fontColor = S.dim,
        }
    end

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
-- 超越模式扫荡逻辑
-- ============================================================================

function ResourceDungeon.OnTranscendSweep(UI, S, ctx, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local tfDef = TFData.TRANSCEND_DEFS[dungeonKey]
    local tfBest = TFData.GetBestWave(dungeonKey)
    local isChest = tfDef.rewardCurrency == "chest"
    if tfBest <= 0 then
        Toast.Show("需要先挑战一次才能扫荡", { 255, 200, 80 })
        return
    end

    -- 关卡提高过多，扫荡记录已过时，需重新挑战
    local needsRC, stageGap = TFData.NeedsRechallenge(dungeonKey)
    if needsRC then
        Toast.Show("关卡已提高" .. stageGap .. "关，需重新挑战更新记录", { 255, 200, 80 })
        return
    end

    local freeLeft = RD.GetFreeRemaining(dungeonKey)
    local totalTickets = RD.GetTotalTicketCount(dungeonKey)
    local totalAvailable = freeLeft + totalTickets
    if totalAvailable <= 0 then
        Toast.Show("次数不足（无免费次数或挑战券）", { 255, 200, 80 })
        return
    end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local rewardCurrDef = Config.CURRENCY[tfDef.rewardCurrency]
    local rewardName = rewardCurrDef and rewardCurrDef.name or tfDef.rewardCurrency
    local rewardImage = rewardCurrDef and rewardCurrDef.image

    local capturedFreeLeft = freeLeft
    SweepPopup.Show(UI, root, S, {
        title = tfDef.name .. " · 连续扫荡",
        maxCount = totalAvailable,
        sweepLabel = "最高纪录",
        sweepValue = "第 " .. tfBest .. " 波",
        costFn = function(count)
            local free = math.min(count, capturedFreeLeft)
            local ticket = count - free
            if free > 0 and ticket > 0 then
                return "免费 " .. free .. " 次 + 挑战券 " .. ticket .. " 张"
            elseif free > 0 then
                return "免费 " .. free .. " 次（不消耗挑战券）"
            else
                return "消耗 " .. ticket .. " 张挑战券"
            end
        end,
        previewFn = function(count)
            if isChest then
                local chests = TFData.EstimateTotalChestReward(tfBest)
                local items = {}
                for _, ctDef in ipairs(Config.CHEST_TYPES) do
                    if chests[ctDef.id] and chests[ctDef.id] > 0 then
                        items[#items + 1] = {
                            icon = ctDef.image or "📦",
                            name = ctDef.name,
                            amount = chests[ctDef.id] * count,
                            color = S.gold,
                        }
                    end
                end
                return items
            else
                local perRun = TFData.EstimateTotalReward(tfBest, nil, dungeonKey)
                return {
                    {
                        icon = rewardImage or tfDef.emoji,
                        name = rewardName,
                        amount = perRun * count,
                        color = tfDef.accentColor,
                    },
                }
            end
        end,
        onConfirm = function(count)
            local successCount = 0
            for i = 1, count do
                -- 优先消耗免费次数，再消耗挑战券
                local curFree = RD.GetFreeRemaining(dungeonKey)
                if curFree > 0 then
                    if not RD.ConsumeAttempt(dungeonKey) then break end
                else
                    if not RD.ConsumeDungeonTicket(dungeonKey) then
                        Toast.Show("挑战券不足，已扫荡 " .. successCount .. " 次", { 255, 200, 80 })
                        break
                    end
                end
                -- 模拟清波并结算
                local session = TFData.CreateSession(dungeonKey)
                if session then
                    for w = 1, tfBest do
                        session.currentWave = w
                        TFData.CompleteWave(session)
                    end
                    TFData.EndSession(session)
                end
                successCount = successCount + 1
            end

            if successCount > 0 then
                -- 构建扫荡总奖励展示
                local rewardItems = {}
                if isChest then
                    local chests = TFData.EstimateTotalChestReward(tfBest)
                    for _, ctDef in ipairs(Config.CHEST_TYPES) do
                        if chests[ctDef.id] and chests[ctDef.id] > 0 then
                            rewardItems[#rewardItems + 1] = {
                                icon = ctDef.image or "📦",
                                name = ctDef.name,
                                amount = chests[ctDef.id] * successCount,
                                borderColor = ctDef.borderColor or nil,
                            }
                        end
                    end
                else
                    local perRun = TFData.EstimateTotalReward(tfBest, nil, dungeonKey)
                    rewardItems[#rewardItems + 1] = {
                        icon = rewardImage or tfDef.emoji,
                        name = rewardName,
                        amount = perRun * successCount,
                    }
                end

                RewardDisplay.Show(UI, root, {
                    title = tfDef.name .. " 扫荡 ×" .. successCount .. " 完成！",
                    rewards = rewardItems,
                    onClose = function()
                        ctx.SetView("resource_detail", dungeonKey)
                    end,
                })
            end
        end,
    })
end

-- ============================================================================
-- 超越模式挑战逻辑 — 直接在资源副本中开战
-- ============================================================================

function ResourceDungeon.OnTranscendChallenge(UI, S, ctx, dungeonKey)
    dungeonKey = dungeonKey or "iron"
    local GameUI = require("Game.GameUI")
    local State = require("Game.State")

    if #HeroData.GetDeployedList() < Config.MAX_DEPLOYED then
        Toast.Show("需要上阵" .. Config.MAX_DEPLOYED .. "名英雄才能挑战", S.red)
        return
    end

    -- 消耗次数：共用对应副本的免费/券
    local freeR = RD.GetFreeRemaining(dungeonKey)
    if freeR > 0 then
        if not RD.ConsumeAttempt(dungeonKey) then return end
    else
        local totalTickets = RD.GetTotalTicketCount(dungeonKey)
        if totalTickets > 0 then
            if not RD.ConsumeDungeonTicket(dungeonKey) then return end
        else
            local adR = RD.GetAdRemaining(dungeonKey)
            if adR > 0 then
                Toast.Show("次数不足，请先领取挑战券", { 255, 200, 80 })
            else
                Toast.Show("今日次数已用完", { 255, 200, 80 })
            end
            return
        end
    end

    local config, session = TFData.BuildBattleConfig(dungeonKey)
    if not config or not session then return end

    local label = config.label

    config.onWin = function(result)
        for w = 1, config.totalWaves do
            session.currentWave = w
            TFData.CompleteWave(session)
        end
        local endResult = TFData.EndSession(session)
        local root = GameUI.GetUIRoot()
        if root then
            RC.ShowFromDefs(UI, root, endResult.rewardDefs,
                label .. " 通关 · 第" .. endResult.clearedWave .. "波", function()
                    ctx.SetView("resource_detail", dungeonKey)
                    GameUI.ExitDungeonBattle()
                end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    config.onLose = function(result)
        local clearedWaves = math.max(0, (State.currentWave or 1) - 1)
        for w = 1, clearedWaves do
            session.currentWave = w
            TFData.CompleteWave(session)
        end
        local endResult = TFData.EndSession(session)
        local root = GameUI.GetUIRoot()
        if root then
            RC.ShowFromDefs(UI, root, endResult.rewardDefs,
                label .. " 失败 · 第" .. endResult.clearedWave .. "波", function()
                    ctx.SetView("resource_detail", dungeonKey)
                    GameUI.ExitDungeonBattle()
                end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    config.onExit = function(result, continueExit)
        local clearedWaves = math.max(0, (State.currentWave or 1) - 1)
        for w = 1, clearedWaves do
            session.currentWave = w
            TFData.CompleteWave(session)
        end
        local endResult = TFData.EndSession(session)
        local root = GameUI.GetUIRoot()
        if root then
            RC.ShowFromDefs(UI, root, endResult.rewardDefs,
                label .. " 退出 · 第" .. endResult.clearedWave .. "波", function()
                    ctx.SetView("resource_detail", dungeonKey)
                    continueExit()
                end)
        else
            continueExit()
        end
    end

    GameUI.EnterDungeonBattle(config)
end

return ResourceDungeon
