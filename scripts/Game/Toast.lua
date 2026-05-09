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

-- ── 加载进度条 ─────────────────────────────────
-- 屏幕中上方显示的持久进度条，需手动调用 HideLoading 关闭
local loading = nil  -- { text, elapsed, fadingOut, fadeTime }

local LOAD_BAR_W      = 200   -- 进度条宽度
local LOAD_BAR_H      = 6    -- 进度条高度
local LOAD_BOX_PAD_H  = 20
local LOAD_BOX_PAD_V  = 10
local LOAD_TOP_MARGIN = 60
local LOAD_CYCLE      = 2.0   -- 进度条来回一个周期的秒数
local LOAD_FADE_DUR   = 0.3   -- 淡出动画时长

--- 显示加载进度条（持久显示，直到调用 HideLoading）
---@param text? string 提示文字，默认 "加载中..."
function Toast.ShowLoading(text)
    loading = {
        text     = text or "加载中...",
        elapsed  = 0,
        fadingOut = false,
        fadeTime  = 0,
    }
end

--- 隐藏加载进度条（带淡出动画）
function Toast.HideLoading()
    if loading and not loading.fadingOut then
        loading.fadingOut = true
        loading.fadeTime  = 0
    end
end

--- 加载进度条是否正在显示
function Toast.IsLoading()
    return loading ~= nil
end

--- 更新加载进度条（在 Toast.Update 中已自动调用）
local function _updateLoading(dt)
    if not loading then return end
    loading.elapsed = loading.elapsed + dt
    if loading.fadingOut then
        loading.fadeTime = loading.fadeTime + dt
        if loading.fadeTime >= LOAD_FADE_DUR then
            loading = nil
        end
    end
end

--- 绘制加载进度条
local function _drawLoading(vg, screenW, fontFaceId)
    if not loading then return end

    -- 透明度
    local alpha = 1.0
    if loading.fadingOut then
        alpha = 1.0 - loading.fadeTime / LOAD_FADE_DUR
    end
    -- 入场淡入
    if loading.elapsed < 0.2 then
        alpha = alpha * (loading.elapsed / 0.2)
    end
    alpha = math.max(0, math.min(1, alpha))

    local cx = screenW * 0.5

    -- 文字
    nvgFontFaceId(vg, fontFaceId)
    nvgFontSize(vg, FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local advance, bounds = nvgTextBounds(vg, 0, 0, loading.text)
    local textW = bounds and (bounds[3] - bounds[1]) or advance
    local boxW = math.max(textW + LOAD_BOX_PAD_H * 2, LOAD_BAR_W + LOAD_BOX_PAD_H * 2)
    local textH = FONT_SIZE
    local boxH = textH + LOAD_BOX_PAD_V + LOAD_BAR_H + LOAD_BOX_PAD_V * 2

    local boxX = cx - boxW * 0.5
    local boxY = LOAD_TOP_MARGIN

    -- 背景
    local bgA = math.floor(200 * alpha)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, boxX, boxY, boxW, boxH, CORNER_RADIUS)
    nvgFillColor(vg, nvgRGBA(20, 20, 30, bgA))
    nvgFill(vg)

    -- 文字
    local textY = boxY + LOAD_BOX_PAD_V + textH * 0.5
    nvgFillColor(vg, nvgRGBA(220, 220, 230, math.floor(255 * alpha)))
    nvgText(vg, cx, textY, loading.text, nil)

    -- 进度条背景（轨道）
    local barX = cx - LOAD_BAR_W * 0.5
    local barY = textY + textH * 0.5 + LOAD_BOX_PAD_V
    local barR = LOAD_BAR_H * 0.5

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, LOAD_BAR_W, LOAD_BAR_H, barR)
    nvgFillColor(vg, nvgRGBA(60, 55, 70, math.floor(180 * alpha)))
    nvgFill(vg)

    -- 进度条滑块（来回往复动画）
    local t = (loading.elapsed % LOAD_CYCLE) / LOAD_CYCLE  -- 0~1
    local pos = t < 0.5 and (t * 2) or (1 - (t - 0.5) * 2)  -- 0→1→0 三角波
    -- 缓动：smoothstep
    pos = pos * pos * (3 - 2 * pos)

    local sliderW = LOAD_BAR_W * 0.35
    local sliderX = barX + pos * (LOAD_BAR_W - sliderW)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderX, barY, sliderW, LOAD_BAR_H, barR)
    nvgFillColor(vg, nvgRGBA(140, 100, 220, math.floor(255 * alpha)))
    nvgFill(vg)
end

-- 包装原有 Update，追加加载条更新
local _origUpdate = Toast.Update
function Toast.Update(dt)
    _origUpdate(dt)
    _updateLoading(dt)
end

-- 包装原有 Draw，追加加载条绘制
local _origDraw = Toast.Draw
function Toast.Draw(vg, screenW, fontFaceId)
    _origDraw(vg, screenW, fontFaceId)
    _drawLoading(vg, screenW, fontFaceId)
end

return Toast
