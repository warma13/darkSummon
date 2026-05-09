--- 数字/时间格式化工具模块
--- 消除项目中多处重复的 FormatNumber / FormatNum 定义
local M = {}

-- 数量级表（从大到小排列，便于遍历命中第一个）
-- 万进制：万(10^4) → 亿(10^8) → 兆(10^12) → 京(10^16) → 垓(10^20) → 秭(10^24) → 穰(10^28) → 沟(10^32) → 涧(10^36) → 正(10^40) → 载(10^44)
local UNITS = {
    { 1e44, "载" },
    { 1e40, "正" },
    { 1e36, "涧" },
    { 1e32, "沟" },
    { 1e28, "穰" },
    { 1e24, "秭" },
    { 1e20, "垓" },
    { 1e16, "京" },
    { 1e12, "兆" },
    { 1e8,  "亿" },
    { 1e4,  "万" },
}

--- 格式化大数字（中文后缀，保留1~2位小数）
--- 统一 EquipUI / RewardDisplay / TemperUI / ActivityUI_Shared / GameUI / Panels 等
---@param n number
---@return string
function M.FormatNumber(n)
    for _, u in ipairs(UNITS) do
        if n >= u[1] then
            local v = n / u[1]
            -- ≥100 只保留整数，≥10 保留1位，否则保留2位
            if v >= 100 then
                return string.format("%.0f%s", v, u[2])
            elseif v >= 10 then
                return string.format("%.1f%s", v, u[2])
            else
                return string.format("%.2f%s", v, u[2])
            end
        end
    end
    return tostring(math.floor(n))
end

--- 紧凑格式化（最多1位小数，适合 HUD / 列表等空间紧凑场景）
---@param n number
---@return string
function M.FormatNum(n)
    for _, u in ipairs(UNITS) do
        if n >= u[1] then
            local v = n / u[1]
            if v >= 100 then
                return string.format("%.0f%s", v, u[2])
            else
                return string.format("%.1f%s", v, u[2])
            end
        end
    end
    return tostring(math.floor(n))
end

return M
