-- Game/Heroes/glacial_sovereign.lua
-- 凛冬君王：凌冽寒意 (piercing_chill) + 霜寒之击 (frost_strike) + 冰川爆发 (glacial_eruption)
local M = {}

local State = require("Game.State")

local function has(tower, id)
    if not tower.skills then return nil end
    for _, s in ipairs(tower.skills) do if s.id == id then return s end end
end

--- 霜寒之击：普通攻击附带 1 层寒意
---@param tower table
---@param target table
---@param killed boolean
function M.OnHit(tower, target, killed)
    local frostStrike = has(tower, "frost_strike")
    if not frostStrike then return end
    if not target.alive then return end

    local Enemy   = require("Game.Enemy")
    local chillDur = tower.typeDef.chillDuration or 5.0
    local added    = Enemy.ApplyChill(target, 1, chillDur, tower.id)
    if added > 0 then
        tower.chillGlobalCounter = (tower.chillGlobalCounter or 0) + added
    end
end

--- 凌冽寒意 + 冰川爆发：复杂帧更新（每帧对范围内施加寒意；计数达阈值时全屏爆发）
---@param towers table
---@param dt number
---@param gridOffsetX number
---@param gridOffsetY number
function M.UpdateFrame(towers, dt, gridOffsetX, gridOffsetY)
    local Grid  = require("Game.Grid")
    local Enemy = require("Game.Enemy")
    local HeroSkills = require("Game.HeroSkills")

    for _, tower in ipairs(towers) do
        -- 凌冽寒意：每秒对范围内敌人施加寒意
        local piercingChill = has(tower, "piercing_chill")
        if piercingChill then
            tower.chillTickTimer = (tower.chillTickTimer or 0) + dt
            if tower.chillTickTimer >= 1.0 then
                tower.chillTickTimer = tower.chillTickTimer - 1.0

                local tx, ty = Grid.CellToScreen(tower.col, tower.row, gridOffsetX, gridOffsetY)
                local effectiveRange = HeroSkills.ModifyRange(tower, tower.range)
                local chillPerSec    = tower.typeDef.chillPerSec or 1
                local chillDur       = tower.typeDef.chillDuration or 5.0

                for _, e in ipairs(State.enemies) do
                    if e.alive and not e.phaseActive then
                        local dx = e.x - tx
                        local dy = e.y - ty
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist <= effectiveRange then
                            local added = Enemy.ApplyChill(e, chillPerSec, chillDur, tower.id)
                            if added > 0 then
                                tower.chillGlobalCounter = (tower.chillGlobalCounter or 0) + added
                            end
                        end
                    end
                end
            end
        end

        -- 冰川爆发：全局寒意计数达阈值时爆发
        local eruption = has(tower, "glacial_eruption")
        if eruption and tower.chillGlobalCounter then
            local threshold = eruption.chillGlobalThreshold or 100
            while tower.chillGlobalCounter >= threshold do
                tower.chillGlobalCounter = tower.chillGlobalCounter - threshold
                local applyStacks = eruption.chillApplyAll or 5
                local chillDur    = tower.typeDef.chillDuration or 5.0

                for _, e in ipairs(State.enemies) do
                    if e.alive then
                        Enemy.ApplyChill(e, applyStacks, chillDur, tower.id)
                    end
                end

                State.skillFlash = { type = "glacial_eruption", timer = 0.6, tower = tower }
                State.AddFloatingText({
                    text     = "冰川爆发!",
                    x        = tower.x or 0,
                    y        = (tower.y or 0) - 20,
                    life     = 1.2,
                    color    = { 100, 200, 255, 255 },
                    fontSize = 16,
                })
                print("[Heroes] glacial_eruption triggered! Applied " .. applyStacks .. " chill stacks to all enemies")
            end
        end
    end
end

return M
