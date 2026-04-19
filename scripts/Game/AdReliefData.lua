-- Game/AdReliefData.lua
-- 减负系统：免广告券里程碑 + 连续看广告加速增强
-- 每看3次广告获得1张免广告券，每日最多3张（需9次广告）
-- 未领取里程碑次日自动通过邮件发放
-- 连续看广告天数影响加速时长：1h / 2h / 3h

local HeroData     = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local ARD = {}

-- ============================================================================
-- 常量
-- ============================================================================
local MILESTONES = { 3, 6, 9 }       -- 每3次广告解锁1张券
local TICKET_PER_MILESTONE = 1       -- 每个里程碑给1张券
local STREAK_THRESHOLD = 3           -- 每日看广告>=3次才计入连续天数
local MAX_BONUS_HOURS = 3            -- 最大加速时长

-- ============================================================================
-- 辅助
-- ============================================================================

local function TodayStr()
    return os.date("%Y-%m-%d")
end

--- 获取昨天的日期字符串
local function YesterdayStr()
    return os.date("%Y-%m-%d", os.time() - 86400)
end

--- 获取/初始化持久化数据
---@return table
local function GetData()
    local d = HeroData.stats.adRelief
    if not d then
        d = {
            date = TodayStr(),
            todayAds = 0,
            milestonesClaimed = {},   -- int keys: [1]=true, [2]=true, [3]=true (对应MILESTONES索引)
            tickets = 0,             -- 免广告券余额（持久，不重置）
            streakDays = 0,          -- 连续看广告天数
            lastAdDate = "",         -- 上次看广告的日期
            bonusHours = 1,          -- 当前加速倍数 1/2/3
        }
        HeroData.stats.adRelief = d
    end
    return d
end

-- ============================================================================
-- 跨天处理
-- ============================================================================

--- 跨天滚动：发未领取邮件、更新streak/bonusHours、重置每日数据
local function DayRollover()
    local d = GetData()
    local today = TodayStr()
    if d.date == today then return end  -- 同一天，无需处理

    local oldDate = d.date
    local oldTodayAds = d.todayAds or 0

    -- 1. 未领取的里程碑自动通过邮件发放
    local MailboxData = require("Game.MailboxData")
    for i, threshold in ipairs(MILESTONES) do
        -- 昨日广告数达标 但 未领取
        if oldTodayAds >= threshold and not d.milestonesClaimed[i] then
            MailboxData.Add({
                title = "减负奖励补发",
                desc = "昨日看广告达" .. threshold .. "次里程碑奖励自动发放",
                rewards = {
                    { type = "currency", id = "ad_ticket", amount = TICKET_PER_MILESTONE },
                },
            })
            -- 直接加券（邮件领取时通过 Currency.GrantReward 发放，这里不加）
            print("[AdRelief] Auto-mail milestone " .. threshold .. " from " .. oldDate)
        end
    end

    -- 2. 更新连续天数和加速倍数
    local yesterday = YesterdayStr()
    if d.lastAdDate == yesterday and oldTodayAds >= STREAK_THRESHOLD then
        -- 昨天（即 oldDate）看了够多广告，连续天数+1
        d.streakDays = (d.streakDays or 0) + 1
    elseif d.lastAdDate ~= yesterday then
        -- 连续中断：bonusHours 减1（最低1）
        d.bonusHours = math.max(1, (d.bonusHours or 1) - 1)
        d.streakDays = 0
    end

    -- 3. 根据 streakDays 计算 bonusHours
    if d.streakDays >= 3 then
        d.bonusHours = 3
    elseif d.streakDays >= 1 then
        d.bonusHours = 2
    end
    -- streakDays == 0 时保持当前 bonusHours（可能被减到1）

    -- 4. 重置每日数据
    d.date = today
    d.todayAds = 0
    d.milestonesClaimed = {}

    HeroData.Save()
    print("[AdRelief] DayRollover: streak=" .. d.streakDays
        .. " bonusHours=" .. d.bonusHours
        .. " tickets=" .. d.tickets)
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 初始化（存档加载后调用）
function ARD.Init()
    local d = GetData()
    DayRollover()
    print("[AdRelief] Init: tickets=" .. d.tickets
        .. " todayAds=" .. d.todayAds
        .. " streak=" .. d.streakDays
        .. " bonusHours=" .. d.bonusHours)
end

--- 记录一次广告观看（由 AdTracker.Record hook 调用）
function ARD.OnAdWatched()
    local d = GetData()
    DayRollover()  -- 确保日期正确
    d.todayAds = (d.todayAds or 0) + 1
    d.lastAdDate = TodayStr()
    HeroData.Save()
    print("[AdRelief] OnAdWatched: todayAds=" .. d.todayAds)
end

--- 获取里程碑状态列表
---@return table[] { threshold, claimed, canClaim }
function ARD.GetMilestones()
    local d = GetData()
    DayRollover()
    local result = {}
    for i, threshold in ipairs(MILESTONES) do
        local claimed = d.milestonesClaimed[i] == true
        local canClaim = (not claimed) and (d.todayAds >= threshold)
        result[#result + 1] = {
            threshold = threshold,
            claimed = claimed,
            canClaim = canClaim,
        }
    end
    return result
end

--- 领取里程碑奖励
---@param index number 里程碑索引（1-3）
---@return boolean success
function ARD.ClaimMilestone(index)
    local d = GetData()
    DayRollover()
    local threshold = MILESTONES[index]
    if not threshold then return false end

    if d.milestonesClaimed[index] then return false end  -- 已领取
    if d.todayAds < threshold then return false end    -- 未达标

    d.milestonesClaimed[index] = true
    d.tickets = (d.tickets or 0) + TICKET_PER_MILESTONE
    HeroData.Save()
    print("[AdRelief] ClaimMilestone " .. threshold .. ": tickets=" .. d.tickets)
    return true
end

--- 获取免广告券余额
---@return number
function ARD.GetTickets()
    local d = GetData()
    return d.tickets or 0
end

--- 使用一张免广告券
---@return boolean success
function ARD.UseTicket()
    local d = GetData()
    if (d.tickets or 0) <= 0 then return false end
    d.tickets = d.tickets - 1
    HeroData.Save()
    print("[AdRelief] UseTicket: remaining=" .. d.tickets)
    return true
end

--- 添加免广告券（供 Currency.Add 路由使用）
---@param amount number
function ARD.AddTickets(amount)
    local d = GetData()
    d.tickets = (d.tickets or 0) + math.floor(amount)
    HeroData.Save()
end

--- 消耗免广告券（供 Currency.Spend 路由使用）
---@param amount number
---@return boolean
function ARD.SpendTickets(amount)
    local d = GetData()
    if (d.tickets or 0) < amount then return false end
    d.tickets = d.tickets - math.floor(amount)
    HeroData.Save()
    return true
end

--- 获取当前加速时长（小时）
---@return number 1, 2, 或 3
function ARD.GetBonusHours()
    local d = GetData()
    DayRollover()
    return d.bonusHours or 1
end

--- 获取今日已看广告数
---@return number
function ARD.GetTodayAds()
    local d = GetData()
    DayRollover()
    return d.todayAds or 0
end

--- 获取连续天数
---@return number
function ARD.GetStreakDays()
    local d = GetData()
    return d.streakDays or 0
end

--- 是否有可领取的里程碑
---@return boolean
function ARD.HasClaimable()
    local milestones = ARD.GetMilestones()
    for _, m in ipairs(milestones) do
        if m.canClaim then return true end
    end
    return false
end

-- ============================================================================
-- SaveRegistry 注册
-- ============================================================================
SaveRegistry.Register("adRelief", {
    group = "meta_game",
    order = 160,

    initDefault = function()
        HeroData.stats.adRelief = {
            date = TodayStr(),
            todayAds = 0,
            milestonesClaimed = {},
            tickets = 0,
            streakDays = 0,
            lastAdDate = "",
            bonusHours = 1,
        }
    end,

    serialize = function()
        return HeroData.stats.adRelief
    end,

    deserialize = function(saved)
        if saved then
            HeroData.stats.adRelief = saved
            -- 确保字段完整（旧存档迁移）
            local d = HeroData.stats.adRelief
            d.milestonesClaimed = d.milestonesClaimed or {}
            -- 迁移旧格式: 旧版用 threshold 值作 key (3,6,9)，新版用索引 (1,2,3)
            local mc = d.milestonesClaimed
            if mc[6] or mc[9] or (mc[3] and not mc[1] and not mc[2]) then
                local newMc = {}
                for i, threshold in ipairs(MILESTONES) do
                    if mc[threshold] then newMc[i] = true end
                end
                d.milestonesClaimed = newMc
                print("[AdRelief] Migrated milestonesClaimed from threshold-keys to index-keys")
            end
            d.tickets = d.tickets or 0
            d.streakDays = d.streakDays or 0
            d.lastAdDate = d.lastAdDate or ""
            d.bonusHours = d.bonusHours or 1
        end
    end,

    validate = function()
        ARD.Init()
    end,
})

return ARD
