-- RuneUI/Popups.lua
-- 弹窗：扩容背包 + 批量分解

local HeroData = require("Game.HeroData")
local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")
local Currency = require("Game.Currency")

local S = require("Game.RuneUI.State")

local M = {}

-- ── 浮层引用 ──
local expandBagOverlay = nil
local batchDecomposeOverlay = nil

-- 记住用户上次的品质选择（默认勾选白+绿）
local batchSelectedQualities = { white = true, green = true }

-- ============================================================================
-- 扩容背包弹窗
-- ============================================================================

---@param onDone function  操作完成回调 ("expand_bag")
function M.ShowExpandBag(onDone)
    if expandBagOverlay then return end

    local UI = S.UI
    local _, cap = RuneData.GetBagCapacity()
    local cost = RuneData.GetExpandCost()
    local amount = RuneConfig.BAG_EXPAND_AMOUNT
    local maxCap = RuneConfig.BAG_MAX_CAPACITY
    local dustOwned = Currency.Get("rift_dust")
    local canAfford = dustOwned >= cost

    local function closePanel()
        if expandBagOverlay and S.pageRoot then
            S.pageRoot:RemoveChild(expandBagOverlay)
            expandBagOverlay = nil
        end
    end

    expandBagOverlay = UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 80,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self) closePanel() end,
        children = {
            UI.Panel {
                width = 260,
                backgroundColor = { 35, 28, 55, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 120, 80, 200, 150 },
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 16, paddingRight = 16,
                gap = 10,
                onClick = function(self) end,
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "背包扩容",
                                fontSize = 17, fontColor = { 240, 220, 255 }, fontWeight = "bold",
                            },
                            UI.Button {
                                text = "✕", fontSize = 14, variant = "ghost",
                                width = 28, height = 28,
                                onClick = function(self) closePanel() end,
                            },
                        },
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 120, 80 } },
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "当前容量", fontSize = 13, fontColor = { 160, 150, 180 } },
                                    UI.Label { text = cap .. " / " .. maxCap, fontSize = 13, fontColor = { 220, 210, 240 } },
                                },
                            },
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "扩容数量", fontSize = 13, fontColor = { 160, 150, 180 } },
                                    UI.Label { text = "+" .. amount .. " 格", fontSize = 13, fontColor = { 100, 255, 100 } },
                                },
                            },
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                alignItems = "center",
                                children = {
                                    UI.Label { text = "消耗", fontSize = 13, fontColor = { 160, 150, 180 } },
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", gap = 4,
                                        children = {
                                            Currency.IconWidget(UI, "rift_dust", 16),
                                            UI.Label {
                                                text = cost .. "",
                                                fontSize = 13,
                                                fontColor = canAfford and { 220, 210, 240 } or { 255, 100, 80 },
                                            },
                                            UI.Label {
                                                text = "(拥有" .. dustOwned .. ")",
                                                fontSize = 10,
                                                fontColor = { 140, 130, 160, 180 },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 120, 80 } },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 12,
                        marginTop = 2,
                        children = {
                            UI.Button {
                                text = "取消", fontSize = 13, variant = "outline",
                                flex = 1, height = 36,
                                onClick = function(self) closePanel() end,
                            },
                            UI.Button {
                                text = "确认扩容", fontSize = 13,
                                variant = canAfford and "primary" or "outline",
                                flex = 1, height = 36,
                                disabled = not canAfford,
                                onClick = function(self)
                                    closePanel()
                                    local ok, msg = RuneData.ExpandBag()
                                    local Toast = require("Game.Toast")
                                    if ok then
                                        Toast.Show(msg, { 100, 255, 100 })
                                    else
                                        Toast.Show(msg, { 255, 200, 80 })
                                    end
                                    if onDone then onDone("expand_bag") end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    S.pageRoot:AddChild(expandBagOverlay)
end

-- ============================================================================
-- 批量分解 helpers
-- ============================================================================

local function _previewBatchDecompose(selections)
    local bag = RuneData.GetBag()
    local count = 0
    local gained = {}
    for _, rune in ipairs(bag) do
        if selections[rune.qualityId] and not rune.locked then
            count = count + 1
            local rewards = RuneConfig.DECOMPOSE[rune.qualityId] or {}
            for currId, amount in pairs(rewards) do
                gained[currId] = (gained[currId] or 0) + amount
            end
        end
    end
    return count, gained
end

local function _execBatchDecompose(selections)
    local bag = RuneData.GetBag()
    local totalGained = {}
    local count = 0
    local keep = {}

    for _, rune in ipairs(bag) do
        if selections[rune.qualityId] and not rune.locked then
            local rewards = RuneConfig.DECOMPOSE[rune.qualityId] or {}
            for currId, amount in pairs(rewards) do
                Currency.GrantReward({ type = "currency", id = currId, amount = amount }, "RuneBatchDecompose")
                totalGained[currId] = (totalGained[currId] or 0) + amount
            end
            count = count + 1
        else
            keep[#keep + 1] = rune
        end
    end

    if HeroData.runeData and HeroData.runeData.bag then
        HeroData.runeData.bag = keep
        if count > 0 then
            HeroData.Save()
        end
    end

    return count, totalGained
end

-- ============================================================================
-- 批量分解弹窗
-- ============================================================================

---@param onDone function  操作完成回调 ("batch_decompose")
function M.ShowBatchDecompose(onDone)
    if batchDecomposeOverlay then return end

    local UI = S.UI
    local selections = {}
    for k, v in pairs(batchSelectedQualities) do
        selections[k] = v
    end

    local function closeBatchPanel()
        if batchDecomposeOverlay and S.pageRoot then
            S.pageRoot:RemoveChild(batchDecomposeOverlay)
            batchDecomposeOverlay = nil
        end
    end

    local function buildContent()
        -- 品质勾选行
        local qualityRows = {}
        local maxBatchIndex = 5
        for i, q in ipairs(RuneConfig.QUALITIES) do
            if i > maxBatchIndex then break end
            local qid = q.id
            local checked = selections[qid] == true

            local qCount = 0
            for _, rune in ipairs(RuneData.GetBag()) do
                if rune.qualityId == qid and not rune.locked then
                    qCount = qCount + 1
                end
            end
            local lockedCount = 0
            for _, rune in ipairs(RuneData.GetBag()) do
                if rune.qualityId == qid and rune.locked then
                    lockedCount = lockedCount + 1
                end
            end

            qualityRows[#qualityRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingTop = 5, paddingBottom = 5,
                paddingLeft = 4, paddingRight = 4,
                id = "bdr_" .. qid,
                backgroundColor = checked and { q.color[1], q.color[2], q.color[3], 30 } or { 0, 0, 0, 0 },
                borderRadius = 6,
                onClick = function(self)
                    selections[qid] = not selections[qid]
                    M._refreshBatchPanel(selections)
                end,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Panel {
                                id = "bchk_" .. qid,
                                width = 20, height = 20,
                                borderRadius = 4,
                                borderWidth = 2,
                                borderColor = checked
                                    and { q.color[1], q.color[2], q.color[3], 255 }
                                    or { 100, 90, 130, 180 },
                                backgroundColor = checked
                                    and { q.color[1], q.color[2], q.color[3], 200 }
                                    or { 30, 25, 50, 180 },
                                justifyContent = "center", alignItems = "center",
                                pointerEvents = "none",
                                children = {
                                    UI.Label {
                                        id = "bmk_" .. qid,
                                        text = "✓", fontSize = 13,
                                        fontColor = { 255, 255, 255, 255 }, fontWeight = "bold",
                                        pointerEvents = "none",
                                        visible = checked,
                                    },
                                },
                            },
                            UI.Label {
                                text = q.name,
                                fontSize = 14, fontColor = q.color, fontWeight = "bold",
                                pointerEvents = "none",
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        pointerEvents = "none",
                        children = {
                            UI.Label {
                                text = qCount .. "个可分解",
                                fontSize = 11,
                                fontColor = qCount > 0 and { 180, 170, 200, 220 } or { 100, 90, 130, 120 },
                                pointerEvents = "none",
                            },
                            lockedCount > 0 and UI.Label {
                                text = "🔒" .. lockedCount,
                                fontSize = 10, fontColor = { 255, 200, 80, 180 },
                                pointerEvents = "none",
                            } or nil,
                        },
                    },
                },
            }
        end

        -- 预览统计
        local previewCount, previewGained = _previewBatchDecompose(selections)
        local LOOT_ORDER = { "rift_dust", "rune_seal", "abyss_crystal" }
        local lootChildren = {}
        for _, currId in ipairs(LOOT_ORDER) do
            local amount = previewGained[currId] or 0
            local info = RuneConfig.CURRENCIES[currId]
            local hasValue = amount > 0
            lootChildren[#lootChildren + 1] = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    Currency.IconWidget(UI, currId, 16),
                    UI.Label {
                        id = "bl_" .. currId,
                        text = (info and info.name or currId) .. " +" .. amount,
                        fontSize = 13,
                        fontColor = hasValue and { 220, 210, 200 } or { 100, 90, 130, 120 },
                    },
                },
            }
        end

        return UI.Panel {
            width = 280,
            backgroundColor = { 35, 28, 55, 250 },
            borderRadius = 12,
            borderWidth = 1,
            borderColor = { 120, 80, 200, 150 },
            paddingTop = 14, paddingBottom = 14,
            paddingLeft = 14, paddingRight = 14,
            gap = 8,
            onClick = function(self) end,
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "批量分解",
                            fontSize = 17, fontColor = { 240, 220, 255 }, fontWeight = "bold",
                        },
                        UI.Button {
                            text = "✕", fontSize = 14, variant = "ghost",
                            width = 28, height = 28,
                            onClick = function(self) closeBatchPanel() end,
                        },
                    },
                },
                UI.Label {
                    text = "选择要分解的品质（已锁定符文不会被分解）",
                    fontSize = 11, fontColor = { 150, 140, 170, 200 },
                },
                UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 120, 80 } },
                UI.Panel {
                    width = "100%",
                    gap = 2,
                    children = qualityRows,
                },
                UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 120, 80 } },
                UI.Panel {
                    width = "100%",
                    alignItems = "center",
                    gap = 4,
                    children = {
                        UI.Label {
                            id = "bps",
                            text = previewCount > 0
                                and ("将分解 " .. previewCount .. " 个符文，获得：")
                                or "选择品质后预览分解收益",
                            fontSize = 12,
                            fontColor = previewCount > 0 and { 200, 190, 220 } or { 130, 120, 150, 180 },
                        },
                        UI.Panel { alignItems = "center", gap = 3, children = lootChildren },
                    },
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    gap = 12,
                    marginTop = 4,
                    children = {
                        UI.Button {
                            text = "取消", fontSize = 13, variant = "outline",
                            flex = 1, height = 36,
                            onClick = function(self) closeBatchPanel() end,
                        },
                        UI.Button {
                            id = "bcfm",
                            text = "确认分解", fontSize = 13,
                            variant = previewCount > 0 and "primary" or "outline",
                            flex = 1, height = 36,
                            disabled = previewCount == 0,
                            onClick = function(self)
                                local curCount = _previewBatchDecompose(selections)
                                if curCount == 0 then return end

                                for k, v in pairs(selections) do
                                    batchSelectedQualities[k] = v
                                end
                                closeBatchPanel()

                                local count, gained = _execBatchDecompose(selections)
                                local Toast = require("Game.Toast")
                                if count > 0 then
                                    local parts = {}
                                    for currId, amount in pairs(gained) do
                                        local info = RuneConfig.CURRENCIES[currId]
                                        parts[#parts + 1] = (info and info.name or currId) .. "×" .. amount
                                    end
                                    Toast.Show("分解" .. count .. "个，获得 " .. table.concat(parts, " "), { 100, 255, 100 })
                                else
                                    Toast.Show("没有可分解的符文", { 255, 200, 80 })
                                end
                                if onDone then onDone("batch_decompose") end
                            end,
                        },
                    },
                },
            },
        }
    end

    batchDecomposeOverlay = UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 80,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self) closeBatchPanel() end,
        children = { buildContent() },
    }
    S.pageRoot:AddChild(batchDecomposeOverlay)
end

-- ============================================================================
-- 增量刷新批量分解面板（品质切换时调用，不重建 UI 树）
-- ============================================================================

function M._refreshBatchPanel(selections)
    if not batchDecomposeOverlay then return end

    for k, v in pairs(selections) do
        batchSelectedQualities[k] = v
    end

    local maxBatchIndex = 5
    for i, q in ipairs(RuneConfig.QUALITIES) do
        if i > maxBatchIndex then break end
        local qid = q.id
        local checked = selections[qid] == true

        local row = batchDecomposeOverlay:FindById("bdr_" .. qid)
        if row then
            row:SetStyle({
                backgroundColor = checked
                    and { q.color[1], q.color[2], q.color[3], 30 }
                    or { 0, 0, 0, 0 },
            })
        end

        local chk = batchDecomposeOverlay:FindById("bchk_" .. qid)
        if chk then
            chk:SetStyle({
                borderColor = checked
                    and { q.color[1], q.color[2], q.color[3], 255 }
                    or { 100, 90, 130, 180 },
                backgroundColor = checked
                    and { q.color[1], q.color[2], q.color[3], 200 }
                    or { 30, 25, 50, 180 },
            })
        end

        local mark = batchDecomposeOverlay:FindById("bmk_" .. qid)
        if mark then mark:SetVisible(checked) end
    end

    local previewCount, previewGained = _previewBatchDecompose(selections)

    local summaryLabel = batchDecomposeOverlay:FindById("bps")
    if summaryLabel then
        summaryLabel:SetText(
            previewCount > 0
                and ("将分解 " .. previewCount .. " 个符文，获得：")
                or "选择品质后预览分解收益"
        )
        summaryLabel:SetFontColor(
            previewCount > 0 and { 200, 190, 220 } or { 130, 120, 150, 180 }
        )
    end

    local LOOT_ORDER = { "rift_dust", "rune_seal", "abyss_crystal" }
    for _, currId in ipairs(LOOT_ORDER) do
        local amount = previewGained[currId] or 0
        local info = RuneConfig.CURRENCIES[currId]
        local lbl = batchDecomposeOverlay:FindById("bl_" .. currId)
        if lbl then
            lbl:SetText((info and info.name or currId) .. " +" .. amount)
            lbl:SetFontColor(amount > 0 and { 220, 210, 200 } or { 100, 90, 130, 120 })
        end
    end

    local btn = batchDecomposeOverlay:FindById("bcfm")
    if btn then btn:SetDisabled(previewCount == 0) end
end

return M
