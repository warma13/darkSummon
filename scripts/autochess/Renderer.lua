-- autochess/Renderer.lua
-- 自走棋 NanoVG 渲染

local Config      = require("autochess.Config")
local Board       = require("autochess.Board")
local SpriteSheet = require("Game.SpriteSheet")
local VFX         = require("autochess.VFX")
local Battle      = require("autochess.Battle")

local R = {}

local fontId_ = -1

-- ============================================================================
-- 拖拽状态
-- ============================================================================
local drag_ = {
    active   = false,
    piece    = nil,     -- 被拖拽的棋子引用
    source   = nil,     -- "board" | "bench"
    srcCol   = 0,
    srcRow   = 0,
    srcIdx   = 0,       -- bench 索引
    mx       = 0,       -- 当前拖拽位置(逻辑坐标)
    my       = 0,
}
local vg_ = nil

-- 精灵图缓存（自走棋独立 NanoVG context 中加载的 image handle）
local spriteImages_ = {}  -- { spriteName -> { img=handle, cols=number } }

-- 布局缓存
local layout_ = {}

-- ============================================================================
-- 初始化 / 销毁
-- ============================================================================

function R.Init(vg, screenW, screenH)
    vg_ = vg
    fontId_ = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    R.CalcLayout(screenW, screenH)

    -- 预加载英雄精灵图到自走棋的独立 NanoVG context
    spriteImages_ = {}
    for heroId, spriteName in pairs(Config.SPRITE_MAP) do
        local def = SpriteSheet.GetDef(spriteName)
        if def then
            local img = nvgCreateImage(vg, def.path, 0)
            if img > 0 then
                spriteImages_[spriteName] = { img = img, cols = def.cols or 3 }
            end
        end
    end

end

function R.Destroy(vg)
    -- NanoVG context 由 MiniGame 管理，销毁时会自动释放图片
    spriteImages_ = {}
    vg_ = nil
end

-- ============================================================================
-- 布局计算（六边形交错棋盘）
-- ============================================================================

function R.CalcLayout(w, h)
    local L = {}
    L.sw = w
    L.sh = h

    -- HUD 顶部高度
    L.hudH = 44

    -- 棋盘
    local boardPad = 8
    local shopH = 100
    local benchH = 60
    local bottomH = shopH + benchH + 12

    local availH = h - L.hudH - bottomH - boardPad * 2
    local availW = w - boardPad * 2

    -- 六边形布局：
    -- 每个 hex cell 的宽 = hexW, 高 = hexH
    -- 行间距 = hexH * 0.75 (交错重叠)，偶数行向右偏移 hexW * 0.5
    -- 总宽 = (BOARD_COLS + 0.5) * hexW  (留半格偏移空间)
    -- 总高 = hexH + (BOARD_ROWS - 1) * hexH * 0.75

    -- 先按宽度和高度分别算最大 hexW
    local maxHexW_byW = availW / (Config.BOARD_COLS + 0.5)
    -- hexH = hexW * 2/sqrt(3) ≈ hexW * 1.1547
    -- 总高 = hexH + (rows-1) * hexH * 0.75 = hexH * (1 + (rows-1)*0.75)
    local rowFactor = 1 + (Config.BOARD_ROWS - 1) * 0.75
    local maxHexW_byH = availH / (rowFactor * 1.1547)

    L.hexW = math.floor(math.min(maxHexW_byW, maxHexW_byH))
    L.hexH = math.floor(L.hexW * 1.1547)
    L.hexR = L.hexH * 0.5  -- 六边形外接圆半径

    -- 棋盘总尺寸
    L.boardW = math.floor((Config.BOARD_COLS + 0.5) * L.hexW)
    L.boardH = math.floor(L.hexH + (Config.BOARD_ROWS - 1) * L.hexH * 0.75)
    L.boardX = math.floor((w - L.boardW) * 0.5)
    L.boardY = L.hudH + boardPad

    -- cellSize 保持兼容（给 DrawPiece 用）
    L.cellSize = L.hexW

    -- 备战席
    local benchTotalW = math.min(L.boardW + L.hexW, availW)
    L.benchCellW = math.floor(benchTotalW / Config.BENCH_SIZE)
    L.benchH = benchH
    L.benchY = L.boardY + L.boardH + 6
    L.benchX = math.floor((w - L.benchCellW * Config.BENCH_SIZE) * 0.5)

    -- 商店
    L.shopH = shopH
    L.shopY = L.benchY + L.benchH + 6
    L.shopX = boardPad
    L.shopW = w - boardPad * 2
    L.shopCardW = math.floor((L.shopW - 60) / Config.SHOP_SLOTS) -- 留空给按钮
    L.shopCardH = L.shopH - 20

    layout_ = L
    return L
end

-- ============================================================================
-- 坐标转换（六边形交错 even-r 布局）
-- ============================================================================

--- 棋盘格 (col, row) → 屏幕中心像素坐标
local function CellToScreen(col, row)
    local L = layout_
    -- 偶数行右移半格
    local offsetX = (row % 2 == 0) and (L.hexW * 0.5) or 0
    local x = L.boardX + (col - 0.5) * L.hexW + offsetX
    local y = L.boardY + L.hexR + (row - 1) * L.hexH * 0.75
    return x, y
end

-- 注入坐标转换函数给 Battle（VFX 生成需要屏幕坐标）
Battle.SetCellToScreen(CellToScreen)

--- 屏幕像素坐标 → 最近的棋盘格 (col, row)
local function ScreenToCell(mx, my)
    local L = layout_
    -- 先估算 row
    local approxRow = (my - L.boardY - L.hexR) / (L.hexH * 0.75) + 1
    -- 检查附近2~3行，找距离最近的 hex 中心
    local bestCol, bestRow = -1, -1
    local bestDist = 999999
    for tryRow = math.max(1, math.floor(approxRow) - 1),
                 math.min(Config.BOARD_ROWS, math.ceil(approxRow) + 1) do
        local offsetX = (tryRow % 2 == 0) and (L.hexW * 0.5) or 0
        local approxCol = (mx - L.boardX - offsetX + 0.5 * L.hexW) / L.hexW
        for tryCol = math.max(1, math.floor(approxCol) - 1),
                     math.min(Config.BOARD_COLS, math.ceil(approxCol) + 1) do
            local cx, cy = CellToScreen(tryCol, tryRow)
            local dx = mx - cx
            local dy = my - cy
            local d = dx * dx + dy * dy
            if d < bestDist then
                bestDist = d
                bestCol = tryCol
                bestRow = tryRow
            end
        end
    end
    return bestCol, bestRow
end

-- ============================================================================
-- 颜色辅助
-- ============================================================================

local function RGBA(tbl)
    return nvgRGBA(tbl[1], tbl[2], tbl[3], tbl[4] or 255)
end

local function RGBAa(tbl, alpha)
    return nvgRGBA(tbl[1], tbl[2], tbl[3], alpha)
end

-- ============================================================================
-- 绘制辅助
-- ============================================================================

local function DrawRoundedRect(vg, x, y, w, h, r, color)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, RGBA(color))
    nvgFill(vg)
end

local function DrawText(vg, text, x, y, size, color, align)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    nvgFillColor(vg, RGBA(color))
    nvgTextAlign(vg, align or NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, x, y, text)
end

local function DrawStars(vg, x, y, star, size)
    local starStr = string.rep("★", star)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size or 10)
    nvgFillColor(vg, RGBA(Config.COLORS.star))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, x, y, starStr)
end

-- ============================================================================
-- 棋子绘制
-- ============================================================================

local function DrawPiece(vg, piece, cx, cy, cellSize, isDragging)
    if not piece then return end

    -- 死亡动画完毕的棋子不再绘制
    if not piece.alive and piece.deathDone then return end

    -- ================================================================
    -- 动画参数计算
    -- ================================================================

    -- 浮动动画（idle 时上下浮动）—— 拖拽中或死亡中不浮动
    local floatOffY = 0
    if piece.alive and not isDragging then
        local phase = piece.floatPhase or 0
        local amp   = piece.floatAmp or 3.0
        floatOffY = math.sin(phase) * amp
    end

    -- 死亡动画：淡出 + 缩小
    local deathAlpha = 1.0
    local deathScale = 1.0
    if not piece.alive then
        local t = piece.deathTimer or 0  -- 0→1
        deathAlpha = math.max(0, 1.0 - t)
        deathScale = math.max(0.2, 1.0 - t * 0.6)
    end

    -- 入场缩放动画：从小弹到正常大小
    local entryScale = 1.0
    if (piece.scaleAnim or 0) > 0 then
        -- scaleAnim 从 1→0 衰减，映射为 scale 从 0.3→1.0 弹出
        entryScale = 1.0 - piece.scaleAnim * 0.7
    end

    -- 攻击前冲动画：brief lunge forward
    local atkLungeX = 0
    local atkLungeY = 0
    if piece.atkAnim and piece.atkAnim > 0 then
        -- 前冲幅度：向敌方方向偏移几像素
        local lungeDir = piece.isEnemy and 1 or -1  -- 玩家向上冲，敌人向下冲
        local lunge = math.sin(piece.atkAnim * math.pi) * cellSize * 0.15
        atkLungeY = lunge * lungeDir
    end

    -- 合成后的 scale
    local finalScale = deathScale * entryScale

    -- 应用浮动 + 攻击前冲到坐标
    local drawCX = cx + atkLungeX
    local drawCY = cy + floatOffY + atkLungeY

    local half = cellSize * 0.42 * finalScale
    local color = piece.color or { 180, 180, 180 }

    -- 全局 alpha（死亡淡出）
    local globalAlpha = math.floor(deathAlpha * 255)

    -- 受伤闪光
    local flashAlpha = 0
    if piece.dmgFlash > 0 then
        flashAlpha = math.floor(piece.dmgFlash * 180 * deathAlpha)
    end

    -- ================================================================
    -- 脚底阴影（椭圆）—— 阴影不浮动，固定在 cy
    -- ================================================================
    local shadowAlpha = math.floor((isDragging and 100 or 60) * deathAlpha)
    nvgBeginPath(vg)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy + cellSize * 0.42 * 0.7)
    nvgScale(vg, 1.0, 0.35)
    nvgCircle(vg, 0, 0, cellSize * 0.42 * 0.7 * finalScale)
    nvgRestore(vg)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowAlpha))
    nvgFill(vg)

    -- ================================================================
    -- 精灵图渲染
    -- ================================================================
    local spriteName = Config.SPRITE_MAP[piece.id]
    local drawSize = half * 2 * 1.1
    local spriteData = spriteName and spriteImages_[spriteName]

    if spriteData and spriteData.img > 0 then
        local frameIdx = 0
        if piece.atkAnim and piece.atkAnim > 0.5 then
            frameIdx = 1
        end
        local dh = drawSize * 0.5
        local totalW = drawSize * spriteData.cols
        local ox = drawCX - dh - frameIdx * drawSize
        local oy = drawCY - dh
        local paint = nvgImagePattern(vg, ox, oy, totalW, drawSize, 0, spriteData.img, deathAlpha)
        nvgBeginPath(vg)
        nvgRect(vg, drawCX - dh, drawCY - dh, drawSize - 1, drawSize)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- 无精灵图回退：半透明圆形 + 名字首字
        nvgBeginPath(vg)
        nvgCircle(vg, drawCX, drawCY, half * 0.7)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(160 * deathAlpha)))
        nvgFill(vg)
        local nameSize = math.max(12, cellSize * 0.3) * finalScale
        local firstChar = string.sub(piece.name, 1, 3)
        DrawText(vg, firstChar, drawCX, drawCY, nameSize, { 255, 255, 255, globalAlpha })
    end

    -- 拖拽高亮（发光边框）
    if isDragging then
        nvgBeginPath(vg)
        nvgCircle(vg, drawCX, drawCY, half + 3)
        nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
    end

    -- 受伤闪白
    if flashAlpha > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, drawCX, drawCY, half * 0.8)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
    end

    -- 名字（底部）
    local nameSize = math.max(8, cellSize * 0.16)
    DrawText(vg, piece.name, drawCX, drawCY + half + 1, nameSize, { 255, 255, 255, globalAlpha })

    -- 星级（顶部）
    if piece.star > 0 then
        local starAlpha = globalAlpha
        DrawStars(vg, drawCX, drawCY - half + 3, piece.star, math.max(8, cellSize * 0.18))
    end

    -- 血条（仅存活棋子显示）
    if piece.alive then
        local barW = half * 1.6
        local barH = 3
        local barX = drawCX - barW * 0.5
        local barY = drawCY + half + nameSize * 0.7 + 2
        local hpRatio = piece.hp / piece.maxHp

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 1.5)
        nvgFillColor(vg, RGBA(Config.COLORS.hpBarBg))
        nvgFill(vg)

        if hpRatio > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 1.5)
            local barColor = piece.isEnemy and Config.COLORS.hpBarEnemy or Config.COLORS.hpBar
            nvgFillColor(vg, RGBA(barColor))
            nvgFill(vg)
        end
    end
end

-- ============================================================================
-- 六边形绘制辅助
-- ============================================================================

--- 绘制正六边形路径（flat-top 六边形，宽=hexW, 高=hexH）
local function HexPath(vg, cx, cy, hexW, hexH)
    local r = hexH * 0.5  -- 外接圆半径（顶点到中心）
    local hw = hexW * 0.5
    -- flat-top hexagon 的6个顶点（顺时针从顶部）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx,      cy - r)          -- 顶
    nvgLineTo(vg, cx + hw,  cy - r * 0.5)   -- 右上
    nvgLineTo(vg, cx + hw,  cy + r * 0.5)   -- 右下
    nvgLineTo(vg, cx,      cy + r)          -- 底
    nvgLineTo(vg, cx - hw,  cy + r * 0.5)   -- 左下
    nvgLineTo(vg, cx - hw,  cy - r * 0.5)   -- 左上
    nvgClosePath(vg)
end

-- ============================================================================
-- 棋盘绘制（六边形交错）
-- ============================================================================

local function DrawBoard(vg)
    local L = layout_

    -- 绘制每个六边形格子
    for r = 1, Config.BOARD_ROWS do
        for c = 1, Config.BOARD_COLS do
            local cx, cy = CellToScreen(c, r)
            local isEnemy = r <= Config.ENEMY_ROW_MAX

            -- 格子填充色（敌方/玩家区域不同底色）
            local fillColor = isEnemy and Config.COLORS.boardEnemy or Config.COLORS.boardPlayer
            HexPath(vg, cx, cy, L.hexW, L.hexH)
            nvgFillColor(vg, RGBAa(fillColor, fillColor[4] or 180))
            nvgFill(vg)

            -- 格子边框
            HexPath(vg, cx, cy, L.hexW, L.hexH)
            nvgStrokeColor(vg, RGBA(Config.COLORS.cellBorder))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end

    -- 中线标记：在 row 4 和 row 5 之间画一条虚线
    local midY1 = L.boardY + L.hexR + (Config.ENEMY_ROW_MAX - 1) * L.hexH * 0.75 + L.hexR * 0.5 + L.hexH * 0.375
    nvgBeginPath(vg)
    nvgMoveTo(vg, L.boardX, midY1)
    nvgLineTo(vg, L.boardX + L.boardW, midY1)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 80))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 拖拽时目标格高亮
    if drag_.active and Board.phase == "prep" then
        local dropCol, dropRow = ScreenToCell(drag_.mx, drag_.my)
        if dropCol >= 1 and dropCol <= Config.BOARD_COLS
           and dropRow >= Config.PLAYER_ROW_MIN and dropRow <= Config.BOARD_ROWS then
            local hx, hy = CellToScreen(dropCol, dropRow)
            -- 高亮六边形
            HexPath(vg, hx, hy, L.hexW * 0.92, L.hexH * 0.92)
            nvgFillColor(vg, nvgRGBA(255, 220, 80, 40))
            nvgFill(vg)
            HexPath(vg, hx, hy, L.hexW * 0.92, L.hexH * 0.92)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 140))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    end

    -- 棋子（跳过正在拖拽的）
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p then
                local skip = drag_.active and drag_.source == "board"
                             and drag_.srcCol == c and drag_.srcRow == r
                if not skip then
                    local cx, cy = CellToScreen(c, r)
                    DrawPiece(vg, p, cx, cy, L.cellSize)
                end
            end
        end
    end
end

-- ============================================================================
-- 备战席绘制
-- ============================================================================

local function DrawBench(vg)
    local L = layout_

    DrawRoundedRect(vg, L.benchX, L.benchY, L.boardW, L.benchH, 6, Config.COLORS.benchBg)

    local benchLabel = "备战席  上场 " .. Board.CountPlayerPieces() .. "/" .. Board.GetMaxOnBoard()
    DrawText(vg, benchLabel, L.benchX + 30, L.benchY + 10, 11, Config.COLORS.dim,
             NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    for i = 1, Config.BENCH_SIZE do
        local cx = L.benchX + (i - 0.5) * L.benchCellW
        local cy = L.benchY + L.benchH * 0.55

        -- 槽位边框
        local slotW = L.benchCellW * 0.85
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - slotW * 0.5, cy - slotW * 0.5, slotW, slotW, 4)
        nvgStrokeColor(vg, RGBA(Config.COLORS.cellBorder))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        local p = Board.bench[i]
        if p then
            -- 拖拽中跳过源位置的棋子
            local skip = drag_.active and drag_.source == "bench"
                         and drag_.srcIdx == i
            if not skip then
                DrawPiece(vg, p, cx, cy, L.cellSize)
            end
        end
    end
end

-- ============================================================================
-- HUD 顶部
-- ============================================================================

local function DrawHUD(vg)
    local L = layout_

    DrawRoundedRect(vg, 0, 0, L.sw, L.hudH, 0, Config.COLORS.hudBg)

    -- 回合
    DrawText(vg, "回合 " .. Board.round .. "/" .. Config.TOTAL_ROUNDS,
             L.sw * 0.5, L.hudH * 0.5, 16, Config.COLORS.white)

    -- 血量
    DrawText(vg, "♥ " .. Board.hp,
             50, L.hudH * 0.5, 15, Config.COLORS.red,
             NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 等级 + 经验条（血量右边）
    local lvlX = 100
    local lvlY = L.hudH * 0.5
    local lvlInfo = Config.LEVEL_TABLE[Board.level]
    local maxXp = lvlInfo and lvlInfo.xpReq or 0
    local lvlLabel = "Lv" .. Board.level
    local slotLabel = " (" .. Board.CountPlayerPieces() .. "/" .. Board.GetMaxOnBoard() .. ")"
    DrawText(vg, lvlLabel .. slotLabel, lvlX, lvlY - 7, 11, Config.COLORS.white,
             NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 经验条
    local xpBarW = 70
    local xpBarH = 4
    local xpBarX = lvlX
    local xpBarY = lvlY + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, xpBarX, xpBarY, xpBarW, xpBarH, 2)
    nvgFillColor(vg, nvgRGBA(40, 35, 60, 200))
    nvgFill(vg)
    if maxXp > 0 then
        local ratio = math.min(Board.xp / maxXp, 1.0)
        if ratio > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, xpBarX, xpBarY, xpBarW * ratio, xpBarH, 2)
            nvgFillColor(vg, nvgRGBA(80, 200, 255, 220))
            nvgFill(vg)
        end
        DrawText(vg, Board.xp .. "/" .. maxXp, xpBarX + xpBarW + 4, xpBarY + 1, 8,
                 { 150, 200, 255, 200 }, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    else
        -- 满级
        nvgBeginPath(vg)
        nvgRoundedRect(vg, xpBarX, xpBarY, xpBarW, xpBarH, 2)
        nvgFillColor(vg, nvgRGBA(255, 215, 80, 200))
        nvgFill(vg)
        DrawText(vg, "MAX", xpBarX + xpBarW + 4, xpBarY + 1, 8,
                 Config.COLORS.gold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end

    -- 金币
    DrawText(vg, "💰 " .. Board.gold,
             L.sw - 50, L.hudH * 0.5, 15, Config.COLORS.gold,
             NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)

    -- 阶段提示
    local phaseText = ""
    if Board.phase == "prep" then
        local t = math.ceil(Board.prepTimer)
        phaseText = "准备中 " .. t .. "s"
    elseif Board.phase == "battle" then
        phaseText = "⚔ 战斗中"
    elseif Board.phase == "result" then
        if Board.lastResult == "win" then
            phaseText = "✓ 胜利"
        else
            phaseText = "✗ 失败"
        end
    end
    if phaseText ~= "" then
        DrawText(vg, phaseText, L.sw * 0.5, L.hudH * 0.5 + 16, 11, Config.COLORS.dim)
    end

    -- 结算阶段：收入明细浮窗
    if Board.phase == "result" and Board.lastIncome then
        local inc = Board.lastIncome

        -- 先构造明细行，再算面板高度
        local lines = {
            { "基础工资", inc.base },
            { "利息", inc.interest },
        }
        if inc.win > 0 then
            lines[#lines + 1] = { "胜利奖励", inc.win }
        end
        if inc.streak > 0 then
            lines[#lines + 1] = { "连胜/连败", inc.streak }
        end

        local lh = 13
        local panelW = 130
        local panelH = 14 + lh + 2 + #lines * lh + 6  -- 标题 + 间距 + 明细行 + 底部留白
        local panelX = L.sw * 0.5 - panelW * 0.5
        local panelY = L.hudH + 4

        -- 半透明背景
        DrawRoundedRect(vg, panelX, panelY, panelW, panelH, 6,
                        { 20, 15, 35, 220 })
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 6)
        nvgStrokeColor(vg, nvgRGBA(255, 215, 80, 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        local ly = panelY + 12
        local lx1 = panelX + 10
        local lx2 = panelX + panelW - 10

        -- 标题
        DrawText(vg, "收入 +" .. inc.total, panelX + panelW * 0.5, ly, 12,
                 Config.COLORS.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        ly = ly + lh + 2

        -- 明细行
        for _, line in ipairs(lines) do
            DrawText(vg, line[1], lx1, ly, 10, Config.COLORS.dim,
                     NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            DrawText(vg, "+" .. line[2], lx2, ly, 10, Config.COLORS.gold,
                     NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            ly = ly + lh
        end
    end

    -- 羁绊信息
    local synX = 8
    local synY = L.hudH + 2
    for faction, info in pairs(Board.activeSynergies) do
        local fDef = Config.FACTIONS[faction]
        if fDef and info.tier then
            local label = fDef.name .. "(" .. info.count .. ") " .. info.tier.desc
            DrawText(vg, label, synX, synY, 10, fDef.color,
                     NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            synY = synY + 14
        end
    end
end

-- ============================================================================
-- 商店绘制
-- ============================================================================

local shopBtnRects_ = {} -- { {x,y,w,h,action,data}, ... }

local function DrawShop(vg)
    local L = layout_

    DrawRoundedRect(vg, L.shopX, L.shopY, L.shopW, L.shopH, 6, Config.COLORS.shopBg)

    -- 商店标题
    DrawText(vg, "商店", L.shopX + 30, L.shopY + 12, 13, Config.COLORS.gold,
             NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 买经验按钮
    local buyXpW = 60
    local buyXpH = 20
    local buyXpX = L.shopX + L.shopW - 120
    local buyXpY = L.shopY + 3
    local canBuyXp = Board.gold >= Config.BUY_XP_COST and Board.phase == "prep"
                     and Board.level < Config.MAX_LEVEL
    local buyXpColor = canBuyXp and { 80, 200, 255 } or Config.COLORS.dim

    DrawRoundedRect(vg, buyXpX, buyXpY, buyXpW, buyXpH, 4,
                    { buyXpColor[1], buyXpColor[2], buyXpColor[3], 60 })
    DrawText(vg, "升级 $" .. Config.BUY_XP_COST, buyXpX + buyXpW * 0.5,
             buyXpY + buyXpH * 0.5, 10, buyXpColor)

    shopBtnRects_[#shopBtnRects_ + 1] = {
        x = buyXpX, y = buyXpY, w = buyXpW, h = buyXpH,
        action = "buyxp",
    }

    -- 刷新按钮
    local rerollX = L.shopX + L.shopW - 55
    local rerollY = L.shopY + 3
    local rerollW = 50
    local rerollH = 20
    local canReroll = Board.gold >= Config.REROLL_COST and Board.phase == "prep"
    local rerollColor = canReroll and Config.COLORS.gold or Config.COLORS.dim

    DrawRoundedRect(vg, rerollX, rerollY, rerollW, rerollH, 4,
                    { rerollColor[1], rerollColor[2], rerollColor[3], 60 })
    DrawText(vg, "刷新 $" .. Config.REROLL_COST, rerollX + rerollW * 0.5,
             rerollY + rerollH * 0.5, 11, rerollColor)

    shopBtnRects_[#shopBtnRects_ + 1] = {
        x = rerollX, y = rerollY, w = rerollW, h = rerollH,
        action = "reroll",
    }

    -- 英雄卡片
    local cardStartX = L.shopX + 5
    local cardY = L.shopY + 28
    local cardH = L.shopH - 36

    for i = 1, Config.SHOP_SLOTS do
        local heroId = Board.shop[i]
        local cx = cardStartX + (i - 1) * L.shopCardW
        local cw = L.shopCardW - 4

        if heroId then
            local def = Config.HERO_BY_ID[heroId]
            if def then
                local canBuy = Board.gold >= def.cost and Board.phase == "prep"
                local alpha = canBuy and 220 or 100

                -- 品质色边框
                local qc = Config.COST_COLORS[def.cost] or { 180, 180, 180 }

                -- 卡片背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx, cardY, cw, cardH, 4)
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3],
                                         math.floor(alpha * 0.15)))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], alpha))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 精灵图（卡片上半部分）
                local spriteName = Config.SPRITE_MAP[heroId]
                local spriteData = spriteName and spriteImages_[spriteName]
                local imgSize = math.min(cw - 4, cardH * 0.5)
                local imgCX = cx + cw * 0.5
                local imgCY = cardY + cardH * 0.3

                if spriteData and spriteData.img > 0 then
                    local dh = imgSize * 0.5
                    local totalW = imgSize * spriteData.cols
                    local ox = imgCX - dh
                    local oy = imgCY - dh
                    local imgAlpha = canBuy and 1.0 or 0.4
                    local paint = nvgImagePattern(vg, ox, oy, totalW, imgSize, 0, spriteData.img, imgAlpha)
                    nvgBeginPath(vg)
                    nvgRect(vg, imgCX - dh, imgCY - dh, imgSize - 1, imgSize)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                end

                -- 品质标签（左上角）
                local rarityName = Config.COST_RARITY_NAME and Config.COST_RARITY_NAME[def.cost] or ""
                if rarityName ~= "" then
                    DrawText(vg, rarityName, cx + 12, cardY + 10, 9,
                             { qc[1], qc[2], qc[3], alpha },
                             NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                end

                -- 名字
                DrawText(vg, def.name, cx + cw * 0.5, cardY + cardH * 0.6,
                         11, { 245, 238, 225, alpha })

                -- 阵营
                local fDef = Config.FACTIONS[def.faction]
                if fDef then
                    DrawText(vg, fDef.name, cx + cw * 0.5, cardY + cardH * 0.75,
                             9, { fDef.color[1], fDef.color[2], fDef.color[3], alpha })
                end

                -- 费用（品质色）
                local costColor = canBuy and qc or Config.COLORS.dim
                DrawText(vg, "$" .. def.cost, cx + cw * 0.5, cardY + cardH * 0.9,
                         12, costColor)

                -- 按钮区域
                shopBtnRects_[#shopBtnRects_ + 1] = {
                    x = cx, y = cardY, w = cw, h = cardH,
                    action = "buy", data = i,
                }
            end
        else
            -- 已购买的空位
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cardY, cw, cardH, 4)
            nvgStrokeColor(vg, RGBA(Config.COLORS.cellBorder))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end

    -- 战斗开始按钮（准备阶段）
    if Board.phase == "prep" then
        local btnW = 70
        local btnH = 28
        local btnX = L.sw * 0.5 - btnW * 0.5
        local btnY = L.shopY + L.shopH + 4

        -- 确保不超出屏幕
        if btnY + btnH < L.sh then
            DrawRoundedRect(vg, btnX, btnY, btnW, btnH, 6,
                            { 220, 160, 40, 200 })
            DrawText(vg, "开战!", btnX + btnW * 0.5, btnY + btnH * 0.5,
                     14, Config.COLORS.white)

            shopBtnRects_[#shopBtnRects_ + 1] = {
                x = btnX, y = btnY, w = btnW, h = btnH,
                action = "fight",
            }
        end
    end
end

-- ============================================================================
-- 游戏结束画面
-- ============================================================================

local function DrawEndScreen(vg, isWin)
    local L = layout_

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, L.sw, L.sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    local title = isWin and "通关成功!" or "挑战失败"
    local titleColor = isWin and Config.COLORS.gold or Config.COLORS.red
    DrawText(vg, title, L.sw * 0.5, L.sh * 0.35, 32, titleColor)

    local subText = "回合 " .. Board.round .. "/" .. Config.TOTAL_ROUNDS
    DrawText(vg, subText, L.sw * 0.5, L.sh * 0.45, 16, Config.COLORS.dim)

    -- 退出按钮
    local btnW = 120
    local btnH = 40
    local btnX = L.sw * 0.5 - btnW * 0.5
    local btnY = L.sh * 0.6

    DrawRoundedRect(vg, btnX, btnY, btnW, btnH, 8,
                    { 80, 60, 120, 220 })
    DrawText(vg, "返回", btnX + btnW * 0.5, btnY + btnH * 0.5,
             18, Config.COLORS.white)

    shopBtnRects_[#shopBtnRects_ + 1] = {
        x = btnX, y = btnY, w = btnW, h = btnH,
        action = "exit", data = isWin and "win" or "lose",
    }
end

-- ============================================================================
-- VFX 绘制（复用主游戏 Renderer_Draw 的渲染模式）
-- ============================================================================

--- 绘制圆形光晕/Bloom（从主游戏 DrawCircleBloom 移植）
local function DrawCircleBloom(vg, x, y, radius, r, g, b, alpha)
    alpha = alpha or 0.6
    local maxR = radius * 3.0
    local innerR = radius * 0.3
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, maxR)
    local grad = nvgRadialGradient(vg, x, y, innerR, maxR,
        nvgRGBAf(r, g, b, alpha),
        nvgRGBAf(r, g, b, 0))
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

--- 绘制攻击光晕
local function DrawHitFlashes(vg)
    for _, hf in ipairs(VFX.hitFlashes) do
        local ratio = hf.timer / 0.3
        local r = hf.radius * (2.0 - ratio)  -- 扩散
        local alpha = ratio * 0.5
        DrawCircleBloom(vg, hf.x, hf.y, r, hf.r, hf.g, hf.b, alpha)
    end
end

--- 绘制弹道
local function DrawProjectiles(vg)
    for _, p in ipairs(VFX.projectiles) do
        local c = p.color
        -- 弹道光晕
        DrawCircleBloom(vg, p.x, p.y, 6, c[1] / 255, c[2] / 255, c[3] / 255, 0.7)

        -- 弹道核心亮点
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, 3)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgFill(vg)

        -- 尾迹（小拖影）
        local tailX = p.x - p.dx * 8
        local tailY = p.y - p.dy * 8
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.x, p.y)
        nvgLineTo(vg, tailX, tailY)
        nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 120))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 绘制受击粒子
local function DrawParticles(vg)
    for _, pt in ipairs(VFX.particles) do
        local ratio = pt.life / pt.maxLife
        local alpha = math.floor(ratio * 200)
        local size = pt.size * ratio
        local c = pt.color
        nvgBeginPath(vg)
        nvgCircle(vg, pt.x, pt.y, size)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgFill(vg)
    end
end

--- 绘制飘字（从主游戏 DrawFloatingTexts 移植）
local function DrawFloatingTexts(vg)
    for _, ft in ipairs(VFX.floatingTexts) do
        local ratio = ft.life / ft.maxLife
        local alpha = math.floor(math.min(1.0, ratio * 2) * 255)

        -- 暴击缩放效果: 1.0 → 1.5 → 1.0
        local scale = 1.0
        if ft.isCrit then
            local t = 1.0 - ratio  -- 0→1 随时间增长
            if t < 0.2 then
                scale = 1.0 + t * 2.5  -- 快速放大到 1.5
            else
                scale = 1.5 - (t - 0.2) * 0.625  -- 缩回到 1.0
            end
        end

        local fontSize = ft.fontSize * scale
        local c = ft.color

        -- 阴影
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.6)))
        nvgText(vg, ft.x + 1, ft.y + 1, ft.text)

        -- 正文
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgText(vg, ft.x, ft.y, ft.text)
    end
end

--- 绘制所有 VFX（在棋盘之上绘制）
local function DrawVFX(vg)
    DrawHitFlashes(vg)
    DrawProjectiles(vg)
    DrawParticles(vg)
    DrawFloatingTexts(vg)
end

-- ============================================================================
-- 主渲染入口
-- ============================================================================

function R.Render(vg, w, h, dpr)
    nvgBeginFrame(vg, w, h, dpr)

    -- 每帧重置按钮区域（gameover/win 画面也需要干净的列表）
    shopBtnRects_ = {}

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    local bg = nvgLinearGradient(vg, 0, 0, 0, h,
        RGBA(Config.COLORS.bg1), RGBA(Config.COLORS.bg2))
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    if Board.phase == "gameover" then
        DrawBoard(vg)
        DrawVFX(vg)
        DrawEndScreen(vg, false)
    elseif Board.phase == "win" then
        DrawBoard(vg)
        DrawVFX(vg)
        DrawEndScreen(vg, true)
    else
        DrawHUD(vg)
        DrawBoard(vg)
        DrawVFX(vg)
        DrawBench(vg)
        DrawShop(vg)
    end

    -- 拖拽中的棋子绘制在最上层
    if drag_.active and drag_.piece then
        local L = layout_
        DrawPiece(vg, drag_.piece, drag_.mx, drag_.my, L.cellSize, true)
    end

    nvgEndFrame(vg)
end

-- ============================================================================
-- 拖拽 & 点击处理
-- ============================================================================

--- 按下：开始拖拽或点击按钮
function R.HandleMouseDown(mx, my)
    local L = layout_

    -- 按钮检测（商店/战斗/退出等）始终响应
    for _, btn in ipairs(shopBtnRects_) do
        if mx >= btn.x and mx <= btn.x + btn.w
           and my >= btn.y and my <= btn.y + btn.h then
            if btn.action == "buy" then
                Board.BuyHero(btn.data)
            elseif btn.action == "reroll" then
                Board.Reroll()
            elseif btn.action == "buyxp" then
                Board.BuyXP()
            elseif btn.action == "fight" then
                Board.StartBattle()
            elseif btn.action == "exit" then
                local MG = require("autochess.MiniGame")
                local exitFn = MG.GetExitFn()
                if exitFn then exitFn(btn.data) end
            end
            return
        end
    end

    -- 仅准备阶段可拖拽
    if Board.phase ~= "prep" then return end

    -- 检测备战席棋子
    if my >= L.benchY and my <= L.benchY + L.benchH then
        local idx = math.floor((mx - L.benchX) / L.benchCellW) + 1
        if idx >= 1 and idx <= Config.BENCH_SIZE and Board.bench[idx] then
            drag_.active  = true
            drag_.piece   = Board.bench[idx]
            drag_.source  = "bench"
            drag_.srcIdx  = idx
            drag_.mx      = mx
            drag_.my      = my
            return
        end
    end

    -- 检测棋盘棋子（玩家区域）
    if mx >= L.boardX and mx <= L.boardX + L.boardW
       and my >= L.boardY and my <= L.boardY + L.boardH then
        local col, row = ScreenToCell(mx, my)
        if col >= 1 and col <= Config.BOARD_COLS
           and row >= Config.PLAYER_ROW_MIN and row <= Config.BOARD_ROWS then
            local p = Board.grid[col][row]
            if p and not p.isEnemy then
                drag_.active  = true
                drag_.piece   = p
                drag_.source  = "board"
                drag_.srcCol  = col
                drag_.srcRow  = row
                drag_.mx      = mx
                drag_.my      = my
                return
            end
        end
    end
end

--- 查询拖拽状态（供 MiniGame Update 轮询用）
function R.IsDragging()
    return drag_.active
end

--- 移动：更新拖拽位置
function R.HandleMouseMove(mx, my)
    if not drag_.active then return end
    drag_.mx = mx
    drag_.my = my
end

--- 松手：放下棋子
function R.HandleMouseUp(mx, my)
    if not drag_.active then
        return
    end

    local L = layout_
    local placed = false

    -- 尝试放到棋盘玩家区域
    if mx >= L.boardX and mx <= L.boardX + L.boardW
       and my >= L.boardY and my <= L.boardY + L.boardH then
        local col, row = ScreenToCell(mx, my)
        if col >= 1 and col <= Config.BOARD_COLS
           and row >= Config.PLAYER_ROW_MIN and row <= Config.BOARD_ROWS then
            local target = Board.grid[col][row]

            if drag_.source == "bench" then
                -- 从备战席拖到棋盘
                if target and not target.isEnemy then
                    -- 交换：目标去备战席（不改变数量，允许）
                    Board.bench[drag_.srcIdx] = target
                    Board.grid[col][row] = drag_.piece
                    placed = true
                else
                    -- 放到空位：检查上场上限
                    if Board.CountPlayerPieces() < Board.GetMaxOnBoard() then
                        Board.bench[drag_.srcIdx] = nil
                        Board.grid[col][row] = drag_.piece
                        placed = true
                    end
                    -- 超限则放回原位（placed = false）
                end
            elseif drag_.source == "board" then
                if col == drag_.srcCol and row == drag_.srcRow then
                    -- 放回原位，不做操作
                    placed = true
                elseif target and not target.isEnemy then
                    -- 棋盘内交换
                    Board.grid[drag_.srcCol][drag_.srcRow] = target
                    Board.grid[col][row] = drag_.piece
                    placed = true
                else
                    -- 放到空位
                    Board.grid[drag_.srcCol][drag_.srcRow] = nil
                    Board.grid[col][row] = drag_.piece
                    placed = true
                end
            end
        end
    end

    -- 尝试放到备战席
    if not placed and my >= L.benchY and my <= L.benchY + L.benchH then
        local idx = math.floor((mx - L.benchX) / L.benchCellW) + 1
        if idx >= 1 and idx <= Config.BENCH_SIZE then
            local target = Board.bench[idx]

            if drag_.source == "bench" then
                if idx == drag_.srcIdx then
                    placed = true  -- 放回原位
                elseif target then
                    -- 备战席内交换
                    Board.bench[drag_.srcIdx] = target
                    Board.bench[idx] = drag_.piece
                    placed = true
                else
                    Board.bench[drag_.srcIdx] = nil
                    Board.bench[idx] = drag_.piece
                    placed = true
                end
            elseif drag_.source == "board" then
                if target then
                    -- 棋盘棋子和备战席交换
                    Board.grid[drag_.srcCol][drag_.srcRow] = target
                    Board.bench[idx] = drag_.piece
                    placed = true
                else
                    -- 棋盘棋子退回备战席空位
                    Board.grid[drag_.srcCol][drag_.srcRow] = nil
                    Board.bench[idx] = drag_.piece
                    placed = true
                end
            end
        end
    end

    -- 放置失败 → 回到原位（不做修改）
    -- placed == false 时棋子自动还在原位

    if placed then
        Board.RecalcSynergies()
    end

    -- 重置拖拽状态
    drag_.active = false
    drag_.piece  = nil
    drag_.source = nil
end

return R
