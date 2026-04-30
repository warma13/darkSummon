-- autochess/Board.lua
-- 自走棋核心：状态机、商店、经济、合成、布阵

local Config = require("autochess.Config")
local VFX    = require("autochess.VFX")

local Board = {}

-- ============================================================================
-- 游戏状态
-- ============================================================================
Board.phase       = "prep"   -- "prep" | "battle" | "result" | "gameover" | "win"
Board.round       = 0
Board.gold        = 0
Board.hp          = 0
Board.winStreak   = 0
Board.loseStreak  = 0
Board.prepTimer   = 0

-- 等级 / 经验
Board.level       = 1
Board.xp          = 0

-- 棋盘 [col][row] = piece | nil   (col 1..6, row 1..6)
Board.grid        = {}
-- 备战席 [1..6] = piece | nil
Board.bench       = {}
-- 商店 [1..5] = heroId | nil
Board.shop        = {}

-- 选中的棋子 { source="board"|"bench", col, row, idx }
Board.selected    = nil

-- 上一次战斗结果（给 Renderer 用）
Board.lastResult  = nil -- "win" | "lose"

-- 敌方棋子（由 AI 生成，战斗开始后复制到 grid）
Board.enemyPieces = {} -- list of pieces

-- 屏幕尺寸（由 MiniGame 注入）
Board.screenW = 0
Board.screenH = 0

-- 羁绊激活状态
Board.activeSynergies = {} -- { faction = { count=n, tier=tbl } }

-- ============================================================================
-- Piece 结构
-- ============================================================================
--- 创建一个棋子
---@param heroId string
---@param star number
---@param isEnemy boolean
---@return table
local function MakePiece(heroId, star, isEnemy)
    local def = Config.HERO_BY_ID[heroId]
    if not def then return nil end
    star = star or 1
    local hpMult  = Config.STAR_HP_MULT[star]  or 1
    local atkMult = Config.STAR_ATK_MULT[star] or 1
    local defMult = Config.STAR_DEF_MULT[star] or 1
    return {
        id       = heroId,
        name     = def.name,
        star     = star,
        faction  = def.faction,
        atkType  = def.atkType,
        cost     = def.cost,
        color    = def.color,
        -- 战斗属性（含星级加成）
        maxHp    = math.floor(def.hp  * hpMult),
        hp       = math.floor(def.hp  * hpMult),
        atk      = math.floor(def.atk * atkMult),
        def      = math.floor(def.def * defMult),
        atkSpeed = def.atkSpeed,
        range    = def.range,
        -- 战斗运行时
        atkCd    = 0,
        isEnemy  = isEnemy or false,
        alive    = true,
        -- 动画状态
        dmgFlash   = 0,
        lastDmg    = 0,
        atkAnim    = 0,     -- 攻击动画计时器（>0 表示正在播放攻击帧）
        floatPhase = math.random() * math.pi * 2,  -- 浮动动画相位（随机错开）
        floatAmp   = 3.0,   -- 浮动幅度（像素）
        deathTimer = 0,     -- 死亡动画计时器（>0 表示正在播放死亡动画）
        deathDone  = false, -- 死亡动画播放完毕
        scaleAnim  = 0,     -- 入场缩放动画（>0 时从小到大）
    }
end
Board.MakePiece = MakePiece

-- ============================================================================
-- 初始化 / 重置
-- ============================================================================

function Board.Reset()
    Board.phase     = "prep"
    Board.round     = 0
    Board.gold      = Config.START_GOLD
    Board.hp        = Config.START_HP
    Board.winStreak = 0
    Board.loseStreak= 0
    Board.prepTimer = 0
    Board.selected  = nil
    Board.lastResult= nil
    Board.lastIncome= nil
    Board.activeSynergies = {}
    Board.level     = 1
    Board.xp        = 0

    -- 清空棋盘
    Board.grid = {}
    for c = 1, Config.BOARD_COLS do
        Board.grid[c] = {}
    end
    -- 清空备战席
    Board.bench = {}
    for i = 1, Config.BENCH_SIZE do
        Board.bench[i] = nil
    end
    -- 清空商店
    Board.shop = {}
    Board.enemyPieces = {}
end

function Board.NewGame()
    Board.Reset()
    Board.round = 1
    Board.prepTimer = Config.PREP_TIME
    Board.RefreshShop()
    -- 生成第一波敌人
    local AI = require("autochess.AI")
    Board.enemyPieces = AI.GenerateWave(Board.round)
    Board.RecalcSynergies()
end

-- ============================================================================
-- 商店
-- ============================================================================

--- 按权重随机选一个英雄ID
local function RollHero()
    local pool = {}
    for _, hero in ipairs(Config.HEROES) do
        local w = Config.SHOP_WEIGHTS[hero.cost] or 0
        for _ = 1, w do
            pool[#pool + 1] = hero.id
        end
    end
    return pool[math.random(1, #pool)]
end

function Board.RefreshShop()
    Board.shop = {}
    for i = 1, Config.SHOP_SLOTS do
        Board.shop[i] = RollHero()
    end
end

function Board.Reroll()
    if Board.gold < Config.REROLL_COST then return false end
    Board.gold = Board.gold - Config.REROLL_COST
    Board.RefreshShop()
    return true
end

--- 购买商店第 idx 个英雄
function Board.BuyHero(idx)
    local heroId = Board.shop[idx]
    if not heroId then return false end
    local def = Config.HERO_BY_ID[heroId]
    if not def then return false end
    if Board.gold < def.cost then return false end

    -- 找备战席空位
    local slot = nil
    for i = 1, Config.BENCH_SIZE do
        if not Board.bench[i] then
            slot = i
            break
        end
    end
    if not slot then return false end -- 满了

    Board.gold = Board.gold - def.cost
    local newPiece = MakePiece(heroId, 1, false)
    newPiece.scaleAnim = 1.0  -- 入场弹出动画
    Board.bench[slot] = newPiece
    Board.shop[idx] = nil

    -- 尝试合成
    Board.TryMerge(heroId)
    Board.RecalcSynergies()
    return true
end

-- ============================================================================
-- 合成（3合1升星）
-- ============================================================================

--- 收集所有同 id 同星级的棋子位置
local function FindPieces(heroId, star)
    local found = {}
    -- 备战席
    for i = 1, Config.BENCH_SIZE do
        local p = Board.bench[i]
        if p and p.id == heroId and p.star == star then
            found[#found + 1] = { source = "bench", idx = i, piece = p }
        end
    end
    -- 棋盘（玩家区域）
    for c = 1, Config.BOARD_COLS do
        for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p and p.id == heroId and p.star == star and not p.isEnemy then
                found[#found + 1] = { source = "board", col = c, row = r, piece = p }
            end
        end
    end
    return found
end

function Board.TryMerge(heroId)
    for star = 1, Config.MAX_STAR - 1 do
        local pieces = FindPieces(heroId, star)
        if #pieces >= Config.MERGE_COUNT then
            -- 移除前 MERGE_COUNT-1 个，升级第一个
            local keep = pieces[1]
            for i = 2, Config.MERGE_COUNT do
                local loc = pieces[i]
                if loc.source == "bench" then
                    Board.bench[loc.idx] = nil
                else
                    Board.grid[loc.col][loc.row] = nil
                end
            end
            -- 升级
            local newPiece = MakePiece(heroId, star + 1, false)
            newPiece.scaleAnim = 1.0  -- 升星弹出动画
            if keep.source == "bench" then
                Board.bench[keep.idx] = newPiece
            else
                Board.grid[keep.col][keep.row] = newPiece
            end
            -- 递归检查更高星级
            Board.TryMerge(heroId)
            return true
        end
    end
    return false
end

-- ============================================================================
-- 布阵：选中 & 放置
-- ============================================================================

function Board.SelectBench(idx)
    if not Board.bench[idx] then
        Board.selected = nil
        return
    end
    Board.selected = { source = "bench", idx = idx }
end

function Board.SelectBoard(col, row)
    if col < 1 or col > Config.BOARD_COLS then return end
    if row < Config.PLAYER_ROW_MIN or row > Config.BOARD_ROWS then return end
    local p = Board.grid[col][row]
    if not p or p.isEnemy then
        -- 尝试放置选中的棋子
        if Board.selected then
            Board.PlaceSelected(col, row)
        end
        return
    end
    Board.selected = { source = "board", col = col, row = row }
end

function Board.PlaceSelected(col, row)
    if not Board.selected then return end
    if col < 1 or col > Config.BOARD_COLS then return end
    if row < Config.PLAYER_ROW_MIN or row > Config.BOARD_ROWS then return end

    local sel = Board.selected
    local piece = nil

    if sel.source == "bench" then
        piece = Board.bench[sel.idx]
        if not piece then Board.selected = nil; return end
    else
        piece = Board.grid[sel.col][sel.row]
        if not piece then Board.selected = nil; return end
    end

    local target = Board.grid[col][row]

    if target then
        -- 交换（不改变场上数量，始终允许）
        if sel.source == "bench" then
            Board.bench[sel.idx] = target
            Board.grid[col][row] = piece
        else
            Board.grid[sel.col][sel.row] = target
            Board.grid[col][row] = piece
        end
    else
        -- 放置到空位
        if sel.source == "bench" then
            -- 从备战席上场：检查上场上限
            if Board.CountPlayerPieces() >= Board.GetMaxOnBoard() then
                Board.selected = nil
                return  -- 已满，不能再上
            end
            Board.bench[sel.idx] = nil
        else
            Board.grid[sel.col][sel.row] = nil
        end
        Board.grid[col][row] = piece
    end

    Board.selected = nil
    Board.RecalcSynergies()
end

--- 把棋盘上的棋子退回备战席
function Board.ReturnToBench(col, row)
    local p = Board.grid[col][row]
    if not p or p.isEnemy then return false end
    for i = 1, Config.BENCH_SIZE do
        if not Board.bench[i] then
            Board.bench[i] = p
            Board.grid[col][row] = nil
            Board.selected = nil
            return true
        end
    end
    return false -- 备战席满
end

-- ============================================================================
-- 等级 / 经验
-- ============================================================================

--- 当前等级允许的上场棋子数
function Board.GetMaxOnBoard()
    local info = Config.LEVEL_TABLE[Board.level]
    return info and info.slots or 1
end

--- 添加经验并处理升级
function Board.AddXP(amount)
    if Board.level >= Config.MAX_LEVEL then return end
    Board.xp = Board.xp + amount
    while Board.level < Config.MAX_LEVEL do
        local req = Config.LEVEL_TABLE[Board.level].xpReq
        if req <= 0 then break end  -- 满级
        if Board.xp >= req then
            Board.xp = Board.xp - req
            Board.level = Board.level + 1
        else
            break
        end
    end
    if Board.level >= Config.MAX_LEVEL then
        Board.xp = 0
    end
end

--- 花金币买经验
function Board.BuyXP()
    if Board.phase ~= "prep" then return false end
    if Board.level >= Config.MAX_LEVEL then return false end
    if Board.gold < Config.BUY_XP_COST then return false end
    Board.gold = Board.gold - Config.BUY_XP_COST
    Board.AddXP(Config.BUY_XP_AMOUNT)
    return true
end

-- ============================================================================
-- 自动部署（开战时自动补满 / 超出自动下场）
-- ============================================================================

--- 计算棋子"战力"用于排序（cost * starMult + 属性权重）
local function CalcPower(piece)
    local starW = Config.STAR_HP_MULT[piece.star] or 1
    return piece.cost * 100 * starW + piece.atk * 2 + piece.maxHp * 0.5 + piece.def * 3
end

--- 自动补满上场位 / 多余下场
function Board.AutoDeploy()
    local maxSlots = Board.GetMaxOnBoard()

    -- 收集场上玩家棋子
    local onBoard = {}
    for c = 1, Config.BOARD_COLS do
        for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p and not p.isEnemy then
                onBoard[#onBoard + 1] = { piece = p, col = c, row = r, power = CalcPower(p) }
            end
        end
    end

    -- 收集备战席棋子
    local onBench = {}
    for i = 1, Config.BENCH_SIZE do
        local p = Board.bench[i]
        if p then
            onBench[#onBench + 1] = { piece = p, idx = i, power = CalcPower(p) }
        end
    end

    local onBoardCount = #onBoard

    if onBoardCount < maxSlots then
        -- 需要补人：从备战席选战力最高的补上去
        table.sort(onBench, function(a, b) return a.power > b.power end)
        local need = maxSlots - onBoardCount
        local added = 0
        for _, info in ipairs(onBench) do
            if added >= need then break end
            -- 找一个空位
            local foundSlot = false
            for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
                for c = 1, Config.BOARD_COLS do
                    if not Board.grid[c][r] then
                        Board.grid[c][r] = info.piece
                        Board.bench[info.idx] = nil
                        added = added + 1
                        foundSlot = true
                        break
                    end
                end
                if foundSlot then break end
            end
        end

    elseif onBoardCount > maxSlots then
        -- 超员：把战力最低的退回备战席
        table.sort(onBoard, function(a, b) return a.power < b.power end)
        local excess = onBoardCount - maxSlots
        local removed = 0
        for _, info in ipairs(onBoard) do
            if removed >= excess then break end
            -- 找备战席空位
            for i = 1, Config.BENCH_SIZE do
                if not Board.bench[i] then
                    Board.bench[i] = info.piece
                    Board.grid[info.col][info.row] = nil
                    removed = removed + 1
                    break
                end
            end
        end
    end
end

-- ============================================================================
-- 羁绊计算
-- ============================================================================

function Board.RecalcSynergies()
    local counts = {}
    -- 统计场上玩家棋子的阵营
    for c = 1, Config.BOARD_COLS do
        for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p and not p.isEnemy then
                counts[p.faction] = (counts[p.faction] or 0) + 1
            end
        end
    end

    Board.activeSynergies = {}
    for faction, count in pairs(counts) do
        local syns = Config.SYNERGIES[faction]
        if syns then
            local best = nil
            for _, tier in ipairs(syns) do
                if count >= tier.count then
                    best = tier
                end
            end
            if best then
                Board.activeSynergies[faction] = { count = count, tier = best }
            end
        end
    end
end

--- 获取棋子经过羁绊加成后的战斗属性
function Board.GetBuffedStats(piece)
    local hp  = piece.maxHp
    local atk = piece.atk
    local def = piece.def
    local spd = piece.atkSpeed

    if not piece.isEnemy then
        local syn = Board.activeSynergies[piece.faction]
        if syn and syn.tier then
            local t = syn.tier
            if t.atkPct then atk = math.floor(atk * (1 + t.atkPct)) end
            if t.spdPct then spd = spd * (1 + t.spdPct) end
            if t.defFlat then def = def + t.defFlat end
            if t.hpFlat  then hp  = hp + t.hpFlat end
        end
    end
    return hp, atk, def, spd
end

-- ============================================================================
-- 回合流程
-- ============================================================================

function Board.StartBattle()
    if Board.phase ~= "prep" then return end

    -- 自动部署：补满上场位 / 超员退回备战席
    Board.AutoDeploy()
    Board.RecalcSynergies()

    -- 把 AI 敌人放到棋盘上方
    for _, ep in ipairs(Board.enemyPieces) do
        if ep.col and ep.row then
            Board.grid[ep.col][ep.row] = ep.piece
        end
    end

    -- 应用羁绊 buff 到初始血量
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p then
                local bufHp, bufAtk, bufDef, bufSpd = Board.GetBuffedStats(p)
                p.maxHp    = bufHp
                p.hp       = bufHp
                p.atk      = bufAtk
                p.def      = bufDef
                p.atkSpeed = bufSpd
                p.atkCd    = 0
                p.alive    = true
                p.dmgFlash = 0
            end
        end
    end

    Board.phase = "battle"
    Board.selected = nil

    VFX.Reset()
    local Battle = require("autochess.Battle")
    Battle.Reset()
end

function Board.EndBattle(playerWon)
    -- =====================================================
    -- 战斗中棋子会移动，玩家棋子可能跑到敌方区域，
    -- 所以必须先收集再清空，避免误删。
    -- =====================================================

    -- 1) 统计残存敌人（扣血用，必须在清空前）
    local enemyAliveCount = 0
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p and p.isEnemy and p.alive then
                enemyAliveCount = enemyAliveCount + 1
            end
        end
    end

    -- 2) 收集所有玩家棋子（无论在哪一行、无论是否存活）
    local playerPieces = {}
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p and not p.isEnemy then
                playerPieces[#playerPieces + 1] = { piece = p, col = c, row = r }
            end
        end
    end

    -- 3) 清空整个棋盘
    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            Board.grid[c][r] = nil
        end
    end

    -- 4) 把玩家棋子放回玩家区域，恢复满血
    --    优先放回原位（如果原位在玩家区域），否则找空位
    local placed = {} -- [col..","..row] = true
    -- 先处理原位在玩家区域的
    for _, info in ipairs(playerPieces) do
        local p = info.piece
        local c, r = info.col, info.row
        -- 如果原位在玩家区域，先占位
        if r >= Config.PLAYER_ROW_MIN and r <= Config.BOARD_ROWS then
            Board.grid[c][r] = p
            placed[c .. "," .. r] = true
        end
    end
    -- 再处理跑到敌方区域的棋子，找玩家区域空位放回
    for _, info in ipairs(playerPieces) do
        local p = info.piece
        local r = info.row
        if r < Config.PLAYER_ROW_MIN then
            -- 找空位
            local foundSlot = false
            for pr = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
                for pc = 1, Config.BOARD_COLS do
                    if not Board.grid[pc][pr] then
                        Board.grid[pc][pr] = p
                        foundSlot = true
                        break
                    end
                end
                if foundSlot then break end
            end
        end
    end

    -- 5) 恢复所有玩家棋子属性（满血复活）
    for c = 1, Config.BOARD_COLS do
        for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p then
                local def = Config.HERO_BY_ID[p.id]
                if def then
                    local hpM  = Config.STAR_HP_MULT[p.star]  or 1
                    local atkM = Config.STAR_ATK_MULT[p.star] or 1
                    local defM = Config.STAR_DEF_MULT[p.star] or 1
                    p.maxHp    = math.floor(def.hp  * hpM)
                    p.hp       = p.maxHp
                    p.atk      = math.floor(def.atk * atkM)
                    p.def      = math.floor(def.def * defM)
                    p.atkSpeed = def.atkSpeed
                    p.alive    = true
                    p.atkCd    = 0
                    p.dmgFlash = 0
                end
            end
        end
    end

    -- 连胜/连败
    if playerWon then
        Board.winStreak  = Board.winStreak + 1
        Board.loseStreak = 0
        Board.lastResult = "win"
    else
        Board.loseStreak = Board.loseStreak + 1
        Board.winStreak  = 0
        Board.lastResult = "lose"
        Board.hp = Board.hp - math.max(2, enemyAliveCount * 2 + Board.round)
    end

    -- 检查胜负
    if Board.hp <= 0 then
        Board.hp = 0
        Board.phase = "gameover"
        return
    end

    if Board.round >= Config.TOTAL_ROUNDS then
        Board.phase = "win"
        return
    end

    -- 进入下一回合准备阶段
    Board.round = Board.round + 1
    Board.phase = "result"  -- 短暂显示结果

    -- 结算金币（TFT 式）
    local baseIncome = Config.ROUND_INCOME[Board.round] or Config.BASE_INCOME_MAX
    local interest   = math.min(math.floor(Board.gold / Config.INTEREST_RATE), Config.MAX_INTEREST)
    local winBonus   = (Board.lastResult == "win") and Config.WIN_BONUS or 0
    local streak     = math.max(Board.winStreak, Board.loseStreak)
    local streakKey  = math.min(streak, 5)
    local streakBonus = Config.STREAK_BONUS[streakKey] or 0
    local totalIncome = baseIncome + interest + winBonus + streakBonus
    Board.gold = Board.gold + totalIncome

    -- 保存收入明细供 Renderer 显示
    Board.lastIncome = {
        base   = baseIncome,
        interest = interest,
        win    = winBonus,
        streak = streakBonus,
        total  = totalIncome,
    }

    -- 每回合免费经验
    Board.AddXP(Config.ROUND_FREE_XP)
end

function Board.NextRound()
    if Board.phase ~= "result" then return end
    Board.phase = "prep"
    Board.prepTimer = Config.PREP_TIME
    Board.RefreshShop()
    local AI = require("autochess.AI")
    Board.enemyPieces = AI.GenerateWave(Board.round)
    Board.RecalcSynergies()
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function Board.Update(dt)
    if Board.phase == "prep" then
        Board.prepTimer = Board.prepTimer - dt
        if Board.prepTimer <= 0 then
            Board.prepTimer = 0
            Board.StartBattle()
        end
    elseif Board.phase == "battle" then
        local Battle = require("autochess.Battle")
        local finished, playerWon = Battle.Tick(dt)
        if finished then
            Board.EndBattle(playerWon)
        end
    elseif Board.phase == "result" then
        -- 结果展示2秒后自动进入下一回合
        Board.prepTimer = (Board.prepTimer or 0) + dt
        if Board.prepTimer >= 2.0 then
            Board.prepTimer = 0
            Board.NextRound()
        end
    end

    -- 更新 VFX 特效
    VFX.Update(dt)

    -- 动画更新（棋盘 + 备战席）
    local function UpdatePieceAnim(p)
        -- 受伤闪白衰减
        if p.dmgFlash > 0 then
            p.dmgFlash = p.dmgFlash - dt * 4
            if p.dmgFlash < 0 then p.dmgFlash = 0 end
        end
        -- 攻击动画衰减
        if p.atkAnim > 0 then
            p.atkAnim = p.atkAnim - dt * 4
            if p.atkAnim < 0 then p.atkAnim = 0 end
        end
        -- 浮动动画（持续更新相位）
        p.floatPhase = (p.floatPhase or 0) + dt * 2.5
        -- 入场缩放动画衰减
        if (p.scaleAnim or 0) > 0 then
            p.scaleAnim = p.scaleAnim - dt * 3
            if p.scaleAnim < 0 then p.scaleAnim = 0 end
        end
        -- 死亡动画推进
        if not p.alive and not p.deathDone then
            p.deathTimer = (p.deathTimer or 0) + dt * 2.5
            if p.deathTimer >= 1.0 then
                p.deathTimer = 1.0
                p.deathDone = true
            end
        end
    end

    for c = 1, Config.BOARD_COLS do
        for r = 1, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p then UpdatePieceAnim(p) end
        end
    end
    for i = 1, Config.BENCH_SIZE do
        local p = Board.bench[i]
        if p then UpdatePieceAnim(p) end
    end
end

-- ============================================================================
-- 棋子计数
-- ============================================================================

function Board.CountPlayerPieces()
    local count = 0
    for c = 1, Config.BOARD_COLS do
        for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
            if Board.grid[c][r] and not Board.grid[c][r].isEnemy then
                count = count + 1
            end
        end
    end
    return count
end

function Board.CountBenchPieces()
    local count = 0
    for i = 1, Config.BENCH_SIZE do
        if Board.bench[i] then count = count + 1 end
    end
    return count
end

--- 获取场上玩家英雄的阵营统计
function Board.GetFactionCounts()
    local counts = {}
    for c = 1, Config.BOARD_COLS do
        for r = Config.PLAYER_ROW_MIN, Config.BOARD_ROWS do
            local p = Board.grid[c][r]
            if p and not p.isEnemy then
                counts[p.faction] = (counts[p.faction] or 0) + 1
            end
        end
    end
    return counts
end

return Board
