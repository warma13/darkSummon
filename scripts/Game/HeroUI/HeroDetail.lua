-- Game/HeroUI/HeroDetail.lua
-- 英雄详情面板（标签页版：信息 / 装备 / 升星 / 皮肤）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")
local RelicData = require("Game.RelicData")
local RelicCalc = require("Game.RelicCalc")
local HeroSkills = require("Game.HeroSkills")

local HeroDetail = {}

--- 当前详情面板打开的英雄ID和选中标签
---@type string|nil
local detailHeroId = nil
---@type string
local detailTab = "info"

--- 详情面板内容容器（用于标签切换时局部刷新）
---@type any
local detailContentContainer = nil

--- 遗物标签页：当前选中的槽位
local selectedRelicSlot = "power"
--- 遗物标签页：当前预览的遗物 { id, quality } 或 nil
local selectedRelicView = nil

--- header 战力 Label 引用（供 _refreshTab 动态更新）
---@type any
local headerPowerLabel = nil

--- 每秒属性自动刷新：计时器 + 缓存的刷新回调
local detailRefreshAccum = 0
local detailRefreshCallback = nil  -- 指向 ctx._refreshTab

--- 英雄标签页定义（普通英雄）
local DETAIL_TABS = {
    { key = "info",    label = "信息" },
    { key = "equip",   label = "装备" },
    { key = "starup",  label = "升星" },
    { key = "skin",    label = "皮肤" },
}

--- 主角专属标签页
local LEADER_TABS = {
    { key = "info",    label = "信息" },
    { key = "costume", label = "时装" },
    { key = "title",   label = "称号" },
    { key = "relic",   label = "遗物" },
}

--- 获取当前详情面板打开的英雄ID（供 HeroUI.Refresh 保存/恢复状态）
function HeroDetail.GetCurrentHeroId()
    return detailHeroId
end

--- 页面重建时清理局部状态
function HeroDetail.OnPageClear()
    HeroDetail.StopAutoRefresh()
    detailContentContainer = nil
    detailHeroId = nil
    headerPowerLabel = nil
    selectedRelicSlot = "power"
    selectedRelicView = nil
end

-- ============================================================================
-- 每秒属性自动刷新（由 GameLoop.HandleUpdate 驱动）
-- ============================================================================

local DETAIL_REFRESH_INTERVAL = 1.0  -- 秒

--- 每帧由 GameLoop 调用，累计 dt 到达 1 秒时触发一次刷新
function HeroDetail.Tick(dt)
    if not detailRefreshCallback then return end
    detailRefreshAccum = detailRefreshAccum + dt
    if detailRefreshAccum >= DETAIL_REFRESH_INTERVAL then
        detailRefreshAccum = detailRefreshAccum - DETAIL_REFRESH_INTERVAL
        detailRefreshCallback()
    end
end

--- 启动属性自动刷新
function HeroDetail.StartAutoRefresh(refreshFn)
    detailRefreshCallback = refreshFn
    detailRefreshAccum = 0
end

--- 停止属性自动刷新
function HeroDetail.StopAutoRefresh()
    detailRefreshCallback = nil
    detailRefreshAccum = 0
end

local function ShowToast(msg)
    Toast.Show(msg)
end

-- ============================================================================
-- 属性行 / 技能图标
-- ============================================================================

--- 格式化属性值为显示字符串
---@param value number|string
---@param fmt string|nil  "pct"=百分比, nil=整数/大数
---@return string
local function FormatStatValue(value, fmt)
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
local function CreateStatRow(UI, S, label, value, color, fmt, valueId)
    local display = FormatStatValue(value, fmt)
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
local function CreateSkillIcon(UI, skillDef, unlocked, selected, onClick)
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
---@param heroId string
---@return table stats  完整属性表（atk 已乘法叠加，含 critRate/critDmg/armorPen/dmgBonus/elemDmgBonus/spdBonus/atkSpeedDisplay/power）
local function ComputeFullStats(heroId)
    local stats = HeroData.GetHeroStats(heroId)
    local EquipData = require("Game.EquipData")
    local eqBonus = EquipData.GetTotalBonus(heroId)

    -- 神裔降临加成
    local DivineBlessDB = require("Game.DivineBlessData")
    local divineAtkPct  = DivineBlessDB.GetBuffValue("atk_pct")
    local divineSpdPct  = DivineBlessDB.GetBuffValue("spd_pct")
    local divineCritPct = DivineBlessDB.GetBuffValue("crit_pct")

    -- 遗物被动加成
    local relicAtkPct, relicSpdPct, relicCritDmgPct = 0, 0, 0
    if RelicData and RelicData.GetPassiveBonus then
        local rb = RelicData.GetPassiveBonus()
        relicAtkPct    = rb.atkPct or 0
        relicSpdPct    = rb.spdPct or 0
        relicCritDmgPct = rb.critDmgPct or 0
    end

    -- 技能被动加成（critRate / critDmg）
    local skillCritRate, skillCritDmg = 0, 0
    local skillDefs0 = Config.HERO_SKILLS and Config.HERO_SKILLS[heroId] or {}
    for _, skill in ipairs(skillDefs0) do
        if skill.type == "passive" then
            skillCritRate = skillCritRate + (skill.critRate or 0)
            skillCritDmg  = skillCritDmg  + (skill.critDmg or 0)
        end
    end

    -- 标签被动加成
    local tagCritRate, tagCritDmg, tagAtkSpdBonus, tagArmorIgnore = 0, 0, 0, 0
    local tagDefs0 = Config.HERO_SKILL_TAGS and Config.HERO_SKILL_TAGS[heroId]
    local mockTags = {}
    if tagDefs0 then
        for _, tagDef in ipairs(tagDefs0) do
            local tier = HeroData.GetTagTier(heroId, tagDef.id)
            local unlocked = HeroData.IsTagUnlocked(heroId, tagDef)
            local reqMet = true
            if tagDef.requires then
                for _, reqId in ipairs(tagDef.requires) do
                    if HeroData.GetTagTier(heroId, reqId) <= 0 then reqMet = false; break end
                end
            end
            local activeTier = (unlocked and reqMet) and tier or 0
            mockTags[tagDef.id] = { def = tagDef, tier = activeTier }
            if tagDef.type == "passive" and activeTier > 0 then
                local eff = tagDef.effects and tagDef.effects[activeTier]
                if eff then
                    tagCritRate    = tagCritRate    + (eff.critRate or 0)
                    tagCritDmg     = tagCritDmg     + (eff.critDmg or 0)
                    tagAtkSpdBonus = tagAtkSpdBonus + (eff.atkSpdBonus or 0)
                    tagArmorIgnore = tagArmorIgnore + (eff.armorIgnore or 0)
                end
            end
        end
    end

    -- 词条三层加成（AffixTagResolver）
    local affixCritRate, affixCritDmg, affixAtkPct, affixArmorPen, affixDmgBonus = 0, 0, 0, 0, 0
    local affixSpdBonus = 0
    do
        local ok, ATR = pcall(require, "Game.AffixTagResolver")
        if ok and ATR then
            local towerDef = nil
            for _, td in ipairs(Config.TOWER_TYPES) do
                if td.id == heroId then towerDef = td; break end
            end
            if not towerDef and Config.LEADER_HERO and Config.LEADER_HERO.id == heroId then
                towerDef = Config.LEADER_HERO
            end
            if towerDef then
                local mockTower = { typeDef = towerDef, tags = mockTags }
                local affixes = ATR.CollectAffixes(heroId)
                local ab = ATR.Resolve(mockTower, affixes)
                affixAtkPct    = ab.atk_pct or 0
                affixCritRate  = ab.critRate_add or 0
                affixCritDmg   = ab.critDmg_add or 0
                affixArmorPen  = ab.armorPen_add or 0
                affixDmgBonus  = ab.skillDmg_pct or 0
                affixSpdBonus  = ab.spdBonus_add or 0
            end
        end
    end

    -- 攻击力 = (基础+装备) × (1+装备%+神裔%) × (1+遗物%) × (1+词条%)
    stats.atk = (stats.atk + (eqBonus.atk or 0))
              * (1 + (eqBonus.atk_pct or 0) + divineAtkPct)
              * (1 + relicAtkPct)
              * (1 + affixAtkPct)
    stats.critRate = (stats.critRate or 0) + (eqBonus.critRate or 0) + divineCritPct
                   + skillCritRate + tagCritRate + affixCritRate
    stats.critDmg = (stats.critDmg or 0) + (eqBonus.critDmg or 0) + relicCritDmgPct
                  + skillCritDmg + tagCritDmg + affixCritDmg
    stats.armorPen = (stats.armorPen or 0) + (eqBonus.armorPen or 0) + tagArmorIgnore + affixArmorPen
    stats.dmgBonus = (stats.dmgBonus or 0) + (eqBonus.dmgBonus or 0) + affixDmgBonus

    -- 称号加成
    local okTD, TitleDataMod = pcall(require, "Game.TitleData")
    if okTD and TitleDataMod then
        local tAtk = TitleDataMod.GetGlobalAtkBonus and TitleDataMod.GetGlobalAtkBonus() or 0
        if tAtk > 0 then stats.atk = stats.atk * (1 + tAtk) end
        local tSpd = TitleDataMod.GetGlobalSpdBonus and TitleDataMod.GetGlobalSpdBonus() or 0
        if tSpd > 0 then stats.spdBonusTitle = tSpd end
    end

    -- 元素伤害
    local heroDmgType = Config.HERO_DAMAGE_TYPE[heroId]
    if heroDmgType and eqBonus.elemDmg and eqBonus.elemDmg > 0 then
        if not stats.elemDmgBonus then stats.elemDmgBonus = {} end
        stats.elemDmgBonus[heroDmgType] = (stats.elemDmgBonus[heroDmgType] or 0) + eqBonus.elemDmg
    end

    -- 计算实际攻速（次/s）
    local totalSpdBonus = (stats.spdBonus or 0) + (eqBonus.spd_pct or 0)
                        + divineSpdPct + relicSpdPct + tagAtkSpdBonus + affixSpdBonus
                        + (stats.spdBonusTitle or 0)
    do
        local baseSpeed = nil
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then baseSpeed = td.baseSpeed; break end
        end
        if not baseSpeed and Config.LEADER_HERO and Config.LEADER_HERO.id == heroId then
            baseSpeed = Config.LEADER_HERO.baseSpeed
        end
        if baseSpeed then
            local interval = baseSpeed / (1 + totalSpdBonus)
            stats.atkSpeedDisplay = string.format("%.2f/s", 1 / interval)
            stats.atkSpeedValue = 1 / interval  -- 数值，用于战力计算
        else
            stats.atkSpeedDisplay = tostring(stats.spd)
            stats.atkSpeedValue = stats.spd or 0
        end
    end

    -- 战力 = 攻击力 + 攻速数值
    stats.power = stats.atk + stats.atkSpeedValue

    return stats
end

-- ============================================================================
-- 运行时属性查询（战斗中从 State.towers 获取实时数据）
-- ============================================================================

--- 从 State.towers 中查找英雄对应的 tower 实例
---@param heroId string
---@return table|nil tower  找到的 tower 实例，未上场返回 nil
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
---@return table stats  { atk, atkSpeedDisplay, critRate, critDmg, armorPen, dmgBonus, elemDmgBonus, power }
---@return boolean isRuntime  是否来自运行时 tower 数据
local function GetRuntimeStats(heroId)
    local tower = FindTowerByHeroId(heroId)
    if not tower then
        return ComputeFullStats(heroId), false
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

    -- 暴击伤害/穿甲/伤害加成（含减益修正）
    stats.critDmg  = Tower.GetEffectiveCritDmg(tower)
    stats.armorPen = Tower.GetEffectiveArmorPen(tower)
    stats.dmgBonus = Tower.GetEffectiveDmgBonus and Tower.GetEffectiveDmgBonus(tower) or (tower.dmgBonus or 0)

    -- 元素伤害加成（从静态数据获取，运行时不变）
    local dmgTypeId = Config.HERO_DAMAGE_TYPE[heroId]
    if dmgTypeId then
        local staticStats = ComputeFullStats(heroId)
        stats.elemDmgBonus = staticStats.elemDmgBonus
    end

    -- 战力 = 攻击力 + 攻速数值
    stats.power = stats.atk + stats.atkSpeedValue

    return stats, true
end

-- ============================================================================
-- 标签页：信息（属性 + 技能）
-- ============================================================================

--- 构建信息标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
local function BuildInfoTab(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()

    local h = HeroData.Get(heroId)
    local level = (h and h.level) or 1
    local isUnlocked = h and h.unlocked or false
    local fragments = (h and h.fragments) or 0
    local rarity = heroDef.rarity or "R"
    local unlockCost = Config.RARITY_SHARD_COST[rarity] or 10

    if not isUnlocked then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 20, paddingBottom = 20,
            children = {
                UI.Label { text = "碎片 " .. fragments .. "/" .. unlockCost, fontSize = 14, fontColor = S.dim },
                UI.Label { text = "收集碎片解锁英雄", fontSize = 12, fontColor = S.dimLocked, marginTop = 6 },
            },
        }
    end

    local stats = GetRuntimeStats(heroId)
    local atkSpeedDisplay = stats.atkSpeedDisplay

    local children = {}

    -- 属性区（带 id 以支持每秒增量更新）
    local statChildren = {
        CreateStatRow(UI, S, "攻击", stats.atk, { 255, 120, 80, 255 }, nil, "detail_atk"),
        CreateStatRow(UI, S, "攻速", atkSpeedDisplay, { 100, 180, 255, 255 }, nil, "detail_spd"),
        CreateStatRow(UI, S, "暴击率", stats.critRate, { 255, 220, 80, 255 }, "pct", "detail_critRate"),
        CreateStatRow(UI, S, "暴击伤害", stats.critDmg, { 255, 160, 60, 255 }, "pct", "detail_critDmg"),
        CreateStatRow(UI, S, "穿甲", stats.armorPen, { 200, 140, 255, 255 }, "pct", "detail_armorPen"),
        CreateStatRow(UI, S, "伤害加成", stats.dmgBonus or 0, { 255, 100, 100, 255 }, "pct", "detail_dmgBonus"),
    }
    do
        local dmgTypeId = Config.HERO_DAMAGE_TYPE[heroId]
        local dmgDef = dmgTypeId and Config.DAMAGE_TYPES[dmgTypeId]
        if dmgTypeId and dmgDef then
            local dmgBonus = stats.elemDmgBonus and stats.elemDmgBonus[dmgTypeId] or 0
            statChildren[#statChildren + 1] = CreateStatRow(UI, S, dmgDef.name .. "伤害", dmgBonus, dmgDef.color, "pct", "detail_elemDmg")
        end
    end
    children[#children + 1] = UI.Panel {
        id = "detail_stat_panel",
        width = "100%",
        backgroundColor = { 35, 25, 18, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 70, 55, 40, 150 },
        paddingTop = 6, paddingBottom = 6,
        gap = 2,
        children = statChildren,
    }

    -- 伤害类型 & 定位
    do
        local dmgTypeId = Config.HERO_DAMAGE_TYPE[heroId]
        local dmgDef = dmgTypeId and Config.DAMAGE_TYPES[dmgTypeId]
        local roles = Config.HERO_ROLE and Config.HERO_ROLE[heroId]
        local roleNames = Config.HERO_ROLE_NAMES or {}
        if dmgDef or (roles and #roles > 0) then
            local infoChildren = {}
            if dmgDef then
                infoChildren[#infoChildren + 1] = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    paddingLeft = 4,
                    children = {
                        UI.Label { text = "伤害类型", fontSize = 10, fontColor = S.dim, width = 50 },
                        UI.Panel {
                            width = 10, height = 10, borderRadius = 5,
                            backgroundColor = { dmgDef.color[1], dmgDef.color[2], dmgDef.color[3], 220 },
                        },
                        UI.Label {
                            text = dmgDef.name, fontSize = 11,
                            fontColor = dmgDef.color, fontWeight = "bold",
                        },
                    },
                }
            end
            if roles and #roles > 0 then
                local parts = {}
                for _, r in ipairs(roles) do
                    parts[#parts + 1] = roleNames[r] or r
                end
                infoChildren[#infoChildren + 1] = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    paddingLeft = 4,
                    children = {
                        UI.Label { text = "定位", fontSize = 10, fontColor = S.dim, width = 50 },
                        UI.Label {
                            text = table.concat(parts, " / "),
                            fontSize = 11, fontColor = { 180, 200, 160, 220 },
                        },
                    },
                }
            end
            children[#children + 1] = UI.Panel {
                width = "100%",
                marginTop = 4,
                backgroundColor = { 35, 25, 18, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 70, 55, 40, 150 },
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 6, paddingRight = 6,
                gap = 3,
                children = infoChildren,
            }
        end
    end

    -- 技能区
    local skillDefs = Config.HERO_SKILLS and Config.HERO_SKILLS[heroId] or {}
    if #skillDefs > 0 then
        local skillDescContainer = UI.Panel { width = "100%" }
        local selectedIdx = 1
        local skillIconsContainer = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 6,
            flexWrap = "wrap",
        }

        -- 星级缩放系数：0星→10%，满星→100%
        local heroStar = (h and h.star) or 0
        local maxStar  = Config.MAX_HERO_STAR or 30
        local starScale = 0.10 + 0.90 * math.sqrt(math.min(heroStar, maxStar) / maxStar)

        -- 星级乘数文本，如 "（★2 ×16%）"
        local starPct = math.floor(starScale * 100 + 0.5)
        local starTag = "（★" .. heroStar .. " ×" .. starPct .. "%）"

        local function UpdateSkillDesc(idx)
            selectedIdx = idx
            local sd = skillDefs[idx]
            if not sd then return end

            -- 动态描述：有 buildDesc 的技能用动态值，否则回退到静态 desc + starTag
            local desc
            if sd.buildDesc then
                desc = sd.buildDesc(starScale) .. " " .. starTag
            else
                desc = sd.desc
            end

            skillDescContainer:ClearChildren()
            skillDescContainer:AddChild(UI.Panel {
                width = "100%",
                marginTop = 4,
                backgroundColor = { 45, 35, 28, 220 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 80, 65, 48, 150 },
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 10, paddingRight = 10,
                gap = 3,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = sd.name, fontSize = 13,
                                fontColor = S.gold,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = sd.type == "active" and "[主动]" or "[被动]",
                                fontSize = 10,
                                fontColor = sd.type == "active"
                                    and { 220, 100, 80, 200 } or { 100, 180, 80, 200 },
                            },
                        },
                    },
                    UI.Label {
                        text = desc, fontSize = 11,
                        fontColor = { 210, 200, 180, 220 },
                    },
                },
            })

            skillIconsContainer:ClearChildren()
            for i, skillDef in ipairs(skillDefs) do
                skillIconsContainer:AddChild(CreateSkillIcon(UI, skillDef, true, i == selectedIdx, function(self)
                    UpdateSkillDesc(i)
                end))
            end
        end

        UpdateSkillDesc(1)

        children[#children + 1] = UI.Panel {
            width = "100%",
            marginTop = 6,
            backgroundColor = { 35, 25, 18, 200 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { 70, 55, 40, 150 },
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 6, paddingRight = 6,
            gap = 4,
            children = {
                UI.Label { text = "技能", fontSize = 12, fontColor = S.dim, marginLeft = 6 },
                skillIconsContainer,
                skillDescContainer,
            },
        }
    end

    -- 技能标签区
    do
        local tagDefs = Config.HERO_SKILL_TAGS and Config.HERO_SKILL_TAGS[heroId]
        if tagDefs and #tagDefs > 0 then
            local typeColors = {
                passive     = { 120, 200, 120, 220 },
                on_hit      = { 255, 160, 80, 220 },
                on_crit     = { 255, 220, 80, 220 },
                on_kill     = { 255, 80, 80, 220 },
                aura        = { 100, 180, 255, 220 },
                active      = { 220, 100, 255, 220 },
                conditional = { 200, 180, 140, 220 },
            }
            local typeLabels = {
                passive = "被动", on_hit = "命中", on_crit = "暴击",
                on_kill = "击杀", aura = "光环", active = "主动",
                conditional = "条件",
            }

            local tagChildren = {}
            tagChildren[#tagChildren + 1] = UI.Label {
                text = "技能标签", fontSize = 12, fontColor = S.dim, marginLeft = 6,
            }

            for i, tagDef in ipairs(tagDefs) do
                local tier = HeroData.GetTagTier(heroId, tagDef.id)
                local unlocked = HeroData.IsTagUnlocked(heroId, tagDef)

                -- 顺序解锁：前一个标签 tier > 0 才能解锁后一个
                local seqLocked = false
                if i > 1 then
                    local prevTag = tagDefs[i - 1]
                    if HeroData.GetTagTier(heroId, prevTag.id) <= 0 then
                        seqLocked = true
                    end
                end
                local effectDesc = ""
                if tier > 0 and tagDef.effects and tagDef.effects[tier] then
                    effectDesc = tagDef.effects[tier].desc or ""
                elseif tagDef.effects and tagDef.effects[1] then
                    effectDesc = tagDef.effects[1].desc or ""
                end

                local tColor = typeColors[tagDef.type] or S.dim
                local tLabel = typeLabels[tagDef.type] or tagDef.type

                -- 解锁条件文本
                local unlockText = ""
                if tagDef.unlock then
                    if tagDef.unlock.star then
                        unlockText = "★" .. tagDef.unlock.star
                    elseif tagDef.unlock.advance then
                        unlockText = "进阶" .. tagDef.unlock.advance
                    end
                end

                local tierText = tier > 0
                    and (" Lv" .. tier .. "/" .. tagDef.maxTier)
                    or (" 0/" .. tagDef.maxTier)

                -- 升级费用计算
                local maxTier = tagDef.maxTier or 1
                local costTable = Config.SKILL_BOOK_COST and Config.SKILL_BOOK_COST[rarity]
                local costMap = (tier < maxTier and costTable) and costTable[tier] or nil
                local canUpgrade = unlocked and not seqLocked and tier < maxTier and costMap
                local hasBooks = false
                if canUpgrade then
                    hasBooks = true
                    for bookId, amount in pairs(costMap) do
                        if not Currency.Has(bookId, amount) then
                            hasBooks = false
                            break
                        end
                    end
                end

                -- 升级按钮
                local upgradeBtn = nil
                if unlocked and not seqLocked and tier < maxTier then
                    -- 构建消耗图标children
                    local costChildren = {}
                    if costMap then
                        local BOOK_ORD = { "skill_book_1", "skill_book_2", "skill_book_3" }
                        for _, bid in ipairs(BOOK_ORD) do
                            if costMap[bid] then
                                local cd = Config.CURRENCY[bid]
                                local bColor = cd and cd.color or {180,180,180}
                                costChildren[#costChildren + 1] = UI.Panel {
                                    width = 11, height = 11, borderRadius = 3,
                                    backgroundColor = { bColor[1], bColor[2], bColor[3], 200 },
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label { text = cd and cd.icon and cd.icon:sub(1,1):upper() or "?",
                                            fontSize = 7, fontColor = {255,255,255,240}, pointerEvents = "none" },
                                    },
                                }
                                costChildren[#costChildren + 1] = UI.Label {
                                    text = tostring(costMap[bid]), fontSize = 8,
                                    fontColor = { 255, 255, 255, 220 },
                                    pointerEvents = "none",
                                    marginRight = 2,
                                }
                            end
                        end
                    end
                    local tagIdCap = tagDef.id  -- capture for closure
                    -- 消耗图标面板（按钮左侧）
                    local costPanel = #costChildren > 0 and UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 1,
                        children = costChildren,
                    } or nil
                    upgradeBtn = UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            costPanel,
                            UI.Button {
                                text = "升级",
                                fontSize = 9,
                                height = 20, minWidth = 36,
                                paddingLeft = 6, paddingRight = 6,
                                variant = hasBooks and "primary" or "outline",
                                disabled = not hasBooks,
                                onClick = function()
                                    local ok, err = HeroSkills.UpgradeTag(heroId, tagIdCap)
                                    if ok then
                                        Toast.Show("标签升级成功！")
                                        if ctx._refreshTab then ctx._refreshTab() else ctx.ShowHeroDetail(heroId) end
                                    else
                                        local errMsgs = {
                                            not_enough_skill_book = "技能书不足",
                                            max_tier = "已满级",
                                            tag_locked = "标签未解锁",
                                            prev_tag_required = "需要先升级前置标签",
                                        }
                                        Toast.Show(errMsgs[err] or ("升级失败: " .. (err or "")))
                                    end
                                end,
                            },
                        },
                    }
                elseif tier >= maxTier then
                    upgradeBtn = UI.Label {
                        text = "已满级", fontSize = 9,
                        fontColor = { 160, 200, 120, 180 },
                    }
                elseif seqLocked and unlocked then
                    upgradeBtn = UI.Label {
                        text = "需升级前置", fontSize = 9,
                        fontColor = { 180, 150, 100, 160 },
                    }
                end

                tagChildren[#tagChildren + 1] = UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    paddingLeft = 6, paddingRight = 6,
                    gap = 4,
                    opacity = (unlocked and not seqLocked) and 1.0 or 0.5,
                    children = {
                        -- 类型标签
                        UI.Panel {
                            backgroundColor = { tColor[1], tColor[2], tColor[3], 60 },
                            borderRadius = 4,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            children = {
                                UI.Label { text = tLabel, fontSize = 9, fontColor = tColor },
                            },
                        },
                        -- 标签名 + 等级
                        UI.Label {
                            text = tagDef.name .. tierText,
                            fontSize = 11,
                            fontColor = (unlocked and not seqLocked) and { 230, 220, 200, 220 } or { 160, 150, 130, 150 },
                            fontWeight = tier > 0 and "bold" or "normal",
                            flexShrink = 1,
                        },
                        -- 解锁条件
                        UI.Label {
                            text = unlockText,
                            fontSize = 9,
                            fontColor = (unlocked and not seqLocked) and { 160, 200, 120, 180 } or { 160, 150, 130, 130 },
                        },
                        -- 占位弹性空间
                        UI.Panel { flexGrow = 1 },
                        -- 升级按钮
                        upgradeBtn,
                    },
                }

                -- 效果描述
                if effectDesc ~= "" then
                    tagChildren[#tagChildren + 1] = UI.Panel {
                        width = "100%",
                        paddingLeft = 24,
                        children = {
                            UI.Label {
                                text = effectDesc,
                                fontSize = 10,
                                fontColor = (unlocked and not seqLocked)
                                    and { 200, 190, 170, 200 }
                                    or { 140, 130, 120, 120 },
                            },
                        },
                    }
                end
            end

            -- 技能书余额（三阶，图片+数量）
            local BOOK_BAL_ORDER = { "skill_book_1", "skill_book_2", "skill_book_3" }
            local balChildren = {}
            for _, bid in ipairs(BOOK_BAL_ORDER) do
                local cnt = Currency.Get(bid)
                local cd = Config.CURRENCY[bid]
                local bColor = cd and cd.color or {180,180,180}
                balChildren[#balChildren + 1] = UI.Panel {
                    width = 12, height = 12, borderRadius = 3,
                    backgroundColor = { bColor[1], bColor[2], bColor[3], 200 },
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = cd and cd.icon and cd.icon:sub(1,1):upper() or "?",
                            fontSize = 7, fontColor = {255,255,255,240}, pointerEvents = "none" },
                    },
                }
                balChildren[#balChildren + 1] = UI.Label {
                    text = ctx.FormatBigNum(cnt), fontSize = 10,
                    fontColor = { 180, 160, 120, 200 },
                    pointerEvents = "none",
                    marginRight = 6,
                }
            end
            tagChildren[#tagChildren + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "flex-end",
                paddingLeft = 6, paddingRight = 6,
                marginTop = 2,
                children = balChildren,
            }

            children[#children + 1] = UI.Panel {
                width = "100%",
                marginTop = 4,
                backgroundColor = { 35, 25, 18, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 70, 55, 40, 150 },
                paddingTop = 6, paddingBottom = 6,
                gap = 3,
                children = tagChildren,
            }
        end
    end

    return UI.Panel {
        width = "100%",
        gap = 4,
        children = children,
    }
end

-- ============================================================================
-- 标签页：装备
-- ============================================================================

--- 构建装备标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
local function BuildEquipTab(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local FormatBigNum = ctx.FormatBigNum

    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false

    if not isUnlocked then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "解锁英雄后可装备", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    -- 主角不参与装备系统
    if heroId == Config.LEADER_HERO.id then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "主角无装备", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    -- 未上阵英雄无装备
    if not HeroData.IsDeployed(heroId) then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "上阵后可查看装备", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    local EquipData = require("Game.EquipData")
    local heroLevel = (h and h.level) or 1
    local cards = {}

    for _, slotDef in ipairs(Config.EQUIP_SLOTS) do
        local info = EquipData.GetSlotInfo(heroId, slotDef.id)
        if info then
            local tier = info.tierDef
            local needBreak, breakInfo = EquipData.CheckBreakthrough(heroId, slotDef.id)
            local upgradeCost = EquipData.GetUpgradeCost(info.level)
            local isMaxLevel = (info.level >= Config.EQUIP_MAX_LEVEL)
            local isAtHeroCap = (info.level >= heroLevel)
            local isAtTierMax = needBreak

            -- 按钮逻辑
            local btnText, btnColor, btnClick
            if isMaxLevel then
                btnText = "满级"
                btnColor = S.btnDisabled
                btnClick = function() end
            elseif isAtTierMax then
                btnText = "突破"
                btnColor = S.btnAdvance
                btnClick = function()
                    EquipData.Breakthrough(heroId, slotDef.id)
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayUpgrade()
                    ctx.ShowHeroDetail(heroId)  -- 刷新
                end
            elseif isAtHeroCap then
                btnText = "升级"
                btnColor = S.btnDisabled
                btnClick = function() end
            else
                local canUpgrade = (HeroData.currencies.forge_iron or 0) >= upgradeCost
                btnText = "升级"
                btnColor = canUpgrade and S.btnGreen or S.btnDisabled
                btnClick = function()
                    EquipData.Upgrade(heroId, slotDef.id)
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayUpgrade()
                    ctx.ShowHeroDetail(heroId)
                end
            end

            cards[#cards + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = { 35, 25, 18, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = tier.borderColor,
                paddingTop = 5, paddingBottom = 5,
                paddingLeft = 6, paddingRight = 6,
                gap = 6,
                children = {
                    -- 装备图标
                    UI.Panel {
                        width = 40, height = 40,
                        flexShrink = 0,
                        borderRadius = 6,
                        backgroundColor = tier.bgColor,
                        borderWidth = 1,
                        borderColor = tier.color,
                        backgroundImage = "image/equip_" .. tier.id .. "_" .. slotDef.id .. ".png",
                        backgroundFit = "cover",
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                position = "absolute",
                                bottom = 0, left = 0,
                                paddingLeft = 3, paddingRight = 3,
                                backgroundColor = { 0, 0, 0, 180 },
                                borderTopRightRadius = 4,
                                children = {
                                    UI.Label { text = tostring(info.level), fontSize = 8, fontColor = tier.color, fontWeight = "bold" },
                                },
                            },
                        },
                    },
                    -- 装备名 + 属性
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        gap = 1,
                        children = (function()
                            local TemperData = require("Game.TemperData")
                            local temperBonus = TemperData.GetSlotBonus(heroId, slotDef.id)
                            local statText = slotDef.statName .. " +" .. (slotDef.fmt == "pct"
                                and string.format("%.1f%%", info.statBonus * 100)
                                or FormatBigNum(info.statBonus))
                            local labelChildren = {
                                UI.Label { text = info.fullName, fontSize = 12, fontColor = tier.color, fontWeight = "bold" },
                                UI.Label { text = statText, fontSize = 10, fontColor = S.gold },
                            }
                            -- 淬炼加成汇总：显示所有词条
                            local parts = {}
                            for statKey, val in pairs(temperBonus) do
                                if val > 0 then
                                    -- 查找属性中文名
                                    local name = statKey
                                    for _, attr in ipairs(Config.TEMPER_ATTRIBUTES) do
                                        if attr.id == statKey then name = attr.name; break end
                                    end
                                    -- atk词条映射到部位属性名
                                    if statKey == slotDef.stat and statKey ~= "atk" then
                                        name = slotDef.statName
                                    end
                                    parts[#parts + 1] = name .. "+" .. string.format("%.1f%%", val * 100)
                                end
                            end
                            if #parts > 0 then
                                labelChildren[#labelChildren + 1] = UI.Label {
                                    text = "淬炼: " .. table.concat(parts, " "),
                                    fontSize = 9, fontColor = { 100, 255, 100, 200 },
                                }
                            end
                            return labelChildren
                        end)(),
                    },
                    -- 操作按钮
                    UI.Panel {
                        width = 50, flexShrink = 0,
                        justifyContent = "center", alignItems = "center",
                        paddingTop = 5, paddingBottom = 5,
                        borderRadius = 6,
                        backgroundColor = btnColor,
                        onClick = btnClick,
                        children = {
                            UI.Label { text = btnText, fontSize = 11, fontColor = S.btnText, fontWeight = "bold" },
                        },
                    },
                },
            }
        end
    end

    -- 锻魂铁货币
    cards[#cards + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 4,
        marginTop = 4,
        children = {
            Currency.IconWidget(UI, "forge_iron", 14),
            UI.Label {
                text = FormatBigNum(HeroData.currencies.forge_iron or 0),
                fontSize = 12, fontColor = S.gold,
            },
        },
    }

    return UI.Panel {
        width = "100%",
        gap = 5,
        children = cards,
    }
end

-- ============================================================================
-- 标签页：升星
-- ============================================================================

--- 构建升星标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
local function BuildStarUpTab(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()

    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false

    if not isUnlocked then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "解锁英雄后可升星", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    local star = h.star or 0
    local fragments = h.fragments or 0
    local tierInfo = HeroData.GetStarTierInfo(heroId)
    local isMaxStar = (star >= Config.MAX_HERO_STAR)

    -- 升星费用
    local starCost = 0
    local canStarUp = false
    if not isMaxStar then
        starCost = HeroData.GetStarUpCost(star)
        canStarUp = fragments >= starCost
    end

    -- 当前星段和下一星段信息
    local currentTierIdx = (star > 0) and HeroData.GetTierFromStar(star) or 0
    local nextTierIdx = (not isMaxStar) and HeroData.GetTierFromStar(star + 1) or currentTierIdx
    local nextTier = Config.STAR_TIERS[nextTierIdx]
    local isTierAdvance = (nextTierIdx > currentTierIdx)

    -- 当前星级显示行
    local CreateStarRows = ctx.CreateStarRows
    local currentStarRows = {}
    if star > 0 then
        currentStarRows = CreateStarRows(tierInfo.starInTier, tierInfo.color)
    end

    -- 下一星级预览
    local nextStarInTier = tierInfo.starInTier + 1
    local nextTierColor = tierInfo.color
    if isTierAdvance and nextTier then
        nextStarInTier = 1
        nextTierColor = nextTier.color
    end
    local nextStarRows = {}
    if not isMaxStar then
        nextStarRows = CreateStarRows(nextStarInTier, nextTierColor)
    end

    -- 碎片进度
    local progRatio = isMaxStar and 1.0 or math.min(1.0, fragments / math.max(1, starCost))

    local children = {}

    -- 星级变化区域：当前 → 下一级
    if not isMaxStar then
        children[#children + 1] = UI.Panel {
            width = "100%",
            backgroundColor = { 35, 25, 18, 200 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { 70, 55, 40, 150 },
            paddingTop = 12, paddingBottom = 12,
            paddingLeft = 10, paddingRight = 10,
            gap = 8,
            children = {
                -- 标题
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = tierInfo.name .. " " .. tierInfo.starInTier .. "星",
                            fontSize = 14, fontColor = tierInfo.color, fontWeight = "bold",
                        },
                        UI.Label {
                            text = "  →  ",
                            fontSize = 14, fontColor = S.dim,
                        },
                        UI.Label {
                            text = (isTierAdvance and nextTier) and (nextTier.name .. " 1星") or (tierInfo.name .. " " .. (tierInfo.starInTier + 1) .. "星"),
                            fontSize = 14,
                            fontColor = isTierAdvance and nextTierColor or tierInfo.color,
                            fontWeight = "bold",
                        },
                    },
                },

                -- 星级图形对比（当前 → 下一）
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    alignItems = "center",
                    gap = 12,
                    children = {
                        -- 当前星级
                        UI.Panel {
                            alignItems = "center",
                            gap = 2,
                            children = {
                                #currentStarRows > 0 and UI.Panel {
                                    alignItems = "center", gap = 0,
                                    children = currentStarRows,
                                } or UI.Label { text = "无星", fontSize = 12, fontColor = S.dim },
                            },
                        },
                        UI.Label { text = "→", fontSize = 18, fontColor = S.gold },
                        -- 下一星级
                        UI.Panel {
                            alignItems = "center",
                            gap = 2,
                            children = {
                                UI.Panel {
                                    alignItems = "center", gap = 0,
                                    children = nextStarRows,
                                },
                            },
                        },
                    },
                },

                -- 属性加成预览
                (function()
                    local baseStat = HeroData.GetHeroStats(heroId)
                    -- 模拟升一星后的属性
                    local nextAtk = baseStat.atk * (1 + 0.02)  -- 每星约+2%
                    local atkDiff = nextAtk - baseStat.atk
                    return UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "升星加成",
                                fontSize = 11, fontColor = S.dim,
                            },
                            UI.Label {
                                text = "攻击 +" .. string.format("%.0f", atkDiff) .. "  攻速 +2%",
                                fontSize = 12, fontColor = { 100, 255, 100, 255 },
                            },
                        },
                    }
                end)(),
            },
        }
    else
        children[#children + 1] = UI.Panel {
            width = "100%",
            backgroundColor = { 35, 25, 18, 200 },
            borderRadius = 8,
            paddingTop = 16, paddingBottom = 16,
            alignItems = "center",
            children = {
                UI.Panel { alignItems = "center", gap = 0, children = currentStarRows },
                UI.Label {
                    text = "已达最高星级",
                    fontSize = 14, fontColor = S.gold, fontWeight = "bold", marginTop = 8,
                },
            },
        }
    end

    -- 碎片进度条
    children[#children + 1] = UI.Panel {
        width = "100%",
        backgroundColor = { 35, 25, 18, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 70, 55, 40, 150 },
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 12, paddingRight = 12,
        gap = 6,
        children = {
            -- 碎片标签
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "英雄碎片", fontSize = 12, fontColor = S.dim },
                    UI.Label {
                        text = isMaxStar and tostring(fragments) or (fragments .. "/" .. starCost),
                        fontSize = 12,
                        fontColor = canStarUp and { 100, 255, 100, 255 } or S.white,
                        fontWeight = "bold",
                    },
                },
            },
            -- 进度条
            UI.Panel {
                width = "100%",
                height = 16,
                borderRadius = 8,
                backgroundColor = S.progBg,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = math.max(3, math.floor(progRatio * 100)) .. "%",
                        height = "100%",
                        borderRadius = 8,
                        backgroundColor = canStarUp and { 100, 255, 100, 255 } or { 200, 160, 60, 255 },
                    },
                },
            },
        },
    }

    -- 升星按钮
    if not isMaxStar then
        children[#children + 1] = UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 4,
            children = {
                UI.Panel {
                    width = "70%",
                    paddingTop = 10, paddingBottom = 10,
                    borderRadius = 10,
                    backgroundColor = canStarUp and S.btnGreen or S.btnDisabled,
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if not canStarUp then
                            ShowToast("碎片不足")
                            return
                        end
                        local ok, msg = HeroData.StarUp(heroId)
                        if ok then
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayUpgrade()
                            ShowToast("升星成功! " .. msg)
                        else
                            ShowToast(msg)
                        end
                        -- 刷新详情面板
                        ctx.ShowHeroDetail(heroId)
                    end,
                    children = {
                        UI.Label {
                            text = isTierAdvance and "突破升星" or "升星",
                            fontSize = 16, fontColor = S.btnText, fontWeight = "bold",
                        },
                    },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        gap = 6,
        children = children,
    }
end

-- ============================================================================
-- 标签页：皮肤
-- ============================================================================

--- 构建皮肤标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
local function BuildSkinTab(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    return UI.Panel {
        width = "100%",
        alignItems = "center", justifyContent = "center",
        paddingTop = 40, paddingBottom = 40,
        children = {
            UI.Label { text = "皮肤系统", fontSize = 16, fontColor = S.dim },
            UI.Label { text = "敬请期待", fontSize = 13, fontColor = S.dimLocked, marginTop = 6 },
        },
    }
end

-- ============================================================================
-- 标签页：时装
-- ============================================================================

--- 构建时装标签页内容
---@param ctx table
---@param heroId string
local function BuildCostumeTab(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local CostumeData = require("Game.CostumeData")

    -- 从精灵图裁出单帧作为图标
    -- size: 显示尺寸(px), def: 时装定义, frameIdx: 0-based 帧索引
    local function FrameIcon(size, def, frameIdx)
        local cols   = def.gridCols or 2
        local rows   = def.gridRows or 2
        local fCol   = frameIdx % cols
        local fRow   = math.floor(frameIdx / cols)
        local sheetW = size * cols
        local sheetH = size * rows
        return UI.Panel {
            position = "absolute",
            left = -fCol * size,
            top  = -fRow * size,
            width  = sheetW,
            height = sheetH,
            backgroundImage = def.preview,
            backgroundFit = "fill",
        }
    end

    local RARITY_COLOR = Config.RARITY_COLORS

    -- ── 系统说明浮层 ──────────────────────────────────────────────────────────
    local _infoOverlay = nil
    local function ShowCostumeInfoPopup()
        if _infoOverlay then return end
        local pageRoot = ctx.GetPageRoot()
        if not pageRoot then return end

        local function closePopup()
            if _infoOverlay then
                pageRoot:RemoveChild(_infoOverlay)
                _infoOverlay = nil
            end
        end

        -- 动态生成图鉴加成描述行
        local bonusRows = {}
        local totalAtk = 0
        for _, slot in ipairs(CostumeData.SLOTS) do
            if slot.costumes then
                for _, def in ipairs(slot.costumes) do
                    if def.owned and def.atkBonus and def.atkBonus > 0 then
                        totalAtk = totalAtk + def.atkBonus
                        bonusRows[#bonusRows + 1] = UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            gap = 8, paddingTop = 3, paddingBottom = 3,
                            children = {
                                UI.Panel {
                                    width = 4, height = 4, borderRadius = 2,
                                    backgroundColor = { 160, 100, 255, 255 },
                                },
                                UI.Label {
                                    text = def.name,
                                    fontSize = 12,
                                    fontColor = def.rarityColor or { 200, 180, 255, 255 },
                                },
                                UI.Label {
                                    text = string.format("全英雄攻击 +%.0f%%", def.atkBonus * 100),
                                    fontSize = 12,
                                    fontColor = { 120, 220, 120, 255 },
                                },
                            },
                        }
                    end
                end
            end
        end
        if #bonusRows == 0 then
            bonusRows[#bonusRows + 1] = UI.Label {
                text = "暂无已解锁时装加成",
                fontSize = 12,
                fontColor = { 140, 130, 150, 200 },
            }
        end

        _infoOverlay = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 0, 0, 0, 160 },
            pointerEvents = "auto",
            zIndex = 300,
            onClick = function() closePopup() end,
            children = {
                UI.Panel {
                    width = 280,
                    backgroundColor = { 28, 20, 42, 252 },
                    borderRadius = 14,
                    borderWidth = 2,
                    borderColor = { 140, 90, 220, 200 },
                    paddingTop = 18, paddingBottom = 18,
                    paddingLeft = 18, paddingRight = 18,
                    gap = 10,
                    pointerEvents = "auto",
                    onClick = function() end,   -- 阻止冒泡关闭
                    children = {
                        -- 标题行
                        UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            justifyContent = "space-between",
                            children = {
                                UI.Label {
                                    text = "时装图鉴系统",
                                    fontSize = 16, fontWeight = "bold",
                                    fontColor = { 200, 160, 255, 255 },
                                },
                                UI.Panel {
                                    paddingLeft = 8, paddingRight = 8,
                                    paddingTop = 4, paddingBottom = 4,
                                    pointerEvents = "auto",
                                    onClick = function() closePopup() end,
                                    children = {
                                        UI.Label { text = "✕", fontSize = 14, fontColor = { 160, 140, 180, 200 } },
                                    },
                                },
                            },
                        },
                        -- 分割线
                        UI.Panel { width = "100%", height = 1, backgroundColor = { 100, 70, 150, 100 } },
                        -- 说明文字
                        UI.Label {
                            text = "解锁时装即可永久获得图鉴加成，无需装备槽位。",
                            fontSize = 12,
                            fontColor = { 190, 175, 210, 230 },
                            flexWrap = "wrap",
                        },
                        UI.Label {
                            text = "收集更多时装，加成效果可叠加。",
                            fontSize = 12,
                            fontColor = { 190, 175, 210, 230 },
                        },
                        -- 分割线
                        UI.Panel { width = "100%", height = 1, backgroundColor = { 100, 70, 150, 100 } },
                        -- 当前图鉴加成标题
                        UI.Label {
                            text = string.format("当前图鉴加成  全英雄攻击 +%.0f%%", totalAtk * 100),
                            fontSize = 13, fontWeight = "bold",
                            fontColor = { 120, 220, 120, 255 },
                        },
                        -- 各时装加成明细
                        UI.Panel {
                            width = "100%", gap = 2,
                            children = bonusRows,
                        },
                    },
                },
            },
        }
        pageRoot:AddChild(_infoOverlay)
    end

    local children = {}

    -- ── 装备槽位行（水平一行显示所有槽位） ──────────────────────────────────
    local function MakeSlotCell(slotDef)
        local def = CostumeData.GetEquippedDef(slotDef.id)
        local bc = def and (def.rarityColor or { 120, 80, 200, 200 }) or { 70, 55, 42, 150 }
        -- 图标内容
        local iconContent
        if def then
            if slotDef.id == "wing" then
                iconContent = { FrameIcon(40, def, def.iconFrame or 0) }
            else
                iconContent = { UI.Panel { width = 40, height = 40, backgroundImage = def.preview, backgroundFit = "contain" } }
            end
        else
            local slotLabels = { wing = "翼", weapon = "武", aura = "环", particle = "粒" }
            local label = slotLabels[slotDef.id] or "?"
            iconContent = { UI.Label { text = label, fontSize = 14, fontColor = { 100, 80, 65, 200 } } }
        end
        return UI.Panel {
            flexGrow = 1, flexShrink = 1, flexBasis = 0,
            flexDirection = "column",
            alignItems = "center",
            gap = 4,
            backgroundColor = { 40, 28, 20, 220 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = def and bc or { 90, 65, 48, 200 },
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 6, paddingRight = 6,
            children = {
                -- 图标
                UI.Panel {
                    width = 40, height = 40,
                    borderRadius = 8,
                    backgroundColor = { 55, 38, 28, 255 },
                    borderWidth = 1,
                    borderColor = bc,
                    justifyContent = "center", alignItems = "center",
                    overflow = "hidden",
                    children = iconContent,
                },
                -- 槽位名
                UI.Label { text = slotDef.label, fontSize = 10, fontColor = S.dim },
                -- 装备名 / 空置
                UI.Label {
                    text = def and def.name or "空置",
                    fontSize = 11,
                    fontColor = def and (def.rarityColor or S.white) or S.dimLocked,
                    fontWeight = def and "bold" or "normal",
                },
                -- 卸下按钮
                def and UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 3, paddingBottom = 3,
                    borderRadius = 5,
                    backgroundColor = { 70, 50, 38, 200 },
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        CostumeData.Equip(slotDef.id, nil)
                        ctx.ShowHeroDetail(heroId)
                    end,
                    children = {
                        UI.Label { text = "卸下", fontSize = 10, fontColor = { 180, 160, 140, 220 } },
                    },
                } or nil,
            },
        }
    end

    local slotCells = {}
    for _, slotDef in ipairs(CostumeData.SLOTS) do
        slotCells[#slotCells + 1] = MakeSlotCell(slotDef)
    end

    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        children = slotCells,
    }

    -- ── 翅膀分类列表 ──────────────────────────────────────────────────────────
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 10,
        pointerEvents = "auto",
        children = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = { 160, 100, 255, 255 } },
            UI.Label { text = "翅膀", fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
            UI.Panel { flex = 1 },
            UI.Panel {
                width = 18, height = 18,
                borderRadius = 9,
                borderWidth = 1,
                borderColor = { 140, 100, 200, 180 },
                backgroundColor = { 50, 35, 75, 200 },
                justifyContent = "center", alignItems = "center",
                onClick = function() ShowCostumeInfoPopup() end,
                children = {
                    UI.Label { text = "?", fontSize = 10, fontWeight = "bold", fontColor = { 180, 140, 240, 255 }, pointerEvents = "none" },
                },
            },
        },
    }

    -- 翅膀时装卡片列表
    for _, def in ipairs(CostumeData.WING_COSTUMES) do
        local isOwned = CostumeData.IsOwned(def.id)
        local isEquipped = CostumeData.IsEquipped("wing", def.id)
        local rc = def.rarityColor or RARITY_COLOR[def.rarity] or { 180, 180, 180, 255 }

        local card = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and { 50, 35, 65, 240 } or (isOwned and { 38, 27, 20, 200 } or { 28, 24, 32, 180 }),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and { 70, 55, 42, 120 } or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            children = {
                -- 预览图（裁出单帧）
                UI.Panel {
                    width = 54, height = 54,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 30, 20, 40, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    overflow = "hidden",
                    children = {
                        FrameIcon(54, def, def.iconFrame or 0),
                        -- 稀有度标签
                        UI.Panel {
                            position = "absolute",
                            top = 2, left = 2,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { 0, 0, 0, 160 },
                            children = {
                                UI.Label { text = def.rarity or "N", fontSize = 8, fontColor = rc, fontWeight = "bold" },
                            },
                        },
                    },
                },
                -- 名称 + 描述
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label { text = def.name, fontSize = 13, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = { 180, 165, 150, 180 } },
                    },
                },
                -- 装备按钮
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and { 80, 55, 110, 240 }
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            CostumeData.Equip("wing", def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and { 200, 170, 255, 220 }
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
        children[#children + 1] = card
    end

    -- ── 武器分类标题 ──────────────────────────────────────────────────────────
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 10,
        children = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = { 255, 180, 50, 255 } },
            UI.Label { text = "武器", fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
        },
    }

    -- ── 武器时装卡片列表 ──────────────────────────────────────────────────────
    for _, def in ipairs(CostumeData.WEAPON_COSTUMES) do
        local isOwned = CostumeData.IsOwned(def.id)
        local isEquipped = CostumeData.IsEquipped("weapon", def.id)
        local rc = def.rarityColor or RARITY_COLOR[def.rarity] or { 180, 180, 180, 255 }

        local wcard = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and { 50, 40, 25, 240 } or (isOwned and { 38, 27, 20, 200 } or { 28, 24, 32, 180 }),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and { 70, 55, 42, 120 } or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            children = {
                UI.Panel {
                    width = 54, height = 54,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 30, 20, 40, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = 54, height = 54,
                            backgroundImage = def.preview,
                            backgroundFit = "contain",
                        },
                        UI.Panel {
                            position = "absolute",
                            top = 2, left = 2,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { 0, 0, 0, 160 },
                            children = {
                                UI.Label { text = def.rarity or "N", fontSize = 8, fontColor = rc, fontWeight = "bold" },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label { text = def.name, fontSize = 13, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = { 180, 165, 150, 180 } },
                    },
                },
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and { 80, 55, 110, 240 }
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            CostumeData.Equip("weapon", def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and { 200, 170, 255, 220 }
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
        children[#children + 1] = wcard
    end

    -- ── 光环分类标题 ──────────────────────────────────────────────────────────
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 10,
        children = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = { 200, 160, 255, 255 } },
            UI.Label { text = "光环", fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
        },
    }

    -- ── 光环时装卡片列表 ──────────────────────────────────────────────────────
    for _, def in ipairs(CostumeData.AURA_COSTUMES) do
        local isOwned = CostumeData.IsOwned(def.id)
        local isEquipped = CostumeData.IsEquipped("aura", def.id)
        local rc = def.rarityColor or RARITY_COLOR[def.rarity] or { 180, 180, 180, 255 }

        local acard = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and { 50, 40, 25, 240 } or (isOwned and { 38, 27, 20, 200 } or { 28, 24, 32, 180 }),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and { 70, 55, 42, 120 } or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            children = {
                UI.Panel {
                    width = 54, height = 54,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 30, 20, 40, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = 54, height = 54,
                            backgroundImage = def.preview,
                            backgroundFit = "contain",
                        },
                        UI.Panel {
                            position = "absolute",
                            top = 2, left = 2,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { 0, 0, 0, 160 },
                            children = {
                                UI.Label { text = def.rarity or "N", fontSize = 8, fontColor = rc, fontWeight = "bold" },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label { text = def.name, fontSize = 13, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = { 180, 165, 150, 180 } },
                    },
                },
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and { 80, 55, 110, 240 }
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            CostumeData.Equip("aura", def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and { 200, 170, 255, 220 }
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
        children[#children + 1] = acard
    end

    -- ── 粒子光效分类标题 ──────────────────────────────────────────────────────
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 10,
        pointerEvents = "auto",
        children = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = { 120, 200, 255, 255 } },
            UI.Label { text = "粒子光效", fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
        },
    }

    -- ── 粒子光效时装卡片列表 ──────────────────────────────────────────────────
    for _, def in ipairs(CostumeData.PARTICLE_COSTUMES) do
        local isOwned = CostumeData.IsOwned(def.id)
        local isEquipped = CostumeData.IsEquipped("particle", def.id)
        local rc = def.rarityColor or RARITY_COLOR[def.rarity] or { 180, 180, 180, 255 }

        local pcard = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and { 25, 40, 55, 240 } or (isOwned and { 20, 30, 38, 200 } or { 28, 24, 32, 180 }),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and { 42, 60, 70, 120 } or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            children = {
                UI.Panel {
                    width = 54, height = 54,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 20, 30, 45, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = 54, height = 54,
                            backgroundImage = def.preview,
                            backgroundFit = "contain",
                        },
                        UI.Panel {
                            position = "absolute",
                            top = 2, left = 2,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { 0, 0, 0, 160 },
                            children = {
                                UI.Label { text = def.rarity or "N", fontSize = 8, fontColor = rc, fontWeight = "bold" },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label { text = def.name, fontSize = 13, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = { 150, 175, 200, 180 } },
                    },
                },
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and { 55, 80, 110, 240 }
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            CostumeData.Equip("particle", def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and { 170, 200, 255, 220 }
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
        children[#children + 1] = pcard
    end

    return UI.Panel {
        width = "100%",
        gap = 6,
        pointerEvents = "auto",
        children = children,
    }
end

-- ============================================================================
-- 称号标签页
-- ============================================================================

--- 构建称号标签页内容
---@param ctx table
---@param heroId string
local function BuildTitleTab(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local TitleData = require("Game.TitleData")

    local RARITY_ORDER = { N = 1, R = 2, SR = 3, SSR = 4, UR = 5, LR = 6 }
    local children = {}

    -- ── 当前装备称号槽 ──────────────────────────────────────────────────────
    local equippedDef = TitleData.GetEquippedDef()
    local slotBorder = equippedDef and equippedDef.borderColor or { 70, 55, 42, 150 }
    local slotRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 10,
        backgroundColor = { 40, 28, 20, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = slotBorder,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        children = {
            -- 称号图标
            UI.Panel {
                width = 44, height = 44,
                flexShrink = 0,
                borderRadius = 8,
                backgroundColor = equippedDef and { 45, 30, 60, 255 } or { 55, 38, 28, 255 },
                borderWidth = 1,
                borderColor = slotBorder,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = equippedDef and "称" or "称",
                        fontSize = equippedDef and 16 or 18,
                        fontColor = equippedDef and equippedDef.color or { 100, 80, 65, 200 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 称号名 + 状态
            UI.Panel {
                flexGrow = 1,
                gap = 2,
                children = {
                    UI.Label { text = "称号", fontSize = 12, fontColor = S.dim },
                    UI.Label {
                        text = equippedDef and equippedDef.name or "空置",
                        fontSize = 14,
                        fontColor = equippedDef and equippedDef.color or S.dimLocked,
                        fontWeight = equippedDef and "bold" or "normal",
                    },
                },
            },
            -- 加成提示
            equippedDef and UI.Panel {
                gap = 1,
                children = (function()
                    local bonusLabels = {}
                    local bonusNames = {
                        atkPct = "攻击", spdPct = "攻速", critRate = "暴击",
                        critDmg = "暴伤", armorPen = "穿甲", scorePct = "排行",
                    }
                    for k, v in pairs(equippedDef.bonuses or {}) do
                        if v > 0 then
                            bonusLabels[#bonusLabels + 1] = UI.Label {
                                text = (bonusNames[k] or k) .. string.format("+%.0f%%", v * 100),
                                fontSize = 9,
                                fontColor = { 120, 220, 120, 255 },
                            }
                        end
                    end
                    return bonusLabels
                end)(),
            } or nil,
            -- 卸下按钮
            equippedDef and UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 6,
                backgroundColor = { 70, 50, 38, 200 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    TitleData.Unequip()
                    ctx.ShowHeroDetail(heroId)
                end,
                children = {
                    UI.Label { text = "卸下", fontSize = 11, fontColor = { 180, 160, 140, 220 } },
                },
            } or nil,
        },
    }
    children[#children + 1] = slotRow

    -- ── 称号分类标题 ────────────────────────────────────────────────────────
    local ownedCount = 0
    for _, def in ipairs(TitleData.TITLES) do
        if TitleData.IsOwned(def.id) then ownedCount = ownedCount + 1 end
    end
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 10,
        children = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = { 255, 200, 60, 255 } },
            UI.Label { text = "称号图鉴", fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
            UI.Panel { flex = 1 },
            UI.Label {
                text = ownedCount .. "/" .. #TitleData.TITLES,
                fontSize = 11, fontColor = { 160, 140, 120, 180 },
            },
        },
    }

    -- ── 称号卡片列表 ────────────────────────────────────────────────────────
    -- 排序：已拥有在前，按品质从高到低
    local sortedTitles = {}
    for _, def in ipairs(TitleData.TITLES) do
        sortedTitles[#sortedTitles + 1] = def
    end
    table.sort(sortedTitles, function(a, b)
        local aOwned = TitleData.IsOwned(a.id) and 1 or 0
        local bOwned = TitleData.IsOwned(b.id) and 1 or 0
        if aOwned ~= bOwned then return aOwned > bOwned end
        return (RARITY_ORDER[a.rarity] or 0) > (RARITY_ORDER[b.rarity] or 0)
    end)

    for _, def in ipairs(sortedTitles) do
        local isOwned = TitleData.IsOwned(def.id)
        local isEquipped = TitleData.IsEquipped(def.id)
        local rc = def.color or { 180, 180, 180, 255 }
        local bc = def.borderColor or { 100, 100, 100, 180 }

        -- 加成描述行
        local bonusText = {}
        local bonusNames = {
            atkPct = "攻击", spdPct = "攻速", critRate = "暴击",
            critDmg = "暴伤", armorPen = "穿甲", scorePct = "排行",
        }
        for k, v in pairs(def.bonuses or {}) do
            if v > 0 then
                bonusText[#bonusText + 1] = (bonusNames[k] or k) .. string.format("+%.0f%%", v * 100)
            end
        end
        local bonusStr = #bonusText > 0 and table.concat(bonusText, "  ") or ""

        -- 获得时间
        local timeStr = ""
        if isOwned then
            local ts = TitleData.GetAcquiredTime(def.id)
            if ts and ts > 0 then
                timeStr = os.date("%Y-%m-%d", ts)
            end
        end

        local card = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and { 50, 35, 65, 240 }
                or (isOwned and { 38, 27, 20, 200 } or { 28, 24, 32, 180 }),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and bc or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            opacity = isOwned and 1.0 or 0.6,
            children = {
                -- 称号图标
                UI.Panel {
                    width = 50, height = 50,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 30, 20, 40, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label {
                            text = "称",
                            fontSize = 18,
                            fontColor = rc,
                            fontWeight = "bold",
                        },
                        -- 稀有度标签
                        UI.Panel {
                            position = "absolute",
                            top = 2, left = 2,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { 0, 0, 0, 160 },
                            children = {
                                UI.Label { text = def.rarity or "N", fontSize = 8, fontColor = rc, fontWeight = "bold" },
                            },
                        },
                    },
                },
                -- 名称 + 描述 + 加成 + 时间
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label { text = def.name, fontSize = 14, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = { 180, 165, 150, 180 } },
                        bonusStr ~= "" and UI.Label {
                            text = bonusStr,
                            fontSize = 10,
                            fontColor = isOwned and { 120, 220, 120, 200 } or { 100, 100, 100, 150 },
                        } or nil,
                        timeStr ~= "" and UI.Label {
                            text = "获得: " .. timeStr,
                            fontSize = 9,
                            fontColor = { 140, 130, 120, 150 },
                        } or nil,
                    },
                },
                -- 装备按钮
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and { 80, 55, 110, 240 }
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            TitleData.Equip(def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and { 200, 170, 255, 220 }
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
        children[#children + 1] = card
    end

    return UI.Panel {
        width = "100%",
        gap = 6,
        pointerEvents = "auto",
        children = children,
    }
end

-- ============================================================================
-- 神圣遗物标签页
-- ============================================================================

--- 构建神圣遗物标签页（仅主角可用）
---@param ctx table
---@param heroId string
---@return any UI.Panel
local function BuildRelicTab(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local FormatBigNum = ctx.FormatBigNum

    local children = {}

    -- ── Section 1: 横排 4 个 1:1 装备槽 ──────────────────────────────────────
    local slotPanels = {}
    for _, slotDef in ipairs(Config.RELIC_SLOTS) do
        local slotId = slotDef.id
        local equipped = RelicData.GetEquipped(slotId)
        local isSelected = (selectedRelicSlot == slotId)

        -- 槽内内容：顶部名称 + 中间图标 + 底部等级
        local titleText, titleColor
        if equipped then
            local def = Config.RELICS[equipped.id]
            titleText = def and def.name or equipped.id
            titleColor = Config.RELIC_QUALITY_COLOR[equipped.quality] or S.gold
        else
            titleText = slotDef.name
            titleColor = { 120, 100, 80 }
        end

        local relicImage = (equipped and Config.RELICS[equipped.id] and Config.RELICS[equipped.id].image) or slotDef.icon

        slotPanels[#slotPanels + 1] = UI.Panel {
            flex = 1,
            aspectRatio = 1,
            margin = 3,
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and S.gold or { 70, 55, 40, 150 },
            backgroundColor = isSelected and { 70, 55, 35, 240 } or { 50, 38, 28, 200 },
            overflow = "hidden",
            onClick = function(self)
                selectedRelicSlot = slotId
                selectedRelicView = nil
                ctx.ShowHeroDetail(heroId)
            end,
            children = {
                -- 上：标题
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 2, paddingBottom = 1,
                    children = {
                        UI.Label { text = titleText, fontSize = 9, fontColor = titleColor, fontWeight = "bold", textAlign = "center" },
                    },
                },
                -- 中：图片铺满（1:1，铺满高度）
                UI.Panel {
                    flex = 1, aspectRatio = 1, alignSelf = "center",
                    backgroundImage = relicImage, backgroundSize = "cover",
                    opacity = equipped and 1.0 or 0.25,
                },
                -- 下：等级/星级
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 1, paddingBottom = 2,
                    children = {
                        equipped and UI.Label {
                            text = "Lv." .. equipped.level .. " ★" .. equipped.star,
                            fontSize = 8, fontColor = { 200, 180, 160 },
                        } or UI.Label { text = "空", fontSize = 8, fontColor = { 80, 70, 60 } },
                    },
                },
            },
        }
    end
    children[#children + 1] = UI.Panel {
        width = "100%", flexDirection = "row",
        children = slotPanels,
    }

    -- ── Section 3: 遗物详情面板（始终显示） ──────────────────────────────────
    local eqRelic = RelicData.GetEquipped(selectedRelicSlot)

    -- 确定当前预览的遗物：优先 selectedRelicView，否则显示已装备
    if not selectedRelicView and eqRelic then
        selectedRelicView = { id = eqRelic.id, quality = eqRelic.quality }
    end

    -- 格式化 desc 模板：将 {paramKey} 替换为缩放后的实际数值
    -- 不应被 V() 缩放的机制参数（概率、上限、间隔、持续时间、次数、比率）
    local FIXED_KEYS = {
        armorPenCap = true, executeCap = true, doubleCastCap = true,
        doubleCastChance = true, executeThreshold = true,
        pulseInterval = true, postCastDuration = true,
        burnDuration = true, burnTicks = true,
        markInterval = true, markDuration = true, autoMarkInterval = true,
        markCount = true, otherAtkRatio = true,
    }
    -- 固定参数 → 对应的星级效果类型（用于将星级加成合并显示到描述中）
    local PARAM_STAR_MAP = {
        doubleCastChance = "chanceAdd",
        pulseInterval = "intervalReduce",
        postCastDuration = "durationAdd",
        markDuration = "durationAdd",
        autoMarkInterval = "intervalReduce",
    }
    local function FormatRelicDesc(relic, def)
        if not def or not def.desc then return "" end
        return (def.desc:gsub("{(%w+)}", function(key)
            local base = def.params and def.params[key]
            if not base then return "{" .. key .. "}" end
            local val = FIXED_KEYS[key] and base or RelicCalc.V(relic, base)
            -- 将星级加成合并到固定参数的显示值中
            local starType = PARAM_STAR_MAP[key]
            if starType and def.starEffect and def.starEffect.type == starType then
                local sv = RelicCalc.StarValue(relic.star, def.starEffect)
                if starType == "intervalReduce" then
                    val = val - sv
                else
                    val = val + sv
                end
            end
            if val < 1 then
                return string.format("%.0f%%", val * 100)
            elseif val == math.floor(val) then
                return string.format("%d", val)
            else
                return string.format("%.1f", val)
            end
        end))
    end

    if selectedRelicView then
        local viewId = selectedRelicView.id
        local viewQuality = selectedRelicView.quality
        local viewDef = Config.RELICS[viewId]

        -- 判断当前预览的是否就是已装备的遗物
        local isViewingEquipped = eqRelic and eqRelic.id == viewId
        -- 用于显示的遗物数据（已装备用真实数据，未装备从 progress 读取）
        local viewRelic
        if isViewingEquipped then
            viewRelic = eqRelic
        else
            local pLv, pStar = RelicData.GetProgress(viewId)
            viewRelic = { id = viewId, quality = viewQuality, level = pLv, star = pStar }
        end

        local qColor = Config.RELIC_QUALITY_COLOR[viewRelic.quality] or S.gold
        local qName = Config.RELIC_QUALITY_NAME[viewRelic.quality] or "?"

        -- 左侧：遗物描述
        local descText = FormatRelicDesc(viewRelic, viewDef)
        local descChildren = {
            UI.Label {
                text = (viewDef and viewDef.name or viewId),
                fontSize = 15, fontColor = qColor, fontWeight = "bold",
            },
        }
        local isViewOwned = RelicData.IsOwned(viewId)
        if isViewingEquipped then
            descChildren[#descChildren + 1] = UI.Label {
                text = qName .. " · Lv." .. viewRelic.level .. " · ★" .. viewRelic.star,
                fontSize = 11, fontColor = { 200, 180, 160 }, marginBottom = 4,
            }
        elseif isViewOwned then
            descChildren[#descChildren + 1] = UI.Label {
                text = qName .. " · Lv." .. viewRelic.level .. " · ★" .. viewRelic.star .. " · 未装备",
                fontSize = 11, fontColor = { 160, 140, 120 }, marginBottom = 4,
            }
        else
            local viewShards = RelicData.GetShards(viewId)
            local viewSynthCost = Config.RELIC_SYNTH_COST[viewDef and viewDef.minQuality or "green"] or 80
            descChildren[#descChildren + 1] = UI.Label {
                text = "未拥有 · 碎片 " .. viewShards .. "/" .. viewSynthCost,
                fontSize = 11, fontColor = { 120, 110, 90 }, marginBottom = 4,
            }
        end
        descChildren[#descChildren + 1] = UI.Label {
            text = descText,
            fontSize = 11, fontColor = { 200, 195, 180 },
            lineHeight = 1.4,
        }

        -- 星级效果描述
        if viewDef and viewDef.starEffect then
            local starVal = RelicCalc.FormatStarValue(viewRelic.star, viewDef.starEffect)
            local starDesc = viewDef.starEffect.desc:gsub("{v}", function() return starVal end)
            descChildren[#descChildren + 1] = UI.Label {
                text = starDesc,
                fontSize = 11, fontColor = { 255, 220, 100 },
                marginTop = 4,
            }
        end

        -- 右侧：按钮列（升级 / 升星 / 卸下或装备）—— 仅已拥有时显示
        local btnChildren = {}
        local upgradeCost = RelicCalc.GetUpgradeCost(viewRelic.level)
        local essence = HeroData.currencies.relic_essence or 0
        local canUpgrade = isViewOwned and essence >= upgradeCost
        local starCost = RelicCalc.GetStarUpShardCost(viewRelic.star)
        local shards = RelicData.GetShards(viewId)
        local canStarUp = isViewOwned and shards >= starCost

        if not isViewOwned then
            -- 未拥有：不显示任何按钮
        else
        -- 升级
        btnChildren[#btnChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 7, paddingBottom = 7,
            borderRadius = 8, overflow = "visible",
            backgroundColor = canUpgrade and { 60, 140, 100, 240 } or { 60, 55, 50, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function(self)
                if not canUpgrade then ShowToast("遗物精华不足") return end
                local ok, msg = RelicData.UpgradeByRelicId(viewId)
                ShowToast(msg)
                if ctx._refreshTab then ctx._refreshTab() else ctx.ShowHeroDetail(heroId) end
            end,
            children = {
                UI.Label { text = "升级", fontSize = 12, fontColor = canUpgrade and { 255, 255, 255 } or { 120, 110, 100 }, fontWeight = "bold" },
                UI.Label { text = FormatBigNum(upgradeCost) .. "精华", fontSize = 9, numberOfLines = 1, fontColor = canUpgrade and { 200, 240, 200 } or { 100, 90, 80 } },
            },
        }
        -- 升星
        btnChildren[#btnChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 7, paddingBottom = 7,
            borderRadius = 8, overflow = "visible",
            backgroundColor = canStarUp and { 180, 140, 40, 240 } or { 60, 55, 50, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function(self)
                if not canStarUp then ShowToast("碎片不足") return end
                local ok, msg = RelicData.StarUpByRelicId(viewId)
                ShowToast(msg)
                if ctx._refreshTab then ctx._refreshTab() else ctx.ShowHeroDetail(heroId) end
            end,
            children = {
                UI.Label { text = "升星", fontSize = 12, fontColor = canStarUp and { 255, 255, 255 } or { 120, 110, 100 }, fontWeight = "bold" },
                UI.Label { text = FormatBigNum(shards) .. "/" .. FormatBigNum(starCost) .. "碎片", fontSize = 9, numberOfLines = 1, fontColor = canStarUp and { 255, 240, 180 } or { 100, 90, 80 } },
            },
        }
        -- 卸下 / 装备
        if isViewingEquipped then
            btnChildren[#btnChildren + 1] = UI.Panel {
                width = "100%",
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 8,
                backgroundColor = { 120, 50, 50, 220 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    RelicData.Unequip(selectedRelicSlot)
                    selectedRelicView = nil
                    ShowToast("已卸下")
                    ctx.ShowHeroDetail(heroId)
                end,
                children = {
                    UI.Label { text = "卸下", fontSize = 11, fontColor = { 255, 180, 160 } },
                },
            }
        else
            btnChildren[#btnChildren + 1] = UI.Panel {
                width = "100%",
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 8,
                backgroundColor = { 60, 140, 100, 240 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    local ok, msg = RelicData.Equip(selectedRelicSlot, viewId, viewQuality)
                    if ok then
                        selectedRelicView = { id = viewId, quality = viewQuality }
                        ShowToast((viewDef and viewDef.name or viewId) .. " 装备成功")
                    else
                        ShowToast(msg)
                    end
                    ctx.ShowHeroDetail(heroId)
                end,
                children = {
                    UI.Label { text = "装备", fontSize = 11, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
                },
            }
        end
        end -- if isViewOwned

        local btnCol = UI.Panel {
            width = 72, gap = 5,
            justifyContent = "center",
            children = btnChildren,
        }

        children[#children + 1] = UI.Panel {
            width = "100%", marginTop = 8,
            paddingTop = 10, paddingBottom = 10,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = { 45, 34, 24, 230 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = qColor,
            flexDirection = "row", gap = 10,
            children = {
                UI.Panel {
                    flex = 1, gap = 2,
                    children = descChildren,
                },
                btnCol,
            },
        }
    else
        -- 没有选中任何遗物时的空状态提示
        children[#children + 1] = UI.Panel {
            width = "100%", marginTop = 8,
            paddingTop = 16, paddingBottom = 16,
            backgroundColor = { 45, 34, 24, 230 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = { 70, 55, 40, 150 },
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "点击下方遗物查看详情", fontSize = 12, fontColor = { 140, 120, 100 } },
            },
        }
    end

    -- ── Section 4: 遗物背包网格（横排，点击预览） ──────────────────────────
    local slotRelics = Config.RELICS_BY_SLOT[selectedRelicSlot] or {}
    -- 按品质排序：已拥有按品质降序靠前，未拥有按最低品质降序靠后
    local sortedRelics = {}
    for _, rDef in ipairs(slotRelics) do sortedRelics[#sortedRelics + 1] = rDef end
    table.sort(sortedRelics, function(a, b)
        local aOwned = RelicData.IsOwned(a.id) and 1 or 0
        local bOwned = RelicData.IsOwned(b.id) and 1 or 0
        if aOwned ~= bOwned then return aOwned > bOwned end
        local aQ = Config.RELIC_QUALITY_INDEX[RelicData.GetOwnedQuality(a.id) or a.minQuality] or 1
        local bQ = Config.RELIC_QUALITY_INDEX[RelicData.GetOwnedQuality(b.id) or b.minQuality] or 1
        return aQ > bQ
    end)
    local catalogCells = {}
    for _, rDef in ipairs(sortedRelics) do
        local isOwned = RelicData.IsOwned(rDef.id)
        local ownedQuality = RelicData.GetOwnedQuality(rDef.id)
        local isEquipped = eqRelic and eqRelic.id == rDef.id
        local isViewing = selectedRelicView and selectedRelicView.id == rDef.id

        -- 已拥有用实际品质颜色，未拥有用灰色
        local displayQuality = ownedQuality or rDef.minQuality
        local qColor = isOwned and (Config.RELIC_QUALITY_COLOR[displayQuality] or { 180, 180, 180 }) or { 80, 70, 60 }
        local qName = Config.RELIC_QUALITY_NAME[displayQuality] or "?"

        -- 高亮优先级：正在预览 > 已装备 > 已拥有 > 未拥有(锁定)
        local cellBorder, cellBg, cellBorderW
        if isViewing and isOwned then
            cellBorder = S.gold
            cellBg = { 65, 52, 30, 240 }
            cellBorderW = 2
        elseif isEquipped then
            cellBorder = { 100, 200, 100, 180 }
            cellBg = { 55, 48, 32, 230 }
            cellBorderW = 2
        elseif isOwned then
            cellBorder = { 70, 55, 40, 150 }
            cellBg = { 50, 38, 28, 200 }
            cellBorderW = 1
        else
            cellBorder = { 40, 35, 30, 120 }
            cellBg = { 30, 25, 20, 180 }
            cellBorderW = 1
        end

        -- 底部标签
        local bottomLabel
        local cardLv, cardStar = RelicData.GetProgress(rDef.id)
        if isEquipped then
            bottomLabel = UI.Label { text = "Lv." .. cardLv .. " ★" .. cardStar, fontSize = 8, fontColor = { 100, 200, 100 }, fontWeight = "bold" }
        elseif isOwned then
            bottomLabel = UI.Label { text = "Lv." .. cardLv .. " ★" .. cardStar, fontSize = 8, fontColor = qColor }
        else
            -- 未拥有：显示碎片数量
            local shardCount = RelicData.GetShards(rDef.id)
            local synthCost = Config.RELIC_SYNTH_COST[rDef.minQuality] or 80
            local shardColor = shardCount >= synthCost and { 100, 220, 100 } or { 120, 110, 90 }
            bottomLabel = UI.Label {
                text = "碎片 " .. shardCount .. "/" .. synthCost,
                fontSize = 8, fontColor = shardColor,
            }
        end

        catalogCells[#catalogCells + 1] = UI.Panel {
            width = "23%",
            aspectRatio = 1,
            margin = "1%",
            borderRadius = 8,
            borderWidth = cellBorderW,
            borderColor = cellBorder,
            backgroundColor = cellBg,
            overflow = "hidden",
            onClick = function(self)
                selectedRelicView = { id = rDef.id, quality = ownedQuality or rDef.minQuality }
                ctx.ShowHeroDetail(heroId)
            end,
            children = {
                -- 上：名称
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 2, paddingBottom = 1,
                    children = {
                        UI.Label { text = rDef.name, fontSize = 10, fontColor = qColor, fontWeight = isOwned and "bold" or "normal", textAlign = "center" },
                    },
                },
                -- 中：图片铺满（1:1，铺满高度）
                UI.Panel {
                    flex = 1, aspectRatio = 1, alignSelf = "center",
                    backgroundImage = rDef.image or "", backgroundSize = "cover",
                    opacity = isOwned and 1.0 or 0.25,
                },
                -- 下：等级/碎片信息
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 1, paddingBottom = 2,
                    children = { bottomLabel },
                },
            },
        }
    end

    -- ── Section 5: 底部货币栏（仅精华） ─────────────────────────────────────
    local essenceAmt = HeroData.currencies.relic_essence or 0

    local currencyBar = UI.Panel {
        width = "100%", marginTop = 4,
        flexDirection = "row",
        justifyContent = "flex-end", alignItems = "center",
        paddingTop = 8, paddingBottom = 8, paddingRight = 12,
        backgroundColor = { 35, 26, 18, 200 },
        borderRadius = 8,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    Currency.IconWidget(UI, "relic_essence", 16),
                    UI.Label { text = FormatBigNum(essenceAmt), fontSize = 12, fontColor = { 255, 215, 100 } },
                },
            },
        },
    }

    -- ── 组装：上部固定 + 中部背包可滚动 + 底部货币栏固定 ────────────────────
    -- children 目前包含：槽位栏(Section1) + 详情面板(Section3)，都固定不动
    local fixedTop = UI.Panel {
        width = "100%", gap = 4,
        flexShrink = 0,
        children = children,
    }

    local inventoryScroll = UI.ScrollView {
        flexGrow = 1, flexBasis = 0,
        scrollY = true,
        width = "100%",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%", gap = 2,
                paddingBottom = 6,
                children = {
                    UI.Label { text = "可用遗物", fontSize = 12, fontColor = S.gold, fontWeight = "bold", marginBottom = 2 },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        children = catalogCells,
                    },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%",
        minHeight = "100%",
        flexGrow = 1,
        gap = 4,
        children = {
            fixedTop,
            inventoryScroll,
            currencyBar,
        },
    }
end

-- ============================================================================
-- 详情面板刷新
-- ============================================================================

--- 刷新详情面板内容区域（切换标签时调用）
---@param ctx table
---@param heroId string
---@param heroDef table
local function RefreshDetailContent(ctx, heroId, heroDef)
    if not detailContentContainer then return end
    detailContentContainer:ClearChildren()

    local content
    if detailTab == "info" then
        content = BuildInfoTab(ctx, heroId, heroDef)
    elseif detailTab == "equip" then
        content = BuildEquipTab(ctx, heroId, heroDef)
    elseif detailTab == "starup" then
        content = BuildStarUpTab(ctx, heroId, heroDef)
    elseif detailTab == "skin" then
        content = BuildSkinTab(ctx, heroId, heroDef)
    elseif detailTab == "costume" then
        content = BuildCostumeTab(ctx, heroId)
    elseif detailTab == "title" then
        content = BuildTitleTab(ctx, heroId)
    elseif detailTab == "relic" then
        content = BuildRelicTab(ctx, heroId)
    end

    if content then
        detailContentContainer:AddChild(content)
    end
end

-- ============================================================================
-- 重生确认弹窗
-- ============================================================================

local rebirthConfirmOverlay = nil

local function ShowRebirthConfirm(ctx, heroId)
    if rebirthConfirmOverlay then return end
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local pageRoot = ctx.GetPageRoot()
    local FormatBigNum = ctx.FormatBigNum

    local refund = HeroData.CalcRebirthRefund(heroId)
    if not refund then
        ShowToast("该英雄无需重生")
        return
    end
    local heroDef = nil
    for _, def in ipairs(Config.TOWER_TYPES) do
        if def.id == heroId then heroDef = def; break end
    end
    local heroName = heroDef and heroDef.name or heroId

    local function closeConfirm()
        if rebirthConfirmOverlay and pageRoot then
            pageRoot:RemoveChild(rebirthConfirmOverlay)
            rebirthConfirmOverlay = nil
        end
    end

    local refundRows = {}
    if refund.nether_crystal > 0 then
        refundRows[#refundRows + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                Currency.IconWidget(UI, "nether_crystal", 18),
                UI.Label { text = "冥晶", fontSize = 14, fontColor = { 200, 180, 160 } },
                UI.Label { text = "+" .. FormatBigNum(refund.nether_crystal), fontSize = 14, fontColor = S.gold, fontWeight = "bold" },
            },
        }
    end
    if refund.forge_iron > 0 then
        refundRows[#refundRows + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                Currency.IconWidget(UI, "forge_iron", 18),
                UI.Label { text = "锻魂铁", fontSize = 14, fontColor = { 200, 180, 160 } },
                UI.Label { text = "+" .. FormatBigNum(refund.forge_iron), fontSize = 14, fontColor = { 140, 200, 255 }, fontWeight = "bold" },
            },
        }
    end
    if refund.devour_stone > 0 then
        refundRows[#refundRows + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                Currency.IconWidget(UI, "devour_stone", 18),
                UI.Label { text = "噬魂石", fontSize = 14, fontColor = { 200, 180, 160 } },
                UI.Label { text = "+" .. FormatBigNum(refund.devour_stone), fontSize = 14, fontColor = { 180, 130, 255 }, fontWeight = "bold" },
            },
        }
    end

    local confirmPanel = UI.Panel {
        width = 260,
        backgroundColor = { 45, 32, 22, 250 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { 120, 50, 50, 200 },
        paddingTop = 16, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        alignItems = "center",
        gap = 10,
        children = {
            UI.Label { text = "确认重生", fontSize = 17, fontColor = { 255, 120, 100 }, fontWeight = "bold" },
            UI.Label { text = heroName .. " 将重置为1级", fontSize = 13, fontColor = { 200, 180, 160 } },
            UI.Label {
                text = (refund.lockedSlots and refund.lockedSlots > 0)
                    and "进阶重置，满级装备保留（" .. refund.lockedSlots .. "件）"
                    or  "装备、进阶也将全部重置",
                fontSize = 12,
                fontColor = (refund.lockedSlots and refund.lockedSlots > 0)
                    and { 100, 220, 140 }
                    or  { 180, 150, 130 },
            },
            UI.Panel { width = "90%", height = 1, backgroundColor = { 100, 75, 55, 100 } },
            UI.Label { text = "返还资源", fontSize = 13, fontColor = S.gold, fontWeight = "bold" },
            UI.Panel {
                alignItems = "center", gap = 6,
                children = refundRows,
            },
            UI.Panel { width = "90%", height = 1, backgroundColor = { 100, 75, 55, 100 } },
            UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 4,
                children = {
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = { 80, 60, 45, 220 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            closeConfirm()
                        end,
                        children = {
                            UI.Label { text = "取消", fontSize = 14, fontColor = { 200, 180, 160 } },
                        },
                    },
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = { 160, 50, 40, 240 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            local ok, msg = HeroData.Rebirth(heroId)
                            closeConfirm()
                            if ok then
                                ShowToast("重生成功！资源已返还")
                                ctx.ShowHeroDetail(heroId)  -- 刷新详情页
                                local DeployPopup = require("Game.HeroUI.DeployPopup")
                                DeployPopup.RefreshCollectionContent(ctx)  -- 刷新收藏列表等级
                                ctx.Refresh()  -- 刷新主页列表
                            else
                                ShowToast(msg or "重生失败")
                            end
                        end,
                        children = {
                            UI.Label { text = "确认重生", fontSize = 14, fontColor = { 255, 240, 220 }, fontWeight = "bold" },
                        },
                    },
                },
            },
        },
    }

    rebirthConfirmOverlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            closeConfirm()
        end,
        children = { confirmPanel },
    }
    pageRoot:AddChild(rebirthConfirmOverlay)
end

-- ============================================================================
-- 显示/隐藏英雄详情面板
-- ============================================================================

--- 显示英雄详情面板
function HeroDetail.ShowHeroDetail(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local pageRoot = ctx.GetPageRoot()
    local FormatBigNum = ctx.FormatBigNum
    local CreateStarRows = ctx.CreateStarRows
    local HeroCardMod = require("Game.HeroUI.HeroCard")

    -- 查找英雄定义
    local heroDef = nil
    if Config.LEADER_HERO.id == heroId then
        heroDef = Config.LEADER_HERO
    else
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then heroDef = td; break end
        end
    end
    if not heroDef then return end

    -- 保持标签状态（如果是同一个英雄则保持标签，否则重置为信息页）
    if detailHeroId ~= heroId then
        detailTab = "info"
    end
    detailHeroId = heroId

    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false
    local level = (h and h.level) or 1
    local rarity = heroDef.rarity or "R"
    local rarityColor = ctx.GetRarityColor(rarity)
    local rarityBorder = ctx.GetRarityBorderColor(rarity)
    local tierInfo = HeroData.GetStarTierInfo(heroId)
    local stats = ComputeFullStats(heroId)
    local power = stats.power
    local HeroAvatar = require("Game.HeroAvatar")

    -- 星级显示
    local starChildren = {}
    if isUnlocked and tierInfo.starInTier > 0 then
        local starRows = CreateStarRows(tierInfo.starInTier, tierInfo.color)
        for _, row in ipairs(starRows) do
            starChildren[#starChildren + 1] = row
        end
    end

    -- ========== 构建英雄切换列表（不含主角，品质高→低排序） ==========
    local isLeader = (heroDef.isLeader == true)
    local allHeroList = HeroCardMod.GetSortedHeroes(ctx)
    local currentHeroIdx = 1
    for i, hd in ipairs(allHeroList) do
        if hd.id == heroId then currentHeroIdx = i; break end
    end

    -- ========== 顶部：大头像展示 + 品质/名字 + 左右切换 ==========
    local elemId = Config.HERO_ELEMENT[heroId]
    local elemDef = elemId and Config.ELEMENTS[elemId]

    -- 构建 topSection children（过滤 nil 避免数组空洞导致 ipairs 提前终止）
    local topChildren = {}

    -- 品质标签（主角 rarity=="none" 时不显示）
    if rarity ~= "none" then
        topChildren[#topChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Label { text = rarity, fontSize = 16, fontColor = rarityBorder, fontWeight = "bold" },
            },
        }
    end

    -- 英雄名字
    topChildren[#topChildren + 1] = UI.Label { text = heroDef.name, fontSize = 18, fontColor = S.white, fontWeight = "bold" }

    -- 元素图标 + 星级（同一行）
    local elemStarChildren = {}
    if elemDef then
        local DMG_SHORT = { physical = "物", magical = "法", pure = "真" }
        local shortLabel = DMG_SHORT[elemId] or "?"
        elemStarChildren[#elemStarChildren + 1] = UI.Panel {
            width = 16, height = 16,
            borderRadius = 8,
            backgroundColor = { elemDef.color[1], elemDef.color[2], elemDef.color[3], 200 },
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = shortLabel,
                    fontSize = 9,
                    fontColor = { 255, 255, 255, 240 },
                    fontWeight = "bold",
                },
            },
        }
    end
    if #starChildren > 0 then
        elemStarChildren[#elemStarChildren + 1] = UI.Panel {
            flexDirection = "row", gap = 1, alignItems = "center",
            children = starChildren,
        }
    end
    topChildren[#topChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        height = 18,
        children = elemStarChildren,
    }

    -- 大头像（使用统一组件）
    topChildren[#topChildren + 1] = UI.Panel {
        width = 100, height = 100,
        children = {
            HeroAvatar.Create(heroId, {
                preset = "icon",
                fit = "contain",
                borderRadius = 12,
                isUnlocked = isUnlocked,
                borderColor = rarityBorder,
                opacity = isUnlocked and 1.0 or 0.5,
            }),
        },
    }

    -- 等级 + 战力
    if isUnlocked then
        headerPowerLabel = UI.Label { text = "战力:" .. FormatBigNum(power), fontSize = 12, fontColor = S.powerYellow }
        topChildren[#topChildren + 1] = UI.Panel {
            flexDirection = "row", gap = 10, alignItems = "center",
            children = {
                UI.Label { text = "Lv." .. level, fontSize = 14, fontColor = S.gold, fontWeight = "bold" },
                headerPowerLabel,
            },
        }
    else
        headerPowerLabel = nil
        topChildren[#topChildren + 1] = UI.Label { text = "未解锁", fontSize = 13, fontColor = S.dimLocked }
    end

    -- 左箭头（居左，主角不显示）
    if not isLeader then
        topChildren[#topChildren + 1] = UI.Panel {
            position = "absolute",
            left = 6, top = "50%",
            marginTop = -18,
            width = 36, height = 36,
            borderRadius = 18,
            backgroundColor = { 60, 45, 35, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function(self)
                local prevIdx = currentHeroIdx - 1
                if prevIdx < 1 then prevIdx = #allHeroList end
                detailHeroId = allHeroList[prevIdx].id
                HeroDetail.ShowHeroDetail(ctx, allHeroList[prevIdx].id)
            end,
            children = {
                UI.Label { text = "<", fontSize = 20, fontColor = { 200, 180, 160, 220 }, fontWeight = "bold" },
            },
        }

        -- 右箭头（居右）
        topChildren[#topChildren + 1] = UI.Panel {
            position = "absolute",
            right = 6, top = "50%",
            marginTop = -18,
            width = 36, height = 36,
            borderRadius = 18,
            backgroundColor = { 60, 45, 35, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function(self)
                local nextIdx = currentHeroIdx + 1
                if nextIdx > #allHeroList then nextIdx = 1 end
                detailHeroId = allHeroList[nextIdx].id
                HeroDetail.ShowHeroDetail(ctx, allHeroList[nextIdx].id)
            end,
            children = {
                UI.Label { text = ">", fontSize = 20, fontColor = { 200, 180, 160, 220 }, fontWeight = "bold" },
            },
        }
    end

    local topSection = UI.Panel {
        width = "100%",
        flex = 4,
        alignItems = "center",
        justifyContent = "center",
        gap = 4,
        children = topChildren,
    }

    -- ========== 标签栏（主角：信息+时装；普通英雄：全部标签） ==========
    local visibleTabs = isLeader and LEADER_TABS or DETAIL_TABS
    local tabItems = {}
    for _, tabDef in ipairs(visibleTabs) do
        local isActive = (tabDef.key == detailTab)
        tabItems[#tabItems + 1] = UI.Panel {
            flex = 1,
            paddingTop = 8, paddingBottom = 8,
            alignItems = "center", justifyContent = "center",
            backgroundColor = isActive and { 80, 60, 45, 255 } or { 0, 0, 0, 0 },
            borderBottomWidth = isActive and 2 or 0,
            borderBottomColor = S.gold,
            onClick = function(self)
                detailTab = tabDef.key
                HeroDetail.ShowHeroDetail(ctx, heroId)
            end,
            children = {
                UI.Label {
                    text = tabDef.label,
                    fontSize = 13,
                    fontColor = isActive and S.gold or S.dim,
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end

    local tabBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexShrink = 0,
        backgroundColor = { 50, 36, 26, 240 },
        borderBottomWidth = 1,
        borderBottomColor = { 75, 55, 38, 100 },
    }
    for _, item in ipairs(tabItems) do
        tabBar:AddChild(item)
    end

    -- ========== 内容区域（可滚动） ==========
    detailContentContainer = UI.Panel {
        width = "100%",
        paddingLeft = 10, paddingRight = 10,
        paddingTop = 6, paddingBottom = 10,
        pointerEvents = "auto",
    }

    local contentScroll = UI.ScrollView {
        flexGrow = 1, flexBasis = 0,
        scrollY = true,
        width = "100%",
        pointerEvents = "auto",

        children = { detailContentContainer },
    }

    -- 下半部分容器（标签栏 + 内容）
    local bottomSection = UI.Panel {
        width = "100%",
        flex = 6,
        flexDirection = "column",
        children = {
            tabBar,
            contentScroll,
        },
    }

    -- ========== 底部按钮栏（左:返回  中:合成  右:重生） ==========

    -- 左：返回
    -- 左 slot：返回按钮，左对齐
    local leftSlot = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                paddingLeft = 10, paddingRight = 14,
                paddingTop = 6, paddingBottom = 6,
                borderRadius = 16,
                backgroundColor = { 80, 60, 45, 220 },
                onClick = function(self)
                    HeroDetail.HideHeroDetail(ctx)
                end,
                children = {
                    UI.Label { text = "<", fontSize = 14, fontColor = { 200, 180, 160, 220 }, fontWeight = "bold" },
                    UI.Label { text = "返回", fontSize = 13, fontColor = { 200, 180, 160, 220 } },
                },
            },
        },
    }

    -- 中 slot：合成按钮（仅未解锁非主角），居中
    local centerSlot = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
    }
    if not isUnlocked and not isLeader then
        local fragments = (h and h.fragments) or 0
        local unlockCost = Config.RARITY_SHARD_COST[rarity] or 10
        local canCompose = fragments >= unlockCost
        local bgColor = canCompose and { 60, 160, 120, 240 } or { 60, 55, 65, 200 }
        local textColor = canCompose and { 255, 255, 255, 255 } or { 120, 110, 130, 180 }
        centerSlot = UI.Panel {
            flexGrow = 1, flexBasis = 0,
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "center",
                    gap = 4,
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 16,
                    backgroundColor = bgColor,
                    onClick = function(self)
                        local hNow = HeroData.Get(heroId)
                        local frags = (hNow and hNow.fragments) or 0
                        local cost = Config.RARITY_SHARD_COST[rarity] or 10
                        if frags < cost then
                            Toast.Show("碎片不足 (" .. frags .. "/" .. cost .. ")", { 200, 160, 100 })
                            return
                        end
                        hNow.fragments = hNow.fragments - cost
                        HeroData.UnlockHero(heroId)
                        HeroData.Save()
                        Toast.Show(heroDef.name .. " 合成成功!", { 100, 255, 180 })
                        HeroDetail.ShowHeroDetail(ctx, heroId, heroDef)
                    end,
                    children = {
                        UI.Label { text = "合成", fontSize = 13, fontColor = textColor, fontWeight = "bold" },
                    },
                },
            },
        }
    end

    -- 右 slot：重生按钮（仅已解锁非主角），右对齐
    local rightSlot = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        justifyContent = "flex-end",
        alignItems = "center",
    }
    if isUnlocked and not isLeader then
        local refund = HeroData.CalcRebirthRefund(heroId)
        if refund then
            rightSlot = UI.Panel {
                flexGrow = 1, flexBasis = 0,
                flexDirection = "row",
                justifyContent = "flex-end",
                alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 6, paddingBottom = 6,
                        borderRadius = 16,
                        backgroundColor = { 120, 50, 50, 220 },
                        onClick = function(self)
                            ShowRebirthConfirm(ctx, heroId)
                        end,
                        children = {
                            UI.Panel {
                                width = 16, height = 16,
                                backgroundImage = "image/icon_rebirth.png",
                                backgroundFit = "contain",
                            },
                            UI.Label { text = "重生", fontSize = 13, fontColor = { 255, 220, 180 }, fontWeight = "bold" },
                        },
                    },
                },
            }
        end
    end

    local bottomBar = UI.Panel {
        width = "100%",
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 6,
        children = { leftSlot, centerSlot, rightSlot },
    }

    -- ========== 组装面板 ==========
    local detailChildren = { topSection, bottomSection, bottomBar }

    local detailPanel = UI.Panel {
        position = "absolute",
        top = 5, left = 5, right = 5, bottom = 5,
        backgroundColor = S.popupBg,
        borderRadius = 12,
        borderWidth = 2,
        borderColor = rarityBorder,
        flexDirection = "column",
        overflow = "hidden",
        children = detailChildren,
    }

    -- 填充内容
    RefreshDetailContent(ctx, heroId, heroDef)

    -- 轻量刷新：重建标签页内容（用于标签切换/装备变更等）
    ctx._refreshTab = function()
        RefreshDetailContent(ctx, heroId, heroDef)
        -- 同步更新 header 战力显示
        if headerPowerLabel then
            local freshStats = GetRuntimeStats(heroId)
            headerPowerLabel:SetText("战力:" .. FormatBigNum(freshStats.power))
        end
    end

    -- 每秒增量刷新属性值（使用 FindById + SetText，不重建 UI）
    local function incrementalStatRefresh()
        if not detailContentContainer then return end
        if detailTab ~= "info" then return end  -- 仅信息标签需要刷新

        local rtStats = GetRuntimeStats(heroId)

        local panel = detailContentContainer:FindById("detail_stat_panel")
        if not panel then return end

        local atkLabel = panel:FindById("detail_atk")
        if atkLabel then atkLabel:SetText(FormatStatValue(rtStats.atk)) end

        local spdLabel = panel:FindById("detail_spd")
        if spdLabel then spdLabel:SetText(FormatStatValue(rtStats.atkSpeedDisplay)) end

        local critLabel = panel:FindById("detail_critRate")
        if critLabel then critLabel:SetText(FormatStatValue(rtStats.critRate, "pct")) end

        local critDmgLabel = panel:FindById("detail_critDmg")
        if critDmgLabel then critDmgLabel:SetText(FormatStatValue(rtStats.critDmg, "pct")) end

        local apLabel = panel:FindById("detail_armorPen")
        if apLabel then apLabel:SetText(FormatStatValue(rtStats.armorPen, "pct")) end

        local dmgLabel = panel:FindById("detail_dmgBonus")
        if dmgLabel then dmgLabel:SetText(FormatStatValue(rtStats.dmgBonus or 0, "pct")) end

        local elemLabel = panel:FindById("detail_elemDmg")
        if elemLabel then
            local dmgTypeId = Config.HERO_DAMAGE_TYPE[heroId]
            local elemBonus = rtStats.elemDmgBonus and rtStats.elemDmgBonus[dmgTypeId] or 0
            elemLabel:SetText(FormatStatValue(elemBonus, "pct"))
        end

        -- 同步更新 header 战力
        if headerPowerLabel then
            headerPowerLabel:SetText("战力:" .. FormatBigNum(rtStats.power))
        end
    end

    -- 启动每秒属性自动刷新（增量更新）
    HeroDetail.StartAutoRefresh(incrementalStatRefresh)

    -- 半透明遮罩
    local oldOverlay = ctx.GetHeroDetailOverlay()
    if oldOverlay then
        pageRoot:RemoveChild(oldOverlay)
    end
    local overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 200,
        backgroundColor = { 0, 0, 0, 180 },
        children = { detailPanel },
    }
    ctx.SetHeroDetailOverlay(overlay)
    pageRoot:AddChild(overlay)
end

--- 隐藏英雄详情面板
function HeroDetail.HideHeroDetail(ctx)
    HeroDetail.StopAutoRefresh()
    local overlay = ctx.GetHeroDetailOverlay()
    if overlay then
        local pageRoot = ctx.GetPageRoot()
        pageRoot:RemoveChild(overlay)
        ctx.SetHeroDetailOverlay(nil)
        detailContentContainer = nil
        detailHeroId = nil
        headerPowerLabel = nil
        -- 刷新英雄收藏列表（合成/重生等操作后数据已变更）
        ctx.Refresh()
    end
end

return HeroDetail
