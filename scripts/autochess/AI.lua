-- autochess/AI.lua
-- PVE 敌方阵容生成

local Config = require("autochess.Config")

local AI = {}

--- 从指定费用列表中随机选一个英雄
---@param costs table  如 {1,2}
---@return table|nil  英雄定义
local function PickHeroFromCosts(costs)
    local pool = {}
    for _, hero in ipairs(Config.HEROES) do
        for _, c in ipairs(costs) do
            if hero.cost == c then
                pool[#pool + 1] = hero
                break
            end
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--- 生成第 round 回合的 PVE 敌方阵容
---@param round number
---@return table  { {col, row, piece}, ... }
function AI.GenerateWave(round)
    local wave = Config.WAVES[round]
    if not wave then
        -- 超出配置的回合，使用最后一波
        wave = Config.WAVES[#Config.WAVES]
    end

    local enemies = {}
    local placed = {} -- 记录已占用位置

    for i = 1, wave.count do
        local hero = PickHeroFromCosts(wave.costs)
        if hero then
            -- 随机星级（不超过 wave.maxStar）
            local star = 1
            if wave.maxStar >= 2 and math.random() < 0.3 then
                star = 2
            end
            if wave.maxStar >= 3 and math.random() < 0.1 then
                star = 3
            end

            -- 随机放置在敌方区域（row 1-ENEMY_ROW_MAX, col 1-BOARD_COLS）
            local col, row
            local attempts = 0
            repeat
                col = math.random(1, Config.BOARD_COLS)
                row = math.random(1, Config.ENEMY_ROW_MAX)
                attempts = attempts + 1
            until (not placed[col * 100 + row]) or attempts > 50

            if attempts <= 50 then
                placed[col * 100 + row] = true

                local Board = require("autochess.Board")
                local piece = Board.MakePiece(hero.id, star, true)
                enemies[#enemies + 1] = {
                    col   = col,
                    row   = row,
                    piece = piece,
                }
            end
        end
    end

    return enemies
end

return AI
