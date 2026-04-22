-- Game/SpriteSheet.lua
-- 通用精灵图模块：注册、加载、绘制横排帧，支持旋转
-- 用法:
--   SpriteSheet.Register("leader", { path = "image/xxx.png", cols = 3 })
--   SpriteSheet.Draw(vg, "leader", 0, x, y, 40, 255)
--   SpriteSheet.DrawRotated(vg, "leader", 2, x, y, 20, 255, angle)

local SpriteSheet = {}

---@class SpriteSheetDef
---@field path string      资源路径（相对 assets/）
---@field cols number      横排帧数
---@field img number       NanoVG image handle（-1 = 未加载）
---@field loaded boolean   是否已尝试加载

--- 已注册的精灵图 { name -> SpriteSheetDef }
local sheets = {}

--- 注册一张精灵图
---@param name string    唯一标识（如 "leader", "archer" 等）
---@param def table      { path = string, cols = number }
function SpriteSheet.Register(name, def)
    sheets[name] = {
        path = def.path,
        cols = def.cols or 3,
        img = -1,
        loaded = false,
    }
end

--- 确保精灵图已加载（延迟加载，首次绘制时调用）
---@param vg userdata   NanoVG context
---@param name string
---@return number       image handle（>0 有效）
function SpriteSheet.Ensure(vg, name)
    local s = sheets[name]
    if not s then return -1 end
    if s.loaded then return s.img end
    s.loaded = true
    s.img = nvgCreateImage(vg, s.path, 0)
    if s.img > 0 then
        print("[SpriteSheet] Loaded '" .. name .. "': " .. s.path)
    else
        print("[SpriteSheet] WARNING: Failed to load '" .. name .. "': " .. s.path)
    end
    return s.img
end

--- 绘制精灵图的某一帧（不旋转）
---@param vg userdata       NanoVG context
---@param name string       精灵图名称
---@param frameIdx number   帧索引（0-based）
---@param x number          中心 X
---@param y number          中心 Y
---@param drawSize number   绘制尺寸（正方形边长）
---@param alpha number      透明度 0~255
function SpriteSheet.Draw(vg, name, frameIdx, x, y, drawSize, alpha)
    local s = sheets[name]
    if not s then return end
    local img = SpriteSheet.Ensure(vg, name)
    if img <= 0 then return end

    alpha = alpha or 255
    local half = drawSize * 0.5
    local totalW = drawSize * s.cols
    local totalH = drawSize
    local ox = x - half - frameIdx * drawSize
    local oy = y - half
    -- 右侧内缩 1px 避免纹理采样到相邻帧边缘（AI生成精灵图帧间泄漏）
    local trim = 1
    local paint = nvgImagePattern(vg, ox, oy, totalW, totalH, 0, img, alpha / 255)
    nvgBeginPath(vg)
    nvgRect(vg, x - half, y - half, drawSize - trim, drawSize)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制精灵图的某一帧（支持水平翻转，角色朝向用）
---@param vg userdata       NanoVG context
---@param name string       精灵图名称
---@param frameIdx number   帧索引（0-based）
---@param x number          中心 X
---@param y number          中心 Y
---@param drawSize number   绘制尺寸（正方形边长）
---@param alpha number      透明度 0~255
---@param flipX boolean     是否水平翻转
function SpriteSheet.DrawEx(vg, name, frameIdx, x, y, drawSize, alpha, flipX)
    if flipX then
        nvgSave(vg)
        nvgTranslate(vg, x, y)
        nvgScale(vg, -1, 1)
        SpriteSheet.Draw(vg, name, frameIdx, 0, 0, drawSize, alpha)
        nvgRestore(vg)
    else
        SpriteSheet.Draw(vg, name, frameIdx, x, y, drawSize, alpha)
    end
end

--- 绘制精灵图的某一帧（带旋转，弹体用）
---@param vg userdata       NanoVG context
---@param name string       精灵图名称
---@param frameIdx number   帧索引（0-based）
---@param x number          中心 X
---@param y number          中心 Y
---@param drawSize number   绘制尺寸
---@param alpha number      透明度 0~255
---@param angle number      旋转角度（弧度）
function SpriteSheet.DrawRotated(vg, name, frameIdx, x, y, drawSize, alpha, angle)
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, angle)
    SpriteSheet.Draw(vg, name, frameIdx, 0, 0, drawSize, alpha)
    nvgRestore(vg)
end

--- 检查精灵图是否已注册
---@param name string
---@return boolean
function SpriteSheet.Has(name)
    return sheets[name] ~= nil
end

--- 检查精灵图是否有指定帧（帧索引0-based）
---@param name string
---@param frameIdx number
---@return boolean
function SpriteSheet.HasFrame(name, frameIdx)
    local s = sheets[name]
    if not s then return false end
    return frameIdx < s.cols
end

--- 获取精灵图定义（供 HeroAvatar 等外部模块读取 path/cols）
---@param name string
---@return { path: string, cols: number }|nil
function SpriteSheet.GetDef(name)
    return sheets[name]
end

return SpriteSheet
