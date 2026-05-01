-- Game/WeeklyActivityUI/MineDungeon.lua
-- 网格探索 UI（全屏页面 + 体力制 + 多层 + 钥匙）
-- 5×4 翻牌网格，资源格自动领取，敌人格点击后战斗

local MDD              = require("Game.MineDungeonData")
local Currency         = require("Game.Currency")
local Toast            = require("Game.Toast")
local RewardController = require("Game.RewardController")
local State            = require("Game.State")
local TabNav           = require("Game.TabNav")

local MineDungeon = {}

---@type any
local _UI = nil
---@type any
local _pageRoot = nil
---@type any
local _S = nil

-- 全屏探索 overlay
---@type any
local exploreOverlay = nil

-- 格子 widget 缓存 { [index] = widget }
local cellWidgets = {}

-- 当前选择的层
local selectedLayer = 1

--- 在 exploreOverlay 内以高 zIndex 显示奖励弹窗（避免被网格内容层遮挡）
---@param defs table[]
---@param title string
---@param onClose function|nil
local function showRewardInOverlay(defs, title, onClose)
    if not _UI or not exploreOverlay then
        if onClose then onClose() end
        return
    end
    -- 创建高 zIndex 包装层
    local wrapper = _UI.Panel {
        id = "rewardPopupWrapper",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 800,
    }
    exploreOverlay:AddChild(wrapper)
    RewardController.ShowFromDefs(_UI, wrapper, defs, title, function()
        wrapper:Remove()
        if onClose then onClose() end
    end)
end

-- 体力恢复计时
local staminaTimerAcc = 0

-- ============================================================================
-- 奖励类型→货币图片（资源格翻开后显示对应图标）
-- ============================================================================

local REWARD_IMAGES = {
    idle_income      = "image/currency_nether_crystal.png",
    shadow_essence   = "image/currency_shadow_essence.png",
    abyss_crystal    = "image/currency_abyss_crystal.png",
    mythic_rune_box  = "image/icon_random_mythic_rune_box_20260426065826.png",
    pale_jade        = "image/currency_pale_jade.png",
    shadow_orb       = "image/currency_shadow_orb.png",
}

local REWARD_COLORS = {
    idle_income      = { 180, 220, 255, 255 },
    shadow_essence   = { 180, 120, 255, 255 },
    abyss_crystal    = { 100, 180, 255, 255 },
    mythic_rune_box  = { 255, 200, 60, 255 },
    pale_jade        = { 140, 255, 180, 255 },
    shadow_orb       = { 200, 100, 255, 255 },
    key              = { 255, 230, 50, 255 },
}

-- 敌人格子随机显示的怪物图片
local ENEMY_IMAGES = {
    "image/mobs/undead_infantry.png",
    "image/mobs/undead_assassin.png",
    "image/mobs/lava_tank.png",
    "image/mobs/frost_special.png",
    "image/mobs/void_blinker.png",
    "image/mobs/forest_splitter.png",
    "image/mobs/undead_boss.png",
}

--- 根据格子索引确定性选取敌人图片
local function getEnemyImage(cellIndex)
    return ENEMY_IMAGES[((cellIndex - 1) % #ENEMY_IMAGES) + 1]
end

--- 资源标签小组件（图标 + 名称）
function MineDungeon._ResTag(label, imgPath)
    local UI = _UI
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 40, 35, 15, 220 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { 100, 85, 30, 120 },
        paddingLeft = 5, paddingRight = 7,
        paddingTop = 3, paddingBottom = 3,
        gap = 4,
        children = {
            UI.Panel {
                width = 16, height = 16,
                backgroundImage = imgPath,
                backgroundFit = "contain",
            },
            UI.Label {
                text = label,
                fontSize = 9,
                fontColor = { 220, 210, 170, 230 },
            },
        },
    }
end

-- ============================================================================
-- 概览横幅（活动列表中的入口卡片）
-- ============================================================================

function MineDungeon.BuildBanner(ctx)
    local UI = ctx.GetUI()
    local S  = ctx.GetS()
    _UI = UI; _S = S; _pageRoot = ctx.GetPageRoot()

    local stamina, maxSta = MDD.GetStamina()
    local unlocked = MDD.GetUnlockedLayer()
    local bestRevealed = MDD.GetBestRevealed()
    local isActive  = MDD.IsActive()

    return UI.Panel {
        width = "100%",
        backgroundColor = { 35, 30, 15, 240 },
        borderRadius = 10,
        borderWidth = 2,
        borderColor = { 200, 160, 60, 200 },
        overflow = "hidden",
        marginBottom = 8,
        children = {
            -- 活动配图
            UI.Panel {
                width = "100%", height = 120,
                backgroundImage = "image/banner_mine_dungeon_20260501011829.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                borderTopLeftRadius = 10,
                borderTopRightRadius = 10,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 12, paddingBottom = 14,
                paddingLeft = 16, paddingRight = 16,
                gap = 10,
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Panel {
                                gap = 2,
                                flexShrink = 1,
                                children = {
                                    UI.Label {
                                        text = "⛏️ 矿洞探索",
                                        fontSize = 16,
                                        fontColor = { 255, 200, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "翻开格子，发现宝藏或迎战怪物",
                                        fontSize = 10,
                                        fontColor = { 200, 180, 130, 200 },
                                    },
                                },
                            },
                            UI.Panel {
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 5, paddingBottom = 5,
                                backgroundColor = { 80, 60, 10, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 200, 160, 60, 150 },
                                children = {
                                    UI.Label {
                                        text = "体力: " .. stamina .. "/" .. maxSta,
                                        fontSize = 12,
                                        fontColor = stamina > 0
                                            and { 100, 255, 150, 255 }
                                            or  { 255, 120, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 已解锁层数 + 开始按钮
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "已解锁: 第" .. unlocked .. "层"
                                    .. (bestRevealed > 0 and (" · 最佳: " .. bestRevealed .. "格") or ""),
                                fontSize = 12,
                                fontColor = { 180, 170, 140, 200 },
                            },
                            UI.Button {
                                text = isActive
                                    and (stamina > 0
                                        and (MDD.GetSavedSessionLayer() and "继续探索" or "开始探索")
                                        or "体力不足")
                                    or "活动未开放",
                                fontSize = 13,
                                height = 34,
                                paddingLeft = 16, paddingRight = 16,
                                borderRadius = 8,
                                variant = (isActive and stamina > 0) and "primary" or "outline",
                                disabled = not isActive or stamina <= 0,
                                onClick = function()
                                    -- 如果有存档，默认选中存档的层
                                    local savedLayer = MDD.GetSavedSessionLayer()
                                    selectedLayer = savedLayer or MDD.GetUnlockedLayer()
                                    MineDungeon._ShowExploreOverlay()
                                end,
                            },
                        },
                    },
                    -- 可获得资源
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 15, 12, 5, 200 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        gap = 6,
                        borderWidth = 1,
                        borderColor = { 100, 80, 30, 100 },
                        children = {
                            UI.Label {
                                text = "可获得资源",
                                fontSize = 11,
                                fontColor = { 100, 255, 180, 240 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                flexWrap = "wrap",
                                gap = 6,
                                children = {
                                    MineDungeon._ResTag("冥晶",       "image/currency_nether_crystal.png"),
                                    MineDungeon._ResTag("锻魂铁",     "image/currency_forge_iron.png"),
                                    MineDungeon._ResTag("噬魂石",     "image/currency_devour_stone.png"),
                                    MineDungeon._ResTag("暗影精粹",   "image/currency_shadow_essence.png"),
                                    MineDungeon._ResTag("深渊结晶",   "image/currency_abyss_crystal.png"),
                                    MineDungeon._ResTag("粹玉",       "image/currency_pale_jade.png"),
                                    MineDungeon._ResTag("幽影珠",     "image/currency_shadow_orb.png"),
                                    MineDungeon._ResTag("神话符文箱", "image/icon_random_mythic_rune_box_20260426065826.png"),
                                    MineDungeon._ResTag("劳动奖章",   "image/currency_labor_medal.png"),
                                },
                            },
                        },
                    },
                    -- 规则说明
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 20, 18, 8, 200 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        gap = 4,
                        borderWidth = 1,
                        borderColor = { 100, 80, 30, 100 },
                        children = {
                            UI.Label {
                                text = "规则说明",
                                fontSize = 11,
                                fontColor = { 200, 180, 80, 240 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "• 每次翻牌消耗" .. MDD.FLIP_COST .. "体力，最大" .. MDD.MAX_STAMINA .. "体力",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "• 体力每小时恢复1点，20小时恢复满",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "• 找到钥匙解锁下一层，共" .. MDD.MAX_LAYER .. "层",
                                fontSize = 10, fontColor = { 180, 170, 140, 180 },
                            },
                            UI.Label {
                                text = "• 击败敌人可获得更丰厚的奖励",
                                fontSize = 10, fontColor = { 255, 160, 80, 200 },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 全屏探索页面
-- ============================================================================

function MineDungeon._ShowExploreOverlay()
    local UI = _UI
    if not UI then return end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    -- 清理旧 overlay
    if exploreOverlay then
        exploreOverlay:Remove()
        exploreOverlay = nil
    end
    cellWidgets = {}
    staminaTimerAcc = 0

    -- 隐藏活动页 + Tab栏
    GameUI.ShowWeeklyActivityOverlay(false)
    TabNav.SetBarVisible(false)

    -- 默认选最高已解锁层
    selectedLayer = math.min(selectedLayer, MDD.GetUnlockedLayer())

    exploreOverlay = UI.Panel {
        id = "mineDungeonExplore",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 150,
        pointerEvents = "auto",
        children = {
            -- 背景图
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "image/mine_explore_bg_20260430231331.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                zIndex = 0,
                pointerEvents = "none",
            },
            -- 半透明遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 120 },
                zIndex = 1,
                pointerEvents = "none",
            },
            -- 内容层
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                zIndex = 2,
                pointerEvents = "auto",
                children = {
                    -- 层选择面板（无会话时）
                    MineDungeon._BuildLayerSelectPanel(),
                },
            },
        },
    }

    root:AddChild(exploreOverlay)
end

-- ============================================================================
-- 层选择面板
-- ============================================================================

function MineDungeon._BuildLayerSelectPanel()
    local UI = _UI
    local unlocked = MDD.GetUnlockedLayer()
    local stamina, maxSta = MDD.GetStamina()
    local secLeft, isFull = MDD.GetStaminaRecoveryInfo()

    -- 层按钮列表
    local layerBtns = {}
    for i = 1, MDD.MAX_LAYER do
        local isUnlocked = i <= unlocked
        local isSelected = i == selectedLayer
        local layerLabel, layerColor = MDD.GetLayerDisplay(i)

        layerBtns[#layerBtns + 1] = UI.Panel {
            width = "30%",
            height = 48,
            backgroundColor = isSelected and { 80, 60, 20, 250 }
                or (isUnlocked and { 40, 35, 20, 230 } or { 30, 28, 25, 200 }),
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and { 255, 200, 50, 255 }
                or (isUnlocked and { 120, 100, 50, 150 } or { 60, 55, 45, 100 }),
            justifyContent = "center",
            alignItems = "center",
            pointerEvents = "auto",
            onClick = function()
                if isUnlocked then
                    selectedLayer = i
                    MineDungeon._RefreshLayerSelect()
                end
            end,
            children = {
                UI.Label {
                    text = isUnlocked and layerLabel or "🔒",
                    fontSize = isUnlocked and 13 or 16,
                    fontColor = isUnlocked and layerColor or { 80, 75, 60, 150 },
                    fontWeight = isSelected and "bold" or "normal",
                },
                not isUnlocked and UI.Label {
                    text = layerLabel,
                    fontSize = 9,
                    fontColor = { 80, 75, 60, 120 },
                } or nil,
            },
        }
    end

    -- 恢复倒计时文字
    local recoveryText
    if isFull then
        recoveryText = "体力已满"
    else
        local m = math.floor(secLeft / 60)
        local s = secLeft % 60
        recoveryText = string.format("下一点恢复: %02d:%02d", m, s)
    end

    return UI.Panel {
        id = "layerSelectPanel",
        width = "100%",
        flexGrow = 1,
        children = {
            -- 顶部：标题 + 体力
            UI.Panel {
                width = "100%",
                flexShrink = 0,
                paddingTop = 14, paddingBottom = 10,
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = { 20, 18, 12, 200 },
                borderBottomWidth = 1,
                borderColor = { 120, 100, 40, 100 },
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Panel {
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "⛏️ 矿洞探索",
                                fontSize = 17,
                                fontColor = { 255, 200, 80, 255 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "选择层数开始探索",
                                fontSize = 10,
                                fontColor = { 200, 180, 130, 180 },
                            },
                        },
                    },
                    UI.Panel {
                        alignItems = "flex-end",
                        gap = 2,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 4,
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                backgroundColor = { 60, 50, 15, 220 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 200, 160, 60, 150 },
                                children = {
                                    UI.Label {
                                        text = "⚡",
                                        fontSize = 14,
                                    },
                                    UI.Label {
                                        id = "staminaLabel",
                                        text = stamina .. "/" .. maxSta,
                                        fontSize = 14,
                                        fontColor = stamina > 0
                                            and { 100, 255, 150, 255 }
                                            or  { 255, 120, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                id = "staminaTimer",
                                text = recoveryText,
                                fontSize = 9,
                                fontColor = { 180, 170, 130, 180 },
                            },
                        },
                    },
                },
            },

            -- 层级选择网格
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                justifyContent = "center",
                alignItems = "center",
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 16, paddingBottom = 16,
                children = {
                    UI.Panel {
                        width = "100%",
                        maxWidth = 360,
                        backgroundColor = { 25, 22, 12, 200 },
                        borderRadius = 12,
                        paddingTop = 16, paddingBottom = 16,
                        paddingLeft = 14, paddingRight = 14,
                        gap = 12,
                        borderWidth = 1,
                        borderColor = { 120, 100, 40, 120 },
                        children = {
                            UI.Label {
                                text = "选择探索层",
                                fontSize = 14,
                                fontColor = { 255, 220, 100, 255 },
                                fontWeight = "bold",
                                textAlign = "center",
                            },
                            -- 层按钮网格
                            UI.Panel {
                                id = "layerGrid",
                                width = "100%",
                                flexDirection = "row",
                                flexWrap = "wrap",
                                justifyContent = "center",
                                gap = 8,
                                children = layerBtns,
                            },
                            -- 选定层信息
                            UI.Panel {
                                id = "layerInfo",
                                width = "100%",
                                paddingTop = 8,
                                borderTopWidth = 1,
                                borderColor = { 80, 65, 30, 100 },
                                gap = 4,
                                alignItems = "center",
                                children = MineDungeon._BuildLayerInfoChildren(),
                            },
                            -- 已有存档提示
                            (function()
                                local savedLayer = MDD.GetSavedSessionLayer()
                                if savedLayer == selectedLayer then
                                    return UI.Label {
                                        text = "📌 该层有未完成的探索进度，将自动恢复",
                                        fontSize = 10,
                                        fontColor = { 100, 255, 150, 200 },
                                        textAlign = "center",
                                        marginBottom = 4,
                                    }
                                elseif savedLayer and savedLayer ~= selectedLayer then
                                    return UI.Label {
                                        text = "⚠️ 第" .. savedLayer .. "层有未完成进度，进入新层将覆盖",
                                        fontSize = 10,
                                        fontColor = { 255, 200, 80, 200 },
                                        textAlign = "center",
                                        marginBottom = 4,
                                    }
                                end
                                -- 不能返回 nil，否则会截断 children 数组导致后面的按钮丢失
                                return UI.Panel { width = 0, height = 0 }
                            end)(),
                            -- 开始按钮
                            UI.Button {
                                text = stamina >= MDD.FLIP_COST
                                    and (MDD.GetSavedSessionLayer() == selectedLayer and "继续探索" or "进入探索")
                                    or "体力不足",
                                fontSize = 15,
                                width = "100%",
                                height = 44,
                                borderRadius = 10,
                                variant = stamina >= MDD.FLIP_COST and "primary" or "outline",
                                disabled = stamina < MDD.FLIP_COST,
                                onClick = function()
                                    MineDungeon._EnterLayer(selectedLayer)
                                end,
                            },
                        },
                    },
                },
            },

            -- 底部左下角：撤退
            UI.Panel {
                width = "100%",
                flexShrink = 0,
                paddingBottom = 14, paddingLeft = 14, paddingRight = 14,
                flexDirection = "row",
                justifyContent = "flex-start",
                children = {
                    UI.Button {
                        text = "返回",
                        fontSize = 12,
                        height = 34,
                        paddingLeft = 16, paddingRight = 16,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function()
                            MineDungeon._CloseExplore()
                        end,
                    },
                },
            },
        },
    }
end

--- 构建选定层的信息描述
function MineDungeon._BuildLayerInfoChildren()
    local UI = _UI
    local layerLabel, layerColor = MDD.GetLayerDisplay(selectedLayer)
    return {
        UI.Label {
            text = layerLabel .. " · " .. MDD.TOTAL_CELLS .. "格",
            fontSize = 13,
            fontColor = layerColor,
            fontWeight = "bold",
        },
        UI.Label {
            text = MDD.RESOURCE_COUNT .. "资源 + " .. MDD.ENEMY_COUNT .. "敌人 + " .. MDD.KEY_COUNT .. "钥匙",
            fontSize = 10,
            fontColor = { 180, 170, 140, 180 },
        },
    }
end

--- 刷新层选择面板高亮（不重建整个 overlay）
function MineDungeon._RefreshLayerSelect()
    if not exploreOverlay then return end
    -- 重建整个 overlay 比较简单（层选面板没有频繁交互）
    MineDungeon._ShowExploreOverlay()
end

-- ============================================================================
-- 关闭探索页面
-- ============================================================================

function MineDungeon._CloseExplore()
    cellWidgets = {}
    if exploreOverlay then
        exploreOverlay:Remove()
        exploreOverlay = nil
    end
    -- 恢复活动页 + Tab栏
    local GameUI = require("Game.GameUI")
    GameUI.ShowWeeklyActivityOverlay(true)
    TabNav.SetBarVisible(true)
end

-- ============================================================================
-- 进入指定层探索
-- ============================================================================

function MineDungeon._EnterLayer(layer)
    local session, msg = MDD.CreateSession(layer)
    if not session then
        Toast.Show(msg or "无法进入", { 255, 200, 80 })
        return
    end
    MineDungeon._ShowGridOverlay()
end

-- ============================================================================
-- 网格探索界面
-- ============================================================================

function MineDungeon._ShowGridOverlay()
    local UI = _UI
    if not UI or not exploreOverlay then return end

    -- 替换 overlay 内容
    local contentLayer = exploreOverlay:FindById("mineDungeonExplore")
    if not contentLayer then contentLayer = exploreOverlay end

    -- 找到 zIndex=2 的内容层并清空替换
    local getChildren = contentLayer.GetChildren
    local children = getChildren and contentLayer:GetChildren()
    if children then
        for _, child in ipairs(children) do
            local z = child.props and child.props.zIndex
            if z == 2 then
                child:ClearChildren()
                child:AddChild(MineDungeon._BuildGridPanel())
                return
            end
        end
    end

    -- fallback: 重建整个界面
    MineDungeon._RebuildGridOverlay()
end

function MineDungeon._RebuildGridOverlay()
    local UI = _UI
    if not UI then return end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    if exploreOverlay then
        exploreOverlay:Remove()
    end
    cellWidgets = {}

    exploreOverlay = UI.Panel {
        id = "mineDungeonExplore",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 150,
        pointerEvents = "auto",
        children = {
            -- 背景图
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "image/mine_explore_bg_20260430231331.png",
                backgroundFit = "cover",
                backgroundPosition = "center",
                zIndex = 0,
                pointerEvents = "none",
            },
            -- 半透明遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 120 },
                zIndex = 1,
                pointerEvents = "none",
            },
            -- 内容层
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                zIndex = 2,
                pointerEvents = "auto",
                children = {
                    MineDungeon._BuildGridPanel(),
                },
            },
        },
    }

    root:AddChild(exploreOverlay)
end

--- 构建网格面板（顶部状态 + 网格 + 底部信息）
function MineDungeon._BuildGridPanel()
    local UI = _UI
    local session = MDD.GetSession()
    if not session then return UI.Panel { width = "100%", height = 0 } end

    return UI.Panel {
        id = "gridPanel",
        width = "100%",
        flexGrow = 1,
        children = {
            -- 顶部状态栏
            MineDungeon._BuildGridHeader(),
            -- 网格区域
            MineDungeon._BuildGrid(),
            -- 下一层按钮容器（翻开钥匙后动态添加按钮）
            UI.Panel {
                id = "nextLayerBtnContainer",
                width = "100%",
                alignItems = "center",
                justifyContent = "center",
                marginTop = 12,
                marginBottom = 4,
            },
            -- 底部信息栏
            MineDungeon._BuildGridFooter(),
        },
    }
end

-- ============================================================================
-- 顶部状态栏（层数 + 翻开进度 + 体力）
-- ============================================================================

function MineDungeon._BuildGridHeader()
    local UI = _UI
    local session = MDD.GetSession()
    if not session then return UI.Panel { height = 0 } end

    local layerLabel, layerColor = MDD.GetLayerDisplay(session.layer)
    local stamina, maxSta = MDD.GetStamina()
    local secLeft, isFull = MDD.GetStaminaRecoveryInfo()

    local recoveryText
    if isFull then
        recoveryText = "已满"
    else
        local m = math.floor(secLeft / 60)
        local s = secLeft % 60
        recoveryText = string.format("%02d:%02d", m, s)
    end

    return UI.Panel {
        id = "gridHeader",
        width = "100%",
        flexShrink = 0,
        paddingTop = 12, paddingBottom = 8,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = { 20, 18, 12, 200 },
        borderBottomWidth = 1,
        borderColor = { 120, 100, 40, 100 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            -- 层数 + 翻开进度
            UI.Panel {
                gap = 2,
                children = {
                    UI.Label {
                        text = "⛏️ " .. layerLabel,
                        fontSize = 16,
                        fontColor = layerColor,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        id = "gridRevealCount",
                        text = "已翻开: " .. session.revealedCount .. "/" .. MDD.TOTAL_CELLS,
                        fontSize = 11,
                        fontColor = { 180, 170, 130, 200 },
                    },
                },
            },
            -- 体力
            UI.Panel {
                alignItems = "flex-end",
                gap = 1,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 3, paddingBottom = 3,
                        backgroundColor = { 60, 50, 15, 220 },
                        borderRadius = 6,
                        borderWidth = 1,
                        borderColor = { 200, 160, 60, 120 },
                        children = {
                            UI.Label { text = "⚡", fontSize = 12 },
                            UI.Label {
                                id = "gridStamina",
                                text = stamina .. "/" .. maxSta,
                                fontSize = 12,
                                fontColor = stamina > 0
                                    and { 100, 255, 150, 255 }
                                    or  { 255, 120, 80, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        id = "gridStaminaTimer",
                        text = recoveryText,
                        fontSize = 9,
                        fontColor = { 180, 170, 130, 160 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 网格区域
-- ============================================================================

function MineDungeon._BuildGrid()
    local UI = _UI
    local session = MDD.GetSession()
    if not session then return UI.Panel { width = "100%", height = 0 } end

    local rows = {}
    for r = 1, MDD.GRID_ROWS do
        local rowCells = {}
        for c = 1, MDD.GRID_COLS do
            local idx = (r - 1) * MDD.GRID_COLS + c
            local cell = session.cells[idx]
            local cellWidget = MineDungeon._BuildCellWidget(cell)
            cellWidgets[idx] = cellWidget
            rowCells[#rowCells + 1] = cellWidget
        end
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 8,
            children = rowCells,
        }
    end

    return UI.Panel {
        id = "mineGrid",
        width = "100%",
        flexGrow = 1,
        justifyContent = "center",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        gap = 8,
        children = rows,
    }
end

--- 构建单个格子 widget
function MineDungeon._BuildCellWidget(cell)
    local UI = _UI
    local idx = cell.index

    -- 已收集
    if cell.collected then
        return MineDungeon._BuildCollectedCell(cell)
    end

    -- 已翻开（敌人等待点击 / 资源等待收集）
    if cell.revealed then
        return MineDungeon._BuildRevealedCell(cell)
    end

    -- 未翻开
    return UI.Panel {
        id = "cell_" .. idx,
        width = 60, height = 60,
        backgroundColor = { 50, 45, 25, 240 },
        borderRadius = 10,
        borderWidth = 1.5,
        borderColor = { 140, 120, 50, 180 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            MineDungeon._OnCellClick(idx)
        end,
        children = {
            UI.Label {
                text = "?",
                fontSize = 26,
                fontColor = { 200, 180, 80, 200 },
                fontWeight = "bold",
            },
        },
    }
end

--- 已翻开但未收集的格子（显示资源图片或敌人图片）
function MineDungeon._BuildRevealedCell(cell)
    local UI = _UI
    local idx = cell.index
    local color, bgColor, img, label

    if cell.cellType == "enemy" then
        color = { 255, 80, 60, 255 }
        bgColor = { 70, 25, 15, 240 }
        img = getEnemyImage(idx)
        label = "敌人"
    elseif cell.cellType == "key" then
        color = { 255, 230, 50, 255 }
        bgColor = { 60, 55, 15, 240 }
        img = nil  -- 钥匙用 emoji
        label = nil
    else
        color = REWARD_COLORS[cell.rewardType] or { 80, 200, 255, 255 }
        bgColor = { 20, 45, 60, 240 }
        img = REWARD_IMAGES[cell.rewardType]
        label = nil
    end

    local children = {}
    if img then
        children[#children + 1] = UI.Panel {
            width = 40, height = 40,
            backgroundImage = img,
            backgroundFit = "contain",
            pointerEvents = "none",
        }
        if label then
            children[#children + 1] = UI.Label {
                text = label,
                fontSize = 8,
                fontColor = color,
            }
        end
    else
        -- 钥匙格用 emoji
        children[#children + 1] = UI.Label {
            text = "🔑",
            fontSize = 28,
        }
    end

    return UI.Panel {
        id = "cell_" .. idx,
        width = 60, height = 60,
        backgroundColor = bgColor,
        borderRadius = 10,
        borderWidth = 2,
        borderColor = color,
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            if cell.cellType == "enemy" and cell.enemyReady then
                MineDungeon._ShowBattleConfirm(cell)
            end
        end,
        children = children,
    }
end

--- 已收集的格子（显示对应图片 + 半透明 ✓ 覆盖）
function MineDungeon._BuildCollectedCell(cell)
    local UI = _UI
    local img
    if cell.cellType == "enemy" then
        img = getEnemyImage(cell.index)
    elseif cell.cellType == "resource" then
        img = REWARD_IMAGES[cell.rewardType]
    end

    local children = {}
    if img then
        children[#children + 1] = UI.Panel {
            width = 36, height = 36,
            backgroundImage = img,
            backgroundFit = "contain",
            pointerEvents = "none",
            opacity = 0.35,
        }
    elseif cell.cellType == "key" then
        -- 钥匙格：显示半透明 🔑
        children[#children + 1] = UI.Label {
            text = "🔑",
            fontSize = 24,
            opacity = 0.4,
        }
    end
    -- 右下角小 ✓
    children[#children + 1] = UI.Label {
        text = "✓",
        fontSize = 14,
        fontColor = { 100, 200, 100, 200 },
        fontWeight = "bold",
        position = "absolute",
        right = 3, bottom = 1,
    }

    -- 钥匙格用金色边框突出
    local bgColor = { 30, 28, 20, 180 }
    local bdColor = { 60, 55, 35, 100 }
    local bdWidth = 1
    if cell.cellType == "key" then
        bgColor = { 40, 38, 15, 200 }
        bdColor = { 200, 180, 50, 120 }
        bdWidth = 1.5
    end

    return UI.Panel {
        id = "cell_" .. cell.index,
        width = 60, height = 60,
        backgroundColor = bgColor,
        borderRadius = 10,
        borderWidth = bdWidth,
        borderColor = bdColor,
        justifyContent = "center",
        alignItems = "center",
        children = children,
    }
end

--- 替换格子 widget
function MineDungeon._ReplaceCell(cell)
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local oldWidget = cellWidgets[cell.index]
    if not oldWidget then return end

    local newWidget
    if cell.collected then
        newWidget = MineDungeon._BuildCollectedCell(cell)
    elseif cell.revealed then
        newWidget = MineDungeon._BuildRevealedCell(cell)
    else
        newWidget = MineDungeon._BuildCellWidget(cell)
    end

    local parent = oldWidget.parent
    if not parent then return end
    -- 找到旧 widget 在父容器中的位置
    local insertIdx = nil
    for i, ch in ipairs(parent.children) do
        if ch == oldWidget then
            insertIdx = i
            break
        end
    end
    parent:RemoveChild(oldWidget)
    if insertIdx then
        parent:InsertChild(newWidget, insertIdx)
    else
        parent:AddChild(newWidget)
    end
    cellWidgets[cell.index] = newWidget
end

-- ============================================================================
-- 底部信息栏（撤退按钮左下 + 累积奖励右下）
-- ============================================================================

function MineDungeon._BuildGridFooter()
    local UI = _UI

    return UI.Panel {
        id = "gridFooter",
        width = "100%",
        flexShrink = 0,
        backgroundColor = { 20, 18, 12, 200 },
        borderTopWidth = 1,
        borderColor = { 100, 80, 30, 100 },
        paddingTop = 8, paddingBottom = 14,
        paddingLeft = 14, paddingRight = 14,
        children = {
            -- 底部按钮行
            UI.Panel {
                id = "gridFooterButtons",
                width = "100%",
                flexDirection = "row",
                justifyContent = "flex-start",
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "返回",
                        fontSize = 12,
                        height = 32,
                        paddingLeft = 14, paddingRight = 14,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function()
                            -- 直接返回，保留进度
                            MDD.SuspendSession()
                            MineDungeon._CloseExplore()
                        end,
                    },
                },
            },
        },
    }
end

--- 刷新底部累积奖励 + 顶部状态
function MineDungeon._RefreshStatus()
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local session = MDD.GetSession()
    if not session then return end

    -- 翻开计数
    local countLabel = exploreOverlay:FindById("gridRevealCount")
    if countLabel then
        countLabel:SetText("已翻开: " .. session.revealedCount .. "/" .. MDD.TOTAL_CELLS)
    end

    -- 体力
    local stamina, maxSta = MDD.GetStamina()
    local staLabel = exploreOverlay:FindById("gridStamina")
    if staLabel then
        staLabel:SetText(stamina .. "/" .. maxSta)
        staLabel:SetStyle({
            fontColor = stamina > 0
                and { 100, 255, 150, 255 }
                or  { 255, 120, 80, 255 },
        })
    end

    -- 体力恢复倒计时
    local secLeft, isFull = MDD.GetStaminaRecoveryInfo()
    local timerLabel = exploreOverlay:FindById("gridStaminaTimer")
    if timerLabel then
        if isFull then
            timerLabel:SetText("已满")
        else
            local m = math.floor(secLeft / 60)
            local s = secLeft % 60
            timerLabel:SetText(string.format("%02d:%02d", m, s))
        end
    end

end

-- ============================================================================
-- 格子点击处理
-- ============================================================================

function MineDungeon._OnCellClick(index)
    local session = MDD.GetSession()
    if not session then return end

    local cell = session.cells[index]
    if not cell or cell.revealed then return end

    -- 翻开格子（消耗体力）
    local revealedCell, errMsg = MDD.RevealCell(index)
    if not revealedCell then
        Toast.Show(errMsg or "无法翻开", { 255, 200, 80 })
        return
    end

    -- 更新格子显示
    MineDungeon._ReplaceCell(cell)

    if cell.cellType == "resource" then
        -- 资源格：自动收集 + 弹出奖励领取界面
        MDD.CollectCellRewards(index)
        MineDungeon._ReplaceCell(cell)
        MineDungeon._RefreshStatus()

        if cell.rewards and #cell.rewards > 0 then
            showRewardInOverlay(cell.rewards, "探索奖励", nil)
        end

    elseif cell.cellType == "key" then
        -- 钥匙格：自动收集 + 解锁提示 + 显示进入下一层按钮
        MDD.CollectCellRewards(index)
        MineDungeon._ReplaceCell(cell)
        MineDungeon._RefreshStatus()

        if session.layer < MDD.MAX_LAYER then
            Toast.Show("🔑 获得钥匙！已解锁第" .. (session.layer + 1) .. "层", { 255, 230, 50 })
        else
            Toast.Show("🔑 获得钥匙！已是最高层", { 255, 230, 50 })
        end
        -- 显示底部"进入下一层"按钮
        MineDungeon._ShowNextLayerButton()

    else
        -- 敌人格：等待玩家点击后弹窗
        MineDungeon._RefreshStatus()
    end
end

-- ============================================================================
-- 战斗确认弹窗
-- ============================================================================

function MineDungeon._ShowBattleConfirm(cell)
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local session = MDD.GetSession()
    if not session then return end

    local confirmPanel = nil

    local function dismiss()
        if confirmPanel then
            confirmPanel:Remove()
            confirmPanel = nil
        end
    end

    -- 奖励预览
    local rewardItems = {}
    for _, r in ipairs(cell.rewards or {}) do
        local info = Currency.GetInfo(r.id)
        local name = info and info.name or r.id
        rewardItems[#rewardItems + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 3,
            marginRight = 6,
            children = {
                Currency.IconWidget(UI, r.id, 13),
                UI.Label {
                    text = name .. " x" .. r.amount,
                    fontSize = 10,
                    fontColor = { 220, 215, 200, 240 },
                },
            },
        }
    end

    local layerLabel, layerColor = MDD.GetLayerDisplay(session.layer)

    confirmPanel = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 900,
        pointerEvents = "auto",
        onClick = function() dismiss() end,
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 340,
                backgroundColor = { 50, 20, 15, 250 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 255, 80, 60, 200 },
                paddingTop = 18, paddingBottom = 16,
                paddingLeft = 18, paddingRight = 18,
                gap = 10,
                pointerEvents = "auto",
                onClick = function() end,  -- 阻止冒泡
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "⚔️ 遭遇敌人",
                                fontSize = 20,
                                fontColor = { 255, 100, 80, 255 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = layerLabel .. " · 是否发起挑战？",
                                fontSize = 11,
                                fontColor = layerColor,
                            },
                        },
                    },
                    -- 胜利奖励
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "胜利奖励（×" .. string.format("%.1f", MDD.ENEMY_REWARD_MULT) .. "）:",
                                fontSize = 11,
                                fontColor = { 180, 170, 140, 200 },
                            },
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                flexWrap = "wrap",
                                gap = 4,
                                children = rewardItems,
                            },
                        },
                    },
                    -- 提示
                    UI.Panel {
                        width = "100%",
                        paddingTop = 6, paddingBottom = 6,
                        paddingLeft = 10, paddingRight = 10,
                        backgroundColor = { 80, 20, 20, 150 },
                        borderRadius = 6,
                        children = {
                            UI.Label {
                                text = "⚠️ 战败不会损失已获得的奖励",
                                fontSize = 10,
                                fontColor = { 255, 180, 100, 220 },
                                textAlign = "center",
                            },
                        },
                    },
                    -- 按钮
                    UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 10,
                        children = {
                            UI.Button {
                                text = "暂不挑战",
                                fontSize = 13,
                                flexGrow = 1,
                                height = 38,
                                borderRadius = 8,
                                variant = "outline",
                                onClick = function()
                                    dismiss()
                                end,
                            },
                            UI.Button {
                                text = "⚔️ 开战",
                                fontSize = 13,
                                flexGrow = 1,
                                height = 38,
                                borderRadius = 8,
                                variant = "primary",
                                onClick = function()
                                    dismiss()
                                    MineDungeon._EnterBattle(cell)
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    exploreOverlay:AddChild(confirmPanel)
end

-- ============================================================================
-- 战斗流程
-- ============================================================================

function MineDungeon._EnterBattle(cell)
    local session = MDD.GetSession()
    if not session then return end

    local config = MDD.BuildBattleConfig(cell, session.layer)
    local GameUI = require("Game.GameUI")

    -- 隐藏探索 overlay
    if exploreOverlay then
        exploreOverlay:SetVisible(false)
    end

    config.onWin = function()
        -- 收集敌人格奖励
        MDD.CollectCellRewards(cell.index)

        local root = GameUI.GetUIRoot()
        if root and _UI then
            RewardController.ShowFromDefs(_UI, root, cell.rewards,
                "⚔️ 战斗胜利！", function()
                    if exploreOverlay then
                        exploreOverlay:SetVisible(true)
                    end
                    GameUI.ExitDungeonBattle()
                    MineDungeon._ReplaceCell(cell)
                    MineDungeon._RefreshStatus()
                end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    config.onLose = function()
        -- 战败：不损失已有奖励，只是该格子不算收集
        local root = GameUI.GetUIRoot()
        if root and _UI then
            RewardController.ShowFromDefs(_UI, root, {},
                "战斗失败", function()
                    if exploreOverlay then
                        exploreOverlay:SetVisible(true)
                    end
                    GameUI.ExitDungeonBattle()
                    -- 敌人格标记为不可再战（避免无限重试）
                    cell.enemyReady = false
                    cell.collected = true
                    MineDungeon._ReplaceCell(cell)
                    MineDungeon._RefreshStatus()
                end)
        else
            GameUI.ExitDungeonBattle()
        end
    end

    config.onExit = function(result, continueExit)
        -- 中途退出战斗：回到探索
        if exploreOverlay then
            exploreOverlay:SetVisible(true)
        end
        continueExit()
    end

    GameUI.EnterDungeonBattle(config)
end

-- （已移除确认撤退弹窗，"返回"按钮直接关闭界面并保留进度）

-- ============================================================================
-- 进入下一层按钮
-- ============================================================================

--- 在底部按钮行添加"进入下一层"按钮
function MineDungeon._ShowNextLayerButton()
    local UI = _UI
    if not UI or not exploreOverlay then return end

    local session = MDD.GetSession()
    if not session then return end

    -- 使用网格下方的专用容器
    local container = exploreOverlay:FindById("nextLayerBtnContainer")
    if not container then return end

    -- 避免重复添加
    local existing = exploreOverlay:FindById("btnNextLayer")
    if existing then return end

    local nextLayer = session.layer + 1
    local isMaxLayer = session.layer >= MDD.MAX_LAYER

    local btnText = isMaxLayer
        and "🏆 结算本层"
        or ("⛏️ 进入第" .. nextLayer .. "层")

    container:AddChild(UI.Button {
        id = "btnNextLayer",
        text = btnText,
        fontSize = 15,
        height = 44,
        paddingLeft = 30, paddingRight = 30,
        borderRadius = 10,
        variant = "primary",
        onClick = function()
            if isMaxLayer then
                MineDungeon._FinishExploration("clear")
            else
                MineDungeon._GoToNextLayer(nextLayer)
            end
        end,
    })
end

--- 结束当前层，进入下一层
function MineDungeon._GoToNextLayer(nextLayer)
    local session = MDD.GetSession()
    if not session then return end

    local layerNum = session.layer

    -- 结束当前层会话（奖励已即时发放，此处只做清理）
    MDD.EndSession("clear")

    Toast.Show("🎉 第" .. layerNum .. "层探索完成！进入第" .. nextLayer .. "层", { 100, 255, 150 })

    -- 创建下一层会话
    local newSession, msg = MDD.CreateSession(nextLayer)
    if not newSession then
        Toast.Show(msg or "无法进入下一层", { 255, 200, 80 })
        MineDungeon._CloseExplore()
        return
    end
    -- 刷新网格显示
    MineDungeon._ShowGridOverlay()
end

-- ============================================================================
-- 探索结束
-- ============================================================================

function MineDungeon._FinishExploration(reason)
    local session = MDD.GetSession()
    if not session then
        MineDungeon._CloseExplore()
        return
    end

    local layerNum = session.layer
    -- 结束会话（奖励已即时发放）
    MDD.EndSession(reason)

    Toast.Show("🏆 第" .. layerNum .. "层探索完成！", { 255, 230, 50 })
    MineDungeon._CloseExplore()
end

return MineDungeon
