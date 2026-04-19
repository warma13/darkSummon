-- Game/Tooltip.lua
-- 通用浮窗组件，可在任意页面复用
--
-- 用法:
--   local Tooltip = require("Game.Tooltip")
--   Tooltip.Show({ title = "物品名", desc = "描述文字", anchor = widget })
--   Tooltip.Hide()
--
-- 无需手动 Init，首次 Show 时自动创建浮窗层

local Tooltip = {}

---@type any UI 模块引用（懒获取）
local UI = nil
---@type any 浮窗容器（absolute 全屏遮罩）
local panel = nil

-- 样式
local STYLE = {
    bg        = { 20, 16, 38, 230 },
    border    = { 120, 90, 180, 180 },
    titleColor = { 255, 220, 100, 255 },
    descColor  = { 190, 180, 210, 220 },
    dismissBg  = { 0, 0, 0, 1 },
    radius     = 10,
    padding    = 10,
    gap        = 4,
    width      = 160,
    height     = 64,
    margin     = 8,   -- 距屏幕边缘最小间距
    spacing    = 6,    -- 距 anchor 间距
}

--- 懒初始化：确保 UI 和 panel 就绪
---@return boolean 是否就绪
local function ensureReady()
    if panel and UI then return true end

    -- 尝试获取 UI 模块
    if not UI then
        local ok, uiMod = pcall(require, "urhox-libs/UI")
        if ok and uiMod then
            UI = uiMod
        else
            return false
        end
    end

    -- 获取根节点
    local root = UI.GetRoot and UI.GetRoot()
    if not root then return false end

    -- 创建浮窗层（zIndex 极高，始终在最顶层）
    panel = UI.Panel {
        id = "tooltipLayer",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        zIndex = 99999,
        pointerEvents = "box-none",
    }
    root:AddChild(panel)
    return true
end

--- 兼容旧接口：手动初始化（可选，不再必须）
---@param uiModule any  UI 模块引用
---@param parent any    父容器
---@return any panel    浮窗层引用
function Tooltip.Init(uiModule, parent)
    UI = uiModule
    -- 有旧调用也走懒初始化路径，确保挂在根节点
    if not panel then
        local root = UI.GetRoot and UI.GetRoot()
        if root then
            panel = UI.Panel {
                id = "tooltipLayer",
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                visible = false,
                zIndex = 99999,
                pointerEvents = "box-none",
            }
            root:AddChild(panel)
        end
    end
    return panel
end

--- 显示浮窗
---@param opts table { title: string, desc: string, anchor: Widget, titleColor?: table, descColor?: table }
function Tooltip.Show(opts)
    if not opts or not opts.anchor then return end

    -- 懒初始化
    if not panel or not UI then
        if not ensureReady() then return end
    end

    local anchor = opts.anchor
    local title = opts.title or ""
    local desc = opts.desc or ""

    -- 获取 anchor 的绝对布局位置
    local layout = anchor:GetAbsoluteLayoutForHitTest()
    local ax, ay = layout.x, layout.y
    local aw, ah = layout.w, layout.h

    -- 浮窗尺寸
    local tw = STYLE.width
    local th = STYLE.height
    local margin = STYLE.margin
    local spacing = STYLE.spacing

    -- 默认居中于 anchor 上方
    local tx = ax + aw / 2 - tw / 2
    local ty = ay - th - spacing

    -- 边界修正（用 panel 自身布局宽度，与 anchor 坐标系一致）
    local parentLayout = panel:GetAbsoluteLayoutForHitTest()
    local parentW = parentLayout.w
    if tx + tw > parentW - margin then tx = parentW - margin - tw end
    if tx < margin then tx = margin end
    if ty < margin then ty = ay + ah + spacing end  -- 放到下方

    -- 重建内容
    panel:ClearChildren()

    -- 点击遮罩（点任意位置关闭）
    panel:AddChild(UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = STYLE.dismissBg,
        pointerEvents = "auto",
        onClick = function() Tooltip.Hide() end,
    })

    -- 气泡
    panel:AddChild(UI.Panel {
        position = "absolute",
        left = tx,
        top = ty,
        width = tw,
        backgroundColor = STYLE.bg,
        borderRadius = STYLE.radius,
        borderWidth = 1,
        borderColor = STYLE.border,
        paddingLeft = STYLE.padding, paddingRight = STYLE.padding,
        paddingTop = STYLE.padding - 2, paddingBottom = STYLE.padding - 2,
        flexDirection = "column",
        gap = STYLE.gap,
        pointerEvents = "auto",
        children = {
            UI.Label {
                text = title,
                fontSize = 13,
                fontColor = opts.titleColor or STYLE.titleColor,
                fontWeight = "bold",
            },
            desc ~= "" and UI.Label {
                text = desc,
                fontSize = 11,
                fontColor = opts.descColor or STYLE.descColor,
            } or nil,
        },
    })

    panel:SetVisible(true)
end

--- 隐藏浮窗
function Tooltip.Hide()
    if panel then
        panel:SetVisible(false)
    end
end

--- 是否正在显示
---@return boolean
function Tooltip.IsVisible()
    return panel ~= nil and panel:IsVisible()
end

return Tooltip
