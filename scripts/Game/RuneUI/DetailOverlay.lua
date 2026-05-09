-- RuneUI/DetailOverlay.lua
-- 符文详情浮层 + 单个分解确认 + 执行分解

local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")
local Currency = require("Game.Currency")
local Tower = require("Game.Tower")

local S = require("Game.RuneUI.State")

local M = {}

-- ── 分解确认浮层引用 ──
local decomposeConfirmOverlay = nil

-- ============================================================================
-- 单个分解
-- ============================================================================

---@param rune table
---@param onDone function  分解完成后回调 ("decompose")
function M.DoDecompose(rune, onDone)
    local ok, msg, gained = RuneData.Decompose(rune.runeId)
    local Toast = require("Game.Toast")
    if ok and gained then
        local parts = {}
        for currId, amount in pairs(gained) do
            local info = RuneConfig.CURRENCIES[currId]
            local name = info and info.name or currId
            parts[#parts + 1] = name .. "×" .. amount
        end
        Toast.Show("分解获得: " .. table.concat(parts, " "), {100,255,100})
    else
        Toast.Show(msg or "分解失败", {255,100,80})
    end
    S.selectedRune = nil
    if onDone then onDone("decompose") end
end

-- ============================================================================
-- 分解确认弹窗（高品质符文）
-- ============================================================================

---@param rune table
---@param onDone function
function M.ShowDecomposeConfirm(rune, onDone)
    if decomposeConfirmOverlay then return end

    local UI = S.UI
    local quality = RuneData.GetQuality(rune.qualityId)
    local series = RuneData.GetSeries(rune.seriesId)
    local qName = quality and quality.name or "未知"
    local sName = series and series.name or "未知"
    local qColor = quality and quality.color or {255,255,255}

    local function closeConfirm()
        if decomposeConfirmOverlay and S.pageRoot then
            S.pageRoot:RemoveChild(decomposeConfirmOverlay)
            decomposeConfirmOverlay = nil
        end
    end

    -- 预览分解获得
    local decomposeLoot = RuneConfig.DECOMPOSE[rune.qualityId] or {}
    local lootChildren = {}
    for currId, amount in pairs(decomposeLoot) do
        local info = RuneConfig.CURRENCIES[currId]
        lootChildren[#lootChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                Currency.IconWidget(UI, currId, 16),
                UI.Label {
                    text = (info and info.name or currId) .. " +" .. amount,
                    fontSize = 13, fontColor = {220,210,200},
                },
            },
        }
    end

    local confirmCard = UI.Panel {
        width = 260,
        backgroundColor = { 40, 28, 18, 250 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { qColor[1], qColor[2], qColor[3], 200 },
        paddingTop = 16, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        alignItems = "center",
        gap = 10,
        onClick = function(self) end,
        children = {
            UI.Label {
                text = "确认分解",
                fontSize = 17, fontColor = {255,120,100}, fontWeight = "bold",
            },
            UI.Label {
                text = qName .. " · " .. sName,
                fontSize = 14, fontColor = { qColor[1], qColor[2], qColor[3], 255 }, fontWeight = "bold",
            },
            UI.Label {
                text = "该符文品质较高，分解后无法恢复",
                fontSize = 12, fontColor = {200,180,160},
            },
            UI.Panel { width = "90%", height = 1, backgroundColor = {100,75,55,100} },
            UI.Label { text = "分解获得", fontSize = 13, fontColor = {255,200,100}, fontWeight = "bold" },
            UI.Panel { alignItems = "center", gap = 4, children = lootChildren },
            UI.Panel { width = "90%", height = 1, backgroundColor = {100,75,55,100} },
            UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 4,
                children = {
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = {80,60,45,220},
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self) closeConfirm() end,
                        children = {
                            UI.Label { text = "取消", fontSize = 14, fontColor = {200,180,160} },
                        },
                    },
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = {160,50,40,240},
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            closeConfirm()
                            M.DoDecompose(rune, onDone)
                        end,
                        children = {
                            UI.Label { text = "确认分解", fontSize = 14, fontColor = {255,255,255}, fontWeight = "bold" },
                        },
                    },
                },
            },
        },
    }

    decomposeConfirmOverlay = UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 80,
        backgroundColor = {0,0,0,160},
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self) closeConfirm() end,
        children = { confirmCard },
    }
    S.pageRoot:AddChild(decomposeConfirmOverlay)
end

-- ============================================================================
-- 符文详情浮层
-- ============================================================================

---@param onRefresh function  刷新回调 (reason: string)
---@return any  overlay Panel
function M.Build(onRefresh)
    local UI = S.UI
    local rune = S.selectedRune
    if not rune then return UI.Panel {} end

    local selectedHero = S.selectedHero
    local selectedSlotIdx = S.selectedSlotIdx
    local selectedSource = S.selectedSource
    local series = RuneData.GetSeries(rune.seriesId)
    local quality = RuneData.GetQuality(rune.qualityId)
    local isEquipped = (selectedSource == "equipped")

    -- ── 词条列表 ──
    local affixChildren = {}
    for i, affix in ipairs(rune.affixes) do
        local descText = nil
        local def = RuneConfig.AFFIX_MAP[affix.id]
        if def and def.desc then
            descText = def.desc
        end

        local rowContent = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = RuneData.FormatAffix(affix),
                                fontSize = 13, fontColor = {220,210,240,255},
                            },
                            UI.Label {
                                text = RuneData.FormatAffixRange(affix, rune.qualityId),
                                fontSize = 10, fontColor = {140,130,160,180},
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            affix.locked and UI.Label {
                                text = "🔒", fontSize = 12,
                            } or nil,
                            UI.Button {
                                text = affix.locked and "解锁" or "锁定",
                                fontSize = 9, variant = "outline",
                                height = 22, paddingLeft = 6, paddingRight = 6,
                                onClick = function(self)
                                    RuneData.ToggleAffixLock(rune, i)
                                    -- 刷新 overlay 自身
                                    if onRefresh then onRefresh("affix_lock") end
                                end,
                            },
                        },
                    },
                },
            },
        }

        if descText then
            rowContent[#rowContent + 1] = UI.Label {
                text = descText,
                fontSize = 10, fontColor = {160,155,180,150},
                paddingLeft = 4,
            }
        end

        affixChildren[#affixChildren + 1] = UI.Panel {
            width = "100%",
            gap = 1,
            children = rowContent,
        }
    end

    -- 标签词条
    local tagAffix = rune.tagAffix
    if tagAffix then
        local tagDef = RuneConfig.AFFIX_MAP[tagAffix.id]
        local tagColor = tagDef and tagDef.color or {200,180,255}
        local tagDescText = tagDef and tagDef.desc or nil

        local tagContent = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel {
                                paddingLeft = 4, paddingRight = 4,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = {tagColor[1], tagColor[2], tagColor[3], 40},
                                borderRadius = 3,
                                children = {
                                    UI.Label {
                                        text = "特殊", fontSize = 9,
                                        fontColor = {tagColor[1], tagColor[2], tagColor[3], 220},
                                    },
                                },
                            },
                            UI.Label {
                                text = RuneData.FormatAffix(tagAffix),
                                fontSize = 13, fontColor = { tagColor[1], tagColor[2], tagColor[3], 255 },
                            },
                            UI.Label {
                                text = RuneData.FormatAffixRange(tagAffix, rune.qualityId),
                                fontSize = 10, fontColor = {140,130,160,180},
                            },
                        },
                    },
                },
            },
        }
        if tagDescText then
            tagContent[#tagContent + 1] = UI.Label {
                text = tagDescText,
                fontSize = 10, fontColor = {160,155,180,150},
                paddingLeft = 4,
            }
        end

        affixChildren[#affixChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 4,
            borderTopWidth = 1,
            borderColor = {80,60,120,60},
            children = tagContent,
        }
    end

    -- ── 操作按钮 ──
    local buttons = {}
    if isEquipped then
        buttons[#buttons + 1] = UI.Button {
            text = "卸下", fontSize = 12, variant = "outline",
            flex = 1, height = 36,
            onClick = function(self)
                local ok, msg = RuneData.Unequip(selectedHero, selectedSlotIdx)
                local Toast = require("Game.Toast")
                Toast.Show(ok and "已卸下" or msg, ok and {100,255,100} or {255,100,80})
                if ok then Tower.RefreshAllStats() end
                S.selectedRune = nil
                if onRefresh then onRefresh("unequip") end
            end,
        }
    else
        buttons[#buttons + 1] = UI.Button {
            text = "装备", fontSize = 12, variant = "primary",
            flex = 1, height = 36,
            onClick = function(self)
                local targetSlot = selectedSlotIdx
                if not targetSlot then
                    local equipped = RuneData.GetEquipped(selectedHero)
                    for si = 1, RuneConfig.MAX_SLOTS do
                        if RuneData.IsSlotUnlocked(si) and not equipped[si] then
                            targetSlot = si
                            break
                        end
                    end
                    if not targetSlot then
                        for si = 1, RuneConfig.MAX_SLOTS do
                            if RuneData.IsSlotUnlocked(si) then
                                targetSlot = si
                                break
                            end
                        end
                    end
                end
                if not targetSlot then
                    local Toast = require("Game.Toast")
                    Toast.Show("没有可用槽位", {255,100,80})
                    return
                end
                local ok, msg = RuneData.Equip(selectedHero, targetSlot, rune.runeId)
                local Toast = require("Game.Toast")
                Toast.Show(ok and "装备成功" or msg, ok and {100,255,100} or {255,100,80})
                if ok then Tower.RefreshAllStats() end
                S.selectedRune = nil
                S.selectedSlotIdx = nil
                if onRefresh then onRefresh("equip") end
            end,
        }
    end

    -- 洗练
    buttons[#buttons + 1] = UI.Button {
        text = "洗练", fontSize = 12, variant = "outline",
        flex = 1, height = 36,
        onClick = function(self)
            local RuneReforgeUI = require("Game.RuneReforgeUI")
            RuneReforgeUI.Open(S.pageRoot, rune, function()
                Tower.RefreshAllStats()
                if onRefresh then onRefresh("reforge") end
            end)
        end,
    }

    -- 锁定/解锁（仅背包）
    if not isEquipped then
        local isLocked = RuneData.IsRuneLocked(rune)
        buttons[#buttons + 1] = UI.Button {
            text = isLocked and "🔒解锁" or "🔒锁定",
            fontSize = 12,
            variant = isLocked and "primary" or "outline",
            flex = 1, height = 36,
            onClick = function(self)
                local ok, msg = RuneData.ToggleRuneLock(rune)
                local Toast = require("Game.Toast")
                Toast.Show(msg, {100,255,100})
                if onRefresh then onRefresh("rune_lock") end
            end,
        }
    end

    -- 分解（仅背包中未锁定）
    if not isEquipped then
        local isLocked = RuneData.IsRuneLocked(rune)
        buttons[#buttons + 1] = UI.Button {
            text = "分解", fontSize = 12, variant = "outline",
            flex = 1, height = 36,
            disabled = isLocked,
            onClick = function(self)
                if RuneData.IsRuneLocked(rune) then
                    local Toast = require("Game.Toast")
                    Toast.Show("符文已锁定，无法分解", {255,200,80})
                    return
                end
                if rune.qualityId == "red" or rune.qualityId == "orange" then
                    M.ShowDecomposeConfirm(rune, onRefresh)
                else
                    M.DoDecompose(rune, onRefresh)
                end
            end,
        }
    end

    -- ── 套装效果预览 ──
    local setChildren = {}
    if series then
        setChildren[#setChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 4,
            borderTopWidth = 1,
            borderColor = {60,50,90,100},
            gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        series.icon and UI.Panel {
                            width = 16, height = 16,
                            backgroundImage = series.icon, backgroundFit = "contain",
                            pointerEvents = "none",
                        } or UI.Label { text = series.emoji, fontSize = 11, fontColor = series.tagColor },
                        UI.Label {
                            text = series.name .. "套装效果",
                            fontSize = 11, fontColor = series.tagColor,
                        },
                    },
                },
                UI.Label {
                    text = "2件: " .. series.set2.desc,
                    fontSize = 10, fontColor = {180,170,200,200},
                },
                UI.Label {
                    text = "3件: " .. series.set3.desc,
                    fontSize = 10, fontColor = {180,170,200,200},
                },
            },
        }
    end

    -- ── 弹窗覆盖层 ──
    return UI.Panel {
        id = S.ID.DETAIL_OVERLAY,
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 50,
        backgroundColor = {0, 0, 0, 160},
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self)
            S.selectedRune = nil
            S.selectedSlotIdx = nil
            if onRefresh then onRefresh("close_detail") end
        end,
        children = {
            UI.Panel {
                width = "90%",
                flexDirection = "column",
                backgroundColor = {30, 24, 50, 240},
                borderRadius = 12,
                borderWidth = 1,
                borderColor = {quality.color[1], quality.color[2], quality.color[3], 150},
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 10, paddingBottom = 10,
                gap = 4,
                pointerEvents = "auto",
                onClick = function(self) end,
                children = {
                    -- 标题行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        flexShrink = 0,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 6,
                                children = {
                                    (series and series.icon) and UI.Panel {
                                        width = 28, height = 28,
                                        backgroundImage = series.icon, backgroundFit = "contain",
                                        pointerEvents = "none",
                                    } or UI.Label { text = series and series.emoji or "🔮", fontSize = 20 },
                                    UI.Label {
                                        text = (series and series.name or "") .. "符文",
                                        fontSize = 16, fontColor = quality.color, fontWeight = "bold",
                                    },
                                    UI.Panel {
                                        paddingLeft = 6, paddingRight = 6,
                                        paddingTop = 1, paddingBottom = 1,
                                        backgroundColor = {quality.color[1], quality.color[2], quality.color[3], 200},
                                        borderRadius = 4,
                                        children = {
                                            UI.Label {
                                                text = quality.name,
                                                fontSize = 10, fontColor = {20,16,32,255},
                                            },
                                        },
                                    },
                                },
                            },
                            UI.Button {
                                text = "✕", fontSize = 14, variant = "ghost",
                                width = 28, height = 28,
                                onClick = function(self)
                                    S.selectedRune = nil
                                    S.selectedSlotIdx = nil
                                    if onRefresh then onRefresh("close_detail") end
                                end,
                            },
                        },
                    },
                    -- 词条
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 2,
                        paddingTop = 4, paddingBottom = 4,
                        flexShrink = 0,
                        children = affixChildren,
                    },
                    -- 套装效果
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 2,
                        flexShrink = 0,
                        children = setChildren,
                    },
                    -- 操作按钮
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 8,
                        paddingTop = 8,
                        flexShrink = 0,
                        children = buttons,
                    },
                },
            },
        },
    }
end

return M
