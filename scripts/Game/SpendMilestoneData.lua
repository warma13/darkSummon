-- Game/SpendMilestoneData.lua
-- 消费周活动：累积消费暗影精粹达标领取奖励（自动发邮件）

local HeroData     = require("Game.HeroData")
local MailboxData  = require("Game.MailboxData")
local SaveRegistry = require("Game.SaveRegistry")
local Toast        = require("Game.Toast")
local WAD          = require("Game.WeeklyActivityData")

local SMD = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 消费达标里程碑 { threshold, desc, rewards }
SMD.MILESTONES = {
    {
        threshold = 5000,
        desc = "招募券自选包×10 随机UR碎片箱×10 朽木宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 10 },
            { type = "item",  id = "random_ur_shard_box",       amount = 10 },
            { type = "chest", id = "wood",                      amount = 10 },
        },
    },
    {
        threshold = 15000,
        desc = "招募券自选包×10 随机UR碎片箱×20 青铜宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 10 },
            { type = "item",  id = "random_ur_shard_box",       amount = 20 },
            { type = "chest", id = "bronze",                    amount = 10 },
        },
    },
    {
        threshold = 30000,
        desc = "招募券自选包×15 随机UR碎片箱×40 黄金宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 15 },
            { type = "item",  id = "random_ur_shard_box",       amount = 40 },
            { type = "chest", id = "gold",                      amount = 10 },
        },
    },
    {
        threshold = 50000,
        desc = "招募券自选包×15 随机UR碎片箱×80 铂金宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 15 },
            { type = "item",  id = "random_ur_shard_box",       amount = 80 },
            { type = "chest", id = "platinum",                  amount = 10 },
        },
    },
    {
        threshold = 80000,
        desc = "招募券自选包×20 自选UR碎片箱×80 钻石宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 20 },
            { type = "item",  id = "ur_shard_box",              amount = 80 },
            { type = "chest", id = "diamond",                   amount = 10 },
        },
    },
}

--- 每轮上限
SMD.ROUND_MAX  = SMD.MILESTONES[#SMD.MILESTONES].threshold  -- 80000
--- 最大轮数
SMD.MAX_ROUNDS = 4
--- 总上限
SMD.MAX_THRESHOLD = SMD.ROUND_MAX * SMD.MAX_ROUNDS

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 若当前轮所有里程碑已领完，推进到下一轮
local function AdvanceRoundIfComplete(data)
    if data.round > SMD.MAX_ROUNDS then return false end
    for i = 1, #SMD.MILESTONES do
        if not data.claimed[i] then return false end
    end
    data.round   = data.round + 1
    data.claimed = {}
    print("[SpendMilestone] Round completed! Now round " .. data.round)
    return true
end

---@return table
function SMD.EnsureData()
    if not HeroData.spendMilestoneData then
        HeroData.spendMilestoneData = {
            weekStart = WAD.GetCurrentWeekStart(),
            count     = 0,
            round     = 1,
            claimed   = {},
        }
    end
    local data = HeroData.spendMilestoneData
    if not data.round then
        data.round = 1
    end
    if AdvanceRoundIfComplete(data) then
        HeroData.Save()
    end
    return data
end

--- 检查是否需要周重置
local function CheckWeekReset(data)
    local expected = WAD.GetCurrentWeekStart()
    if data.weekStart ~= expected then
        data.weekStart = expected
        data.count     = 0
        data.round     = 1
        data.claimed   = {}
        print("[SpendMilestone] Week reset")
    end
end

--- 活动是否处于活跃状态（始终活跃，不区分周类型）
---@return boolean
function SMD.IsActive()
    return WAD.IsActive()
end

--- 获取当前累计消费量
---@return number
function SMD.GetCount()
    local data = SMD.EnsureData()
    CheckWeekReset(data)
    return data.count
end

--- 获取当前轮数
---@return number
function SMD.GetRound()
    local data = SMD.EnsureData()
    CheckWeekReset(data)
    return data.round
end

--- 获取当前轮的有效消费量
---@return number
function SMD.GetRoundCount()
    local data = SMD.EnsureData()
    CheckWeekReset(data)
    if data.round > SMD.MAX_ROUNDS then
        return SMD.ROUND_MAX
    end
    local offset = (data.round - 1) * SMD.ROUND_MAX
    return math.min(SMD.ROUND_MAX, math.max(0, data.count - offset))
end

-- ============================================================================
-- 消费计数（由 EventBus CURRENCY_CHANGED 事件触发）
-- ============================================================================

---@param amount number  消费的暗影精粹数量（正数）
function SMD.AddCount(amount)
    if not WAD.IsActive() then return end
    local data = SMD.EnsureData()
    CheckWeekReset(data)
    if data.round > SMD.MAX_ROUNDS then return end
    local maxTotal = SMD.MAX_ROUNDS * SMD.ROUND_MAX
    data.count = math.min(data.count + amount, maxTotal)
    SMD._AutoClaimToMailbox(data)
end

--- 自动将已达标未领取的里程碑奖励发放到邮件
---@param data table
function SMD._AutoClaimToMailbox(data)
    if data.round > SMD.MAX_ROUNDS then return end
    local anyClaimed = false
    local offset     = (data.round - 1) * SMD.ROUND_MAX
    local roundCount = math.max(0, data.count - offset)

    for i, milestone in ipairs(SMD.MILESTONES) do
        if roundCount >= milestone.threshold and not data.claimed[i] then
            data.claimed[i] = true
            anyClaimed = true
            MailboxData.Add({
                title = "消费达标奖励",
                desc  = milestone.threshold .. "暗影精粹消费达标奖励（第" .. data.round .. "轮）",
                rewards = milestone.rewards,
            })
            Toast.Show("消费达标: " .. milestone.threshold .. "暗影精粹! 奖励已发邮件", { 180, 140, 255 })
            print("[SpendMilestone] Auto-claimed milestone " .. i .. ": " .. milestone.threshold)
        end
    end

    local advanced = AdvanceRoundIfComplete(data)
    if anyClaimed or advanced then
        HeroData.Save()
    end
end

-- ============================================================================
-- 状态查询
-- ============================================================================

---@param index number
---@return boolean canClaim, boolean claimed, boolean reached
function SMD.GetMilestoneStatus(index)
    local data = SMD.EnsureData()
    CheckWeekReset(data)
    local milestone = SMD.MILESTONES[index]
    if not milestone then return false, false, false end
    local claimed    = data.claimed[index] or false
    local offset     = (data.round - 1) * SMD.ROUND_MAX
    local roundCount = math.max(0, data.count - offset)
    local reached    = roundCount >= milestone.threshold
    return reached and not claimed, claimed, reached
end

--- 是否有可领取奖励（红点）
---@return boolean
function SMD.HasClaimable()
    if not SMD.IsActive() then return false end
    local data = SMD.EnsureData()
    CheckWeekReset(data)
    if data.round > SMD.MAX_ROUNDS then return false end
    local offset     = (data.round - 1) * SMD.ROUND_MAX
    local roundCount = math.max(0, data.count - offset)
    for i, m in ipairs(SMD.MILESTONES) do
        if roundCount >= m.threshold and not (data.claimed[i] or false) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("spendMilestoneData", {
    group = "meta_game",
    order = 73,
    serialize = function()
        return HeroData.spendMilestoneData
    end,
    deserialize = function(saved, _saveData)
        HeroData.spendMilestoneData = saved or nil
    end,
})

return SMD
