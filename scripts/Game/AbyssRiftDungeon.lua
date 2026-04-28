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
local DungeonScaling = require("Game.DungeonScaling")
local WaveGen = require("Game.WaveGenerator")

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

--- 消耗一次进入次数（仅免费次数）
---@return boolean success, string msg
function Abyss.ConsumeEntry()
    local free, _ = RuneData.GetAbyssRiftRemaining()
    if free > 0 then
        RuneData.UseAbyssRiftEntry(false)
        return true, ""
    else
        return false, "no_free"
    end
end

--- 看广告领取深渊裂隙挑战券
---@return boolean
function Abyss.ConsumeAdForTicket()
    local ok = RuneData.ConsumeAdForTicket()
    if ok then
        Toast.Show("获得 深渊裂隙挑战券 ×1", { 80, 220, 120 })
    else
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
    end
    return ok
end

--- 获取背包中挑战券数量
---@return number
function Abyss.GetTicketCount()
    return RuneData.GetAbyssTicketCount()
end

--- 消耗一张挑战券进入
---@return boolean
function Abyss.ConsumeTicket()
    if not RuneData.ConsumeAbyssTicket() then
        Toast.Show("挑战券不足", { 255, 200, 80 })
        return false
    end
    return true
end

--- 获取今日广告领券剩余次数
---@return number
function Abyss.GetAdRemaining()
    local _, ad = RuneData.GetAbyssRiftRemaining()
    return ad
end

--- 获取最佳通关波次（扫荡用）
---@return number
function Abyss.GetBestWave()
    local d = RuneData.GetAbyssRiftProgress()
    return d and d.bestWave or 0
end

--- 获取上次挑战难度（扫荡用）
---@return string
function Abyss.GetLastDifficultyId()
    local d = RuneData.GetAbyssRiftProgress()
    return d and d.lastDifficultyId or ""
end

--- 记录最佳通关波次和难度（EndSession 时调用）
---@param clearedWave number
---@param difficultyId string
function Abyss.RecordBestResult(clearedWave, difficultyId)
    local d = RuneData.GetAbyssRiftProgress()
    if d then
        if clearedWave > (d.bestWave or 0) then
            d.bestWave = clearedWave
        end
        d.lastDifficultyId = difficultyId
    end
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
    local base  = RuneConfig.ABYSS_RIFT.baseStage   -- 500
    local final = RuneConfig.ABYSS_RIFT.finalStage   -- 6000

    -- 指数增长：ratio=12，wave1=500, wave8≈1732, wave15=6000 (× 难度系数)
    local t = (wave - 1) / (TOTAL_WAVES - 1)         -- 0 ~ 1
    local stageEquiv = base * (final / base) ^ t * diff.levelMult

    return math.max(1, math.floor(stageEquiv))
end

-- HP/Speed 缩放统一使用 DungeonScaling 模块
Abyss.CalcHPScale    = DungeonScaling.CalcHPScale
Abyss.CalcSpeedScale = DungeonScaling.CalcSpeedScale

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

--- 获取波次类型
---@param wave number 1-15
---@return string "normal"/"elite3"/"elite7"/"elite10"/"elite13"/"boss"
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
    elseif wtype == "elite13" then
        return "精英++", { 255, 100, 40 }
    elseif wtype == "elite10" then
        return "精英+", { 255, 180, 40 }
    elseif wtype == "elite7" then
        return "精英", { 200, 160, 60 }
    elseif wtype == "elite3" then
        return "精英", { 200, 200, 80 }
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

    local tags = { isAbyssRift = true }
    local normalCount = (waveType == "boss") and (ENEMIES_PER_WAVE - 1) or ENEMIES_PER_WAVE

    -- 生成普通怪
    local enemies = WaveGen.GenerateBatch(stageNum, normalCount, hpScale, spdScale, tags)

    -- BOSS 波：追加 BOSS
    if waveType == "boss" then
        local bossDef = WaveGen.CreateBoss(stageNum, hpScale, spdScale, BOSS_HP_MULT, 0.6, tags)
        if bossDef then
            enemies[#enemies + 1] = bossDef
        end
    end

    -- 精英波：根据阶段强化不同数量和强度的精英怪
    if waveType == "elite3" then
        WaveGen.MarkElitesTail(enemies, 2, 2.0, 0.85)     -- 2个精英，HP×2.0，速度×0.85
    elseif waveType == "elite7" then
        WaveGen.MarkElitesTail(enemies, 2, 2.5, 0.80)     -- 2个精英，HP×2.5，速度×0.80
    elseif waveType == "elite10" then
        WaveGen.MarkElitesTail(enemies, 3, 3.0, 0.75)     -- 3个精英，HP×3.0，速度×0.75
    elseif waveType == "elite13" then
        WaveGen.MarkElitesTail(enemies, 4, 3.5, 0.70)     -- 4个精英，HP×3.5，速度×0.70
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

    -- 符文掉落（dropChanceMult 按难度提升爆率）
    local chanceMult = diff.dropChanceMult or 1.0
    local runeChance = math.min((dropDef.runeChance or 0) * chanceMult, 1.0)
    if runeChance > 0 and math.random() < runeChance then
        local rune = RuneData.Generate(diff.qualityMult)
        drops.runes[#drops.runes + 1] = rune
    end

    -- 符文封印掉落
    local sealChance = math.min((dropDef.sealChance or 0) * chanceMult, 1.0)
    if sealChance > 0 and math.random() < sealChance then
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
    local chanceMult = diff.dropChanceMult or 1.0
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

            -- 符文概率（×难度爆率系数）
            local rc = math.min((dropDef.runeChance or 0) * chanceMult, 1.0)
            avgRunes = avgRunes + rc

            -- 封印概率（×难度爆率系数）
            if dropDef.sealChance then
                local sc = math.min(dropDef.sealChance * chanceMult, 1.0)
                local avgSealCount = ((dropDef.sealMin or 1) + (dropDef.sealMax or 1)) / 2
                avgSeals = avgSeals + sc * avgSealCount
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
        Currency.GrantReward({ type = "currency", id = "rift_dust", amount = totalDust }, "AbyssRift")
    end

    -- 发放符文封印
    if totalSeals > 0 then
        Currency.GrantReward({ type = "currency", id = "rune_seal", amount = totalSeals }, "AbyssRift")
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

    -- 记录最佳波次和难度（扫荡用）
    Abyss.RecordBestResult(clearedWave, difficultyId)

    -- 保存
    HeroData.Save(true)  -- 立即云端保存

    -- 构建 rewardDefs 供 RewardController 统一展示
    local rewardDefs = {}
    if totalDust > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "rift_dust", amount = totalDust }
    end
    if totalSeals > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "rune_seal", amount = totalSeals }
    end
    local runeCounts, runeOrder = {}, {}
    for _, rune in ipairs(addedRunes) do
        local sid = rune.seriesId
        if not runeCounts[sid] then runeCounts[sid] = 0; runeOrder[#runeOrder + 1] = sid end
        runeCounts[sid] = runeCounts[sid] + 1
    end
    for _, sid in ipairs(runeOrder) do
        rewardDefs[#rewardDefs + 1] = { type = "rune", id = sid, amount = runeCounts[sid] }
    end

    local result = {
        totalDust = totalDust,
        totalSeals = totalSeals,
        runes = addedRunes,
        overflowRunes = overflowRunes,
        waveDrops = waveDrops,
        clearedWave = clearedWave,
        difficultyId = difficultyId,
        rewardDefs = rewardDefs,
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
        normal    = "入门难度，保底符文，适合日常刷取",
        hard      = "怪物等级×5，符文品质提升，材料更丰厚",
        nightmare = "怪物×20倍等级，高品质符文频出，终极试炼",
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

--- 结束副本（正常通关或中途退出），发放 session 中已记录的累计奖励
--- 不再重新 roll，直接使用 CompleteWave 已确定的掉落结果
---@param session table
---@return table result
function Abyss.EndSession(session)
    -- 发放裂隙之尘
    if session.totalDust > 0 then
        Currency.GrantReward({ type = "currency", id = "rift_dust", amount = session.totalDust }, "AbyssRiftSession")
    end

    -- 发放符文封印
    if session.totalSeals > 0 then
        Currency.GrantReward({ type = "currency", id = "rune_seal", amount = session.totalSeals }, "AbyssRiftSession")
    end

    -- 发放符文到背包
    local addedRunes = {}
    local overflowRunes = {}
    for _, rune in ipairs(session.runes) do
        local ok, msg = RuneData.AddToBag(rune)
        if ok then
            addedRunes[#addedRunes + 1] = rune
        else
            overflowRunes[#overflowRunes + 1] = rune
        end
    end

    -- 记录最佳波次和难度（扫荡用）
    Abyss.RecordBestResult(session.currentWave, session.difficultyId)

    -- 保存
    HeroData.Save(true)

    -- 构建 rewardDefs 供 RewardController 统一展示
    local rewardDefs = {}
    if session.totalDust > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "rift_dust", amount = session.totalDust }
    end
    if session.totalSeals > 0 then
        rewardDefs[#rewardDefs + 1] = { type = "currency", id = "rune_seal", amount = session.totalSeals }
    end
    local runeCounts2, runeOrder2 = {}, {}
    for _, rune in ipairs(addedRunes) do
        local sid = rune.seriesId
        if not runeCounts2[sid] then runeCounts2[sid] = 0; runeOrder2[#runeOrder2 + 1] = sid end
        runeCounts2[sid] = runeCounts2[sid] + 1
    end
    for _, sid in ipairs(runeOrder2) do
        rewardDefs[#rewardDefs + 1] = { type = "rune", id = sid, amount = runeCounts2[sid] }
    end

    local result = {
        totalDust = session.totalDust,
        totalSeals = session.totalSeals,
        runes = addedRunes,
        overflowRunes = overflowRunes,
        waveDrops = session.waveDrops,
        clearedWave = session.currentWave,
        difficultyId = session.difficultyId,
        rewardDefs = rewardDefs,
    }

    print(string.format("[AbyssRift] EndSession wave %d/%d (diff=%s) dust=%d seals=%d runes=%d overflow=%d",
        session.currentWave, TOTAL_WAVES, session.difficultyId,
        session.totalDust, session.totalSeals, #addedRunes, #overflowRunes))

    return result
end

-- ============================================================================
-- 数据常量导出
-- ============================================================================

Abyss.TOTAL_WAVES = TOTAL_WAVES
Abyss.ENEMIES_PER_WAVE = ENEMIES_PER_WAVE
Abyss.DAILY_FREE = RuneConfig.ABYSS_RIFT.dailyFree
Abyss.DAILY_AD   = RuneConfig.ABYSS_RIFT.dailyAd

-- ============================================================================
-- 战斗配置构建（静态部分，不含 UI 回调）
-- ============================================================================

--- 构建深渊裂隙战斗配置（纯数据，无 UI 依赖）
---@param difficultyId string 难度 ID
---@return table|nil config 静态配置
---@return table|nil session 会话对象（供回调中 CompleteWave/EndSession 使用）
function Abyss.BuildBattleConfig(difficultyId)
    local BM = require("Game.BattleManager")
    local session = Abyss.CreateSession(difficultyId)
    if not session then return nil, nil end

    local waves = {}
    for w = 1, TOTAL_WAVES do
        local enemyDefs = Abyss.GenerateWaveEnemies(w, difficultyId)
        waves[w] = BM.BuildSpawnQueue(enemyDefs, 0.5)
    end

    local diffName = Abyss.DIFFICULTY_MAP[difficultyId]
        and Abyss.DIFFICULTY_MAP[difficultyId].name or "普通"
    local label = "深渊裂隙 · " .. diffName

    local config = {
        mode = "abyss_rift",
        waves = waves,
        totalWaves = TOTAL_WAVES,
        label = label,
        waveInterval = 20,
        autoAdvanceWave = true,
        overloadEnabled = true,
        overloadLimit = 60,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,
    }

    return config, session
end

return Abyss
