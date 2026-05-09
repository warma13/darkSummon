-- Game/HeroUI/HeroDetail/CostumeTab.lua
-- 英雄详情 - 时装标签页（翼/武器/光环/粒子光效）

local Config = require("Game.Config")

local CostumeTab = {}

--- 构建时装标签页内容
---@param ctx table
---@param heroId string
function CostumeTab.Build(ctx, heroId)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local CostumeData = require("Game.CostumeData")

    -- 从精灵图裁出单帧作为图标
    local function FrameIcon(size, def, frameIdx)
        local cols   = def.gridCols or 2
        local rows   = def.gridRows or 2
        local fCol   = frameIdx % cols
        local fRow   = math.floor(frameIdx / cols)
        local sheetW = size * cols
        local sheetH = size * rows
        return UI.Panel {
            position = "absolute",
            left = -fCol * size,
            top  = -fRow * size,
            width  = sheetW,
            height = sheetH,
            backgroundImage = def.preview,
            backgroundFit = "fill",
        }
    end

    local RARITY_COLOR = Config.RARITY_COLORS

    -- ── 系统说明浮层 ──────────────────────────────────────────────────────────
    local _infoOverlay = nil
    local function ShowCostumeInfoPopup()
        if _infoOverlay then return end
        local pageRoot = ctx.GetPageRoot()
        if not pageRoot then return end

        local function closePopup()
            if _infoOverlay then
                pageRoot:RemoveChild(_infoOverlay)
                _infoOverlay = nil
            end
        end

        -- 动态生成图鉴加成描述行
        local bonusRows = {}
        local totalAtk = 0
        for _, slot in ipairs(CostumeData.SLOTS) do
            if slot.costumes then
                for _, def in ipairs(slot.costumes) do
                    if def.owned and def.atkBonus and def.atkBonus > 0 then
                        totalAtk = totalAtk + def.atkBonus
                        bonusRows[#bonusRows + 1] = UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            gap = 8, paddingTop = 3, paddingBottom = 3,
                            children = {
                                UI.Panel {
                                    width = 4, height = 4, borderRadius = 2,
                                    backgroundColor = { 160, 100, 255, 255 },
                                },
                                UI.Label {
                                    text = def.name,
                                    fontSize = 12,
                                    fontColor = def.rarityColor or { 200, 180, 255, 255 },
                                },
                                UI.Label {
                                    text = string.format("全英雄攻击 +%.0f%%", def.atkBonus * 100),
                                    fontSize = 12,
                                    fontColor = { 120, 220, 120, 255 },
                                },
                            },
                        }
                    end
                end
            end
        end
        if #bonusRows == 0 then
            bonusRows[#bonusRows + 1] = UI.Label {
                text = "暂无已解锁时装加成",
                fontSize = 12,
                fontColor = { 140, 130, 150, 200 },
            }
        end

        _infoOverlay = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 0, 0, 0, 160 },
            pointerEvents = "auto",
            zIndex = 300,
            onClick = function() closePopup() end,
            children = {
                UI.Panel {
                    width = 280,
                    backgroundColor = { 28, 20, 42, 252 },
                    borderRadius = 14,
                    borderWidth = 2,
                    borderColor = { 140, 90, 220, 200 },
                    paddingTop = 18, paddingBottom = 18,
                    paddingLeft = 18, paddingRight = 18,
                    gap = 10,
                    pointerEvents = "auto",
                    onClick = function() end,   -- 阻止冒泡关闭
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            justifyContent = "space-between",
                            children = {
                                UI.Label {
                                    text = "时装图鉴系统",
                                    fontSize = 16, fontWeight = "bold",
                                    fontColor = { 200, 160, 255, 255 },
                                },
                                UI.Panel {
                                    paddingLeft = 8, paddingRight = 8,
                                    paddingTop = 4, paddingBottom = 4,
                                    pointerEvents = "auto",
                                    onClick = function() closePopup() end,
                                    children = {
                                        UI.Label { text = "✕", fontSize = 14, fontColor = { 160, 140, 180, 200 } },
                                    },
                                },
                            },
                        },
                        UI.Panel { width = "100%", height = 1, backgroundColor = { 100, 70, 150, 100 } },
                        UI.Label {
                            text = "解锁时装即可永久获得图鉴加成，无需装备槽位。",
                            fontSize = 12,
                            fontColor = { 190, 175, 210, 230 },
                            flexWrap = "wrap",
                        },
                        UI.Label {
                            text = "收集更多时装，加成效果可叠加。",
                            fontSize = 12,
                            fontColor = { 190, 175, 210, 230 },
                        },
                        UI.Panel { width = "100%", height = 1, backgroundColor = { 100, 70, 150, 100 } },
                        UI.Label {
                            text = string.format("当前图鉴加成  全英雄攻击 +%.0f%%", totalAtk * 100),
                            fontSize = 13, fontWeight = "bold",
                            fontColor = { 120, 220, 120, 255 },
                        },
                        UI.Panel {
                            width = "100%", gap = 2,
                            children = bonusRows,
                        },
                    },
                },
            },
        }
        pageRoot:AddChild(_infoOverlay)
    end

    local children = {}

    -- ── 装备槽位行（水平一行显示所有槽位） ──────────────────────────────────
    local function MakeSlotCell(slotDef)
        local def = CostumeData.GetEquippedDef(slotDef.id)
        local bc = def and (def.rarityColor or { 120, 80, 200, 200 }) or { 70, 55, 42, 150 }
        local iconContent
        if def then
            if slotDef.id == "wing" then
                iconContent = { FrameIcon(40, def, def.iconFrame or 0) }
            else
                iconContent = { UI.Panel { width = 40, height = 40, backgroundImage = def.preview, backgroundFit = "contain" } }
            end
        else
            local slotLabels = { wing = "翼", weapon = "武", aura = "环", particle = "粒" }
            local label = slotLabels[slotDef.id] or "?"
            iconContent = { UI.Label { text = label, fontSize = 14, fontColor = { 100, 80, 65, 200 } } }
        end
        return UI.Panel {
            flexGrow = 1, flexShrink = 1, flexBasis = 0,
            flexDirection = "column",
            alignItems = "center",
            gap = 4,
            backgroundColor = { 40, 28, 20, 220 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = def and bc or { 90, 65, 48, 200 },
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 6, paddingRight = 6,
            children = {
                UI.Panel {
                    width = 40, height = 40,
                    borderRadius = 8,
                    backgroundColor = { 55, 38, 28, 255 },
                    borderWidth = 1,
                    borderColor = bc,
                    justifyContent = "center", alignItems = "center",
                    overflow = "hidden",
                    children = iconContent,
                },
                UI.Label { text = slotDef.label, fontSize = 10, fontColor = S.dim },
                UI.Label {
                    text = def and def.name or "空置",
                    fontSize = 11,
                    fontColor = def and (def.rarityColor or S.white) or S.dimLocked,
                    fontWeight = def and "bold" or "normal",
                },
                def and UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 3, paddingBottom = 3,
                    borderRadius = 5,
                    backgroundColor = { 70, 50, 38, 200 },
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        CostumeData.Equip(slotDef.id, nil)
                        ctx.ShowHeroDetail(heroId)
                    end,
                    children = {
                        UI.Label { text = "卸下", fontSize = 10, fontColor = { 180, 160, 140, 220 } },
                    },
                } or nil,
            },
        }
    end

    local slotCells = {}
    for _, slotDef in ipairs(CostumeData.SLOTS) do
        slotCells[#slotCells + 1] = MakeSlotCell(slotDef)
    end

    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        children = slotCells,
    }

    -- ── 通用时装卡片构建器 ──────────────────────────────────────────────────
    local function BuildCostumeCard(slotId, def, opts)
        local isOwned = CostumeData.IsOwned(def.id)
        local isEquipped = CostumeData.IsEquipped(slotId, def.id)
        local rc = def.rarityColor or RARITY_COLOR[def.rarity] or { 180, 180, 180, 255 }
        local bgEquipped = opts and opts.bgEquipped or { 50, 35, 65, 240 }
        local bgOwned = opts and opts.bgOwned or { 38, 27, 20, 200 }
        local bgLocked = opts and opts.bgLocked or { 28, 24, 32, 180 }
        local descColor = opts and opts.descColor or { 180, 165, 150, 180 }
        local btnEquippedBg = opts and opts.btnEquippedBg or { 80, 55, 110, 240 }
        local btnEquippedColor = opts and opts.btnEquippedColor or { 200, 170, 255, 220 }

        -- 预览图
        local previewChildren
        if slotId == "wing" then
            previewChildren = { FrameIcon(54, def, def.iconFrame or 0) }
        else
            previewChildren = { UI.Panel { width = 54, height = 54, backgroundImage = def.preview, backgroundFit = "contain" } }
        end

        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            backgroundColor = isEquipped and bgEquipped or (isOwned and bgOwned or bgLocked),
            borderRadius = 10,
            borderWidth = isEquipped and 2 or 1,
            borderColor = isEquipped and rc or (isOwned and { 70, 55, 42, 120 } or { 50, 45, 60, 80 }),
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 10, paddingRight = 10,
            children = {
                UI.Panel {
                    width = 54, height = 54,
                    flexShrink = 0,
                    borderRadius = 8,
                    backgroundColor = { 30, 20, 40, 255 },
                    borderWidth = 1,
                    borderColor = rc,
                    overflow = "hidden",
                    children = {
                        previewChildren[1],
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
                    gap = 3,
                    children = {
                        UI.Label { text = def.name, fontSize = 13, fontColor = rc, fontWeight = "bold" },
                        UI.Label { text = def.desc or "", fontSize = 10, fontColor = descColor },
                    },
                },
                UI.Panel {
                    width = 54, flexShrink = 0,
                    paddingTop = 7, paddingBottom = 7,
                    borderRadius = 8,
                    backgroundColor = isEquipped and btnEquippedBg
                        or (isOwned and { 60, 100, 80, 220 } or { 45, 40, 55, 180 }),
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if isOwned and not isEquipped then
                            CostumeData.Equip(slotId, def.id)
                            ctx.ShowHeroDetail(heroId)
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isEquipped and "已装备" or (isOwned and "装备" or "未解锁"),
                            fontSize = 11,
                            fontColor = isEquipped and btnEquippedColor
                                or (isOwned and { 220, 255, 220, 255 } or { 120, 110, 130, 180 }),
                            fontWeight = "bold",
                        },
                    },
                },
            },
        }
    end

    -- ── 分类标题构建器 ──────────────────────────────────────────────────────
    local function BuildSectionTitle(text, color, extraChildren)
        local titleChildren = {
            UI.Panel { width = 3, height = 14, borderRadius = 2, backgroundColor = color },
            UI.Label { text = text, fontSize = 13, fontColor = S.dim, fontWeight = "bold" },
        }
        if extraChildren then
            for _, c in ipairs(extraChildren) do
                titleChildren[#titleChildren + 1] = c
            end
        end
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            marginTop = 10,
            pointerEvents = "auto",
            children = titleChildren,
        }
    end

    -- ── 翅膀 ──────────────────────────────────────────────────────────────────
    children[#children + 1] = BuildSectionTitle("翅膀", { 160, 100, 255, 255 }, {
        UI.Panel { flex = 1 },
        UI.Panel {
            width = 18, height = 18,
            borderRadius = 9,
            borderWidth = 1,
            borderColor = { 140, 100, 200, 180 },
            backgroundColor = { 50, 35, 75, 200 },
            justifyContent = "center", alignItems = "center",
            onClick = function() ShowCostumeInfoPopup() end,
            children = {
                UI.Label { text = "?", fontSize = 10, fontWeight = "bold", fontColor = { 180, 140, 240, 255 }, pointerEvents = "none" },
            },
        },
    })
    for _, def in ipairs(CostumeData.WING_COSTUMES) do
        children[#children + 1] = BuildCostumeCard("wing", def)
    end

    -- ── 武器 ──────────────────────────────────────────────────────────────────
    children[#children + 1] = BuildSectionTitle("武器", { 255, 180, 50, 255 })
    for _, def in ipairs(CostumeData.WEAPON_COSTUMES) do
        children[#children + 1] = BuildCostumeCard("weapon", def, {
            bgEquipped = { 50, 40, 25, 240 },
        })
    end

    -- ── 光环 ──────────────────────────────────────────────────────────────────
    children[#children + 1] = BuildSectionTitle("光环", { 200, 160, 255, 255 })
    for _, def in ipairs(CostumeData.AURA_COSTUMES) do
        children[#children + 1] = BuildCostumeCard("aura", def, {
            bgEquipped = { 50, 40, 25, 240 },
        })
    end

    -- ── 粒子光效 ──────────────────────────────────────────────────────────────
    children[#children + 1] = BuildSectionTitle("粒子光效", { 120, 200, 255, 255 })
    for _, def in ipairs(CostumeData.PARTICLE_COSTUMES) do
        children[#children + 1] = BuildCostumeCard("particle", def, {
            bgEquipped = { 25, 40, 55, 240 },
            bgOwned = { 20, 30, 38, 200 },
            descColor = { 150, 175, 200, 180 },
            btnEquippedBg = { 55, 80, 110, 240 },
            btnEquippedColor = { 170, 200, 255, 220 },
        })
    end

    return UI.Panel {
        width = "100%",
        gap = 6,
        pointerEvents = "auto",
        children = children,
    }
end

return CostumeTab
