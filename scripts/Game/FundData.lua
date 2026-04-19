-- Game/FundData.lua
-- 基金商城数据模块 - 噬魂石基金 / 锻魂铁基金
-- 里程碑: 50, 100, 200, 300, ..., 6000 关
-- 每5个一组，需看5次广告解锁该组奖励，必须依次解锁

local Config = require("Game.Config")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")

local FundData = {}

-- ============================================================================
-- 基金定义
-- ============================================================================
FundData.FUNDS = {
    {
        id = "devour_stone",
        name = "噬魂石基金",
        currency = "devour_stone",
        -- 每组奖励: 388→588→888→1288→1788→2388→3088→3888，后续组维持3888
        groupRewards = { 388, 588, 888, 1288, 1788, 2388, 3088, 3888 },
    },
    {
        id = "forge_iron",
        name = "锻魂铁基金",
        currency = "forge_iron",
        -- 每组奖励: 688→988→1388→1888→2488→3188→3988→4888→5888，后续组维持5888
        groupRewards = { 688, 988, 1388, 1888, 2488, 3188, 3988, 4888, 5888 },
    },
}

FundData.GROUP_SIZE = 5
FundData.ADS_PER_GROUP = 5

-- ============================================================================
-- 里程碑关卡列表
-- ============================================================================
local function GenerateStages()
    local stages = { 50, 100 }
    for s = 200, 6000, 100 do
        stages[#stages + 1] = s
    end
    return stages
end

FundData.STAGES = GenerateStages()
FundData.TOTAL_MILESTONES = #FundData.STAGES
FundData.TOTAL_GROUPS = math.ceil(FundData.TOTAL_MILESTONES / FundData.GROUP_SIZE)

--- 获取某组的每个里程碑奖励数额
---@param fundDef table
---@param groupIndex number 组索引(1-based)
---@return number
function FundData.GetGroupReward(fundDef, groupIndex)
    local rewards = fundDef.groupRewards
    if groupIndex <= #rewards then
        return rewards[groupIndex]
    end
    -- 超出定义范围的组，使用最后一个值
    return rewards[#rewards]
end

--- 获取某里程碑的奖励数额
---@param fundDef table
---@param milestoneIndex number 里程碑索引(1-based)
---@return number
function FundData.GetMilestoneReward(fundDef, milestoneIndex)
    local groupIndex = math.ceil(milestoneIndex / FundData.GROUP_SIZE)
    return FundData.GetGroupReward(fundDef, groupIndex)
end

--- 获取基金累计总奖励
---@param fundDef table
---@return number
function FundData.GetTotalReward(fundDef)
    local total = 0
    for i = 1, FundData.TOTAL_GROUPS do
        local count = FundData.GROUP_SIZE
        -- 最后一组可能不满5个
        if i == FundData.TOTAL_GROUPS then
            count = FundData.TOTAL_MILESTONES - (FundData.TOTAL_GROUPS - 1) * FundData.GROUP_SIZE
        end
        total = total + FundData.GetGroupReward(fundDef, i) * count
    end
    return total
end

-- ============================================================================
-- 数据访问
-- ============================================================================
local function EnsureData()
    if not HeroData.activityData.fund then
        HeroData.activityData.fund = {}
    end
    return HeroData.activityData.fund
end

local function GetFundData(fundId)
    local data = EnsureData()
    if not data[fundId] then
        data[fundId] = {
            groupAds = {},   -- { [groupIndex] = adsWatched }
            claimed  = {},   -- { [milestoneIndex] = true }
        }
    end
    return data[fundId]
end

function FundData.Load()
    EnsureData()
end

function FundData.Save()
    HeroData.Save()
end

-- ============================================================================
-- 当前通关进度（连接实际游戏进度）
-- ============================================================================
function FundData.GetMaxStage()
    return HeroData.stats.bestStage or 0
end

-- ============================================================================
-- 组操作
-- ============================================================================
function FundData.GetGroupAds(fundId, groupIndex)
    local fd = GetFundData(fundId)
    return fd.groupAds[groupIndex] or 0
end

function FundData.IsGroupUnlocked(fundId, groupIndex)
    return FundData.GetGroupAds(fundId, groupIndex) >= FundData.ADS_PER_GROUP
end

function FundData.CanWatchAd(fundId, groupIndex)
    if FundData.IsGroupUnlocked(fundId, groupIndex) then return false end
    if groupIndex > 1 and not FundData.IsGroupUnlocked(fundId, groupIndex - 1) then
        return false
    end
    return true
end

function FundData.RecordAdWatch(fundId, groupIndex)
    if not FundData.CanWatchAd(fundId, groupIndex) then
        return false, "无法解锁"
    end
    local fd = GetFundData(fundId)
    fd.groupAds[groupIndex] = (fd.groupAds[groupIndex] or 0) + 1
    FundData.Save()
    return true
end

-- ============================================================================
-- 里程碑操作
-- ============================================================================
function FundData.IsClaimed(fundId, milestoneIndex)
    local fd = GetFundData(fundId)
    return fd.claimed[milestoneIndex] == true
end

function FundData.CanClaim(fundId, milestoneIndex)
    if milestoneIndex < 1 or milestoneIndex > FundData.TOTAL_MILESTONES then return false end
    local fd = GetFundData(fundId)
    if fd.claimed[milestoneIndex] then return false end
    local groupIndex = math.ceil(milestoneIndex / FundData.GROUP_SIZE)
    if not FundData.IsGroupUnlocked(fundId, groupIndex) then return false end
    local stage = FundData.STAGES[milestoneIndex]
    return FundData.GetMaxStage() >= stage
end

function FundData.Claim(fundId, milestoneIndex)
    if not FundData.CanClaim(fundId, milestoneIndex) then
        return false, "无法领取"
    end
    local fund
    for _, f in ipairs(FundData.FUNDS) do
        if f.id == fundId then fund = f; break end
    end
    if not fund then return false, "基金不存在" end

    local amount = FundData.GetMilestoneReward(fund, milestoneIndex)
    Currency.GrantReward({ type = "currency", id = fund.currency, amount = amount })

    local fd = GetFundData(fundId)
    fd.claimed[milestoneIndex] = true
    FundData.Save()

    local currName = Config.CURRENCY[fund.currency] and Config.CURRENCY[fund.currency].name or fund.currency
    local rewardDef = { type = "currency", id = fund.currency, amount = amount }
    return true, currName .. " ×" .. amount, rewardDef
end

--- 获取基金已领取总数
function FundData.GetClaimedCount(fundId)
    local fd = GetFundData(fundId)
    local count = 0
    for i = 1, FundData.TOTAL_MILESTONES do
        if fd.claimed[i] then count = count + 1 end
    end
    return count
end

return FundData
