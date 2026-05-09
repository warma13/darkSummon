-- Game/GameVersion.lua
-- 版本检测：通过排行榜存储版本号之和，比对是否为最新版本
local M = {}

local VERSION_STRING = "v1.1.4"
local LB_KEY = "lb_version"

-- 新版本检测状态
local _hasNewVersion = false
local _checkTimer = 0
local CHECK_INTERVAL = 600  -- 每 10 分钟静默检测一次
local _firstCheckDone = false

--- 解析版本号，按层级加权计算
--- major × 10000 + minor × 100 + patch
--- "v1.0.75" → 1×10000 + 0×100 + 75 = 10075
---@return number
function M.GetVersionSum()
    local s = VERSION_STRING:gsub("^v", "")
    local parts = {}
    for part in s:gmatch("[^%.]+") do
        parts[#parts + 1] = tonumber(part) or 0
    end
    local major = parts[1] or 0
    local minor = parts[2] or 0
    local patch = parts[3] or 0
    return major * 10000 + minor * 100 + patch
end

--- 获取版本字符串
function M.GetVersionString()
    return VERSION_STRING
end

--- 检测版本并上报
---@param closeModal function|nil 关闭设置弹窗的回调
function M.CheckAndReport(closeModal)
    local Toast = require("Game.Toast")
    local mySum = M.GetVersionSum()

    Toast.Show("正在检测版本...")

    clientCloud:GetRankList(LB_KEY, 0, 1, {
        ok = function(rankList)
            local topScore = 0
            if #rankList > 0 then
                topScore = (rankList[1].iscore and rankList[1].iscore[LB_KEY]) or 0
            end

            if mySum >= topScore then
                -- 当前版本 >= 排行榜最高，上传并提示最新
                clientCloud:SetInt(LB_KEY, mySum)
                _hasNewVersion = false
                Toast.Show("当前已是最新版本 " .. VERSION_STRING)
            else
                -- 当前版本落后，不上传，提示更新
                _hasNewVersion = true
                Toast.Show("当前不是最新版本，请点右上角三个点，然后点下面的重新开始更新版本")
            end
            M._notifyUI()
        end,
        error = function(code, reason)
            Toast.Show("版本检测失败: " .. tostring(reason))
        end,
    })
end

--- 是否检测到新版本
---@return boolean
function M.HasNewVersion()
    return _hasNewVersion
end

--- 静默检测（不弹 Toast，仅更新标记）
function M.CheckSilent()
    local mySum = M.GetVersionSum()
    clientCloud:GetRankList(LB_KEY, 0, 1, {
        ok = function(rankList)
            local topScore = 0
            if #rankList > 0 then
                topScore = (rankList[1].iscore and rankList[1].iscore[LB_KEY]) or 0
            end
            if mySum >= topScore then
                clientCloud:SetInt(LB_KEY, mySum)
                _hasNewVersion = false
            else
                _hasNewVersion = true
            end
            -- 通知 UI 刷新红点
            M._notifyUI()
        end,
        error = function()
            -- 检测失败不改变状态
        end,
    })
end

--- 每帧调用的定时检测（由 GameUI.Update 驱动）
---@param dt number
function M.Update(dt)
    -- 首次延迟 5 秒后检测
    if not _firstCheckDone then
        _checkTimer = _checkTimer + dt
        if _checkTimer >= 5 then
            _firstCheckDone = true
            _checkTimer = 0
            M.CheckSilent()
        end
        return
    end
    -- 之后按 CHECK_INTERVAL 定时检测
    _checkTimer = _checkTimer + dt
    if _checkTimer >= CHECK_INTERVAL then
        _checkTimer = 0
        M.CheckSilent()
    end
end

--- UI 刷新回调（由 Widgets 注册）
M._notifyUI = function() end

return M
