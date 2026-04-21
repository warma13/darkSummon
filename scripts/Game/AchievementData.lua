-- Game/AchievementData.lua
-- 成就系统：一次性里程碑奖励（关卡进度 + 暗影君主升级 + 累积登录 + 排行榜名次）

local HeroData     = require("Game.HeroData")
local Currency     = require("Game.Currency")
local SaveRegistry = require("Game.SaveRegistry")

local AchievementData = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 关卡成就：每5关奖励暗影精粹（虚空契约已改为通关直发，此处不再重复）
local STAGE_INTERVAL = 5
local STAGE_REWARD   = { type = "currency", id = "shadow_essence", amount = 50 }

--- 暗影君主升级成就：每100级，100~6000级，奖励冥晶从1万到1000万
local LEVEL_INTERVAL = 100
local LEVEL_MIN      = 100
local LEVEL_MAX      = 6000
local LEVEL_REWARD_MIN = 10000      -- 1万
local LEVEL_REWARD_MAX = 10000000   -- 1000万

--- 累积登录成就：固定天数里程碑，奖励暗影精粹
local LOGIN_MILESTONES = {
    { days = 1,   reward = 100 },
    { days = 3,   reward = 500 },
    { days = 7,   reward = 1200 },
    { days = 15,  reward = 2500 },
    { days = 30,  reward = 6000 },
    { days = 60,  reward = 15000 },
    { days = 90,  reward = 30000 },
    { days = 120, reward = 70000 },
    { days = 150, reward = 150000 },
    { days = 365, reward = 400000 },
}

--- 排行榜名次成就（名次越小越好）：主线 + 试练塔共用里程碑配置
local RANK_MILESTONES = {
    { rank = 100, reward = 100 },
    { rank = 50,  reward = 500 },
    { rank = 20,  reward = 2000 },
    { rank = 10,  reward = 5000 },
    { rank = 5,   reward = 10000 },
    { rank = 1,   reward = 50000 },
}

--- 开启宝箱次数成就：奖励宝箱
local CHEST_MILESTONES = {
    { count = 10,    rewardId = "wood",     rewardAmt = 1 },
    { count = 100,   rewardId = "bronze",   rewardAmt = 5 },
    { count = 300,   rewardId = "bronze",   rewardAmt = 40 },
    { count = 1000,  rewardId = "gold",     rewardAmt = 20 },
    { count = 5000,  rewardId = "platinum", rewardAmt = 30 },
    { count = 10000, rewardId = "diamond",  rewardAmt = 40 },
}

--- 累积招募次数成就：奖励暗影精粹
local RECRUIT_MILESTONES = {
    { count = 10,    reward = 100 },
    { count = 100,   reward = 3000 },
    { count = 300,   reward = 6000 },
    { count = 1000,  reward = 20000 },
    { count = 10000, reward = 100000 },
}

--- 排行榜名次缓存（异步获取）
local _rankCache = {
    campaign = nil,   -- number|nil  我的主线排名
    tower    = nil,   -- number|nil  我的试练塔排名
    fetched  = false, -- 是否已发起过请求
}

-- ============================================================================
-- 工具
-- ============================================================================

--- 计算暗影君主升级里程碑的冥晶奖励
---@param level number 里程碑等级（100的倍数）
---@return number
local function CalcLevelReward(level)
    local t = (level - LEVEL_MIN) / (LEVEL_MAX - LEVEL_MIN)
    t = math.max(0, math.min(1, t))
    return math.floor(LEVEL_REWARD_MIN + (LEVEL_REWARD_MAX - LEVEL_REWARD_MIN) * t)
end

local function TodayStr()
    return os.date("%Y-%m-%d")
end

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 确保数据结构存在，并修正 DeepNormalizeIntKeys 问题
---@return table data
function AchievementData.EnsureData()
    if not HeroData.achievementData then
        HeroData.achievementData = {
            stageClaimed = {},  -- { ["5"]=true, ... }
            levelClaimed = {},  -- { ["100"]=true, ... }
            loginClaimed = {},  -- { ["1"]=true, ["3"]=true, ... }
            rankCampaignClaimed = {},  -- { ["100"]=true, ... } 主线排名
            rankTowerClaimed    = {},  -- { ["100"]=true, ... } 试练塔排名
            chestClaimed   = {},  -- { ["10"]=true, ... } 开宝箱次数
            recruitClaimed = {},  -- { ["10"]=true, ... } 招募次数
            totalLoginDays = 0,
            lastLoginDate  = "",
            totalChestOpened = 0,
            totalRecruitCount = 0,
        }
    end
    local d = HeroData.achievementData
    if d.stageClaimed == nil then d.stageClaimed = {} end
    if d.levelClaimed == nil then d.levelClaimed = {} end
    if d.loginClaimed == nil then d.loginClaimed = {} end
    if d.rankCampaignClaimed == nil then d.rankCampaignClaimed = {} end
    if d.rankTowerClaimed == nil then d.rankTowerClaimed = {} end
    if d.chestClaimed == nil then d.chestClaimed = {} end
    if d.recruitClaimed == nil then d.recruitClaimed = {} end
    if d.totalLoginDays == nil then d.totalLoginDays = 0 end
    if d.lastLoginDate == nil then d.lastLoginDate = "" end
    if d.totalChestOpened == nil then d.totalChestOpened = 0 end
    if d.totalRecruitCount == nil then d.totalRecruitCount = 0 end
    -- 兼容：DeepNormalizeIntKeys 将 "5"→5，需还原为字符串键
    local function fixKeys(tbl)
        local fixed = {}
        for k, v in pairs(tbl) do fixed[tostring(k)] = v end
        return fixed
    end
    d.stageClaimed = fixKeys(d.stageClaimed)
    d.levelClaimed = fixKeys(d.levelClaimed)
    d.loginClaimed = fixKeys(d.loginClaimed)
    d.rankCampaignClaimed = fixKeys(d.rankCampaignClaimed)
    d.rankTowerClaimed = fixKeys(d.rankTowerClaimed)
    d.chestClaimed = fixKeys(d.chestClaimed)
    d.recruitClaimed = fixKeys(d.recruitClaimed)
    return d
end

--- 每日登录计数（游戏启动时调用一次）
function AchievementData.MarkLogin()
    local data = AchievementData.EnsureData()
    local today = TodayStr()
    if data.lastLoginDate == today then return end  -- 今天已计过
    data.lastLoginDate = today
    data.totalLoginDays = (data.totalLoginDays or 0) + 1
    HeroData.Save()
    print("[Achievement] Login day " .. data.totalLoginDays .. " (" .. today .. ")")
end

--- 获取累积登录天数
---@return number
function AchievementData.GetTotalLoginDays()
    local data = AchievementData.EnsureData()
    return data.totalLoginDays or 0
end

-- ============================================================================
-- 关卡成就
-- ============================================================================

---@param stage number
---@return boolean canClaim, boolean claimed, boolean reached
function AchievementData.GetStageStatus(stage)
    local data = AchievementData.EnsureData()
    local claimed = data.stageClaimed[tostring(stage)] or false
    local bestStage = HeroData.stats and HeroData.stats.bestStage or 0
    local reached = bestStage >= stage
    return reached and not claimed, claimed, reached
end

---@param stage number
---@return boolean success, string msg
function AchievementData.ClaimStage(stage)
    local data = AchievementData.EnsureData()
    local key = tostring(stage)
    if data.stageClaimed[key] then return false, "已领取" end
    local bestStage = HeroData.stats and HeroData.stats.bestStage or 0
    if bestStage < stage then return false, "未达成（需通关第" .. stage .. "关）" end
    data.stageClaimed[key] = true
    Currency.Add(STAGE_REWARD.id, STAGE_REWARD.amount)
    HeroData.Save()
    print("[Achievement] Stage " .. stage .. " claimed: +" .. STAGE_REWARD.amount .. " " .. STAGE_REWARD.id)
    return true, "获得 暗影精粹x" .. STAGE_REWARD.amount
end

---@return number targetStage, boolean canClaim, boolean reached
function AchievementData.GetCurrentStageMilestone()
    local data = AchievementData.EnsureData()
    local bestStage = HeroData.stats and HeroData.stats.bestStage or 0
    for s = STAGE_INTERVAL, bestStage, STAGE_INTERVAL do
        if not data.stageClaimed[tostring(s)] then
            return s, true, true
        end
    end
    local nextStage = (math.floor(bestStage / STAGE_INTERVAL) + 1) * STAGE_INTERVAL
    return nextStage, false, false
end

-- ============================================================================
-- 暗影君主升级成就
-- ============================================================================

function AchievementData.GetLeaderLevel()
    return HeroData.GetLeaderLevel()
end

---@param level number
---@return boolean canClaim, boolean claimed, boolean reached
function AchievementData.GetLevelStatus(level)
    local data = AchievementData.EnsureData()
    local claimed = data.levelClaimed[tostring(level)] or false
    local curLevel = AchievementData.GetLeaderLevel()
    local reached = curLevel >= level
    return reached and not claimed, claimed, reached
end

---@param level number
---@return boolean success, string msg
function AchievementData.ClaimLevel(level)
    local data = AchievementData.EnsureData()
    local key = tostring(level)
    if data.levelClaimed[key] then return false, "已领取" end
    local curLevel = AchievementData.GetLeaderLevel()
    if curLevel < level then return false, "未达成（需达到" .. level .. "级）" end
    data.levelClaimed[key] = true
    local reward = CalcLevelReward(level)
    Currency.Add("nether_crystal", reward)
    HeroData.Save()
    print("[Achievement] Level " .. level .. " claimed: +" .. reward .. " nether_crystal")
    return true, "获得 冥晶x" .. reward
end

---@return number targetLevel, boolean canClaim, boolean reached, number reward
function AchievementData.GetCurrentLevelMilestone()
    local data = AchievementData.EnsureData()
    local curLevel = AchievementData.GetLeaderLevel()
    local maxClaimed = math.min(curLevel, LEVEL_MAX)
    for lv = LEVEL_MIN, maxClaimed, LEVEL_INTERVAL do
        if not data.levelClaimed[tostring(lv)] then
            return lv, true, true, CalcLevelReward(lv)
        end
    end
    local nextLevel = math.max(LEVEL_MIN, (math.floor(curLevel / LEVEL_INTERVAL) + 1) * LEVEL_INTERVAL)
    nextLevel = math.min(nextLevel, LEVEL_MAX)
    return nextLevel, false, false, CalcLevelReward(nextLevel)
end

-- ============================================================================
-- 累积登录成就
-- ============================================================================

---@param days number
---@return boolean canClaim, boolean claimed, boolean reached
function AchievementData.GetLoginStatus(days)
    local data = AchievementData.EnsureData()
    local claimed = data.loginClaimed[tostring(days)] or false
    local reached = data.totalLoginDays >= days
    return reached and not claimed, claimed, reached
end

---@param days number
---@return boolean success, string msg
function AchievementData.ClaimLogin(days)
    local data = AchievementData.EnsureData()
    local key = tostring(days)
    if data.loginClaimed[key] then return false, "已领取" end
    if data.totalLoginDays < days then return false, "未达成（需累积登录" .. days .. "天）" end
    data.loginClaimed[key] = true
    -- 查找对应奖励数量
    local reward = 0
    for _, m in ipairs(LOGIN_MILESTONES) do
        if m.days == days then reward = m.reward; break end
    end
    Currency.Add("shadow_essence", reward)
    HeroData.Save()
    print("[Achievement] Login " .. days .. "d claimed: +" .. reward .. " shadow_essence")
    return true, "获得 暗影精粹x" .. reward
end

--- 获取当前应显示的登录里程碑（第一个未领取的）
---@return number targetDays, boolean canClaim, boolean reached, number reward
function AchievementData.GetCurrentLoginMilestone()
    local data = AchievementData.EnsureData()
    for _, m in ipairs(LOGIN_MILESTONES) do
        if not data.loginClaimed[tostring(m.days)] then
            local reached = data.totalLoginDays >= m.days
            return m.days, reached, reached, m.reward
        end
    end
    -- 全部领完，显示最后一个
    local last = LOGIN_MILESTONES[#LOGIN_MILESTONES]
    return last.days, false, true, last.reward
end

-- ============================================================================
-- 排行榜名次成就（主线 + 试练塔）
-- ============================================================================

--- 异步获取排名并缓存（打开成就页时调用一次）
---@param onDone function|nil  两个排名都到位后的回调
function AchievementData.FetchRanks(onDone)
    if not clientCloud then
        if onDone then onDone() end
        return
    end
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if not ok then
        if onDone then onDone() end
        return
    end
    local pending = 2
    local function tick()
        pending = pending - 1
        if pending <= 0 and onDone then onDone() end
    end
    LB.FetchMyRank(LB.KEY_CAMPAIGN, function(rank, _score)
        _rankCache.campaign = rank  -- nil=未上榜
        print("[Achievement] campaign rank = " .. tostring(rank))
        tick()
    end)
    LB.FetchMyRank(LB.KEY_TOWER, function(rank, _score)
        _rankCache.tower = rank
        print("[Achievement] tower rank = " .. tostring(rank))
        tick()
    end)
    _rankCache.fetched = true
end

--- 获取缓存的排名
---@return number|nil campaignRank, number|nil towerRank
function AchievementData.GetCachedRanks()
    return _rankCache.campaign, _rankCache.tower
end

--- 通用：获取某排行榜的当前里程碑
---@param claimedTbl table  已领取表（rankCampaignClaimed / rankTowerClaimed）
---@param myRank number|nil 我的排名（nil=未上榜）
---@return number targetRank, boolean canClaim, boolean reached, number reward
local function _GetCurrentRankMilestone(claimedTbl, myRank)
    -- 里程碑从大到小（100→1），排名越小越好
    for _, m in ipairs(RANK_MILESTONES) do
        if not claimedTbl[tostring(m.rank)] then
            local reached = myRank ~= nil and myRank <= m.rank
            return m.rank, reached, reached, m.reward
        end
    end
    -- 全部领完
    local last = RANK_MILESTONES[#RANK_MILESTONES]
    return last.rank, false, true, last.reward
end

--- 通用：领取排行榜名次奖励
---@param claimedTbl table
---@param myRank number|nil
---@param targetRank number
---@param label string  显示用标签（"主线"/"试练塔"）
---@return boolean success, string msg
local function _ClaimRank(claimedTbl, myRank, targetRank, label)
    local key = tostring(targetRank)
    if claimedTbl[key] then return false, "已领取" end
    if not myRank or myRank > targetRank then
        return false, "未达成（需" .. label .. "排名前" .. targetRank .. "）"
    end
    claimedTbl[key] = true
    local reward = 0
    for _, m in ipairs(RANK_MILESTONES) do
        if m.rank == targetRank then reward = m.reward; break end
    end
    Currency.Add("shadow_essence", reward)
    HeroData.Save()
    print("[Achievement] " .. label .. " rank " .. targetRank .. " claimed: +" .. reward .. " shadow_essence")
    return true, "获得 暗影精粹x" .. reward
end

-- 主线排行榜
---@return number targetRank, boolean canClaim, boolean reached, number reward
function AchievementData.GetCurrentCampaignRankMilestone()
    local data = AchievementData.EnsureData()
    return _GetCurrentRankMilestone(data.rankCampaignClaimed, _rankCache.campaign)
end

---@param targetRank number
---@return boolean success, string msg
function AchievementData.ClaimCampaignRank(targetRank)
    local data = AchievementData.EnsureData()
    return _ClaimRank(data.rankCampaignClaimed, _rankCache.campaign, targetRank, "主线")
end

-- 试练塔排行榜
---@return number targetRank, boolean canClaim, boolean reached, number reward
function AchievementData.GetCurrentTowerRankMilestone()
    local data = AchievementData.EnsureData()
    return _GetCurrentRankMilestone(data.rankTowerClaimed, _rankCache.tower)
end

---@param targetRank number
---@return boolean success, string msg
function AchievementData.ClaimTowerRank(targetRank)
    local data = AchievementData.EnsureData()
    return _ClaimRank(data.rankTowerClaimed, _rankCache.tower, targetRank, "试练塔")
end

-- ============================================================================
-- 开启宝箱次数成就
-- ============================================================================

--- 增加累计开箱次数（由 ChestData.Open 调用）
---@param count number
function AchievementData.AddChestOpened(count)
    local data = AchievementData.EnsureData()
    data.totalChestOpened = (data.totalChestOpened or 0) + count
    HeroData.Save()
    print("[Achievement] totalChestOpened = " .. data.totalChestOpened)
end

--- 获取累计开箱次数
---@return number
function AchievementData.GetTotalChestOpened()
    local data = AchievementData.EnsureData()
    return data.totalChestOpened or 0
end

--- 获取当前应显示的开箱里程碑（第一个未领取的）
---@return number targetCount, boolean canClaim, boolean reached, string rewardId, number rewardAmt
function AchievementData.GetCurrentChestMilestone()
    local data = AchievementData.EnsureData()
    local total = data.totalChestOpened or 0
    for _, m in ipairs(CHEST_MILESTONES) do
        if not data.chestClaimed[tostring(m.count)] then
            local reached = total >= m.count
            return m.count, reached, reached, m.rewardId, m.rewardAmt
        end
    end
    -- 全部领完，显示最后一个
    local last = CHEST_MILESTONES[#CHEST_MILESTONES]
    return last.count, false, true, last.rewardId, last.rewardAmt
end

--- 领取开箱里程碑奖励（奖励是宝箱）
---@param targetCount number
---@return boolean success, string msg
function AchievementData.ClaimChest(targetCount)
    local data = AchievementData.EnsureData()
    local key = tostring(targetCount)
    if data.chestClaimed[key] then return false, "已领取" end
    local total = data.totalChestOpened or 0
    if total < targetCount then return false, "未达成（需开启" .. targetCount .. "次宝箱）" end
    data.chestClaimed[key] = true
    -- 查找对应奖励
    local rewardId, rewardAmt = "wood", 1
    for _, m in ipairs(CHEST_MILESTONES) do
        if m.count == targetCount then rewardId = m.rewardId; rewardAmt = m.rewardAmt; break end
    end
    -- 发放宝箱奖励
    local ok, ChestDataMod = pcall(require, "Game.ChestData")
    if ok and ChestDataMod then
        ChestDataMod.Add(rewardId, rewardAmt)
        ChestDataMod.Save()
    end
    HeroData.Save()
    print("[Achievement] Chest " .. targetCount .. " claimed: +" .. rewardAmt .. " " .. rewardId)
    return true, "获得 宝箱x" .. rewardAmt
end

-- ============================================================================
-- 累积招募次数成就
-- ============================================================================

--- 增加累计招募次数（由 GachaResult 调用）
---@param count number
function AchievementData.AddRecruitCount(count)
    local data = AchievementData.EnsureData()
    data.totalRecruitCount = (data.totalRecruitCount or 0) + count
    HeroData.Save()
    print("[Achievement] totalRecruitCount = " .. data.totalRecruitCount)
end

--- 获取累计招募次数
---@return number
function AchievementData.GetTotalRecruitCount()
    local data = AchievementData.EnsureData()
    return data.totalRecruitCount or 0
end

--- 获取当前应显示的招募里程碑（第一个未领取的）
---@return number targetCount, boolean canClaim, boolean reached, number reward
function AchievementData.GetCurrentRecruitMilestone()
    local data = AchievementData.EnsureData()
    local total = data.totalRecruitCount or 0
    for _, m in ipairs(RECRUIT_MILESTONES) do
        if not data.recruitClaimed[tostring(m.count)] then
            local reached = total >= m.count
            return m.count, reached, reached, m.reward
        end
    end
    -- 全部领完，显示最后一个
    local last = RECRUIT_MILESTONES[#RECRUIT_MILESTONES]
    return last.count, false, true, last.reward
end

--- 领取招募里程碑奖励（奖励是暗影精粹）
---@param targetCount number
---@return boolean success, string msg
function AchievementData.ClaimRecruit(targetCount)
    local data = AchievementData.EnsureData()
    local key = tostring(targetCount)
    if data.recruitClaimed[key] then return false, "已领取" end
    local total = data.totalRecruitCount or 0
    if total < targetCount then return false, "未达成（需招募" .. targetCount .. "次）" end
    data.recruitClaimed[key] = true
    -- 查找对应奖励
    local reward = 0
    for _, m in ipairs(RECRUIT_MILESTONES) do
        if m.count == targetCount then reward = m.reward; break end
    end
    Currency.Add("shadow_essence", reward)
    HeroData.Save()
    print("[Achievement] Recruit " .. targetCount .. " claimed: +" .. reward .. " shadow_essence")
    return true, "获得 暗影精粹x" .. reward
end

-- ============================================================================
-- 红点
-- ============================================================================

---@return boolean
function AchievementData.HasClaimable()
    local data = AchievementData.EnsureData()
    -- 关卡成就
    local bestStage = HeroData.stats and HeroData.stats.bestStage or 0
    for s = STAGE_INTERVAL, bestStage, STAGE_INTERVAL do
        if not data.stageClaimed[tostring(s)] then return true end
    end
    -- 暗影君主升级成就
    local curLevel = AchievementData.GetLeaderLevel()
    local maxCheck = math.min(curLevel, LEVEL_MAX)
    for lv = LEVEL_MIN, maxCheck, LEVEL_INTERVAL do
        if not data.levelClaimed[tostring(lv)] then return true end
    end
    -- 累积登录成就
    for _, m in ipairs(LOGIN_MILESTONES) do
        if data.totalLoginDays >= m.days and not data.loginClaimed[tostring(m.days)] then
            return true
        end
    end
    -- 排行榜名次成就（依赖缓存排名）
    if _rankCache.campaign then
        for _, m in ipairs(RANK_MILESTONES) do
            if _rankCache.campaign <= m.rank and not data.rankCampaignClaimed[tostring(m.rank)] then
                return true
            end
        end
    end
    if _rankCache.tower then
        for _, m in ipairs(RANK_MILESTONES) do
            if _rankCache.tower <= m.rank and not data.rankTowerClaimed[tostring(m.rank)] then
                return true
            end
        end
    end
    -- 开启宝箱次数成就
    local totalChest = data.totalChestOpened or 0
    for _, m in ipairs(CHEST_MILESTONES) do
        if totalChest >= m.count and not data.chestClaimed[tostring(m.count)] then
            return true
        end
    end
    -- 累积招募次数成就
    local totalRecruit = data.totalRecruitCount or 0
    for _, m in ipairs(RECRUIT_MILESTONES) do
        if totalRecruit >= m.count and not data.recruitClaimed[tostring(m.count)] then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("achievementData", {
    group = "meta_game",
    order = 74,
    serialize = function()
        return HeroData.achievementData
    end,
    deserialize = function(saved, _saveData)
        HeroData.achievementData = saved or nil
        -- 存档加载后自动标记今日登录
        AchievementData.MarkLogin()
    end,
})

return AchievementData
