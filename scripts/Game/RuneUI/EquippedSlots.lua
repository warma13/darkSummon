-- RuneUI/EquippedSlots.lua
-- 已装备符文槽位区

local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")

local S = require("Game.RuneUI.State")
local RuneCell = require("Game.RuneUI.RuneCell")

local M = {}

---@param onSelect function  (rune, source, heroId, slotIdx)
---@param onSlotClick function  (slotIdx) 点击空槽
function M.Build(onSelect, onSlotClick)
    local UI = S.UI
    local equipped = RuneData.GetEquipped(S.selectedHero)

    local COLS = 5
    local CELL_GAP = 4

    local cells = {}

    for i = 1, RuneConfig.MAX_SLOTS do
        local slotDef = RuneConfig.SLOT_DEFS[i]
        local rune = equipped[i]
        local unlocked = RuneData.IsSlotUnlocked(i)

        if rune then
            cells[#cells + 1] = RuneCell.Create(rune, {
                source = "equipped",
                heroId = S.selectedHero,
                slotIdx = i,
            }, onSelect)
        else
            local isHighlight = (S.selectedSlotIdx == i and S.selectedSource == "equipped")
            local children = {}
            if not unlocked then
                children = {
                    UI.Label { text = "🔒", fontSize = 20, pointerEvents = "none" },
                    UI.Label {
                        text = "第" .. slotDef.unlockStage .. "关",
                        fontSize = 8, fontColor = {120,110,140,180}, pointerEvents = "none",
                    },
                }
            else
                children = {
                    UI.Label { text = "＋", fontSize = 20, fontColor = {100,90,130,200}, pointerEvents = "none" },
                    UI.Label {
                        text = slotDef.name,
                        fontSize = 8, fontColor = {100,90,130,150}, pointerEvents = "none",
                    },
                }
            end

            cells[#cells + 1] = UI.Panel {
                flexGrow = 1, flexShrink = 1, flexBasis = 0,
                aspectRatio = 1,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = {20,18,35,180},
                borderRadius = 6,
                borderWidth = isHighlight and 2 or 1,
                borderColor = isHighlight and {255,200,80,255} or {50,45,70,200},
                gap = 2,
                pointerEvents = unlocked and "auto" or "none",
                onClick = unlocked and function(self)
                    if onSlotClick then onSlotClick(i) end
                end or nil,
                children = children,
            }
        end
    end

    -- 填充空白占位到满一行
    local remainder = #cells % COLS
    if remainder > 0 then
        for _ = 1, COLS - remainder do
            cells[#cells + 1] = UI.Panel {
                flexGrow = 1, flexShrink = 1, flexBasis = 0,
                aspectRatio = 1,
            }
        end
    end

    -- 按 COLS 列分行
    local rowWidgets = {}
    for i = 1, #cells, COLS do
        local rowSlots = {}
        for c = 1, COLS do
            local cell = cells[i + c - 1]
            if cell then
                rowSlots[#rowSlots + 1] = cell
            end
        end
        rowWidgets[#rowWidgets + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "stretch",
            gap = CELL_GAP,
            children = rowSlots,
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        flexDirection = "column",
        gap = CELL_GAP,
        children = {
            UI.Panel {
                width = "100%",
                paddingBottom = 2,
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = "已装备符文",
                        fontSize = 12, fontColor = {180,170,200,200},
                    },
                },
            },
            table.unpack(rowWidgets),
        },
    }
end

return M
