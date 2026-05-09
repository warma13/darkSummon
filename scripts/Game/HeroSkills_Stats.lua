-- Game/HeroSkills_Stats.lua
-- 属性计算与工具函数：GetEffective* / CheckCritSplash / Star缩放 / HasSkill
-- 从 HeroSkills.lua 拆分，注入到 HeroSkills 表

local Config = require("Game.Config")
local State  = require("Game.State")

local AddFloatingText = State.AddFloatingText
local COLOR_STUN = { 255, 220, 60, 255 }

-- 延迟 require（避免循环依赖）
local _Enemy, _CostumeData, _Debuff, _Tower, _TitleData
local function GetEnemy()
    if not _Enemy then _Enemy = require("Game.Enemy") end
    return _Enemy
end
local function GetDebuff()
    if not _Debuff then _Debuff = require("Game.Debuff") end
    return _Debuff
end
local function GetCostumeData()
    if not _CostumeData then _CostumeData = require("Game.CostumeData") end
    return _CostumeData
end
local function GetTower()
    if not _Tower then _Tower = require("Game.Tower") end
    return _Tower
end
local function GetTitleData()
    if not _TitleData then _TitleData = require("Game.TitleData") end
    return _TitleData
end

--- 注入属性计算函数到 HeroSkills 表
---@param HeroSkills table
return function(HeroSkills)

-- ============================================================================
-- 星级缩放系数
-- ============================================================================

--- 根据英雄星级计算缩放系数：0星→10%，满星→100%
---@param heroStar number  0-30
---@return number  0.10 ~ 1.00
function HeroSkills.GetStarScaleFactor(heroStar)
    local maxStar = Config.MAX_HERO_STAR or 30
    return 0.10 + 0.90 * math.sqrt(math.min(heroStar, maxStar) / maxStar)
end

-- ============================================================================
-- 工具函数
-- ============================================================================

---@param tower table
---@param skillId string
---@return table|nil
function HeroSkills.HasSkill(tower, skillId)
    if not tower.skills then return nil end
    for _, skill in ipairs(tower.skills) do
        if skill.id == skillId then return skill end
    end
    return nil
end

-- ============================================================================
-- 眩晕
-- ============================================================================

---@param target table
---@param duration number
function HeroSkills.ApplyStun(target, duration)
    if GetDebuff().IsImmune(target, "stun") then return end
    if target.isBoss then
        duration = duration * (Config.BOSS_BALANCE.stunDurationMult or 0.50)
    end
    if not target.stunTimer or target.stunTimer <= 0 then
        AddFloatingText({
            text     = "眩晕",
            x        = target.x + (math.random() - 0.5) * 10,
            y        = target.y - (target.typeDef.size or 8) - 16,
            life     = 0.6,
            color    = COLOR_STUN,
            fontSize = 12,
        })
    end
    GetDebuff().Apply(target, "stun", { duration = duration })
end

-- ============================================================================
-- 获取塔最终攻击力
-- ============================================================================

---@param tower table
---@return number
function HeroSkills.GetEffectiveAttack(tower)
    local Tower = GetTower()
    local baseAtk = Tower.GetEffectiveAttack(tower)

    -- 加算桶：所有百分比加成先相加，再一次性乘算
    local pctBucket = 0
    if tower.auraAtkBuff and tower.auraAtkBuff > 0 then
        pctBucket = pctBucket + tower.auraAtkBuff
    end
    if State.heroicAnthemBuff then
        pctBucket = pctBucket + State.heroicAnthemBuff.atkMult
    end
    local CD    = GetCostumeData()
    local bonus = CD.GetGlobalAtkBonus()
    if bonus > 0 then pctBucket = pctBucket + bonus end
    -- 称号攻击加成
    local TD = GetTitleData()
    if TD then
        local titleAtk = TD.GetGlobalAtkBonus()
        if titleAtk > 0 then pctBucket = pctBucket + titleAtk end
    end
    local hs = tower.hstate
    if hs and hs.wreathActive and hs.wreathBonus and hs.wreathBonus > 0 then
        pctBucket = pctBucket + hs.wreathBonus
    end
    if hs and hs.resonanceAtkBonus and hs.resonanceAtkBonus > 0 then
        pctBucket = pctBucket + hs.resonanceAtkBonus
    end

    -- 标签系统：攻击力加成（v1.0.82）
    if State.tagWarCryBuff and State.tagWarCryBuff.timer > 0 then
        pctBucket = pctBucket + State.tagWarCryBuff.atkMult
    end
    if hs and hs.killDmgStacks and hs.killDmgStacks > 0 and hs.killDmgBonus then
        pctBucket = pctBucket + hs.killDmgStacks * hs.killDmgBonus
    end

    local atk = baseAtk * (1 + pctBucket)

    -- 固定值加成（加法）
    if hs and hs.natureFlatAtk and hs.natureFlatAtk > 0 then
        atk = atk + hs.natureFlatAtk
    end

    return atk
end

-- ============================================================================
-- 获取塔最终攻速
-- ============================================================================

---@param tower table
---@return number
function HeroSkills.GetEffectiveSpeed(tower)
    local Tower = GetTower()
    return HeroSkills.ModifyAttackSpeed(tower, Tower.GetEffectiveSpeed(tower))
end

-- ============================================================================
-- 获取塔最终暴击率
-- ============================================================================

---@param tower table
---@return number
function HeroSkills.GetEffectiveCritRate(tower)
    local Tower = GetTower()
    local rate = Tower.GetEffectiveCritRate(tower)
    if tower.auraCritRateBuff and tower.auraCritRateBuff > 0 then
        rate = rate + tower.auraCritRateBuff
    end
    local hs2 = tower.hstate
    if hs2 then
        if hs2.bonusCritRate and hs2.bonusCritRate > 0 then
            rate = rate + hs2.bonusCritRate
        end
    end

    -- 标签系统：暴击率加成（v1.0.82）
    if tower.tagCritRateBonus and tower.tagCritRateBonus > 0 then
        rate = rate + tower.tagCritRateBonus
    end
    if tower.tagInfernalCritRate and tower.tagInfernalCritRate > 0 then
        rate = rate + tower.tagInfernalCritRate
    end
    if tower.tagGuaranteedCrit then
        rate = 1.0
    end

    return rate
end

-- ============================================================================
-- 获取有效暴击伤害
-- ============================================================================

--- 集中函数：基础 + 技能叠层 + 光环 + 标签
---@param tower table
---@return number
function HeroSkills.GetEffectiveCritDmg(tower)
    local Tower = GetTower()
    local critDmg = Tower.GetEffectiveCritDmg(tower)
    local hs = tower.hstate
    if hs and hs.bonusCritDmg and hs.bonusCritDmg > 0 then
        critDmg = critDmg + hs.bonusCritDmg
    end
    if tower.auraCritDmgBuff and tower.auraCritDmgBuff > 0 then
        critDmg = critDmg + tower.auraCritDmgBuff
    end
    if tower.tagCritDmgBonus and tower.tagCritDmgBonus > 0 then
        critDmg = critDmg + tower.tagCritDmgBonus
    end
    if tower.tagInfernalCritDmg and tower.tagInfernalCritDmg > 0 then
        critDmg = critDmg + tower.tagInfernalCritDmg
    end
    return critDmg
end

-- ============================================================================
-- 获取有效伤害加成
-- ============================================================================

--- 集中函数：基础 + 技能叠层
---@param tower table
---@return number
function HeroSkills.GetEffectiveDmgBonus(tower)
    local Tower = GetTower()
    local dmgBonus = Tower.GetEffectiveDmgBonus(tower)
    local hs = tower.hstate
    if hs and hs.bonusDmgBonus and hs.bonusDmgBonus > 0 then
        dmgBonus = dmgBonus + hs.bonusDmgBonus
    end
    return dmgBonus
end

-- ============================================================================
-- 命运终章（暴击溅射）
-- ============================================================================

---@param tower table
---@param target table
---@param damage number
function HeroSkills.CheckCritSplash(tower, target, damage)
    -- 命运织者 fate_finale
    for _, t in ipairs(State.towers) do
        local splash = HeroSkills.HasSkill(t, "fate_finale")
        if splash then
            local splashDmg = damage * (splash.critSplashPct or 0.50)
            local Enemy = GetEnemy()
            for _, e in ipairs(State.enemies) do
                if e.alive and e ~= target then
                    local dx = e.x - target.x
                    local dy = e.y - target.y
                    if dx * dx + dy * dy < 3600 then -- 60²
                        Enemy.TakeDamage(e, splashDmg)
                    end
                end
            end
            break
        end
    end

    -- 符文套装：雷霆 set3 — 暴击时溅射
    if tower.runeSetEffects then
        for _, eff in ipairs(tower.runeSetEffects) do
            if eff.effect == "crit_splash" then
                local splashDmg = damage * (eff.splashPct or 0.30)
                local Enemy = GetEnemy()
                for _, e in ipairs(State.enemies) do
                    if e.alive and e ~= target then
                        local dx = e.x - target.x
                        local dy = e.y - target.y
                        if dx * dx + dy * dy < 2500 then -- 50²
                            Enemy.TakeDamage(e, splashDmg)
                        end
                    end
                end
                break
            end
        end
    end
end

end -- return function(HeroSkills)
