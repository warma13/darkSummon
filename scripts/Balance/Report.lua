------------------------------------------------------------------------
-- Report.lua  —  格式化 print 输出工具
-- 纯函数，无引擎依赖
------------------------------------------------------------------------
local Report = {}

local SEP_CHAR = "-"
local SEP_WIDTH = 80

------------------------------------------------------------
-- 基础格式
------------------------------------------------------------

function Report.Separator()
    print(string.rep(SEP_CHAR, SEP_WIDTH))
end

function Report.Header(title)
    print("")
    Report.Separator()
    print("  " .. title)
    Report.Separator()
end

function Report.Section(title, lines)
    print("")
    print("[ " .. title .. " ]")
    for _, line in ipairs(lines) do
        print("  " .. line)
    end
end

------------------------------------------------------------
-- 对齐表格
------------------------------------------------------------

--- 右对齐数字、左对齐文本
---@param val any
---@param width number
---@param isNumber boolean|nil
---@return string
local function padCell(val, width, isNumber)
    local s = tostring(val)
    if isNumber then
        return string.rep(" ", math.max(0, width - #s)) .. s
    else
        return s .. string.rep(" ", math.max(0, width - #s))
    end
end

--- 打印对齐表格
---@param headers string[]
---@param rows any[][]       每行是值数组
---@param colWidths number[] 每列宽度
---@param numCols table|nil  哪些列是数字 (1-based set)  例如 {[2]=true,[3]=true}
function Report.Table(headers, rows, colWidths, numCols)
    numCols = numCols or {}

    -- 自动计算列宽 (如果没指定)
    if not colWidths or #colWidths == 0 then
        colWidths = {}
        for i, h in ipairs(headers) do
            colWidths[i] = #tostring(h) + 2
        end
        for _, row in ipairs(rows) do
            for i, v in ipairs(row) do
                colWidths[i] = math.max(colWidths[i] or 4, #tostring(v) + 2)
            end
        end
    end

    -- 表头
    local hdrParts = {}
    for i, h in ipairs(headers) do
        hdrParts[i] = padCell(h, colWidths[i], false)
    end
    print("  " .. table.concat(hdrParts, " | "))

    -- 分隔线
    local sepParts = {}
    for i = 1, #headers do
        sepParts[i] = string.rep("-", colWidths[i])
    end
    print("  " .. table.concat(sepParts, "-+-"))

    -- 数据行
    for _, row in ipairs(rows) do
        local parts = {}
        for i, v in ipairs(row) do
            parts[i] = padCell(v, colWidths[i], numCols[i])
        end
        print("  " .. table.concat(parts, " | "))
    end
end

------------------------------------------------------------
-- ASCII 条形图
------------------------------------------------------------

--- 打印单行条形图
---@param label string
---@param value number
---@param maxValue number
---@param barWidth number|nil  默认 40
function Report.Bar(label, value, maxValue, barWidth)
    barWidth = barWidth or 40
    local ratio = maxValue > 0 and (value / maxValue) or 0
    ratio = math.min(1.0, math.max(0, ratio))
    local filled = math.floor(ratio * barWidth + 0.5)
    local bar = string.rep("#", filled) .. string.rep(".", barWidth - filled)
    print(string.format("  %-16s |%s| %s", label, bar, tostring(value)))
end

------------------------------------------------------------
-- 数字格式化辅助
------------------------------------------------------------

--- 带千位分隔符的整数
function Report.FormatInt(n)
    if n ~= n then return "NaN" end             -- NaN
    if n == math.huge then return "Inf" end
    if n == -math.huge then return "-Inf" end
    local s = string.format("%.0f", n)
    -- 处理负号
    local neg = ""
    if s:sub(1, 1) == "-" then neg = "-"; s = s:sub(2) end
    local pos = #s % 3
    if pos == 0 then pos = 3 end
    local parts = { s:sub(1, pos) }
    for i = pos + 1, #s, 3 do
        parts[#parts + 1] = s:sub(i, i + 2)
    end
    return neg .. table.concat(parts, ",")
end

--- 百分比字符串
function Report.Pct(v, decimals)
    decimals = decimals or 1
    return string.format("%." .. decimals .. "f%%", v * 100)
end

--- 固定小数位
function Report.Fixed(v, decimals)
    decimals = decimals or 2
    return string.format("%." .. decimals .. "f", v)
end

return Report
