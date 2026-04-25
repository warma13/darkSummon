#!/usr/bin/env python3
"""
v5: 修复元素抗性 — 使用实际主题元素抗性替代硬编码 er=0.20

v4 bug: 硬编码 er=0.20 (undead 主题对 shadow 的抗性)
        但采样点 100~6000 全部落在 void 主题 (shadow 抗性 0.40)
        导致 Python 预测 KT 比 Lua 模拟器低 ~25-33%

修复: 复现 MonsterEHP.lua 的 inferThemeId 逻辑，查表获取实际抗性
"""
import math

# ============================================================
# Constants
# ============================================================
BASE_ATK = 3600
RARITY = "SSR"
GROWTH_PCT = {"N":0.06, "R":0.08, "SR":0.10, "SSR":0.12, "UR":0.15, "LR":0.18}

STAR_NORMAL_MULT = 1.10
STAR_CROWN_MULT = 1.15
TIER_ADVANCE_MULT = 1.40
STAR_CROWN_START = 21
STAR_TIERS = [(1,5),(6,10),(11,15),(16,20),(21,25),(26,30)]

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

# ============================================================
# 元素抗性系统 (从 Config_Enemies.lua 复制)
# ============================================================
HERO_ELEMENT = "shadow"
THEMES = ["undead", "lava", "forest", "frost", "void"]
STAGES_PER_THEME = 5

# Config.THEME_ELEMENT_RESIST 对 shadow 的抗性值
THEME_SHADOW_RESIST = {
    "undead": 0.20,   # 亡灵亲和暗
    "lava":   0.00,
    "forest": -0.15,  # 森林弱于暗
    "frost":  0.00,
    "void":   0.40,   # 虚空极抗暗
}

def infer_theme_id(stage_num):
    """复现 MonsterEHP.lua 的 inferThemeId fallback 逻辑"""
    idx = (stage_num - 1) % (len(THEMES) * STAGES_PER_THEME)  # (stage-1) % 25
    theme_idx = idx // STAGES_PER_THEME  # 0~4
    return THEMES[theme_idx]

def get_elem_resist_factor(stage_num):
    """获取指定关卡的元素抗性因子 (1 - resist)"""
    theme = infer_theme_id(stage_num)
    resist = THEME_SHADOW_RESIST.get(theme, 0)
    return 1 - resist, theme, resist

# ============================================================
# Utility
# ============================================================
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
            }

def calc_combat(hero, stage):
    """v5: 使用实际主题元素抗性"""
    apr=piecewise4(ARMOR_PEN_RESIST_SEGS,stage)
    ep=min(1.0,max(0,hero["armorPen"]))*(1-apr)
    scd=soft_cap_stat(hero["critDmg"],SOFT_CAPS["critDmg"])
    ecd=max(0,scd-piecewise4(CRIT_DMG_REDUCE_SEGS,stage))
    cem=1+hero["critRate"]*(BASE_CRIT_MULT-1+ecd)
    sdb=soft_cap_stat(hero["dmgBonus"],SOFT_CAPS["dmgBonus"])
    edb=max(0,sdb-piecewise4(DMG_BONUS_REDUCE_SEGS,stage))
    dbm=1+edb
    # v5 fix: 使用实际主题元素抗性
    erf, theme, resist = get_elem_resist_factor(stage)
    sed=soft_cap_stat(hero["elemDmg"],SOFT_CAPS["elemDmg"])
    eed=max(0,sed+hero["elemMastery"]-piecewise4(ELEM_DMG_REDUCE_SEGS,stage))
    edm=1+eed
    tdm=cem*erf*dbm*edm
    return {"effPen":ep,"totalDmgMult":tdm,"effDPS":hero["rawDPS"]*tdm,
            "rawDPS":hero["rawDPS"],"theme":theme,"elemResist":resist,"erf":erf}

# ============================================================
# STEP 0: 元素抗性诊断
# ============================================================
SAMPLE = [1, 100, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000]

print("="*80)
print("STEP 0: 采样点元素抗性诊断")
print("="*80)
print()
print(f"{'Stage':>6} {'Theme':>8} {'Resist':>8} {'Factor':>8} | v4(er=0.20)")
print("-"*56)
for s in SAMPLE:
    erf, theme, resist = get_elem_resist_factor(s)
    v4_erf = 0.80
    diff = "✅ match" if abs(erf - v4_erf) < 0.01 else f"❌ off by {(erf-v4_erf)/v4_erf*100:+.0f}%"
    print(f"{s:>6} {theme:>8} {resist:>8.2f} {erf:>8.2f} | {v4_erf:.2f}  {diff}")

# ============================================================
# STEP 1: 在每个采样点精确计算英雄参数
# ============================================================
TARGET_DEF_FACTOR = 1.25  # 20% DEF contribution

def target_kill_time(stage):
    progress = min(1.0, (stage-1)/5999)
    return 2 + 8 * math.sqrt(progress)

print()
print("="*80)
print("STEP 1: 精确采样点校准 (v5 - 实际元素抗性)")
print("="*80)
print()

results = []
for s in SAMPLE:
    hp = hero_params_at_stage(s)
    h = build_hero(hp)
    c = calc_combat(h, s)
    
    rn = (s-1)//25 + 1
    rhm = 1.0 + (rn-1)*0.5
    
    # DEF: defFactor = 1.25 → effDEF = 0.25 * finalAtk
    needed_eff_def = (TARGET_DEF_FACTOR - 1) * h["finalAtk"]
    ep = c["effPen"]
    needed_raw_def = needed_eff_def / (1 - ep) if ep < 1 else needed_eff_def
    def_scale = needed_raw_def / MINION_BASE_DEF
    
    # Verify DEF
    raw_def = MINION_BASE_DEF * def_scale
    eff_def = raw_def * (1 - ep)
    actual_df = 1 + eff_def / h["finalAtk"]
    actual_def_pct = (actual_df - 1) / actual_df * 100
    
    # HP: target KT
    tkt = target_kill_time(s)
    # kt = baseHP * hpScale * rhm * actual_df / (rawDPS * totalDmgMult) * totalDmgMult
    # 简化: kt = baseHP * hpScale * rhm * actual_df / effDPS
    hp_scale = tkt * c["effDPS"] / (MINION_BASE_HP * rhm * actual_df)
    
    # Verify HP
    raw_hp = MINION_BASE_HP * hp_scale * rhm
    ehp = raw_hp * actual_df / c["totalDmgMult"]
    actual_kt = ehp / c["rawDPS"]
    
    results.append({
        "stage": s, "defScale": def_scale, "hpScale": hp_scale,
        "kt": actual_kt, "defPct": actual_def_pct,
        "tkt": tkt, "finalAtk": h["finalAtk"],
        "effDPS": c["effDPS"], "rawDPS": c["rawDPS"],
        "round": rn, "rhm": rhm,
        "theme": c["theme"], "erf": c["erf"],
    })

print(f"{'Stage':>6} {'Theme':>8} {'erf':>5} {'defScale':>14} {'hpScale':>14} | {'KT':>8} {'tgt':>8} {'DEF%':>6}")
print("-"*96)
for r in results:
    print(f"{r['stage']:>6} {r['theme']:>8} {r['erf']:>5.2f} {r['defScale']:>14,.1f} {r['hpScale']:>14,.1f} | "
          f"{r['kt']:>8.2f} {r['tkt']:>8.2f} {r['defPct']:>5.1f}%")

# Check monotonicity
print()
print("单调性检查:")
mono_ok = True
for i in range(1, len(results)):
    r = results[i]
    p = results[i-1]
    issues = []
    if r["defScale"] < p["defScale"]: issues.append(f"DEF↓ {p['defScale']:.1f}→{r['defScale']:.1f}")
    if r["hpScale"] < p["hpScale"]: issues.append(f"HP↓ {p['hpScale']:.1f}→{r['hpScale']:.1f}")
    if r["kt"] < p["kt"]: issues.append(f"KT↓ {p['kt']:.2f}→{r['kt']:.2f}")
    if issues:
        mono_ok = False
        print(f"  ❌ Stage {p['stage']}→{r['stage']}: {', '.join(issues)}")
if mono_ok:
    print("  ✅ 原始值已单调")

# ============================================================
# STEP 2: 强制单调 (running max)
# ============================================================
print()
print("="*80)
print("STEP 2: 强制单调（running max）")
print("="*80)

mono_results = []
max_ds = 0
max_hs = 0
for r in results:
    max_ds = max(max_ds, r["defScale"])
    max_hs = max(max_hs, r["hpScale"])
    mono_results.append({**r, "defScale": max_ds, "hpScale": max_hs})

print()
print(f"{'Stage':>6} {'defScale':>14} {'hpScale':>14} | {'KT':>8} {'tgt':>8} {'DEF%':>6}")
print("-"*76)

prev_kt = 0
all_ok = True
for mr in mono_results:
    s = mr["stage"]
    ds = mr["defScale"]
    hs = mr["hpScale"]
    
    hp = hero_params_at_stage(s)
    h = build_hero(hp)
    c = calc_combat(h, s)
    
    rn = (s-1)//25 + 1
    rhm = 1.0 + (rn-1)*0.5
    ep = c["effPen"]
    
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / h["finalAtk"]
    def_pct = (df-1)/df*100
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / c["totalDmgMult"]
    kt = ehp / c["rawDPS"]
    tkt = target_kill_time(s)
    
    status = "✅" if kt >= prev_kt or s == 1 else "❌"
    if kt < prev_kt and s > 1:
        all_ok = False
    
    print(f"{s:>6} {ds:>14,.1f} {hs:>14,.1f} | {kt:>8.2f} {tkt:>8.2f} {def_pct:>5.1f}% {status}")
    prev_kt = kt

if all_ok:
    print("\n✅ 14 采样点全部严格单调递增!")
else:
    print("\n❌ 仍有非单调")

# ============================================================
# STEP 3: 生成 Lua 代码
# ============================================================
print()
print("="*80)
print("STEP 3: Lua 代码输出")
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

def monotonic_round(values):
    result = []
    for i, v in enumerate(values):
        rv = round_scale(v)
        if i > 0 and rv <= result[-1]:
            rv = result[-1] + (1 if result[-1] < 100 else
                              10 if result[-1] < 1000 else
                              100 if result[-1] < 10000 else
                              1000 if result[-1] < 100000 else
                              10000 if result[-1] < 1000000 else
                              100000)
        result.append(rv)
    return result

def_vals = [mr["defScale"] for mr in mono_results]
hp_vals = [mr["hpScale"] for mr in mono_results]

def_rounded = monotonic_round(def_vals)
hp_rounded = monotonic_round(hp_vals)

print()
print("-- DEF 缩放表: heroParamsAtStage 精确校准，defFactor=1.25 (DEF 贡献 ~20%)")
print("-- v5: 使用实际主题元素抗性 (shadow_mage vs 各主题)")
print("Config.DEF_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    d1 = def_rounded[i]
    d2 = def_rounded[i+1]
    print(f"    {{ {s1:>5}, {s2:>5}, {d1:>14}, {d2:>14} }},")
print("}")

print()
print("-- HP 缩放表: heroParamsAtStage 精确校准，killTime = 2+8√progress")
print("-- v5: 使用实际主题元素抗性 (shadow_mage vs 各主题)")
print("Config.HP_SCALE_SEGMENTS = {")
for i in range(len(SAMPLE)-1):
    s1,s2 = SAMPLE[i], SAMPLE[i+1]
    h1 = hp_rounded[i]
    h2 = hp_rounded[i+1]
    print(f"    {{ {s1:>5}, {s2:>5}, {h1:>14}, {h2:>14} }},")
print("}")

# ============================================================
# STEP 4: 验证分段线性版本
# ============================================================
print()
print("="*80)
print("STEP 4: 分段线性版本验证")
print("="*80)

def_segs = []
hp_segs = []
for i in range(len(SAMPLE)-1):
    def_segs.append((SAMPLE[i], SAMPLE[i+1], def_rounded[i], def_rounded[i+1]))
    hp_segs.append((SAMPLE[i], SAMPLE[i+1], hp_rounded[i], hp_rounded[i+1]))

print()
print("14 采样点验证 (分段线性):")
prev_kt = 0
for s in SAMPLE:
    hp = hero_params_at_stage(s)
    h = build_hero(hp)
    c = calc_combat(h, s)
    
    rn = (s-1)//25 + 1
    rhm = 1.0 + (rn-1)*0.5
    ep = c["effPen"]
    
    ds = piecewise4(def_segs, s)
    hs = piecewise4(hp_segs, s)
    
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / h["finalAtk"]
    def_pct = (df-1)/df*100
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / c["totalDmgMult"]
    kt = ehp / c["rawDPS"]
    tkt = target_kill_time(s)
    
    status = "✅" if kt >= prev_kt or s == 1 else f"❌ (drop {(prev_kt-kt)/prev_kt*100:.1f}%)"
    print(f"  Stage {s:>5}: KT={kt:.2f}s (tgt={tkt:.2f}), DEF%={def_pct:.1f}% {status}")
    prev_kt = kt

print()
print("每100关抽查 (查找 >20% 大幅下降):")
big_drops = 0
prev_kt = 0
for s in range(1, 6001, 100):
    hp = hero_params_at_stage(s)
    h = build_hero(hp)
    c = calc_combat(h, s)
    
    rn = (s-1)//25 + 1
    rhm = 1.0 + (rn-1)*0.5
    ep = c["effPen"]
    
    ds = piecewise4(def_segs, s)
    hs = piecewise4(hp_segs, s)
    
    raw_def = MINION_BASE_DEF * ds
    eff_def = raw_def * (1 - ep)
    df = 1 + eff_def / h["finalAtk"]
    
    raw_hp = MINION_BASE_HP * hs * rhm
    ehp = raw_hp * df / c["totalDmgMult"]
    kt = ehp / c["rawDPS"]
    
    if kt < prev_kt and s > 1:
        drop = (prev_kt - kt)/prev_kt*100
        if drop > 20:
            big_drops += 1
            print(f"  ⚠️ Stage {s}: KT={kt:.2f}s < prev={prev_kt:.2f}s (drop {drop:.1f}%)")
    prev_kt = kt

if big_drops == 0:
    print("  ✅ 无大幅下降 (>20%)")

# ============================================================
# STEP 5: midGameBaseline 验证
# ============================================================
print()
print("="*80)
print("STEP 5: midGameBaseline 在 stage 1000 的 DEF 贡献")
print("="*80)
mgb = {"level":1000,"star":10,"advanceLevel":5,"battleStar":3,
       "atkPctBonus":0.20,"relicAtkPct":0.10,
       "relicSpdPct":0.05,"relicCritDmgPct":0.10,
       "equipArmorPen":0.10,"equipCritRate":0.10,
       "equipCritDmg":0.20,"equipDmgBonus":0.10,
       "elemDmg":0.10,"elemMastery":0.0}
mh = build_hero(mgb)
mc = calc_combat(mh, 1000)
ds_1000 = piecewise4(def_segs, 1000)
rd = MINION_BASE_DEF * ds_1000
ed = rd * (1 - mc["effPen"])
df_ = 1 + ed / mh["finalAtk"]
dp_ = (df_-1)/df_*100
print(f"  baseline finalAtk = {mh['finalAtk']:,}")
print(f"  heroParamsAtStage(1000) finalAtk = {build_hero(hero_params_at_stage(1000))['finalAtk']:,}")
print(f"  倍率差 = {mh['finalAtk']/build_hero(hero_params_at_stage(1000))['finalAtk']:.1f}x")
print(f"  DEF scale at 1000 = {ds_1000:,.1f}")
print(f"  baseline DEF% = {dp_:.1f}% (正常: 高 ATK 英雄自然稀释 DEF)")
print(f"  heroParamsAtStage DEF% = 20.0% (校准目标)")
print()
print("结论: Report 5 的 DEF% 低是预期行为，不是 bug。")
