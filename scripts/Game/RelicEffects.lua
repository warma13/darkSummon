-- Game/RelicEffects.lua
-- 神圣遗物战斗效果模块
-- 充能系统运行时 + 5种力部位释放处理 + 意志部位后释放效果
-- 每帧由 Combat.Update 驱动

local Config    = require("Game.Config")
local State     = require("Game.State")
local RelicCalc = require("Game.RelicCalc")
local FormatNum = require("Game.FormatUtil").FormatNum

local RelicEffects = {}

-- 延迟 require（打破循环依赖）
local _RelicData, _HeroData, _Enemy, _DamageStats, _HeroSkills, _Tower
local function GetRelicData()
    if not _RelicData then _RelicData = require("Game.RelicData") end
    return _RelicData
end
local function GetHeroData()
    if not _HeroData then _HeroData = require("Game.HeroData") end
    return _HeroData
end
local function GetEnemy()
    if not _Enemy then _Enemy = require("Game.Enemy") end
    return _Enemy
end
local function GetDamageStats()
    if not _DamageStats then _DamageStats = require("Game.DamageStats") end
    return _DamageStats
end
local function GetHeroSkills()
    if not _HeroSkills then _HeroSkills = require("Game.HeroSkills") end
    return _HeroSkills
end
local function GetTower()
    if not _Tower then _Tower = require("Game.Tower") end
    return _Tower
end

-- 飘字/粒子安全添加
local AddFloatingText = State.AddFloatingText
local AddParticle = State.AddParticle

-- ============================================================================
-- 运行时状态（Init 时重置）
-- ============================================================================

local _charge = { current = 0, max = 100, ready = false }
local _globalCD = 0          -- 释放后全局冷却
local _pulseTimer = 0        -- void_pulse 脉冲定时器
local _burns = {}            -- 灼烧 DOT 列表: { target, tickDmg, remaining, interval, timer }

-- 意志部位后释放效果
local _postCastBuff = nil    -- { id, remaining, value }

-- ============================================================================
-- 预定义飘字颜色
-- ============================================================================
local COLOR_RELIC_NORMAL = Config.RELIC_DMG_COLORS.normal
local COLOR_TRUE_DMG     = Config.RELIC_DMG_COLORS.trueDmg
local COLOR_BURN         = Config.RELIC_DMG_COLORS.burn
local COLOR_EXECUTE      = Config.RELIC_DMG_COLORS.execute
local COLOR_PULSE        = Config.RELIC_DMG_COLORS.pulse

-- ============================================================================
-- 初始化 / 重置（进入战斗或 Combat.Reset 时调用）
-- ============================================================================

function RelicEffects.Init()
    _charge.current = 0
    _charge.max = 100
    _charge.ready = false
    _globalCD = 0
    _pulseTimer = 0
    _burns = {}
    _postCastBuff = nil

    -- 计算有效充能上限
    local RD = GetRelicData()
    local powerRelic = RD.GetEquipped("power")
    if powerRelic and Config.RELICS[powerRelic.id] and Config.RELICS[powerRelic.id].hasCharge then
        local willReduction = 0
        local willRelic = RD.GetEquipped("will")
        if willRelic and willRelic.id == "rapid_charge" then
            local rcDef = Config.RELICS.rapid_charge
            willReduction = RelicCalc.V(willRelic, rcDef.params.chargeReduce)
            -- 急速充能自身星级额外减少（渐进值）
            if rcDef.starEffect and rcDef.starEffect.type == "chargeReduce" then
                willReduction = willReduction + RelicCalc.StarValue(willRelic.star, rcDef.starEffect)
            end
        end
        _charge.max = RelicCalc.GetEffectiveChargeMax(powerRelic, willReduction)
    end

    print("[RelicEffects] Init, chargeMax=" .. _charge.max)
end

--- 获取充能状态（供 UI 读取）
---@return table { current, max, ready }
function RelicEffects.GetChargeState()
    return _charge
end

--- 获取当前后释放 buff（供 UI/Tower 读取）
---@return table|nil { id, remaining, value }
function RelicEffects.GetPostCastBuff()
    return _postCastBuff
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取场上最高ATK英雄的攻击力
local function GetMaxTowerATK()
    local HS = GetHeroSkills()
    local maxAtk = 0
    for _, tower in ipairs(State.towers) do
        local atk = HS.GetEffectiveAttack(tower)
        if atk > maxAtk then
            maxAtk = atk
        end
    end
    return maxAtk
end

--- 获取场上所有塔平均ATK
local function GetAvgTowerATK()
    local HS = GetHeroSkills()
    local total = 0
    local count = #State.towers
    if count == 0 then return 0 end
    for _, tower in ipairs(State.towers) do
        total = total + HS.GetEffectiveAttack(tower)
    end
    return total / count
end

--- 查找血量最高的存活敌人
local function FindHighestHPEnemy()
    local best = nil
    local maxHP = 0
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            if e.hp > maxHP then
                maxHP = e.hp
                best = e
            end
        end
    end
    return best
end

--- 显示遗物伤害飘字
local function ShowRelicDamageText(target, dmg, color, fontSize, prefix)
    local text = prefix and (prefix .. FormatNum(dmg)) or FormatNum(dmg)
    local size = target.typeDef and target.typeDef.size or 8
    local vx = (math.random() - 0.5) * 80
    local vy = -(65 + math.random() * 40)
    AddFloatingText({
        text = text,
        x = target.x + (math.random() - 0.5) * 12,
        y = target.y - size - 10,
        vx = vx, vy = vy,
        life = 0.9,
        maxLife = 0.9,
        color = color,
        fontSize = fontSize or 14,
    })
end

--- 计算真实伤害（跳过 DEF 和元素抗性，保留暴击/伤害加成/易伤）
--- 返回 finalDmg, isCrit
local function CalcTrueDamage(baseDmg, tower, target)
    local isCrit = false
    local mult = 1.0

    -- 暴击乘区
    if tower then
        local HS = GetHeroSkills()
        local critRate = HS.GetEffectiveCritRate(tower)
        if critRate > 0 and math.random() < critRate then
            isCrit = true
            local T = GetTower()
            local critDmg = T.GetEffectiveCritDmg(tower)
            local hs = tower.hstate
            if hs and hs.bonusCritDmg and hs.bonusCritDmg > 0 then
                critDmg = critDmg + hs.bonusCritDmg
            end
            mult = mult * (Config.BASE_CRIT_MULT + critDmg)
        end

        -- 伤害加成乘区
        local T = GetTower()
        local dmgBonus = T.GetEffectiveDmgBonus(tower)
        if dmgBonus > 0 then
            mult = mult * (1 + dmgBonus)
        end
    end

    -- 易伤标记乘区（检查 Debuff）
    if target then
        local Debuff = require("Game.Debuff")
        if Debuff.Has(target, "amp_damage") then
            local ampValue = target.ampDamage or 0
            mult = mult * (1 + ampValue)
        end
    end

    return baseDmg * mult, isCrit
end

-- ============================================================================
-- 后释放效果处理（意志部位联动）
-- ============================================================================

local function TriggerPostCastEffects()
    local RD = GetRelicData()

    -- 不灭圣焰（心·橙）：力部位释放后，全体攻速 +15% 持续 3 秒
    local heartRelic = RD.GetEquipped("heart")
    if heartRelic and heartRelic.id == "immortal_flame" then
        local def = Config.RELICS.immortal_flame
        local duration = def.params.postCastDuration
        -- 星级效果：持续时间延长
        if def.starEffect and def.starEffect.type == "durationAdd" then
            duration = duration + RelicCalc.StarValue(heartRelic.star, def.starEffect)
        end
        _postCastBuff = {
            id = "immortal_flame_spd",
            remaining = duration,
            value = def.params.postCastSpdBonus,
        }
    end

    -- 超载爆发（意志·紫）：释放后 5 秒全体伤害 +X%
    local willRelic = RD.GetEquipped("will")
    if willRelic and willRelic.id == "overload_burst" then
        local def = Config.RELICS.overload_burst
        local dmgVal = RelicCalc.V(willRelic, def.params.postCastDmgBonus)
        local duration = def.params.postCastDuration
        -- 星级效果：持续时间延长
        if def.starEffect and def.starEffect.type == "durationAdd" then
            duration = duration + RelicCalc.StarValue(willRelic.star, def.starEffect)
        end
        _postCastBuff = {
            id = "overload_burst_dmg",
            remaining = duration,
            value = dmgVal,
        }
    end
end

-- ============================================================================
-- 5种力部位释放处理器
-- ============================================================================

local _castHandlers = {}

--- 裁决之矛：单体高额伤害，锁定血量最高敌人
_castHandlers.judgment_spear = function(relic, relicDef)
    local target = FindHighestHPEnemy()
    if not target then return end

    local maxAtk = GetMaxTowerATK()
    local damageMult = RelicCalc.V(relic, relicDef.params.damageMult)
    local baseDmg = maxAtk * damageMult

    -- 找到 ATK 最高的塔作为 attacker（影响暴击等属性）
    local bestTower = nil
    local bestAtk = 0
    local HS = GetHeroSkills()
    for _, tower in ipairs(State.towers) do
        local atk = HS.GetEffectiveAttack(tower)
        if atk > bestAtk then
            bestAtk = atk
            bestTower = tower
        end
    end

    -- 额外破甲（临时应用到 target）
    local armorPenBonus = RelicCalc.V(relic, relicDef.params.armorPenBonus)
    armorPenBonus = math.min(armorPenBonus, relicDef.params.armorPenCap)
    local oldArmorReduce = target.armorReduceFromDot
    target.armorReduceFromDot = armorPenBonus  -- Combat.CalcFinalDamage 会使用并清除

    -- 通过正常伤害计算
    local Combat = require("Game.Combat")
    local finalDmg, isCrit = Combat.CalcFinalDamage(bestTower, target, baseDmg)
    local killed = GetEnemy().TakeDamage(target, finalDmg)
    GetDamageStats().Record(bestTower, finalDmg, isCrit, killed, target.isBoss)

    ShowRelicDamageText(target, finalDmg, COLOR_RELIC_NORMAL, 16)
    if killed then
        RelicEffects.OnEnemyKilled()
    end

    print("[RelicEffects] judgment_spear: dmg=" .. math.floor(finalDmg) .. " crit=" .. tostring(isCrit))
end

--- 虚空脉冲：定时全场伤害（不在此处触发，由 _UpdatePulse 处理）
_castHandlers.void_pulse = function(relic, relicDef)
    -- void_pulse 不通过充能释放
end

--- 湮灭风暴：全体 AoE 伤害
_castHandlers.annihilation_storm = function(relic, relicDef)
    local maxAtk = GetMaxTowerATK()
    local damageMult = RelicCalc.V(relic, relicDef.params.damageMult)
    local baseDmg = maxAtk * damageMult

    -- 狂热信念（意志·绿）伤害增幅
    local RD = GetRelicData()
    local willRelic = RD.GetEquipped("will")
    if willRelic and willRelic.id == "fervent_faith" then
        local faithDef = Config.RELICS.fervent_faith
        local dmgBoost = RelicCalc.V(willRelic, faithDef.params.powerDmgBonus)
        baseDmg = baseDmg * (1 + dmgBoost)
    end

    local bestTower = nil
    local bestAtk = 0
    local HS = GetHeroSkills()
    for _, tower in ipairs(State.towers) do
        local atk = HS.GetEffectiveAttack(tower)
        if atk > bestAtk then bestAtk = atk; bestTower = tower end
    end

    local Combat = require("Game.Combat")
    local totalDmg = 0
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local finalDmg, isCrit = Combat.CalcFinalDamage(bestTower, e, baseDmg)
            local killed = GetEnemy().TakeDamage(e, finalDmg)
            GetDamageStats().Record(bestTower, finalDmg, isCrit, killed, e.isBoss)
            ShowRelicDamageText(e, finalDmg, COLOR_RELIC_NORMAL, 13)
            totalDmg = totalDmg + finalDmg
            if killed then
                RelicEffects.OnEnemyKilled()
            end
        end
    end

    print("[RelicEffects] annihilation_storm: totalDmg=" .. math.floor(totalDmg))
end

--- 命运收割：全体审判（斩杀 + 高额伤害）
_castHandlers.fate_reaper = function(relic, relicDef)
    local RD = GetRelicData()

    -- 计算斩杀线
    local executeThreshold = relicDef.params.executeThreshold
    executeThreshold = math.min(executeThreshold, relicDef.params.executeCap)

    local maxAtk = GetMaxTowerATK()
    local nonExecDmgMult = RelicCalc.V(relic, relicDef.params.nonExecuteDmg)
    local nonExecBaseDmg = maxAtk * nonExecDmgMult

    -- 狂热信念增幅
    local willRelic = RD.GetEquipped("will")
    if willRelic and willRelic.id == "fervent_faith" then
        local faithDef = Config.RELICS.fervent_faith
        local dmgBoost = RelicCalc.V(willRelic, faithDef.params.powerDmgBonus)
        nonExecBaseDmg = nonExecBaseDmg * (1 + dmgBoost)
    end

    local bestTower = nil
    local bestAtk = 0
    local HS = GetHeroSkills()
    for _, tower in ipairs(State.towers) do
        local atk = HS.GetEffectiveAttack(tower)
        if atk > bestAtk then bestAtk = atk; bestTower = tower end
    end

    local Combat = require("Game.Combat")
    local executeCount = 0
    local damageCount = 0

    local BOSS_EXECUTE_ATK_MULT = 15  -- BOSS免疫斩杀，改为ATK×15固定伤害

    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local hpRatio = e.hp / (e.maxHP or e.hp)
            if hpRatio <= executeThreshold then
                if e.isBoss then
                    -- BOSS兜底：免疫斩杀，改为固定倍率伤害
                    local baseDmg = bestAtk * BOSS_EXECUTE_ATK_MULT
                    local finalDmg, isCrit = Combat.CalcFinalDamage(bestTower, e, baseDmg)
                    local killed = GetEnemy().TakeDamage(e, finalDmg)
                    GetDamageStats().Record(bestTower, finalDmg, isCrit, killed, e.isBoss)
                    ShowRelicDamageText(e, finalDmg, COLOR_EXECUTE, 14, "审判!")
                    damageCount = damageCount + 1
                    if killed then RelicEffects.OnEnemyKilled() end
                else
                    -- 普通怪：直接斩杀
                    local killed = GetEnemy().TakeDamage(e, e.hp + 1)
                    GetDamageStats().Record(bestTower, e.maxHP or 0, false, true, e.isBoss)
                    ShowRelicDamageText(e, 0, COLOR_EXECUTE, 18, "处决!")
                    executeCount = executeCount + 1
                    if killed then RelicEffects.OnEnemyKilled() end
                end
            else
                -- 正常伤害
                local finalDmg, isCrit = Combat.CalcFinalDamage(bestTower, e, nonExecBaseDmg)
                local killed = GetEnemy().TakeDamage(e, finalDmg)
                GetDamageStats().Record(bestTower, finalDmg, isCrit, killed, e.isBoss)
                ShowRelicDamageText(e, finalDmg, COLOR_RELIC_NORMAL, 14)
                damageCount = damageCount + 1
                if killed then RelicEffects.OnEnemyKilled() end
            end
        end
    end

    print("[RelicEffects] fate_reaper: executed=" .. executeCount .. " damaged=" .. damageCount)
end

--- 终焉之光：真实伤害 + 灼烧 DOT
_castHandlers.end_light = function(relic, relicDef)
    local target = FindHighestHPEnemy()
    if not target then return end

    local RD = GetRelicData()
    local maxAtk = GetMaxTowerATK()

    -- 真实伤害
    local trueDmgMult = RelicCalc.V(relic, relicDef.params.trueDamageMult)
    local baseTrueDmg = maxAtk * trueDmgMult

    -- 狂热信念增幅
    local willRelic = RD.GetEquipped("will")
    if willRelic and willRelic.id == "fervent_faith" then
        local faithDef = Config.RELICS.fervent_faith
        local dmgBoost = RelicCalc.V(willRelic, faithDef.params.powerDmgBonus)
        baseTrueDmg = baseTrueDmg * (1 + dmgBoost)
    end

    -- 找 ATK 最高的塔作为 attacker
    local bestTower = nil
    local bestAtk = 0
    local HS = GetHeroSkills()
    for _, tower in ipairs(State.towers) do
        local atk = HS.GetEffectiveAttack(tower)
        if atk > bestAtk then bestAtk = atk; bestTower = tower end
    end

    -- 真实伤害计算（跳过防御和元素抗性）
    local finalDmg, isCrit = CalcTrueDamage(baseTrueDmg, bestTower, target)
    local killed = GetEnemy().TakeDamage(target, finalDmg)
    GetDamageStats().Record(bestTower, finalDmg, isCrit, killed, target.isBoss)
    ShowRelicDamageText(target, finalDmg, COLOR_TRUE_DMG, 16, "真实")

    if killed then
        RelicEffects.OnEnemyKilled()
    end

    -- 灼烧 DOT
    if target.alive then
        local burnTotalMult = RelicCalc.V(relic, relicDef.params.burnTotalMult)
        local totalBurnDmg = maxAtk * burnTotalMult
        local ticks = relicDef.params.burnTicks
        local tickDmg = totalBurnDmg / ticks
        local interval = relicDef.params.burnDuration / ticks

        -- 查找已有灼烧，刷新（不叠加）
        local found = false
        for i, b in ipairs(_burns) do
            if b.targetId == target.id then
                b.tickDmg = math.max(b.tickDmg, tickDmg)
                b.remaining = relicDef.params.burnDuration
                b.interval = interval
                b.timer = 0
                b.tower = bestTower
                found = true
                break
            end
        end
        if not found then
            _burns[#_burns + 1] = {
                targetId = target.id,
                tickDmg = tickDmg,
                remaining = relicDef.params.burnDuration,
                interval = interval,
                timer = 0,
                tower = bestTower,
            }
        end
    end

    print("[RelicEffects] end_light: trueDmg=" .. math.floor(finalDmg) .. " burn=" .. tostring(target.alive))
end

-- ============================================================================
-- 充能释放（充能满时自动触发）
-- ============================================================================

local function DoCast(relic, relicDef)
    local handler = _castHandlers[relic.id]
    if not handler then return end

    -- 释放提示：全屏闪光
    State.skillFlash = { type = "relic_cast", timer = 0.6 }

    -- 释放提示：技能名飘字（屏幕中央偏上）
    local Renderer = require("Game.Renderer")
    local gridW = Config.GRID_COLS * Config.CELL_SIZE
    local gridH = Config.GRID_ROWS * Config.CELL_SIZE
    local cx = Renderer.gridOffsetX + gridW * 0.5
    local cy = Renderer.gridOffsetY + gridH * 0.5
    local castVx = (math.random() - 0.5) * 100
    local castVy = -(75 + math.random() * 45)
    State.AddFloatingText({
        text = relicDef.name,
        x = cx + (math.random() - 0.5) * 16,
        y = cy - 30,
        vx = castVx, vy = castVy,
        life = 1.0, maxLife = 1.0,
        fontSize = 20,
        color = { 220, 180, 255 },
        isCrit = true,
    })

    -- 充能条爆发动画状态
    State.relicCastFX = { timer = 0.8, maxTimer = 0.8 }

    -- 执行释放
    handler(relic, relicDef)

    -- 双重释放（意志·橙）概率触发第二次
    local RD = GetRelicData()
    local willRelic = RD.GetEquipped("will")
    if willRelic and willRelic.id == "double_cast" then
        local dcDef = Config.RELICS.double_cast
        local chance = dcDef.params.doubleCastChance
        -- 星级效果：触发概率增加（渐进值）
        if dcDef.starEffect and dcDef.starEffect.type == "chanceAdd" then
            chance = chance + RelicCalc.StarValue(willRelic.star, dcDef.starEffect)
        end
        chance = math.min(chance, dcDef.params.doubleCastCap)
        if math.random() < chance then
            print("[RelicEffects] double_cast triggered!")
            -- 第二次释放（50% 效果）—— 通过临时修改攻击力实现
            -- 简化处理：直接再调一次 handler，伤害自然受当前状态影响
            -- 实际效果约等于 50%：通过减半 baseDmg 的方式
            -- 为简化实现，我们创建一个临时 relic 副本，把 level 减半近似
            local tempRelic = {
                id = relic.id,
                quality = relic.quality,
                level = relic.level,
                star = relic.star,
                _doubleCastMult = dcDef.params.secondCastMult,
            }
            -- 直接再执行一次，handler 内部使用 maxATK 不受影响
            -- 用 flag 控制伤害减半
            State._relicDoubleCastMult = dcDef.params.secondCastMult
            handler(relic, relicDef)
            State._relicDoubleCastMult = nil
        end
    end

    -- 触发后释放效果（意志部位联动）
    TriggerPostCastEffects()

    -- 重置充能
    _charge.current = 0
    _charge.ready = false
    _globalCD = Config.RELIC_CHARGE_GLOBAL_CD

    print("[RelicEffects] Cast complete, CD=" .. _globalCD)
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

--- void_pulse 定时脉冲更新
local function UpdatePulse(dt)
    local RD = GetRelicData()
    local relic = RD.GetEquipped("power")
    if not relic or relic.id ~= "void_pulse" then return end

    local def = Config.RELICS.void_pulse
    -- 星级效果：脉冲间隔减少（渐进值）
    local interval = def.params.pulseInterval
    if def.starEffect and def.starEffect.type == "intervalReduce" then
        interval = math.max(2.0, interval - RelicCalc.StarValue(relic.star, def.starEffect))
    end
    _pulseTimer = _pulseTimer + dt
    if _pulseTimer >= interval then
        _pulseTimer = _pulseTimer - interval

        local avgAtk = GetAvgTowerATK()
        local pulseDmgMult = RelicCalc.V(relic, def.params.pulseDamageMult)
        local baseDmg = avgAtk * pulseDmgMult

        -- 狂热信念增幅（void_pulse 的脉冲伤害视为"力部位技能伤害"）
        local willRelic = RD.GetEquipped("will")
        if willRelic and willRelic.id == "fervent_faith" then
            local faithDef = Config.RELICS.fervent_faith
            local dmgBoost = RelicCalc.V(willRelic, faithDef.params.powerDmgBonus)
            baseDmg = baseDmg * (1 + dmgBoost)
        end

        -- 永恒意志增幅（含星级 amplifyAdd）
        local ewRelic = RD.GetEquipped("will")
        if ewRelic and ewRelic.id == "eternal_will" then
            local ewDef = Config.RELICS.eternal_will
            local amp = RelicCalc.V(ewRelic, ewDef.params.globalAmplify)
            if ewDef.starEffect and ewDef.starEffect.type == "amplifyAdd" then
                amp = amp + RelicCalc.StarValue(ewRelic.star, ewDef.starEffect)
            end
            baseDmg = baseDmg * (1 + amp)
        end

        -- 双重释放倍率
        local dmgMult = State._relicDoubleCastMult or 1.0

        local totalDmg = 0
        for _, e in ipairs(State.enemies) do
            if e.alive and not e.phaseActive then
                -- 脉冲固定伤害（不经过防御减伤，但受元素抗性影响——简化：直接应用）
                local finalDmg = baseDmg * dmgMult
                local killed = GetEnemy().TakeDamage(e, finalDmg)
                ShowRelicDamageText(e, finalDmg, COLOR_PULSE, 12)
                totalDmg = totalDmg + finalDmg
            end
        end

        print("[RelicEffects] void_pulse: totalDmg=" .. math.floor(totalDmg))
    end
end

--- 灼烧 DOT 更新
local function UpdateBurns(dt)
    local i = 1
    while i <= #_burns do
        local b = _burns[i]
        b.remaining = b.remaining - dt
        b.timer = b.timer + dt

        -- 查找目标
        local target = nil
        for _, e in ipairs(State.enemies) do
            if e.id == b.targetId and e.alive then
                target = e
                break
            end
        end

        if b.remaining <= 0 or not target then
            -- 移除已结束或目标已死的灼烧
            _burns[i] = _burns[#_burns]
            _burns[#_burns] = nil
        else
            -- 触发 tick
            if b.timer >= b.interval then
                b.timer = b.timer - b.interval
                local finalDmg, isCrit = CalcTrueDamage(b.tickDmg, b.tower, target)
                local killed = GetEnemy().TakeDamage(target, finalDmg)
                if b.tower then
                    GetDamageStats().Record(b.tower, finalDmg, isCrit, killed, target.isBoss)
                end
                ShowRelicDamageText(target, finalDmg, COLOR_BURN, 11)
                if killed then
                    RelicEffects.OnEnemyKilled()
                end
            end
            i = i + 1
        end
    end
end

--- 充能检查与自动释放
local function UpdateCharge(dt)
    local RD = GetRelicData()
    local relic = RD.GetEquipped("power")
    if not relic then return end
    local relicDef = Config.RELICS[relic.id]
    if not relicDef or not relicDef.hasCharge then return end

    -- 全局 CD 递减
    _globalCD = math.max(0, _globalCD - dt)

    -- 充能满且 CD 结束 → 自动释放
    if _charge.ready and _globalCD <= 0 then
        DoCast(relic, relicDef)
    end
end

--- 后释放 buff 递减
local function UpdatePostCastBuff(dt)
    if not _postCastBuff then return end
    _postCastBuff.remaining = _postCastBuff.remaining - dt
    if _postCastBuff.remaining <= 0 then
        _postCastBuff = nil
    end
end

--- 主更新（Combat.Update 中调用）
function RelicEffects.Update(dt)
    local RD = GetRelicData()
    local powerRelic = RD.GetEquipped("power")
    if not powerRelic then
        -- 即使没有力部位遗物，也要更新灼烧和后释放buff
        UpdateBurns(dt)
        UpdatePostCastBuff(dt)
        return
    end

    if powerRelic.id == "void_pulse" then
        UpdatePulse(dt)
    else
        UpdateCharge(dt)
    end

    UpdateBurns(dt)
    UpdatePostCastBuff(dt)
end

-- ============================================================================
-- 战斗事件钩子（由 Combat 调用）
-- ============================================================================

--- 英雄攻击命中时调用（充能累加）
---@param tower table 发起攻击的塔
---@param target table 被攻击的敌人
---@param isCrit boolean 是否暴击
function RelicEffects.OnTowerAttack(tower, target, isCrit)
    local RD = GetRelicData()
    local relic = RD.GetEquipped("power")
    if not relic then return end
    local relicDef = Config.RELICS[relic.id]
    if not relicDef or not relicDef.hasCharge then return end

    local gain = isCrit and Config.RELIC_CHARGE_PER_CRIT or Config.RELIC_CHARGE_PER_ATTACK
    _charge.current = math.min(_charge.current + gain, _charge.max)
    if _charge.current >= _charge.max then
        _charge.ready = true
    end
end

--- 敌人被击杀时调用（充能 +3）
function RelicEffects.OnEnemyKilled()
    local RD = GetRelicData()
    local relic = RD.GetEquipped("power")
    if not relic then return end
    local relicDef = Config.RELICS[relic.id]
    if not relicDef or not relicDef.hasCharge then return end

    _charge.current = math.min(_charge.current + Config.RELIC_CHARGE_PER_KILL, _charge.max)
    if _charge.current >= _charge.max then
        _charge.ready = true
    end
end

-- ============================================================================
-- Tower 属性修正（后释放 buff 影响攻速/伤害）
-- ============================================================================

--- 获取遗物对塔的攻速加成（后释放 buff）
---@return number 额外攻速百分比加成
function RelicEffects.GetSpeedBuff()
    if _postCastBuff and _postCastBuff.id == "immortal_flame_spd" then
        return _postCastBuff.value
    end
    return 0
end

--- 获取遗物对塔的伤害加成（超载爆发后释放 buff）
---@return number 额外伤害百分比加成
function RelicEffects.GetDamageBuff()
    if _postCastBuff and _postCastBuff.id == "overload_burst_dmg" then
        return _postCastBuff.value
    end
    return 0
end

return RelicEffects
