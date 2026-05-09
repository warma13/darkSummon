-- Game/Heroes/crimson_moon.lua
-- 弦月：蚀痕 (eclipse_scar) + 月穿 (moon_pierce)
--       + 血月猎杀 (blood_hunt) + 绯红新月 (crimson_crescent)
--
-- 被动1 蚀痕：攻击命中叠加蚀痕(最多6层)，每层使目标受伤+5%
-- 被动2 月穿：每次攻击获得1层月穿(最多8层)，每层+4%法穿
-- 被动3 血月猎杀：击杀叠血月，满10层消耗进入【血月】状态8s（叠层上限翻倍，ATK+20%）
-- 主动  绯红新月：全场敌人受伤+25%持续8s，期间每次攻击ATK+3%（最多10次+30%）

local M = {}

local State = require("Game.State")

local AddFloatingText = State.AddFloatingText

-- 飘字颜色
local COLOR_SCAR       = { 220, 40, 80, 255 }      -- 暗红（蚀痕）
local COLOR_BLOOD_MOON = { 255, 60, 60, 255 }       -- 红色（血月状态）
local COLOR_CRESCENT   = { 255, 200, 100, 255 }     -- 金色（绯红新月）
local COLOR_PIERCE     = { 180, 120, 255, 255 }     -- 紫色（月穿）

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

-- ============================================================================
-- 伤害修正 — 血月ATK + 主动ATK + 蚀痕受伤（magicVuln由HeroSkills统一处理）
-- ============================================================================

---@param tower table
---@param target table
---@param damage number
---@return number
function M.ModifyDamage(tower, target, damage)
    local hs = tower.hstate
    if not hs then return damage end

    -- 血月状态：ATK 加成
    if hs.isBloodMoon and hs.bloodMoonAtkBuff > 0 then
        damage = damage * (1 + hs.bloodMoonAtkBuff)
    end

    -- 主动期间：递增 ATK 加成
    if hs.crescentActive and hs.crescentAtkBuff > 0 then
        damage = damage * (1 + hs.crescentAtkBuff)
    end

    return damage
end

-- ============================================================================
-- 攻速修正 — 月穿标签提供的攻速（pierceAtkSpd）
-- ============================================================================

---@param tower table
---@param speed number
---@return number
function M.ModifyAttackSpeed(tower, speed)
    local hs = tower.hstate
    if not hs then return speed end

    -- 月穿标签 Tier3 攻速加成
    if hs.pierceStacks > 0 and hs.pierceTimer > 0 and (hs.pierceAtkSpd or 0) > 0 then
        speed = speed / (1 + hs.pierceStacks * hs.pierceAtkSpd)
    end

    return speed
end

-- ============================================================================
-- 命中触发 — 蚀痕叠加 + 月穿叠加 + 主动ATK递增 + 击杀处理
-- ============================================================================

---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local hs = tower.hstate
    if not hs then return end

    -- ================================================================
    -- 被动1 蚀痕：叠加目标受伤
    -- ================================================================
    local scar = has(tower, "eclipse_scar")
    if scar and target.alive then
        if not hs.scarMarks then hs.scarMarks = {} end
        local targetId = target.id or tostring(target)
        local mark = hs.scarMarks[targetId]
        if not mark then
            mark = { stacks = 0, timer = scar.stackDuration or 6.0 }
            hs.scarMarks[targetId] = mark
        end

        -- 每次叠加层数（标签 scarDoubleApply 时叠2层）
        local addStacks = (hs.scarDoubleApply) and 2 or 1
        -- 血月状态下上限翻倍
        local baseMax = (scar.maxStacks or 6) + (hs.scarMaxStacksBonus or 0)
        local maxStacks = hs.isBloodMoon and (baseMax * 2) or baseMax
        mark.stacks = math.min(mark.stacks + addStacks, maxStacks)
        mark.timer = scar.stackDuration or 6.0

        -- 写入 magicVuln（HeroSkills.ModifyDamage 统一读取）
        local dmgAmp = (scar.dmgAmpPerStack or 0.05) + (hs.extraDmgAmpPerStack or 0)
        target.magicVuln = mark.stacks * dmgAmp
        target.magicVulnTimer = scar.stackDuration or 6.0
    end

    -- ================================================================
    -- 被动2 月穿：叠加自身法穿
    -- ================================================================
    local pierce = has(tower, "moon_pierce")
    if pierce then
        local baseMax = (pierce.maxStacks or 8) + (hs.pierceMaxStacksBonus or 0)
        local maxStacks = hs.isBloodMoon and (baseMax * 2) or baseMax
        hs.pierceStacks = math.min(hs.pierceStacks + 1, maxStacks)
        hs.pierceTimer = pierce.stackDuration or 5.0

        -- 计算法穿并写入 tower.magicPen（Combat.CalcFinalDamage 读取）
        local penPerStack = (pierce.penPerStack or 0.04) + (hs.extraPenPerStack or 0)
        tower.magicPen = hs.pierceStacks * penPerStack
    end

    -- ================================================================
    -- 主动期间：每次攻击递增 ATK
    -- ================================================================
    if hs.crescentActive then
        local skill = has(tower, "crimson_crescent")
        if skill then
            local maxStacks = skill.atkMaxStacks or 10
            if hs.crescentAtkStacks < maxStacks then
                hs.crescentAtkStacks = hs.crescentAtkStacks + 1
                local perHit = (skill.atkPerHit or 0.03) + (hs.atkPerHitBonus or 0)
                hs.crescentAtkBuff = hs.crescentAtkStacks * perHit
            end
        end
    end

    -- ================================================================
    -- 被动3 血月猎杀：击杀叠血月
    -- ================================================================
    if killed then
        hs.totalKills = (hs.totalKills or 0) + 1

        local hunt = has(tower, "blood_hunt")
        if hunt and not hs.isBloodMoon then
            local required = (hunt.maxStacks or 10) - (hs.huntStacksReduce or 0)
            hs.huntStacks = hs.huntStacks + 1

            if hs.huntStacks >= required then
                -- 消耗层数进入血月状态
                hs.huntStacks = 0
                hs.isBloodMoon = true
                hs.bloodMoonTimer = (hunt.stateDuration or 8.0) + (hs.stateDurationBonus or 0)
                hs.bloodMoonAtkBuff = (hunt.atkBuff or 0.20) + (hs.stateAtkBonus or 0)

                AddFloatingText({
                    text     = "血月!",
                    x        = tower._sx or 0,
                    y        = (tower._sy or 0) - 30,
                    life     = 1.5,
                    color    = COLOR_BLOOD_MOON,
                    fontSize = 18,
                })
                State.skillFlash = { type = "blood_moon", timer = 0.8, tower = tower }
                print("[Heroes] crimson_moon BLOOD MOON activated! atkBuff=" .. hs.bloodMoonAtkBuff)
            end
        end

        -- 清理已死亡目标的蚀痕
        if hs.scarMarks then
            local targetId = target.id or tostring(target)
            hs.scarMarks[targetId] = nil
        end
    end
end

-- ============================================================================
-- 主动技能：绯红新月 — 全场增伤 + 递增ATK
-- ============================================================================

---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "crimson_crescent" then return end

    local hs = tower.hstate
    if not hs then return end

    local Debuff = require("Game.Debuff")

    -- 全场敌人施加受伤增加
    local globalAmp = (skill.globalAmp or 0.25) + (hs.ampBonus or 0)
    local ampDuration = skill.ampDuration or 8.0

    local hitCount = 0
    for _, e in ipairs(State.enemies) do
        if e.alive then
            Debuff.Apply(e, "amp_damage", {
                duration = ampDuration,
                value = globalAmp,
            })
            hitCount = hitCount + 1
        end
    end

    -- 进入主动状态（递增ATK）
    hs.crescentActive = true
    hs.crescentTimer = ampDuration
    hs.crescentGlobalAmp = globalAmp
    hs.crescentAtkStacks = 0
    hs.crescentAtkBuff = 0

    State.skillFlash = { type = "crimson_crescent", timer = 0.6, tower = tower }

    AddFloatingText({
        text     = "绯红新月!",
        x        = tower._sx or 0,
        y        = (tower._sy or 0) - 30,
        life     = 1.5,
        color    = COLOR_CRESCENT,
        fontSize = 16,
    })

    print("[Heroes] crimson_crescent: " .. hitCount .. " enemies marked, amp=" .. globalAmp .. ", duration=" .. ampDuration)
end

-- ============================================================================
-- 帧更新：计时器衰减（血月状态、月穿、主动技能、蚀痕）
-- ============================================================================

---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    for _, tower in ipairs(towers) do
        if tower.typeDef and tower.typeDef.id == "crimson_moon" and tower.hstate then
            local hs = tower.hstate

            -- ============================================================
            -- 血月状态：持续时间递减
            -- ============================================================
            if hs.isBloodMoon and hs.bloodMoonTimer > 0 then
                hs.bloodMoonTimer = hs.bloodMoonTimer - dt
                if hs.bloodMoonTimer <= 0 then
                    hs.isBloodMoon      = false
                    hs.bloodMoonTimer   = 0
                    hs.bloodMoonAtkBuff = 0

                    -- 血月结束时重新计算法穿（上限恢复正常）
                    local pierce = has(tower, "moon_pierce")
                    if pierce then
                        local baseMax = (pierce.maxStacks or 8) + (hs.pierceMaxStacksBonus or 0)
                        if hs.pierceStacks > baseMax then
                            hs.pierceStacks = baseMax
                            local penPerStack = (pierce.penPerStack or 0.04) + (hs.extraPenPerStack or 0)
                            tower.magicPen = hs.pierceStacks * penPerStack
                        end
                    end
                end
            end

            -- ============================================================
            -- 月穿：持续时间递减
            -- ============================================================
            if hs.pierceTimer > 0 then
                hs.pierceTimer = hs.pierceTimer - dt
                if hs.pierceTimer <= 0 then
                    hs.pierceStacks = 0
                    hs.pierceTimer  = 0
                    tower.magicPen  = 0
                end
            end

            -- ============================================================
            -- 主动技能：持续时间递减
            -- ============================================================
            if hs.crescentActive and hs.crescentTimer > 0 then
                hs.crescentTimer = hs.crescentTimer - dt
                if hs.crescentTimer <= 0 then
                    hs.crescentActive    = false
                    hs.crescentTimer     = 0
                    hs.crescentAtkStacks = 0
                    hs.crescentAtkBuff   = 0
                end
            end

            -- ============================================================
            -- 蚀痕：计时器到期后逐层衰减
            -- ============================================================
            if hs.scarMarks then
                for targetId, mark in pairs(hs.scarMarks) do
                    mark.timer = mark.timer - dt
                    if mark.timer <= 0 then
                        mark.stacks = mark.stacks - 1
                        if mark.stacks <= 0 then
                            hs.scarMarks[targetId] = nil
                        else
                            mark.timer = 1.0  -- 后续每1秒掉1层
                        end
                    end
                end
            end
        end
    end
end

return M
