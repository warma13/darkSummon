-- RuneUI/RuneCell.lua
-- 符文格子渲染器（已装备和背包共用）

local RuneData = require("Game.RuneData")
local S = require("Game.RuneUI.State")

local M = {}

--- 创建一个符文格子 UI
---@param rune table         符文数据
---@param opts table|nil     { source, heroId, slotIdx, heroName }
---@param onSelect function  点击回调 (rune, source, heroId, slotIdx)
---@return any  Panel widget
function M.Create(rune, opts, onSelect)
    opts = opts or {}
    local UI = S.UI
    local source = opts.source or "bag"
    local series = RuneData.GetSeries(rune.seriesId)
    local quality = RuneData.GetQuality(rune.qualityId)
    local isSelected = (S.selectedRune and S.selectedRune.runeId == rune.runeId)
    local isLocked = rune.locked == true
    local isEquipped = (source == "equipped")

    local cellChildren = {
        -- 符文图标铺满格子
        (series and series.icon) and UI.Panel {
            width = "100%", flexGrow = 1,
            backgroundImage = series.icon, backgroundFit = "cover",
            borderRadius = 6,
            pointerEvents = "none",
        } or UI.Panel {
            width = "100%", flexGrow = 1,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "none",
            children = {
                UI.Label { text = series and series.emoji or "🔮", fontSize = 24, pointerEvents = "none" },
            },
        },
        -- 底部品质名
        UI.Panel {
            width = "100%", height = 14, flexShrink = 0,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { quality.color[1], quality.color[2], quality.color[3], 180 },
            borderBottomLeftRadius = 5, borderBottomRightRadius = 5,
            pointerEvents = "none",
            children = {
                UI.Label {
                    text = quality.name, fontSize = 8, fontWeight = "bold",
                    fontColor = {255,255,255,255}, pointerEvents = "none",
                },
            },
        },
    }

    -- 锁定标记（左上角）
    if isLocked then
        cellChildren[#cellChildren + 1] = UI.Panel {
            position = "absolute", top = 2, left = 2,
            width = 16, height = 16,
            backgroundColor = {0, 0, 0, 160},
            borderRadius = 8,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "none",
            children = {
                UI.Label { text = "🔒", fontSize = 9, pointerEvents = "none" },
            },
        }
    end

    -- 已装备标记：右上角显示英雄名
    if isEquipped and opts.heroName then
        cellChildren[#cellChildren + 1] = UI.Panel {
            position = "absolute", top = 1, right = 1,
            paddingLeft = 3, paddingRight = 3,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = {0, 0, 0, 180},
            borderRadius = 3,
            pointerEvents = "none",
            children = {
                UI.Label {
                    text = opts.heroName,
                    fontSize = 7, fontColor = {120, 220, 255, 255},
                    pointerEvents = "none",
                },
            },
        }
    end

    return UI.Panel {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        aspectRatio = 1,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { quality.color[1], quality.color[2], quality.color[3], isEquipped and 20 or 35 },
        borderRadius = 6,
        borderWidth = isSelected and 2 or 1,
        borderColor = isSelected and {255,200,80,255} or {quality.color[1], quality.color[2], quality.color[3], isEquipped and 100 or 180},
        opacity = isEquipped and 0.75 or 1.0,
        pointerEvents = "auto",
        onClick = function(self)
            if onSelect then
                onSelect(rune, source, opts.heroId, opts.slotIdx)
            end
        end,
        children = cellChildren,
    }
end

return M
