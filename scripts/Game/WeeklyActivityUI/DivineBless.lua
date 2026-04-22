-- Game/WeeklyActivityUI/DivineBless.lua
-- 神裔降临：每日 3 选 1 神裔加成，周末磐古自动降临

local DivineBlessDB = require("Game.DivineBlessData")
local Toast         = require("Game.Toast")

local DivineBless = {}

-- 缓存 ctx 供 local 函数使用（Build 入口设置）
local _ctx = nil

-- 确认弹窗状态
local _divineConfirmOverlay = nil  ---@type any
local _divineConfirmEntry   = nil  ---@type DivineEntry
local _divineConfirmIndex   = nil  ---@type number

-- ============================================================================
-- 确认弹窗
-- ============================================================================

local function HideDivineConfirm()
    if _divineConfirmOverlay then
        _divineConfirmOverlay:SetVisible(false)
        local pageRoot = _ctx and _ctx.GetPageRoot() or nil
        if pageRoot then pcall(function() pageRoot:RemoveChild(_divineConfirmOverlay) end) end
        _divineConfirmOverlay = nil
    end
    _divineConfirmEntry = nil
    _divineConfirmIndex = nil
end

local function DoDivineConfirm()
    if not _divineConfirmEntry or not _divineConfirmIndex then return end
    local entry = _divineConfirmEntry
    local c = entry.color
    local ok, msg = DivineBlessDB.Choose(_divineConfirmIndex)
    if ok then
        Toast.Show(msg, { c[1], c[2], c[3], 255 })
        local tok, Tower = pcall(require, "Game.Tower")
        if tok then Tower.RefreshAllStats() end
    else
        Toast.Show(msg, { 255, 100, 100 })
    end
    HideDivineConfirm()
    if _ctx then _ctx.Refresh() end
end

local function ShowDivineConfirm(entry, index)
    local UI       = _ctx.GetUI()
    local pageRoot = _ctx.GetPageRoot()

    _divineConfirmEntry = entry
    _divineConfirmIndex = index
    local c = entry.color
    local themeColor = { c[1], c[2], c[3], 255 }

    if _divineConfirmOverlay then
        local nameEl = _divineConfirmOverlay:FindById("dcDivineName")
        local descEl = _divineConfirmOverlay:FindById("dcDivineDesc")
        local iconEl = _divineConfirmOverlay:FindById("dcDivineIcon")
        if nameEl then nameEl:SetText(entry.name .. " · " .. entry.title) end
        if descEl then descEl:SetText(entry.desc) end
        if iconEl then iconEl:SetText(entry.domain:sub(1, 3) or "?") end
        _divineConfirmOverlay:SetVisible(true)
        return
    end

    _divineConfirmOverlay = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        zIndex = 100,
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() HideDivineConfirm() end,
        children = {
            UI.Panel {
                width = "80%",
                paddingTop = 22, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                backgroundColor = { 32, 26, 50, 252 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 90, 78, 120, 180 },
                gap = 14,
                alignItems = "center",
                onClick = function() end,  -- 阻止点击穿透
                children = {
                    UI.Label {
                        text = "确认选择祝福",
                        fontSize = 16,
                        fontColor = { 230, 225, 245, 255 },
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 110, 120 },
                    },
                    -- 神裔图标
                    UI.Panel {
                        width = 52, height = 52,
                        borderRadius = 26,
                        backgroundColor = { c[1], c[2], c[3], 35 },
                        borderWidth = 2,
                        borderColor = themeColor,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "dcDivineIcon",
                                text = entry.domain:sub(1, 3) or "?",
                                fontSize = 20,
                                fontColor = themeColor,
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        id = "dcDivineName",
                        text = entry.name .. " · " .. entry.title,
                        fontSize = 18,
                        fontColor = themeColor,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        id = "dcDivineDesc",
                        text = entry.desc,
                        fontSize = 14,
                        fontColor = { 140, 255, 190, 230 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "选择后今日不可更改",
                        fontSize = 11,
                        fontColor = { 255, 180, 80, 200 },
                    },
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                paddingTop = 10, paddingBottom = 10,
                                alignItems = "center",
                                backgroundColor = { 45, 40, 62, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 75, 68, 98, 160 },
                                onClick = function() HideDivineConfirm() end,
                                children = {
                                    UI.Label {
                                        text = "取消",
                                        fontSize = 13,
                                        fontColor = { 170, 160, 190, 230 },
                                    },
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                paddingTop = 10, paddingBottom = 10,
                                alignItems = "center",
                                backgroundColor = { c[1], c[2], c[3], 200 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { c[1], c[2], c[3], 240 },
                                onClick = function() DoDivineConfirm() end,
                                children = {
                                    UI.Label {
                                        text = "确认",
                                        fontSize = 13,
                                        fontColor = { 255, 255, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    if pageRoot then
        pageRoot:AddChild(_divineConfirmOverlay)
    end
end

-- ============================================================================
-- 神裔卡片
-- ============================================================================

---@param entry DivineEntry
---@param index number
---@param isActive boolean
---@param isWeekend boolean
---@param hasChosen boolean
local function _CreateDivineCard(entry, index, isActive, isWeekend, hasChosen)
    local UI = _ctx.GetUI()
    local S  = _ctx.GetS()

    local c = entry.color
    local themeColor  = { c[1], c[2], c[3], 255 }
    local themeBg     = { c[1], c[2], c[3], isActive and 35 or 15 }
    local themeBorder = { c[1], c[2], c[3], isActive and 200 or 80 }

    local btnText, btnBg, btnColor, btnEnabled
    if isActive then
        btnText = "降临中"
        btnBg = { c[1], c[2], c[3], 60 }
        btnColor = themeColor
        btnEnabled = false
    elseif isWeekend then
        btnText = "自动降临"
        btnBg = { 60, 60, 60, 200 }
        btnColor = S.textDim
        btnEnabled = false
    elseif hasChosen then
        btnText = "今日已选"
        btnBg = { 60, 60, 60, 200 }
        btnColor = S.textDim
        btnEnabled = false
    else
        btnText = "选择祝福"
        btnBg = { c[1], c[2], c[3], 180 }
        btnColor = { 255, 255, 255, 255 }
        btnEnabled = true
    end

    return UI.Panel {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        backgroundColor = themeBg,
        borderRadius = 12,
        borderWidth = isActive and 2 or 1,
        borderColor = themeBorder,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = "100%", height = 3,
                backgroundColor = themeColor,
            },
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                paddingTop = 14, paddingBottom = 12,
                paddingLeft = 10, paddingRight = 10,
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Panel {
                        width = 44, height = 44,
                        borderRadius = 22,
                        backgroundColor = { c[1], c[2], c[3], isActive and 50 or 25 },
                        borderWidth = 2,
                        borderColor = themeBorder,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = entry.domain:sub(1, 3) or "?",
                                fontSize = 16,
                                fontColor = themeColor,
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        text = entry.name,
                        fontSize = 15,
                        fontColor = themeColor,
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                    UI.Label {
                        text = entry.title,
                        fontSize = 11,
                        fontColor = { c[1], c[2], c[3], 160 },
                        textAlign = "center",
                    },
                    UI.Panel {
                        width = "80%", height = 1,
                        backgroundColor = { c[1], c[2], c[3], 40 },
                    },
                    UI.Panel {
                        width = "100%",
                        paddingLeft = 4, paddingRight = 4,
                        paddingTop = 4, paddingBottom = 4,
                        backgroundColor = { c[1], c[2], c[3], isActive and 25 or 10 },
                        borderRadius = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = entry.desc,
                                fontSize = 12,
                                fontColor = isActive and { 255, 255, 255, 255 } or S.textNormal,
                                fontWeight = "bold",
                                textAlign = "center",
                            },
                        },
                    },
                    UI.Label {
                        text = entry.lore,
                        fontSize = 10,
                        fontColor = S.textDim,
                        textAlign = "center",
                        flexWrap = "wrap",
                    },
                    UI.Panel {
                        width = "100%",
                        marginTop = "auto",
                        paddingTop = 6,
                        alignItems = "center",
                        children = {
                            UI.Button {
                                text = btnText,
                                fontSize = 13,
                                fontWeight = "bold",
                                fontColor = btnColor,
                                backgroundColor = btnBg,
                                borderRadius = 8,
                                paddingLeft = 16, paddingRight = 16,
                                paddingTop = 6, paddingBottom = 6,
                                disabled = not btnEnabled,
                                onClick = btnEnabled and function()
                                    ShowDivineConfirm(entry, index)
                                end or nil,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 入口
-- ============================================================================

function DivineBless.Build(ctx)
    _ctx = ctx
    local UI = ctx.GetUI()
    local S  = ctx.GetS()

    local isWeekend = DivineBlessDB.IsWeekend()
    local hasChosen = DivineBlessDB.HasChosen()
    local active    = DivineBlessDB.GetActiveBlessing()
    local options   = DivineBlessDB.GetTodayOptions()

    local wdayNames = { "周日","周一","周二","周三","周四","周五","周六" }
    local todayName = wdayNames[os.date("*t").wday]

    local container = UI.Panel { width = "100%", gap = 10 }

    -- ── 状态横幅 ─────────────────────────────────────────────────
    local statusText, statusSub
    if isWeekend then
        statusText = "磐古降临中"
        statusSub = "今日 " .. todayName .. " · 冥晶收益 ×1.5 自动生效"
    elseif active then
        statusText = active.name .. " 降临中"
        statusSub = "今日 " .. todayName .. " · " .. active.desc .. " 已生效"
    else
        statusText = "今日神裔待选"
        statusSub = "今日 " .. todayName .. " · 选择一位初裔神获得全天加成"
    end

    local hasActive = (active ~= nil)
    container:AddChild(UI.Panel {
        width  = "100%",
        backgroundColor = hasActive and { 32, 12, 62, 255 } or S.bgSection,
        borderRadius = 10,
        borderWidth  = 1,
        borderColor  = hasActive and { 150, 70, 240, 180 } or S.border,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = "100%", height = 3,
                backgroundColor = hasActive
                    and { active.color[1], active.color[2], active.color[3], 255 }
                    or { 80, 70, 110, 200 },
            },
            UI.Panel {
                width = "100%",
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 14, paddingRight = 14,
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = statusText,
                        fontSize = 20,
                        fontColor = hasActive
                            and { active.color[1], active.color[2], active.color[3], 255 }
                            or S.textDim,
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                    UI.Label {
                        text = statusSub,
                        fontSize = 12,
                        fontColor = hasActive and { 140, 255, 190, 210 } or S.textDim,
                        textAlign = "center",
                    },
                },
            },
        },
    })

    -- ── 神裔选择卡片（横排 3 列） ───────────────────────────────
    local cardChildren = {}
    for i, entry in ipairs(options) do
        local isThisActive = (active ~= nil and active.id == entry.id)
        cardChildren[#cardChildren + 1] = _CreateDivineCard(entry, i, isThisActive, isWeekend, hasChosen)
    end

    container:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        children = cardChildren,
    })

    -- ── 当前生效加成卡片 ──────────────────────────────────────
    if active then
        local ac = active.color
        container:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = { ac[1], ac[2], ac[3], 20 },
            borderRadius = 10,
            borderWidth  = 1,
            borderColor  = { ac[1], ac[2], ac[3], 120 },
            paddingTop = 12, paddingBottom = 12,
            paddingLeft = 14, paddingRight = 14,
            flexDirection = "row",
            alignItems = "center",
            gap = 12,
            children = {
                UI.Panel {
                    width = 44, height = 44,
                    borderRadius = 22,
                    backgroundColor = { ac[1], ac[2], ac[3], 40 },
                    borderWidth = 2,
                    borderColor = { ac[1], ac[2], ac[3], 160 },
                    justifyContent = "center",
                    alignItems = "center",
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = active.domain:sub(1, 3) or "?",
                            fontSize = 18,
                            fontColor = { ac[1], ac[2], ac[3], 255 },
                            fontWeight = "bold",
                        },
                    },
                },
                UI.Panel {
                    flexGrow = 1, gap = 3,
                    children = {
                        UI.Label {
                            text = active.name .. " · " .. active.title,
                            fontSize = 14,
                            fontColor = { ac[1], ac[2], ac[3], 255 },
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = active.desc .. "（今日全天生效）",
                            fontSize = 12,
                            fontColor = S.textNormal,
                        },
                    },
                },
                UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 3, paddingBottom = 3,
                    backgroundColor = { ac[1], ac[2], ac[3], 50 },
                    borderRadius = 8,
                    flexShrink = 0,
                    children = {
                        UI.Label {
                            text = "生效中",
                            fontSize = 11,
                            fontColor = S.textGreen,
                            fontWeight = "bold",
                        },
                    },
                },
            },
        })
    end

    -- ── 活动规则 ─────────────────────────────────────────────────
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = S.bgSection,
        borderRadius = 10,
        borderWidth  = 1,
        borderColor  = S.border,
        paddingTop   = 12, paddingBottom = 12,
        paddingLeft  = 14, paddingRight  = 14,
        gap = 8,
        children = {
            UI.Label {
                text = "| 活动规则",
                fontSize = 15,
                fontColor = S.textTitle,
                fontWeight = "bold",
            },
            UI.Label { text = "· 周一至周五：每日随机降临 3 位初裔神，可选择 1 位获得全天加成", fontSize = 12, fontColor = S.textDim },
            UI.Label { text = "· 周六、周日：土嗣·磐古自动降临，冥晶收益 ×1.5", fontSize = 12, fontColor = S.textDim },
            UI.Label { text = "· 每日 00:00 刷新，选择后当日不可更改", fontSize = 12, fontColor = S.textDim },
            UI.Label { text = "· 加成效果与特权、装备等增益叠加计算", fontSize = 12, fontColor = S.textDim },
        },
    })

    return container
end

return DivineBless
