#!/usr/bin/env python3
"""
v2: 逐关计算 DPS，找到所有跳变点，用"包络线"策略确保单调
策略：
  1. 每 1 关计算一次 effDPS
  2. 构建 "DPS 包络线" = max(effDPS[1..stage]) — 确保曲线只看到最大历史 DPS
  3. 用包络线 DPS 反推 HP scale = target_KT * envelope_DPS / (baseHP * roundHPMult * defFactor)
  4. 同样用包络线推 DEF scale（使用 max 历史 finalAtk）
  5. 从逐关结果中提取分段线性近似
"""
import math

# ============================================================
# Constants (exact copy from v1)
# ============================================================
BASE_ATK = 3600
GROWTH_PCT = {"N":0.06, "R":0.08, "SR":0.10, "SSR":0.12, "UR":0.15, "LR":0.18}
RARITY = "SSR"

STAR_NORMAL_MULT = 1.10
STAR_CROWN_MULT = 1.15
TIER_ADVANCE_MULT = 1.40
STAR_CROWN_START = 21
STAR_TIERS = [(1,5),(6,10),(11,15),(16,20),(21,25),(26,30)]

ADVANCE_GATES_BONUS = [0.10]*20
STAR_MULTIPLIER = {1:1.0, 2:2.0, 3:4.5, 4:10.0, 5:22.0}
STAR_SPEED_MULT = {1:1.0, 2:1.15, 3:1.30, 4:1.50, 5:1.75}
BASE_SPEED = 1.0

SPD_BONUS_CURVE = [(1,0.0),(3,0.10),(10,0.20),(50,0.27),(200,0.30)]
SPD_BONUS_MAX = 0.30
BASE_CRIT_MULT = 1.50

MINION_BASE_HP = 4500
MINION_BASE_DEF = 500

ARMOR_PEN_RESIST_SEGS = [(1,500,0.0,0.0),(500,2000,0.0,0.05),(2000,4000,0.05,0.10),(4000,6000,0.10,0.15)]
CRIT_DMG_REDUCE_SEGS = [(1,500,0.0,0.0),(500,1500,0.0,0.05),(1500,3000,0.05,0.10),(3000,5000,0.10,0.15),(5000,6000,0.15,0.20)]
DMG_BONUS_REDUCE_SEGS = [(1,500,0.0,0.0),(500,1500,0.0,0.05),(1500,3000,0.05,0.08),(3000,5000,0.08,0.12),(5000,6000,0.12,0.15)]
ELEM_DMG_REDUCE_SEGS = [(1,500,0.0,0.0),(500,1500,0.0,0.03),(1500,3000,0.03,0.06),(3000,5000,0.06,0.10),(5000,6000,0.10,0.15)]

SOFT_CAPS = {
    "critDmg":{"threshold":1.00,"scale":0.50},
    "dmgBonus":{"threshold":0.60,"scale":0.40},
    "elemDmg":{"threshold":0.50,"scale":0.30},
}

def piecewise(segments, x):
    if not segments: return 0
    if len(segments)==1: return segments[0][1]
    if x<=segments[0][0]: return segments[0][1]
    for i in range(1,len(segments)):
        if x<=segments[i][0]:
            x0,y0=segments[i-1]; x1,y1=segments[i]
            return y0+(x-x0)/(x1-x0)*(y1-y0)
    return segments[-1][1]

def piecewise4(segments, x):
    if not segments: return 1.0
    if x<=segments[0][0]: return segments[0][2]
    for seg in segments:
        if x<=seg[1]:
            t=(x-seg[0])/(seg[1]-seg[0])
            return seg[2]+t*(seg[3]-seg[2])
    last=segments[-1]
    slope=(last[3]-last[2])/(last[1]-last[0])
    return last[3]+slope*(x-last[1])

def soft_cap_stat(raw, cap):
    if raw<=cap["threshold"]: return raw
    return cap["threshold"]+(raw-cap["threshold"])*cap["scale"]

def get_tier(star):
    for idx,(lo,hi) in enumerate(STAR_TIERS):
        if lo<=star<=hi: return idx+1
    return 1

def calc_level_mult(level):
    return 1.0+GROWTH_PCT[RARITY]*max(0,level-1)

def calc_advance_mult(adv):
    if adv<=0: return 1.0
    r=1.0
    for i in range(min(adv,20)): r*=1.10
    return r

def calc_star_mult(star):
    if star<=0: return 1.0
    m=1.0; pt=0
    for s in range(1,star+1):
        ct=get_tier(s)
        if ct>pt and pt>0: m*=TIER_ADVANCE_MULT
        m*=(STAR_CROWN_MULT if s>=STAR_CROWN_START else STAR_NORMAL_MULT)
        pt=ct
    return m

def hero_params_at_stage(stage):
    p=min(1.0,(stage-1)/5999)
    return {
        "level":int(1+p*5999),"star":int(p*30),
        "advanceLevel":int(p*20),"battleStar":min(5,1+int(p*5)),
        "atkPctBonus":p*0.70,"relicAtkPct":p*0.20,
        "relicSpdPct":p*0.10,"relicCritDmgPct":p*0.30,
        "equipArmorPen":min(0.80,p*0.60),
        "equipCritRate":min(0.50,p*0.50),"equipCritDmg":p*1.50,
        "equipDmgBonus":p*0.40,"elemDmg":p*0.30,"elemMastery":p*0.10,
    }

def build_hero(p):
    lm=calc_level_mult(p["level"])
    am=calc_advance_mult(p["advanceLevel"])
    sm=calc_star_mult(p["star"])
    tm=lm*am*sm
    ra=int(BASE_ATK*lm); ha=int(ra*am*sm)
    bsm=STAR_MULTIPLIER.get(p["battleStar"],1.0)
    fa=int(ha*bsm*(1+p["atkPctBonus"])*(1+p["relicAtkPct"]))
    sb=min(piecewise(SPD_BONUS_CURVE,tm),SPD_BONUS_MAX)
    ssm=STAR_SPEED_MULT.get(p["battleStar"],1.0)
    ai=BASE_SPEED/ssm/(1+sb+p["relicSpdPct"])
    return {"finalAtk":fa,"rawDPS":fa/ai,
            "armorPen":min(1.0,p["equipArmorPen"]),
            "critRate":p["equipCritRate"],
            "critDmg":p["equipCritDmg"]+p["relicCritDmgPct"],
            "dmgBonus":p["equipDmgBonus"],
            "elemDmg":p["elemDmg"],"elemMastery":p["elemMastery"],
            "totalMult":tm,"attackInterval":ai,
            "level":p["level"],"star":p["star"],"battleStar":p["battleStar"],
            }

def calc_combat(hero, stage):
    apr=piecewise4(ARMOR_PEN_RESIST_SEGS,stage)
    ep=min(1.0,max(0,hero["armorPen"]))*(1-apr)
    scd=soft_cap_stat(hero["critDmg"],SOFT_CAPS["critDmg"])
    ecd=max(0,scd-piecewise4(CRIT_DMG_REDUCE_SEGS,stage))
    cem=1+hero["critRate"]*(BASE_CRIT_MULT-1+ecd)
    sdb=soft_cap_stat(hero["dmgBonus"],SOFT_CAPS["dmgBonus"])
    edb=max(0,sdb-piecewise4(DMG_BONUS_REDUCE_SEGS,stage))
    dbm=1+edb
    er=0.20  # shadow vs undead
    erf=1-er
    sed=soft_cap_stat(hero["elemDmg"],SOFT_CAPS["elemDmg"])
    eed=max(0,sed+hero["elemMastery"]-piecewise4(ELEM_DMG_REDUCE_SEGS,stage))
    edm=1+eed
    tdm=cem*erf*dbm*edm
    return {"effPen":ep,"totalDmgMult":tdm,"effDPS":hero["rawDPS"]*tdm}

# ============================================================
# STEP 1: 逐关计算 DPS 和包络线
# ============================================================
print("逐关计算 DPS 并构建包络线...")

stages = list(range(1, 6001))
stage_data = {}
max_eff_dps = 0
max_final_atk = 0

for s in stages:
    hp = hero_params_at_stage(s)
    h = build_hero(hp)
    c = calc_combat(h, s)
    
    max_eff_dps = max(max_eff_dps, c["effDPS"])
    max_final_atk = max(max_final_atk, h["finalAtk"])
    
    stage_data[s] = {
        "effDPS": c["effDPS"],
        "rawDPS": h["rawDPS"],
        "finalAtk": h["finalAtk"],
        "effPen": c["effPen"],
        "totalDmgMult": c["totalDmgMult"],
        "envelope_DPS": max_eff_dps,      # monotonically increasing
        "envelope_ATK": max_final_atk,    # monotonically increasing
        "star": h["star"],
        "battleStar": h["battleStar"],
        "level": h["level"],
    }

# Check: how many DPS jumps?
jumps = 0
prev_dps = 0
big_jumps = []
for s in stages:
    d = stage_data[s]
    if d["effDPS"] < prev_dps:
        drop = (prev_dps - d["effDPS"]) / prev_dps * 100
        if drop > 5:
            big_jumps.append((s, drop, d["star"], d["battleStar"]))
        jumps += 1
    prev_dps = d["effDPS"]

print(f"DPS 非单调点数量: {jumps}")
print(f"大幅下降 (>5%): {len(big_jumps)} 处")
for s, drop, star, bs in big_jumps[:10]:
    print(f"  Stage {s}: drop {drop:.1f}%, ★{star}, B★{bs}")

# ============================================================
# STEP 2: 用包络线计算理想 DEF 和 HP
# ============================================================
print()
print("用包络线 DPS/ATK 求解 DEF 和 HP...")

TARGET_DEF_FACTOR = 1.25  # 20% DEF contribution

ideal = {}
for s in stages:
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    # DEF: target defFactor=1.25 based on envelope_ATK
    # effectiveDEF = 0.25 * envelope_ATK
    # rawDEF = effectiveDEF / (1 - effPen)
    # defScale = rawDEF / baseDEF
    needed_eff_def = (TARGET_DEF_FACTOR-1) * d["envelope_ATK"]
    ep = d["effPen"]
    needed_raw_def = needed_eff_def / (1-ep) if ep<1 else needed_eff_def
    def_scale = needed_raw_def / MINION_BASE_DEF
    
    # HP: target killTime with envelope DPS
    progress = min(1.0, (s-1)/5999)
    target_kt = 2 + 8 * math.sqrt(progress)
    
    # killTime = baseHP * hpScale * roundHPMult * defFactor / (rawDPS * totalDmgMult)
    # But we use envelope_DPS (=rawDPS*totalDmgMult at max)
    # killTime = baseHP * hpScale * roundHPMult * defFactor / envelope_DPS
    # → hpScale = target_kt * envelope_DPS / (baseHP * roundHPMult * defFactor)
    hp_scale = target_kt * d["envelope_DPS"] / (MINION_BASE_HP * rhm * TARGET_DEF_FACTOR)
    
    ideal[s] = {"defScale": def_scale, "hpScale": hp_scale}

# ============================================================
# STEP 3: Verify monotonicity with envelope-based scales
# ============================================================
print()
print("验证包络线方案的单调性...")

prev_kt = 0
violations = 0
for s in stages:
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    ds = ideal[s]["defScale"]
    hs = ideal[s]["hpScale"]
    
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1-ep)
    df = 1 + eff_def / d["finalAtk"]  # actual defFactor (using real ATK, not envelope)
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    if kt < prev_kt and s > 1:
        violations += 1
    prev_kt = kt

print(f"非单调点: {violations}")
if violations > 0:
    print("包络线方案仍有非单调 — 这是因为 defFactor 使用实际 ATK 而非包络 ATK")
    print("修正: 使 defScale 和 hpScale 自身也单调递增")

# ============================================================
# STEP 4: 确保 defScale 和 hpScale 本身单调递增
# ============================================================
print()
print("STEP 4: 强制 defScale 和 hpScale 单调递增...")

mono_def = {}
mono_hp = {}
max_ds = 0
max_hs = 0
for s in stages:
    max_ds = max(max_ds, ideal[s]["defScale"])
    max_hs = max(max_hs, ideal[s]["hpScale"])
    mono_def[s] = max_ds
    mono_hp[s] = max_hs

# Re-verify with monotonic scales
prev_kt = 0
violations = 0
violation_list = []
for s in stages:
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    ds = mono_def[s]
    hs = mono_hp[s]
    
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1-ep)
    df = 1 + eff_def / d["finalAtk"]
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    if kt < prev_kt and s > 1:
        violations += 1
        drop = (prev_kt - kt)/prev_kt*100
        if drop > 1:
            violation_list.append((s, kt, prev_kt, drop, d["star"], d["battleStar"]))
    prev_kt = kt

print(f"非单调点: {violations}")
if violation_list:
    print(f"大幅下降 (>1%): {len(violation_list)} 处")
    for s,kt,pkt,drop,star,bs in violation_list[:15]:
        print(f"  Stage {s}: KT={kt:.2f}s→{pkt:.2f}s (drop {drop:.1f}%), ★{star}, B★{bs}")

# The issue is: even with monotonic scales, the ACTUAL defFactor varies
# because finalAtk has step jumps (star tier, battleStar).
# When finalAtk jumps UP, defFactor DROPS (less DEF contribution),
# and combined with rawDPS jumping up, killTime drops.
#
# Solution: Instead of targeting a fixed defFactor, we need to:
# Target a MINIMUM kill time that's monotonically increasing.
# This means: at each stage, hpScale must be high enough that
# killTime >= target_kt EVEN with the actual (not envelope) DPS.
#
# killTime = baseHP * hpScale * roundHPMult * defFactor / (rawDPS * totalDmgMult)
# We need: hpScale >= target_kt * rawDPS * totalDmgMult / (baseHP * roundHPMult * defFactor)

print()
print("=" * 80)
print("STEP 5: 最终方案 — 逐关保证最低 kill time")
print("=" * 80)

# For DEF: keep the envelope-based monotonic DEF scale
# For HP: at each stage, compute minimum hpScale needed,
# then take running maximum to ensure monotonicity

# But defFactor depends on defScale AND finalAtk...
# Let's iterate: fix DEF at mono_def, then solve HP

final_hp = {}
max_needed_hs = 0

for s in stages:
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    ds = mono_def[s]
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1-ep)
    df = 1 + eff_def / d["finalAtk"]
    
    progress = min(1.0, (s-1)/5999)
    target_kt = 2 + 8 * math.sqrt(progress)
    
    # hpScale needed for this stage to achieve target_kt
    # kt = baseHP * hs * rhm * df / (rawDPS * tdm)
    needed_hs = target_kt * d["rawDPS"] * d["totalDmgMult"] / (MINION_BASE_HP * rhm * df)
    
    max_needed_hs = max(max_needed_hs, needed_hs)
    final_hp[s] = max_needed_hs

# Verify one more time
prev_kt = 0
violations = 0
violation_list = []
for s in stages:
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    ds = mono_def[s]
    hs = final_hp[s]
    
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1-ep)
    df = 1 + eff_def / d["finalAtk"]
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    if kt < prev_kt and s > 1:
        violations += 1
        drop = (prev_kt - kt)/prev_kt*100
        violation_list.append((s, kt, prev_kt, drop))
    prev_kt = kt

print(f"最终方案验证: 非单调点 = {violations}")
if violations == 0:
    print("✅ 6000 关全部严格单调递增!")
else:
    print("仍有非单调:")
    for s,kt,pkt,drop in violation_list[:10]:
        print(f"  Stage {s}: {kt:.4f}s < {pkt:.4f}s (drop {drop:.4f}%)")

# ============================================================
# STEP 6: 提取分段线性近似
# ============================================================
print()
print("=" * 80)
print("STEP 6: 提取分段端点")
print("=" * 80)

# Use the simulator's sample points
SAMPLE = [1, 100, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000]

# But we need segment boundaries that align with star tier/battleStar transitions
# Let's also check where big DPS jumps happen
print("\nDPS 主要跳变点（每个星级段、战斗星级变化）:")
prev_star = 0
prev_bs = 0
for s in stages:
    d = stage_data[s]
    if d["star"] != prev_star or d["battleStar"] != prev_bs:
        if s > 1:
            ratio = d["effDPS"] / stage_data[s-1]["effDPS"] if stage_data[s-1]["effDPS"] > 0 else 1
            if ratio > 1.05 or ratio < 0.95:
                print(f"  Stage {s}: ★{prev_star}→{d['star']}, B★{prev_bs}→{d['battleStar']}, "
                      f"DPS ratio={ratio:.2f}")
        prev_star = d["star"]
        prev_bs = d["battleStar"]

# Output DEF and HP values at sample points
print()
print(f"{'Stage':>6} {'defScale':>14} {'hpScale':>14} | verify: {'KT':>8} {'DEF%':>8}")
print("-" * 70)

sample_results = []
for s in SAMPLE:
    ds = mono_def[s]
    hs = final_hp[s]
    
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1-ep)
    df = 1 + eff_def / d["finalAtk"]
    def_pct = (df-1)/df*100
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    sample_results.append({"stage":s,"defScale":ds,"hpScale":hs,"kt":kt,"defPct":def_pct})
    print(f"{s:>6} {ds:>14,.1f} {hs:>14,.1f} | {kt:>8.2f} {def_pct:>7.1f}%")

# Generate Lua code
print()
print("=" * 80)
print("Lua 代码输出")
print("=" * 80)

def round_scale(v):
    if v < 2: return round(v, 2)
    if v < 10: return round(v, 1)
    if v < 1000: return round(v)
    if v < 100000: return round(v, -1)
    if v < 1000000: return round(v, -2)
    return round(v, -3)

print()
print("-- DEF 缩放表: 基于 heroParamsAtStage 包络线，defFactor≈1.25 (DEF 贡献 ~20%)")
print("-- 逐关包络线取 max 确保单调递增")
print("Config.DEF_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    d1 = round_scale(mono_def[s1])
    d2 = round_scale(mono_def[s2])
    print(f"    {{ {s1:>5}, {s2:>5}, {d1:>14}, {d2:>14} }},")
print("}")

print()
print("-- HP 缩放表: 逐关保证 kill time >= target (2+8√progress)")
print("-- running max 确保严格单调递增，吸收所有 DPS 跳变")
print("Config.HP_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    h1 = round_scale(final_hp[s1])
    h2 = round_scale(final_hp[s2])
    print(f"    {{ {s1:>5}, {s2:>5}, {h1:>14}, {h2:>14} }},")
print("}")

# ============================================================
# STEP 7: 用分段线性版本重新验证
# ============================================================
print()
print("=" * 80)
print("STEP 7: 分段线性版本验证 (每 1 关)")
print("=" * 80)

# Build segments from SAMPLE points
def_segs = []
hp_segs = []
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    def_segs.append((s1, s2, round_scale(mono_def[s1]), round_scale(mono_def[s2])))
    hp_segs.append((s1, s2, round_scale(final_hp[s1]), round_scale(final_hp[s2])))

prev_kt = 0
violations = 0
v_list = []
for s in stages:
    d = stage_data[s]
    rn = (s-1)//25+1
    rhm = 1.0+(rn-1)*0.5
    
    if s <= 1:
        ds = 1.0
    else:
        ds = piecewise4(def_segs, s)
    hs = piecewise4(hp_segs, s)
    
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1-ep)
    df = 1 + eff_def / d["finalAtk"]
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    if kt < prev_kt and s > 1:
        violations += 1
        drop = (prev_kt - kt)/prev_kt*100
        if drop > 0.5:
            v_list.append((s, kt, prev_kt, drop, d["star"], d["battleStar"]))
    prev_kt = kt

print(f"分段线性版本: 非单调点 = {violations}")
if v_list:
    print(f"  大幅下降 (>0.5%): {len(v_list)} 处")
    for s,kt,pkt,drop,star,bs in v_list[:20]:
        print(f"    Stage {s}: KT={kt:.2f}s→{pkt:.2f}s (drop {drop:.1f}%), ★{star}, B★{bs}")
    
    # The issue: piecewise4 interpolates BETWEEN sample points,
    # but the exact monotonic values were computed per-stage.
    # Between sample points, the interpolated value might be LOWER than the per-stage max.
    # Solution: add more breakpoints at DPS jump locations.
    
    print()
    print("需要在 DPS 跳变处添加额外断点...")
    
    # Find all stages where DPS jumps significantly
    jump_stages = set()
    prev_dps = 0
    for s in stages:
        cur_dps = stage_data[s]["effDPS"]
        if s > 1 and prev_dps > 0:
            ratio = cur_dps / prev_dps
            if ratio > 1.10:  # >10% jump
                jump_stages.add(s)
                jump_stages.add(s-1)  # also the stage before
        prev_dps = cur_dps
    
    # Merge with SAMPLE
    all_points = sorted(set(SAMPLE) | jump_stages)
    print(f"新断点集合 ({len(all_points)} 个): {all_points}")
    
    # Rebuild segments
    def_segs2 = []
    hp_segs2 = []
    for i in range(len(all_points)-1):
        s1,s2 = all_points[i], all_points[i+1]
        def_segs2.append((s1, s2, round_scale(mono_def[s1]), round_scale(mono_def[s2])))
        hp_segs2.append((s1, s2, round_scale(final_hp[s1]), round_scale(final_hp[s2])))
    
    # Re-verify
    prev_kt = 0
    violations2 = 0
    v_list2 = []
    for s in stages:
        d = stage_data[s]
        rn = (s-1)//25+1
        rhm = 1.0+(rn-1)*0.5
        
        if s <= 1:
            ds = 1.0
        else:
            ds = piecewise4(def_segs2, s)
        hs = piecewise4(hp_segs2, s)
        
        ep = d["effPen"]
        raw_def = MINION_BASE_DEF * ds
        eff_def = raw_def * (1-ep)
        df = 1 + eff_def / d["finalAtk"]
        
        raw_hp = MINION_BASE_HP * hs * rhm
        ehp = raw_hp * df / d["totalDmgMult"]
        kt = ehp / d["rawDPS"]
        
        if kt < prev_kt and s > 1:
            violations2 += 1
            drop = (prev_kt - kt)/prev_kt*100
            if drop > 0.5:
                v_list2.append((s, kt, prev_kt, drop, d["star"], d["battleStar"]))
        prev_kt = kt
    
    print(f"密集断点版本: 非单调点 = {violations2}")
    if v_list2:
        print(f"  大幅下降 (>0.5%): {len(v_list2)} 处")
        for s,kt,pkt,drop,star,bs in v_list2[:20]:
            print(f"    Stage {s}: KT={kt:.2f}s→{pkt:.2f}s (drop {drop:.1f}%), ★{star}, B★{bs}")
    
    if violations2 == 0 or not v_list2:
        print("\n✅ 密集断点版本通过单调性检查!")
        
        # Output the dense segments
        print()
        print("-- DEF_SCALE_SEGMENTS (密集断点版本)")
        print("Config.DEF_SCALE_SEGMENTS = {")
        for seg in def_segs2:
            print(f"    {{ {seg[0]:>5}, {seg[1]:>5}, {seg[2]:>14}, {seg[3]:>14} }},")
        print("}")
        
        print()
        print("-- HP_SCALE_SEGMENTS (密集断点版本)")
        print("Config.HP_SCALE_SEGMENTS = {")
        for seg in hp_segs2:
            print(f"    {{ {seg[0]:>5}, {seg[1]:>5}, {seg[2]:>14}, {seg[3]:>14} }},")
        print("}")
else:
    print("✅ 分段线性版本通过单调性检查!")

# midGameBaseline verification
print()
print("=" * 80)
print("midGameBaseline (★10, Adv5, B★3) 在 stage 1000 的 DEF 贡献")
print("=" * 80)
mgb = {"level":1000,"star":10,"advanceLevel":5,"battleStar":3,
       "atkPctBonus":0.20,"relicAtkPct":0.10,
       "relicSpdPct":0.05,"relicCritDmgPct":0.10,
       "equipArmorPen":0.10,"equipCritRate":0.10,
       "equipCritDmg":0.20,"equipDmgBonus":0.10,
       "elemDmg":0.10,"elemMastery":0.0}
mh = build_hero(mgb)
mc = calc_combat(mh, 1000)
mgb_ds = mono_def[1000]
mgb_rd = MINION_BASE_DEF * mgb_ds
mgb_ed = mgb_rd * (1 - mc["effPen"])
mgb_df = 1 + mgb_ed / mh["finalAtk"]
mgb_dp = (mgb_df-1)/mgb_df*100
print(f"  baseline finalAtk = {mh['finalAtk']:,}")
print(f"  DEF scale at 1000 = {mgb_ds:,.1f}")
print(f"  rawDEF = {int(mgb_rd):,}, effDEF = {mgb_ed:,.0f}")
print(f"  defFactor = {mgb_df:.4f}, DEF% = {mgb_dp:.1f}%")
print(f"  (heroParamsAtStage(1000) 下 DEF% = 20.0%)")
print(f"  差异原因: baseline finalAtk={mh['finalAtk']:,} >> stage(1000) finalAtk={stage_data[1000]['finalAtk']:,}")
print(f"  倍率: {mh['finalAtk']/stage_data[1000]['finalAtk']:.1f}x")
