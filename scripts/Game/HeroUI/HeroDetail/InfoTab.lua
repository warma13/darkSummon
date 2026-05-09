-- Game/HeroUI/HeroDetail/InfoTab.lua
-- 英雄详情 - 信息标签页（属性 + 光环 + 技能 + 技能标签）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local HeroSkills = require("Game.HeroSkills")
local Toast = require("Game.Toast")

local StatEngine = require("Game.HeroUI.HeroDetail.StatEngine")
local GetRuntimeStats = StatEngine.GetRuntimeStats
local CreateStatRow = StatEngine.CreateStatRow
local CreateSkillIcon = StatEngine.CreateSkillIcon

local InfoTab = {}

--- 构建信息标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
function InfoTab.Build(ctx, heroId, heroDef)
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
        CreateStatRow(UI, S, stats.penLabel or "穿甲", stats.penValue or 0, { 200, 140, 255, 255 }, "pct", "detail_pen"),
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

    -- 光环效果展示（从技能 + 技能标签中收集对友方的光环 buff）
    do
        local auraRows = {}
        local fmtP = function(v)
            local r = v * 100
            if r == math.floor(r) then return string.format("+%d%%", r) end
            return string.format("+%.1f%%", r)
        end

        -- 星级缩放（与技能区保持一致）
        local heroStar0 = (h and h.star) or 0
        local maxStar0  = Config.MAX_HERO_STAR or 30
        local starScale0 = 0.10 + 0.90 * math.sqrt(math.min(heroStar0, maxStar0) / maxStar0)

        -- 1) 从基础技能收集光环字段
        local skillDefs1 = Config.HERO_SKILLS and Config.HERO_SKILLS[heroId] or {}
        for _, skill in ipairs(skillDefs1) do
            if skill.type == "passive" then
                local sf = (skill.starScale and starScale0) or 1.0
                if skill.atkSpdBonus and skill.atkSpdBonus > 0 then
                    auraRows[#auraRows + 1] = { label = "友方攻速", value = fmtP(skill.atkSpdBonus * sf), color = { 100, 200, 255, 255 }, src = skill.name }
                end
                if skill.critRate and skill.critRate > 0 then
                    auraRows[#auraRows + 1] = { label = "友方暴击率", value = fmtP(skill.critRate * sf), color = { 255, 220, 80, 255 }, src = skill.name }
                end
                if skill.stunAtkBonusMax and skill.stunAtkBonusMax > 0 then
                    auraRows[#auraRows + 1] = { label = "眩晕增攻(上限)", value = fmtP(skill.stunAtkBonusMax * sf), color = { 255, 160, 80, 255 }, src = skill.name }
                end
            end
        end

        -- 2) 从技能标签收集光环字段
        local tagDefs1 = Config.HERO_SKILL_TAGS and Config.HERO_SKILL_TAGS[heroId]
        if tagDefs1 then
            for _, tagDef in ipairs(tagDefs1) do
                local tier = HeroData.GetTagTier(heroId, tagDef.id)
                local unlocked = HeroData.IsTagUnlocked(heroId, tagDef)
                if unlocked and tier > 0 and tagDef.effects and tagDef.effects[tier] then
                    local eff = tagDef.effects[tier]
                    if eff.auraAtkBuff and eff.auraAtkBuff > 0 then
                        auraRows[#auraRows + 1] = { label = "友方攻击力", value = fmtP(eff.auraAtkBuff), color = { 255, 120, 80, 255 }, src = tagDef.name }
                    end
                    if eff.critDmg and eff.critDmg > 0 then
                        auraRows[#auraRows + 1] = { label = "友方暴伤", value = fmtP(eff.critDmg), color = { 255, 160, 60, 255 }, src = tagDef.name }
                    end
                end
            end
        end

        if #auraRows > 0 then
            local auraChildren = {
                UI.Label { text = "光环效果", fontSize = 12, fontColor = { 155, 115, 207, 220 }, marginLeft = 6 },
            }
            for _, row in ipairs(auraRows) do
                auraChildren[#auraChildren + 1] = UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 3, paddingBottom = 3,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 4,
                            children = {
                                UI.Label { text = row.label, fontSize = 12, fontColor = S.dim },
                                UI.Label { text = "(" .. row.src .. ")", fontSize = 9, fontColor = { 150, 140, 130, 150 } },
                            },
                        },
                        UI.Label { text = row.value, fontSize = 13, fontColor = row.color, fontWeight = "bold" },
                    },
                }
            end
            children[#children + 1] = UI.Panel {
                width = "100%",
                marginTop = 4,
                backgroundColor = { 30, 22, 40, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 80, 55, 120, 150 },
                paddingTop = 6, paddingBottom = 6,
                gap = 2,
                children = auraChildren,
            }
        end
    end

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

return InfoTab
