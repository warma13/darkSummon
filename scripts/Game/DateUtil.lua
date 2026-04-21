--- 日期工具模块
--- 消除项目中 15+ 处重复的 TodayStr 函数定义
local M = {}

--- 返回今天的日期字符串，连字符格式 "YYYY-MM-DD"
---@return string
function M.TodayStr()
    return os.date("%Y-%m-%d")
end

--- 返回今天的日期键，紧凑格式 "YYYYMMDD"
---@return string
function M.TodayKey()
    return os.date("%Y%m%d")
end

--- 返回昨天的日期字符串，连字符格式 "YYYY-MM-DD"
---@return string
function M.YesterdayStr()
    return os.date("%Y-%m-%d", os.time() - 86400)
end

return M
