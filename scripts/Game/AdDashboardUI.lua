-- Game/AdDashboardUI.lua
-- 管理员广告统计面板 —— 按 F 键打开，仅对指定管理员可见
-- 从云排行榜拉取全服玩家广告数据，按用户横向展示：
--   昵称 | 累计 | 今日发起 | 今日完成 | 今日取消 | 成功率
-- 无 UI 入口，仅管理员按 F 键可用

local AdDashboardUI = {}

---@type any
local UI = nil

-- 管理员 ID 白名单
local ADMIN_IDS = { [1779057459] = true }

-- 每个排行榜最多拉取条数
local MAX_PER_SECTION = 30

-- 排行榜 key 定义
local function GetKeys()
    local today = os.date("%Y%m%d")
    return {
        total  = "ad_total",
        start  = "ad_start_"  .. today,
        done   = "ad_done_"   .. today,
        cancel = "ad_cancel_" .. today,
    }
end

-- 配色
local C = {
    bg           = { 0, 0, 0, 200 },
    cardBg       = { 18, 14, 30, 245 },
    cardBorder   = { 80, 160, 220, 180 },
    headerBg     = { 25, 40, 65, 255 },
    colHeaderBg  = { 30, 25, 50, 255 },
    rowBg        = { 28, 22, 45, 220 },
    rowAlt       = { 35, 28, 55, 220 },
    title        = { 100, 200, 255, 255 },
    white        = { 245, 238, 225, 255 },
    dim          = { 150, 140, 160, 200 },
    green        = { 120, 220, 100, 255 },
    gold         = { 255, 215, 80, 255 },
    silver       = { 200, 200, 220, 255 },
    bronze       = { 200, 150, 80, 255 },
    red          = { 255, 100, 80, 255 },
    cyan         = { 80, 200, 230, 255 },
}

-- ============================================================================
-- 权限
-- ============================================================================

---@return boolean
function AdDashboardUI.IsAdmin()
    ---@diagnostic disable-next-line: undefined-global
    local uid = clientCloud and clientCloud.userId
    if not uid then return false end
    return ADMIN_IDS[uid] == true
end

-- ============================================================================
-- 聚合数据存储
-- ============================================================================

-- { userId -> { total=0, start=0, done=0, cancel=0, nickname=nil } }
local mergedData = {}
local loadedCount = 0
local totalKeys = 4  -- total, start, done, cancel

local function ResetMergedData()
    mergedData = {}
    loadedCount = 0
end

local function EnsureUser(uid)
    if not mergedData[uid] then
        mergedData[uid] = { total = 0, start = 0, done = 0, cancel = 0, nickname = nil }
    end
    return mergedData[uid]
end

-- ============================================================================
-- 排名行组件（横向表格行）
-- ============================================================================

local COL_RANK  = 28
local COL_NAME  = 0  -- flex=1
local COL_TOTAL = 52
local COL_START = 52
local COL_DONE  = 52
local COL_CANCEL = 52
local COL_RATE  = 56

local function BuildHeaderRow()
    local function HeaderCell(text, w, extra)
        local props = {
            width = w > 0 and w or nil,
            flex = w == 0 and 1 or nil,
            alignItems = w == 0 and "flex-start" or "center",
            justifyContent = "center",
            paddingLeft = w == 0 and 4 or 0,
            children = {
                UI.Label {
                    text = text,
                    fontSize = 10,
                    fontWeight = "bold",
                    fontColor = C.dim,
                    pointerEvents = "none",
                },
            },
        }
        if extra then
            for k, v in pairs(extra) do props[k] = v end
        end
        return UI.Panel(props)
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 6, paddingRight = 6,
        paddingTop = 6, paddingBottom = 4,
        backgroundColor = C.colHeaderBg,
        gap = 2,
        children = {
            HeaderCell("#",     COL_RANK),
            HeaderCell("用户",   COL_NAME),
            HeaderCell("累计",   COL_TOTAL),
            HeaderCell("发起",   COL_START),
            HeaderCell("完成",   COL_DONE),
            HeaderCell("取消",   COL_CANCEL),
            HeaderCell("成功率", COL_RATE),
        },
    }
end

local function BuildDataRow(entry, index)
    local rank = index
    local rankColor = C.white
    local rankText = tostring(rank)
    if rank == 1 then rankColor = C.gold;   rankText = "🥇"
    elseif rank == 2 then rankColor = C.silver; rankText = "🥈"
    elseif rank == 3 then rankColor = C.bronze; rankText = "🥉"
    end

    local nickname = entry.nickname or ("ID:" .. tostring(entry.userId or "?"))
    if #nickname > 16 then nickname = string.sub(nickname, 1, 16) .. "…" end

    -- 成功率 = done / start，start==0 时显示 "-"
    local rateText = "-"
    local rateColor = C.dim
    if entry.start > 0 then
        local rate = entry.done / entry.start * 100
        rateText = string.format("%.0f%%", rate)
        if rate >= 80 then rateColor = C.green
        elseif rate >= 50 then rateColor = C.gold
        else rateColor = C.red end
    end

    local function DataCell(text, w, color)
        return UI.Panel {
            width = w > 0 and w or nil,
            flex = w == 0 and 1 or nil,
            alignItems = w == 0 and "flex-start" or "center",
            justifyContent = "center",
            paddingLeft = w == 0 and 4 or 0,
            children = {
                UI.Label {
                    text = text,
                    fontSize = 11,
                    fontColor = color or C.white,
                    pointerEvents = "none",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 6, paddingRight = 6,
        paddingTop = 4, paddingBottom = 4,
        backgroundColor = index % 2 == 0 and C.rowAlt or C.rowBg,
        gap = 2,
        children = {
            -- 排名
            UI.Panel {
                width = COL_RANK,
                alignItems = "center",
                justifyContent = "center",
                children = {
                    UI.Label {
                        text = rankText,
                        fontSize = rank <= 3 and 14 or 11,
                        fontWeight = rank <= 3 and "bold" or "normal",
                        fontColor = rankColor,
                        pointerEvents = "none",
                    },
                },
            },
            -- 昵称
            DataCell(nickname, COL_NAME, C.white),
            -- 累计
            DataCell(tostring(entry.total), COL_TOTAL, C.cyan),
            -- 发起
            DataCell(tostring(entry.start), COL_START, C.white),
            -- 完成
            DataCell(tostring(entry.done),  COL_DONE,  C.green),
            -- 取消
            DataCell(tostring(entry.cancel), COL_CANCEL, entry.cancel > 0 and C.red or C.dim),
            -- 成功率
            DataCell(rateText, COL_RATE, rateColor),
        },
    }
end

-- ============================================================================
-- 汇总行
-- ============================================================================

local function BuildSummaryRow(entries)
    local sumTotal, sumStart, sumDone, sumCancel = 0, 0, 0, 0
    for _, e in ipairs(entries) do
        sumTotal  = sumTotal  + e.total
        sumStart  = sumStart  + e.start
        sumDone   = sumDone   + e.done
        sumCancel = sumCancel + e.cancel
    end
    local rateText = "-"
    local rateColor = C.dim
    if sumStart > 0 then
        local rate = sumDone / sumStart * 100
        rateText = string.format("%.0f%%", rate)
        if rate >= 80 then rateColor = C.green
        elseif rate >= 50 then rateColor = C.gold
        else rateColor = C.red end
    end

    local function SumCell(text, w, color)
        return UI.Panel {
            width = w > 0 and w or nil,
            flex = w == 0 and 1 or nil,
            alignItems = w == 0 and "flex-start" or "center",
            justifyContent = "center",
            paddingLeft = w == 0 and 4 or 0,
            children = {
                UI.Label {
                    text = text,
                    fontSize = 11,
                    fontWeight = "bold",
                    fontColor = color or C.white,
                    pointerEvents = "none",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 6, paddingRight = 6,
        paddingTop = 6, paddingBottom = 6,
        backgroundColor = { 40, 50, 30, 240 },
        borderTop = 1,
        borderColor = C.green,
        gap = 2,
        children = {
            SumCell("",          COL_RANK, C.dim),
            SumCell("合计 (" .. #entries .. "人)", COL_NAME, C.green),
            SumCell(tostring(sumTotal),  COL_TOTAL,  C.cyan),
            SumCell(tostring(sumStart),  COL_START,  C.white),
            SumCell(tostring(sumDone),   COL_DONE,   C.green),
            SumCell(tostring(sumCancel), COL_CANCEL, sumCancel > 0 and C.red or C.dim),
            SumCell(rateText,            COL_RATE,   rateColor),
        },
    }
end

-- ============================================================================
-- 数据加载（4个排行榜并行加载，全部完成后聚合渲染）
-- ============================================================================

local function LoadKey(lbKey, field)
    ---@diagnostic disable-next-line: undefined-global
    if not clientCloud then return end

    ---@diagnostic disable-next-line: undefined-global
    clientCloud:GetRankList(lbKey, 0, MAX_PER_SECTION, {
        ok = function(list)
            if list then
                for _, item in ipairs(list) do
                    local uid = item.userId or item.player
                    local scoreVal = 0
                    if item.iscore then
                        local v = item.iscore[lbKey]
                        if v and type(v) == "number" then scoreVal = v end
                    end
                    local u = EnsureUser(uid)
                    u[field] = scoreVal
                end
            end
            loadedCount = loadedCount + 1
            if loadedCount >= totalKeys then
                AdDashboardUI._ResolveNicknamesAndRender()
            end
        end,
        error = function()
            loadedCount = loadedCount + 1
            if loadedCount >= totalKeys then
                AdDashboardUI._ResolveNicknamesAndRender()
            end
        end,
    }, lbKey)
end

function AdDashboardUI._ResolveNicknamesAndRender()
    -- 收集所有 userId
    local userIds = {}
    for uid, _ in pairs(mergedData) do
        userIds[#userIds + 1] = uid
    end

    if #userIds > 0 then
        ---@diagnostic disable-next-line: undefined-global
        GetUserNickname({
            userIds = userIds,
            onSuccess = function(nicknames)
                for uid, data in pairs(mergedData) do
                    if nicknames[uid] then
                        data.nickname = nicknames[uid]
                    end
                end
                AdDashboardUI._RenderTable()
            end,
            onError = function()
                AdDashboardUI._RenderTable()
            end,
        })
    else
        AdDashboardUI._RenderTable()
    end
end

function AdDashboardUI._RenderTable()
    if not UI then return end
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local container = root:FindById("adTableBody")
    if not container then return end

    container:ClearChildren()

    -- 转为排序列表（按累计总观看降序）
    local entries = {}
    for uid, data in pairs(mergedData) do
        entries[#entries + 1] = {
            userId   = uid,
            nickname = data.nickname,
            total    = data.total,
            start    = data.start,
            done     = data.done,
            cancel   = data.cancel,
        }
    end
    table.sort(entries, function(a, b) return a.total > b.total end)

    if #entries == 0 then
        container:AddChild(UI.Panel {
            width = "100%", height = 40,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无数据",
                    fontSize = 12,
                    fontColor = C.dim,
                    pointerEvents = "none",
                },
            },
        })
        return
    end

    -- 数据行
    for i, entry in ipairs(entries) do
        container:AddChild(BuildDataRow(entry, i))
    end

    -- 汇总行（固定在滚动区外）
    local summaryContainer = root:FindById("adSummaryRow")
    if summaryContainer then
        summaryContainer:ClearChildren()
        summaryContainer:AddChild(BuildSummaryRow(entries))
    end
end

-- ============================================================================
-- 卡片构建
-- ============================================================================

function AdDashboardUI._BuildCard()
    return UI.Panel {
        width = 520, height = "85%",
        maxHeight = 650,
        flexDirection = "column",
        backgroundColor = C.cardBg,
        borderRadius = 16,
        borderWidth = 2,
        borderColor = C.cardBorder,
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function() end,
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%", height = 38,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                backgroundColor = C.headerBg,
                paddingLeft = 12, paddingRight = 6,
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = "📈 全服广告统计",
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = C.title,
                        pointerEvents = "none",
                    },
                    UI.Panel {
                        width = 34, height = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function() AdDashboardUI.Hide() end,
                        children = {
                            UI.Label {
                                text = "✕",
                                fontSize = 18,
                                fontColor = C.dim,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
            -- 副标题
            UI.Panel {
                width = "100%", height = 18,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 40, 60, 30, 200 },
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = "管理员专属 · 按 F 关闭 · " .. os.date("%Y-%m-%d"),
                        fontSize = 9,
                        fontColor = C.green,
                        pointerEvents = "none",
                    },
                },
            },
            -- 表头
            BuildHeaderRow(),
            -- 数据区（可滚动）
            UI.ScrollView {
                width = "100%",
                flex = 1,
                children = {
                    UI.Panel {
                        id = "adTableBody",
                        width = "100%",
                        flexDirection = "column",
                        children = {
                            UI.Panel {
                                width = "100%", height = 40,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "加载中...",
                                        fontSize = 11,
                                        fontColor = C.dim,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    },
                },
            },
            -- 合计行（固定在底部，不随滚动）
            UI.Panel {
                id = "adSummaryRow",
                width = "100%",
                flexShrink = 0,
                flexDirection = "column",
            },
        },
    }
end

-- ============================================================================
-- 浮层管理
-- ============================================================================

function AdDashboardUI.CreateOverlay(uiModule)
    UI = uiModule
    return UI.Panel {
        id = "adDashboardOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = C.bg,
        pointerEvents = "auto",
        onClick = function() AdDashboardUI.Hide() end,
        children = {
            AdDashboardUI._BuildCard(),
        },
    }
end

function AdDashboardUI.Show()
    if not AdDashboardUI.IsAdmin() then
        print("[AdDashboard] Not admin, ignored")
        return
    end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlay = root:FindById("adDashboardOverlay")
    if overlay then
        overlay:ClearChildren()
        overlay:AddChild(AdDashboardUI._BuildCard())
        overlay:SetVisible(true)
    end

    local TabNav = require("Game.TabNav")
    TabNav.SetBarVisible(false)

    -- 重置并并行加载所有排行榜
    ResetMergedData()
    local keys = GetKeys()
    LoadKey(keys.total,  "total")
    LoadKey(keys.start,  "start")
    LoadKey(keys.done,   "done")
    LoadKey(keys.cancel, "cancel")

    print("[AdDashboard] Shown")
end

function AdDashboardUI.Hide()
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlay = root:FindById("adDashboardOverlay")
    if overlay then overlay:SetVisible(false) end

    local TabNav = require("Game.TabNav")
    TabNav.SetBarVisible(true)
    print("[AdDashboard] Hidden")
end

function AdDashboardUI.Toggle()
    if not AdDashboardUI.IsAdmin() then return end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlay = root:FindById("adDashboardOverlay")
    if overlay and overlay:IsVisible() then
        AdDashboardUI.Hide()
    else
        AdDashboardUI.Show()
    end
end

return AdDashboardUI
