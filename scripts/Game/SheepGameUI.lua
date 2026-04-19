-- Game/SheepGameUI.lua
-- 羊了个羊 —— 真实两关设计
-- 第一关：3种花色，2层，必过
-- 第二关：13种花色，6层，78张，极难（<1% 通关率）
--
-- 【修复说明】
-- ClearChildren 在已有子节点的容器上调用会破坏 UrhoX 指针状态，
-- 导致后续所有子节点不可点击。
-- 因此网格渲染改为：
--   - 初始建格：AddChild（容器本来是空的，安全）
--   - 点击移除：RemoveChild（只移除被点击的牌）
--   - 颜色变化：SetStyle（原地更新，无需重建）
--   - 动画：SetStyle 每帧更新颜色
--   - 重开/换关：延迟到 SheepUI_OnUpdate（Update 事件内 ClearChildren 安全）

local SheepGameUI = {}

---@type any
local _UI     = nil
---@type fun()|nil
local _onBack = nil

-- ============================================================
-- 渲染常量
-- ============================================================
local TILE_W    = 50
local TILE_H    = 50
local TILE_GAP  = 3
local TILE_STEP = TILE_W + TILE_GAP  -- 53
local LAYER_OX  = 25   -- TILE_W/2：上层牌中心在下层4牌角交叉点
local LAYER_OY  = 25   -- TILE_H/2
local MAX_TRAY  = 7
local ANIM_DUR  = 0.20

local GRAY_BG     = { 170, 178, 168, 255 }
local GRAY_BORDER = { 128, 135, 125, 155 }
local GRAY_FC     = { 120, 128, 118, 200 }

-- ============================================================
-- 牌型
-- ============================================================
local TYPES = {
    { label="⭐", bg={215,225,255,255}, border={95,130,255,255},  fc={25,50,185,255}  },
    { label="🦀", bg={255,208,185,255}, border={225,85,45,255},   fc={150,25,0,255}   },
    { label="🌽", bg={255,244,172,255}, border={195,148,0,255},   fc={115,70,0,255}   },
    { label="🍀", bg={185,238,195,255}, border={45,168,75,255},   fc={10,88,32,255}   },
    { label="💎", bg={205,232,255,255}, border={45,118,235,255},  fc={10,48,178,255}  },
    { label="🔥", bg={255,195,175,255}, border={235,65,18,255},   fc={150,20,0,255}   },
    { label="🌙", bg={238,225,255,255}, border={148,88,235,255},  fc={68,10,172,255}  },
    { label="🔔", bg={255,238,192,255}, border={212,150,0,255},   fc={132,70,0,255}   },
    { label="🐟", bg={185,225,242,255}, border={38,128,198,255},  fc={8,72,145,255}   },
    { label="🌸", bg={255,212,225,255}, border={225,78,118,255},  fc={152,18,62,255}  },
    { label="☁️",  bg={230,238,255,255}, border={138,165,222,255}, fc={58,88,172,255}  },
    { label="🐦", bg={195,238,218,255}, border={38,165,98,255},   fc={8,98,48,255}    },
    { label="🎂", bg={255,228,208,255}, border={212,118,58,255},  fc={145,52,8,255}   },
}

-- ============================================================
-- 关卡配置
-- ============================================================
local LEVEL_CONFIGS = {
    {
        numTypes=3, perType=6, numLayers=2,
        bgColor={88,158,68,255},
        layout={
            {cols=4, rows=3},
            {cols=3, rows=2},
        },
    },
    {
        numTypes=13, perType=6, numLayers=6,
        bgColor={20,30,80,255},
        layout={
            {cols=5, rows=5},
            {cols=4, rows=4},
            {cols=4, rows=3},
            {cols=3, rows=3},
            {cols=2, rows=4},
            {cols=2, rows=4},
        },
    },
}

-- ============================================================
-- 游戏状态
-- ============================================================
---@class SheepTile
---@field col number
---@field row number
---@field layer number
---@field typeId number
---@field removed boolean
---@field blocked boolean

---@type SheepTile[]
local _tiles  = {}
---@type number[]
local _tray   = {}
local _level  = 1
local _over   = false
local _won    = false

local _undoUsed     = false
local _undoSnapshot = nil

local _animTileSet = {}
local _animTimer   = -1
local _scale       = 1.0

-- ============================================================
-- Widget 引用（原地更新，避免 ClearChildren）
-- ============================================================
-- 每张牌对应的 Panel/Label widget
local _tilePanel  = {}   -- {[tileObj] = panelWidget}
local _tileLabel  = {}   -- {[tileObj] = labelWidget}

-- 延迟操作标志（从 SheepUI_OnUpdate 中安全执行）
local _pendingLevel = 0   -- 0=无; >0=切换到该关卡
local _pendingReset = false  -- true=重置当前关卡

-- 整体 UI 引用
local _gridContainer = nil
local _trayPanel     = nil
local _infoLabel     = nil
local _btnUndo       = nil

-- 前向声明
local RebuildTray
local RebuildInfo
local UpdateBlocked
local BuildGrid
local BuildOverlay

-- ============================================================
-- 工具函数
-- ============================================================
local function Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function LerpColor(c1, c2, t)
    return {
        math.floor(c1[1] + (c2[1]-c1[1]) * t),
        math.floor(c1[2] + (c2[2]-c1[2]) * t),
        math.floor(c1[3] + (c2[3]-c1[3]) * t),
        math.floor(c1[4] + (c2[4]-c1[4]) * t),
    }
end

local function CountRemaining()
    local n = 0
    for _, t in ipairs(_tiles) do
        if not t.removed then n = n + 1 end
    end
    return n
end

-- ============================================================
-- 遮挡检测
-- 层L的格(c,r)被层L+1的格(c2,r2)遮挡，当且仅当：
--   dc = c2-c ∈ {-1,0}  AND  dr = r2-r ∈ {0,1}
-- ============================================================
UpdateBlocked = function()
    for _, tile in ipairs(_tiles) do
        if tile.removed then
            tile.blocked = false
        else
            tile.blocked = false
            local L, c, r = tile.layer, tile.col, tile.row
            for _, t2 in ipairs(_tiles) do
                if not t2.removed and t2.layer == L + 1 then
                    local dc = t2.col - c
                    local dr = t2.row - r
                    if (dc == -1 or dc == 0) and (dr == 0 or dr == 1) then
                        tile.blocked = true
                        break
                    end
                end
            end
        end
    end
end

-- ============================================================
-- 生成牌组
-- ============================================================
local function BuildTiles(cfg)
    local pool = {}
    for i = 1, cfg.numTypes do
        for _ = 1, cfg.perType do table.insert(pool, i) end
    end
    Shuffle(pool)
    local tiles, poolIdx = {}, 1
    for layerIdx, def in ipairs(cfg.layout) do
        local offX = def.offX or 0
        local offY = def.offY or 0
        for r = 0, def.rows - 1 do
            for c = 0, def.cols - 1 do
                table.insert(tiles, {
                    col=c+offX, row=r+offY, layer=layerIdx,
                    typeId=pool[poolIdx], removed=false, blocked=false,
                })
                poolIdx = poolIdx + 1
            end
        end
    end
    return tiles
end

local function DeepCopyTiles(src)
    local dst = {}
    for _, t in ipairs(src) do
        table.insert(dst, {
            col=t.col, row=t.row, layer=t.layer,
            typeId=t.typeId, removed=t.removed, blocked=t.blocked,
        })
    end
    return dst
end

-- ============================================================
-- 初始化关卡
-- ============================================================
local function InitLevel(lvl)
    _level        = lvl
    _tray         = {}
    _over         = false
    _won          = false
    _undoUsed     = false
    _undoSnapshot = nil
    _animTileSet  = {}
    _animTimer    = -1
    _tilePanel    = {}
    _tileLabel    = {}
    _tiles        = BuildTiles(LEVEL_CONFIGS[lvl])
    UpdateBlocked()
end

-- ============================================================
-- 托盘管理
-- ============================================================
local function TrayInsert(typeId)
    local pos = #_tray + 1
    for i = #_tray, 1, -1 do
        if _tray[i] == typeId then pos = i + 1; break end
    end
    table.insert(_tray, pos, typeId)
end

local function TrayCheckMatch()
    local i = 1
    while i <= #_tray - 2 do
        if _tray[i] == _tray[i+1] and _tray[i+1] == _tray[i+2] then
            table.remove(_tray, i+2)
            table.remove(_tray, i+1)
            table.remove(_tray, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================
-- 撤销
-- ============================================================
local function SaveUndoSnapshot()
    _undoSnapshot = {
        tiles = DeepCopyTiles(_tiles),
        tray  = { table.unpack(_tray) },
    }
end

local function DoUndo()
    if _over or _won or _undoUsed or not _undoSnapshot then return end
    _undoUsed     = true
    _tiles        = _undoSnapshot.tiles
    _tray         = _undoSnapshot.tray
    _undoSnapshot = nil
    _animTileSet  = {}
    _animTimer    = -1
    UpdateBlocked()
    if _btnUndo then _btnUndo:SetStyle({ opacity = 0.35 }) end
    -- 撤销后牌组变化大，通过 pendingReset 重建整个网格
    _pendingReset = true
end

local function DoShuffle()
    if _over or _won then return end
    local alive, types = {}, {}
    for _, t in ipairs(_tiles) do
        if not t.removed then
            table.insert(alive, t)
            table.insert(types, t.typeId)
        end
    end
    Shuffle(types)
    for i, t in ipairs(alive) do t.typeId = types[i] end
    _animTileSet = {}
    _animTimer   = -1
    UpdateBlocked()
    -- typeId 改变，需要重建全部 widget（label/color 都变）
    _pendingReset = true
end

-- ============================================================
-- 坐标计算
-- ============================================================
local function TilePixelPos(tile, cfg)
    local baseY = (cfg.numLayers - 1) * LAYER_OY
    local px    = tile.col * TILE_STEP + (tile.layer - 1) * LAYER_OX
    local py    = baseY + tile.row * TILE_STEP - (tile.layer - 1) * LAYER_OY
    return math.floor(px * _scale), math.floor(py * _scale)
end

local function ContainerSize(cfg)
    local maxCols, maxRows = 0, 0
    for _, def in ipairs(cfg.layout) do
        local c = def.cols + (def.offX or 0)
        local r = def.rows + (def.offY or 0)
        if c > maxCols then maxCols = c end
        if r > maxRows then maxRows = r end
    end
    local w = maxCols * TILE_STEP + (cfg.numLayers - 1) * LAYER_OX + TILE_W
    local h = maxRows * TILE_STEP + (cfg.numLayers - 1) * LAYER_OY + TILE_H
    return math.floor(w * _scale), math.floor(h * _scale)
end

-- ============================================================
-- 颜色查询（含动画插值）
-- ============================================================
local function GetTileColors(tile, animT)
    local info = TYPES[tile.typeId]
    local t    = math.max(0, math.min(1, animT or 1))
    local isAnim = _animTileSet[tile] == true
    if tile.blocked then
        return GRAY_BG, GRAY_BORDER, GRAY_FC
    elseif isAnim and t < 1 then
        return LerpColor(GRAY_BG, info.bg, t),
               LerpColor(GRAY_BORDER, info.border, t),
               LerpColor(GRAY_FC, info.fc, t)
    else
        return info.bg, info.border, info.fc
    end
end

-- ============================================================
-- 原地更新单张牌颜色（SetStyle，无需重建 widget）
-- ============================================================
local function RefreshTile(tile, animT)
    local panel = _tilePanel[tile]
    local label = _tileLabel[tile]
    if not panel then return end
    local bg, border, fc = GetTileColors(tile, animT)
    panel:SetStyle({ backgroundColor = bg, borderColor = border })
    if label then label:SetStyle({ fontColor = fc }) end
end

-- ============================================================
-- 移除单张牌的 widget（RemoveChild，不影响其他牌）
-- ============================================================
local function RemoveTileWidget(tile)
    local panel = _tilePanel[tile]
    if panel then
        _gridContainer:RemoveChild(panel)
        _tilePanel[tile] = nil
        _tileLabel[tile] = nil
    end
end

-- ============================================================
-- 创建单张牌的 widget 并注册 onClick
-- ============================================================
local function MakeTileWidget(tile)
    local info    = TYPES[tile.typeId]
    local cfg     = LEVEL_CONFIGS[_level]
    local px, py  = TilePixelPos(tile, cfg)
    local tileRef = tile
    local tw      = math.floor(TILE_W * _scale)
    local th      = math.floor(TILE_H * _scale)
    local fontSize= math.floor(20 * _scale)
    local bg, border, fc = GetTileColors(tile)

    local labelWidget = _UI.Label { text=info.label, fontSize=fontSize, fontColor=fc }
    local panelWidget = _UI.Panel {
        position        = "absolute",
        left            = px,
        top             = py,
        width           = tw,
        height          = th,
        borderRadius    = math.floor(9 * _scale),
        borderWidth     = 2,
        borderColor     = border,
        backgroundColor = bg,
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "auto",
        onClick = function()
            if tileRef.removed or tileRef.blocked or _over or _won then return end
            if #_tray >= MAX_TRAY then return end
            if _animTimer >= 0 then return end

            if not _undoUsed then SaveUndoSnapshot() end

            local wasBlocked = {}
            for _, t2 in ipairs(_tiles) do wasBlocked[t2] = t2.blocked end

            tileRef.removed = true
            TrayInsert(tileRef.typeId)
            TrayCheckMatch()
            UpdateBlocked()

            -- 移除该牌的 widget（RemoveChild，不影响其他牌）
            RemoveTileWidget(tileRef)

            -- 找新暴露的牌并开始动画
            _animTileSet = {}
            local hasAnim = false
            for _, t2 in ipairs(_tiles) do
                if not t2.removed and wasBlocked[t2] and not t2.blocked then
                    _animTileSet[t2] = true
                    hasAnim = true
                    RefreshTile(t2, 0)   -- 立即显示为灰色起始帧
                end
            end

            -- 检查胜负
            if CountRemaining() == 0 and #_tray == 0 then
                _won = true
            elseif #_tray >= MAX_TRAY then
                _over = true
            end

            if hasAnim and not _over and not _won then
                _animTimer = 0
            else
                _animTileSet = {}
                _animTimer   = -1
            end

            -- 托盘和信息可以直接更新（它们的 ClearChildren 在自己容器里，不影响 _gridContainer）
            RebuildTray()
            RebuildInfo()

            -- 胜负遮罩：只用 AddChild，从 onClick 直接调用安全
            if _over or _won then
                BuildOverlay()
            end
        end,
        children = { labelWidget },
    }

    _tilePanel[tile] = panelWidget
    _tileLabel[tile] = labelWidget
    return panelWidget
end

-- ============================================================
-- 初始建格（仅在空容器或 Update 事件中调用）
-- ============================================================
BuildGrid = function()
    -- 按层排序（低层先加，高层后加→渲染在上方）
    local sorted = {}
    for _, tile in ipairs(_tiles) do
        if not tile.removed then table.insert(sorted, tile) end
    end
    table.sort(sorted, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        if a.row   ~= b.row   then return a.row   < b.row   end
        return a.col < b.col
    end)
    for _, tile in ipairs(sorted) do
        _gridContainer:AddChild(MakeTileWidget(tile))
    end
end

-- ============================================================
-- 胜负遮罩（在 Update 中安全构建，deferred）
-- ============================================================
BuildOverlay = function()
    if not (_over or _won) then return end
    local msg  = _won  and "全部消除！🎉" or "托盘已满！😢"
    local sub  = _won  and "恭喜通关！" or "再试一次吧~"
    local mclr = _won  and {38,162,58,255} or {208,50,50,255}
    local bgC  = _won  and {200,242,205,228} or {242,205,200,228}

    local btns = _UI.Panel { flexDirection="row", gap=12, marginTop=16 }
    btns:AddChild(_UI.Panel {
        paddingLeft=18, paddingRight=18, paddingTop=9, paddingBottom=9,
        borderRadius=9, borderWidth=2,
        borderColor={52,168,72,200}, backgroundColor={212,245,212,242},
        pointerEvents="auto",
        onClick=function()
            if _btnUndo then _btnUndo:SetStyle({ opacity = 1.0 }) end
            _pendingLevel = _level   -- 延迟重置到当前关
        end,
        children={ _UI.Label{text="再来一局", fontSize=14, fontColor={20,112,42,255}} },
    })
    if _won and _level < #LEVEL_CONFIGS then
        btns:AddChild(_UI.Panel {
            paddingLeft=18, paddingRight=18, paddingTop=9, paddingBottom=9,
            borderRadius=9, borderWidth=2,
            borderColor={85,138,235,200}, backgroundColor={212,225,255,242},
            pointerEvents="auto",
            onClick=function()
                if _btnUndo then _btnUndo:SetStyle({ opacity = 1.0 }) end
                _pendingLevel = _level + 1   -- 延迟切换到下一关
            end,
            children={ _UI.Label{text="挑战第二关 ▶", fontSize=14, fontColor={32,62,195,255}} },
        })
    end
    _gridContainer:AddChild(_UI.Panel {
        position="absolute", top=0, left=0, right=0, bottom=0,
        backgroundColor=bgC,
        justifyContent="center", alignItems="center",
        children={
            _UI.Label{text=msg, fontSize=26, fontColor=mclr},
            _UI.Label{text=sub, fontSize=13, fontColor={50,85,50,215}, marginTop=5},
            btns,
        },
    })
end

-- ============================================================
-- 托盘和信息更新（各自容器内 ClearChildren，不影响网格）
-- ============================================================
RebuildTray = function()
    if not _trayPanel then return end
    _trayPanel:ClearChildren()
    for i = 1, MAX_TRAY do
        local tid = _tray[i]
        if tid then
            local info = TYPES[tid]
            _trayPanel:AddChild(_UI.Panel {
                width=40, height=40,
                borderRadius=8, borderWidth=2,
                borderColor=info.border, backgroundColor=info.bg,
                justifyContent="center", alignItems="center",
                children={ _UI.Label{text=info.label, fontSize=17, fontColor=info.fc} },
            })
        else
            _trayPanel:AddChild(_UI.Panel {
                width=40, height=40,
                borderRadius=8, borderWidth=1,
                borderColor={145,155,145,88}, backgroundColor={178,190,178,42},
            })
        end
    end
end

RebuildInfo = function()
    if not _infoLabel then return end
    local lbl = _level == 1 and "第1关（教程）" or "第2关（地狱）"
    _infoLabel:SetText(lbl .. "  剩 " .. CountRemaining() .. " 张")
end

-- ============================================================
-- 全局 Update 事件
-- 所有需要 ClearChildren 的操作都在这里安全执行
-- ============================================================
function SheepUI_OnUpdate(_, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 处理延迟关卡切换（含重开）
    if _pendingLevel > 0 then
        local lvl = _pendingLevel
        _pendingLevel = 0
        _pendingReset = false
        _animTimer    = -1
        _animTileSet  = {}
        InitLevel(lvl)
        _gridContainer:ClearChildren()   -- 此处 ClearChildren 安全（来自 Update 事件）
        BuildGrid()
        RebuildTray()
        RebuildInfo()
        return
    end

    -- 处理延迟重置（undo/shuffle 后网格重建）
    if _pendingReset then
        _pendingReset = false
        _animTimer    = -1
        _animTileSet  = {}
        _tilePanel    = {}
        _tileLabel    = {}
        _gridContainer:ClearChildren()   -- 安全
        BuildGrid()
        BuildOverlay()
        RebuildTray()
        RebuildInfo()
        return
    end

    -- 动画推进（SetStyle 原地更新颜色，不重建 widget）
    if _animTimer < 0 then return end
    _animTimer = _animTimer + dt
    local t = math.min(1.0, _animTimer / ANIM_DUR)
    for tile, _ in pairs(_animTileSet) do
        RefreshTile(tile, t)
    end
    if _animTimer >= ANIM_DUR then
        for tile, _ in pairs(_animTileSet) do
            RefreshTile(tile, 1.0)
        end
        _animTileSet = {}
        _animTimer   = -1
    end
end
SubscribeToEvent("Update", "SheepUI_OnUpdate")

-- ============================================================
-- 操作按钮工厂
-- ============================================================
local function ActionBtn(label, clr, fn)
    return _UI.Panel {
        flex=1, paddingTop=9, paddingBottom=9,
        borderRadius=9, borderWidth=2,
        borderColor=clr, backgroundColor={200,220,200,228},
        justifyContent="center", alignItems="center",
        pointerEvents="auto",
        onClick=function()
            fn()
            -- fn() 内部可能设置 _pendingReset，Update 中处理
            RebuildTray()
            RebuildInfo()
        end,
        children={ _UI.Label{text=label, fontSize=13, fontColor=clr} },
    }
end

-- ============================================================
-- 页面构建
-- ============================================================
function SheepGameUI.CreatePage(uiModule)
    _UI = uiModule

    local physW  = graphics:GetWidth()
    local logW   = physW / graphics:GetDPR()
    local availW = logW - 24
    local maxRawW = 5 * TILE_STEP + 5 * LAYER_OX + TILE_W
    _scale = math.min(1.0, availW / maxRawW)

    InitLevel(1)

    local maxW, maxH = 0, 0
    for _, cfg in ipairs(LEVEL_CONFIGS) do
        local w, h = ContainerSize(cfg)
        if w > maxW then maxW = w end
        if h > maxH then maxH = h end
    end
    _gridContainer = _UI.Panel { width=maxW, height=maxH }

    _trayPanel = _UI.Panel {
        flexDirection="row", justifyContent="center", alignItems="center",
        gap=4, paddingTop=6, paddingBottom=6, paddingLeft=8, paddingRight=8,
        borderRadius=11, borderWidth=2,
        borderColor={148,115,68,215}, backgroundColor={138,95,38,175},
        minWidth="90%",
    }

    _infoLabel = _UI.Label { text="", fontSize=12, fontColor={52,92,52,220} }

    local undoBtn = ActionBtn("↩ 撤回一步", {50,90,195,255}, DoUndo)
    _btnUndo = undoBtn

    local pageRoot = _UI.Panel {
        width="100%", height="100%",
        backgroundColor={ table.unpack(LEVEL_CONFIGS[1].bgColor) },
        flexDirection="column", alignItems="center",
        children = {
            -- 顶栏
            _UI.Panel {
                width="100%",
                flexDirection="row", alignItems="center", justifyContent="space-between",
                paddingTop=12, paddingBottom=8, paddingLeft=12, paddingRight=12,
                backgroundColor={0,0,0,38},
                children = {
                    _UI.Panel {
                        pointerEvents="auto",
                        paddingLeft=12, paddingRight=12, paddingTop=7, paddingBottom=7,
                        borderRadius=9, borderWidth=2,
                        borderColor={255,255,255,100}, backgroundColor={255,255,255,42},
                        onClick=function() if _onBack then _onBack() end end,
                        children={ _UI.Label{text="← 返回", fontSize=12, fontColor={255,255,255,230}} },
                    },
                    _UI.Label{text="羊了个羊", fontSize=19, fontColor={255,255,240,255}},
                    _infoLabel,
                },
            },
            -- 网格区
            _UI.Panel {
                flex=1, width="100%",
                justifyContent="center", alignItems="center",
                overflow="hidden",
                children={ _gridContainer },
            },
            -- 托盘
            _UI.Panel {
                width="100%",
                flexDirection="column", alignItems="center",
                gap=3, paddingBottom=5,
                children={
                    _UI.Label{
                        text="集满 3 张自动消除 · 托盘满 7 张则失败",
                        fontSize=10, fontColor={255,255,255,168},
                    },
                    _trayPanel,
                },
            },
            -- 操作栏
            _UI.Panel {
                width="100%",
                flexDirection="row", gap=7,
                paddingLeft=10, paddingRight=10, paddingBottom=15,
                children={
                    undoBtn,
                    ActionBtn("🔀 重新洗牌", {168,90,22,255}, DoShuffle),
                },
            },
        },
    }

    -- 初始建格（容器是空的，AddChild 安全）
    BuildGrid()
    RebuildTray()
    RebuildInfo()
    return pageRoot
end

-- ============================================================
-- 公开 API
-- ============================================================
function SheepGameUI.Reset()
    _pendingLevel = 1
    if _btnUndo then _btnUndo:SetStyle({ opacity = 1.0 }) end
end

function SheepGameUI.SetOnBack(fn)
    _onBack = fn
end

return SheepGameUI
