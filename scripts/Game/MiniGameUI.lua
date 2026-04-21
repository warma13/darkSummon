-- Game/MiniGameUI.lua
-- 小游戏入口页面 —— 展示可用小游戏列表（类似副本页面风格）

local YangMiniGame = require("yang.MiniGame")

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
    -- 后续可在此添加更多小游戏
    -- {
    --     key        = "2048",
    --     name       = "2048",
    --     desc       = "数字合并，挑战最高分",
    --     accentColor = { 60, 180, 220, 255 },
    --     available  = false,
    --     statusText = "即将开放",
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
    return YangMiniGame.isActive()
end

--- 启动指定小游戏
function MiniGameUI._LaunchGame(key)
    if key == "sheep" then
        if onGameStartFn then onGameStartFn() end
        YangMiniGame.start({
            startLvl = 1,
            onDone = function(result)
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

    -- 底部返回栏
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Panel {
                paddingLeft = 20, paddingRight = 20,
                paddingTop = 8, paddingBottom = 8,
                borderRadius = 8,
                backgroundColor = { 50, 40, 70, 200 },
                pointerEvents = "auto",
                onClick = function(self)
                    if onBackFn then onBackFn() end
                end,
                children = {
                    UI.Label {
                        text = "◀ 返回",
                        fontSize = 15,
                        fontColor = S.white,
                        pointerEvents = "none",
                    },
                },
            },
        },
    })
end

return MiniGameUI
