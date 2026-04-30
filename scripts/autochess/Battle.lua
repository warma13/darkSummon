-- autochess/Battle.lua
-- 自走棋战斗系统：固定位置自动攻击（类塔防）

local Config = require("autochess.Config")
local VFX    = require("autochess.VFX")

local Battle = {}

-- 屏幕坐标转换函数（由 Renderer 注入）
local cellToScreen_ = nil
function Battle.SetCellToScreen(fn)
    cellToScreen_ = fn
end

-- ============================================================================
-- 辅助：距离计算（六边形）
-- ============================================================================

--- 六边形距离（委托给 Config.HexDist）
local function GridDist(c1, r1, c2, r2)
    return Config.HexDist(c1, r1, c2, r2)
end

-- ============================================================================
-- 寻找目标
-- ============================================================================

--- 在棋盘中找到最近的敌对目标
---@param grid table
---@param col number
---@param row number
---@param isEnemy boolean  当前棋子是否为敌方
---@param range number     攻击范围
---@return number|nil, number|nil  目标的 col, row
local function FindTarget(grid, col, row, isEnemy, range)
    local bestCol, bestRow = nil, nil
    local bestDist = 999

    local cols = Config.BOARD_COLS
    local rows = Config.BOARD_ROWS

    for c = 1, cols do
        for r = 1, rows do
            local target = grid[c][r]
            if target and target.alive and target.isEnemy ~= isEnemy then
                local d = GridDist(col, row, c, r)
                if d <= range and d < bestDist then
                    bestDist = d
                    bestCol  = c
                    bestRow  = r
                end
            end
        end
    end
    return bestCol, bestRow
end

-- ============================================================================
-- 伤害计算
-- ============================================================================

local function CalcDamage(atk, def)
    -- 简单减法公式，最低1
    local raw = atk - def * 0.5
    return math.max(1, math.floor(raw))
end

--- 对目标施加伤害并生成VFX
local function ApplyDamage(target, dmg, tc, tr, attackerColor)
    target.hp = target.hp - dmg
    target.dmgFlash = 1.0
    target.lastDmg = dmg
    if target.hp <= 0 then
        target.hp = 0
        target.alive = false
    end
    -- 生成飘字和受击粒子
    if cellToScreen_ then
        local sx, sy = cellToScreen_(tc, tr)
        local isCrit = dmg >= 40  -- 高伤害视为暴击
        VFX.SpawnDamageText(sx, sy - 10, dmg, isCrit)
        VFX.SpawnHitParticles(sx, sy, attackerColor or { 255, 200, 100 }, isCrit and 6 or 3)
    end
end

--- 对目标施加治疗并生成VFX
local function ApplyHeal(target, heal, tc, tr)
    target.hp = math.min(target.maxHp, target.hp + heal)
    target.dmgFlash = 0.5
    target.lastDmg = -heal
    if cellToScreen_ then
        local sx, sy = cellToScreen_(tc, tr)
        VFX.SpawnDamageText(sx, sy - 10, -heal, false)
    end
end

--- 生成弹道特效
local function SpawnProjectileVFX(sc, sr, tc, tr, color, spriteName)
    if not cellToScreen_ then return end
    local sx, sy = cellToScreen_(sc, sr)
    local tx, ty = cellToScreen_(tc, tr)
    VFX.SpawnProjectile(sx, sy, tx, ty, color, spriteName)
end

-- ============================================================================
-- AOE 攻击
-- ============================================================================

--- 对目标周围造成溅射伤害（六边形邻居）
local function DoAOE(grid, col, row, atk, isEnemy, attackerColor)
    local neighbors = Config.HexNeighbors(col, row)
    for _, nb in ipairs(neighbors) do
        local tc, tr = nb[1], nb[2]
        if Config.InBoard(tc, tr) then
            local target = grid[tc][tr]
            if target and target.alive and target.isEnemy ~= isEnemy then
                local dmg = CalcDamage(math.floor(atk * 0.5), target.def)
                ApplyDamage(target, dmg, tc, tr, attackerColor)
            end
        end
    end
end

-- ============================================================================
-- 辅助攻击（治疗友方）
-- ============================================================================

local function DoSupport(grid, col, row, atk, isEnemy)
    -- 治疗范围内血量最低的友方
    local bestCol, bestRow = nil, nil
    local lowestRatio = 2.0

    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local target = grid[c][r]
            if target and target.alive and target.isEnemy == isEnemy then
                if target.hp < target.maxHp then
                    local ratio = target.hp / target.maxHp
                    if ratio < lowestRatio then
                        lowestRatio = ratio
                        bestCol = c
                        bestRow = r
                    end
                end
            end
        end
    end

    if bestCol then
        local target = grid[bestCol][bestRow]
        local heal = math.floor(atk * 2) -- 支援型治疗量 = 攻击力 × 2
        ApplyHeal(target, heal, bestCol, bestRow)
    end
end

-- ============================================================================
-- 链式攻击
-- ============================================================================

local function DoChain(grid, col, row, atk, def, isEnemy, range, attackerColor)
    -- 攻击最近目标后弹跳到旁边1个
    local tc, tr = FindTarget(grid, col, row, isEnemy, range)
    if not tc then return end

    local target = grid[tc][tr]
    local dmg = CalcDamage(atk, target.def)
    ApplyDamage(target, dmg, tc, tr, attackerColor)

    -- 弹道：从攻击者到目标
    SpawnProjectileVFX(col, row, tc, tr, attackerColor)

    -- 弹跳：找 target 附近另一个敌人
    local bc, br = nil, nil
    local bestD = 999
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local t2 = grid[c][r]
            if t2 and t2.alive and t2.isEnemy ~= isEnemy
               and (c ~= tc or r ~= tr) then
                local d = GridDist(tc, tr, c, r)
                if d <= 2 and d < bestD then
                    bestD = d
                    bc = c
                    br = r
                end
            end
        end
    end
    if bc then
        local t2 = grid[bc][br]
        local dmg2 = CalcDamage(math.floor(atk * 0.6), t2.def)
        ApplyDamage(t2, dmg2, bc, br, attackerColor)
        -- 弹跳弹道：从第一个目标到第二个目标
        SpawnProjectileVFX(tc, tr, bc, br, attackerColor)
    end
end

-- ============================================================================
-- 移动逻辑
-- ============================================================================

local moveCd_ = 0  -- 全局移动冷却，控制移动节奏

function Battle.Reset()
    moveCd_ = 0
end

--- 找最近敌人（不限范围）
local function FindClosestEnemy(grid, col, row, isEnemy)
    local bestCol, bestRow = nil, nil
    local bestDist = 999
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local t = grid[c][r]
            if t and t.alive and t.isEnemy ~= isEnemy then
                local d = GridDist(col, row, c, r)
                if d < bestDist then
                    bestDist = d
                    bestCol = c
                    bestRow = r
                end
            end
        end
    end
    return bestCol, bestRow, bestDist
end

--- 让一个棋子朝目标移动一格（六边形邻居）
local function TryMove(grid, c, r, tc, tr)
    -- 获取6个六边形邻居，按到目标的距离排序，选最近的空位
    local neighbors = Config.HexNeighbors(c, r)
    -- 按到目标的 hex 距离排序
    table.sort(neighbors, function(a, b)
        local da = Config.HexDist(a[1], a[2], tc, tr)
        local db = Config.HexDist(b[1], b[2], tc, tr)
        return da < db
    end)

    for _, nb in ipairs(neighbors) do
        local nc, nr = nb[1], nb[2]
        if Config.InBoard(nc, nr) and not grid[nc][nr] then
            grid[nc][nr] = grid[c][r]
            grid[c][r] = nil
            return true
        end
    end
    return false
end

-- ============================================================================
-- 战斗帧更新
-- ============================================================================

--- 每帧推进战斗
---@param dt number
---@return boolean finished, boolean playerWon
function Battle.Tick(dt)
    local Board = require("autochess.Board")
    local grid  = Board.grid

    local playerAlive = false
    local enemyAlive  = false

    -- ---- 移动阶段 ----
    moveCd_ = moveCd_ - dt
    if moveCd_ <= 0 then
        moveCd_ = 0.5  -- 每0.5秒移动一次

        -- 收集需要移动的棋子（先收集再移动，避免遍历中修改grid）
        local movers = {}
        for c = 1, Config.BOARD_COLS do
            for r = 1, Config.BOARD_ROWS do
                local p = grid[c][r]
                if p and p.alive then
                    local tc, tr, dist = FindClosestEnemy(grid, c, r, p.isEnemy)
                    if tc and dist > p.range then
                        movers[#movers + 1] = { c = c, r = r, tc = tc, tr = tr }
                    end
                end
            end
        end
        -- 随机打乱移动顺序，避免固定优先级
        for i = #movers, 2, -1 do
            local j = math.random(1, i)
            movers[i], movers[j] = movers[j], movers[i]
        end
        for _, m in ipairs(movers) do
            -- 棋子可能已经被前一个移动覆盖，重新检查
            if grid[m.c][m.r] and grid[m.c][m.r].alive then
                TryMove(grid, m.c, m.r, m.tc, m.tr)
            end
        end
    end

    -- ---- 攻击阶段 ----
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local p = grid[c][r]
            if p and p.alive then
                -- 统计存活
                if p.isEnemy then
                    enemyAlive = true
                else
                    playerAlive = true
                end

                -- 攻击冷却
                p.atkCd = p.atkCd - dt
                if p.atkCd <= 0 then
                    p.atkCd = 1.0 / p.atkSpeed

                    p.atkAnim = 1.0  -- 触发攻击动画

                    -- 攻击者光晕
                    local atkColor = p.color or { 200, 200, 200 }
                    if cellToScreen_ then
                        local ax, ay = cellToScreen_(c, r)
                        VFX.SpawnAttackBloom(ax, ay, atkColor)
                    end

                    if p.atkType == "support" then
                        DoSupport(grid, c, r, p.atk, p.isEnemy)
                    elseif p.atkType == "chain" then
                        DoChain(grid, c, r, p.atk, p.def, p.isEnemy, p.range, atkColor)
                    else
                        -- single / aoe：找目标
                        local tc, tr = FindTarget(grid, c, r, p.isEnemy, p.range)
                        if tc then
                            local target = grid[tc][tr]
                            local dmg = CalcDamage(p.atk, target.def)

                            -- 远程弹道（range > 1 视为远程）
                            if p.range > 1 then
                                SpawnProjectileVFX(c, r, tc, tr, atkColor)
                            end

                            ApplyDamage(target, dmg, tc, tr, atkColor)

                            -- AOE 溅射
                            if p.atkType == "aoe" then
                                DoAOE(grid, tc, tr, p.atk, p.isEnemy, atkColor)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 检查结束
    if not enemyAlive then
        return true, true   -- 玩家胜
    end
    if not playerAlive then
        return true, false  -- 玩家败
    end

    return false, false
end

return Battle
