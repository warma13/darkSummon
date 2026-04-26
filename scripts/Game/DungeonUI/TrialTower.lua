-- Game/DungeonUI/TrialTower.lua
-- 试练塔详情页 UI + 挑战逻辑

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local TrialTowerData = require("Game.TrialTowerData")
local Toast = require("Game.Toast")
local RC = require("Game.RewardController")

local TrialTower = {}

-- 前置声明（实际定义在下方）
local DoChallenge
local BuildTrialConfig

-- ============================================================================
-- 连续挑战状态
-- ============================================================================
local _autoContinue = false          -- 连续挑战开关
local _countdown    = nil            -- 当前倒计时（nil=不在倒计时）
local COUNTDOWN_SECONDS = 3          -- 倒计时秒数
local _cdFloor      = nil            -- 倒计时目标层
local _cdUI         = nil            -- 倒计时缓存的 UI 引用
local _cdS          = nil
local _cdCtx        = nil
local _cdDefs       = nil            -- 倒计时缓存的奖励 defs
local _cdLabel      = nil            -- 倒计时缓存的关卡名

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

    -- 按钮行
    local buttonRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6, paddingBottom = 10,
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

    -- 连续挑战开关行
    local toggleRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "flex-end",
        paddingRight = 16,
        paddingTop = 4,
        gap = 6,
        children = {
            UI.Label {
                text = "连续挑战",
                fontSize = 12,
                fontColor = S.dim,
                pointerEvents = "none",
            },
            UI.Toggle {
                value = _autoContinue,
                trackWidth = 38,
                trackHeight = 20,
                thumbSize = 16,
                onChange = function(self, v)
                    _autoContinue = v
                    print("[TrialTower] autoContinue = " .. tostring(v))
                end,
            },
        },
    }

    return UI.Panel {
        width = "100%",
        flexShrink = 0,
        children = {
            toggleRow,
            buttonRow,
        },
    }
end

-- ============================================================================
-- 挑战逻辑
-- ============================================================================

--- 构建试练塔战斗配置
---@param UI any
---@param S any
---@param ctx any
---@param floor number  当前全局层数
---@return table config  BattleManager 所需的配置
BuildTrialConfig = function(UI, S, ctx, floor)
    local BM = require("Game.BattleManager")
    local GameUI = require("Game.GameUI")
    local RewardDisplay = require("Game.RewardDisplay")
    local config = TrialTowerData.BuildBattleConfig(floor)
    local label  = config.label

    config.onWin = function(result)
        local rewards = TrialTowerData.ClearFloor(floor)
        local defs = rewards and rewards.rewardDefs or {}

        local root = GameUI.GetUIRoot()
        if not root or #defs == 0 then
            GameUI.ExitDungeonBattle()
            return
        end

        -- 检查是否可以继续下一层（有券）
        local nextFloor = floor + 1
        local canContinue = TrialTowerData.GetTickets() > 0

        if not canContinue then
            -- 无券，正常退出
            RC.ShowFromDefs(UI, root, defs, label .. " 通关", function()
                GameUI.ExitDungeonBattle()
            end)
            return
        end

        -- 有券：根据连续挑战开关决定行为
        local nextTower = TrialTowerData.GetTowerNum(nextFloor)
        local nextFloorInTower = TrialTowerData.GetFloorInTower(nextFloor)
        local nextLabel = "继续 " .. nextTower .. "-" .. nextFloorInTower
        local ticketsLeft = TrialTowerData.GetTickets()

        -- 聚合同类奖励后构建展示列表
        local aggMap, aggOrder = {}, {}
        for _, d in ipairs(defs) do
            local key = (d.type or "") .. ":" .. (d.id or "")
            if aggMap[key] then
                aggMap[key].amount = (aggMap[key].amount or 1) + (d.amount or 1)
            else
                local m = { type = d.type, id = d.id, amount = d.amount or 1 }
                aggMap[key] = m
                aggOrder[#aggOrder + 1] = m
            end
        end

        if _autoContinue then
            -- 连续模式：启动倒计时覆盖层
            _cdFloor = nextFloor
            _cdUI    = UI
            _cdS     = S
            _cdCtx   = ctx
            _cdDefs  = aggOrder
            _cdLabel = label
            TrialTower._StartCountdown(UI, root, aggOrder, label, ticketsLeft, nextLabel)
            return
        end

        -- 手动模式：双按钮
        local rewardList = RC.BuildList(aggOrder)
        RewardDisplay.Show(UI, root, {
            title   = label .. " 通关",
            rewards = rewardList,
            hint    = "剩余试练券: " .. ticketsLeft,
            buttons = {
                {
                    text = "返回",
                    variant = "outline",
                    onClick = function()
                        RewardDisplay.Hide(root)
                        GameUI.ExitDungeonBattle()
                    end,
                },
                {
                    text = nextLabel,
                    variant = "primary",
                    onClick = function()
                        RewardDisplay.Hide(root)
                        if not TrialTowerData.SpendTicket() then
                            Toast.Show("试练券不足", { 255, 100, 100 })
                            GameUI.ExitDungeonBattle()
                            return
                        end
                        -- 直接启动下一层，不退出副本
                        local nextConfig = BuildTrialConfig(UI, S, ctx, nextFloor)
                        BM.Start(nextConfig)
                        if GameUI.UpdateHUD then GameUI.UpdateHUD() end
                        print("[TrialTower] Continue to next floor: " .. nextFloor)
                    end,
                },
            },
        })
    end

    config.onLose = function(result)
        local msg = label .. " 挑战失败 (第" .. result.wave .. "/" .. TrialTowerData.WAVE_COUNT .. "波)"
        Toast.Show(msg, { 255, 100, 100 })
        GameUI.ExitDungeonBattle()
    end

    config.onExit = function(result, continueExit)
        local msg = label .. " 提前退出 (第" .. (result.wave or 1) .. "/" .. TrialTowerData.WAVE_COUNT .. "波)"
        Toast.Show(msg, { 255, 200, 100 })
        continueExit()
    end

    return config
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

-- ============================================================================
-- 倒计时覆盖层
-- ============================================================================

--- 启动倒计时覆盖层
function TrialTower._StartCountdown(UI, root, aggDefs, label, ticketsLeft, nextLabel)
    _countdown = COUNTDOWN_SECONDS

    -- 构建奖励摘要文本
    local rewardTexts = {}
    for _, d in ipairs(aggDefs) do
        local name = d.id or d.type or "?"
        local cDef = Config.CURRENCY[d.id]
        if cDef and cDef.name then name = cDef.name end
        rewardTexts[#rewardTexts + 1] = name .. "×" .. (d.amount or 1)
    end
    local rewardSummary = table.concat(rewardTexts, "  ")

    -- 移除旧覆盖层（如果有）
    local old = root:FindById("trial_cd_overlay")
    if old then old:Remove() end

    local overlay = UI.Panel {
        id = "trial_cd_overlay",
        position = "absolute",
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 280,
                backgroundColor = { 30, 30, 40, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 80, 200, 120 },
                paddingTop = 20, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Label {
                        text = label .. " 通关",
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = { 255, 215, 0 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = rewardSummary,
                        fontSize = 12,
                        fontColor = { 200, 200, 200 },
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        id = "trial_cd_num",
                        text = tostring(math.ceil(_countdown)),
                        fontSize = 48,
                        fontWeight = "bold",
                        fontColor = { 120, 200, 255 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "秒后继续下一层",
                        fontSize = 13,
                        fontColor = { 160, 160, 180 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "剩余试练券: " .. ticketsLeft,
                        fontSize = 11,
                        fontColor = { 140, 140, 160 },
                        pointerEvents = "none",
                    },
                    UI.Button {
                        text = "取消",
                        width = 120,
                        height = 36,
                        borderRadius = 8,
                        variant = "outline",
                        fontSize = 13,
                        onClick = function()
                            TrialTower._CancelCountdown()
                        end,
                    },
                },
            },
        },
    }
    root:AddChild(overlay)
    print("[TrialTower] Countdown started: " .. COUNTDOWN_SECONDS .. "s to floor " .. _cdFloor)
end

--- 取消倒计时 → 退出副本
function TrialTower._CancelCountdown()
    _countdown = nil
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if root then
        local ov = root:FindById("trial_cd_overlay")
        if ov then ov:Remove() end
    end
    GameUI.ExitDungeonBattle()
    print("[TrialTower] Countdown cancelled, exiting dungeon")
end

--- 每帧更新倒计时（由 GameUI.Update 调用）
function TrialTower.UpdateCountdown(dt)
    if not _countdown then return end

    _countdown = _countdown - dt

    -- 更新显示数字
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if root then
        local numLabel = root:FindById("trial_cd_num")
        if numLabel then
            numLabel:SetText(tostring(math.ceil(math.max(0, _countdown))))
        end
    end

    -- 倒计时结束
    if _countdown <= 0 then
        _countdown = nil
        -- 移除覆盖层
        if root then
            local ov = root:FindById("trial_cd_overlay")
            if ov then ov:Remove() end
        end

        -- 花券 + 启动下一层
        if not TrialTowerData.SpendTicket() then
            Toast.Show("试练券不足", { 255, 100, 100 })
            GameUI.ExitDungeonBattle()
            return
        end

        local BM = require("Game.BattleManager")
        local nextConfig = BuildTrialConfig(_cdUI, _cdS, _cdCtx, _cdFloor)
        BM.Start(nextConfig)
        if GameUI.UpdateHUD then GameUI.UpdateHUD() end
        print("[TrialTower] Auto-continue to floor: " .. _cdFloor)
    end
end

return TrialTower
