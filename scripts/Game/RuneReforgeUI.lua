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
local previewAffixes = nil  -- 洗练预览结果
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
    local bestStage = HeroData.stats.bestGlobalWave or 0
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
                        text = "定向洗练需通关第" .. RuneConfig.DIRECTED_UNLOCK_STAGE .. "波解锁",
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

    -- 构建词条标签
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
                text = "重随范围：" .. poolLabel .. "（" .. #pool .. "种）",
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

    if hasPreview then
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            paddingTop = 6, paddingBottom = 6,
            flexShrink = 0,
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
        return UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 3,
            paddingTop = 6, paddingBottom = 6,
            flexShrink = 0,
            children = {
                UI.Label {
                    text = "当前词条（点击🔒锁定保留）",
                    fontSize = 11, fontColor = { 150, 140, 180, 200 },
                },
                table.unpack(currentItems),
            },
        }
    end
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

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingTop = 2, paddingBottom = 2,
        paddingLeft = 4, paddingRight = 4,
        backgroundColor = isLocked and { 40, 200, 160, 20 } or { 0, 0, 0, 0 },
        borderRadius = 4,
        children = rowChildren,
    }
end

-- ============================================================================
-- 费用信息
-- ============================================================================

function RuneReforgeUI.CreateCostInfo(lockedCount)
    local costItems = {}
    local isDirected = reforgeMode ~= "basic"

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

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 3,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "消耗",
                fontSize = 11, fontColor = { 150, 140, 180, 200 }, fontWeight = "bold",
            },
            table.unpack(costItems),
        },
    }
end

-- ============================================================================
-- 操作按钮
-- ============================================================================

function RuneReforgeUI.CreateButtons(rune, lockedCount)
    local hasPreview = previewAffixes ~= nil
    local buttons = {}

    if hasPreview then
        -- 有预览：[保留原来] [接受新词条]
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
    else
        -- 无预览：[洗练]
        local isDirected = reforgeMode ~= "basic"
        local btnText = "洗练"
        if isDirected then
            btnText = reforgeMode == "directed_base" and "定向·基础洗练" or "定向·特殊洗练"
        end

        buttons[#buttons + 1] = UI.Button {
            text = btnText,
            fontSize = 13, variant = "primary",
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

        -- 关闭按钮
        buttons[#buttons + 1] = UI.Button {
            text = "返回",
            fontSize = 13, variant = "outline",
            width = 70, height = 38,
            onClick = function(self)
                RuneReforgeUI.Close()
            end,
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        paddingTop = 4,
        flexShrink = 0,
        children = buttons,
    }
end

return RuneReforgeUI
