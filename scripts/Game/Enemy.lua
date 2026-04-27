-- Game/Enemy.lua
-- 暗黑塔防游戏 - 敌人系统（支持词缀、被动、BOSS）

local Config = require("Game.Config")
local State = require("Game.State")
local Grid = require("Game.Grid")
local Currency = require("Game.Currency")
local LootDrop = require("Game.LootDrop")
local EnemyAnim = require("Game.EnemyAnim")
local Debuff    = require("Game.Debuff")
local DivineBlessDB = require("Game.DivineBlessData")
local Tower     = require("Game.Tower")

local F = require("Game.FormulaLib")
local DungeonScaling = require("Game.DungeonScaling")

-- 热路径 math 函数本地缓存（避免每次全局表查找）
local mfloor  = math.floor
local mrandom = math.random
local mmin    = math.min
local mmax    = math.max
local msin    = math.sin
local mcos    = math.cos
local mabs    = math.abs
local msqrt   = math.sqrt
local mpi     = math.pi

local Enemy = {}

-- 粒子/飘字安全添加（带数量上限），共享定义在 State.lua
local AddFloatingText = State.AddFloatingText
local AddParticle = State.AddParticle

-- 缓存网格偏移（由 Update 每帧设置，供死亡回调等使用）
Enemy._gridOffsetX = 0
Enemy._gridOffsetY = 0

local nextEnemyId = 1

-- ============================================================================
-- 延迟生成队列（防止迭代中修改数组导致 nil 空洞）
-- ============================================================================
local _updating = false        -- Update 循环执行中标记
local _pendingSpawns = {}      -- 延迟队列：循环内生成的敌人暂存于此

--- 将敌人加入 State.enemies 或延迟队列
local function AddEnemy(enemy)
    State.aliveEnemyCount = State.aliveEnemyCount + 1
    -- 世界BOSS直接引用（WorldBossSkills 每帧更新DEF时避免O(E)扫描）
    if enemy.isWorldBoss then
        State.worldBoss = enemy
    end
    if _updating then
        _pendingSpawns[#_pendingSpawns + 1] = enemy
    else
        State.enemies[#State.enemies + 1] = enemy
    end
end

--- 刷入延迟队列中的敌人到 State.enemies
local function FlushPending()
    for i = 1, #_pendingSpawns do
        State.enemies[#State.enemies + 1] = _pendingSpawns[i]
        _pendingSpawns[i] = nil
    end
end

--- 移除所有 alive == false 且死亡动画也已结束的敌人（单次紧凑遍历）
local function CompactDead()
    local enemies = State.enemies
    local n = #enemies
    local j = 1
    for i = 1, n do
        local e = enemies[i]
        -- 保留：存活中，或死亡动画还在播放中
        if e ~= nil and (e.alive or e._dyingAnim) then
            if i ~= j then
                enemies[j] = e
                enemies[i] = nil
            end
            j = j + 1
        else
            enemies[i] = nil
        end
    end
    -- 清除可能存在的尾部残留
    for i = j, n do
        enemies[i] = nil
    end
end

--- 从全局波次号反推 HP/速度缩放（使用 DungeonScaling 统一模块）
local function CalcScalesFromGlobalWave(globalWave)
    local stageNum = mfloor((globalWave - 1) / Config.WAVES_PER_STAGE) + 1
    local waveInStage = globalWave - (stageNum - 1) * Config.WAVES_PER_STAGE
    if waveInStage < 1 then waveInStage = 1 end

    local hpScale    = DungeonScaling.CalcHPScaleWithWave(stageNum, waveInStage)
    local speedScale = DungeonScaling.CalcSpeedScale(stageNum)

    return hpScale, speedScale
end

-- ============================================================================
-- 敌人创建
-- ============================================================================

--- 创建基础敌人数据
local function CreateBase(typeDef, waveNum, hpScale, speedScale)
    local hp = typeDef.baseHP * hpScale
    local speed = typeDef.speed * speedScale

    -- DEF 成长: baseDEF × defScale（独立于 HP 缩放，追踪英雄 ATK 成长）
    -- 优先使用 typeDef.stageEquiv（副本系统传入的等效关卡），否则从 waveNum 反推
    local baseDEF = typeDef.baseDEF or 0
    local stageForDEF = typeDef.stageEquiv or (mfloor((waveNum - 1) / Config.WAVES_PER_STAGE) + 1)
    local defScale = DungeonScaling.CalcDEFScale(stageForDEF)
    local totalDEF = mfloor(baseDEF * defScale)

    local enemy = {
        id = nextEnemyId,
        typeId = typeDef.id,
        typeDef = typeDef,
        hp = hp,
        maxHP = hp,
        speed = speed,
        baseSpeed = speed,
        progress = 0,
        loops = 0,
        x = 0,
        y = 0,
        alive = true,
        reachedEnd = false,
        waveNum = waveNum,

        -- 防御值（伤害公式: ATK × ATK / (ATK + DEF)）
        def = totalDEF,

        -- 状态效果
        slowTimer = 0,
        dotTimer = 0,
        dotDamage = 0,
        dotTickTimer = 0,
        animTime = 0,

        -- 词缀
        isElite = false,
        isBoss = typeDef.isBoss or false,
        isWorldBoss = typeDef.isWorldBoss or false,
        isHatredBoss = typeDef.isHatredBoss or false,
        affixes = {},
        affixIds = {},    -- 用于快速查询

        -- 护盾
        shield = 0,
        maxShield = 0,

        -- 被动计时器
        blinkTimer = 0,
        phaseTimer = 0,
        phaseActive = false,
        disableTimer = 0,
        summonTimer = 0,
        revived = false,

        -- BOSS 阶数
        bossTier = 1,

        -- 攻击词缀
        attackCooldown = 0,

        -- 特殊被动计时器
        regenLostTimer = 0,       -- regen_lost 回血计时
        scorchApplied = false,    -- scorch 是否已施加（命中时触发）
        firstHitArmored = typeDef.specialPassive == "first_hit_armor",  -- 首击减伤
        poisonTrailTimer = 0,     -- poison_trail 毒径计时

        -- 新词缀计时器
        ironWallTimer = 0,        -- 铁壁：DEF 增加周期
        ironWallStacks = 0,       -- 铁壁：已叠加次数
        rejuvTimer = 0,           -- 回春：已损失 HP 恢复周期
        starDrainTimer = 0,       -- 降星：降低英雄星级周期
        annihilateTimer = 0,      -- 毁灭：销毁英雄塔周期
        debuffTimer = 0,          -- 通用减益词缀：施加 debuff 周期
    }

    -- 冰盾坦克被动：出生自带护盾
    if typeDef.tankPassive == "ice_shield" then
        local pct = typeDef.shieldPct or 0.30
        enemy.shield = hp * pct
        enemy.maxShield = enemy.shield
    end

    -- 光环类型的 hp_boost：提升自身 HP
    if typeDef.aura and typeDef.aura.type == "hp_boost" then
        local boost = typeDef.aura.value or 0
        enemy.hp = enemy.hp * (1 + boost)
        enemy.maxHP = enemy.maxHP * (1 + boost)
    end

    -- 怪物防御属性（随关卡成长，对抗英雄各乘区）
    do
        local stageNum = stageForDEF  -- 复用上面已计算的 stageForDEF（含 stageEquiv 优先逻辑）
        local es = Config.ENEMY_SCALING
        if es then
            enemy.critDmgReduce   = F.Piecewise4(es.critDmgReduce,   stageNum)
            enemy.dmgBonusReduce  = F.Piecewise4(es.dmgBonusReduce,  stageNum)
            enemy.elemDmgReduce   = F.Piecewise4(es.elemDmgReduce,   stageNum)
            enemy.armorPenResist  = F.Piecewise4(es.armorPenResist,  stageNum)
        end
    end

    -- 初始化代码动画状态
    EnemyAnim.InitAnim(enemy)

    -- 根据 typeDef 批量注册静态免疫（immune_cc / dotImmune）
    Debuff.RegisterEnemyImmunities(enemy, typeDef)

    nextEnemyId = nextEnemyId + 1
    return enemy
end

--- 应用词缀到敌人
local function ApplyAffixes(enemy, affixes)
    if not affixes or #affixes == 0 then return end

    enemy.affixes = affixes
    for _, affix in ipairs(affixes) do
        enemy.affixIds[affix.id] = true

        if affix.hpMult then
            enemy.hp = enemy.hp * affix.hpMult
            enemy.maxHP = enemy.maxHP * affix.hpMult
        end
        if affix.speedMult then
            local bonus = enemy.baseSpeed * (affix.speedMult - 1)
            enemy.speed = enemy.speed + bonus
            enemy.baseSpeed = enemy.baseSpeed + bonus
        end
        if affix.shieldHP then
            enemy.shield = enemy.maxHP * affix.shieldHP
            enemy.maxShield = enemy.shield
        end
        -- 隐身词缀：初始化 phaseTimer 为可见间隔，避免出生即隐身
        if affix.id == "stealth" then
            enemy.phaseTimer = affix.phaseInterval or 4.0
        end
        -- void_aura：免疫所有控制 debuff
        if affix.id == "void_aura" then
            Debuff.GrantVoidAuraImmunity(enemy)
        end
    end

    -- 预计算 debuff 类词缀列表（避免每帧遍历全部词缀再过滤）
    local debuffList = {}
    for _, a in ipairs(affixes) do
        if a.category == "debuff" and a.debuffStat then
            debuffList[#debuffList + 1] = a
        end
    end
    if #debuffList > 0 then
        enemy._debuffAffixes = debuffList
    end
end

--- 创建普通/精英怪物（通过 typeId 查找，向后兼容）
function Enemy.CreateEnemy(typeId, waveNum, hpScale, speedScale, isElite, affixes)
    local typeDef = Config.ENEMY_TYPES[typeId]
    if not typeDef then
        print("[Enemy] ERROR: unknown type=" .. tostring(typeId))
        return nil
    end

    return Enemy.CreateEnemyFromDef(typeDef, waveNum, hpScale, speedScale, isElite, affixes)
end

--- 从完整定义创建普通/精英怪物（新系统主入口）
function Enemy.CreateEnemyFromDef(typeDef, waveNum, hpScale, speedScale, isElite, affixes)
    local enemy = CreateBase(typeDef, waveNum, hpScale, speedScale)
    enemy.isElite = isElite or false

    if isElite then
        ApplyAffixes(enemy, affixes)
    end

    AddEnemy(enemy)

    local prefix = isElite and "[精英]" or ""
    local affixNames = ""
    if isElite and affixes and #affixes > 0 then
        local names = {}
        for _, a in ipairs(affixes) do names[#names + 1] = a.name end
        affixNames = " [" .. table.concat(names, "+") .. "]"
    end
    print(string.format("[Enemy] Spawned %s%s%s HP=%.0f SPD=%.0f",
        prefix, typeDef.name, affixNames, enemy.hp, enemy.speed))

    return enemy
end

--- 创建 BOSS
function Enemy.CreateBoss(bossDef, waveNum, hpScale, speedScale, affixes, tier)
    local enemy = CreateBase(bossDef, waveNum, hpScale, speedScale)
    enemy.isBoss = true
    enemy.bossTier = tier or 1
    enemy.isEmeraldDungeon = bossDef.isEmeraldDungeon or false

    -- BOSS 被动计时器初始化
    if bossDef.passive == "disable" then
        enemy.disableTimer = bossDef.disableInterval or 8.0
    elseif bossDef.passive == "summon" then
        enemy.summonTimer = bossDef.summonInterval or 6.0
    elseif bossDef.passive == "phase" then
        enemy.phaseTimer = bossDef.phaseInterval or 5.0
    end

    ApplyAffixes(enemy, affixes)

    AddEnemy(enemy)

    local affixNames = ""
    if affixes and #affixes > 0 then
        local names = {}
        for _, a in ipairs(affixes) do names[#names + 1] = a.name end
        affixNames = " [" .. table.concat(names, "+") .. "]"
    end
    print(string.format("[Enemy] BOSS Spawned: %s (Tier %d)%s HP=%.0f",
        bossDef.name, tier, affixNames, enemy.hp))

    return enemy
end

--- 创建分裂出的小怪（无词缀，继承父怪进度）
function Enemy.CreateSplitChild(typeId, waveNum, progress, hpScale, speedScale)
    local typeDef = Config.ENEMY_TYPES[typeId]
    if not typeDef then return nil end

    local enemy = CreateBase(typeDef, waveNum, hpScale * 0.4, speedScale)
    enemy.progress = progress + (mrandom() - 0.5) * 0.02  -- 微小偏移
    if enemy.progress < 0 then enemy.progress = 0 end

    AddEnemy(enemy)
    return enemy
end

--- 从完整 def 创建分裂小怪（新系统用）
function Enemy.CreateSplitChildFromDef(typeDef, waveNum, progress, hpScale, speedScale)
    if not typeDef then return nil end

    local enemy = CreateBase(typeDef, waveNum, hpScale * 0.4, speedScale)
    enemy.progress = progress + (mrandom() - 0.5) * 0.02
    if enemy.progress < 0 then enemy.progress = 0 end

    AddEnemy(enemy)
    return enemy
end

local function HandleEnemyDeath(enemy)

    -- 不朽词缀：首次死亡复活
    if enemy.affixIds["undying"] and not enemy.revived then
        enemy.revived = true
        local reviveRate = 0.5
        for _, a in ipairs(enemy.affixes) do
            if a.reviveHPRate then reviveRate = a.reviveHPRate end
        end
        enemy.hp = enemy.maxHP * reviveRate
        -- 复活时强制解除隐身，确保玩家能看到复活效果并索敌
        if enemy.phaseActive then
            enemy.phaseActive = false
            local interval = 4.0
            for _, a in ipairs(enemy.affixes) do
                if a.phaseInterval then interval = a.phaseInterval end
            end
            enemy.phaseTimer = interval
        end
        AddFloatingText({
            text = "复活!",
            x = enemy.x, y = enemy.y - 15,
            life = 1.0,
            color = { 255, 220, 60, 255 },
        })
        print("[Enemy] " .. enemy.typeDef.name .. " revived!")
        return
    end

    enemy.alive = false
    State.aliveEnemyCount = State.aliveEnemyCount - 1
    EnemyAnim.OnDeath(enemy)     -- 死亡淡出动画
    -- 击杀奖励：暗魂（战斗内货币，固定值）
    local reward = enemy.typeDef.reward
    Currency.CollectDarkSoul(reward)
    State.score = State.score + reward

    -- 暗魂飘字
    AddFloatingText({
        text = "+" .. reward,
        x = enemy.x, y = enemy.y - 8,
        life = 0.8,
        color = { 80, 150, 220, 255 },
        fontSize = 11,
    })

    -- ======== 击杀掉落局外货币（掉落物动画） ========
    local enemyTier = enemy.isBoss and "boss" or (enemy.isElite and "elite" or "normal")
    local s = State.currentStage - 1
    local dropScale = 1.0 + s * Config.KILL_DROP.stageScale + s * s * (Config.KILL_DROP.stageQuadratic or 0)

    -- 冥晶（紫色）→ 掉落物
    local crystalBase = Config.KILL_DROP.crystal[enemyTier] or 0
    if crystalBase > 0 then
        local crystalAmt = mfloor(crystalBase * dropScale)
        -- 神裔降临：冥晶加成（周末磐古自动 ×1.5 / 工作日选择磐古时 ×1.5）
        local crystalMulti = DivineBlessDB.GetBuffValue("crystal_multi")
        if crystalMulti > 1.0 then crystalAmt = mfloor(crystalAmt * crystalMulti) end
        if crystalAmt > 0 then
            LootDrop.Spawn("nether_crystal", crystalAmt, enemy.x, enemy.y)
        end
    end

    -- 噬魂石（绿色，精英/BOSS）→ 掉落物
    local stoneBase = Config.KILL_DROP.stone[enemyTier] or 0
    if stoneBase > 0 then
        local stoneAmt = mfloor(stoneBase * dropScale)
        -- 神裔降临：噬魂石加成
        local stoneMulti = DivineBlessDB.GetBuffValue("stone_multi")
        if stoneMulti > 1.0 then stoneAmt = mfloor(stoneAmt * stoneMulti) end
        if stoneAmt > 0 then
            LootDrop.Spawn("devour_stone", stoneAmt, enemy.x, enemy.y)
        end
    end

    -- 锻魂铁（蓝白色，仅BOSS）→ 掉落物
    local ironBase = Config.KILL_DROP.iron[enemyTier] or 0
    if ironBase > 0 then
        local ironAmt = mfloor(ironBase * dropScale)
        -- 神裔降临：锻魂铁加成
        local ironMulti = DivineBlessDB.GetBuffValue("iron_multi")
        if ironMulti > 1.0 then ironAmt = mfloor(ironAmt * ironMulti) end
        if ironAmt > 0 then
            LootDrop.Spawn("forge_iron", ironAmt, enemy.x, enemy.y)
        end
    end

    -- 死亡粒子
    local particleCount = enemy.isBoss and 16 or 8
    for i = 1, particleCount do
        local angle = mrandom() * mpi * 2
        local spd = 30 + mrandom() * 50
        AddParticle({
            x = enemy.x, y = enemy.y,
            vx = mcos(angle) * spd,
            vy = msin(angle) * spd,
            life = 0.6 + mrandom() * 0.4,
            maxLife = 1.0,
            color = enemy.typeDef.color,
            size = 3 + mrandom() * 3,
        })
    end

    -- 分裂被动（支持 splitRole 和向后兼容 splitTypeId）
    if enemy.typeDef.passive == "split" then
        local count = enemy.typeDef.splitCount or 2
        local hpScale, speedScale = CalcScalesFromGlobalWave(enemy.waveNum)
        if enemy.typeDef.splitRole then
            -- 新系统：按 role 分裂，用同主题的对应角色
            local stageNum = mfloor((enemy.waveNum - 1) / Config.WAVES_PER_STAGE) + 1
            local splitDef = Config.BuildEnemyDef(stageNum, enemy.typeDef.splitRole)
            if splitDef then
                for i = 1, count do
                    Enemy.CreateSplitChildFromDef(splitDef, enemy.waveNum, enemy.progress, hpScale, speedScale)
                end
            end
        elseif enemy.typeDef.splitTypeId then
            -- 向后兼容
            for i = 1, count do
                Enemy.CreateSplitChild(enemy.typeDef.splitTypeId, enemy.waveNum, enemy.progress, hpScale, speedScale)
            end
        end
        print("[Enemy] " .. enemy.typeDef.name .. " split into " .. count)
    end

    -- death_silence 特殊被动：死亡时沉默周围塔
    if enemy.typeDef.specialPassive == "death_silence" then
        local range = enemy.typeDef.silenceRange or 80
        local dur = enemy.typeDef.silenceDuration or 2.0
        for _, tower in ipairs(State.towers) do
            local tx, ty = Grid.CellToScreen(tower.col, tower.row,
                Enemy._gridOffsetX, Enemy._gridOffsetY)
            local dx = tx - enemy.x
            local dy = ty - enemy.y
            if dx * dx + dy * dy <= range * range then
                Debuff.Apply(tower, "silence", { duration = dur })
            end
        end
        AddFloatingText({
            text = "沉默!",
            x = enemy.x, y = enemy.y - 10,
            life = 1.0,
            color = { 140, 60, 200, 255 },
        })
    end

    print("[Enemy] " .. enemy.typeDef.name .. " killed, reward=" .. enemy.typeDef.reward)
    return true  -- 返回击杀结果，供 OnHit 触发击杀效果（fire_spread/double_soul/killReset）
end

-- ============================================================================
-- 伤害处理
-- ============================================================================

--- 对敌人造成伤害（支持护盾、闪避、隐身无敌）
function Enemy.TakeDamage(enemy, damage)
    if not enemy.alive then return end

    -- 隐身无敌检查
    if enemy.phaseActive then return end

    -- 免疫控制词缀不影响伤害

    -- 闪避检查（角色被动 + 光环加成）
    local dodgeChance = 0
    if enemy.typeDef.passive == "dodge" then
        dodgeChance = enemy.typeDef.dodgeChance or 0.3
    end
    -- 光环 dodge_boost 加成
    if enemy.auraDodgeBoost then
        dodgeChance = dodgeChance + enemy.auraDodgeBoost
    end
    if dodgeChance > 0 and mrandom() < dodgeChance then
        AddFloatingText({
            text = "闪避",
            x = enemy.x + (mrandom() - 0.5) * 10,
            y = enemy.y - (enemy.typeDef.size or 8) - 5,
            life = 0.6,
            color = { 140, 180, 220, 255 },
        })
        return
    end

    -- first_hit_armor 特殊被动：首次受击减伤
    if enemy.firstHitArmored then
        enemy.firstHitArmored = false
        local reduce = enemy.typeDef.firstHitReduce or 0.50
        damage = damage * (1 - reduce)
        AddFloatingText({
            text = "护甲",
            x = enemy.x, y = enemy.y - (enemy.typeDef.size or 8) - 5,
            life = 0.5,
            color = { 100, 180, 255, 255 },
        })
    end

    -- 护盾先吸收
    if enemy.shield > 0 then
        if damage <= enemy.shield then
            enemy.shield = enemy.shield - damage
            -- 护盾吸收也触发受击反馈（轻微）
            enemy.hitFlash = 0.08
            return
        else
            damage = damage - enemy.shield
            enemy.shield = 0
        end
    end

    -- 世界BOSS伤害追踪
    if enemy.isWorldBoss and State.worldBossActive then
        State.worldBossTotalDamage = State.worldBossTotalDamage + damage
    end

    -- 受击反馈：闪白 + 抖动
    enemy.hitFlash = 0.12            -- 闪白持续时间
    enemy.hitShakeTimer = 0.1        -- 抖动持续时间
    enemy.hitShakeIntensity = mmin(damage / enemy.maxHP * 8, 4)  -- 按伤害比例抖动，上限4px
    EnemyAnim.OnHit(enemy)           -- 受击后退动画

    enemy.hp = enemy.hp - damage
    if enemy.hp <= 0 then
        enemy.hp = 0
        -- 世界BOSS/憎恨化身兜底：HP归零不走死亡，直接触发战斗结算
        if enemy.isWorldBoss then
            print("[Enemy] World boss HP reached 0, triggering battle end")
            State.bossTimer = 0
            return
        end
        return HandleEnemyDeath(enemy)
    end
end

--- 应用减速效果
function Enemy.ApplySlow(enemy, duration, rate)
    -- 静态免疫检查（immune_cc / void_aura 在创建/词缀时已注册）
    if Debuff.IsImmune(enemy, "slow") then return end

    -- 光环 slow_immune 检查（每帧动态计算，保留直接判断）
    if enemy.auraSlowImmune then return end

    -- 坦克被动 slow_resist：减少减速效果
    local actualRate = rate
    if enemy.typeDef.tankPassive == "slow_resist" then
        local resist = enemy.typeDef.slowResist or 0.50
        actualRate = rate * (1 - resist)
    end
    -- 光环 slow_resist 叠加
    if enemy.auraSlowResist then
        actualRate = actualRate * (1 - enemy.auraSlowResist)
    end

    -- 仅在首次施加或刷新时显示飘字（避免重复）
    if enemy.slowTimer <= 0 then
        AddFloatingText({
            text = "减速",
            x = enemy.x + (mrandom() - 0.5) * 10,
            y = enemy.y - (enemy.typeDef.size or 8) - 16,
            life = 0.5,
            color = { 60, 200, 200, 255 },
            fontSize = 10,
        })
    end

    enemy.slowTimer = mmax(enemy.slowTimer, duration)
    enemy.speed = enemy.baseSpeed * (1 - actualRate)
end

--- 应用DOT效果
function Enemy.ApplyDOT(enemy, damage, duration)
    -- 静态免疫检查（immune_cc / void_aura / dotImmune 均已注册）
    if Debuff.IsImmune(enemy, "dot") then return end

    enemy.dotDamage = damage
    enemy.dotTimer = mmax(enemy.dotTimer, duration)
    enemy.dotTickTimer = 0
end

-- ============================================================================
-- 寒意系统（凛冬君王专属）
-- ============================================================================

--- 对敌人施加寒意层数
---@param enemy table
---@param stacks number  施加层数
---@param duration number  持续时间
---@param towerId number|string  施加来源塔ID（用于追踪全局计数）
---@return number  实际新增层数（用于全局计数）
function Enemy.ApplyChill(enemy, stacks, duration, towerId)
    if not enemy.alive then return 0 end

    -- 静态免疫检查（immune_cc / void_aura 在创建/词缀时已注册）
    if Debuff.IsImmune(enemy, "chill") then return 0 end

    -- 初始化寒意数据
    if not enemy.chillStacks then
        enemy.chillStacks = 0
        enemy.chillTimer = 0
    end

    local maxStacks = 5
    local oldStacks = enemy.chillStacks
    enemy.chillStacks = mmin(enemy.chillStacks + stacks, maxStacks)
    enemy.chillTimer = mmax(enemy.chillTimer, duration)

    local added = enemy.chillStacks - oldStacks

    -- 应用减速效果：每层 10%，最多 50%
    local slowRate = enemy.chillStacks * 0.10
    -- BOSS 减速效率衰减
    if enemy.isBoss then
        slowRate = slowRate * (Config.BOSS_BALANCE and Config.BOSS_BALANCE.slowEfficiency or 0.50)
    end
    -- 坦克被动 slow_resist
    if enemy.typeDef.tankPassive == "slow_resist" then
        local resist = enemy.typeDef.slowResist or 0.50
        slowRate = slowRate * (1 - resist)
    end
    enemy.speed = enemy.baseSpeed * (1 - slowRate)

    -- 首次施加飘字
    if oldStacks == 0 and enemy.chillStacks > 0 then
        AddFloatingText({
            text = "寒意",
            x = enemy.x + (mrandom() - 0.5) * 10,
            y = enemy.y - (enemy.typeDef.size or 8) - 16,
            life = 0.5,
            color = { 130, 210, 255, 255 },
            fontSize = 10,
        })
    -- 满层时飘字
    elseif enemy.chillStacks >= maxStacks and oldStacks < maxStacks then
        AddFloatingText({
            text = "极寒!",
            x = enemy.x + (mrandom() - 0.5) * 10,
            y = enemy.y - (enemy.typeDef.size or 8) - 16,
            life = 0.8,
            color = { 80, 180, 255, 255 },
            fontSize = 13,
        })
        -- 寒意粒子
        for j = 1, 6 do
            local angle = mrandom() * mpi * 2
            AddParticle({
                x = enemy.x, y = enemy.y,
                vx = mcos(angle) * 30,
                vy = msin(angle) * 30,
                life = 0.5, maxLife = 0.6,
                color = { 130, 210, 255 },
                size = 3,
            })
        end
    end

    return added
end

--- 更新敌人寒意计时器（每帧调用）
function Enemy.UpdateChill(enemy, dt)
    if not enemy.chillStacks or enemy.chillStacks <= 0 then return end

    enemy.chillTimer = enemy.chillTimer - dt
    if enemy.chillTimer <= 0 then
        -- 寒意过期，清除所有层数
        enemy.chillStacks = 0
        enemy.chillTimer = 0
        -- 如果没有其他减速效果，恢复速度
        if enemy.slowTimer <= 0 then
            enemy.speed = enemy.baseSpeed
        end
    end
end

--- 检查敌人是否有满层寒意
---@param enemy table
---@return boolean
function Enemy.HasMaxChill(enemy)
    return (enemy.chillStacks or 0) >= 5
end

--- 获取敌人寒意增伤倍率
--- 满5层时受到的伤害增加50%
---@param enemy table
---@return number  伤害倍率（1.0 = 无增伤，1.5 = 满层增伤）
function Enemy.GetChillDamageAmp(enemy)
    if Enemy.HasMaxChill(enemy) then
        return 1.50  -- 满层增伤 50%
    end
    return 1.0
end

-- ============================================================================
-- 更新
-- ============================================================================

--- 更新光环效果（每帧重新计算）
--- 优化：先收集光环源（通常极少），再只做 m×n 而非 n×n 遍历
local auraSources = {}  -- 复用表，避免每帧分配
local function UpdateAuras(gridOffsetX, gridOffsetY)
    local enemies = State.enemies
    local srcCount = 0

    -- 清除光环标记 + 收集光环源（单次遍历）
    for _, e in ipairs(enemies) do
        if e.alive then
            e.auraSpeedBoost = nil
            e.auraSlowResist = nil
            e.auraDodgeBoost = nil
            e.auraSlowImmune = nil
            if e.typeDef.passive == "aura" and e.typeDef.aura then
                srcCount = srcCount + 1
                auraSources[srcCount] = e
            end
        end
    end

    -- 无光环源则跳过
    if srcCount == 0 then return end

    -- 遍历光环源 × 全体敌人（O(m×n)，m 远小于 n）
    for si = 1, srcCount do
        local src = auraSources[si]
        local aura = src.typeDef.aura
        local range = aura.range or 60
        local rangeSq = range * range

        for _, tgt in ipairs(enemies) do
            if tgt.alive and tgt.id ~= src.id then
                local dx = tgt.x - src.x
                local dy = tgt.y - src.y
                if dx * dx + dy * dy <= rangeSq then
                    if aura.type == "speed" then
                        tgt.auraSpeedBoost = mmax(tgt.auraSpeedBoost or 0, aura.value or 0)
                    elseif aura.type == "slow_resist" then
                        tgt.auraSlowResist = mmax(tgt.auraSlowResist or 0, aura.value or 0)
                    elseif aura.type == "dodge_boost" then
                        tgt.auraDodgeBoost = mmax(tgt.auraDodgeBoost or 0, aura.value or 0)
                    elseif aura.type == "slow_immune" then
                        tgt.auraSlowImmune = true
                    end
                end
            end
        end
        auraSources[si] = nil  -- 释放引用
    end
end

--- 更新所有敌人
local function UpdateHitFeedback(e, dt)
    -- ======== 受击反馈计时器衰减 ========
    if e.hitFlash and e.hitFlash > 0 then
        e.hitFlash = e.hitFlash - dt
        if e.hitFlash <= 0 then e.hitFlash = nil end
    end
    if e.hitShakeTimer and e.hitShakeTimer > 0 then
        e.hitShakeTimer = e.hitShakeTimer - dt
        if e.hitShakeTimer <= 0 then
            e.hitShakeTimer = nil
            e.hitShakeIntensity = nil
        end
    end

end

local function UpdateAffixEffects(e, dt)
    -- ======== 词缀被动效果 ========

    -- 再生词缀
    if e.affixIds["regen"] then
        local rate = 0.01
        for _, a in ipairs(e.affixes) do
            if a.regenRate then rate = a.regenRate end
        end
        e.hp = mmin(e.hp + e.maxHP * rate * dt, e.maxHP)
    end

    -- 铁壁词缀：每隔 N 秒增加 DEF
    if e.affixIds["iron_wall"] then
        local interval = 6.0
        local defPct = 0.10
        for _, a in ipairs(e.affixes) do
            if a.ironWallInterval then interval = a.ironWallInterval end
            if a.ironWallDefPct then defPct = a.ironWallDefPct end
        end
        e.ironWallTimer = (e.ironWallTimer or 0) + dt
        if e.ironWallTimer >= interval then
            e.ironWallTimer = e.ironWallTimer - interval
            e.ironWallStacks = (e.ironWallStacks or 0) + 1
            local addDef = mfloor((e.typeDef.baseDEF or 0) * defPct)
            e.def = e.def + addDef
            AddFloatingText({
                text = "铁壁+" .. e.ironWallStacks,
                x = e.x + (mrandom() - 0.5) * 10,
                y = e.y - (e.typeDef.size or 8) - 5,
                life = 0.6,
                color = { 160, 160, 180, 255 },
                fontSize = 10,
            })
        end
    end

    -- 回春词缀：每隔 N 秒恢复已损失 HP 百分比
    if e.affixIds["rejuvenate"] then
        local interval = 5.0
        local pct = 0.05
        for _, a in ipairs(e.affixes) do
            if a.rejuvInterval then interval = a.rejuvInterval end
            if a.rejuvPct then pct = a.rejuvPct end
        end
        e.rejuvTimer = (e.rejuvTimer or 0) + dt
        if e.rejuvTimer >= interval then
            e.rejuvTimer = e.rejuvTimer - interval
            local lost = e.maxHP - e.hp
            if lost > 0 then
                local heal = lost * pct
                e.hp = mmin(e.hp + heal, e.maxHP)
                AddFloatingText({
                    text = "回春",
                    x = e.x + (mrandom() - 0.5) * 10,
                    y = e.y - (e.typeDef.size or 8) - 5,
                    life = 0.5,
                    color = { 100, 220, 160, 255 },
                    fontSize = 10,
                })
            end
        end
    end

    -- 降星词缀：每隔 N 秒随机降低一个英雄塔 1 星
    if e.affixIds["star_drain"] then
        local interval = 12.0
        for _, a in ipairs(e.affixes) do
            if a.starDrainInterval then interval = a.starDrainInterval end
        end
        e.starDrainTimer = (e.starDrainTimer or 0) + dt
        if e.starDrainTimer >= interval then
            e.starDrainTimer = e.starDrainTimer - interval
            -- 找一个星级 > 1 的非 Leader 塔降星
            local candidates = {}
            for _, t in ipairs(State.towers) do
                if not t.isLeader and t.star > 1 then
                    candidates[#candidates + 1] = t
                end
            end
            if #candidates > 0 then
                local target = candidates[mrandom(1, #candidates)]
                local oldStar = target.star
                target.star = target.star - 1
                -- 重新计算塔的战斗属性
                Tower.RecalcStats(target)
                AddFloatingText({
                    text = target.typeDef.name .. " ★-1",
                    x = e.x, y = e.y - (e.typeDef.size or 8) - 15,
                    life = 1.0,
                    color = { 200, 80, 200, 255 },
                })
                print("[Affix] star_drain: " .. target.typeDef.name .. " " .. oldStar .. "★ → " .. target.star .. "★")
            end
        end
    end

    -- 毁灭词缀：每隔 N 秒销毁一个随机英雄塔
    if e.affixIds["annihilate"] then
        local interval = 20.0
        for _, a in ipairs(e.affixes) do
            if a.annihilateInterval then interval = a.annihilateInterval end
        end
        e.annihilateTimer = (e.annihilateTimer or 0) + dt
        if e.annihilateTimer >= interval then
            e.annihilateTimer = e.annihilateTimer - interval
            -- 找一个非 Leader 塔销毁
            local candidates = {}
            for _, t in ipairs(State.towers) do
                if not t.isLeader then
                    candidates[#candidates + 1] = t
                end
            end
            if #candidates > 0 then
                local target = candidates[mrandom(1, #candidates)]
                local towerName = target.typeDef and target.typeDef.name or "塔"
                local tx, ty = Grid.CellToScreen(target.col, target.row,
                    Enemy._gridOffsetX, Enemy._gridOffsetY)
                Tower.Remove(target)
                AddFloatingText({
                    text = "毁灭! " .. towerName,
                    x = tx, y = ty - 10,
                    life = 1.2,
                    color = { 255, 40, 40, 255 },
                })
                -- 毁灭粒子
                for j = 1, 10 do
                    local angle = mrandom() * mpi * 2
                    AddParticle({
                        x = tx, y = ty,
                        vx = mcos(angle) * 50,
                        vy = msin(angle) * 50,
                        life = 0.6, maxLife = 0.8,
                        color = { 255, 40, 40 },
                        size = 4,
                    })
                end
                print("[Affix] annihilate: destroyed " .. towerName)
            end
        end
    end

    -- ====== 通用减益词缀（debuff category）======
    -- 统一处理 atk_down/spd_down/crit_down/critdmg_down/pen_down/elem_down
    do
        -- 使用 ApplyAffixes 时预计算的 debuff 词缀列表
        local debuffAffixes = e._debuffAffixes
        if debuffAffixes then
            -- 取最短间隔作为统一 tick（每个词缀独立判断自己的间隔也可，但这里共享 timer 简化）
            for _, da in ipairs(debuffAffixes) do
                local interval = da.debuffInterval or 10.0
                -- 每个 debuff 词缀用自己 id 做独立计时器
                local timerKey = "dbTimer_" .. da.id
                e[timerKey] = (e[timerKey] or 0) + dt
                if e[timerKey] >= interval then
                    e[timerKey] = e[timerKey] - interval
                    local stat = da.debuffStat
                    local duration = da.debuffDuration or 4.0
                    local value = da.debuffPct or da.debuffFlat or 0.1
                    local mode = da.debuffPct and "pct" or "flat"
                    local targeting = da.targeting or "single"
                    local radius = da.debuffRadius or 120

                    -- 根据 targeting 获取目标塔列表
                    local targets = {}
                    if targeting == "group" then
                        -- 全体：所有非 Leader 塔
                        for _, t in ipairs(State.towers) do
                            if not t.isLeader then targets[#targets + 1] = t end
                        end
                    elseif targeting == "area" then
                        -- 范围：以敌人位置为中心，半径内的塔
                        for _, t in ipairs(State.towers) do
                            if not t.isLeader then
                                local tx, ty = Grid.CellToScreen(t.col, t.row,
                                    Enemy._gridOffsetX, Enemy._gridOffsetY)
                                local dist = msqrt((e.x - tx) ^ 2 + (e.y - ty) ^ 2)
                                if dist <= radius then
                                    targets[#targets + 1] = t
                                end
                            end
                        end
                    else
                        -- 单体：随机一个非 Leader 塔
                        local pool = {}
                        for _, t in ipairs(State.towers) do
                            if not t.isLeader then pool[#pool + 1] = t end
                        end
                        if #pool > 0 then
                            targets[#targets + 1] = pool[mrandom(1, #pool)]
                        end
                    end

                    -- 施加 debuff
                    for _, target in ipairs(targets) do
                        Tower.ApplyDebuff(target, da.id, stat, value, mode, duration)
                        local tx, ty = Grid.CellToScreen(target.col, target.row,
                            Enemy._gridOffsetX, Enemy._gridOffsetY)
                        AddFloatingText({
                            text = da.name .. (targeting == "group" and "!" or ""),
                            x = tx + (mrandom() - 0.5) * 10,
                            y = ty - 15,
                            life = 0.8,
                            color = da.color and { da.color[1], da.color[2], da.color[3], 255 }
                                or { 255, 100, 100, 255 },
                            fontSize = 10,
                        })
                    end
                    if #targets > 0 then
                        print("[Affix] " .. da.id .. " (" .. targeting .. "): debuff "
                            .. stat .. " on " .. #targets .. " tower(s)")
                    end
                end
            end
        end
    end

    -- 狂暴词缀
    if e.affixIds["berserk"] then
        local threshold, mult = 0.5, 1.8
        for _, a in ipairs(e.affixes) do
            if a.enrageThreshold then threshold = a.enrageThreshold end
            if a.enrageSpeedMult then mult = a.enrageSpeedMult end
        end
        if e.hp / e.maxHP <= threshold then
            e.speed = e.baseSpeed * mult
        end
    end

    -- 隐身词缀：周期性隐身（复用 phaseActive，与 BOSS phase 被动共享渲染逻辑）
    if e.affixIds["stealth"] and e.typeDef.passive ~= "phase" then
        local interval = 4.0
        local duration = 1.5
        for _, a in ipairs(e.affixes) do
            if a.phaseInterval then interval = a.phaseInterval end
            if a.phaseDuration then duration = a.phaseDuration end
        end
        -- NaN 防护：phaseTimer 异常时强制重置（NaN ~= NaN 为 true）
        if e.phaseTimer ~= e.phaseTimer then
            e.phaseActive = false
            e.phaseTimer = interval
            e._phaseElapsed = 0
        elseif e.phaseActive then
            e.phaseTimer = e.phaseTimer - dt
            e._phaseElapsed = (e._phaseElapsed or 0) + dt
            -- 安全上限：隐身时间不超过 duration × 2，防止边界情况导致永久隐身
            if e.phaseTimer <= 0 or e._phaseElapsed >= duration * 2 then
                e.phaseActive = false
                e.phaseTimer = interval
                e._phaseElapsed = 0
            end
        else
            e._phaseElapsed = 0
            e.phaseTimer = e.phaseTimer - dt
            if e.phaseTimer <= 0 then
                e.phaseActive = true
                e.phaseTimer = duration
            end
        end
    end

end

local function UpdateMonsterPassives(e, dt)
    -- ======== 怪物被动效果 ========

    -- BOSS: 狂暴被动
    if e.typeDef.passive == "enrage" then
        local threshold = e.typeDef.enrageThreshold or 0.5
        local mult = e.typeDef.enrageSpeedMult or 2.0
        if e.hp / e.maxHP <= threshold then
            e.speed = mmax(e.speed, e.baseSpeed * mult)
        end
    end

    -- BOSS: 隐身无敌
    if e.typeDef.passive == "phase" then
        local phaseDur = e.typeDef.phaseDuration or 2.5
        local phaseInt = e.typeDef.phaseInterval or 5.0
        -- NaN 防护：phaseTimer 异常时强制重置
        if e.phaseTimer ~= e.phaseTimer then
            e.phaseActive = false
            e.phaseTimer = phaseInt
            e._phaseElapsed = 0
        elseif e.phaseActive then
            e.phaseTimer = e.phaseTimer - dt
            e._phaseElapsed = (e._phaseElapsed or 0) + dt
            -- 安全上限：防止永久隐身
            if e.phaseTimer <= 0 or e._phaseElapsed >= phaseDur * 2 then
                e.phaseActive = false
                e.phaseTimer = phaseInt
                e._phaseElapsed = 0
            end
        else
            e._phaseElapsed = 0
            e.phaseTimer = e.phaseTimer - dt
            if e.phaseTimer <= 0 then
                e.phaseActive = true
                e.phaseTimer = phaseDur
            end
        end
    end

    -- BOSS: 召唤小怪（支持 summonRole 和向后兼容 summonTypeId）
    if e.typeDef.passive == "summon" then
        e.summonTimer = e.summonTimer - dt
        if e.summonTimer <= 0 then
            e.summonTimer = e.typeDef.summonInterval or 6.0
            local sCount = e.typeDef.summonCount or 2
            local hpS, spS = CalcScalesFromGlobalWave(e.waveNum)
            hpS = hpS * 0.5  -- 召唤物 HP 减半
            if e.typeDef.summonRole then
                local stageNum = mfloor((e.waveNum - 1) / Config.WAVES_PER_STAGE) + 1
                local summonDef = Config.BuildEnemyDef(stageNum, e.typeDef.summonRole)
                if summonDef then
                    for j = 1, sCount do
                        Enemy.CreateSplitChildFromDef(summonDef, e.waveNum, e.progress, hpS, spS)
                    end
                end
            elseif e.typeDef.summonTypeId then
                for j = 1, sCount do
                    Enemy.CreateSplitChild(e.typeDef.summonTypeId, e.waveNum, e.progress, hpS, spS)
                end
            end
            print("[Enemy] BOSS " .. e.typeDef.name .. " summoned " .. sCount)
        end
    end

    -- 传送者: 闪烁
    if e.typeDef.passive == "blink" then
        e.blinkTimer = e.blinkTimer + dt
        if e.blinkTimer >= (e.typeDef.blinkInterval or 4.0) then
            e.blinkTimer = 0
            e.progress = e.progress + (e.typeDef.blinkProgress or 0.08)
            -- 闪烁粒子
            for j = 1, 5 do
                local angle = mrandom() * mpi * 2
                AddParticle({
                    x = e.x, y = e.y,
                    vx = mcos(angle) * 40,
                    vy = msin(angle) * 40,
                    life = 0.4, maxLife = 0.5,
                    color = e.typeDef.color,
                    size = 3,
                })
            end
        end
    end

    -- BOSS: 禁锢（周期性沉默附近塔防）
    if e.typeDef.passive == "disable" then
        e.disableTimer = e.disableTimer - dt
        if e.disableTimer <= 0 then
            local dur = e.typeDef.disableDuration or 2.0
            local range = 100  -- 禁锢范围
            e.disableTimer = e.typeDef.disableInterval or 8.0
            -- 沉默范围内的塔
            for _, tower in ipairs(State.towers) do
                local tx, ty = Grid.CellToScreen(tower.col, tower.row,
                    Enemy._gridOffsetX, Enemy._gridOffsetY)
                local dx = tx - e.x
                local dy = ty - e.y
                if dx * dx + dy * dy <= range * range then
                    Debuff.Apply(tower, "silence", { duration = dur })
                end
            end
            -- 禁锢特效
            AddFloatingText({
                text = "禁锢!",
                x = e.x, y = e.y - (e.typeDef.size or 8) - 10,
                life = 1.0,
                color = { 200, 60, 60, 255 },
            })
            for j = 1, 8 do
                local angle = j * mpi / 4
                AddParticle({
                    x = e.x, y = e.y,
                    vx = mcos(angle) * 60,
                    vy = msin(angle) * 60,
                    life = 0.6, maxLife = 0.6,
                    color = { 200, 60, 60 },
                    size = 4,
                })
            end
        end
    end

    -- ======== 坦克被动：regen（周期回血）========
    if e.typeDef.tankPassive == "regen" then
        local rate = e.typeDef.regenRate or 0.005
        e.hp = mmin(e.hp + e.maxHP * rate * dt, e.maxHP)
    end

    -- ======== 特殊被动 ========

    -- regen_lost: 每隔一段时间恢复已损失生命值的一定百分比
    if e.typeDef.specialPassive == "regen_lost" then
        e.regenLostTimer = (e.regenLostTimer or 0) + dt
        local interval = e.typeDef.regenInterval or 3.0
        if e.regenLostTimer >= interval then
            e.regenLostTimer = e.regenLostTimer - interval
            local pct = e.typeDef.regenLostPct or 0.05
            local lost = e.maxHP - e.hp
            if lost > 0 then
                e.hp = mmin(e.hp + lost * pct, e.maxHP)
            end
        end
    end

    -- poison_trail: 经过的位置降低附近塔攻击力（通过标记实现）
    if e.typeDef.specialPassive == "poison_trail" then
        e.poisonTrailTimer = (e.poisonTrailTimer or 0) + dt
        if e.poisonTrailTimer >= 1.0 then
            e.poisonTrailTimer = e.poisonTrailTimer - 1.0
            -- 在当前位置留下毒径粒子
            AddParticle({
                x = e.x, y = e.y,
                vx = 0, vy = 0,
                life = e.typeDef.trailDuration or 3.0,
                maxLife = e.typeDef.trailDuration or 3.0,
                color = { 100, 60, 140 },
                size = 6,
                isPoisonTrail = true,
                atkReduce = e.typeDef.trailAtkReduce or 0.20,
            })
        end
    end

end

local function UpdateTimers(e, dt)
    -- ======== 光环速度加成 ========
    if e.auraSpeedBoost and e.auraSpeedBoost > 0 then
        -- 仅在非减速时应用加速
        if e.slowTimer <= 0 then
            e.speed = e.baseSpeed * (1 + e.auraSpeedBoost)
        end
    end

    -- ======== 减速恢复 ========
    if e.slowTimer > 0 then
        e.slowTimer = e.slowTimer - dt
        if e.slowTimer <= 0 then
            -- 如果还有寒意减速，不完全恢复
            if e.chillStacks and e.chillStacks > 0 then
                local chillSlow = e.chillStacks * 0.10
                if e.isBoss then
                    chillSlow = chillSlow * (Config.BOSS_BALANCE and Config.BOSS_BALANCE.slowEfficiency or 0.50)
                end
                if e.typeDef.tankPassive == "slow_resist" then
                    chillSlow = chillSlow * (1 - (e.typeDef.slowResist or 0.50))
                end
                e.speed = e.baseSpeed * (1 - chillSlow)
            else
                e.speed = e.baseSpeed
            end
        end
    end

    -- ======== 寒意衰减 ========
    Enemy.UpdateChill(e, dt)

    -- ======== DOT 伤害 ========
    if e.dotTimer > 0 then
        e.dotTimer = e.dotTimer - dt
        e.dotTickTimer = e.dotTickTimer + dt
        if e.dotTickTimer >= 0.5 then
            e.dotTickTimer = e.dotTickTimer - 0.5
            Enemy.TakeDamage(e, e.dotDamage * 0.5)
        end
    end

end

-- 速度软上限：超出 SOFT_CAP 部分按 DIMINISH 衰减，不超过 HARD_CAP
local SPEED_SOFT_CAP  = 200
local SPEED_DIMINISH  = 0.3
local SPEED_HARD_CAP  = 350

local function ClampSpeed(speed)
    if speed <= SPEED_SOFT_CAP then return speed end
    local clamped = SPEED_SOFT_CAP + (speed - SPEED_SOFT_CAP) * SPEED_DIMINISH
    if clamped > SPEED_HARD_CAP then clamped = SPEED_HARD_CAP end
    return clamped
end

local function UpdateMovement(e, dt, pathLen, gridOffsetX, gridOffsetY)
    -- ======== 移动（眩晕/冰冻时停止） ========
    local isImmobilized = (e.stunTimer and e.stunTimer > 0)
                       or (e.frozenTimer and e.frozenTimer > 0)
    if e.alive and pathLen > 0 and not isImmobilized then
        local moveDist = ClampSpeed(e.speed) * dt
        e.progress = e.progress + moveDist / pathLen

        -- 到达终点后循环（环形路径直接绕圈，非环形也回起点继续）
        if e.progress >= 1.0 then
            e.progress = e.progress - 1.0
            e.loops = e.loops + 1
        end
        e.x, e.y = Grid.GetPositionOnPath(e.progress, gridOffsetX, gridOffsetY)
    end

    -- ======== 缓存路径方向/法线供渲染使用 ========
    local pdx, pdy = Grid.GetPathDirection(e.progress, gridOffsetX, gridOffsetY)
    e._pdx, e._pdy = pdx, pdy
    if e.isBoss then
        e._pnx, e._pny = Grid.GetPathOutwardNormal(e.progress, gridOffsetX, gridOffsetY)
    end
end

function Enemy.Update(dt, gridOffsetX, gridOffsetY)
    -- dt 防护：NaN 或异常大值（如设备休眠恢复）会破坏计时器算术
    if dt ~= dt or dt > 1.0 then
        dt = 1.0 / 60.0  -- 回退到 60fps 帧时间
    end

    local pathLen = Grid.GetPathLength(gridOffsetX, gridOffsetY)

    -- 缓存偏移（供 TakeDamage 死亡回调使用）
    Enemy._gridOffsetX = gridOffsetX
    Enemy._gridOffsetY = gridOffsetY

    -- 先更新光环效果
    UpdateAuras(gridOffsetX, gridOffsetY)

    -- 两阶段更新：
    -- 阶段1: 遍历处理所有存活敌人（死亡只设 alive=false，新生敌人进延迟队列）
    -- 阶段2: CompactDead 移除死亡敌人 → FlushPending 刷入新生敌人
    -- 这样遍历中绝不修改数组长度，彻底消除 nil 空洞风险。
    _updating = true
    local enemies = State.enemies
    for i = 1, #enemies do
        local e = enemies[i]
        if e ~= nil and e.alive then
            e.animTime = e.animTime + dt

            UpdateHitFeedback(e, dt)
            UpdateAffixEffects(e, dt)
            UpdateMonsterPassives(e, dt)
            UpdateTimers(e, dt)
            UpdateMovement(e, dt, pathLen, gridOffsetX, gridOffsetY)
        end

        -- 不再需要 swap-and-pop：死亡敌人保留 alive=false 标记
        -- 循环结束后由 CompactDead 统一移除
    end

    -- 阶段2: 统一清理 + 刷入新生成的敌人
    _updating = false
    EnemyAnim.Update(dt, State.enemies)   -- 更新死亡/受击/呼吸动画计时器
    CompactDead()
    FlushPending()
end

--- 获取存活敌人数量（运行计数，O(1)）
function Enemy.GetAliveCount()
    return State.aliveEnemyCount
end

--- 获取最早有存活敌人的波次号（用于结算时计算实际通关波数）
--- 实际通关波数 = GetFirstAliveWaveNum() - 1
---@return number|nil waveNum 最早存活敌人的波次号，nil 表示全部清除
function Enemy.GetFirstAliveWaveNum()
    local earliest = nil
    for _, e in ipairs(State.enemies) do
        if e.alive then
            local w = e.waveNum or 1
            if not earliest or w < earliest then
                earliest = w
            end
        end
    end
    return earliest
end

return Enemy
