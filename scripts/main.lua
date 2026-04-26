-- ============================================================================
-- Dark Merge TD - 暗黑合成塔防
-- 入口文件：仅做全局事件绑定，逻辑分布在子模块
-- ============================================================================

local Bootstrap    = require("Game.Bootstrap")
local GameLoop     = require("Game.GameLoop")
local InputHandler = require("Game.InputHandler")

-- ============================================================================
-- 生命周期（引擎回调，必须全局函数）
-- ============================================================================

function Start()
    Bootstrap.Start()
end

function Stop()
    Bootstrap.Stop()
end

-- ============================================================================
-- 帧更新 & 渲染（引擎回调）
-- ============================================================================

function HandleUpdate(eventType, eventData)
    GameLoop.HandleUpdate(eventType, eventData)
end

function HandleNanoVGRender(eventType, eventData)
    GameLoop.HandleNanoVGRender(eventType, eventData)
end

function HandleToastRender(eventType, eventData)
    GameLoop.HandleToastRender(eventType, eventData)
end

-- ============================================================================
-- 输入事件（引擎回调）
-- ============================================================================

function HandleKeyDown(eventType, eventData)
    Bootstrap.HandleKeyDown(eventType, eventData)
end

function HandleScreenMode(eventType, eventData)
    Bootstrap.HandleScreenMode(eventType, eventData)
end

function HandleMouseDown(eventType, eventData)
    InputHandler.HandleMouseDown(eventType, eventData)
end

function HandleMouseMove(eventType, eventData)
    InputHandler.HandleMouseMove(eventType, eventData)
end

function HandleMouseUp(eventType, eventData)
    InputHandler.HandleMouseUp(eventType, eventData)
end

function HandleTouchBegin(eventType, eventData)
    InputHandler.HandleTouchBegin(eventType, eventData)
end

function HandleTouchMove(eventType, eventData)
    InputHandler.HandleTouchMove(eventType, eventData)
end

function HandleTouchEnd(eventType, eventData)
    InputHandler.HandleTouchEnd(eventType, eventData)
end
