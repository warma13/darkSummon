-- Game/AdHelper.lua
-- 统一激励视频广告入口
-- 所有需要看广告的地方统一调用 AdHelper.ShowRewardAd(onSuccess)
-- 内部处理：免广告券检查 → SDK 可用性检查 → 播放广告 → 验证完成 → AdTracker 计数 → 回调

local AdTracker = require("Game.AdTracker")
local Toast     = require("Game.Toast")

local AdHelper = {}

--- 内部：实际播放广告的逻辑
---@param onSuccess fun()
---@param onFail? fun(reason:string)
local function _doShowAd(onSuccess, onFail)
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        local msg = "广告不可用"
        if onFail then
            onFail(msg)
        else
            Toast.Show(msg, { 255, 100, 80 })
        end
        return
    end

    ---@diagnostic disable-next-line: undefined-global
    sdk:ShowRewardVideoAd(function(result)
        if result and result.success then
            AdTracker.Record()
            if onSuccess then onSuccess() end
        else
            local msg = (result and result.msg) or "广告未完成"
            if msg == "embed manual close" then
                msg = "需完整观看广告才能获得奖励"
            end
            if onFail then
                onFail(msg)
            else
                Toast.Show(msg, { 200, 100, 100 })
            end
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
    -- 检查是否有免广告券
    local ok, ARD = pcall(require, "Game.AdReliefData")
    if ok and ARD and ARD.GetTickets() > 0 and AdHelper._showTicketConfirm then
        -- 弹窗让玩家选择：使用券 or 看广告
        AdHelper._showTicketConfirm(function(useTicket)
            if useTicket then
                -- 使用免广告券
                ARD.UseTicket()
                if onSuccess then onSuccess() end
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
