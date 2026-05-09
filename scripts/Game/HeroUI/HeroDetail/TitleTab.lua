-- Game/HeroUI/HeroDetail/TitleTab.lua
-- 英雄详情 - 称号图鉴标签页

local TitleTab = {}

--- 构建称号标签页内容
---@param ctx table
---@param heroId string
function TitleTab.Build(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local TitleData = require("Game.TitleData")

    local RARITY_ORDER = { N = 1, R = 2, SR = 3, SSR = 4, UR = 5, LR = 6 }
    local children = {}

    -- ── 当前装备称号槽 ──────────────────────────────────────────────────────
    local equippedDef = TitleData.GetEquippedDef()
    local slotBorder = equippedDef and equippedDef.borderColor or { 70, 55, 42, 150 }
    local slotRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 10,
        backgroundColor = { 40, 28, 20, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = slotBorder,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        children = {
            UI.Panel {
                width = 44, height = 44,
                flexShrink = 0,
                borderRadius = 8,
                backgroundColor = equippedDef and { 45, 30, 60, 255 } or { 55, 38, 28, 255 },
                borderWidth = 1,
                borderColor = slotBorder,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = equippedDef and "称" or "称",
                        fontSize = equippedDef and 16 or 18,
                        fontColor = equippedDef and equippedDef.color or { 100, 80, 65, 200 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Panel {
                flexGrow = 1,
                gap = 2,
                children = {
                    UI.Label { text = "称号", fontSize = 12, fontColor = S.dim },
                    UI.Label {
                        text = equippedDef and equippedDef.name or "空置",
                        fontSize = 14,
                        fontColor = equippedDef and equippedDef.color or S.dimLocked,
                        fontWeight = equippedDef and "bold" or "normal",
                    },
                },
            },
            equippedDef and UI.Panel {
                gap = 1,
                children = (function()
                    local bonusLabels = {}
                    local bonusNames = {
                        atkPct = "攻击", spdPct = "攻速", critRate = "暴击",
                        critDmg = "暴伤", armorPen = "穿甲", scorePct = "排行",
                    }
                    for k, v in pairs(equippedDef.bonuses or {}) do
                        if v > 0 then
                            bonusLabels[#bonusLabels + 1] = UI.Label {
                                text = (bonusNames[k] or k) .. string.format("+%.0f%%", v * 100),
                                fontSize = 9,
                                fontColor = { 120, 220, 120, 255 },
                            }
                        end
                    end
                    return bonusLabels
                end)(),
            } or nil,
            equippedDef and UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 6,
                backgroundColor = { 70, 50, 38, 200 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    TitleData.Unequip()
                    ctx.ShowHeroDetail(heroId)
                end,
                children = {
                    UI.Label { text = "卸下", fontSize = 11, fontColor = { 180, 160, 140, 220 } },
                },
            } or nil,
        },
    }
    children[#children + 1] = slotRow

    -- ── 称号分类标题 ────────────────────────────────────────────────────────
    local ownedCount = 0
    for _, def in ipairs(TitleData.TITLES) do
        if TitleData.IsOwned(def.id) then ownedCount = ownedCount + 1 end
    end
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 10,
        children = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = { 255, 200, 60, 255 } },
            UI.Label { text = "称号图鉴", fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
            UI.Panel { flex = 1 },
            UI.Label {
                text = ownedCount .. "/" .. #TitleData.TITLES,
                fontSize = 11, fontColor = { 160, 140, 120, 180 },
            },
        },
    }

    -- ── 称号卡片列表 ────────────────────────────────────────────────────────
    local sortedTitles = {}
    for _, def in ipairs(TitleData.TITLES) do
        sortedTitles[#sortedTitles + 1] = def
    end
    table.sort(sortedTitles, function(a, b)
        local aOwned = TitleData.IsOwned(a.id) and 1 or 0
        local bOwned = TitleData.IsOwned(b.id) and 1 or 0
        if aOwned ~= bOwned then return aOwned > bOwned end
        return (RARITY_ORDER[a.rarity] or 0) > (RARITY_ORDER[b.rarity] or 0)
    end)

    for _, def in ipairs(sortedTitles) do
        local isOwned = TitleData.IsOwned(def.id)
        local isEquipped = TitleData.IsEquipped(def.id)
        local rc = def.color or { 180, 180, 180, 255 }
        local bc = def.borderColor or { 100, 100, 100, 180 }

        local bonusText = {}
        local bonusNames = {
            atkPct = "攻击", spdPct = "攻速", critRate = "暴击",
            critDmg = "暴伤", armorPen = "穿甲", scorePct = "排行",
        }
        for k, v in pairs(def.bonuses or {}) do
            if v > 0 then
                bonusText[#bonusText + 1] = (bonusNames[k] or k) .. string.format("+%.0f%%", v * 100)
            end
        end
        local bonusStr = #bonusText > 0 and table.concat(bonusText, "  ") or ""

        local timeStr = ""
        if isOwned then
            local ts = TitleData.GetAcquiredTime(def.id)
            if ts and ts > 0 then
                timeStr = os.date("%Y-%m-%d", ts)
            end
        end

        local card = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and { 50, 35, 65, 240 }
                or (isOwned and { 38, 27, 20, 200 } or { 28, 24, 32, 180 }),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and bc or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            opacity = isOwned and 1.0 or 0.6,
            children = {
                UI.Panel {
                    width = 50, height = 50,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 30, 20, 40, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label {
                            text = "称",
                            fontSize = 18,
                            fontColor = rc,
                            fontWeight = "bold",
                        },
                        UI.Panel {
                            position = "absolute",
                            top = 2, left = 2,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 3,
                            backgroundColor = { 0, 0, 0, 160 },
                            children = {
                                UI.Label { text = def.rarity or "N", fontSize = 8, fontColor = rc, fontWeight = "bold" },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label { text = def.name, fontSize = 14, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = { 180, 165, 150, 180 } },
                        bonusStr ~= "" and UI.Label {
                            text = bonusStr,
                            fontSize = 10,
                            fontColor = isOwned and { 120, 220, 120, 200 } or { 100, 100, 100, 150 },
                        } or nil,
                        timeStr ~= "" and UI.Label {
                            text = "获得: " .. timeStr,
                            fontSize = 9,
                            fontColor = { 140, 130, 120, 150 },
                        } or nil,
                    },
                },
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and { 80, 55, 110, 240 }
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            TitleData.Equip(def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and { 200, 170, 255, 220 }
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
        children[#children + 1] = card
    end

    return UI.Panel {
        width = "100%",
        gap = 6,
        pointerEvents = "auto",
        children = children,
    }
end

return TitleTab
