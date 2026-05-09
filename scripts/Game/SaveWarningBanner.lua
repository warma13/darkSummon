-- Game/SaveWarningBanner.lua
-- 云端存档异常时屏幕顶部持久红色警告横幅

local SaveWarningBanner = {}

-- ── 配置 ──────────────────────────────────────
local FONT_SIZE     = 14
local PAD_H         = 20
local PAD_V         = 8
local BG_COLOR      = { 180, 40, 40 }
local TEXT_COLOR    = { 255, 255, 255 }
local ICON_TEXT     = "⚠ "

-- ── 状态 ──────────────────────────────────────
local visible = false
local message = ""
local fadeAlpha = 0       -- 0~1，用于淡入淡出
local FADE_SPEED = 3.0    -- 每秒淡入/淡出速度

-- ── 公开 API ──────────────────────────────────

--- 显示警告横幅
---@param text string
function SaveWarningBanner.Show(text)
    message = text or "云端存档异常，请检查网络"
    visible = true
end

--- 隐藏警告横幅（淡出）
function SaveWarningBanner.Hide()
    visible = false
end

--- 是否正在显示（含淡出中）
---@return boolean
function SaveWarningBanner.IsVisible()
    return visible or fadeAlpha > 0
end

--- 每帧更新淡入淡出
---@param dt number
function SaveWarningBanner.Update(dt)
    local target = visible and 1 or 0
    if fadeAlpha < target then
        fadeAlpha = math.min(fadeAlpha + dt * FADE_SPEED, 1)
    elseif fadeAlpha > target then
        fadeAlpha = math.max(fadeAlpha - dt * FADE_SPEED, 0)
    end
end

--- NanoVG 渲染
---@param vg userdata
---@param screenW number 逻辑宽度
---@param fontFaceId number
function SaveWarningBanner.Draw(vg, screenW, fontFaceId)
    if fadeAlpha <= 0 then return end

    local alpha = math.floor(fadeAlpha * 230)
    local textAlpha = math.floor(fadeAlpha * 255)
    local boxH = FONT_SIZE + PAD_V * 2
    local displayText = ICON_TEXT .. message

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, boxH)
    nvgFillColor(vg, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], alpha))
    nvgFill(vg)

    -- 文字
    nvgFontFaceId(vg, fontFaceId)
    nvgFontSize(vg, FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3], textAlpha))
    nvgText(vg, screenW * 0.5, boxH * 0.5, displayText, nil)
end

return SaveWarningBanner
