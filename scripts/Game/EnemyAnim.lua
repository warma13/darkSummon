-- Game/EnemyAnim.lua
-- 敌人代码动画模块 —— 完全解耦，零侵入
--
-- 架构：
--   逻辑层调用 InitAnim / OnHit / OnDeath 注入事件
--   Update(dt, enemies) 每帧 tick 计时器
--   渲染层调用 GetDrawTransform(e, time) 获取变换参数（零分配）
--
-- 与原有字段的分工：
--   e.hitFlash / e.hitShakeTimer  → 保留（闪白 + 随机抖动，即时反馈）
--   e.anim                        → 本模块管理（呼吸/后退/出生/死亡/Boss脉冲）
--   e._dyingAnim                  → 死亡动画标记（CompactDead / DrawEnemies 读取）

local EnemyAnim = {}

-- ============================================================================
-- 调节常量
-- ============================================================================
local BREATHE_FREQ    = 0.7   -- Hz  呼吸频率
local BREATHE_AMP     = 1.2   -- px  呼吸幅度（怪物比英雄小）
local RECOIL_DURATION = 0.20  -- s   受击后退时长
local RECOIL_DIST     = 3.0   -- px  受击后退最大位移
local SPAWN_DURATION  = 0.30  -- s   出生弹跳时长
local DEATH_DURATION  = 0.40  -- s   死亡动画时长
local BOSS_PULSE_FREQ = 0.5   -- Hz  Boss 脉冲频率
local BOSS_PULSE_AMP  = 0.02  -- ±   Boss 脉冲缩放幅度

-- ============================================================================
-- 缓动函数（局部，避免全局查找）
-- ============================================================================
local sin  = math.sin
local sqrt = math.sqrt
local PI   = math.pi

local function easeInQuad(t)    return t * t end
local function easeOutCubic(t)  return 1 - (1-t)^3 end

-- ============================================================================
-- 零分配结果表（调用方必须立即使用，勿持久引用）
-- ============================================================================
local _r = {
    offsetX   = 0,   -- X 位移（后退方向，不含呼吸）
    offsetY   = 0,   -- Y 位移（后退 + 死亡下沉，不含呼吸）
    bobY      = 0,   -- 呼吸浮动（仅叠加到精灵，阴影不用）
    scaleX    = 1,
    scaleY    = 1,
    alpha     = 1,
    rotation  = 0,
}

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化动画状态（在 Enemy.CreateBase 末尾调用）
---@param e table  敌人实体
function EnemyAnim.InitAnim(e)
    e.anim = {
        breathePhase = math.random() * PI * 2,  -- 随机初相位，避免所有怪同步
        recoilTimer  = 0,
        recoilDirX   = 0,
        recoilDirY   = 0,
        spawnTimer   = SPAWN_DURATION,
        deathTimer   = 0,
    }
    e._dyingAnim = false
end

--- 每帧 tick（在 Enemy.Update 内循环结束、CompactDead 之前调用）
---@param dt      number
---@param enemies table   State.enemies（直接传入，模块不 require State）
function EnemyAnim.Update(dt, enemies)
    for _, e in ipairs(enemies) do
        local a = e.anim
        if not a then goto continue end

        -- 呼吸相位（仅存活时更新）
        if e.alive then
            a.breathePhase = a.breathePhase + dt * BREATHE_FREQ * PI * 2
        end

        -- 出生弹跳计时
        if a.spawnTimer > 0 then
            a.spawnTimer = math.max(0, a.spawnTimer - dt)
        end

        -- 受击后退计时
        if a.recoilTimer > 0 then
            a.recoilTimer = math.max(0, a.recoilTimer - dt)
        end

        -- 死亡动画计时
        if a.deathTimer > 0 then
            a.deathTimer = math.max(0, a.deathTimer - dt)
            if a.deathTimer <= 0 then
                e._dyingAnim = false  -- 动画结束 → CompactDead 可移除此实体
            end
        end

        ::continue::
    end
end

--- 受击触发（在 Enemy.TakeDamage 设置 hitFlash 后调用）
---@param e          table   敌人实体
---@param attackerX  number|nil  攻击来源 X（用于计算后退方向）
---@param attackerY  number|nil  攻击来源 Y
function EnemyAnim.OnHit(e, attackerX, attackerY)
    local a = e.anim
    if not a then return end

    a.recoilTimer = RECOIL_DURATION

    -- 计算远离攻击者的方向
    local dx = e.x - (attackerX or e.x)
    local dy = e.y - (attackerY or e.y + 10)
    local len = sqrt(dx*dx + dy*dy)
    if len > 0.001 then
        a.recoilDirX = dx / len
        a.recoilDirY = dy / len
    else
        a.recoilDirX = 0
        a.recoilDirY = -1   -- 默认向上后退
    end
end

--- 死亡触发（在 Enemy.TakeDamage 设置 alive=false 后立即调用）
---@param e table  敌人实体
function EnemyAnim.OnDeath(e)
    local a = e.anim
    if not a then return end
    a.deathTimer = DEATH_DURATION
    e._dyingAnim = true
end

--- 检查死亡动画是否仍在播放（CompactDead 用）
---@param e table
---@return boolean
function EnemyAnim.IsDying(e)
    return e._dyingAnim == true
end

--- 获取绘制变换参数（渲染层调用，立即使用，勿缓存返回值）
---@param e    table   敌人实体
---@param time number  当前游戏时间（State.time），用于 Boss 脉冲
---@return table  _r  零分配结果表
function EnemyAnim.GetDrawTransform(e, time)
    local a = e.anim

    -- 无动画数据：返回默认值
    if not a then
        _r.offsetX  = 0;  _r.offsetY   = 0;  _r.bobY  = 0
        _r.scaleX   = 1;  _r.scaleY    = 1
        _r.alpha    = 1;  _r.rotation  = 0
        return _r
    end

    local oX, oY  = 0, 0
    local bob     = 0
    local sX, sY  = 1.0, 1.0
    local alpha   = 1.0
    local rot     = 0

    -- ① 死亡动画（最高优先级）
    if e._dyingAnim and a.deathTimer > 0 then
        local t    = 1.0 - (a.deathTimer / DEATH_DURATION)
        local ease = easeInQuad(t)
        sX    = 1.0 - ease * 0.8
        sY    = 1.0 - ease * 0.8
        alpha = 1.0 - ease
        oY    = ease * 4           -- 轻微下沉
        _r.offsetX = oX; _r.offsetY = oY; _r.bobY = 0
        _r.scaleX  = sX; _r.scaleY  = sY
        _r.alpha   = alpha; _r.rotation = rot
        return _r
    end

    -- ② 出生弹跳
    if a.spawnTimer > 0 then
        local t    = 1.0 - (a.spawnTimer / SPAWN_DURATION)
        local ease = easeOutCubic(t)
        local s    = ease * (1.0 + 0.2 * sin(t * PI))  -- 弹出 + 微弹回
        sX, sY = s, s
    end

    -- ③ 呼吸浮动（仅写入 bobY，阴影 Y 轴不受影响）
    bob = sin(a.breathePhase) * BREATHE_AMP

    -- ④ 受击后退（sin 曲线：弹出→回正）
    if a.recoilTimer > 0 then
        local t   = a.recoilTimer / RECOIL_DURATION
        local mag = (1.0 - t) * sin(t * PI) * RECOIL_DIST
        oX = oX + a.recoilDirX * mag
        oY = oY + a.recoilDirY * mag
    end

    -- ⑤ Boss 脉冲（叠加缩放，增加压迫感）
    if e.isBoss and e.alive then
        local pd = sin(time * BOSS_PULSE_FREQ * PI * 2) * BOSS_PULSE_AMP
        sX = sX + pd
        sY = sY + pd
    end

    _r.offsetX  = oX
    _r.offsetY  = oY
    _r.bobY     = bob
    _r.scaleX   = sX
    _r.scaleY   = sY
    _r.alpha    = alpha
    _r.rotation = rot
    return _r
end

return EnemyAnim
