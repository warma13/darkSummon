-- Game/InputHandler.lua
-- 输入处理：拖拽系统 + 鼠标/触屏事件分发

local Config = require("Game.Config")
local State = require("Game.State")
local Grid = require("Game.Grid")
local Tower = require("Game.Tower")
local Renderer = require("Game.Renderer")
local MiniGameUI = require("Game.MiniGameUI")

local UI     -- 延迟注入

local InputHandler = {}

-- ============================================================================
-- 坐标转换
-- ============================================================================

--- 将屏幕坐标转为逻辑坐标
local function ScreenToLogical(rawX, rawY)
    local dpr = graphics:GetDPR()
    return rawX / dpr, rawY / dpr
end

-- ============================================================================
-- 拖拽系统
-- ============================================================================

--- 判定拖拽阈值（像素）
local DRAG_THRESHOLD = 10

--- 更新拖拽目标格子信息
local function UpdateDragTarget(x, y)
    local ox = Renderer.gridOffsetX
    local oy = Renderer.gridOffsetY
    State.dragX = x
    State.dragY = y
    local col, row = Grid.ScreenToCell(x, y, ox, oy)
    State.dragTargetCol = col
    State.dragTargetRow = row

    -- 判断目标是否有效（在网格内、非路径格、不是原位）
    if col < 1 or col > Config.GRID_COLS or row < 1 or row > Config.GRID_ROWS then
        State.dragValid = false
    elseif Grid.IsPathCell(col, row) then
        State.dragValid = false
    elseif col == State.dragOriginCol and row == State.dragOriginRow then
        State.dragValid = false
    else
        State.dragValid = true
    end
end

--- 按下开始拖拽
local function HandlePointerDown(x, y)
    -- 非战斗页禁用拖拽
    if State.activeTab ~= "battle" then return end

    if State.phase ~= State.PHASE_PLAYING and State.phase ~= State.PHASE_WAVE_READY then
        return
    end

    local ox = Renderer.gridOffsetX
    local oy = Renderer.gridOffsetY
    local col, row = Grid.ScreenToCell(x, y, ox, oy)

    -- 检查是否按在塔上
    if col >= 1 and col <= Config.GRID_COLS and row >= 1 and row <= Config.GRID_ROWS then
        local tower = State.grid[col][row]
        if tower then
            -- 记录按下，等移动超过阈值才真正开始拖拽
            State.dragging = false
            State.dragPending = true
            State.dragTower = tower
            State.dragOriginCol = col
            State.dragOriginRow = row
            State.dragStartX = x
            State.dragStartY = y
            State.dragX = x
            State.dragY = y
            State.dragTargetCol = col
            State.dragTargetRow = row
            State.dragValid = false
            return
        end
    end

    -- 点击空白区域取消选中
    State.selectedTower = nil
end

--- 移动更新拖拽位置
local function HandlePointerMove(x, y)
    if State.activeTab ~= "battle" then return end
    if not State.dragPending and not State.dragging then return end

    -- 检查是否超过拖拽阈值
    if State.dragPending and not State.dragging then
        local dx = x - (State.dragStartX or x)
        local dy = y - (State.dragStartY or y)
        if math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD then
            State.dragging = true
            State.dragPending = false
        else
            return
        end
    end

    UpdateDragTarget(x, y)
end

--- 释放结束拖拽
local function HandlePointerUp(x, y)
    if State.activeTab ~= "battle" then return end

    -- 点击（未拖动）→ 选中/取消选中英雄
    if State.dragPending and not State.dragging then
        if State.dragTower then
            -- 点击同一个英雄 → 取消选中；点击不同英雄 → 切换选中
            if State.selectedTower == State.dragTower then
                State.selectedTower = nil
            else
                State.selectedTower = State.dragTower
            end
        end
        State.dragPending = false
        State.dragTower = nil
        return
    end

    if not State.dragging then return end

    UpdateDragTarget(x, y)

    -- 执行拖拽操作
    if State.dragValid and State.dragTower then
        Tower.HandleDrop(State.dragTower, State.dragTargetCol, State.dragTargetRow)
    end

    -- 清除拖拽状态（拖拽结束不保留选中）
    State.dragging = false
    State.dragPending = false
    State.dragTower = nil
    State.selectedTower = nil
end

-- ============================================================================
-- 输入去重
-- ============================================================================

-- 移动端触屏会同时触发 Touch 和 Mouse 事件
-- 策略：一旦收到 touch 事件，永久屏蔽合成的 mouse 事件
local touchDetected = false

---@param source string "mouse" | "touch"
---@return boolean blocked 是否应被忽略
local function InputDedup(source)
    if source == "touch" then
        touchDetected = true
        return false
    end
    -- source == "mouse"：如果已检测到触摸设备，屏蔽所有鼠标事件
    return touchDetected
end

-- ============================================================================
-- 鼠标事件
-- ============================================================================

function InputHandler.HandleMouseDown(eventType, eventData)
    if MiniGameUI.isActive() then
        _YangMG_MouseDown(eventType, eventData)
        return
    end
    if UI.IsPointerOverUI() then return end
    if InputDedup("mouse") then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerDown(x, y)
end

function InputHandler.HandleMouseMove(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("mouse") then return end
    if not State.dragging and not State.dragPending then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerMove(x, y)
end

function InputHandler.HandleMouseUp(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("mouse") then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerUp(x, y)
end

-- ============================================================================
-- 触摸事件
-- ============================================================================

function InputHandler.HandleTouchBegin(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if UI.IsPointerOverUI() then return end
    if InputDedup("touch") then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerDown(x, y)
end

function InputHandler.HandleTouchMove(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("touch") then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerMove(x, y)
end

function InputHandler.HandleTouchEnd(eventType, eventData)
    if MiniGameUI.isActive() then return end
    if InputDedup("touch") then return end
    local x, y = ScreenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    HandlePointerUp(x, y)
end

--- 注入 UI 模块引用
function InputHandler.Init(uiModule)
    UI = uiModule
end

return InputHandler
