-- Game/LaborMedalData.lua
-- 劳动奖章收集活动数据模块
-- 活动期间各玩法额外产出劳动奖章，可兑换限定奖励 + 累计里程碑

local Currency     = require("Game.Currency")
local HeroData     = require("Game.HeroData")
local MailboxData  = require("Game.MailboxData")
local SaveRegistry = require("Game.SaveRegistry")
local Toast        = require("Game.Toast")
local DateUtil     = require("Game.DateUtil")
local LaborDayData = require("Game.LaborDayData")

local LMD = {}

-- ============================================================================
-- 活动时间（与劳动节签到共用）
-- ============================================================================

LMD.START_DATE = LaborDayData.START_DATE   -- "2026-05-01"
LMD.END_DATE   = LaborDayData.END_DATE     -- "2026-05-07"

--- 活动是否正在进行
---@return boolean
function LMD.IsActive()
    local today = DateUtil.TodayStr()
    return today >= LMD.START_DATE and today <= LMD.END_DATE
end

--- 活动是否已结束
---@return boolean
function LMD.IsExpired()
    return DateUtil.TodayStr() > LMD.END_DATE
end

-- ============================================================================
-- 奖章产出配置（各玩法每次获取量）
-- ============================================================================

LMD.SOURCES = {
    campaign        = { amount = 5,  label = "推图结算" },
    resource_dungeon = { amount = 8, label = "资源副本" },
    hatred_land     = { amount = 8,  label = "憎恨之地" },
    abyss_rift      = { amount = 10, label = "深渊裂隙" },
    emerald_dungeon = { amount = 8,  label = "翠影秘境" },
    world_boss      = { amount = 10, label = "世界BOSS" },
    rune_recast     = { amount = 3,  label = "符文重铸" },
    labor_signin    = { amount = 15, label = "劳动签到" },
    mine_dungeon    = { amount = 12, label = "矿洞寻宝" },
}

-- ============================================================================
-- 累计里程碑配置
-- ============================================================================

LMD.MILESTONES = {
    {
        threshold = 30,
        desc = "暗影精粹×800 + 锻魂铁×1500",
        rewards = {
            { type = "currency", id = "shadow_essence", amount = 800 },
            { type = "currency", id = "forge_iron",     amount = 1500 },
        },
    },
    {
        threshold = 80,
        desc = "招募券自选包×5 + 深渊结晶×5",
        rewards = {
            { type = "item",     id = "recruit_ticket_select_box", amount = 5 },
            { type = "currency", id = "abyss_crystal",             amount = 5 },
        },
    },
    {
        threshold = 150,
        desc = "随机UR碎片箱×10 + 暗影精粹×2000",
        rewards = {
            { type = "item",     id = "random_ur_shard_box", amount = 10 },
            { type = "currency", id = "shadow_essence",      amount = 2000 },
        },
    },
    {
        threshold = 250,
        desc = "万能UR碎片箱×5 + 随机神话符文箱×2",
        rewards = {
            { type = "item", id = "ur_shard_box",             amount = 5 },
            { type = "item", id = "random_mythic_rune_box",   amount = 2 },
        },
    },
    {
        threshold = 400,
        desc = "自选SSR碎片×80 + 限定称号「劳模」",
        rewards = {
            { type = "item",  id = "ssr_shard_select_box", amount = 80 },
            { type = "title", id = "title_labor_model" },
        },
    },
}

-- ============================================================================
-- 兑换商品配置
-- ============================================================================

LMD.SHOP_ITEMS = {
    {
        id = "medal_shadow_essence_x500",
        name = "暗影精粹×500",
        cost = 20,
        reward = { type = "currency", id = "shadow_essence", amount = 500 },
        limit = 10,
    },
    {
        id = "medal_recruit_ticket_x3",
        name = "招募券自选包×3",
        cost = 30,
        reward = { type = "item", id = "recruit_ticket_select_box", amount = 3 },
        limit = 3,
    },
    {
        id = "medal_abyss_crystal_x5",
        name = "深渊结晶×5",
        cost = 25,
        reward = { type = "currency", id = "abyss_crystal", amount = 5 },
        limit = 5,
    },
    {
        id = "medal_ur_shard_box_x1",
        name = "万能UR碎片箱×1",
        cost = 50,
        reward = { type = "item", id = "ur_shard_box", amount = 1 },
        limit = 3,
    },
    {
        id = "medal_mythic_rune_x1",
        name = "随机神话符文箱×1",
        cost = 60,
        reward = { type = "item", id = "random_mythic_rune_box", amount = 1 },
        limit = 2,
    },
    {
        id = "medal_ssr_shard_x20",
        name = "自选SSR碎片×20",
        cost = 40,
        reward = { type = "item", id = "ssr_shard_select_box", amount = 20 },
        limit = 5,
    },
}

-- ============================================================================
-- 数据存取
-- ============================================================================

--- 确保数据结构存在
---@return table
function LMD.EnsureData()
    if not HeroData.laborMedalData then
        HeroData.laborMedalData = {
            totalEarned = 0,          -- 累计获取总量（用于里程碑判定）
            milestoneClaimed = {},    -- { [1]=true, [2]=true, ... }
            shopBought = {},          -- { ["medal_xxx"] = number, ... }
        }
    end
    return HeroData.laborMedalData
end

-- ============================================================================
-- 奖章产出（各玩法调用）
-- ============================================================================

--- 各玩法调用此函数产出奖章，内部检查活动状态
---@param source string  产出来源 key（对应 SOURCES 表的 key）
---@return number amount  实际获得数量（0=活动未开启）
function LMD.EarnMedals(source)
    if not LMD.IsActive() then return 0 end
    local cfg = LMD.SOURCES[source]
    if not cfg then return 0 end

    local amount = cfg.amount
    Currency.Add("labor_medal", amount)

    local data = LMD.EnsureData()
    data.totalEarned = (data.totalEarned or 0) + amount

    -- 自动检查里程碑
    LMD._AutoClaimMilestones(data)

    HeroData.Save()
    return amount
end

-- ============================================================================
-- 里程碑系统
-- ============================================================================

--- 自动将已达标未领取的里程碑奖励发放到邮箱
---@param data table
function LMD._AutoClaimMilestones(data)
    local anyClaimed = false
    for i, milestone in ipairs(LMD.MILESTONES) do
        if data.totalEarned >= milestone.threshold and not data.milestoneClaimed[i] then
            data.milestoneClaimed[i] = true
            anyClaimed = true
            MailboxData.Add({
                title = "劳动奖章里程碑",
                desc  = "累计获得" .. milestone.threshold .. "枚奖章达标奖励",
                rewards = milestone.rewards,
            })
            Toast.Show("奖章里程碑达标: " .. milestone.threshold .. "枚! 奖励已发邮件", { 255, 160, 60 })
            print("[LaborMedal] Milestone " .. i .. " claimed: " .. milestone.threshold)
        end
    end
    if anyClaimed then
        HeroData.Save()
    end
end

--- 获取里程碑状态
---@param index number 1~5
---@return boolean canClaim, boolean claimed, boolean reached
function LMD.GetMilestoneStatus(index)
    local data = LMD.EnsureData()
    local milestone = LMD.MILESTONES[index]
    if not milestone then return false, false, false end
    local claimed = data.milestoneClaimed[index] or false
    local reached = data.totalEarned >= milestone.threshold
    return reached and not claimed, claimed, reached
end

--- 获取累计获得总量
---@return number
function LMD.GetTotalEarned()
    local data = LMD.EnsureData()
    return data.totalEarned or 0
end

-- ============================================================================
-- 兑换商店
-- ============================================================================

--- 获取已购买次数
---@param itemId string
---@return number
function LMD.GetBoughtCount(itemId)
    local data = LMD.EnsureData()
    return data.shopBought[itemId] or 0
end

--- 获取剩余可购买次数
---@param itemId string
---@return number
function LMD.GetRemaining(itemId)
    for _, item in ipairs(LMD.SHOP_ITEMS) do
        if item.id == itemId then
            return math.max(0, item.limit - LMD.GetBoughtCount(itemId))
        end
    end
    return 0
end

--- 执行兑换
---@param itemId string
---@return boolean success
---@return string msg
---@param itemId string
---@param qty? number  购买数量，默认1
---@return boolean ok, string msg, table|nil rewardDefs  成功时返回实际发放的奖励列表
function LMD.Purchase(itemId, qty)
    qty = qty or 1
    if qty < 1 then return false, "数量无效" end
    if not LMD.IsActive() then return false, "活动已结束" end

    local item
    for _, it in ipairs(LMD.SHOP_ITEMS) do
        if it.id == itemId then item = it; break end
    end
    if not item then return false, "商品不存在" end

    -- 检查限购
    local remaining = item.limit - LMD.GetBoughtCount(itemId)
    if remaining <= 0 then return false, "已达兑换上限" end
    if qty > remaining then return false, "超过剩余可兑换次数（剩余" .. remaining .. "）" end

    -- 检查奖章
    local totalCost = item.cost * qty
    if not Currency.Has("labor_medal", totalCost) then
        return false, "劳动奖章不足（需要" .. totalCost .. "）"
    end

    -- 扣费
    Currency.Spend("labor_medal", totalCost)

    -- 发放（按数量倍数）
    local rewardDefs = {}
    local r = item.reward
    local grantDef = { type = r.type, id = r.id, amount = r.amount * qty }
    Currency.GrantReward(grantDef, "LaborMedalShop")
    rewardDefs[#rewardDefs + 1] = grantDef

    -- 记录
    local data = LMD.EnsureData()
    data.shopBought[itemId] = (data.shopBought[itemId] or 0) + qty

    HeroData.Save(true)
    return true, "兑换成功！", rewardDefs
end

-- ============================================================================
-- 红点判断
-- ============================================================================

--- 是否有可操作项（里程碑可自动领取 → 主要看商店是否买得起）
---@return boolean
function LMD.HasClaimable()
    if not LMD.IsActive() then return false end
    -- 检查是否有未领取的已达标里程碑
    local data = LMD.EnsureData()
    for i, m in ipairs(LMD.MILESTONES) do
        if data.totalEarned >= m.threshold and not data.milestoneClaimed[i] then
            return true
        end
    end
    -- 检查商店是否有可购买项
    local balance = Currency.Get("labor_medal")
    for _, item in ipairs(LMD.SHOP_ITEMS) do
        if balance >= item.cost and LMD.GetRemaining(item.id) > 0 then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("laborMedalData", {
    group = "meta_game",
    order = 76,
    serialize = function()
        return HeroData.laborMedalData
    end,
    deserialize = function(saved, _saveData)
        HeroData.laborMedalData = saved or nil
    end,
})

return LMD
