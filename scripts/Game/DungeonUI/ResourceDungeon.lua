-- Game/DungeonUI/ResourceDungeon.lua
-- 资源副本列表 + 详情页 + 挑战逻辑

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local RD = require("Game.ResourceDungeonData")
local InventoryData = require("Game.InventoryData")
local Toast = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local AdHelper = require("Game.AdHelper")
local SweepPopup = require("Game.SweepPopup")

local ResourceDungeon = {}

-- 严格点击判定（拖动不触发）
local _tapPressX, _tapPressY = 0, 0
local TAP_THRESHOLD = 10

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
        backgroundColor = S.headerBg,
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
    if def.rewardCurrency ~= "chest" and currDef then
        rewardChildren = {
            Currency.IconWidget(UI, def.rewardCurrency, 13),
            UI.Label {
                text = currDef.name, fontSize = 11,
                fontColor = currDef.color or S.dim, pointerEvents = "none",
            },
        }
    else
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
    end

    return UI.Panel {
        width = "100%",
        aspectRatio = 16 / 9,
        flexDirection = "column",
        backgroundColor = canChallenge and S.cardBg or { 25, 20, 38, 180 },
        backgroundImage = def.cover,
        backgroundScaleMode = def.cover and "aspectFill" or nil,
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
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = 50, height = 50,
                justifyContent = "center", alignItems = "center",
                onClick = function()
                    ctx.SetView("resource_list")
                end,
                children = {
                    UI.Label { text = "‹", fontSize = 22, fontColor = S.dim, pointerEvents = "none" },
                },
            },
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
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildInfoCard(UI, S, def, bestWave)
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildDifficultySelector(UI, S, ctx, selectedDiff)
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildWaveGrid(UI, S, ctx, def, bestWave)
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildRewardPreview(UI, S, ctx, def, selectedDiff)

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = contentChildren,
    })

    -- 底部按钮
    pageRoot:AddChild(ResourceDungeon._BuildChallengeButton(UI, S, ctx, def, remaining))
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
                                text = RD.TOTAL_WAVES .. "波 × " .. RD.ENEMIES_PER_WAVE .. "怪 · 每波末尾Boss",
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
function ResourceDungeon._BuildDifficultySelector(UI, S, ctx, selectedDiff)
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

        diffButtons[#diffButtons + 1] = UI.Panel {
            flex = 1,
            height = 40,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = isSelected and { color[1], color[2], color[3], 60 } or { 30, 30, 40, 120 },
            borderRadius = 6,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and color or { 60, 60, 70, 100 },
            opacity = isUnlocked and 1.0 or 0.4,
            onClick = isUnlocked and function()
                RD.SetSelectedDifficulty(diffLevel)
                ctx.Refresh()
            end or function()
                Toast.Show("需要先通关「" .. RD.GetDifficultyDef(diffLevel - 1).label .. "」难度全20波", { 255, 200, 80 })
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

    -- 描述文本
    local diff = RD.GetDifficultyDef(selectedDiff)
    local descText
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
    local rows = {}
    for row = 1, 4 do
        local cells = {}
        for col = 1, 5 do
            local wave = (row - 1) * 5 + col
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
    if def.rewardCurrency == "chest" then
        chestReward = RD.GetChestWaveReward(wave)
        if chestReward then
            local ct = Config.CHEST_TYPES_MAP[chestReward.id]
            chestImage = ct and ct.image
        end
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
    local milestones = { 5, 10, 15, 20 }
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
        else
            local currDef = Config.CURRENCY[def.rewardCurrency]
            local name = currDef and currDef.name or def.rewardCurrency
            rewardText = name .. " +" .. ctx.FormatNum(reward)
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
    local totalRewards = RD.CalcTotalRewards(def.key, RD.TOTAL_WAVES, selectedDiff)
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
    else
        local total = totalRewards[def.rewardCurrency] or 0
        local currDef = Config.CURRENCY[def.rewardCurrency]
        totalText = (currDef and currDef.name or "") .. " " .. ctx.FormatNum(total)
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
            UI.Label {
                text = totalText, fontSize = 12,
                fontWeight = "bold", fontColor = S.gold, pointerEvents = "none",
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

    local BM = require("Game.BattleManager")
    local GameUI = require("Game.GameUI")

    local diffLevel = RD.GetSelectedDifficulty()
    local diffDef = RD.GetDifficultyDef(diffLevel)

    local waves = {}
    local totalWaves = RD.TOTAL_WAVES

    for w = 1, totalWaves do
        local enemyDefs = RD.GenerateWaveEnemies(dungeonKey, w, diffLevel)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    local diffSuffix = diffLevel > 0 and (" [" .. diffDef.label .. "]") or ""
    local label = (def.name or dungeonKey) .. "副本" .. diffSuffix

    GameUI.EnterDungeonBattle({
        mode = "resource_dungeon",
        waves = waves,
        totalWaves = totalWaves,
        stageNum = 1,
        label = label,
        waveInterval = 30,
        autoAdvanceWave = true,
        bossTimerEnabled = true,
        overloadEnabled = true,
        overloadLimit = 10,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,

        onWin = function(result)
            local rewards = RD.ClaimReward(dungeonKey, totalWaves, diffLevel)
            if rewards then
                local rewardItems = {}
                if def.rewardCurrency == "chest" then
                    local c = rewards.chests or {}
                    for chestId, count in pairs(c) do
                        if count > 0 then
                            local ct = Config.CHEST_TYPES_MAP[chestId]
                            rewardItems[#rewardItems + 1] = {
                                icon = ct and ct.image or "?",
                                name = ct and ct.name or chestId,
                                amount = count,
                                borderColor = ct and ct.borderColor or nil,
                            }
                        end
                    end
                else
                    local currDef = Config.CURRENCY[def.rewardCurrency]
                    local amount = rewards[def.rewardCurrency] or 0
                    if amount > 0 then
                        rewardItems[#rewardItems + 1] = {
                            icon = currDef and currDef.image or "?",
                            name = currDef and currDef.name or def.rewardCurrency,
                            amount = amount,
                        }
                    end
                end
                if #rewardItems > 0 then
                    local root = GameUI.GetUIRoot()
                    if root then
                        RewardDisplay.Show(UI, root, {
                            title = label .. " 全部通关!",
                            rewards = rewardItems,
                            onClose = function()
                                GameUI.ExitDungeonBattle()
                            end,
                        })
                        return
                    end
                end
            end
            GameUI.ExitDungeonBattle()
        end,

        onExit = function(result)
            local clearedWave = math.max(0, result.wave - 1)
            if clearedWave > 0 then
                local rewards = RD.ClaimReward(dungeonKey, clearedWave, diffLevel)
                if rewards then
                    local rewardItems = {}
                    if def.rewardCurrency == "chest" then
                        local c = rewards.chests or {}
                        for chestId, count in pairs(c) do
                            if count > 0 then
                                local ct = Config.CHEST_TYPES_MAP[chestId]
                                rewardItems[#rewardItems + 1] = {
                                    icon = ct and ct.image or "?",
                                    name = ct and ct.name or chestId,
                                    amount = count,
                                    borderColor = ct and ct.borderColor or nil,
                                }
                            end
                        end
                    else
                        local currDef = Config.CURRENCY[def.rewardCurrency]
                        local amount = rewards[def.rewardCurrency] or 0
                        if amount > 0 then
                            rewardItems[#rewardItems + 1] = {
                                icon = currDef and currDef.image or "?",
                                name = currDef and currDef.name or def.rewardCurrency,
                                amount = amount,
                            }
                        end
                    end
                    if #rewardItems > 0 then
                        local root = GameUI.GetUIRoot()
                        if root then
                            RewardDisplay.Show(UI, root, {
                                title = label .. " 提前退出 (第" .. clearedWave .. "波)",
                                rewards = rewardItems,
                                onClose = function()
                                    GameUI.ExitDungeonBattle()
                                end,
                            })
                            return
                        end
                    end
                end
            else
                Toast.Show(label .. " 提前退出，无奖励", S.red)
            end
            GameUI.ExitDungeonBattle()
        end,

        onLose = function(result)
            local BM_ = require("Game.BattleManager")
            if BM_.config then BM_.config.onExit = nil end

            local clearedWave = math.max(0, result.wave - 1)
            if clearedWave > 0 then
                local rewards = RD.ClaimReward(dungeonKey, clearedWave, diffLevel)
                if rewards then
                    local rewardItems = {}
                    if def.rewardCurrency == "chest" then
                        local c = rewards.chests or {}
                        for chestId, count in pairs(c) do
                            if count > 0 then
                                local ct = Config.CHEST_TYPES_MAP[chestId]
                                rewardItems[#rewardItems + 1] = {
                                    icon = ct and ct.image or "?",
                                    name = ct and ct.name or chestId,
                                    amount = count,
                                    borderColor = ct and ct.borderColor or nil,
                                }
                            end
                        end
                    else
                        local currDef = Config.CURRENCY[def.rewardCurrency]
                        local amount = rewards[def.rewardCurrency] or 0
                        if amount > 0 then
                            rewardItems[#rewardItems + 1] = {
                                icon = currDef and currDef.image or "?",
                                name = currDef and currDef.name or def.rewardCurrency,
                                amount = amount,
                            }
                        end
                    end
                    if #rewardItems > 0 then
                        local root = GameUI.GetUIRoot()
                        if root then
                            RewardDisplay.Show(UI, root, {
                                title = label .. " 第" .. clearedWave .. "波失败",
                                rewards = rewardItems,
                                onClose = function()
                                    GameUI.ExitDungeonBattle()
                                end,
                            })
                            return
                        end
                    end
                end
            else
                Toast.Show(label .. " 挑战失败", S.red)
            end
            GameUI.ExitDungeonBattle()
        end,
    })
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

    local totalTickets = RD.GetTotalTicketCount(def.key)
    if totalTickets <= 0 then
        Toast.Show("没有可用的挑战券", { 255, 200, 80 })
        return
    end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    SweepPopup.Show(UI, root, S, {
        title = def.name .. diffSuffix .. " · 连续扫荡",
        maxCount = totalTickets,
        sweepLabel = "最高纪录",
        sweepValue = "第 " .. bestWave .. " 波" .. (diffLevel > 0 and ("  奖励×" .. diffDef.rewardMult) or ""),
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
            else
                local amount = rewards[def.rewardCurrency] or 0
                local currDef = Config.CURRENCY[def.rewardCurrency]
                if amount > 0 then
                    items[#items + 1] = {
                        icon = currDef and currDef.image or "💰",
                        name = currDef and currDef.name or def.rewardCurrency,
                        amount = amount * count,
                        color = def.accentColor,
                    }
                end
            end
            return items
        end,
        onConfirm = function(count)
            -- 执行扫荡：消耗门票 + 发放奖励
            local successCount = 0

            for i = 1, count do
                if not RD.ConsumeDungeonTicket(def.key) then
                    Toast.Show("挑战券不足，已扫荡 " .. successCount .. " 次", { 255, 200, 80 })
                    break
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
                else
                    local currDef = Config.CURRENCY[def.rewardCurrency]
                    local amount = (totalRewards[def.rewardCurrency] or 0) * successCount
                    if amount > 0 then
                        rewardItems[#rewardItems + 1] = {
                            icon = currDef and currDef.image or "💰",
                            name = currDef and currDef.name or def.rewardCurrency,
                            amount = amount,
                        }
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

return ResourceDungeon
