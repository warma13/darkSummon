-- Game/HeroUI/HeroDetail/StatEngine.lua
-- 英雄属性计算引擎 + UI 工具函数

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local HeroSkills = require("Game.HeroSkills")

local StatEngine = {}

-- ============================================================================
-- UI 工具函数
-- ============================================================================

--- 格式化属性值为显示字符串
---@param value number|string
---@param fmt string|nil  "pct"=百分比, nil=整数/大数
---@return string
function StatEngine.FormatStatValue(value, fmt)
    if fmt == "pct" then
        return string.format("%.1f%%", (value or 0) * 100)
    elseif type(value) == "number" then
        local FormatBigNum = require("Game.HeroUI").FormatBigNum
        return FormatBigNum(value)
    else
        return tostring(value)
    end
end

--- 创建属性行
---@param UI any
---@param S table
---@param label string
---@param value number|string
---@param color table|nil
---@param fmt string|nil  "pct"=百分比, nil=整数
---@param valueId string|nil  可选 id，用于 FindById 增量更新
function StatEngine.CreateStatRow(UI, S, label, value, color, fmt, valueId)
    local display = StatEngine.FormatStatValue(value, fmt)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 4, paddingBottom = 4,
        children = {
            UI.Label { text = label, fontSize = 13, fontColor = S.dim },
            UI.Label { id = valueId, text = display, fontSize = 13, fontColor = color or S.white, fontWeight = "bold" },
        },
    }
end

--- 创建技能图标
--- @param UI any
--- @param skillDef table
--- @param unlocked boolean
--- @param selected boolean
--- @param onClick function|nil
function StatEngine.CreateSkillIcon(UI, skillDef, unlocked, selected, onClick)
    local typeTag = skillDef.type == "active" and "主" or "被"
    local tagColor = skillDef.type == "active" and { 220, 70, 50, 255 } or { 80, 160, 60, 255 }
    local bgColor = unlocked and { 60, 48, 36, 255 } or { 40, 35, 30, 200 }
    local borderCol = (selected and unlocked) and { 255, 200, 80, 255 }
        or (unlocked and { 120, 95, 65, 200 } or { 60, 50, 40, 150 })
    local textAlpha = unlocked and 255 or 100
    local borderW = selected and 3 or 2

    return UI.Panel {
        alignItems = "center",
        gap = 3,
        width = 56,
        onClick = onClick,
        children = {
            -- 圆形技能图标
            UI.Panel {
                width = 42, height = 42,
                borderRadius = 21,
                backgroundColor = bgColor,
                borderWidth = borderW,
                borderColor = borderCol,
                justifyContent = "center", alignItems = "center",
                opacity = unlocked and 1.0 or 0.5,
                children = {
                    UI.Label {
                        text = string.sub(skillDef.name, 1, 6),
                        fontSize = 10,
                        fontColor = { 255, 255, 255, textAlpha },
                        textAlign = "center",
                    },
                    -- 主/被 角标
                    UI.Panel {
                        position = "absolute",
                        top = -2, right = -2,
                        width = 16, height = 16,
                        borderRadius = 8,
                        backgroundColor = tagColor,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = typeTag, fontSize = 8, fontColor = { 255, 255, 255, 240 }, fontWeight = "bold" },
                        },
                    },
                },
            },
            -- 技能名
            UI.Label {
                text = skillDef.name,
                fontSize = 9,
                fontColor = { 255, 255, 255, textAlpha },
                textAlign = "center",
            },
        },
    }
end

-- ============================================================================
-- 统一属性计算（header 战力 + BuildInfoTab 共用）
-- ============================================================================

--- 计算英雄全量属性（含装备/神裔/遗物/技能/标签/词条/称号）
--- 基础层（装备/神裔/遗物/词条/图鉴）委托 Tower.BuildStaticPreview（SSOT），
--- 本函数只叠加"预览层"：技能被动 + 友军光环 + 称号 + 元素伤害
---@param heroId string
---@return table stats  完整属性表
function StatEngine.ComputeFullStats(heroId)
    local Tower = require("Game.Tower")

    -- ① 基础层：BuildStaticPreview 覆盖装备+神裔+遗物+词条标签+图鉴
    local mock = Tower.BuildStaticPreview(heroId)
    if not mock then
        -- fallback: 仅返回裸属性
        local fallback = HeroData.GetHeroStats(heroId)
        fallback.atkSpeedDisplay = "0/s"; fallback.atkSpeedValue = 0; fallback.power = fallback.atk or 0
        return fallback
    end

    local stats = {}
    stats.atk      = mock.attack
    stats.critRate = mock.critRate or 0
    stats.critDmg  = mock.critDmg or 0
    -- 穿透：根据伤害类型选择物理穿甲或法术穿透
    local heroDmgType0 = Config.HERO_DAMAGE_TYPE[heroId] or "physical"
    if heroDmgType0 == "magical" then
        stats.penValue = mock.magicPen or 0
        stats.penLabel = "法穿"
    else
        stats.penValue = mock.armorPen or 0
        stats.penLabel = "穿甲"
    end
    stats.dmgBonus = mock.dmgBonus or 0

    -- ② 技能被动加成（带星级缩放，非光环类 passive）
    local h0 = HeroData.heroes and HeroData.heroes[heroId]
    local heroStar0 = (h0 and h0.star) or 0
    local maxStar0  = Config.MAX_HERO_STAR or 30
    local skillStarScale = 0.10 + 0.90 * math.sqrt(math.min(heroStar0, maxStar0) / maxStar0)
    local skillCritRate, skillCritDmg, skillSpdBonus = 0, 0, 0
    local skillDefs0 = Config.HERO_SKILLS and Config.HERO_SKILLS[heroId] or {}
    for _, skill in ipairs(skillDefs0) do
        if skill.type == "passive" and not skill.auraRange then
            local sf = (skill.starScale and skillStarScale) or 1.0
            skillCritRate  = skillCritRate  + (skill.critRate or 0) * sf
            skillCritDmg   = skillCritDmg  + (skill.critDmg or 0) * sf
            skillSpdBonus  = skillSpdBonus + (skill.atkSpdBonus or 0) * sf
        end
    end

    -- ③ 友军光环加成（遍历已部署英雄收集 aura 效果）
    local auraCritRate, auraCritDmg, auraSpdBonus = 0, 0, 0
    do
        local allOnBoard = {}
        local leaderId = Config.LEADER_HERO and Config.LEADER_HERO.id
        if leaderId and leaderId ~= heroId then
            allOnBoard[#allOnBoard + 1] = leaderId
        end
        if HeroData.deployed then
            for _, did in ipairs(HeroData.deployed) do
                if did ~= heroId then
                    allOnBoard[#allOnBoard + 1] = did
                end
            end
        end

        for _, allyId in ipairs(allOnBoard) do
            local allyH = HeroData.heroes and HeroData.heroes[allyId]
            if allyH then
                local allyStar = allyH.star or 0
                local allyScale = 0.10 + 0.90 * math.sqrt(math.min(allyStar, maxStar0) / maxStar0)

                -- 光环型 passive 技能
                local allySkills = Config.HERO_SKILLS and Config.HERO_SKILLS[allyId] or {}
                for _, sk in ipairs(allySkills) do
                    if sk.type == "passive" and sk.auraRange then
                        local sf = (sk.starScale and allyScale) or 1.0
                        auraCritRate  = auraCritRate  + (sk.critRate or 0) * sf
                        auraCritDmg   = auraCritDmg   + (sk.critDmg or 0) * sf
                        auraSpdBonus  = auraSpdBonus  + (sk.atkSpdBonus or 0) * sf
                    end
                end

                -- aura 类型 tag（buff_aura）
                local allyTags = Config.HERO_SKILL_TAGS and Config.HERO_SKILL_TAGS[allyId]
                if allyTags then
                    for _, atDef in ipairs(allyTags) do
                        if atDef.type == "aura" and atDef.category == "buff_aura" then
                            local aTier = HeroData.GetTagTier(allyId, atDef.id)
                            local aUnlocked = HeroData.IsTagUnlocked(allyId, atDef)
                            local aReqMet = true
                            if atDef.requires then
                                for _, rId in ipairs(atDef.requires) do
                                    if HeroData.GetTagTier(allyId, rId) <= 0 then aReqMet = false; break end
                                end
                            end
                            if (aUnlocked and aReqMet) and aTier > 0 then
                                local aEff = atDef.effects and atDef.effects[aTier]
                                if aEff then
                                    auraCritRate = auraCritRate + (aEff.critRateBuff or 0)
                                    auraCritDmg  = auraCritDmg  + (aEff.critDmgBuff or 0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 叠加技能/光环到基础属性
    stats.critRate = stats.critRate + skillCritRate + auraCritRate
    stats.critDmg  = stats.critDmg  + skillCritDmg  + auraCritDmg

    -- ④ 称号加成
    local okTD, TitleDataMod = pcall(require, "Game.TitleData")
    local spdBonusTitle = 0
    if okTD and TitleDataMod then
        local tAtk = TitleDataMod.GetGlobalAtkBonus and TitleDataMod.GetGlobalAtkBonus() or 0
        if tAtk > 0 then stats.atk = stats.atk * (1 + tAtk) end
        local tSpd = TitleDataMod.GetGlobalSpdBonus and TitleDataMod.GetGlobalSpdBonus() or 0
        if tSpd > 0 then spdBonusTitle = tSpd end
    end

    -- ⑤ 类型伤害（装备来源：typeDmg + elemDmg → 路由到英雄伤害类型）
    local EquipData = require("Game.EquipData")
    local eqBonus = EquipData.GetTotalBonus(heroId)
    local heroDmgType = Config.HERO_DAMAGE_TYPE[heroId]
    local elemTotal = (eqBonus.elemDmg or 0) + (eqBonus.typeDmg or 0)
    if heroDmgType and elemTotal > 0 then
        stats.elemDmgBonus = stats.elemDmgBonus or {}
        stats.elemDmgBonus[heroDmgType] = (stats.elemDmgBonus[heroDmgType] or 0) + elemTotal
    end

    -- ⑥ 攻速：mock.speed 已含基础+装备+神裔+遗物+词条层，再叠技能/光环/称号
    local extraSpdFactor = skillSpdBonus + auraSpdBonus + spdBonusTitle
    local finalSpeed = mock.speed
    if extraSpdFactor > 0 then
        finalSpeed = finalSpeed / (1 + extraSpdFactor)
    end
    stats.atkSpeedDisplay = string.format("%.2f/s", 1 / finalSpeed)
    stats.atkSpeedValue   = 1 / finalSpeed

    -- ⑦ 战力
    stats.power = stats.atk + stats.atkSpeedValue

    return stats
end

-- ============================================================================
-- 运行时属性查询（战斗中从 State.towers 获取实时数据）
-- ============================================================================

--- 从 State.towers 中查找英雄对应的 tower 实例
---@param heroId string
---@return table|nil tower
local function FindTowerByHeroId(heroId)
    local ok, State = pcall(require, "Game.State")
    if not ok or not State or not State.towers then return nil end
    for _, tower in ipairs(State.towers) do
        if tower and tower.typeDef and tower.typeDef.id == heroId then
            return tower
        end
    end
    return nil
end

--- 获取英雄运行时属性（优先从 tower 实例取实时值，未上场 fallback 到静态计算）
---@param heroId string
---@return table stats
---@return boolean isRuntime
function StatEngine.GetRuntimeStats(heroId)
    local tower = FindTowerByHeroId(heroId)
    if not tower then
        return StatEngine.ComputeFullStats(heroId), false
    end

    local Tower = require("Game.Tower")
    local stats = {}

    -- 攻击力（含光环/全局/皮肤/称号/击杀叠加/自然平攻等）
    stats.atk = HeroSkills.GetEffectiveAttack(tower)

    -- 攻速（含光环/技能加速等）
    local interval = HeroSkills.GetEffectiveSpeed(tower)
    stats.atkSpeedDisplay = string.format("%.2f/s", 1.0 / interval)
    stats.atkSpeedValue = 1.0 / interval

    -- 暴击率（含光环/技能/标签加成）
    stats.critRate = HeroSkills.GetEffectiveCritRate(tower)

    -- 暴击伤害/穿透/伤害加成
    stats.critDmg  = HeroSkills.GetEffectiveCritDmg(tower)

    -- 穿透：根据伤害类型选择物理穿甲或法术穿透
    local heroDmgTypeRT = Config.HERO_DAMAGE_TYPE[heroId] or "physical"
    if heroDmgTypeRT == "magical" then
        stats.penValue = Tower.GetEffectiveMagicPen(tower)
        stats.penLabel = "法穿"
    else
        stats.penValue = Tower.GetEffectiveArmorPen(tower)
        stats.penLabel = "穿甲"
    end
    stats.dmgBonus = HeroSkills.GetEffectiveDmgBonus(tower)

    -- 元素伤害加成（从静态数据获取，运行时不变）
    local dmgTypeId = Config.HERO_DAMAGE_TYPE[heroId]
    if dmgTypeId then
        local staticStats = StatEngine.ComputeFullStats(heroId)
        stats.elemDmgBonus = staticStats.elemDmgBonus
    end

    -- 战力 = 攻击力 + 攻速数值
    stats.power = stats.atk + stats.atkSpeedValue

    return stats, true
end

return StatEngine
