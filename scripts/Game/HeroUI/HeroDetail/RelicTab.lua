-- Game/HeroUI/HeroDetail/RelicTab.lua
-- 遗物标签页 + 重生确认弹窗

local Config   = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local RelicData = require("Game.RelicData")
local RelicCalc = require("Game.RelicCalc")
local Toast    = require("Game.Toast")

local RelicTab = {}

local function ShowToast(msg) Toast.Show(msg) end

-- ── FormatRelicDesc 辅助 ─────────────────────────────────────────────────────

--- 不应被 V() 缩放的机制参数
local FIXED_KEYS = {
    armorPenCap = true, executeCap = true, doubleCastCap = true,
    doubleCastChance = true, executeThreshold = true,
    pulseInterval = true, postCastDuration = true,
    burnDuration = true, burnTicks = true,
    markInterval = true, markDuration = true, autoMarkInterval = true,
    markCount = true, otherAtkRatio = true,
}

--- 固定参数 → 对应的星级效果类型
local PARAM_STAR_MAP = {
    doubleCastChance = "chanceAdd",
    pulseInterval    = "intervalReduce",
    postCastDuration = "durationAdd",
    markDuration     = "durationAdd",
    autoMarkInterval = "intervalReduce",
}

local function FormatRelicDesc(relic, def)
    if not def or not def.desc then return "" end
    return (def.desc:gsub("{(%w+)}", function(key)
        local base = def.params and def.params[key]
        if not base then return "{" .. key .. "}" end
        local val = FIXED_KEYS[key] and base or RelicCalc.V(relic, base)
        -- 将星级加成合并到固定参数的显示值中
        local starType = PARAM_STAR_MAP[key]
        if starType and def.starEffect and def.starEffect.type == starType then
            local sv = RelicCalc.StarValue(relic.star, def.starEffect)
            if starType == "intervalReduce" then
                val = val - sv
            else
                val = val + sv
            end
        end
        if val < 1 then
            return string.format("%.0f%%", val * 100)
        elseif val == math.floor(val) then
            return string.format("%d", val)
        else
            return string.format("%.1f", val)
        end
    end))
end

-- ============================================================================
-- BuildRelicTab
-- ============================================================================

--- 构建遗物标签页
---@param ctx table
---@param heroId string
---@param state table  { selectedRelicSlot, selectedRelicView, setSlot, setView }
---@return any UI widget
function RelicTab.Build(ctx, heroId, state)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local FormatBigNum = ctx.FormatBigNum

    local selectedRelicSlot = state.selectedRelicSlot
    local selectedRelicView = state.selectedRelicView

    local children = {}

    -- ── Section 1: 横排 4 个 1:1 装备槽 ──────────────────────────────────────
    local slotPanels = {}
    for _, slotDef in ipairs(Config.RELIC_SLOTS) do
        local slotId = slotDef.id
        local equipped = RelicData.GetEquipped(slotId)
        local isSelected = (selectedRelicSlot == slotId)

        local titleText, titleColor
        if equipped then
            local def = Config.RELICS[equipped.id]
            titleText = def and def.name or equipped.id
            titleColor = Config.RELIC_QUALITY_COLOR[equipped.quality] or S.gold
        else
            titleText = slotDef.name
            titleColor = { 120, 100, 80 }
        end

        local relicImage = (equipped and Config.RELICS[equipped.id] and Config.RELICS[equipped.id].image) or slotDef.icon

        slotPanels[#slotPanels + 1] = UI.Panel {
            flex = 1,
            aspectRatio = 1,
            margin = 3,
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and S.gold or { 70, 55, 40, 150 },
            backgroundColor = isSelected and { 70, 55, 35, 240 } or { 50, 38, 28, 200 },
            overflow = "hidden",
            onClick = function(self)
                state.setSlot(slotId)
                state.setView(nil)
                ctx.ShowHeroDetail(heroId)
            end,
            children = {
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 2, paddingBottom = 1,
                    children = {
                        UI.Label { text = titleText, fontSize = 9, fontColor = titleColor, fontWeight = "bold", textAlign = "center" },
                    },
                },
                UI.Panel {
                    flex = 1, aspectRatio = 1, alignSelf = "center",
                    backgroundImage = relicImage, backgroundSize = "cover",
                    opacity = equipped and 1.0 or 0.25,
                },
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 1, paddingBottom = 2,
                    children = {
                        equipped and UI.Label {
                            text = "Lv." .. equipped.level .. " ★" .. equipped.star,
                            fontSize = 8, fontColor = { 200, 180, 160 },
                        } or UI.Label { text = "空", fontSize = 8, fontColor = { 80, 70, 60 } },
                    },
                },
            },
        }
    end
    children[#children + 1] = UI.Panel {
        width = "100%", flexDirection = "row",
        children = slotPanels,
    }

    -- ── Section 3: 遗物详情面板 ──────────────────────────────────────────────
    local eqRelic = RelicData.GetEquipped(selectedRelicSlot)

    if not selectedRelicView and eqRelic then
        selectedRelicView = { id = eqRelic.id, quality = eqRelic.quality }
        state.setView(selectedRelicView)
    end

    if selectedRelicView then
        local viewId = selectedRelicView.id
        local viewQuality = selectedRelicView.quality
        local viewDef = Config.RELICS[viewId]

        local isViewingEquipped = eqRelic and eqRelic.id == viewId
        local viewRelic
        if isViewingEquipped then
            viewRelic = eqRelic
        else
            local pLv, pStar = RelicData.GetProgress(viewId)
            viewRelic = { id = viewId, quality = viewQuality, level = pLv, star = pStar }
        end

        local qColor = Config.RELIC_QUALITY_COLOR[viewRelic.quality] or S.gold
        local qName = Config.RELIC_QUALITY_NAME[viewRelic.quality] or "?"

        -- 左侧：遗物描述
        local descText = FormatRelicDesc(viewRelic, viewDef)
        local descChildren = {
            UI.Label {
                text = (viewDef and viewDef.name or viewId),
                fontSize = 15, fontColor = qColor, fontWeight = "bold",
            },
        }
        local isViewOwned = RelicData.IsOwned(viewId)
        if isViewingEquipped then
            descChildren[#descChildren + 1] = UI.Label {
                text = qName .. " · Lv." .. viewRelic.level .. " · ★" .. viewRelic.star,
                fontSize = 11, fontColor = { 200, 180, 160 }, marginBottom = 4,
            }
        elseif isViewOwned then
            descChildren[#descChildren + 1] = UI.Label {
                text = qName .. " · Lv." .. viewRelic.level .. " · ★" .. viewRelic.star .. " · 未装备",
                fontSize = 11, fontColor = { 160, 140, 120 }, marginBottom = 4,
            }
        else
            local viewShards = RelicData.GetShards(viewId)
            local viewSynthCost = Config.RELIC_SYNTH_COST[viewDef and viewDef.minQuality or "green"] or 80
            descChildren[#descChildren + 1] = UI.Label {
                text = "未拥有 · 碎片 " .. viewShards .. "/" .. viewSynthCost,
                fontSize = 11, fontColor = { 120, 110, 90 }, marginBottom = 4,
            }
        end
        descChildren[#descChildren + 1] = UI.Label {
            text = descText,
            fontSize = 11, fontColor = { 200, 195, 180 },
            lineHeight = 1.4,
        }

        -- 星级效果描述
        if viewDef and viewDef.starEffect then
            local starVal = RelicCalc.FormatStarValue(viewRelic.star, viewDef.starEffect)
            local starDesc = viewDef.starEffect.desc:gsub("{v}", function() return starVal end)
            descChildren[#descChildren + 1] = UI.Label {
                text = starDesc,
                fontSize = 11, fontColor = { 255, 220, 100 },
                marginTop = 4,
            }
        end

        -- 右侧：按钮列
        local btnChildren = {}
        local upgradeCost = RelicCalc.GetUpgradeCost(viewRelic.level)
        local essence = HeroData.currencies.relic_essence or 0
        local canUpgrade = isViewOwned and essence >= upgradeCost
        local starCost = RelicCalc.GetStarUpShardCost(viewRelic.star)
        local shards = RelicData.GetShards(viewId)
        local canStarUp = isViewOwned and shards >= starCost

        if isViewOwned then
            -- 升级
            btnChildren[#btnChildren + 1] = UI.Panel {
                width = "100%",
                paddingTop = 7, paddingBottom = 7,
                borderRadius = 8, overflow = "visible",
                backgroundColor = canUpgrade and { 60, 140, 100, 240 } or { 60, 55, 50, 200 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    if not canUpgrade then ShowToast("遗物精华不足") return end
                    local ok, msg = RelicData.UpgradeByRelicId(viewId)
                    ShowToast(msg)
                    if ctx._refreshTab then ctx._refreshTab() else ctx.ShowHeroDetail(heroId) end
                end,
                children = {
                    UI.Label { text = "升级", fontSize = 12, fontColor = canUpgrade and { 255, 255, 255 } or { 120, 110, 100 }, fontWeight = "bold" },
                    UI.Label { text = FormatBigNum(upgradeCost) .. "精华", fontSize = 9, numberOfLines = 1, fontColor = canUpgrade and { 200, 240, 200 } or { 100, 90, 80 } },
                },
            }
            -- 升星
            btnChildren[#btnChildren + 1] = UI.Panel {
                width = "100%",
                paddingTop = 7, paddingBottom = 7,
                borderRadius = 8, overflow = "visible",
                backgroundColor = canStarUp and { 180, 140, 40, 240 } or { 60, 55, 50, 200 },
                justifyContent = "center", alignItems = "center",
                onClick = function(self)
                    if not canStarUp then ShowToast("碎片不足") return end
                    local ok, msg = RelicData.StarUpByRelicId(viewId)
                    ShowToast(msg)
                    if ctx._refreshTab then ctx._refreshTab() else ctx.ShowHeroDetail(heroId) end
                end,
                children = {
                    UI.Label { text = "升星", fontSize = 12, fontColor = canStarUp and { 255, 255, 255 } or { 120, 110, 100 }, fontWeight = "bold" },
                    UI.Label { text = FormatBigNum(shards) .. "/" .. FormatBigNum(starCost) .. "碎片", fontSize = 9, numberOfLines = 1, fontColor = canStarUp and { 255, 240, 180 } or { 100, 90, 80 } },
                },
            }
            -- 卸下 / 装备
            if isViewingEquipped then
                btnChildren[#btnChildren + 1] = UI.Panel {
                    width = "100%",
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 8,
                    backgroundColor = { 120, 50, 50, 220 },
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        RelicData.Unequip(selectedRelicSlot)
                        state.setView(nil)
                        ShowToast("已卸下")
                        ctx.ShowHeroDetail(heroId)
                    end,
                    children = {
                        UI.Label { text = "卸下", fontSize = 11, fontColor = { 255, 180, 160 } },
                    },
                }
            else
                btnChildren[#btnChildren + 1] = UI.Panel {
                    width = "100%",
                    paddingTop = 6, paddingBottom = 6,
                    borderRadius = 8,
                    backgroundColor = { 60, 140, 100, 240 },
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        local ok, msg = RelicData.Equip(selectedRelicSlot, viewId, viewQuality)
                        if ok then
                            state.setView({ id = viewId, quality = viewQuality })
                            ShowToast((viewDef and viewDef.name or viewId) .. " 装备成功")
                        else
                            ShowToast(msg)
                        end
                        ctx.ShowHeroDetail(heroId)
                    end,
                    children = {
                        UI.Label { text = "装备", fontSize = 11, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
                    },
                }
            end
        end -- if isViewOwned

        local btnCol = UI.Panel {
            width = 72, gap = 5,
            justifyContent = "center",
            children = btnChildren,
        }

        children[#children + 1] = UI.Panel {
            width = "100%", marginTop = 8,
            paddingTop = 10, paddingBottom = 10,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = { 45, 34, 24, 230 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = qColor,
            flexDirection = "row", gap = 10,
            children = {
                UI.Panel {
                    flex = 1, gap = 2,
                    children = descChildren,
                },
                btnCol,
            },
        }
    else
        children[#children + 1] = UI.Panel {
            width = "100%", marginTop = 8,
            paddingTop = 16, paddingBottom = 16,
            backgroundColor = { 45, 34, 24, 230 },
            borderRadius = 10,
            borderWidth = 1,
            borderColor = { 70, 55, 40, 150 },
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "点击下方遗物查看详情", fontSize = 12, fontColor = { 140, 120, 100 } },
            },
        }
    end

    -- ── Section 4: 遗物背包网格 ──────────────────────────────────────────────
    local slotRelics = Config.RELICS_BY_SLOT[selectedRelicSlot] or {}
    local sortedRelics = {}
    for _, rDef in ipairs(slotRelics) do sortedRelics[#sortedRelics + 1] = rDef end
    table.sort(sortedRelics, function(a, b)
        local aOwned = RelicData.IsOwned(a.id) and 1 or 0
        local bOwned = RelicData.IsOwned(b.id) and 1 or 0
        if aOwned ~= bOwned then return aOwned > bOwned end
        local aQ = Config.RELIC_QUALITY_INDEX[RelicData.GetOwnedQuality(a.id) or a.minQuality] or 1
        local bQ = Config.RELIC_QUALITY_INDEX[RelicData.GetOwnedQuality(b.id) or b.minQuality] or 1
        return aQ > bQ
    end)
    local catalogCells = {}
    for _, rDef in ipairs(sortedRelics) do
        local isOwned = RelicData.IsOwned(rDef.id)
        local ownedQuality = RelicData.GetOwnedQuality(rDef.id)
        local isEquipped = eqRelic and eqRelic.id == rDef.id
        local isViewing = selectedRelicView and selectedRelicView.id == rDef.id

        local displayQuality = ownedQuality or rDef.minQuality
        local cellQColor = isOwned and (Config.RELIC_QUALITY_COLOR[displayQuality] or { 180, 180, 180 }) or { 80, 70, 60 }

        local cellBorder, cellBg, cellBorderW
        if isViewing and isOwned then
            cellBorder = S.gold
            cellBg = { 65, 52, 30, 240 }
            cellBorderW = 2
        elseif isEquipped then
            cellBorder = { 100, 200, 100, 180 }
            cellBg = { 55, 48, 32, 230 }
            cellBorderW = 2
        elseif isOwned then
            cellBorder = { 70, 55, 40, 150 }
            cellBg = { 50, 38, 28, 200 }
            cellBorderW = 1
        else
            cellBorder = { 40, 35, 30, 120 }
            cellBg = { 30, 25, 20, 180 }
            cellBorderW = 1
        end

        local bottomLabel
        local cardLv, cardStar = RelicData.GetProgress(rDef.id)
        if isEquipped then
            bottomLabel = UI.Label { text = "Lv." .. cardLv .. " ★" .. cardStar, fontSize = 8, fontColor = { 100, 200, 100 }, fontWeight = "bold" }
        elseif isOwned then
            bottomLabel = UI.Label { text = "Lv." .. cardLv .. " ★" .. cardStar, fontSize = 8, fontColor = cellQColor }
        else
            local shardCount = RelicData.GetShards(rDef.id)
            local synthCost = Config.RELIC_SYNTH_COST[rDef.minQuality] or 80
            local shardColor = shardCount >= synthCost and { 100, 220, 100 } or { 120, 110, 90 }
            bottomLabel = UI.Label {
                text = "碎片 " .. shardCount .. "/" .. synthCost,
                fontSize = 8, fontColor = shardColor,
            }
        end

        catalogCells[#catalogCells + 1] = UI.Panel {
            width = "23%",
            aspectRatio = 1,
            margin = "1%",
            borderRadius = 8,
            borderWidth = cellBorderW,
            borderColor = cellBorder,
            backgroundColor = cellBg,
            overflow = "hidden",
            onClick = function(self)
                state.setView({ id = rDef.id, quality = ownedQuality or rDef.minQuality })
                ctx.ShowHeroDetail(heroId)
            end,
            children = {
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 2, paddingBottom = 1,
                    children = {
                        UI.Label { text = rDef.name, fontSize = 10, fontColor = cellQColor, fontWeight = isOwned and "bold" or "normal", textAlign = "center" },
                    },
                },
                UI.Panel {
                    flex = 1, aspectRatio = 1, alignSelf = "center",
                    backgroundImage = rDef.image or "", backgroundSize = "cover",
                    opacity = isOwned and 1.0 or 0.25,
                },
                UI.Panel {
                    width = "100%", alignItems = "center", paddingTop = 1, paddingBottom = 2,
                    children = { bottomLabel },
                },
            },
        }
    end

    -- ── Section 5: 底部货币栏 ────────────────────────────────────────────────
    local essenceAmt = HeroData.currencies.relic_essence or 0

    local currencyBar = UI.Panel {
        width = "100%", marginTop = 4,
        flexDirection = "row",
        justifyContent = "flex-end", alignItems = "center",
        paddingTop = 8, paddingBottom = 8, paddingRight = 12,
        backgroundColor = { 35, 26, 18, 200 },
        borderRadius = 8,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    Currency.IconWidget(UI, "relic_essence", 16),
                    UI.Label { text = FormatBigNum(essenceAmt), fontSize = 12, fontColor = { 255, 215, 100 } },
                },
            },
        },
    }

    -- ── 组装 ─────────────────────────────────────────────────────────────────
    local fixedTop = UI.Panel {
        width = "100%", gap = 4,
        flexShrink = 0,
        children = children,
    }

    local inventoryScroll = UI.ScrollView {
        flexGrow = 1, flexBasis = 0,
        scrollY = true,
        width = "100%",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%", gap = 2,
                paddingBottom = 6,
                children = {
                    UI.Label { text = "可用遗物", fontSize = 12, fontColor = S.gold, fontWeight = "bold", marginBottom = 2 },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        children = catalogCells,
                    },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%",
        minHeight = "100%",
        flexGrow = 1,
        gap = 4,
        children = {
            fixedTop,
            inventoryScroll,
            currencyBar,
        },
    }
end

-- ============================================================================
-- ShowRebirthConfirm
-- ============================================================================

local rebirthConfirmOverlay = nil

--- 显示重生确认弹窗
---@param ctx table
---@param heroId string
function RelicTab.ShowRebirthConfirm(ctx, heroId)
    if rebirthConfirmOverlay then return end
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local pageRoot = ctx.GetPageRoot()
    local FormatBigNum = ctx.FormatBigNum

    local refund = HeroData.CalcRebirthRefund(heroId)
    if not refund then
        ShowToast("该英雄无需重生")
        return
    end
    local heroDef = nil
    for _, def in ipairs(Config.TOWER_TYPES) do
        if def.id == heroId then heroDef = def; break end
    end
    local heroName = heroDef and heroDef.name or heroId

    local function closeConfirm()
        if rebirthConfirmOverlay and pageRoot then
            pageRoot:RemoveChild(rebirthConfirmOverlay)
            rebirthConfirmOverlay = nil
        end
    end

    local refundRows = {}
    if refund.nether_crystal > 0 then
        refundRows[#refundRows + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                Currency.IconWidget(UI, "nether_crystal", 18),
                UI.Label { text = "冥晶", fontSize = 14, fontColor = { 200, 180, 160 } },
                UI.Label { text = "+" .. FormatBigNum(refund.nether_crystal), fontSize = 14, fontColor = S.gold, fontWeight = "bold" },
            },
        }
    end
    if refund.forge_iron > 0 then
        refundRows[#refundRows + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                Currency.IconWidget(UI, "forge_iron", 18),
                UI.Label { text = "锻魂铁", fontSize = 14, fontColor = { 200, 180, 160 } },
                UI.Label { text = "+" .. FormatBigNum(refund.forge_iron), fontSize = 14, fontColor = { 140, 200, 255 }, fontWeight = "bold" },
            },
        }
    end
    if refund.devour_stone > 0 then
        refundRows[#refundRows + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = {
                Currency.IconWidget(UI, "devour_stone", 18),
                UI.Label { text = "噬魂石", fontSize = 14, fontColor = { 200, 180, 160 } },
                UI.Label { text = "+" .. FormatBigNum(refund.devour_stone), fontSize = 14, fontColor = { 180, 130, 255 }, fontWeight = "bold" },
            },
        }
    end

    local confirmPanel = UI.Panel {
        width = 260,
        backgroundColor = { 45, 32, 22, 250 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { 120, 50, 50, 200 },
        paddingTop = 16, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        alignItems = "center",
        gap = 10,
        children = {
            UI.Label { text = "确认重生", fontSize = 17, fontColor = { 255, 120, 100 }, fontWeight = "bold" },
            UI.Label { text = heroName .. " 将重置为1级", fontSize = 13, fontColor = { 200, 180, 160 } },
            UI.Label {
                text = (refund.lockedSlots and refund.lockedSlots > 0)
                    and "进阶重置，满级装备保留（" .. refund.lockedSlots .. "件）"
                    or  "装备、进阶也将全部重置",
                fontSize = 12,
                fontColor = (refund.lockedSlots and refund.lockedSlots > 0)
                    and { 100, 220, 140 }
                    or  { 180, 150, 130 },
            },
            UI.Panel { width = "90%", height = 1, backgroundColor = { 100, 75, 55, 100 } },
            UI.Label { text = "返还资源", fontSize = 13, fontColor = S.gold, fontWeight = "bold" },
            UI.Panel {
                alignItems = "center", gap = 6,
                children = refundRows,
            },
            UI.Panel { width = "90%", height = 1, backgroundColor = { 100, 75, 55, 100 } },
            UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 4,
                children = {
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = { 80, 60, 45, 220 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            closeConfirm()
                        end,
                        children = {
                            UI.Label { text = "取消", fontSize = 14, fontColor = { 200, 180, 160 } },
                        },
                    },
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = { 160, 50, 40, 240 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            local ok, msg = HeroData.Rebirth(heroId)
                            closeConfirm()
                            if ok then
                                ShowToast("重生成功！资源已返还")
                                ctx.ShowHeroDetail(heroId)
                                local DeployPopup = require("Game.HeroUI.DeployPopup")
                                DeployPopup.RefreshCollectionContent(ctx)
                                ctx.Refresh()
                            else
                                ShowToast(msg or "重生失败")
                            end
                        end,
                        children = {
                            UI.Label { text = "确认重生", fontSize = 14, fontColor = { 255, 240, 220 }, fontWeight = "bold" },
                        },
                    },
                },
            },
        },
    }

    rebirthConfirmOverlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            closeConfirm()
        end,
        children = { confirmPanel },
    }
    pageRoot:AddChild(rebirthConfirmOverlay)
end

return RelicTab
