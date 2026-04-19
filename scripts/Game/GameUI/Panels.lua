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
local SpeedBoost = require("Game.SpeedBoostData")

local FormatNum = ctx.FormatNum
local RARITY_COLORS = ctx.RARITY_COLORS

local function FormatStat(n)
    if n >= 100000000 then return string.format("%.1f亿", n / 100000000) end
    if n >= 10000 then return string.format("%.1f万", n / 10000) end
    return tostring(math.floor(n))
end

--- 攻击类型中文名
local ATTACK_TYPE_NAMES = {
    single = "单体", aoe = "范围", chain = "连锁",
}

--- 特殊效果中文名
local SPECIAL_NAMES = {
    none = "无", slow = "减速", dot = "持续伤害",
    amp_damage = "增伤标记", aura_buff = "攻击光环",
    armor_break = "破甲",
}

--- 英雄信息面板（点击塔时顶栏下方显示）
function GameUI.CreateHeroInfoPanel()
    return ctx.UI.Panel {
        id = "heroInfoPanel",
        position = "absolute",
        top = 52, left = 8, right = 8,
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
    local avatarPath = td.icon and ("image/avatars/avatar_" .. td.icon .. ".png") or nil
    local tierInfo = HeroData.GetStarTierInfo(td.id)

    -- 属性行辅助函数
    local function StatRow(label, value, color)
        return ctx.UI.Panel {
            flexDirection = "row", justifyContent = "space-between",
            width = "100%",
            children = {
                ctx.UI.Label { text = label, fontSize = 11, fontColor = { 160, 150, 180, 200 } },
                ctx.UI.Label { text = value, fontSize = 11, fontColor = color or { 255, 255, 255, 230 }, fontWeight = "bold" },
            },
        }
    end

    -- 技能列表
    local skillItems = {}
    for i, sk in ipairs(skills) do
        local typeTag = sk.type == "active" and "[主动]" or "[被动]"
        skillItems[#skillItems + 1] = ctx.UI.Panel {
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
                        ctx.UI.Label {
                            text = typeTag .. " " .. sk.name,
                            fontSize = 11,
                            fontColor = { 220, 210, 240, 255 },
                            fontWeight = "bold",
                        },
                        ctx.UI.Label {
                            text = sk.desc or "",
                            fontSize = 10,
                            fontColor = { 150, 140, 170, 200 },
                        },
                    },
                },
            },
        }
    end

    return {
        -- 第一行：头像 + 名称/品质/星级
        ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            alignItems = "center",
            children = {
                -- 头像
                ctx.UI.Panel {
                    width = 48, height = 48,
                    borderRadius = 8,
                    backgroundColor = rarityColor,
                    overflow = "hidden",
                    borderWidth = 1,
                    borderColor = rarityColor,
                    children = {
                        avatarPath and ctx.UI.Panel {
                            position = "absolute",
                            top = 0, left = 0, right = 0, bottom = 0,
                            backgroundImage = avatarPath,
                            backgroundFit = "cover",
                        } or ctx.UI.Label {
                            text = td.emoji or "👤",
                            fontSize = 24,
                        },
                    },
                },
                -- 名称信息
                ctx.UI.Panel {
                    flex = 1, gap = 2,
                    children = {
                        ctx.UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = {
                                ctx.UI.Label {
                                    text = td.name,
                                    fontSize = 15,
                                    fontColor = rarityColor,
                                    fontWeight = "bold",
                                },
                                rarity ~= "none" and ctx.UI.Panel {
                                    paddingLeft = 4, paddingRight = 4,
                                    paddingTop = 1, paddingBottom = 1,
                                    backgroundColor = rarityColor,
                                    borderRadius = 3,
                                    children = {
                                        ctx.UI.Label { text = rarity, fontSize = 9, fontColor = { 20, 16, 32, 255 }, fontWeight = "bold" },
                                    },
                                } or nil,
                            },
                        },
                        ctx.UI.Label {
                            text = "Lv." .. tower.heroLevel
                                .. "  ★" .. tower.star
                                .. "  " .. (tierInfo and tierInfo.name or "") .. (tower.heroStar or 0) .. "星",
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
        },

        -- 分隔线
        ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 140, 80 } },

        -- 属性区域
        ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 12,
            children = {
                -- 左列属性
                ctx.UI.Panel {
                    flex = 1, gap = 3,
                    children = {
                        StatRow("攻击", FormatStat(tower.attack), { 255, 120, 80, 255 }),
                        StatRow("攻速", string.format("%.2f/s", 1.0 / tower.speed), { 255, 200, 80, 255 }),
                    },
                },
                -- 右列属性
                ctx.UI.Panel {
                    flex = 1, gap = 3,
                    children = {
                        StatRow("射程", tostring(math.floor(tower.range)), { 200, 180, 255, 255 }),
                        StatRow("类型", ATTACK_TYPE_NAMES[td.attackType] or td.attackType, { 200, 200, 200, 230 }),
                    },
                },
            },
        },

        -- 副属性（如果有）
        (tower.armorPen > 0 or tower.critRate > 0) and ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 12,
            children = {
                ctx.UI.Panel {
                    flex = 1, gap = 3,
                    children = {
                        tower.armorPen > 0 and StatRow("破甲", string.format("%.1f%%", tower.armorPen * 100), { 255, 160, 80, 230 }) or nil,
                    },
                },
                ctx.UI.Panel {
                    flex = 1, gap = 3,
                    children = {
                        tower.critRate > 0 and StatRow("暴击", string.format("%.1f%%", tower.critRate * 100), { 255, 80, 80, 230 }) or nil,
                        tower.critDmg > 0 and StatRow("暴伤", string.format("%.0f%%", tower.critDmg * 100), { 255, 100, 100, 230 }) or nil,
                    },
                },
            },
        } or nil,

        -- 特殊效果
        td.special ~= "none" and ctx.UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = {
                ctx.UI.Label { text = "特殊:", fontSize = 10, fontColor = { 140, 130, 160, 180 } },
                ctx.UI.Panel {
                    paddingLeft = 4, paddingRight = 4,
                    paddingTop = 1, paddingBottom = 1,
                    backgroundColor = { 80, 60, 140, 150 },
                    borderRadius = 3,
                    children = {
                        ctx.UI.Label {
                            text = SPECIAL_NAMES[td.special] or td.special,
                            fontSize = 10,
                            fontColor = { 200, 180, 255, 230 },
                        },
                    },
                },
            },
        } or nil,

        -- 技能区域
        #skillItems > 0 and ctx.UI.Panel {
            width = "100%", gap = 4,
            children = {
                ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 140, 80 } },
                ctx.UI.Label { text = "技能", fontSize = 11, fontColor = { 180, 170, 200, 220 }, fontWeight = "bold" },
                table.unpack(skillItems),
            },
        } or nil,
    }
end

--- 底部操作栏（圆形召唤按钮）
function GameUI.CreateBottomBar()
    return ctx.UI.Panel {
        id = "bottomBar",
        position = "absolute",
        bottom = 4, left = 0, right = 0,
        height = 90,
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
                    -- 自动召唤开关（每日看一次广告解锁）
                    ctx.UI.Button {
                        id = "autoSummonBtn",
                        text = "自动召唤:关",
                        fontSize = 11,
                        variant = "outline",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function(self)
                            if not AutoPlay.IsUnlockedToday("autoSummon") then
                                local AdHelper = require("Game.AdHelper")
                                AdHelper.ShowRewardAd(function()
                                    AutoPlay.RecordAdUnlock("autoSummon")
                                    AutoPlay.autoSummon = true
                                    AutoPlay.autoSummonTimer = 0.4
                                    GameUI.UpdateHUD()
                                    Toast.Show("自动召唤已解锁", { 100, 200, 100 })
                                end)
                                return
                            end
                            AutoPlay.autoSummon = not AutoPlay.autoSummon
                            AutoPlay.autoSummonTimer = AutoPlay.autoSummon and 0.4 or 0
                            GameUI.UpdateHUD()
                        end,
                    },
                    -- 自动合成开关（每日看一次广告解锁）
                    ctx.UI.Button {
                        id = "autoMergeBtn",
                        text = "自动合成:关",
                        fontSize = 11,
                        variant = "outline",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function(self)
                            if not AutoPlay.IsUnlockedToday("autoMerge") then
                                local AdHelper = require("Game.AdHelper")
                                AdHelper.ShowRewardAd(function()
                                    AutoPlay.RecordAdUnlock("autoMerge")
                                    AutoPlay.autoMerge = true
                                    AutoPlay.autoMergeTimer = 0.4
                                    GameUI.UpdateHUD()
                                    Toast.Show("自动合成已解锁", { 100, 200, 100 })
                                end)
                                return
                            end
                            AutoPlay.autoMerge = not AutoPlay.autoMerge
                            AutoPlay.autoMergeTimer = AutoPlay.autoMerge and 0.4 or 0
                            GameUI.UpdateHUD()
                        end,
                    },
                    -- 自动布阵开关（每日看一次广告解锁）
                    ctx.UI.Button {
                        id = "autoDeployBtn",
                        text = "自动布阵:关",
                        fontSize = 11,
                        variant = "outline",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function(self)
                            if not AutoPlay.IsUnlockedToday("autoDeploy") then
                                local AdHelper = require("Game.AdHelper")
                                AdHelper.ShowRewardAd(function()
                                    AutoPlay.RecordAdUnlock("autoDeploy")
                                    AutoPlay.autoDeploy = true
                                    AutoPlay.autoDeployTimer = 3.0
                                    GameUI.UpdateHUD()
                                    Toast.Show("自动布阵已解锁", { 100, 200, 100 })
                                end)
                                return
                            end
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
