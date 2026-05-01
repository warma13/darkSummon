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
LMD.END_DATE   = LaborDayData.END_DATE     -- "2026-05-08"

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

LMD.DAILY_CAP = 100   -- 每日通过途径获得的奖章上限

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
    daily_task      = { amount = 8,  label = "每日任务" },
    trial_tower     = { amount = 5,  label = "试炼塔" },
    chest_open      = { amount = 5,  label = "开启宝箱" },
    equip_enhance   = { amount = 3,  label = "装备强化" },
}
-- 途径每日合计: 5+8+8+10+8+10+3+15+12+8+5+5+3 = 100

-- ============================================================================
-- 累计里程碑配置（活动期间累计，一次性领取）
-- ============================================================================

LMD.MILESTONES = {
    {
        threshold = 50,
        desc = "暗影精粹×5000 + 锻魂铁×3000",
        rewards = {
            { type = "currency", id = "shadow_essence", amount = 5000 },
            { type = "currency", id = "forge_iron",     amount = 3000 },
        },
    },
    {
        threshold = 150,
        desc = "招募自选包×15 + 噬魂石×3000",
        rewards = {
            { type = "item",     id = "recruit_ticket_select_box", amount = 15 },
            { type = "currency", id = "devour_stone",              amount = 3000 },
        },
    },
    {
        threshold = 300,
        desc = "随机UR碎片箱×8 + 冥晶礼包×3",
        rewards = {
            { type = "item", id = "random_ur_shard_box", amount = 8 },
            { type = "item", id = "nether_crystal_pack", amount = 3 },
        },
    },
    {
        threshold = 500,
        desc = "深渊结晶×8 + 随机神话符文箱×2",
        rewards = {
            { type = "currency", id = "abyss_crystal",           amount = 8 },
            { type = "item",     id = "random_mythic_rune_box",  amount = 2 },
        },
    },
    {
        threshold = 700,
        desc = "万能UR碎片箱×3 + 劳动奖章×30",
        rewards = {
            { type = "item",     id = "ur_shard_box",  amount = 3 },
            { type = "currency", id = "labor_medal",   amount = 30 },
        },
    },
}
-- 7天满勤 100×7=700，阶梯: 50(1天) → 150(2天) → 300(3天) → 500(5天) → 700(7天满勤)

-- ============================================================================
-- 兑换商品配置
-- ============================================================================

LMD.SHOP_ITEMS = {
    -- ── 基础资源 ──
    {
        id = "medal_shadow_essence_x5000",
        name = "暗影精粹×5000",
        cost = 30,
        reward = { type = "currency", id = "shadow_essence", amount = 5000 },
        limit = 10,  -- 满购 300
    },
    {
        id = "medal_nether_crystal_pack_x3",
        name = "冥晶礼包×3",
        cost = 25,
        reward = { type = "item", id = "nether_crystal_pack", amount = 3 },
        limit = 8,   -- 满购 200
    },
    {
        id = "medal_devour_stone_x3000",
        name = "噬魂石×3000",
        cost = 25,
        reward = { type = "currency", id = "devour_stone", amount = 3000 },
        limit = 8,   -- 满购 200
    },
    {
        id = "medal_forge_iron_x3000",
        name = "锻魂铁×3000",
        cost = 25,
        reward = { type = "currency", id = "forge_iron", amount = 3000 },
        limit = 8,   -- 满购 200
    },
    -- ── 招募 ──
    {
        id = "medal_recruit_ticket_x20",
        name = "招募自选包×20",
        cost = 40,
        reward = { type = "item", id = "recruit_ticket_select_box", amount = 20 },
        limit = 8,   -- 满购 320
    },
    -- ── 符文 ──
    {
        id = "medal_abyss_crystal_x10",
        name = "深渊结晶×10",
        cost = 50,
        reward = { type = "currency", id = "abyss_crystal", amount = 10 },
        limit = 5,   -- 满购 250
    },
    {
        id = "medal_rift_dust_x500",
        name = "裂隙之尘×500",
        cost = 30,
        reward = { type = "currency", id = "rift_dust", amount = 500 },
        limit = 5,   -- 满购 150
    },
    {
        id = "medal_mythic_rune_x1",
        name = "随机神话符文箱×1",
        cost = 80,
        reward = { type = "item", id = "random_mythic_rune_box", amount = 1 },
        limit = 3,   -- 满购 240
    },
    -- ── 碎片/宝箱 ──
    {
        id = "medal_ur_shard_box_x10",
        name = "随机UR碎片箱×10",
        cost = 60,
        reward = { type = "item", id = "random_ur_shard_box", amount = 10 },
        limit = 5,   -- 满购 300
    },
    {
        id = "medal_diamond_chest_x5",
        name = "钻石宝箱×5",
        cost = 45,
        reward = { type = "chest", id = "diamond_chest", amount = 5 },
        limit = 5,   -- 满购 225
    },
    -- ── 高级 ──
    {
        id = "medal_universal_ur_shard_x3",
        name = "万能UR碎片箱×3",
        cost = 100,
        reward = { type = "item", id = "ur_shard_box", amount = 3 },
        limit = 3,   -- 满购 300
    },
    {
        id = "medal_relic_shard_x5",
        name = "随机遗物碎片箱×5",
        cost = 50,
        reward = { type = "item", id = "random_relic_shard_box", amount = 5 },
        limit = 5,   -- 满购 250
    },
    -- ── 票券 ──
    {
        id = "medal_dungeon_ticket_x3",
        name = "资源副本券×3",
        cost = 30,
        reward = { type = "currency", id = "dungeon_ticket", amount = 3 },
        limit = 5,   -- 满购 150
    },
    {
        id = "medal_trial_ticket_x5",
        name = "试练券×5",
        cost = 35,
        reward = { type = "currency", id = "trial_ticket", amount = 5 },
        limit = 3,   -- 满购 105
    },
    -- ── 技能书 ──
    {
        id = "medal_skill_book_3_x5",
        name = "高级技能书×5",
        cost = 40,
        reward = { type = "currency", id = "skill_book_3", amount = 5 },
        limit = 5,   -- 满购 200
    },
    -- ── 淬炼 ──
    {
        id = "medal_pale_jade_x30",
        name = "粹玉×30",
        cost = 35,
        reward = { type = "currency", id = "pale_jade", amount = 30 },
        limit = 5,   -- 满购 175
    },
    -- ── 时装 ──
    {
        id = "medal_weapon_magic_broom",
        name = "魔法扫帚(时装)",
        cost = 300,
        reward = { type = "costume", id = "weapon_magic_broom", amount = 1 },
        limit = 1,
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
            totalEarned = 0,          -- 活动期间累计获取总量
            dailyEarned = 0,          -- 今日获取量（每日重置，上限 DAILY_CAP）
            dailyDate   = "",         -- 今日日期标记，用于判断是否需要重置
            dailySources = {},        -- 今日已领取途径 { ["campaign"]=true, ... }
            milestoneClaimed = {},    -- 已领取 { [1]=true, ... }
            shopBought = {},          -- { ["medal_xxx"] = number, ... }
        }
    end
    -- 老存档迁移：补充新增字段
    local d = HeroData.laborMedalData
    if d.dailySources == nil then d.dailySources = {} end
    if d.dailyEarned  == nil then d.dailyEarned  = 0  end
    if d.dailyDate    == nil then d.dailyDate    = "" end
    return d
end

--- 检查每日重置（仅重置 dailyEarned，不影响累计数据/里程碑/商店）
---@param data table
function LMD._CheckDailyReset(data)
    local today = DateUtil.TodayStr()
    if (data.dailyDate or "") ~= today then
        data.dailyEarned  = 0
        data.dailyDate    = today
        data.dailySources = {}
    end
end

--- 获取今日获取量（仅展示用）
---@return number
function LMD.GetDailyEarned()
    local data = LMD.EnsureData()
    LMD._CheckDailyReset(data)
    return data.dailyEarned or 0
end

--- 查询某途径今日是否已领取奖章
---@param source string
---@return boolean
function LMD.IsSourceEarnedToday(source)
    local data = LMD.EnsureData()
    LMD._CheckDailyReset(data)
    return data.dailySources[source] == true
end

-- ============================================================================
-- 奖章产出（各玩法调用）
-- ============================================================================

--- 各玩法调用此函数产出奖章，内部检查活动状态
--- 每个途径每天只算一次，每日总上限 DAILY_CAP
---@param source string  产出来源 key（对应 SOURCES 表的 key）
---@return number amount  实际获得数量（0=不可领取）
function LMD.EarnMedals(source)
    if not LMD.IsActive() then return 0 end
    local cfg = LMD.SOURCES[source]
    if not cfg then return 0 end

    local data = LMD.EnsureData()
    LMD._CheckDailyReset(data)

    -- 该途径今日已领取
    if data.dailySources[source] then return 0 end
    -- 今日已达上限
    if (data.dailyEarned or 0) >= LMD.DAILY_CAP then return 0 end

    -- 实际获得量（受每日剩余额度限制）
    local remaining = LMD.DAILY_CAP - (data.dailyEarned or 0)
    local amount = math.min(cfg.amount, remaining)

    Currency.Add("labor_medal", amount)
    data.totalEarned = (data.totalEarned or 0) + amount
    data.dailyEarned = (data.dailyEarned or 0) + amount
    data.dailySources[source] = true

    -- 自动检查累计里程碑
    LMD._AutoClaimMilestones(data)

    HeroData.Save()
    return amount
end

-- ============================================================================
-- 累计里程碑系统
-- ============================================================================

--- 自动将已达标未领取的累计里程碑奖励发放到邮箱
---@param data table
function LMD._AutoClaimMilestones(data)
    local anyClaimed = false
    for i, milestone in ipairs(LMD.MILESTONES) do
        if data.totalEarned >= milestone.threshold and not data.milestoneClaimed[i] then
            data.milestoneClaimed[i] = true
            anyClaimed = true
            MailboxData.Add({
                title = "奖章里程碑",
                desc  = "累计获得" .. milestone.threshold .. "枚奖章达标奖励",
                rewards = milestone.rewards,
            })
            Toast.Show("里程碑达标: " .. milestone.threshold .. "枚! 奖励已发邮件", { 255, 160, 60 })
            print("[LaborMedal] Milestone " .. i .. " claimed: " .. milestone.threshold)
        end
    end
    if anyClaimed then
        HeroData.Save()
    end
end

--- 获取里程碑状态（基于累计获得量）
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

--- 获取活动累计获得总量
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
    -- 检查是否有未领取的已达标累计里程碑
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
