# Dark Merge TD — 英雄设计总表

> 版本 v1.0 | 适用于当前架构（Config.TOWER_TYPES / LEADER_HERO / HeroSkills / HeroData）

---

## 一、设计原则

1. **稀有度决定上限，定位决定玩法** — N/R 是基础填充，LR 是传说级终极追求
2. **主角独立于品质体系** — 暗影君主不属于任何品质，是独立的主角单位
3. **合成不改类型** — 同类型同星级合成升星，跨类型不能合
4. **羁绊鼓励混搭** — 不同阵营/种族的组合激活全局增益，避免"满场同一个英雄"
5. **主角等级压制** — 随从英雄等级 ≤ 主角等级，保证主角养成优先级

---

## 二、稀有度体系

| 稀有度 | 底色 | 招募权重 | 灵魄碎片 | 基础攻击力区间 | 技能数 | 定位 |
|--------|------|---------|---------|---------------|--------|------|
| **N**  | 灰白 | 40      | 5       | 8 ~ 12        | 1      | 廉价填充、前期过渡 |
| **R**  | 绿色 | 30      | 10      | 12 ~ 18       | 2      | 基础主力 |
| **SR** | 蓝色 | 17      | 20      | 15 ~ 22       | 3      | 中坚力量、有特色机制 |
| **SSR**| 紫色 | 8       | 30      | 22 ~ 30       | 3      | 核心输出/功能，高养成收益 |
| **UR** | 金色 | 3       | 50      | 28 ~ 35       | 3      | 顶级战力，阵容核心 |
| **LR** | 🔴红色 | 1       | 80      | 35 ~ 45       | 4      | 传说级，改变战局的存在 |

> N 级英雄不出现在招募池，只通过关卡掉落获取，用于新手过渡。
>
> **主角（暗影君主）独立于品质体系**，不参与招募，始终拥有，详见"主角"章节。

---

## 三、角色定位分类

### 3.1 攻击类型

| 类型 | attackType | 说明 |
|------|-----------|------|
| 对单 | `single`  | 锁定单目标，高单体DPS |
| 对群 | `aoe`     | 范围伤害，清小怪效率高 |
| 链式 | `chain`   | 弹道跳跃 N 个目标，逐跳衰减 |

### 3.2 功能定位

| 定位标签 | special 值 | 核心效果 | 代表英雄 |
|---------|-----------|---------|---------|
| 纯输出   | `high_damage` | 高面板、暴击 | 暗影法师、剑圣 |
| 快攻     | `fast_attack` | 极高攻速 | 骷髅弓手、匕首刺客 |
| 减速     | `slow`        | 降低敌人移速 | 死灵术士、冰霜女巫 |
| 减抗     | `armor_break` | 降低敌人护甲/破甲抵抗 | 破甲骑士、腐蚀使徒 |
| 增伤     | `amp_damage`  | 标记目标使其受到更多伤害 | 诅咒师、幽魂刺客 |
| 持续伤害 | `dot`         | 灼烧/中毒持续掉血 | 炼狱火焰、瘟疫博士 |
| 范围控制 | `aoe_control` | 大范围减速/定身 | 暴风领主、寒冰巨灵 |
| 辅助增益 | `support`     | 增加周围友方攻击/攻速 | 战鼓祭司、光明主教 |
| BOSS杀手 | `boss_killer` | 对BOSS额外伤害/百分比生命伤害 | 屠龙者、深渊猎手 |

---

## 三点五、技能体系

### 3.5.1 技能分类

英雄拥有两类技能：**被动技能**和**主动技能**。

| 类型 | type 值 | 触发方式 | 说明 |
|------|---------|---------|------|
| **被动技能** | `passive` | 自动生效，无需操作 | 永久增益/攻击附带效果/条件触发 |
| **主动技能** | `active` | 按冷却周期自动释放 | 有 `interval` 字段控制 CD |

### 3.5.2 技能槽位与解锁

每个英雄拥有 **被动技能** + **主动技能** 共计多个技能槽位，按品质不同：

| 品质 | 总技能数 | 被动/主动分配 | 说明 |
|------|---------|-------------|------|
| N    | 1 | 1被动 | 纯被动，无主动 |
| R    | 2 | 自由分配 | 通常2被动，或1被动+1主动 |
| SR   | 3 | 自由分配 | 通常2~3被动，至多1主动 |
| SSR  | 3 | 至少1主动 | 2被动+1主动 |
| UR   | 3 | 至少1主动 | 2被动+1主动 |
| LR   | 4 | 至少1主动 | 3被动+1主动 |
| 主角 | 3 | 至少1主动 | 2被动+1主动 |

> **设计原则**: N/R/SR 级英雄被动/主动比例灵活，允许全被动的辅助/减速型英雄存在；
> SSR 及以上品质**必须有至少 1 个主动技能**，体现高品质英雄的主动操作感。

### 3.5.3 技能升级（随升星/进阶提升）

**技能不再只靠觉醒一次性 ×1.5，而是随养成进度分阶段提升。**

#### 被动技能升级节点

被动技能每到达指定**星级**时自动提升一个等级：

| 被动技能等级 | 解锁条件 | 效果 |
|-------------|---------|------|
| Lv1（初始） | 等级达到解锁线（Lv100/Lv500） | 基础效果 |
| Lv2 | ★5（黄星满） | 数值参数 ×1.3 |
| Lv3 | ★10（紫星满） | 数值参数 ×1.3（累计 ×1.69） |
| Lv4 | ★15（橙星满） | 数值参数 ×1.3（累计 ×2.20） |
| Lv5 | ★20（红星满） | 数值参数 ×1.5（累计 ×3.29） |
| Lv6 | ★25（皇冠满） | 数值参数 ×1.5（累计 ×4.94） |
| Lv7（满级） | ★30（紫晶满） | 数值参数 ×2.0（累计 ×9.88） |

> 被动技能从初始到满星共约 **×9.88 倍数值成长**。

#### 主动技能升级节点

主动技能每到达指定**进阶**阶段时提升：

| 主动技能等级 | 解锁条件 | 效果 |
|-------------|---------|------|
| Lv1（初始） | 等级达到解锁线（Lv1500） | 基础效果 |
| Lv2 | 进阶 5 | 伤害/效果 ×1.3，CD ×0.95 |
| Lv3 | 进阶 10 | 伤害/效果 ×1.3，CD ×0.95（累计 ×1.69，CD ×0.90） |
| Lv4 | 进阶 15 | 伤害/效果 ×1.5，CD ×0.90（累计 ×2.54，CD ×0.81） |
| Lv5（满级） | 进阶 20 | 伤害/效果 ×2.0，CD ×0.85（累计 ×5.07，CD ×0.69） |

> 主动技能从初始到满进阶共约 **×5.07 倍伤害**，**CD 缩短至 69%**。

### 3.5.4 技能等级与觉醒的关系

**觉醒系统保留**，但定位改为"额外加成层"，与技能等级**乘算叠加**：

```
最终技能数值 = 基础值 × 技能等级倍率 × 觉醒倍率

示例（暗影法师·暗影穿透，基础15%概率）:
  ★30 + 觉醒4 + 满进阶:
  0.15 × 9.88(被动满级) × 1.95(觉醒1+4) = 2.89 → clamp 上限
  实际设计: 概率类属性有 clamp 上限（如最高75%），倍率对其他数值生效
```

### 3.5.5 技能解锁等级

| 技能槽位 | 解锁等级 | 说明 |
|---------|---------|------|
| 技能1 | Lv100 | 所有英雄第一个技能（通常为被动） |
| 技能2 | Lv500 | R 级及以上解锁第 2 技能 |
| 技能3 | Lv1500 | SR 级及以上解锁第 3 技能 |
| 技能4（LR专属） | Lv3000 | LR 独有的第 4 技能 |

> 每个技能是被动还是主动由英雄设计决定，与解锁等级无关。
> 主动技能按 §3.5.3 进阶节点升级，被动技能按星级节点升级，系统根据 `type` 字段自动判定。

### 3.5.6 数据接口

```lua
-- 技能定义新增字段
{
    id = "shadow_pierce",
    name = "暗影穿透",
    desc = "攻击15%概率无视护盾",
    type = "passive",           -- "passive" | "active"
    chance = 0.15,              -- 基础数值参数（随技能等级倍率成长）
    maxChance = 0.75,           -- 概率类上限（clamp），可选
    -- 技能等级由系统根据星级/进阶自动计算，无需配置
}

-- Config 新增
Config.PASSIVE_UPGRADE_STARS  = { 5, 10, 15, 20, 25, 30 }  -- 被动升级星级节点
Config.PASSIVE_UPGRADE_MULTS  = { 1.3, 1.3, 1.3, 1.5, 1.5, 2.0 }  -- 每级倍率
Config.ACTIVE_UPGRADE_GATES   = { 5, 10, 15, 20 }  -- 主动升级进阶节点
Config.ACTIVE_UPGRADE_MULTS   = { 1.3, 1.3, 1.5, 2.0 }  -- 每级伤害倍率
Config.ACTIVE_UPGRADE_CD_MULTS = { 0.95, 0.95, 0.90, 0.85 }  -- 每级CD倍率
```

### 3.5.7 BOSS 平衡规则（全局约束）

所有技能在设计时必须遵守以下 BOSS 专用约束：

| 效果类型 | 对普通怪 | 对 BOSS | 说明 |
|---------|---------|---------|------|
| **%最大HP伤害** | 正常生效 | 上限为 ATK×N 倍 | N 由具体技能定义，防止 BOSS 被秒 |
| **%当前HP伤害** | 正常生效 | 上限为 ATK×N 倍 | 同上 |
| **冰冻/定身** | 正常生效 | 免疫，改为减速 | BOSS 不可被硬控 |
| **处决（斩杀线）** | 正常生效 | 免疫处决，改为固定伤害 | BOSS 不可被一击处决 |
| **减速** | 正常生效 | 效果减半 | BOSS 减速效率 ×50% |
| **眩晕** | 正常生效 | 持续时间减半 | BOSS 眩晕抗性 |
| **无限堆叠增益** | 正常生效 | 必须设上限 | 如攻速+%/波需有 cap |
| **DOT扩散/感染** | 正常生效 | 不二次扩散 | 防止连锁反应失控 |

> **设计原则**: 所有 %HP 类伤害对 BOSS 必须换算为基于英雄自身 ATK 的上限，
> 确保 BOSS 的生存时间与英雄养成程度成正相关，而非被机制直接秒杀。

---

## 三点六、货币体系

### 3.6.1 货币总览

游戏采用暗黑风货币命名，按使用场景分为 **战斗内** 和 **战斗外** 两大类：

| 货币 | 英文 ID | 图标色 | 场景 | 获取方式 | 用途 |
|------|---------|--------|------|---------|------|
| **暗魂** | `dark_soul` | 幽蓝 | 战斗内 | 击杀敌人掉落 | 战斗中召唤/合成塔 |
| **冥晶** | `nether_crystal` | 暗紫 | 战斗外 | 通关奖励、日常任务 | 英雄**升级**（提升等级） |
| **噬魂石** | `devour_stone` | 暗绿 | 战斗外 | 精英关、周常副本 | 英雄**进阶**（突破阶段） |
| **虚空契约** | `void_pact` | 深红 | 战斗外 | 成就、累计登录、稀有掉落 | 英雄招募（抽卡） |
| **灵魄碎片** | `soul_shard_{heroId}` | 随英雄品质色 | 战斗外 | 重复招募、关卡掉落 | 英雄**升星**（英雄专属） |
| **万能碎片** | `universal_shard_{rarity}` | 随品质色 | 战斗外 | 活动奖励、商店兑换 | 替代同品质任意英雄的灵魄碎片 |
| **暗影精华** | `shadow_essence` | 紫金 | 战斗外 | 高难关卡、赛季奖励 | 兑换 UR/LR 碎片、觉醒材料 |

### 3.6.2 战斗内经济 — 暗魂

```
暗魂（dark_soul）— 战斗内唯一货币

获取: 击杀普通怪 +1，精英怪 +3，BOSS +10，每波通关奖金
消耗: 召唤塔（消耗随塔数递增）、合成不消耗
特点: 每局独立，不跨局携带
```

> **设计规则**: 技能不得直接增减暗魂掉落量（见 §3.5.7）。
> 经济调节只通过关卡设计（波次奖金、怪物数量）实现，保证公平性。

### 3.6.3 战斗外养成货币

| 货币 | 用途 | 典型消耗量 | 说明 |
|------|------|-----------|------|
| **冥晶** | 升级 | Lv1→100 约需 5000 | 基础养成，产出稳定 |
| **噬魂石** | 进阶 | 每阶段 10~50 个递增 | 进阶材料，产出较慢 |
| **虚空契约** | 招募 | 单抽 1 张，十连 10 张 | 抽卡专用，产出受控 |

### 3.6.4 升星碎片体系

升星需要消耗**英雄专属的灵魄碎片**，也可用同品质**万能碎片**替代：

```
升星消耗 = 英雄专属灵魄碎片 + 万能碎片（同品质，可混用）
```

#### 灵魄碎片（英雄专属）

每个英雄拥有独立的碎片池，碎片来源：
- **重复招募**: 已拥有英雄再次抽到 → 自动转为该英雄碎片
- **关卡掉落**: 特定关卡/副本掉落指定英雄碎片
- **商店购买**: 用暗影精华兑换指定英雄碎片

| 用途 | 消耗（灵魄碎片数） |
|------|-------------------|
| 解锁英雄 | N=5 / R=10 / SR=20 / SSR=30 / UR=50 / LR=80 |
| 每次升星 | 按星级递增（★1→2 需 5 片，★29→30 需 80 片） |

#### 万能碎片（按品质分级）

可替代同品质任意英雄的灵魄碎片，但**不可跨品质使用**：

| 万能碎片 | 英文 ID | 图标色 | 可替代 |
|---------|---------|--------|--------|
| N级万能碎片 | `universal_shard_N` | 灰白 | 任意 N 级英雄碎片 |
| R级万能碎片 | `universal_shard_R` | 绿色 | 任意 R 级英雄碎片 |
| SR级万能碎片 | `universal_shard_SR` | 蓝色 | 任意 SR 级英雄碎片 |
| SSR级万能碎片 | `universal_shard_SSR` | 紫色 | 任意 SSR 级英雄碎片 |
| UR级万能碎片 | `universal_shard_UR` | 金色 | 任意 UR 级英雄碎片 |
| LR级万能碎片 | `universal_shard_LR` | 🔴红色 | 任意 LR 级英雄碎片 |

> **获取途径**: 活动奖励、赛季商店、暗影精华兑换。品质越高越稀有。

### 3.6.5 暗影精华 — 高端保底

| 操作 | 消耗暗影精华 |
|------|-------------|
| 兑换 1 个 SSR 万能碎片 | 30 |
| 兑换 1 个 UR 万能碎片 | 50 |
| 兑换 1 个 LR 万能碎片 | 100 |
| 兑换觉醒材料 | 40~80 |

### 3.6.6 数据接口

```lua
Config.CURRENCY = {
    -- 战斗内
    dark_soul       = { name = "暗魂",     icon = "soul",     color = { 80, 150, 220 } },
    -- 战斗外 · 养成
    nether_crystal  = { name = "冥晶",     icon = "crystal",  color = { 140, 80, 200 },  usage = "升级" },
    devour_stone    = { name = "噬魂石",   icon = "stone",    color = { 60, 160, 80 },   usage = "进阶" },
    -- 战斗外 · 招募
    void_pact       = { name = "虚空契约", icon = "pact",     color = { 200, 40, 40 },   usage = "招募" },
    -- 战斗外 · 高端
    shadow_essence  = { name = "暗影精华", icon = "essence",  color = { 180, 140, 255 }, usage = "兑换" },
}

-- 灵魄碎片（英雄专属，动态生成 ID）
-- ID 规则: "soul_shard_" .. heroId  (如 "soul_shard_shadow_mage")
-- 万能碎片 ID 规则: "universal_shard_" .. rarity  (如 "universal_shard_SSR")

-- 战斗内暗魂掉落（不可被技能修改）
Config.DARK_SOUL_DROP = {
    normal = 1,     -- 普通怪
    elite  = 3,     -- 精英怪
    boss   = 10,    -- BOSS
}

-- 英雄解锁所需灵魄碎片（或等量万能碎片）
Config.RARITY_SHARD_COST = { N = 5, R = 10, SR = 20, SSR = 30, UR = 50, LR = 80 }
```

---

## 四、全部英雄设计

### 4.1 N 级英雄 (3个) — 前期过渡

#### 骷髅小兵 (Skeleton Grunt)
```
id:          skeleton_grunt
rarity:      N
color:       { 180, 170, 140 }
glowColor:   { 0.7, 0.65, 0.55 }
icon:        grunt
attackType:  single
baseAttack:  8
baseRange:   100
baseSpeed:   0.8
special:     none
faction:     undead
desc:        最基础的骷髅战士，攻击稳定但伤害低
技能1 (Lv100): 亡灵韧性 — 攻速+5%（被动）
```

#### 蝙蝠仆从 (Bat Minion)
```
id:          bat_minion
rarity:      N
color:       { 140, 120, 160 }
glowColor:   { 0.55, 0.47, 0.63 }
icon:        bat
attackType:  single
baseAttack:  6
baseRange:   120
baseSpeed:   0.4
special:     fast_attack
faction:     demon
desc:        攻击极快但伤害极低的蝙蝠，适合触发命中效果
技能1 (Lv100): 吸血本能 — 攻击有10%概率使目标减速10%持续1秒（被动）
```

#### 地狱犬 (Hell Hound)
```
id:          hell_hound
rarity:      N
color:       { 200, 100, 50 }
glowColor:   { 0.8, 0.4, 0.2 }
icon:        hound
attackType:  aoe
baseAttack:  10
baseRange:   70
baseSpeed:   1.2
special:     dot
dotDamage:   2
dotDuration: 1.5
faction:     demon
desc:        喷出小范围火焰灼烧敌人，前期清小怪利器
技能1 (Lv100): 烈焰喷息 — DOT伤害+30%（被动）
```

---

### 4.2 R 级英雄 (4个) — 基础主力

#### 骷髅弓手 (Skeleton Archer) ★已实现
```
id:          skeleton_archer
rarity:      R
color:       { 80, 200, 80 }
glowColor:   { 0.3, 0.8, 0.3 }
icon:        archer
attackType:  single
baseAttack:  12
baseRange:   140
baseSpeed:   0.5
special:     fast_attack
faction:     undead
desc:        射速极快的远程射手，持续输出稳定
技能1 (Lv100): 连射       — 20%概率连射2箭（被动）
技能2 (Lv500): 弱点标记   — 目标受伤+10%持续3秒（被动）
```

#### 恶魔战士 (Demon Warrior) ★已实现
```
id:          demon_warrior
rarity:      R
color:       { 220, 60, 60 }
glowColor:   { 0.9, 0.2, 0.2 }
icon:        demon
attackType:  aoe
baseAttack:  18
baseRange:   80
baseSpeed:   1.2
special:     aoe_damage
faction:     demon
desc:        近距离范围攻击，对密集怪群伤害可观
技能1 (Lv100): 燃烧大地   — AOE留下燃烧地面2秒（被动）
技能2 (Lv500): 恶魔之怒   — 攻速随波次+0.5%/波，最多+25%，每波结束重置（被动）
```

#### 幽魂刺客 (Ghost Assassin)
```
id:          ghost_assassin
rarity:      R
color:       { 100, 180, 200 }
glowColor:   { 0.4, 0.7, 0.8 }
icon:        assassin
attackType:  single
baseAttack:  15
baseRange:   90
baseSpeed:   0.7
special:     amp_damage
ampRate:     0.08
ampDuration: 3.0
faction:     undead
desc:        攻击标记敌人，使其受到所有来源8%额外伤害
技能1 (Lv100): 致命标记   — 本英雄施加的标记增伤提升至12%，标记对所有友方伤害源生效（被动）
技能2 (Lv500): 背刺       — 本英雄对已标记目标15%概率双倍伤害（被动）
```

#### 石像兵 (Stone Golem)
```
id:          stone_golem
rarity:      R
color:       { 160, 150, 130 }
glowColor:   { 0.6, 0.55, 0.5 }
icon:        golem
attackType:  single
baseAttack:  14
baseRange:   80
baseSpeed:   1.5
special:     slow
slowRate:    0.20
faction:     elemental
desc:        攻击缓慢但自带减速效果，适合配合高输出英雄
技能1 (Lv100): 沉重一击   — 减速提升至30%（被动）
技能2 (Lv500): 碎石溅射   — 20%概率减速周围30px内其他敌人（被动）
```

---

### 4.3 SR 级英雄 (5个) — 中坚特色

#### 死灵术士 (Necromancer) ★已实现
```
id:          necromancer
rarity:      SR
color:       { 60, 200, 200 }
glowColor:   { 0.2, 0.8, 0.8 }
icon:        necro
attackType:  single
baseAttack:  15
baseRange:   110
baseSpeed:   1.0
special:     slow
slowRate:    0.30
faction:     undead
desc:        强力减速专家，让敌人在攻击范围内停留更久
技能1 (Lv100):  深度冻结   — 减速提升至45%（被动）
技能2 (Lv500):  诅咒标记   — 被本英雄减速的敌人每秒额外受到死灵术士ATK×5%的伤害（被动）
技能3 (Lv1500): 灵魂锁链   — 减速效果扩散至目标40px内最多2个敌人，不会二次扩散（被动）
```

#### 炼狱火焰 (Inferno Flame) ★已实现
```
id:          inferno_flame
rarity:      SR
color:       { 240, 150, 30 }
glowColor:   { 1.0, 0.6, 0.1 }
icon:        flame
attackType:  aoe
baseAttack:  8
baseRange:   90
baseSpeed:   0.8
special:     dot
dotDamage:   5
dotDuration: 2.0
faction:     elemental
desc:        持续灼烧大范围敌人，拖延战消耗型选手
技能1 (Lv100):  强化灼烧   — DOT伤害+50%（被动）
技能2 (Lv500):  火焰蔓延   — DOT目标死亡传递剩余DOT（被动）
技能3 (Lv1500): 涅槃之炎   — 对BOSS时DOT伤害改为ATK×300%每秒，无视普通DOT上限（被动）
```

#### 破甲骑士 (Armor Breaker)
```
id:          armor_breaker
rarity:      SR
color:       { 200, 180, 100 }
glowColor:   { 0.8, 0.7, 0.4 }
icon:        knight
attackType:  single
baseAttack:  18
baseRange:   90
baseSpeed:   1.1
special:     armor_break
armorBreak:  0.08
armorBreakDuration: 5.0
faction:     human
desc:        攻击降低敌人8%护甲抵抗，持续5秒，可叠加
技能1 (Lv100):  精准打击   — 护甲削减提升至12%（被动）
技能2 (Lv500):  破甲叠加   — 最多叠加3层（被动）
技能3 (Lv1500): 致命弱点   — 满层目标额外受到20%伤害（被动）
```

#### 冰霜女巫 (Frost Witch)
```
id:          frost_witch
rarity:      SR
color:       { 120, 180, 255 }
glowColor:   { 0.47, 0.7, 1.0 }
icon:        witch
attackType:  chain
baseAttack:  12
baseRange:   120
baseSpeed:   1.0
special:     slow
slowRate:    0.25
chainCount:  3
chainDecay:  0.7
faction:     elemental
desc:        冰霜链式弹道跳跃3个目标，逐跳减速+伤害衰减
技能1 (Lv100):  极寒之触   — 减速提升至35%（被动）
技能2 (Lv500):  冰冻概率   — 10%概率冰冻目标1.5秒；BOSS免疫冰冻，改为额外减速50%持续1秒（被动）
技能3 (Lv1500): 暴风雪     — 每20秒释放全屏减速40%持续3秒（主动）
```

#### 战鼓祭司 (War Drummer)
```
id:          war_drummer
rarity:      SR
color:       { 220, 180, 80 }
glowColor:   { 0.85, 0.7, 0.3 }
icon:        drummer
attackType:  single
baseAttack:  10
baseRange:   100
baseSpeed:   1.2
special:     support
auraRange:   80
atkBuff:     0.10
faction:     human
desc:        本身输出低，但为周围80px内友方塔提供10%攻击加成
技能1 (Lv100):  鼓舞士气   — 光环攻击加成提升至15%（被动）
技能2 (Lv500):  战吼节奏   — 光环额外+10%攻速（被动）
技能3 (Lv1500): 英勇战歌   — 每30秒全体塔攻击+25%持续5秒（主动）
```

---

### 4.4 SSR 级英雄 (4个) — 核心输出

#### 暗影法师 (Shadow Mage) ★已实现
```
id:          shadow_mage
rarity:      SSR
color:       { 160, 80, 220 }
glowColor:   { 0.6, 0.3, 0.9 }
icon:        mage
attackType:  single
baseAttack:  25
baseRange:   120
baseSpeed:   1.0
special:     high_damage
faction:     undead
desc:        暗影系核心输出，高伤害+击杀叠加爆发
技能1 (Lv100):  暗影穿透   — 攻击15%概率无视护盾（被动）
技能2 (Lv500):  灵魂收割   — 击杀敌人后下次攻击伤害+30%，可叠加3层，攻击后清零（被动）
技能3 (Lv1500): 虚空风暴   — 每15秒全屏30%攻击力伤害（主动）
```

#### 深渊猎手 (Abyss Hunter)
```
id:          abyss_hunter
rarity:      SSR
color:       { 180, 50, 90 }
glowColor:   { 0.7, 0.2, 0.35 }
icon:        hunter
attackType:  single
baseAttack:  22
baseRange:   130
baseSpeed:   0.9
special:     boss_killer
bossExtraDmg: 0.30
faction:     demon
desc:        BOSS杀手定位，对BOSS+30%额外伤害，精英也有效
技能1 (Lv100):  猎杀本能   — 对BOSS额外伤害提升至50%（被动）
技能2 (Lv500):  致命猎弩   — 暴击率+15%，暴击伤害+30%（被动）
技能3 (Lv1500): 深渊之箭   — 每12秒对血量最高敌人造成其8%最大HP伤害，对BOSS伤害上限为ATK×8（主动）
```

#### 瘟疫博士 (Plague Doctor)
```
id:          plague_doctor
rarity:      SSR
color:       { 100, 180, 60 }
glowColor:   { 0.4, 0.7, 0.25 }
icon:        plague
attackType:  aoe
baseAttack:  15
baseRange:   100
baseSpeed:   1.0
special:     dot
dotDamage:   12
dotDuration: 4.0
faction:     human
desc:        高伤DOT+减抗复合型，对群持续施压
技能1 (Lv100):  剧毒瘴气   — DOT期间敌人护甲抵抗-5%（被动）
技能2 (Lv500):  感染扩散   — DOT目标30px内最多2个敌人感染50%DOT，被感染目标不会二次扩散（被动）
技能3 (Lv1500): 瘟疫爆发   — 每18秒引爆所有DOT目标，造成剩余DOT总量200%即时伤害（主动）
```

#### 暴风领主 (Storm Lord)
```
id:          storm_lord
rarity:      SSR
color:       { 80, 140, 255 }
glowColor:   { 0.3, 0.55, 1.0 }
icon:        storm
attackType:  aoe
baseAttack:  20
baseRange:   110
baseSpeed:   1.3
special:     aoe_control
slowRate:    0.35
stunChance:  0.08
stunDuration: 1.0
faction:     elemental
desc:        大范围AOE+减速+概率眩晕，人形战场控制器
技能1 (Lv100):  雷鸣一击   — 眩晕概率提升至15%（被动）
技能2 (Lv500):  风暴之眼   — 攻击范围+20px（被动）
技能3 (Lv1500): 天降雷霆   — 每22秒对所有敌人造成25%攻击力伤害并减速50%持续2秒（主动）
```

---

### 4.5 UR 级英雄 (2个) — 顶级战力

#### 堕天使长 (Fallen Archangel)
```
id:          fallen_archangel
rarity:      UR
color:       { 255, 215, 60 }
glowColor:   { 1.0, 0.85, 0.25 }
icon:        archangel
attackType:  aoe
baseAttack:  30
baseRange:   130
baseSpeed:   1.0
special:     amp_damage
ampRate:     0.15
ampDuration: 5.0
faction:     human
desc:        堕落的天使长，攻击标记全体目标使其受到15%额外伤害
技能1 (Lv100):  神罚之光   — 标记增伤提升至20%（被动）
技能2 (Lv500):  天使审判   — 每15秒对全屏敌人造成35%攻击力伤害（主动）
技能3 (Lv1500): 堕落荣光   — 光环：周围100px友方塔暴击率+12%（被动）
```

#### 虚空龙王 (Void Dragon)
```
id:          void_dragon
rarity:      UR
color:       { 255, 200, 50 }
glowColor:   { 1.0, 0.8, 0.2 }
icon:        dragon
attackType:  chain
baseAttack:  28
baseRange:   120
baseSpeed:   0.8
special:     boss_killer
bossExtraDmg: 0.25
chainCount:  4
chainDecay:  0.8
faction:     demon
desc:        来自虚空的龙王，链式吐息弹射4个目标，对BOSS有25%额外伤害
技能1 (Lv100):  龙息灼烧   — 链式攻击附带灼烧DOT，造成ATK×10%每秒，持续3秒（被动）
技能2 (Lv500):  虚空撕裂   — 对BOSS额外伤害提升至40%（被动）
技能3 (Lv1500): 龙王之怒   — 每12秒释放全屏龙息，造成50%攻击力伤害并减速30%持续3秒（主动）
```

---

### 4.6 LR 级英雄 (2个) — 传说级

#### 命运织者 (Fate Weaver)
```
id:          fate_weaver
rarity:      LR
color:       { 220, 40, 40 }
glowColor:   { 0.9, 0.15, 0.15 }
icon:        weaver
attackType:  aoe
baseAttack:  38
baseRange:   140
baseSpeed:   1.0
special:     support
auraRange:   999
atkBuff:     0.12
spdBuff:     0.10
faction:     elemental
desc:        编织命运之线的太古存在，全场光环增攻12%+增速10%，同时AOE输出不俗
技能1 (Lv100):  命运之线   — 光环额外降低敌人受治愈效果30%（被动）
技能2 (Lv500):  时间编织   — 每25秒重置全体友方塔技能CD（主动）
技能3 (Lv1500): 因果律     — 全体友方塔获得15%概率双倍伤害（被动）
技能4 (Lv3000): 命运终章   — 当任何友方造成致命一击时，额外对周围敌人造成溅射50%伤害（被动）
```

#### 永恒魔君 (Eternal Archfiend)
```
id:          eternal_archfiend
rarity:      LR
color:       { 200, 20, 20 }
glowColor:   { 0.85, 0.1, 0.1 }
icon:        archfiend
attackType:  single
baseAttack:  45
baseRange:   120
baseSpeed:   0.7
special:     high_damage
faction:     demon
desc:        面板最高的纯输出单位，单体爆发无人能敌
技能1 (Lv100):  魔君一击   — 暴击率+20%，暴击伤害+50%（被动）
技能2 (Lv500):  永恒之力   — 每击杀一个敌人，本波剩余时间内攻击永久+1%，最多+50%（被动）
技能3 (Lv1500): 灭世之炎   — 每10秒对血量最高敌人造成其当前HP 10%的伤害，对BOSS伤害上限为ATK×10（主动）
技能4 (Lv3000): 终焉审判   — 对HP低于15%的敌人直接处决；BOSS免疫处决，改为造成ATK×15的固定伤害（被动）
```

---

### 4.7 主角 — 暗影君主 (独立，无品质)

> **暗影君主不属于任何品质体系**，是玩家始终拥有的独立主角单位。
> 随从英雄等级不能超过主角等级，保证主角养成优先级。

#### 暗影君主 (Shadow Lord) ★已实现
```
id:          leader
rarity:      none（主角独立）
color:       { 180, 120, 255 }
glowColor:   { 0.7, 0.45, 1.0 }
borderColor: 渐变紫金（独特主角边框，区别于所有品质）
icon:        leader
attackType:  single
baseAttack:  30
baseRange:   130
baseSpeed:   0.9
special:     leader
isLeader:    true
faction:     shadow
desc:        暗影之主，统率一切暗影军团。不属于品质体系，始终拥有。
技能1 (Lv100):  暗影支配   — 全体友方塔攻击+5%（被动光环）
技能2 (Lv500):  君主意志   — 击杀敌人时8%概率重置主动技能1秒CD（被动）
技能3 (Lv1500): 暗影吞噬   — 每10秒对全屏敌人造成40%攻击力伤害（主动）
```

---

## 五、阵营与羁绊系统

### 5.1 阵营分类

| 阵营 | faction 值 | 颜色标识 | 包含英雄 |
|------|-----------|---------|---------|
| **亡灵** | `undead`    | 暗绿 | 骷髅小兵、骷髅弓手、幽魂刺客、死灵术士、暗影法师 |
| **恶魔** | `demon`     | 暗红 | 蝙蝠仆从、恶魔战士、深渊猎手、虚空龙王(UR)、永恒魔君(LR) |
| **元素** | `elemental` | 青蓝 | 地狱犬、炼狱火焰、冰霜女巫、暴风领主、命运织者(LR) |
| **人类** | `human`     | 金黄 | 石像兵、破甲骑士、战鼓祭司、瘟疫博士、堕天使长(UR) |
| **暗影** | `shadow`    | 紫金 | 暗影君主(主角独占，无品质) |

### 5.2 同阵营羁绊（场上同阵营英雄数触发）

| 人数 | 效果 | 说明 |
|------|------|------|
| 2    | 攻击 +8% | 小型增益，容易凑齐 |
| 3    | 攻击 +15%, 攻速 +8% | 明显提升 |
| 4    | 攻击 +25%, 攻速 +15%, 特殊效果 | 强力羁绊 |

#### 各阵营 4 人特殊效果

| 阵营 | 4人特殊效果 |
|------|------------|
| 亡灵 | **亡灵诅咒** — 敌人死亡时对周围敌人造成其最大HP 5%的伤害 |
| 恶魔 | **恶魔狂热** — 每击杀1个敌人，全体攻速+2%，最多叠加15层，每波重置 |
| 元素 | **元素共鸣** — 减速/DOT/眩晕效果持续时间+40% |
| 人类 | **人类联盟** — 全体塔射程+20px，且暴击率+8% |

### 5.3 跨阵营组合羁绊

| 组合名 | 条件 | 效果 |
|--------|------|------|
| **死亡军团** | 亡灵 ×2 + 恶魔 ×2 | 全体暴击率+10% |
| **自然之力** | 元素 ×2 + 人类 ×2 | 全体攻击+12%, 减速效果+15% |
| **暗影议会** | 暗影(主角) + 亡灵 ×2 + 恶魔 ×1 | 主角攻击+20%, 暗影吞噬CD-3秒 |
| **五族共存** | 4个不同阵营各≥1 | 全体攻击+10%, 攻速+10%, 射程+10px |

---

## 六、数据接口对照

### 6.1 TOWER_TYPES 字段规范

```lua
{
    -- 基础标识
    id          = "armor_breaker",     -- 唯一ID
    name        = "破甲骑士",           -- 显示名称
    rarity      = "SR",                -- N/R/SR/SSR/UR/LR（主角为 "none"）
    faction     = "human",             -- 阵营

    -- 视觉
    color       = { 200, 180, 100 },   -- RGB主色
    glowColor   = { 0.8, 0.7, 0.4 },  -- Bloom光晕色(0~1)
    icon        = "knight",            -- 图标标识/精灵图名

    -- 战斗属性
    attackType  = "single",            -- single/aoe/chain
    baseAttack  = 18,                  -- 基础攻击力
    baseRange   = 90,                  -- 基础射程(px)
    baseSpeed   = 1.1,                 -- 攻击间隔(秒)

    -- 特殊能力 (可选)
    special         = "armor_break",   -- 定位标签
    armorBreak      = 0.08,            -- 减抗比例
    armorBreakDuration = 5.0,          -- 减抗持续时间

    -- 链式攻击专用 (可选)
    chainCount  = 3,                   -- 跳跃次数
    chainDecay  = 0.7,                 -- 逐跳伤害衰减

    -- 辅助专用 (可选)
    auraRange   = 80,                  -- 光环范围
    atkBuff     = 0.10,                -- 攻击加成

    -- BOSS杀手专用 (可选)
    bossExtraDmg = 0.30,               -- 对BOSS额外伤害
}
```

### 6.2 招募权重与招募池（消耗虚空契约）

```lua
Config.RARITY_SUMMON_WEIGHT = { N = 40, R = 30, SR = 17, SSR = 8, UR = 3, LR = 1 }
-- RARITY_SHARD_COST 见 §3.6.6 货币体系数据接口

Config.RECRUIT_POOL = {
    N   = { "skeleton_grunt", "bat_minion", "hell_hound" },
    R   = { "skeleton_archer", "demon_warrior", "ghost_assassin", "stone_golem" },
    SR  = { "necromancer", "inferno_flame", "armor_breaker", "frost_witch", "war_drummer" },
    SSR = { "shadow_mage", "abyss_hunter", "plague_doctor", "storm_lord" },
    UR  = { "fallen_archangel", "void_dragon" },
    LR  = { "fate_weaver", "eternal_archfiend" },
    -- 主角 (leader) 不在招募池，始终拥有，rarity = "none"
}
```

### 6.3 羁绊配置结构

```lua
Config.FACTIONS = {
    undead    = { name = "亡灵", color = { 80, 180, 80 } },
    demon     = { name = "恶魔", color = { 220, 60, 60 } },
    elemental = { name = "元素", color = { 80, 180, 255 } },
    human     = { name = "人类", color = { 220, 200, 80 } },
    shadow    = { name = "暗影", color = { 200, 160, 255 } },
}

Config.FACTION_BONDS = {
    -- 同阵营羁绊
    { type = "same_faction", count = 2, effects = { atkMult = 0.08 } },
    { type = "same_faction", count = 3, effects = { atkMult = 0.15, spdMult = 0.08 } },
    { type = "same_faction", count = 4, effects = { atkMult = 0.25, spdMult = 0.15 } },
}

Config.FACTION_SPECIAL_4 = {
    undead    = { id = "undead_curse",  name = "亡灵诅咒", deathAoePct = 0.05 },
    demon     = { id = "demon_frenzy", name = "恶魔狂热", killAtkSpd = 0.02, maxStacks = 15 },
    elemental = { id = "elem_resonance", name = "元素共鸣", effectDurationMult = 1.4 },
    human     = { id = "human_alliance", name = "人类联盟", rangeBonus = 20, critRate = 0.08 },
}

Config.CROSS_BONDS = {
    { id = "death_legion", name = "死亡军团",
      require = { undead = 2, demon = 2 },
      effects = { critRate = 0.10 } },
    { id = "nature_force", name = "自然之力",
      require = { elemental = 2, human = 2 },
      effects = { atkMult = 0.12, slowBonus = 0.15 } },
    { id = "shadow_council", name = "暗影议会",
      require = { shadow = 1, undead = 2, demon = 1 },
      effects = { leaderAtkMult = 0.20, leaderCdReduce = 3.0 } },
    { id = "five_factions", name = "五族共存",
      requireDistinct = 4,
      effects = { atkMult = 0.10, spdMult = 0.10, rangeBonus = 10 } },
}
```

---

## 七、英雄总览矩阵

| 英雄 | 品质 | 阵营 | 攻击 | 定位 | 核心价值 |
|------|------|------|------|------|---------|
| 骷髅小兵 | N | 亡灵 | 对单 | 基础 | 廉价填充 |
| 蝙蝠仆从 | N | 恶魔 | 对单 | 快攻 | 极快攻速触发效果 |
| 地狱犬 | N | 恶魔 | 对群 | DOT | 前期清杂兵 |
| 骷髅弓手 | R | 亡灵 | 对单 | 快攻 | 远程持续输出 |
| 恶魔战士 | R | 恶魔 | 对群 | AOE | 近战群伤 |
| 幽魂刺客 | R | 亡灵 | 对单 | 增伤 | 标记增伤辅助 |
| 石像兵 | R | 人类 | 对单 | 减速 | 减速+肉盾定位 |
| 死灵术士 | SR | 亡灵 | 对单 | 减速 | 强力减速+连锁 |
| 炼狱火焰 | SR | 元素 | 对群 | DOT | 大范围灼烧 |
| 破甲骑士 | SR | 人类 | 对单 | 减抗 | 削甲叠层增伤 |
| 冰霜女巫 | SR | 元素 | 链式 | 减速 | 链式减速+冰冻 |
| 战鼓祭司 | SR | 人类 | 对单 | 辅助 | 光环增攻增速 |
| 暗影法师 | SSR | 亡灵 | 对单 | 纯输出 | 高伤+击杀叠加爆发 |
| 深渊猎手 | SSR | 恶魔 | 对单 | BOSS杀手 | 对BOSS额外伤害 |
| 瘟疫博士 | SSR | 人类 | 对群 | DOT+减抗 | DOT引爆+减甲 |
| 暴风领主 | SSR | 元素 | 对群 | 范围控制 | AOE眩晕+减速 |
| 堕天使长 | UR | 人类 | 对群 | 增伤 | AOE标记+暴击光环 |
| 虚空龙王 | UR | 恶魔 | 链式 | BOSS杀手 | 链式龙息+BOSS克星 |
| 命运织者 | 🔴LR | 元素 | 对群 | 辅助 | 全场光环+双倍概率 |
| 永恒魔君 | 🔴LR | 恶魔 | 对单 | 纯输出 | 最高面板+处决机制 |
| **暗影君主** | **主角** | **暗影** | **对单** | **统领** | **等级压制+全局光环** |

---

## 八、推荐阵容搭配

### 8.1 纯输出阵容 — "死亡军团"
```
暗影法师(SSR) + 深渊猎手(SSR) + 骷髅弓手(R) + 恶魔战士(R) + 暗影君主(主角)
羁绊: 亡灵×2(+8%攻), 恶魔×2(+8%攻), 死亡军团(暴击+10%)
定位: 纯DPS，暴击+高面板碾压
```

### 8.2 控制消耗阵容 — "冰火地狱"
```
死灵术士(SR) + 冰霜女巫(SR) + 炼狱火焰(SR) + 暴风领主(SSR) + 暗影君主(主角)
羁绊: 元素×3(+15%攻, +8%速), 元素共鸣(效果+40%)
定位: 全场减速+DOT+眩晕，敌人寸步难行
```

### 8.3 BOSS速杀阵容 — "暗影议会"
```
暗影法师(SSR) + 深渊猎手(SSR) + 破甲骑士(SR) + 幽魂刺客(R) + 暗影君主(主角)
羁绊: 暗影议会(主角+20%攻), 亡灵×3(+15%攻, +8%速)
定位: 削甲+标记+BOSS额外伤害，BOSS关速通
```

### 8.4 平衡泛用阵容 — "五族共存"
```
骷髅弓手(R) + 恶魔战士(R) + 冰霜女巫(SR) + 战鼓祭司(SR) + 暗影君主(主角)
羁绊: 五族共存(+10%攻, +10%速, +10射程)
定位: 万金油，输出/控制/辅助均衡
```

### 8.5 传说毕业阵容 — "永恒终焉"
```
永恒魔君(LR) + 命运织者(LR) + 深渊猎手(SSR) + 破甲骑士(SR) + 暗影君主(主角)
羁绊: 恶魔×2(+8%攻), 暗影议会(主角+20%攻)
定位: LR双核，命运织者全场增益+永恒魔君处决收割，终极阵容
```

### 8.6 龙王破甲流 — "虚空屠龙"
```
虚空龙王(UR) + 堕天使长(UR) + 破甲骑士(SR) + 瘟疫博士(SSR) + 暗影君主(主角)
羁绊: 人类×2(+8%攻), 恶魔×2(+8%攻), 死亡军团(暴击+10%)
定位: 链式+AOE增伤+破甲，BOSS关和精英关兼顾
```

---

## 九、实现优先级

| 阶段 | 内容 | 涉及文件 |
|------|------|---------|
| **P0** | 将新英雄数据写入 Config.TOWER_TYPES + HERO_BASE_STATS + HERO_SKILLS（含 UR/LR 新英雄） | Config.lua |
| **P0** | 为每个新英雄生成精灵图并注册 SpriteSheet | Renderer.lua, assets/ |
| **P0** | 主角品质改为 `"none"`，独立于品质体系显示（紫金渐变边框） | Config.lua, Renderer.lua |
| **P1** | 实现 chain 攻击类型 | Combat.lua |
| **P1** | 实现 armor_break / amp_damage / support / boss_killer 四种 special | Combat.lua, HeroSkills.lua |
| **P1** | 实现阵营羁绊计算与 UI 展示 | 新建 Faction.lua, HeroUI.lua |
| **P1** | LR 品质特殊视觉效果（红色光效、独特边框动画） | Renderer.lua |
| **P2** | 实现跨阵营组合羁绊 | Faction.lua |
| **P2** | N级英雄关卡掉落机制 | Wave.lua, GameUI.lua |
| **P2** | LR 第4技能系统（Lv3000 解锁） | HeroSkills.lua |
| **P3** | 阵容推荐 UI | HeroUI.lua |
