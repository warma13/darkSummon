-- Game/Renderer_Utils.lua
-- 渲染工具函数：精灵注册、怪物图片、粒子系统、颜色辅助

return function(Renderer, ctx)

local Config = require("Game.Config")
local State  = require("Game.State")
local SpriteSheet = require("Game.SpriteSheet")

-- 主题光晕缓存
local themeGlowCache = {}
for _, theme in ipairs(Config.THEMES) do
    themeGlowCache[theme.id] = theme.palette.glow
end

-- 精灵图漂浮时间（跨模块共享）
ctx.spriteFloatTime = 0

-- 导出模块引用
ctx.SpriteSheet = SpriteSheet
ctx.Config = Config
ctx.State = State

local bgImageHandle = -1

-- 怪物图片缓存 { path -> nvg image handle }
local mobImageCache = {}



--- 延迟加载怪物图片
---@param vg userdata
---@param path string 资源路径
---@return number image handle (>0 有效)
local function EnsureMobImage(vg, path)
    if not path then return -1 end
    local cached = mobImageCache[path]
    if cached ~= nil then return cached end
    local img = nvgCreateImage(vg, path, 0)
    mobImageCache[path] = img
    if img > 0 then
        print("[MobImage] Loaded: " .. path)
    else
        print("[MobImage] WARNING: Failed to load: " .. path)
    end
    return img
end

--- 绘制怪物图片（单张PNG，居中绘制）
---@param vg userdata
---@param img number  nvg image handle
---@param x number    中心X
---@param y number    中心Y
---@param drawSize number 绘制尺寸（正方形边长）
---@param alpha number 透明度 0~255
local function DrawMobImage(vg, img, x, y, drawSize, alpha, flipX)
    if img <= 0 then return end
    alpha = alpha or 255
    local half = drawSize * 0.5
    if flipX then
        nvgSave(vg)
        nvgTranslate(vg, x, y)
        nvgScale(vg, -1, 1)
        nvgTranslate(vg, -x, -y)
    end
    local paint = nvgImagePattern(vg, x - half, y - half, drawSize, drawSize, 0, img, alpha / 255)
    nvgBeginPath(vg)
    nvgRect(vg, x - half, y - half, drawSize, drawSize)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    if flipX then
        nvgRestore(vg)
    end
end

-- 注册暗影君主精灵图
SpriteSheet.Register("leader", {
    path = "image/shadow_lord_spritesheet.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册N级英雄精灵图
SpriteSheet.Register("grunt", {
    path = "image/skeleton_grunt_sprite.png",
    cols = 2,   -- 0=idle, 1=attack（近战，无弹体帧）
})
SpriteSheet.Register("bat_m", {
    path = "image/bat_minion_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("hound", {
    path = "image/hell_hound_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册R级英雄精灵图
SpriteSheet.Register("archer", {
    path = "image/skeleton_archer_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("demon", {
    path = "image/demon_warrior_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("assassin", {
    path = "image/ghost_assassin_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("golem", {
    path = "image/stone_golem_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册SR级英雄精灵图
SpriteSheet.Register("necro", {
    path = "image/necromancer_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("flame", {
    path = "image/inferno_flame_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("knight", {
    path = "image/armor_breaker_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("witch", {
    path = "image/frost_witch_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("drummer", {
    path = "image/war_drummer_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册SSR级英雄精灵图
SpriteSheet.Register("mage", {
    path = "image/shadow_mage_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("hunter", {
    path = "image/abyss_hunter_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("plague", {
    path = "image/plague_doctor_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("storm", {
    path = "image/storm_lord_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册UR级英雄精灵图
SpriteSheet.Register("archangel", {
    path = "image/fallen_archangel_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("dragon", {
    path = "image/void_dragon_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册UR级限定英雄精灵图
SpriteSheet.Register("glacial", {
    path = "image/glacial_sovereign_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})

-- 注册LR级英雄精灵图
SpriteSheet.Register("weaver", {
    path = "image/fate_weaver_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("archfiend", {
    path = "image/eternal_archfiend_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("nature_elf", {
    path = "image/lingyan_spritesheet_3frames.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("crimson_night", {
    path = "image/crimson_night_sprite.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("ember_wraith", {
    path = "image/ember_wraith_spritesheet_20260426025527.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
SpriteSheet.Register("dream_weave", {
    path = "image/dream_weave_spritesheet.png",
    cols = 3,   -- 0=idle, 1=attack, 2=projectile
})
-- 注册世界BOSS精灵图
SpriteSheet.Register("world_boss", {
    path = "image/world_boss_abyss_lord_20260414151439.png",
    cols = 3,   -- 0=idle, 1=walk, 2=attack
})
-- 注册翠影秘境BOSS精灵图
SpriteSheet.Register("emerald_boss", {
    path = "image/emerald_boss_spritesheet.png",
    cols = 3,   -- 0=idle, 1=cast, 2=attack
})
-- 注册憎恨化身BOSS精灵图
SpriteSheet.Register("hatred_boss", {
    path = "image/mobs/hatred_boss.png",
    cols = 3,   -- 0=idle, 1=cast, 2=attack
})
-- 注册垃圾Boss精灵图
SpriteSheet.Register("garbage_boss", {
    path = "image/garbage_boss_spritesheet_20260501082141.png",
    cols = 3,   -- 0=idle, 1=cast, 2=attack
})

-- ========== Debuff 粒子系统 ==========

-- 粒子纹理（延迟加载）
local particleTextures = {}
local particleTexPaths = {
    ice     = "image/particle_ice.png",
    star    = "image/particle_star.png",
    frozen  = "image/particle_frozen.png",
    armor   = "image/particle_armor.png",
    curse   = "image/particle_curse.png",
    poison  = "image/particle_poison.png",
}

local function EnsureParticleTextures(vg)
    if particleTextures._loaded then return end
    for key, path in pairs(particleTexPaths) do
        particleTextures[key] = nvgCreateImage(vg, path, 0)
    end
    particleTextures._loaded = true
end

--- 每个敌人的 debuff 粒子池，key = enemyId
---@type table<number, table[]>
local debuffParticles = {}

-- ======== 粒子对象池（避免高频 GC） ========
local _particlePool = {}
local _particlePoolSize = 0

--- 从对象池获取或创建粒子
---@return table particle
local function SpawnParticle(texKey, x, y, vx, vy, life, pSize, rot, rotSpd)
    local p
    if _particlePoolSize > 0 then
        p = _particlePool[_particlePoolSize]
        _particlePool[_particlePoolSize] = nil
        _particlePoolSize = _particlePoolSize - 1
    else
        p = {}
    end
    p.tex = texKey
    p.x = x; p.y = y
    p.vx = vx; p.vy = vy
    p.life = life; p.maxLife = life
    p.size = pSize
    p.rot = rot or 0; p.rotSpd = rotSpd or 0
    return p
end

--- 回收粒子到对象池
local function RecycleParticle(p)
    _particlePoolSize = _particlePoolSize + 1
    _particlePool[_particlePoolSize] = p
end

--- 为指定敌人生成 debuff 粒子（每帧调用，按概率发射）
local MAX_DEBUFF_PARTICLES_PER_ENEMY = 20  -- 每个敌人 debuff 粒子上限（从30降至20，减少渲染量）
local function EmitDebuffParticles(e, dt)
    -- 快速检查：无任何 debuff 则跳过
    local hasSlow = e.slowTimer and e.slowTimer > 0
    local hasDot = e.dotTimer and e.dotTimer > 0
    local hasStun = e.stunTimer and e.stunTimer > 0
    local hasFrozen = e.frozenTimer and e.frozenTimer > 0
    local hasAmp = e.ampDamageTimer and e.ampDamageTimer > 0
    local hasArmor = e.armorBreakStacks and e.armorBreakStacks > 0
    if not (hasSlow or hasDot or hasStun or hasFrozen or hasAmp or hasArmor) then return end

    local id = e.id
    if not debuffParticles[id] then debuffParticles[id] = {} end
    local pool = debuffParticles[id]
    if #pool >= MAX_DEBUFF_PARTICLES_PER_ENEMY then return end  -- 达上限跳过发射
    local size = e.typeDef.size or 8

    -- 减速：脚底冰晶向上飘散
    if e.slowTimer and e.slowTimer > 0 then
        if math.random() < dt * 5 then
            local ox = (math.random() - 0.5) * size * 2
            pool[#pool + 1] = SpawnParticle("ice",
                e.x + ox, e.y + size * 0.5,
                (math.random() - 0.5) * 8, -math.random() * 20 - 10,
                0.6 + math.random() * 0.4,
                4 + math.random() * 4,
                math.random() * math.pi * 2, (math.random() - 0.5) * 4)
        end
    end

    -- DOT：毒液/火焰从身体冒出上升
    if e.dotTimer and e.dotTimer > 0 then
        if math.random() < dt * 6 then
            local ox = (math.random() - 0.5) * size * 1.6
            local oy = (math.random() - 0.5) * size * 1.2
            pool[#pool + 1] = SpawnParticle("poison",
                e.x + ox, e.y + oy,
                (math.random() - 0.5) * 6, -math.random() * 25 - 8,
                0.5 + math.random() * 0.3,
                3 + math.random() * 4,
                0, (math.random() - 0.5) * 2)
        end
    end

    -- 眩晕：星星绕头顶旋转飞散
    if e.stunTimer and e.stunTimer > 0 then
        if math.random() < dt * 7 then
            local angle = math.random() * math.pi * 2
            local r = size * 0.8
            pool[#pool + 1] = SpawnParticle("star",
                e.x + math.cos(angle) * r, e.y - size - 4 + math.sin(angle) * r * 0.4,
                math.cos(angle + math.pi * 0.5) * 15, math.sin(angle + math.pi * 0.5) * 8 - 5,
                0.4 + math.random() * 0.3,
                5 + math.random() * 3,
                0, (math.random() - 0.5) * 8)
        end
    end

    -- 冰冻：冰碎片从身体四周缓慢扩散
    if e.frozenTimer and e.frozenTimer > 0 then
        if math.random() < dt * 4 then
            local angle = math.random() * math.pi * 2
            pool[#pool + 1] = SpawnParticle("frozen",
                e.x + math.cos(angle) * size * 0.3, e.y + math.sin(angle) * size * 0.3,
                math.cos(angle) * (5 + math.random() * 8), math.sin(angle) * (5 + math.random() * 8) - 3,
                0.7 + math.random() * 0.5,
                4 + math.random() * 5,
                math.random() * math.pi * 2, (math.random() - 0.5) * 3)
        end
    end

    -- 易伤：紫色符文从身体飘出上升
    if e.ampDamageTimer and e.ampDamageTimer > 0 then
        if math.random() < dt * 4 then
            local ox = (math.random() - 0.5) * size * 1.4
            pool[#pool + 1] = SpawnParticle("curse",
                e.x + ox, e.y - size * 0.3,
                (math.random() - 0.5) * 10, -math.random() * 15 - 8,
                0.6 + math.random() * 0.4,
                4 + math.random() * 3,
                math.random() * math.pi * 2, (math.random() - 0.5) * 3)
        end
    end

    -- 破甲：金属碎片从身体爆散
    if e.armorBreakStacks and e.armorBreakStacks > 0
       and e.armorBreakTimer and e.armorBreakTimer > 0 then
        local rate = 3 + e.armorBreakStacks * 2  -- 层数越多粒子越密
        if math.random() < dt * rate then
            local angle = math.random() * math.pi * 2
            local spd = 10 + math.random() * 15
            pool[#pool + 1] = SpawnParticle("armor",
                e.x + math.cos(angle) * size * 0.5, e.y + math.sin(angle) * size * 0.5,
                math.cos(angle) * spd, math.sin(angle) * spd - 8,
                0.4 + math.random() * 0.3,
                3 + math.random() * 4,
                math.random() * math.pi * 2, (math.random() - 0.5) * 6)
        end
    end
end

--- 更新敌人的 debuff 粒子
local function UpdateDebuffParticles(dt)
    for eid, pool in pairs(debuffParticles) do
        local i = 1
        local n = #pool
        while i <= n do
            local p = pool[i]
            p.life = p.life - dt
            if p.life <= 0 then
                RecycleParticle(p)
                pool[i] = pool[n]
                pool[n] = nil
                n = n - 1
            else
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + p.rotSpd * dt
                i = i + 1
            end
        end
        -- 清理已死敌人的空池
        if n == 0 then
            debuffParticles[eid] = nil
        end
    end
end

--- 绘制单个粒子纹理（仅用于有旋转的粒子）
local function DrawParticleTexRotated(vg, img, x, y, pSize, alpha, rot)
    local half = pSize * 0.5
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, rot)
    local imgPaint = nvgImagePattern(vg, -half, -half, pSize, pSize, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, -half, -half, pSize, pSize)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)
    nvgRestore(vg)
end

-- 按纹理分组的粒子缓冲区（每帧复用，避免 GC）
local _texGroups = {}       -- texKey -> { img, particles[] }
local _texGroupKeys = {}    -- 有序的 texKey 列表

--- 绘制指定敌人的所有 debuff 粒子（按纹理分组批绘）
local function DrawEnemyDebuffParticles(vg, eid)
    local pool = debuffParticles[eid]
    if not pool or #pool == 0 then return end

    -- 清除分组缓冲
    for _, key in ipairs(_texGroupKeys) do
        local g = _texGroups[key]
        for i = 1, #g do g[i] = nil end
    end
    for i = 1, #_texGroupKeys do _texGroupKeys[i] = nil end

    -- 按纹理分组
    for _, p in ipairs(pool) do
        local texKey = p.tex
        local g = _texGroups[texKey]
        if not g then
            g = {}
            _texGroups[texKey] = g
        end
        if #g == 0 then
            _texGroupKeys[#_texGroupKeys + 1] = texKey
        end
        g[#g + 1] = p
    end

    -- 按纹理组绘制
    local ROT_THRESHOLD = 0.01
    for _, texKey in ipairs(_texGroupKeys) do
        local img = particleTextures[texKey]
        if img and img ~= 0 then
            local group = _texGroups[texKey]
            for _, p in ipairs(group) do
                local lifeRatio = p.life / p.maxLife
                local alpha = lifeRatio < 0.3 and (lifeRatio / 0.3) or 1.0
                local sizeScale = lifeRatio < 0.5 and (0.5 + lifeRatio) or 1.0
                local pSize = p.size * sizeScale
                local half = pSize * 0.5
                local rot = p.rot
                if rot and (rot > ROT_THRESHOLD or rot < -ROT_THRESHOLD) then
                    -- 有旋转：单独绘制（需要 save/translate/rotate/restore）
                    DrawParticleTexRotated(vg, img, p.x, p.y, pSize, alpha, rot)
                else
                    -- 无旋转：直接绘制（省去 save/restore）
                    local imgPaint = nvgImagePattern(vg, p.x - half, p.y - half, pSize, pSize, 0, img, alpha)
                    nvgBeginPath(vg)
                    nvgRect(vg, p.x - half, p.y - half, pSize, pSize)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                end
            end
        end
    end
end

local function rgba(c)
    return nvgRGBA(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 255)
end

--- 绘制圆形 Bloom 光晕
local function DrawCircleBloom(vg, x, y, radius, r, g, b, alpha)
    alpha = alpha or Config.BLOOM.innerAlpha
    local maxR = radius * Config.BLOOM.size * (1 + Config.BLOOM.outerAlpha * 3)
    local innerR = radius * Config.BLOOM.midAlpha * 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, maxR)
    local grad = nvgRadialGradient(vg, x, y, innerR, maxR,
        nvgRGBAf(r, g, b, alpha),
        nvgRGBAf(r, g, b, 0))
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

--- 绘制暗黑背景

-- 导出共享函数
ctx.rgba = rgba
ctx.DrawCircleBloom = DrawCircleBloom
ctx.EnsureMobImage = EnsureMobImage
ctx.DrawMobImage = DrawMobImage
ctx.EnsureParticleTextures = EnsureParticleTextures
ctx.UpdateDebuffParticles = UpdateDebuffParticles
ctx.EmitDebuffParticles = EmitDebuffParticles
ctx.DrawEnemyDebuffParticles = DrawEnemyDebuffParticles

end
