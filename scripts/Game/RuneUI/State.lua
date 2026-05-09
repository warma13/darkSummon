-- RuneUI/State.lua
-- 共享状态 + section wrapper 工具函数

local State = {}

-- ── UI 框架引用 ──
---@type any
State.UI = nil
---@type any
State.pageRoot = nil

-- ── 选中状态 ──
---@type string|nil
State.selectedHero = nil
---@type table|nil
State.selectedRune = nil
---@type string|nil
State.selectedSource = nil   -- "bag" / "equipped"
---@type number|nil
State.selectedSlotIdx = nil

-- ── 嵌入模式 ──
---@type boolean
State.embedded = false
---@type function|nil
State.embeddedRefresh = nil

-- ── 滚动位置记忆 ──
---@type number
State.bagScrollY = 0

-- ── Section ID 常量 ──
State.ID = {
    HEADER         = "rs_header",
    HERO_SELECTOR  = "rs_hero_sel",
    EQUIPPED_SLOTS = "rs_equip",
    SET_BONUS      = "rs_setbonus",
    BAG_PANEL      = "rs_bag",
    BOTTOM_BAR     = "rs_bottom",
    DETAIL_OVERLAY = "rs_detail",
    EMPTY_HINT     = "rs_empty",
}

--- 创建一个稳定 wrapper Panel（id 固定，内容可替换）
---@param id string
---@param content any  inner widget
---@param extraProps table|nil  额外属性
---@return any  wrapper Panel
function State.Wrap(id, content, extraProps)
    local props = {
        id = id,
        width = "100%",
        flexShrink = 0,
        children = content and { content } or {},
    }
    if extraProps then
        for k, v in pairs(extraProps) do
            props[k] = v
        end
    end
    return State.UI.Panel(props)
end

--- 局部刷新：找到 wrapper → 清空 → 填入新内容
---@param sectionId string
---@param content any  new inner widget
function State.RefreshSection(sectionId, content)
    if not State.pageRoot then return end
    local wrapper = State.pageRoot:FindById(sectionId)
    if not wrapper then return end
    wrapper:ClearChildren()
    if content then
        wrapper:AddChild(content)
    end
end

--- 移除浮层（如果存在）
---@param sectionId string
function State.RemoveOverlay(sectionId)
    if not State.pageRoot then return end
    local overlay = State.pageRoot:FindById(sectionId)
    if overlay then
        State.pageRoot:RemoveChild(overlay)
    end
end

return State
