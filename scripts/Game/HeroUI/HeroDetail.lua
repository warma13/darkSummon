-- Game/HeroUI/HeroDetail.lua
-- 英雄详情面板（标签页版：信息 / 装备 / 升星 / 皮肤）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")

local HeroDetail = {}

--- 当前详情面板打开的英雄ID和选中标签
---@type string|nil
local detailHeroId = nil
---@type string
local detailTab = "info"

--- 详情面板内容容器（用于标签切换时局部刷新）
---@type any
local detailContentContainer = nil

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
}

--- 页面重建时清理局部状态
function HeroDetail.OnPageClear()
    detailContentContainer = nil
    detailHeroId = nil
end

local function ShowToast(msg)
    Toast.Show(msg)
end

-- ============================================================================
-- 属性行 / 技能图标
-- ============================================================================

--- 创建属性行
---@param UI any
---@param S table
---@param label string
---@param value number|string
---@param color table|nil
---@param fmt string|nil  "pct"=百分比, nil=整数
local function CreateStatRow(UI, S, label, value, color, fmt)
    local FormatBigNum = require("Game.HeroUI").FormatBigNum
    local display
    if fmt == "pct" then
        display = string.format("%.1f%%", (value or 0) * 100)
    elseif type(value) == "number" then
        display = FormatBigNum(value)
    else
        display = tostring(value)
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 4, paddingBottom = 4,
        children = {
            UI.Label { text = label, fontSize = 13, fontColor = S.dim },
            UI.Label { text = display, fontSize = 13, fontColor = color or S.white, fontWeight = "bold" },
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

    local stats = HeroData.GetHeroStats(heroId)
    local EquipData = require("Game.EquipData")
    local eqBonus = EquipData.GetTotalBonus(heroId)
    stats.atk = stats.atk + (eqBonus.atk or 0)
    stats.critDmg = (stats.critDmg or 0) + (eqBonus.critDmg or 0)
    stats.dmgBonus = (stats.dmgBonus or 0) + (eqBonus.dmgBonus or 0)
    local heroElem = Config.HERO_ELEMENT[heroId]
    if heroElem and eqBonus.elemDmg and eqBonus.elemDmg > 0 then
        if not stats.elemDmgBonus then stats.elemDmgBonus = {} end
        stats.elemDmgBonus[heroElem] = (stats.elemDmgBonus[heroElem] or 0) + eqBonus.elemDmg
    end

    -- 计算实际攻速（次/s）= 1 / 攻击间隔
    -- 攻击间隔 = baseSpeed / (1 + spdBonus + 装备攻速%)
    local atkSpeedDisplay
    do
        local baseSpeed = nil
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then baseSpeed = td.baseSpeed; break end
        end
        if not baseSpeed and Config.LEADER_HERO and Config.LEADER_HERO.id == heroId then
            baseSpeed = Config.LEADER_HERO.baseSpeed
        end
        if baseSpeed then
            local interval = baseSpeed / (1 + (stats.spdBonus or 0) + (eqBonus.spd_pct or 0))
            atkSpeedDisplay = string.format("%.2f/s", 1 / interval)
        else
            atkSpeedDisplay = tostring(stats.spd)
        end
    end

    local children = {}

    -- 属性区
    children[#children + 1] = UI.Panel {
        width = "100%",
        backgroundColor = { 35, 25, 18, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 70, 55, 40, 150 },
        paddingTop = 6, paddingBottom = 6,
        gap = 2,
        children = {
            CreateStatRow(UI, S, "攻击", stats.atk, { 255, 120, 80, 255 }),
            CreateStatRow(UI, S, "攻速", atkSpeedDisplay, { 100, 180, 255, 255 }),
            CreateStatRow(UI, S, "暴击率", stats.critRate, { 255, 220, 80, 255 }, "pct"),
            CreateStatRow(UI, S, "暴击伤害", stats.critDmg, { 255, 160, 60, 255 }, "pct"),
            CreateStatRow(UI, S, "穿甲", stats.armorPen, { 200, 140, 255, 255 }, "pct"),
            CreateStatRow(UI, S, "伤害加成", stats.dmgBonus or 0, { 255, 100, 100, 255 }, "pct"),
            (function()
                local elemId = Config.HERO_ELEMENT[heroId]
                local elemDef = elemId and Config.ELEMENTS[elemId]
                if not elemId or not elemDef then return nil end
                local elemBonus = stats.elemDmgBonus and stats.elemDmgBonus[elemId] or 0
                return CreateStatRow(UI, S, elemDef.name .. "伤害", elemBonus, elemDef.color, "pct")
            end)(),
        },
    }

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

        local skillAutoUnlock = (heroId == "glacial_sovereign")

        -- 星级缩放系数：0星→10%，满星→100%
        local heroStar = (h and h.star) or 0
        local maxStar  = Config.MAX_HERO_STAR or 30
        local starScale = 0.10 + 0.90 * math.min(heroStar, maxStar) / maxStar

        -- 星级乘数文本，如 "×55%"
        local starPct = math.floor(starScale * 100 + 0.5)
        local starTag = "（★" .. heroStar .. " ×" .. starPct .. "%）"

        --- 为带 starScale 标记的翎嫣技能生成动态描述，数值后附星级乘数
        local function BuildNatureElfDesc(skillId)
            if skillId == "nature_gift" then
                local atkPct = math.floor(60 * starScale + 0.5)
                local spdPct = math.floor(40 * starScale + 0.5)
                local ratPct = math.floor(10 * starScale * 10 + 0.5) / 10
                local ratStr = ratPct % 1 == 0 and string.format("%d", ratPct) or string.format("%.1f", ratPct)
                return string.format(
                    "每3秒为范围内英雄注入3点自然之力（持续8秒），自然之力越多越接近上限：攻击+%d%%、攻速+%d%%，并额外获得翎嫣ATK×%s%%的固定攻击加成%s",
                    atkPct, spdPct, ratStr, starTag
                )
            elseif skillId == "wilds_call" then
                local force     = math.floor(30 * starScale)
                local wreathPct = math.floor(40 * starScale + 0.5)
                return string.format(
                    "每20秒自动为所有英雄提供%d点自然之力，并为攻击力最高且未持有鲜花环的英雄赠送鲜花环（+%d%%攻击力，持续10秒，每个英雄最多1个）%s",
                    force, wreathPct, starTag
                )
            end
            return nil
        end

        local function UpdateSkillDesc(idx)
            selectedIdx = idx
            local sd = skillDefs[idx]
            if not sd then return end
            local unlockLv = Config.SKILL_UNLOCK_LEVELS[idx] or 999
            local isLocked = (not skillAutoUnlock) and (level < unlockLv)

            -- 动态描述：starScale 标记的技能显示当前星级对应的数值
            local desc = sd.desc
            if sd.starScale then
                desc = BuildNatureElfDesc(sd.id) or desc
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
                                fontColor = isLocked and S.dimLocked or S.gold,
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
                        fontColor = isLocked and { 180, 170, 155, 180 } or { 210, 200, 180, 220 },
                    },
                    isLocked and UI.Label {
                        text = "Lv." .. unlockLv .. " 解锁",
                        fontSize = 10, fontColor = { 255, 140, 60, 200 }, marginTop = 2,
                    } or nil,
                },
            })

            skillIconsContainer:ClearChildren()
            for i, skillDef in ipairs(skillDefs) do
                local ulv = Config.SKILL_UNLOCK_LEVELS[i] or 999
                local su = skillAutoUnlock or (level >= ulv)
                skillIconsContainer:AddChild(CreateSkillIcon(UI, skillDef, su, i == selectedIdx, function(self)
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
                        children = {
                            UI.Label { text = info.fullName, fontSize = 12, fontColor = tier.color, fontWeight = "bold" },
                            UI.Label {
                                text = slotDef.statName .. " +" .. (slotDef.fmt == "pct"
                                    and string.format("%.1f%%", info.statBonus * 100)
                                    or FormatBigNum(info.statBonus)),
                                fontSize = 10, fontColor = S.gold,
                            },
                        },
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

    -- ── 槽位行 ────────────────────────────────────────────────────────────────
    local wingDef = CostumeData.GetEquippedDef("wing")
    local slotRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 10,
        backgroundColor = { 40, 28, 20, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 90, 65, 48, 200 },
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        children = {
            -- 槽位图标
            UI.Panel {
                width = 44, height = 44,
                flexShrink = 0,
                borderRadius = 8,
                backgroundColor = { 55, 38, 28, 255 },
                borderWidth = 1,
                borderColor = wingDef and (wingDef.rarityColor or { 120, 80, 200, 200 }) or { 70, 55, 42, 150 },
                justifyContent = "center", alignItems = "center",
                overflow = "hidden",
                children = wingDef and {
                    FrameIcon(44, wingDef, wingDef.iconFrame or 0),
                } or {
                    UI.Label { text = "翼", fontSize = 18, fontColor = { 100, 80, 65, 200 } },
                },
            },
            -- 槽位名 + 装备状态
            UI.Panel {
                flexGrow = 1,
                gap = 2,
                children = {
                    UI.Label { text = "翅膀", fontSize = 12, fontColor = S.dim },
                    UI.Label {
                        text = wingDef and wingDef.name or "空置",
                        fontSize = 14,
                        fontColor = wingDef and (wingDef.rarityColor or S.white) or S.dimLocked,
                        fontWeight = wingDef and "bold" or "normal",
                    },
                },
            },
            -- 卸下按钮（已装备时显示）
            wingDef and UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 6,
                backgroundColor = { 70, 50, 38, 200 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    CostumeData.Equip("wing", nil)
                    ctx.ShowHeroDetail(heroId)
                end,
                children = {
                    UI.Label { text = "卸下", fontSize = 11, fontColor = { 180, 160, 140, 220 } },
                },
            } or nil,
        },
    }
    children[#children + 1] = slotRow

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

    return UI.Panel {
        width = "100%",
        gap = 6,
        pointerEvents = "auto",
        children = children,
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
            UI.Label { text = "装备、进阶也将全部重置", fontSize = 12, fontColor = { 180, 150, 130 } },
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
    local stats = HeroData.GetHeroStats(heroId)
    local EquipData = require("Game.EquipData")
    local eqBonus = EquipData.GetTotalBonus(heroId)
    stats.atk = stats.atk + (eqBonus.atk or 0)
    local power = stats.atk + stats.spd
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
        elemStarChildren[#elemStarChildren + 1] = UI.Panel {
            width = 16, height = 16,
            backgroundImage = elemDef.icon,
            backgroundFit = "contain",
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
        topChildren[#topChildren + 1] = UI.Panel {
            flexDirection = "row", gap = 10, alignItems = "center",
            children = {
                UI.Label { text = "Lv." .. level, fontSize = 14, fontColor = S.gold, fontWeight = "bold" },
                UI.Label { text = "战力:" .. FormatBigNum(power), fontSize = 12, fontColor = S.powerYellow },
            },
        }
    else
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
        position = "absolute",
        bottom = 8, left = 8, right = 8,
        flexDirection = "row",
        alignItems = "center",
        zIndex = 10,
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
    local overlay = ctx.GetHeroDetailOverlay()
    if overlay then
        local pageRoot = ctx.GetPageRoot()
        pageRoot:RemoveChild(overlay)
        ctx.SetHeroDetailOverlay(nil)
        detailContentContainer = nil
        detailHeroId = nil
        -- 刷新英雄收藏列表（合成/重生等操作后数据已变更）
        ctx.Refresh()
    end
end

return HeroDetail
