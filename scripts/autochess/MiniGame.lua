-- autochess/MiniGame.lua
-- 自走棋小游戏封装：独立 NanoVG 上下文、事件桥接
-- 接口模式与 yang/MiniGame.lua 一致

local Board    = require("autochess.Board")
local Renderer = require("autochess.Renderer")
local AudioManager = require("Game.AudioManager")
local UI       = require("urhox-libs/UI")

local M = {}

local vg_     = nil
local LW_, LH_, DPR_
local onDone_ = nil
local active_  = false

-- ============================================================================
-- 全局事件处理函数（引擎通过字符串名查找，必须为全局）
-- ============================================================================

function _AutoChessMG_Render(eventType, eventData)
    if not active_ then return end
    Renderer.Render(vg_, LW_, LH_, DPR_)
end

function _AutoChessMG_Update(eventType, eventData)
    if not active_ then return end
    local dt = eventData["TimeStep"]:GetFloat()
    Board.Update(dt)

    -- 拖拽中每帧轮询鼠标/触摸位置（MouseMove 事件在触屏上不可靠）
    if Renderer.IsDragging() then
        local mx = input:GetMousePosition().x / DPR_
        local my = input:GetMousePosition().y / DPR_
        Renderer.HandleMouseMove(mx, my)
    end

    -- 游戏结束检测
    if Board.phase == "gameover" or Board.phase == "win" then
        -- 不立即退出，等待玩家点击
    end
end

function _AutoChessMG_MouseDown(eventType, eventData)
    if not active_ then return end
    -- 兼容鼠标事件(有Button字段)和触摸事件(无Button字段)
    local btnVar = eventData["Button"]
    if btnVar and btnVar:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / DPR_
    local my = eventData["Y"]:GetInt() / DPR_

    Renderer.HandleMouseDown(mx, my)
end

function _AutoChessMG_MouseMove(eventType, eventData)
    if not active_ then return end
    local mx = eventData["X"]:GetInt() / DPR_
    local my = eventData["Y"]:GetInt() / DPR_

    Renderer.HandleMouseMove(mx, my)
end

function _AutoChessMG_MouseUp(eventType, eventData)
    if not active_ then return end
    -- Button 字段: 鼠标事件有,触摸事件可能无 → 仅当有且不是左键时忽略
    local btnVar = eventData["Button"]
    if btnVar and btnVar:GetInt() ~= MOUSEB_LEFT then return end
    -- 优先用事件坐标；若无则用 input 轮询
    local xVar = eventData["X"]
    local yVar = eventData["Y"]
    local mx, my
    if xVar and yVar then
        mx = xVar:GetInt() / DPR_
        my = yVar:GetInt() / DPR_
    else
        mx = input:GetMousePosition().x / DPR_
        my = input:GetMousePosition().y / DPR_
    end

    Renderer.HandleMouseUp(mx, my)
end

function _AutoChessMG_KeyDown(eventType, eventData)
    if not active_ then return end
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        M.stop()
        if onDone_ then onDone_("exit") end
    end
end

-- 全局事件路由说明：
-- Update / 鼠标 / 触摸 / KeyDown 均由宿主统一分发（GameLoop / InputHandler / Bootstrap），
-- 这里不再独立订阅，避免被覆盖或重复调用。

-- ============================================================================
-- 公开接口
-- ============================================================================

function M.isActive()
    return active_
end

function M.start(opts)
    if active_ then M.stop() end

    opts    = opts or {}
    onDone_ = opts.onDone
    active_ = true

    -- ★ 冻结宿主 UI 事件通道，阻止点击穿透到 UI 组件树
    UI.SetEnabled(false)

    local g = GetGraphics()
    DPR_ = g:GetDPR()
    LW_  = g:GetWidth()  / DPR_
    LH_  = g:GetHeight() / DPR_

    math.randomseed(os.time())

    vg_ = nvgCreate(1)
    Renderer.Init(vg_, LW_, LH_)

    Board.screenW = LW_
    Board.screenH = LH_
    Board.NewGame()

    SubscribeToEvent(vg_, "NanoVGRender", "_AutoChessMG_Render")

    AudioManager.StopBGM()
    print("[AutoChessMiniGame] 启动")
end

function M.stop()
    if not active_ then return end
    active_ = false

    -- ★ 恢复宿主 UI 事件通道
    UI.SetEnabled(true)

    AudioManager.PlayBGM()

    if vg_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        Renderer.Destroy(vg_)
        vg_ = nil
    end
    print("[AutoChessMiniGame] 退出")
end

--- 获取退出回调（给 Renderer 的结束按钮用）
function M.GetExitFn()
    return function(result)
        M.stop()
        if onDone_ then onDone_(result or "exit") end
    end
end

return M
