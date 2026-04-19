-- Game/RecruitMilestoneData.lua
-- 招募周活动：累积招募次数达标领取奖励（自动发邮件）

local HeroData    = require("Game.HeroData")
local MailboxData = require("Game.MailboxData")
local SaveRegistry = require("Game.SaveRegistry")
local Toast       = require("Game.Toast")
local WAD         = require("Game.WeeklyActivityData")

local RMD = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 招募达标里程碑 { threshold, desc, rewards }
RMD.MILESTONES = {
    {
        threshold = 50,
        desc = "招募券自选包×10 随机UR碎片箱×10 朽木宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 10 },
            { type = "item",  id = "random_ur_shard_box",       amount = 10 },
            { type = "chest", id = "wood",                      amount = 10 },
        },
    },
    {
        threshold = 100,
        desc = "招募券自选包×10 随机UR碎片箱×20 青铜宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 10 },
            { type = "item",  id = "random_ur_shard_box",       amount = 20 },
            { type = "chest", id = "bronze",                    amount = 10 },
        },
    },
    {
        threshold = 200,
        desc = "招募券自选包×15 随机UR碎片箱×40 黄金宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 15 },
            { type = "item",  id = "random_ur_shard_box",       amount = 40 },
            { type = "chest", id = "gold",                      amount = 10 },
        },
    },
    {
        threshold = 300,
        desc = "招募券自选包×15 随机UR碎片箱×80 铂金宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 15 },
            { type = "item",  id = "random_ur_shard_box",       amount = 80 },
            { type = "chest", id = "platinum",                  amount = 10 },
        },
    },
    {
        threshold = 400,
        desc = "招募券自选包×20 自选UR碎片箱×80 钻石宝箱×10",
        rewards = {
            { type = "item",  id = "recruit_ticket_select_box", amount = 20 },
            { type = "item",  id = "ur_shard_box",              amount = 80 },
            { type = "chest", id = "diamond",                   amount = 10 },
        },
    },
}

--- 每轮上限（单轮最后一个里程碑阈值）
RMD.ROUND_MAX  = RMD.MILESTONES[#RMD.MILESTONES].threshold  -- 400
--- 最大轮数
RMD.MAX_ROUNDS = 4
--- 总上限（向后兼容）
RMD.MAX_THRESHOLD = RMD.ROUND_MAX * RMD.MAX_ROUNDS  -- 1600

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 若当前轮所有里程碑已领完，推进到下一轮（返回是否推进）
local function AdvanceRoundIfComplete(data)
    if data.round > RMD.MAX_ROUNDS then return false end
    for i = 1, #RMD.MILESTONES do
        if not data.claimed[i] then return false end
    end
    data.round   = data.round + 1
    data.claimed = {}
    print("[RecruitMilestone] Round completed! Now round " .. data.round)
    return true
end

---@return table
function RMD.EnsureData()
    if not HeroData.recruitMilestoneData then
        HeroData.recruitMilestoneData = {
            weekStart = WAD.GetCurrentWeekStart(),
            count     = 0,
            round     = 1,
            claimed   = {},
        }
    end
    local data = HeroData.recruitMilestoneData
    -- 兼容旧存档：补 round 字段
    if not data.round then
        data.round = 1
    end
    -- 每次读档都检查是否完成本轮但未推进（兼容旧存档 + 异常恢复）
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
        print("[RecruitMilestone] Week reset")
    end
end

--- 活动是否处于招募周
---@return boolean
function RMD.IsActive()
    return WAD.IsActive() and WAD.GetCurrentWeekType() == "recruit"
end

--- 获取当前累计招募次数（总量）
---@return number
function RMD.GetCount()
    local data = RMD.EnsureData()
    CheckWeekReset(data)
    return data.count
end

--- 获取当前轮数
---@return number
function RMD.GetRound()
    local data = RMD.EnsureData()
    CheckWeekReset(data)
    return data.round
end

--- 获取当前轮的有效次数（去掉前几轮已消耗的部分）
---@return number
function RMD.GetRoundCount()
    local data = RMD.EnsureData()
    CheckWeekReset(data)
    if data.round > RMD.MAX_ROUNDS then
        return RMD.ROUND_MAX
    end
    local offset = (data.round - 1) * RMD.ROUND_MAX
    return math.min(RMD.ROUND_MAX, math.max(0, data.count - offset))
end

-- ============================================================================
-- 招募计数（由 Tower.Summon 调用）
-- ============================================================================

---@param amount number
function RMD.AddCount(amount)
    -- 只在招募周计数
    if WAD.GetCurrentWeekType() ~= "recruit" then return end
    local data = RMD.EnsureData()
    CheckWeekReset(data)
    if data.round > RMD.MAX_ROUNDS then return end  -- 全部轮次已完成
    local maxTotal = RMD.MAX_ROUNDS * RMD.ROUND_MAX
    data.count = math.min(data.count + amount, maxTotal)
    RMD._AutoClaimToMailbox(data)
end

--- 自动将已达标未领取的里程碑奖励发放到邮件
---@param data table
function RMD._AutoClaimToMailbox(data)
    if data.round > RMD.MAX_ROUNDS then return end
    local anyClaimed = false
    local offset     = (data.round - 1) * RMD.ROUND_MAX
    local roundCount = math.max(0, data.count - offset)

    for i, milestone in ipairs(RMD.MILESTONES) do
        if roundCount >= milestone.threshold and not data.claimed[i] then
            data.claimed[i] = true
            anyClaimed = true
            MailboxData.Add({
                title = "招募达标奖励",
                desc  = milestone.threshold .. "次招募达标奖励（第" .. data.round .. "轮）",
                rewards = milestone.rewards,
            })
            Toast.Show("招募达标: " .. milestone.threshold .. "次! 奖励已发送到邮件", { 180, 140, 255 })
            print("[RecruitMilestone] Auto-claimed milestone " .. i .. ": " .. milestone.threshold)
        end
    end

    -- 无论本次是否有新领取，均检查是否完成本轮 → 进入下一轮
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
function RMD.GetMilestoneStatus(index)
    local data = RMD.EnsureData()
    CheckWeekReset(data)
    local milestone = RMD.MILESTONES[index]
    if not milestone then return false, false, false end
    local claimed    = data.claimed[index] or false
    local offset     = (data.round - 1) * RMD.ROUND_MAX
    local roundCount = math.max(0, data.count - offset)
    local reached    = roundCount >= milestone.threshold
    return reached and not claimed, claimed, reached
end

--- 是否有可领取奖励（红点）
---@return boolean
function RMD.HasClaimable()
    if not RMD.IsActive() then return false end
    local data = RMD.EnsureData()
    CheckWeekReset(data)
    if data.round > RMD.MAX_ROUNDS then return false end
    local offset     = (data.round - 1) * RMD.ROUND_MAX
    local roundCount = math.max(0, data.count - offset)
    for i, m in ipairs(RMD.MILESTONES) do
        if roundCount >= m.threshold and not (data.claimed[i] or false) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("recruitMilestoneData", {
    group = "meta_game",
    order = 72,
    serialize = function()
        return HeroData.recruitMilestoneData
    end,
    deserialize = function(saved, _saveData)
        HeroData.recruitMilestoneData = saved or nil
    end,
})

return RMD
