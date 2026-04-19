-- Game/Grid.lua
-- 暗黑塔防游戏 - 网格系统

local Config = require("Game.Config")
local State = require("Game.State")

local Grid = {}

-- 路径占据格子的查找表
local pathCellLookup = {}
for _, cell in ipairs(Config.PATH_CELLS) do
    local key = cell[1] .. "," .. cell[2]
    pathCellLookup[key] = true
end

--- 判断格子是否是路径
function Grid.IsPathCell(col, row)
    return pathCellLookup[col .. "," .. row] == true
end

--- 判断格子是否可以放塔
function Grid.CanPlace(col, row)
    if col < 1 or col > Config.GRID_COLS or row < 1 or row > Config.GRID_ROWS then
        return false
    end
    if Grid.IsPathCell(col, row) then
        return false
    end
    if State.grid[col][row] ~= nil then
        return false
    end
    return true
end

--- 获取所有空位
function Grid.GetEmptyCells()
    local empty = {}
    for c = 1, Config.GRID_COLS do
        for r = 1, Config.GRID_ROWS do
            if Grid.CanPlace(c, r) then
                empty[#empty + 1] = { col = c, row = r }
            end
        end
    end
    return empty
end

--- 网格坐标转屏幕像素坐标（返回格子中心点）
function Grid.CellToScreen(col, row, gridOffsetX, gridOffsetY)
    local x = gridOffsetX + (col - 0.5) * Config.CELL_SIZE
    local y = gridOffsetY + (row - 0.5) * Config.CELL_SIZE
    return x, y
end

--- 屏幕坐标转网格坐标
function Grid.ScreenToCell(screenX, screenY, gridOffsetX, gridOffsetY)
    local col = math.floor((screenX - gridOffsetX) / Config.CELL_SIZE) + 1
    local row = math.floor((screenY - gridOffsetY) / Config.CELL_SIZE) + 1
    return col, row
end

--- 路径航点转屏幕坐标
function Grid.WaypointToScreen(wp, gridOffsetX, gridOffsetY)
    local x = gridOffsetX + wp.x * Config.CELL_SIZE
    local y = gridOffsetY + wp.y * Config.CELL_SIZE
    return x, y
end

--- 获取路径线段列表（支持闭合环形）
--- 返回 { {x1,y1,x2,y2,len}, ... }
local cachedSegments = nil
local cachedOX, cachedOY = nil, nil

local function GetPathSegments(gridOffsetX, gridOffsetY)
    if cachedSegments and cachedOX == gridOffsetX and cachedOY == gridOffsetY then
        return cachedSegments
    end
    local wps = Config.PATH_WAYPOINTS
    local segs = {}
    local n = #wps
    -- 常规线段: 1→2, 2→3, ..., (n-1)→n
    for i = 2, n do
        local x1, y1 = Grid.WaypointToScreen(wps[i - 1], gridOffsetX, gridOffsetY)
        local x2, y2 = Grid.WaypointToScreen(wps[i], gridOffsetX, gridOffsetY)
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        segs[#segs + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, len = len }
    end
    -- 闭合线段: n→1（如果是环形路径）
    if Config.PATH_LOOP then
        local x1, y1 = Grid.WaypointToScreen(wps[n], gridOffsetX, gridOffsetY)
        local x2, y2 = Grid.WaypointToScreen(wps[1], gridOffsetX, gridOffsetY)
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        segs[#segs + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, len = len }
    end
    cachedSegments = segs
    cachedOX, cachedOY = gridOffsetX, gridOffsetY
    cachedPathLength = nil  -- 线段变化时清除路径长度缓存
    return segs
end

--- 获取路径总长度（像素）— 缓存结果避免每次遍历
local cachedPathLength = nil
function Grid.GetPathLength(gridOffsetX, gridOffsetY)
    local segs = GetPathSegments(gridOffsetX, gridOffsetY)
    -- segs 有缓存：如果 segments 没变，pathLength 也不变
    if cachedPathLength and cachedOX == gridOffsetX and cachedOY == gridOffsetY then
        return cachedPathLength
    end
    local totalLen = 0
    for _, s in ipairs(segs) do
        totalLen = totalLen + s.len
    end
    cachedPathLength = totalLen
    return totalLen
end

--- 根据路径进度(0~1)获取屏幕坐标
function Grid.GetPositionOnPath(progress, gridOffsetX, gridOffsetY)
    local segs = GetPathSegments(gridOffsetX, gridOffsetY)
    local totalLen = Grid.GetPathLength(gridOffsetX, gridOffsetY)
    local targetDist = progress * totalLen
    local accumulated = 0

    for _, s in ipairs(segs) do
        if accumulated + s.len >= targetDist then
            local t = (targetDist - accumulated) / s.len
            return s.x1 + (s.x2 - s.x1) * t, s.y1 + (s.y2 - s.y1) * t
        end
        accumulated = accumulated + s.len
    end

    -- fallback: 返回第一个航点（环形路径不应走到这里）
    local wps = Config.PATH_WAYPOINTS
    return Grid.WaypointToScreen(wps[1], gridOffsetX, gridOffsetY)
end

--- 根据路径进度(0~1)获取当前段的外侧法线方向（单位向量）
--- 路径为顺时针矩形，外侧=远离网格中心的方向（右手法线）
---@param progress number 0~1
---@param gridOffsetX number
---@param gridOffsetY number
---@return number nx, number ny  外侧法线单位向量
function Grid.GetPathOutwardNormal(progress, gridOffsetX, gridOffsetY)
    local segs = GetPathSegments(gridOffsetX, gridOffsetY)
    local totalLen = Grid.GetPathLength(gridOffsetX, gridOffsetY)
    local targetDist = (progress % 1.0) * totalLen
    local accumulated = 0

    for _, s in ipairs(segs) do
        if accumulated + s.len >= targetDist then
            -- 路径方向向量
            local dx = s.x2 - s.x1
            local dy = s.y2 - s.y1
            local len = s.len
            if len < 0.001 then return 0, -1 end
            -- 顺时针路径的外侧法线 = 右手法线 = (dy, -dx) / len
            -- 段1(→): (0, -1)=上  段2(↓): (1, 0)=右
            -- 段3(←): (0, 1)=下   段4(↑): (-1, 0)=左
            return dy / len, -dx / len
        end
        accumulated = accumulated + s.len
    end
    return 0, -1 -- fallback
end

--- 根据路径进度(0~1)获取当前段的行进方向（归一化）
---@param progress number 0~1
---@param gridOffsetX number
---@param gridOffsetY number
---@return number dx, number dy  归一化方向向量
function Grid.GetPathDirection(progress, gridOffsetX, gridOffsetY)
    local segs = GetPathSegments(gridOffsetX, gridOffsetY)
    local totalLen = Grid.GetPathLength(gridOffsetX, gridOffsetY)
    local targetDist = (progress % 1.0) * totalLen
    local accumulated = 0

    for _, s in ipairs(segs) do
        if accumulated + s.len >= targetDist then
            local len = s.len
            if len < 0.001 then return 1, 0 end
            return (s.x2 - s.x1) / len, (s.y2 - s.y1) / len
        end
        accumulated = accumulated + s.len
    end
    return 1, 0 -- fallback
end

--- 清除路径缓存（窗口大小变化时调用）
function Grid.InvalidateCache()
    cachedSegments = nil
    cachedOX, cachedOY = nil, nil
end

return Grid
