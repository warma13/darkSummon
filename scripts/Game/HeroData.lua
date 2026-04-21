-- Game/HeroData.lua
-- 英雄养成数据管理（局外永久数据）
-- 升星(0-30) + 觉醒(0-4) + 进阶(0-20) 系统，对齐咸鱼之王
--
-- 通过 SaveRegistry 自注册核心数据（heroes/currencies/stats/deployed/recruitData）
-- 子模块数据（chestData/equipData/activityData 等）由各子模块自行注册
-- HeroData 仍保留字段引用，保证对外 API 完全兼容

local Config = require("Game.Config")
local SaveManager = require("Game.SaveManager")
local SafeTable = require("Game.SafeTable")
local SaveRegistry = require("Game.SaveRegistry")
local EventBus = require("Game.EventBus")
local F = require("Game.FormulaLib")

local HeroData = {}

-- Memoization 缓存（Phase 3 优化）
local _starMultCache = {}       -- star(0-30) → multiplier
local _advMultCache = {}        -- advanceLevel(0-20) → multiplier

-- 存档版本号：用于识别数据格式，触发迁移
-- v1(无版本号): 排行榜上传 bestStage
-- v2: 排行榜上传 bestGlobalWave
HeroData.SAVE_VERSION = 2

-- 英雄数据存储
HeroData.heroes = {}       -- heroId -> { unlocked, fragments, level, star, awakening }
HeroData.deployed = {}     -- 已上阵随从英雄ID列表（最多 MAX_DEPLOYED 个，不含主角）
-- 快照函数（存档时调用，返回明文 table）
local currencySnapshot = nil
local heroesSnapshot = nil
local statsSnapshot = nil
local chestSnapshot = nil
local equipSnapshot = nil

HeroData.currencies = {    -- 局外货币（新体系）- 运行时会被 SafeTable 代理替换
    nether_crystal = 0,     -- 冥晶（升级用）
    devour_stone = 0,       -- 噬魂石（进阶用）
    forge_iron = 0,         -- 锻魂铁（装备用）
    void_pact = 0,          -- 虚空契约（招募用）
    shadow_essence = 0,     -- 暗影精华（兑换用）
    dark_soul = 0,          -- 暗魂（战斗内掉落）
    -- 兼容旧存档字段
    gold = 0,
    diamonds = 0,
    advanceStones = 0,
    recruitTokens = 0,
}
HeroData.recruitData = {   -- 招募系统数据
    pityCounter = 0,        -- 保底计数器（每10次重置）
    totalPulls = 0,         -- 历史总抽数
    freeDaily = "",         -- 今日免费抽标记（日期字符串 "YYYY-MM-DD"）
    lrPityCount = 0,        -- LR 保底计数（0~100，第100次强制LR）
}
HeroData.stats = {
    bestStage = 0,
    bestGlobalWave = 0,
    totalGames = 0,
}
HeroData.chestData = nil      -- 宝箱系统数据（由 ChestData 模块管理）
HeroData.equipData = nil      -- 装备系统数据（由 EquipData 模块管理）
HeroData.activityData = nil   -- 活动系统数据（由 ActivityData 模块管理）
HeroData.launchGiftData = nil -- 开服好礼数据（由 LaunchGiftData 模块管理）
HeroData.dailyTaskData = nil  -- 每日任务数据（由 DailyTaskData 模块管理）
HeroData.weeklyActivityData = nil -- 单周活动数据（由 WeeklyActivityData 模块管理）
HeroData.mailboxData = nil        -- 邮件数据（由 MailboxData 模块管理）
HeroData.welfareData = nil        -- 限时福利数据（由 WelfareData 模块管理）
HeroData.costumeSignInData = nil  -- 14天时装签到数据（由 CostumeSignInData 模块管理）

--- 初始化默认数据（新玩家）
--- 现在由 SaveRegistry.InitAllDefaults() 统一调度
--- 此函数仍可直接调用，用于兼容旧路径
function HeroData.InitDefault()
    -- 核心数据由 SaveRegistry 注册的 initDefault 处理
    -- 这里调用 SaveRegistry 来确保所有模块都被初始化
    SaveRegistry.InitAllDefaults()
    print("[HeroData] InitDefault complete (via SaveRegistry)")
end

--- 核心数据初始化（仅 HeroData 自身的数据）
--- 由 SaveRegistry 注册回调调用，不要直接调用
function HeroData._InitCoreDefaults()
    HeroData.heroes, heroesSnapshot = SafeTable.CreateDeep({})
    HeroData.currencies, currencySnapshot = SafeTable.Create({
        nether_crystal = 0,
        devour_stone = 0,
        forge_iron = 0,
        void_pact = 0,
        shadow_essence = 0,
        dark_soul = 0,
        -- 旧字段置零
        gold = 0, diamonds = 0, advanceStones = 0, recruitTokens = 0,
    })
    HeroData.recruitData = { pityCounter = 0, totalPulls = 0, freeDaily = "", lrPityCount = 0 }
    HeroData.stats, statsSnapshot = SafeTable.Create({ bestStage = 0, bestGlobalWave = 0, totalGames = 0 })

    -- 新玩家首日免费赠送自动召唤/合成/布阵/x2
    local today = os.date("%Y-%m-%d")
    HeroData.stats.autoSummonAdDate = today
    HeroData.stats.autoMergeAdDate  = today
    HeroData.stats.autoDeployAdDate = today
    HeroData.stats.speedBoost = {
        date     = today,
        adsUsed  = 0,
        remaining = 3600,  -- 赠送 1 小时 x2 加速
        lastTs   = os.time(),
    }

    HeroData.deployed = {}
    for _, heroId in ipairs(Config.DEFAULT_DEPLOYED) do
        HeroData.deployed[#HeroData.deployed + 1] = heroId
    end
    HeroData.lastSaveTime = 0
    HeroData.redeemData = {}

    -- 所有英雄初始化为未解锁
    for _, towerDef in ipairs(Config.TOWER_TYPES) do
        HeroData.heroes[towerDef.id] = {
            unlocked = false,
            fragments = 0,
            level = 1,
            star = 0,
            awakening = 0,
            advanceLevel = 0,
        }
    end

    -- 默认解锁英雄
    for _, heroId in ipairs(Config.DEFAULT_UNLOCKED) do
        if HeroData.heroes[heroId] then
            HeroData.heroes[heroId].unlocked = true
            HeroData.heroes[heroId].fragments = 5
        end
    end

    -- 初始化主角英雄（始终解锁，无星级/觉醒/碎片）
    HeroData.heroes[Config.LEADER_HERO.id] = {
        unlocked = true,
        fragments = 0,
        level = 1,
        star = 0,
        awakening = 0,
        advanceLevel = 0,
    }

    -- 子模块字段清空（各子模块通过 SaveRegistry 自行初始化）
    HeroData.chestData = nil
    HeroData.equipData = nil
    equipSnapshot = nil
    HeroData.activityData = nil
    HeroData.launchGiftData = nil
    HeroData.dailyTaskData = nil
    HeroData.weeklyActivityData = nil
    HeroData.mailboxData = nil
    HeroData.welfareData = nil
    HeroData.exchangeShop = nil
    HeroData.worldBossData = nil
    HeroData.runeData = nil
    HeroData.towerData = nil
    HeroData.limitedBanner = nil

    print("[HeroData] Core defaults initialized")
end

--- 从本地存档加载（兼容旧路径，新路径走 SlotSaveSystem）
function HeroData.Load()
    local data = SaveManager.Load()
    HeroData.RestoreFromSnapshot(data)
    print("[HeroData] Loaded from local save")
end

--- 获取当前运行时数据的明文快照（用于序列化/存档）
--- 现在由 SaveRegistry.SnapshotAll() 统一收集
---@return table  完整存档数据
function HeroData.GetSaveSnapshot()
    return SaveRegistry.SnapshotAll()
end

--- 核心数据序列化（仅 HeroData 自身）
--- 由 SaveRegistry 注册回调调用
---@return table
function HeroData._SerializeCore()
    return {
        heroes = heroesSnapshot and heroesSnapshot() or HeroData.heroes,
        currencies = currencySnapshot and currencySnapshot() or HeroData.currencies,
        recruitData = HeroData.recruitData,
        deployed = HeroData.deployed,
        stats = statsSnapshot and statsSnapshot() or HeroData.stats,
        redeemData = HeroData.redeemData,
        lastSaveTime = os.time(),
    }
end

--- 从存档快照恢复运行时数据
--- 现在委托给 SaveRegistry.RestoreAll() 统一调度
--- 此函数仍可直接调用，用于兼容旧路径
---@param data table  存档数据（明文）
function HeroData.RestoreFromSnapshot(data)
    SaveRegistry.RestoreAll(data)
    print("[HeroData] RestoreFromSnapshot complete (via SaveRegistry)")
end

--- 核心数据迁移（在 deserialize 之前执行）
--- 处理全量存档级别的迁移：saveVersion、rank→star、旧货币字段
--- 由 SaveRegistry 的 migrate 回调调用
---@param saveData table 完整存档数据
function HeroData._MigrateCore(saveData)
    -- v1→v2 迁移：bestStage → bestGlobalWave
    local oldVersion = saveData.saveVersion or 1
    local rawStats = saveData.stats or {}
    if oldVersion < 2 then
        if not rawStats.bestGlobalWave or rawStats.bestGlobalWave <= 0 then
            rawStats.bestGlobalWave = (rawStats.bestStage or 0) * Config.WAVES_PER_STAGE
        end
        saveData._needLeaderboardResync = true
        print("[HeroData] Save migrated v1→v2: bestGlobalWave=" .. rawStats.bestGlobalWave)
    end

    -- rank→star 迁移
    local heroes = saveData.heroes
    if heroes then
        local rankToStar = { [1] = 0, [2] = 5, [3] = 10, [4] = 15, [5] = 20, [6] = 25 }
        for heroId, h in pairs(heroes) do
            if h.rank and not h.star then
                h.star = rankToStar[h.rank] or 0
                h.awakening = 0
                h.rank = nil
                print("[HeroData] Migrated " .. heroId .. " rank→star=" .. h.star)
            end
        end
    end

    -- 旧货币字段迁移（在 saveData 原表上就地修改）
    local cur = saveData.currencies
    if cur then
        -- advanceStones → devour_stone
        if cur.advanceStones and cur.advanceStones > 0 then
            cur.devour_stone = (cur.devour_stone or 0) + cur.advanceStones
            cur.advanceStones = nil
        end
        -- recruitTokens → void_pact
        if cur.recruitTokens and cur.recruitTokens > 0 then
            cur.void_pact = (cur.void_pact or 0) + cur.recruitTokens
            cur.recruitTokens = nil
        end
        -- gold → nether_crystal
        if cur.gold and cur.gold > 0 then
            cur.nether_crystal = (cur.nether_crystal or 0) + cur.gold
            cur.gold = nil
        end
        -- diamonds → shadow_essence
        if cur.diamonds and cur.diamonds > 0 then
            cur.shadow_essence = (cur.shadow_essence or 0) + cur.diamonds
            cur.diamonds = nil
        end
    end
end

--- 核心数据反序列化（heroes/currencies/stats/deployed/recruitData）
--- 由 SaveRegistry 的 deserialize 回调调用
--- saved 参数为 saveData["_core"]（始终为 nil，因为核心数据散布在顶层）
--- saveData 参数为完整存档数据
---@param _saved any 未使用（核心数据不在单一 key 下）
---@param saveData table 完整存档数据
function HeroData._DeserializeCore(_saved, saveData)
    if not saveData or not saveData.heroes or next(saveData.heroes) == nil then
        HeroData._InitCoreDefaults()
        return
    end

    -- heroes
    HeroData.heroes = saveData.heroes

    -- currencies（补齐缺失字段）
    local rawCurrencies = saveData.currencies or {}
    if rawCurrencies.nether_crystal == nil then rawCurrencies.nether_crystal = 0 end
    if rawCurrencies.devour_stone == nil then rawCurrencies.devour_stone = 0 end
    if rawCurrencies.forge_iron == nil then rawCurrencies.forge_iron = 0 end
    if rawCurrencies.void_pact == nil then rawCurrencies.void_pact = Config.RECRUIT_INITIAL_TOKENS end
    if rawCurrencies.shadow_essence == nil then rawCurrencies.shadow_essence = 0 end
    if rawCurrencies.dark_soul == nil then rawCurrencies.dark_soul = 0 end
    HeroData.currencies = rawCurrencies

    -- stats
    local rawStats = saveData.stats or { bestStage = 0, bestGlobalWave = 0, totalGames = 0 }
    HeroData.stats = rawStats
    HeroData.lastSaveTime = saveData.lastSaveTime or 0

    -- recruitData
    HeroData.recruitData = saveData.recruitData or { pityCounter = 0, totalPulls = 0, freeDaily = "", lrPityCount = 0 }
    if HeroData.recruitData.lrPityCount == nil then
        HeroData.recruitData.lrPityCount = 0  -- 旧存档迁移
    end

    -- deployed（旧存档可能无此字段，需迁移）
    if saveData.deployed and #saveData.deployed > 0 then
        HeroData.deployed = saveData.deployed
    else
        HeroData.deployed = {}
        for _, towerDef in ipairs(Config.TOWER_TYPES) do
            if HeroData.heroes[towerDef.id] and HeroData.heroes[towerDef.id].unlocked then
                HeroData.deployed[#HeroData.deployed + 1] = towerDef.id
                if #HeroData.deployed >= Config.MAX_DEPLOYED then break end
            end
        end
        print("[HeroData] Migrated: deployed " .. #HeroData.deployed .. " heroes")
    end

    -- 补齐新英雄（配置新增但存档里没有的）
    for _, towerDef in ipairs(Config.TOWER_TYPES) do
        if not HeroData.heroes[towerDef.id] then
            HeroData.heroes[towerDef.id] = {
                unlocked = false, fragments = 0, level = 1,
                star = 0, awakening = 0, advanceLevel = 0,
            }
        end
        local h = HeroData.heroes[towerDef.id]
        if h.awakening == nil then h.awakening = 0 end
        if h.star == nil then h.star = 0 end
        if h.advanceLevel == nil then h.advanceLevel = 0 end
    end

    -- 补齐主角英雄
    if not HeroData.heroes[Config.LEADER_HERO.id] then
        HeroData.heroes[Config.LEADER_HERO.id] = {
            unlocked = true, fragments = 0, level = 1,
            star = 0, awakening = 0, advanceLevel = 0,
        }
        print("[HeroData] Migrated: added leader hero")
    else
        local lh = HeroData.heroes[Config.LEADER_HERO.id]
        if lh.unlocked == nil then lh.unlocked = true end
        if lh.advanceLevel == nil then lh.advanceLevel = 0 end
    end

    -- redeemData
    HeroData.redeemData = saveData.redeemData or {}

    -- 记录是否需要排行榜重传（由 _MigrateCore 设置）
    HeroData._needLeaderboardResync = saveData._needLeaderboardResync or false

    -- SafeTable 包装
    HeroData.currencies, currencySnapshot = SafeTable.Create(rawCurrencies)
    HeroData.heroes, heroesSnapshot = SafeTable.CreateDeep(HeroData.heroes)
    HeroData.stats, statsSnapshot = SafeTable.Create(rawStats)

    print("[HeroData] Core deserialized")
end

--- 核心数据校验（反序列化后执行）
--- 处理排行榜重传和版本奖励邮件
function HeroData._ValidateCore()
    -- 新玩家兜底：DEFAULT_UNLOCKED 英雄没有任何一个处于已解锁状态时，强制应用默认值
    local anyUnlocked = false
    for _, heroId in ipairs(Config.DEFAULT_UNLOCKED) do
        local h = HeroData.heroes[heroId]
        if h and h.unlocked then
            anyUnlocked = true
            break
        end
    end
    if not anyUnlocked then
        for _, heroId in ipairs(Config.DEFAULT_UNLOCKED) do
            if HeroData.heroes[heroId] then
                HeroData.heroes[heroId].unlocked = true
                HeroData.heroes[heroId].fragments = 5
            end
        end
        if #HeroData.deployed == 0 then
            HeroData.deployed = {}
            for _, heroId in ipairs(Config.DEFAULT_DEPLOYED) do
                HeroData.deployed[#HeroData.deployed + 1] = heroId
            end
        end
        print("[HeroData] Applied default heroes (new player fallback)")
    end

    -- v1→v2 迁移后：立即重新上传排行榜
    if HeroData._needLeaderboardResync then
        HeroData._needLeaderboardResync = nil
        local bestGW = HeroData.stats.bestGlobalWave or 0
        if bestGW > 0 then
            local ok, LB = pcall(require, "Game.LeaderboardData")
            if ok then
                LB.UploadCampaign(bestGW)
                print("[HeroData] v2 migration: re-uploaded globalWave=" .. bestGW)
            end
        end
        HeroData.Save()
    end

    -- 版本更新奖励邮件
    local CURRENT_VERSION = "1.0.27"
    local lastRewarded = HeroData.stats.lastRewardedVersion or "0"
    if lastRewarded ~= CURRENT_VERSION then
        local ok, Mailbox = pcall(require, "Game.MailboxData")
        if ok then
            Mailbox.Add({
                title = "v" .. CURRENT_VERSION .. " 版本更新奖励",
                desc = "感谢您更新到最新版本！请查收版本更新福利。",
                rewards = {
                    { type = "item", id = "nether_crystal_pack", amount = 3 },
                    { type = "item", id = "shadow_essence_bag",  amount = 2 },
                },
            })
            print("[HeroData] Version reward mail sent for v" .. CURRENT_VERSION)
        end
        HeroData.stats.lastRewardedVersion = CURRENT_VERSION
    end

    -- ========================================================================
    -- 补偿邮件系统（一次性发放，通过 stats.compensations 防重复）
    -- ========================================================================
    if not HeroData.stats.compensations then
        HeroData.stats.compensations = {}
    end

    local COMP_ID = "forge_iron_comp_20260417"  -- 补偿唯一标识
    if not HeroData.stats.compensations[COMP_ID] then
        local ok2, Mailbox2 = pcall(require, "Game.MailboxData")
        if ok2 then
            local myId = clientCloud and clientCloud.userId
            local myIdStr = tostring(myId or 0)

            -- 用户专属补偿：锻魂铁 × 1.3 倍
            local USER_COMP = {
                ["2020363704"] = 57760, ["1931873719"] = 57760, ["897945791"] = 53496,
                ["1699603952"] = 52524, ["191390351"] = 52180, ["346333596"] = 47860,
                ["1840951947"] = 44840, ["1732013179"] = 43860, ["1318083359"] = 39920,
                ["1006084432"] = 39228, ["834166930"] = 39020, ["891277712"] = 36760,
                ["1996655648"] = 36440, ["2091211151"] = 30680, ["1915921944"] = 26060,
                ["1779057459"] = 22400, ["881479440"] = 21920, ["1484115547"] = 19120,
                ["1296664190"] = 18360, ["946074957"] = 18020, ["748065890"] = 17480,
                ["454920882"] = 17000, ["564418097"] = 16200, ["167706129"] = 16200,
                ["1261081970"] = 15640, ["2028526586"] = 14580, ["207736188"] = 13280,
                ["1496964265"] = 13280, ["775402848"] = 12540, ["109012304"] = 11980,
                ["245165705"] = 11980, ["2051179867"] = 11580, ["325089170"] = 10360,
                ["1879205879"] = 10360, ["700145371"] = 9520, ["274791815"] = 9820,
                ["387796072"] = 9820, ["297004786"] = 9260, ["1067207118"] = 8700,
                ["1423946121"] = 8700, ["2007770672"] = 8400, ["131827644"] = 8120,
                ["1539976632"] = 8120, ["1633980224"] = 8120, ["1876099833"] = 8120,
                ["401852988"] = 8060, ["206314218"] = 7560, ["1367044334"] = 7560,
                ["193359618"] = 7380, ["119895248"] = 6980, ["269928001"] = 6980,
                ["618075321"] = 6980, ["1282500428"] = 6980, ["2002684324"] = 6980,
                ["495148045"] = 6400, ["1655784214"] = 6400, ["1870353422"] = 6400,
                ["1964036015"] = 6400, ["2123455409"] = 6400, ["1451919725"] = 5280,
                ["916796984"] = 4700, ["1039992199"] = 4700, ["1445552941"] = 4700,
                ["1757491293"] = 4700, ["1882627292"] = 4700, ["866787093"] = 4100,
                ["272984296"] = 4100, ["335861629"] = 4140, ["873234404"] = 4140,
                ["943097607"] = 4140, ["1217462873"] = 4140, ["2099051752"] = 4140,
                ["43403298"] = 3560, ["427490200"] = 3560, ["906922086"] = 3560,
                ["1094909353"] = 3560, ["1157287233"] = 3560, ["1361621003"] = 3560,
                ["334267249"] = 3000, ["1450505971"] = 3000, ["2095015368"] = 3000,
                ["1472611886"] = 2980, ["1558991381"] = 2520, ["52140186"] = 2420,
                ["255787037"] = 2420, ["258517379"] = 2420, ["416333665"] = 2420,
                ["600188821"] = 2420, ["877957650"] = 2420, ["1210530881"] = 2420,
                ["1332431322"] = 2420, ["1803685670"] = 2420, ["1993012413"] = 2420,
                ["2007100563"] = 2420, ["848730628"] = 1880, ["676035608"] = 1880,
                ["224346719"] = 1880, ["392461447"] = 1880, ["403859421"] = 1880,
                ["496429438"] = 1880, ["650074077"] = 1880, ["653727306"] = 1880,
                ["715665336"] = 1880, ["868709718"] = 1880, ["904918738"] = 1880,
                ["910571537"] = 1880, ["919095641"] = 1880, ["1064772654"] = 1880,
                ["1198164965"] = 1880, ["1239137981"] = 1880, ["1446171235"] = 1880,
                ["1457215985"] = 1880, ["1457669922"] = 1880, ["1466399795"] = 1880,
                ["1665738335"] = 1880, ["1740450395"] = 1880, ["1751253646"] = 1880,
                ["110484933"] = 1340, ["331752427"] = 1340, ["503487263"] = 1340,
                ["556448763"] = 1340, ["583705977"] = 1340, ["825188598"] = 1340,
                ["854049702"] = 1340, ["860246613"] = 1340, ["875534184"] = 1340,
                ["1048863227"] = 1340, ["1184016209"] = 1340, ["1247689958"] = 1340,
                ["1283663886"] = 1340, ["1287973309"] = 1340, ["1306067981"] = 1340,
                ["1327558451"] = 1340, ["1534198407"] = 1340, ["1581296706"] = 1340,
                ["1611471373"] = 1340, ["2111340486"] = 1340, ["1755818496"] = 1080,
                ["212576708"] = 800, ["333707816"] = 800, ["354983203"] = 800,
                ["520541145"] = 800, ["629712865"] = 800, ["743991968"] = 800,
                ["872755351"] = 800, ["1008515761"] = 800, ["1081837956"] = 800,
                ["1478354298"] = 800, ["1589125468"] = 800, ["1612927248"] = 800,
                ["1676072742"] = 800, ["1744120810"] = 800, ["1797641984"] = 800,
                ["1818166524"] = 800, ["221406954"] = 540, ["171258081"] = 540,
                ["545293927"] = 540, ["2010377452"] = 540, ["1715339605"] = 360,
                ["143512556"] = 360, ["154955192"] = 360, ["161549444"] = 360,
                ["184682554"] = 360, ["192815818"] = 360, ["294037728"] = 360,
                ["359852280"] = 360, ["645199302"] = 360, ["659073503"] = 360,
                ["726979543"] = 360, ["736510107"] = 360, ["765993298"] = 360,
                ["797295374"] = 360, ["812878144"] = 360, ["838949832"] = 360,
                ["865799524"] = 360, ["870901184"] = 360, ["873037689"] = 360,
                ["873756536"] = 360, ["951270429"] = 360, ["967162897"] = 360,
                ["967191872"] = 360, ["1034787989"] = 360, ["1135651403"] = 360,
                ["1250341860"] = 360, ["1297574786"] = 360, ["1327014002"] = 360,
                ["1367700010"] = 360, ["1373321665"] = 360, ["1392693663"] = 360,
                ["1478621824"] = 360, ["1526547665"] = 360, ["1614323741"] = 360,
                ["1686036671"] = 360, ["1860990699"] = 360, ["1913014619"] = 360,
                ["1925659912"] = 360, ["2119629164"] = 360, ["18907874"] = 100,
            }

            local personalAmount = USER_COMP[myIdStr]
            if personalAmount then
                local compAmount = math.floor(personalAmount * 1.3)
                Mailbox2.Add({
                    title = "装备补偿邮件",
                    desc = "亲爱的召唤师，因近期装备系统调整给您带来的不便，特此补偿锻魂铁 " .. compAmount .. "。感谢您的理解与支持！",
                    rewards = {
                        { type = "currency", id = "forge_iron", amount = compAmount },
                    },
                })
                print("[HeroData] Personal compensation sent: forge_iron " .. compAmount .. " for user " .. myIdStr)
            end

            -- 全服补偿：所有玩家 1000 锻魂铁
            Mailbox2.Add({
                title = "全服补偿邮件",
                desc = "亲爱的召唤师，因近期系统调整给各位带来的不便，特此向全服玩家补偿锻魂铁 1000。感谢您的支持！",
                rewards = {
                    { type = "currency", id = "forge_iron", amount = 1000 },
                },
            })
            print("[HeroData] Global compensation sent: forge_iron 1000")
        end
        HeroData.stats.compensations[COMP_ID] = true
    end

    local COMP_ID2 = "shadow_essence_comp_20260417"
    if not HeroData.stats.compensations[COMP_ID2] then
        local ok3, Mailbox3 = pcall(require, "Game.MailboxData")
        if ok3 then
            Mailbox3.Add({
                title = "全服补偿邮件",
                desc = "亲爱的召唤师，因近期系统调整给各位带来的不便，特此向全服玩家补偿暗影精粹 1000。感谢您的支持！",
                rewards = {
                    { type = "currency", id = "shadow_essence", amount = 1000 },
                },
            })
            print("[HeroData] Global compensation sent: shadow_essence 1000")
        end
        HeroData.stats.compensations[COMP_ID2] = true
    end

    local COMP_ID3 = "v1036_reward_20260420"
    if not HeroData.stats.compensations[COMP_ID3] then
        local ok4, Mailbox4 = pcall(require, "Game.MailboxData")
        if ok4 then
            Mailbox4.Add({
                title = "版本更新奖励",
                desc = "亲爱的召唤师，感谢您的持续支持！本次更新新增宝箱与招募成就系统，特此赠送暗影精粹 3000 和虚空契约 10，祝您游戏愉快！",
                rewards = {
                    { type = "currency", id = "shadow_essence", amount = 3000 },
                    { type = "currency", id = "void_pact", amount = 10 },
                },
            })
            print("[HeroData] v1.0.36 reward sent: shadow_essence 3000 + void_pact 10")
        end
        HeroData.stats.compensations[COMP_ID3] = true
    end

    -- ========================================================================
    -- 虚空契约产出公式重平衡补偿（一次性）
    -- 旧公式：主线 floor(1+s/10)，试练塔通塔 10，成就每5关 1
    -- 新公式：主线 floor(2*ln(s+1))，试练塔每层 floor(2*ln(t*10+1))，
    --         通塔 floor(2*ln(t*10+1))*10，成就改为暗影精粹
    -- 差值为正则补发，为负则不扣
    -- ========================================================================
    local COMP_VOID_REBALANCE = "void_pact_rebalance_20260420"
    if not HeroData.stats.compensations[COMP_VOID_REBALANCE] then
        local bestStage = HeroData.stats.bestStage or 0
        local towerData = HeroData.towerData
        local clearedFloors = towerData and towerData.clearedFloors or 0
        local claimedTowers = towerData and towerData.claimedTowers or 0

        if bestStage > 0 or clearedFloors > 0 then
            -- ---- 旧公式总产出 ----
            local oldTotal = 0
            -- 旧主线：floor(1 + s/10) per stage
            for s = 1, bestStage do
                oldTotal = oldTotal + math.floor(1 + s / 10)
            end
            -- 旧试练塔：每通塔 10
            oldTotal = oldTotal + claimedTowers * 10
            -- 旧成就：每5关 1 张虚空契约
            oldTotal = oldTotal + math.floor(bestStage / 5)

            -- ---- 新公式总产出 ----
            local newTotal = 0
            -- 新主线：floor(2 * ln(s + 1)) per stage
            for s = 1, bestStage do
                newTotal = newTotal + math.floor(2 * math.log(s + 1))
            end
            -- 新试练塔每层：floor(2 * ln(towerNum * 10 + 1))
            for f = 1, clearedFloors do
                local tNum = math.ceil(f / 10)
                newTotal = newTotal + math.floor(2 * math.log(tNum * 10 + 1))
            end
            -- 新试练塔通塔：floor(2 * ln(t * 10 + 1)) * 10
            for t = 1, claimedTowers do
                newTotal = newTotal + math.floor(2 * math.log(t * 10 + 1)) * 10
            end
            -- 新成就：0（已改为暗影精粹，不再发虚空契约）

            local diff = newTotal - oldTotal
            if diff > 0 then
                local ok5, Mailbox5 = pcall(require, "Game.MailboxData")
                if ok5 then
                    Mailbox5.Add({
                        title = "虚空契约调整补偿",
                        desc = "亲爱的召唤师，因虚空契约产出公式调整，根据您的游戏进度"
                            .. "（主线第" .. bestStage .. "关，试练塔第" .. clearedFloors .. "层），"
                            .. "系统已为您补发虚空契约 " .. diff .. " 张。",
                        rewards = {
                            { type = "currency", id = "void_pact", amount = diff },
                        },
                    })
                end
                print("[HeroData] Void pact rebalance comp: old=" .. oldTotal
                    .. " new=" .. newTotal .. " diff=+" .. diff)
            else
                print("[HeroData] Void pact rebalance: old=" .. oldTotal
                    .. " new=" .. newTotal .. " no comp needed (diff=" .. diff .. ")")
            end
        end
        HeroData.stats.compensations[COMP_VOID_REBALANCE] = true
    end
end

--- 保存数据（自动分流：SlotSaveSystem 活跃时标记脏，否则走本地）
--- @param immediate boolean|nil  true=立即云端保存（用于不可逆操作如抽卡、消耗货币等）
function HeroData.Save(immediate)
    local SlotSave = require("Game.SlotSaveSystem")
    if SlotSave.GetActiveSlot() > 0 then
        if immediate then
            SlotSave.SaveNow()
        else
            SlotSave.MarkDirty()
        end
    else
        -- 未加载槽位时使用旧路径（兼容初始化阶段）
        SaveManager.Save(HeroData.GetSaveSnapshot())
    end
    -- 通知订阅方（TabNav 红点刷新等）
    EventBus.emit(EventBus.EVENT.DATA_SAVED, { immediate = immediate == true })
end

--- 设置 chestData（纯表直接赋值，与 welfareData 一致）
---@param data table|nil  明文宝箱数据
function HeroData.SetChestData(data)
    HeroData.chestData = data
end

--- 设置 equipData 并自动包装 SafeTable（供 EquipData 调用）
---@param data table  明文装备数据
function HeroData.SetEquipData(data)
    if data then
        HeroData.equipData, equipSnapshot = SafeTable.CreateDeep(data)
    else
        HeroData.equipData = nil
        equipSnapshot = nil
    end
end

--- 获取 equipData 的明文快照（供 EquipData.serialize 使用）
---@return table|nil
function HeroData.GetEquipSnapshot()
    if equipSnapshot then
        return equipSnapshot()
    end
    return HeroData.equipData
end

--- 获取英雄数据
---@param heroId string
---@return table|nil
function HeroData.Get(heroId)
    return HeroData.heroes[heroId]
end

--- 英雄是否已解锁
---@param heroId string
---@return boolean
function HeroData.IsUnlocked(heroId)
    local h = HeroData.heroes[heroId]
    return h and h.unlocked or false
end

--- 获取已解锁英雄列表
---@return table  -- array of heroId strings
function HeroData.GetUnlockedList()
    local list = {}
    for _, towerDef in ipairs(Config.TOWER_TYPES) do
        if HeroData.IsUnlocked(towerDef.id) then
            list[#list + 1] = towerDef.id
        end
    end
    return list
end

-- ============================================================================
-- 上阵/部署系统
-- ============================================================================

--- 英雄是否已上阵
---@param heroId string
---@return boolean
function HeroData.IsDeployed(heroId)
    for _, id in ipairs(HeroData.deployed) do
        if id == heroId then return true end
    end
    return false
end

--- 获取已上阵英雄列表
---@return string[]
function HeroData.GetDeployedList()
    return HeroData.deployed
end

--- 获取已上阵英雄数量
---@return number
function HeroData.GetDeployedCount()
    return #HeroData.deployed
end

--- 上阵英雄
---@param heroId string
---@return boolean success
---@return string msg
function HeroData.Deploy(heroId)
    if not HeroData.IsUnlocked(heroId) then
        return false, "英雄未解锁"
    end
    if heroId == Config.LEADER_HERO.id then
        return false, "主角始终上阵，无需操作"
    end
    if HeroData.IsDeployed(heroId) then
        return false, "已在阵中"
    end
    if #HeroData.deployed >= Config.MAX_DEPLOYED then
        return false, "阵位已满(最多" .. Config.MAX_DEPLOYED .. "个)"
    end
    HeroData.deployed[#HeroData.deployed + 1] = heroId
    HeroData.Save()
    print("[HeroData] Deployed " .. heroId .. " (" .. #HeroData.deployed .. "/" .. Config.MAX_DEPLOYED .. ")")
    return true, "上阵成功"
end

--- 下阵英雄
---@param heroId string
---@return boolean success
---@return string msg
function HeroData.Undeploy(heroId)
    for i, id in ipairs(HeroData.deployed) do
        if id == heroId then
            table.remove(HeroData.deployed, i)
            HeroData.Save()
            print("[HeroData] Undeployed " .. heroId .. " (" .. #HeroData.deployed .. "/" .. Config.MAX_DEPLOYED .. ")")
            return true, "下阵成功"
        end
    end
    return false, "不在阵中"
end

--- 交换阵位
---@param idx1 number
---@param idx2 number
function HeroData.SwapDeployed(idx1, idx2)
    if idx1 < 1 or idx1 > #HeroData.deployed then return end
    if idx2 < 1 or idx2 > #HeroData.deployed then return end
    HeroData.deployed[idx1], HeroData.deployed[idx2] = HeroData.deployed[idx2], HeroData.deployed[idx1]
    HeroData.Save()
end

-- ============================================================================
-- 升星系统
-- ============================================================================

--- 根据星数计算所在段号(1-6)
---@param star number  0-30
---@return number  tierNum 1-6 (0星返回1表示黄星段)
function HeroData.GetTierFromStar(star)
    if star <= 0 then return 1 end
    for i, tier in ipairs(Config.STAR_TIERS) do
        if star >= tier.starRange[1] and star <= tier.starRange[2] then
            return i
        end
    end
    return #Config.STAR_TIERS
end

--- 计算已完成的段进阶次数
---@param star number
---@return number  0-5
function HeroData.GetCompletedAdvances(star)
    if star <= 0 then return 0 end
    local advances = 0
    for _, tier in ipairs(Config.STAR_TIERS) do
        if star >= tier.starRange[1] then
            advances = advances + 1
        else
            break
        end
    end
    -- advances 代表已进入的段数(1-6)，完成的进阶 = 进入段数 - 1
    return math.max(0, advances - 1)
end

--- 获取星级段信息
---@param heroId string
---@return table  { tierNum, name, color, starInTier, totalInTier }
function HeroData.GetStarTierInfo(heroId)
    local h = HeroData.heroes[heroId]
    local star = (h and h.star) or 0
    if star <= 0 then
        local tier = Config.STAR_TIERS[1]
        return { tierNum = 0, name = "无星", color = { 200, 200, 200 }, starInTier = 0, totalInTier = 5 }
    end
    local tierNum = HeroData.GetTierFromStar(star)
    local tier = Config.STAR_TIERS[tierNum]
    local starInTier = star - tier.starRange[1] + 1
    local totalInTier = tier.starRange[2] - tier.starRange[1] + 1
    return {
        tierNum = tierNum,
        name = tier.name,
        color = tier.color,
        starInTier = starInTier,
        totalInTier = totalInTier,
    }
end

--- 获取星级段颜色（供 Renderer 使用）
---@param heroId string
---@return table  { r, g, b }
function HeroData.GetStarTierColor(heroId)
    local info = HeroData.GetStarTierInfo(heroId)
    return info.color
end

--- 计算升星所需碎片（当前星→下一星）
---@param star number  当前星数
---@return number cost, boolean isTierAdvance
function HeroData.GetStarUpCost(star)
    if star >= Config.MAX_HERO_STAR then
        return 0, false
    end
    local nextStar = star + 1
    local nextTier = HeroData.GetTierFromStar(nextStar)
    local costPerStar = Config.STAR_COST_PER_TIER[nextTier] or 400
    -- 判断是否为段进阶（进入新段的第1颗星）
    local currentTier = star > 0 and HeroData.GetTierFromStar(star) or 0
    local isTierAdvance = (nextTier > currentTier)
    return costPerStar, isTierAdvance
end

--- 升星（消耗碎片）
---@param heroId string
---@return boolean, string  -- success, message
function HeroData.StarUp(heroId)
    local h = HeroData.heroes[heroId]
    if not h or not h.unlocked then
        return false, "英雄未解锁"
    end
    if h.star >= Config.MAX_HERO_STAR then
        return false, "已达最高星级(30星)"
    end

    local cost, isTierAdvance = HeroData.GetStarUpCost(h.star)
    if h.fragments < cost then
        return false, "碎片不足(需要" .. cost .. "，当前" .. h.fragments .. ")"
    end

    h.fragments = h.fragments - cost
    h.star = h.star + 1

    -- 检查觉醒
    HeroData.CheckAwakening(heroId)

    HeroData.Save()

    local tierInfo = HeroData.GetStarTierInfo(heroId)
    local msg = tierInfo.name .. " " .. tierInfo.starInTier .. "/" .. tierInfo.totalInTier
    if isTierAdvance then
        msg = "突破! " .. msg
    end
    print("[HeroData] " .. heroId .. " star up to " .. h.star .. " (" .. msg .. ")")
    return true, msg
end

--- 计算升星带来的全属性倍率（乘算，对齐咸鱼之王）
--- 黄紫橙红: 每星 ×1.10 | 皇冠紫晶: 每星 ×1.15 | 段突破: ×1.40
--- 30星满: 1.10^20 × 1.15^10 × 1.40^4 ≈ ×104.5
---@param heroId string
---@return number
function HeroData.GetStarMultiplier(heroId)
    local h = HeroData.heroes[heroId]
    if not h then return 1.0 end
    local star = h.star or 0
    if star <= 0 then return 1.0 end

    -- Memoization: star 值只有 0-30，缓存命中直接返回
    local cached = _starMultCache[star]
    if cached then return cached end

    local mult = 1.0
    local crownStart = Config.STAR_CROWN_START  -- 21
    local normalMult = Config.STAR_NORMAL_MULT  -- 1.10
    local crownMult = Config.STAR_CROWN_MULT    -- 1.15
    local tierAdvMult = Config.TIER_ADVANCE_MULT -- 1.40

    -- 逐星计算（含段进阶）
    local prevTier = 0
    for s = 1, star do
        local curTier = HeroData.GetTierFromStar(s)
        -- 进入新段时触发段进阶加成
        if curTier > prevTier and prevTier > 0 then
            mult = mult * tierAdvMult
        end
        -- 每星乘算
        if s >= crownStart then
            mult = mult * crownMult
        else
            mult = mult * normalMult
        end
        prevTier = curTier
    end

    _starMultCache[star] = mult
    return mult
end

-- ============================================================================
-- 觉醒系统
-- ============================================================================

--- 根据星级检查并更新觉醒等级
---@param heroId string
function HeroData.CheckAwakening(heroId)
    local h = HeroData.heroes[heroId]
    if not h then return end
    local oldAwaken = h.awakening or 0
    local newAwaken = 0
    for i, threshold in ipairs(Config.AWAKENING_STAR_THRESHOLDS) do
        if h.star >= threshold then
            newAwaken = i
        end
    end
    if newAwaken > oldAwaken then
        h.awakening = newAwaken
        print("[HeroData] " .. heroId .. " awakened to level " .. newAwaken .. "!")
    end
end

-- ============================================================================
-- 技能系统（等级解锁）
-- ============================================================================

--- 获取英雄已解锁的技能列表（按等级解锁）
---@param heroId string
---@return table  -- array of skill definitions
function HeroData.GetUnlockedSkills(heroId)
    local h = HeroData.heroes[heroId]
    if not h or not h.unlocked then return {} end

    local skillDefs = Config.HERO_SKILLS[heroId]
    if not skillDefs then return {} end

    local skills = {}
    -- 凛冬君王全被动技能，自动解锁全部
    local autoUnlockAll = (heroId == "glacial_sovereign")
    for i, skillDef in ipairs(skillDefs) do
        if autoUnlockAll then
            skills[#skills + 1] = skillDef
        else
            local unlockLv = Config.SKILL_UNLOCK_LEVELS[i] or 999
            if h.level >= unlockLv then
                skills[#skills + 1] = skillDef
            end
        end
    end
    return skills
end

-- ============================================================================
-- 等级系统（6000级 + 进阶石门槛）
-- ============================================================================

--- 获取英雄已完成的进阶次数
---@param heroId string
---@return number  0-20
function HeroData.GetAdvanceLevel(heroId)
    local h = HeroData.heroes[heroId]
    return (h and h.advanceLevel) or 0
end

--- 获取下一个进阶门槛（如果当前等级恰好在门槛处）
--- 返回 nil 表示无需进阶
---@param heroId string
---@return table|nil  { level, stones, bonus, gateIndex }
function HeroData.GetPendingAdvanceGate(heroId)
    local h = HeroData.heroes[heroId]
    if not h then return nil end
    local advLv = h.advanceLevel or 0
    local nextGateIdx = advLv + 1
    local gate = Config.ADVANCE_GATES[nextGateIdx]
    if gate and h.level >= gate.level then
        return { level = gate.level, stones = gate.stones, bonus = gate.bonus, gateIndex = nextGateIdx }
    end
    return nil
end

--- 获取主角英雄等级
---@return number
function HeroData.GetLeaderLevel()
    local leader = HeroData.heroes[Config.LEADER_HERO.id]
    return (leader and leader.level) or 1
end

--- 获取当前等级上限（受进阶限制 + 主角等级限制）
--- 随从英雄: min(进阶上限, 主角等级)
--- 主角英雄: 仅受进阶上限
---@param heroId string
---@return number
function HeroData.GetCurrentLevelCap(heroId)
    local h = HeroData.heroes[heroId]
    if not h then return 1 end
    local advLv = h.advanceLevel or 0
    local nextGateIdx = advLv + 1
    local gate = Config.ADVANCE_GATES[nextGateIdx]
    local advanceCap = gate and gate.level or Config.MAX_LEVEL

    -- 随从英雄等级上限 = min(进阶上限, 主角等级)
    if heroId ~= Config.LEADER_HERO.id then
        local leaderLevel = HeroData.GetLeaderLevel()
        return math.min(advanceCap, leaderLevel)
    end

    return advanceCap
end

--- 进阶（消耗进阶石，突破等级门槛）
---@param heroId string
---@return boolean, string
function HeroData.Advance(heroId)
    local h = HeroData.heroes[heroId]
    if not h or not h.unlocked then
        return false, "英雄未解锁"
    end
    local gate = HeroData.GetPendingAdvanceGate(heroId)
    if not gate then
        return false, "无需进阶"
    end
    if (HeroData.currencies.devour_stone or 0) < gate.stones then
        return false, "噬魂石不足(需要" .. gate.stones .. "，当前" .. (HeroData.currencies.devour_stone or 0) .. ")"
    end

    HeroData.currencies.devour_stone = HeroData.currencies.devour_stone - gate.stones
    h.advanceLevel = gate.gateIndex
    HeroData.Save()
    print("[HeroData] " .. heroId .. " advanced to gate " .. gate.gateIndex .. " (Lv" .. gate.level .. "+)")
    return true, "进阶成功! 等级上限提升"
end

-- ============================================================================
-- 属性计算（对齐咸鱼之王量级）
-- 四维属性(ATK/HP/DEF/SPD): 基础 × 等级倍率 × 进阶倍率 × 升星倍率
--   等级倍率 = 1 + (level-1) × growthPct（百分比线性成长）
-- 战斗子属性(破甲/暴击/暴伤): 基础 + 等级线性成长（不受星/阶乘算）
--   → 后续装备/宝石/宠物等系统通过加算叠加到这些属性上
-- ============================================================================

--- 计算等级带来的全属性乘算倍率（百分比线性成长，对齐咸鱼之王）
--- 公式: 1 + (level - 1) × growthPct
--- 例: N级 growthPct=0.01, Lv30 → 1.29 (+29%), Lv100 → 1.99 (+99%)
---@param growthPct number  每级成长百分比（如 0.01 = 1%/级）
---@param level number  当前等级
---@return number  倍率（≥1.0）
local function CalcLevelMultiplier(growthPct, level)
    if level <= 1 then return 1.0 end
    return F.Linear(1.0, growthPct, level - 1)
end

--- 计算进阶倍率（每阶 ×1.10，乘算，对齐咸鱼之王）
--- 20阶满: 1.10^20 ≈ ×6.73
---@param heroId string
---@return number
local function CalcAdvanceMultiplier(heroId)
    local h = HeroData.heroes[heroId]
    if not h then return 1.0 end
    local advLv = h.advanceLevel or 0
    if advLv <= 0 then return 1.0 end

    -- Memoization: advanceLevel 只有 0-20，按 advLv 缓存
    local cached = _advMultCache[advLv]
    if cached then return cached end

    local result = F.CompoundMult(advLv, function(i)
        local gate = Config.ADVANCE_GATES[i]
        return gate and (1.0 + gate.bonus) or 1.0
    end)

    _advMultCache[advLv] = result
    return result
end

--- 获取英雄完整属性（二维 + 战斗子属性）
--- 二维(ATK/SPD): 基础 × 等级倍率 × 进阶 × 升星
--- 战斗子属性(破甲/暴击/暴伤): 基础 + 等级线性成长（后续+装备+宝石等）
---@param heroId string
---@return table  { atk, spd, armorPen, critRate, critDmg, baseAtk, ... }
function HeroData.GetHeroStats(heroId)
    local base = Config.HERO_BASE_STATS[heroId]
    if not base then
        return {
            atk = 0, spd = 0,
            armorPen = 0, critRate = 0, critDmg = 0,
            baseAtk = 0, baseSpd = 0,
        }
    end
    local h = HeroData.heroes[heroId]
    local level = (h and h.level) or 1

    -- 等级成长倍率（百分比乘算，按品质查表）
    local rarity = Config.HERO_RARITY[heroId] or "N"
    local growthPct = Config.RARITY_GROWTH_PCT[rarity] or 0.01
    local levelMult = CalcLevelMultiplier(growthPct, level)

    -- 等级后裸属性
    local rawAtk = math.floor(base.atk * levelMult)

    -- 进阶倍率 × 升星倍率（仅作用于三维）
    local advMult = CalcAdvanceMultiplier(heroId)
    local starMult = HeroData.GetStarMultiplier(heroId)

    -- SPD: 分段线性增长，直接计算攻速加成比例（0 ~ SPD_BONUS_MAX）
    local totalMult = levelMult * advMult * starMult
    local spdBonus = math.min(F.Piecewise(Config.SPD_BONUS_CURVE, totalMult), Config.SPD_BONUS_MAX)

    -- 战斗子属性: 基础 + 等级线性成长（不受星/阶乘算影响）
    -- 来源分离: 等级提供基础值，后续装备/宝石等系统加算叠加
    local n = math.max(0, level - 1)
    local armorPen = (base.armorPen or 0) + n * (base.armorPenGrowth or 0)
    local critRate = (base.critRate or 0) + n * (base.critRateGrowth or 0)
    local critDmg  = (base.critDmg or 0)  + n * (base.critDmgGrowth or 0)

    return {
        atk = math.floor(rawAtk * advMult * starMult),
        spd = math.floor(base.spd * (1 + spdBonus)),  -- 面板值: baseSpd × (1 + 加成)
        spdBonus = spdBonus,                            -- 攻速加成比例 (0~0.30)
        -- 战斗子属性（小数比例: 0.30 = 30%）
        armorPen = armorPen,
        critRate = critRate,
        critDmg  = critDmg,
        dmgBonus = 0,  -- 伤害加成%（由装备等系统赋值）
        elemDmgBonus = { fire = 0, ice = 0, lightning = 0, poison = 0, shadow = 0 },  -- 各元素伤害加成（由装备/宝石等系统赋值）
        baseAtk = base.atk,
        baseSpd = base.spd,
    }
end

--- 计算等级带来的射程加成
---@param heroId string
---@return number
function HeroData.GetLevelRangeBonus(heroId)
    local h = HeroData.heroes[heroId]
    if not h then return 0 end
    return (h.level - 1) * Config.LEVEL_RANGE_BONUS
end

-- 升级费用分段多项式定义: { fromX, toX, a, b, c }
-- 值 = a + b*(level - fromX) + c*(level - fromX)^2
local LEVEL_COST_SEGMENTS = {
    { 1,    101,  10,    0.5,   0     },  -- 1~100:    极便宜，快速冲级
    { 101,  501,  60,    1.2,   0.003 },  -- 101~500:  平稳过渡
    { 501,  1501, 1040,  20,    0.03  },  -- 501~1500: 中期成长
    { 1501, 3601, 51000, 1200,  1.249 },  -- 1501~3600: 后期陡峭
}

--- 计算升级费用（分段公式，对齐咸鱼之王曲线）
--- 阶段1(1~100):    前期极便宜，快速冲级    ~57/级
--- 阶段2(101~500):  平稳过渡               ~60→1020/级
--- 阶段3(501~1500): 中期成长               ~1040→5.1万/级
--- 阶段4(1501~3600): 后期陡峭              ~5.1万→808万/级
--- 阶段5(3601+):    封顶固定值 807.8万/级
---@param level number 当前等级
---@return number
function HeroData.GetLevelUpCost(level)
    return math.floor(F.PiecewisePoly(LEVEL_COST_SEGMENTS, level, Config.LEVEL_COST_CAP))
end

--- 升级英雄（消耗金币，受进阶门槛限制）
---@param heroId string
---@return boolean, string  -- success, message
function HeroData.LevelUp(heroId)
    local h = HeroData.heroes[heroId]
    if not h or not h.unlocked then
        return false, "英雄未解锁"
    end

    if h.level >= Config.MAX_LEVEL then
        return false, "已达最高等级(Lv6000)"
    end

    -- 检查是否被等级上限卡住（进阶门槛 或 主角等级）
    local cap = HeroData.GetCurrentLevelCap(heroId)
    if h.level >= cap then
        -- 区分限制原因：主角等级不足 vs 需要进阶
        if heroId ~= Config.LEADER_HERO.id then
            local leaderLevel = HeroData.GetLeaderLevel()
            local advLv = h.advanceLevel or 0
            local nextGateIdx = advLv + 1
            local gate = Config.ADVANCE_GATES[nextGateIdx]
            local advanceCap = gate and gate.level or Config.MAX_LEVEL
            if leaderLevel < advanceCap then
                return false, "主角等级不足(Lv" .. leaderLevel .. ")，请先提升主角"
            end
        end
        return false, "需要进阶才能继续升级(Lv" .. cap .. ")"
    end

    local cost = HeroData.GetLevelUpCost(h.level)
    if (HeroData.currencies.nether_crystal or 0) < cost then
        return false, "冥晶不足(需要" .. cost .. ")"
    end

    HeroData.currencies.nether_crystal = HeroData.currencies.nether_crystal - cost
    h.level = h.level + 1
    HeroData.Save()
    print("[HeroData] " .. heroId .. " leveled up to Lv." .. h.level)
    return true, "升级成功 Lv." .. h.level
end

-- ============================================================================
-- 碎片 & 解锁
-- ============================================================================

--- 添加碎片（纯加碎片，不触发解锁）
---@param heroId string
---@param amount number
function HeroData.AddFragments(heroId, amount)
    local h = HeroData.heroes[heroId]
    if not h then return end
    h.fragments = h.fragments + amount
end

--- 首次获得英雄：直接解锁并设为1星（咸鱼之王机制）
---@param heroId string
function HeroData.UnlockHero(heroId)
    local h = HeroData.heroes[heroId]
    if not h or h.unlocked then return end
    h.unlocked = true
    h.star = 1
    print("[HeroData] " .. heroId .. " unlocked! (first pull, star=1)")
end

-- ============================================================================
-- 重生（重置等级+装备，返还消耗）
-- ============================================================================

--- 计算英雄从1级升到指定等级的总冥晶消耗
---@param targetLevel number
---@return number
function HeroData.CalcTotalLevelCost(targetLevel)
    local total = 0
    for lv = 1, targetLevel - 1 do
        total = total + HeroData.GetLevelUpCost(lv)
    end
    return total
end

--- 计算装备从1级升到指定等级的总锻魂铁消耗
---@param targetLevel number
---@return number
local function CalcEquipLevelCost(targetLevel)
    local EquipData = require("Game.EquipData")
    local total = 0
    for lv = 1, targetLevel - 1 do
        total = total + EquipData.GetUpgradeCost(lv)
    end
    return total
end

--- 计算英雄重生返还的资源
---@param heroId string
---@return table|nil  { nether_crystal, forge_iron }  nil=无法重生
function HeroData.CalcRebirthRefund(heroId)
    local h = HeroData.heroes[heroId]
    if not h or not h.unlocked then return nil end
    local advLv = h.advanceLevel or 0

    if h.level <= 1 and advLv <= 0 then
        -- 检查装备是否也全是1级
        local EquipData = require("Game.EquipData")
        local hasEquipLevel = false
        local equips = EquipData.GetHeroEquips(heroId)
        for _, slot in ipairs(Config.EQUIP_SLOTS) do
            local e = equips[slot.id]
            if e and (e.level > 1 or e.tierIdx > 1) then
                hasEquipLevel = true
                break
            end
        end
        if not hasEquipLevel then return nil end  -- 等级和装备都是初始，无需重生
    end

    local crystalRefund = HeroData.CalcTotalLevelCost(h.level)

    -- 进阶（噬魂石）返还
    local stoneRefund = 0
    for i = 1, advLv do
        local gate = Config.ADVANCE_GATES[i]
        if gate then
            stoneRefund = stoneRefund + gate.stones
        end
    end

    local EquipData = require("Game.EquipData")
    local equips = EquipData.GetHeroEquips(heroId)
    local ironRefund = 0
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local e = equips[slot.id]
        if e then
            ironRefund = ironRefund + CalcEquipLevelCost(e.level)
            -- 突破费用返还
            for ti = 2, e.tierIdx do
                local tierDef = Config.EQUIP_TIERS[ti]
                if tierDef then
                    ironRefund = ironRefund + (tierDef.breakCost or 0)
                end
            end
        end
    end

    return { nether_crystal = crystalRefund, forge_iron = ironRefund, devour_stone = stoneRefund }
end

--- 执行重生（重置英雄等级和装备等级，返还资源，保留升星）
---@param heroId string
---@return boolean, string, table|nil
function HeroData.Rebirth(heroId)
    local refund = HeroData.CalcRebirthRefund(heroId)
    if not refund then return false, "该英雄无需重生", nil end

    local h = HeroData.heroes[heroId]

    -- 重置英雄等级
    h.level = 1
    h.advanceLevel = 0

    -- 重置装备
    local EquipData = require("Game.EquipData")
    local equips = EquipData.GetHeroEquips(heroId)
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        equips[slot.id] = { level = 1, tierIdx = 1 }
    end

    -- 返还资源
    HeroData.currencies.nether_crystal = (HeroData.currencies.nether_crystal or 0) + refund.nether_crystal
    HeroData.currencies.forge_iron = (HeroData.currencies.forge_iron or 0) + refund.forge_iron
    HeroData.currencies.devour_stone = (HeroData.currencies.devour_stone or 0) + refund.devour_stone

    HeroData.Save(true)
    print("[HeroData] " .. heroId .. " rebirth! refund crystal=" .. refund.nether_crystal .. " iron=" .. refund.forge_iron .. " stone=" .. refund.devour_stone)
    return true, "重生成功", refund
end

-- ============================================================================
-- 结算奖励
-- ============================================================================

--- 通关结算（更新统计、上传排行榜，不发放奖励）
---@param stageNum number 通关的关卡号
---@param score number 得分
function HeroData.SettleRewards(stageNum, score)
    -- 更新统计
    HeroData.stats.totalGames = HeroData.stats.totalGames + 1
    if stageNum > (HeroData.stats.bestStage or 0) then
        HeroData.stats.bestStage = stageNum
    end
    -- 上传主线排行榜（用 bestGlobalWave，已在 Wave.StartNext 中更新）
    local bestGW = HeroData.stats.bestGlobalWave or 0
    if bestGW > 0 then
        local ok, LB = pcall(require, "Game.LeaderboardData")
        if ok then LB.UploadCampaign(bestGW) end
    end

    HeroData.Save()
    print("[HeroData] Settlement: stage " .. stageNum .. " (no rewards)")
end

-- ============================================================================
-- 挂机离线收益
-- ============================================================================

--- 计算离线挂机收益（不发放，仅计算）
---@return table|nil  rewards { seconds, nether_crystal, devour_stone, forge_iron } 或 nil（时间不足）
function HeroData.CalcIdleRewards()
    local lastTime = HeroData.lastSaveTime or 0
    if lastTime <= 0 then return nil end

    local now = os.time()
    local elapsed = now - lastTime
    if elapsed < Config.IDLE_MIN_SECONDS then return nil end

    -- 特权增益 + 神裔降临：挂机时长上限
    local PrivilegeData = require("Game.PrivilegeData")
    local DivineBlessDB = require("Game.DivineBlessData")
    local maxSeconds = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds() + DivineBlessDB.GetBuffValue("idle_extra")
    local capped = math.min(elapsed, maxSeconds)
    local hours = capped / 3600

    -- 基于当前关卡实际战斗掉落推算
    local stage = HeroData.stats.bestStage or 1
    if stage < 1 then stage = 1 end
    local crystalPerStage, stonePerStage, ironPerStage = Config.EstimateStageDrop(stage)
    local stagesCleared = (capped / Config.IDLE_STAGE_SECONDS) * Config.IDLE_RATE

    -- 宝箱掉落计算
    local chestDrops = {}  -- { wood=N, bronze=N, ... }
    -- 阶梯掉落
    if Config.IDLE_CHEST_DROPS then
        for _, rule in ipairs(Config.IDLE_CHEST_DROPS) do
            if hours >= rule.minHours then
                for id, count in pairs(rule.chests) do
                    chestDrops[id] = (chestDrops[id] or 0) + count
                end
            end
        end
    end
    -- 随机掉落（每小时判定一次）
    if Config.IDLE_CHEST_RANDOM then
        local fullHours = math.floor(hours)
        for _, rule in ipairs(Config.IDLE_CHEST_RANDOM) do
            for _ = 1, fullHours do
                if math.random() < rule.chancePerHour then
                    chestDrops[rule.id] = (chestDrops[rule.id] or 0) + 1
                end
            end
        end
    end

    -- 随机碎片箱掉落（每小时判定一次，掉落碎片箱道具）
    local fragmentBoxDrops = {}  -- { [itemId] = count }
    if Config.IDLE_FRAGMENT_RANDOM then
        local fullHours = math.floor(hours)
        for _, rule in ipairs(Config.IDLE_FRAGMENT_RANDOM) do
            for _ = 1, fullHours do
                if math.random() < rule.chancePerHour then
                    fragmentBoxDrops[rule.id] = (fragmentBoxDrops[rule.id] or 0) + 1
                end
            end
        end
    end

    -- 基础收益
    local crystal = math.floor(crystalPerStage * stagesCleared)
    local stone   = math.floor(stonePerStage * stagesCleared)
    local iron    = math.floor(ironPerStage * stagesCleared)

    -- 特权增益：冥晶+10%
    crystal = math.floor(crystal * PrivilegeData.GetCrystalBonusRate())

    -- 特权增益：概率翻倍（可叠加）
    local doubled = false
    local doubleChance = PrivilegeData.GetDoubleChance()
    if doubleChance > 0 and math.random() < doubleChance then
        crystal = crystal * 2
        stone   = stone * 2
        iron    = iron * 2
        doubled = true
    end

    return {
        seconds = capped,
        nether_crystal = crystal,
        devour_stone = stone,
        forge_iron = iron,
        chestDrops = chestDrops,
        fragmentBoxDrops = fragmentBoxDrops,  -- { [itemId] = count }
        isOffline = true,
        doubled = doubled,  -- 是否触发了翻倍
    }
end

--- 领取挂机收益（发放到账户）
---@param rewards table  CalcIdleRewards 的返回值
function HeroData.ClaimIdleRewards(rewards)
    if not rewards then return end
    local Currency = require("Game.Currency")
    Currency.Add("nether_crystal", rewards.nether_crystal)
    Currency.Add("devour_stone", rewards.devour_stone)
    Currency.Add("forge_iron", rewards.forge_iron)

    -- 发放宝箱（神裔降临加成）
    if rewards.chestDrops then
        local ChestData = require("Game.ChestData")
        local DivineBlessDB = require("Game.DivineBlessData")
        local chestMulti = DivineBlessDB.GetBuffValue("chest_multi")
        local mult = (chestMulti > 1.0) and math.floor(chestMulti) or 1
        for id, count in pairs(rewards.chestDrops) do
            if count > 0 then
                ChestData.Add(id, count * mult)
                print("[HeroData] Idle chest drop: " .. id .. " x" .. count * mult)
            end
        end
        ChestData.Save()
    end

    -- 发放碎片箱道具到背包
    if rewards.fragmentBoxDrops then
        local InventoryData = require("Game.InventoryData")
        for itemId, count in pairs(rewards.fragmentBoxDrops) do
            if count > 0 then
                InventoryData.Add(itemId, count)
                print("[HeroData] Idle fragment box drop: " .. itemId .. " x" .. count)
            end
        end
    end

    -- 重置时间戳
    HeroData.lastSaveTime = os.time()
    HeroData.Save()
    print("[HeroData] Idle rewards claimed: crystal+" .. rewards.nether_crystal ..
          " stone+" .. rewards.devour_stone ..
          " iron+" .. rewards.forge_iron ..
          " fragBoxes+" .. (rewards.fragmentBoxDrops and next(rewards.fragmentBoxDrops) and "yes" or "0") ..
          " (" .. math.floor(rewards.seconds / 60) .. " min)")
end

-- ============================================================================
-- SaveRegistry 自注册
-- 核心数据（heroes/currencies/stats/deployed/recruitData）注册为 "_core"
-- order=1 确保最先初始化/恢复
-- ============================================================================
SaveRegistry.Register("_core", {
    group = "core",
    order = 1,
    spread = true,  -- 序列化结果展开到 saveData 顶层而非嵌套在 _core 下
    fieldGroups = {  -- 各字段对应的分片分组（供 SplitIntoGroups 使用）
        heroes = "core",
        deployed = "core",
        stats = "core",
        recruitData = "core",
        lastSaveTime = "core",
        currencies = "currency",
        redeemData = "meta_game",
    },
    initDefault = HeroData._InitCoreDefaults,
    migrate = HeroData._MigrateCore,
    serialize = HeroData._SerializeCore,
    deserialize = HeroData._DeserializeCore,
    validate = HeroData._ValidateCore,
})

return HeroData
