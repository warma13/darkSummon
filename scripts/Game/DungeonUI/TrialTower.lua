-- Game/DungeonUI/TrialTower.lua
-- 试练塔详情页 UI + 挑战逻辑

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local TrialTowerData = require("Game.TrialTowerData")
local Toast = require("Game.Toast")

local TrialTower = {}

-- DoChallenge 前置声明（实际定义在下方）
local DoChallenge

-- ============================================================================
-- 试练塔详情页
-- ============================================================================

function TrialTower.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local data = TrialTowerData.GetData()
    local currentFloor = data.currentFloor
    local towerNum = TrialTowerData.GetTowerNum(currentFloor)
    local floorInTower = TrialTowerData.GetFloorInTower(currentFloor)

    -- 标题栏
    pageRoot:AddChild(TrialTower._BuildHeader(UI, S, towerNum))

    -- 内容区
    local contentChildren = {}
    contentChildren[#contentChildren + 1] = TrialTower._BuildInfoCard(UI, S, towerNum, floorInTower, currentFloor)
    contentChildren[#contentChildren + 1] = TrialTower._BuildFloorGrid(UI, S, towerNum, currentFloor)
    contentChildren[#contentChildren + 1] = TrialTower._BuildRewardPreview(UI, S, ctx, towerNum)

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = contentChildren,
    })

    -- 底部按钮
    pageRoot:AddChild(TrialTower._BuildChallengeButton(UI, S, ctx, currentFloor))
end

--- 标题栏
function TrialTower._BuildHeader(UI, S, towerNum)
    local diffLabel, diffColor = TrialTowerData.GetDifficultyLabel(towerNum)
    return UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        gap = 8,
        children = {
            UI.Label {
                text = "试练塔",
                fontSize = 20,
                fontWeight = "bold",
                fontColor = S.white,
                pointerEvents = "none",
            },
            UI.Panel {
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 2, paddingBottom = 2,
                borderRadius = 4,
                backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 60 },
                children = {
                    UI.Label {
                        text = diffLabel,
                        fontSize = 12,
                        fontColor = diffColor,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

--- 当前塔信息卡片
function TrialTower._BuildInfoCard(UI, S, towerNum, floorInTower, currentFloor)
    local themeDef = TrialTowerData.GetTheme(currentFloor)
    local themeName = themeDef and themeDef.name or "未知"
    local themeColor = (themeDef and themeDef.color) or S.purple

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
                borderColor = S.cardBorder,
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 12, paddingBottom = 12,
                children = {
                    UI.Panel {
                        flexDirection = "column",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "第 " .. towerNum .. " 塔",
                                fontSize = 18,
                                fontWeight = "bold",
                                fontColor = S.gold,
                                pointerEvents = "none",
                            },
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "主题:",
                                        fontSize = 12,
                                        fontColor = S.dim,
                                        pointerEvents = "none",
                                    },
                                    UI.Label {
                                        text = themeName,
                                        fontSize = 12,
                                        fontColor = themeColor,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column",
                        alignItems = "flex-end",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "进度",
                                fontSize = 11,
                                fontColor = S.dim,
                                pointerEvents = "none",
                            },
                            UI.Label {
                                text = (floorInTower - 1) .. " / 10",
                                fontSize = 16,
                                fontWeight = "bold",
                                fontColor = S.white,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 层数网格
function TrialTower._BuildFloorGrid(UI, S, towerNum, currentFloor)
    local towerStartFloor = (towerNum - 1) * 10 + 1

    local rows = {}
    for row = 1, 2 do
        local cells = {}
        for col = 1, 5 do
            local floorInTower = (row - 1) * 5 + col
            local globalFloor = towerStartFloor + floorInTower - 1
            cells[#cells + 1] = TrialTower._BuildFloorCell(UI, S, floorInTower, globalFloor, currentFloor)
        end
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 6,
            children = cells,
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexDirection = "column",
        gap = 6,
        flexShrink = 0,
        children = rows,
    }
end

--- 单个层格子
function TrialTower._BuildFloorCell(UI, S, floorInTower, globalFloor, currentFloor)
    local isCleared = TrialTowerData.IsFloorCleared(globalFloor)
    local isCurrent = TrialTowerData.IsCurrentFloor(globalFloor)
    local isBoss = (floorInTower == 10)

    local bg, border, textColor
    if isCleared then
        bg = S.clearedBg
        border = S.clearedBorder
        textColor = S.green
    elseif isCurrent then
        bg = S.currentBg
        border = S.currentBorder
        textColor = S.white
    else
        bg = S.lockedBg
        border = S.lockedBorder
        textColor = S.dim
    end

    local label = tostring(floorInTower)
    if isBoss then label = "BOSS" end

    local statusText = ""
    if isCleared then statusText = "✓"
    elseif isCurrent then statusText = "→"
    else statusText = "🔒"
    end

    return UI.Panel {
        flex = 1,
        height = 56,
        maxWidth = 60,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = bg,
        borderRadius = 6,
        borderWidth = isCurrent and 2 or 1,
        borderColor = border,
        gap = 2,
        children = {
            UI.Label {
                text = label,
                fontSize = isBoss and 11 or 14,
                fontWeight = (isCurrent or isBoss) and "bold" or "normal",
                fontColor = textColor,
                pointerEvents = "none",
            },
            UI.Label {
                text = statusText,
                fontSize = 10,
                fontColor = textColor,
                pointerEvents = "none",
            },
        },
    }
end

--- 奖励预览
function TrialTower._BuildRewardPreview(UI, S, ctx, towerNum)
    local stones, gold = TrialTowerData.GetFloorReward(towerNum)
    local floorPact = TrialTowerData.GetFloorVoidPact(towerNum)
    local clearPact = TrialTowerData.GetTowerClearVoidPact(towerNum)
    local ticketReward = TrialTowerData.GetTowerTicketReward()

    -- 每层奖励行
    local perFloorChildren = {
        UI.Label { text = "每层:", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
        Currency.IconWidget(UI, "devour_stone", 14),
        UI.Label { text = ctx.FormatNum(stones), fontSize = 12, fontColor = { 60, 160, 80 }, pointerEvents = "none" },
        UI.Label { text = "+", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
        Currency.IconWidget(UI, "nether_crystal", 14),
        UI.Label { text = ctx.FormatNum(gold), fontSize = 12, fontColor = { 140, 80, 200 }, pointerEvents = "none" },
    }
    -- 每层虚空契约（大于 0 时显示）
    if floorPact > 0 then
        perFloorChildren[#perFloorChildren + 1] = UI.Label { text = "+", fontSize = 10, fontColor = S.dim, pointerEvents = "none" }
        perFloorChildren[#perFloorChildren + 1] = Currency.IconWidget(UI, "void_pact", 14)
        perFloorChildren[#perFloorChildren + 1] = UI.Label { text = ctx.FormatNum(floorPact), fontSize = 12, fontColor = { 200, 40, 40 }, pointerEvents = "none" }
    end

    local rewardItems = {
        UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            flexWrap = "wrap",
            children = perFloorChildren,
        },
        UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Label { text = "通塔:", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                Currency.IconWidget(UI, "void_pact", 14),
                UI.Label { text = "×" .. ctx.FormatNum(clearPact), fontSize = 12, fontColor = { 200, 40, 40 }, pointerEvents = "none" },
                UI.Label { text = "+", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
                Currency.IconWidget(UI, "trial_ticket", 14),
                UI.Label { text = "×" .. ticketReward, fontSize = 12, fontColor = { 80, 200, 220 }, pointerEvents = "none" },
            },
        },
    }

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-around",
                backgroundColor = S.cardBg,
                borderRadius = 6,
                paddingTop = 8, paddingBottom = 8,
                paddingLeft = 8, paddingRight = 8,
                children = rewardItems,
            },
        },
    }
end

--- 底部按钮栏
function TrialTower._BuildChallengeButton(UI, S, ctx, currentFloor)
    local towerNum = TrialTowerData.GetTowerNum(currentFloor)
    local floorInTower = TrialTowerData.GetFloorInTower(currentFloor)
    local isBoss = (floorInTower == 10)
    local tickets = TrialTowerData.GetTickets()
    local baseText = isBoss and "BOSS" or ("第" .. floorInTower .. "层")
    local ticketDef = Config.CURRENCY["trial_ticket"]
    local ticketImg = ticketDef and ticketDef.image or "image/trial_ticket.png"

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 10, paddingBottom = 10,
        flexShrink = 0,
        gap = 8,
        children = {
            UI.Button {
                text = "返回",
                fontSize = 13,
                width = 56,
                height = 46,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    ctx.SetView("list")
                end,
            },
            UI.Button {
                id = "towerChallengeBtn",
                flex = 1,
                height = 46,
                borderRadius = 8,
                variant = "primary",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 6,
                onClick = function(self)
                    TrialTower.OnChallenge(UI, S, ctx)
                end,
                children = {
                    UI.Label {
                        text = "挑战 " .. baseText,
                        fontSize = 14,
                        fontColor = { 255, 255, 255, 255 },
                        pointerEvents = "none",
                    },
                    UI.Panel {
                        width = 15, height = 15,
                        backgroundImage = ticketImg,
                        backgroundFit = "contain",
                        pointerEvents = "none",
                        flexShrink = 0,
                    },
                    UI.Label {
                        text = "×1(" .. tickets .. ")",
                        fontSize = 12,
                        fontColor = { 200, 240, 255, 230 },
                        pointerEvents = "none",
                    },
                },
            },
            UI.Button {
                text = "排行",
                fontSize = 13,
                width = 56,
                height = 46,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    local LeaderboardUI = require("Game.LeaderboardUI")
                    LeaderboardUI.Show(2)
                end,
            },
        },
    }
end

-- ============================================================================
-- 挑战逻辑
-- ============================================================================

-- 试练塔专用奖励弹窗 ID
local TOWER_REWARD_ID = "towerRewardPopup"

-- ---- 奖励弹窗倒计时（Update 事件驱动） ----
local _cd = nil
local _cdRegistered = false

_G["_TrialTowerCdUpdate"] = function(eventType, eventData)
    if not _cd then return end
    _cd.elapsed = (_cd.elapsed or 0) + eventData:GetFloat("TimeStep")
    local remain = math.max(0, math.ceil(_cd.total - _cd.elapsed))
    if remain ~= _cd.lastRemain then
        _cd.lastRemain = remain
        if _cd.onTick then _cd.onTick(remain) end
    end
    if _cd.elapsed >= _cd.total then
        local done = _cd.onDone
        _cd = nil
        if done then done() end
    end
end

local function StartCountdown(seconds, onTick, onDone)
    _cd = { total = seconds, elapsed = 0, lastRemain = math.ceil(seconds), onTick = onTick, onDone = onDone }
    if not _cdRegistered then
        _cdRegistered = true
        SubscribeToEvent("Update", "_TrialTowerCdUpdate")
    end
end

local function StopCountdown()
    _cd = nil
end

--- 隐藏试练塔奖励弹窗
local function HideTowerReward(root)
    local p = root:FindById(TOWER_REWARD_ID)
    if p then p:Remove() end
end

--- 显示试练塔通关奖励弹窗
--- @param UI any
--- @param root any       UI 根节点
--- @param opts table     { title, items, onClose, countdown }
local function ShowTowerReward(UI, root, opts)
    local title     = opts.title or "通关奖励"
    local items     = opts.items or {}
    local onClose   = opts.onClose
    local countdown = opts.countdown  -- 秒数，nil 表示不自动关闭

    HideTowerReward(root)

    local closed = false
    local function dismiss()
        if closed then return end
        closed = true
        StopCountdown()
        HideTowerReward(root)
        if onClose then onClose() end
    end

    -- 奖励卡片
    local cards = {}
    for _, item in ipairs(items) do
        local iconWidget
        if item.icon and type(item.icon) == "string" and item.icon:find("%.png$") then
            iconWidget = UI.Panel {
                width = 44, height = 44,
                backgroundImage = item.icon,
                backgroundFit = "contain",
                flexShrink = 0,
            }
        else
            iconWidget = UI.Label {
                text = item.icon or "?",
                fontSize = 28,
                flexShrink = 0,
            }
        end
        cards[#cards + 1] = UI.Panel {
            width = 76,
            flexDirection = "column",
            alignItems = "center",
            gap = 4,
            paddingTop = 10, paddingBottom = 10,
            backgroundColor = { 35, 30, 25, 240 },
            borderRadius = 10,
            borderWidth = 2,
            borderColor = item.borderColor or { 100, 85, 50, 180 },
            children = {
                iconWidget,
                UI.Label {
                    text = item.name or "",
                    fontSize = 10,
                    fontColor = { 200, 185, 145, 255 },
                    flexShrink = 0,
                },
                UI.Label {
                    text = "×" .. tostring(item.amount or 0),
                    fontSize = 15,
                    fontColor = { 255, 220, 80, 255 },
                    fontWeight = "bold",
                    flexShrink = 0,
                },
            },
        }
    end

    -- 卡片内容（命令式构建，避免 nil 空洞）
    local inner = {}
    inner[#inner + 1] = UI.Label {
        text = "🏆  " .. title,
        fontSize = 18,
        fontColor = { 255, 245, 200, 255 },
        fontWeight = "bold",
        marginBottom = 10,
        flexShrink = 0,
    }
    inner[#inner + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        gap = 10,
        paddingLeft = 16, paddingRight = 16,
        paddingBottom = 10,
        flexShrink = 0,
        children = cards,
    }

    inner[#inner + 1] = UI.Button {
        text = "确定",
        variant = "primary",
        width = 130,
        height = 44,
        marginBottom = countdown and 4 or 18,
        marginTop = 6,
        flexShrink = 0,
        onClick = function() dismiss() end,
    }

    -- 倒计时标签（连续挑战时显示）
    if countdown and countdown > 0 then
        inner[#inner + 1] = UI.Label {
            id = "towerRewardCdLabel",
            text = countdown .. "s 后自动继续",
            fontSize = 12,
            fontColor = { 120, 200, 255, 180 },
            marginBottom = 14,
            flexShrink = 0,
        }
    end

    local popup = UI.Panel {
        id = TOWER_REWARD_ID,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 170 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "78%",
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 18, 16, 28, 252 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 80, 130, 220, 200 },
                paddingTop = 22,
                overflow = "hidden",
                pointerEvents = "auto",
                children = inner,
            },
        },
    }

    root:AddChild(popup)

    -- 启动倒计时（连续挑战时自动关闭弹窗）
    if countdown and countdown > 0 then
        StartCountdown(
            countdown,
            function(remain)
                local lbl = root:FindById("towerRewardCdLabel")
                if lbl then lbl:SetText(remain .. "s 后自动继续") end
            end,
            dismiss
        )
    end
end

--- 构建奖励列表
local function BuildRewardItems(rewards)
    local items = {}
    local function add(id, fallback, extra)
        local def = Config.CURRENCY[id]
        local item = {
            icon   = def and def.image or "?",
            name   = def and def.name or fallback,
            amount = rewards[id],
        }
        if extra then for k, v in pairs(extra) do item[k] = v end end
        items[#items + 1] = item
    end
    if (rewards.devour_stone    or 0) > 0 then add("devour_stone",   "噬魂石") end
    if (rewards.nether_crystal  or 0) > 0 then add("nether_crystal", "冥晶") end
    if (rewards.void_pact       or 0) > 0 then add("void_pact",    "虚空契约", { borderColor = { 255, 200, 50, 200 } }) end
    if rewards.isTowerClear then
        if (rewards.trial_ticket or 0) > 0 then add("trial_ticket", "试练券",   { borderColor = { 80, 200, 220, 200 } }) end
    end
    return items
end

--- 构建试练塔战斗配置
---@param UI any
---@param S any
---@param ctx any
---@param floor number  当前全局层数
---@return table config  BattleManager 所需的配置
local function BuildTrialConfig(UI, S, ctx, floor)
    local towerNum     = TrialTowerData.GetTowerNum(floor)
    local floorInTower = TrialTowerData.GetFloorInTower(floor)
    local isBoss       = (floorInTower == 10)
    local label        = "试练塔 " .. towerNum .. "-" .. floorInTower

    local BM = require("Game.BattleManager")

    local waves = {}
    for w = 1, TrialTowerData.WAVE_COUNT do
        waves[w] = BM.BuildSpawnQueue(TrialTowerData.GenerateWaveEnemies(floor, w), 0.5)
    end

    return {
        mode             = "trial_tower",
        waves            = waves,
        totalWaves       = TrialTowerData.WAVE_COUNT,
        stageNum         = towerNum,
        label            = label,
        waveInterval     = 25,
        autoAdvanceWave  = true,
        bossTimerEnabled = isBoss,
        overloadEnabled  = true,
        overloadLimit    = TrialTowerData.OVERLOAD_LIMIT,
        initialDarkSoul  = Config.INITIAL_DARK_SOUL,

        onWin = function(result)
            local rewards     = TrialTowerData.ClearFloor(floor)
            local rewardItems = rewards and BuildRewardItems(rewards) or {}

            require("Game.GameUI").ExitDungeonBattle()
            if #rewardItems > 0 then
                local root = require("Game.GameUI").GetUIRoot()
                if root then
                    ShowTowerReward(UI, root, {
                        title = label .. " 通关",
                        items = rewardItems,
                    })
                end
            end
        end,

        onLose = function(result)
            Toast.Show(label .. " 挑战失败 (第" .. result.wave .. "/" .. TrialTowerData.WAVE_COUNT .. "波)", S.red)
            require("Game.GameUI").ExitDungeonBattle()
        end,
    }
end

--- 核心挑战函数（进入副本，走 EnterDungeonBattle 完整流程）
DoChallenge = function(UI, S, ctx, floor)
    local GameUI = require("Game.GameUI")
    local config = BuildTrialConfig(UI, S, ctx, floor)
    GameUI.EnterDungeonBattle(config)
end

function TrialTower.OnChallenge(UI, S, ctx)
    if #HeroData.GetDeployedList() < Config.MAX_DEPLOYED then
        Toast.Show("需要上阵" .. Config.MAX_DEPLOYED .. "名英雄才能挑战", S.red)
        return
    end
    if not TrialTowerData.SpendTicket() then
        Toast.Show("试练券不足，每日0点自动补充10张", S.red)
        return
    end
    DoChallenge(UI, S, ctx, TrialTowerData.GetCurrentFloor())
end

return TrialTower
