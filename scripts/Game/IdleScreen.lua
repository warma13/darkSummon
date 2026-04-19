-- Game/IdleScreen.lua
-- 待机模式：全屏背景图 + "战斗中..." 动画文字 + 左下角返回按钮

local UI = require("urhox-libs/UI")
local Enemy = require("Game.Enemy")
local State = require("Game.State")
local Config = require("Game.Config")
local BattleManager = require("Game.BattleManager")

local IdleScreen = {}

---@type any
local idleRoot = nil
---@type any
local dotLabel = nil
---@type any
local statusLabel = nil
local dotTimer = 0
local dotCount = 0
local active = false

--- 进入待机模式
function IdleScreen.Show()
    if active then return end
    active = true
    dotTimer = 0
    dotCount = 0

    -- 若已存在 UI 则先移除
    if idleRoot then
        local root = UI.GetRoot()
        if root then root:RemoveChild(idleRoot) end
        idleRoot = nil
        dotLabel = nil
    end

    local function onReturn()
        IdleScreen.Hide()
    end

    idleRoot = UI.Panel {
        id = "idleScreenRoot",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 999,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 255 },
        children = {
            -- 背景图（铺满）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "image/idle_bg_20260417032832.png",
                backgroundFit = "cover",
                opacity = 0.7,
            },

            -- 中央 "战斗中..." 文字 + 状态信息
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        paddingLeft = 30, paddingRight = 30,
                        paddingTop = 14, paddingBottom = 14,
                        borderRadius = 16,
                        backgroundColor = { 0, 0, 0, 140 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            (function()
                                dotLabel = UI.Label {
                                    text = "战斗中",
                                    fontSize = 28,
                                    fontColor = { 200, 180, 255, 255 },
                                    fontWeight = "bold",
                                }
                                return dotLabel
                            end)(),
                            (function()
                                statusLabel = UI.Label {
                                    text = "加载中...",
                                    fontSize = 14,
                                    fontColor = { 180, 170, 210, 200 },
                                    marginTop = 6,
                                }
                                return statusLabel
                            end)(),
                        },
                    },
                },
            },

            -- 左下角返回按钮
            UI.Panel {
                position = "absolute",
                bottom = 30, left = 20,
                pointerEvents = "auto",
                children = {
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 10, paddingBottom = 10,
                        borderRadius = 10,
                        backgroundColor = { 80, 50, 140, 220 },
                        borderWidth = 1,
                        borderColor = { 160, 120, 255, 180 },
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        onClick = function(self) onReturn() end,
                        children = {
                            UI.Label {
                                text = "< 返回游戏",
                                fontSize = 16,
                                fontColor = { 220, 210, 255, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    UI.GetRoot():AddChild(idleRoot)
end

--- 退出待机模式
function IdleScreen.Hide()
    if idleRoot then
        local root = UI.GetRoot()
        if root then
            root:RemoveChild(idleRoot)
        end
        idleRoot = nil
        dotLabel = nil
        statusLabel = nil
    end
    active = false
    -- 不调用 UnsubscribeFromEvent("Update")！
    -- 那会移除所有 Update 处理器（包括游戏核心循环）
    -- 改用 active 标志控制，handler 内 early-return
end

--- 是否正在待机
---@return boolean
function IdleScreen.IsActive()
    return active
end

--- 每帧更新（从主循环 HandleUpdate 中调用）
---@param dt number
function IdleScreen.Update(dt)
    if not active or not dotLabel then return end
    dotTimer = dotTimer + dt
    if dotTimer >= 0.5 then
        dotTimer = dotTimer - 0.5
        dotCount = (dotCount + 1) % 4  -- 0,1,2,3 循环
        local dots = string.rep(".", dotCount)
        dotLabel:SetText("战斗中" .. dots)
    end

    -- 更新怪物数 + 下一波倒计时
    if statusLabel then
        local count = Enemy.GetAliveCount()
        local max = (BattleManager.IsActive() and BattleManager.config.overloadLimit) or Config.MAX_ENEMIES
        local parts = { "怪物 " .. count .. "/" .. max }

        -- 下一波倒计时（非最后一波时显示）
        if State.phase == State.PHASE_PLAYING
           and State.currentWave < Config.WAVES_PER_STAGE then
            local remain = math.max(0, Config.WAVE_INTERVAL - State.waveTimer)
            local sec = math.ceil(remain)
            parts[#parts + 1] = "下一波 " .. sec .. "s"
        end

        statusLabel:SetText(table.concat(parts, "  |  "))
    end
end

return IdleScreen
