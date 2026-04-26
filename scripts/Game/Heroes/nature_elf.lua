-- Game/Heroes/nature_elf.lua
-- 翎嫣·自然之精：自然馈赠 (nature_gift) + 翠意庇护 (verdant_ward) + 绿野之呼 (wilds_call)
-- 技能等级解锁：Skill1→Lv.100, Skill2→Lv.500, Skill3→Lv.1500
local M = {}

local State    = require("Game.State")
local Config   = require("Game.Config")
local HeroData = require("Game.HeroData")
local Debuff   = require("Game.Debuff")

--- 在友军位置生成缓慢上飘的绿色自然粒子
local function SpawnNatureParticles(t, count)
    for _ = 1, (count or 5) do
        local lt = 0.7 + math.random() * 0.5
        State.AddParticle({
            x       = t._sx + (math.random() - 0.5) * 18,
            y       = t._sy + (math.random() - 0.5) * 8,
            vx      = (math.random() - 0.5) * 10,      -- 轻微横向飘移
            vy      = -(20 + math.random() * 20),       -- 缓慢向上 -20~-40，重力会逐渐减速
            life    = lt,
            maxLife = lt,
            color   = { 60 + math.random(0, 50), 190 + math.random(0, 65), 85 + math.random(0, 65) },
            size    = 1.2 + math.random() * 1.3,        -- 小颗粒 1.2~2.5px
        })
    end
end

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 渐近线系数：nf / (nf + halfSat)
local function NatForceFactor(nf, halfSat)
    return nf / (nf + halfSat)
end

--- 星级技能缩放系数：0星→10%，满星→100%，线性插值
--- @param heroId string
--- @return number factor 0.10 ~ 1.00
local function StarScaleFactor(heroId)
    local h = HeroData.Get(heroId)
    local star = (h and h.star) or 0
    local maxStar = Config.MAX_HERO_STAR or 30
    return 0.10 + 0.90 * math.sqrt(math.min(star, maxStar) / maxStar)
end

--- 自然光环完整帧更新（替代 UpdateNatureAura）
--- 必须在 UpdateAuras 之后调用（叠加到已有 auraAtkBuff 上）
---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    local towerCount = #towers

    -- =========================================================
    -- 第一遍：翎嫣发出脉冲 / 主动计时 / 向友军派发自然之力
    -- =========================================================
    for si = 1, towerCount do
        local elf = towers[si]
        if elf.typeDef.special ~= "nature_aura" then goto nextElf end

        local td   = elf.typeDef
        local elfX = elf._sx
        local elfY = elf._sy
        local auraRangeSq      = (td.auraRange or 120) ^ 2
        local natForceDuration = td.natForceDuration or 8.0
        local starScale        = StarScaleFactor(td.id)

        -- 计时器递减（使用 hstate 子命名空间）
        local ehs = elf.hstate
        if not ehs then goto nextElf end
        ehs.natPulseTimer = ehs.natPulseTimer - dt
        ehs.natActiveCd   = ehs.natActiveCd   - dt

        -- 主动：绿野之呼
        local activeFired = false
        if ehs.natActiveCd <= 0 then
            ehs.natActiveCd = td.activeCooldown or 20.0
            activeFired = true
        end

        -- 向所有英雄派发自然之力（被动脉冲范围内，主动全场）
        local pulseHit = 0
        for ti = 1, towerCount do
            local t = towers[ti]
            if t ~= elf then
                local dx, dy = t._sx - elfX, t._sy - elfY
                local inRange = dx * dx + dy * dy <= auraRangeSq
                -- 被动①：定时脉冲（范围内）
                if inRange and ehs.natPulseTimer <= 0 then
                    local forceGain = td.natForcePerPulse or 3
                    local ths = t.hstate
                    if ths then
                        ths.naturalForce      = ths.naturalForce + forceGain
                        ths.naturalForceTimer = natForceDuration
                    end
                    pulseHit = pulseHit + 1
                    SpawnNatureParticles(t, 6)
                end
                -- 主动：绿野之呼（全场所有英雄+自然之力，数值随星级缩放）
                if activeFired then
                    local bonus = math.floor((td.activeForce or 30) * starScale)
                    local ths2 = t.hstate
                    if ths2 then
                        ths2.naturalForce      = ths2.naturalForce + bonus
                        ths2.naturalForceTimer = natForceDuration
                    end
                end
            end
        end

        -- 主动：鲜花环——给攻击力最高且无花环的英雄赠送
        if activeFired then
            local HeroSkills = require("Game.HeroSkills")
            local bestT, bestAtk = nil, -1
            for ti = 1, towerCount do
                local t = towers[ti]
                if t ~= elf and not (t.hstate and t.hstate.wreathActive) then
                    local atk = HeroSkills.GetEffectiveAttack(t)
                    if atk > bestAtk then
                        bestAtk = atk
                        bestT   = t
                    end
                end
            end
            if bestT and bestT.hstate then
                bestT.hstate.wreathActive = true
                bestT.hstate.wreathTimer  = td.wreathDuration or 10.0
                bestT.hstate.wreathBonus  = (td.wreathAtkBonus or 0.40) * starScale
                State.AddFloatingText({
                    text     = "🌸 鲜花环",
                    x        = bestT._sx,
                    y        = bestT._sy - 32,
                    life     = 1.5,
                    color    = { 255, 180, 200, 255 },
                    fontSize = 14,
                })
                SpawnNatureParticles(bestT, 12)
            end
        end

        -- 脉冲触发后在翎嫣自身显示"自然馈赠"提示
        if ehs.natPulseTimer <= 0 and pulseHit > 0 then
            State.AddFloatingText({
                text     = "自然馈赠",
                x        = elfX + (math.random() - 0.5) * 10,
                y        = elfY - 28,
                life     = 0.8,
                color    = { 120, 255, 160, 220 },
                fontSize = 11,
            })
        end

        -- 重置脉冲计时器
        if ehs.natPulseTimer <= 0 then
            ehs.natPulseTimer = td.baseSpeed or 3.0
        end

        ::nextElf::
    end

    -- =========================================================
    -- 收集翎嫣参数（首个有效翎嫣为准，支持多翎嫣取最强）
    -- 数值类参数随星级缩放：0星→10%，满星→100%
    -- =========================================================
    local halfSat       = 20
    local maxAtkPct     = 0.60
    local maxSpdPct     = 0.40
    local atkRatio      = 0.50
    local verdantThresh = 20
    local verdantDur    = 5.0
    local verdantCd     = 3.0
    local elfAtk        = 0
    local skill2On_global = false  -- 是否有翎嫣已解锁翠意庇护

    for si = 1, towerCount do
        local elf = towers[si]
        if elf.typeDef.special == "nature_aura" then
            local td      = elf.typeDef
            local ss      = StarScaleFactor(td.id)
            halfSat       = td.natForceHalfSat  or 20
            maxAtkPct     = (td.natForceMaxAtkPct or 0.60) * ss
            maxSpdPct     = (td.natForceMaxSpdPct or 0.40) * ss
            atkRatio      = (td.natForceAtkRatio  or 0.50) * ss
            verdantThresh = td.verdantThreshold  or 20
            verdantDur    = td.verdantDuration   or 5.0
            verdantCd     = td.verdantCooldown   or 3.0
            elfAtk        = elf.attack or 0
            skill2On_global = true  -- 翠意庇护始终生效
            break
        end
    end

    -- =========================================================
    -- 第二遍：衰减自然之力 + 渐近线 buff + 翠意庇护
    -- =========================================================
    for ti = 1, towerCount do
        local t = towers[ti]
        local ths = t.hstate
        if not ths then goto nextTarget end

        -- 自然之力衰减
        if ths.naturalForceTimer > 0 then
            ths.naturalForceTimer = ths.naturalForceTimer - dt
            if ths.naturalForceTimer <= 0 then
                ths.naturalForce      = 0
                ths.naturalForceTimer = 0
            end
        end

        local nf = ths.naturalForce
        if nf > 0 then
            local factor = NatForceFactor(nf, halfSat)
            t.auraAtkBuff   = (t.auraAtkBuff or 0) + maxAtkPct * factor
            t.auraSpdBuff   = (t.auraSpdBuff or 0) + maxSpdPct * factor
            ths.natureFlatAtk = elfAtk * atkRatio * factor
        else
            ths.natureFlatAtk = 0
        end

        -- 鲜花环计时器衰减
        if ths.wreathTimer > 0 then
            ths.wreathTimer = ths.wreathTimer - dt
            if ths.wreathTimer <= 0 then
                ths.wreathTimer  = 0
                ths.wreathActive = false
                ths.wreathBonus  = 0
                State.AddFloatingText({
                    text     = "鲜花环消散",
                    x        = t._sx,
                    y        = t._sy - 26,
                    life     = 1.0,
                    color    = { 180, 140, 160, 200 },
                    fontSize = 11,
                })
            end
        end

        -- 翠意计时器衰减
        if ths.verdantTimer > 0 then
            ths.verdantTimer = ths.verdantTimer - dt
            if ths.verdantTimer <= 0 then
                ths.verdantTimer         = 0
                ths.verdantActive        = false
                ths.verdantCooldownTimer = verdantCd
                -- 翠意庇护结束，撤销免疫
                Debuff.RevokeImmunity(t, "silence")
                Debuff.RevokeImmunity(t, "shackle")
            end
        end
        if ths.verdantCooldownTimer > 0 then
            ths.verdantCooldownTimer = ths.verdantCooldownTimer - dt
        end

        -- 翠意触发（技能2，Lv.500 解锁）
        if skill2On_global
            and nf >= verdantThresh
            and not ths.verdantActive
            and ths.verdantCooldownTimer <= 0
        then
            ths.verdantActive        = true
            ths.verdantTimer         = verdantDur
            ths.verdantCooldownTimer = verdantDur + verdantCd
            -- 翠意庇护激活，授予免疫（同时立即清除已有的沉默/束缚）
            Debuff.GrantImmunity(t, "silence")
            Debuff.GrantImmunity(t, "shackle")
            State.AddFloatingText({
                text     = "翠意",
                x        = t._sx + (math.random() - 0.5) * 14,
                y        = t._sy - 26,
                life     = 1.0,
                color    = { 100, 255, 160, 255 },
                fontSize = 14,
            })
        end
        ::nextTarget::
    end
end

return M
