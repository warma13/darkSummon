-- ============================================================================
-- yang/PosGen.lua  ·  位置生成（纯函数，无副作用）
-- ============================================================================

local Cfg = require "yang.Config"
local M   = {}

local YANG_FACE = Cfg.YANG_FACE
local YANG_X_A  = Cfg.YANG_X_A
local YANG_Y_A  = Cfg.YANG_Y_A
local YANG_X_B  = Cfg.YANG_X_B
local YANG_Y_B  = Cfg.YANG_Y_B

-- ── 工具 ─────────────────────────────────────────────────────────────────────

function M.shuffle(t, seed)
    math.randomseed(seed)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

-- 生成 kindList：每种图案出现 3N 次，总数恰好 = total
function M.makeKindList(total, kindCount)
    -- total 必须是 3 的倍数（调用方已保证）
    local triples = total // 3                      -- 总共需要多少个"三连"
    local baseT   = triples // kindCount            -- 每种至少分到的三连数
    local extraT  = triples - baseT * kindCount     -- 还剩余的三连数，分给前 extraT 种
    local list    = {}
    for k = 1, kindCount do
        local cnt = (baseT + (k <= extraT and 1 or 0)) * 3
        for _ = 1, cnt do list[#list + 1] = k end
    end
    return list
end

-- ── 判断布局风格 ──────────────────────────────────────────────────────────────

function M.isYangStyle(cfg)
    return cfg.maxCols == 7 and cfg.maxRows == 7
end

-- ── 羊了个羊风格位置生成 ─────────────────────────────────────────────────────

-- 生成指定层的全部合法格位（像素坐标）
-- isTypeA=true  → A 型（距顶偶数步），使用 YANG_X_A × YANG_Y_A
-- isTypeA=false → B 型（距顶奇数步），使用 YANG_X_B × YANG_Y_B
function M.yangAllPos(layerNum, isTypeA)
    local xs = isTypeA and YANG_X_A or YANG_X_B
    local ys = isTypeA and YANG_Y_A or YANG_Y_B
    local pos = {}
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            table.insert(pos, { px = x, py = y, layerNum = layerNum })
        end
    end
    return pos
end

-- 从当前层合法格位中，只保留与上方层有 AABB 重叠的格位
-- 重叠判定：|px 差| < YANG_FACE AND |py 差| < YANG_FACE
function M.yangAABBPos(layerNum, count, aboveCards, seed, isTypeA)
    local allPos = M.yangAllPos(layerNum, isTypeA)
    local valid  = {}
    for _, p in ipairs(allPos) do
        for _, above in ipairs(aboveCards) do
            if math.abs(p.px - above.px) < YANG_FACE
            and math.abs(p.py - above.py) < YANG_FACE then
                table.insert(valid, p)
                break
            end
        end
    end
    M.shuffle(valid, seed + layerNum * 31 + 7)
    while #valid > count do table.remove(valid) end
    -- 当 AABB 过滤后位置不够时，从全网格补充，确保返回恰好 count 个
    if #valid < count then
        local usedSet = {}
        for _, v in ipairs(valid) do
            usedSet[v.px .. "," .. v.py] = true
        end
        local extra = {}
        for _, p in ipairs(allPos) do
            if not usedSet[p.px .. "," .. p.py] then
                table.insert(extra, p)
            end
        end
        M.shuffle(extra, seed + layerNum * 37 + 13)
        while #valid < count and #extra > 0 do
            table.insert(valid, table.remove(extra))
        end
    end
    return valid
end

-- ── 矩形网格位置生成（第一关用）──────────────────────────────────────────────

function M.rectLayerPos(layerNum, count, cfg, seed)
    local maxC   = cfg.maxCols
    local maxR   = cfg.maxRows
    local offset = (layerNum % 2 == 0) and 1 or 0
    local cols   = math.min(maxC, math.ceil(math.sqrt(count)))
    local rows   = math.min(maxR, math.ceil(count / cols))
    while cols < maxC and cols * rows < count do cols = cols + 1 end
    local cStart = math.floor((maxC - cols) / 2)
    local rStart = math.floor((maxR - rows) / 2)
    local pos    = {}
    for c = cStart, cStart + cols - 1 do
        for r = rStart, rStart + rows - 1 do
            table.insert(pos, {
                rolNum   = c * 2 + offset,
                rowNum   = r * 2 + offset,
                layerNum = layerNum,
            })
        end
    end
    M.shuffle(pos, seed + layerNum * 31)
    while #pos > count do table.remove(pos) end
    return pos
end

return M
