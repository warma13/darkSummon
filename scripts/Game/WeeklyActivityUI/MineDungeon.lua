-- Game/WeeklyActivityUI/MineDungeon.lua
-- 矿洞寻宝 UI 子模块
-- 概览横幅（嵌入限时活动标签页）+ 全屏探索流程 + 战斗衔接

local MDD              = require("Game.MineDungeonData")
local Currency         = require("Game.Currency")
local Toast            = require("Game.Toast")
local RewardController = require("Game.RewardController")
local RewardIcon       = require("Game.RewardIcon")
local State            = require("Game.State")

local MineDungeon = {}

-- 缓存
---@type any
local _UI = nil
---@type any
local _pageRoot = nil
---@type any
local _S = nil

-- 全屏探索 overlay
---@type any
local exploreOverlay = nil

-- ============================================================================
-- 概览横幅（嵌入 WeeklyActivityUI 限时活动标签页）
-- ============================================================================

function MineDungeon.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()
    _UI = UI; _S = S; _pageRoot = ctx.GetPageRoot()

    local remaining = MDD.GetRemaining()
    local bestFloor = MDD.GetBestFloor()
    local isActive  = MDD.IsActive()

    return UI.Panel {
        width = "100%",
        backgroundColor = { 35, 30, 15, 240 },
        borderRadius = 10,
        borderWidth = 2,
        borderColor = { 200, 160, 60, 200 },
        overflow = "hidden",
        marginBottom = 8,
        children = {
            -- 活动配图
            UI.Panel {
                width = "100%", height = 120,
                backgroundImage = "image/banner_mine_dungeon.png",
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
                                        text = "⛏️ 矿洞寻宝",
                                        fontSize = 16,
                                        fontColor = { 255, 200, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "深入矿洞探索，挖掘珍稀矿石与战利品",
                                        fontSize = 10,
                                        fontColor = { 200, 180, 130, 200 },
                                    },
                                },
                            },
                            -- 今日剩余
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 5, paddingBottom = 5,
                                backgroundColor = { 80, 60, 10, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 200, 160, 60, 150 },
                                children = {
                                    UI.Label {
                                        text = "剩余: " .. remaining .. "/" .. MDD.DAILY_ENTRIES,
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
                    -- 历史最佳 + 开始按钮
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = bestFloor > 0
                                    and ("历史最深: 第" .. bestFloor .. "层")
                                    or "尚未探索",
                                fontSize = 12,
                                fontColor = { 180, 170, 140, 200 },
                            },
                            UI.Button {
                                text = isActive and (remaining > 0 and "开始探索" or "次数已用完") or "活动未开放",
                                fontSize = 13,
                                height = 34,
                                paddingLeft = 16, paddingRight = 16,
                                borderRadius = 8,
                                variant = (isActive and remaining > 0) and "primary" or "outline",
                                disabled = not isActive or remaining <= 0,
                                onClick = function()
                                    MineDungeon._StartExploration()
                                end,
                            },
                        },
                    },
                    -- 规则说明
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 20, 18, 8, 200 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        gap = 4,
                        borderWidth = 1,
                        borderColor = { 100, 80, 30, 100 },
                        children = {
                            UI.Label {
                                text = "规则说明",
                                fontSize = 11,
                                fontColor = { 200, 180, 80, 240 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "• 共10层，每层随机遭遇矿脉(安全挖矿)或怪物(战斗)",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "• 第5/10层固定出现Boss，击败后获得丰厚奖励",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "• 战斗失败仅获得50%已累积奖励，请量力而行",
                                fontSize = 10, fontColor = { 255, 160, 80, 200 },
                            },
                            UI.Label {
                                text = "• 每日" .. MDD.DAILY_ENTRIES .. "次入场机会",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 全屏探索流程
-- ============================================================================

--- 开始一次新探索
function MineDungeon._StartExploration()
    local session, msg = MDD.CreateSession()
    if not session then
        Toast.Show(msg or "无法进入", { 255, 200, 80 })
        return
    end

    -- 创建全屏探索 overlay
    MineDungeon._ShowExploreOverlay()
    -- 自动推进到第一层
    MineDungeon._AdvanceToNextFloor()
end

--- 显示全屏探索 overlay
function MineDungeon._ShowExploreOverlay()
    local UI = _UI
    if not UI then return end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    -- 移除旧的 overlay
    if exploreOverlay then
        exploreOverlay:Remove()
        exploreOverlay = nil
    end

    exploreOverlay = UI.Panel {
        id = "mineDungeonOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 10, 8, 5, 250 },
        zIndex = 800,
        children = {
            -- 顶部状态栏
            MineDungeon._BuildExploreHeader(),
            -- 内容区域（动态替换）
            UI.ScrollView {
                id = "mineExploreContent",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                padding = 14,
                gap = 10,
            },
        },
    }

    root:AddChild(exploreOverlay)
end

--- 探索顶部状态栏
function MineDungeon._BuildExploreHeader()
    local UI = _UI
    local session = MDD.GetSession()
    local floor = session and session.currentFloor or 0

    return UI.Panel {
        id = "mineExploreHeader",
        width = "100%",
        flexShrink = 0,
        paddingTop = 12, paddingBottom = 10,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = { 30, 25, 12, 250 },
        borderBottomWidth = 1,
        borderColor = { 120, 100, 40, 120 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Panel {
                gap = 2,
                children = {
                    UI.Label {
                        text = "⛏️ 矿洞寻宝",
                        fontSize = 16,
                        fontColor = { 255, 200, 80, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        id = "mineFloorIndicator",
                        text = floor > 0 and ("当前: 第" .. floor .. "/" .. MDD.MAX_FLOORS .. "层") or "准备进入...",
                        fontSize = 11,
                        fontColor = { 180, 170, 130, 200 },
                    },
                },
            },
            UI.Button {
                text = "撤退",
                fontSize = 12,
                height = 30,
                paddingLeft = 12, paddingRight = 12,
                borderRadius = 6,
                variant = "outline",
                onClick = function()
                    MineDungeon._ConfirmExit()
                end,
            },
        },
    }
end

--- 更新顶部层指示
function MineDungeon._UpdateHeader()
    if not exploreOverlay then return end
    local indicator = exploreOverlay:FindById("mineFloorIndicator")
    if not indicator then return end
    local session = MDD.GetSession()
    if session then
        indicator:SetText("当前: 第" .. session.currentFloor .. "/" .. MDD.MAX_FLOORS .. "层")
    end
end

--- 推进到下一层
function MineDungeon._AdvanceToNextFloor()
    local encounter = MDD.AdvanceFloor()
    if not encounter then
        -- 全部通关
        MineDungeon._FinishExploration("clear")
        return
    end

    MineDungeon._UpdateHeader()
    MineDungeon._ShowEncounter(encounter)
end

--- 显示遭遇内容
function MineDungeon._ShowEncounter(encounter)
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local contentArea = exploreOverlay:FindById("mineExploreContent")
    if not contentArea then return end
    contentArea:ClearChildren()

    local floor = encounter.floor
    local floorLabel, floorColor = MDD.GetFloorLabel(floor)
    local emoji, typeLabel, typeColor = MDD.GetEncounterDisplay(encounter.encounterType)

    -- 层标题
    contentArea:AddChild(UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 6,
        paddingTop = 10, paddingBottom = 10,
        children = {
            UI.Label {
                text = floorLabel,
                fontSize = 18,
                fontColor = floorColor,
                fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = emoji,
                        fontSize = 24,
                    },
                    UI.Label {
                        text = "遭遇: " .. typeLabel,
                        fontSize = 15,
                        fontColor = typeColor,
                        fontWeight = "bold",
                    },
                },
            },
        },
    })

    if encounter.encounterType == "ore" then
        MineDungeon._ShowOreEncounter(contentArea, encounter)
    else
        MineDungeon._ShowBattleEncounter(contentArea, encounter)
    end
end

--- 矿脉遭遇 UI
function MineDungeon._ShowOreEncounter(contentArea, encounter)
    local UI = _UI

    -- 矿脉描述
    contentArea:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = { 20, 40, 60, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 60, 140, 200, 150 },
        paddingTop = 14, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        gap = 10,
        children = {
            UI.Label {
                text = "发现一处闪烁的矿脉！可以安全开采。",
                fontSize = 13,
                fontColor = { 140, 210, 255, 255 },
                textAlign = "center",
            },
            -- 奖励预览
            MineDungeon._BuildRewardPreview(encounter.rewards),
        },
    })

    -- 操作按钮
    contentArea:AddChild(MineDungeon._BuildActionButtons(encounter, "ore"))
end

--- 战斗遭遇 UI（怪物/Boss）
function MineDungeon._ShowBattleEncounter(contentArea, encounter)
    local UI = _UI
    local isBoss = encounter.encounterType == "boss"

    local descText = isBoss
        and "前方洞穴深处传来低沉的咆哮...Boss正在等待！"
        or "矿道中潜伏着一群怪物，必须战斗才能通过！"

    local descColor = isBoss
        and { 255, 120, 80, 255 }
        or { 255, 200, 100, 255 }

    contentArea:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = isBoss and { 50, 15, 15, 220 } or { 45, 30, 10, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = isBoss and { 255, 80, 60, 150 } or { 200, 140, 40, 150 },
        paddingTop = 14, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        gap = 10,
        children = {
            UI.Label {
                text = descText,
                fontSize = 13,
                fontColor = descColor,
                textAlign = "center",
            },
            -- 胜利奖励预览
            UI.Label {
                text = "胜利奖励:",
                fontSize = 11,
                fontColor = { 180, 170, 140, 200 },
            },
            MineDungeon._BuildRewardPreview(encounter.rewards),
            -- 失败提示
            UI.Panel {
                width = "100%",
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = { 80, 20, 20, 150 },
                borderRadius = 6,
                children = {
                    UI.Label {
                        text = "⚠️ 战斗失败将仅获得 " .. math.floor(MDD.FAIL_REWARD_RATIO * 100) .. "% 已累积奖励",
                        fontSize = 10,
                        fontColor = { 255, 160, 80, 220 },
                        textAlign = "center",
                    },
                },
            },
        },
    })

    -- 操作按钮
    contentArea:AddChild(MineDungeon._BuildActionButtons(encounter, encounter.encounterType))
end

--- 奖励预览列表
function MineDungeon._BuildRewardPreview(rewards)
    local UI = _UI
    if not rewards or #rewards == 0 then
        return UI.Panel { width = 0, height = 0 }
    end

    local items = {}
    for _, r in ipairs(rewards) do
        local name = r.id
        local info = Currency.GetInfo(r.id)
        if info and info.name then name = info.name end

        items[#items + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            marginRight = 10,
            children = {
                Currency.IconWidget(UI, r.id, 14),
                UI.Label {
                    text = name .. " ×" .. r.amount,
                    fontSize = 11,
                    fontColor = { 220, 215, 200, 240 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 4,
        children = items,
    }
end

--- 操作按钮区域
function MineDungeon._BuildActionButtons(encounter, encounterType)
    local UI = _UI
    local session = MDD.GetSession()
    local isLastFloor = session and session.currentFloor >= MDD.MAX_FLOORS

    local buttons = {}

    if encounterType == "ore" then
        -- 矿脉：挖掘 → 自动领取奖励 → 选择继续或撤退
        buttons[#buttons + 1] = UI.Button {
            text = "💎 开采矿脉",
            fontSize = 14,
            width = "100%",
            height = 44,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                MDD.CollectRewards(encounter)
                Toast.Show("成功开采矿脉！获得资源", { 80, 200, 120 })
                MineDungeon._ShowPostCollect(encounter)
            end,
        }
    else
        -- 怪物/Boss：进入战斗
        local btnText = encounterType == "boss" and "💀 挑战Boss" or "⚔️ 迎战怪物"
        buttons[#buttons + 1] = UI.Button {
            text = btnText,
            fontSize = 14,
            width = "100%",
            height = 44,
            borderRadius = 8,
            variant = "primary",
            onClick = function()
                MineDungeon._EnterBattle(encounter)
            end,
        }
    end

    -- 撤退按钮（非首层才显示）
    if session and session.currentFloor > 1 then
        buttons[#buttons + 1] = UI.Button {
            text = "🏃 带着战利品撤退",
            fontSize = 12,
            width = "100%",
            height = 36,
            borderRadius = 8,
            variant = "outline",
            marginTop = 4,
            onClick = function()
                MineDungeon._ConfirmExit()
            end,
        }
    end

    -- 累积奖励汇总
    local accSummary = MineDungeon._BuildAccumulatedSummary()

    return UI.Panel {
        width = "100%",
        gap = 8,
        paddingTop = 10,
        children = {
            accSummary,
            table.unpack(buttons),
        },
    }
end

--- 挖矿/胜利后的继续选择界面
function MineDungeon._ShowPostCollect(encounter)
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local contentArea = exploreOverlay:FindById("mineExploreContent")
    if not contentArea then return end
    contentArea:ClearChildren()

    local session = MDD.GetSession()
    local isLastFloor = session and session.currentFloor >= MDD.MAX_FLOORS

    local floorLabel, floorColor = MDD.GetFloorLabel(encounter.floor)

    contentArea:AddChild(UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 8,
        paddingTop = 20, paddingBottom = 10,
        children = {
            UI.Label {
                text = "✅ " .. floorLabel .. " 完成！",
                fontSize = 18,
                fontColor = { 100, 255, 150, 255 },
                fontWeight = "bold",
            },
            -- 本层获得
            UI.Label {
                text = "本层获得:",
                fontSize = 12,
                fontColor = { 180, 170, 140, 200 },
            },
            MineDungeon._BuildRewardPreview(encounter.rewards),
        },
    })

    -- 累积奖励
    contentArea:AddChild(MineDungeon._BuildAccumulatedSummary())

    if isLastFloor then
        -- 全部通关
        contentArea:AddChild(UI.Panel {
            width = "100%",
            alignItems = "center",
            paddingTop = 10,
            gap = 8,
            children = {
                UI.Label {
                    text = "🎉 恭喜！已探索到矿洞最深处！",
                    fontSize = 15,
                    fontColor = { 255, 220, 80, 255 },
                    fontWeight = "bold",
                },
                UI.Button {
                    text = "领取全部奖励",
                    fontSize = 14,
                    width = "100%",
                    height = 44,
                    borderRadius = 8,
                    variant = "primary",
                    onClick = function()
                        MineDungeon._FinishExploration("clear")
                    end,
                },
            },
        })
    else
        contentArea:AddChild(UI.Panel {
            width = "100%",
            gap = 8,
            paddingTop = 10,
            children = {
                UI.Button {
                    text = "⬇️ 继续深入下一层",
                    fontSize = 14,
                    width = "100%",
                    height = 44,
                    borderRadius = 8,
                    variant = "primary",
                    onClick = function()
                        MineDungeon._AdvanceToNextFloor()
                    end,
                },
                UI.Button {
                    text = "🏃 带着战利品撤退",
                    fontSize = 12,
                    width = "100%",
                    height = 36,
                    borderRadius = 8,
                    variant = "outline",
                    onClick = function()
                        MineDungeon._FinishExploration("exit")
                    end,
                },
            },
        })
    end
end

--- 累积奖励汇总
function MineDungeon._BuildAccumulatedSummary()
    local UI = _UI
    local session = MDD.GetSession()
    if not session or not UI then
        return UI and UI.Panel { width = 0, height = 0 } or nil
    end

    local acc = session.accumulatedRewards
    local hasAny = false
    for _ in pairs(acc) do hasAny = true; break end

    if not hasAny then
        return UI.Panel { width = 0, height = 0 }
    end

    local items = {}
    for currencyId, amount in pairs(acc) do
        local info = Currency.GetInfo(currencyId)
        local name = info and info.name or currencyId
        items[#items + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            marginRight = 8,
            children = {
                Currency.IconWidget(UI, currencyId, 12),
                UI.Label {
                    text = name .. " ×" .. amount,
                    fontSize = 10,
                    fontColor = { 200, 195, 170, 220 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 25, 22, 10, 200 },
        borderRadius = 8,
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        gap = 4,
        borderWidth = 1,
        borderColor = { 100, 80, 30, 100 },
        children = {
            UI.Label {
                text = "📦 已累积奖励:",
                fontSize = 11,
                fontColor = { 200, 180, 80, 240 },
                fontWeight = "bold",
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 4,
                children = items,
            },
        },
    }
end

-- ============================================================================
-- 战斗流程
-- ============================================================================

--- 进入战斗
function MineDungeon._EnterBattle(encounter)
    local session = MDD.GetSession()
    if not session then return end

    local floor = encounter.floor
    local config = MDD.BuildBattleConfig(floor, encounter)

    local GameUI = require("Game.GameUI")

    -- 隐藏探索 overlay（战斗中不显示）
    if exploreOverlay then
        exploreOverlay:SetVisible(false)
    end

    -- 隐藏限时活动 overlay
    GameUI.ShowWeeklyActivityOverlay(false)

    config.onWin = function()
        -- 战斗胜利：收集奖励，回到探索流程
        MDD.CollectRewards(encounter)

        local root = GameUI.GetUIRoot()
        if root and _UI then
            RewardController.ShowFromDefs(_UI, root, encounter.rewards,
                "第" .. floor .. "层 胜利", function()
                    -- 恢复探索 overlay
                    if exploreOverlay then
                        exploreOverlay:SetVisible(true)
                    end
                    GameUI.ExitDungeonBattle()
                    MineDungeon._ShowPostCollect(encounter)
                end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    config.onLose = function()
        -- 战斗失败：标记失败，50% 奖励结算
        MDD.MarkBattleFailed()

        local endResult = MDD.EndSession("fail")

        local root = GameUI.GetUIRoot()
        if root and _UI then
            local title = "第" .. floor .. "层 战斗失败 (奖励×" .. math.floor(MDD.FAIL_REWARD_RATIO * 100) .. "%)"
            RewardController.ShowFromDefs(_UI, root, endResult.rewardDefs, title, function()
                MineDungeon._CleanupOverlay()
                GameUI.ExitDungeonBattle()
            end)
        else
            MineDungeon._CleanupOverlay()
            GameUI.ExitDungeonBattle()
        end
    end

    config.onExit = function(result, continueExit)
        -- 主动退出战斗：按当前累积发放
        local endResult = MDD.EndSession("exit")

        local root = GameUI.GetUIRoot()
        if root and _UI then
            local title = "矿洞寻宝 · 撤退 (第" .. floor .. "层)"
            RewardController.ShowFromDefs(_UI, root, endResult.rewardDefs, title, function()
                MineDungeon._CleanupOverlay()
                continueExit()
            end)
        else
            MineDungeon._CleanupOverlay()
            continueExit()
        end
    end

    GameUI.EnterDungeonBattle(config)
end

-- ============================================================================
-- 确认撤退弹窗
-- ============================================================================

function MineDungeon._ConfirmExit()
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local session = MDD.GetSession()
    if not session then return end

    -- 简易确认弹窗（overlay 内弹层）
    local confirmPanel = nil

    local function dismiss()
        if confirmPanel then
            confirmPanel:Remove()
            confirmPanel = nil
        end
    end

    confirmPanel = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 900,
        pointerEvents = "auto",
        onClick = function() dismiss() end,
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 320,
                backgroundColor = { 35, 30, 15, 250 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 200, 160, 60, 200 },
                paddingTop = 20, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                gap = 12,
                pointerEvents = "auto",
                onClick = function() end, -- 阻止冒泡
                children = {
                    UI.Label {
                        text = "确认撤退？",
                        fontSize = 16,
                        fontColor = { 255, 200, 80, 255 },
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "撤退将结算当前已累积的全部奖励",
                        fontSize = 12,
                        fontColor = { 200, 190, 160, 220 },
                        textAlign = "center",
                    },
                    MineDungeon._BuildAccumulatedSummary(),
                    UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 10,
                        children = {
                            UI.Button {
                                text = "继续探索",
                                fontSize = 13,
                                flexGrow = 1,
                                height = 38,
                                borderRadius = 8,
                                variant = "outline",
                                onClick = function() dismiss() end,
                            },
                            UI.Button {
                                text = "确认撤退",
                                fontSize = 13,
                                flexGrow = 1,
                                height = 38,
                                borderRadius = 8,
                                variant = "primary",
                                onClick = function()
                                    dismiss()
                                    MineDungeon._FinishExploration("exit")
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    exploreOverlay:AddChild(confirmPanel)
end

-- ============================================================================
-- 探索结束
-- ============================================================================

--- 结束探索（通关/撤退）
function MineDungeon._FinishExploration(reason)
    local endResult = MDD.EndSession(reason)

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()

    if root and _UI and endResult.rewardDefs and #endResult.rewardDefs > 0 then
        local title = reason == "clear"
            and ("矿洞寻宝 · 全部通关！(第" .. endResult.reachedFloor .. "层)")
            or  ("矿洞寻宝 · 撤退 (第" .. endResult.reachedFloor .. "层)")
        if reason == "fail" then
            title = "矿洞寻宝 · 失败 (奖励×" .. math.floor(endResult.ratio * 100) .. "%)"
        end

        RewardController.ShowFromDefs(_UI, root, endResult.rewardDefs, title, function()
            MineDungeon._CleanupOverlay()
        end)
    else
        MineDungeon._CleanupOverlay()
    end
end

--- 清理探索 overlay
function MineDungeon._CleanupOverlay()
    if exploreOverlay then
        exploreOverlay:Remove()
        exploreOverlay = nil
    end
end

return MineDungeon
