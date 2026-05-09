-- Game/DungeonUI/Collectible.lua
-- 武器收集面板 — DungeonUI 子模块
-- 展示 37 种武器的收集进度与加成详情，按 10 个能力类别分组

local CollectibleData = require("Game.CollectibleData")

local Collectible = {}

-- 当前选中的能力类别索引（1-based，默认第一个）
local selectedCatIdx = 1

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 格式化加成值
---@param value number
---@param format string  "pct" | "flat"
---@return string
local function FormatBonus(value, format)
    if format == "pct" then
        return string.format("+%.1f%%", value * 100)
    else
        return string.format("+%d", value)
    end
end

--- 混合两种颜色（用于已收集/未收集状态区分）
---@param c number[]
---@param alpha number
---@return number[]
local function WithAlpha(c, alpha)
    return { c[1], c[2], c[3], alpha }
end

-- ============================================================================
-- 详情视图：武器收集面板
-- ============================================================================

function Collectible.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    -- ── 顶部标题栏 ──────────────────────────────────────────
    local totalCount, totalTypes = CollectibleData.GetTotalStats()
    local uniqueStats = CollectibleData.GetUniqueStatCount()

    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "武器收集",
                fontSize = 20,
                fontWeight = "bold",
                fontColor = S.white,
                pointerEvents = "none",
            },
        },
    })

    -- ── 概览统计条 ──────────────────────────────────────────
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-around",
        alignItems = "center",
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 25, 20, 40, 220 },
        flexShrink = 0,
        children = {
            -- 已收集种类
            UI.Panel {
                alignItems = "center", gap = 2,
                children = {
                    UI.Label {
                        text = totalTypes .. "/" .. #CollectibleData.ITEM_DEFS,
                        fontSize = 16, fontWeight = "bold",
                        fontColor = totalTypes > 0 and S.gold or S.dim,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "已收集",
                        fontSize = 10, fontColor = S.dim,
                        pointerEvents = "none",
                    },
                },
            },
            -- 总数量
            UI.Panel {
                alignItems = "center", gap = 2,
                children = {
                    UI.Label {
                        text = tostring(totalCount),
                        fontSize = 16, fontWeight = "bold",
                        fontColor = totalCount > 0 and S.green or S.dim,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "总数量",
                        fontSize = 10, fontColor = S.dim,
                        pointerEvents = "none",
                    },
                },
            },
            -- 加成类型
            UI.Panel {
                alignItems = "center", gap = 2,
                children = {
                    UI.Label {
                        text = tostring(uniqueStats),
                        fontSize = 16, fontWeight = "bold",
                        fontColor = S.purple,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "种加成",
                        fontSize = 10, fontColor = S.dim,
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    -- ── 能力类别横向标签栏 ──────────────────────────────────
    local catTabs = {}
    for i, cat in ipairs(CollectibleData.CATEGORIES) do
        local isSelected = (i == selectedCatIdx)
        local catColor = cat.color
        catTabs[#catTabs + 1] = UI.Panel {
            paddingLeft = 8, paddingRight = 8,
            paddingTop = 5, paddingBottom = 5,
            borderRadius = 6,
            borderWidth = isSelected and 1 or 0,
            borderColor = isSelected and { catColor[1], catColor[2], catColor[3], 200 } or nil,
            backgroundColor = isSelected
                and { catColor[1], catColor[2], catColor[3], 60 }
                or { 40, 32, 60, 150 },
            pointerEvents = "auto",
            onClick = function(self)
                selectedCatIdx = i
                ctx.SetView("collectible_detail")
            end,
            children = {
                UI.Label {
                    text = cat.emoji .. " " .. cat.label,
                    fontSize = 11,
                    fontColor = isSelected
                        and { catColor[1], catColor[2], catColor[3], 255 }
                        or S.dim,
                    fontWeight = isSelected and "bold" or "normal",
                    pointerEvents = "none",
                },
            },
        }
    end

    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexShrink = 0,
        children = {
            UI.ScrollView {
                width = "100%",
                height = 40,
                scrollDirection = "horizontal",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        paddingLeft = 12, paddingRight = 12,
                        alignItems = "center",
                        height = "100%",
                        children = catTabs,
                    },
                },
            },
        },
    })

    -- ── 当前类别的武器列表 ──────────────────────────────────
    local currentCat = CollectibleData.CATEGORIES[selectedCatIdx]
    local items = CollectibleData.CATEGORY_ITEMS[currentCat.key] or {}
    local data = CollectibleData.GetData()
    local catColor = currentCat.color

    local itemCards = {}
    for _, def in ipairs(items) do
        local count = data[def.id] or 0
        local st = CollectibleData.STAT_TYPE_MAP[def.statKey]
        local bonus = count * def.perItem
        local hasAny = count > 0

        local bonusText = st and FormatBonus(bonus, st.format) or "+0"
        local bonusDesc = st and st.label or ""

        itemCards[#itemCards + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 8, paddingBottom = 8,
            gap = 10,
            backgroundColor = hasAny and { 35, 28, 55, 240 } or { 25, 20, 38, 180 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = hasAny
                and { def.color[1], def.color[2], def.color[3], 100 }
                or { 50, 42, 65, 60 },
            children = {
                -- 左侧：emoji 图标
                UI.Panel {
                    width = 40, height = 40,
                    justifyContent = "center",
                    alignItems = "center",
                    borderRadius = 8,
                    backgroundColor = hasAny
                        and { def.color[1], def.color[2], def.color[3], 50 }
                        or { 40, 35, 55, 100 },
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = def.emoji,
                            fontSize = 20,
                            pointerEvents = "none",
                        },
                    },
                },
                -- 中间：名称 + 描述 + 加成效果
                UI.Panel {
                    flex = 1,
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        -- 名称行
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                UI.Label {
                                    text = def.name,
                                    fontSize = 14,
                                    fontWeight = "bold",
                                    fontColor = hasAny
                                        and { def.color[1], def.color[2], def.color[3], 255 }
                                        or S.dim,
                                    pointerEvents = "none",
                                },
                                -- 加成标签
                                UI.Panel {
                                    paddingLeft = 4, paddingRight = 4,
                                    paddingTop = 1, paddingBottom = 1,
                                    borderRadius = 4,
                                    backgroundColor = { catColor[1], catColor[2], catColor[3], 40 },
                                    children = {
                                        UI.Label {
                                            text = bonusDesc,
                                            fontSize = 9,
                                            fontColor = { catColor[1], catColor[2], catColor[3], 200 },
                                            pointerEvents = "none",
                                        },
                                    },
                                },
                            },
                        },
                        -- 道具描述
                        UI.Label {
                            text = def.desc,
                            fontSize = 10,
                            fontColor = { 140, 130, 160, 180 },
                            pointerEvents = "none",
                        },
                        -- 加成效果
                        hasAny and UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 4,
                            children = {
                                UI.Label {
                                    text = bonusText,
                                    fontSize = 12,
                                    fontWeight = "bold",
                                    fontColor = S.green,
                                    pointerEvents = "none",
                                },
                                UI.Label {
                                    text = "(" .. st.desc .. ")",
                                    fontSize = 10,
                                    fontColor = S.dim,
                                    pointerEvents = "none",
                                },
                            },
                        } or UI.Label {
                            text = "每件 " .. FormatBonus(def.perItem, st and st.format or "pct"),
                            fontSize = 10,
                            fontColor = { 100, 90, 120, 150 },
                            pointerEvents = "none",
                        },
                    },
                },
                -- 右侧：数量
                UI.Panel {
                    width = 48,
                    alignItems = "center",
                    justifyContent = "center",
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = tostring(count),
                            fontSize = 18,
                            fontWeight = "bold",
                            fontColor = hasAny and S.gold or { 60, 50, 80, 150 },
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = "件",
                            fontSize = 10,
                            fontColor = S.dim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    -- 如果该类别为空
    if #itemCards == 0 then
        itemCards[#itemCards + 1] = UI.Panel {
            width = "100%",
            height = 100,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "该类别暂无武器",
                    fontSize = 14,
                    fontColor = S.dim,
                    pointerEvents = "none",
                },
            },
        }
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingTop = 8, paddingBottom = 8,
                paddingLeft = 12, paddingRight = 12,
                gap = 6,
                children = itemCards,
            },
        },
    })

    -- ── 底部：加成汇总 + 返回按钮 ────────────────────────
    -- 加成汇总面板
    local bonusMap = CollectibleData.GetBonusMap()
    local summaryItems = {}
    -- 只展示有值的加成
    for _, st in ipairs(CollectibleData.STAT_TYPES) do
        local val = bonusMap[st.key]
        if val and val > 0 then
            summaryItems[#summaryItems + 1] = UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                paddingLeft = 6, paddingRight = 6,
                paddingTop = 2, paddingBottom = 2,
                borderRadius = 4,
                backgroundColor = { 50, 40, 70, 120 },
                children = {
                    UI.Label {
                        text = st.label,
                        fontSize = 10,
                        fontColor = S.dim,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = FormatBonus(val, st.format),
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = S.green,
                        pointerEvents = "none",
                    },
                },
            }
        end
    end

    if #summaryItems > 0 then
        pageRoot:AddChild(UI.Panel {
            width = "100%",
            flexShrink = 0,
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 6, paddingBottom = 4,
            backgroundColor = { 20, 16, 32, 220 },
            borderTopWidth = 1,
            borderColor = { 70, 55, 100, 80 },
            children = {
                UI.Label {
                    text = "加成汇总",
                    fontSize = 11,
                    fontWeight = "bold",
                    fontColor = S.gold,
                    pointerEvents = "none",
                    marginBottom = 4,
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 4,
                    children = summaryItems,
                },
            },
        })
    end

    -- 返回按钮
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        flexShrink = 0,
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6, paddingBottom = 10,
        children = {
            UI.Button {
                text = "返回",
                fontSize = 16,
                width = "100%",
                height = 44,
                borderRadius = 8,
                variant = "outline",
                onClick = function()
                    ctx.SetView("list")
                end,
            },
        },
    })
end

return Collectible
