-- Game/MiniGameUI.lua
-- 小游戏入口页面 —— 展示可用小游戏列表（类似副本页面风格）

local YangMiniGame = require("yang.MiniGame")
local YangBoard    = require("yang.Board")
local AutoChessMiniGame = require("autochess.MiniGame")
local JoyShopData  = require("Game.JoyShopData")
local JoyShopUI    = require("Game.JoyShopUI")

local MiniGameUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type function|nil
local onBackFn = nil
---@type function|nil
local onGameStartFn = nil
---@type function|nil
local onGameEndFn = nil

-- ============================================================================
-- 配色
-- ============================================================================
local S = {
    pageBg       = { 15, 12, 25, 255 },
    headerBg     = { 28, 20, 45, 255 },
    cardBg       = { 30, 24, 48, 240 },
    cardBorder   = { 70, 55, 100, 120 },
    white        = { 245, 238, 225, 255 },
    dim          = { 150, 140, 160, 200 },
    gold         = { 255, 215, 80, 255 },
    green        = { 120, 220, 100, 255 },
    comingSoon   = { 80, 70, 95, 200 },
}

-- ============================================================================
-- 小游戏定义
-- ============================================================================
local MINIGAME_DEFS = {
    {
        key        = "sheep",
        name       = "暗黑消除",
        desc       = "经典三消消除，挑战你的眼力与策略",
        banner     = "image/banner_dark_match.png",
        accentColor = { 255, 180, 60, 255 },
        available  = true,
        statusText = "开始游戏",
    },
    -- {
    --     key        = "autochess",
    --     name       = "暗黑棋局",
    --     desc       = "自走棋策略对战，合成升星，羁绊制胜",
    --     accentColor = { 140, 100, 220, 255 },
    --     available  = true,
    --     statusText = "开始游戏",
    -- },
}

-- ============================================================================
-- 构建卡片
-- ============================================================================

---@param def table
---@return any
local function BuildGameCard(def)
    local isAvailable = def.available
    local statusText = def.statusText or (isAvailable and "开始游戏" or "即将开放")
    local statusColor = isAvailable and S.green or S.comingSoon
    local accentColor = isAvailable and def.accentColor or S.comingSoon

    local cardChildren = {}

    -- banner 图片（如果有）
    if def.banner then
        cardChildren[#cardChildren + 1] = UI.Panel {
            width = "100%",
            height = 160,
            backgroundImage = def.banner,
            backgroundFit = "cover",
            pointerEvents = "none",
        }
    end

    -- 下方信息区
    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 12, paddingBottom = 12,
        children = {
            -- 文本区（居左）
            UI.Panel {
                flex = 1,
                flexDirection = "column",
                gap = 4,
                alignItems = "flex-start",
                children = {
                    UI.Label {
                        text = def.name,
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = isAvailable and S.white or S.dim,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = def.desc,
                        fontSize = 12,
                        fontColor = S.dim,
                        pointerEvents = "none",
                    },
                },
            },
            -- 右侧状态按钮
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 12,
                backgroundColor = { statusColor[1], statusColor[2], statusColor[3], 40 },
                children = {
                    UI.Label {
                        text = statusText,
                        fontSize = 12,
                        fontColor = statusColor,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = isAvailable and S.cardBg or { 25, 20, 38, 180 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = isAvailable and S.cardBorder or { 50, 42, 65, 80 },
        overflow = "hidden",
        pointerEvents = isAvailable and "auto" or "none",
        onClick = isAvailable and function(self)
            MiniGameUI._LaunchGame(def.key)
        end or nil,
        children = cardChildren,
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function MiniGameUI.SetOnBack(fn)
    onBackFn = fn
end

function MiniGameUI.SetOnGameStart(fn)
    onGameStartFn = fn
end

function MiniGameUI.SetOnGameEnd(fn)
    onGameEndFn = fn
end

--- 查询小游戏是否正在运行（供宿主 Update/输入跳过用）
function MiniGameUI.isActive()
    return YangMiniGame.isActive() or AutoChessMiniGame.isActive()
end

--- 启动指定小游戏
function MiniGameUI._LaunchGame(key)
    if key == "sheep" then
        if onGameStartFn then onGameStartFn() end
        YangMiniGame.start({
            startLvl = 1,
            onDone = function(result)
                -- 记录本局得分和关卡到每日排行榜
                MiniGameUI.RecordScore(YangBoard.score or 0, YangBoard.curLvl or 1)
                -- 每日首局欢乐币奖励
                JoyShopData.OnGameComplete()
                if onGameEndFn then onGameEndFn(result) end
            end,
        })
    elseif key == "autochess" then
        if onGameStartFn then onGameStartFn() end
        AutoChessMiniGame.start({
            onDone = function(result)
                -- 每日首局欢乐币奖励
                JoyShopData.OnGameComplete()
                if onGameEndFn then onGameEndFn(result) end
            end,
        })
    end
end

function MiniGameUI.CreatePage(uiModule)
    UI = uiModule

    pageRoot = UI.Panel {
        id = "miniGamePage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = S.pageBg,
        children = {},
    }

    MiniGameUI.Refresh()
    return pageRoot
end

function MiniGameUI.Refresh()
    if not pageRoot or not UI then return end
    pageRoot:ClearChildren()

    -- 每日排行榜结算（异步，静默发放欢乐币）
    JoyShopData.CheckSettlement(nil)

    -- 顶部标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "小游戏",
                fontSize = 20,
                fontWeight = "bold",
                fontColor = S.white,
                pointerEvents = "none",
            },
        },
    })

    -- 游戏卡片列表
    local cards = {}
    for _, def in ipairs(MINIGAME_DEFS) do
        cards[#cards + 1] = BuildGameCard(def)
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
                gap = 10,
                children = cards,
            },
        },
    })

    -- 底部工具栏：返回(左) | 欢乐商店(中) | 排行榜(右)
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            -- 返回按钮（居左）
            UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 8, paddingBottom = 8,
                borderRadius = 8,
                backgroundColor = { 50, 40, 70, 200 },
                pointerEvents = "auto",
                onClick = function(self)
                    if onBackFn then onBackFn() end
                end,
                children = {
                    UI.Label {
                        text = "返回",
                        fontSize = 15,
                        fontColor = S.white,
                        pointerEvents = "none",
                    },
                },
            },
            -- 欢乐商店按钮（居中）
            UI.Panel {
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 8, paddingBottom = 8,
                borderRadius = 8,
                backgroundColor = { 80, 60, 20, 200 },
                borderWidth = 1,
                borderColor = { 255, 200, 60, 100 },
                pointerEvents = "auto",
                onClick = function(self)
                    MiniGameUI.ShowJoyShop()
                end,
                children = {
                    UI.Label {
                        text = "欢乐商店",
                        fontSize = 15,
                        fontColor = S.gold,
                        pointerEvents = "none",
                    },
                },
            },
            -- 排行榜按钮（居右）
            UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 8, paddingBottom = 8,
                borderRadius = 8,
                backgroundColor = { 60, 40, 100, 200 },
                pointerEvents = "auto",
                onClick = function(self)
                    MiniGameUI.ShowLeaderboard()
                end,
                children = {
                    UI.Label {
                        text = "排行榜",
                        fontSize = 15,
                        fontColor = S.gold,
                        pointerEvents = "none",
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 排行榜 —— 暗黑消除每日最高分
-- key = "yang_daily_YYYYMMDD"，写入时删除前一天的 key
-- ============================================================================

---@type any
local leaderboardRoot = nil

--- 获取今日 key
local function todayKey()
    return "yang_daily_" .. os.date("%Y%m%d")
end

--- 获取昨日 key（需要删除）
local function yesterdayKey()
    return "yang_daily_" .. os.date("%Y%m%d", os.time() - 86400)
end

--- 记录分数 —— 仅在比已有分数更高时写入
--- @param score number 消除次数得分
--- @param level number 到达的关卡
function MiniGameUI.RecordScore(score, level)
    if not clientCloud then return end
    local key    = todayKey()
    local lvlKey = todayKey() .. "_lvl"
    clientCloud:Get(key, {
        ok = function(values, iscores)
            local ok2, err2 = pcall(function()
                local old = (iscores and iscores[key]) or 0
                if score > old then
                    clientCloud:BatchSet()
                        :SetInt(key, score)
                        :SetInt(lvlKey, level)
                        :Delete(yesterdayKey())
                        :Delete(yesterdayKey() .. "_lvl")
                        :Save("暗黑消除最高分")
                end
            end)
            if not ok2 then print("[MiniGameUI] RecordScore ok error: " .. tostring(err2)) end
        end,
        error = function()
            local ok2, err2 = pcall(function()
                clientCloud:BatchSet()
                    :SetInt(key, score)
                    :SetInt(lvlKey, level)
                    :Delete(yesterdayKey())
                    :Delete(yesterdayKey() .. "_lvl")
                    :Save("暗黑消除最高分")
            end)
            if not ok2 then print("[MiniGameUI] RecordScore error fallback error: " .. tostring(err2)) end
        end,
    })
end

--- 显示排行榜弹窗
function MiniGameUI.ShowLeaderboard()
    if not UI then return end
    if leaderboardRoot then return end  -- 防止重复打开

    local key = todayKey()
    local dateStr = os.date("%m/%d")

    -- 先构建加载中界面
    local listContainer = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 8,
        children = {
            UI.Label { text = "加载中...", fontSize = 14, fontColor = S.dim },
        },
    }

    leaderboardRoot = UI.Panel {
        id = "leaderboardOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function(self)
            MiniGameUI.HideLeaderboard()
        end,
        children = {
            UI.Panel {
                width = 300,
                maxHeight = 420,
                flexDirection = "column",
                backgroundColor = { 35, 28, 55, 250 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 255, 215, 80, 80 },
                overflow = "hidden",
                pointerEvents = "auto",
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        paddingTop = 14, paddingBottom = 10,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "暗黑消除 · 今日排行",
                                fontSize = 18,
                                fontWeight = "bold",
                                fontColor = S.gold,
                            },
                            UI.Label {
                                text = dateStr,
                                fontSize = 12,
                                fontColor = S.dim,
                                marginTop = 4,
                            },
                        },
                    },
                    -- 列表区
                    UI.ScrollView {
                        width = "100%",
                        flex = 1,
                        maxHeight = 280,
                        children = { listContainer },
                    },
                    -- 关闭按钮
                    UI.Panel {
                        width = "100%",
                        paddingTop = 10, paddingBottom = 14,
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                paddingLeft = 30, paddingRight = 30,
                                paddingTop = 8, paddingBottom = 8,
                                borderRadius = 8,
                                backgroundColor = { 60, 45, 90, 220 },
                                pointerEvents = "auto",
                                onClick = function(self)
                                    MiniGameUI.HideLeaderboard()
                                end,
                                children = {
                                    UI.Label {
                                        text = "关闭",
                                        fontSize = 15,
                                        fontColor = S.white,
                                        pointerEvents = "none",
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
        pageRoot:AddChild(leaderboardRoot)
    end

    -- 拉取排行榜数据
    if not clientCloud then
        listContainer:ClearChildren()
        listContainer:AddChild(UI.Label { text = "排行榜暂不可用", fontSize = 14, fontColor = S.dim })
        return
    end

    local lvlKey = key .. "_lvl"
    clientCloud:GetRankList(key, 0, 20, false, {
        ok = function(rankList)
            local ok2, err2 = pcall(function()
            if not leaderboardRoot then return end
            listContainer:ClearChildren()

            if #rankList == 0 then
                listContainer:AddChild(UI.Label {
                    text = "今日暂无记录",
                    fontSize = 14,
                    fontColor = S.dim,
                    marginTop = 20,
                })
                return
            end

            -- 收集 userId 查昵称
            local userIds = {}
            for _, item in ipairs(rankList) do
                userIds[#userIds + 1] = item.userId
            end

            local function buildRows(nickMap)
                if not leaderboardRoot then return end
                listContainer:ClearChildren()
                for i, item in ipairs(rankList) do
                    local score  = (item.iscore and item.iscore[key]) or 0
                    local lvl    = (item.iscore and item.iscore[lvlKey]) or 0
                    local isMe   = (item.userId == clientCloud.userId)
                    local nick   = (nickMap and nickMap[item.userId]) or ("玩家" .. tostring(item.userId):sub(-4))

                    -- 排名颜色
                    local rankColor = S.white
                    if i == 1 then rankColor = { 255, 215, 80, 255 }
                    elseif i == 2 then rankColor = { 200, 200, 210, 255 }
                    elseif i == 3 then rankColor = { 205, 150, 80, 255 }
                    end

                    listContainer:AddChild(UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        paddingLeft = 14, paddingRight = 14,
                        paddingTop = 8, paddingBottom = 8,
                        backgroundColor = isMe and { 80, 60, 130, 60 } or { 0, 0, 0, 0 },
                        children = {
                            -- 排名
                            UI.Label {
                                text = "#" .. i,
                                fontSize = 16,
                                fontWeight = "bold",
                                fontColor = rankColor,
                                width = 36,
                                pointerEvents = "none",
                            },
                            -- 昵称
                            UI.Label {
                                text = nick,
                                fontSize = 14,
                                fontColor = isMe and S.gold or S.white,
                                flex = 1,
                                pointerEvents = "none",
                            },
                            -- 分数 + 关卡
                            UI.Panel {
                                flexDirection = "column",
                                alignItems = "flex-end",
                                children = {
                                    UI.Label {
                                        text = score .. "分",
                                        fontSize = 14,
                                        fontWeight = "bold",
                                        fontColor = rankColor,
                                        pointerEvents = "none",
                                    },
                                    UI.Label {
                                        text = "第" .. lvl .. "关",
                                        fontSize = 11,
                                        fontColor = S.dim,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    })
                end
            end

            -- 尝试查昵称
            if GetUserNickname then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        buildRows(map)
                    end,
                    onError = function()
                        buildRows(nil)
                    end,
                })
            else
                buildRows(nil)
            end
            end) -- pcall end
            if not ok2 then print("[MiniGameUI] ShowLeaderboard ok error: " .. tostring(err2)) end
        end,
        error = function()
            if not leaderboardRoot then return end
            listContainer:ClearChildren()
            listContainer:AddChild(UI.Label {
                text = "加载失败",
                fontSize = 14,
                fontColor = { 220, 100, 100, 255 },
                marginTop = 20,
            })
        end,
    }, lvlKey)
end

function MiniGameUI.HideLeaderboard()
    if leaderboardRoot then
        leaderboardRoot:Remove()
        leaderboardRoot = nil
    end
end

-- ============================================================================
-- 欢乐商店 —— 欢乐币兑换物资
-- ============================================================================

---@type any
local joyShopPage = nil

function MiniGameUI.ShowJoyShop()
    if not UI then return end
    if joyShopPage then return end  -- 防止重复打开

    JoyShopUI.SetOnBack(function()
        MiniGameUI.HideJoyShop()
    end)
    joyShopPage = JoyShopUI.CreatePage(UI)
    if pageRoot then
        pageRoot:AddChild(joyShopPage)
    end
end

function MiniGameUI.HideJoyShop()
    if joyShopPage then
        JoyShopUI.Remove()
        joyShopPage = nil
    end
end

return MiniGameUI
