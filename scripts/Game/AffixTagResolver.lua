-- Game/AffixTagResolver.lua
-- 三层词条条件匹配引擎
-- 在 Tower.RefreshAllStats 和 HeroSkills.ApplyTag 中调用
-- 负责：收集词条 → 条件匹配 → 计算加成

local Config = require("Game.Config")

local AffixTagResolver = {}

-- ============================================================================
-- 收集英雄身上所有生效的三层词条
-- 来源：符文词条 + 淬炼词条 + 装备套装
-- ============================================================================
---@param heroId string 英雄类型 id
---@return table[] affixes  { id, value, value2?, source }
function AffixTagResolver.CollectAffixes(heroId)
    local affixes = {}

    -- 1) 符文词条
    local RuneData = rawget(_G, "RuneData")
    if RuneData and RuneData.GetEquippedRunes then
        local runes = RuneData.GetEquippedRunes(heroId)
        if runes then
            for _, rune in ipairs(runes) do
                if rune.affixes then
                    for _, af in ipairs(rune.affixes) do
                        local def = Config.AFFIX_TAG_LOOKUP[af.id]
                        if def then
                            affixes[#affixes + 1] = {
                                id     = af.id,
                                value  = af.value or 0,
                                value2 = af.value2,
                                source = "rune",
                            }
                        end
                    end
                end
            end
        end
    end

    -- 2) 淬炼词条
    local TemperData = rawget(_G, "TemperData")
    if TemperData and TemperData.GetTemperStats then
        local stats = TemperData.GetTemperStats(heroId)
        if stats then
            for _, st in ipairs(stats) do
                local def = Config.AFFIX_TAG_LOOKUP[st.id]
                if def then
                    affixes[#affixes + 1] = {
                        id     = st.id,
                        value  = st.value or 0,
                        value2 = st.value2,
                        source = "temper",
                    }
                end
            end
        end
    end

    -- 3) 装备套装加成
    local EquipData = rawget(_G, "EquipData")
    if EquipData and EquipData.GetEquipSetTier then
        local setTier = EquipData.GetEquipSetTier(heroId)
        local setBonus = Config.EQUIP_SET_AFFIX_BONUS and Config.EQUIP_SET_AFFIX_BONUS[setTier]
        if setBonus then
            for stat, val in pairs(setBonus) do
                affixes[#affixes + 1] = {
                    id     = "equip_set_" .. stat,
                    value  = val,
                    source = "equip_set",
                    -- 套装泛效果：标记为特殊处理
                    _setBonus = true,
                    _stat     = stat,
                }
            end
        end
    end

    return affixes
end

-- ============================================================================
-- 核心：计算一个英雄在当前词条加成下的总增幅
-- ============================================================================
---@param tower table 英雄实例（含 typeDef, tags 等）
---@param affixes table[] 由 CollectAffixes 返回的词条列表
---@return table bonus  { [stat] = value }
function AffixTagResolver.Resolve(tower, affixes)
    local bonus = {}
    local heroId    = tower.typeDef and tower.typeDef.id or ""
    local heroRoles = Config.HERO_ROLE and Config.HERO_ROLE[heroId] or {}
    local heroTags  = tower.tags or {}

    for _, affix in ipairs(affixes) do
        -- 套装泛效果：直接加到对应 stat
        if affix._setBonus then
            bonus[affix._stat] = (bonus[affix._stat] or 0) + affix.value
            goto continue
        end

        local def = Config.AFFIX_TAG_LOOKUP[affix.id]
        if not def then goto continue end

        if def.tier == 1 then
            -- 第1层：检查英雄角色定位是否匹配
            if AffixTagResolver._matchRoles(heroRoles, def.roles) then
                bonus[def.stat] = (bonus[def.stat] or 0) + affix.value
            end

        elseif def.tier == 2 then
            -- 第2层：检查英雄是否拥有匹配类型的已解锁技能标签
            if AffixTagResolver._matchSkillTypes(heroId, heroTags, def.skillTypes) then
                bonus[def.stat] = (bonus[def.stat] or 0) + affix.value
                if def.stat2 and affix.value2 then
                    bonus[def.stat2] = (bonus[def.stat2] or 0) + affix.value2
                end
            end

        elseif def.tier == 3 then
            -- 第3层：精确匹配英雄的技能标签 id
            if AffixTagResolver._matchTags(heroTags, def.tags) then
                bonus[def.stat] = (bonus[def.stat] or 0) + affix.value
                if def.stat2 and affix.value2 then
                    bonus[def.stat2] = (bonus[def.stat2] or 0) + affix.value2
                end
            end
        end

        ::continue::
    end

    return bonus
end

-- ============================================================================
-- 快捷接口：获取指定标签 id 的第3层词条加成
-- 用于 HeroSkills.ApplyTag 中实时查询
-- ============================================================================
---@param tower table 英雄实例
---@param tagId string 技能标签 id
---@return table bonus  { [stat] = value }
function AffixTagResolver.GetTagBonus(tower, tagId)
    local bonus = {}
    local heroId = tower.typeDef and tower.typeDef.id or ""

    -- 收集该英雄所有词条
    local affixes = AffixTagResolver.CollectAffixes(heroId)

    for _, affix in ipairs(affixes) do
        if affix._setBonus then goto continue end

        local def = Config.AFFIX_TAG_LOOKUP[affix.id]
        if not def or def.tier ~= 3 then goto continue end

        -- 检查此词条是否覆盖目标标签
        for _, t in ipairs(def.tags) do
            if t == tagId then
                bonus[def.stat] = (bonus[def.stat] or 0) + affix.value
                if def.stat2 and affix.value2 then
                    bonus[def.stat2] = (bonus[def.stat2] or 0) + affix.value2
                end
                break
            end
        end

        ::continue::
    end

    return bonus
end

-- ============================================================================
-- 查询接口：获取一个英雄能从哪些词条中获益（UI 展示用）
-- ============================================================================
---@param heroId string
---@param heroTags table  tower.tags
---@return table[] matchedDefs  匹配的词条定义列表
function AffixTagResolver.GetMatchableAffixes(heroId, heroTags)
    local result = {}
    local heroRoles = Config.HERO_ROLE and Config.HERO_ROLE[heroId] or {}

    local system = Config.AFFIX_TAG_SYSTEM
    if not system then return result end

    -- 第1层
    for _, def in ipairs(system.role_affixes) do
        if AffixTagResolver._matchRoles(heroRoles, def.roles) then
            result[#result + 1] = def
        end
    end

    -- 第2层
    for _, def in ipairs(system.skilltype_affixes) do
        if AffixTagResolver._matchSkillTypes(heroId, heroTags, def.skillTypes) then
            result[#result + 1] = def
        end
    end

    -- 第3层
    for _, def in ipairs(system.tag_affixes) do
        if AffixTagResolver._matchTags(heroTags, def.tags) then
            result[#result + 1] = def
        end
    end

    return result
end

-- ============================================================================
-- 内部匹配函数
-- ============================================================================

--- 第1层：检查英雄角色是否与词条目标角色有交集
---@param heroRoles string[]
---@param targetRoles string[]
---@return boolean
function AffixTagResolver._matchRoles(heroRoles, targetRoles)
    for _, role in ipairs(heroRoles) do
        for _, target in ipairs(targetRoles) do
            if role == target then return true end
        end
    end
    return false
end

--- 第2层：检查英雄是否拥有匹配技能类型的已解锁标签
---@param heroId string
---@param heroTags table  { [tagId] = { tier = n } }
---@param targetTypes string[]
---@return boolean
function AffixTagResolver._matchSkillTypes(heroId, heroTags, targetTypes)
    for tagId, tagState in pairs(heroTags) do
        if tagState.tier and tagState.tier > 0 then
            local tagDef = Config.FindTagDef(heroId, tagId)
            if tagDef then
                for _, st in ipairs(targetTypes) do
                    if tagDef.type == st then return true end
                end
            end
        end
    end
    return false
end

--- 第3层：检查英雄是否拥有目标标签（已解锁）
---@param heroTags table  { [tagId] = { tier = n } }
---@param targetTags string[]
---@return boolean
function AffixTagResolver._matchTags(heroTags, targetTags)
    for _, tag in ipairs(targetTags) do
        local state = heroTags[tag]
        if state and state.tier and state.tier > 0 then
            return true
        end
    end
    return false
end

return AffixTagResolver
