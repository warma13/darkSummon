------------------------------------------------------------------------
-- HeroDPS.lua  —  英雄有效 DPS 计算器
-- 组合 HeroProfile (ATK/SPD) + MonsterEHP (7-zone 伤害链)
-- 输出: rawDPS, effectiveDPS, kill-time, DPS/EHP 比率
------------------------------------------------------------------------
local HeroDPS = {}

local HeroProfile = require "Balance.HeroProfile"
local MonsterEHP  = require "Balance.MonsterEHP"

------------------------------------------------------------
-- 核心: 计算有效 DPS
------------------------------------------------------------

--- 完整计算: 给定英雄参数 + 怪物参数，返回有效 DPS 报告
---@param heroParams table   HeroProfile.Build 的参数
---@param monsterParams table MonsterEHP.Calc 的参数 (armorPen/critRate 等可省略，自动从 profile 填充)
---@return table
function HeroDPS.Calc(heroParams, monsterParams)
    -- 1. 构建英雄属性快照
    local profile = HeroProfile.Build(heroParams)

    -- 2. 用英雄属性填充怪物参数中缺失的战斗属性
    local mp = {}
    for k, v in pairs(monsterParams or {}) do
        mp[k] = v
    end
    -- 传递英雄每击伤害, 用于 Diminishing DEF 公式
    if mp.heroDamage == nil then mp.heroDamage = profile.finalAtk end
    -- 自动继承英雄副属性
    if mp.armorPen == nil then mp.armorPen = profile.armorPen end
    if mp.critRate == nil then mp.critRate = profile.critRate end
    if mp.critDmg  == nil then mp.critDmg  = profile.critDmg end
    if mp.dmgBonus == nil then mp.dmgBonus = profile.dmgBonus end
    if mp.elemDmg  == nil then mp.elemDmg  = profile.elemDmg end
    if mp.elemMastery == nil then mp.elemMastery = profile.elemMastery end
    if mp.heroElement == nil then mp.heroElement = profile.element end

    -- 3. 计算怪物有效生命
    local monster = MonsterEHP.Calc(mp)

    -- 4. raw DPS (无任何怪物减伤)
    local rawDPS = profile.finalAtk / profile.attackInterval

    -- 5. effective DPS = rawDPS × 各增伤乘区 / DEF 乘区
    -- 注意: DEF 不在 totalDmgMult 中，需要单独处理
    -- effectiveDPS = rawDPS × totalDmgMult / defFactor
    -- 但 EHP 那边已经把 defFactor 算进去了 (EHP = rawHP × defFactor / totalDmgMult)
    -- 所以: killTime = EHP / rawDPS = rawHP × defFactor / (totalDmgMult × rawDPS)
    -- 等价: effectiveDPS = rawDPS × totalDmgMult / defFactor
    local effectiveDPS = rawDPS * monster.totalDmgMult / monster.defFactor

    -- 6. 击杀时间
    local killTime = monster.effectiveHP / rawDPS

    -- 7. DPS / EHP 比率 (> 1 表示英雄一秒内可击杀)
    local dpsEhpRatio = rawDPS / monster.effectiveHP

    return {
        -- 英雄属性
        profile = profile,

        -- 怪物属性
        monster = monster,

        -- DPS 结果
        rawDPS       = rawDPS,
        effectiveDPS = effectiveDPS,
        killTime     = killTime,
        dpsEhpRatio  = dpsEhpRatio,

        -- 各乘区明细 (方便报表)
        zones = {
            { name = "DEF穿透",   value = 1 / monster.defFactor,        desc = string.format("DEF=%.0f, pen=%.1f%%, through=%.2f%%", monster.rawDEF, monster.effectivePen * 100, 1 / monster.defFactor * 100) },
            { name = "暴击期望",  value = monster.critExpMult,           desc = string.format("rate=%.0f%%, dmg=%.0f%%", (mp.critRate or 0) * 100, (mp.critDmg or 0) * 100) },
            { name = "元素抗性",  value = monster.elemResistFactor,      desc = string.format("resist=%.0f%%", (1 - monster.elemResistFactor) * 100) },
            { name = "伤害加成",  value = monster.dmgBonusMult,          desc = string.format("bonus=%.0f%%", (mp.dmgBonus or 0) * 100) },
            { name = "元素伤害",  value = monster.elemDmgMult,           desc = string.format("elem=%.0f%%", (mp.elemDmg or 0) * 100) },
            { name = "冰冻增幅",  value = monster.chillMult,             desc = "default 1.0" },
            { name = "易伤标记",  value = monster.vulnMult,              desc = "default 1.0" },
        },
    }
end

------------------------------------------------------------
-- 便捷: 快速 DPS (只关注 ATK/SPD，忽略怪物减伤)
------------------------------------------------------------
function HeroDPS.RawDPS(heroParams)
    local profile = HeroProfile.Build(heroParams)
    return profile.finalAtk / profile.attackInterval, profile
end

return HeroDPS
