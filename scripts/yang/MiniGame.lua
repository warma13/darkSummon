-- ============================================================================
-- yang/MiniGame.lua  ·  羊了个羊 · 小游戏封装模块
-- ============================================================================
--
-- 【事件架构】
--   · NanoVG 使用独立 context（nvgCreate），与宿主渲染完全隔离。
--   · Update / Mouse / Touch / KeyDown 由宿主统一分发
--     （GameLoop / InputHandler / Bootstrap），本模块不独立订阅。
--   · start() 时调用 UI.SetEnabled(false) 冻结宿主 UI 事件通道，
--     stop() 时调用 UI.SetEnabled(true) 恢复，彻底阻断 UI 层穿透。
-- ============================================================================

local Board        = require "yang.Board"
local Renderer     = require "yang.Renderer"
local AudioManager = require "Game.AudioManager"
local AdHelper     = require "Game.AdHelper"
local UI           = require "urhox-libs/UI"
local Toast        = require "Game.Toast"

local _ok_ard, _ARD = pcall(require, "Game.AdReliefData")
if not _ok_ard then _ARD = nil end

--- 优先使用免广券（弹窗确认），没有券才看广告
---@param onSuccess fun()
local function useTicketOrAd(onSuccess)
    -- 1) 免广卡（当日看满20次自动激活）
    if _ARD and _ARD.IsAdFreeToday and _ARD.IsAdFreeToday() then
        Toast.Show("免广卡生效", { 100, 220, 180 })
        onSuccess()
        return
    end
    -- 2) 有免广券 → 弹窗让用户选择
    if _ARD and _ARD.GetTickets and _ARD.GetTickets() > 0 then
        Board.ticketConfirmCb   = onSuccess
        Board.showTicketConfirm = true
        return
    end
    -- 3) 没有券 → 直接看广告
    AdHelper.ShowRewardAd(onSuccess)
end

local M        = {}
local vg_      = nil
local LW_, LH_, DPR_
local onDone_  = nil
local active_  = false


-- ============================================================================
-- 全局事件处理函数（引擎通过字符串名查找，必须为全局）
-- ============================================================================

function _YangMG_Render(eventType, eventData)
    if not active_ then return end
    Renderer.render(vg_, LW_, LH_, DPR_)
end

function _YangMG_Update(eventType, eventData)
    if not active_ then return end
    Board.update(eventData["TimeStep"]:GetFloat())
end

--- 辅助：检测点击是否在按钮区域内
local function hitBtn(btn, mx, my)
    return btn and mx >= btn.x and mx <= btn.x + btn.w
               and my >= btn.y and my <= btn.y + btn.h
end

--- 鼠标/触摸按下（兼容两种事件：MouseButtonDown 有 Button 字段，TouchBegin 没有）
function _YangMG_MouseDown(eventType, eventData)
    if not active_ then return end
    -- 兼容鼠标事件(有Button字段)和触摸事件(无Button字段)
    local btnVar = eventData["Button"]
    if btnVar and btnVar:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / DPR_
    local my = eventData["Y"]:GetInt() / DPR_

    -- ── 免广券确认弹窗 ────────────────────────────────────────────────────────
    if Board.showTicketConfirm then
        if hitBtn(Renderer.ticketUseBtn, mx, my) then
            -- 使用免广券
            Board.showTicketConfirm = false
            local cb = Board.ticketConfirmCb
            Board.ticketConfirmCb = nil
            if cb and _ARD and _ARD.UseTicket then
                _ARD.UseTicket()
                Toast.Show("已使用免广券（剩余 " .. _ARD.GetTickets() .. "）", { 100, 220, 180 })
                cb()
            end
        elseif hitBtn(Renderer.ticketAdBtn, mx, my) then
            -- 选择看广告
            Board.showTicketConfirm = false
            local cb = Board.ticketConfirmCb
            Board.ticketConfirmCb = nil
            if cb then
                AdHelper.ShowRewardAd(cb)
            end
        end
        return
    end

    -- ── 确认弹窗最高优先级 ──────────────────────────────────────────────────
    if Board.showExitConfirm then
        if hitBtn(Renderer.confirmYesBtn, mx, my) then
            -- 确定 → 退出小游戏
            Board.showExitConfirm = false
            M.stop()
            if onDone_ then onDone_("exit") end
        elseif hitBtn(Renderer.confirmNoBtn, mx, my) then
            -- 取消
            Board.showExitConfirm = false
        end
        -- 弹窗显示期间吞掉所有点击
        return
    end

    -- ── 救场弹窗（失败时看广告获得移出道具）────────────────────────────────
    if Board.state == "lose" and Board.showRescueConfirm then
        if hitBtn(Renderer.rescueAdBtn, mx, my) then
            Board.showRescueConfirm = false
            useTicketOrAd(function()
                Board.moveOutAdUsed = true
                Board.moveOutUses = 1
                Board.moveOutCards()
            end)
        elseif hitBtn(Renderer.rescueGiveUpBtn, mx, my) then
            Board.showRescueConfirm = false
        end
        return
    end

    -- ── 通关/失败界面：响应 overlay 按钮 ────────────────────────────────────
    if Board.state == "win" or Board.state == "lose" then
        if hitBtn(Renderer.overlayRestartBtn, mx, my) then
            Board.newGame(1)
        elseif hitBtn(Renderer.overlayBackBtn, mx, my) then
            Board.showExitConfirm = true
        end
        return
    end

    -- ── HUD 返回按钮 ────────────────────────────────────────────────────────
    if hitBtn(Renderer.backBtn, mx, my) then
        Board.showExitConfirm = true
        return
    end

    -- 动画期间封锁所有点击
    if Board.shuffleAnim or Board.undoAnim or #Board.moveAnims > 0 then return end

    -- 道具按钮（看广告获得 1 次使用，每局每个道具限 1 次）
    -- 广告不可用时（如预览环境）也直接授予
    if hitBtn(Renderer.moveOutBtn, mx, my) then
        if Board.moveOutUses > 0 then
            Board.moveOutCards()
        elseif not Board.moveOutAdUsed then
            useTicketOrAd(function()
                Board.moveOutAdUsed = true
                Board.moveOutUses = 1
            end)
        end
        return
    end
    if hitBtn(Renderer.undoBtn, mx, my) then
        if Board.undoUses > 0 then
            Board.undoCard()
        elseif not Board.undoAdUsed then
            useTicketOrAd(function()
                Board.undoAdUsed = true
                Board.undoUses = 1
            end)
        end
        return
    end
    if hitBtn(Renderer.shuffleBtn, mx, my) then
        if Board.shuffleUses > 0 then
            Board.shuffleCards()
        elseif not Board.shuffleAdUsed then
            useTicketOrAd(function()
                Board.shuffleAdUsed = true
                Board.shuffleUses = 1
            end)
        end
        return
    end

    -- 暂存区顶牌
    for colIdx = 1, 3 do
        local col = Board.overflowCols[colIdx]
        if #col > 0 then
            local cx = Board.overflowColX(colIdx)
            local cy = Board.overflowCardY(#col)
            if mx >= cx and mx <= cx + Board.SLOT_CW and
               my >= cy and my <= cy + Board.SLOT_CH then
                Board.clickOverflowCard(colIdx); return
            end
        end
    end

    -- 牌区点击
    local card = Board.hitA(mx, my) or Board.hitB(mx, my)
    if card then Board.onCardClick(card) end
end

--- 鼠标/触摸移动（当前无拖拽需求，预留接口供宿主统一路由）
function _YangMG_MouseMove(eventType, eventData)
    if not active_ then return end
    -- 暂无拖拽逻辑，留空
end

--- 鼠标/触摸释放（当前无拖拽需求，预留接口供宿主统一路由）
function _YangMG_MouseUp(eventType, eventData)
    if not active_ then return end
    -- 暂无拖拽逻辑，留空
end

function _YangMG_KeyDown(eventType, eventData)
    if not active_ then return end
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        if Board.showExitConfirm then
            -- 弹窗中按 ESC → 关闭弹窗
            Board.showExitConfirm = false
        else
            -- 游戏中按 ESC → 弹出确认返回弹窗
            Board.showExitConfirm = true
        end
    elseif key == KEY_R then
        if not Board.showExitConfirm and
           (Board.state == "playing" or Board.state == "lose") then
            Board.newGame(Board.curLvl)
        end
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 查询小游戏是否正在运行
function M.isActive()
    return active_
end

--- 启动小游戏
--- @param opts table  { startLvl=1, onDone=function(result) }
function M.start(opts)
    if active_ then M.stop() end

    opts    = opts or {}
    onDone_ = opts.onDone
    active_ = true

    -- ★ 冻结宿主 UI 事件通道，阻止点击穿透到 UI 组件树
    UI.SetEnabled(false)

    local g = GetGraphics()
    DPR_    = g:GetDPR()
    LW_     = g:GetWidth()  / DPR_
    LH_     = g:GetHeight() / DPR_

    Board.setScreen(LW_, LH_)
    Board.init()
    math.randomseed(os.time())

    vg_ = nvgCreate(1)
    Renderer.init(vg_)
    Board.newGame(1)

    -- 用 vg 作为 sender，保证只渲染自己的 context
    SubscribeToEvent(vg_, "NanoVGRender", "_YangMG_Render")

    -- 切换到暗黑消除 BGM（通过 AudioManager 统一管理，自动循环）
    AudioManager.PlayBGM("dark_match")

    print("[YangMiniGame] 启动，显示菜单")
end

--- 强制退出小游戏，不触发 onDone
function M.stop()
    if not active_ then return end
    active_ = false

    -- ★ 恢复宿主 UI 事件通道
    UI.SetEnabled(true)

    -- 恢复主游戏 BGM（AudioManager 内部会先停当前 BGM）
    AudioManager.PlayBGM()
    if vg_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        Renderer.destroy(vg_)
        vg_ = nil
    end
    print("[YangMiniGame] 退出")
end

return M
