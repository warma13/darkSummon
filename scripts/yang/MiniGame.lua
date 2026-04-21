-- ============================================================================
-- yang/MiniGame.lua  ·  羊了个羊 · 小游戏封装模块
-- ============================================================================
--
-- 【快速接入】
--
--   local MiniGame = require "yang.MiniGame"
--
--   -- ① 启动
--   MiniGame.start({
--       startLvl = 1,          -- 可选，从第几关开始（默认 1）
--       onDone = function(result)
--           -- result = "win"   全部关卡通关
--           -- result = "exit"  玩家按 ESC 主动退出
--           -- 在此处恢复宿主游戏逻辑 ...
--       end,
--   })
--
--   -- ② 在宿主的 Update / 鼠标 / 键盘 处理函数首行加一句跳过即可
--   function HostUpdate(et, ed)
--       if MiniGame.isActive() then return end
--       -- ... 宿主逻辑 ...
--   end
--
--   -- ③ 强制退出（不触发 onDone）
--   MiniGame.stop()
--
-- 【原理说明】
--   · NanoVG 使用独立 context（nvgCreate），与宿主渲染完全隔离。
--   · Update / MouseButtonDown / KeyDown 与宿主共用事件总线；
--     mini-game 内部通过 active_ 标志快速跳过，宿主通过 isActive() 让路。
--   · 全局事件只订阅一次（require 时），vg 事件随 start/stop 订阅/取消。
-- ============================================================================

local Board        = require "yang.Board"
local Renderer     = require "yang.Renderer"
local AudioManager = require "Game.AudioManager"

local M        = {}
local vg_      = nil
local LW_, LH_, DPR_
local onDone_  = nil
local active_  = false
local bgmNode_ = nil
local bgmSrc_  = nil

-- ── 全局事件处理函数（引擎通过字符串名查找，必须为全局）────────────────────────

function _YangMG_Render(eventType, eventData)
    if not active_ then return end
    Renderer.render(vg_, LW_, LH_, DPR_)
end

function _YangMG_Update(eventType, eventData)
    if not active_ then return end
    Board.update(eventData["TimeStep"]:GetFloat())
end

function _YangMG_MouseDown(eventType, eventData)
    if not active_ then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / DPR_
    local my = eventData["Y"]:GetInt() / DPR_

    -- 菜单界面：点击按钮开始游戏
    if Board.state == "menu" then
        for _, btn in ipairs(Renderer.menuBtns) do
            if mx >= btn.x and mx <= btn.x + btn.w and
               my >= btn.y and my <= btn.y + btn.h then
                Board.newGame(btn.lvl)
                break
            end
        end
        return
    end

    -- 全关通关 → 通知宿主
    if Board.state == "win" then
        M.stop()
        if onDone_ then onDone_("win") end
        return
    end

    -- 失败 → 退回内部菜单，让玩家自行选择重试
    if Board.state == "lose" then
        Board.state = "menu"
        return
    end

    -- 动画期间封锁所有点击
    if Board.shuffleAnim or Board.undoAnim or #Board.moveAnims > 0 then return end

    -- 道具按钮
    local mob = Renderer.moveOutBtn
    if mob and mx >= mob.x and mx <= mob.x + mob.w
           and my >= mob.y and my <= mob.y + mob.h then
        Board.moveOutCards(); return
    end
    local ub = Renderer.undoBtn
    if ub and mx >= ub.x and mx <= ub.x + ub.w
          and my >= ub.y and my <= ub.y + ub.h then
        Board.undoCard(); return
    end
    local sb = Renderer.shuffleBtn
    if sb and mx >= sb.x and mx <= sb.x + sb.w
          and my >= sb.y and my <= sb.y + sb.h then
        Board.shuffleCards(); return
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

function _YangMG_KeyDown(eventType, eventData)
    if not active_ then return end
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        if Board.state == "menu" then
            -- 菜单界面按 ESC → 退出小游戏
            M.stop()
            if onDone_ then onDone_("exit") end
        else
            -- 游戏中按 ESC → 回到内部菜单
            Board.state = "menu"
        end
    elseif key == KEY_R then
        if Board.state == "playing" or Board.state == "lose" then
            Board.newGame(Board.curLvl)
        end
    end
end

-- ── 一次性订阅全局事件（require 时执行，避免重复注册）────────────────────────
-- NanoVGRender 依赖 vg context，在 start/stop 里动态管理。

SubscribeToEvent("Update",          "_YangMG_Update")
SubscribeToEvent("MouseButtonDown", "_YangMG_MouseDown")
SubscribeToEvent("KeyDown",         "_YangMG_KeyDown")

-- ── 公开接口 ──────────────────────────────────────────────────────────────────

--- 查询小游戏是否正在运行（宿主在自己的事件处理函数里调用）
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

    local g = GetGraphics()
    DPR_    = g:GetDPR()
    LW_     = g:GetWidth()  / DPR_
    LH_     = g:GetHeight() / DPR_

    Board.setScreen(LW_, LH_)
    Board.init()
    math.randomseed(os.time())

    vg_ = nvgCreate(1)
    Renderer.init(vg_)
    Board.newGame(opts.startLvl or 1)

    -- 用 vg 作为 sender，保证只渲染自己的 context
    SubscribeToEvent(vg_, "NanoVGRender", "_YangMG_Render")

    -- 停主游戏 BGM，播放暗黑消除 BGM
    AudioManager.StopBGM()
    local audioScene = AudioManager.GetScene()
    local bgmRes = cache:GetResource("Sound", "audio/dark_match_bgm.ogg")
    if bgmRes and audioScene then
        bgmRes.looped = true
        bgmNode_ = audioScene:CreateChild("YangBGM")
        bgmSrc_ = bgmNode_:CreateComponent("SoundSource")
        bgmSrc_.soundType = SOUND_MUSIC
        bgmSrc_:Play(bgmRes)
        bgmSrc_.gain = 2.0
    end

    print("[YangMiniGame] 启动，从第" .. (opts.startLvl or 1) .. "关开始")
end

--- 强制退出小游戏，不触发 onDone
function M.stop()
    if not active_ then return end
    active_ = false
    if bgmSrc_ then
        bgmSrc_:Stop()
        bgmSrc_ = nil
    end
    if bgmNode_ then
        bgmNode_:Remove()
        bgmNode_ = nil
    end
    -- 恢复主游戏 BGM
    AudioManager.PlayBGM()
    if vg_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        Renderer.destroy(vg_)
        vg_ = nil
    end
    print("[YangMiniGame] 退出")
end

return M
