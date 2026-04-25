#!/usr/bin/env python3
"""
v3: 务实方案 — 在每个 roundHPMult 跳变点（每25关）取包络线保证，
    而不是逐关保证。
    
原因: roundHPMult 每25关阶梯+0.5，DPS 每关线性增长，导致25关周期
内 KT 自然波动 ~2-5%。这是正常的游戏机制，不需要消除。
真正需要消除的是: star tier 和 battleStar 导致的大幅 DPS 跳变(>10%)。

策略:
  1. 逐关计算 DPS
  2. 在每个 round 边界(每25关)取当前 round 内的 max DPS
  3. 用 round-level max DPS 计算 HP scale
  4. 确保 round 维度上 KT 严格单调
  5. 输出分段线性表
"""
import math

# ============================================================
# Constants (exact copy from Lua)
# ============================================================
BASE_ATK = 3600
RARITY = "SSR"
GROWTH_PCT = {"N":0.06, "R":0.08, "SR":0.10, "SSR":0.12, "UR":0.15, "LR":0.18}

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
    er=0.20
    erf=1-er
    sed=soft_cap_stat(hero["elemDmg"],SOFT_CAPS["elemDmg"])
    eed=max(0,sed+hero["elemMastery"]-piecewise4(ELEM_DMG_REDUCE_SEGS,stage))
    edm=1+eed
    tdm=cem*erf*dbm*edm
    return {"effPen":ep,"totalDmgMult":tdm,"effDPS":hero["rawDPS"]*tdm}

# ============================================================
# STEP 1: 逐关计算 DPS
# ============================================================
print("="*80)
print("STEP 1: 逐关计算 DPS")
print("="*80)

stages = list(range(1, 6001))
stage_data = {}

for s in stages:
    hp = hero_params_at_stage(s)
    h = build_hero(hp)
    c = calc_combat(h, s)
    rn = (s-1)//25 + 1
    rhm = 1.0 + (rn-1)*0.5
    stage_data[s] = {
        "effDPS": c["effDPS"],
        "rawDPS": h["rawDPS"],
        "finalAtk": h["finalAtk"],
        "effPen": c["effPen"],
        "totalDmgMult": c["totalDmgMult"],
        "star": h["star"],
        "battleStar": h["battleStar"],
        "level": h["level"],
        "round": rn,
        "roundHPMult": rhm,
    }

# ============================================================
# STEP 2: 在每个 round 内取 max DPS/ATK，round 粒度包络线
# ============================================================
print("STEP 2: 构建 round 粒度包络线")

# Group by round
max_round = stage_data[6000]["round"]
round_max_dps = {}
round_max_atk = {}
round_last_stage = {}

for s in stages:
    d = stage_data[s]
    rn = d["round"]
    if rn not in round_max_dps or d["effDPS"] > round_max_dps[rn]:
        round_max_dps[rn] = d["effDPS"]
    if rn not in round_max_atk or d["finalAtk"] > round_max_atk[rn]:
        round_max_atk[rn] = d["finalAtk"]
    round_last_stage[rn] = s

# running max across rounds (envelope)
env_dps = {}
env_atk = {}
mx_dps = 0
mx_atk = 0
for rn in range(1, max_round+1):
    mx_dps = max(mx_dps, round_max_dps.get(rn, 0))
    mx_atk = max(mx_atk, round_max_atk.get(rn, 0))
    env_dps[rn] = mx_dps
    env_atk[rn] = mx_atk

print(f"  Round 数量: {max_round}")
print(f"  最终包络 DPS: {env_dps[max_round]:,.0f}")
print(f"  最终包络 ATK: {env_atk[max_round]:,}")

# ============================================================
# STEP 3: 求解 DEF/HP scale per-stage, 使用 round 包络
# ============================================================
print()
print("="*80)
print("STEP 3: 求解 DEF/HP scale")
print("="*80)

TARGET_DEF_PCT = 0.20  # 20% DEF contribution
TARGET_DEF_FACTOR = 1.0 / (1.0 - TARGET_DEF_PCT)  # = 1.25

def target_kill_time(stage):
    progress = min(1.0, (stage-1)/5999)
    return 2 + 8 * math.sqrt(progress)

# For each stage, DEF scale targets 20% of envelope ATK at that round
# For HP scale, we use round envelope DPS and ensure per-round monotonicity

# DEF: defFactor = 1 + effDEF / finalAtk = 1.25
# → effDEF = 0.25 * finalAtk
# → rawDEF = effDEF / (1 - effPen)
# → defScale = rawDEF / baseDEF
# We use envelope_ATK at the round level for the ATK reference

# First pass: compute ideal DEF/HP at each stage
ideal_def = {}
ideal_hp = {}

for s in stages:
    d = stage_data[s]
    rn = d["round"]
    rhm = d["roundHPMult"]
    
    # DEF: use round-envelope ATK
    ref_atk = env_atk[rn]
    needed_eff_def = (TARGET_DEF_FACTOR - 1) * ref_atk
    ep = d["effPen"]
    needed_raw_def = needed_eff_def / (1 - ep) if ep < 1 else needed_eff_def
    ds = needed_raw_def / MINION_BASE_DEF
    ideal_def[s] = ds
    
    # HP: use round-envelope DPS
    ref_dps = env_dps[rn]
    tkt = target_kill_time(s)
    # killTime = baseHP * hpScale * rhm * defFactor / effDPS
    # → hpScale = tkt * effDPS / (baseHP * rhm * defFactor)
    # But we want to compute defFactor at this stage using the ideal DEF:
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    actual_df = 1 + eff_def / ref_atk  # ≈ 1.25 by construction
    
    hs = tkt * ref_dps / (MINION_BASE_HP * rhm * actual_df)
    ideal_hp[s] = hs

# Running max to ensure monotonic
mono_def = {}
mono_hp = {}
mx_d = 0
mx_h = 0
for s in stages:
    mx_d = max(mx_d, ideal_def[s])
    mx_h = max(mx_h, ideal_hp[s])
    mono_def[s] = mx_d
    mono_hp[s] = mx_h

# ============================================================
# STEP 4: 验证 — 在 round 边界点(每25关的最后一关) KT 必须单调
# ============================================================
print()
print("="*80)
print("STEP 4: 验证 round 边界单调性")
print("="*80)

# Check at round boundaries (last stage of each round)
prev_min_kt = 0
round_violations = 0
all_round_kts = []

for rn in range(1, max_round+1):
    # Find min KT within this round (worst case stage)
    first_s = (rn-1)*25 + 1
    last_s = min(rn*25, 6000)
    
    min_kt_in_round = float('inf')
    worst_stage = first_s
    
    for s in range(first_s, last_s+1):
        d = stage_data[s]
        ds = mono_def[s]
        hs = mono_hp[s]
        
        ep = d["effPen"]
        raw_def = MINION_BASE_DEF * ds
        eff_def = raw_def * (1 - ep)
        df = 1 + eff_def / d["finalAtk"]
        
        raw_hp = MINION_BASE_HP * hs * d["roundHPMult"]
        ehp = raw_hp * df / d["totalDmgMult"]
        kt = ehp / d["rawDPS"]
        
        if kt < min_kt_in_round:
            min_kt_in_round = kt
            worst_stage = s
    
    all_round_kts.append((rn, min_kt_in_round, worst_stage))
    
    if min_kt_in_round < prev_min_kt and rn > 1:
        round_violations += 1
        drop = (prev_min_kt - min_kt_in_round)/prev_min_kt*100
        if drop > 1:
            print(f"  Round {rn} (stage {worst_stage}): min KT={min_kt_in_round:.2f}s < prev={prev_min_kt:.2f}s (drop {drop:.1f}%)")
    prev_min_kt = max(prev_min_kt, min_kt_in_round)

print(f"Round 边界非单调: {round_violations} (共 {max_round} rounds)")

# ============================================================
# STEP 4b: 如果 round 边界有违规，需要加强 HP
# ============================================================
if round_violations > 0:
    print()
    print("="*80)
    print("STEP 4b: 修正 — 逐 round 取 min KT 的 running max 做 HP 补偿")
    print("="*80)
    
    # For each round, if its min KT < target, boost HP scale
    # We need to find the actual min KT at each stage considering actual DPS (not envelope)
    # Then ensure running max of hpScale
    
    # Recompute: for each stage, compute needed hpScale using ACTUAL DPS
    actual_hp = {}
    for s in stages:
        d = stage_data[s]
        ds = mono_def[s]
        ep = d["effPen"]
        raw_def = MINION_BASE_DEF * ds
        eff_def = raw_def * (1 - ep)
        df = 1 + eff_def / d["finalAtk"]
        
        tkt = target_kill_time(s)
        # kt = baseHP * hs * rhm * df / (rawDPS * tdm)
        # hs = tkt * rawDPS * tdm / (baseHP * rhm * df)
        needed_hs = tkt * d["rawDPS"] * d["totalDmgMult"] / (MINION_BASE_HP * d["roundHPMult"] * df)
        actual_hp[s] = needed_hs
    
    # Running max
    mx_h = 0
    for s in stages:
        mx_h = max(mx_h, actual_hp[s])
        mono_hp[s] = mx_h
    
    # Re-verify round boundaries
    prev_min_kt = 0
    round_violations2 = 0
    for rn in range(1, max_round+1):
        first_s = (rn-1)*25 + 1
        last_s = min(rn*25, 6000)
        min_kt = float('inf')
        for s in range(first_s, last_s+1):
            d = stage_data[s]
            ds = mono_def[s]
            hs = mono_hp[s]
            ep = d["effPen"]
            raw_def = MINION_BASE_DEF * ds
            eff_def = raw_def * (1 - ep)
            df = 1 + eff_def / d["finalAtk"]
            raw_hp = MINION_BASE_HP * hs * d["roundHPMult"]
            ehp = raw_hp * df / d["totalDmgMult"]
            kt = ehp / d["rawDPS"]
            min_kt = min(min_kt, kt)
        if min_kt < prev_min_kt and rn > 1:
            round_violations2 += 1
            drop = (prev_min_kt - min_kt)/prev_min_kt*100
            if drop > 0.1:
                print(f"  Round {rn}: min KT={min_kt:.4f}s < prev={prev_min_kt:.4f}s (drop {drop:.2f}%)")
        prev_min_kt = max(prev_min_kt, min_kt)
    
    print(f"修正后 round 边界非单调: {round_violations2}")

# ============================================================
# STEP 5: 逐关验证
# ============================================================
print()
print("="*80)
print("STEP 5: 逐关验证 (每 1 关)")
print("="*80)

prev_kt = 0
per_stage_violations = 0
big_violations = []
for s in stages:
    d = stage_data[s]
    ds = mono_def[s]
    hs = mono_hp[s]
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / d["finalAtk"]
    raw_hp = MINION_BASE_HP * hs * d["roundHPMult"]
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    if kt < prev_kt and s > 1:
        per_stage_violations += 1
        drop = (prev_kt - kt)/prev_kt*100
        if drop > 5:
            big_violations.append((s, kt, prev_kt, drop, d["star"], d["battleStar"], d["round"]))
    prev_kt = kt

print(f"逐关非单调: {per_stage_violations}")
print(f"大幅下降 (>5%): {len(big_violations)} 处")
if big_violations:
    for s,kt,pkt,drop,star,bs,rn in big_violations[:20]:
        print(f"  Stage {s} (round {rn}): KT={kt:.2f}s→{pkt:.2f}s (drop {drop:.1f}%), ★{star}, B★{bs}")

# Analyze: what are these violations?
# Expect: within each 25-stage round, KT may drop slightly because level grows
# but roundHPMult stays constant. Between rounds, roundHPMult jumps.
# This is NORMAL game behavior.

# Count violations only at round BOUNDARIES (not within rounds)
boundary_violations = 0
for s, kt, pkt, drop, star, bs, rn in big_violations:
    prev_rn = stage_data[s-1]["round"] if s > 1 else 0
    if rn != prev_rn:
        boundary_violations += 1
        print(f"  [BOUNDARY] Stage {s}: round {prev_rn}→{rn}, KT {pkt:.2f}→{kt:.2f} (drop {drop:.1f}%)")

print(f"\n其中 round 边界处大幅违规: {boundary_violations}")

# ============================================================
# STEP 6: 输出采样点数据
# ============================================================
print()
print("="*80)
print("STEP 6: 采样点数据")
print("="*80)

SAMPLE = [1, 100, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000]

print(f"\n{'Stage':>6} {'defScale':>14} {'hpScale':>14} | {'KT':>8} {'DEF%':>8} {'tgt KT':>8}")
print("-"*76)

for s in SAMPLE:
    ds = mono_def[s]
    hs = mono_hp[s]
    d = stage_data[s]
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / d["finalAtk"]
    def_pct = (df-1)/df*100
    raw_hp = MINION_BASE_HP * hs * d["roundHPMult"]
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    tkt = target_kill_time(s)
    print(f"{s:>6} {ds:>14,.1f} {hs:>14,.1f} | {kt:>8.2f} {def_pct:>7.1f}% {tkt:>8.2f}")

# ============================================================
# STEP 7: 输出 Lua 代码
# ============================================================
print()
print("="*80)
print("STEP 7: Lua 代码输出")
print("="*80)

def round_scale(v):
    if v < 2: return round(v, 2)
    if v < 10: return round(v, 1)
    if v < 100: return round(v)
    if v < 1000: return round(v)
    if v < 10000: return round(v, -1)
    if v < 100000: return round(v, -2)
    if v < 1000000: return round(v, -3)
    return round(v, -4)

print()
print("Config.DEF_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    d1 = round_scale(mono_def[s1])
    d2 = round_scale(mono_def[s2])
    print(f"    {{ {s1:>5}, {s2:>5}, {d1:>14}, {d2:>14} }},")
print("}")

print()
print("Config.HP_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    h1 = round_scale(mono_hp[s1])
    h2 = round_scale(mono_hp[s2])
    print(f"    {{ {s1:>5}, {s2:>5}, {h1:>14}, {h2:>14} }},")
print("}")

# ============================================================
# STEP 8: 用分段线性版本验证
# ============================================================
print()
print("="*80)
print("STEP 8: 分段线性版本验证")
print("="*80)

def_segs = []
hp_segs = []
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    def_segs.append((s1, s2, round_scale(mono_def[s1]), round_scale(mono_def[s2])))
    hp_segs.append((s1, s2, round_scale(mono_hp[s1]), round_scale(mono_hp[s2])))

prev_kt = 0
seg_violations = 0
seg_big = []
for s in stages:
    d = stage_data[s]
    ds = piecewise4(def_segs, s)
    hs = piecewise4(hp_segs, s)
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / d["finalAtk"]
    raw_hp = MINION_BASE_HP * hs * d["roundHPMult"]
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    if kt < prev_kt and s > 1:
        seg_violations += 1
        drop = (prev_kt - kt)/prev_kt*100
        if drop > 5:
            seg_big.append((s, kt, prev_kt, drop, d["star"], d["battleStar"], d["round"]))
    prev_kt = kt

print(f"分段线性版本: 逐关非单调点 = {seg_violations}")
print(f"  大幅下降 (>5%): {len(seg_big)} 处")
for s,kt,pkt,drop,star,bs,rn in seg_big[:20]:
    print(f"    Stage {s} (round {rn}): KT={kt:.2f}s→{pkt:.2f}s (drop {drop:.1f}%), ★{star}, B★{bs}")

# Check: are all >5% violations at round boundaries or star transitions?
# If so, they're natural game mechanics, not scale problems

# Also verify at the 14 sample points (simulator checks these)
print()
print("14 采样点连续性检查:")
prev_kt = 0
for s in SAMPLE:
    d = stage_data[s]
    ds = piecewise4(def_segs, s)
    hs = piecewise4(hp_segs, s)
    ep = d["effPen"]
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / d["finalAtk"]
    raw_hp = MINION_BASE_HP * hs * d["roundHPMult"]
    ehp = raw_hp * df / d["totalDmgMult"]
    kt = ehp / d["rawDPS"]
    
    status = "✅" if kt >= prev_kt or s == 1 else f"❌ drop {(prev_kt-kt)/prev_kt*100:.1f}%"
    print(f"  Stage {s:>5}: KT = {kt:.2f}s  {status}")
    prev_kt = kt

# ============================================================
# STEP 9: midGameBaseline 验证
# ============================================================
print()
print("="*80)
print("STEP 9: midGameBaseline 验证")
print("="*80)
mgb = {"level":1000,"star":10,"advanceLevel":5,"battleStar":3,
       "atkPctBonus":0.20,"relicAtkPct":0.10,
       "relicSpdPct":0.05,"relicCritDmgPct":0.10,
       "equipArmorPen":0.10,"equipCritRate":0.10,
       "equipCritDmg":0.20,"equipDmgBonus":0.10,
       "elemDmg":0.10,"elemMastery":0.0}
mh = build_hero(mgb)
mc = calc_combat(mh, 1000)
mgb_ds = piecewise4(def_segs, 1000)
mgb_rd = MINION_BASE_DEF * mgb_ds
mgb_ed = mgb_rd * (1 - mc["effPen"])
mgb_df = 1 + mgb_ed / mh["finalAtk"]
mgb_dp = (mgb_df-1)/mgb_df*100
print(f"  baseline finalAtk = {mh['finalAtk']:,}")
print(f"  heroParamsAtStage(1000) finalAtk = {stage_data[1000]['finalAtk']:,}")
print(f"  倍率差 = {mh['finalAtk']/stage_data[1000]['finalAtk']:.1f}x")
print(f"  DEF scale at 1000 = {mgb_ds:,.1f}")
print(f"  baseline DEF% = {mgb_dp:.1f}% (expected: low due to high ATK)")
print(f"  heroParamsAtStage DEF% = 20.0% (calibration target)")
