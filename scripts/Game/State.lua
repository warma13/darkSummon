-- Game/State.lua
-- 暗黑塔防游戏 - 全局状态管理

local Config = require("Game.Config")
local AutoPlay = require("Game.AutoPlay")

local State = {}

-- 游戏阶段
State.PHASE_MENU = "menu"
State.PHASE_PLAYING = "playing"
State.PHASE_WAVE_READY = "wave_ready"
State.PHASE_GAME_OVER = "game_over"      -- 失败（无奖励）
State.PHASE_STAGE_CLEAR = "stage_clear"   -- 通关（有奖励）

--- 统一阶段切换入口（带日志，便于调试流程跳转）
---@param newPhase string  目标阶段常量
---@param source string|nil 调用来源标识（可选，用于日志追踪）
function State.SetPhase(newPhase, source)
    local old = State.phase
    if old == newPhase then return end
    State.phase = newPhase
    print(string.format("[State] phase: %s → %s%s", tostring(old), newPhase,
        source and (" (" .. source .. ")") or ""))
end

function State.Reset()
    State.SetPhase(State.PHASE_MENU, "State.Reset")
    State.score = 0
    State.currentStage = 1       -- 当前关卡号（局外持久化）
    State.currentWave = 0        -- 关内波次号 (1~20)
    State.time = 0
    State.waveType = "normal"    -- "normal" / "elite" / "boss"

    -- 网格: grid[col][row] = tower 或 nil
    State.grid = {}
    for c = 1, Config.GRID_COLS do
        State.grid[c] = {}
    end

    -- 塔列表
    State.towers = {}
    -- 敌人列表
    State.enemies = {}
    State.aliveEnemyCount = 0  -- 存活敌人运行计数（Enemy.lua 维护）
    -- 子弹/弹道列表
    State.projectiles = {}
    -- 粒子特效列表
    State.particles = {}
    -- 飘字列表（伤害数字等）
    State.floatingTexts = {}
    -- 掉落物列表
    State.lootDrops = {}

    -- 波次状态
    State.waveSpawnQueue = {}
    State.waveSpawnIdx = 1              -- 队列消费索引（替代 table.remove(1) 的 O(N) 开销）
    State.waveSpawnTimer = 0
    State.waveActive = false

    -- 选中的塔（用于合成）
    State.selectedTower = nil

    -- 拖拽状态
    State.dragging = false       -- 是否正在拖拽
    State.dragTower = nil        -- 被拖拽的塔
    State.dragOriginCol = 0      -- 拖拽起始列
    State.dragOriginRow = 0      -- 拖拽起始行
    State.dragX = 0              -- 当前拖拽位置 X（屏幕坐标）
    State.dragY = 0              -- 当前拖拽位置 Y（屏幕坐标）
    State.dragTargetCol = 0      -- 鼠标指向的目标列
    State.dragTargetRow = 0      -- 鼠标指向的目标行
    State.dragValid = false      -- 目标位置是否有效

    -- 超限倒计时（怪物超过上限后10秒未清理则输）
    State.overloadTimer = 0     -- 0=未超限, >0=正在倒计时
    State.overloading = false   -- 是否处于超限状态

    -- BOSS 战斗倒计时
    State.bossTimer = 0         -- >0 表示 BOSS 战斗中，倒计时剩余秒数
    State.bossActive = false    -- 是否正在 BOSS 战斗
    State.bossIntro = nil       -- BOSS 出场动画 { timer, duration, name }

    -- 波次定时器（30秒自动出下一波）
    State.waveTimer = 0

    -- 召唤次数（用于递增消耗，每局重置）
    State.summonCount = 0

    -- 自动召唤/合成/布阵：仅重置计时器（开关由 AutoPlay 持久保存）
    AutoPlay.ResetTimers()

    -- UI 状态
    State.summonFlash = 0       -- 召唤闪光计时
    State.mergeFlash = 0        -- 合成闪光计时
    State.mergeFlashPos = nil   -- 合成闪光位置
    State.skillFlash = nil      -- 技能释放闪光 { timer, r, g, b }
    State.emeraldBossSkill = nil -- 翠影BOSS技能演出 { type, phase, timer, bossId, ... }

    -- 结算状态
    State.settleRewards = nil   -- 结算奖励数据（非nil时显示结算面板）

    -- 世界BOSS状态
    State.worldBossActive = false       -- 是否在世界BOSS战斗中
    State.worldBossTotalDamage = 0      -- 本场对BOSS累计伤害
    State.worldBossWarning = nil        -- 销毁预警 { timer, targetTowerId }
    State.worldBoss = nil               -- 世界BOSS直接引用（避免每帧O(E)扫描）

    print("[State] Game state reset")
end

-- 标签页状态（不在 Reset 中重置，保持用户当前页签）
State.activeTab = "battle"   -- "hero" / "battle" / "recruit" / "activity"

-- 跳过Boss模式（不在 Reset 中重置，跨关卡持久）
-- true = 只刷小怪，小怪清完自动失败重开；false = 正常挑战Boss
State.skipBoss = false

--- 压缩数组：移除所有 nil 空洞，保证 ipairs 安全
---@param arr table
local function compactArray(arr)
    local n = #arr
    local j = 1
    for i = 1, n do
        if arr[i] ~= nil then
            if i ~= j then
                arr[j] = arr[i]
                arr[i] = nil
            end
            j = j + 1
        end
    end
    -- 清理尾部残留（#arr 可能因空洞导致长度不准）
    for i = j, n do
        arr[i] = nil
    end
end

-- dirty flag：仅在实际产生 nil 空洞时才执行压缩
State._dirtyArrays = false

--- 标记数组有空洞需要压缩（swap-and-pop 移除元素时调用）
function State.MarkDirty()
    State._dirtyArrays = true
end

--- 每帧开头调用：压缩所有游戏数组，消除 nil 空洞（仅在 dirty 时执行）
function State.CompactArrays()
    if not State._dirtyArrays then return end
    State._dirtyArrays = false
    compactArray(State.enemies)
    compactArray(State.towers)
    compactArray(State.projectiles)
    compactArray(State.particles)
    compactArray(State.floatingTexts)
    compactArray(State.lootDrops)
end

-- 粒子/飘字数量上限（超过时淘汰最旧的，避免无限增长导致卡顿）
State.MAX_PARTICLES = 300
State.MAX_FLOATING_TEXTS = 150

-- ======== 对象池：复用飘字/粒子/弹道 table，减少 GC 压力 ========
local _ftPool = {}              -- 飘字对象池
local _ftPoolN = 0
local _ptPool = {}              -- 粒子对象池
local _ptPoolN = 0
local _projPool = {}            -- 弹道对象池
local _projPoolN = 0

--- 从飘字池获取 table（或创建新的），用字段赋值替代每次新建
---@return table
function State.AcquireFloatingText()
    if _ftPoolN > 0 then
        local t = _ftPool[_ftPoolN]
        _ftPool[_ftPoolN] = nil
        _ftPoolN = _ftPoolN - 1
        return t
    end
    return {}
end

--- 回收飘字 table 到池中
function State.RecycleFloatingText(ft)
    -- 清除引用字段防止内存泄漏，保留 table 本身
    ft.text = nil; ft.color = nil; ft.isCrit = nil; ft.maxLife = nil
    _ftPoolN = _ftPoolN + 1
    _ftPool[_ftPoolN] = ft
end

--- 从粒子池获取 table
function State.AcquireParticle()
    if _ptPoolN > 0 then
        local t = _ptPool[_ptPoolN]
        _ptPool[_ptPoolN] = nil
        _ptPoolN = _ptPoolN - 1
        return t
    end
    return {}
end

--- 回收粒子 table 到池中
function State.RecycleParticle(pt)
    pt.color = nil; pt.maxLife = nil
    _ptPoolN = _ptPoolN + 1
    _ptPool[_ptPoolN] = pt
end

--- 从弹道池获取 table
function State.AcquireProjectile()
    if _projPoolN > 0 then
        local t = _projPool[_projPoolN]
        _projPool[_projPoolN] = nil
        _projPoolN = _projPoolN - 1
        return t
    end
    return {}
end

--- 回收弹道 table 到池中
function State.RecycleProjectile(proj)
    proj.tower = nil; proj.color = nil; proj.spriteSheet = nil
    proj.isEnemyProjectile = nil
    _projPoolN = _projPoolN + 1
    _projPool[_projPoolN] = proj
end

--- 安全添加飘字（超过上限时淘汰剩余寿命最短的旧飘字）
function State.AddFloatingText(ft)
    local fts = State.floatingTexts
    if #fts < State.MAX_FLOATING_TEXTS then
        fts[#fts + 1] = ft
    else
        -- 找剩余 life 最小的槽位替换，回收被替换的旧飘字
        local minLife = fts[1].life
        local minIdx = 1
        for i = 2, #fts do
            if fts[i].life < minLife then
                minLife = fts[i].life
                minIdx = i
            end
        end
        State.RecycleFloatingText(fts[minIdx])
        fts[minIdx] = ft
    end
end

--- 安全添加粒子（超过上限时跳过）
function State.AddParticle(pt)
    if #State.particles < State.MAX_PARTICLES then
        State.particles[#State.particles + 1] = pt
    else
        -- 超出上限，回收未使用的 table
        State.RecycleParticle(pt)
    end
end

-- 初始化
State.Reset()

return State
