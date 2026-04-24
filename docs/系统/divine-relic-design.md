# 神圣遗物系统设计

> 暗影君主专属装备系统，从憎恨之地掉落获取

---

## 一、系统概述

4个**部位槽**，每个部位有独立的遗物池，通过憎恨之地战斗掉落获取。

- 部位只是槽位概念，**不限定效果类型**
- 每个遗物自身定义效果，可以是攻击、被动、增强等任意组合
- 遗物之间可以有**跨部位联动**（效果中标注"若装备了XX"）
- 品质决定基础强度，升级/升星无上限

### 部位定义

| 部位 | ID | 图标 |
|------|-----|------|
| 神之力 | `power` | ⚡ |
| 神之心 | `heart` | ❤ |
| 神之眼 | `eye` | 👁 |
| 神之意志 | `will` | 🔥 |

---

## 二、品质体系

5档品质，决定基础倍率和掉落稀有度：

| 品质 | ID | 颜色 | 基础倍率 | 掉落权重（普通难度） |
|------|------|------|---------|-------------------|
| 精良 | `green` | `{100, 200, 100}` | ×1.0 | 50% |
| 稀有 | `blue` | `{80, 150, 255}` | ×1.8 | 28% |
| 史诗 | `purple` | `{180, 100, 255}` | ×3.0 | 15% |
| 传说 | `orange` | `{255, 180, 50}` | ×5.0 | 6% |
| 神话 | `red` | `{220, 40, 40}` | ×8.0 | 1% |

---

## 三、遗物池

每个部位 5 个遗物，按品质门槛解锁。

### 神之力 (power)

| 遗物 | ID | 最低品质 | 效果 |
|------|-----|---------|------|
| 裁决之矛 | `judgment_spear` | 绿 | 每X次英雄攻击充能满后，对血量最高敌人造成`最高ATK x 倍率`伤害 |
| 虚空脉冲 | `void_pulse` | 蓝 | 全体英雄攻击力+X%；每10秒对全场敌人造成一次固定伤害 |
| 湮灭风暴 | `annihilation_storm` | 紫 | 充能满后对全体敌人造成范围伤害；若装备了`战意之核`(心)，范围伤害额外+30% |
| 命运收割 | `fate_reaper` | 橙 | 充能满后对血量低于X%的敌人直接斩杀，否则造成高额伤害；若装备了`因果之瞳`(眼)，斩杀线+5% |
| 终焉之光 | `end_light` | 红 | 充能满后造成真实伤害(无视防御)+灼烧3秒；若装备了`永恒意志`(意志)，伤害翻倍 |

**充能机制**：每次场上英雄攻击充能+1，基础充能上限100（受升级/升星/其他遗物影响）。无充能效果的遗物不使用此机制。

### 神之心 (heart)

| 遗物 | ID | 最低品质 | 效果 |
|------|-----|---------|------|
| 生命洪流 | `life_torrent` | 绿 | 全体英雄攻击力+X% |
| 战意之核 | `war_core` | 蓝 | 全体英雄攻速+X%；被`湮灭风暴`(力)引用 |
| 暗影凝聚 | `shadow_focus` | 紫 | 攻击力最高的英雄额外攻击+X%，其余英雄攻击+X/3% |
| 不灭圣焰 | `immortal_flame` | 橙 | 全体攻击+X%；每次神之力部位技能释放后，全体攻速+15%持续3秒 |
| 万象归一 | `unity_of_all` | 红 | 攻击+X%、攻速+X%、暴击伤害+X%；每装备1件红色品质遗物，所有加成再+3% |

### 神之眼 (eye)

| 遗物 | ID | 最低品质 | 效果 |
|------|-----|---------|------|
| 洞察之瞳 | `insight` | 绿 | 每X秒标记血量最高敌人，被标记敌人受到伤害+X% |
| 弱点瓦解 | `weakness_break` | 蓝 | 被标记敌人防御降低X%；若无标记效果，自动每8秒标记一次 |
| 连锁印记 | `chain_mark` | 紫 | 敌人死亡时将其标记传递给附近敌人；全体英雄对标记敌人伤害+X% |
| 因果之瞳 | `causality_eye` | 橙 | 被标记敌人死亡时爆炸，对附近敌人造成其最大生命值X%伤害；被`命运收割`(力)引用 |
| 全知之眼 | `omniscient_eye` | 红 | 同时标记3个敌人；标记目标受到的所有伤害+X%；每个被标记目标使全体英雄攻击+2% |

### 神之意志 (will)

| 遗物 | ID | 最低品质 | 效果 |
|------|-----|---------|------|
| 狂热信念 | `fervent_faith` | 绿 | 神之力部位技能伤害+X%（若力部位无伤害技能，转为全体攻击+X/2%） |
| 急速充能 | `rapid_charge` | 蓝 | 神之力部位充能需求-X次（若力部位无充能，转为全体攻速+X%） |
| 超载爆发 | `overload_burst` | 紫 | 神之力部位技能释放后，下5秒内全体英雄伤害+X% |
| 双重释放 | `double_cast` | 橙 | 神之力部位技能有X%概率释放2次（第2次50%效果） |
| 永恒意志 | `eternal_will` | 红 | 所有其他已装备遗物的数值效果+X%（全局增幅）；被`终焉之光`(力)引用 |

---

## 四、升级与升星

### 升级 (Level)

- **消耗**: `relic_essence`（遗物精华）
- **费用公式**: `cost(lv) = floor(80 * 1.08^(lv-1))`
- **效果**: 线性提升遗物数值参数
- **无上限**

### 升星 (Star)

- **消耗**: 1个相同遗物 或 X个同部位通用碎片
- **碎片公式**: `shards(star) = floor(5 * 1.25^(star-1))`
  - 1->2星: 5碎片, 2->3: 6, 3->4: 8, 4->5: 10, 5->6: 12 ...
- **效果**: 基础倍率 +15%/星
- **无上限**

### 属性计算

```
最终数值 = 基础值 x 品质倍率 x (1 + star x 0.15) x (1 + (level-1) x 0.03)
```

### 重复遗物处理

获得已拥有的同名同品质遗物时：
- 可选择**替换**当前装备（星级/等级重置）
- 或**分解**为1个同部位通用碎片

---

## 五、新资源

### 货币

| 资源ID | 名称 | 用途 |
|--------|------|------|
| `relic_essence` | 遗物精华 | 遗物升级 |

### 碎片（每部位独立）

| 资源ID | 名称 | 用途 |
|--------|------|------|
| `power_shard` | 神之力碎片 | 神之力部位遗物升星 |
| `heart_shard` | 神之心碎片 | 神之心部位遗物升星 |
| `eye_shard` | 神之眼碎片 | 神之眼部位遗物升星 |
| `will_shard` | 神之意志碎片 | 神之意志部位遗物升星 |

---

## 六、憎恨之地产出（替换原有奖励）

### 移除

原有的 `recruit_ticket_select_box`（招募券选择箱）奖励全部移除。

### 新奖励（按累计伤害阶梯）

| 伤害阈值 | 遗物精华 | 遗物掉落 |
|----------|---------|---------|
| 500万 | 30 | 1件 |
| 1000万 | 50 | — |
| 5000万 | 80 | 1件 |
| 2.5亿 | 120 | — |
| 5亿 | 150 | 1件 |
| 10亿 | 200 | — |
| 25亿 | 300 | 1件 |
| 50亿 | 400 | 1件 |
| 100亿 | 600 | 1件 |
| 250亿 | 1000 | 2件 |

### 掉落规则

1. **随机部位**：4部位均等概率
2. **随机品质**：按品质权重（受难度加成影响）
3. **随机遗物**：该部位该品质及以下可选遗物池中随机
4. 已拥有的遗物再次掉落 → 玩家选择替换或分解为碎片

### 难度品质加成

| 难度 | 精华倍率 | 品质权重调整 |
|------|---------|-------------|
| 普通 | x1.0 | 绿50 / 蓝28 / 紫15 / 橙6 / 红1 |
| 困难 | x1.5 | 绿40 / 蓝33 / 紫18 / 橙8 / 红1 |
| 噩梦 | x2.0 | 绿30 / 蓝36 / 紫21 / 橙10 / 红3 |
| 地狱 | x3.0 | 绿20 / 蓝38 / 紫25 / 橙12 / 红5 |

---

## 七、跨部位联动关系图

```
终焉之光(力·红) ←→ 永恒意志(意志·红)    伤害翻倍
湮灭风暴(力·紫) ←→ 战意之核(心·蓝)      范围伤害+30%
命运收割(力·橙) ←→ 因果之瞳(眼·橙)      斩杀线+5%

不灭圣焰(心·橙)  → 监听力部位释放        攻速+15%持续3秒
万象归一(心·红)   → 统计红色遗物数量      每件+3%全属性

狂热信念(意志·绿) → 增幅力部位伤害        适配力部位效果
急速充能(意志·蓝) → 减少力部位充能        适配力部位效果
超载爆发(意志·紫) → 监听力部位释放        全体伤害+X%
双重释放(意志·橙) → 监听力部位释放        概率双发
永恒意志(意志·红) → 增幅所有其他遗物      全局数值+X%
```

---

## 八、实现要点

### 数据存储

```lua
HeroData.relicData = {
    -- 4个部位各装备一件
    equipped = {
        power = { id = "judgment_spear", quality = "purple", level = 15, star = 3 },
        heart = { id = "life_torrent", quality = "green", level = 8, star = 1 },
        eye   = nil,  -- 未装备
        will  = nil,
    },
    -- 同部位通用碎片
    shards = {
        power = 12,
        heart = 5,
        eye   = 0,
        will  = 3,
    },
}
```

### 战斗集成

- **被动效果**：在 `Tower.ApplyRelicPassives()` 中于每帧/每次攻击时应用
- **充能技能**：在 `Combat.OnTowerAttack()` 中累加充能，满后触发
- **标记系统**：在 `Enemy` 上添加 `marks` 表，标记来源和持续时间
- **跨部位联动**：效果函数内部读取其他部位的装备状态判断

### SaveRegistry

```lua
SaveRegistry.Register("relicData", {
    group = "meta_game",
    order = 76,  -- hatredLandData(71) 之后
    ...
})
```

### 新货币注册

在 `Config.CURRENCY` 中添加 `relic_essence`，在 `InventoryData.ITEM_DEFS` 中添加碎片物品定义。

---

## 九、神之力 (power) 详细设计

> 本节为神之力部位 5 件遗物的完整数值规格，包括充能公式、伤害公式、缩放曲线和战斗集成方案。

---

### 9.0 通用公式回顾

```
最终数值 = 基础值 × 品质倍率 × (1 + star × 0.15) × (1 + (level-1) × 0.03)
```

| 品质 | 倍率 |
|------|------|
| green | ×1.0 |
| blue | ×1.8 |
| purple | ×3.0 |
| orange | ×5.0 |
| red | ×8.0 |

下文中所有标记 `V(base)` 的数值均通过此公式缩放，`base` 为精良(green)品质 1 级 0 星时的基准值。

---

### 9.1 充能系统规格

神之力部位引入**充能蓄力**机制，独立于现有技能 CD 系统。

#### 运行时状态

```lua
relicCharge = {
    current  = 0,      -- 当前充能值
    max      = 100,    -- 充能上限（受遗物/意志部位修正）
    ready    = false,  -- 是否可释放
}
```

#### 充能来源

| 来源 | 充能量 | 说明 |
|------|--------|------|
| 英雄普通攻击 | +1 / 次 | 每个英雄每次攻击独立计数 |
| 英雄暴击攻击 | +2 / 次 | 暴击额外 +1 |
| 击杀敌人 | +3 / 次 | 任意英雄击杀均触发 |

#### 充能上限修正

```lua
effectiveMax = baseMax
    - rapidChargeReduction      -- 急速充能(意志·蓝)减少的次数
    - V(starReduction)          -- 升星每星 -1（基础值1）
```

下限保护：`effectiveMax = max(20, effectiveMax)`，防止无限释放。

#### 释放后行为

- `current` 归零，`ready` 置 false
- 触发事件 `OnRelicPowerCast`（供意志部位监听）
- 进入 1.0 秒全局冷却（防止同帧多次释放）

#### 无充能遗物

`void_pulse` 不使用充能，改用**定时触发**（固定间隔），充能条 UI 隐藏。

---

### 9.2 裁决之矛 (judgment_spear)

> 单体精确打击，锁定血量最高敌人

#### 效果描述

充能满后，对当前**血量最高**的敌人造成一次高额伤害。

#### 参数表

| 参数 | 基础值(green Lv1 ★0) | 缩放方式 | 说明 |
|------|----------------------|---------|------|
| 充能上限 | 100 | 固定（受意志部位修正） | 约 10-15 秒一次 |
| 伤害倍率 | 250% | `V(2.50)` | 以场上**最高 ATK 英雄**的攻击力为基准 |
| 破甲加成 | 15% | `V(0.15)` | 该次攻击额外破甲率 |

#### 伤害公式

```
damage = maxTowerATK × V(2.50) 
```

经过 `Combat.CalcFinalDamage()` 正常计算（防御减伤、暴击等乘区均生效），额外叠加 `V(0.15)` 破甲率。

#### 目标选择

```lua
-- 选择当前HP最高的存活敌人
local target = nil
local maxHP = 0
for _, enemy in ipairs(activeEnemies) do
    if enemy.hp > maxHP then
        maxHP = enemy.hp
        target = enemy
    end
end
```

#### 数值示例

| 品质 | 等级 | 星级 | 伤害倍率 | 破甲加成 |
|------|------|------|---------|---------|
| green | 1 | 0 | 250% | 15.0% |
| blue | 1 | 0 | 450% | 27.0% |
| purple | 10 | 2 | 1,072% | 64.4% |
| orange | 20 | 5 | 2,978% | 178.7% → cap 80% |
| red | 30 | 8 | 5,734% | cap 80% |

#### 破甲上限

单次攻击的总破甲率（英雄自身 + 遗物加成 + 破甲层）上限 **80%**，防止防御完全无效化。

#### 视觉效果

- 充能满时目标头顶出现金色十字准星标记
- 释放时一道光矛从屏幕上方落下命中目标
- 命中时显示大号白色伤害数字 + 屏幕微震

---

### 9.3 虚空脉冲 (void_pulse)

> 被动增攻 + 定时 AoE，唯一不使用充能的神之力遗物

#### 效果描述

**被动**：全体英雄攻击力 +X%。
**定时**：每 10 秒对全场敌人造成一次固定伤害。

#### 参数表

| 参数 | 基础值(green Lv1 ★0) | 缩放方式 | 说明 |
|------|----------------------|---------|------|
| 攻击力加成 | 8% | `V(0.08)` | 独立乘区（不与装备攻击%叠加计算） |
| 脉冲间隔 | 10 秒 | 固定 | 不受攻速/CDR 影响 |
| 脉冲伤害 | 50% | `V(0.50)` | 以全队**平均 ATK** 为基准 |
| 脉冲目标 | 全场敌人 | — | 无数量上限 |

#### 被动效果集成

```lua
-- Tower.ApplyRelicPassives() 中
-- void_pulse 的攻击力加成归入 "遗物增攻" 独立乘区
-- 不与 atkPctBonus（装备%攻击）合并，避免乘算膨胀
tower.attack = tower.attack * (1 + voidPulseAtkPct)
```

这是一个**独立乘区**，与装备的 `atkPctBonus` 分开计算（加算区 vs 遗物区），避免攻击力过度膨胀。

#### 脉冲伤害公式

```
pulseDamage = avgTeamATK × V(0.50)
```

脉冲伤害**不经过防御减伤乘区**（视为固定伤害），但受敌人元素抗性影响。这确保了它在面对高防 Boss（如憎恨之地渐进 DEF）时仍有清理小怪的作用，但不会对 Boss 造成过量伤害。

#### 意志部位交互

- 由于无充能/释放行为，`狂热信念` 的"力部位技能伤害+X%"作用于**脉冲伤害**
- `急速充能` 的"充能需求-X次"回退为"全体攻速+X%"
- `超载爆发`/`双重释放` 的监听不触发（无 `OnRelicPowerCast` 事件）

#### 数值示例

| 品质 | 等级 | 星级 | 攻击力加成 | 脉冲伤害倍率 |
|------|------|------|----------|------------|
| green | 1 | 0 | 8.0% | 50% |
| blue | 1 | 0 | 14.4% | 90% |
| purple | 10 | 2 | 34.0% | 213% |
| orange | 20 | 5 | 94.5% | 594% |
| red | 30 | 8 | 181.9% | 1,143% |

#### 视觉效果

- 被动：场上英雄脚下有淡紫色脉冲光环（常驻）
- 定时脉冲：全屏紫色能量波纹向外扩散，命中敌人时显示紫色伤害数字

---

### 9.4 湮灭风暴 (annihilation_storm)

> 充能 AoE 爆发，跨部位联动核心

#### 效果描述

充能满后，对**全体敌人**造成范围伤害。若装备了`战意之核`(心)，范围伤害额外 +30%。

#### 参数表

| 参数 | 基础值(green Lv1 ★0) | 缩放方式 | 说明 |
|------|----------------------|---------|------|
| 充能上限 | 100 | 固定 | 同通用充能 |
| 伤害倍率 | 180% | `V(1.80)` | 以全队**最高 ATK** 为基准 |
| 目标 | 全体敌人 | — | 无上限 |
| 联动加成 | +30% | 固定 | 装备 `war_core` 时激活 |

#### 伤害公式

```
baseDmg = maxTowerATK × V(1.80)
if equipped("heart", "war_core") then
    baseDmg = baseDmg × 1.30
end
```

经过 `Combat.CalcFinalDamage()` 正常计算，对每个敌人独立结算（各自防御/抗性）。

#### 与裁决之矛的定位区分

| 维度 | 裁决之矛 | 湮灭风暴 |
|------|---------|---------|
| 目标 | 单体（最高HP） | 全体 |
| 基础倍率 | 250%（更高） | 180%（更低） |
| 优势场景 | 打 Boss / 精英 | 清波次 / 多怪 |
| 联动 | 无 | 战意之核 +30% |

#### 联动检查实现

```lua
local function hasHeartRelic(relicId)
    local heart = HeroData.relicData.equipped.heart
    return heart and heart.id == relicId
end
```

#### 数值示例

| 品质 | 等级 | 星级 | 单体伤害倍率 | 联动后倍率 |
|------|------|------|------------|-----------|
| green | 1 | 0 | 180% | 234% |
| blue | 1 | 0 | 324% | 421% |
| purple | 10 | 2 | 772% | 1,003% |
| orange | 20 | 5 | 2,144% | 2,787% |
| red | 30 | 8 | 4,128% | 5,366% |

#### 视觉效果

- 充能满时屏幕边缘出现紫色风暴漩涡预警
- 释放时全屏暗紫色风暴席卷，所有敌人同时受击
- 联动激活时风暴带橙色核心光效

---

### 9.5 命运收割 (fate_reaper)

> 斩杀机制，高血量打伤害 + 低血量直接处决

#### 效果描述

充能满后，对**全体敌人**进行审判：
- 血量 **≤ 斩杀线** 的敌人直接死亡（斩杀）
- 血量 **> 斩杀线** 的敌人受到高额伤害

若装备了`因果之瞳`(眼)，斩杀线 +5%。

#### 参数表

| 参数 | 基础值(green Lv1 ★0) | 缩放方式 | 说明 |
|------|----------------------|---------|------|
| 充能上限 | 100 | 固定 | 同通用充能 |
| 斩杀线 | 10% | `V(0.10)` | 敌人当前HP/最大HP ≤ 此值则斩杀 |
| 非斩杀伤害 | 300% | `V(3.00)` | 以最高 ATK 为基准 |
| 联动加成 | +5% 斩杀线 | 固定 | 装备 `causality_eye` 时激活 |
| 斩杀线上限 | 35% | 固定 | 防止 100% 斩杀 |

#### 斩杀公式

```lua
local executeThreshold = math.min(
    V(0.10) + (hasCausalityEye and 0.05 or 0),
    0.35  -- 硬上限
)

for _, enemy in ipairs(activeEnemies) do
    local hpRatio = enemy.hp / enemy.maxHP
    if hpRatio <= executeThreshold then
        -- 直接斩杀
        enemy.hp = 0
        -- 显示 "处决" 特殊文字
    else
        -- 正常高额伤害
        local dmg = maxTowerATK * V(3.00)
        Combat.CalcFinalDamage(dmg, ...)
    end
end
```

#### 斩杀线缩放与上限

| 品质 | 等级 | 星级 | 斩杀线 | 联动后 | 非斩杀倍率 |
|------|------|------|--------|--------|-----------|
| green | 1 | 0 | 10.0% | 15.0% | 300% |
| blue | 1 | 0 | 18.0% | 23.0% | 540% |
| purple | 10 | 2 | 35%→cap | 35%→cap | 1,286% |
| orange | 20 | 5 | 35%→cap | 35%→cap | 3,573% |
| red | 30 | 8 | 35%→cap | 35%→cap | 6,878% |

> 紫色品质中期升级后斩杀线即触顶 35%，后续成长全部体现在非斩杀伤害倍率上。这是有意为之——斩杀是保底清理工具，不是无限缩放的胜利条件。

#### 憎恨之地特殊处理

憎恨之躯 HP 为 `math.maxinteger`（无限），斩杀机制对其**无效**（`hpRatio` 永远接近 100%），退化为纯伤害技能。这符合设计意图——斩杀用于普通关卡清波，不会破坏 Boss 战节奏。

#### 视觉效果

- 充能满时全场敌人头顶出现红色命运之环
- 低于斩杀线的敌人环变为金色（预告处决）
- 释放时金色死神镰刀横扫全场
- 被斩杀的敌人播放特殊消散动画 + "处决!" 文字

---

### 9.6 终焉之光 (end_light)

> 最高品质，真实伤害 + 灼烧 DOT，联动可翻倍

#### 效果描述

充能满后，对**血量最高的敌人**造成**真实伤害**（无视防御），并施加 3 秒灼烧。若装备了`永恒意志`(意志)，伤害翻倍。

#### 参数表

| 参数 | 基础值(green Lv1 ★0) | 缩放方式 | 说明 |
|------|----------------------|---------|------|
| 充能上限 | 100 | 固定 | 同通用充能 |
| 真实伤害倍率 | 400% | `V(4.00)` | 以最高 ATK 为基准 |
| 灼烧总伤害 | 120% | `V(1.20)` | 3 秒内均匀分配，每 0.5 秒一跳 |
| 灼烧持续 | 3 秒 | 固定 | 6 跳，每跳 `V(1.20) / 6` |
| 联动加成 | ×2.0 | 固定 | 装备 `eternal_will` 时，真实伤害和灼烧均翻倍 |
| 目标 | 1 个 | — | 血量最高的敌人 |

#### 真实伤害实现

```lua
-- 新增伤害类型：真实伤害，跳过防御减伤乘区
function Combat.CalcTrueDamage(baseDmg, attacker, target)
    -- 跳过 DEF 减伤乘区
    -- 保留暴击乘区（可暴击）
    -- 跳过元素抗性
    -- 保留 dmgBonus 乘区
    -- 保留易伤标记
    local zones = {
        crit = CalcCritZone(attacker),       -- 保留
        dmgBonus = 1 + attacker.dmgBonus,    -- 保留
        vulnMark = 1 + (target.vulnMark or 0), -- 保留
    }
    return baseDmg * zones.crit * zones.dmgBonus * zones.vulnMark
end
```

**设计理由**：真实伤害跳过防御和元素抗性两个乘区，但保留暴击/伤害加成/易伤标记。这确保它能穿透憎恨之地 Boss 的超高防御增长（800K × 1.18^t），但仍然受玩家构建影响（不是纯固定值）。

#### 灼烧 DOT 实现

```lua
-- 灼烧 debuff，挂在目标 enemy 上
enemy.burns = enemy.burns or {}
table.insert(enemy.burns, {
    totalDmg   = maxTowerATK * V(1.20) * (hasEternalWill and 2.0 or 1.0),
    remaining  = 3.0,
    interval   = 0.5,
    timer      = 0,
    isTrueDmg  = true,  -- 灼烧也是真实伤害
    source     = "end_light",
})
```

灼烧 DOT 同样为真实伤害，不可叠加（刷新持续时间，取更高伤害值）。

#### 数值示例

| 品质 | 等级 | 星级 | 真实伤害倍率 | 灼烧总倍率 | 联动后(×2) |
|------|------|------|------------|-----------|-----------|
| green | 1 | 0 | 400% | 120% | 800% + 240% |
| blue | 1 | 0 | 720% | 216% | 1,440% + 432% |
| purple | 10 | 2 | 1,715% | 514% | 3,430% + 1,029% |
| orange | 20 | 5 | 4,763% | 1,429% | 9,527% + 2,858% |
| red | 30 | 8 | 9,171% | 2,751% | 18,342% + 5,502% |

#### 视觉效果

- 充能满时目标头顶出现金白色光柱预警（1秒）
- 释放时一道炽白光柱从天而降贯穿目标
- 命中后目标身上持续燃烧金色火焰（灼烧期间）
- 联动激活时光柱变为双重螺旋 + 金色粒子爆发

---

### 9.7 五件遗物横向对比

| 维度 | 裁决之矛 | 虚空脉冲 | 湮灭风暴 | 命运收割 | 终焉之光 |
|------|---------|---------|---------|---------|---------|
| 最低品质 | 绿 | 蓝 | 紫 | 橙 | 红 |
| 触发方式 | 充能 | 被动+定时 | 充能 | 充能 | 充能 |
| 目标 | 单体 | 全体 | 全体 | 全体 | 单体 |
| 伤害类型 | 普通 | 固定(无视防御) | 普通 | 普通+斩杀 | 真实 |
| 基础倍率 | 250% | 50%/10s | 180% | 300% | 400% |
| 特殊机制 | 额外破甲 | 攻击力被动 | — | 斩杀处决 | 灼烧DOT |
| 跨部位联动 | 无 | 无 | 心·战意之核 | 眼·因果之瞳 | 意志·永恒意志 |
| 核心定位 | 单体输出 | 泛用增强 | AoE清场 | 收割终结 | Boss杀手 |
| 推荐场景 | 精英/Boss | 通用 | 多波次清怪 | 中后期关卡 | 憎恨之地 |

---

### 9.8 战斗集成方案

#### 新增模块

```lua
-- scripts/Game/RelicPower.lua（神之力战斗逻辑）

local RelicPower = {}

-- 初始化（进入战斗时调用）
function RelicPower.Init()
    RelicPower.charge = { current = 0, max = 100, ready = false }
    RelicPower.globalCD = 0
    RelicPower.pulseTimer = 0  -- void_pulse 专用
end

-- 每帧更新
function RelicPower.Update(dt, towers, enemies)
    local relic = HeroData.relicData.equipped.power
    if not relic then return end

    RelicPower.globalCD = math.max(0, RelicPower.globalCD - dt)

    if relic.id == "void_pulse" then
        RelicPower._UpdatePulse(dt, relic, towers, enemies)
    else
        RelicPower._UpdateCharge(dt, relic, towers, enemies)
    end
end

-- 英雄攻击时调用（Combat.OnTowerAttack 中插入）
function RelicPower.OnTowerAttack(tower, target, isCrit)
    local relic = HeroData.relicData.equipped.power
    if not relic or relic.id == "void_pulse" then return end

    local charge = RelicPower.charge
    charge.current = charge.current + (isCrit and 2 or 1)
    if charge.current >= charge.max then
        charge.current = charge.max
        charge.ready = true
    end
end

-- 击杀敌人时调用
function RelicPower.OnEnemyKilled()
    local relic = HeroData.relicData.equipped.power
    if not relic or relic.id == "void_pulse" then return end

    local charge = RelicPower.charge
    charge.current = math.min(charge.current + 3, charge.max)
    if charge.current >= charge.max then
        charge.ready = true
    end
end

return RelicPower
```

#### 现有代码插入点

```lua
-- Tower.lua 中的 ApplyRelicPassives()（新增函数）
function Tower.ApplyRelicPassives(tower)
    local relic = HeroData.relicData.equipped.power
    if not relic then return end

    if relic.id == "void_pulse" then
        -- 独立乘区：遗物攻击力加成
        local atkPct = RelicCalc.V(relic, 0.08)
        tower.attack = tower.attack * (1 + atkPct)
    end
end

-- Combat.lua:OnTowerAttack() 末尾追加
RelicPower.OnTowerAttack(tower, target, isCrit)

-- Combat.lua:OnEnemyKilled() 末尾追加
RelicPower.OnEnemyKilled()

-- Combat.lua 新增 CalcTrueDamage()（终焉之光专用）
function Combat.CalcTrueDamage(baseDmg, attacker, target)
    -- 跳过防御乘区和元素抗性乘区
    -- 保留暴击、伤害加成、易伤标记
    ...
end
```

#### 数值缩放工具函数

```lua
-- scripts/Game/RelicCalc.lua

local RelicCalc = {}

local QUALITY_MULT = {
    green = 1.0, blue = 1.8, purple = 3.0, orange = 5.0, red = 8.0
}

--- 通用数值缩放：基础值 × 品质 × 星级 × 等级
function RelicCalc.V(relic, baseValue)
    local qm = QUALITY_MULT[relic.quality] or 1.0
    local sm = 1 + (relic.star or 0) * 0.15
    local lm = 1 + ((relic.level or 1) - 1) * 0.03
    return baseValue * qm * sm * lm
end

return RelicCalc
```

---

### 9.9 UI 显示规格

#### 充能条

- 位置：战斗界面顶部，暗影君主头像下方
- 尺寸：宽 160px，高 8px
- 颜色：渐变填充（暗紫 → 亮金），满时脉冲闪烁
- 隐藏条件：未装备神之力遗物，或装备 `void_pulse`

#### 技能释放提示

- 充能满时充能条上方显示遗物图标 + 呼吸光效
- 自动释放（不需要手动点击），释放瞬间闪白 0.1 秒

#### 伤害数字样式

| 伤害类型 | 颜色 | 字号 | 特殊 |
|---------|------|------|------|
| 遗物普通伤害 | 金色 `{255, 215, 0}` | 1.5× 标准 | 无 |
| 真实伤害 | 白色 `{255, 255, 255}` | 1.5× | "真实" 前缀 |
| 灼烧伤害 | 橙红 `{255, 100, 30}` | 1.0× | 每跳独立显示 |
| 斩杀处决 | 红色 `{220, 40, 40}` | 2.0× | "处决!" 文字 |
| 脉冲伤害 | 紫色 `{180, 100, 255}` | 1.2× | 无 |
