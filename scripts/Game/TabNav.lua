-- Game/TabNav.lua
-- 底部标签栏导航 + 页面容器管理

local Config = require("Game.Config")
local State = require("Game.State")

local AudioManager = require("Game.AudioManager")

local TabNav = {}

-- ============================================================================
-- 红点条件检测
-- ============================================================================

--- 英雄页红点：有英雄可升级/升星/进阶
---@return boolean
local function CheckHeroRedDot()
    local HeroData = require("Game.HeroData")
    for _, towerDef in ipairs(Config.TOWER_TYPES) do
        local h = HeroData.heroes[towerDef.id]
        if h and h.unlocked then
            -- 可升级？
            local cap = HeroData.GetCurrentLevelCap(towerDef.id)
            if h.level < cap then
                local cost = HeroData.GetLevelUpCost(h.level)
                if (HeroData.currencies.nether_crystal or 0) >= cost then
                    return true
                end
            end
            -- 可升星？
            if h.star < Config.MAX_HERO_STAR then
                local cost = HeroData.GetStarUpCost(h.star)
                if h.fragments >= cost then
                    return true
                end
            end
            -- 可进阶？
            local gate = HeroData.GetPendingAdvanceGate(towerDef.id)
            if gate and (HeroData.currencies.devour_stone or 0) >= gate.stones then
                return true
            end
        end
    end
    return false
end

--- 装备页红点：有装备可升级/突破
---@return boolean
local function CheckEquipRedDot()
    local HeroData = require("Game.HeroData")
    local EquipData = require("Game.EquipData")
    for _, towerDef in ipairs(Config.TOWER_TYPES) do
        local h = HeroData.heroes[towerDef.id]
        if h and h.unlocked then
            for _, slot in ipairs(Config.EQUIP_SLOTS) do
                local equips = EquipData.GetHeroEquips(towerDef.id)
                local e = equips[slot.id]
                if e then
                    local tier = Config.EQUIP_TIERS[e.tierIdx]
                    -- 可升级？
                    if e.level < tier.maxLevel and e.level < h.level then
                        local cost = EquipData.GetUpgradeCost(e.level)
                        if (HeroData.currencies.forge_iron or 0) >= cost then
                            return true
                        end
                    end
                    -- 可突破？
                    if e.level >= tier.maxLevel and e.tierIdx < #Config.EQUIP_TIERS then
                        local nextTier = Config.EQUIP_TIERS[e.tierIdx + 1]
                        if (HeroData.currencies.forge_iron or 0) >= nextTier.breakCost then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--- 宝箱页红点：有宝箱可开 或 里程碑可领
---@return boolean
local function CheckChestRedDot()
    local ChestData = require("Game.ChestData")
    -- 有任一宝箱库存 > 0
    for _, ct in ipairs(Config.CHEST_TYPES) do
        if ChestData.GetCount(ct.id) > 0 then
            return true
        end
    end
    -- 里程碑可领取
    local canClaim = ChestData.CanClaimMilestone()
    if canClaim then return true end
    return false
end

--- 副本页红点：有任一副本今日剩余次数 > 0
---@return boolean
local function CheckDungeonRedDot()
    local RD = require("Game.ResourceDungeonData")
    for _, def in ipairs(RD.DUNGEON_DEFS) do
        if RD.GetRemainingAttempts(def.key) > 0 then
            return true
        end
    end
    return false
end

--- 各标签红点检测函数映射
local TAB_RED_DOT_CHECKERS = {
    hero    = CheckHeroRedDot,
    equip   = CheckEquipRedDot,
    chest   = CheckChestRedDot,
    dungeon = CheckDungeonRedDot,
}

-- 标签定义
local TAB_DEFS = {
    { key = "hero",    label = "英雄",   icon = "image/tab_battle.png" },
    { key = "equip",   label = "装备",   icon = "image/tab_equip.png" },
    { key = "battle",  label = "战斗",   icon = "image/tab_hero.png" },
    { key = "chest",   label = "宝箱",   icon = "image/tab_chest.png" },
    { key = "dungeon", label = "副本",   icon = "image/tab_dungeon.png" },
}

local TAB_BAR_HEIGHT = 56

---@type any
local uiRef = nil         -- UI 模块引用
---@type any
local tabBarRef = nil      -- 标签栏面板引用
---@type table<string, any>
local pageRefs = {}        -- key -> 页面面板引用
---@type function|nil
local onSwitchCallback = nil  -- 切换回调

--- 创建底部标签栏和页面容器
---@param UI any  UI 模块
---@param pages table  { hero=Panel, battle=Panel, chest=Panel, activity=Panel }
---@param onSwitch function|nil  切换回调 function(fromKey, toKey)
---@return any  根面板
function TabNav.Create(UI, pages, onSwitch)
    uiRef = UI
    onSwitchCallback = onSwitch
    pageRefs = pages

    -- 页面容器: 占满除标签栏外的区域
    local pageChildren = {}
    for _, def in ipairs(TAB_DEFS) do
        local page = pages[def.key]
        if page then
            pageChildren[#pageChildren + 1] = page
        end
    end

    local pageContainer = UI.Panel {
        id = "pageContainer",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = TAB_BAR_HEIGHT,
        pointerEvents = "box-none",
        children = pageChildren,
    }

    -- 标签栏
    local tabButtons = {}
    for _, def in ipairs(TAB_DEFS) do
        local isActive = (def.key == State.activeTab)
        local fontColor = isActive and Config.TAB_COLORS.active or Config.TAB_COLORS.inactive
        -- 红点初始状态
        local checker = TAB_RED_DOT_CHECKERS[def.key]
        local showRedDot = checker and checker() or false

        tabButtons[#tabButtons + 1] = UI.Panel {
            id = "tab_" .. def.key,
            flex = 1,
            height = "100%",
            justifyContent = "center",
            alignItems = "center",
            gap = 2,
            pointerEvents = "auto",
            onClick = function(self)
                AudioManager.PlayClickTab()
                TabNav.SwitchTo(def.key)
            end,
            children = {
                -- 图标容器（相对定位，用于承载红点）
                UI.Panel {
                    width = 28, height = 28,
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            id = "tabIcon_" .. def.key,
                            width = 24,
                            height = 24,
                            backgroundImage = def.icon,
                            backgroundSize = "contain",
                            opacity = isActive and 1.0 or 0.5,
                            pointerEvents = "none",
                        },
                        -- 红点
                        UI.Panel {
                            id = "tabRedDot_" .. def.key,
                            position = "absolute",
                            top = 0, right = 0,
                            width = 8, height = 8,
                            borderRadius = 4,
                            backgroundColor = { 255, 50, 50, 255 },
                            visible = showRedDot,
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Label {
                    id = "tabLabel_" .. def.key,
                    text = def.label,
                    fontSize = 11,
                    fontColor = fontColor,
                    pointerEvents = "none",
                },
            },
        }
    end

    tabBarRef = UI.Panel {
        id = "tabBar",
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        height = TAB_BAR_HEIGHT,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = Config.TAB_COLORS.bg,
        borderWidth = 1,
        borderColor = Config.TAB_COLORS.border,
        pointerEvents = "auto",
        children = tabButtons,
    }

    -- 初始显示: 只显示当前激活页
    for _, def in ipairs(TAB_DEFS) do
        local page = pages[def.key]
        if page then
            page:SetVisible(def.key == State.activeTab)
        end
    end

    -- 根面板
    local root = UI.Panel {
        id = "tabNavRoot",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            pageContainer,
            tabBarRef,
        },
    }

    print("[TabNav] Created with activeTab=" .. State.activeTab)
    return root
end

--- 切换到指定标签页
---@param targetKey string
function TabNav.SwitchTo(targetKey)
    -- 点击已激活的非战斗标签 → 切回战斗页
    if targetKey == State.activeTab then
        if targetKey ~= "battle" then
            targetKey = "battle"
        else
            return
        end
    end

    local fromKey = State.activeTab

    -- 隐藏当前页，显示目标页
    for _, def in ipairs(TAB_DEFS) do
        local page = pageRefs[def.key]
        if page then
            page:SetVisible(def.key == targetKey)
        end
    end

    -- 更新标签栏样式
    TabNav.UpdateTabStyles(targetKey)

    State.activeTab = targetKey

    -- 触发回调
    if onSwitchCallback then
        onSwitchCallback(fromKey, targetKey)
    end

    print("[TabNav] Switched from " .. fromKey .. " to " .. targetKey)
end

--- 更新标签栏高亮样式
---@param activeKey string
function TabNav.UpdateTabStyles(activeKey)
    if not tabBarRef then return end
    for _, def in ipairs(TAB_DEFS) do
        local isActive = (def.key == activeKey)
        local color = isActive and Config.TAB_COLORS.active or Config.TAB_COLORS.inactive
        local iconPanel = tabBarRef:FindById("tabIcon_" .. def.key)
        if iconPanel then
            iconPanel:SetStyle({ opacity = isActive and 1.0 or 0.5 })
        end
        local textLabel = tabBarRef:FindById("tabLabel_" .. def.key)
        if textLabel then
            textLabel:SetStyle({ fontColor = color })
        end
    end
end

--- 获取标签栏高度（供外部布局使用）
function TabNav.GetBarHeight()
    return TAB_BAR_HEIGHT
end

--- 设置标签栏显示/隐藏
---@param visible boolean
function TabNav.SetBarVisible(visible)
    if tabBarRef then
        tabBarRef:SetVisible(visible)
    end
end

--- 刷新所有标签的红点状态
function TabNav.RefreshRedDots()
    if not tabBarRef then return end
    for key, checker in pairs(TAB_RED_DOT_CHECKERS) do
        local dot = tabBarRef:FindById("tabRedDot_" .. key)
        if dot then
            local ok, show = pcall(checker)
            dot:SetVisible(ok and show or false)
        end
    end
end

return TabNav
