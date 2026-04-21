-- ============================================================================
-- yang/Renderer.lua  ·  所有 NanoVG 绘制逻辑
-- 从 Board 读取状态，不持有任何游戏数据
-- ============================================================================

local Cfg   = require "yang.Config"
local Board = require "yang.Board"
local M     = {}

local LEVELS     = Cfg.LEVELS
local SLOT_MAX   = Cfg.SLOT_MAX
local ANIM_SPLIT = Cfg.ANIM_SPLIT

-- 预加载的图案纹理 id（索引=kind）
local kindImages_ = {}

-- 菜单按钮位置缓存（供 main.lua 碰撞检测用）
M.menuBtns   = {}
-- 打乱道具按钮位置缓存（供 main.lua 碰撞检测用）
M.shuffleBtn = nil
-- 撤回道具按钮位置缓存（供 main.lua 碰撞检测用）
M.undoBtn    = nil
-- 移出道具按钮位置缓存（供 main.lua 碰撞检测用）
M.moveOutBtn = nil

-- ── 初始化 / 销毁 ─────────────────────────────────────────────────────────────

function M.init(vg)
    nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    for i, kc in ipairs(Cfg.KIND_CFG) do
        kindImages_[i] = nvgCreateImage(vg, "image/" .. kc.img .. ".png", 0)
        print(string.format("[Renderer] 加载图案 %d: image/%s.png → id=%d",
            i, kc.img, kindImages_[i]))
    end
end

function M.destroy(vg)
    nvgDelete(vg)
end

-- ── 核心绘制原语 ──────────────────────────────────────────────────────────────

local function drawCard(vg, x, y, kind, dimmed, hideImg, cw, ch, faceH)
    cw    = cw    or Board.CW
    ch    = ch    or Board.CH
    faceH = faceH or Board.FACE_H
    local r = math.max(4, cw // 8)

    -- 阴影条
    nvgBeginPath(vg); nvgRoundedRect(vg, x, y, cw, ch, r)
    nvgFillColor(vg, nvgRGBA(20, 16, 38, dimmed and 180 or 220)); nvgFill(vg)
    -- 卡面
    nvgBeginPath(vg); nvgRoundedRect(vg, x, y, cw, faceH, r)
    nvgFillColor(vg, nvgRGBA(72, 60, 110, dimmed and 160 or 255)); nvgFill(vg)
    -- 描边
    nvgBeginPath(vg); nvgRoundedRect(vg, x, y, cw, ch, r)
    nvgStrokeColor(vg, nvgRGBA(255,255,255, dimmed and 40 or 100))
    nvgStrokeWidth(vg, 1.0); nvgStroke(vg)
    -- 图案
    local img = kindImages_[kind]
    if img and img > 0 and not hideImg then
        local pad   = faceH * 0.1
        local imgSz = faceH - pad * 2
        local imgX  = x + (cw - imgSz) / 2
        local imgY  = y + pad
        local alpha = dimmed and 0.55 or 1.0
        local paint = nvgImagePattern(vg, imgX, imgY, imgSz, imgSz, 0, img, alpha)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, imgX, imgY, imgSz, imgSz, 4)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

-- ── A 区绘制 ─────────────────────────────────────────────────────────────────

local function drawACards(vg)
    local layerGroups = {}
    local maxLayer    = 0
    for _, c in ipairs(Board.allCards) do
        if not c.removed and c.moldType == 1 and c.state ~= "hidden" then
            local ln = c.layerNum
            if not layerGroups[ln] then layerGroups[ln] = {} end
            table.insert(layerGroups[ln], c)
            if ln > maxLayer then maxLayer = ln end
        end
    end
    for _, cards in pairs(layerGroups) do
        table.sort(cards, function(a, b)
            return (a.py or a.rowNum) < (b.py or b.rowNum)
        end)
    end
    for ln = 1, maxLayer do
        local cards = layerGroups[ln]
        if cards then
            -- 先画阴影条（在网格外）
            for _, c in ipairs(cards) do
                local sx, sy = Board.gridToScreen(c)
                sy = sy + (c.entryOffsetY or 0)
                nvgSave(vg)
                nvgScissor(vg, sx, sy + Board.FACE_H, Board.CW, Board.CARD_SHADOW)
                drawCard(vg, sx, sy, c.kind, c.state == "dim")
                nvgRestore(vg)
            end
            -- 再画牌面（覆盖相邻阴影渗出）
            for _, c in ipairs(cards) do
                local sx, sy = Board.gridToScreen(c)
                sy = sy + (c.entryOffsetY or 0)
                nvgSave(vg)
                nvgScissor(vg, sx, sy, Board.CW, Board.FACE_H)
                drawCard(vg, sx, sy, c.kind, c.state == "dim")
                nvgRestore(vg)
            end
        end
    end
end

-- ── B 区绘制 ─────────────────────────────────────────────────────────────────

local function drawBPiles(vg)
    for _, pile in ipairs(Board.piles) do
        local sorted = {}
        for _, c in ipairs(pile.cards) do
            if not c.removed then table.insert(sorted, c) end
        end
        table.sort(sorted, function(a, b) return a.layerNum < b.layerNum end)
        local topLN = #sorted > 0 and sorted[#sorted].layerNum or nil
        local dir   = pile.dir or "down"
        local sh    = Board.CARD_SHADOW
        for _, c in ipairs(sorted) do
            local sx, sy = Board.pilePos(pile, c.layerNum)
            if c.layerNum == topLN then
                drawCard(vg, sx, sy, c.kind, false)
            else
                nvgSave(vg)
                if     dir == "down"  then nvgScissor(vg, sx,               sy + Board.CH - sh, Board.CW, sh)
                elseif dir == "up"    then nvgScissor(vg, sx,               sy,                 Board.CW, sh)
                elseif dir == "right" then nvgScissor(vg, sx + Board.CW - sh, sy,               sh,       Board.CH)
                else                       nvgScissor(vg, sx,               sy,                 sh,       Board.CH)
                end
                drawCard(vg, sx, sy, c.kind, true, true)
                nvgRestore(vg)
            end
        end
    end
end

-- ── 槽位绘制 ─────────────────────────────────────────────────────────────────

local function drawSlot(vg)
    local bW = Board.SLOT_CW * SLOT_MAX   -- 卡牌实际总宽，居中
    local bH = Board.SLOT_CH + 14
    nvgBeginPath(vg); nvgRect(vg, Board.SLOT_X, Board.SLOT_Y, bW, bH)
    nvgFillColor(vg, nvgRGBA(18,15,38,220)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255,255,255,45)); nvgStrokeWidth(vg,1); nvgStroke(vg)
    for i = 1, SLOT_MAX do
        local sx = Board.SLOT_X + (i-1) * Board.SLOT_STEP
        nvgBeginPath(vg); nvgRoundedRect(vg, sx, Board.SLOT_Y+7, Board.SLOT_CW, Board.SLOT_CH, 5)
        nvgFillColor(vg, nvgRGBA(45,40,70,170)); nvgFill(vg)
    end
    for _, c in ipairs(Board.slot) do
        local sx = c.slotX or Board.SLOT_X
        drawCard(vg, sx, Board.SLOT_Y+7, c.kind, false, false,
                 Board.SLOT_CW, Board.SLOT_CH, Board.SLOT_FACE_H)
    end
end

-- ── HUD 绘制 ─────────────────────────────────────────────────────────────────

local function drawHUD(vg)
    local rem = 0
    for _, c in ipairs(Board.allCards) do if not c.removed then rem = rem + 1 end end
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(210,210,255,210))
    nvgText(vg, 12, 8, string.format("%s  剩余 %d 张  槽位 %d/7  [R]重开 [ESC]菜单",
        LEVELS[Board.curLvl].name, rem, #Board.slot))
end

-- ── 道具按钮绘制（底部居中）─────────────────────────────────────────────────
-- 排列：[移出 80] 12 [撤回 80] 12 [打乱 88]  总宽 272，距底部 10px，高 36px
local BTN_H       = 36
local BTN_BOT_PAD = 10
local BTN_GAP     = 12
local BTN_TOTAL_W = 80 + 12 + 80 + 12 + 88  -- 272

local function drawUndoBtn(vg, LW, LH)
    local uses   = Board.undoUses
    local bW, bH = 80, BTN_H
    local startX = math.floor((LW - BTN_TOTAL_W) / 2)
    local bx     = startX + 80 + BTN_GAP   -- 撤回在移出右侧
    local by     = LH - BTN_BOT_PAD - bH
    M.undoBtn    = { x=bx, y=by, w=bW, h=bH }

    -- 可用条件：有次数 + lastSlotCard 仍在槽位中（未被三消）+ 无动画
    local hasCard = false
    if Board.lastSlotCard then
        for _, c in ipairs(Board.slot) do
            if c == Board.lastSlotCard then hasCard = true; break end
        end
    end
    local enabled = uses > 0 and hasCard and not Board.shuffleAnim
                    and not Board.undoAnim and #Board.anims == 0
    nvgBeginPath(vg); nvgRoundedRect(vg, bx, by, bW, bH, bH/2)
    nvgFillColor(vg, enabled and nvgRGBA(80,160,255,220) or nvgRGBA(70,70,80,160))
    nvgFill(vg)
    nvgStrokeColor(vg, enabled and nvgRGBA(160,210,255,180) or nvgRGBA(120,120,130,100))
    nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, enabled and nvgRGBA(255,255,255,240) or nvgRGBA(140,140,145,200))
    nvgText(vg, bx + bW/2, by + bH/2, "撤回 x" .. uses)
end

-- ── 暂存区（移出三张）绘制 ───────────────────────────────────────────────────

local function drawOverflowCols(vg)
    local sh = Board.SLOT_SHADOW
    for colIdx = 1, 3 do
        local col = Board.overflowCols[colIdx]
        if #col > 0 then
            local cx  = Board.overflowColX(colIdx)
            local top = #col
            -- 从底部到顶部依次绘制（牌堆式层叠）
            for si = 1, top do
                local cy    = Board.overflowCardY(si)
                local isTop = (si == top)
                if isTop then
                    -- 顶牌完整显示
                    drawCard(vg, cx, cy, col[si].kind, false, false,
                        Board.SLOT_CW, Board.SLOT_CH, Board.SLOT_FACE_H)
                else
                    -- 非顶牌只露出底部 sh 像素（阴影条）
                    nvgSave(vg)
                    nvgScissor(vg, cx, cy + Board.SLOT_CH - sh, Board.SLOT_CW, sh)
                    drawCard(vg, cx, cy, col[si].kind, true, true,
                        Board.SLOT_CW, Board.SLOT_CH, Board.SLOT_FACE_H)
                    nvgRestore(vg)
                end
            end
        end
    end
end

-- 移出飞行动画绘制（卡牌从槽位飞往暂存列，保持槽位尺寸）
local function drawMoveOutAnims(vg)
    for _, ma in ipairs(Board.moveAnims) do
        local te = 1 - (1 - ma.t)^3   -- ease-out cubic
        local x  = ma.srcX + (ma.dstX - ma.srcX) * te
        local y  = ma.srcY + (ma.dstY - ma.srcY) * te
        drawCard(vg, x, y, ma.card.kind, false, false,
            Board.SLOT_CW, Board.SLOT_CH, Board.SLOT_FACE_H)
    end
end

local function drawMoveOutBtn(vg, LW, LH)
    local uses   = Board.moveOutUses
    local bW, bH = 80, BTN_H
    local startX = math.floor((LW - BTN_TOTAL_W) / 2)
    local bx     = startX                  -- 移出在最左
    local by     = LH - BTN_BOT_PAD - bH
    M.moveOutBtn = { x=bx, y=by, w=bW, h=bH }

    local enabled = uses > 0 and #Board.slot >= 3
                    and not Board.shuffleAnim and not Board.undoAnim
                    and #Board.anims == 0 and #Board.moveAnims == 0
    nvgBeginPath(vg); nvgRoundedRect(vg, bx, by, bW, bH, bH/2)
    nvgFillColor(vg, enabled and nvgRGBA(180, 90, 255, 220) or nvgRGBA(70,70,80,160))
    nvgFill(vg)
    nvgStrokeColor(vg, enabled and nvgRGBA(220,160,255,180) or nvgRGBA(120,120,130,100))
    nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, enabled and nvgRGBA(255,255,255,240) or nvgRGBA(140,140,145,200))
    nvgText(vg, bx + bW/2, by + bH/2, "移出 x" .. uses)
end

local function drawShuffleBtn(vg, LW, LH)
    local uses   = Board.shuffleUses
    local bW, bH = 88, BTN_H
    local startX = math.floor((LW - BTN_TOTAL_W) / 2)
    local bx     = startX + 80 + BTN_GAP + 80 + BTN_GAP  -- 打乱在最右
    local by     = LH - BTN_BOT_PAD - bH
    M.shuffleBtn = { x=bx, y=by, w=bW, h=bH }

    local enabled = uses > 0 and not Board.shuffleAnim
    -- 背景
    nvgBeginPath(vg); nvgRoundedRect(vg, bx, by, bW, bH, bH/2)
    nvgFillColor(vg, enabled and nvgRGBA(240,175,40,230) or nvgRGBA(70,70,80,160))
    nvgFill(vg)
    -- 描边
    nvgStrokeColor(vg, enabled and nvgRGBA(255,220,100,180) or nvgRGBA(120,120,130,100))
    nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    -- 文字
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, enabled and nvgRGBA(40,20,0,255) or nvgRGBA(140,140,145,200))
    nvgText(vg, bx + bW/2, by + bH/2, "打乱 x" .. uses)
end

-- ── 菜单绘制 ─────────────────────────────────────────────────────────────────

-- 菜单装饰粒子（首次调用时生成，之后复用）
local menuParticles_ = nil
local menuTime_      = 0

local function ensureParticles(LW, LH)
    if menuParticles_ then return end
    menuParticles_ = {}
    math.randomseed(42)
    for i = 1, 35 do
        menuParticles_[i] = {
            x     = math.random() * LW,
            y     = math.random() * LH,
            r     = 1.0 + math.random() * 2.5,
            speed = 6 + math.random() * 14,
            phase = math.random() * math.pi * 2,
            alpha = 40 + math.random(60),
        }
    end
end

local function drawMenu(vg, LW, LH)
    menuTime_ = menuTime_ + 1/60
    ensureParticles(LW, LH)
    local cx = LW / 2

    -- ── 背景：深色渐变 ──────────────────────────────────────────────────────
    local bg = nvgLinearGradient(vg, 0, 0, 0, LH,
        nvgRGBA(8, 4, 22, 255), nvgRGBA(30, 14, 55, 255))
    nvgBeginPath(vg); nvgRect(vg, 0, 0, LW, LH)
    nvgFillPaint(vg, bg); nvgFill(vg)

    -- 中心径向光晕
    local glowR  = LW * 0.7
    local glowCY = LH * 0.32
    local glow   = nvgRadialGradient(vg, cx, glowCY, 0, glowR,
        nvgRGBA(120, 50, 180, 35), nvgRGBA(120, 50, 180, 0))
    nvgBeginPath(vg); nvgRect(vg, cx - glowR, glowCY - glowR, glowR * 2, glowR * 2)
    nvgFillPaint(vg, glow); nvgFill(vg)

    -- ── 浮动粒子 ────────────────────────────────────────────────────────────
    for _, p in ipairs(menuParticles_) do
        local py = (p.y - p.speed * menuTime_) % LH
        local flicker = 0.6 + 0.4 * math.sin(menuTime_ * 2.0 + p.phase)
        local a  = math.floor(p.alpha * flicker)
        nvgBeginPath(vg); nvgCircle(vg, p.x, py, p.r)
        nvgFillColor(vg, nvgRGBA(180, 130, 255, a)); nvgFill(vg)
    end

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- ── 标题 "暗黑消除" ─────────────────────────────────────────────────────
    local titleY = LH * 0.17

    -- 标题光晕
    local tGlow = nvgRadialGradient(vg, cx, titleY, 0, 100,
        nvgRGBA(200, 100, 255, 30), nvgRGBA(200, 100, 255, 0))
    nvgBeginPath(vg); nvgRect(vg, cx - 100, titleY - 100, 200, 200)
    nvgFillPaint(vg, tGlow); nvgFill(vg)

    -- 文字阴影
    nvgFontSize(vg, 44)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgText(vg, cx + 2, titleY + 2, "暗黑消除")
    -- 主标题（渐变感：用两层叠加）
    nvgFillColor(vg, nvgRGBA(220, 170, 255, 255))
    nvgText(vg, cx, titleY, "暗黑消除")
    -- 高光层
    nvgFillColor(vg, nvgRGBA(255, 220, 255, 60))
    nvgText(vg, cx, titleY - 1, "暗黑消除")

    -- ── 装饰线 ──────────────────────────────────────────────────────────────
    local lineW = 120
    local lineY = titleY + 32
    local lineGradL = nvgLinearGradient(vg, cx - lineW, lineY, cx, lineY,
        nvgRGBA(180, 120, 255, 0), nvgRGBA(180, 120, 255, 120))
    nvgBeginPath(vg); nvgRect(vg, cx - lineW, lineY, lineW, 1.5)
    nvgFillPaint(vg, lineGradL); nvgFill(vg)
    local lineGradR = nvgLinearGradient(vg, cx, lineY, cx + lineW, lineY,
        nvgRGBA(180, 120, 255, 120), nvgRGBA(180, 120, 255, 0))
    nvgBeginPath(vg); nvgRect(vg, cx, lineY, lineW, 1.5)
    nvgFillPaint(vg, lineGradR); nvgFill(vg)
    -- 中心菱形点缀
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, lineY - 4)
    nvgLineTo(vg, cx + 4, lineY + 1)
    nvgLineTo(vg, cx, lineY + 6)
    nvgLineTo(vg, cx - 4, lineY + 1)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 150, 255, 180)); nvgFill(vg)

    -- ── 副标题 ──────────────────────────────────────────────────────────────
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(160, 140, 200, 180))
    nvgText(vg, cx, lineY + 26, "三消堆叠卡牌 · 集齐三张自动消除 · 槽满即败")

    -- ── 关卡预览卡片 ────────────────────────────────────────────────────────
    local cardStartY = LH * 0.36
    local cardH      = 38
    local cardGap    = 6
    local cardW      = math.min(280, LW - 40)
    local cardX      = cx - cardW / 2

    for i, lv in ipairs(LEVELS) do
        local cy = cardStartY + (i - 1) * (cardH + cardGap)
        local isFirst = (i == 1)

        -- 卡片背景
        nvgBeginPath(vg); nvgRoundedRect(vg, cardX, cy, cardW, cardH, 8)
        if isFirst then
            nvgFillColor(vg, nvgRGBA(100, 50, 160, 160))
        else
            nvgFillColor(vg, nvgRGBA(40, 25, 70, 140))
        end
        nvgFill(vg)
        -- 描边
        nvgStrokeColor(vg, isFirst and nvgRGBA(180, 120, 255, 140) or nvgRGBA(80, 60, 120, 100))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 关卡序号标签
        local tagW = 52
        nvgBeginPath(vg); nvgRoundedRect(vg, cardX + 6, cy + 7, tagW, cardH - 14, 5)
        nvgFillColor(vg, isFirst and nvgRGBA(180, 100, 255, 200) or nvgRGBA(70, 45, 110, 180))
        nvgFill(vg)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, isFirst and 255 or 180))
        nvgText(vg, cardX + 6 + tagW / 2, cy + cardH / 2, lv.name)

        -- 卡牌数 & 种数
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(190, 175, 220, isFirst and 240 or 160))
        local info = lv.totalCards .. " 张"
        if lv.kindCount then info = info .. " · " .. lv.kindCount .. " 种" end
        nvgText(vg, cardX + 66, cy + cardH / 2, info)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 第一关右侧标记
        if isFirst then
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 200, 100, 200))
            nvgText(vg, cardX + cardW - 10, cy + cardH / 2, "入门")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        elseif i == #LEVELS then
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 100, 100, 180))
            nvgText(vg, cardX + cardW - 10, cy + cardH / 2, "无尽")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    end

    -- ── 开始按钮 ────────────────────────────────────────────────────────────
    local BW, BH = 220, 54
    local btnY   = cardStartY + #LEVELS * (cardH + cardGap) + 20
    local btnX   = cx - BW / 2

    -- 按钮光晕
    local pulse = 0.7 + 0.3 * math.sin(menuTime_ * 3.0)
    local btnGlow = nvgRadialGradient(vg, cx, btnY + BH / 2, BW * 0.3, BW * 0.7,
        nvgRGBA(160, 80, 255, math.floor(40 * pulse)),
        nvgRGBA(160, 80, 255, 0))
    nvgBeginPath(vg); nvgRect(vg, cx - BW, btnY - BH / 2, BW * 2, BH * 2)
    nvgFillPaint(vg, btnGlow); nvgFill(vg)

    -- 按钮主体渐变
    local btnBg = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + BH,
        nvgRGBA(140, 70, 220, 240), nvgRGBA(100, 40, 180, 240))
    nvgBeginPath(vg); nvgRoundedRect(vg, btnX, btnY, BW, BH, 12)
    nvgFillPaint(vg, btnBg); nvgFill(vg)
    -- 顶部高光条
    local hlGrad = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + BH * 0.5,
        nvgRGBA(255, 255, 255, 35), nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg); nvgRoundedRect(vg, btnX, btnY, BW, BH * 0.5, 12)
    nvgFillPaint(vg, hlGrad); nvgFill(vg)
    -- 描边
    nvgBeginPath(vg); nvgRoundedRect(vg, btnX, btnY, BW, BH, 12)
    nvgStrokeColor(vg, nvgRGBA(200, 150, 255, math.floor(120 * pulse)))
    nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

    -- 按钮文字
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, cx, btnY + BH / 2 - 1, "开始挑战")

    M.menuBtns = { { lvl = 1, x = btnX, y = btnY, w = BW, h = BH } }

    -- ── 底部提示 ────────────────────────────────────────────────────────────
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(120, 110, 150, 130))
    nvgText(vg, cx, btnY + BH + 22, "通关后自动进入下一关")
end

-- ── 飞行动画绘制 ─────────────────────────────────────────────────────────────

local function drawAnims(vg)
    local faceH    = Board.FACE_H
    local SPLIT    = ANIM_SPLIT
    local PEAK     = 1.30
    local dstScale = Board.SLOT_CW / Board.CW
    for _, a in ipairs(Board.anims) do
        local t = a.t
        local x, y, scale
        local pivotDstX = a.dstX + Board.CW / 2 * (dstScale - 1)
        local pivotDstY = a.dstY + faceH / 2 * (dstScale - 1)
        if t < SPLIT then
            local tp = t / SPLIT
            x, y = a.srcX, a.srcY
            if tp < 0.45 then
                scale = 1.0 + (PEAK - 1.0) * (tp / 0.45)
            else
                scale = PEAK + (dstScale - PEAK) * ((tp - 0.45) / 0.55)
            end
        else
            local tp = (t - SPLIT) / (1 - SPLIT)
            local te = 1 - (1 - tp) * (1 - tp) * (1 - tp)
            x     = a.srcX + (pivotDstX - a.srcX) * te
            y     = a.srcY + (pivotDstY - a.srcY) * te
            scale = dstScale
        end
        nvgSave(vg)
        nvgTranslate(vg, x + Board.CW / 2, y + faceH / 2)
        nvgScale(vg, scale, scale)
        nvgTranslate(vg, -Board.CW / 2, -faceH / 2)
        drawCard(vg, 0, 0, a.card.kind, false)
        nvgRestore(vg)
    end
end

-- ── 撤回飞行动画绘制 ──────────────────────────────────────────────────────────
--  牌从槽位位置飞回牌堆原位，同时从槽位缩放还原为原始大小

local function drawUndoAnim(vg)
    local ua = Board.undoAnim
    if not ua then return end
    local te  = 1 - (1 - ua.t)^3                  -- ease-out cubic
    local x   = ua.srcX + (ua.dstX - ua.srcX) * te
    local y   = ua.srcY + (ua.dstY - ua.srcY) * te
    local s0  = Board.SLOT_CW / Board.CW            -- 槽位缩放比
    local s   = s0 + (1.0 - s0) * te               -- 还原到原始大小
    nvgSave(vg)
    nvgTranslate(vg, x + Board.CW / 2, y + Board.FACE_H / 2)
    nvgScale(vg, s, s)
    nvgTranslate(vg, -Board.CW / 2, -Board.FACE_H / 2)
    drawCard(vg, 0, 0, ua.card.kind, false)
    nvgRestore(vg)
end

-- ── 打乱动画绘制 ─────────────────────────────────────────────────────────────
--  三段式：收拢 → 旋转 → 扩散归位
--  只绘制 anim.entries（可见牌），隐藏牌在 update 中途静默换 kind

local function drawShuffleAnim(vg)
    local anim = Board.shuffleAnim
    if not anim then return end
    local t      = anim.t
    local P1, P2 = 0.35, 0.65           -- 阶段分界
    local cx, cy = anim.cx, anim.cy
    local R      = anim.radius
    local rotAmt = anim.rotAmt          -- π (180°)
    local CW, FH = Board.CW, Board.FACE_H

    for _, e in ipairs(anim.entries) do
        local x, y
        if t < P1 then
            -- 阶段1：srcPos → circPos（ease-out cubic）
            local tp = t / P1
            local te = 1 - (1 - tp)^3
            x = e.srcX + (e.circX - e.srcX) * te
            y = e.srcY + (e.circY - e.srcY) * te
        elseif t < P2 then
            -- 阶段2：在圆圈上旋转
            local tp  = (t - P1) / (P2 - P1)
            local ang = e.angle + rotAmt * tp
            x = cx + math.cos(ang) * R - CW / 2
            y = cy + math.sin(ang) * R - FH / 2
        else
            -- 阶段3：旋转后位置 → srcPos（ease-out cubic）
            local tp     = (t - P2) / (1 - P2)
            local te     = 1 - (1 - tp)^3
            local rotAng = e.angle + rotAmt
            local fromX  = cx + math.cos(rotAng) * R - CW / 2
            local fromY  = cy + math.sin(rotAng) * R - FH / 2
            x = fromX + (e.srcX - fromX) * te
            y = fromY + (e.srcY - fromY) * te
        end
        drawCard(vg, x, y, e.card.kind, false)
    end
end

-- ── 遮罩覆盖层绘制 ───────────────────────────────────────────────────────────

local function drawOverlay(vg, LW, LH, title, tr, tg, tb, hint)
    nvgBeginPath(vg); nvgRect(vg,0,0,LW,LH)
    nvgFillColor(vg, nvgRGBA(0,0,0,165)); nvgFill(vg)
    nvgFontFace(vg,"sans"); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 50); nvgFillColor(vg, nvgRGBA(tr,tg,tb,255))
    nvgText(vg, LW/2, LH/2-40, title)
    nvgFontSize(vg, 20); nvgFillColor(vg, nvgRGBA(220,220,220,210))
    nvgText(vg, LW/2, LH/2+22, hint)
end

-- ── 渲染入口 ─────────────────────────────────────────────────────────────────

function M.render(vg, LW, LH, DPR)
    nvgBeginFrame(vg, LW, LH, DPR)
    if Board.state == "menu" then
        drawMenu(vg, LW, LH)
    else
        local bg = nvgLinearGradient(vg,0,0,0,LH,nvgRGBA(20,16,42,255),nvgRGBA(28,20,50,255))
        nvgBeginPath(vg); nvgRect(vg,0,0,LW,LH); nvgFillPaint(vg,bg); nvgFill(vg)

        if Board.shuffleAnim then
            drawShuffleAnim(vg)
        else
            drawACards(vg)
            if #Board.piles > 0 then drawBPiles(vg) end
        end
        drawOverflowCols(vg)
        drawSlot(vg)
        drawAnims(vg)
        drawMoveOutAnims(vg)
        drawUndoAnim(vg)
        drawHUD(vg)
        drawMoveOutBtn(vg, LW, LH)
        drawUndoBtn(vg, LW, LH)
        drawShuffleBtn(vg, LW, LH)

        local st = Board.state
        if st == "win" then
            drawOverlay(vg, LW, LH, "全部通关！",   255,220, 60, "点击返回菜单")
        elseif st == "lose" then
            drawOverlay(vg, LW, LH, "游戏结束",     255,100, 80, "槽位已满 — 点击重新开始")
        end
    end
    nvgEndFrame(vg)
end

return M
