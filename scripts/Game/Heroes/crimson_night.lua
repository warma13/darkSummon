-- Game/Heroes/crimson_night.lua
-- 绯夜：暗影之针 (shadow_needle) + 绯瞳锁定 (blood_eye) + 深渊一刺 (abyss_strike)
local M = {}

local State = require("Game.State")

local AddFloatingText = State.AddFloatingText

-- 飘字颜色
local COLOR_NEEDLE_BURST = { 200, 50, 80, 255 }
local COLOR_ABYSS_STRIKE = { 255, 40, 60, 255 }

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 暗影之针 + 绯瞳锁定：命中触发
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    -- ================================================================
    -- 技能1：暗影之针 — 叠加印记，满层穿刺爆发
    -- ================================================================
    local needle = has(tower, "shadow_needle")
    if needle and target.alive then
        -- 叠加 1 层印记（刷新持续时间）
        target.shadowNeedleStacks = math.min(
            (target.shadowNeedleStacks or 0) + 1,
            needle.maxStacks or 5
        )
        target.shadowNeedleTimer = needle.stackDuration or 4.0
        target.shadowNeedleTowerId = tower.id

        -- 满层触发穿刺爆发
        if target.shadowNeedleStacks >= (needle.maxStacks or 5) then
            local HeroSkills = require("Game.HeroSkills")
            local Combat     = require("Game.Combat")
            local Enemy      = require("Game.Enemy")

            local atk = HeroSkills.GetEffectiveAttack(tower)
            local burstDmg = atk * (needle.burstAtkPct or 2.0)

            -- 穿甲：利用 armorReduceFromDot（CalcFinalDamage 已支持，单次使用后自动清 nil）
            target.armorReduceFromDot = needle.armorIgnore or 0.20

            local finalDmg, isCrit = Combat.CalcFinalDamage(tower, target, burstDmg)
            Enemy.TakeDamage(target, finalDmg)

            -- 消耗全部印记
            target.shadowNeedleStacks = 0
            target.shadowNeedleTimer = nil

            -- 飘字
            AddFloatingText({
                text     = "穿刺爆发!",
                x        = target.x + (math.random() - 0.5) * 10,
                y        = target.y - (target.typeDef.size or 8) - 20,
                life     = 1.0,
                color    = COLOR_NEEDLE_BURST,
                fontSize = 14,
            })

            print("[Heroes] shadow_needle burst on enemy " .. tostring(target.id)
                .. " dmg=" .. math.floor(finalDmg))
        end
    end

    -- ================================================================
    -- 技能2：绯瞳锁定 — 连续攻击同一目标提升暴击率
    -- ================================================================
    local bloodEye = has(tower, "blood_eye")
    if bloodEye then
        local prevTargetId = tower.bloodEyeTargetId

        if target.id == prevTargetId then
            -- 同一目标：叠层
            tower.bloodEyeStacks = math.min(
                (tower.bloodEyeStacks or 0) + 1,
                bloodEye.maxCritStacks or 10
            )
        else
            -- 切换目标：检查余韵
            if tower.bloodEyeEchoTimer and tower.bloodEyeEchoTimer > 0
               and tower.bloodEyeEchoStacks and tower.bloodEyeEchoStacks > 0 then
                -- 继承余韵层数
                tower.bloodEyeStacks = tower.bloodEyeEchoStacks
                tower.bloodEyeEchoStacks = 0
                tower.bloodEyeEchoTimer = 0
            else
                tower.bloodEyeStacks = 0
            end
            -- 本次攻击也算 1 层
            tower.bloodEyeStacks = math.min(
                (tower.bloodEyeStacks or 0) + 1,
                bloodEye.maxCritStacks or 10
            )
        end

        tower.bloodEyeTargetId = target.id

        -- 击杀：启动余韵
        if killed then
            local echoRatio = bloodEye.echoRatio or 0.50
            tower.bloodEyeEchoStacks = math.floor((tower.bloodEyeStacks or 0) * echoRatio)
            tower.bloodEyeEchoTimer = bloodEye.echoDuration or 2.0
            tower.bloodEyeTargetId = nil
            tower.bloodEyeStacks = 0
        end

        -- 更新 bonusCritRate / bonusCritDmg（供 CalcFinalDamage 使用）
        local stacks = tower.bloodEyeStacks or 0
        tower.bonusCritRate = stacks * (bloodEye.critRatePerHit or 0.03)
        tower.bonusCritDmg  = stacks > 0 and (bloodEye.critDmgBonus or 0.50) or 0
    end
end

--- 深渊一刺：主动技能
---@param tower table
---@param skill table
function M.TriggerActive(tower, skill)
    if skill.id ~= "abyss_strike" then return end

    local target = tower.target
    if not target or not target.alive then return end

    local HeroSkills = require("Game.HeroSkills")
    local Combat     = require("Game.Combat")
    local Enemy      = require("Game.Enemy")

    local atk = HeroSkills.GetEffectiveAttack(tower)
    local baseDmg = atk * (skill.baseAtkPct or 8.0)

    -- 印记加成：每层额外 stackBonusPct × ATK
    local stacks = target.shadowNeedleStacks or 0
    if stacks > 0 then
        baseDmg = baseDmg + atk * (skill.stackBonusPct or 1.0) * stacks

        -- 穿刺爆发的穿甲也对深渊一刺生效
        local needle = has(tower, "shadow_needle")
        if needle then
            target.armorReduceFromDot = needle.armorIgnore or 0.20
        end

        -- 消耗印记
        target.shadowNeedleStacks = 0
        target.shadowNeedleTimer = nil
    end

    -- 强制暴击：临时拉高 bonusCritRate
    local savedCritRate = tower.bonusCritRate
    tower.bonusCritRate = (tower.bonusCritRate or 0) + 10.0

    local finalDmg, isCrit = Combat.CalcFinalDamage(tower, target, baseDmg)
    Enemy.TakeDamage(target, finalDmg)

    -- 恢复
    tower.bonusCritRate = savedCritRate

    local size = target.typeDef.size or 8

    -- 技能闪光 + 技能名飘字
    State.skillFlash = { type = "abyss_strike", timer = 0.6, tower = tower }
    AddFloatingText({
        text     = "深渊一刺!",
        x        = target.x + (math.random() - 0.5) * 10,
        y        = target.y - size - 28,
        life     = 1.2,
        color    = COLOR_ABYSS_STRIKE,
        fontSize = 16,
    })

    -- 伤害数字飘字
    local dmgText = tostring(math.floor(finalDmg))
    if finalDmg >= 1e8 then
        dmgText = string.format("%.1f亿", finalDmg / 1e8):gsub("%.0亿", "亿")
    elseif finalDmg >= 1e4 then
        dmgText = string.format("%.1f万", finalDmg / 1e4):gsub("%.0万", "万")
    end
    local vx = (math.random() - 0.5) * 80
    local vy = -(80 + math.random() * 40)
    AddFloatingText({
        text     = dmgText .. "!",
        x        = target.x + (math.random() - 0.5) * 12,
        y        = target.y - size - 10,
        vx       = vx,
        vy       = vy,
        life     = 0.9,
        maxLife  = 0.9,
        color    = COLOR_ABYSS_STRIKE,
        fontSize = 16,
        isCrit   = true,
    })

    print("[Heroes] abyss_strike on enemy " .. tostring(target.id)
        .. " stacks=" .. stacks .. " dmg=" .. math.floor(finalDmg))
end

--- 帧更新：印记计时器衰减 + 余韵计时器衰减
---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    -- 衰减所有敌人的暗影印记计时器
    for _, e in ipairs(State.enemies) do
        if e.alive and e.shadowNeedleTimer then
            e.shadowNeedleTimer = e.shadowNeedleTimer - dt
            if e.shadowNeedleTimer <= 0 then
                e.shadowNeedleStacks = 0
                e.shadowNeedleTimer = nil
                e.shadowNeedleTowerId = nil
            end
        end
    end

    -- 衰减所有绯夜的余韵计时器
    for _, tower in ipairs(towers) do
        if tower.typeDef and tower.typeDef.id == "crimson_night" then
            if tower.bloodEyeEchoTimer and tower.bloodEyeEchoTimer > 0 then
                tower.bloodEyeEchoTimer = tower.bloodEyeEchoTimer - dt
                if tower.bloodEyeEchoTimer <= 0 then
                    tower.bloodEyeEchoStacks = 0
                    tower.bloodEyeEchoTimer = 0
                end
            end
        end
    end
end

return M
