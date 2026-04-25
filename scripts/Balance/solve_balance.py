#!/usr/bin/env python3
"""
精确复刻 Lua 计算链，求解 DEF_SCALE_SEGMENTS 和 HP_SCALE_SEGMENTS
使得：
  1. DEF 贡献 ~20% (对 midGameBaseline hero)
  2. Kill time 严格单调递增（对 heroParamsAtStage hero）
"""
import math

# ============================================================
# 常量 (from Config_Heroes.lua)
# ============================================================
BASE_ATK = 3600          # shadow_mage
RARITY = "SSR"
GROWTH_PCT = {"N":0.06, "R":0.08, "SR":0.10, "SSR":0.12, "UR":0.15, "LR":0.18}

STAR_NORMAL_MULT = 1.10
STAR_CROWN_MULT = 1.15
TIER_ADVANCE_MULT = 1.40
STAR_CROWN_START = 21
STAR_TIERS = [
    (1, 5), (6, 10), (11, 15), (16, 20), (21, 25), (26, 30)
]

ADVANCE_GATES_BONUS = [0.10] * 20  # all 20 gates have bonus=0.10

STAR_MULTIPLIER = {1:1.0, 2:2.0, 3:4.5, 4:10.0, 5:22.0}

STAR_SPEED_MULT = {1:1.0, 2:1.15, 3:1.30, 4:1.50, 5:1.75}

BASE_SPEED = 1.0  # shadow_mage baseSpeed

SPD_BONUS_CURVE = [(1, 0.0), (3, 0.10), (10, 0.20), (50, 0.27), (200, 0.30)]
SPD_BONUS_MAX = 0.30

BASE_CRIT_MULT = 1.50

# Monster
MINION_BASE_HP = 4500
MINION_BASE_DEF = 500

# ENEMY_SCALING.armorPenResist
ARMOR_PEN_RESIST_SEGS = [
    (1, 500, 0.0, 0.0),
    (500, 2000, 0.0, 0.05),
    (2000, 4000, 0.05, 0.10),
    (4000, 6000, 0.10, 0.15),
]

# Soft caps
SOFT_CAPS = {
    "critDmg":  {"threshold": 1.00, "scale": 0.50},
    "dmgBonus": {"threshold": 0.60, "scale": 0.40},
    "elemDmg":  {"threshold": 0.50, "scale": 0.30},
}

# ENEMY_SCALING reduces
CRIT_DMG_REDUCE_SEGS = [
    (1, 500, 0.0, 0.0), (500, 1500, 0.0, 0.05),
    (1500, 3000, 0.05, 0.10), (3000, 5000, 0.10, 0.15), (5000, 6000, 0.15, 0.20),
]
DMG_BONUS_REDUCE_SEGS = [
    (1, 500, 0.0, 0.0), (500, 1500, 0.0, 0.05),
    (1500, 3000, 0.05, 0.08), (3000, 5000, 0.08, 0.12), (5000, 6000, 0.12, 0.15),
]
ELEM_DMG_REDUCE_SEGS = [
    (1, 500, 0.0, 0.0), (500, 1500, 0.0, 0.03),
    (1500, 3000, 0.03, 0.06), (3000, 5000, 0.06, 0.10), (5000, 6000, 0.10, 0.15),
]

# ============================================================
# Helper functions
# ============================================================

def piecewise(segments, x):
    """Piecewise linear: [(x0,y0), (x1,y1), ...]"""
    if not segments: return 0
    if len(segments) == 1: return segments[0][1]
    if x <= segments[0][0]: return segments[0][1]
    for i in range(1, len(segments)):
        if x <= segments[i][0]:
            x0, y0 = segments[i-1]
            x1, y1 = segments[i]
            t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return segments[-1][1]

def piecewise4(segments, x):
    """Piecewise4: [(fromStage, toStage, fromVal, toVal), ...]"""
    if not segments: return 1.0
    if x <= segments[0][0]: return segments[0][2]
    for seg in segments:
        if x <= seg[1]:
            t = (x - seg[0]) / (seg[1] - seg[0])
            return seg[2] + t * (seg[3] - seg[2])
    last = segments[-1]
    slope = (last[3] - last[2]) / (last[1] - last[0])
    return last[3] + slope * (x - last[1])

def soft_cap_stat(raw, cap_info):
    threshold = cap_info["threshold"]
    scale = cap_info["scale"]
    if raw <= threshold:
        return raw
    return threshold + (raw - threshold) * scale

def get_tier(star):
    for idx, (lo, hi) in enumerate(STAR_TIERS):
        if lo <= star <= hi:
            return idx + 1
    return 1

def calc_level_mult(level, rarity):
    g = GROWTH_PCT.get(rarity, 0.06)
    return 1.0 + g * max(0, level - 1)

def calc_advance_mult(adv_level):
    if adv_level <= 0: return 1.0
    n = min(adv_level, len(ADVANCE_GATES_BONUS))
    result = 1.0
    for i in range(n):
        result *= (1.0 + ADVANCE_GATES_BONUS[i])
    return result

def calc_star_mult(star):
    if star <= 0: return 1.0
    mult = 1.0
    prev_tier = 0
    for s in range(1, star + 1):
        cur_tier = get_tier(s)
        if cur_tier > prev_tier and prev_tier > 0:
            mult *= TIER_ADVANCE_MULT
        if s >= STAR_CROWN_START:
            mult *= STAR_CROWN_MULT
        else:
            mult *= STAR_NORMAL_MULT
        prev_tier = cur_tier
    return mult

# ============================================================
# Hero profile builders
# ============================================================

def midgame_baseline():
    return {
        "level": 1000, "star": 10, "advanceLevel": 5, "battleStar": 3,
        "equipAtk": 0, "atkPctBonus": 0.20, "relicAtkPct": 0.10,
        "relicSpdPct": 0.05, "relicCritDmgPct": 0.10,
        "equipArmorPen": 0.10, "equipCritRate": 0.10,
        "equipCritDmg": 0.20, "equipDmgBonus": 0.10,
        "elemDmg": 0.10, "elemMastery": 0.0,
        "spdPctBonus": 0, "divineAtkPct": 0, "divineSpdPct": 0,
    }

def hero_params_at_stage(stage):
    progress = min(1.0, (stage - 1) / 5999)
    return {
        "level": int(1 + progress * 5999),
        "star": int(progress * 30),
        "advanceLevel": int(progress * 20),
        "battleStar": min(5, 1 + int(progress * 5)),
        "equipAtk": 0,
        "atkPctBonus": progress * 0.30 + progress * 0.40,
        "relicAtkPct": progress * 0.20,
        "relicSpdPct": progress * 0.10,
        "relicCritDmgPct": progress * 0.30,
        "equipArmorPen": min(0.80, progress * 0.60),
        "equipCritRate": min(0.50, progress * 0.50),
        "equipCritDmg": progress * 1.50,
        "equipDmgBonus": progress * 0.40,
        "elemDmg": progress * 0.30,
        "elemMastery": progress * 0.10,
        "spdPctBonus": 0, "divineAtkPct": 0, "divineSpdPct": 0,
    }

# ============================================================
# Build hero profile → finalAtk, DPS, combat stats
# ============================================================

def build_hero(p, rarity=RARITY):
    level_mult = calc_level_mult(p["level"], rarity)
    adv_mult = calc_advance_mult(p["advanceLevel"])
    star_mult = calc_star_mult(p["star"])
    total_mult = level_mult * adv_mult * star_mult

    raw_atk = int(BASE_ATK * level_mult)
    hero_atk = int(raw_atk * adv_mult * star_mult)

    battle_star_mult = STAR_MULTIPLIER.get(p["battleStar"], 1.0)
    final_atk = int((hero_atk * battle_star_mult + p["equipAtk"])
                     * (1 + p["atkPctBonus"] + p.get("divineAtkPct", 0))
                     * (1 + p["relicAtkPct"]))

    # Attack interval
    spd_bonus = min(piecewise(SPD_BONUS_CURVE, total_mult), SPD_BONUS_MAX)
    star_speed_mult = STAR_SPEED_MULT.get(p["battleStar"], 1.0)
    attack_interval = BASE_SPEED / star_speed_mult / (1 + spd_bonus + p.get("spdPctBonus", 0) + p["relicSpdPct"] + p.get("divineSpdPct", 0))

    raw_dps = final_atk / attack_interval

    # Sub-stats
    armor_pen = min(1.0, p["equipArmorPen"])
    crit_rate = p["equipCritRate"]
    crit_dmg = p["equipCritDmg"] + p["relicCritDmgPct"]
    dmg_bonus = p["equipDmgBonus"]
    elem_dmg = p["elemDmg"]
    elem_mastery = p["elemMastery"]

    return {
        "finalAtk": final_atk,
        "attackInterval": attack_interval,
        "rawDPS": raw_dps,
        "armorPen": armor_pen,
        "critRate": crit_rate,
        "critDmg": crit_dmg,
        "dmgBonus": dmg_bonus,
        "elemDmg": elem_dmg,
        "elemMastery": elem_mastery,
        "totalMult": total_mult,
        "starMult": star_mult,
        "battleStarMult": battle_star_mult,
        "level": p["level"],
        "star": p["star"],
    }

# ============================================================
# Effective DPS (with monster reducing)
# ============================================================

def calc_effective_dps(hero, stage):
    armor_pen_resist = piecewise4(ARMOR_PEN_RESIST_SEGS, stage)
    crit_dmg_reduce = piecewise4(CRIT_DMG_REDUCE_SEGS, stage)
    dmg_bonus_reduce = piecewise4(DMG_BONUS_REDUCE_SEGS, stage)
    elem_dmg_reduce = piecewise4(ELEM_DMG_REDUCE_SEGS, stage)

    # Effective armor pen after resist
    eff_pen = min(1.0, max(0, hero["armorPen"])) * (1 - armor_pen_resist)

    # Crit multiplier
    soft_crit_dmg = soft_cap_stat(hero["critDmg"], SOFT_CAPS["critDmg"])
    eff_crit_dmg = max(0, soft_crit_dmg - crit_dmg_reduce)
    crit_exp_mult = 1 + hero["critRate"] * (BASE_CRIT_MULT - 1 + eff_crit_dmg)

    # DmgBonus multiplier
    soft_dmg_bonus = soft_cap_stat(hero["dmgBonus"], SOFT_CAPS["dmgBonus"])
    eff_dmg_bonus = max(0, soft_dmg_bonus - dmg_bonus_reduce)
    dmg_bonus_mult = 1 + eff_dmg_bonus

    # ElemDmg multiplier (shadow element, undead theme at wave 1)
    # shadow on undead = +0.20 resist → elemResist=0.20
    elem_resist = 0.20  # shadow_mage (shadow) vs undead theme
    elem_resist_factor = 1 - elem_resist

    soft_elem_dmg = soft_cap_stat(hero["elemDmg"], SOFT_CAPS["elemDmg"])
    eff_elem_dmg = max(0, soft_elem_dmg + hero["elemMastery"] - elem_dmg_reduce)
    elem_dmg_mult = 1 + eff_elem_dmg

    total_dmg_mult = crit_exp_mult * elem_resist_factor * dmg_bonus_mult * elem_dmg_mult

    eff_dps = hero["rawDPS"] * total_dmg_mult

    return {
        "effDPS": eff_dps,
        "totalDmgMult": total_dmg_mult,
        "effPen": eff_pen,
        "armorPenResist": armor_pen_resist,
    }

# ============================================================
# Monster EHP
# ============================================================

def calc_monster_ehp(stage, hero_final_atk, eff_pen, total_dmg_mult, 
                     def_scale=None, hp_scale=None):
    """Compute monster EHP for a single minion at wave 1."""
    round_num = (stage - 1) // 25 + 1
    round_hp_mult = 1.0 + (round_num - 1) * 0.5
    wave_scale = 1.0  # wave 1

    raw_hp = MINION_BASE_HP * hp_scale * wave_scale * round_hp_mult
    raw_def = int(MINION_BASE_DEF * def_scale)

    eff_def = max(0, raw_def * (1 - eff_pen))
    def_factor = 1 + eff_def / hero_final_atk

    ehp = raw_hp * def_factor / total_dmg_mult

    def_contrib = (def_factor - 1) / def_factor * 100

    return {
        "rawHP": raw_hp,
        "rawDEF": raw_def,
        "effDEF": eff_def,
        "defFactor": def_factor,
        "defContrib": def_contrib,
        "ehp": ehp,
        "roundHPMult": round_hp_mult,
    }

# ============================================================
# MAIN: Solve for DEF and HP scales
# ============================================================

SAMPLE_STAGES = [1, 100, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000]

# Step 1: Compute both profiles at all sample stages
print("=" * 100)
print("STEP 1: 两个 hero profile 对比 (shadow_mage, SSR)")
print("=" * 100)
print(f"{'Stage':>6} | {'--- heroParamsAtStage ---':^50} | {'--- midGameBaseline ---':^30}")
print(f"{'':>6} | {'Lv':>5} {'★':>3} {'Adv':>4} {'B★':>3} {'finalAtk':>14} {'rawDPS':>14} | {'finalAtk':>14} {'rawDPS':>14}")
print("-" * 100)

baseline_hero = build_hero(midgame_baseline())
baseline_dps_info = calc_effective_dps(baseline_hero, 1000)

for stage in SAMPLE_STAGES:
    hp = hero_params_at_stage(stage)
    h = build_hero(hp)
    dps = calc_effective_dps(h, stage)
    print(f"{stage:>6} | {hp['level']:>5} {hp['star']:>3} {hp['advanceLevel']:>4} {hp['battleStar']:>3} "
          f"{h['finalAtk']:>14,} {dps['effDPS']:>14,.0f} | "
          f"{baseline_hero['finalAtk']:>14,} {baseline_dps_info['effDPS']:>14,.0f}")

print()
print(f"midGameBaseline at stage 1000: finalAtk = {baseline_hero['finalAtk']:,}")
print()

# Step 2: Solve DEF_SCALE to give ~20% DEF contribution for midGameBaseline at stage 1000
# defFactor = 1 + effectiveDEF / heroDamage
# defContrib = (defFactor-1)/defFactor = 20% → defFactor = 1.25
# effectiveDEF = 0.25 * heroDamage
# effectiveDEF = rawDEF * (1 - effectivePen)
# rawDEF = baseDEF * defScale
# effectivePen = armorPen * (1 - armorPenResist)

# For midGameBaseline: armorPen=0.10, armorPenResist at stage 1000 = Piecewise4(...)
TARGET_DEF_CONTRIB = 0.20
TARGET_DEF_FACTOR = 1 / (1 - TARGET_DEF_CONTRIB)  # = 1.25

print("=" * 100)
print(f"STEP 2: 求解 DEF_SCALE (目标: midGameBaseline DEF贡献 = {TARGET_DEF_CONTRIB*100:.0f}%)")
print("=" * 100)

# Solve DEF scale for midGameBaseline at each sample stage
# For midGameBaseline, hero params are FIXED (level=1000, star=10, etc.)
# But at different stages, armorPenResist changes
# And heroDamage = finalAtk is constant (it's the same hero)
# We solve: what defScale makes DEF contribute TARGET_DEF_CONTRIB?
#
# defFactor = TARGET_DEF_FACTOR
# effectiveDEF = (TARGET_DEF_FACTOR - 1) * heroDamage
# rawDEF = effectiveDEF / (1 - effectivePen)
# defScale = rawDEF / baseDEF

print(f"\n注意: midGameBaseline hero finalAtk = {baseline_hero['finalAtk']:,}")
print(f"目标 defFactor = {TARGET_DEF_FACTOR:.4f}")
print()

# But wait — Report 5 only evaluates at stage 1000.
# For other stages, the DEF contribution will be different because armorPenResist changes.
# The real question: should we calibrate DEF to the BENCHMARK hero (midGameBaseline)?
# Or to the PROGRESSIVE hero (heroParamsAtStage)?
#
# Answer: calibrate to heroParamsAtStage (the actual difficulty curve), but
# verify that midGameBaseline at stage 1000 also gives reasonable DEF%.
#
# For heroParamsAtStage: solve DEF so that defContrib ≈ 20% at each stage

print("Strategy: 以 heroParamsAtStage 为基准校准 DEF 贡献 ~20%")
print("同时输出 midGameBaseline 在 stage 1000 的 DEF 贡献作为参考")
print()

ideal_def_scales = {}
print(f"{'Stage':>6} {'finalAtk':>14} {'armorPen':>10} {'penResist':>10} {'effPen':>10} "
      f"{'needed_DEF':>14} {'defScale':>12} {'verify_def%':>12}")
print("-" * 100)

for stage in SAMPLE_STAGES:
    hp = hero_params_at_stage(stage)
    h = build_hero(hp)
    dps = calc_effective_dps(h, stage)

    hero_dmg = h["finalAtk"]
    eff_pen = dps["effPen"]

    # Solve: defFactor = 1 + effectiveDEF / heroDmg = TARGET_DEF_FACTOR
    needed_eff_def = (TARGET_DEF_FACTOR - 1) * hero_dmg
    # effectiveDEF = rawDEF * (1 - effPen)
    # rawDEF = baseDEF * defScale
    needed_raw_def = needed_eff_def / (1 - eff_pen) if eff_pen < 1.0 else needed_eff_def
    needed_def_scale = needed_raw_def / MINION_BASE_DEF

    ideal_def_scales[stage] = needed_def_scale

    # Verify
    verify_eff_def = MINION_BASE_DEF * needed_def_scale * (1 - eff_pen)
    verify_def_factor = 1 + verify_eff_def / hero_dmg
    verify_def_pct = (verify_def_factor - 1) / verify_def_factor * 100

    print(f"{stage:>6} {hero_dmg:>14,} {h['armorPen']:>10.4f} {dps['armorPenResist']:>10.4f} "
          f"{eff_pen:>10.4f} {needed_eff_def:>14,.0f} {needed_def_scale:>12,.1f} {verify_def_pct:>11.1f}%")

# Check midGameBaseline at stage 1000 with the computed DEF scale
print()
print("--- midGameBaseline at stage 1000 验证 ---")
mgb_eff_pen = baseline_dps_info["effPen"]
mgb_def_scale = ideal_def_scales[1000]
mgb_raw_def = int(MINION_BASE_DEF * mgb_def_scale)
mgb_eff_def = mgb_raw_def * (1 - mgb_eff_pen)
mgb_def_factor = 1 + mgb_eff_def / baseline_hero["finalAtk"]
mgb_def_pct = (mgb_def_factor - 1) / mgb_def_factor * 100
print(f"  DEF scale at 1000 = {mgb_def_scale:,.1f}")
print(f"  rawDEF = {mgb_raw_def:,}, effDEF = {mgb_eff_def:,.0f}")
print(f"  baseline finalAtk = {baseline_hero['finalAtk']:,}")
print(f"  defFactor = {mgb_def_factor:.4f}, DEF% = {mgb_def_pct:.1f}%")
print()
print(f"  注: DEF% 在 midGameBaseline 下为 {mgb_def_pct:.1f}%，")
print(f"  因为 baseline hero 的 finalAtk({baseline_hero['finalAtk']:,}) >> heroParamsAtStage(1000) 的 finalAtk")
print(f"  这是 Diminishing DEF 公式的设计意图: 强力英雄自然碾压 DEF")

# Step 3: Solve HP_SCALE for monotonic kill time
# Kill time = EHP / effDPS
# We want kill time monotonically increasing
# Use target: killTime = 2 + 8 * sqrt(progress), from 2s to 10s
# But these are per-MONSTER kill times, not per-stage
# For Report 2, the EHP is per-stage (all 20 waves × multiple monsters)
# That's controlled by how many monsters are in each stage
#
# Actually, for the purpose of ensuring monotonicity, we just need:
# killTime(stage_i+1) > killTime(stage_i)
# killTime = EHP / effDPS = rawHP * defFactor / (totalDmgMult * effDPS_raw)
#
# where rawHP = baseHP * hpScale * roundHPMult
# defFactor is already solved above
# effDPS = rawDPS * totalDmgMult
# so killTime = rawHP * defFactor / (rawDPS * totalDmgMult)
# = baseHP * hpScale * roundHPMult * defFactor / (rawDPS * totalDmgMult)

print("=" * 100)
print("STEP 3: 求解 HP_SCALE 使 Kill Time 严格单调递增")
print("=" * 100)

# First compute DPS and defFactor at each sample stage with the ideal DEF scales
# Then solve for hpScale that gives desired kill time
# Target: killTime(stage) = base + slope * sqrt(progress)
# where progress = (stage-1)/5999

# But we need to be careful: the kill time should INCREASE at each step.
# Rather than targeting a specific formula, let's compute the DPS at each stage,
# then solve backwards: for each stage, what hpScale gives a kill time that's
# at least X% higher than the previous stage?

# First, compute raw kill-time factor without hpScale:
# killTime = (baseHP * hpScale * roundHPMult * defFactor) / (rawDPS * totalDmgMult)
# → hpScale = killTime * rawDPS * totalDmgMult / (baseHP * roundHPMult * defFactor)

# Let's target smooth kill time: 2 + 8*sqrt(progress)
# This gives 2s at stage 1, 10s at stage 6000

results = []
print()
print(f"{'Stage':>6} {'rawDPS':>14} {'effDPS':>14} {'defFactor':>10} {'roundHP':>8} "
      f"{'target_KT':>10} {'hpScale':>14} {'verify_KT':>10} {'DEF%':>8}")
print("-" * 120)

for stage in SAMPLE_STAGES:
    hp = hero_params_at_stage(stage)
    h = build_hero(hp)
    dps = calc_effective_dps(h, stage)

    def_scale = ideal_def_scales[stage]

    round_num = (stage - 1) // 25 + 1
    round_hp_mult = 1.0 + (round_num - 1) * 0.5

    # DEF factor with the ideal def_scale
    eff_pen = dps["effPen"]
    raw_def = MINION_BASE_DEF * def_scale
    eff_def = raw_def * (1 - eff_pen)
    def_factor = 1 + eff_def / h["finalAtk"]

    # Target kill time
    progress = min(1.0, (stage - 1) / 5999)
    target_kt = 2 + 8 * math.sqrt(progress)

    # Solve for hpScale
    # killTime = baseHP * hpScale * roundHPMult * defFactor / (rawDPS * totalDmgMult)
    # Note: rawDPS * totalDmgMult = effDPS
    eff_dps = dps["effDPS"]
    hp_scale = target_kt * eff_dps / (MINION_BASE_HP * round_hp_mult * def_factor)

    # Verify
    verify_hp = MINION_BASE_HP * hp_scale * round_hp_mult
    verify_ehp = verify_hp * def_factor / dps["totalDmgMult"]
    verify_kt = verify_ehp / h["rawDPS"]  # = rawHP * defFactor / (rawDPS * totalDmgMult) = target_kt ✓

    def_pct = (def_factor - 1) / def_factor * 100

    results.append({
        "stage": stage,
        "defScale": def_scale,
        "hpScale": hp_scale,
        "killTime": verify_kt,
        "defPct": def_pct,
        "effDPS": eff_dps,
        "rawDPS": h["rawDPS"],
        "defFactor": def_factor,
        "roundHPMult": round_hp_mult,
    })

    print(f"{stage:>6} {h['rawDPS']:>14,.0f} {eff_dps:>14,.0f} {def_factor:>10.4f} {round_hp_mult:>8.1f} "
          f"{target_kt:>10.2f} {hp_scale:>14,.1f} {verify_kt:>10.2f} {def_pct:>7.1f}%")

# Step 4: Check monotonicity
print()
print("--- 单调性检查 ---")
prev_kt = 0
all_mono = True
for r in results:
    if r["killTime"] <= prev_kt:
        print(f"  ❌ Stage {r['stage']}: KT={r['killTime']:.2f} <= prev {prev_kt:.2f}")
        all_mono = False
    prev_kt = r["killTime"]
if all_mono:
    print("  ✅ Kill time 严格单调递增")

# Step 5: Format as Lua segments
print()
print("=" * 100)
print("STEP 4: 生成 Lua 代码")
print("=" * 100)

# DEF_SCALE_SEGMENTS
print()
print("Config.DEF_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE_STAGES) - 1):
    s1 = SAMPLE_STAGES[i]
    s2 = SAMPLE_STAGES[i + 1]
    d1 = ideal_def_scales[s1]
    d2 = ideal_def_scales[s2]
    # Round to clean numbers
    d1_r = round(d1)
    d2_r = round(d2)
    if d1 < 10: d1_r = round(d1, 1)
    if d2 < 10: d2_r = round(d2, 1)
    print(f"    {{ {s1:>5}, {s2:>5}, {d1_r:>14}, {d2_r:>14} }},")
print("}")

# HP_SCALE_SEGMENTS
print()
print("Config.HP_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE_STAGES) - 1):
    s1 = SAMPLE_STAGES[i]
    s2 = SAMPLE_STAGES[i + 1]
    h1 = results[i]["hpScale"]
    h2 = results[i + 1]["hpScale"]
    h1_r = round(h1)
    h2_r = round(h2)
    if h1 < 10: h1_r = round(h1, 1)
    if h2 < 10: h2_r = round(h2, 1)
    print(f"    {{ {s1:>5}, {s2:>5}, {h1_r:>14}, {h2_r:>14} }},")
print("}")

# Step 6: Also show what happens when we verify with a denser grid
# to check for non-monotonic spots between sample points
print()
print("=" * 100)
print("STEP 5: 密集网格单调性检查 (每 100 关)")
print("=" * 100)

# Build interpolated DEF and HP scales from the solved segments
def_seg_data = []
hp_seg_data = []
for i in range(len(SAMPLE_STAGES) - 1):
    s1, s2 = SAMPLE_STAGES[i], SAMPLE_STAGES[i+1]
    def_seg_data.append((s1, s2, ideal_def_scales[s1], ideal_def_scales[s2]))
    hp_seg_data.append((s1, s2, results[i]["hpScale"], results[i+1]["hpScale"]))

dense_stages = list(range(1, 6001, 100))
if 6000 not in dense_stages:
    dense_stages.append(6000)

prev_kt = 0
violations = []
for stage in dense_stages:
    hp = hero_params_at_stage(stage)
    h = build_hero(hp)
    dps = calc_effective_dps(h, stage)

    def_scale = piecewise4(def_seg_data, stage)
    hp_scale = piecewise4(hp_seg_data, stage)

    round_num = (stage - 1) // 25 + 1
    round_hp_mult = 1.0 + (round_num - 1) * 0.5

    eff_pen = dps["effPen"]
    raw_def = MINION_BASE_DEF * def_scale
    eff_def = raw_def * (1 - eff_pen)
    def_factor = 1 + eff_def / h["finalAtk"]

    raw_hp = MINION_BASE_HP * hp_scale * round_hp_mult
    ehp = raw_hp * def_factor / dps["totalDmgMult"]
    kt = ehp / h["rawDPS"]

    if kt <= prev_kt and stage > 1:
        drop_pct = (prev_kt - kt) / prev_kt * 100
        violations.append((stage, kt, prev_kt, drop_pct))
    prev_kt = kt

if violations:
    print(f"  ⚠️ 发现 {len(violations)} 处非单调点:")
    for stage, kt, prev_kt, drop in violations:
        print(f"    Stage {stage}: KT={kt:.2f}s, prev={prev_kt:.2f}s (drop {drop:.1f}%)")
else:
    print("  ✅ 每 100 关一个采样点，Kill time 全部严格单调递增")
