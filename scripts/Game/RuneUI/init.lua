-- RuneUI/init.lua
-- 符文页面主控制器 + 增量刷新调度
--
-- 增量策略：
--   每个 section 用带 id 的 wrapper Panel 包裹，操作后只重建受影响的 section。
--   overlay（详情/弹窗）直接 add/remove，不触碰底层 section。

local HeroData = require("Game.HeroData")
local RuneData = require("Game.RuneData")

local S        = require("Game.RuneUI.State")
local ID       = S.ID
local Sections = require("Game.RuneUI.Sections")
local EquipSlots = require("Game.RuneUI.EquippedSlots")
local BagPanel = require("Game.RuneUI.BagPanel")
local DetailOverlay = require("Game.RuneUI.DetailOverlay")
local Popups   = require("Game.RuneUI.Popups")

local RuneUI = {}

-- ============================================================================
-- 回调工厂（传给子模块，避免循环 require）
-- ============================================================================

--- 选中符文回调（点击格子）
local function onSelectRune(rune, source, heroId, slotIdx)
    S.selectedRune = rune
    S.selectedSource = source
    if source == "equipped" then
        S.selectedHero = heroId
        S.selectedSlotIdx = slotIdx
    else
        -- bag rune: keep selectedSource = "bag"
    end
    -- 只添加详情浮层，不重建底层
    RuneUI._showDetailOverlay()
end

--- 点击空槽回调
local function onSlotClick(slotIdx)
    S.selectedRune = nil
    S.selectedSource = nil
    S.selectedSlotIdx = slotIdx
    -- 仅刷新 equipped slots（高亮选中槽位）
    S.RefreshSection(ID.EQUIPPED_SLOTS, EquipSlots.Build(onSelectRune, onSlotClick))
end

--- 排序回调
local function onSort()
    RuneData.SortBag()
    RuneUI._refreshBag()
end

--- 扩容回调
local function onExpandBag()
    Popups.ShowExpandBag(function(reason)
        RuneUI._refreshBag()
        RuneUI._refreshBottomBar()
    end)
end

--- 批量分解回调
local function onBatchDecompose()
    Popups.ShowBatchDecompose(function(reason)
        RuneUI._refreshEquipArea()
        RuneUI._refreshBag()
        RuneUI._refreshBottomBar()
    end)
end

--- 详情浮层内操作完成回调（增量刷新调度中枢）
---@param reason string
local function onDetailAction(reason)
    if reason == "close_detail" then
        -- 仅移除浮层
        S.RemoveOverlay(ID.DETAIL_OVERLAY)

    elseif reason == "equip" or reason == "unequip" then
        -- 装备/卸下 → 移除浮层 + 刷新 equipped + setBonus + bag + bottomBar
        S.RemoveOverlay(ID.DETAIL_OVERLAY)
        RuneUI._refreshEquipArea()
        RuneUI._refreshBag()
        RuneUI._refreshBottomBar()

    elseif reason == "decompose" then
        -- 分解 → 移除浮层 + 刷新 bag + bottomBar
        S.RemoveOverlay(ID.DETAIL_OVERLAY)
        RuneUI._refreshBag()
        RuneUI._refreshBottomBar()

    elseif reason == "rune_lock" then
        -- 锁定/解锁 → 重建浮层 + 刷新 bag（锁定图标变化）
        RuneUI._showDetailOverlay()
        RuneUI._refreshBag()

    elseif reason == "affix_lock" then
        -- 词条锁定 → 只重建浮层
        RuneUI._showDetailOverlay()

    elseif reason == "reforge" then
        -- 洗练完成 → 重建浮层 + 刷新 bag
        RuneUI._showDetailOverlay()
        RuneUI._refreshBag()

    else
        -- 兜底：全量刷新
        RuneUI.Refresh()
    end
end

--- 英雄选择回调
local function onHeroChange(reason)
    -- 切换英雄 → 重置滚动位置 + 刷新 heroSelector + equipped + setBonus + bag，移除 overlay
    S.bagScrollY = 0
    S.RemoveOverlay(ID.DETAIL_OVERLAY)
    S.RefreshSection(ID.HERO_SELECTOR, Sections.BuildHeroSelector(onHeroChange))
    RuneUI._refreshEquipArea()
    RuneUI._refreshBag()
end

-- ============================================================================
-- 增量刷新 helpers
-- ============================================================================

function RuneUI._refreshEquipArea()
    S.RefreshSection(ID.EQUIPPED_SLOTS, EquipSlots.Build(onSelectRune, onSlotClick))
    S.RefreshSection(ID.SET_BONUS, Sections.BuildSetBonusBar())
end

function RuneUI._restoreBagScroll()
    if S.bagScrollY > 0 then
        local sv = S.pageRoot and S.pageRoot:FindById("rune_bag_scroll")
        if sv and sv.SetScrollDirect then
            -- 用 SetScrollDirect 绕过边界 clamp（新 ScrollView 布局未完成时
            -- contentHeight_ 为 0，SetScroll 会把值 clamp 回 0）。
            -- 下一帧 OnUpdate 会自动把越界值平滑修正回合法范围。
            sv:SetScrollDirect(0, S.bagScrollY)
        end
    end
end

function RuneUI._refreshBag()
    S.RefreshSection(ID.BAG_PANEL, BagPanel.Build(onSelectRune, onSort, onExpandBag, onBatchDecompose))
    RuneUI._restoreBagScroll()
end

function RuneUI._refreshBottomBar()
    S.RefreshSection(ID.BOTTOM_BAR, Sections.BuildBottomBar())
end

function RuneUI._showDetailOverlay()
    -- 先移除旧的（如果有）
    S.RemoveOverlay(ID.DETAIL_OVERLAY)
    if S.selectedRune then
        S.pageRoot:AddChild(DetailOverlay.Build(onDetailAction))
    end
end

-- ============================================================================
-- 公开 API（保持与原 RuneUI.lua 完全相同的外部接口）
-- ============================================================================

--- 初始化
---@param uiModule any
function RuneUI.Init(uiModule)
    S.UI = uiModule
end

--- 创建符文页面
---@param uiModule any
---@return any
function RuneUI.CreatePage(uiModule)
    S.UI = uiModule
    S.embedded = false
    S.embeddedRefresh = nil

    if not S.selectedHero then
        if #HeroData.deployed > 0 then
            S.selectedHero = HeroData.deployed[1]
        end
    end

    S.pageRoot = S.UI.Panel {
        id = "runePage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 15, 12, 25, 255 },
        children = {},
    }

    RuneUI._buildAllSections()
    return S.pageRoot
end

--- 全量刷新（兜底，也用于嵌入模式和首次构建后的外部调用）
function RuneUI.Refresh()
    if not S.pageRoot or not S.UI then return end

    -- 嵌入模式下委托外部刷新
    if S.embedded and S.embeddedRefresh then
        S.embeddedRefresh()
        return
    end

    if not S.selectedHero or not HeroData.IsDeployed(S.selectedHero) then
        S.selectedHero = nil
        if #HeroData.deployed > 0 then
            S.selectedHero = HeroData.deployed[1]
        end
    end

    S.pageRoot:ClearChildren()
    RuneUI._buildAllSections()
end

--- 嵌入模式（EquipUI 的 tab 中使用）
---@param parentPanel any
---@param refreshFn function|nil
function RuneUI.RenderInto(parentPanel, refreshFn)
    if not S.UI then return end

    S.embedded = true
    S.embeddedRefresh = refreshFn

    if not S.selectedHero or not HeroData.IsDeployed(S.selectedHero) then
        S.selectedHero = nil
        if #HeroData.deployed > 0 then
            S.selectedHero = HeroData.deployed[1]
        end
    end

    S.pageRoot = parentPanel

    -- 嵌入模式不显示 Header
    parentPanel:AddChild(S.Wrap(ID.HERO_SELECTOR, Sections.BuildHeroSelector(onHeroChange)))

    if S.selectedHero then
        parentPanel:AddChild(S.Wrap(ID.EQUIPPED_SLOTS, EquipSlots.Build(onSelectRune, onSlotClick)))
        parentPanel:AddChild(S.Wrap(ID.SET_BONUS, Sections.BuildSetBonusBar()))
        parentPanel:AddChild(S.Wrap(ID.BAG_PANEL,
            BagPanel.Build(onSelectRune, onSort, onExpandBag, onBatchDecompose),
            { flexGrow = 1, flexShrink = 1 }
        ))
        parentPanel:AddChild(S.Wrap(ID.BOTTOM_BAR, Sections.BuildBottomBar()))
        if S.selectedRune then
            parentPanel:AddChild(DetailOverlay.Build(onDetailAction))
        end
    else
        parentPanel:AddChild(S.Wrap(ID.EMPTY_HINT, S.UI.Panel {
            width = "100%", flexGrow = 1,
            justifyContent = "center", alignItems = "center",
            children = {
                S.UI.Label {
                    text = "请先在英雄页上阵英雄",
                    fontSize = 14, fontColor = { 150, 140, 130, 180 },
                },
            },
        }))
        parentPanel:AddChild(S.Wrap(ID.BOTTOM_BAR, Sections.BuildBottomBar()))
    end
end

--- 帧更新
---@param dt number
function RuneUI.Update(dt)
    -- 暂无帧更新需求
end

-- ============================================================================
-- 内部：构建所有 section（首次 / 全量刷新时调用）
-- ============================================================================

function RuneUI._buildAllSections()
    local root = S.pageRoot

    -- 顶部标题 + 货币
    root:AddChild(S.Wrap(ID.HEADER, Sections.BuildHeader()))
    -- 英雄选择栏
    root:AddChild(S.Wrap(ID.HERO_SELECTOR, Sections.BuildHeroSelector(onHeroChange)))

    if S.selectedHero then
        -- 已装备符文槽
        root:AddChild(S.Wrap(ID.EQUIPPED_SLOTS, EquipSlots.Build(onSelectRune, onSlotClick)))
        -- 套装效果
        root:AddChild(S.Wrap(ID.SET_BONUS, Sections.BuildSetBonusBar()))
        -- 符文背包
        root:AddChild(S.Wrap(ID.BAG_PANEL,
            BagPanel.Build(onSelectRune, onSort, onExpandBag, onBatchDecompose),
            { flexGrow = 1, flexShrink = 1 }
        ))
        -- 底部货币栏
        root:AddChild(S.Wrap(ID.BOTTOM_BAR, Sections.BuildBottomBar()))

        -- 详情浮层
        if S.selectedRune then
            root:AddChild(DetailOverlay.Build(onDetailAction))
        end

        -- 恢复背包滚动位置
        RuneUI._restoreBagScroll()
    else
        root:AddChild(S.Wrap(ID.EMPTY_HINT, S.UI.Panel {
            width = "100%", flexGrow = 1,
            justifyContent = "center", alignItems = "center",
            children = {
                S.UI.Label {
                    text = "请先在英雄页上阵英雄",
                    fontSize = 14, fontColor = { 150, 140, 130, 180 },
                },
            },
        }))
        root:AddChild(S.Wrap(ID.BOTTOM_BAR, Sections.BuildBottomBar()))
    end
end

return RuneUI
