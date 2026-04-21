# 羊了个羊 实现详细计划

> 基于网络调研的真实游戏机制，审核通过后再动代码。

---

## 一、架构概览

公共 API 保持不变（GameUI.lua 无需修改）：

```lua
SheepGameUI.CreatePage(uiModule)   -- 首次挂载，创建 UI 容器
SheepGameUI.Reset()                -- 重置为第一关
SheepGameUI.SetOnBack(fn)         -- 返回回调
```

---

## 二、核心数据结构

### SheepTile（单个牌）

```lua
{
  col     = int,     -- 列坐标（0-based）
  row     = int,     -- 行坐标（0-based）
  layer   = int,     -- 层号（1=底层，最大=顶层）
  typeId  = int,     -- 图案 ID（1~13）
  removed = bool,    -- 已入托盘或已消除
  blocked = bool,    -- 被上层覆盖，不可点击
}
```

### 状态变量

```lua
_tiles       = {}     -- 所有牌的列表
_tray        = {}     -- 托盘，最多 7 个 typeId
_level       = 1      -- 当前关卡（1 或 2）
_animTimer   = -1     -- -1 表示不在动画中
_animTileSet = {}     -- table-as-set：_animTileSet[tile]=true，O(1) 查询
_undoUsed    = false  -- 撤销是否已用过（每局限 1 次）
_undoSnapshot= nil    -- 撤销快照
_scale       = 1.0    -- 屏幕缩放因子（小屏手机 < 1.0）
_btnUndo     = nil    -- 撤销按钮引用（用于设置 disabled 状态）
```

---

## 三、常量定义（修正值）

```lua
local TILE_W    = 50     -- 牌宽（像素）
local TILE_H    = 50     -- 牌高
local TILE_STEP = 53     -- 格距（含间隔）
local LAYER_OX  = 25     -- 每层向右偏移 = TILE_W/2（上层牌中心在下层4牌角交叉点）
local LAYER_OY  = 25     -- 每层向上偏移 = TILE_H/2
local MAX_TRAY  = 7      -- 托盘最大容量
local ANIM_DUR  = 0.22   -- 入托盘动画时长（秒）
```

**层偏移原理（来自真实游戏）：**
- 网格排列：上层牌中心恰好落在下层相邻4张牌的角交叉点
- 连续行/列：上下两层牌几乎完全重叠，下层仅边缘约1/6可见
- 公式：`LAYER_OX = LAYER_OY = TILE_W / 2 = 25px`

---

## 四、图案类型（13 种）

```lua
local TYPES = {
  { id=1,  emoji="⭐" }, { id=2,  emoji="🦀" }, { id=3,  emoji="🌽" },
  { id=4,  emoji="🍃" }, { id=5,  emoji="💎" }, { id=6,  emoji="🔥" },
  { id=7,  emoji="🌙" }, { id=8,  emoji="🔔" }, { id=9,  emoji="🐟" },
  { id=10, emoji="🌸" }, { id=11, emoji="☁️"  }, { id=12, emoji="🐦" },
  { id=13, emoji="🎂" },
}
```

---

## 五、关卡配置（最重要！）

### 第一关（Easy - 保证可过）

- 图案种类：3 种（各 6 张 = 18 张总）
- 层数：2 层
- 布局：Layer1 = 4×3=12 张，Layer2 = 3×2=6 张（居中）
- 背景色：绿色系 `rgba(0.13, 0.55, 0.13, 0.15)`
- 数学验证：18 ÷ 3 = 6 ✅ 必然可全消

```lua
LEVEL_CONFIGS[1] = {
  numLayers = 2,
  bgColor   = {0.13, 0.55, 0.13, 0.15},
  types     = {1, 2, 3},
  layout    = {
    { cols=4, rows=3, offX=0, offY=0 },   -- Layer 1（底）
    { cols=3, rows=2, offX=1, offY=0 },   -- Layer 2（居中）
  },
}
```

### 第二关（地狱 - <1% 通关率）

- 图案种类：13 种（各 6 张 = 78 张总）
- 层数：6 层（纺锤形，底宽顶窄）
- 背景色：暗蓝色 `rgba(0.08, 0.12, 0.31, 0.85)`

| 层 | 列 | 行 | 牌数 |
|----|----|----|------|
| L1 |  5 |  5 |  25  |
| L2 |  4 |  4 |  16  |
| L3 |  4 |  3 |  12  |
| L4 |  3 |  3 |   9  |
| L5 |  2 |  4 |   8  |
| L6 |  2 |  4 |   8  |
| 合计| | | **78** ✅ |

```lua
LEVEL_CONFIGS[2] = {
  numLayers = 6,
  bgColor   = {0.08, 0.12, 0.31, 0.85},
  types     = {1,2,3,4,5,6,7,8,9,10,11,12,13},
  layout    = {
    { cols=5, rows=5, offX=0, offY=0 },
    { cols=4, rows=4, offX=0, offY=0 },
    { cols=4, rows=3, offX=0, offY=0 },
    { cols=3, rows=3, offX=1, offY=0 },
    { cols=2, rows=4, offX=1, offY=0 },
    { cols=2, rows=4, offX=1, offY=0 },
  },
}
```

---

## 六、牌的生成算法

```lua
local function BuildTiles(cfg)
  -- 生成 typeId 池（每种 6 张），Fisher-Yates 洗牌
  local pool = {}
  for _, tid in ipairs(cfg.types) do
    for _ = 1, 6 do table.insert(pool, tid) end
  end
  for i = #pool, 2, -1 do
    local j = math.random(i)
    pool[i], pool[j] = pool[j], pool[i]
  end
  -- 按层布局填充
  local tiles, poolIdx = {}, 1
  for layerIdx, def in ipairs(cfg.layout) do
    for r = 0, def.rows - 1 do
      for c = 0, def.cols - 1 do
        table.insert(tiles, {
          col=c+(def.offX or 0), row=r+(def.offY or 0),
          layer=layerIdx, typeId=pool[poolIdx],
          removed=false, blocked=false,
        })
        poolIdx = poolIdx + 1
      end
    end
  end
  return tiles
end
```

---

## 七、遮挡检测算法（核心）

**规则**：牌 `(c,r,L)` 被 `(c2,r2,L+1)` 遮挡，当且仅当：
```
dc = c2-c ∈ {-1, 0}   AND   dr = r2-r ∈ {0, 1}
```

测试用例验证：
```
(1,1,1) 被 (1,1,2)？ dc=0,dr=0 → YES ✅
(1,1,1) 被 (0,1,2)？ dc=-1,dr=0 → YES ✅
(1,1,1) 被 (1,2,2)？ dc=0,dr=1 → YES ✅
(1,1,1) 被 (0,2,2)？ dc=-1,dr=1 → YES ✅
(1,1,1) 被 (2,1,2)？ dc=1 → NO ✅
(1,1,1) 被 (1,0,2)？ dr=-1 → NO ✅
```

---

## 八、托盘逻辑

### 插入（同类聚集规则）

```lua
local function TrayInsert(typeId)
  local pos = #_tray + 1
  for i = #_tray, 1, -1 do
    if _tray[i] == typeId then pos = i + 1; break end
  end
  table.insert(_tray, pos, typeId)
end
```

### 消除检查（3 连消除，循环检查）

```lua
local function TrayCheckMatch()
  local i = 1
  while i <= #_tray - 2 do
    if _tray[i] == _tray[i+1] and _tray[i+1] == _tray[i+2] then
      table.remove(_tray, i+2)
      table.remove(_tray, i+1)
      table.remove(_tray, i)
      -- 不 break，继续检查（消除后可能产生新三连）
    else
      i = i + 1
    end
  end
end
```

托盘插入测试：
```
[] → 插A → [A]
[A] → 插B → [A,B]
[A,B] → 插A → [A,A,B]  ← 插在已有A之后
[A,A,B] → 插A → [A,A,A,B] → 消除 → [B] ✅
```

---

## 九、像素坐标计算

```lua
local function TilePixelPos(tile, cfg)
  local baseY = (cfg.numLayers - 1) * LAYER_OY * _scale
  local px = (tile.col * TILE_STEP + (tile.layer-1) * LAYER_OX) * _scale
  local py = baseY + tile.row * TILE_STEP * _scale - (tile.layer-1) * LAYER_OY * _scale
  return px, py
end
```

容器尺寸：
```lua
local maxCols = -- 各层最大列数
local maxRows = -- 各层最大行数
local rawW = maxCols * TILE_STEP + (numLayers-1) * LAYER_OX + TILE_W
local rawH = maxRows * TILE_STEP + (numLayers-1) * LAYER_OY + TILE_H
-- 容器尺寸 = rawW * _scale, rawH * _scale
```

---

## 十、屏幕适配（_scale 因子）

```lua
-- 在 CreatePage 中计算，一次性
local physW = graphics:GetWidth()
local logW  = physW / graphics:GetDPR()
local availW = logW - 24  -- 左右各 12px 边距

-- 第二关 L1=5cols，6层，是最宽的情况
-- 宽度 = 5*TILE_STEP + (6-1)*LAYER_OX + TILE_W = 5*53 + 5*25 + 50 = 440px
local maxRawW = 5 * 53 + 5 * 25 + 50  -- = 440px
_scale = math.min(1.0, availW / maxRawW)
-- 375px手机：availW=351, scale≈0.80, 实际tile=40px（可接受）
```

---

## 十一、动画流程

点击牌 → 标记 `removed=true` → 保存起点坐标 → 开启 `_animTimer=0`
→ `SheepUI_OnUpdate` 每帧插值位置 → 动画结束：
  → `TrayInsert()` → `TrayCheckMatch()` → `CheckWinOrLose()` → 刷新 UI

```lua
function SheepUI_OnUpdate(_, eventData)
  if _animTimer < 0 then return end
  local dt = eventData["TimeStep"]:GetFloat()
  _animTimer = _animTimer + dt
  local t = math.min(1.0, _animTimer / ANIM_DUR)
  RebuildGrid(t)
  if _animTimer >= ANIM_DUR then
    _animTimer = -1; _animTileSet = {}
    TrayInsert(_pendingTypeId)
    TrayCheckMatch()
    CheckWinOrLose()
    RebuildGrid(1); DrawTray()
  end
end
```

---

## 十二、撤销功能

```lua
-- 点击前保存快照（每局只保存一次有效快照）
local function SaveUndoSnapshot()
  _undoSnapshot = { tiles=DeepCopyTiles(_tiles), tray={table.unpack(_tray)} }
end

local function Undo()
  if _undoUsed or not _undoSnapshot then return end
  _undoUsed = true
  _tiles = _undoSnapshot.tiles
  _tray  = _undoSnapshot.tray
  _undoSnapshot = nil
  UpdateBlocked(); RebuildGrid(1); DrawTray()
  -- 撤销按钮变灰（设置 disabled 或降低 opacity）
  _btnUndo:SetAttribute("opacity", 0.4)
end
```

---

## 十三、关卡背景与胜负

```lua
local function LoadLevel(lv)
  _level = lv
  local cfg = LEVEL_CONFIGS[lv]
  -- 背景色
  _root:SetAttribute("backgroundColor", cfg.bgColor)
  -- 重置状态
  _undoUsed=false; _undoSnapshot=nil
  _tiles=BuildTiles(cfg); _tray={}
  UpdateBlocked(); RebuildGrid(1); DrawTray(); DrawButtons()
end

local function CheckWinOrLose()
  if #_tray >= MAX_TRAY then ShowResult(false); return end
  for _, t in ipairs(_tiles) do
    if not t.removed then return end  -- 还有牌未消
  end
  ShowResult(true)  -- 全消 = 胜利
end
```

---

## 十四、实现顺序

### P0（核心正确性，必须）

1. 更新常量（TILE_W=50, TILE_STEP=53, LAYER_OX=16, LAYER_OY=14）
2. 修正 Level 2 为 6 层纺锤形布局（78 张，验证总数正确）
3. layout 支持 `offX`/`offY` 偏移
4. 添加 `_scale` 屏幕适配（CreatePage 中计算，所有像素乘以 _scale）
5. 关卡背景色区分（L1 绿 / L2 暗蓝）

### P1（体验优化）

6. `_animTileSet` 改为 table-as-set
7. 撤销按钮 disabled 状态（`_undoUsed` 后变灰）
8. 撤销快照系统（`DeepCopyTiles` + `SaveUndoSnapshot`）

### P2（可选锦上添花）

9. 胜利/失败结果面板动画
10. 进入第二关时显示警告提示（"通关率不足1%，祝您好运"）

---

## 十五、关键文件

- **主要修改**：`/workspace/scripts/Game/SheepGameUI.lua`
- **无需修改**：`/workspace/scripts/Game/GameUI.lua`（公共 API 不变）

## 十六、验证方法

1. 构建成功（build 工具无报错）
2. 第一关：点击牌入托盘，3 连消除正常，18 张全消后显示胜利
3. 第二关：牌数 78 张全显示，层级遮挡视觉正确，难度明显高于第一关
4. 小屏（逻辑宽 < 395px）：牌格自动缩小不溢出屏幕
5. 撤销：只能用一次，用后按钮变灰
