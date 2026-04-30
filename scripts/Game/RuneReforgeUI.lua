-- Game/RuneReforgeUI.lua
-- 深渊符文系统 — 洗练界面
-- 弹窗形式：当前词条 vs 预览词条 对比 + 锁定控制 + 费用显示

local Config = require("Game.Config")
local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")

local RuneReforgeUI = {}

---@type any
local UI = nil
---@type any
local overlayRoot = nil     -- 弹窗挂载的父容器
---@type table|nil
local currentRune = nil     -- 当前正在洗练的符文
---@type table|nil
local previewAffixes = nil  -- 常规洗练预览结果
---@type table|nil
local previewTagAffix = nil -- 标签洗练预览结果（单条或nil）
---@type boolean
local showTagPreview = false -- 是否处于标签词条预览状态
---@type function|nil
local onCloseCallback = nil -- 关闭时的回调
---@type string
local reforgeMode = "basic" -- "basic" / "directed_base" / "directed_special"

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开洗练弹窗
---@param parentPanel any   挂载弹窗的父面板
---@param rune table        要洗练的符文
---@param onClose function  关闭回调
function RuneReforgeUI.Open(parentPanel, rune, onClose)
    UI = UI or require("urhox-libs/UI")
    overlayRoot = parentPanel
    currentRune = rune
    previewAffixes = nil
    previewTagAffix = nil
    showTagPreview = false
    onCloseCallback = onClose
    reforgeMode = "basic"
    RuneReforgeUI.Render()
end

--- 关闭弹窗
function RuneReforgeUI.Close()
    if overlayRoot and overlayRoot.overlay_ then
        overlayRoot:RemoveChild(overlayRoot.overlay_)
        overlayRoot.overlay_ = nil
    end
    currentRune = nil
    previewAffixes = nil
    previewTagAffix = nil
    showTagPreview = false
    if onCloseCallback then
        onCloseCallback()
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================

function RuneReforgeUI.Render()
    if not overlayRoot or not currentRune then return end

    -- 清除旧弹窗
    if overlayRoot.overlay_ then
        overlayRoot:RemoveChild(overlayRoot.overlay_)
    end

    local rune = currentRune
    local series = RuneData.GetSeries(rune.seriesId)
    local quality = RuneData.GetQuality(rune.qualityId)

    -- 计算锁定数 & 费用
    local lockedCount = 0
    for _, a in ipairs(rune.affixes) do
        if a.locked then lockedCount = lockedCount + 1 end
    end

    local overlay = UI.Panel {
        id = "reforgeOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 60,
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self)
            -- 点击背景关闭
            RuneReforgeUI.Close()
        end,
        children = {
            RuneReforgeUI.CreatePanel(rune, series, quality, lockedCount),
        },
    }

    overlayRoot:AddChild(overlay)
    overlayRoot.overlay_ = overlay
end

--- 创建洗练面板主体
function RuneReforgeUI.CreatePanel(rune, series, quality, lockedCount)
    local children = {}

    -- 标题行
    children[#children + 1] = RuneReforgeUI.CreateTitle(rune, series, quality)

    -- 模式选择（基础 / 定向基础 / 定向特殊）
    children[#children + 1] = RuneReforgeUI.CreateModeSelector()

    -- 词条池说明（定向模式时显示）
    if reforgeMode ~= "basic" then
        children[#children + 1] = RuneReforgeUI.CreatePoolHint()
    end

    -- 分隔线
    children[#children + 1] = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 60, 120, 100 },
        flexShrink = 0,
    }

    -- 词条对比区
    children[#children + 1] = RuneReforgeUI.CreateAffixComparison(rune, quality)

    -- 分隔线
    children[#children + 1] = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 60, 120, 100 },
        flexShrink = 0,
    }

    -- 费用信息
    children[#children + 1] = RuneReforgeUI.CreateCostInfo(lockedCount)

    -- 操作按钮
    children[#children + 1] = RuneReforgeUI.CreateButtons(rune, lockedCount)

    return UI.Panel {
        width = "90%",
        maxHeight = "90%",
        backgroundColor = { 25, 20, 40, 250 },
        borderRadius = 12,
        borderWidth = 1,
        borderColor = { quality.color[1], quality.color[2], quality.color[3], 150 },
        flexDirection = "column",
        paddingTop = 12, paddingBottom = 12,
        paddingLeft = 14, paddingRight = 14,
        gap = 8,
        pointerEvents = "auto",
        onClick = function(self) end, -- 阻止穿透到背景
        overflow = "scroll",
        children = children,
    }
end

-- ============================================================================
-- 标题行
-- ============================================================================

function RuneReforgeUI.CreateTitle(rune, series, quality)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Label {
                        text = "洗练",
                        fontSize = 18, fontColor = { 220, 200, 255, 255 }, fontWeight = "bold",
                    },
                    UI.Panel {
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 1, paddingBottom = 1,
                        backgroundColor = { quality.color[1], quality.color[2], quality.color[3], 180 },
                        borderRadius = 4,
                        children = {
                            UI.Label {
                                text = quality.name,
                                fontSize = 10, fontColor = { 20, 16, 32, 255 },
                            },
                        },
                    },
                    -- 词条说明问号按钮
                    UI.Panel {
                        width = 18, height = 18,
                        borderRadius = 9,
                        borderWidth = 1,
                        borderColor = { 140, 100, 200, 180 },
                        backgroundColor = { 50, 35, 75, 200 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function() RuneReforgeUI.ShowAffixHelpPopup() end,
                        children = {
                            UI.Label {
                                text = "?", fontSize = 10, fontWeight = "bold",
                                fontColor = { 180, 140, 240, 255 }, pointerEvents = "none",
                            },
                        },
                    },
                },
            },
            UI.Button {
                text = "✕", fontSize = 14, variant = "ghost",
                width = 28, height = 28,
                onClick = function(self)
                    RuneReforgeUI.Close()
                end,
            },
        },
    }
end

-- ============================================================================
-- 模式选择器
-- ============================================================================

function RuneReforgeUI.CreateModeSelector()
    local bestStage = HeroData.stats.bestStage or 0
    local directedUnlocked = bestStage >= RuneConfig.DIRECTED_UNLOCK_STAGE

    local modes = {
        { id = "basic",            label = "基础洗练",   desc = "重随所有未锁定词条" },
        { id = "directed_base",    label = "定向·基础",  desc = "仅从基础属性池重随" },
        { id = "directed_special", label = "定向·特殊",  desc = "仅从特殊效果池重随" },
    }

    local tabs = {}
    for _, m in ipairs(modes) do
        local isActive = (reforgeMode == m.id)
        local isLocked = (m.id ~= "basic") and not directedUnlocked

        tabs[#tabs + 1] = UI.Panel {
            flex = 1,
            height = 32,
            justifyContent = "center", alignItems = "center",
            backgroundColor = isActive and { 80, 50, 140, 220 } or { 35, 30, 55, 180 },
            borderRadius = 6,
            borderWidth = isActive and 1 or 0,
            borderColor = { 160, 120, 255, 200 },
            pointerEvents = isLocked and "none" or "auto",
            opacity = isLocked and 0.4 or 1.0,
            onClick = not isLocked and function(self)
                reforgeMode = m.id
                previewAffixes = nil
                RuneReforgeUI.Render()
            end or nil,
            children = {
                UI.Label {
                    text = isLocked and ("🔒 " .. m.label) or m.label,
                    fontSize = 10,
                    fontColor = isActive and { 255, 255, 255, 255 } or { 180, 170, 210, 200 },
                    pointerEvents = "none",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = tabs,
            },
            -- 模式说明
            (function()
                if not directedUnlocked then
                    return UI.Label {
                        text = "定向洗练需通关第" .. RuneConfig.DIRECTED_UNLOCK_STAGE .. "关解锁",
                        fontSize = 9, fontColor = { 150, 130, 180, 150 },
                    }
                end
                local descMap = {
                    basic            = { text = "从全部词条池中随机重随未锁定词条", color = { 150, 140, 180, 180 } },
                    directed_base    = { text = "仅从攻击力/暴击/穿甲等基础属性池中重随", color = { 100, 180, 255, 180 } },
                    directed_special = { text = "仅从连锁/减速/DOT等特殊效果池中重随", color = { 255, 160, 80, 180 } },
                }
                local d = descMap[reforgeMode]
                if d then
                    return UI.Label {
                        text = d.text,
                        fontSize = 9, fontColor = d.color,
                    }
                end
                return nil
            end)(),
        },
    }
end

-- ============================================================================
-- 词条池说明（定向模式时显示可选词条范围）
-- ============================================================================

function RuneReforgeUI.CreatePoolHint()
    local isBase = reforgeMode == "directed_base"
    local pool = isBase and RuneConfig.AFFIX_BASE or RuneConfig.AFFIX_SPECIAL
    local poolLabel = isBase and "基础属性池" or "特殊效果池"
    local poolColor = isBase and { 100, 180, 255, 200 } or { 255, 160, 80, 200 }
    local bgColor   = isBase and { 30, 50, 80, 120 }   or { 60, 35, 20, 120 }

    -- 构建词条标签（基础池词缀）
    local tags = {}
    for _, def in ipairs(pool) do
        tags[#tags + 1] = UI.Panel {
            paddingLeft = 5, paddingRight = 5,
            paddingTop = 2, paddingBottom = 2,
            backgroundColor = { poolColor[1], poolColor[2], poolColor[3], 50 },
            borderRadius = 3,
            borderWidth = 1,
            borderColor = { poolColor[1], poolColor[2], poolColor[3], 80 },
            children = {
                UI.Label {
                    text = def.name,
                    fontSize = 9,
                    fontColor = poolColor,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        paddingTop = 4, paddingBottom = 4,
        paddingLeft = 6, paddingRight = 6,
        backgroundColor = bgColor,
        borderRadius = 6,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "重随范围：" .. poolLabel .. "（共" .. #pool .. "种）",
                fontSize = 10,
                fontColor = poolColor,
                fontWeight = "bold",
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 4,
                children = tags,
            },
        },
    }
end

-- ============================================================================
-- 词条对比区
-- ============================================================================

function RuneReforgeUI.CreateAffixComparison(rune, quality)
    local hasPreview = previewAffixes ~= nil

    -- 左列：当前词条
    local currentItems = {}
    for i, affix in ipairs(rune.affixes) do
        currentItems[#currentItems + 1] = RuneReforgeUI.CreateAffixRow(
            affix, quality, true, i, not hasPreview
        )
    end

    -- 右列：预览词条（如果有）
    local previewItems = {}
    if hasPreview then
        for _, affix in ipairs(previewAffixes) do
            previewItems[#previewItems + 1] = RuneReforgeUI.CreateAffixRow(
                affix, quality, false, nil, false
            )
        end
    end

    -- 标签词条区域
    local tagSection = RuneReforgeUI.CreateTagAffixSection(rune, quality)

    local sections = {}

    if hasPreview then
        sections[#sections + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            children = {
                -- 当前词条列
                UI.Panel {
                    flex = 1,
                    flexDirection = "column",
                    gap = 3,
                    children = {
                        UI.Label {
                            text = "当前",
                            fontSize = 11, fontColor = { 150, 140, 180, 200 },
                            fontWeight = "bold",
                        },
                        table.unpack(currentItems),
                    },
                },
                -- 箭头
                UI.Panel {
                    width = 20,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = "→", fontSize = 18, fontColor = { 255, 200, 80, 255 } },
                    },
                },
                -- 预览词条列
                UI.Panel {
                    flex = 1,
                    flexDirection = "column",
                    gap = 3,
                    children = {
                        UI.Label {
                            text = "预览",
                            fontSize = 11, fontColor = { 255, 200, 80, 200 },
                            fontWeight = "bold",
                        },
                        table.unpack(previewItems),
                    },
                },
            },
        }
    else
        sections[#sections + 1] = UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 3,
            children = {
                UI.Label {
                    text = "当前词条（点击🔒锁定保留）",
                    fontSize = 11, fontColor = { 150, 140, 180, 200 },
                },
                table.unpack(currentItems),
            },
        }
    end

    -- 追加标签词条区
    if tagSection then
        sections[#sections + 1] = tagSection
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
        paddingTop = 6, paddingBottom = 6,
        flexShrink = 0,
        children = sections,
    }
end

--- 创建标签词条区域（当前 + 预览）
function RuneReforgeUI.CreateTagAffixSection(rune, quality)
    local tagAffix = rune.tagAffix
    local hasTagPreview = showTagPreview and previewTagAffix ~= nil

    -- 没有标签词条也没有预览 → 显示占位提示
    if not tagAffix and not hasTagPreview then
        return UI.Panel {
            width = "100%",
            paddingTop = 4, paddingBottom = 4,
            paddingLeft = 4, paddingRight = 4,
            borderTopWidth = 1,
            borderColor = { 80, 60, 120, 60 },
            flexDirection = "column",
            gap = 2,
            children = {
                UI.Label {
                    text = "标签词条",
                    fontSize = 10, fontColor = { 200, 120, 255, 180 }, fontWeight = "bold",
                },
                UI.Label {
                    text = "（无标签词条，可通过标签洗练获得）",
                    fontSize = 10, fontColor = { 140, 120, 170, 150 },
                },
            },
        }
    end

    local tagColor = { 200, 120, 255 }
    -- 获取标签词条的层级颜色
    if tagAffix then
        local cat = RuneConfig.AFFIX_CATEGORY[tagAffix.id]
        if cat then
            local tier = tonumber(cat:sub(6, 6))
            if tier and Config.AFFIX_TIER_COLORS[tier] then
                tagColor = Config.AFFIX_TIER_COLORS[tier]
            end
        end
    end

    local children = {}

    -- 标题
    children[#children + 1] = UI.Label {
        text = "标签词条（独立洗练）",
        fontSize = 10, fontColor = { tagColor[1], tagColor[2], tagColor[3], 200 }, fontWeight = "bold",
    }

    if hasTagPreview then
        -- 标签词条有预览：左→右对比
        local curText = tagAffix and RuneData.FormatAffix(tagAffix) or "（无）"
        local newText = previewTagAffix and RuneData.FormatAffix(previewTagAffix) or "（清除标签）"
        local newColor = previewTagAffix and { 200, 120, 255, 255 } or { 140, 120, 170, 180 }

        children[#children + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = curText,
                    fontSize = 12,
                    fontColor = tagAffix and { tagColor[1], tagColor[2], tagColor[3], 255 } or { 140, 120, 170, 180 },
                    flex = 1,
                },
                UI.Label { text = "→", fontSize = 14, fontColor = { 255, 200, 80, 255 } },
                UI.Label {
                    text = newText,
                    fontSize = 12,
                    fontColor = newColor,
                    flex = 1,
                },
            },
        }
        -- 预览描述
        if previewTagAffix then
            local previewDef = RuneConfig.AFFIX_MAP[previewTagAffix.id]
            if previewDef and previewDef.desc then
                local dText = previewDef.desc
                if previewDef.tier and Config.FormatAffixDesc then
                    dText = Config.FormatAffixDesc(previewDef, previewTagAffix.value, previewTagAffix.value2)
                end
                children[#children + 1] = UI.Label {
                    text = dText,
                    fontSize = 9, fontColor = { 160, 155, 180, 160 },
                    paddingLeft = 4,
                }
            end
        end
    elseif tagAffix then
        -- 仅显示当前标签词条
        local valueText = RuneData.FormatAffix(tagAffix)
        local rangeText = RuneData.FormatAffixRange(tagAffix, rune.qualityId)
        children[#children + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            paddingTop = 2, paddingBottom = 2,
            paddingLeft = 4,
            children = {
                UI.Panel {
                    paddingLeft = 4, paddingRight = 4,
                    paddingTop = 1, paddingBottom = 1,
                    backgroundColor = { tagColor[1], tagColor[2], tagColor[3], 40 },
                    borderRadius = 3,
                    borderWidth = 1,
                    borderColor = { tagColor[1], tagColor[2], tagColor[3], 80 },
                    children = {
                        UI.Label {
                            text = "标签",
                            fontSize = 8, fontColor = { tagColor[1], tagColor[2], tagColor[3], 200 },
                        },
                    },
                },
                UI.Label {
                    text = valueText,
                    fontSize = 12, fontColor = { tagColor[1], tagColor[2], tagColor[3], 255 },
                },
                rangeText and rangeText ~= "" and UI.Label {
                    text = rangeText,
                    fontSize = 9, fontColor = { 140, 130, 160, 180 },
                } or nil,
            },
        }
        -- 标签词条描述
        local tagDef = RuneConfig.AFFIX_MAP[tagAffix.id]
        if tagDef and tagDef.desc then
            local dText = tagDef.desc
            if tagDef.tier and Config.FormatAffixDesc then
                dText = Config.FormatAffixDesc(tagDef, tagAffix.value, tagAffix.value2)
            end
            children[#children + 1] = UI.Label {
                text = dText,
                fontSize = 9, fontColor = { 160, 155, 180, 160 },
                paddingLeft = 4,
            }
        end
    end

    return UI.Panel {
        width = "100%",
        paddingTop = 4, paddingBottom = 4,
        paddingLeft = 4, paddingRight = 4,
        borderTopWidth = 1,
        borderColor = { 80, 60, 120, 60 },
        flexDirection = "column",
        gap = 2,
        children = children,
    }
end

--- 创建单个词条行
---@param affix table
---@param quality table
---@param showLockBtn boolean  是否显示锁定按钮
---@param affixIndex number|nil  词条序号(用于锁定操作)
---@param interactive boolean  是否可交互(锁定按钮)
function RuneReforgeUI.CreateAffixRow(affix, quality, showLockBtn, affixIndex, interactive)
    local valueText = RuneData.FormatAffix(affix)
    local isLocked = affix.locked

    local rangeText = RuneData.FormatAffixRange(affix, currentRune and currentRune.qualityId or nil)
    local leftChildren = {}
    if isLocked then
        leftChildren[#leftChildren + 1] = UI.Label {
            text = "🔒", fontSize = 11,
            fontColor = { 40, 200, 160, 255 },
            pointerEvents = "none",
        }
    end
    leftChildren[#leftChildren + 1] = UI.Label {
        text = valueText,
        fontSize = 12,
        fontColor = isLocked and { 40, 200, 160, 255 } or { 220, 210, 240, 255 },
        pointerEvents = "none",
    }
    if rangeText and rangeText ~= "" then
        leftChildren[#leftChildren + 1] = UI.Label {
            text = rangeText,
            fontSize = 9, fontColor = { 140, 130, 160, 180 },
            pointerEvents = "none",
        }
    end

    local rowChildren = {
        UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            flexShrink = 1,
            children = leftChildren,
        },
    }

    -- 锁定按钮（仅当前词条列且可交互时显示）
    if showLockBtn and interactive and affixIndex then
        local canLock = true
        -- 检查锁定上限：最多 N-1 条
        if not isLocked then
            local lockedCount = 0
            for _, a in ipairs(currentRune.affixes) do
                if a.locked then lockedCount = lockedCount + 1 end
            end
            if lockedCount >= #currentRune.affixes - 1 then
                canLock = false
            end
        end

        rowChildren[#rowChildren + 1] = UI.Button {
            text = isLocked and "解锁" or "锁定",
            fontSize = 9, variant = "outline",
            height = 20, paddingLeft = 5, paddingRight = 5,
            opacity = canLock and 1.0 or 0.4,
            onClick = canLock and function(self)
                RuneData.ToggleAffixLock(currentRune, affixIndex)
                previewAffixes = nil  -- 清除旧预览
                RuneReforgeUI.Render()
            end or nil,
        }
    end

    -- 查找词条描述
    local descText = nil
    local def = RuneConfig.AFFIX_MAP[affix.id]
    if def and def.desc then
        descText = def.desc
    end
    -- 标签词条用 FormatAffixDesc 做模板替换
    local Config_ = require("Game.Config")
    if def and def.tier and Config_.FormatAffixDesc then
        descText = Config_.FormatAffixDesc(def, affix.value, affix.value2)
    end

    local wrapChildren = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = rowChildren,
        },
    }
    if descText then
        wrapChildren[#wrapChildren + 1] = UI.Label {
            text = descText,
            fontSize = 9, fontColor = { 160, 155, 180, 160 },
            paddingLeft = isLocked and 18 or 0,
            pointerEvents = "none",
        }
    end

    return UI.Panel {
        width = "100%",
        paddingTop = 2, paddingBottom = 2,
        paddingLeft = 4, paddingRight = 4,
        backgroundColor = isLocked and { 40, 200, 160, 20 } or { 0, 0, 0, 0 },
        borderRadius = 4,
        children = wrapChildren,
    }
end

-- ============================================================================
-- 费用信息
-- ============================================================================

function RuneReforgeUI.CreateCostInfo(lockedCount)
    local costItems = {}
    local isDirected = reforgeMode ~= "basic"
    local hasPreview = previewAffixes ~= nil
    local hasTagPreview = showTagPreview

    -- ── 常规洗练费用 ──
    if not hasTagPreview then
        -- 裂隙之尘
        local dustCost = isDirected and RuneConfig.DIRECTED_COST_DUST or RuneConfig.REFORGE_COST_DUST
        local dustHave = Currency.Get("rift_dust")
        local dustEnough = dustHave >= dustCost
        costItems[#costItems + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            children = {
                Currency.IconWidget(UI, "rift_dust", 14),
                UI.Label {
                    text = "裂隙之尘 " .. dustCost,
                    fontSize = 11,
                    fontColor = dustEnough and { 160, 120, 200, 255 } or { 255, 80, 80, 255 },
                },
                UI.Label {
                    text = "(" .. dustHave .. ")",
                    fontSize = 9, fontColor = { 120, 110, 140, 180 },
                },
            },
        }

        -- 深渊结晶（定向洗练）
        if isDirected then
            local crystalCost = RuneConfig.DIRECTED_COST_CRYSTAL
            local crystalHave = Currency.Get("abyss_crystal")
            local crystalEnough = crystalHave >= crystalCost
            costItems[#costItems + 1] = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "abyss_crystal", 14),
                    UI.Label {
                        text = "深渊结晶 " .. crystalCost,
                        fontSize = 11,
                        fontColor = crystalEnough and { 200, 60, 255, 255 } or { 255, 80, 80, 255 },
                    },
                    UI.Label {
                        text = "(" .. crystalHave .. ")",
                        fontSize = 9, fontColor = { 120, 110, 140, 180 },
                    },
                },
            }
        end

        -- 符文封印（锁定词条）
        if lockedCount > 0 then
            local sealHave = Currency.Get("rune_seal")
            local sealEnough = sealHave >= lockedCount
            costItems[#costItems + 1] = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "rune_seal", 14),
                    UI.Label {
                        text = "符文封印 " .. lockedCount,
                        fontSize = 11,
                        fontColor = sealEnough and { 40, 200, 160, 255 } or { 255, 80, 80, 255 },
                    },
                    UI.Label {
                        text = "(" .. sealHave .. ")",
                        fontSize = 9, fontColor = { 120, 110, 140, 180 },
                    },
                },
            }
        end
    end

    -- ── 标签洗练费用（独立显示） ──
    local tagCostLabel = hasTagPreview and "标签洗练消耗" or "标签洗练"
    local tagDustCost = RuneConfig.TAG_REFORGE_COST_DUST
    local tagCrystalCost = RuneConfig.TAG_REFORGE_COST_CRYSTAL
    local tagDustHave = Currency.Get("rift_dust")
    local tagCrystalHave = Currency.Get("abyss_crystal")

    costItems[#costItems + 1] = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
        paddingTop = (not hasTagPreview and not hasPreview) and 4 or 0,
        borderTopWidth = (not hasTagPreview and not hasPreview) and 1 or 0,
        borderColor = { 80, 60, 120, 60 },
        children = {
            UI.Label {
                text = tagCostLabel,
                fontSize = 10, fontColor = { 200, 120, 255, 180 }, fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            Currency.IconWidget(UI, "rift_dust", 12),
                            UI.Label {
                                text = tagDustCost .. "",
                                fontSize = 10,
                                fontColor = tagDustHave >= tagDustCost and { 160, 120, 200, 255 } or { 255, 80, 80, 255 },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            Currency.IconWidget(UI, "abyss_crystal", 12),
                            UI.Label {
                                text = tagCrystalCost .. "",
                                fontSize = 10,
                                fontColor = tagCrystalHave >= tagCrystalCost and { 200, 60, 255, 255 } or { 255, 80, 80, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 3,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        children = {
            not hasTagPreview and UI.Label {
                text = "消耗",
                fontSize = 11, fontColor = { 150, 140, 180, 200 }, fontWeight = "bold",
            } or nil,
            table.unpack(costItems),
        },
    }
end

-- ============================================================================
-- 操作按钮
-- ============================================================================

function RuneReforgeUI.CreateButtons(rune, lockedCount)
    local hasPreview = previewAffixes ~= nil
    local hasTagPreview = showTagPreview
    local buttons = {}

    if hasPreview then
        -- 常规洗练预览：[保留原来] [接受新词条]
        buttons[#buttons + 1] = UI.Button {
            text = "保留原来",
            fontSize = 13, variant = "outline",
            flex = 1, height = 38,
            onClick = function(self)
                previewAffixes = nil
                RuneReforgeUI.Render()
            end,
        }
        buttons[#buttons + 1] = UI.Button {
            text = "✓ 接受新词条",
            fontSize = 13, variant = "primary",
            flex = 1, height = 38,
            onClick = function(self)
                RuneData.ApplyReforge(rune, previewAffixes)
                previewAffixes = nil
                local Toast = require("Game.Toast")
                Toast.Show("词条已更新", { 100, 255, 100 })
                RuneReforgeUI.Render()
            end,
        }
    elseif hasTagPreview then
        -- 标签洗练预览：[保留原来] [接受标签]
        buttons[#buttons + 1] = UI.Button {
            text = "保留原来",
            fontSize = 13, variant = "outline",
            flex = 1, height = 38,
            onClick = function(self)
                showTagPreview = false
                previewTagAffix = nil
                RuneReforgeUI.Render()
            end,
        }
        buttons[#buttons + 1] = UI.Button {
            text = "✓ 接受标签",
            fontSize = 13, variant = "primary",
            flex = 1, height = 38,
            onClick = function(self)
                RuneData.ApplyTagReforge(rune, previewTagAffix)
                showTagPreview = false
                previewTagAffix = nil
                local Toast = require("Game.Toast")
                Toast.Show("标签词条已更新", { 200, 120, 255 })
                RuneReforgeUI.Render()
            end,
        }
    else
        -- 无预览：[洗练] [标签洗练] [返回]
        local isDirected = reforgeMode ~= "basic"
        local btnText = "洗练"
        if isDirected then
            btnText = reforgeMode == "directed_base" and "定向·基础洗练" or "定向·特殊洗练"
        end

        buttons[#buttons + 1] = UI.Button {
            text = btnText,
            fontSize = 12, variant = "primary",
            flex = 1, height = 38,
            onClick = function(self)
                local ok, msg, preview
                if reforgeMode == "basic" then
                    ok, msg, preview = RuneData.Reforge(rune)
                else
                    local category = reforgeMode == "directed_base" and "base" or "special"
                    ok, msg, preview = RuneData.DirectedReforge(rune, category)
                end

                local Toast = require("Game.Toast")
                if ok and preview then
                    previewAffixes = preview.affixes
                    RuneReforgeUI.Render()
                else
                    Toast.Show(msg or "洗练失败", { 255, 100, 80 })
                end
            end,
        }

        -- 标签洗练按钮
        buttons[#buttons + 1] = UI.Button {
            text = "标签洗练",
            fontSize = 12, variant = "outline",
            flex = 1, height = 38,
            onClick = function(self)
                local ok, msg, preview = RuneData.TagReforge(rune)
                local Toast = require("Game.Toast")
                if ok and preview then
                    previewTagAffix = preview.tagAffix
                    showTagPreview = true
                    RuneReforgeUI.Render()
                else
                    Toast.Show(msg or "标签洗练失败", { 255, 100, 80 })
                end
            end,
        }

        -- 关闭按钮
        buttons[#buttons + 1] = UI.Button {
            text = "返回",
            fontSize = 12, variant = "outline",
            width = 60, height = 38,
            onClick = function(self)
                RuneReforgeUI.Close()
            end,
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        paddingTop = 4,
        flexShrink = 0,
        children = buttons,
    }
end

-- ============================================================================
-- 词条说明弹窗
-- ============================================================================

function RuneReforgeUI.ShowAffixHelpPopup()
    if not overlayRoot then return end

    -- 颜色常量
    local C = {
        title     = { 220, 200, 255, 255 },
        subtitle  = { 180, 160, 220, 255 },
        body      = { 160, 150, 190, 230 },
        dim       = { 130, 120, 160, 180 },
        divider   = { 80, 60, 120, 100 },
        base      = { 100, 180, 255 },
        special   = { 255, 160, 80 },
        t1        = Config.AFFIX_TIER_COLORS[1],
        t2        = Config.AFFIX_TIER_COLORS[2],
        t3        = Config.AFFIX_TIER_COLORS[3],
    }

    -- ── 辅助：创建一个词条说明行 ──
    local function AffixLine(name, desc, color)
        return UI.Panel {
            width = "100%", flexDirection = "row", gap = 4,
            alignItems = "flex-start",
            paddingTop = 1, paddingBottom = 1,
            children = {
                UI.Panel {
                    paddingLeft = 4, paddingRight = 4,
                    paddingTop = 1, paddingBottom = 1,
                    backgroundColor = { color[1], color[2], color[3], 50 },
                    borderRadius = 3,
                    borderWidth = 1,
                    borderColor = { color[1], color[2], color[3], 80 },
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = name, fontSize = 9,
                            fontColor = { color[1], color[2], color[3], 220 },
                        },
                    },
                },
                UI.Label {
                    text = desc, fontSize = 9,
                    fontColor = C.dim, flexShrink = 1,
                },
            },
        }
    end

    -- ── 辅助：分隔线 ──
    local function Divider()
        return UI.Panel {
            width = "100%", height = 1,
            backgroundColor = C.divider, marginTop = 4, marginBottom = 4,
            flexShrink = 0,
        }
    end

    -- ── 辅助：带颜色圆点的小标题 ──
    local function SectionTitle(text, color)
        return UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", gap = 5,
            marginTop = 2,
            children = {
                UI.Panel {
                    width = 6, height = 6, borderRadius = 3,
                    backgroundColor = { color[1], color[2], color[3], 220 },
                },
                UI.Label {
                    text = text, fontSize = 11, fontWeight = "bold",
                    fontColor = { color[1], color[2], color[3], 240 },
                },
            },
        }
    end

    -- ════════════════════════════════════════════
    -- 构建内容
    -- ════════════════════════════════════════════
    local content = {}

    -- ── 总览 ──
    content[#content + 1] = UI.Label {
        text = "符文词条系统",
        fontSize = 16, fontWeight = "bold", fontColor = C.title,
    }
    content[#content + 1] = UI.Label {
        text = "符文最多携带4条词条，分为基础属性、特殊效果、标签词条三大类。洗练可重随未锁定词条，定向洗练可限定词条池。",
        fontSize = 10, fontColor = C.body,
    }

    content[#content + 1] = Divider()

    -- ── 基础属性池 ──
    content[#content + 1] = SectionTitle("基础属性池（" .. #RuneConfig.AFFIX_BASE .. "种）", C.base)
    content[#content + 1] = UI.Label {
        text = "通用属性加成，对所有英雄生效。",
        fontSize = 9, fontColor = C.dim,
    }
    for _, def in ipairs(RuneConfig.AFFIX_BASE) do
        local range = ""
        if def.unit == "%" then
            range = math.floor(def.minVal * 100 + 0.5) .. "%-" .. math.floor(def.maxVal * 100 + 0.5) .. "%"
        else
            range = def.minVal .. "-" .. def.maxVal
        end
        local lineDesc = range
        if def.desc then
            lineDesc = range .. "  " .. def.desc
        end
        content[#content + 1] = AffixLine(def.name, lineDesc, C.base)
    end

    content[#content + 1] = Divider()

    -- ── 特殊效果池 ──
    content[#content + 1] = SectionTitle("特殊效果池（" .. #RuneConfig.AFFIX_SPECIAL .. "种）", C.special)
    content[#content + 1] = UI.Label {
        text = "特殊机制加成，提供连锁、减速、DOT等独特效果。",
        fontSize = 9, fontColor = C.dim,
    }
    for _, def in ipairs(RuneConfig.AFFIX_SPECIAL) do
        local range = ""
        if def.unit == "%" then
            range = math.floor(def.minVal * 100 + 0.5) .. "%-" .. math.floor(def.maxVal * 100 + 0.5) .. "%"
        else
            range = def.minVal .. "-" .. def.maxVal
        end
        local lineDesc = range
        if def.desc then
            lineDesc = range .. "  " .. def.desc
        end
        content[#content + 1] = AffixLine(def.name, lineDesc, C.special)
    end

    content[#content + 1] = Divider()

    -- ── 标签词条（三层体系）──
    content[#content + 1] = UI.Label {
        text = "标签词条（三层体系）",
        fontSize = 13, fontWeight = "bold", fontColor = { 200, 120, 255, 255 },
    }
    content[#content + 1] = UI.Label {
        text = "条件词条：只对符合条件的英雄/技能生效，匹配时效果强于基础词条。符文专属定向·特殊洗练池可出。",
        fontSize = 9, fontColor = C.body,
    }

    -- T1
    content[#content + 1] = SectionTitle(
        "T1 角色类别（" .. #Config.AFFIX_TAG_SYSTEM.role_affixes .. "种）", C.t1
    )
    content[#content + 1] = UI.Label {
        text = "按英雄职业匹配，每条覆盖同职业的所有英雄。出现率较高。",
        fontSize = 9, fontColor = C.dim,
    }
    for _, def in ipairs(Config.AFFIX_TAG_SYSTEM.role_affixes) do
        local desc = def.desc:gsub("{v}", math.floor(def.minVal * 100 + 0.5) .. "-" .. math.floor(def.maxVal * 100 + 0.5))
        content[#content + 1] = AffixLine(def.name, desc, C.t1)
    end

    -- T2
    content[#content + 1] = SectionTitle(
        "T2 技能类型（" .. #Config.AFFIX_TAG_SYSTEM.skilltype_affixes .. "种）", C.t2
    )
    content[#content + 1] = UI.Label {
        text = "按技能触发方式匹配（命中/暴击/主动/光环/被动）。出现率较低。",
        fontSize = 9, fontColor = C.dim,
    }
    for _, def in ipairs(Config.AFFIX_TAG_SYSTEM.skilltype_affixes) do
        local desc = def.desc:gsub("{v}", math.floor(def.minVal * 100 + 0.5) .. "-" .. math.floor(def.maxVal * 100 + 0.5))
        if def.stat2 then
            desc = desc:gsub("{v2}", math.floor((def.minVal2 or 0) * 100 + 0.5) .. "-" .. math.floor((def.maxVal2 or 0) * 100 + 0.5))
        end
        content[#content + 1] = AffixLine(def.name, desc, C.t2)
    end

    -- T3
    content[#content + 1] = SectionTitle(
        "T3 效果类别（" .. #Config.AFFIX_TAG_SYSTEM.tag_affixes .. "种）", C.t3
    )
    content[#content + 1] = UI.Label {
        text = "按技能效果类别匹配（持续伤害/爆发/控制等），每条覆盖多个英雄。最稀有的毕业词条。",
        fontSize = 9, fontColor = C.dim,
    }
    for _, def in ipairs(Config.AFFIX_TAG_SYSTEM.tag_affixes) do
        local desc = def.desc:gsub("{v}", math.floor(def.minVal * 100 + 0.5) .. "-" .. math.floor(def.maxVal * 100 + 0.5))
        if def.stat2 then
            if def.stat2:find("Dur") or def.stat2:find("dur") then
                desc = desc:gsub("{v2}", string.format("%.1f-%.1f", def.minVal2 or 0, def.maxVal2 or 0))
            else
                desc = desc:gsub("{v2}", math.floor((def.minVal2 or 0) * 100 + 0.5) .. "-" .. math.floor((def.maxVal2 or 0) * 100 + 0.5))
            end
        end
        content[#content + 1] = AffixLine(def.name, desc, C.t3)
    end

    content[#content + 1] = Divider()

    -- ── 洗练模式说明 ──
    content[#content + 1] = UI.Label {
        text = "洗练模式",
        fontSize = 13, fontWeight = "bold", fontColor = C.title,
    }

    local modeDescs = {
        { name = "基础洗练",   desc = "从全部词条池随机重随，费用最低",      color = C.body },
        { name = "定向·基础",  desc = "仅从基础属性池重随，追求纯属性流",    color = C.base },
        { name = "定向·特殊",  desc = "仅从特殊效果池重随，追求机制词条", color = C.special },
    }
    for _, m in ipairs(modeDescs) do
        content[#content + 1] = UI.Panel {
            width = "100%", flexDirection = "row", gap = 4, alignItems = "center",
            children = {
                UI.Panel {
                    width = 4, height = 4, borderRadius = 2,
                    backgroundColor = { m.color[1], m.color[2], m.color[3], 200 },
                },
                UI.Label {
                    text = m.name, fontSize = 10, fontWeight = "bold",
                    fontColor = { m.color[1], m.color[2], m.color[3], 240 },
                },
                UI.Label {
                    text = m.desc, fontSize = 9, fontColor = C.dim, flexShrink = 1,
                },
            },
        }
    end

    content[#content + 1] = Divider()

    -- ── 标签洗练说明 ──
    content[#content + 1] = UI.Label {
        text = "标签洗练（独立系统）",
        fontSize = 13, fontWeight = "bold", fontColor = { 200, 120, 255, 255 },
    }
    content[#content + 1] = UI.Label {
        text = "标签词条与基础/特殊词条完全独立，每个符文最多拥有1条标签词条。",
        fontSize = 10, fontColor = C.body,
    }
    content[#content + 1] = UI.Label {
        text = "标签洗练不影响已有的基础/特殊词条，可随时单独进行。",
        fontSize = 10, fontColor = C.body,
    }
    content[#content + 1] = UI.Panel {
        width = "100%", flexDirection = "row", gap = 4, alignItems = "center",
        children = {
            Currency.IconWidget(UI, "rift_dust", 12),
            UI.Label {
                text = "费用：裂隙之尘 " .. RuneConfig.TAG_REFORGE_COST_DUST .. " + 深渊结晶 " .. RuneConfig.TAG_REFORGE_COST_CRYSTAL,
                fontSize = 10, fontColor = { 200, 120, 255, 200 },
            },
        },
    }

    content[#content + 1] = Divider()

    -- ── 锁定说明 ──
    content[#content + 1] = UI.Label {
        text = "词条锁定",
        fontSize = 13, fontWeight = "bold", fontColor = C.title,
    }
    content[#content + 1] = UI.Label {
        text = "锁定的词条在洗练时保留不变，每次消耗1枚符文封印。最多锁定N-1条（至少1条参与重随）。标签词条独立洗练，不受锁定影响。",
        fontSize = 10, fontColor = C.body,
    }

    -- ════════════════════════════════════════════
    -- 弹窗容器
    -- ════════════════════════════════════════════
    local popup = UI.Panel {
        id = "affixHelpOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 80,
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self)
            if overlayRoot and overlayRoot.helpPopup_ then
                overlayRoot:RemoveChild(overlayRoot.helpPopup_)
                overlayRoot.helpPopup_ = nil
            end
        end,
        children = {
            UI.Panel {
                width = "88%",
                maxHeight = "85%",
                backgroundColor = { 28, 20, 42, 252 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 140, 90, 220, 200 },
                flexDirection = "column",
                paddingTop = 14, paddingBottom = 14,
                paddingLeft = 14, paddingRight = 14,
                gap = 4,
                pointerEvents = "auto",
                onClick = function(self) end, -- 阻止穿透
                overflow = "scroll",
                children = {
                    -- 标题行
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 4, flexShrink = 0,
                        children = {
                            UI.Label {
                                text = "词条说明",
                                fontSize = 16, fontWeight = "bold", fontColor = C.title,
                            },
                            UI.Button {
                                text = "✕", fontSize = 14, variant = "ghost",
                                width = 28, height = 28,
                                onClick = function(self)
                                    if overlayRoot and overlayRoot.helpPopup_ then
                                        overlayRoot:RemoveChild(overlayRoot.helpPopup_)
                                        overlayRoot.helpPopup_ = nil
                                    end
                                end,
                            },
                        },
                    },
                    table.unpack(content),
                },
            },
        },
    }

    -- 移除旧弹窗（如果有）
    if overlayRoot.helpPopup_ then
        overlayRoot:RemoveChild(overlayRoot.helpPopup_)
    end
    overlayRoot:AddChild(popup)
    overlayRoot.helpPopup_ = popup
end

return RuneReforgeUI
