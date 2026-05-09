-- RuneUI/Sections.lua
-- 静态/轻量 section: Header, BottomBar, HeroSelector, SetBonusBar

local HeroData = require("Game.HeroData")
local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")
local Currency = require("Game.Currency")
local HeroAvatar = require("Game.HeroAvatar")

local S = require("Game.RuneUI.State")

local M = {}

-- ============================================================================
-- Header（标题 + 货币行）
-- ============================================================================

function M.BuildHeader()
    local UI = S.UI
    return UI.Panel {
        width = "100%",
        paddingTop = 8, paddingBottom = 4,
        paddingLeft = 16, paddingRight = 16,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Label {
                text = "深渊符文", fontSize = 18,
                fontColor = {220, 200, 255, 255}, fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    Currency.IconWidget(UI, "rift_dust", 16),
                    UI.Label {
                        text = Currency.Format("rift_dust"),
                        fontSize = 13, fontColor = {200,180,220},
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- BottomBar（底部货币栏）
-- ============================================================================

function M.BuildBottomBar()
    local UI = S.UI
    local GameUI = require("Game.GameUI")
    return UI.Panel {
        width = "100%",
        flexShrink = 0,
        flexDirection = "row",
        justifyContent = "flex-end",
        alignItems = "center",
        paddingTop = 6, paddingBottom = 8,
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = { 30, 22, 16, 240 },
        borderTopWidth = 1,
        borderTopColor = { 75, 55, 38, 100 },
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    GameUI.CreateCurrencyChip(UI, "rift_dust",      "runeDustLabel",    { 160, 120, 200 }),
                    GameUI.CreateCurrencyChip(UI, "rune_seal",      "runeSealLabel",    { 40, 200, 160 }),
                    GameUI.CreateCurrencyChip(UI, "abyss_crystal",  "runeCrystalLabel", { 200, 60, 255 }),
                },
            },
        },
    }
end

-- ============================================================================
-- HeroSelector（英雄选择栏）
-- ============================================================================

---@param onRefresh function  选择英雄后的刷新回调
function M.BuildHeroSelector(onRefresh)
    local UI = S.UI
    local heroes = {}
    for _, heroId in ipairs(HeroData.deployed) do
        heroes[#heroes + 1] = heroId
    end

    local items = {}
    for _, heroId in ipairs(heroes) do
        local isSelected = (heroId == S.selectedHero)

        items[#items + 1] = UI.Panel {
            flex = 1,
            aspectRatio = 1,
            children = {
                HeroAvatar.Create(heroId, {
                    preset = "selector",
                    selected = isSelected,
                    onClick = function(self)
                        S.selectedHero = heroId
                        S.selectedRune = nil
                        S.selectedSlotIdx = nil
                        if onRefresh then onRefresh("hero_change") end
                    end,
                }),
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        flexDirection = "row",
        gap = 6,
        children = items,
    }
end

-- ============================================================================
-- SetBonusBar（套装效果）
-- ============================================================================

function M.BuildSetBonusBar()
    local UI = S.UI
    local sets = RuneData.GetSetBonuses(S.selectedHero)

    if #sets == 0 then
        return UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 4, paddingBottom = 4,
            flexShrink = 0,
            children = {
                UI.Label {
                    text = "装备同系列符文可激活套装效果",
                    fontSize = 11, fontColor = {100,90,130,150},
                },
            },
        }
    end

    local children = {}
    for _, setInfo in ipairs(sets) do
        local s = setInfo.series
        local color = s.tagColor
        local desc2 = setInfo.set2 and s.set2.desc or ""
        local desc3 = setInfo.set3 and s.set3.desc or ""

        children[#children + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Panel {
                    paddingLeft = 4, paddingRight = 4,
                    paddingTop = 1, paddingBottom = 1,
                    backgroundColor = {color[1], color[2], color[3], 200},
                    borderRadius = 3,
                    flexDirection = "row", alignItems = "center", gap = 2,
                    children = {
                        s.icon and UI.Panel {
                            width = 14, height = 14,
                            backgroundImage = s.icon, backgroundFit = "contain",
                            pointerEvents = "none",
                        } or UI.Label { text = s.emoji, fontSize = 10, fontColor = {20,16,32,255} },
                        UI.Label {
                            text = s.name .. " " .. setInfo.count .. "/" .. RuneConfig.MAX_SLOTS,
                            fontSize = 10, fontColor = {20,16,32,255},
                        },
                    },
                },
                setInfo.set2 and UI.Label {
                    text = "2件:" .. desc2,
                    fontSize = 10, fontColor = {100,255,100,255},
                } or nil,
                setInfo.set3 and UI.Label {
                    text = "3件:" .. desc3,
                    fontSize = 10, fontColor = {255,200,80,255},
                } or nil,
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        gap = 2,
        children = children,
    }
end

return M
