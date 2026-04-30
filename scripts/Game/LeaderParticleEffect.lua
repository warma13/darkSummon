-- Game/LeaderParticleEffect.lua
-- 主角(Leader)粒子光效时装
-- 从身体中心向外散发、逐渐消散的发光粒子
-- 绘制层级：在翅膀之后、塔图标之前

local State       = require("Game.State")
local CostumeData = require("Game.CostumeData")

local M = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

local MAX_PARTICLES    = 36       -- 单角色最大粒子数
local EMIT_RATE        = 6        -- 常态每秒发射数
local BURST_COUNT      = 10       -- 攻击爆发额外发射数
local ATK_DUR          = 0.30     -- 攻击动画时长

local BASE_LIFE        = 1.0      -- 粒子基础生命（秒）
local LIFE_VAR         = 0.4      -- 生命随机偏移 ±
local BASE_SIZE_MIN    = 2.5      -- 最小粒子初始尺寸
local BASE_SIZE_MAX    = 5.0      -- 最大粒子初始尺寸
local SPEED_MIN        = 18       -- 向外扩散最小速度（像素/秒）
local SPEED_MAX        = 40       -- 向外扩散最大速度
local SPAWN_RADIUS     = 0.08     -- 出生点偏移（相对 size，贴近身体中心）
local DECEL            = 0.92     -- 每帧速度衰减（越小减速越快）

-- ============================================================================
-- 粒子池（按角色分组，key = tower.id）
-- ============================================================================

---@class Particle
---@field x number       相对于角色中心的偏移
---@field y number
---@field vx number      速度
---@field vy number
---@field life number    剩余生命
---@field maxLife number 初始生命
---@field size number    粒子尺寸

---@type table<number, Particle[]>
local particlePool = {}

-- 图像句柄缓存
local imageCache = {}

local function EnsureImage(vg, def)
    local id = def.id
    if not imageCache[id] then
        imageCache[id] = nvgCreateImage(vg, def.preview, 0)
    end
    return imageCache[id]
end

-- ============================================================================
-- 粒子创建
-- ============================================================================

local function _RandRange(a, b)
    return a + math.random() * (b - a)
end

--- 创建一个新粒子（从身体中心向外射出）
---@param size number 角色尺寸
---@param burst boolean 是否攻击爆发粒子
---@return Particle
local function _NewParticle(size, burst)
    local angle = math.random() * math.pi * 2
    local spawnR = SPAWN_RADIUS * size * _RandRange(0.5, 1.5)
    local speed = _RandRange(SPEED_MIN, SPEED_MAX)
    if burst then speed = speed * 1.8 end

    local life = BASE_LIFE + _RandRange(-LIFE_VAR, LIFE_VAR)
    local pSize = _RandRange(BASE_SIZE_MIN, BASE_SIZE_MAX)
    if burst then pSize = pSize * 1.4 end

    -- 方向略偏上（粒子倾向上飘）
    local upBias = _RandRange(-0.3, -0.15)

    return {
        x  = math.cos(angle) * spawnR,
        y  = math.sin(angle) * spawnR * 0.7 + upBias * size * 0.1,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed * 0.7 + upBias * speed,
        life    = life,
        maxLife = life,
        size    = pSize,
    }
end

-- ============================================================================
-- 更新
-- ============================================================================

local function _UpdatePool(dt, towerId, size, tower)
    local pool = particlePool[towerId]
    if not pool then
        pool = {}
        particlePool[towerId] = pool
    end

    -- 更新存活粒子
    local i = 1
    while i <= #pool do
        local p = pool[i]
        p.life = p.life - dt
        if p.life <= 0 then
            pool[i] = pool[#pool]
            pool[#pool] = nil
        else
            -- 向外扩散 + 减速
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vx = p.vx * DECEL
            p.vy = p.vy * DECEL
            -- 轻微上飘
            p.vy = p.vy - 3.0 * dt
            i = i + 1
        end
    end

    -- 发射新粒子
    local atkTimer = tower.attackAnimTimer or 0

    -- 攻击爆发
    if atkTimer > ATK_DUR * 0.85 and #pool < MAX_PARTICLES then
        local burstN = math.min(BURST_COUNT, MAX_PARTICLES - #pool)
        for _ = 1, burstN do
            pool[#pool + 1] = _NewParticle(size, true)
        end
    end

    -- 常态发射
    if not pool._emitAccum then pool._emitAccum = 0 end
    pool._emitAccum = pool._emitAccum + EMIT_RATE * dt
    while pool._emitAccum >= 1.0 and #pool < MAX_PARTICLES do
        pool._emitAccum = pool._emitAccum - 1.0
        pool[#pool + 1] = _NewParticle(size, false)
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================

function M.Draw(vg, x, y, size, tower)
    local def = CostumeData.GetEquippedDef("particle")
    if not def then return end

    local img = EnsureImage(vg, def)
    local dt = State.dt or 0.016

    _UpdatePool(dt, tower.id, size, tower)

    local pool = particlePool[tower.id]
    if not pool or #pool == 0 then return end

    -- 攻击发光
    local atkTimer = tower.attackAnimTimer or 0
    local atkGlow = 0
    if atkTimer > 0 then
        local progress = 1.0 - (atkTimer / ATK_DUR)
        if progress < 0.3 then
            atkGlow = progress / 0.3
        else
            atkGlow = 1.0 - ((progress - 0.3) / 0.7)
        end
        atkGlow = math.max(0, math.min(1, atkGlow))
    end

    -- 呼吸脉冲
    local breathAlpha = math.sin(State.time * 2.0) * 0.12 + 0.88

    -- 粒子颜色
    local cr = (def.rarityColor and def.rarityColor[1] or 200) / 255
    local cg = (def.rarityColor and def.rarityColor[2] or 180) / 255
    local cb = (def.rarityColor and def.rarityColor[3] or 255) / 255

    nvgSave(vg)

    for i = 1, #pool do
        local p = pool[i]
        if p.life > 0 then
            local lifeRatio = p.life / p.maxLife  -- 1→0（刚出生=1，将死=0）

            -- 透明度：快速淡入 → 缓慢淡出
            local alpha
            if lifeRatio > 0.85 then
                alpha = (1.0 - lifeRatio) / 0.15  -- 快速淡入
            else
                alpha = lifeRatio / 0.85           -- 线性淡出
            end
            alpha = alpha * breathAlpha * (0.7 + atkGlow * 0.3)

            -- 尺寸：出生时小 → 中途最大 → 消散时缩小
            local sizeScale
            if lifeRatio > 0.85 then
                sizeScale = (1.0 - lifeRatio) / 0.15   -- 快速长大
            elseif lifeRatio < 0.25 then
                sizeScale = lifeRatio / 0.25 * 0.6      -- 消散缩小
            else
                sizeScale = 1.0
            end
            local drawSize = p.size * sizeScale * (1.0 + atkGlow * 0.4)

            local px = x + p.x
            local py = y + p.y

            if img and img > 0 then
                local hs = drawSize * 0.5
                local paint = nvgImagePattern(vg, px - hs, py - hs,
                    drawSize, drawSize, 0, img, alpha)
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, hs)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            else
                local grad = nvgRadialGradient(vg, px, py,
                    drawSize * 0.1, drawSize * 0.5,
                    nvgRGBAf(cr, cg, cb, alpha),
                    nvgRGBAf(cr, cg, cb, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, drawSize * 0.5)
                nvgFillPaint(vg, grad)
                nvgFill(vg)
            end
        end
    end

    nvgRestore(vg)
end

function M.Reset()
    particlePool = {}
    imageCache = {}
end

return M
