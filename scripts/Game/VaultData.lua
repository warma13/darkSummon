-- Game/VaultData.lua
-- 深渊金库数据模块
-- 总容量 6000，日存上限 2000，分段利率，自然日结算

local HeroData = require("Game.HeroData")
local Currency  = require("Game.Currency")
local TodayKey  = require("Game.DateUtil").TodayKey

local VaultData = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

VaultData.VAULT_CAP          = 6000    -- 金库总容量
VaultData.DAILY_LIMIT        = 2000    -- 每日存入上限
VaultData.MAX_ACCRUED_DAYS   = 2       -- 最多累积天数（超出停止计息）

--- 分段利率配置：每段最大 2000，利率为日收益率
VaultData.TIERS = {
    { cap = 2000, rate = 0.10 },   -- 0~2000：10%/天
    { cap = 2000, rate = 0.05 },   -- 2000~4000：5%/天
    { cap = 2000, rate = 0.01 },   -- 4000~6000：1%/天
}

-- ============================================================================
-- 内部工具
-- ============================================================================

local function TodayDay()
    -- 使用本地日期（与签到、免费抽等系统一致），午夜跨天，非 UTC 8:00
    return TodayKey()  -- e.g. "20260419"
end

--- 将 "YYYYMMDD" 字符串转为 Unix 时间戳（午夜 00:00:00）
local function DateStrToTs(dateStr)
    if not dateStr or type(dateStr) ~= "string" or #dateStr ~= 8 then return 0 end
    local y = tonumber(dateStr:sub(1, 4))
    local m = tonumber(dateStr:sub(5, 6))
    local d = tonumber(dateStr:sub(7, 8))
    if not y or not m or not d then return 0 end
    return os.time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0 })
end

--- 计算两个 "YYYYMMDD" 字符串之间的自然日差（toStr - fromStr）
--- 直接用时间戳差/86400，正确处理跨月、跨年
local function DaysBetween(fromStr, toStr)
    local t1 = DateStrToTs(fromStr)
    local t2 = DateStrToTs(toStr)
    if t1 == 0 or t2 == 0 then return 0 end
    return math.max(0, math.floor((t2 - t1) / 86400 + 0.5))
end

--- 按总量计算日利息（分段，向下取整）
local function TieredInterest(amount)
    if amount <= 0 then return 0 end
    local interest   = 0
    local remaining  = amount
    for _, tier in ipairs(VaultData.TIERS) do
        local portion = math.min(remaining, tier.cap)
        interest  = interest + portion * tier.rate
        remaining = remaining - portion
        if remaining <= 0 then break end
    end
    return math.floor(interest)
end

local function EnsureData()
    if not HeroData.activityData then HeroData.activityData = {} end
    local today = TodayDay()
    if not HeroData.activityData.vault then
        HeroData.activityData.vault = {
            totalDeposit    = 0,      -- 当前金库本金总量
            todayDeposited  = 0,      -- 今日已存入金额
            lastDepositDay  = 0,      -- 最后存入日序号
            withdrawnDay    = 0,      -- 取出的日序号（当日不可再存）
            pendingInterest = 0,      -- 待领利息
            lastSettledDay  = today,  -- 上次结算日（初始化为今天，防止空库计息）
            lastCollectDay  = 0,      -- 上次领取利息日（当日只能领一次）
        }
        HeroData.Save()
    end
    local v = HeroData.activityData.vault
    -- 字段缺失兼容（旧存档）
    if v.totalDeposit    == nil then v.totalDeposit    = 0      end
    if v.todayDeposited  == nil then v.todayDeposited  = 0      end
    if v.lastDepositDay  == nil then v.lastDepositDay  = 0      end
    if v.withdrawnDay    == nil then v.withdrawnDay    = 0      end
    if v.pendingInterest == nil then v.pendingInterest = 0      end
    if v.lastSettledDay  == nil then v.lastSettledDay  = today  end
    if v.lastCollectDay  == nil then v.lastCollectDay  = 0      end
    -- v1 迁移：日期字段从整数（UTC天序号）迁移为本地日期字符串
    -- lastSettledDay 重置为 today 避免误结算；其余重置为 "0" 表示"未操作"
    if type(v.lastSettledDay) == "number" then v.lastSettledDay = today end
    if type(v.lastDepositDay) == "number" then v.lastDepositDay = "0"   end
    if type(v.withdrawnDay)   == "number" then v.withdrawnDay   = "0"   end
    if type(v.lastCollectDay) == "number" then v.lastCollectDay = "0"   end

    -- v2 迁移：修复 v1 迁移中 lastSettledDay 被误设为 today 的问题
    -- 识别条件：有本金 + 存入日被清为"0"（v1 清掉了整数存入日）+ 待领利息为 0 + 结算日等于今天
    -- 这说明：玩家之前有存款，v1 迁移清掉了存入日和结算日，导致昨天的利息没有被结算
    -- 修复方式：把结算日回拨到昨天，下次 Settle() 就能正确补算昨天的利息
    if not v._vaultV2Ok then
        if v.totalDeposit > 0 and v.lastDepositDay == "0"
                and (v.pendingInterest or 0) == 0 and v.lastSettledDay == today then
            v.lastSettledDay = os.date("%Y%m%d", os.time() - 86400)
            print("[VaultData] v2 migration: roll back lastSettledDay to yesterday for interest catch-up")
        end
        v._vaultV2Ok = true
        HeroData.Save()
    end

    return v
end

function VaultData.Load()  EnsureData() end
function VaultData.Save()  HeroData.Save() end

-- ============================================================================
-- 结算（打开面板时调用）
-- ============================================================================

--- 按自然日结算利息
--- 计息基数 = totalDeposit 减去今日新存，即"昨日及之前已在金库的本金"
function VaultData.Settle()
    local v     = EnsureData()
    local today = TodayDay()
    if v.lastSettledDay >= today then return end

    local daysPassed = DaysBetween(v.lastSettledDay, today)
    local effective  = math.min(daysPassed, VaultData.MAX_ACCRUED_DAYS)

    if effective > 0 then
        -- 计息基数：总本金中排除今日存入部分
        local todayAmt   = (v.lastDepositDay == today) and (v.todayDeposited or 0) or 0
        local interestBase = v.totalDeposit - todayAmt
        if interestBase > 0 then
            v.pendingInterest = v.pendingInterest + TieredInterest(interestBase) * effective
        end
    end

    v.lastSettledDay = today
    VaultData.Save()
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 今日是否已存过（一天只能存一次）
---@return boolean
function VaultData.DepositedToday()
    local v = EnsureData()
    return v.lastDepositDay == TodayDay()
end

--- 今日可存入的最大金额（未存过才返回正数）
---@return number  0 表示不能存
function VaultData.GetMaxDeposit()
    local v     = EnsureData()
    local today = TodayDay()
    if v.withdrawnDay   == today then return 0 end  -- 当日取出不可再存
    if v.lastDepositDay == today then return 0 end  -- 一天只能存一次
    if v.totalDeposit   >= VaultData.VAULT_CAP then return 0 end
    return math.min(VaultData.DAILY_LIMIT, VaultData.VAULT_CAP - v.totalDeposit)
end

--- 今日是否可存入
---@return boolean
function VaultData.CanDeposit()
    return VaultData.GetMaxDeposit() > 0
end

--- 当前金库本金总量
---@return number
function VaultData.GetTotalDeposit()
    return EnsureData().totalDeposit
end

--- 今日已存入金额
---@return number
function VaultData.GetTodayDeposited()
    local v     = EnsureData()
    local today = TodayDay()
    return (v.lastDepositDay == today) and (v.todayDeposited or 0) or 0
end

--- 待领利息
---@return number
function VaultData.GetPendingInterest()
    return EnsureData().pendingInterest or 0
end

--- 今日预计日利息（以 settledBalance 即"已稳定计息的本金"为基准）
---@return number
function VaultData.GetDailyInterest()
    local v     = EnsureData()
    local today = TodayDay()
    local todayAmt = (v.lastDepositDay == today) and (v.todayDeposited or 0) or 0
    local base     = v.totalDeposit - todayAmt
    return TieredInterest(base)
end

--- 今日是否可领取利息（有利息 且 今日未领过 且 今日未存入）
---@return boolean
function VaultData.CanCollect()
    local v     = EnsureData()
    local today = TodayDay()
    if v.lastCollectDay  == today then return false end  -- 今日已领
    if v.lastDepositDay  == today then return false end  -- 当日存入不可领
    return (v.pendingInterest or 0) > 0
end

--- 今日是否已取出本金
---@return boolean
function VaultData.WithdrawnToday()
    return EnsureData().withdrawnDay == TodayDay()
end

--- 各分段当前占用量（用于 UI 显示）
--- 返回 { { used, cap, rate }, ... }
function VaultData.GetTierStatus()
    local total  = EnsureData().totalDeposit
    local result = {}
    local filled = 0
    for _, tier in ipairs(VaultData.TIERS) do
        local used = math.min(math.max(total - filled, 0), tier.cap)
        table.insert(result, { used = used, cap = tier.cap, rate = tier.rate })
        filled = filled + tier.cap
    end
    return result
end

-- ============================================================================
-- 存入
-- ============================================================================

---@param amount number  存入金额（正整数）
---@return boolean success
---@return string  msg
function VaultData.Deposit(amount)
    local v     = EnsureData()
    local today = TodayDay()

    if v.withdrawnDay == today then
        return false, "今日已取出，明日方可再存"
    end
    local maxDep = VaultData.GetMaxDeposit()
    if maxDep <= 0 then
        if v.totalDeposit >= VaultData.VAULT_CAP then
            return false, "金库已满（" .. VaultData.VAULT_CAP .. " 精粹）"
        end
        return false, "今日存入已达上限（" .. VaultData.DAILY_LIMIT .. " 精粹/天）"
    end

    amount = math.min(amount, maxDep)
    if not Currency.Spend("shadow_essence", amount) then
        return false, "暗影精粹不足（需要 " .. amount .. "）"
    end

    v.totalDeposit = v.totalDeposit + amount
    if v.lastDepositDay == today then
        v.todayDeposited = v.todayDeposited + amount
    else
        v.todayDeposited = amount
        v.lastDepositDay = today
    end
    VaultData.Save()
    return true, "存入 " .. amount .. " 暗影精粹"
end

-- ============================================================================
-- 领取利息
-- ============================================================================

---@return number  领取量（0 表示无法领取）
---@return string  提示
function VaultData.CollectInterest()
    local v     = EnsureData()
    local today = TodayDay()

    if v.lastCollectDay == today then
        return 0, "今日已领取，明日再来"
    end
    if v.lastDepositDay == today then
        return 0, "当日存入不可当日领取"
    end

    VaultData.Settle()
    v = EnsureData()

    local interest = v.pendingInterest or 0
    if interest <= 0 then
        return 0, "暂无可领取利息"
    end

    Currency.Add("shadow_essence", interest)
    v.pendingInterest = 0
    v.lastCollectDay  = today
    VaultData.Save()
    return interest, "领取利息 " .. interest .. " 暗影精粹"
end

-- ============================================================================
-- 取出本金
-- ============================================================================

--- 取出全部本金（利息保留，当日不可再存；当日存入不可当日取出）
---@return number  取出量
---@return string  提示
function VaultData.WithdrawAll()
    local v     = EnsureData()
    local today = TodayDay()

    if v.lastDepositDay == today then
        return 0, "当日存入不可当日取出，请明日再来"
    end

    VaultData.Settle()
    v = EnsureData()

    local principal = v.totalDeposit
    if principal <= 0 then
        return 0, "金库为空"
    end

    Currency.Add("shadow_essence", principal)
    v.totalDeposit   = 0
    v.todayDeposited = 0
    v.lastDepositDay = "0"   -- 保持字符串类型，避免下次 EnsureData 触发整数迁移
    v.withdrawnDay   = today          -- 当日不可再存
    v.lastSettledDay = today          -- 金库清空，重置结算基准
    VaultData.Save()
    return principal, "取出本金 " .. principal .. " 暗影精粹"
end

-- ============================================================================
-- 红点
-- ============================================================================

---@return boolean
function VaultData.HasPending()
    return VaultData.CanCollect()
end

return VaultData
