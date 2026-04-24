# 暗影召唤师 - 英雄技能详情文档

> 本文档记录所有英雄的基础属性、技能数值（30星满值）和代码实现逻辑。
>
> **数值缩放公式**：`factor = 0.10 + 0.90 × √(star / 30)`（0星=10%，30星=100%）
>
> **场内星级倍率**：★1=1.0x / ★2=2.0x / ★3=4.5x / ★4=10.0x / ★5=22.0x

---

## 目录

- [N 级](#n-级)
  - [骷髅小兵 skeleton_grunt](#骷髅小兵-skeleton_grunt)
  - [蝙蝠仆从 bat_minion](#蝙蝠仆从-bat_minion)
  - [地狱犬 hell_hound](#地狱犬-hell_hound)
- [R 级](#r-级)
  - [骷髅弓手 skeleton_archer](#骷髅弓手-skeleton_archer)
  - [恶魔战士 demon_warrior](#恶魔战士-demon_warrior)
  - [幽魂刺客 ghost_assassin](#幽魂刺客-ghost_assassin)
  - [石像兵 stone_golem](#石像兵-stone_golem)
- [SR 级](#sr-级)
  - [死灵术士 necromancer](#死灵术士-necromancer)
  - [炼狱火焰 inferno_flame](#炼狱火焰-inferno_flame)
  - [破甲骑士 armor_breaker](#破甲骑士-armor_breaker)
  - [冰霜女巫 frost_witch](#冰霜女巫-frost_witch)
  - [战鼓祭司 war_drummer](#战鼓祭司-war_drummer)
- [SSR 级](#ssr-级)
  - [暗影法师 shadow_mage](#暗影法师-shadow_mage)
  - [深渊猎手 abyss_hunter](#深渊猎手-abyss_hunter)
  - [瘟疫博士 plague_doctor](#瘟疫博士-plague_doctor)
  - [暴风领主 storm_lord](#暴风领主-storm_lord)
- [UR 级](#ur-级)
  - [堕天使长 fallen_archangel](#堕天使长-fallen_archangel)
  - [虚空龙王 void_dragon](#虚空龙王-void_dragon)
  - [翎嫣 nature_elf](#翎嫣-nature_elf)
  - [绯夜 crimson_night](#绯夜-crimson_night)
  - [凛冬君王 glacial_sovereign](#凛冬君王-glacial_sovereign)
- [LR 级](#lr-级)
  - [命运织者 fate_weaver](#命运织者-fate_weaver)
  - [永恒魔君 eternal_archfiend](#永恒魔君-eternal_archfiend)
- [主角](#主角)
  - [暗影领主 leader](#暗影领主-leader)

---

## N 级

> 功率参考：1个被动，效果简单

### 骷髅小兵 skeleton_grunt

| 属性 | 值 |
|------|-----|
| 阵营 | 亡灵 |
| 攻击类型 | 单体 |
| 基础射程 | 100px |
| 基础攻速 | 0.8s |
| 特殊 | 无 |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 亡灵韧性 (undead_tenacity) | 被动 | 攻速+30% |

**实现逻辑**（skeleton_grunt.lua）：
- `ModifyAttackSpeed`：读取 `atkSpdBonus`（默认0.05，技能满值0.30），将攻击间隔除以 `(1 + atkSpdBonus)`，即攻击频率提升30%。

---

### 蝙蝠仆从 bat_minion

| 属性 | 值 |
|------|-----|
| 阵营 | 恶魔 |
| 攻击类型 | 单体 |
| 基础射程 | 120px |
| 基础攻速 | 0.4s（快攻） |
| 特殊 | fast_attack |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 吸血本能 (vampire_instinct) | 被动 | 攻击40%概率减速目标30%持续1秒 |

**实现逻辑**（bat_minion.lua）：
- `OnHit`：每次命中存活目标，以 `chance`（0.40）概率触发，调用 `Enemy.ApplySlow(target, 1.0, 0.30)`。

---

### 地狱犬 hell_hound

| 属性 | 值 |
|------|-----|
| 阵营 | 恶魔 |
| 攻击类型 | AOE |
| 基础射程 | 70px |
| 基础攻速 | 1.2s |
| 特殊 | DOT（基础DOT伤害2，持续1.5s） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 烈焰喷息 (flame_breath) | 被动 | DOT伤害+100%（×2.0倍） |

**实现逻辑**（hell_hound.lua）：
- `ModifyDotDamage`：将DOT伤害乘以 `dotMultiplier`（2.0），即DOT翻倍。

---

## R 级

> 功率参考：2个被动，组合效果。总收益约为N级2倍

### 骷髅弓手 skeleton_archer

| 属性 | 值 |
|------|-----|
| 阵营 | 亡灵 |
| 攻击类型 | 单体 |
| 基础射程 | 140px |
| 基础攻速 | 0.5s（快攻） |
| 特殊 | fast_attack |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 连射 (multi_shot) | 被动 | 40%概率连射2箭 |
| 2 | 弱点标记 (weak_mark) | 被动 | 目标受伤+25%持续3秒 |

**实现逻辑**（skeleton_archer.lua）：
- `ShouldMultiShot`：以 `chance`（0.40）概率返回 true，触发额外一发攻击。
- `OnHit`：对存活目标施加 `amp_damage` debuff，增伤 `bonusDmg`（0.25），持续3秒。该增伤对所有友方塔生效。

---

### 恶魔战士 demon_warrior

| 属性 | 值 |
|------|-----|
| 阵营 | 恶魔 |
| 攻击类型 | AOE |
| 基础射程 | 80px |
| 基础攻速 | 1.2s |
| 特殊 | aoe_damage |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 燃烧大地 (burning_ground) | 被动 | AOE留下燃烧地面2秒 |
| 2 | 恶魔之怒 (demon_fury) | 被动 | 攻速随波次+1.5%/波，最多+50%，每波重置 |

**实现逻辑**（demon_warrior.lua）：
- `ModifyAttackSpeed`：计算 `bonus = min(当前波数 × bonusPerWave(0.015), maxBonus(0.50))`，攻击间隔除以 `(1 + bonus)`。例如第20波时 bonus=30%，第34波封顶50%。

---

### 幽魂刺客 ghost_assassin

| 属性 | 值 |
|------|-----|
| 阵营 | 亡灵 |
| 攻击类型 | 单体 |
| 基础射程 | 90px |
| 基础攻速 | 0.7s |
| 特殊 | amp_damage（基础增伤8%，持续3秒） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 致命标记 (lethal_mark) | 被动 | 标记增伤提升至20%，对所有友方生效 |
| 2 | 背刺 (backstab) | 被动 | 对已标记目标25%概率双倍伤害 |

**实现逻辑**（ghost_assassin.lua）：
- `OnHit`：对存活目标施加 `amp_damage` debuff，增伤 `ampRate`（0.20），持续3秒。覆盖 Config_Core 的基础 ampRate(0.08)。

> 注：backstab 的实现在 Combat.lua 的 CalcFinalDamage 中检查 target 是否携带 amp_damage 标记。

---

### 石像兵 stone_golem

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | 单体 |
| 基础射程 | 80px |
| 基础攻速 | 1.5s（慢攻） |
| 特殊 | slow（基础减速20%） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 沉重一击 (heavy_strike) | 被动 | 减速提升至30% |
| 2 | 碎石溅射 (rock_splash) | 被动 | 50%概率减速周围30px内其他敌人 |

**实现逻辑**（stone_golem.lua）：
- `ModifySlowRate`：直接返回 `newSlowRate`（0.30），覆盖基础减速率。
- `OnHit`：以 `chance`（0.50）概率触发，遍历 `splashRange`（30px）内的存活敌人，施加减速 `slowRate`（0.25）持续1.5秒。**BOSS减速效率减半**（×0.50）。

---

## SR 级

> 功率参考：2-3被动 + 0-1主动。总收益约为R级2倍

### 死灵术士 necromancer

| 属性 | 值 |
|------|-----|
| 阵营 | 亡灵 |
| 攻击类型 | 单体 |
| 基础射程 | 110px |
| 基础攻速 | 1.0s |
| 特殊 | slow（基础减速30%） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 深度冻结 (deep_freeze) | 被动 | 减速提升至45% |
| 2 | 诅咒标记 (curse_mark) | 被动 | 被减速敌人每秒受ATK×15%伤害 |
| 3 | 灵魂锁链 (soul_chain) | 被动 | 减速扩散至40px内最多2敌人，不二次扩散 |

**实现逻辑**（necromancer.lua）：
- `ModifySlowRate`：返回 `newSlowRate`（0.45）。
- `HandleSlowSpread`：减速命中时，查找40px内最多2个未被扩散的存活敌人，施加相同减速。标记 `e.slowSpread = true` 防止二次扩散。
- `UpdateGlobal(dt)`：**全局帧更新**。遍历所有塔找到拥有 curse_mark 的术士，然后遍历所有存活且正在被减速的敌人（`slowTimer > 0`），每帧造成 `tower.attack × curseDmgAtkPct(0.15) × dt` 伤害。多个术士叠加。

---

### 炼狱火焰 inferno_flame

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | AOE |
| 基础射程 | 90px |
| 基础攻速 | 0.8s |
| 特殊 | DOT（基础DOT伤害5，持续2.0s） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 强化灼烧 (enhanced_burn) | 被动 | DOT伤害+200%（×3.0倍） |
| 2 | 火焰蔓延 (fire_spread) | 被动 | DOT目标死亡传递剩余DOT |
| 3 | 涅槃之炎 (nirvana_flame) | 被动 | 对BOSS DOT改为ATK×800%每秒 |

**实现逻辑**（inferno_flame.lua）：
- `ModifyDotDamage`：将DOT伤害×`dotMultiplier`（3.0）。如果目标是BOSS且有 nirvana_flame，则取 `tower.attack × bossAtkPct(8.0)` 与当前DOT伤害的较大值。
- `OnHit`：**仅在击杀时触发**。如果被击杀目标携带DOT（`dotTimer > 0`），查找60px内最近的存活敌人，将剩余DOT传递给它（BOSS可能免疫传播：`Config.BOSS_BALANCE.dotSpreadImmune`）。

---

### 破甲骑士 armor_breaker

| 属性 | 值 |
|------|-----|
| 阵营 | 人类 |
| 攻击类型 | 单体 |
| 基础射程 | 90px |
| 基础攻速 | 1.1s |
| 特殊 | armor_break（基础破甲8%，持续5秒） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 精准打击 (precise_strike) | 被动 | 护甲削减提升至20% |
| 2 | 破甲叠加 (armor_stack) | 被动 | 最多叠加3层 |
| 3 | 致命弱点 (fatal_weakness) | 被动 | 满层目标额外受到35%伤害 |

**实现逻辑**（armor_breaker.lua）：
- `OnHit`：每次命中给目标 +1 `armorBreakStacks`（上限 `maxStacks`=3），设置 `armorBreakValue`（0.20）和 `armorBreakTimer`（5秒）。
- `ModifyDamage`：如果目标破甲层数已达满层（3），且拥有 fatal_weakness 技能，伤害×`(1 + fullStackBonus(0.35))`。

---

### 冰霜女巫 frost_witch

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | 链式（3链，衰减0.7） |
| 基础射程 | 120px |
| 基础攻速 | 1.0s |
| 特殊 | slow（基础减速25%） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 极寒之触 (extreme_cold) | 被动 | 减速提升至35% |
| 2 | 冰冻概率 (freeze_chance) | 被动 | 20%概率冰冻1.5秒；BOSS免疫改减速50% |
| 3 | 暴风雪 (blizzard) | **主动** | 每20秒全屏减速50%持续3秒 |

**实现逻辑**（frost_witch.lua）：
- `ModifySlowRate`：返回 `newSlowRate`（0.35）。
- `OnHit`：以 `chance`（0.20）概率触发冰冻。非BOSS：减速100%（完全停止）+施加 "frozen" debuff。BOSS：免疫冰冻，改为减速 `bossFallbackSlow(0.50) × BOSS减速效率(0.50)` = 25%。冰冻时显示浮字"冰冻"。
- `TriggerActive`（blizzard）：对全场存活敌人施加减速 `slowPct`（0.50），持续3秒。BOSS减速效率减半。

---

### 战鼓祭司 war_drummer

| 属性 | 值 |
|------|-----|
| 阵营 | 人类 |
| 攻击类型 | 单体 |
| 基础射程 | 100px |
| 基础攻速 | 1.2s |
| 特殊 | support（光环：80px范围，基础攻击加成10%） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 鼓舞士气 (morale_boost) | 被动 | 光环攻击加成提升至25% |
| 2 | 战吼节奏 (war_rhythm) | 被动 | 光环额外+15%攻速 |
| 3 | 英勇战歌 (heroic_anthem) | **主动** | 每30秒全体塔攻击+40%持续5秒 |

**实现逻辑**（war_drummer.lua）：
- `UpdateAura`：遍历所有塔，80px范围内的友军获得 `auraAtkBuff += atkBuff(0.25)` 和 `auraSpdBuff += spdBuff(0.15)`。
- `TriggerActive`（heroic_anthem）：设置全局 `State.heroicAnthemBuff`，所有塔攻击力×`(1 + atkBuffPct(0.40))`，持续5秒。

---

## SSR 级

> 功率参考：2-3被动 + 1主动。总收益约为SR级1.5倍

### 暗影法师 shadow_mage

| 属性 | 值 |
|------|-----|
| 阵营 | 亡灵 |
| 攻击类型 | 单体 |
| 基础射程 | 120px |
| 基础攻速 | 1.0s |
| 特殊 | high_damage |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 暗影穿透 (shadow_pierce) | 被动 | 攻击35%概率无视护盾（上限75%） |
| 2 | 灵魂收割 (soul_reap) | 被动 | 击杀后下次攻击+50%，叠3层，攻击后清零 |
| 3 | 虚空风暴 (void_storm) | **主动** | 每15秒全屏80%攻击力伤害 |

**实现逻辑**（shadow_mage.lua）：
- `ModifyDamage`：
  - 暗影穿透：如果目标有护盾且roll < `chance`（0.35），标记 `target.piercedThisHit = true`，Combat 跳过护盾。
  - 灵魂收割：如果塔有 `soulReapStacks > 0`，伤害×`(1 + stacks × killDmgBonus(0.50))`，然后清零叠层。最多3层=+150%伤害。
- `OnHit`：击杀时叠1层灵魂收割，上限 `maxStacks`（3）。
- `TriggerActive`（void_storm）：对全场非阶段免疫敌人造成 `tower.attack × damagePct(0.80)` 伤害，经过 CalcFinalDamage 计算。

---

### 深渊猎手 abyss_hunter

| 属性 | 值 |
|------|-----|
| 阵营 | 恶魔 |
| 攻击类型 | 单体 |
| 基础射程 | 130px |
| 基础攻速 | 0.9s |
| 特殊 | boss_killer |

> 注：Config_Core 中有 `bossExtraDmg = 0.30`，但该字段未被任何代码读取（残留配置）。实际BOSS额外伤害由技能 hunt_instinct 的 `bossExtraDmg = 0.50` 控制。

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 猎杀本能 (hunt_instinct) | 被动 | 对BOSS额外伤害提升至50% |
| 2 | 致命猎弩 (deadly_crossbow) | 被动 | 暴击率+30%，暴击伤害+80% |
| 3 | 深渊之箭 (abyss_arrow) | **主动** | 每12秒对最高血量敌人造成20%最大HP，BOSS上限ATK×12 |

**实现逻辑**（abyss_hunter.lua）：
- `ModifyDamage`：对BOSS目标，伤害×`(1 + bossExtraDmg(0.50))` = 1.5倍。
- `TriggerActive`（abyss_arrow）：找血量最高的敌人，造成 `enemy.hp × hpPct(0.20)` 伤害。如果是BOSS，伤害上限 `tower.attack × bossAtkCap(12)`。

---

### 瘟疫博士 plague_doctor

| 属性 | 值 |
|------|-----|
| 阵营 | 人类 |
| 攻击类型 | AOE |
| 基础射程 | 100px |
| 基础攻速 | 1.0s |
| 特殊 | DOT（基础DOT伤害12，持续4.0s） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 剧毒瘴气 (toxic_miasma) | 被动 | DOT期间敌人护甲抵抗-10% |
| 2 | 感染扩散 (infection_spread) | 被动 | DOT目标30px内最多2敌人感染70%DOT，不二次扩散 |
| 3 | 瘟疫爆发 (plague_burst) | **主动** | 每18秒引爆全部DOT，造成剩余DOT 500%即时伤害 |

**实现逻辑**（plague_doctor.lua）：
- `ModifyDamage`：如果目标正在受DOT（`dotTimer > 0`），标记 `target.armorReduceFromDot = armorReduce(0.10)`，Combat 计算时降低10%护甲。
- `OnHit`：如果目标存活且携带DOT且未被二次扩散（`!dotSpread`），查找30px内最多2个敌人，施加 `目标DOT伤害 × spreadRatio(0.70)` 的DOT。标记 `dotSpread = true`。
- `TriggerActive`（plague_burst）：遍历全场携带DOT的敌人，造成 `dotDamage × dotTimer × burstMult(5.0)` 即时伤害，然后清除DOT。

---

### 暴风领主 storm_lord

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | AOE |
| 基础射程 | 110px |
| 基础攻速 | 1.3s |
| 特殊 | aoe_control（基础减速35%，眩晕8%概率，持续1秒） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 雷鸣一击 (thunder_strike) | 被动 | 眩晕概率提升至30% |
| 2 | 风暴之眼 (storm_eye) | 被动 | 攻击范围+30px |
| 3 | 天降雷霆 (divine_thunder) | **主动** | 每22秒全屏60%攻击力伤害并减速50%持续2秒 |

**实现逻辑**（storm_lord.lua）：
- `ModifyRange`：射程 += `rangeBonus`（30），最终射程=110+30=140px。
- `TriggerActive`（divine_thunder）：对全场非阶段免疫敌人造成 `tower.attack × damagePct(0.60)` 伤害，并施加 `slowPct`（0.50）减速持续2秒。BOSS减速效率减半。

---

## UR 级

> 功率参考：2-3被动 + 1主动。总收益约为SSR级1.4倍

### 堕天使长 fallen_archangel

| 属性 | 值 |
|------|-----|
| 阵营 | 人类 |
| 攻击类型 | AOE |
| 基础射程 | 130px |
| 基础攻速 | 1.0s |
| 特殊 | amp_damage（基础增伤15%，持续5秒） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 神罚之光 (divine_judgment_light) | 被动 | 标记增伤提升至35% |
| 2 | 天使审判 (angel_judgment) | **主动** | 每15秒全屏120%攻击力伤害 |
| 3 | 堕落荣光 (fallen_glory) | 被动 | 光环：100px内友方暴击率+25% |

**实现逻辑**（fallen_archangel.lua）：
- `UpdateAura`：遍历100px内友军，`auraCritRateBuff += critRateBuff(0.25)`。
- `TriggerActive`（angel_judgment）：对全场非阶段免疫敌人造成 `tower.attack × damagePct(1.20)` 伤害。

---

### 虚空龙王 void_dragon

| 属性 | 值 |
|------|-----|
| 阵营 | 恶魔 |
| 攻击类型 | 链式（3链，衰减0.65） |
| 基础射程 | 120px |
| 基础攻速 | 0.8s |
| 特殊 | boss_killer |

> 注：Config_Core 中有 `bossExtraDmg = 0.25`，但该字段未被任何代码读取（残留配置）。实际由技能 void_tear 的 `bossExtraDmg = 0.50` 控制。

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 龙息灼烧 (dragon_breath_dot) | 被动 | 链式攻击附带ATK×25%/秒DOT，持续3秒 |
| 2 | 虚空撕裂 (void_tear) | 被动 | 对BOSS额外伤害提升至50% |
| 3 | 龙王之怒 (dragon_wrath) | **主动** | 每12秒全屏150%攻击力伤害并减速30%持续3秒 |

**实现逻辑**（void_dragon.lua）：
- `ModifyDamage`：对BOSS目标，伤害×`(1 + bossExtraDmg(0.50))`。
- `OnHit`：对存活目标施加DOT，伤害 = `tower.attack × dotAtkPct(0.25)` 每秒，持续3秒。**链式攻击的每个目标都会触发OnHit**，因此3个链式目标都会被上DOT。
- `TriggerActive`（dragon_wrath）：对全场非阶段免疫敌人造成 `tower.attack × damagePct(1.50)` 伤害，并施加 `slowPct`（0.30）减速持续3秒。BOSS减速效率减半。

**链式攻击机制**（Combat.lua HandleChainAttack）：
- 使用 `hitSet` 字典防止同一目标被链式攻击命中两次。
- 链式伤害衰减：每链伤害 = 上一链 × `chainDecay`（0.65）。
- 每个链式目标都会触发 `HeroSkills.OnHit`。

---

### 翎嫣 nature_elf

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | support（不主动攻击） |
| 基础射程 | 140px |
| 基础攻速 | 3.0s（脉冲间隔） |
| 特殊 | nature_aura |
| 光环范围 | 120px |

> **自管缩放**：nature_elf 的技能标记 `starScale = true`，跳过通用 NUMERIC_KEYS 缩放，在实现代码中自行调用 `StarScaleFactor()` 处理数值缩放。

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 自然馈赠 (nature_gift) | 被动 | 每3秒为范围内英雄注入3点自然之力（持续8秒），渐近线加成：攻击+60%、攻速+40%，额外获得翎嫣ATK×10%固定攻击加成 |
| 2 | 翠意庇护 (verdant_ward) | 被动 | 自然之力≥20时触发翠意状态，持续5秒免疫沉默/禁锢，内置20秒冷却 |
| 3 | 绿野之呼 (wilds_call) | **主动** | 每20秒全体英雄+30点自然之力，并赠送鲜花环（+40%攻击力，持续10秒） |

**实现逻辑**（nature_elf.lua）：
- **渐近线公式**：`factor = natForce / (natForce + halfSat)`，其中 `halfSat = 20`。当自然之力=20时达50%上限效果，40时达67%。
- `UpdateFrame`（每帧调用）：
  1. **第一遍**：翎嫣每3秒对120px范围内友军发放3点自然之力。主动技能每20秒触发，给全场英雄 `activeForce(30) × starScale` 点自然之力，并给ATK最高且无花环的英雄赠送鲜花环。
  2. **第二遍**：自然之力衰减计时。根据渐近线公式计算 buff：`auraAtkBuff += maxAtkPct(0.60) × factor`，`auraSpdBuff += maxSpdPct(0.40) × factor`，`natureFlatAtk = elfAtk × atkRatio(0.10) × factor`。翠意庇护：当自然之力≥20且未在冷却中，激活翠意（免疫沉默/束缚5秒）。
- 所有百分比参数随星级缩放：`maxAtkPct × starScale`，`maxSpdPct × starScale` 等。

---

### 绯夜 crimson_night

| 属性 | 值 |
|------|-----|
| 阵营 | 亡灵 |
| 攻击类型 | 单体 |
| 基础射程 | 110px |
| 基础攻速 | 0.9s |
| 特殊 | high_damage |

> **自管缩放**：crimson_night 的技能标记 `starScale = true`，跳过通用缩放。

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 暗影之针 (shadow_needle) | 被动 | 普攻叠加暗影印记(最多5层，持续4秒)；满5层触发穿刺爆发，造成ATK×200%暗影伤害，无视20%护甲 |
| 2 | 绯瞳锁定 (blood_eye) | 被动 | 攻击获得绯瞳，每层+3%暴击率(最多+30%)，暴击伤害+50%；4秒未攻击则绯瞳逐层消失 |
| 3 | 深渊一刺 (abyss_strike) | **主动** | CD 14秒。对当前目标造成ATK×800%暗影伤害，必定暴击；每层绯瞳额外+100%ATK伤害；击杀时保留一半绯瞳层数 |

**实现逻辑**（crimson_night.lua）：
- `OnHit`：
  - 暗影之针：每次命中+1印记（上限5层），刷新4秒持续时间。满5层时触发穿刺爆发：计算 `GetEffectiveAttack(tower) × burstAtkPct(2.0)` 伤害，设置 `armorReduceFromDot = armorIgnore(0.20)` 穿甲，经 CalcFinalDamage 计算后造成伤害。爆发后清零印记。
  - 绯瞳锁定：每次攻击+1绯瞳（上限10层），刷新4秒衰减计时器。更新 `tower.bonusCritRate = stacks × critRatePerHit(0.03)`，`tower.bonusCritDmg = critDmgBonus(0.50)`。
- `TriggerActive`（abyss_strike）：对当前目标造成 `atk × baseAtkPct(8.0)` 基础伤害 + `atk × stackBonusPct(1.0) × 绯瞳层数` 绯瞳加成伤害。临时拉高暴击率保证必定暴击。释放后保留一半绯瞳层数（向下取整）。
- `UpdateFrame`（每帧调用）：
  - 暗影印记逐层衰减（每1.5秒减1层）。
  - 绯瞳逐层衰减（每1秒减1层），同步更新暴击率/暴击伤害。

**满绯瞳深渊一刺伤害**（10层绯瞳）：`ATK × (8.0 + 1.0 × 10) = ATK × 18`，必定暴击。

---

### 凛冬君王 glacial_sovereign

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | AOE |
| 基础射程 | 110px |
| 基础攻速 | 1.0s |
| 特殊 | chill（寒意机制） |
| 限定 | 是（限定池专属） |

**寒意机制参数**（Config_Core）：
- 每秒施加1层寒意
- 每层减速10%，最多5层
- 寒意持续5秒
- 满5层增伤50%

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 凌冽寒意 (piercing_chill) | 被动 | 每秒对范围内敌人施加1层寒意，每层减速10%，最多5层，持续5秒；满5层受伤+50% |
| 2 | 霜寒之击 (frost_strike) | 被动 | 普通攻击附带1层寒意 |
| 3 | 冰川爆发 (glacial_eruption) | 被动 | 每累积100层全局寒意，对全屏敌人施加5层寒意 |

**实现逻辑**（glacial_sovereign.lua）：
- `OnHit`：普通攻击命中存活目标时，调用 `Enemy.ApplyChill(target, 1, 5.0, tower.id)` 施加1层寒意，累加 `chillGlobalCounter`。
- `UpdateFrame`（每帧调用）：
  - 凌冽寒意：每秒（`chillTickTimer`）对攻击范围内的存活敌人施加 `chillPerSec`（1）层寒意，累加全局计数器。
  - 冰川爆发：当 `chillGlobalCounter >= chillGlobalThreshold(100)` 时触发，对全场敌人施加 `chillApplyAll`（5）层寒意。可连续触发（while循环）。

---

## LR 级

> 功率参考：3-4被动 + 1主动。总收益约为UR级1.3倍。顶级定位

### 命运织者 fate_weaver

| 属性 | 值 |
|------|-----|
| 阵营 | 元素 |
| 攻击类型 | AOE |
| 基础射程 | 140px |
| 基础攻速 | 1.0s |
| 特殊 | support（光环：全场范围，攻击12%，攻速10%） |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 命运之线 (fate_thread) | 被动 | 光环降低敌人受治愈效果50% |
| 2 | 因果律 (causality) | 被动 | 全体友方塔25%概率双倍伤害 |
| 3 | 命运终章 (fate_finale) | 被动 | 友方致命一击时，溅射80%伤害给周围敌人 |
| 4 | 时间编织 (time_weave) | **主动** | 每25秒重置全体友方塔技能CD |

**实现逻辑**（fate_weaver.lua）：
- `UpdateAura`：
  - 命运之线：设置 `State.healReduction = max(当前值, 0.50)`，全局降低敌人治愈效果。
  - 因果律：设置 `State.causalityActive = true`，`State.causalityChance = max(当前值, 0.25)`。Combat 中每次计算伤害时以25%概率翻倍。
- `TriggerActive`（time_weave）：遍历所有塔的 `skillTimers`，将所有主动技能CD归零（排除 time_weave 自身）。

---

### 永恒魔君 eternal_archfiend

| 属性 | 值 |
|------|-----|
| 阵营 | 恶魔 |
| 攻击类型 | 单体 |
| 基础射程 | 120px |
| 基础攻速 | 0.7s（快攻） |
| 特殊 | high_damage |

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 魔君一击 (archfiend_strike) | 被动 | 暴击率+40%，暴击伤害+150% |
| 2 | 永恒之力 (eternal_power) | 被动 | 击杀+3%攻击，最多+60%，每波重置 |
| 3 | 终焉审判 (final_judgment) | 被动 | HP<15%处决；BOSS免疫，改为ATK×15固定伤害 |
| 4 | 灭世之炎 (worldfire) | **主动** | 每10秒对最高血量敌人造成当前HP 25%，BOSS上限ATK×15 |

**实现逻辑**（eternal_archfiend.lua）：
- `ModifyDamage`：如果有 `killAtkStacks > 0`（永恒之力叠层），伤害×`(1 + stacks × killAtkBonus(0.03))`。
- `OnHit`：
  - 永恒之力：击杀时叠1层，上限 `maxBonus(0.60) / killAtkBonus(0.03)` = 20层。每波重置。
  - 终焉审判：如果目标血量比 < `executeThreshold`（0.15），非BOSS直接击杀（造成 hp+1 伤害）；BOSS免疫处决，改为造成 `tower.attack × bossFixedAtkMult(15)` 固定伤害。
- `TriggerActive`（worldfire）：找血量最高的敌人，造成 `enemy.hp × hpPct(0.25)` 伤害，BOSS上限 `tower.attack × bossAtkCap(15)`。

---

## 主角

### 暗影领主 leader

| 属性 | 值 |
|------|-----|
| 攻击类型 | 由配置决定 |
| 特殊 | 全局辅助 |

> 主角按SSR级功率设计

**技能：**

| # | 技能名 | 类型 | 描述（30星满值） |
|---|--------|------|-----------------|
| 1 | 暗影支配 (shadow_dominion) | 被动 | 全体友方塔攻击+15% |
| 2 | 君主意志 (lord_will) | 被动 | 击杀时15%概率重置主动技能1秒CD |
| 3 | 暗影吞噬 (shadow_devour) | **主动** | 每10秒全屏80%攻击力伤害 |

**实现逻辑**（leader.lua）：
- `UpdateAura`：全体友军 `auraAtkBuff += globalAtkBuff(0.15)`。无范围限制。
- `OnHit`：击杀时以 `chance`（0.15）概率，将所有主动技能CD减少 `cdResetAmount`（1秒）。
- `TriggerActive`（shadow_devour）：对全场非阶段免疫敌人造成 `tower.attack × damagePct(0.80)` 伤害。

---

## 附录

### 阵营体系

| 阵营 | 英雄 |
|------|------|
| 亡灵 | 骷髅小兵、骷髅弓手、幽魂刺客、死灵术士、暗影法师、绯夜 |
| 恶魔 | 蝙蝠仆从、地狱犬、恶魔战士、深渊猎手、虚空龙王、永恒魔君 |
| 元素 | 石像兵、炼狱火焰、冰霜女巫、暴风领主、翎嫣、凛冬君王、命运织者 |
| 人类 | 破甲骑士、战鼓祭司、堕天使长、瘟疫博士 |

### 羁绊效果

| 同阵营数量 | 效果 |
|-----------|------|
| 2 | 攻击+8% |
| 3 | 攻击+15%，攻速+8% |
| 4 | 攻击+25%，攻速+15%，额外触发阵营专属效果 |

**4阵营专属效果**：
- 亡灵诅咒：敌人死亡时AOE 5%HP伤害
- 恶魔狂热：击杀+2%攻速，最多叠15层
- 元素共鸣：控制效果持续时间×1.4
- 人类联盟：射程+20，暴击率+8%

### 跨阵营羁绊

| 羁绊 | 需求 | 效果 |
|------|------|------|
| 死亡军团 | 亡灵×2 + 恶魔×2 | 暴击率+10% |
| 自然之力 | 元素×2 + 人类×2 | 攻击+12%，减速+15% |
| 暗影议会 | 暗影×1 + 亡灵×2 + 恶魔×1 | 主角攻击+20%，CD-3秒 |
| 五族共存 | 4个不同阵营 | 攻击+10%，攻速+10%，射程+10 |
