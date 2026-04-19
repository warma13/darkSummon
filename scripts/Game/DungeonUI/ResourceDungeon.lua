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

    local currDef = Config.CURRENCY[def.rewardCurrency]
    local freeRem = RD.GetFreeRemaining(def.key)

    local badgeBg = canChallenge and { 80, 180, 80, 40 } or { 200, 60, 60, 40 }
    local badgeColor = canChallenge and S.green or S.red

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
                                            or  (remaining .. "/" .. RD.DAILY_ATTEMPTS),
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

    local bestWave = RD.GetBestWave(def.key)
    local remaining = RD.GetRemainingAttempts(def.key)
    local ticketCount = InventoryData.GetCount("dungeon_ticket")

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
            ticketCount > 0 and UI.Panel {
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
                        text = "×" .. ticketCount,
                        fontSize = 11,
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

    -- 滚动内容
    local contentChildren = {}
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildInfoCard(UI, S, def, bestWave)
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildWaveGrid(UI, S, ctx, def, bestWave)
    contentChildren[#contentChildren + 1] = ResourceDungeon._BuildRewardPreview(UI, S, ctx, def)

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
function ResourceDungeon._BuildRewardPreview(UI, S, ctx, def)
    local milestones = { 5, 10, 15, 20 }
    local items = {}

    for _, w in ipairs(milestones) do
        local reward = RD.GetWaveReward(def.key, w)
        local diffLabel, diffColor = RD.GetWaveDifficulty(w)
        local rewardText = ""
        local rewardImage = nil
        if def.rewardCurrency == "chest" then
            local cr = RD.GetChestWaveReward(w)
            if cr then
                local ct = Config.CHEST_TYPES_MAP[cr.id]
                rewardText = (ct and ct.name or cr.id) .. " ×" .. cr.count
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
    local totalRewards = RD.CalcTotalRewards(def.key, RD.TOTAL_WAVES)
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
    local ticketCount   = InventoryData.GetCount("dungeon_ticket")

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
    elseif adRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "📺 看广告挑战 (剩" .. adRemaining .. "次)",
            fontSize = 14,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                ResourceDungeon.OnAdChallenge(UI, S, ctx, def.key)
            end,
        }
    elseif ticketCount > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "使用门票挑战 (余" .. ticketCount .. "张)",
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
            text = "今日次数已用完",
            fontSize = 13,
            flex = 1, height = 46,
            borderRadius = 8,
            variant = "outline",
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

function ResourceDungeon.OnAdChallenge(UI, S, ctx, dungeonKey)
    local def = RD.DUNGEON_MAP[dungeonKey]
    if not def then return end

    if RD.GetAdRemaining(dungeonKey) <= 0 then
        Toast.Show("今日广告次数已达上限", { 255, 200, 80 })
        return
    end

    AdHelper.ShowRewardAd(function()
        if not RD.ConsumeAdAttempt(dungeonKey) then return end
        ResourceDungeon.OnChallenge(UI, S, ctx, dungeonKey, false, true)
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
            if not RD.ConsumeTicket() then return end
        else
            if not RD.ConsumeAttempt(dungeonKey) then return end
        end
    end

    local BM = require("Game.BattleManager")
    local GameUI = require("Game.GameUI")

    local waves = {}
    local totalWaves = RD.TOTAL_WAVES

    for w = 1, totalWaves do
        local enemyDefs = RD.GenerateWaveEnemies(dungeonKey, w)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    local label = (def.name or dungeonKey) .. "副本"

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
            local rewards = RD.ClaimReward(dungeonKey, totalWaves)
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
                local rewards = RD.ClaimReward(dungeonKey, clearedWave)
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
                local rewards = RD.ClaimReward(dungeonKey, clearedWave)
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

return ResourceDungeon
