--- 数字/时间格式化工具模块
--- 消除项目中多处重复的 FormatNumber / FormatNum 定义
local M = {}

--- 格式化大数字（中文"亿/万"后缀）
--- 统一 EquipUI / RewardDisplay / TemperUI / ActivityUI_Shared / GameUI / Panels 等
---@param n number
---@return string
function M.FormatNumber(n)
    if n >= 100000000000000000000 then
        return string.format("%.1f垓", n / 100000000000000000000)
    elseif n >= 10000000000000000 then
        return string.format("%.1f京", n / 10000000000000000)
    elseif n >= 1000000000000 then
        return string.format("%.1f兆", n / 1000000000000)
    elseif n >= 100000000 then
        return string.format("%.2f亿", n / 100000000)
    elseif n >= 10000 then
        return string.format("%.1f万", n / 10000)
    end
    return tostring(math.floor(n))
end

--- 紧凑格式化（1位小数，适合 HUD / 列表等空间紧凑场景）
---@param n number
---@return string
function M.FormatNum(n)
    if n >= 100000000000000000000 then return string.format("%.1f垓", n / 100000000000000000000) end
    if n >= 10000000000000000 then return string.format("%.1f京", n / 10000000000000000) end
    if n >= 1000000000000 then return string.format("%.1f兆", n / 1000000000000) end
    if n >= 100000000 then return string.format("%.1f亿", n / 100000000) end
    if n >= 10000 then return string.format("%.1f万", n / 10000) end
    return tostring(math.floor(n))
end

return M
