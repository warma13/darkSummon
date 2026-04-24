-- Game/Combat.lua
-- 暗黑塔防游戏 - 战斗计算系统
-- v3: 链式攻击、光环系统、BOSS平衡、技能升级集成

local Config     = require("Game.Config")
local F          = require("Game.FormulaLib")
local State      = require("Game.State")
local Enemy      = require("Game.Enemy")
local HeroSkills = require("Game.HeroSkills")
local Debuff     = require("Game.Debuff")
local AudioManager = require("Game.AudioManager")
local HeroAnim = require("Game.HeroAnim")

-- 音效节流：避免高频攻击时音效堆叠
local lastAttackSfxTime = 0
local lastHitSfxTime = 0
local SFX_ATTACK_INTERVAL = 0.15   -- 攻击音效最小间隔
local SFX_HIT_INTERVAL = 0.12      -- 命中音效最小间隔
local Tower = require("Game.Tower")
local LootDrop = require("Game.LootDrop")
local DamageStats = require("Game.DamageStats")
local HatredBossSkills = require("Game.HatredBossSkills")

local Combat = {}

-- 模块级 enemyById 查找表（Combat.Update 中构建，OnProjectileHit 中复用）
local _enemyById = {}

-- ========== 空间网格哈希（FindTarget / FindChainTarget 加速） ==========
-- 每帧在 Combat.Update 中重建（O(E)），查询时只检查邻近格子（O(K)，K≪E）
local SPATIAL_CELL = Config.CELL_SIZE  -- 42px，与网格格子大小一致
local _spatialGrid = {}

--- 重建空间网格（每帧调用一次）
local function RebuildSpatialGrid()
    -- 清除旧数据
    for k in pairs(_spatialGrid) do _spatialGrid[k] = nil end
    for _, e in ipairs(State.enemies) do
        if e.alive and not e.phaseActive then
            local cx = math.floor(e.x / SPATIAL_CELL)
            local cy = math.floor(e.y / SPATIAL_CELL)
            local key = cx * 10000 + cy
            local cell = _spatialGrid[key]
            if not cell then
                cell = {}
                _spatialGrid[key] = cell
            end
            cell[#cell + 1] = e
        end
    end
end

-- 粒子/飘字安全添加（带数量上限），共享定义在 State.lua
local AddFloatingText = State.AddFloatingText
local AddParticle = State.AddParticle

-- 预定义飘字颜色（避免每次创建新 table）
local COLOR_CRIT       = { 255, 60, 60, 255 }
local COLOR_RESIST     = { 140, 140, 140 }
local COLOR_AMP_MARK   = { 200, 100, 255, 255 }
local COLOR_ARMOR_BREAK = { 255, 180, 60, 255 }

--- 获取元素伤害的飘字颜色（弱点=元素色高亮，抗性=灰色，普通=塔色）
---@param heroElement string|nil
---@param elemMult number
---@param towerColor table
---@return table color
---@return string|nil suffix  弱点/抗性后缀
local function GetElementDmgColor(heroElement, elemMult, towerColor)
    if not heroElement or elemMult == 1.0 then
        return towerColor, nil
    end
    local elemDef = Config.ELEMENTS[heroElement]
    if elemMult > 1.05 then
        -- 弱点：元素色
        return elemDef and elemDef.color or towerColor, nil
    elseif elemMult < 0.95 then
        -- 抗性：灰暗色
        return COLOR_RESIST, nil
    end
    return towerColor, nil
end

--- 格式化大数字（万/亿/万亿）
---@param n number
---@return string
local function FormatDamage(n)
    if not n or n ~= n then return "0" end  -- nil / NaN 保护
    n = math.floor(n)
    if n >= 1e12 then
        local v = n / 1e12
        local s = v >= 100 and string.format("%.0f万亿", v)
            or string.format("%.1f万亿", v)
        return (s:gsub("%.0万亿", "万亿"))
    elseif n >= 1e8 then
        local v = n / 1e8
        local s = v >= 100 and string.format("%.0f亿", v)
            or string.format("%.1f亿", v)
        return (s:gsub("%.0亿", "亿"))
    elseif n >= 1e4 then
        local v = n / 1e4
        local s = v >= 100 and string.format("%.0f万", v)
            or string.format("%.1f万", v)
        return (s:gsub("%.0万", "万"))
    end
    return tostring(n)
end

--- 统一伤害飘字（暴击/普通自动格式化）
---@param target table   被击中的敌人
---@param finalDmg number 最终伤害值
---@param isCrit boolean  是否暴击
---@param elemColor table 普通伤害颜色（元素着色后）
local function ShowDamageText(target, finalDmg, isCrit, elemColor)
    local text = FormatDamage(finalDmg)
    local size = target.typeDef.size or 8
    -- 随机抛物线初速度
    local vx = (math.random() - 0.5) * 80          -- 水平随机 ±40
    local vy = -(55 + math.random() * 35)           -- 向上 55~90
    if isCrit then
        vy = -(80 + math.random() * 40)             -- 暴击弹得更高
        AddFloatingText({
            text = text .. "!",
            x = target.x + (math.random() - 0.5) * 12,
            y = target.y - size - 10,
            vx = vx, vy = vy,
            life = 0.9,
            maxLife = 0.9,
            color = COLOR_CRIT,
            fontSize = 16,
            isCrit = true,
        })
    else
        AddFloatingText({
            text = text,
            x = target.x + (math.random() - 0.5) * 14,
            y = target.y - size - 6,
            vx = vx, vy = vy,
            life = 0.7,
            color = elemColor,
            fontSize = 11,
        })
    end
end

-- 复用乘区表（避免每次 CalcFinalDamage 创建新 table）
local _zones = {}

--- 计算最终伤害（护甲系数 × 暴击倍率）
--- 集成破甲叠加、光环暴击加成
---@param tower table
---@param enemy table
---@param damage number
---@return number finalDamage
---@return boolean isCrit
local function CalcFinalDamage(tower, enemy, damage)
    -- 英雄元素（多处乘区共用）
    local heroElement = Config.HERO_ELEMENT[tower.typeDef.id]

    -- 暴击判定（需要返回 isCrit 标记）
    local isCrit = false

    -- ====================================================================
    -- 命名乘区表：每个乘区独立计算，最终统一相乘
    -- 新增乘区只需追加 zones.xxx = value，无需修改最终公式
    -- ====================================================================
    -- 清除上次残留的 key（已知全部 key，直接置 nil）
    local zones = _zones
    zones.def = nil; zones.crit = nil; zones.elemResist = nil
    zones.chill = nil; zones.dmgBonus = nil; zones.elemDmg = nil; zones.vuln = nil

    -- [DEF减伤] ATK / (ATK + effectiveDEF)
    do
        local enemyDEF = enemy.def or 0
        -- 英雄穿甲：按比例削减敌方 DEF（armorPen 0.30 = 削减30% DEF）
        -- 怪物穿甲抗性：降低穿甲有效率（armorPenResist 0.30 = 穿甲效果打7折）
        local armorPen = Tower.GetEffectiveArmorPen(tower)
        local penResist = enemy.armorPenResist or 0
        if penResist > 0 then
            armorPen = armorPen * (1 - penResist)
        end
        if armorPen > 0 then
            enemyDEF = enemyDEF * (1 - armorPen)
        end
        -- 破甲叠层：每层削减固定比例 DEF
        if enemy.armorBreakStacks and enemy.armorBreakStacks > 0 and enemy.armorBreakValue then
            enemyDEF = enemyDEF * (1 - enemy.armorBreakStacks * enemy.armorBreakValue)
        end
        -- 剧毒瘴气：额外削减 DEF
        if enemy.armorReduceFromDot then
            enemyDEF = enemyDEF * (1 - enemy.armorReduceFromDot)
            enemy.armorReduceFromDot = nil  -- 单次使用
        end
        enemyDEF = math.max(0, enemyDEF)
        zones.def = F.Diminishing(enemyDEF, damage)
    end

    -- [暴击] 概率触发，倍率 = baseCritMult + critDmg
    -- 怪物暴击伤害减免：critDmgReduce 削减暴击额外倍率部分
    do
        local critRate = HeroSkills.GetEffectiveCritRate(tower)
        if critRate > 0 and math.random() < critRate then
            isCrit = true
            local critDmg = Tower.GetEffectiveCritDmg(tower)
            -- 英雄模块额外暴击伤害（绯夜绯瞳锁定等）
            if tower.bonusCritDmg and tower.bonusCritDmg > 0 then
                critDmg = critDmg + tower.bonusCritDmg
            end
            local critReduce = enemy.critDmgReduce or 0
            if critReduce > 0 then
                critDmg = critDmg * (1 - critReduce)
            end
            zones.crit = Config.BASE_CRIT_MULT + critDmg
        end
    end

    -- [元素抗性] 1 - resistance（由敌人主题×英雄元素查表）
    do
        local elemMult = 1.0
        if heroElement and enemy.typeDef and enemy.typeDef.themeId then
            local resists = Config.THEME_ELEMENT_RESIST[enemy.typeDef.themeId]
            if resists and resists[heroElement] then
                elemMult = 1.0 - resists[heroElement]
            end
        end
        zones.elemResist = elemMult
    end

    -- [寒意增伤] 5层寒意时受到的伤害增加
    if enemy.chillStacks and enemy.chillStacks >= 5 then
        zones.chill = 1.0 + (tower.typeDef.chillDmgAmpAtMax or 0.50)
    end

    -- [伤害加成] 通用独立乘区 (1 + dmgBonus)
    -- 怪物伤害加成减免：dmgBonusReduce 削减英雄 dmgBonus
    do
        local dmgBonus = Tower.GetEffectiveDmgBonus(tower)
        local dmgReduce = enemy.dmgBonusReduce or 0
        if dmgReduce > 0 then
            dmgBonus = dmgBonus * (1 - dmgReduce)
        end
        if dmgBonus > 0 then
            zones.dmgBonus = 1.0 + dmgBonus
        end
    end

    -- [元素伤害] 匹配英雄元素时的专属乘区
    -- 怪物元素伤害减免：elemDmgReduce 削减英雄 elemDmg
    do
        local elemDmg = 0
        if heroElement and tower.elemDmgBonus then
            elemDmg = tower.elemDmgBonus[heroElement] or 0
        end
        -- 符文词条：元素精通追加到同一乘区
        if heroElement and tower.runeBonus and tower.runeBonus.elemMastery and tower.runeBonus.elemMastery > 0 then
            elemDmg = elemDmg + tower.runeBonus.elemMastery
        end
        local elemReduce = enemy.elemDmgReduce or 0
        if elemReduce > 0 then
            elemDmg = elemDmg * (1 - elemReduce)
        end
        if elemDmg > 0 then
            zones.elemDmg = 1.0 + elemDmg
        end
    end

    -- [易伤标记] 符文词条独立乘区
    if tower.runeBonus and tower.runeBonus.vulnMark and tower.runeBonus.vulnMark > 0 then
        zones.vuln = 1.0 + tower.runeBonus.vulnMark
    end

    -- ====================================================================
    -- 统一相乘：遍历所有乘区
    -- ====================================================================
    local final = damage
    for _, mult in pairs(zones) do
        final = final * mult
    end

    return final, isCrit, heroElement, zones.elemResist
end
Combat.CalcFinalDamage = CalcFinalDamage

--- 计算两点距离
local function Distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

--- 从空间网格中查找指定范围内最近的敌人（O(K)，K 为邻近格内敌人数）
---@param px number 查询中心 X
---@param py number 查询中心 Y
---@param rangeSq number 范围的平方
---@param range number 范围（用于计算搜索半径）
---@param hitSet table|nil 排除集合（链弹用，key=敌人ID）
---@return table|nil bestEnemy
---@return number bestDistSq
local function SpatialQuery(px, py, rangeSq, range, hitSet)
    local cx = math.floor(px / SPATIAL_CELL)
    local cy = math.floor(py / SPATIAL_CELL)
    local r = math.ceil(range / SPATIAL_CELL)
    local bestDistSq = rangeSq
    local bestEnemy = nil
    for dx = -r, r do
        for dy = -r, r do
            local key = (cx + dx) * 10000 + (cy + dy)
            local cell = _spatialGrid[key]
            if cell then
                for _, e in ipairs(cell) do
                    if not hitSet or not hitSet[e.id] then
                        local ddx = e.x - px
                        local ddy = e.y - py
                        local d2 = ddx * ddx + ddy * ddy
                        if d2 < bestDistSq then
                            bestDistSq = d2
                            bestEnemy = e
                        end
                    end
                end
            end
        end
    end
    return bestEnemy, bestDistSq
end

--- 寻找塔攻击范围内最近的敌人（空间网格加速）
--- 嘲讽激活时：优先攻击范围内的憎恨之躯 BOSS
local function FindTarget(tower, towerX, towerY)
    local effectiveRange = HeroSkills.ModifyRange(tower, tower.range)
    local rangeSq = effectiveRange * effectiveRange

    -- 嘲讽激活时，优先攻击范围内的 BOSS
    if HatredBossSkills.IsTauntActive() then
        for _, e in ipairs(State.enemies) do
            if e.alive and e.isHatredBoss then
                local dx = e.x - towerX
                local dy = e.y - towerY
                if dx * dx + dy * dy <= rangeSq then
                    return e
                end
                break
            end
        end
    end

    return SpatialQuery(towerX, towerY, rangeSq, effectiveRange, nil)
end

--- 寻找链式攻击的下一个目标（空间网格加速）
---@param source table  当前被击中的敌人
---@param hitSet table  已被击中的敌人id集合
---@param range number  链式搜索范围
---@return table|nil
local function FindChainTarget(source, hitSet, range)
    return SpatialQuery(source.x, source.y, range * range, range, hitSet)
end

--- 塔发起攻击
local function TowerAttack(tower, towerX, towerY, target)
    -- 应用攻速加成
    local baseSpeed = Tower.GetEffectiveSpeed(tower)  -- debuff 修正后的攻速
    local effectiveSpeed = HeroSkills.ModifyAttackSpeed(tower, baseSpeed)
    tower.cooldown = effectiveSpeed
    tower.target = target

    -- 获取有效攻击力（含光环buff + debuff）
    local effectiveAtk = HeroSkills.GetEffectiveAttack(tower)

    -- 攻击动画（有精灵图的角色都播放）
    tower.attackAnimTimer = 0.3
    HeroAnim.OnAttack(tower)   -- 压缩弹出动画

    -- 播放攻击音效（节流）
    if State.time - lastAttackSfxTime >= SFX_ATTACK_INTERVAL then
        AudioManager.PlayAttack()
        lastAttackSfxTime = State.time
    end

    -- 创建弹道
    State.projectiles[#State.projectiles + 1] = {
        x = towerX,
        y = towerY,
        targetId = target.id,
        tx = target.x,
        ty = target.y,
        speed = 300,
        damage = effectiveAtk,
        tower = tower,
        life = 2.0,
        color = tower.typeDef.color,
        spriteSheet = tower.typeDef.icon or nil,
    }

    -- 连射技能: 概率额外发射
    if HeroSkills.ShouldMultiShot(tower) then
        State.projectiles[#State.projectiles + 1] = {
            x = towerX + 3,
            y = towerY + 3,
            targetId = target.id,
            tx = target.x,
            ty = target.y,
            speed = 280,
            damage = effectiveAtk,
            tower = tower,
            life = 2.0,
            color = tower.typeDef.color,
        }
    end
end

--- 憎恨之躯 BOSS 受击钩子（嘲讽叠层 + 韧性条伤害）
local function CheckHatredBossHit(tower, target, damage)
    if not target.isHatredBoss then return end
    if not HatredBossSkills.IsActive() then return end
    -- 嘲讽回调：叠加攻速减益
    if HatredBossSkills.IsTauntActive() then
        HatredBossSkills.OnTowerHitBoss(tower)
    end
    -- 韧性条命中（每次攻击计 1 次，与伤害数值无关）
    if HatredBossSkills.GetStarCrushState() then
        HatredBossSkills.DamageToughness()
    end
    if HatredBossSkills.GetDestructionState() then
        HatredBossSkills.DamageDestructionToughness()
    end
end

--- 处理链式攻击命中
---@param tower table
---@param firstTarget table
---@param damage number
local function HandleChainAttack(tower, firstTarget, damage)
    local typeDef = tower.typeDef
    local chainCount = typeDef.chainCount or 3
    local chainDecay = typeDef.chainDecay or 0.7

    local hitSet = { [firstTarget.id] = true }
    local currentTarget = firstTarget
    local currentDmg = damage

    for c = 2, chainCount do
        currentDmg = currentDmg * chainDecay
        local nextTarget = FindChainTarget(currentTarget, hitSet, 80)
        if not nextTarget then break end

        hitSet[nextTarget.id] = true
        local modDmg = HeroSkills.ModifyDamage(tower, nextTarget, currentDmg)
        local finalDmg, isCrit, heroElem, elemMult = CalcFinalDamage(tower, nextTarget, modDmg)
        local killed = Enemy.TakeDamage(nextTarget, finalDmg)
        DamageStats.Record(tower, finalDmg, isCrit, killed, nextTarget.isBoss)

        -- 伤害飘字
        local elemColor = GetElementDmgColor(heroElem, elemMult, tower.typeDef.color)
        ShowDamageText(nextTarget, finalDmg, isCrit, elemColor)
        if isCrit then HeroSkills.CheckCritSplash(tower, nextTarget, finalDmg) end

        HeroSkills.OnHit(tower, nextTarget, killed)
        CheckHatredBossHit(tower, nextTarget, finalDmg)

        -- 链式特殊效果
        if typeDef.special == "slow" and nextTarget.alive then
            local slowRate = typeDef.slowRate or 0.25
            slowRate = HeroSkills.ModifySlowRate(tower, slowRate, nextTarget)
            Enemy.ApplySlow(nextTarget, 2.0, slowRate)
        end

        -- 链闪电粒子
        AddParticle({
            x = (currentTarget.x + nextTarget.x) / 2,
            y = (currentTarget.y + nextTarget.y) / 2,
            vx = 0, vy = -20,
            life = 0.3, maxLife = 0.3,
            color = tower.typeDef.color,
            size = 3,
        })

        currentTarget = nextTarget
    end
end

--- 弹道命中处理
local function OnProjectileHit(proj)
    local tower = proj.tower
    local typeDef = tower.typeDef

    -- 查找目标（复用 Combat.Update 中构建的 _enemyById 哈希表，O(1)）
    local target = _enemyById[proj.targetId]

    if not target then return end

    -- 播放命中音效（节流）
    if State.time - lastHitSfxTime >= SFX_HIT_INTERVAL then
        AudioManager.PlayEnemyHit()
        lastHitSfxTime = State.time
    end

    -- === 链式攻击 ===
    if typeDef.attackType == "chain" then
        local damage = HeroSkills.ModifyDamage(tower, target, proj.damage)
        local finalDmg, isCrit, heroElem, elemMult = CalcFinalDamage(tower, target, damage)
        local killed = Enemy.TakeDamage(target, finalDmg)
        DamageStats.Record(tower, finalDmg, isCrit, killed, target.isBoss)

        local elemColor = GetElementDmgColor(heroElem, elemMult, proj.color)
        ShowDamageText(target, finalDmg, isCrit, elemColor)
        if isCrit then HeroSkills.CheckCritSplash(tower, target, finalDmg) end
        HeroSkills.OnHit(tower, target, killed)
        CheckHatredBossHit(tower, target, finalDmg)

        -- 链式弹跳
        HandleChainAttack(tower, target, proj.damage)

    elseif typeDef.attackType == "aoe" then
        -- === AOE 伤害 ===
        for _, e in ipairs(State.enemies) do
            if e.alive then
                local dx = proj.tx - e.x
                local dy = proj.ty - e.y
                local distSq = dx * dx + dy * dy
                if distSq < 2500 then -- 50²
                    local dist = math.sqrt(distSq)
                    local dmgMult = 1.0 - (dist / 50) * 0.5
                    local damage = HeroSkills.ModifyDamage(tower, e, proj.damage * dmgMult)
                    local finalDmg, isCrit, heroElem, elemMult = CalcFinalDamage(tower, e, damage)
                    local killed = Enemy.TakeDamage(e, finalDmg)
                    DamageStats.Record(tower, finalDmg, isCrit, killed, e.isBoss)

                    local elemColor = GetElementDmgColor(heroElem, elemMult, proj.color)
                    ShowDamageText(e, finalDmg, isCrit, elemColor)
                    if isCrit then HeroSkills.CheckCritSplash(tower, e, finalDmg) end
                    HeroSkills.OnHit(tower, e, killed)
                    CheckHatredBossHit(tower, e, finalDmg)
                end
            end
        end
    else
        -- === 单体伤害 ===
        local damage = HeroSkills.ModifyDamage(tower, target, proj.damage)
        local finalDmg, isCrit, heroElem, elemMult = CalcFinalDamage(tower, target, damage)
        local killed = Enemy.TakeDamage(target, finalDmg)
        DamageStats.Record(tower, finalDmg, isCrit, killed, target.isBoss)

        local elemColor = GetElementDmgColor(heroElem, elemMult, proj.color)
        ShowDamageText(target, finalDmg, isCrit, elemColor)
        if isCrit then HeroSkills.CheckCritSplash(tower, target, finalDmg) end
        HeroSkills.OnHit(tower, target, killed)
        CheckHatredBossHit(tower, target, finalDmg)
    end

    -- === 特殊效果 ===
    if typeDef.special == "slow" and target.alive then
        local slowRate = typeDef.slowRate or 0.3
        slowRate = HeroSkills.ModifySlowRate(tower, slowRate, target)
        local slowDur = 2.0
        if target.isBoss then
            -- BOSS减速效率已在ModifySlowRate处理
        end
        Enemy.ApplySlow(target, slowDur, slowRate)
        -- 灵魂锁链扩散
        HeroSkills.HandleSlowSpread(tower, target, slowDur, slowRate)
    elseif typeDef.special == "dot" and target.alive then
        local dotDmg = typeDef.dotDamage or 5
        dotDmg = HeroSkills.ModifyDotDamage(tower, dotDmg, target)
        Enemy.ApplyDOT(target, dotDmg, typeDef.dotDuration or 2.0)
    elseif typeDef.special == "amp_damage" and target.alive then
        -- 增伤标记（首次施加时飘字）
        local isFirst = not Debuff.Has(target, "amp_damage")
        Debuff.Apply(target, "amp_damage", {
            value    = typeDef.ampRate or 0.08,
            duration = typeDef.ampDuration or 3.0,
        })
        if isFirst then
            AddFloatingText({
                text = "易伤",
                x = target.x + (math.random() - 0.5) * 10,
                y = target.y - (target.typeDef.size or 8) - 16,
                life = 0.5,
                color = COLOR_AMP_MARK,
                fontSize = 11,
            })
        end
    elseif typeDef.special == "armor_break" and target.alive then
        -- 破甲（首次施加或叠层时飘字）
        local oldStacks = target.armorBreakStacks or 0
        target.armorBreakStacks = math.min(oldStacks + 1, 3)
        target.armorBreakValue = typeDef.armorBreak or 0.08
        target.armorBreakTimer = typeDef.armorBreakDuration or 5.0
        if oldStacks == 0 then
            AddFloatingText({
                text = "破甲",
                x = target.x + (math.random() - 0.5) * 10,
                y = target.y - (target.typeDef.size or 8) - 16,
                life = 0.5,
                color = COLOR_ARMOR_BREAK,
                fontSize = 11,
            })
        end
    elseif typeDef.special == "aoe_control" and target.alive then
        -- AOE控制（眩晕）
        if typeDef.stunChance and math.random() < typeDef.stunChance then
            HeroSkills.ApplyStun(target, typeDef.stunDuration or 1.0)
        end
        if typeDef.slowRate then
            local slowRate = typeDef.slowRate
            slowRate = HeroSkills.ModifySlowRate(tower, slowRate, target)
            Enemy.ApplySlow(target, 2.0, slowRate)
        end
    elseif typeDef.special == "boss_killer" and target.alive then
        -- BOSS额外伤害已在 ModifyDamage 中通过 hunt_instinct / void_tear 处理
    elseif typeDef.special == "chill" and target.alive then
        -- 寒意机制: AOE命中时对范围内敌人施加寒意（通过 OnHit 中的 frost_strike 处理）
        -- 此处不需要额外逻辑，因为 frost_strike 已在 OnHit 中处理
        -- 但 AOE 分支中每个命中的敌人都会触发 OnHit，所以自然生效
    end

    -- scorch 被动：灼烧攻击者，降低攻速
    if target.alive and target.typeDef.specialPassive == "scorch" then
        local reduce = target.typeDef.scorchAtkSpdReduce or 0.10
        local dur = target.typeDef.scorchDuration or 3.0
        tower.scorchTimer = math.max(tower.scorchTimer or 0, dur)
        tower.scorchReduction = reduce
    end

    -- 命中粒子
    for i = 1, 4 do
        local angle = math.random() * math.pi * 2
        local spd = 20 + math.random() * 30
        AddParticle({
            x = proj.tx,
            y = proj.ty,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            life = 0.3 + math.random() * 0.3,
            maxLife = 0.6,
            color = proj.color,
            size = 2 + math.random() * 2,
        })
    end
end

--- 重置音效节流计时器（过关/重开时调用）
function Combat.Reset()
    lastAttackSfxTime = 0
    lastHitSfxTime = 0
end

--- 更新战斗系统
function Combat.Update(dt, gridOffsetX, gridOffsetY)
    local Grid = require("Game.Grid")

    -- 更新光环系统
    HeroSkills.UpdateAuras(State.towers, gridOffsetX, gridOffsetY)

    -- 更新全局buff
    HeroSkills.UpdateGlobalBuffs(dt)

    -- 更新诅咒标记DOT
    HeroSkills.UpdateCurseDOT(dt)

    -- 英雄专属帧更新（凛冬君王寒意 + 翎嫣自然光环等，统一调度）
    -- 必须在 UpdateAuras 之后调用（自然光环叠加渐近线buff）
    HeroSkills.UpdateFrame(State.towers, dt, gridOffsetX, gridOffsetY)

    -- 符文套装: 铁壁 set3 — 致命伤害免疫（冷却计时器递减）
    for _, tower in ipairs(State.towers) do
        if tower.runeSetEffects then
            for _, eff in ipairs(tower.runeSetEffects) do
                if eff.effect == "fatal_immune" then
                    -- 递减冷却计时器
                    if tower._fatalImmuneCooldown and tower._fatalImmuneCooldown > 0 then
                        tower._fatalImmuneCooldown = tower._fatalImmuneCooldown - dt
                    end
                    break
                end
            end
        end
    end

    -- 重建空间网格哈希（O(E) 一次，FindTarget / FindChainTarget 复用）
    RebuildSpatialGrid()

    -- 更新塔攻击 + 朝向
    for _, tower in ipairs(State.towers) do
        local tx, ty = Grid.CellToScreen(tower.col, tower.row, gridOffsetX, gridOffsetY)
        local target = FindTarget(tower, tx, ty)

        -- 更新朝向
        if target then
            tower.faceLeft = target.x < tx
        end

        -- 沉默期间无法攻击（death_silence / disable 施加）
        local silenced = tower.silenceTimer and tower.silenceTimer > 0
        if tower.cooldown <= 0 and target and not tower.shackled and not silenced then
            TowerAttack(tower, tx, ty, target)
        end
    end

    -- 构建敌人 ID 查找表（O(e) 一次，OnProjectileHit 复用，避免每弹道 O(e) 线性扫描）
    -- 先清除旧数据
    for k in pairs(_enemyById) do _enemyById[k] = nil end
    for _, e in ipairs(State.enemies) do
        if e.alive then _enemyById[e.id] = e end
    end
    local enemyById = _enemyById

    -- 更新弹道（swap-and-pop 避免 O(n) 的 table.remove）
    do
        local projs = State.projectiles
        local n = #projs
        local i = 1
        while i <= n do
            local p = projs[i]
            p.life = p.life - dt
            local remove = false

            if not p.isEnemyProjectile then
                local target = enemyById[p.targetId]

                if target then
                    p.tx = target.x
                    p.ty = target.y
                end

                local dx = p.tx - p.x
                local dy = p.ty - p.y
                local distSq = dx * dx + dy * dy

                if distSq < 64 or p.life <= 0 then  -- 64 = 8²
                    -- pcall 保护：OnProjectileHit 报错时仍移除弹道，
                    -- 防止卡死弹道导致 Combat.Update 每帧崩溃（飘字/掉落物/攻击全部停止）
                    local ok, err = pcall(OnProjectileHit, p)
                    if not ok then
                        print("[Combat] ERROR in OnProjectileHit: " .. tostring(err))
                    end
                    remove = true
                else
                    local dist = math.sqrt(distSq)
                    -- 动态追踪：弹体速度至少比目标快 150 px/s，防止高速怪永远追不上
                    local effSpeed = p.speed
                    local tgt = enemyById[p.targetId]
                    if tgt and tgt.speed then
                        effSpeed = math.max(effSpeed, tgt.speed + 150)
                    end
                    local move = effSpeed * dt
                    p.x = p.x + dx / dist * move
                    p.y = p.y + dy / dist * move
                end
            end

            if remove then
                projs[i] = projs[n]
                projs[n] = nil
                n = n - 1
            else
                i = i + 1
            end
        end
    end

    -- 更新粒子（swap-and-pop）
    do
        local parts = State.particles
        local n = #parts
        local i = 1
        while i <= n do
            local pt = parts[i]
            pt.life = pt.life - dt
            pt.x = pt.x + pt.vx * dt
            pt.y = pt.y + pt.vy * dt
            pt.vy = pt.vy + 40 * dt
            if pt.life <= 0 then
                parts[i] = parts[n]
                parts[n] = nil
                n = n - 1
            else
                i = i + 1
            end
        end
    end

    -- 更新飘字（swap-and-pop）
    do
        local GRAVITY = 140  -- 抛物线重力加速度 (px/s²)
        local fts = State.floatingTexts
        local n = #fts
        local i = 1
        while i <= n do
            local ft = fts[i]
            ft.life = ft.life - dt
            if ft.vx then
                -- 抛物线运动（伤害飘字）
                ft.x = ft.x + ft.vx * dt
                ft.y = ft.y + ft.vy * dt
                ft.vy = ft.vy + GRAVITY * dt
            else
                -- 直线上飘（状态飘字：减速/破甲/闪避等）
                ft.y = ft.y - 30 * dt
            end
            if ft.life <= 0 then
                fts[i] = fts[n]
                fts[n] = nil
                n = n - 1
            else
                i = i + 1
            end
        end
    end

    -- 更新掉落物（飞行动画 + 到达后加货币）
    LootDrop.Update(dt)

    -- 更新技能闪光
    if State.skillFlash then
        State.skillFlash.timer = State.skillFlash.timer - dt
        if State.skillFlash.timer <= 0 then
            State.skillFlash = nil
        end
    end

    -- 更新敌人buff计时器
    for _, e in ipairs(State.enemies) do
        -- 增伤标记衰减
        if e.ampDamageTimer and e.ampDamageTimer > 0 then
            e.ampDamageTimer = e.ampDamageTimer - dt
            if e.ampDamageTimer <= 0 then
                Debuff.Clear(e, "amp_damage")
            end
        end
        -- 破甲叠层衰减
        if e.armorBreakTimer and e.armorBreakTimer > 0 then
            e.armorBreakTimer = e.armorBreakTimer - dt
            if e.armorBreakTimer <= 0 then
                e.armorBreakStacks = nil
                e.armorBreakValue = nil
                e.armorBreakTimer = nil
            end
        end
        -- 眩晕衰减
        if e.stunTimer and e.stunTimer > 0 then
            e.stunTimer = e.stunTimer - dt
        end
        -- 冰冻衰减
        if e.frozenTimer and e.frozenTimer > 0 then
            e.frozenTimer = e.frozenTimer - dt
            if e.frozenTimer <= 0 then
                Debuff.Clear(e, "frozen")
            end
        end
    end
end

return Combat
