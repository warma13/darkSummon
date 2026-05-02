-- Game/AdHelper.lua
-- 统一激励视频广告入口
-- 所有需要看广告的地方统一调用 AdHelper.ShowRewardAd(onSuccess)
-- 内部处理：免广告券检查 → SDK 可用性检查 → 播放广告 → 验证完成 → AdTracker 计数 → 回调

local AdTracker = require("Game.AdTracker")
local Toast     = require("Game.Toast")
local TodayKey  = require("Game.DateUtil").TodayKey

local AdHelper = {}

-- ============================================================================
-- 云端广告行为上报（供管理员排行榜统计）
-- 永久 key: ad_total（累计总观看）
-- 每日 key: ad_start_YYYYMMDD / ad_done_YYYYMMDD / ad_cancel_YYYYMMDD
-- ============================================================================

--- 上报广告行为到云端排行榜（永久 + 每日）
---@param action string "ad_start" | "ad_done" | "ad_cancel"
local function _reportAdEvent(action)
    ---@diagnostic disable-next-line: undefined-global
    if not clientCloud then return end
    local dailyKey = action .. "_" .. TodayKey()
    clientCloud:BatchSet()
        :Add("ad_total", 1)     -- 永久累计
        :Add(dailyKey, 1)       -- 每日分类
        :Save("ad_event", {
            ok = function()
                print("[AdHelper] Reported " .. dailyKey .. " + ad_total")
            end,
            error = function(code, reason)
                print("[AdHelper] Report failed: " .. tostring(reason))
            end,
        })
end

--- 内部：实际播放广告的逻辑
---@param onSuccess fun()
---@param onFail? fun(reason:string)
local function _doShowAd(onSuccess, onFail)
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        local msg = "广告不可用"
        if onFail then
            pcall(onFail, msg)
        else
            pcall(Toast.Show, msg, { 255, 100, 80 })
        end
        return
    end

    -- 上报：开始播放广告
    pcall(_reportAdEvent, "ad_start")

    ---@diagnostic disable-next-line: undefined-global
    sdk:ShowRewardVideoAd(function(result)
        -- SDK 回调是异步的，触发时游戏状态可能已变化，全部 pcall 防闪退
        local cbOk, cbErr = pcall(function()
            if result and result.success then
                pcall(_reportAdEvent, "ad_done")
                pcall(AdTracker.Record)
                if onSuccess then
                    local ok, err = pcall(onSuccess)
                    if not ok then
                        print("[AdHelper] onSuccess callback error: " .. tostring(err))
                    end
                end
            else
                pcall(_reportAdEvent, "ad_cancel")
                local msg = (result and result.msg) or "广告未完成"
                if msg == "embed manual close" then
                    msg = "需完整观看广告才能获得奖励"
                end
                if onFail then
                    pcall(onFail, msg)
                else
                    pcall(Toast.Show, msg, { 200, 100, 100 })
                end
            end
        end)
        if not cbOk then
            print("[AdHelper] SDK callback crash prevented: " .. tostring(cbErr))
        end
    end)
end

--- 免广告券确认弹窗回调引用（由 GameUI 设置）
---@type fun(onConfirm:fun(useTicket:boolean))|nil
AdHelper._showTicketConfirm = nil

--- 设置免广告券确认弹窗回调（由 GameUI 初始化时调用）
---@param fn fun(onConfirm:fun(useTicket:boolean))
function AdHelper.SetTicketConfirmHandler(fn)
    AdHelper._showTicketConfirm = fn
end

--- 播放激励视频广告，仅在广告播放完成后才执行 onSuccess
--- 如果玩家拥有免广告券，会先弹窗询问是否使用
---@param onSuccess fun()        广告完整观看后的回调（发放奖励等）
---@param onFail?   fun(reason:string)  广告未完成/不可用时的回调（可选，默认弹 Toast）
function AdHelper.ShowRewardAd(onSuccess, onFail)
    -- 安全调用 onSuccess（广告回调期间 UI 可能已切换，pcall 防闪退）
    local function safeOnSuccess()
        if not onSuccess then return end
        local ok2, err2 = pcall(onSuccess)
        if not ok2 then
            print("[AdHelper] onSuccess callback error: " .. tostring(err2))
        end
    end

    -- 检查是否已激活免广卡（当日看满20次广告，免所有广告）
    local ok, ARD = pcall(require, "Game.AdReliefData")
    if ok and ARD and ARD.IsAdFreeToday() then
        Toast.Show("免广卡生效，已跳过广告", { 100, 220, 180 })
        pcall(AdTracker.Record)
        safeOnSuccess()
        return
    end

    -- 检查是否有免广告券
    if ok and ARD and ARD.GetTickets() > 0 and AdHelper._showTicketConfirm then
        -- 弹窗让玩家选择：使用券 or 看广告
        AdHelper._showTicketConfirm(function(useTicket)
            if useTicket then
                -- 使用免广告券（pcall 防闪退）
                local utOk, utErr = pcall(ARD.UseTicket)
                if not utOk then
                    print("[AdHelper] UseTicket error: " .. tostring(utErr))
                end
                safeOnSuccess()
            else
                -- 选择看广告
                _doShowAd(onSuccess, onFail)
            end
        end)
        return
    end

    -- 无券或无弹窗处理器，直接看广告
    _doShowAd(onSuccess, onFail)
end

return AdHelper
