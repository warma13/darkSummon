-- Game/HeroAnim.lua
-- 英雄代码动画模块 —— 完全解耦，零侵入
--
-- 架构：
--   逻辑层调用 InitAnim / OnAttack 注入事件
--   Update(dt, towers) 每帧 tick 计时器
--   渲染层调用 GetDrawTransform(tower) 获取变换参数（零分配）
--
-- 与原有字段的分工：
--   tower.attackAnimTimer   → 保留（帧切换逻辑，DrawTowerIcon 读取）
--   tower.spawnTime         → 保留（出生缩放，Renderer_Towers 读取）
--   tower.hanim             → 本模块管理（呼吸/攻击压缩弹出）
--   ctx.spriteFloatTime     → 废弃浮动 cy 偏移，改为 hanim.bobY 每塔独立相位

local HeroAnim = {}

-- ============================================================================
-- 调节常量
-- ============================================================================
local BREATHE_FREQ  = 0.6   -- Hz  呼吸频率（英雄比怪物稍慢）
local BREATHE_AMP   = 1.5   -- px  呼吸幅度（像素）

-- 攻击压缩弹出节奏（对应 attackAnimTimer = 0.3s）
local ATK_DURATION  = 0.30  -- s   攻击动画总时长（与 Combat.lua 赋值保持一致）
-- 阶段划分（归一化 progress = atkProgress/ATK_DURATION）
-- 0.0 ~ 0.25: 预备压缩（squash: X压 Y拉）
-- 0.25 ~ 0.55: 弹出拉伸（stretch: X拉 Y压）
-- 0.55 ~ 1.0:  回弹至正常
local ATK_SQUASH_END    = 0.25   -- 压缩阶段结束
local ATK_STRETCH_END   = 0.55   -- 拉伸阶段结束

-- 最大压缩/拉伸量（幅度减半，保持手感但不过于夸张）
local SQUASH_X   = 0.92   -- X 最窄（92% 宽）
local SQUASH_Y   = 1.08   -- Y 最高（108% 高）
local STRETCH_X  = 1.08   -- X 最宽（108% 宽）
local STRETCH_Y  = 0.93   -- Y 最矮（93% 高）

-- ============================================================================
-- 缓动函数
-- ============================================================================
local sin = math.sin
local PI  = math.pi

local function easeInOut(t)
    return t < 0.5 and 2*t*t or 1 - (-2*t+2)^2 / 2
end

local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t-1)^3 + c1 * (t-1)^2
end

-- ============================================================================
-- 零分配结果表（调用方必须立即使用，勿持久引用）
-- ============================================================================
local _r = {
    bobY    = 0,   -- 呼吸浮动 Y（仅叠加到精灵，阴影不用）
    scaleX  = 1,   -- 攻击压缩弹出 X 缩放（锚点在角色脚底）
    scaleY  = 1,   -- 攻击压缩弹出 Y 缩放
    -- floatPhase 用于阴影缩放同步（-1 ~ 1），与 bobY 相位一致
    floatPhase = 0,
}

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化动画状态（在 Tower.Create / Tower.CreateLeader 末尾调用）
---@param tower table  塔/英雄实体
function HeroAnim.InitAnim(tower)
    tower.hanim = {
        breathePhase = math.random() * PI * 2,  -- 随机初相位，避免所有英雄同步呼吸
        atkProgress  = 0,                        -- 攻击动画进度（秒，倒计时）
    }
end

--- 每帧 tick（在 Tower.Update 末尾调用）
---@param dt     number
---@param towers table   State.towers（直接传入，模块不 require State）
function HeroAnim.Update(dt, towers)
    for _, tower in ipairs(towers) do
        local h = tower.hanim
        if not h then goto continue end

        -- 呼吸相位持续更新（活跃时始终呼吸）
        h.breathePhase = h.breathePhase + dt * BREATHE_FREQ * PI * 2

        -- 攻击动画倒计时
        if h.atkProgress > 0 then
            h.atkProgress = math.max(0, h.atkProgress - dt)
        end

        ::continue::
    end
end

--- 攻击触发（在 Combat.lua TowerAttack 设置 attackAnimTimer 后调用）
---@param tower table  塔/英雄实体
function HeroAnim.OnAttack(tower)
    local h = tower.hanim
    if not h then return end
    h.atkProgress = ATK_DURATION
end

--- 获取绘制变换参数（渲染层调用，立即使用，勿缓存返回值）
---@param tower table  塔/英雄实体
---@return table  _r  零分配结果表
function HeroAnim.GetDrawTransform(tower)
    local h = tower.hanim

    -- 无动画数据：返回默认
    if not h then
        _r.bobY = 0; _r.scaleX = 1; _r.scaleY = 1; _r.floatPhase = 0
        return _r
    end

    -- 呼吸浮动（正弦）
    local phase = h.breathePhase
    local bob   = sin(phase) * BREATHE_AMP
    _r.bobY      = bob
    _r.floatPhase = -sin(phase)  -- 取反：精灵越高（bobY < 0）floatPhase 越大，阴影越小（物理正确）

    -- 攻击压缩弹出
    local sX, sY = 1.0, 1.0
    if h.atkProgress > 0 then
        -- progress 从 ATK_DURATION 倒数到 0
        -- t = 已过时间比 (0→1)
        local t = 1.0 - (h.atkProgress / ATK_DURATION)

        if t < ATK_SQUASH_END then
            -- 阶段1：预备压缩（0 → squash peak）
            local p = t / ATK_SQUASH_END
            local ease = easeInOut(p)
            sX = 1.0 + (SQUASH_X - 1.0) * ease
            sY = 1.0 + (SQUASH_Y - 1.0) * ease

        elseif t < ATK_STRETCH_END then
            -- 阶段2：弹出拉伸（squash → stretch peak）
            local p = (t - ATK_SQUASH_END) / (ATK_STRETCH_END - ATK_SQUASH_END)
            local ease = easeInOut(p)
            -- squash → stretch 插值
            sX = SQUASH_X + (STRETCH_X - SQUASH_X) * ease
            sY = SQUASH_Y + (STRETCH_Y - SQUASH_Y) * ease

        else
            -- 阶段3：回弹至正常（stretch → 1.0）
            local p = (t - ATK_STRETCH_END) / (1.0 - ATK_STRETCH_END)
            local ease = easeOutBack(math.min(p, 1.0))
            sX = STRETCH_X + (1.0 - STRETCH_X) * ease
            sY = STRETCH_Y + (1.0 - STRETCH_Y) * ease
        end
    end

    _r.scaleX = sX
    _r.scaleY = sY
    return _r
end

return HeroAnim
