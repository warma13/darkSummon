-- Game/Toast.lua
-- 屏幕中上信息提示：上浮 + 淡出，新消息顶旧消息，最多 3 条

local Toast = {}

-- ── 配置 ──────────────────────────────────────
local MAX_VISIBLE   = 3       -- 同时可见最大条数
local LIFE_TIME     = 2.0     -- 每条消息总存活时间(秒)
local FADE_START    = 1.2     -- 开始淡出的时刻(秒)
local FLOAT_SPEED   = 30      -- 上浮速度(逻辑像素/秒)
local FONT_SIZE     = 16
local PAD_H         = 16      -- 水平内边距
local PAD_V         = 6       -- 垂直内边距
local GAP           = 4       -- 条目间距
local TOP_MARGIN    = 50      -- 距屏幕顶部距离
local BG_COLOR      = { 20, 20, 30, 180 }   -- 背景色
local TEXT_COLOR    = { 230, 230, 240, 255 } -- 默认文字色
local CORNER_RADIUS = 8

-- ── 内部状态 ──────────────────────────────────
local messages = {}  -- { text, color, life }

--- 是否有待显示的消息
function Toast.IsEmpty()
    return #messages == 0
end

-- ── 公开 API ──────────────────────────────────

--- 显示一条提示消息
---@param text string 消息文本
---@param color? table {r,g,b} 或 {r,g,b,a}，可选
function Toast.Show(text, color)
    -- 超过上限时移除最旧的
    while #messages >= MAX_VISIBLE do
        table.remove(messages, 1)
    end
    messages[#messages + 1] = {
        text  = text,
        color = color or TEXT_COLOR,
        life  = 0,        -- 已存活时间，从 0 开始递增
    }
end

--- 每帧更新（在 HandleUpdate 中调用）
---@param dt number
function Toast.Update(dt)
    for i = #messages, 1, -1 do
        local m = messages[i]
        m.life = m.life + dt
        if m.life >= LIFE_TIME then
            table.remove(messages, i)
        end
    end
end

--- NanoVG 渲染（在 Renderer.Render 之后调用）
---@param vg userdata NanoVG 上下文
---@param screenW number 逻辑宽度
---@param fontFaceId number 字体 ID
function Toast.Draw(vg, screenW, fontFaceId)
    if #messages == 0 then return end

    nvgFontFaceId(vg, fontFaceId)
    nvgFontSize(vg, FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local count = #messages
    for idx = 1, count do
        local m = messages[idx]

        -- 最旧的(idx=1)在最上面 slot=0，最新的在最下面
        local slot = idx - 1

        -- 透明度：前段不透明，后段淡出
        local alpha = 1.0
        if m.life > FADE_START then
            alpha = 1.0 - (m.life - FADE_START) / (LIFE_TIME - FADE_START)
        end
        -- 入场：前 0.15s 快速淡入
        if m.life < 0.15 then
            alpha = alpha * (m.life / 0.15)
        end
        alpha = math.max(0, math.min(1, alpha))

        -- 上浮偏移
        local floatOff = m.life * FLOAT_SPEED

        -- Y 坐标：基准线 + slot 偏移 - 上浮
        local rowH = FONT_SIZE + PAD_V * 2 + GAP
        local baseY = TOP_MARGIN + slot * rowH
        local y = baseY - floatOff

        -- 测量文本宽度（返回 advance, bounds）
        local advance, bounds = nvgTextBounds(vg, 0, 0, m.text)
        local textW = advance
        if bounds then
            textW = bounds[3] - bounds[1]
        end
        local boxW = textW + PAD_H * 2
        local boxH = FONT_SIZE + PAD_V * 2
        local x = screenW * 0.5

        -- 背景圆角矩形
        local bgAlpha = math.floor(BG_COLOR[4] * alpha)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - boxW * 0.5, y - boxH * 0.5, boxW, boxH, CORNER_RADIUS)
        nvgFillColor(vg, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], bgAlpha))
        nvgFill(vg)

        -- 文字
        local c = m.color
        local textAlpha = math.floor((c[4] or 255) * alpha)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], textAlpha))
        nvgText(vg, x, y, m.text, nil)
    end
end

return Toast
