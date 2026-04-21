-- Game/FormulaLib.lua
-- 通用数学曲线原语库（纯函数，无游戏逻辑依赖）
-- 用于统一项目中散落的数值公式，方便调参和对比平衡

local F = {}

--- 线性函数: base + k * x
---@param base number 基础值
---@param k number 每单位增长
---@param x number 输入变量
---@return number
function F.Linear(base, k, x)
    return base + k * x
end

--- 线性函数 + 上下限: clamp(base + k * x, lo, hi)
---@param base number 基础值
---@param k number 每单位增长
---@param x number 输入变量
---@param lo number 下限
---@param hi number 上限
---@return number
function F.LinearClamp(base, k, x, lo, hi)
    local v = base + k * x
    if lo and v < lo then return lo end
    if hi and v > hi then return hi end
    return v
end

--- 幂函数: base * x^exp
---@param base number 系数
---@param exp number 指数
---@param x number 输入变量
---@return number
function F.Power(base, exp, x)
    return base * (x ^ exp)
end

--- 指数函数: base * rate^x
---@param base number 初始值
---@param rate number 底数（增长率）
---@param x number 输入变量
---@return number
function F.Exponential(base, rate, x)
    return base * (rate ^ x)
end

--- 对数函数: base + scale * ln(x + 1)
---@param base number 基础值
---@param scale number 缩放系数
---@param x number 输入变量
---@return number
function F.Log(base, scale, x)
    return base + scale * math.log(x + 1)
end

--- 分段线性插值
--- segments 格式: { {x1, y1}, {x2, y2}, ... } 按 x 升序
--- x < 第一段取 y1，x > 最后段按最后段斜率外推
---@param segments table 分段节点数组
---@param x number 输入变量
---@return number
function F.Piecewise(segments, x)
    if #segments == 0 then return 0 end
    if #segments == 1 then return segments[1][2] end

    -- 低于第一个节点
    if x <= segments[1][1] then return segments[1][2] end

    -- 分段插值
    for i = 2, #segments do
        if x <= segments[i][1] then
            local x0, y0 = segments[i - 1][1], segments[i - 1][2]
            local x1, y1 = segments[i][1], segments[i][2]
            local t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
        end
    end

    -- 超出最后节点：按最后段斜率线性外推
    local last2 = segments[#segments - 1]
    local last1 = segments[#segments]
    local slope = (last1[2] - last2[2]) / (last1[1] - last2[1])
    return last1[2] + slope * (x - last1[1])
end

--- 分段线性插值（4列格式，兼容 HP_SCALE_SEGMENTS）
--- segments 格式: { {fromX, toX, fromY, toY}, ... }
--- x < 第一段取 fromY，x > 最后段按最后段斜率外推
---@param segments table 分段数组（每行4列）
---@param x number 输入变量
---@return number
function F.Piecewise4(segments, x)
    if #segments == 0 then return 1.0 end
    if x <= segments[1][1] then return segments[1][3] end

    for i = 1, #segments do
        local seg = segments[i]
        if x <= seg[2] then
            local t = (x - seg[1]) / (seg[2] - seg[1])
            return seg[3] + t * (seg[4] - seg[3])
        end
    end

    -- 超出最后段：线性外推
    local last = segments[#segments]
    local slope = (last[4] - last[3]) / (last[2] - last[1])
    return last[4] + slope * (x - last[2])
end

--- 分段多项式（每段支持常数项 + 一次项 + 二次项）
--- segments 格式: { { fromX, toX, a, b, c }, ... }
--- 值 = a + b*(x - fromX) + c*(x - fromX)^2
--- 最后一段若 toX == nil 或 x > 最后 toX，取最后段封顶值
---@param segments table 分段数组
---@param x number 输入变量
---@param cap number|nil 全局封顶值
---@return number
function F.PiecewisePoly(segments, x, cap)
    for i = 1, #segments do
        local seg = segments[i]
        local fromX, toX = seg[1], seg[2]
        if x >= fromX and (toX == nil or x < toX) then
            local t = x - fromX
            local val = seg[3] + (seg[4] or 0) * t + (seg[5] or 0) * t * t
            if cap then return math.min(val, cap) end
            return val
        end
    end
    -- 超出所有段：返回封顶值
    if cap then return cap end
    -- 用最后段的 toX 点计算
    local last = segments[#segments]
    local t = (last[2] or x) - last[1]
    return last[3] + (last[4] or 0) * t + (last[5] or 0) * t * t
end

--- S曲线: 1 / (1 + e^(-k*(x-center)))
---@param center number 中心点
---@param k number 陡峭度
---@param x number 输入变量
---@return number 0~1
function F.Sigmoid(center, k, x)
    return 1.0 / (1.0 + math.exp(-k * (x - center)))
end

--- 递减收益（减伤公式）: x / (x + base)
--- 当 x=base 时返回 0.5
---@param base number 基础值（半值点）
---@param x number 输入变量
---@return number 0~1
function F.Diminishing(base, x)
    if x <= 0 then return 0 end
    return x / (x + base)
end

--- 连乘: result = init * ∏ getFn(i) for i=1..n
---@param n number 步数
---@param getFn fun(i: number): number 每步乘数
---@param init number|nil 初始值（默认1.0）
---@return number
function F.CompoundMult(n, getFn, init)
    local result = init or 1.0
    for i = 1, n do
        result = result * getFn(i)
    end
    return result
end

--- 阶梯函数: thresholds = { {fromX, value}, ... } 按 fromX 降序匹配
---@param thresholds table 阈值数组 { {fromX, value}, ... }
---@param x number 输入变量
---@return number
function F.StepFunction(thresholds, x)
    for i = #thresholds, 1, -1 do
        if x >= thresholds[i][1] then
            return thresholds[i][2]
        end
    end
    return thresholds[1] and thresholds[1][2] or 0
end

return F
