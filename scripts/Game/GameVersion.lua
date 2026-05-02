-- Game/GameVersion.lua
-- 版本检测：通过排行榜存储版本号之和，比对是否为最新版本
local M = {}

local VERSION_STRING = "v1.0.91"
local LB_KEY = "lb_version"

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
                Toast.Show("当前已是最新版本 " .. VERSION_STRING)
            else
                -- 当前版本落后，不上传，提示更新
                Toast.Show("当前不是最新版本，请点右上角三个点，然后点下面的重新开始更新版本")
            end
        end,
        error = function(code, reason)
            Toast.Show("版本检测失败: " .. tostring(reason))
        end,
    })
end

return M
