-- Game/GameUI/Stage.lua
-- 关卡流程：自动合并、波次就绪、游戏结束、通关结算、菜单

return function(GameUI, ctx)

local Config   = require("Game.Config")
local State    = require("Game.State")
local Tower    = require("Game.Tower")
local Grid     = require("Game.Grid")
local Wave     = require("Game.Wave")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local ChestData = require("Game.ChestData")

local CS = require("Game.CampaignSettlement")
local AudioManager = require("Game.AudioManager")
local Renderer = require("Game.Renderer")
local IdleScreen = require("Game.IdleScreen")
local FormatNum = ctx.FormatNum

function GameUI.AutoMerge()
    local merged = false

    -- 检查棋盘是否已满（所有非路径格都有塔）
    local totalSlots = 0
    for c = 1, Config.GRID_COLS do
        for r = 1, Config.GRID_ROWS do
            if not Grid.IsPathCell(c, r) then
                totalSlots = totalSlots + 1
            end
        end
    end
    local boardFull = (#State.towers >= totalSlots)

    -- 找到场上攻击力最高的英雄（最高输出）
    local topAtk = 0
    local topTypeIndex, topStar = nil, nil
    for _, t in ipairs(State.towers) do
        if t.attack > topAtk then
            topAtk = t.attack
            topTypeIndex = t.typeIndex
            topStar = t.star
        end
    end

    -- 统计最高输出英雄的同类型同星级数量
    local topCount = 0
    if topTypeIndex then
        for _, t in ipairs(State.towers) do
            if t.typeIndex == topTypeIndex and t.star == topStar then
                topCount = topCount + 1
            end
        end
    end

    -- 从低星开始找第一个可合成的配对
    for star = 1, Config.MAX_STAR - 1 do
        for i = 1, #State.towers do
            local t1 = State.towers[i]
            if t1 and t1.star == star and t1.star < Config.MAX_STAR then
                -- 如果这对是最高输出英雄，检查保护条件
                local isTopOutput = (t1.typeIndex == topTypeIndex and t1.star == topStar)
                if isTopOutput and topCount < 3 and not boardFull then
                    -- 跳过：保留最高输出，除非有3个以上或棋盘满
                else
                    for j = i + 1, #State.towers do
                        local t2 = State.towers[j]
                        if t2 and t2.typeIndex == t1.typeIndex and t2.star == t1.star then
                            if Tower.CanMerge(t1, t2) then
                                local result = Tower.Merge(t1, t2)
                                if result then
                                    merged = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
            if merged then break end
        end
        if merged then break end
    end
    if not merged then
        print("[UI] No mergeable pair found")
    end
    GameUI.UpdateHUD()
end

--- 波次准备面板
function GameUI.CreateWaveReadyPanel()
    return ctx.UI.Panel {
        id = "waveReadyPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            ctx.UI.Panel {
                padding = 24,
                gap = 12,
                backgroundColor = { 20, 16, 32, 230 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 70, 160, 150 },
                alignItems = "center",
                pointerEvents = "auto",
                children = {
                    ctx.UI.Label {
                        id = "nextWaveLabel",
                        text = "准备下一波",
                        fontSize = 18,
                        fontColor = Config.COLORS.textPrimary,
                    },
                    ctx.UI.Button {
                        text = "开始波次",
                        variant = "primary",
                        fontSize = 16,
                        onClick = function(self)
                            Wave.StartNext()
                            State.SetPhase(State.PHASE_PLAYING, "UI.waveReadyBtn")
                            GameUI.ShowPanel("waveReadyPanel", false)
                            GameUI.UpdateHUD()
                        end,
                    },
                }
            }
        }
    }
end

--- 失败面板（无奖励）
function GameUI.CreateGameOverPanel()
    return ctx.UI.Panel {
        id = "gameOverPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        children = {
            ctx.UI.Panel {
                width = 260,
                paddingTop = 24, paddingBottom = 24,
                paddingLeft = 20, paddingRight = 20,
                gap = 12,
                backgroundColor = { 30, 20, 45, 245 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 200, 50, 50, 200 },
                alignItems = "center",
                children = {
                    ctx.UI.Label {
                        text = "挑战失败",
                        fontSize = 26,
                        fontColor = { 220, 50, 50, 255 },
                    },
                    ctx.UI.Label {
                        id = "failStageLabel",
                        text = "第1关",
                        fontSize = 16,
                        fontColor = Config.COLORS.textSecondary,
                    },
                    ctx.UI.Label {
                        id = "failWaveLabel",
                        text = "进度: 0/20",
                        fontSize = 14,
                        fontColor = Config.COLORS.textSecondary,
                    },
                    -- 提示
                    ctx.UI.Label {
                        text = "通关才有奖励，提升英雄再来!",
                        fontSize = 12,
                        fontColor = { 180, 140, 100, 200 },
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 2, marginBottom = 2,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    ctx.UI.Button {
                        text = "重新挑战",
                        variant = "primary",
                        fontSize = 16,
                        onClick = function(self)
                            GameUI.RetryStage()
                        end,
                    },
                }
            }
        }
    }
end

--- 通关结算面板（有奖励）
function GameUI.CreateStageClearPanel()
    return ctx.UI.Panel {
        id = "stageClearPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        children = {
            ctx.UI.Panel {
                width = 280,
                paddingTop = 24, paddingBottom = 24,
                paddingLeft = 20, paddingRight = 20,
                gap = 10,
                backgroundColor = { 20, 25, 50, 245 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 255, 200, 50, 200 },
                alignItems = "center",
                children = {
                    ctx.UI.Label {
                        id = "clearTitleLabel",
                        text = "通关!",
                        fontSize = 28,
                        fontColor = Config.COLORS.textGold,
                    },
                    ctx.UI.Label {
                        id = "clearStageLabel",
                        text = "第1关",
                        fontSize = 16,
                        fontColor = Config.COLORS.textPrimary,
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 4, marginBottom = 4,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    ctx.UI.Label {
                        text = "通关奖励",
                        fontSize = 16,
                        fontColor = { 180, 160, 220, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearGoldLabel",
                        text = "冥晶: +0",
                        fontSize = 14,
                        fontColor = { 255, 215, 0, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearDiamondLabel",
                        text = "暗影精华: +0",
                        fontSize = 14,
                        fontColor = { 100, 200, 255, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearTokenLabel",
                        text = "虚空契约: +0",
                        fontSize = 14,
                        fontColor = { 200, 180, 100, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearFragLabel",
                        text = "碎片: +0",
                        fontSize = 14,
                        fontColor = { 180, 120, 255, 255 },
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 4, marginBottom = 4,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    ctx.UI.Button {
                        text = "下一关",
                        variant = "primary",
                        fontSize = 16,
                        onClick = function(self)
                            GameUI.NextStage()
                        end,
                    },
                }
            }
        }
    }
end

--- 设置按钮 + 弹窗（手动保存、返回区服选择、兑换码）
-- 注意：齿轮按钮已移至 CreateHUD() 内部，此处仅保留空容器供兼容调用
function GameUI.CreateMenuPanel()
    return ctx.UI.Panel {
        id = "menuPanel",
        pointerEvents = "none",
    }
end

local RedeemSystem = require("Game.RedeemSystem")

--- 显示设置弹窗
function GameUI.ShowSettingsPopup()
    if not ctx.uiRoot or not ctx.UI then return end

    local old = ctx.uiRoot:FindById("settingsModal")
    if old then ctx.uiRoot:RemoveChild(old) end

    local SlotSave = require("Game.SlotSaveSystem")
    local Toast    = require("Game.Toast")

    local function closeModal()
        local m = ctx.uiRoot and ctx.uiRoot:FindById("settingsModal")
        if m then ctx.uiRoot:RemoveChild(m) end
    end

    -- 兑换码输入值
    local redeemInput = ""

    local function tryRedeem()
        if RedeemSystem.TryRedeem(redeemInput) then
            closeModal()
        end
    end

    local modal = ctx.UI.Panel {
        id = "settingsModal",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        zIndex = 50,
        onClick = function(self) closeModal() end,
        children = {
            ctx.UI.Panel {
                width = 300,
                backgroundColor = { 20, 14, 40, 250 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 160, 120, 255, 160 },
                paddingTop = 18, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                gap = 14,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,
                children = {
                    -- 标题
                    ctx.UI.Label {
                        text = "设置",
                        fontSize = 20,
                        fontColor = { 200, 170, 255, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 60 } },

                    -- 音乐音量
                    ctx.UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            ctx.UI.Label {
                                text = "音乐音量",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Slider {
                                value = math.floor(AudioManager.GetBGMVolume() * 100),
                                min = 0, max = 100,
                                width = "100%",
                                height = 28,
                                onChange = function(self, v)
                                    AudioManager.SetBGMVolume(v / 100)
                                end,
                            },
                        },
                    },
                    -- 音效音量
                    ctx.UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            ctx.UI.Label {
                                text = "音效音量",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Slider {
                                value = math.floor(AudioManager.GetSFXVolume() * 100),
                                min = 0, max = 100,
                                width = "100%",
                                height = 28,
                                onChange = function(self, v)
                                    AudioManager.SetSFXVolume(v / 100)
                                end,
                            },
                        },
                    },

                    -- 背景遮罩透明度
                    ctx.UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            ctx.UI.Label {
                                text = "背景遮罩",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Slider {
                                value = math.floor(Renderer.bgOverlayAlpha / 255 * 100),
                                min = 0, max = 100,
                                width = "100%",
                                height = 28,
                                onChange = function(self, v)
                                    Renderer.SetBgOverlayAlpha(math.floor(v / 100 * 255))
                                end,
                            },
                        },
                    },

                    -- 增减益标签显示
                    ctx.UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            ctx.UI.Label {
                                text = "增减益标签",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Toggle {
                                value = Renderer.showBuffDebuffLabels,
                                trackWidth = 42,
                                trackHeight = 24,
                                thumbSize = 20,
                                onChange = function(self, v)
                                    Renderer.SetShowBuffDebuffLabels(v)
                                end,
                            },
                        },
                    },

                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 手动保存
                    ctx.UI.Button {
                        text = "手动保存",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            if SlotSave.GetActiveSlot() > 0 then
                                SlotSave.SaveNow()
                                Toast.Show("存档已保存")
                            else
                                Toast.Show("当前无活跃存档")
                            end
                        end,
                    },
                    -- 返回区服选择
                    ctx.UI.Button {
                        text = "返回区服选择",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            closeModal()
                            GameUI.ReturnToServerSelect()
                        end,
                    },
                    -- 待机模式
                    ctx.UI.Button {
                        text = "待机模式",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            closeModal()
                            IdleScreen.Show()
                        end,
                    },
                    -- 检测新版本
                    ctx.UI.Button {
                        text = "检测新版本",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            local GameVersion = require("Game.GameVersion")
                            GameVersion.CheckAndReport(closeModal)
                        end,
                    },

                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 兑换码区域
                    ctx.UI.Label {
                        text = "[ 兑换码 ]",
                        fontSize = 15,
                        fontColor = { 255, 200, 60, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            ctx.UI.TextField {
                                id = "redeemCodeInput",
                                value = "",
                                placeholder = "请输入兑换码",
                                fontSize = 14,
                                fontColor = { 255, 255, 255, 255 },
                                textAlign = "center",
                                maxLength = 20,
                                flex = 1,
                                height = 40,
                                backgroundColor = { 35, 28, 55, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 100, 80, 160, 180 },
                                onChange = function(self, value)
                                    redeemInput = value or ""
                                end,
                                onSubmit = function(self, value)
                                    redeemInput = value or ""
                                    tryRedeem()
                                end,
                            },
                            ctx.UI.Panel {
                                width = 64, height = 40,
                                borderRadius = 8,
                                backgroundColor = { 120, 70, 220, 255 },
                                justifyContent = "center",
                                alignItems = "center",
                                pointerEvents = "auto",
                                onClick = function(self)
                                    tryRedeem()
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "兑换",
                                        fontSize = 14,
                                        fontColor = { 255, 255, 255, 255 },
                                    },
                                },
                            },
                        },
                    },

                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 关闭按钮
                    ctx.UI.Panel {
                        width = 140, height = 38,
                        backgroundColor = { 80, 50, 130, 200 },
                        borderRadius = 19,
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self) closeModal() end,
                        children = {
                            ctx.UI.Label {
                                text = "关闭",
                                fontSize = 14,
                                fontColor = { 220, 210, 240, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    ctx.uiRoot:AddChild(modal)
end

--- 显示/隐藏面板
function GameUI.ShowPanel(panelId, visible)
    if not ctx.uiRoot then return end
    local panel = ctx.uiRoot:FindById(panelId)
    if panel then
        panel:SetVisible(visible)
    end
end

--- 隐藏所有弹出面板
local function HideAllPanels()
    GameUI.ShowPanel("gameOverPanel", false)
    GameUI.ShowPanel("stageClearPanel", false)
    GameUI.ShowPanel("idleRewardPanel", false)
    GameUI.ShowPanel("waveReadyPanel", false)
    -- menuPanel（设置按钮）始终可见，不在此隐藏
end

--- 开始一个关卡（通过 BattleManager.Enter 统一启动）
local function StartStage(stageNum)
    HideAllPanels()
    local BM = require("Game.BattleManager")
    BM.Enter("campaign", {
        stageNum = stageNum,
        onWin    = function() GameUI.DoStageClear() end,
        onLose   = function() GameUI.DoGameOver() end,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
    })
    print("[GameUI] Starting stage " .. stageNum)
end

--- 重新挑战当前关（失败后调用）
function GameUI.RetryStage()
    StartStage(State.currentStage)
end

--- 重新开始游戏（从第1关开始，兼容旧调用）
function GameUI.RestartGame()
    StartStage(1)
end

--- 进入下一关（通关后调用）
function GameUI.NextStage()
    StartStage(State.currentStage + 1)
end

--- 通关结算：委托 CampaignSettlement 处理奖励与任务追踪，然后进入下一关
function GameUI.DoStageClear()
    CS.SettleStageClear(State.currentStage, State.score)
    GameUI.NextStage()
end

--- 自动召唤：用光所有金币填满格子
local function AutoSummonAll()
    local count = 0
    while true do
        local canSummon = Tower.CanSummon()
        if not canSummon then break end
        local t = Tower.Summon()
        if not t then break end
        count = count + 1
    end
    print("[GameUI] Auto-summoned " .. count .. " towers")
    return count
end

--- 自动合成：循环合成直到无法继续（从低星开始）
local function AutoMergeAll()
    local totalMerged = 0
    local merged = true
    while merged do
        merged = false
        for star = 1, Config.MAX_STAR - 1 do
            for i = 1, #State.towers do
                local t1 = State.towers[i]
                if t1 and t1.star == star and t1.star < Config.MAX_STAR then
                    for j = i + 1, #State.towers do
                        local t2 = State.towers[j]
                        if t2 and t2.typeIndex == t1.typeIndex and t2.star == t1.star then
                            if Tower.CanMerge(t1, t2) then
                                local result = Tower.Merge(t1, t2)
                                if result then
                                    totalMerged = totalMerged + 1
                                    merged = true
                                    break
                                end
                            end
                        end
                    end
                end
                if merged then break end
            end
            if merged then break end
        end
    end
    print("[GameUI] Auto-merged " .. totalMerged .. " pairs")
    return totalMerged
end

--- 失败处理：委托 CampaignSettlement 记录任务进度，然后重新开始当前关卡
function GameUI.DoGameOver()
    local failedStage = State.currentStage
    CS.SettleGameOver(failedStage, State.currentWave)
    StartStage(failedStage)
end


end
