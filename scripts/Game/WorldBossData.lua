-- Game/WorldBossData.lua
-- 世界BOSS数据模块：BOSS不可击杀，20波小怪，按累计伤害发放霜誓契约奖励
-- 全服统一难度，不随主线进度缩放

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")
local SaveRegistry = require("Game.SaveRegistry")
local InventoryData = require("Game.InventoryData")

local WB = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

WB.CONFIG = {
    -- BOSS 属性（全服统一）
    bossHP = math.maxinteger,
    bossDEF = 1000000,          -- 初始DEF（100万）
    bossSpeed = 12,
    bossSize = 28,

    -- 战斗时长
    totalDuration = 60,         -- 60秒总时长
    darkSoulDrain = 50,         -- BOSS每秒掉落暗魂数

    -- ========== 渐进难度（越打越难） ==========
    -- DEF 随时间指数增长: bossDEF × (1 + defGrowthRate)^(elapsed / defGrowthInterval)
    -- 0s=100万, 60s≈320万, 120s≈1000万, 180s≈3200万, 240s≈1亿, 300s≈3.2亿
    defGrowthRate = 0.20,       -- 每个周期增长20%
    defGrowthInterval = 5,      -- 每5秒增长一次

    -- 技能CD衰减: cooldown × max(cdMinMult, 1 - cdDecayRate × elapsed)
    -- 300秒时: shackle 15→7.5s, summon 30→15s, annihilate 45→22.5s
    cdDecayRate = 1/600,        -- 每秒衰减 1/600（300秒时衰减50%）
    cdMinMult = 0.5,            -- CD最低降至原来的50%

    -- 精英HP随时间增强: eliteHP × (1 + eliteHPGrowth × elapsed)
    eliteHPGrowthRate = 0.01,   -- 每秒+1%，300秒时精英HP ×4

    -- 束缚技能
    shackleCooldown = 15,
    shackleFirstCast = 20,
    shackleDuration = 5,
    shackleWeights = { 5, 4, 3, 2, 1 },  -- ★1~★5

    -- 召唤精英技能
    summonCooldown = 30,
    summonFirstCast = 30,
    summonMaxCount = 5,

    -- 销毁技能
    annihilateCooldown = 45,
    annihilateFirstCast = 60,
    annihilateWarning = 3,
    annihilateWeights = { 6, 4, 2, 1, 0.5 },  -- ★1~★5

    -- 奖励档位 { 伤害阈值, 霜誓契约数量 }
    rewardTiers = {
        { 5000000,         1 },  -- 500万
        { 10000000,        1 },  -- 1000万
        { 50000000,        1 },  -- 5000万
        { 250000000,       1 },  -- 2.5亿
        { 500000000,       2 },  -- 5亿
        { 1000000000,      2 },  -- 10亿
        { 2500000000,      2 },  -- 25亿
        { 5000000000,      4 },  -- 50亿
        { 10000000000,     4 },  -- 100亿
        { 25000000000,     4 },  -- 250亿
        { 50000000000,     6 },  -- 500亿
        { 100000000000,    6 },  -- 1000亿
        { 500000000000,    8 },  -- 5000亿
        { 1000000000000,   8 },  -- 1万亿
        { 5000000000000,  10 },  -- 5万亿
        { 10000000000000, 10 },  -- 10万亿
        { 50000000000000, 12 },  -- 50万亿
    },
}

-- ============================================================================
-- 每日次数
-- ============================================================================
WB.DAILY_ATTEMPTS    = 4
WB.FREE_ATTEMPTS     = 1
WB.AD_EXTRA_ATTEMPTS = 3

-- ============================================================================
-- BOSS 定义
-- ============================================================================

--- 创建世界BOSS定义（独立于主题系统的固定BOSS）
---@return table bossDef
function WB.CreateWorldBossDef()
    local cfg = WB.CONFIG
    return {
        id = "world_boss_abyss_lord",
        name = "深渊主宰",
        color = { 180, 30, 50 },
        icon = nil,  -- 使用精灵图渲染，不走单张图片
        spriteSheet = "world_boss",  -- 精灵图名称（在 Renderer_Utils 中注册）
        baseHP = cfg.bossHP,
        baseDEF = cfg.bossDEF,
        speed = cfg.bossSpeed,
        size = cfg.bossSize,
        shape = "diamond",
        reward = 0,
        liveCost = 0,       -- 世界BOSS不占超限名额
        isBoss = true,
        isWorldBoss = true,
        themeId = "void",
        -- BOSS 平衡规则
        passive = nil,       -- 技能由 WorldBossSkills 模块管理
    }
end

-- ============================================================================
-- 渐进难度：动态DEF / CD衰减 / 精英增强
-- ============================================================================

--- 计算当前战斗时间对应的动态DEF
---@param elapsed number 战斗已过秒数
---@return number currentDEF
function WB.GetScaledDEF(elapsed)
    local cfg = WB.CONFIG
    local periods = math.floor(elapsed / cfg.defGrowthInterval)
    return math.floor(cfg.bossDEF * (1 + cfg.defGrowthRate) ^ periods)
end

--- 计算技能CD衰减倍率（越久CD越短）
---@param elapsed number 战斗已过秒数
---@return number cdMult  0.5 ~ 1.0
function WB.GetCDMultiplier(elapsed)
    local cfg = WB.CONFIG
    return math.max(cfg.cdMinMult, 1 - cfg.cdDecayRate * elapsed)
end

--- 计算精英怪HP增强倍率
---@param elapsed number 战斗已过秒数
---@return number hpMult  1.0 ~ 4.0
function WB.GetEliteHPMultiplier(elapsed)
    local cfg = WB.CONFIG
    return 1 + cfg.eliteHPGrowthRate * elapsed
end

-- ============================================================================
-- 难度缩放（全服统一）
-- ============================================================================

--- 计算某波的等效关卡号
---@param wave number 1~20
---@return number stageEquiv
function WB.WaveToStage(wave)
    local cfg = WB.CONFIG
    local base = cfg.baseStageEquiv or 5
    local scale = cfg.waveScaleRate or 0.15
    return base * (1 + (wave - 1) * scale)
end

--- HP 缩放（复用主线公式）
---@param stageEquiv number
---@return number
function WB.CalcHPScale(stageEquiv)
    return Config.GetStageHPScale(stageEquiv)
end

--- 速度缩放
---@param wave number
---@return number
function WB.CalcSpeedScale(wave)
    return math.min(1.0 + (wave - 1) * 0.02, 1.8)
end

-- ============================================================================
-- 主题轮换
-- ============================================================================

--- 获取某波对应的主题索引 (1-based)
---@param wave number 1~20
---@return number themeIdx
local function GetWaveThemeIndex(wave)
    -- 1~4=1, 5~8=2, 9~12=3, 13~16=4, 17~20=5
    return math.floor((wave - 1) / 4) + 1
end

-- ============================================================================
-- 词缀系统
-- ============================================================================

--- 从池中随机选择词缀
---@param tier number 词缀阶级 1/2/3
---@return table|nil affix
local function GetRandomAffix(tier)
    local pool = {}
    for _, affix in ipairs(Config.AFFIXES) do
        if affix.tier == tier then
            pool[#pool + 1] = affix
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

--- 获取某波的词缀精英数量
---@param wave number
---@return number t1Count, number t2Count, number t3Count
local function GetWaveAffixCounts(wave)
    if wave <= 5 then
        return 0, 0, 0
    elseif wave <= 10 then
        return 1, 0, 0
    elseif wave <= 15 then
        return 2, 1, 0
    else
        return 0, 3, 1
    end
end

-- ============================================================================
-- 波次敌人生成
-- ============================================================================

--- 生成指定波次的小怪列表（不含世界BOSS本身）
---@param wave number 1~20
---@return table enemies 敌人定义列表
function WB.GenerateWaveEnemies(wave)
    local stageEquiv = WB.WaveToStage(wave)
    local stageNum = math.max(1, math.floor(stageEquiv))
    local hpScale = WB.CalcHPScale(stageEquiv)
    local spdScale = WB.CalcSpeedScale(wave)

    -- 主题轮换
    local themeIdx = GetWaveThemeIndex(wave)
    if themeIdx > Config.THEME_COUNT then themeIdx = Config.THEME_COUNT end
    local theme = Config.THEMES[themeIdx]

    -- 可用角色池（按全局波次解锁）
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

    -- 词缀精英数量
    local t1Count, t2Count, t3Count = GetWaveAffixCounts(wave)
    local totalElites = t1Count + t2Count + t3Count

    local enemies = {}
    local count = WB.CONFIG.enemiesPerWave

    for i = 1, count do
        local roleId = availRoles[((i - 1) % #availRoles) + 1]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale
            def.speed = def.speed * spdScale
            def.isDungeonEnemy = true

            -- 词缀精英
            if i <= totalElites then
                def.isElite = true
                local tier
                if i <= t3Count then
                    tier = 3
                elseif i <= t3Count + t2Count then
                    tier = 2
                else
                    tier = 1
                end
                local affix = GetRandomAffix(tier)
                if affix then
                    def.eliteAffixes = { affix }
                end
            end

            enemies[#enemies + 1] = def
        end
    end

    return enemies
end

-- ============================================================================
-- 进度管理
-- ============================================================================

--- 获取世界BOSS进度数据（懒初始化 + 每日重置）
---@return table
function WB.GetData()
    if not HeroData.worldBossData then
        HeroData.worldBossData = {
            bestDamage = 0,
            todayAttempts = 0,
            todayAdAttempts = 0,
            lastResetDate = os.date("%Y-%m-%d"),
            totalAttempts = 0,
        }
    end

    -- 每日重置
    local today = os.date("%Y-%m-%d")
    if HeroData.worldBossData.lastResetDate ~= today then
        HeroData.worldBossData.todayAttempts = 0
        HeroData.worldBossData.todayAdAttempts = 0
        HeroData.worldBossData.bestDailyDamage = 0
        HeroData.worldBossData.lastResetDate = today
    end

    return HeroData.worldBossData
end

--- 获取剩余总次数（含神裔降临加成）
---@return number
function WB.GetRemainingAttempts()
    local data = WB.GetData()
    local DivineBlessDB = require("Game.DivineBlessData")
    local bonusAttempt = DivineBlessDB.GetBuffValue("boss_attempt")
    return math.max(0, WB.DAILY_ATTEMPTS + bonusAttempt - data.todayAttempts)
end

--- 获取剩余免费次数
---@return number
function WB.GetFreeRemaining()
    local data = WB.GetData()
    return math.max(0, WB.FREE_ATTEMPTS - data.todayAttempts)
end

--- 获取剩余广告次数
---@return number
function WB.GetAdRemaining()
    local data = WB.GetData()
    return math.max(0, WB.AD_EXTRA_ATTEMPTS - (data.todayAdAttempts or 0))
end

--- 获取最高伤害
---@return number
function WB.GetBestDamage()
    local data = WB.GetData()
    return data.bestDamage or 0
end

--- 消耗免费次数
---@return boolean
function WB.ConsumeAttempt()
    local data = WB.GetData()
    if data.todayAttempts >= WB.DAILY_ATTEMPTS then
        Toast.Show("今日挑战次数已用完", { 255, 200, 80 })
        return false
    end
    if data.todayAttempts >= WB.FREE_ATTEMPTS then
        Toast.Show("免费次数已用完，请观看广告继续", { 255, 200, 80 })
        return false
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    HeroData.Save()
    return true
end

--- 消耗广告领券次数（看完广告后调用，发一张 boss_ticket 到背包）
---@return boolean
function WB.ConsumeAdForTicket()
    local data = WB.GetData()
    local adUsed = data.todayAdAttempts or 0
    if adUsed >= WB.AD_EXTRA_ATTEMPTS then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return false
    end
    data.todayAdAttempts = adUsed + 1
    InventoryData.Add("boss_ticket", 1)
    Toast.Show("获得 深渊主宰挑战券 ×1", { 80, 220, 120 })
    HeroData.Save()
    return true
end

--- 获取背包中 Boss 挑战券数量
---@return number
function WB.GetTicketCount()
    return InventoryData.GetCount("boss_ticket")
end

--- 消耗一张 Boss 挑战券进入挑战
---@return boolean
function WB.ConsumeTicket()
    if InventoryData.GetCount("boss_ticket") <= 0 then
        Toast.Show("挑战券不足", { 255, 200, 80 })
        return false
    end
    local data = WB.GetData()
    -- 扣券
    for i, slot in ipairs(InventoryData.items) do
        if slot.id == "boss_ticket" then
            slot.count = slot.count - 1
            if slot.count <= 0 then
                table.remove(InventoryData.items, i)
            end
            break
        end
    end
    data.todayAttempts = data.todayAttempts + 1
    data.totalAttempts = (data.totalAttempts or 0) + 1
    HeroData.Save()
    return true
end

-- ============================================================================
-- 奖励结算
-- ============================================================================

--- 计算累计伤害可获得的奖励
---@param totalDamage number
---@return number frostPactTotal 霜誓契约总数
function WB.CalcRewards(totalDamage)
    local total = 0
    for _, tier in ipairs(WB.CONFIG.rewardTiers) do
        if totalDamage >= tier[1] then
            total = total + tier[2]
        end
    end
    return total
end

--- 结算奖励（战斗结束时调用）
---@param totalDamage number 本场对BOSS累计伤害
---@return table|nil rewards { recruit_ticket_select_box = amount }
function WB.ClaimReward(totalDamage)
    local data = WB.GetData()

    -- 更新最高纪录
    if totalDamage > (data.bestDamage or 0) then
        data.bestDamage = totalDamage
    end

    -- 计算奖励（招募券自选包）
    local frostPact = WB.CalcRewards(totalDamage)
    if frostPact > 0 then
        InventoryData.Add("recruit_ticket_select_box", frostPact)
    end

    -- 更新当日最高伤害
    local bestDaily = data.bestDailyDamage or 0
    if totalDamage > bestDaily then
        data.bestDailyDamage = totalDamage
    end

    -- 上传排行榜（历史总榜 + 每日榜，均取最高）
    local ok, LBMod = pcall(require, "Game.LeaderboardData")
    if ok then
        if LBMod.UploadWorldBoss then
            LBMod.UploadWorldBoss(data.bestDamage)
        end
        if LBMod.UploadWorldBossDaily and totalDamage > bestDaily then
            LBMod.UploadWorldBossDaily(data.bestDailyDamage)
        end
    end

    HeroData.Save(true)

    print("[WorldBoss] Claimed reward: damage=" .. totalDamage
        .. " recruit_ticket_select_box=" .. frostPact
        .. " bestDamage=" .. data.bestDamage)

    return frostPact > 0 and { recruit_ticket_select_box = frostPact } or nil
end

-- ============================================================================
-- 伤害格式化
-- ============================================================================

--- 格式化伤害数值为可读字符串
---@param damage number
---@return string
function WB.FormatDamage(damage)
    if damage >= 10000000000000000 then
        return string.format("%.1f京", damage / 10000000000000000)
    elseif damage >= 1000000000000 then
        return string.format("%.1f兆", damage / 1000000000000)
    elseif damage >= 100000000 then
        return string.format("%.1f亿", damage / 100000000)
    elseif damage >= 10000 then
        return string.format("%.0f万", damage / 10000)
    else
        return tostring(math.floor(damage))
    end
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("worldBossData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.worldBossData
    end,
    deserialize = function(saved, _saveData)
        HeroData.worldBossData = saved or nil
    end,
})

return WB
