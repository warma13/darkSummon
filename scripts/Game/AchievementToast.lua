-- Game/AchievementToast.lua
-- 成就达成弹出动画：从顶部滑入，3秒后滑出
-- 新成就会把旧的往下挤，重置计时器后全部一起滑出

local AchievementToast = {}

-- ── 配置 ──────────────────────────────────────
local DISPLAY_TIME   = 3.0      -- 展示时长(秒)，最后一条加入后重新计时
local SLIDE_SPEED    = 600      -- 滑出速度(逻辑像素/秒)
local ENTER_DURATION = 0.3      -- 单条入场动画时长(秒)
local ENTER_OFFSET   = 60       -- 入场时从上方偏移的距离
local LERP_SPEED     = 12       -- 旧条目下移的插值速度(越大越快)
local ITEM_HEIGHT    = 52       -- 单条高度
local ITEM_GAP       = 6        -- 条目间距
local ROW_STEP       = ITEM_HEIGHT + ITEM_GAP  -- 每行占高
local MAX_VISIBLE    = 5        -- 同时最多显示条数
local BANNER_WIDTH   = 280      -- 横幅宽度
local CORNER_RADIUS  = 10
local START_Y        = 10       -- 距顶部基准

-- 颜色
local BG_COLOR       = { 15, 12, 25, 220 }
local BORDER_COLOR   = { 255, 200, 50, 200 }
local TITLE_COLOR    = { 255, 215, 0, 255 }
local DESC_COLOR     = { 220, 220, 230, 255 }
local ICON_BG_COLOR  = { 255, 200, 50, 40 }

-- ── 状态 ──────────────────────────────────────
local items = {}
--   每条: { name, desc, age, currentY }
--   age  = 该条目已存在时间，控制自身入场动画
--   currentY = 当前渲染 Y（用插值平滑过渡到目标位置）

local dismissTimer = 0          -- 距最后一条加入的时间
local phase = "idle"            -- "idle" | "showing" | "slide_out"
local slideOutOffset = 0

-- ── 工具 ──────────────────────────────────────
local function clamp01(v) return math.max(0, math.min(1, v)) end
local function lerp(a, b, t) return a + (b - a) * t end

-- ── 公开 API ──────────────────────────────────

--- 显示一条成就弹出
---@param name string 成就名称
---@param desc string 成就描述(可选)
function AchievementToast.Show(name, desc)
    -- 如果正在滑出，立即清掉旧的，重新开始
    if phase == "slide_out" then
        items = {}
        slideOutOffset = 0
    end

    -- 超过上限移除最旧的
    while #items >= MAX_VISIBLE do
        table.remove(items, 1)
    end

    -- 新条目：age=0 表示刚加入，currentY 初始为目标位置上方(稍后入场动画处理)
    local slot = #items  -- 0-based，插入后变为最后一条
    items[#items + 1] = {
        name     = name or "成就达成",
        desc     = desc or "",
        age      = 0,
        currentY = START_Y + slot * ROW_STEP - ENTER_OFFSET,  -- 初始在目标位置上方
    }

    -- 重置退出计时器(最后一条加入后重新等 DISPLAY_TIME)
    dismissTimer = 0
    phase = "showing"
end

--- 每帧更新
---@param dt number
function AchievementToast.Update(dt)
    if phase == "idle" then return end

    -- 更新每条的 age
    for _, item in ipairs(items) do
        item.age = item.age + dt
    end

    if phase == "showing" then
        dismissTimer = dismissTimer + dt

        -- 平滑插值每条到目标 Y
        for idx, item in ipairs(items) do
            local targetY = START_Y + (idx - 1) * ROW_STEP
            item.currentY = lerp(item.currentY, targetY, clamp01(LERP_SPEED * dt))
            -- 避免无限逼近，足够近就吸附
            if math.abs(item.currentY - targetY) < 0.5 then
                item.currentY = targetY
            end
        end

        if dismissTimer >= DISPLAY_TIME then
            phase = "slide_out"
            slideOutOffset = 0
        end
    elseif phase == "slide_out" then
        slideOutOffset = slideOutOffset + SLIDE_SPEED * dt

        -- 所有条目 Y 减去滑出偏移
        local totalH = #items * ROW_STEP
        if slideOutOffset >= totalH + 20 then
            items = {}
            phase = "idle"
            dismissTimer = 0
            slideOutOffset = 0
        end
    end
end

--- 绘制单条横幅
---@param vg userdata
---@param screenW number
---@param item table
---@param y number
---@param alpha number
local function _DrawBanner(vg, screenW, item, y, alpha)
    local centerX = screenW * 0.5
    local boxW = BANNER_WIDTH
    local boxH = ITEM_HEIGHT
    local boxX = centerX - boxW * 0.5

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, boxX, y, boxW, boxH, CORNER_RADIUS)
    nvgFillColor(vg, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3],
        math.floor(BG_COLOR[4] * alpha)))
    nvgFill(vg)

    -- 边框
    nvgStrokeColor(vg, nvgRGBA(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3],
        math.floor(BORDER_COLOR[4] * alpha)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 左侧奖杯图标区域
    local iconSize = 32
    local iconX = boxX + 10
    local iconY = y + (boxH - iconSize) * 0.5

    nvgBeginPath(vg)
    nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 6)
    nvgFillColor(vg, nvgRGBA(ICON_BG_COLOR[1], ICON_BG_COLOR[2], ICON_BG_COLOR[3],
        math.floor(ICON_BG_COLOR[4] * alpha)))
    nvgFill(vg)

    -- 奖杯 emoji
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, math.floor(255 * alpha)))
    nvgText(vg, iconX + iconSize * 0.5, iconY + iconSize * 0.5, "\xF0\x9F\x8F\x86", nil)

    -- 文字区域
    local textX = iconX + iconSize + 10

    -- 标题 "成就达成"
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3],
        math.floor(TITLE_COLOR[4] * alpha * 0.7)))
    nvgText(vg, textX, y + 7, "成就达成", nil)

    -- 成就名称
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3],
        math.floor(TITLE_COLOR[4] * alpha)))
    nvgText(vg, textX, y + 21, item.name, nil)

    -- 描述
    if item.desc and item.desc ~= "" then
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3],
            math.floor(DESC_COLOR[4] * alpha * 0.8)))
        nvgText(vg, textX, y + 38, item.desc, nil)
    end
end

--- NanoVG 渲染
---@param vg userdata NanoVG 上下文
---@param screenW number 逻辑宽度
---@param fontFaceId number 字体 ID
function AchievementToast.Draw(vg, screenW, fontFaceId)
    if #items == 0 then return end

    nvgFontFaceId(vg, fontFaceId)

    for _, item in ipairs(items) do
        -- 基础 Y = 插值后的 currentY
        local y = item.currentY

        -- 入场动画：前 ENTER_DURATION 秒淡入（只影响透明度，位移由 currentY 插值处理）
        local enterT = clamp01(item.age / ENTER_DURATION)

        -- 滑出偏移
        if phase == "slide_out" then
            y = y - slideOutOffset
        end

        -- 透明度
        local alpha = enterT
        if phase == "slide_out" then
            local fadeRatio = clamp01((y + ITEM_HEIGHT) / ITEM_HEIGHT)
            alpha = alpha * fadeRatio
        end

        if alpha <= 0.01 then goto continue end

        _DrawBanner(vg, screenW, item, y, alpha)

        ::continue::
    end
end

return AchievementToast
