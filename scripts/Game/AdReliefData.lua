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
--- 里程碑配置：threshold = 解锁次数, rewards = 奖励列表
--- type: "currency" → Currency.Add, "item" → InventoryData.Add, "chest" → ChestData.Add
--- 减负中心不送免广券，改为挑战券/副本券/资源；看满20次自动激活当日免广卡
local MILESTONES = {
    { threshold = 3,  rewards = { { type = "item", id = "nether_crystal_pack", amount = 1 } } },
    { threshold = 6,  rewards = { { type = "item", id = "dungeon_ticket", amount = 1 } } },
    { threshold = 9,  rewards = { { type = "item", id = "nether_crystal_pack", amount = 4 } } },
    { threshold = 12, rewards = {
        { type = "item", id = "shadow_essence_bag", amount = 2 },
        { type = "item", id = "dungeon_ticket", amount = 1 },
    }},
    { threshold = 15, rewards = {
        { type = "currency", id = "devour_stone", amount = 3000 },
        { type = "item",     id = "dungeon_ticket", amount = 2 },
    }},
    { threshold = 17, rewards = {
        { type = "currency", id = "trial_ticket", amount = 3 },
        { type = "item",     id = "recruit_ticket_select_box", amount = 10 },
    }},
    { threshold = 20, rewards = {
        { type = "item", id = "boss_ticket", amount = 1 },
        { type = "item", id = "shadow_essence_bag", amount = 2 },
        { type = "item", id = "nether_crystal_pack", amount = 4 },
        { type = "item", id = "recruit_ticket_select_box", amount = 20 },
    }},
}
local AD_FREE_THRESHOLD = 20         -- 每日看满此数量自动激活免广卡
local STREAK_THRESHOLD = 3           -- 每日看广告>=3次才计入连续天数
local MAX_BONUS_HOURS = 3            -- 最大加速时长

-- ============================================================================
-- 辅助
-- ============================================================================

local TodayStr = require("Game.DateUtil").TodayStr
local YesterdayStr = require("Game.DateUtil").YesterdayStr

--- 获取/初始化持久化数据
---@return table
local function GetData()
    local d = HeroData.stats.adRelief
    if not d then
        d = {
            date = TodayStr(),
            todayAds = 0,
            milestonesClaimed = {},   -- string keys: ["1"]=true, ["2"]=true (避免cjson int/string歧义)
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
    for i, ms in ipairs(MILESTONES) do
        -- 昨日广告数达标 但 未领取
        if oldTodayAds >= ms.threshold and not d.milestonesClaimed[tostring(i)] then
            local mailRewards = {}
            for _, r in ipairs(ms.rewards) do
                mailRewards[#mailRewards + 1] = { type = r.type, id = r.id, amount = r.amount }
            end
            MailboxData.Add({
                title = "减负奖励补发",
                desc = "昨日看广告达" .. ms.threshold .. "次里程碑奖励自动发放",
                rewards = mailRewards,
            })
            print("[AdRelief] Auto-mail milestone " .. ms.threshold .. " from " .. oldDate)
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
---@return table[] { threshold, rewards, claimed, canClaim }
function ARD.GetMilestones()
    local d = GetData()
    DayRollover()
    local result = {}
    for i, ms in ipairs(MILESTONES) do
        local claimed = d.milestonesClaimed[tostring(i)] == true
        local canClaim = (not claimed) and (d.todayAds >= ms.threshold)
        result[#result + 1] = {
            threshold = ms.threshold,
            rewards = ms.rewards,
            claimed = claimed,
            canClaim = canClaim,
        }
    end
    return result
end

--- 领取里程碑奖励
---@param index number 里程碑索引
---@return boolean success
---@return table|nil rewards 实际发放的奖励列表
function ARD.ClaimMilestone(index)
    local d = GetData()
    DayRollover()
    local ms = MILESTONES[index]
    if not ms then return false end

    local key = tostring(index)
    if d.milestonesClaimed[key] then return false end  -- 已领取
    if d.todayAds < ms.threshold then return false end -- 未达标

    d.milestonesClaimed[key] = true

    -- 发放所有奖励（按 type 路由到正确的存储系统）
    local Currency = require("Game.Currency")
    for _, r in ipairs(ms.rewards) do
        Currency.GrantReward(r)
    end

    HeroData.Save()
    print("[AdRelief] ClaimMilestone " .. ms.threshold .. ": rewards=" .. #ms.rewards)
    return true, ms.rewards
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

--- 今日是否已激活免广卡（看满 AD_FREE_THRESHOLD 次自动激活）
---@return boolean
function ARD.IsAdFreeToday()
    local d = GetData()
    DayRollover()
    return (d.todayAds or 0) >= AD_FREE_THRESHOLD
end

--- 获取免广卡进度
---@return number current, number target
function ARD.GetAdFreeProgress()
    local d = GetData()
    DayRollover()
    return math.min(d.todayAds or 0, AD_FREE_THRESHOLD), AD_FREE_THRESHOLD
end

--- 获取当前加速时长（小时）
---@return number 1, 2, 或 3
function ARD.GetBonusHours()
    local d = GetData()
    DayRollover()
    -- 与 GetStreakDays 对齐：今天看满阈值时，用含今天的连续天数计算
    local streak = ARD.GetStreakDays()
    if streak >= 3 then
        return 3
    elseif streak >= 1 then
        return 2
    end
    return d.bonusHours or 1
end

--- 获取今日已看广告数
---@return number
function ARD.GetTodayAds()
    local d = GetData()
    DayRollover()
    return d.todayAds or 0
end

--- 获取连续天数（含今天：今天看满阈值次数则 +1）
---@return number
function ARD.GetStreakDays()
    local d = GetData()
    local base = d.streakDays or 0
    -- 今天已看满阈值，算入连续天数（跨天时才持久化，这里仅影响显示）
    if (d.todayAds or 0) >= STREAK_THRESHOLD then
        return base + 1
    end
    return base
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

            -- 迁移：将所有 int key 统一为 string key（修复 cjson 稀疏数组问题）
            local mc = d.milestonesClaimed
            local newMc = {}
            local needMigrate = false
            for k, v in pairs(mc) do
                if v == true then
                    local sk = tostring(k)  -- int key 或 string key 都统一为 string
                    newMc[sk] = true
                    if type(k) == "number" then needMigrate = true end
                end
            end
            if needMigrate then
                d.milestonesClaimed = newMc
                print("[AdRelief] Migrated milestonesClaimed int-keys to string-keys")
            end

            d.tickets = d.tickets or 0
            d.streakDays = d.streakDays or 0
            d.lastAdDate = d.lastAdDate or ""
            d.bonusHours = d.bonusHours or 1
        end
    end,

    validate = function()
        ARD.Init()

        -- 一次性修正：因里程碑重复领取 bug 导致的物资超发（只执行一次）
        local d = GetData()
        if not d._overCapFixed then
            local InventoryData = require("Game.InventoryData")
            local caps = {
                { getter = function() return ARD.GetTickets() end,
                  setter = function(v) d.tickets = v end,
                  cap = 32, name = "ad_ticket" },
                { getter = function() return InventoryData.GetCount("recruit_ticket_select_box") end,
                  setter = function(v)
                      for _, slot in ipairs(InventoryData.items or {}) do
                          if slot.id == "recruit_ticket_select_box" then slot.count = v; return end
                      end
                  end,
                  cap = 600, name = "recruit_ticket_select_box" },
                { getter = function() return InventoryData.GetCount("dungeon_ticket") end,
                  setter = function(v)
                      for _, slot in ipairs(InventoryData.items or {}) do
                          if slot.id == "dungeon_ticket" then slot.count = v; return end
                      end
                  end,
                  cap = 16, name = "dungeon_ticket" },
            }
            for _, c in ipairs(caps) do
                local cur = c.getter()
                if cur > c.cap then
                    print("[AdRelief] OverCap fix: " .. c.name .. " " .. cur .. " → " .. c.cap)
                    c.setter(c.cap)
                end
            end
            d._overCapFixed = true
            HeroData.Save()
            print("[AdRelief] OverCap check done (one-time)")
        end

        -- 一次性补偿：里程碑奖励写错存储导致玩家领了但没到账
        -- 条件：累计成功观看广告 > 20 次的玩家
        if not d._milestoneBugCompensated then
            local AdTracker = require("Game.AdTracker")
            local totalAds = AdTracker.GetTotalCount()
            if totalAds > 20 then
                local Currency = require("Game.Currency")
                local compensations = {
                    { type = "item",     id = "dungeon_ticket",            amount = 5 },
                    { type = "currency", id = "trial_ticket",             amount = 10 },
                    { type = "chest",    id = "platinum",                 amount = 5 },
                    { type = "item",     id = "recruit_ticket_select_box", amount = 15 },
                }
                for _, r in ipairs(compensations) do
                    Currency.GrantReward(r)
                end
                print("[AdRelief] Milestone bug compensation granted (totalAds=" .. totalAds .. "): dungeon_ticket×5, trial_ticket×10, platinum_chest×5, recruit_ticket_select_box×15")
            end
            d._milestoneBugCompensated = true
            HeroData.Save()
        end
    end,
})

return ARD
