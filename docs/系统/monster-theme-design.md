# Dark Merge TD - 怪物主题系统设计

## 目录

1. [架构概览](#1-架构概览)
2. [角色定义 (Role)](#2-角色定义-role)
3. [主题定义 (Theme)](#3-主题定义-theme)
4. [运行时组合 (BuildEnemyDef)](#4-运行时组合-buildenemydef)
5. [被动系统](#5-被动系统)
6. [波次生成与解锁](#6-波次生成与解锁)
7. [BOSS 设计](#7-boss-设计)
8. [视觉渲染](#8-视觉渲染)
9. [轮次缩放](#9-轮次缩放)
10. [50 怪物速查表](#10-50-怪物速查表)

---

## 1. 架构概览

### 核心思想：角色 × 主题 = 怪物

系统采用 **10 种标准角色 × 5 个视觉主题** 的数据驱动架构，运行时组合生成 50 种独特怪物。

```
怪物定义 = 角色(行为/数值) + 主题皮肤(名称/颜色/特化被动)
```

**好处**：
- 角色定义一处维护（HP/速度/形状/基础被动），所有主题共享
- 主题定义只负责视觉差异化（名称/颜色）和少量特化（坦克被动、光环类型、特殊被动）
- 新增主题只需添加皮肤数据，无需修改逻辑代码

### 关键数据结构

| 结构 | 位置 | 说明 |
|------|------|------|
| `Config.ENEMY_ROLES` | Config.lua | 10 种角色的行为和数值模板 |
| `Config.THEMES` | Config.lua | 5 个主题的皮肤和特化定义 |
| `Config.BuildEnemyDef(stageNum, roleId)` | Config.lua | 运行时组合函数 |
| `Config.BuildBossDef(stageNum)` | Config.lua | BOSS 定义构建函数 |

### 文件职责

| 文件 | 职责 |
|------|------|
| `Config.lua` | 角色模板 + 主题皮肤 + 组合函数 + 向后兼容 |
| `Enemy.lua` | 创建/伤害/被动/光环逻辑，`CreateEnemyFromDef()` 为新入口 |
| `Wave.lua` | 按主题怪物池生成波次，`GetUnlockedRoles(stageNum)` 筛选 |
| `Renderer.lua` | 主题配色渲染 + 光环范围指示 + 被动视觉效果 |

---

## 2. 角色定义 (Role)

### 9 种普通角色 + 1 种 BOSS（每主题独立定义）

| roleId | 定位 | 形状 | HP | 速度 | 金币 | 基础被动 | 解锁顺序 |
|--------|------|------|-----|------|------|---------|---------|
| `minion` | 小兵 | circle | 30 | 85 | 2 | — | 1 |
| `infantry` | 步兵 | square | 80 | 50 | 4 | — | 2 |
| `tank` | 坦克 | square | 300 | 25 | 10 | *(主题特化)* | 3 |
| `assassin` | 刺客 | triangle | 35 | 90 | 6 | — | 4 |
| `dodger` | 闪避者 | circle | 55 | 55 | 7 | dodge (30%) | 5 |
| `support` | 辅助 | diamond | 70 | 40 | 8 | aura *(主题特化)* | 6 |
| `splitter` | 分裂 | circle | 100 | 55 | 7 | split → minion ×2 | 7 |
| `blinker` | 瞬移 | diamond | 60 | 40 | 8 | blink (4s/8%) | 8 |
| `special` | 特殊 | triangle | 150 | 45 | 9 | *(主题独有)* | 9 |
| *(BOSS)* | BOSS | diamond | 800+ | 25+ | 50 | *(主题独有)* | 10波 |

### 角色属性说明

- **HP/速度**：角色定义基础值，实际值 = 基础 × 轮次加成 × 波次缩放
- **形状 (shape)**：几何渲染形状 — circle/square/triangle/diamond
- **size**：渲染尺寸（像素），小兵 6、步兵 8、坦克 12、BOSS 16+
- **解锁顺序 (unlockOrder)**：对应 `Config.ROLE_UNLOCK_WAVE` 中的波次门槛

---

## 3. 主题定义 (Theme)

### 5 个主题

| # | themeId | 名称 | 主色调 | 光晕色 | 关卡范围 |
|---|---------|------|--------|--------|---------|
| 1 | `undead` | 亡灵墓地 | 灰绿 (80,160,80) | (60,140,60) | 关 1-5 |
| 2 | `lava` | 熔岩地狱 | 暗红橙 (220,80,30) | (240,120,20) | 关 6-10 |
| 3 | `forest` | 幽暗森林 | 暗绿紫 (60,140,60) | (80,180,80) | 关 11-15 |
| 4 | `frost` | 冰霜冻土 | 冰蓝 (100,180,255) | (80,160,240) | 关 16-20 |
| 5 | `void` | 虚空深渊 | 深紫 (140,60,200) | (160,80,255) | 关 21-25 |

### 主题皮肤结构

每个主题为每种角色提供 `monsters[roleId]` 皮肤：

```lua
monsters = {
    minion   = { name = "腐鼠",     color = { 130, 150, 100 } },
    infantry = { name = "骷髅兵",   color = { 180, 170, 150 } },
    tank     = { name = "白骨巨人", color = { 200, 190, 170 }, tankPassive = "slow_resist", slowResist = 0.05 },
    assassin = { name = "亡灵蝙蝠", color = { 100, 80, 130 } },
    dodger   = { name = "怨灵",     color = { 140, 180, 140 } },
    support  = { name = "亡灵侍僧", color = { 80, 160, 80 },  aura = { type = "speed", value = 0.20, range = 60 } },
    splitter = { name = "尸蛛",     color = { 120, 130, 100 } },
    blinker  = { name = "游魂",     color = { 160, 200, 160 } },
    special  = { name = "墓穴骑士", color = { 100, 100, 80 },  specialPassive = "regen_lost", regenLostPct = 0.05, regenLostInterval = 3.0 },
}
```

### 主题特化三要素

每个主题通过以下三个维度做差异化：

| 维度 | 字段 | 影响角色 | 说明 |
|------|------|---------|------|
| **坦克被动** | `tankPassive` | tank | 每主题坦克有独特防御机制 |
| **辅助光环** | `aura` | support | 每主题辅助提供不同增益 |
| **特殊被动** | `specialPassive` | special | 每主题特殊怪有独有机制 |

---

## 4. 运行时组合 (BuildEnemyDef)

### 组合流程

```
Config.BuildEnemyDef(stageNum, roleId)
  │
  ├── 查找主题: Config.GetTheme(stageNum)
  ├── 查找角色: Config.ENEMY_ROLES[roleId]
  ├── 查找皮肤: theme.monsters[roleId]
  ├── 计算轮次加成: round HP ×(1+0.5n), speed ×min(1+0.1n, 2.0)
  │
  └── 合并输出:
      ├── id = "{themeId}_{roleId}" (如 "undead_minion")
      ├── name/color ← 皮肤
      ├── HP/speed/size/shape ← 角色（乘轮次加成）
      ├── passive/dodge/split/blink ← 角色基础被动
      ├── tankPassive ← 皮肤（如有）
      ├── aura ← 皮肤（如有，覆盖 passive 为 "aura"）
      ├── specialPassive ← 皮肤（如有）
      └── themeId ← 主题 ID（用于渲染查色）
```

### 向后兼容

`Config.ENEMY_TYPES` 和 `Config.BOSS_TYPES` 仍然保留，用主题 1（亡灵）的数据填充，确保旧代码路径不会崩溃。

---

## 5. 被动系统

### 5.1 角色基础被动

| 被动 | 角色 | 效果 |
|------|------|------|
| dodge | dodger | 一定概率闪避攻击 |
| split | splitter | 死后分裂为同主题 minion |
| blink | blinker | 每N秒瞬移一段路径 |

### 5.2 坦克被动 (tankPassive)

每个主题的坦克有不同的防御机制：

| 主题 | tankPassive | 效果 |
|------|------------|------|
| 亡灵 | `slow_resist` | 减速效果降低 5% |
| 熔岩 | `slow_resist` | 减速效果降低 50% |
| 森林 | `regen` | 每秒回复 0.5% 最大 HP |
| 冰霜 | `ice_shield` | 出生自带 30% HP 的冰盾 |
| 虚空 | `dot_immune` | 完全免疫 DOT 伤害 |

### 5.3 辅助光环 (aura)

每个主题的辅助提供不同的范围增益：

| 主题 | aura.type | 效果 | 范围 |
|------|-----------|------|------|
| 亡灵 | `speed` | 周围队友速度 +20% | 60px |
| 熔岩 | `slow_resist` | 周围队友减速抗性 +30% | 60px |
| 森林 | `hp_boost` | 自身 HP +15%（出生时生效） | — |
| 冰霜 | `dodge_boost` | 周围队友闪避 +10% | 60px |
| 虚空 | `slow_immune` | 周围队友免疫减速 | 60px |

**光环实现**：每帧在 `UpdateAuras()` 中清除并重新计算所有光环效果，避免状态累积。

### 5.4 特殊被动 (specialPassive)

每个主题的特殊怪有独有机制：

| 主题 | specialPassive | 效果 |
|------|---------------|------|
| 亡灵 | `regen_lost` | 每 3 秒回复 5% 已损失 HP |
| 熔岩 | `scorch` | 攻击它的塔降低 10% 攻速 3 秒 |
| 森林 | `poison_trail` | 每 0.5 秒在路径留下毒雾粒子 |
| 冰霜 | `first_hit_armor` | 首次受击伤害减少 50% |
| 虚空 | `death_silence` | 死亡时沉默周围 80px 塔 2 秒 |

### 5.5 光环系统实现细节

```lua
-- 每帧更新（Enemy.lua 中 UpdateAuras）
1. 清除所有敌人的光环标记（auraSpeedBoost, auraSlowResist 等）
2. 遍历所有 passive=="aura" 的活着敌人
3. 对范围内的友军应用光环效果
4. 光环效果在各系统中被读取：
   - ApplySlow: 检查 auraSlowImmune / auraSlowResist
   - TakeDamage: 检查 auraDodgeBoost（叠加闪避率）
   - Update: 检查 auraSpeedBoost（非减速状态下加速）
```

---

## 6. 波次生成与解锁

### 角色解锁节奏

波次解锁基于全局波次号，由 `Config.ROLE_UNLOCK_WAVE` 控制：

| 解锁顺序 | 全局波次 | 解锁的角色 |
|----------|---------|-----------|
| 1-2 | 波 1 | minion, infantry |
| 3-4 | 波 11 | tank, assassin |
| 5-6 | 波 21 | dodger, support |
| 7-8 | 波 41 | splitter, blinker |
| 9 | 波 61 | special |

### 波次类型

| 类型 | 出现规律 | 构成 |
|------|---------|------|
| 普通波 | 大多数波次 | 已解锁角色的随机组合 |
| 精英波 | 每 5 波 | 1-2 只精英怪（带词缀） |
| BOSS 波 | 每 10 波 | 前置杂兵 → BOSS → 增援杂兵 |

### 波次生成流程 (Wave.lua)

```
Wave.Generate(stageNum, waveInStage)
  │
  ├── GetUnlockedRoles(stageNum) → roleIds, roleDefs
  │   └── 使用 Config.BuildEnemyDef 为每个解锁角色构建定义
  │
  ├── BOSS 波: Config.BuildBossDef(stageNum)
  │   └── 增援从当前主题的角色池随机选择
  │
  ├── 精英波: 从角色池选取 → 叠加词缀
  │
  └── 普通波: 从角色池随机选取
      └── 队列条目携带 typeDef 用于 CreateEnemyFromDef
```

---

## 7. BOSS 设计

### 五大 BOSS 对照表

| 主题 | BOSS 名称 | HP | 速度 | 大小 | 被动 | 核心威胁 |
|------|----------|-----|------|------|------|---------|
| 亡灵 | 骨龙 | 800 | 25 | 16 | disable (禁用塔 2s/8s) | 火力中断 |
| 熔岩 | 炼狱领主 | 1000 | 28 | 18 | summon (召唤 minion/6s) | 场上压力 |
| 森林 | 森林九头蛇 | 2500 | 18 | 20 | phase (免疫控制) | 纯 HP 碾压 |
| 冰霜 | 暴风雪之王 | 700 | 40 | 16 | phase (隐身 2.5s/5s) | 速度+无敌 |
| 虚空 | 虚空帝王 | 1500 | 30 | 18 | rage (<50% HP 加速+免控) | 后半段失控 |

### BOSS 阶数系统（保留原系统）

| 每 10 波出现次数 | 阶数 | HP 倍率 | 额外词缀 |
|----------------|------|--------|---------|
| 第 1-2 次 | 1 阶 | ×1 | 0 |
| 第 3 次 | 2 阶 | ×3 | 1 |
| 第 4 次 | 3 阶 | ×9 | 2 |
| 第 5 次 | 4 阶 | ×27 | 3 |

---

## 8. 视觉渲染

### 主题色彩系统

每个主题有三组颜色（`palette`）：

| 颜色 | 用途 |
|------|------|
| `primary` | 主色调 |
| `secondary` | 辅助色 |
| `glow` | 光晕效果色（用于微光辉光和光环指示） |

### 渲染层次（从底到顶）

```
1. 光环范围指示（aura 型敌人）
   └── 脉冲渐变圆 + 外圈描边，颜色取决于光环类型
2. 主题微光（非 BOSS/精英的普通怪）
   └── 使用 themeGlowCache[themeId] 绘制微弱 DrawCircleBloom
3. BOSS 光晕 / 精英光晕（保留原系统）
4. 词缀效果环（offensive 脉冲）
5. 敌人身体（DrawEnemyShape: circle/square/triangle/diamond）
6. 受击闪白叠加
7. 坦克被动指示（regen: 绿色+号 / dot_immune: 红色x号）
8. 特殊被动指示:
   ├── poison_trail: 绿色尾迹点
   ├── regen_lost: 暗红心跳脉冲
   ├── first_hit_armor: 金色描边环（未消耗时）
   └── death_silence: 紫色†标记
9. 护盾弧线 + 护盾条
10. 血条 + BOSS 名字标签
```

### 光环类型颜色编码

| aura.type | 指示环颜色 | 语义 |
|-----------|-----------|------|
| `speed` | 绿色 (100,220,100) | 加速 |
| `slow_resist` / `slow_immune` | 蓝色 (100,180,255) | 抗减速 |
| `dodge_boost` | 黄色 (200,200,100) | 闪避 |
| `hp_boost` | 橙色 (255,160,80) | 生命 |

---

## 9. 轮次缩放

### 主题轮换

```lua
theme_index = ((stageNum - 1) % THEME_COUNT) + 1
round = floor((stageNum - 1) / (STAGES_PER_THEME * THEME_COUNT)) + 1
```

每 25 关（5 主题 × 5 关/主题）完成一个完整轮次，之后主题循环重复。

### 轮次数值加成

| 轮次 | 关卡范围 | HP 加成 | 速度加成 |
|------|---------|--------|---------|
| 1 | 1-25 | ×1.0 | ×1.0 |
| 2 | 26-50 | ×1.5 | ×1.1 |
| 3 | 51-75 | ×2.0 | ×1.2 |
| 4 | 76-100 | ×2.5 | ×1.3 |

轮次加成在 `BuildEnemyDef` 中应用于基础值，与波次/阶段缩放叠加。

---

## 10. 50 怪物速查表

### 亡灵墓地 (undead)

| roleId | 名称 | 颜色 | 坦克被动 | 光环 | 特殊被动 |
|--------|------|------|---------|------|---------|
| minion | 腐鼠 | (130,150,100) | — | — | — |
| infantry | 骷髅兵 | (180,170,150) | — | — | — |
| tank | 白骨巨人 | (200,190,170) | slow_resist 5% | — | — |
| assassin | 亡灵蝙蝠 | (100,80,130) | — | — | — |
| dodger | 怨灵 | (140,180,140) | — | — | — |
| support | 亡灵侍僧 | (80,160,80) | — | speed +20% | — |
| splitter | 尸蛛 | (120,130,100) | — | — | — |
| blinker | 游魂 | (160,200,160) | — | — | — |
| special | 墓穴骑士 | (100,100,80) | — | — | regen_lost 5%/3s |
| BOSS | 骨龙 | (60,140,60) | — | — | disable 2s/8s |

### 熔岩地狱 (lava)

| roleId | 名称 | 颜色 | 坦克被动 | 光环 | 特殊被动 |
|--------|------|------|---------|------|---------|
| minion | 小火魔 | (220,80,50) | — | — | — |
| infantry | 熔岩蛮兵 | (180,100,60) | — | — | — |
| tank | 岩浆巨人 | (160,80,40) | slow_resist 50% | — | — |
| assassin | 火焰精灵 | (255,160,40) | — | — | — |
| dodger | 灰烬幽魂 | (180,120,80) | — | — | — |
| support | 地狱萨满 | (200,60,30) | — | slow_resist +30% | — |
| splitter | 爆炎甲虫 | (200,100,40) | — | — | — |
| blinker | 瞬焰 | (240,140,40) | — | — | — |
| special | 熔岩蠕虫 | (140,60,30) | — | — | scorch -10%攻速/3s |
| BOSS | 炼狱领主 | (240,120,20) | — | — | summon minion/6s |

### 幽暗森林 (forest)

| roleId | 名称 | 颜色 | 坦克被动 | 光环 | 特殊被动 |
|--------|------|------|---------|------|---------|
| minion | 毒菇精 | (140,80,160) | — | — | — |
| infantry | 荆棘行者 | (100,130,70) | — | — | — |
| tank | 远古树人 | (80,120,60) | regen 0.5%/s | — | — |
| assassin | 暗影狐 | (100,60,120) | — | — | — |
| dodger | 迷雾蛾 | (120,100,160) | — | — | — |
| support | 腐化德鲁伊 | (60,140,60) | — | hp_boost +15% | — |
| splitter | 育母蛛 | (90,110,70) | — | — | — |
| blinker | 鬼火 | (80,180,80) | — | — | — |
| special | 剧毒藤蔓 | (80,160,40) | — | — | poison_trail |
| BOSS | 森林九头蛇 | (60,100,40) | — | — | phase 免控 |

### 冰霜冻土 (frost)

| roleId | 名称 | 颜色 | 坦克被动 | 光环 | 特殊被动 |
|--------|------|------|---------|------|---------|
| minion | 冰晶虱 | (140,200,240) | — | — | — |
| infantry | 冰封战士 | (120,160,200) | — | — | — |
| tank | 冰川魔像 | (100,140,200) | ice_shield 30% | — | — |
| assassin | 雪原疾兔 | (200,220,240) | — | — | — |
| dodger | 冰魄 | (150,180,220) | — | — | — |
| support | 霜歌者 | (80,160,240) | — | dodge_boost +10% | — |
| splitter | 冰甲虫 | (120,170,210) | — | — | — |
| blinker | 暴风雪精灵 | (160,200,240) | — | — | — |
| special | 永冻蛟 | (80,120,180) | — | — | first_hit_armor -50% |
| BOSS | 暴风雪之王 | (80,160,240) | — | — | phase 隐身 |

### 虚空深渊 (void)

| roleId | 名称 | 颜色 | 坦克被动 | 光环 | 特殊被动 |
|--------|------|------|---------|------|---------|
| minion | 虚空虱 | (120,60,160) | — | — | — |
| infantry | 虚空战兵 | (100,60,140) | — | — | — |
| tank | 深渊泰坦 | (80,40,120) | dot_immune | — | — |
| assassin | 相位潜行者 | (160,80,200) | — | — | — |
| dodger | 扭曲暗影 | (140,60,180) | — | — | — |
| support | 虚空先驱 | (120,60,180) | — | slow_immune | — |
| splitter | 裂隙爬行者 | (100,50,140) | — | — | — |
| blinker | 闪现恐魔 | (160,80,220) | — | — | — |
| special | 熵能织者 | (140,60,200) | — | — | death_silence 2s/80px |
| BOSS | 虚空帝王 | (160,80,255) | — | — | rage 加速+免控 |

---

## 附录：与现有系统的兼容

| 现有系统 | 整合方式 |
|---------|---------|
| 精英词缀系统 | 完全保留，T1/T2/T3 词缀可叠加到任何角色 |
| HP/速度/数量缩放 | 完全保留，在组合后的基础值上应用 |
| BOSS 阶数系统 | 完全保留 |
| 受击反馈 | 完全保留（hitFlash/hitShake/damageNumber） |
| debuff 粒子效果 | 完全保留 |
| 超限判负 | 完全保留 (MAX_ENEMIES = 7) |
| `Config.ENEMY_TYPES` | 向后兼容，用亡灵主题数据填充 |
| `Config.BOSS_TYPES` | 向后兼容，用各主题 BOSS 填充 |
| `Enemy.CreateEnemy(typeId)` | 向后兼容包装，内部调用 `CreateEnemyFromDef` |
