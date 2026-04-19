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

        -- 技能等级解锁判断
        local heroInfo  = HeroData.Get(elf.typeDef.id)
        local elfLevel  = heroInfo and heroInfo.level or 1
        local unlocks   = Config.SKILL_UNLOCK_LEVELS
        local skill1On  = elfLevel >= (unlocks[1] or 100)    -- 自然馈赠（脉冲）
        local skill2On  = elfLevel >= (unlocks[2] or 500)    -- 翠意庇护
        local skill3On  = elfLevel >= (unlocks[3] or 1500)   -- 绿野之呼

        -- 计时器递减
        elf.natPulseTimer = (elf.natPulseTimer or 0) - dt
        elf.natActiveCd   = (elf.natActiveCd   or 0) - dt

        -- 统计范围内英雄数（主动翻倍判定）
        local heroesInRange = 0
        for ti = 1, towerCount do
            local t = towers[ti]
            if t ~= elf then
                local dx, dy = t._sx - elfX, t._sy - elfY
                if dx * dx + dy * dy <= auraRangeSq then
                    heroesInRange = heroesInRange + 1
                end
            end
        end

        -- 主动：绿野之呼（技能3，Lv.1500 解锁）
        local activeFired = false
        if elf.natActiveCd <= 0 then
            if skill3On then
                elf.natActiveCd = td.activeCooldown or 20.0
                activeFired = true
            else
                -- 未解锁时仍重置计时器，防止解锁后立即爆发
                elf.natActiveCd = td.activeCooldown or 20.0
            end
        end

        -- 向范围内英雄派发自然之力
        local pulseHit = 0   -- 记录本次脉冲命中友军数（用于视觉反馈）
        for ti = 1, towerCount do
            local t = towers[ti]
            if t ~= elf then
                local dx, dy = t._sx - elfX, t._sy - elfY
                if dx * dx + dy * dy <= auraRangeSq then
                    -- 被动①：定时脉冲（技能1，Lv.100 解锁）
                    if elf.natPulseTimer <= 0 and skill1On then
                        local forceGain = td.natForcePerPulse or 3
                        t.naturalForce      = (t.naturalForce or 0) + forceGain
                        t.naturalForceTimer = natForceDuration
                        pulseHit = pulseHit + 1
                        -- 粒子爆发替代飘字
                        SpawnNatureParticles(t, 6)
                    end
                    -- 主动：绿野之呼爆发
                    if activeFired then
                        local bonus = td.activeForce or 50
                        if heroesInRange >= (td.activeDoubleCount or 4) then
                            bonus = bonus * 2
                        end
                        t.naturalForce      = (t.naturalForce or 0) + bonus
                        t.naturalForceTimer = natForceDuration
                        State.AddFloatingText({
                            text     = "+" .. bonus .. " 自然之力",
                            x        = t._sx + (math.random() - 0.5) * 20,
                            y        = t._sy - 22,
                            life     = 1.2,
                            color    = { 80, 220, 120, 255 },
                            fontSize = 12,
                        })
                    end
                end
            end
        end

        -- 脉冲触发后在翎嫣自身显示"自然馈赠"提示（让玩家看到被动激活）
        if elf.natPulseTimer <= 0 and skill1On and pulseHit > 0 then
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
        if elf.natPulseTimer <= 0 then
            elf.natPulseTimer = td.baseSpeed or 1.5
        end

        ::nextElf::
    end

    -- =========================================================
    -- 收集翎嫣参数（首个有效翎嫣为准，支持多翎嫣取最强）
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
            halfSat       = td.natForceHalfSat  or 20
            maxAtkPct     = td.natForceMaxAtkPct or 0.60
            maxSpdPct     = td.natForceMaxSpdPct or 0.40
            atkRatio      = td.natForceAtkRatio  or 0.50
            verdantThresh = td.verdantThreshold  or 20
            verdantDur    = td.verdantDuration   or 5.0
            verdantCd     = td.verdantCooldown   or 3.0
            elfAtk        = elf.attack or 0
            -- 检查该翎嫣的技能2解锁状态
            local heroInfo = HeroData.Get(elf.typeDef.id)
            local elfLevel = heroInfo and heroInfo.level or 1
            if elfLevel >= (Config.SKILL_UNLOCK_LEVELS[2] or 500) then
                skill2On_global = true
            end
            break
        end
    end

    -- =========================================================
    -- 第二遍：衰减自然之力 + 渐近线 buff + 翠意庇护
    -- =========================================================
    for ti = 1, towerCount do
        local t = towers[ti]

        -- 自然之力衰减
        if (t.naturalForceTimer or 0) > 0 then
            t.naturalForceTimer = t.naturalForceTimer - dt
            if t.naturalForceTimer <= 0 then
                t.naturalForce      = 0
                t.naturalForceTimer = 0
            end
        end

        local nf = t.naturalForce or 0
        if nf > 0 then
            local factor = NatForceFactor(nf, halfSat)
            t.auraAtkBuff   = (t.auraAtkBuff or 0) + maxAtkPct * factor
            t.auraSpdBuff   = (t.auraSpdBuff or 0) + maxSpdPct * factor
            t.natureFlatAtk = elfAtk * atkRatio * factor
        else
            t.natureFlatAtk = 0
        end

        -- 翠意计时器衰减
        if (t.verdantTimer or 0) > 0 then
            t.verdantTimer = t.verdantTimer - dt
            if t.verdantTimer <= 0 then
                t.verdantTimer         = 0
                t.verdantActive        = false
                t.verdantCooldownTimer = verdantCd
                -- 翠意庇护结束，撤销免疫
                Debuff.RevokeImmunity(t, "silence")
                Debuff.RevokeImmunity(t, "shackle")
            end
        end
        if (t.verdantCooldownTimer or 0) > 0 then
            t.verdantCooldownTimer = t.verdantCooldownTimer - dt
        end

        -- 翠意触发（技能2，Lv.500 解锁）
        if skill2On_global
            and nf >= verdantThresh
            and not t.verdantActive
            and (not t.verdantCooldownTimer or t.verdantCooldownTimer <= 0)
        then
            t.verdantActive        = true
            t.verdantTimer         = verdantDur
            t.verdantCooldownTimer = verdantDur + verdantCd
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
    end
end

return M
