-- Game/GameUI/Panels.lua
-- 面板：英雄信息面板、底部操作栏

return function(GameUI, ctx)

local Config    = require("Game.Config")
local State     = require("Game.State")
local AutoPlay  = require("Game.AutoPlay")
local Tower     = require("Game.Tower")
local Currency  = require("Game.Currency")
local HeroData  = require("Game.HeroData")
local Toast     = require("Game.Toast")
local AdTracker = require("Game.AdTracker")
local HeroSkills = require("Game.HeroSkills")
local SpeedBoost = require("Game.SpeedBoostData")
local HeroAvatar = require("Game.HeroAvatar")

local FormatNum = ctx.FormatNum
local FormatStat = FormatNum  -- FormatStat 与 FormatNum 逻辑一致，统一使用
local RARITY_COLORS = ctx.RARITY_COLORS

--- 攻击范围前缀
local SCOPE_PREFIX = {
    single = "单体", aoe = "群体", chain = "连锁", support = "",
}

--- 战斗特性后缀 + 标签色
local SPECIAL_SUFFIX = {
    none        = { suffix = "",       color = { 150, 150, 180 } },
    high_damage = { suffix = "爆发",   color = { 255, 80, 80 } },
    fast_attack = { suffix = "速攻",   color = { 255, 180, 60 } },
    boss_killer = { suffix = "斩杀",   color = { 255, 60, 120 } },
    dot         = { suffix = "持伤",   color = { 200, 100, 60 } },
    aoe_damage  = { suffix = "轰炸",   color = { 255, 140, 60 } },
    slow        = { suffix = "减速",   color = { 100, 180, 255 } },
    chill       = { suffix = "冰冻",   color = { 120, 210, 255 } },
    armor_break = { suffix = "破甲",   color = { 255, 160, 80 } },
    amp_damage  = { suffix = "增伤",   color = { 220, 160, 255 } },
    aoe_control = { suffix = "控制",   color = { 160, 120, 255 } },
    support     = { suffix = "增益",   color = { 100, 220, 140 } },
    aura_buff   = { suffix = "光环",   color = { 120, 220, 100 } },
    nature_aura = { suffix = "光环",   color = { 80, 200, 120 } },
    leader      = { suffix = "统帅",   color = { 180, 120, 255 } },
}

--- 每个英雄的额外标签（技能衍生的能力描述）
local HERO_EXTRA_TAGS = {
    nature_elf        = { { name = "免控",   color = { 255, 220, 80 } } },   -- 翎嫣：自然之力满层禁锢负面效果
    glacial_sovereign = { { name = "冻结",   color = { 120, 210, 255 } } },  -- 凛冬：满层寒意冻结
    crimson_night     = { { name = "穿刺",   color = { 255, 80, 100 } } },   -- 绯夜：暗影之针无视护甲
}

--- 根据 typeDef 生成英雄定位标签列表
local function getHeroRoleTags(td)
    local tags = {}
    local prefix = SCOPE_PREFIX[td.attackType] or ""
    local info = SPECIAL_SUFFIX[td.special] or SPECIAL_SUFFIX.none

    -- 主标签：攻击范围 + 特性
    local mainName
    if td.attackType == "support" then
        -- 辅助型：不加前缀，直接用特性名
        mainName = info.suffix ~= "" and info.suffix or "辅助"
    elseif info.suffix == "" then
        -- 无特殊：只显示攻击范围
        mainName = prefix
    else
        -- 组合：如 "群体增伤"、"单体爆发"、"连锁减速"
        mainName = prefix .. info.suffix
    end
    tags[#tags + 1] = { name = mainName, color = info.color }

    -- 英雄额外标签
    local extras = HERO_EXTRA_TAGS[td.id]
    if extras then
        for _, et in ipairs(extras) do
            tags[#tags + 1] = et
        end
    end

    return tags
end

--- 英雄信息面板（点击塔时顶栏下方显示）
function GameUI.CreateHeroInfoPanel()
    return ctx.UI.Panel {
        id = "heroInfoPanel",
        position = "absolute",
        top = 52, left = 8, right = 8,
        zIndex = 100,
        backgroundColor = { 15, 12, 28, 230 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 80, 60, 140, 150 },
        paddingTop = 8, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        visible = false,
        pointerEvents = "auto",
        gap = 6,
        children = {},
    }
end

--- 构建英雄信息面板内容
function GameUI.BuildHeroInfoContent(tower)
    local td = tower.typeDef
    local rarity = td.rarity or "N"
    local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.N
    local skills = Config.HERO_SKILLS[td.id] or {}
    local tierInfo = HeroData.GetStarTierInfo(td.id)

    -- 元素信息
    local heroElem = Config.HERO_ELEMENT and Config.HERO_ELEMENT[td.id]
    local elemInfo = heroElem and Config.ELEMENTS and Config.ELEMENTS[heroElem]

    -- 有效属性（含光环/技能加成）
    local effCritRate = HeroSkills.GetEffectiveCritRate(tower)
    local effCritDmg = Tower.GetEffectiveCritDmg(tower)
    local effArmorPen = Tower.GetEffectiveArmorPen(tower)
    local effDmgBonus = Tower.GetEffectiveDmgBonus and Tower.GetEffectiveDmgBonus(tower) or (tower.dmgBonus or 0)

    -- 属性行辅助函数
    local function StatRow(label, value, color, valueId)
        return ctx.UI.Panel {
            flexDirection = "row", justifyContent = "space-between",
            width = "100%",
            children = {
                ctx.UI.Label { text = label, fontSize = 11, fontColor = { 160, 150, 180, 200 } },
                ctx.UI.Label { id = valueId, text = value, fontSize = 11, fontColor = color or { 255, 255, 255, 230 }, fontWeight = "bold" },
            },
        }
    end

    -- 使用显式 table.insert 构建返回数组，避免中间 nil 导致 ipairs 断裂
    local result = {}

    -- ① 第一行：头像 + 名称/品质/星级/元素
    local nameRowChildren = {
        ctx.UI.Label {
            text = td.name,
            fontSize = 15,
            fontColor = rarityColor,
            fontWeight = "bold",
        },
    }
    if rarity ~= "none" then
        nameRowChildren[#nameRowChildren + 1] = ctx.UI.Panel {
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = rarityColor,
            borderRadius = 3,
            children = {
                ctx.UI.Label { text = rarity, fontSize = 9, fontColor = { 20, 16, 32, 255 }, fontWeight = "bold" },
            },
        }
    end
    if elemInfo then
        nameRowChildren[#nameRowChildren + 1] = ctx.UI.Panel {
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = { elemInfo.color[1], elemInfo.color[2], elemInfo.color[3], 180 },
            borderRadius = 3,
            children = {
                ctx.UI.Label { text = elemInfo.name, fontSize = 9, fontColor = { 255, 255, 255, 255 }, fontWeight = "bold" },
            },
        }
    end

    -- 详情行：等级/星级/觉醒
    local detailText = "Lv." .. tower.heroLevel
        .. "  ★" .. tower.star
        .. "  " .. (tierInfo and tierInfo.name or "") .. (tower.heroStar or 0) .. "星"

    result[#result + 1] = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        alignItems = "center",
        children = {
            -- 头像
            ctx.UI.Panel {
                width = 48, height = 48,
                children = {
                    HeroAvatar.Create(td.id, {
                        preset = "icon",
                        borderRadius = 8,
                        borderWidth = 1,
                    }),
                },
            },
            -- 名称信息
            ctx.UI.Panel {
                flex = 1, gap = 2,
                children = {
                    ctx.UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        flexWrap = "wrap",
                        children = nameRowChildren,
                    },
                    ctx.UI.Label {
                        id = "heroPanel_detail",
                        text = detailText,
                        fontSize = 11,
                        fontColor = { 180, 170, 200, 200 },
                    },
                },
            },
            -- 关闭按钮
            ctx.UI.Panel {
                width = 28, height = 28,
                borderRadius = 14,
                backgroundColor = { 60, 50, 80, 150 },
                justifyContent = "center", alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self)
                    State.selectedTower = nil
                end,
                children = {
                    ctx.UI.Label { text = "✕", fontSize = 12, fontColor = { 180, 170, 200, 200 } },
                },
            },
        },
    }

    -- ② 分隔线
    result[#result + 1] = ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 140, 80 } }

    -- ③ 主属性区域（攻击/攻速/射程 — 始终显示）
    result[#result + 1] = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 12,
        children = {
            ctx.UI.Panel {
                flex = 1, gap = 3,
                children = {
                    StatRow("攻击", FormatStat(HeroSkills.GetEffectiveAttack(tower)), { 255, 120, 80, 255 }, "heroPanel_atk"),
                    StatRow("攻速", string.format("%.2f/s", 1.0 / HeroSkills.GetEffectiveSpeed(tower)), { 255, 200, 80, 255 }, "heroPanel_spd"),
                },
            },
            ctx.UI.Panel {
                flex = 1, gap = 3,
                children = {
                    StatRow("射程", tostring(math.floor(HeroSkills.ModifyRange(tower, tower.range))), { 200, 180, 255, 255 }, "heroPanel_range"),
                },
            },
        },
    }

    -- ④ 副属性区域（暴击/暴伤/破甲/伤害加成 — 始终显示）
    local subStatLeft = {}
    local subStatRight = {}

    -- 暴击率
    local critColor = effCritRate > 0 and { 255, 80, 80, 230 } or { 120, 110, 140, 180 }
    subStatLeft[#subStatLeft + 1] = StatRow("暴击率", string.format("%.1f%%", effCritRate * 100), critColor, "heroPanel_crit")

    -- 暴击伤害
    local critDmgColor = effCritDmg > 0 and { 255, 100, 100, 230 } or { 120, 110, 140, 180 }
    subStatLeft[#subStatLeft + 1] = StatRow("暴伤", string.format("%.0f%%", effCritDmg * 100), critDmgColor, "heroPanel_critDmg")

    -- 破甲
    local apColor = effArmorPen > 0 and { 255, 160, 80, 230 } or { 120, 110, 140, 180 }
    subStatRight[#subStatRight + 1] = StatRow("破甲", string.format("%.1f%%", effArmorPen * 100), apColor, "heroPanel_armorPen")

    -- 伤害加成
    local dmgBonusColor = effDmgBonus > 0 and { 180, 220, 120, 230 } or { 120, 110, 140, 180 }
    subStatRight[#subStatRight + 1] = StatRow("伤害加成", string.format("%.1f%%", effDmgBonus * 100), dmgBonusColor, "heroPanel_dmgBonus")

    result[#result + 1] = ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 12,
        children = {
            ctx.UI.Panel { flex = 1, gap = 3, children = subStatLeft },
            ctx.UI.Panel { flex = 1, gap = 3, children = subStatRight },
        },
    }

    -- ⑤ 标签行：攻击方式 + 战斗特性 + 元素伤害加成
    local tagChildren = {}

    --- 创建单个彩色标签
    local function addTag(text, color)
        tagChildren[#tagChildren + 1] = ctx.UI.Panel {
            paddingLeft = 5, paddingRight = 5,
            paddingTop = 2, paddingBottom = 2,
            backgroundColor = { color[1], color[2], color[3], 50 },
            borderRadius = 4,
            borderWidth = 1,
            borderColor = { color[1], color[2], color[3], 120 },
            children = {
                ctx.UI.Label {
                    text = text,
                    fontSize = 10,
                    fontColor = { color[1], color[2], color[3], 255 },
                    fontWeight = "bold",
                },
            },
        }
    end

    -- 英雄定位标签（组合：群体增伤、单体爆发、免控 等）
    local roleTags = getHeroRoleTags(td)
    for _, tag in ipairs(roleTags) do
        addTag(tag.name, tag.color)
    end

    -- 伤害类型加成标签
    if tower.physDmgBonus and tower.physDmgBonus > 0 then
        local ti = Config.DAMAGE_TYPES and Config.DAMAGE_TYPES["physical"]
        local tColor = ti and ti.color or { 255, 160, 60 }
        addTag("物伤+" .. string.format("%.0f%%", tower.physDmgBonus * 100), tColor)
    end
    if tower.magicDmgBonus and tower.magicDmgBonus > 0 then
        local ti = Config.DAMAGE_TYPES and Config.DAMAGE_TYPES["magical"]
        local tColor = ti and ti.color or { 100, 140, 255 }
        addTag("法伤+" .. string.format("%.0f%%", tower.magicDmgBonus * 100), tColor)
    end
    if tower.magicPen and tower.magicPen > 0 then
        addTag("法穿+" .. string.format("%.0f%%", tower.magicPen * 100), { 180, 100, 255 })
    end
    if #tagChildren > 0 then
        result[#result + 1] = ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 5,
            alignItems = "center",
            children = tagChildren,
        }
    end

    -- ⑥ 技能区域（始终显示，不再使用条件 nil）
    if #skills > 0 then
        result[#result + 1] = ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 140, 80 } }
        result[#result + 1] = ctx.UI.Label { text = "技能", fontSize = 11, fontColor = { 180, 170, 200, 220 }, fontWeight = "bold" }

        -- 星级缩放系数：用于动态技能描述
        local heroStar = tower.heroStar or 0
        local maxStar  = Config.MAX_HERO_STAR or 30
        local starScale = 0.10 + 0.90 * math.sqrt(math.min(heroStar, maxStar) / maxStar)

        for i, sk in ipairs(skills) do
            local typeTag = sk.type == "active" and "[主动]" or "[被动]"
            local typeColor = sk.type == "active" and { 255, 180, 80, 255 } or { 120, 200, 255, 255 }

            -- 技能描述：优先使用 buildDesc 动态描述（随星级变化）
            local descText
            if sk.buildDesc then
                descText = sk.buildDesc(starScale)
            else
                descText = sk.desc or ""
            end
            if sk.type == "active" and sk.interval then
                descText = descText .. " (CD:" .. sk.interval .. "s)"
            end

            result[#result + 1] = ctx.UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                alignItems = "flex-start",
                children = {
                    -- 技能序号圆点
                    ctx.UI.Panel {
                        width = 18, height = 18,
                        borderRadius = 9,
                        backgroundColor = rarityColor,
                        justifyContent = "center", alignItems = "center",
                        flexShrink = 0,
                        children = {
                            ctx.UI.Label { text = tostring(i), fontSize = 10, fontColor = { 255, 255, 255, 255 }, fontWeight = "bold" },
                        },
                    },
                    ctx.UI.Panel {
                        flex = 1, gap = 1,
                        children = {
                            ctx.UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    ctx.UI.Panel {
                                        paddingLeft = 3, paddingRight = 3,
                                        backgroundColor = { typeColor[1], typeColor[2], typeColor[3], 60 },
                                        borderRadius = 2,
                                        children = {
                                            ctx.UI.Label {
                                                text = typeTag,
                                                fontSize = 9,
                                                fontColor = typeColor,
                                            },
                                        },
                                    },
                                    ctx.UI.Label {
                                        text = sk.name,
                                        fontSize = 11,
                                        fontColor = { 220, 210, 240, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            ctx.UI.Label {
                                text = descText,
                                fontSize = 10,
                                fontColor = { 150, 140, 170, 200 },
                            },
                        },
                    },
                },
            }
        end
    end

    return result
end

--- 增量更新英雄信息面板的动态数值（不重建面板结构）
--- 仅更新：等级/星级行、攻击、攻速、射程、暴击率、暴伤、破甲、伤害加成
function GameUI.UpdateHeroInfoValues(tower, panel)
    if not tower or not panel then return end

    local tierInfo = HeroData.GetStarTierInfo(tower.typeDef.id)

    -- 等级/星级行
    local detailLabel = panel:FindById("heroPanel_detail")
    if detailLabel then
        local detailText = "Lv." .. tower.heroLevel
            .. "  ★" .. tower.star
            .. "  " .. (tierInfo and tierInfo.name or "") .. (tower.heroStar or 0) .. "星"
        detailLabel:SetText(detailText)
    end

    -- 主属性
    local atkLabel = panel:FindById("heroPanel_atk")
    if atkLabel then
        atkLabel:SetText(FormatStat(HeroSkills.GetEffectiveAttack(tower)))
    end
    local spdLabel = panel:FindById("heroPanel_spd")
    if spdLabel then
        spdLabel:SetText(string.format("%.2f/s", 1.0 / HeroSkills.GetEffectiveSpeed(tower)))
    end
    local rangeLabel = panel:FindById("heroPanel_range")
    if rangeLabel then
        rangeLabel:SetText(tostring(math.floor(HeroSkills.ModifyRange(tower, tower.range))))
    end

    -- 副属性
    local effCritRate = HeroSkills.GetEffectiveCritRate(tower)
    local effCritDmg = Tower.GetEffectiveCritDmg(tower)
    local effArmorPen = Tower.GetEffectiveArmorPen(tower)
    local effDmgBonus = Tower.GetEffectiveDmgBonus and Tower.GetEffectiveDmgBonus(tower) or (tower.dmgBonus or 0)

    local critLabel = panel:FindById("heroPanel_crit")
    if critLabel then
        critLabel:SetText(string.format("%.1f%%", effCritRate * 100))
    end
    local critDmgLabel = panel:FindById("heroPanel_critDmg")
    if critDmgLabel then
        critDmgLabel:SetText(string.format("%.0f%%", effCritDmg * 100))
    end
    local apLabel = panel:FindById("heroPanel_armorPen")
    if apLabel then
        apLabel:SetText(string.format("%.1f%%", effArmorPen * 100))
    end
    local dmgLabel = panel:FindById("heroPanel_dmgBonus")
    if dmgLabel then
        dmgLabel:SetText(string.format("%.1f%%", effDmgBonus * 100))
    end
end

--- 底部操作栏（圆形召唤按钮）
function GameUI.CreateBottomBar()
    return ctx.UI.Panel {
        id = "bottomBar",
        position = "absolute",
        bottom = 4, left = 0, right = 0,
        height = 110,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            -- 左侧：冥晶数量
            ctx.UI.Panel {
                position = "absolute",
                left = 16, bottom = 10,
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                paddingLeft = 8, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 20, 16, 32, 200 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 70, 180, 100 },
                pointerEvents = "none",
                children = {
                    Currency.IconWidget(ctx.UI, "dark_soul", 18),
                    ctx.UI.Label {
                        id = "bottomGoldLabel",
                        text = "0",
                        fontSize = 14,
                        fontColor = { 80, 150, 220, 255 },
                    },
                },
            },
            -- 中间：圆形召唤按钮
            ctx.UI.Panel {
                alignItems = "center",
                gap = 3,
                pointerEvents = "auto",
                children = {
                    ctx.UI.Panel {
                        id = "summonBtn",
                        width = 64, height = 64,
                        borderRadius = 32,
                        backgroundColor = { 100, 60, 200, 255 },
                        borderWidth = 3,
                        borderColor = { 160, 120, 255, 200 },
                        justifyContent = "center",
                        alignItems = "center",
                        onClick = function(self)
                            if State.phase == State.PHASE_PLAYING or State.phase == State.PHASE_WAVE_READY then
                                local t, reason = Tower.Summon()
                                if not t then
                                    Toast.Show(reason or "召唤失败", { 255, 100, 100 })
                                else
                                    HeroData.Save()
                                end
                                -- UpdateHUD 由 Currency.Spend("dark_soul") 触发 EventBus 自动调用
                            end
                        end,
                        children = {
                            ctx.UI.Label {
                                text = "召唤",
                                fontSize = 15,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                                pointerEvents = "none",
                            },
                        },
                    },
                    -- 消耗文字（动态递增）
                    ctx.UI.Panel {
                        id = "summonCostPanel",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 2,
                        pointerEvents = "none",
                        children = {
                            Currency.IconWidget(ctx.UI, "dark_soul", 13),
                            ctx.UI.Label {
                                id = "summonCostLabel",
                                text = tostring(Config.SUMMON_BASE_COST),
                                fontSize = 11,
                                fontColor = { 80, 150, 220, 255 },
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
            -- 右侧：自动召唤 + 自动合成 开关
            ctx.UI.Panel {
                position = "absolute",
                right = 12, bottom = 6,
                flexDirection = "column",
                gap = 8,
                pointerEvents = "auto",
                alignItems = "center",
                children = {
                    -- 自动召唤开关
                    ctx.UI.Button {
                        id = "autoSummonBtn",
                        text = "自动召唤:关",
                        fontSize = 11,
                        variant = "outline",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function(self)
                            AutoPlay.autoSummon = not AutoPlay.autoSummon
                            AutoPlay.autoSummonTimer = AutoPlay.autoSummon and 0.4 or 0
                            GameUI.UpdateHUD()
                        end,
                    },
                    -- 自动合成开关
                    ctx.UI.Button {
                        id = "autoMergeBtn",
                        text = "自动合成:关",
                        fontSize = 11,
                        variant = "outline",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function(self)
                            AutoPlay.autoMerge = not AutoPlay.autoMerge
                            AutoPlay.autoMergeTimer = AutoPlay.autoMerge and 0.4 or 0
                            GameUI.UpdateHUD()
                        end,
                    },
                    -- 自动布阵开关
                    ctx.UI.Button {
                        id = "autoDeployBtn",
                        text = "自动布阵:关",
                        fontSize = 11,
                        variant = "outline",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function(self)
                            AutoPlay.autoDeploy = not AutoPlay.autoDeploy
                            AutoPlay.autoDeployTimer = AutoPlay.autoDeploy and 3.0 or 0
                            GameUI.UpdateHUD()
                        end,
                    },
                },
            },
        }
    }
end

--- 自动合成逻辑

end
