-- ============================================================================
-- yang/Board.lua  ·  游戏状态与逻辑
-- 持有所有可变游戏状态，供 Renderer 直接读取
-- ============================================================================

local Cfg          = require "yang.Config"
local PosGen       = require "yang.PosGen"
local AudioManager = require "Game.AudioManager"
local M            = {}

-- ── 常量引用 ──────────────────────────────────────────────────────────────────
local LEVELS     = Cfg.LEVELS
local YANG_FACE  = Cfg.YANG_FACE
local YANG_X_B   = Cfg.YANG_X_B
local YANG_Y_B   = Cfg.YANG_Y_B
local SLOT_MAX   = Cfg.SLOT_MAX
local ANIM_SPLIT = Cfg.ANIM_SPLIT

-- ── 游戏状态（Renderer 直接读取这些字段）────────────────────────────────────
M.state    = "menu"   -- menu|playing|nextlevel|win|lose
M.curLvl   = 1
---@type table[]
M.allCards = {}
---@type table[]
M.piles    = {}
---@type table[]
M.slot     = {}
---@type table[]
M.anims    = {}

M.shuffleUses = 0   -- 每关可用次数（看广告获得）
M.shuffleAnim = nil  -- 打乱动画状态（nil = 无动画）
M.shuffleAdUsed = false -- 本局是否已看过广告

M.undoUses     = 0   -- 每关撤回次数（看广告获得）
M.lastSlotCard = nil -- 最近一张落入槽位的牌（用于撤回）
M.undoAnim     = nil -- 撤回飞行动画状态
M.undoAdUsed   = false -- 本局是否已看过广告

M.moveOutUses  = 0   -- 移出三张道具次数（看广告获得）
M.moveOutAdUsed = false -- 本局是否已看过广告
M.score        = 0   -- 累计得分（消除一次 +1）
M.overflowCols = {{},{},{}}  -- 3列暂存区，每列堆叠的牌
M.moveAnims    = {}  -- 移出飞行动画列表
M.OVERFLOW_X   = 0  -- 暂存区3列居中起始 X（newGame/init 后更新）

M.transAnim    = nil -- 关卡切换滑入动画 { t, dur, startX, targetX }
M.entryActive  = false -- 第一关入场动画进行中
M.showExitConfirm = false -- 是否显示退出确认弹窗
M.showTicketConfirm = false -- 是否显示免广券确认弹窗
M.ticketConfirmCb   = nil   -- 免广券弹窗确认后的回调 fun()
M.showRescueConfirm = false -- 是否显示救场（移出道具）确认弹窗

-- ── 视觉参数（newGame 后更新）────────────────────────────────────────────────
M.CW          = 42; M.CH          = 50
M.GRID_X      = 21; M.GRID_Y      = 21
M.LAYER_OFF   = 4;  M.CARD_SHADOW = 6
M.PILE_CARDS  = 0
M.FACE_H      = 44   -- CH - CARD_SHADOW

-- 槽位尺寸
M.SLOT_CW     = 52; M.SLOT_CH    = 62
M.SLOT_FACE_H = 56; M.SLOT_SHADOW= 6
M.SLOT_STEP   = 57

-- ── 布局坐标（newGame 后更新）────────────────────────────────────────────────
M.ORIGIN_X = 0; M.ORIGIN_Y = 0
M.AREA_W   = 0
M.PILE1_X  = 0; M.PILE1_Y  = 0
M.PILE2_X  = 0; M.PILE2_Y  = 0
M.SLOT_X   = 0; M.SLOT_Y   = 0

-- ── 屏幕尺寸（由 main.lua 调用 setScreen 初始化）────────────────────────────
M.LW = 0; M.LH = 0

-- ── 基础接口 ─────────────────────────────────────────────────────────────────

function M.setScreen(lw, lh)
    M.LW = lw; M.LH = lh
end

-- 初始化默认视觉参数（防止菜单阶段访问未定义变量）
function M.init()
    local cfg1    = LEVELS[1]
    M.CW          = cfg1.cardW; M.CH          = cfg1.cardH
    M.GRID_X      = cfg1.gridX; M.GRID_Y      = cfg1.gridY
    M.LAYER_OFF   = cfg1.layerOff; M.CARD_SHADOW = cfg1.cardShadow
    M.PILE_CARDS  = 0
    M.FACE_H      = M.CH - M.CARD_SHADOW
    M.SLOT_CW     = 52
    M.SLOT_SHADOW = math.floor(M.SLOT_CW * cfg1.cardShadow / cfg1.cardW)
    M.SLOT_CH     = math.floor(M.SLOT_CW * cfg1.cardH / cfg1.cardW)
    M.SLOT_FACE_H = M.SLOT_CH - M.SLOT_SHADOW
    M.SLOT_STEP   = M.SLOT_CW
    M.SLOT_X      = math.floor((M.LW - M.SLOT_CW * SLOT_MAX) / 2)
    M.shuffleUses = 0
    M.shuffleAnim = nil
    M.shuffleAdUsed = false
    M.undoUses     = 0
    M.lastSlotCard = nil
    M.undoAnim     = nil
    M.undoAdUsed   = false
    M.moveOutUses  = 0
    M.moveOutAdUsed = false
    M.overflowCols = {{},{},{}}
    M.moveAnims    = {}
    M.OVERFLOW_X   = math.floor((M.LW - (2 * M.SLOT_STEP + M.SLOT_CW)) / 2)
end

-- ── 坐标转换 ─────────────────────────────────────────────────────────────────

function M.gridToScreen(card)
    local depth = (card.layerNum - 1) * M.LAYER_OFF
    if card.px then
        return M.ORIGIN_X + card.px + depth, M.ORIGIN_Y + card.py - depth
    else
        return M.ORIGIN_X + card.rolNum * M.GRID_X + depth,
               M.ORIGIN_Y + card.rowNum * M.GRID_Y - depth
    end
end

function M.pilePos(pile, layerNum)
    local depth = M.PILE_CARDS - layerNum
    local dir   = pile.dir or "down"
    local sh    = M.CARD_SHADOW
    if     dir == "down"  then return pile.ox,            pile.oy + depth * sh
    elseif dir == "up"    then return pile.ox,            pile.oy - depth * sh
    elseif dir == "right" then return pile.ox + depth * sh, pile.oy
    else                       return pile.ox - depth * sh, pile.oy
    end
end

function M.pileTop(pile)
    local top = nil
    for _, c in ipairs(pile.cards) do
        if not c.removed and (top == nil or c.layerNum > top.layerNum) then
            top = c
        end
    end
    return top
end

-- ── 遮挡检测（内部）──────────────────────────────────────────────────────────

local function overlaps(a, b)
    if a.px then
        -- X 用卡牌宽度，Y 用卡牌高度（CW≠CH 时避免漏检遮挡）
        return math.abs(a.px - b.px) < M.CW and math.abs(a.py - b.py) < M.CH
    else
        return a.rolNum < b.rolNum + 2 and b.rolNum < a.rolNum + 2
           and a.rowNum < b.rowNum + 2 and b.rowNum < a.rowNum + 2
    end
end

local function buildGroups()
    local g, maxL = {}, 0
    for _, c in ipairs(M.allCards) do
        if not c.removed and c.moldType == 1 then
            local ln = c.layerNum
            if not g[ln] then g[ln] = {} end
            table.insert(g[ln], c)
            if ln > maxL then maxL = ln end
        end
    end
    return g, maxL
end

local function refreshCardState()
    local groups, maxLayer = buildGroups()

    -- 第一步：计算每张牌被多少层直接覆盖（遍历所有更高层，不要求连续）
    local coverMap = {}  -- card → coverLayers
    for _, c in ipairs(M.allCards) do
        if not c.removed and c.moldType == 1 then
            local coverLayers = 0
            for ln = c.layerNum + 1, maxLayer do
                if groups[ln] then
                    for _, above in ipairs(groups[ln]) do
                        if overlaps(c, above) then
                            coverLayers = coverLayers + 1
                            break
                        end
                    end
                end
            end
            coverMap[c] = coverLayers
        end
    end

    -- 第二步：从高层往低层传播 hidden 状态
    -- 规则：如果一张 hidden 牌（coverLayers >= 2）与下方某牌重叠，
    -- 下方牌也必须是 hidden（因为上方牌不渲染会露出下方牌）
    for ln = maxLayer, 1, -1 do
        if groups[ln] then
            for _, c in ipairs(groups[ln]) do
                if coverMap[c] >= 2 then  -- c 是 hidden
                    for lnBelow = ln - 1, 1, -1 do
                        if groups[lnBelow] then
                            for _, below in ipairs(groups[lnBelow]) do
                                if overlaps(c, below) and coverMap[below] < 2 then
                                    coverMap[below] = 2  -- 强制 hidden
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 第三步：赋值状态
    for c, cover in pairs(coverMap) do
        if     cover == 0 then c.state = "bright"
        elseif cover == 1 then c.state = "dim"
        else                    c.state = "hidden"
        end
    end
end

-- ── 槽位（内部）──────────────────────────────────────────────────────────────

local function eliminate()
    local eliminated = {}
    local changed = true
    while changed do
        changed = false
        for i = 1, #M.slot - 2 do
            if M.slot[i].kind == M.slot[i+1].kind
            and M.slot[i+1].kind == M.slot[i+2].kind then
                M.slot[i].removed   = true; table.insert(eliminated, M.slot[i])
                M.slot[i+1].removed = true; table.insert(eliminated, M.slot[i+1])
                M.slot[i+2].removed = true; table.insert(eliminated, M.slot[i+2])
                table.remove(M.slot, i+2)
                table.remove(M.slot, i+1)
                table.remove(M.slot, i)
                changed = true; break
            end
        end
    end
    if #eliminated > 0 then
        M.score = M.score + (#eliminated / 3)  -- 每3张=1次消除=1分
        AudioManager.PlaySFX("card_match")
    end
    return eliminated
end

local function pushSlot(card)
    local pos = #M.slot + 1
    for i = #M.slot, 1, -1 do
        if M.slot[i].kind == card.kind then pos = i + 1; break end
    end
    table.insert(M.slot, pos, card)
    return eliminate()
end

-- ── 布局计算（内部）──────────────────────────────────────────────────────────

local function computeLayout(cfg)
    local nLayers    = #cfg.cardsPerLayer
    local totalDrift = (nLayers - 1) * cfg.layerOff
    local areaW, areaH
    if PosGen.isYangStyle(cfg) then
        areaW = YANG_X_B[#YANG_X_B] + YANG_FACE + totalDrift
        areaH = YANG_Y_B[#YANG_Y_B] + YANG_FACE + cfg.cardShadow
    else
        local maxRolNum = (cfg.maxCols - 1) * 2 + 1
        local maxRowNum = (cfg.maxRows - 1) * 2 + 1
        areaW = maxRolNum * cfg.gridX + cfg.cardW + totalDrift
        areaH = maxRowNum * cfg.gridY + cfg.cardH
    end
    M.AREA_W   = areaW
    M.ORIGIN_X = math.max(4, math.floor((M.LW - areaW) / 2))

    -- 先算槽位尺寸和 Y（不依赖 ORIGIN_Y）
    M.SLOT_CW     = 52
    M.SLOT_SHADOW = math.floor(M.SLOT_CW * cfg.cardShadow / cfg.cardW)
    M.SLOT_CH     = math.floor(M.SLOT_CW * cfg.cardH / cfg.cardW)
    M.SLOT_FACE_H = M.SLOT_CH - M.SLOT_SHADOW
    M.SLOT_STEP   = M.SLOT_CW
    M.SLOT_X      = math.floor((M.LW - M.SLOT_CW * SLOT_MAX) / 2)
    M.SLOT_Y      = M.LH - 56 - M.SLOT_CH - 22

    -- 牌堆垂直居中：在 HUD(32px) 与槽位之间居中
    local topMargin = 32
    local visualH   = areaH + totalDrift   -- 含层叠偏移的完整视觉高度
    local centerTop = topMargin + math.floor((M.SLOT_Y - topMargin - visualH) / 2)
    M.ORIGIN_Y = math.max(topMargin + totalDrift, centerTop + totalDrift)

    local aBottom = M.ORIGIN_Y + areaH
    local pileH   = cfg.cardH + (cfg.pileCards - 1) * cfg.cardShadow
    M.PILE1_X = M.LW * 0.22 - cfg.cardW / 2
    M.PILE1_Y = aBottom + 18
    M.PILE2_X = M.LW * 0.78 - cfg.cardW / 2
    M.PILE2_Y = aBottom + 18

    -- 暂存区3列居中
    M.OVERFLOW_X = math.floor((M.LW - (2 * M.SLOT_STEP + M.SLOT_CW)) / 2)
end

-- ── 新游戏 ───────────────────────────────────────────────────────────────────

function M.newGame(lvl)
    local cfg    = LEVELS[lvl]
    M.curLvl     = lvl
    M.allCards    = {}; M.piles = {}; M.slot = {}; M.anims = {}
    M.state       = "playing"
    M.shuffleUses = 0
    M.shuffleAnim = nil
    M.shuffleAdUsed = false
    M.undoUses     = 0
    M.lastSlotCard = nil
    M.undoAnim     = nil
    M.undoAdUsed   = false
    M.moveOutUses  = 0
    M.moveOutAdUsed = false
    M.showRescueConfirm = false
    if lvl == 1 then M.score = 0 end  -- 从头开始时清零，过关保持累加
    M.overflowCols = {{},{},{}}
    M.moveAnims    = {}
    M.OVERFLOW_X   = 0  -- computeLayout 中重新计算
    M.transAnim    = nil
    M.entryActive  = false

    M.CW = cfg.cardW; M.CH = cfg.cardH
    M.GRID_X = cfg.gridX; M.GRID_Y = cfg.gridY
    M.LAYER_OFF = cfg.layerOff; M.CARD_SHADOW = cfg.cardShadow
    M.PILE_CARDS = cfg.pileCards
    M.FACE_H = M.CH - M.CARD_SHADOW

    local totalA = 0
    for _, c in ipairs(cfg.cardsPerLayer) do totalA = totalA + c end
    local totalB = cfg.useB and cfg.pileCards * 2 or 0

    local seed  = cfg.seed or os.time()

    computeLayout(cfg)

    local yang    = PosGen.isYangStyle(cfg)
    local nLayers = #cfg.cardsPerLayer
    local layerPosList = {}

    if not yang then
        for layerNum, count in ipairs(cfg.cardsPerLayer) do
            layerPosList[layerNum] = PosGen.rectLayerPos(layerNum, count, cfg, seed)
        end
    else
        -- 顶层 = nLayers，A型；向下每层交替A/B
        for layerNum = nLayers, 1, -1 do
            local count       = cfg.cardsPerLayer[layerNum]
            local distFromTop = nLayers - layerNum
            local isTypeA     = (distFromTop % 2 == 0)
            if layerNum == nLayers then
                local allPos = PosGen.yangAllPos(layerNum, true)
                PosGen.shuffle(allPos, seed + layerNum * 31)
                while #allPos > count do table.remove(allPos) end
                layerPosList[layerNum] = allPos
            else
                layerPosList[layerNum] = PosGen.yangAABBPos(
                    layerNum, count, layerPosList[layerNum + 1], seed, isTypeA)
            end
        end
    end

    -- ── 安全网：统计实际放置的 A 区牌数（位置生成可能少于配置值）──
    local actualA = 0
    for layerNum = 1, nLayers do
        actualA = actualA + #(layerPosList[layerNum] or {})
    end
    local actualTotal = actualA + totalB
    -- 确保总数是 3 的倍数（裁掉多余位置）
    local remainder = actualTotal % 3
    if remainder > 0 then
        -- 从最底层开始裁掉多余的位置
        local toRemove = remainder
        for layerNum = 1, nLayers do
            local pos = layerPosList[layerNum]
            if pos and toRemove > 0 then
                while toRemove > 0 and #pos > 0 do
                    table.remove(pos)
                    toRemove = toRemove - 1
                end
            end
            if toRemove <= 0 then break end
        end
        actualTotal = actualTotal - remainder
    end

    -- 按实际牌数生成 kindList，保证每种牌数量是 3 的倍数
    local kinds = PosGen.makeKindList(actualTotal, cfg.kindCount)
    PosGen.shuffle(kinds, seed)

    local ki = 1
    for layerNum = 1, nLayers do
        local pos = layerPosList[layerNum] or {}
        for _, p in ipairs(pos) do
            local id = p.px
                and string.format("%d-px%d-py%d", p.layerNum, p.px, p.py)
                or  string.format("%d-%d-%d",      p.layerNum, p.rolNum, p.rowNum)
            table.insert(M.allCards, {
                id       = id,
                kind     = kinds[ki], layerNum = p.layerNum,
                rolNum   = p.rolNum,  rowNum   = p.rowNum,
                px       = p.px,      py       = p.py,
                moldType = 1, state = "bright", removed = false, pileIdx = 0,
            })
            ki = ki + 1
        end
    end

    if cfg.useB then
        local useHoriz = (math.random(2) == 1)
        local pileDirs = useHoriz and { "left", "right" } or { "down", "down" }
        local sh = M.CARD_SHADOW
        for pi = 1, 2 do
            local dir   = pileDirs[pi]
            local baseX = (pi == 1) and M.PILE1_X or M.PILE2_X
            local ox
            if     dir == "left"  then ox = M.ORIGIN_X + (M.PILE_CARDS - 1) * sh
            elseif dir == "right" then ox = M.ORIGIN_X + M.AREA_W - M.CW - (M.PILE_CARDS - 1) * sh
            else                       ox = baseX
            end
            local pile = {
                ox = ox, oy = (pi == 1) and M.PILE1_Y or M.PILE2_Y,
                dir = dir, cards = {}
            }
            for ln = 1, cfg.pileCards do
                local card = {
                    id = string.format("B%d-%d", pi, ln),
                    kind = kinds[ki], layerNum = ln,
                    rolNum = -1, rowNum = -1,
                    moldType = 2, state = "bright", removed = false, pileIdx = pi,
                }
                table.insert(M.allCards, card)
                table.insert(pile.cards, card)
                ki = ki + 1
            end
            table.insert(M.piles, pile)
        end
    end

    refreshCardState()

    -- 第一关入场动画：每张牌从屏幕顶部外依次掉落
    -- 排序：层号由小到大，同层内按行（Y）再按列（X）
    if lvl == 1 then
        local animCards = {}
        for _, c in ipairs(M.allCards) do
            if c.moldType == 1 and c.state ~= "hidden" then
                table.insert(animCards, c)
            end
        end
        table.sort(animCards, function(a, b)
            if a.layerNum ~= b.layerNum then return a.layerNum < b.layerNum end
            local ay = a.py or (a.rowNum * M.GRID_Y)
            local by2 = b.py or (b.rowNum * M.GRID_Y)
            if ay ~= by2 then return ay < by2 end
            local ax = a.px or (a.rolNum * M.GRID_X)
            local bx = b.px or (b.rolNum * M.GRID_X)
            return ax < bx
        end)

        local CARD_GAP  = 0.035  -- 同层内每张牌之间的延迟
        local LAYER_GAP = 0.05   -- 换层时额外延迟
        local delay     = 0
        local prevLayer = -1
        for _, c in ipairs(animCards) do
            if c.layerNum ~= prevLayer then
                if prevLayer >= 0 then delay = delay + LAYER_GAP end
                prevLayer = c.layerNum
            end
            -- 起始 Y：让牌面底边与屏幕顶部对齐（-CH 处），确保从屏幕外掉入
            local _, sy   = M.gridToScreen(c)
            local startOY = -sy - M.CH
            c.entryStartY  = startOY
            c.entryOffsetY = startOY
            c.entryDelay   = delay
            c.entryT       = 0
            c.entryDur     = 0.50
            delay = delay + CARD_GAP
        end
        M.entryActive = true
    end

    print(string.format("[羊了个羊] %s 开始：A区%d + B区%d = 共%d张，%d种图案",
        cfg.name, actualA, totalB, actualTotal, cfg.kindCount))
end

-- ── 关卡切换动画缓动 ─────────────────────────────────────────────────────────

local function easeOutBack(t)
    local c1 = 0.35
    local c3 = c1 + 1
    return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
end

-- ── 点击处理 ─────────────────────────────────────────────────────────────────

local function checkWinLose()
    local allDone = true
    for _, c in ipairs(M.allCards) do if not c.removed then allDone = false; break end end
    if allDone and #M.slot == 0 then
        if M.curLvl < #LEVELS then
            -- 直接切换下一关，牌堆从右侧滑入+回弹
            M.newGame(M.curLvl + 1)
            local targetX = M.ORIGIN_X
            M.transAnim   = { t = 0, dur = 0.65,
                              startX = M.LW + M.AREA_W, targetX = targetX }
            M.ORIGIN_X    = M.LW + M.AREA_W
        else
            M.state = "win"
        end
    elseif #M.slot >= SLOT_MAX then
        M.state = "lose"
        -- 如果移出道具还没用过广告，自动弹出救场弹窗
        if not M.moveOutAdUsed then
            M.showRescueConfirm = true
        end
    end
end

function M.onCardClick(card)
    if M.entryActive then return end
    if card.removed then return end
    if #M.slot + #M.anims >= SLOT_MAX then return end
    if card.moldType == 1 and card.state ~= "bright" then return end
    if card.moldType == 2 then
        if M.pileTop(M.piles[card.pileIdx]) ~= card then return end
    end

    local srcX, srcY
    if card.moldType == 1 then
        srcX, srcY = M.gridToScreen(card)
    else
        srcX, srcY = M.pilePos(M.piles[card.pileIdx], card.layerNum)
    end

    -- 构建虚拟槽位，计算落点插入位置
    local vSlot = {}
    for _, c in ipairs(M.slot) do table.insert(vSlot, c) end
    for _, a in ipairs(M.anims) do
        local safePos = math.min(a.insertPos, #vSlot + 1)
        table.insert(vSlot, safePos, a.card)
    end
    local insertPos = #vSlot + 1
    for i = #vSlot, 1, -1 do
        if vSlot[i].kind == card.kind then insertPos = i + 1; break end
    end
    local dstX = M.SLOT_X + (insertPos - 1) * M.SLOT_STEP
    local dstY = M.SLOT_Y + 7

    AudioManager.PlaySFX("card_click")

    card.removed = true
    refreshCardState()

    table.insert(M.anims, {
        card      = card,
        srcX      = srcX,       srcY = srcY,
        dstX      = dstX,       dstY = dstY,
        insertPos = insertPos,
        t         = 0,          dur  = 0.55,
    })
end

-- ── 碰撞检测 ─────────────────────────────────────────────────────────────────

function M.hitA(mx, my)
    local best = nil
    for _, c in ipairs(M.allCards) do
        if not c.removed and c.moldType == 1 and c.state == "bright" then
            local sx, sy = M.gridToScreen(c)
            if mx >= sx and mx <= sx + M.CW and my >= sy and my <= sy + M.FACE_H then
                if not best or c.layerNum > best.layerNum then best = c end
            end
        end
    end
    return best
end

function M.hitB(mx, my)
    for _, pile in ipairs(M.piles) do
        local top = M.pileTop(pile)
        if top then
            local sx, sy = M.pilePos(pile, top.layerNum)
            if mx >= sx and mx <= sx + M.CW and my >= sy and my <= sy + M.FACE_H then
                return top
            end
        end
    end
    return nil
end

-- ── 道具：随机打乱 ───────────────────────────────────────────────────────────

function M.shuffleCards()
    if M.shuffleUses <= 0 then return end
    if M.shuffleAnim then return end  -- 动画进行中，禁止重复触发

    -- ── 1. 收集【可见牌】作为动画粒子 ────────────────────────────────────────
    --   A区：state ~= "hidden" 的牌（bright + dim）
    --   B区：每堆顶牌（top card）
    local entries = {}
    for _, c in ipairs(M.allCards) do
        if not c.removed then
            local show = false
            if c.moldType == 1 and c.state ~= "hidden" then
                show = true
            elseif c.moldType == 2 and M.pileTop(M.piles[c.pileIdx]) == c then
                show = true
            end
            if show then
                local sx, sy
                if c.moldType == 1 then
                    sx, sy = M.gridToScreen(c)
                else
                    sx, sy = M.pilePos(M.piles[c.pileIdx], c.layerNum)
                end
                table.insert(entries, { card=c, srcX=sx, srcY=sy })
            end
        end
    end
    if #entries == 0 then return end

    -- ── 2. 以可见牌的重心作为圆圈中心（即牌堆中间）──────────────────────────
    local n      = #entries
    local cx, cy = 0, 0
    for _, e in ipairs(entries) do
        cx = cx + e.srcX + M.CW  / 2
        cy = cy + e.srcY + M.FACE_H / 2
    end
    cx = cx / n
    cy = cy / n

    -- ── 3. 为每张可见牌分配圆圈位置 ─────────────────────────────────────────
    -- 半径：让圆圈放得下 n 张牌（不超过屏幕边距）
    local minR   = n * (M.CW + 2) / (2 * math.pi)  -- 卡牌刚好不挤压时的最小半径
    local maxR   = math.min(M.LW, M.LH) * 0.30
    local radius = math.max(50, math.min(minR, maxR))
    for i, e in ipairs(entries) do
        local ang  = (i - 1) / n * math.pi * 2
        e.angle = ang
        e.circX = cx + math.cos(ang) * radius - M.CW / 2
        e.circY = cy + math.sin(ang) * radius - M.FACE_H / 2
    end

    -- ── 3. 预计算全部未移除牌（含隐藏）的新 kind 顺序 ────────────────────────
    --   隐藏牌不播动画，但 kind 同样被打乱（在动画中途静默赋值）
    local allUnremoved = {}
    for _, c in ipairs(M.allCards) do
        if not c.removed then table.insert(allUnremoved, c) end
    end
    local kinds = {}
    for _, c in ipairs(allUnremoved) do table.insert(kinds, c.kind) end
    math.randomseed(os.time() + math.random(99999))
    for i = #kinds, 2, -1 do
        local j  = math.random(1, i)
        kinds[i], kinds[j] = kinds[j], kinds[i]
    end

    AudioManager.PlaySFX("card_shuffle")

    M.shuffleUses = M.shuffleUses - 1
    M.shuffleAnim = {
        t          = 0,
        dur        = 1.6,      -- 总时长（秒）
        entries    = entries,  -- 可见牌动画条目
        cx         = cx, cy = cy,
        radius     = radius,
        rotAmt     = math.pi,  -- 旋转 180°
        allCards   = allUnremoved,
        kinds      = kinds,
        shuffled   = false,    -- 是否已在中途赋值
    }
    print(string.format("[打乱] 动画开始：%d 张可见牌，剩余 %d 次", n, M.shuffleUses))
end

-- ── 道具：撤回上一步 ─────────────────────────────────────────────────────────

function M.undoCard()
    if M.undoUses    <= 0 then return end
    if M.shuffleAnim       then return end
    if M.undoAnim          then return end
    if #M.anims      >  0  then return end
    if not M.lastSlotCard  then return end

    -- 确认该牌仍在槽位中（没被三消消掉）
    local card     = M.lastSlotCard
    local slotIdx  = nil
    for i, c in ipairs(M.slot) do
        if c == card then slotIdx = i; break end
    end
    if not slotIdx then
        M.lastSlotCard = nil   -- 已被消除，清除指针
        return
    end

    -- ① 起点：牌在槽位的当前坐标
    local srcX = card.slotX or M.SLOT_X
    local srcY = M.SLOT_Y + 7

    -- ② 终点：牌在牌堆的原始坐标
    local dstX, dstY
    if card.moldType == 1 then
        dstX, dstY = M.gridToScreen(card)
    else
        dstX, dstY = M.pilePos(M.piles[card.pileIdx], card.layerNum)
    end

    -- ③ 从槽位移除，重排剩余牌 X
    table.remove(M.slot, slotIdx)
    for idx, c in ipairs(M.slot) do
        c.slotX = M.SLOT_X + (idx - 1) * M.SLOT_STEP
    end

    M.lastSlotCard = nil
    M.undoUses     = M.undoUses - 1
    if M.state == "lose" then M.state = "playing" end

    M.undoAnim = {
        card = card,
        srcX = srcX, srcY = srcY,
        dstX = dstX, dstY = dstY,
        t    = 0,
        dur  = 0.45,
    }
    print(string.format("[撤回] 动画开始 kind=%d，剩余 %d 次", card.kind, M.undoUses))
end

-- ── 道具：移出三张 ───────────────────────────────────────────────────────────

-- 暂存区第 colIdx 列的左上角 X（居中于屏幕，3列等距排列）
function M.overflowColX(colIdx)
    return M.OVERFLOW_X + (colIdx - 1) * M.SLOT_STEP
end

-- 暂存区第 stackPos 层的 Y（牌堆式：第1张在底部，往上每张只偏移 SLOT_SHADOW）
function M.overflowCardY(stackPos)
    local anchor = M.SLOT_Y - 4        -- 堆底锚点（卡槽上方4px）
    return anchor - M.SLOT_CH - (stackPos - 1) * M.SLOT_SHADOW
end

function M.moveOutCards()
    if M.moveOutUses  <= 0 then return end
    if M.shuffleAnim        then return end
    if M.undoAnim           then return end
    if #M.anims       >  0  then return end
    if #M.moveAnims   >  0  then return end
    if #M.slot        <  3  then return end

    M.moveOutUses = M.moveOutUses - 1

    -- 将进入哪一层（当前各列已有几张牌，下一张是第几层）
    local stackPos = #M.overflowCols[1] + 1

    -- 取出前 3 张，记录各自的槽位坐标
    local taken = {}
    for _ = 1, 3 do
        local card = M.slot[1]
        local srcX = card.slotX or M.SLOT_X
        table.insert(taken, { card = card, srcX = srcX })
        table.remove(M.slot, 1)
    end

    -- 重排剩余槽位牌 X
    for idx, c in ipairs(M.slot) do
        c.slotX = M.SLOT_X + (idx - 1) * M.SLOT_STEP
    end

    -- 若 lastSlotCard 在被取出的牌中，清除指针
    for _, item in ipairs(taken) do
        if item.card == M.lastSlotCard then M.lastSlotCard = nil; break end
    end

    -- 移出后槽位不再满，恢复 playing 状态
    if M.state == "lose" then M.state = "playing" end

    -- 创建飞行动画
    local srcY = M.SLOT_Y + 7
    for colIdx, item in ipairs(taken) do
        local dstX = M.overflowColX(colIdx)
        local dstY = M.overflowCardY(stackPos)
        table.insert(M.moveAnims, {
            card     = item.card,
            colIdx   = colIdx,
            stackPos = stackPos,
            srcX     = item.srcX, srcY = srcY,
            dstX     = dstX,      dstY = dstY,
            t        = 0,
            dur      = 0.40,
        })
    end
    print(string.format("[移出] 动画开始，stackPos=%d，剩余 %d 次", stackPos, M.moveOutUses))
end

-- 点击暂存区某列顶牌，行为与点击普通牌完全一致（同种插位 + 三消）
function M.clickOverflowCard(colIdx)
    if M.shuffleAnim                    then return end
    if M.undoAnim                       then return end
    if #M.moveAnims > 0                 then return end
    if #M.slot + #M.anims >= SLOT_MAX   then return end
    local col = M.overflowCols[colIdx]
    if #col == 0 then return end

    local stackPos = #col
    local card     = col[stackPos]
    table.remove(col, stackPos)

    local srcX = M.overflowColX(colIdx)
    local srcY = M.overflowCardY(stackPos)

    -- 与 onCardClick 完全相同的虚拟槽位 + 同种插位计算
    local vSlot = {}
    for _, c in ipairs(M.slot) do table.insert(vSlot, c) end
    for _, a in ipairs(M.anims) do
        local safePos = math.min(a.insertPos, #vSlot + 1)
        table.insert(vSlot, safePos, a.card)
    end
    local insertPos = #vSlot + 1
    for i = #vSlot, 1, -1 do
        if vSlot[i].kind == card.kind then insertPos = i + 1; break end
    end
    local dstX = M.SLOT_X + (insertPos - 1) * M.SLOT_STEP
    local dstY = M.SLOT_Y + 7

    table.insert(M.anims, {
        card      = card,
        srcX      = srcX,       srcY = srcY,
        dstX      = dstX,       dstY = dstY,
        insertPos = insertPos,
        t         = 0,          dur  = 0.55,
    })
    print(string.format("[暂存点击] col=%d 牌飞入槽位 insertPos=%d", colIdx, insertPos))
end

-- ── 帧更新 ───────────────────────────────────────────────────────────────────

function M.update(dt)
    -- 关卡切换滑入动画推进
    if M.transAnim then
        local ta = M.transAnim
        ta.t = math.min(ta.t + dt / ta.dur, 1.0)
        local te = easeOutBack(ta.t)
        M.ORIGIN_X = math.floor(ta.startX + (ta.targetX - ta.startX) * te)
        if ta.t >= 1.0 then
            M.ORIGIN_X = ta.targetX
            M.transAnim = nil
        end
    end

    -- 第一关入场动画推进
    if M.entryActive then
        local anyLeft = false
        for _, c in ipairs(M.allCards) do
            if c.entryOffsetY ~= nil then
                if c.entryDelay > 0 then
                    c.entryDelay = math.max(0, c.entryDelay - dt)
                    anyLeft = true
                else
                    c.entryT = math.min(c.entryT + dt, c.entryDur)
                    local p  = c.entryT / c.entryDur
                    local te = 1 - (1 - p)^3   -- easeOutCubic 减速落下
                    c.entryOffsetY = c.entryStartY * (1 - te)
                    if c.entryT >= c.entryDur then
                        c.entryOffsetY = nil
                    else
                        anyLeft = true
                    end
                end
            end
        end
        if not anyLeft then M.entryActive = false end
    end

    -- 打乱动画推进
    if M.shuffleAnim then
        local anim = M.shuffleAnim
        anim.t = math.min(anim.t + dt / anim.dur, 1.0)
        -- t=0.5 时静默赋值所有未移除牌（含隐藏牌）
        if not anim.shuffled and anim.t >= 0.5 then
            for i2, c in ipairs(anim.allCards) do c.kind = anim.kinds[i2] end
            anim.shuffled = true
            refreshCardState()
            print("[打乱] 中途赋值完成，所有牌 kind 已更新")
        end
        if anim.t >= 1.0 then
            M.shuffleAnim = nil
            print("[打乱] 动画结束")
        end
    end

    -- 撤回飞行动画推进
    if M.undoAnim then
        local ua = M.undoAnim
        ua.t = math.min(ua.t + dt / ua.dur, 1.0)
        if ua.t >= 1.0 then
            -- 动画结束：牌归回原位
            ua.card.removed = false
            ua.card.slotX   = nil
            refreshCardState()
            M.undoAnim = nil
            print("[撤回] 动画结束")
        end
    end

    -- 移出动画推进
    local mi = 1
    while mi <= #M.moveAnims do
        local ma = M.moveAnims[mi]
        ma.t = math.min(ma.t + dt / ma.dur, 1.0)
        if ma.t >= 1.0 then
            table.insert(M.overflowCols[ma.colIdx], ma.card)
            table.remove(M.moveAnims, mi)
        else
            mi = mi + 1
        end
    end

    local i = 1
    while i <= #M.anims do
        local a = M.anims[i]
        a.t = a.t + dt / a.dur
        if a.t >= 1.0 then
            table.remove(M.anims, i)
            a.card.slotX = a.dstX
            pushSlot(a.card)
            M.lastSlotCard = a.card  -- 记录最近落槽的牌，供撤回使用
            checkWinLose()
        else
            i = i + 1
        end
    end
    -- 驱动槽位牌 X 位置动画
    local slotSpeed = M.SLOT_STEP / 0.12
    for idx, c in ipairs(M.slot) do
        local targetX = M.SLOT_X + (idx - 1) * M.SLOT_STEP
        for _, a in ipairs(M.anims) do
            if a.t >= ANIM_SPLIT and a.insertPos <= idx then
                targetX = targetX + M.SLOT_STEP
            end
        end
        if c.slotX == nil then c.slotX = targetX end
        local dx = targetX - c.slotX
        if math.abs(dx) > 0.5 then
            local step = slotSpeed * dt
            c.slotX = c.slotX + (math.abs(dx) <= step and dx or (dx > 0 and step or -step))
        else
            c.slotX = targetX
        end
    end
end

return M
