-- Game/DungeonUI/TrainingDummy.lua
-- 木桩副本 UI：预设选择 / 参数调节 / 属性预览 / 进入实战

local TDD       = require("Game.TrainingDummyData")
local HeroData  = require("Game.HeroData")
local Config    = require("Game.Config")
local FormatNum = require("Game.FormatUtil").FormatNum
local Toast     = require("Game.Toast")

local TrainingDummy = {}

-- ============================================================================
-- 主题色板
-- ============================================================================
local C = {
    cardBg        = { 30, 24, 50, 200 },
    cardBorder    = { 60, 50, 90, 100 },
    sectionTitle  = { 210, 195, 240, 255 },
    accentPurple  = { 130, 50, 200, 220 },
    accentPurpleBd= { 180, 120, 255, 255 },
    accentBlue    = { 50, 110, 180, 230 },
    accentBlueBd  = { 100, 180, 255, 220 },
    chipOff       = { 40, 34, 58, 200 },
    chipBorderOff = { 65, 55, 90, 120 },
    statLabel     = { 150, 140, 175 },
    statValue     = { 230, 220, 255 },
    gold          = { 255, 200, 80, 255 },
    red           = { 255, 90, 90, 255 },
    green         = { 100, 220, 140, 255 },
    tipBg         = { 35, 45, 60, 200 },
    tipBorder     = { 60, 100, 140, 100 },
    tipText       = { 160, 190, 220 },
    btnStartBg    = { 170, 50, 55, 255 },
    btnStartBd    = { 220, 100, 100, 120 },
    dim           = { 130, 120, 155 },
}

-- ============================================================================
-- 通用卡片容器
-- ============================================================================
local function Card(UI, children, opts)
    opts = opts or {}
    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = opts.bg or C.cardBg,
        borderRadius = opts.radius or 12,
        borderWidth = 1,
        borderColor = opts.border or C.cardBorder,
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 12, paddingBottom = 12,
        gap = opts.gap or 10,
        children = children,
    }
end

-- 段落标题（带可选图标前缀）
local function SectionHeader(UI, icon, text, color)
    return UI.Label {
        text = (icon or "") .. text,
        fontSize = 14,
        fontWeight = "bold",
        fontColor = color or C.sectionTitle,
        pointerEvents = "none",
    }
end

-- ============================================================================
-- 详情页
-- ============================================================================

---@param ctx table  DungeonUI 上下文
function TrainingDummy.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    pageRoot:RemoveAllChildren()

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "center",
        children = {
            UI.Panel { width = 12 },
            UI.Label {
                text = "木桩训练",
                fontSize = 20,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 240 },
                pointerEvents = "none",
            },
        },
    })

    local content = {}

    -- 1) 预设选择 卡片
    content[#content + 1] = TrainingDummy.BuildPresetCard(UI, S, ctx)

    -- 2) 属性预览 卡片
    content[#content + 1] = TrainingDummy.BuildStatsCard(UI, S)

    -- 3) 自定义参数 卡片（仅自定义模式）
    local preset = TDD.GetPresets()[TDD.GetSelectedIndex()]
    if preset and preset.isCustom then
        content[#content + 1] = TrainingDummy.BuildCustomSection(UI, S, ctx)
    end

    -- 4) 挑战时长 卡片
    content[#content + 1] = TrainingDummy.BuildDurationCard(UI, S, ctx)

    -- 5) 开始挑战按钮
    content[#content + 1] = TrainingDummy.BuildStartButton(UI, S, ctx)

    -- 6) 最佳记录 卡片
    local bestCard = TrainingDummy.BuildBestRecordCard(UI, S)
    if bestCard then
        content[#content + 1] = bestCard
    end

    -- 7) 战斗提示 卡片
    content[#content + 1] = TrainingDummy.BuildTipsCard(UI, S)

    -- 8) 历史记录
    local history = TDD.GetHistory()
    if #history > 0 then
        content[#content + 1] = TrainingDummy.BuildHistorySection(UI, S)
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 4, paddingBottom = 20,
                gap = 10,
                children = content,
            },
        },
    })

    -- 底部栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 8, paddingBottom = 8,
        flexShrink = 0,
        children = {
            UI.Button {
                text = "返回",
                fontSize = 13,
                width = 56, height = 42,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    ctx.SetView("list")
                end,
            },
        },
    })
end

-- ============================================================================
-- 开始战斗
-- ============================================================================

function TrainingDummy._StartBattle(UI, S, ctx)
    local GameUI = require("Game.GameUI")
    local State  = require("Game.State")
    local WorldBossData = require("Game.WorldBossData")

    local config, label = TDD.BuildBattleConfig()
    local duration = TDD.GetSimDuration()

    config.onStart = function()
        State.worldBossActive = true
        State.worldBossTotalDamage = 0
        local dummyDef = config.waves[1] and config.waves[1][1] and config.waves[1][1].typeDef
        if dummyDef then
            TDD.InitPanel(dummyDef)
        end
    end

    config.onWin = function(result)
        State.worldBossActive = false
        State.trainingDummy = nil
        local totalDamage = result.totalDamage or State.worldBossTotalDamage or 0
        TDD.RecordHistory(totalDamage, duration, label)
        local dps = duration > 0 and math.floor(totalDamage / duration) or 0
        Toast.Show(label .. " · 伤害 " .. WorldBossData.FormatDamage(totalDamage)
                   .. " · DPS " .. WorldBossData.FormatDamage(dps), { 255, 200, 80 })
        GameUI.ExitDungeonBattle()
    end

    config.onExit = function(result, continueExit)
        State.worldBossActive = false
        State.trainingDummy = nil
        local totalDamage = result.totalDamage or State.worldBossTotalDamage or 0
        if totalDamage > 0 then
            TDD.RecordHistory(totalDamage, duration, label)
            Toast.Show(label .. " · 伤害 " .. WorldBossData.FormatDamage(totalDamage), S.dim)
        end
        continueExit()
    end

    config.onLose = function(result)
        State.worldBossActive = false
        State.trainingDummy = nil
        local totalDamage = result.totalDamage or State.worldBossTotalDamage or 0
        if totalDamage > 0 then
            TDD.RecordHistory(totalDamage, duration, label)
        end
        GameUI.ExitDungeonBattle()
    end

    GameUI.EnterDungeonBattle(config)
end

-- ============================================================================
-- 1) 预设选择 卡片
-- ============================================================================

function TrainingDummy.BuildPresetCard(UI, S, ctx)
    local presets = TDD.GetPresets()
    local selIdx = TDD.GetSelectedIndex()
    local chips = {}

    for i, p in ipairs(presets) do
        local isSel = (i == selIdx)
        chips[#chips + 1] = UI.Panel {
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 8, paddingBottom = 8,
            borderRadius = 10,
            backgroundColor = isSel and C.accentPurple or C.chipOff,
            borderWidth = isSel and 2 or 1,
            borderColor = isSel and C.accentPurpleBd or C.chipBorderOff,
            onClick = function()
                TDD.SetSelectedIndex(i)
                ctx.SetView("training_dummy_detail")
            end,
            children = {
                UI.Label {
                    text = p.name,
                    fontSize = 13,
                    fontWeight = isSel and "bold" or "normal",
                    fontColor = isSel and { 255, 255, 255, 255 } or { 180, 170, 200 },
                    pointerEvents = "none",
                },
            },
        }
    end

    local preset = presets[selIdx]
    local descText = preset and preset.desc or ""

    if preset and preset.dynamic then
        local bestStage = (HeroData.stats and HeroData.stats.bestStage) or 1
        local stageNum = bestStage + 1
        local theme = Config.GetTheme(stageNum)
        descText = string.format("模拟第%d关 %s Boss 的防御属性", stageNum, theme.name or "")
    end

    -- 当前Boss模式：血量切换选项
    local hpToggle = nil
    if preset and preset.dynamic then
        local useBossHP = TDD.GetUseBossHP()
        hpToggle = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            marginTop = 4,
            children = {
                UI.Label {
                    text = "血量模式",
                    fontSize = 12,
                    fontColor = C.statLabel,
                    pointerEvents = "none",
                },
                UI.Panel {
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 8,
                    backgroundColor = (not useBossHP) and C.accentBlue or C.chipOff,
                    borderWidth = (not useBossHP) and 2 or 1,
                    borderColor = (not useBossHP) and C.accentBlueBd or C.chipBorderOff,
                    onClick = function()
                        TDD.SetUseBossHP(false)
                        ctx.SetView("training_dummy_detail")
                    end,
                    children = {
                        UI.Label {
                            text = "无限",
                            fontSize = 12,
                            fontWeight = (not useBossHP) and "bold" or "normal",
                            fontColor = (not useBossHP) and { 255, 255, 255 } or { 180, 170, 200 },
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 8,
                    backgroundColor = useBossHP and { 170, 80, 50, 220 } or C.chipOff,
                    borderWidth = useBossHP and 2 or 1,
                    borderColor = useBossHP and { 230, 140, 80, 255 } or C.chipBorderOff,
                    onClick = function()
                        TDD.SetUseBossHP(true)
                        ctx.SetView("training_dummy_detail")
                    end,
                    children = {
                        UI.Label {
                            text = "Boss真实血量",
                            fontSize = 12,
                            fontWeight = useBossHP and "bold" or "normal",
                            fontColor = useBossHP and { 255, 255, 255 } or { 180, 170, 200 },
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "选择木桩"),
        UI.Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 8,
            children = chips,
        },
        descText ~= "" and UI.Label {
            text = descText,
            fontSize = 11,
            fontColor = C.dim,
            pointerEvents = "none",
        } or nil,
        hpToggle,
    })
end

-- ============================================================================
-- 2) 属性预览 卡片
-- ============================================================================

function TrainingDummy.BuildStatsCard(UI, S)
    local dummyDef = TDD.BuildDummyDef()

    -- 属性行
    local function StatRow(label, value, color)
        return UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            children = {
                UI.Label {
                    text = label,
                    fontSize = 12,
                    fontColor = C.statLabel,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = value,
                    fontSize = 12,
                    fontWeight = "bold",
                    fontColor = color or C.statValue,
                    pointerEvents = "none",
                },
            },
        }
    end

    -- 格式化百分比
    local function FmtPct(v)
        if type(v) ~= "number" then return "0%" end
        local pct = v < 1 and (v * 100) or v  -- 兼容 0-1 和 0-100
        return string.format("%.0f%%", pct)
    end

    -- HP 显示
    local hpText
    if dummyDef.baseHP == math.huge then
        hpText = "无限"
    else
        hpText = FormatNum(math.floor(dummyDef.baseHP))
    end

    local statRows = {
        StatRow("生命值 HP", hpText, { 100, 200, 120 }),
        StatRow("物理防御 DEF", FormatNum(math.floor(dummyDef.baseDEF or 0)), { 200, 180, 130 }),
        StatRow("魔法抗性 RES", FmtPct(dummyDef.baseRES or 0), { 130, 180, 200 }),
    }

    -- 额外减免属性（非零才显示）
    local extras = {
        { key = "critDmgReduce",  label = "暴伤减免" },
        { key = "dmgBonusReduce", label = "伤害减免" },
        { key = "typeDmgReduce",  label = "类型减免" },
        { key = "armorPenResist", label = "破甲抵抗" },
    }
    for _, ex in ipairs(extras) do
        local v = dummyDef[ex.key] or 0
        if v > 0 then
            statRows[#statRows + 1] = StatRow(ex.label, FmtPct(v), { 180, 160, 200 })
        end
    end

    -- 分隔线
    local function Divider()
        return UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 80, 65, 120, 80 },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "木桩属性"),
        Divider(),
        UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 6,
            children = statRows,
        },
    }, { gap = 8 })
end

-- ============================================================================
-- 3) 自定义参数
-- ============================================================================

function TrainingDummy.BuildCustomSection(UI, S, ctx)
    local params = TDD.GetCustomParams()

    local function ParamRow(label, key, unit, min, max, step)
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = label,
                    fontSize = 12,
                    fontColor = C.statLabel,
                    width = 70,
                    pointerEvents = "none",
                },
                UI.Panel {
                    width = 30, height = 30,
                    borderRadius = 8,
                    backgroundColor = { 60, 45, 90, 200 },
                    borderWidth = 1,
                    borderColor = { 100, 80, 140, 120 },
                    justifyContent = "center",
                    alignItems = "center",
                    onClick = function()
                        local v = math.max(min, (params[key] or 0) - step)
                        TDD.SetCustomParam(key, v)
                        ctx.SetView("training_dummy_detail")
                    end,
                    children = {
                        UI.Label {
                            text = "-",
                            fontSize = 16, fontWeight = "bold",
                            fontColor = { 200, 180, 230 },
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    flex = 1,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = FormatNum(params[key] or 0) .. (unit or ""),
                            fontSize = 13,
                            fontWeight = "bold",
                            fontColor = C.statValue,
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    width = 30, height = 30,
                    borderRadius = 8,
                    backgroundColor = { 60, 45, 90, 200 },
                    borderWidth = 1,
                    borderColor = { 100, 80, 140, 120 },
                    justifyContent = "center",
                    alignItems = "center",
                    onClick = function()
                        local v = math.min(max, (params[key] or 0) + step)
                        TDD.SetCustomParam(key, v)
                        ctx.SetView("training_dummy_detail")
                    end,
                    children = {
                        UI.Label {
                            text = "+",
                            fontSize = 16, fontWeight = "bold",
                            fontColor = { 200, 180, 230 },
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "自定义参数", { 200, 160, 255, 255 }),
        ParamRow("物防 DEF", "def", "", 0, 100000, 1000),
        ParamRow("魔抗 RES", "res", "%", 0, 95, 5),
        ParamRow("暴击减免", "critDmgReduce", "%", 0, 90, 5),
        ParamRow("伤害减免", "dmgBonusReduce", "%", 0, 90, 5),
        ParamRow("类型减免", "typeDmgReduce", "%", 0, 90, 5),
        ParamRow("破甲抵抗", "armorPenResist", "%", 0, 90, 5),
    }, { gap = 6 })
end

-- ============================================================================
-- 4) 挑战时长 卡片
-- ============================================================================

function TrainingDummy.BuildDurationCard(UI, S, ctx)
    local dur = TDD.GetSimDuration()
    local durations = { 30, 60, 120, 300 }
    local labels    = { "30s", "60s", "120s", "5min" }
    local chips = {}

    for idx, d in ipairs(durations) do
        local isSel = (d == dur)
        chips[#chips + 1] = UI.Panel {
            flex = 1,
            height = 38,
            justifyContent = "center",
            alignItems = "center",
            borderRadius = 10,
            backgroundColor = isSel and C.accentBlue or C.chipOff,
            borderWidth = isSel and 2 or 1,
            borderColor = isSel and C.accentBlueBd or C.chipBorderOff,
            onClick = function()
                TDD.SetSimDuration(d)
                ctx.SetView("training_dummy_detail")
            end,
            children = {
                UI.Label {
                    text = labels[idx],
                    fontSize = 13,
                    fontWeight = isSel and "bold" or "normal",
                    fontColor = isSel and { 255, 255, 255, 255 } or { 180, 170, 200 },
                    pointerEvents = "none",
                },
            },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "挑战时长"),
        UI.Panel {
            flexDirection = "row",
            gap = 8,
            width = "100%",
            children = chips,
        },
    })
end

-- ============================================================================
-- 5) 开始挑战按钮
-- ============================================================================

function TrainingDummy.BuildStartButton(UI, S, ctx)
    return UI.Panel {
        width = "100%",
        alignItems = "center",
        marginTop = 4,
        children = {
            UI.Panel {
                width = "100%",
                height = 52,
                borderRadius = 14,
                backgroundColor = C.btnStartBg,
                borderWidth = 1.5,
                borderColor = C.btnStartBd,
                justifyContent = "center",
                alignItems = "center",
                onClick = function()
                    TrainingDummy._StartBattle(UI, S, ctx)
                end,
                children = {
                    UI.Label {
                        text = "开始挑战",
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255 },
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 6) 最佳记录 卡片
-- ============================================================================

function TrainingDummy.BuildBestRecordCard(UI, S)
    local history = TDD.GetHistory()
    if #history == 0 then return nil end

    -- 找最佳 DPS 和最佳总伤
    local bestDPS = { dps = 0 }
    local bestDmg = { totalDmg = 0 }
    for _, h in ipairs(history) do
        if h.dps > bestDPS.dps then bestDPS = h end
        if h.totalDmg > bestDmg.totalDmg then bestDmg = h end
    end

    local function RecordItem(title, mainVal, subVal, color)
        return UI.Panel {
            flex = 1,
            flexDirection = "column",
            alignItems = "center",
            gap = 4,
            children = {
                UI.Label {
                    text = title,
                    fontSize = 11,
                    fontColor = C.dim,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = mainVal,
                    fontSize = 18,
                    fontWeight = "bold",
                    fontColor = color,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = subVal,
                    fontSize = 10,
                    fontColor = C.dim,
                    pointerEvents = "none",
                },
            },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "最佳记录", C.gold),
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            children = {
                RecordItem(
                    "最高 DPS",
                    FormatNum(math.floor(bestDPS.dps)),
                    bestDPS.preset or "",
                    C.red
                ),
                -- 分隔竖线
                UI.Panel {
                    width = 1,
                    height = "100%",
                    backgroundColor = { 80, 65, 120, 80 },
                },
                RecordItem(
                    "最高总伤",
                    FormatNum(math.floor(bestDmg.totalDmg)),
                    bestDmg.preset or "",
                    C.gold
                ),
            },
        },
    }, { bg = { 35, 28, 20, 200 }, border = { 100, 80, 40, 120 } })
end

-- ============================================================================
-- 7) 战斗提示 卡片
-- ============================================================================

function TrainingDummy.BuildTipsCard(UI, S)
    local tips = {
        "战斗中可实时调节 DEF / RES",
        "点击 +木桩 可同时测试群体伤害",
        "切换「运动」让木桩沿路径移动",
        "使用「重置」恢复初始防御属性",
    }

    local tipRows = {}
    for _, t in ipairs(tips) do
        tipRows[#tipRows + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Panel {
                    width = 4, height = 4,
                    borderRadius = 2,
                    backgroundColor = { 100, 160, 220, 200 },
                },
                UI.Label {
                    text = t,
                    fontSize = 11,
                    fontColor = C.tipText,
                    pointerEvents = "none",
                    flex = 1,
                    flexShrink = 1,
                },
            },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "操作提示", { 120, 170, 220 }),
        UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 5,
            children = tipRows,
        },
    }, { bg = C.tipBg, border = C.tipBorder, gap = 8 })
end

-- ============================================================================
-- 8) 历史记录
-- ============================================================================

function TrainingDummy.BuildHistorySection(UI, S)
    local history = TDD.GetHistory()
    local bestDPS = 0
    for _, h in ipairs(history) do
        if h.dps > bestDPS then bestDPS = h.dps end
    end

    local rows = {}
    for i = #history, math.max(1, #history - 9), -1 do
        local h = history[i]
        local isBest = (h.dps >= bestDPS and bestDPS > 0)

        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 6, paddingBottom = 6,
            paddingLeft = 8, paddingRight = 8,
            borderBottomWidth = 1,
            borderColor = { 50, 40, 70, 60 },
            backgroundColor = isBest and { 80, 60, 20, 60 } or nil,
            borderRadius = isBest and 6 or 0,
            children = {
                UI.Panel {
                    flexDirection = "column",
                    flex = 1,
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 4,
                            children = {
                                UI.Label {
                                    text = h.preset,
                                    fontSize = 12,
                                    fontWeight = isBest and "bold" or "normal",
                                    fontColor = isBest and C.gold or { 220, 215, 230 },
                                    pointerEvents = "none",
                                },
                                isBest and UI.Label {
                                    text = "BEST",
                                    fontSize = 9,
                                    fontWeight = "bold",
                                    fontColor = C.gold,
                                    pointerEvents = "none",
                                } or nil,
                            },
                        },
                        UI.Label {
                            text = h.duration .. "s · " .. h.heroes,
                            fontSize = 10,
                            fontColor = C.dim,
                            pointerEvents = "none",
                            numberOfLines = 1,
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "column",
                    alignItems = "flex-end",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = "DPS " .. FormatNum(math.floor(h.dps)),
                            fontSize = 12,
                            fontWeight = "bold",
                            fontColor = isBest and C.gold or C.red,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = "总伤 " .. FormatNum(math.floor(h.totalDmg)),
                            fontSize = 10,
                            fontColor = C.dim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    return Card(UI, {
        SectionHeader(UI, nil, "历史记录"),
        UI.Panel {
            width = "100%",
            flexDirection = "column",
            children = rows,
        },
    })
end

return TrainingDummy
