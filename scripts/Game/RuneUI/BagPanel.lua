-- RuneUI/BagPanel.lua
-- 符文背包网格面板

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")

local S = require("Game.RuneUI.State")
local RuneCell = require("Game.RuneUI.RuneCell")

local M = {}

---@param onSelect function    (rune, source, heroId, slotIdx) 点击符文
---@param onSort function      整理回调
---@param onExpandBag function 扩容回调
---@param onBatchDecompose function 批量分解回调
function M.Build(onSelect, onSort, onExpandBag, onBatchDecompose)
    local UI = S.UI
    local bag = RuneData.GetBag()
    local cur, cap = RuneData.GetBagCapacity()

    local COLS = 5
    local CELL_GAP = 4

    -- ── 收集所有符文（先已装备、再背包）──
    local allCells = {}

    local heroNameCache = {}
    for _, td in ipairs(Config.TOWER_TYPES) do
        heroNameCache[td.id] = td.name
    end

    -- 收集所有已解锁英雄的已装备符文
    local deployedSet = {}
    for _, hid in ipairs(HeroData.deployed) do
        deployedSet[hid] = true
    end

    local orderedHeroes = {}
    for _, hid in ipairs(HeroData.deployed) do
        orderedHeroes[#orderedHeroes + 1] = hid
    end
    for _, hid in ipairs(HeroData.GetUnlockedList()) do
        if not deployedSet[hid] then
            orderedHeroes[#orderedHeroes + 1] = hid
        end
    end

    for _, heroId in ipairs(orderedHeroes) do
        local equipped = RuneData.GetEquipped(heroId)
        local hName = heroNameCache[heroId] or heroId
        for slotIdx = 1, RuneConfig.MAX_SLOTS do
            local rune = equipped[slotIdx]
            if rune then
                allCells[#allCells + 1] = RuneCell.Create(rune, {
                    source = "equipped",
                    heroId = heroId,
                    slotIdx = slotIdx,
                    heroName = hName,
                }, onSelect)
            end
        end
    end

    for _, rune in ipairs(bag) do
        allCells[#allCells + 1] = RuneCell.Create(rune, { source = "bag" }, onSelect)
    end

    -- ── 填充空格子到背包容量上限 ──
    local emptySlots = cap - #bag
    for _ = 1, emptySlots do
        allCells[#allCells + 1] = UI.Panel {
            flexGrow = 1, flexShrink = 1, flexBasis = 0,
            aspectRatio = 1,
            backgroundColor = { 40, 32, 60, 120 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { 80, 65, 110, 100 },
        }
    end

    -- ── 按 COLS 列分行 ──
    local rowWidgets = {}
    for i = 1, #allCells, COLS do
        local slots = {}
        for c = 1, COLS do
            local cell = allCells[i + c - 1]
            if cell then
                slots[#slots + 1] = cell
            else
                slots[#slots + 1] = UI.Panel {
                    flexGrow = 1, flexShrink = 1, flexBasis = 0,
                    aspectRatio = 1,
                }
            end
        end
        rowWidgets[#rowWidgets + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "stretch",
            gap = CELL_GAP,
            children = slots,
        }
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        flexDirection = "column",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4,
        children = {
            -- 标题行（固定不滚动）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingBottom = 4,
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = "符文背包 (" .. cur .. "/" .. cap .. ")",
                        fontSize = 13, fontColor = {180,170,200,220},
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 6,
                        children = (function()
                            local btns = {}
                            if cap < RuneConfig.BAG_MAX_CAPACITY then
                                btns[#btns + 1] = UI.Button {
                                    text = "扩容",
                                    fontSize = 10, variant = "outline",
                                    height = 26, paddingLeft = 8, paddingRight = 8,
                                    onClick = function(self)
                                        if onExpandBag then onExpandBag() end
                                    end,
                                }
                            end
                            btns[#btns + 1] = UI.Button {
                                text = "整理",
                                fontSize = 10, variant = "outline",
                                height = 26, paddingLeft = 8, paddingRight = 8,
                                onClick = function(self)
                                    if onSort then onSort() end
                                end,
                            }
                            btns[#btns + 1] = UI.Button {
                                text = "批量分解",
                                fontSize = 10, variant = "outline",
                                height = 26, paddingLeft = 8, paddingRight = 8,
                                onClick = function(self)
                                    if onBatchDecompose then onBatchDecompose() end
                                end,
                            }
                            return btns
                        end)(),
                    },
                },
            },
            -- 网格容器（可滚动，记忆滚动位置）
            UI.ScrollView {
                id = "rune_bag_scroll",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                flexBasis = 0,
                scrollY = true,
                onScroll = function(self, sx, sy)
                    S.bagScrollY = sy
                end,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = CELL_GAP,
                        children = rowWidgets,
                    },
                },
            },
        },
    }
end

return M
