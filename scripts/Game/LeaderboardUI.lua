-- Game/LeaderboardUI.lua
-- 排行榜 UI 面板：主线关卡 / 试练塔排行，标签栏切换

local LB = require("Game.LeaderboardData")
local Toast = require("Game.Toast")

local LeaderboardUI = {}

---@type any
local UI = nil

-- 默认标签定义
local _fmtBoss = function(s) return LB.FormatWorldBoss(s) end
local DEFAULT_TABS = {
    { key = LB.KEY_CAMPAIGN, label = "主线", format = function(s) return LB.FormatStage(s) end },
    { key = LB.KEY_TOWER,    label = "试练", format = function(s) return LB.FormatTower(s) end },
    { key = "wb_diff_combined", label = "BOSS", format = _fmtBoss,
      combined = {
          { level = 9, label = "地狱", color = { 255, 80, 80 },   getKey = function() return LB.GetWorldBossDiffDailyKey(9) end },
          { level = 3, label = "噩梦", color = { 255, 160, 80 },  getKey = function() return LB.GetWorldBossDiffDailyKey(3) end },
          { level = 1, label = "困难", color = { 255, 220, 100 }, getKey = function() return LB.GetWorldBossDiffDailyKey(1) end },
          { level = 0, label = "普通", color = { 150, 220, 150 }, getKey = function() return LB.GetWorldBossDiffDailyKey(0) end },
      },
    },
    { key = "hl_diff_combined", label = "憎恨", format = _fmtBoss,
      combined = {
          { level = 9, label = "地狱", color = { 255, 80, 80 },   getKey = function() return LB.GetHatredLandDiffDailyKey(9) end },
          { level = 3, label = "噩梦", color = { 255, 160, 80 },  getKey = function() return LB.GetHatredLandDiffDailyKey(3) end },
          { level = 1, label = "困难", color = { 255, 220, 100 }, getKey = function() return LB.GetHatredLandDiffDailyKey(1) end },
          { level = 0, label = "普通", color = { 150, 220, 150 }, getKey = function() return LB.GetHatredLandDiffDailyKey(0) end },
      },
    },
    { key = LB.KEY_COSTUME,  label = "时装", format = function(s) return LB.FormatCostume(s) end,
      onActivate = function()
          local ok, CD = pcall(require, "Game.CostumeData")
          if ok then LB.UploadCostume(CD.GetTotalScoreBonus()) end
      end },
}
local TABS = DEFAULT_TABS
local activeTab = 1  -- 当前选中标签索引

-- 状态
local rankList = {}        -- 已加载的排名列表
local myRank = nil         -- 我的排名 (1-based, nil=未上榜)
local myScore = 0          -- 我的分数
local rankTotal = 0        -- 排行榜总人数
local loadedCount = 0      -- 已加载条数
local isLoading = false    -- 是否正在加载
local MAX_LOAD = 100       -- 最多加载 100 条
local PAGE_SIZE = 20       -- 每页 20 条

-- 配色
local C = {
    bg         = { 0, 0, 0, 200 },
    cardBg     = { 20, 16, 35, 245 },
    cardBorder = { 100, 60, 180, 180 },
    headerBg   = { 30, 22, 50, 255 },
    rowBg      = { 28, 22, 45, 220 },
    rowAlt     = { 35, 28, 55, 220 },
    rowMe      = { 60, 30, 100, 255 },
    gold       = { 255, 215, 80, 255 },
    silver     = { 200, 200, 220, 255 },
    bronze     = { 200, 150, 80, 255 },
    white      = { 245, 238, 225, 255 },
    dim        = { 150, 140, 160, 200 },
    purple     = { 160, 120, 240, 255 },
    green      = { 120, 220, 100, 255 },
    loadMore   = { 100, 80, 180, 255 },
    tabActive  = { 160, 120, 240, 255 },
    tabInactive = { 80, 70, 100, 200 },
    tabUnderline = { 160, 120, 240, 255 },
}

-- ============================================================================
-- 获取当前标签的 key 和格式化函数
-- ============================================================================

local function GetActiveKey()
    local tab = TABS[activeTab]
    if tab.getKey then return tab.getKey() end
    if tab.dynamic and tab.key == "wb_daily" then
        return LB.GetWorldBossDailyKey()
    end
    return tab.key
end

local function GetActiveFormat()
    return TABS[activeTab].format
end

-- ============================================================================
-- 标签按钮组件
-- ============================================================================

function LeaderboardUI._BuildTab(tabIndex)
    local tab = TABS[tabIndex]
    local isActive = (tabIndex == activeTab)
    return UI.Panel {
        flex = 1,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function()
            if activeTab == tabIndex then return end
            activeTab = tabIndex
            LeaderboardUI._SwitchTab()
        end,
        children = {
            UI.Label {
                text = tab.label,
                fontSize = 15,
                fontWeight = isActive and "bold" or "normal",
                fontColor = isActive and C.gold or C.tabInactive,
                pointerEvents = "none",
            },
            -- 下划线指示器
            UI.Panel {
                position = "absolute",
                bottom = 0, left = "20%", right = "20%",
                height = 3,
                borderRadius = 2,
                backgroundColor = isActive and C.tabUnderline or { 0, 0, 0, 0 },
            },
        },
    }
end

--- 切换标签：重建整个弹窗内容
function LeaderboardUI._SwitchTab()
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlay = root:FindById("leaderboardOverlay")
    if not overlay then return end

    -- 移除旧弹窗，重建
    overlay:ClearChildren()
    overlay:AddChild(LeaderboardUI._BuildCard())

    -- 重新加载数据
    rankList = {}
    myRank = nil
    myScore = 0
    rankTotal = 0
    loadedCount = 0
    isLoading = false
    -- 切换到该标签时的回调（如上传数据）
    local tab = TABS[activeTab]
    if tab and tab.onActivate then tab.onActivate() end
    LeaderboardUI.LoadMyRank()
    LeaderboardUI.LoadMore()
end

-- ============================================================================
-- 创建排行榜浮层
-- ============================================================================

--- 构建卡片内容（标签栏 + 列表 + 底部我的排名）
function LeaderboardUI._BuildCard()
    return UI.Panel {
        width = 340, height = "80%",
        maxHeight = 520,
        flexDirection = "column",
        backgroundColor = C.cardBg,
        borderRadius = 16,
        borderWidth = 2,
        borderColor = C.cardBorder,
        overflow = "hidden",
        pointerEvents = "auto",
        onClick = function() end, -- 阻止冒泡关闭
        children = {
            -- 标签栏 + 关闭按钮
            UI.Panel {
                width = "100%", height = 46,
                flexDirection = "row",
                alignItems = "stretch",
                backgroundColor = C.headerBg,
                flexShrink = 0,
                children = (function()
                    local tabChildren = {}
                    for i = 1, #TABS do
                        tabChildren[#tabChildren + 1] = LeaderboardUI._BuildTab(i)
                    end
                    -- 关闭按钮（固定宽度，不使用绝对定位避免遮挡标签）
                    tabChildren[#tabChildren + 1] = UI.Panel {
                        width = 40, height = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        flexShrink = 0,
                        pointerEvents = "auto",
                        onClick = function()
                            LeaderboardUI.Hide()
                        end,
                        children = {
                            UI.Label {
                                text = "✕",
                                fontSize = 18,
                                fontColor = C.dim,
                                pointerEvents = "none",
                            },
                        },
                    }
                    return tabChildren
                end)(),
            },
            -- 排名列表
            UI.ScrollView {
                id = "lb_scrollView",
                width = "100%",
                flex = 1,
                children = {
                    UI.Panel {
                        id = "lb_listContainer",
                        width = "100%",
                        flexDirection = "column",
                        children = {
                            UI.Panel {
                                id = "lb_loadingHint",
                                width = "100%", height = 60,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "加载中...",
                                        fontSize = 14,
                                        fontColor = C.dim,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    },
                },
            },
            -- 底部：我的排名
            UI.Panel {
                id = "lb_myRankCard",
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 10, paddingBottom = 10,
                backgroundColor = { 40, 25, 65, 255 },
                borderTopWidth = 1,
                borderColor = { 80, 50, 120, 100 },
                flexShrink = 0,
                gap = 8,
                children = {
                    UI.Label {
                        id = "lb_myRankLabel",
                        text = "加载中...",
                        fontSize = 13,
                        fontColor = C.purple,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

function LeaderboardUI.CreateOverlay(uiModule)
    UI = uiModule

    return UI.Panel {
        id = "leaderboardOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = C.bg,
        pointerEvents = "auto",
        onClick = function(self)
            LeaderboardUI.Hide()
        end,
        children = {
            LeaderboardUI._BuildCard(),
        },
    }
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

--- 使用自定义标签组显示排行榜
---@param tabs table[] { key, label, format }
---@param defaultTab? number 默认选中标签索引
function LeaderboardUI.ShowWithTabs(tabs, defaultTab)
    TABS = tabs
    activeTab = defaultTab or 1
    LeaderboardUI._DoShow()
end

--- 显示排行榜，可选指定默认标签索引
---@param tabIndex? number 标签索引 (1=主线, 2=试练塔, 3=BOSS日榜)
function LeaderboardUI.Show(tabIndex)
    TABS = DEFAULT_TABS
    if tabIndex and tabIndex >= 1 and tabIndex <= #TABS then
        activeTab = tabIndex
    end
    LeaderboardUI._DoShow()
end

function LeaderboardUI._DoShow()

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlay = root:FindById("leaderboardOverlay")
    if overlay then
        -- 重建卡片（刷新标签状态）
        overlay:ClearChildren()
        overlay:AddChild(LeaderboardUI._BuildCard())
        overlay:SetVisible(true)
    end

    local TabNav = require("Game.TabNav")
    TabNav.SetBarVisible(false)

    -- 重置状态并加载数据
    rankList = {}
    myRank = nil
    myScore = 0
    rankTotal = 0
    loadedCount = 0
    isLoading = false
    -- 当前标签激活回调
    local tab = TABS[activeTab]
    if tab and tab.onActivate then tab.onActivate() end

    LeaderboardUI.LoadMyRank()
    LeaderboardUI.LoadMore()
end

function LeaderboardUI.Hide()
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local overlay = root:FindById("leaderboardOverlay")
    if overlay then
        overlay:SetVisible(false)
    end

    local TabNav = require("Game.TabNav")
    TabNav.SetBarVisible(true)
end

-- ============================================================================
-- 数据加载
-- ============================================================================

function LeaderboardUI.LoadMyRank()
    local tab = TABS[activeTab]

    -- combined 模式：查询所有子难度的排名
    if tab.combined then
        local results = {}
        local pending = #tab.combined
        for i, sub in ipairs(tab.combined) do
            local subKey = sub.getKey()
            LB.FetchMyRank(subKey, function(rank, score)
                local s = score or 0
                local r = (s > 0 and rank) and rank or nil
                results[i] = { label = sub.label, rank = r, score = s, color = sub.color }
                pending = pending - 1
                if pending <= 0 then
                    -- 所有查询完毕，更新 UI
                    LeaderboardUI._UpdateMyRankCombined(results, tab.format)
                end
            end)
        end
        return
    end

    -- 普通模式
    local key = GetActiveKey()
    LB.FetchMyRank(key, function(rank, score)
        myScore = score or 0
        -- 无有效分数时视为未上榜（API 可能对 score=0 也返回 rank=1）
        myRank = (myScore > 0 and rank) and rank or nil
        LeaderboardUI.UpdateMyRankCard()
    end)

    LB.FetchRankTotal(key, function(total)
        rankTotal = total or 0
        LeaderboardUI.UpdateMyRankCard()
    end)
end

--- combined 模式下更新底部"我的排名"
function LeaderboardUI._UpdateMyRankCombined(results, fmt)
    if not UI then return end
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local card = root:FindById("lb_myRankCard")
    if not card then return end

    card:ClearChildren()

    local hasAny = false
    for _, r in ipairs(results) do
        if r.rank and r.rank > 0 then hasAny = true; break end
    end

    if not hasAny then
        card:AddChild(UI.Label {
            text = "暂无排名数据",
            fontSize = 13,
            fontColor = C.purple,
            pointerEvents = "none",
        })
        return
    end

    -- 显示各难度排名，一行展示
    for _, r in ipairs(results) do
        local txt
        if r.rank and r.rank > 0 then
            txt = r.label .. " #" .. r.rank
        else
            txt = r.label .. " —"
        end
        card:AddChild(UI.Label {
            text = txt,
            fontSize = 12,
            fontColor = r.color or C.purple,
            pointerEvents = "none",
            marginRight = 10,
        })
    end
end

function LeaderboardUI.LoadMore()
    if isLoading then return end

    local tab = TABS[activeTab]

    -- combined 模式：一次性加载所有子难度的排行榜
    if tab.combined then
        if loadedCount > 0 then return end  -- combined 模式只加载一次
        isLoading = true
        local subCount = #tab.combined
        local subResults = {}
        local pending = subCount
        local PER_DIFF = 10  -- 每个难度显示 top 10

        for i, sub in ipairs(tab.combined) do
            local subKey = sub.getKey()
            LB.FetchRankList(subKey, 0, PER_DIFF, function(list)
                subResults[i] = list or {}
                pending = pending - 1
                if pending <= 0 then
                    isLoading = false
                    -- 合并结果：每个难度一个分区头 + 排名列表
                    rankList = {}
                    for j, sub2 in ipairs(tab.combined) do
                        -- 分区头
                        rankList[#rankList + 1] = {
                            isHeader = true,
                            label = sub2.label,
                            color = sub2.color,
                        }
                        local sList = subResults[j]
                        if #sList > 0 then
                            for _, entry in ipairs(sList) do
                                rankList[#rankList + 1] = entry
                            end
                        else
                            rankList[#rankList + 1] = {
                                isEmpty = true,
                            }
                        end
                    end
                    loadedCount = #rankList
                    LeaderboardUI.RebuildList(false)
                end
            end)
        end
        return
    end

    -- 普通模式
    if loadedCount >= MAX_LOAD then
        Toast.Show("已加载全部排名", C.dim)
        return
    end

    isLoading = true
    local start = loadedCount  -- 0-based

    LB.FetchRankList(GetActiveKey(), start, PAGE_SIZE, function(list)
        isLoading = false
        if not list then
            Toast.Show("加载排行榜失败", { 255, 100, 100 })
            return
        end

        for _, entry in ipairs(list) do
            rankList[#rankList + 1] = entry
        end
        loadedCount = loadedCount + #list

        LeaderboardUI.RebuildList(#list >= PAGE_SIZE and loadedCount < MAX_LOAD)
    end)
end

-- ============================================================================
-- UI 刷新
-- ============================================================================

function LeaderboardUI.UpdateMyRankCard()
    if not UI then return end
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local label = root:FindById("lb_myRankLabel")
    if not label then return end

    local fmt = GetActiveFormat()
    local text
    if myRank and myRank > 0 then
        text = "我的排名: 第" .. myRank .. "名 · " .. fmt(myScore)
    else
        if myScore > 0 then
            text = "我的成绩: " .. fmt(myScore) .. " · 未上榜"
        else
            text = "暂无排名数据"
        end
    end
    label:SetText(text)
end

function LeaderboardUI.RebuildList(hasMore)
    if not UI then return end
    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local container = root:FindById("lb_listContainer")
    if not container then return end

    container:ClearChildren()

    -- 排名行（支持分区头 + 空区域 + 普通排名行）
    for i, entry in ipairs(rankList) do
        if entry.isHeader then
            -- 分区头：难度标题
            container:AddChild(LeaderboardUI._BuildSectionHeader(entry))
        elseif entry.isEmpty then
            -- 空分区提示
            container:AddChild(UI.Panel {
                width = "100%", height = 32,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 25, 20, 40, 180 },
                children = {
                    UI.Label {
                        text = "暂无数据",
                        fontSize = 11,
                        fontColor = C.dim,
                        pointerEvents = "none",
                    },
                },
            })
        else
            container:AddChild(LeaderboardUI.BuildRankRow(entry, i))
        end
    end

    -- "加载更多" 按钮
    if hasMore then
        container:AddChild(UI.Panel {
            width = "100%", height = 44,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { 35, 28, 55, 180 },
            pointerEvents = "auto",
            onClick = function()
                LeaderboardUI.LoadMore()
            end,
            children = {
                UI.Label {
                    text = "点击加载更多",
                    fontSize = 13,
                    fontColor = C.loadMore,
                    pointerEvents = "none",
                },
            },
        })
    elseif #rankList > 0 then
        container:AddChild(UI.Panel {
            width = "100%", height = 30,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "— 已显示全部 —",
                    fontSize = 11,
                    fontColor = C.dim,
                    pointerEvents = "none",
                },
            },
        })
    else
        container:AddChild(UI.Panel {
            width = "100%", height = 60,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无排名数据",
                    fontSize = 14,
                    fontColor = C.dim,
                    pointerEvents = "none",
                },
            },
        })
    end
end

--- 构建分区头（难度标题行）
function LeaderboardUI._BuildSectionHeader(entry)
    local clr = entry.color or { 200, 200, 200 }
    return UI.Panel {
        width = "100%", height = 32,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        backgroundColor = { clr[1], clr[2], clr[3], 35 },
        borderBottomWidth = 1,
        borderColor = { clr[1], clr[2], clr[3], 80 },
        children = {
            -- 彩色圆点
            UI.Panel {
                width = 8, height = 8,
                borderRadius = 4,
                backgroundColor = { clr[1], clr[2], clr[3], 255 },
                marginRight = 8,
            },
            UI.Label {
                text = entry.label,
                fontSize = 13,
                fontWeight = "bold",
                fontColor = { clr[1], clr[2], clr[3], 255 },
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 排名行组件
-- ============================================================================

function LeaderboardUI.BuildRankRow(entry, index)
    local rank = entry.rank
    local isMe = entry.isMe

    -- 排名颜色
    local rankColor = C.white
    local rankText = tostring(rank)
    if rank == 1 then
        rankColor = C.gold
        rankText = "🥇"
    elseif rank == 2 then
        rankColor = C.silver
        rankText = "🥈"
    elseif rank == 3 then
        rankColor = C.bronze
        rankText = "🥉"
    end

    -- 行背景
    local rowBg = isMe and C.rowMe or (index % 2 == 0 and C.rowAlt or C.rowBg)

    -- 昵称（截断）
    local nickname = entry.nickname or "玩家"
    if #nickname > 24 then
        nickname = string.sub(nickname, 1, 24) .. "…"
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 10, paddingRight = 10,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = rowBg,
        borderBottomWidth = 1,
        borderColor = { 50, 40, 70, 60 },
        gap = 8,
        children = {
            -- 排名
            UI.Panel {
                width = 36,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = rankText,
                        fontSize = rank <= 3 and 18 or 14,
                        fontWeight = rank <= 3 and "bold" or "normal",
                        fontColor = rankColor,
                        pointerEvents = "none",
                    },
                },
            },
            -- 昵称
            UI.Panel {
                flex = 1,
                children = {
                    UI.Label {
                        text = nickname .. (isMe and " (我)" or ""),
                        fontSize = 13,
                        fontColor = isMe and C.gold or C.white,
                        fontWeight = isMe and "bold" or "normal",
                        pointerEvents = "none",
                    },
                },
            },
            -- 分数
            UI.Panel {
                alignItems = "flex-end",
                children = {
                    UI.Label {
                        text = GetActiveFormat()(entry.score),
                        fontSize = 13,
                        fontWeight = "bold",
                        fontColor = C.green,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

return LeaderboardUI
