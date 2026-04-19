-- Game/AbyssRiftDungeon.lua
-- 深渊裂隙副本 — 数据与战斗逻辑
-- 符文专属副本：15波 × 25怪，3种难度，掉落符文/裂隙之尘/符文封印

local Config = require("Game.Config")
local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local State = require("Game.State")
local Toast = require("Game.Toast")

local Abyss = {}

-- ============================================================================
-- 常量
-- ============================================================================

local TOTAL_WAVES      = RuneConfig.ABYSS_RIFT.totalWaves      -- 15
local ENEMIES_PER_WAVE = RuneConfig.ABYSS_RIFT.enemiesPerWave  -- 25
local BOSS_HP_MULT     = 6.0    -- BOSS HP 倍率（比资源副本略高）
local UNLOCK_STAGE     = RuneConfig.ABYSS_RIFT.unlockStage     -- 100

-- ============================================================================
-- 副本定义（供 DungeonUI 使用）
-- ============================================================================

Abyss.DUNGEON_DEF = {
    key         = "abyss_rift",
    name        = "深渊裂隙",
    emoji       = "🌀",
    desc        = "探索深渊裂隙，获取神秘符文",
    accentColor = { 160, 80, 220, 255 },
    cover       = "image/dungeon_abyss_rift.png",
}

-- ============================================================================
-- 难度等级（引用 Config_Runes）
-- ============================================================================

Abyss.DIFFICULTIES = RuneConfig.ABYSS_DIFFICULTY

--- 按 ID 查难度
Abyss.DIFFICULTY_MAP = {}
for _, d in ipairs(Abyss.DIFFICULTIES) do
    Abyss.DIFFICULTY_MAP[d.id] = d
end

-- ============================================================================
-- 解锁检测
-- ============================================================================

--- 检查是否已解锁深渊裂隙
---@return boolean
function Abyss.IsUnlocked()
    local currentStage = State.currentStage or 1
    return currentStage >= UNLOCK_STAGE
end

--- 获取解锁需要的关卡数
---@return number
function Abyss.GetUnlockStage()
    return UNLOCK_STAGE
end

-- ============================================================================
-- 次数管理（委托 RuneData）
-- ============================================================================

--- 获取剩余次数
---@return number freeLeft, number adLeft
function Abyss.GetRemaining()
    return RuneData.GetAbyssRiftRemaining()
end

--- 获取总剩余（免费+广告）
---@return number
function Abyss.GetTotalRemaining()
    local free, ad = RuneData.GetAbyssRiftRemaining()
    return free + ad
end

--- 消耗一次进入次数
---@return boolean success, string msg
function Abyss.ConsumeEntry()
    local free, ad = RuneData.GetAbyssRiftRemaining()
    if free > 0 then
        RuneData.UseAbyssRiftEntry(false)
        return true, ""
    elseif ad > 0 then
        -- 需要看广告，返回提示
        return false, "ad_required"
    else
        Toast.Show("今日挑战次数已用完", { 255, 200, 80 })
        return false, "no_attempts"
    end
end

--- 消耗广告次数（看完广告后调用）
---@return boolean
function Abyss.ConsumeAdEntry()
    return RuneData.UseAbyssRiftEntry(true)
end

-- ============================================================================
-- 难度缩放
-- 深渊裂隙基于玩家当前关卡 × 难度系数，15波内从低到高递增
-- wave 1 ≈ 当前关卡 × levelMult × 0.5
-- wave 15 ≈ 当前关卡 × levelMult × 1.5
-- ============================================================================

--- 将副本波次映射到等效关卡
---@param wave number 1-15
---@param difficultyId string "normal"/"hard"/"nightmare"
---@return number stageEquiv
function Abyss.WaveToStage(wave, difficultyId)
    local diff = Abyss.DIFFICULTY_MAP[difficultyId] or Abyss.DIFFICULTIES[1]
    local base  = RuneConfig.ABYSS_RIFT.baseStage   -- 5
    local final = RuneConfig.ABYSS_RIFT.finalStage   -- 6000

    -- 指数增长：wave1=5, wave8≈173, wave15=6000 (× 难度系数)
    local t = (wave - 1) / (TOTAL_WAVES - 1)         -- 0 ~ 1
    local stageEquiv = base * (final / base) ^ t * diff.levelMult

    return math.max(1, math.floor(stageEquiv))
end

--- 根据等效关卡计算 HP 缩放
---@param stageEquiv number
---@return number
function Abyss.CalcHPScale(stageEquiv)
    return Config.GetStageHPScale(stageEquiv)
end

--- 根据等效关卡计算速度缩放
---@param stageEquiv number
---@return number
function Abyss.CalcSpeedScale(stageEquiv)
    return math.min(1.0 + (stageEquiv - 1) * Config.STAGE_SPEED_PER_STAGE, Config.STAGE_SPEED_CAP)
end

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

--- 获取波次类型
---@param wave number 1-15
---@return string "normal"/"elite5"/"elite10"/"boss"
function Abyss.GetWaveType(wave)
    return RuneConfig.GetWaveDropType(wave)
end

--- 获取波次类型标签
---@param wave number
---@return string label, number[] color
function Abyss.GetWaveLabel(wave)
    local wtype = Abyss.GetWaveType(wave)
    if wtype == "boss" then
        return "BOSS", { 255, 60, 60 }
    elseif wtype == "elite10" then
        return "精英+", { 255, 180, 40 }
    elseif wtype == "elite5" then
        return "精英", { 200, 160, 60 }
    else
        return "普通", { 160, 160, 160 }
    end
end

--- 生成指定波次的敌人列表
---@param wave number 1-15
---@param difficultyId string
---@return table[] enemies
function Abyss.GenerateWaveEnemies(wave, difficultyId)
    local stageEquiv = Abyss.WaveToStage(wave, difficultyId)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = Abyss.CalcHPScale(stageEquiv)
    local spdScale = Abyss.CalcSpeedScale(stageEquiv)
    local waveType = Abyss.GetWaveType(wave)

    -- 获取主题
    local themeIdx = ((stageNum - 1) % Config.THEME_COUNT) + 1
    if themeIdx > Config.THEME_COUNT then themeIdx = Config.THEME_COUNT end

    -- 可用角色池
    local globalWave = stageNum * Config.WAVES_PER_STAGE
    local availRoles = {}
    for _, roleId in ipairs(Config.ROLE_IDS) do
        local role = Config.ENEMY_ROLES[roleId]
        if role then
            local unlockWave = Config.ROLE_UNLOCK_WAVE[role.unlockOrder] or 1
            if globalWave >= unlockWave then
                availRoles[#availRoles + 1] = roleId
            end
        end
    end
    if #availRoles == 0 then
        availRoles = { "minion", "infantry" }
    end

    local enemies = {}
    local normalCount = ENEMIES_PER_WAVE

    if waveType == "boss" then
        normalCount = ENEMIES_PER_WAVE - 1  -- 留一个位置给BOSS
    end

    -- 生成普通怪
    for i = 1, normalCount do
        local roleId = availRoles[((i - 1) % #availRoles) + 1]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale
            def.speed = def.speed * spdScale
            def.isDungeonEnemy = true
            def.isAbyssRift = true
            enemies[#enemies + 1] = def
        end
    end

    -- BOSS 波：追加 BOSS
    if waveType == "boss" then
        local bossDef = Config.BuildBossDef(stageNum)
        if bossDef then
            bossDef.baseHP = bossDef.baseHP * hpScale * BOSS_HP_MULT
            bossDef.speed = bossDef.speed * spdScale * 0.6  -- BOSS 更慢
            bossDef.isDungeonEnemy = true
            bossDef.isDungeonBoss = true
            bossDef.isAbyssRift = true
            enemies[#enemies + 1] = bossDef
        end
    end

    -- 精英波：强化最后2个怪为精英
    if waveType == "elite5" or waveType == "elite10" then
        local eliteCount = (waveType == "elite10") and 3 or 2
        for i = math.max(1, #enemies - eliteCount + 1), #enemies do
            if enemies[i] then
                enemies[i].baseHP = enemies[i].baseHP * 2.5  -- 精英 HP 翻倍
                enemies[i].speed = enemies[i].speed * 0.8    -- 精英略慢
                enemies[i].isElite = true
            end
        end
    end

    return enemies
end

-- ============================================================================
-- 掉落计算
-- ============================================================================

--- 计算单波掉落奖励
---@param wave number 1-15
---@param difficultyId string
---@return table drops { dust=N, runes={...}, seals=N }
function Abyss.CalcWaveDrops(wave, difficultyId)
    local diff = Abyss.DIFFICULTY_MAP[difficultyId] or Abyss.DIFFICULTIES[1]
    local waveType = Abyss.GetWaveType(wave)
    local dropDef = RuneConfig.ABYSS_WAVE_DROPS[waveType]
    if not dropDef then return { dust = 0, runes = {}, seals = 0 } end

    local drops = { dust = 0, runes = {}, seals = 0 }

    -- 裂隙之尘（基础掉落 × 难度系数范围）
    local baseDust = math.random(dropDef.dustMin, dropDef.dustMax)
    -- 难度额外尘：从 dustRange 取
    local extraDust = math.random(diff.dustRange[1], diff.dustRange[2])
    drops.dust = baseDust + extraDust

    -- 符文掉落
    if dropDef.runeChance > 0 and math.random() < dropDef.runeChance then
        local rune = RuneData.Generate(diff.qualityMult)
        drops.runes[#drops.runes + 1] = rune
    end

    -- 符文封印掉落
    if dropDef.sealChance and dropDef.sealChance > 0 and math.random() < dropDef.sealChance then
        local sealCount = math.random(dropDef.sealMin or 1, dropDef.sealMax or 1)
        drops.seals = sealCount
    end

    return drops
end

--- 计算全通关（所有波次）的预期掉落
---@param difficultyId string
---@return table summary { totalDust, avgRunes, avgSeals }
function Abyss.EstimateFullClearDrops(difficultyId)
    local diff = Abyss.DIFFICULTY_MAP[difficultyId] or Abyss.DIFFICULTIES[1]
    local totalDust = 0
    local avgRunes = 0
    local avgSeals = 0

    for w = 1, TOTAL_WAVES do
        local waveType = Abyss.GetWaveType(w)
        local dropDef = RuneConfig.ABYSS_WAVE_DROPS[waveType]
        if dropDef then
            -- 尘：取中间值
            local avgWaveDust = (dropDef.dustMin + dropDef.dustMax) / 2
            local avgDiffDust = (diff.dustRange[1] + diff.dustRange[2]) / 2
            totalDust = totalDust + avgWaveDust + avgDiffDust

            -- 符文概率
            avgRunes = avgRunes + (dropDef.runeChance or 0)

            -- 封印概率
            if dropDef.sealChance then
                local avgSealCount = ((dropDef.sealMin or 1) + (dropDef.sealMax or 1)) / 2
                avgSeals = avgSeals + dropDef.sealChance * avgSealCount
            end
        end
    end

    return {
        totalDust = math.floor(totalDust),
        avgRunes = avgRunes,  -- 期望符文数
        avgSeals = avgSeals,  -- 期望封印数
    }
end

-- ============================================================================
-- 结算
-- ============================================================================

--- 副本结算：发放所有波次的累计掉落
---@param clearedWave number 本次通关到第几波
---@param difficultyId string
---@return table result { totalDust, runes, totalSeals, waveDrops }
function Abyss.ClaimReward(clearedWave, difficultyId)
    local totalDust = 0
    local totalSeals = 0
    local allRunes = {}
    local waveDrops = {}  -- 按波记录（供 UI 展示）

    for w = 1, clearedWave do
        local drops = Abyss.CalcWaveDrops(w, difficultyId)
        totalDust = totalDust + drops.dust
        totalSeals = totalSeals + drops.seals
        for _, rune in ipairs(drops.runes) do
            allRunes[#allRunes + 1] = rune
        end
        waveDrops[w] = drops
    end

    -- 发放裂隙之尘
    if totalDust > 0 then
        Currency.Add("rift_dust", totalDust)
    end

    -- 发放符文封印
    if totalSeals > 0 then
        Currency.Add("rune_seal", totalSeals)
    end

    -- 发放符文到背包
    local addedRunes = {}
    local overflowRunes = {}
    for _, rune in ipairs(allRunes) do
        local ok, msg = RuneData.AddToBag(rune)
        if ok then
            addedRunes[#addedRunes + 1] = rune
        else
            overflowRunes[#overflowRunes + 1] = rune
        end
    end

    -- 保存
    HeroData.Save(true)  -- 立即云端保存

    local result = {
        totalDust = totalDust,
        totalSeals = totalSeals,
        runes = addedRunes,
        overflowRunes = overflowRunes,
        waveDrops = waveDrops,
        clearedWave = clearedWave,
        difficultyId = difficultyId,
    }

    print(string.format("[AbyssRift] cleared wave %d/%d (diff=%s) dust=%d seals=%d runes=%d overflow=%d",
        clearedWave, TOTAL_WAVES, difficultyId,
        totalDust, totalSeals, #addedRunes, #overflowRunes))

    return result
end

-- ============================================================================
-- 难度预览（供 UI 显示）
-- ============================================================================

--- 获取难度推荐描述
---@param difficultyId string
---@return string label, number[] color, string desc
function Abyss.GetDifficultyInfo(difficultyId)
    local diff = Abyss.DIFFICULTY_MAP[difficultyId]
    if not diff then
        return "未知", { 160, 160, 160 }, ""
    end

    local colorMap = {
        normal    = { 120, 200, 120 },
        hard      = { 255, 180, 40 },
        nightmare = { 255, 60, 60 },
    }

    local descMap = {
        normal    = "适合初次挑战，保底获得符文",
        hard      = "稀有符文概率提升，材料更丰厚",
        nightmare = "高品质符文概率翻倍，终极挑战",
    }

    return diff.name, colorMap[difficultyId] or { 160, 160, 160 }, descMap[difficultyId] or ""
end

--- 获取波次难度描述
---@param wave number
---@param difficultyId string
---@return string label, number[] color
function Abyss.GetWaveDifficulty(wave, difficultyId)
    local stageEquiv = Abyss.WaveToStage(wave, difficultyId)
    local lv = math.floor(stageEquiv)

    if wave <= 4 then
        return "Lv." .. lv, { 120, 200, 120 }
    elseif wave <= 9 then
        return "Lv." .. lv, { 200, 200, 100 }
    elseif wave <= 14 then
        return "Lv." .. lv, { 220, 160, 60 }
    else
        return "Lv." .. lv .. "(BOSS)", { 255, 60, 60 }
    end
end

--- 获取波次掉落预览文本
---@param wave number
---@return string
function Abyss.GetWaveDropPreview(wave)
    local waveType = Abyss.GetWaveType(wave)
    local dropDef = RuneConfig.ABYSS_WAVE_DROPS[waveType]
    if not dropDef then return "" end

    local parts = {}
    parts[#parts + 1] = string.format("尘×%d~%d", dropDef.dustMin, dropDef.dustMax)
    if dropDef.runeChance > 0 then
        parts[#parts + 1] = string.format("符文(%d%%)", math.floor(dropDef.runeChance * 100))
    end
    if dropDef.sealChance and dropDef.sealChance > 0 then
        parts[#parts + 1] = string.format("封印(%d%%)", math.floor(dropDef.sealChance * 100))
    end
    return table.concat(parts, " + ")
end

-- ============================================================================
-- 副本状态（供战斗循环使用）
-- ============================================================================

--- 创建一次副本实例（进入副本时调用）
---@param difficultyId string
---@return table|nil session
function Abyss.CreateSession(difficultyId)
    if not Abyss.IsUnlocked() then
        Toast.Show("需要通关第5章解锁", { 255, 200, 80 })
        return nil
    end

    local diff = Abyss.DIFFICULTY_MAP[difficultyId]
    if not diff then
        Toast.Show("未知难度", { 255, 100, 100 })
        return nil
    end

    return {
        difficultyId = difficultyId,
        difficulty = diff,
        currentWave = 0,
        totalWaves = TOTAL_WAVES,
        enemiesPerWave = ENEMIES_PER_WAVE,
        cleared = false,
        waveDrops = {},    -- 每波掉落记录
        totalDust = 0,
        totalSeals = 0,
        runes = {},
    }
end

--- 推进到下一波
---@param session table
---@return table|nil enemies 本波敌人列表，nil表示已全通关
function Abyss.AdvanceWave(session)
    if session.currentWave >= session.totalWaves then
        session.cleared = true
        return nil
    end

    session.currentWave = session.currentWave + 1
    local enemies = Abyss.GenerateWaveEnemies(session.currentWave, session.difficultyId)
    return enemies
end

--- 标记当波完成，计算并记录掉落
---@param session table
---@return table drops 本波掉落
function Abyss.CompleteWave(session)
    local drops = Abyss.CalcWaveDrops(session.currentWave, session.difficultyId)
    session.waveDrops[session.currentWave] = drops
    session.totalDust = session.totalDust + drops.dust
    session.totalSeals = session.totalSeals + drops.seals
    for _, rune in ipairs(drops.runes) do
        session.runes[#session.runes + 1] = rune
    end

    if session.currentWave >= session.totalWaves then
        session.cleared = true
    end

    return drops
end

--- 结束副本（正常通关或中途退出），发放累计奖励
---@param session table
---@return table result
function Abyss.EndSession(session)
    return Abyss.ClaimReward(session.currentWave, session.difficultyId)
end

-- ============================================================================
-- 数据常量导出
-- ============================================================================

Abyss.TOTAL_WAVES = TOTAL_WAVES
Abyss.ENEMIES_PER_WAVE = ENEMIES_PER_WAVE
Abyss.DAILY_FREE = RuneConfig.ABYSS_RIFT.dailyFree
Abyss.DAILY_AD   = RuneConfig.ABYSS_RIFT.dailyAd

return Abyss
