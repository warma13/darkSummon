-- autochess/VFX.lua
-- 自走棋战斗视觉特效：飘字、弹道、粒子、光晕
-- 复用主游戏 Renderer_Draw 的渲染模式

local Config = require("autochess.Config")

local VFX = {}

-- ============================================================================
-- 特效数据池
-- ============================================================================

VFX.floatingTexts = {}  -- { x, y, text, color, life, maxLife, isCrit, fontSize, vy }
VFX.projectiles   = {}  -- { x, y, tx, ty, color, speed, life, spriteSheet }
VFX.particles     = {}  -- { x, y, vx, vy, life, maxLife, size, color }
VFX.hitFlashes    = {}  -- { x, y, timer, radius, r, g, b }

-- ============================================================================
-- 创建特效
-- ============================================================================

--- 生成伤害飘字
---@param x number 屏幕坐标
---@param y number
---@param dmg number 伤害值（正=伤害，负=治疗）
---@param isCrit boolean 是否暴击
function VFX.SpawnDamageText(x, y, dmg, isCrit)
    local text, color
    if dmg > 0 then
        text = "-" .. dmg
        color = isCrit and { 255, 50, 50 } or { 255, 120, 80 }
    else
        text = "+" .. math.abs(dmg)
        color = { 100, 255, 100 }
    end
    local ft = {
        x = x + (math.random() - 0.5) * 10,
        y = y,
        text = text,
        color = color,
        life = 0.9,
        maxLife = 0.9,
        isCrit = isCrit,
        fontSize = isCrit and 16 or 12,
        vy = -40,  -- 向上漂浮速度
    }
    VFX.floatingTexts[#VFX.floatingTexts + 1] = ft
end

--- 生成弹道（远程攻击）
---@param sx number 起始x
---@param sy number 起始y
---@param tx number 目标x
---@param ty number 目标y
---@param color table {r,g,b}
---@param spriteName string|nil 精灵图名
function VFX.SpawnProjectile(sx, sy, tx, ty, color, spriteName)
    local dx = tx - sx
    local dy = ty - sy
    local dist = math.sqrt(dx * dx + dy * dy)
    local speed = 200  -- px/s
    local p = {
        x = sx, y = sy,
        tx = tx, ty = ty,
        dx = dx / dist, dy = dy / dist,
        speed = speed,
        dist = dist,
        traveled = 0,
        color = color or { 200, 200, 255 },
        spriteName = spriteName,
        life = dist / speed + 0.1,
    }
    VFX.projectiles[#VFX.projectiles + 1] = p
end

--- 生成受击粒子（爆散）
---@param x number
---@param y number
---@param color table {r,g,b}
---@param count number 粒子数量
function VFX.SpawnHitParticles(x, y, color, count)
    count = count or 4
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local spd = 30 + math.random() * 50
        local pt = {
            x = x,
            y = y,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd - 20,
            life = 0.3 + math.random() * 0.3,
            maxLife = 0.6,
            size = 2 + math.random() * 3,
            color = color or { 255, 200, 100 },
        }
        pt.maxLife = pt.life
        VFX.particles[#VFX.particles + 1] = pt
    end
end

--- 生成攻击光晕（攻击者身上）
---@param x number
---@param y number
---@param color table {r,g,b}
function VFX.SpawnAttackBloom(x, y, color)
    local hf = {
        x = x, y = y,
        timer = 0.3,
        radius = 15,
        r = (color[1] or 200) / 255,
        g = (color[2] or 200) / 255,
        b = (color[3] or 200) / 255,
    }
    VFX.hitFlashes[#VFX.hitFlashes + 1] = hf
end

-- ============================================================================
-- 更新（每帧调用）
-- ============================================================================

function VFX.Update(dt)
    -- 飘字
    local i = 1
    while i <= #VFX.floatingTexts do
        local ft = VFX.floatingTexts[i]
        ft.life = ft.life - dt
        ft.y = ft.y + ft.vy * dt
        ft.vy = ft.vy * 0.95  -- 减速
        if ft.life <= 0 then
            table.remove(VFX.floatingTexts, i)
        else
            i = i + 1
        end
    end

    -- 弹道
    i = 1
    while i <= #VFX.projectiles do
        local p = VFX.projectiles[i]
        local step = p.speed * dt
        p.x = p.x + p.dx * step
        p.y = p.y + p.dy * step
        p.traveled = p.traveled + step
        p.life = p.life - dt
        if p.life <= 0 or p.traveled >= p.dist then
            table.remove(VFX.projectiles, i)
        else
            i = i + 1
        end
    end

    -- 粒子
    i = 1
    while i <= #VFX.particles do
        local pt = VFX.particles[i]
        pt.life = pt.life - dt
        pt.x = pt.x + pt.vx * dt
        pt.y = pt.y + pt.vy * dt
        pt.vy = pt.vy + 60 * dt  -- 重力
        if pt.life <= 0 then
            table.remove(VFX.particles, i)
        else
            i = i + 1
        end
    end

    -- 光晕
    i = 1
    while i <= #VFX.hitFlashes do
        local hf = VFX.hitFlashes[i]
        hf.timer = hf.timer - dt
        if hf.timer <= 0 then
            table.remove(VFX.hitFlashes, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 重置
-- ============================================================================

function VFX.Reset()
    VFX.floatingTexts = {}
    VFX.projectiles   = {}
    VFX.particles     = {}
    VFX.hitFlashes    = {}
end

return VFX
