-- Game/SpeedBoostData.lua
-- 战斗加速系统 —— 看广告获得 x3 加速时长
-- 时长持续流逝（即使不打开加速开关），每天最多看 MAX_ADS_PER_DAY 次广告

local HeroData = require("Game.HeroData")

local SB = {}

-- ============ 常量 ============
SB.BOOST_HOURS  = 1               -- 每次广告奖励小时数
SB.BOOST_SECS   = SB.BOOST_HOURS * 3600  -- 3600 秒
SB.MAX_ADS      = 12              -- 每日最多看广告次数
SB.SPEED_MULT   = 2               -- 加速倍率

-- ============ 运行时状态 ============
SB.remaining    = 0               -- 剩余加速秒数（实时递减）
SB.enabled      = false           -- 当前是否开启加速

-- ============ 辅助 ============

local TodayStr = require("Game.DateUtil").TodayStr

--- 获取存档数据（懒初始化）
---@return table { date:string, adsUsed:number, remaining:number, lastTs:number }
local function GetPersist()
    local d = HeroData.stats.speedBoost
    if not d then
        d = { date = TodayStr(), adsUsed = 0, remaining = 0, lastTs = os.time() }
        HeroData.stats.speedBoost = d
    end
    -- 跨天重置广告次数
    if d.date ~= TodayStr() then
        d.date = TodayStr()
        d.adsUsed = 0
    end
    return d
end

--- 初始化 / 从存档恢复（在存档加载后调用一次）
function SB.Init()
    local d = GetPersist()

    -- 计算离线流逝时间
    local now = os.time()
    local elapsed = now - (d.lastTs or now)
    if elapsed < 0 then elapsed = 0 end

    d.remaining = math.max(0, (d.remaining or 0) - elapsed)
    d.lastTs = now

    SB.remaining = d.remaining
    SB.enabled = (SB.remaining > 0)  -- 有时长就默认开启

    print("[SpeedBoost] Init: remaining=" .. string.format("%.0f", SB.remaining)
        .. "s, adsUsed=" .. d.adsUsed .. ", elapsed=" .. elapsed .. "s")
end

--- 每帧更新（在 HandleUpdate 中调用）
---@param dt number 原始时间步
function SB.Update(dt)
    if SB.remaining <= 0 then
        SB.remaining = 0
        SB.enabled = false
        return
    end

    -- 时长始终流逝
    SB.remaining = SB.remaining - dt
    if SB.remaining <= 0 then
        SB.remaining = 0
        SB.enabled = false
        print("[SpeedBoost] Expired")
    end

    -- 定期持久化（每 10 秒写一次，避免频繁 IO）
    if not SB._saveTimer then SB._saveTimer = 0 end
    SB._saveTimer = SB._saveTimer + dt
    if SB._saveTimer >= 10 then
        SB._saveTimer = 0
        SB.Save()
    end
end

--- 持久化到存档
function SB.Save()
    local d = GetPersist()
    d.remaining = SB.remaining
    d.lastTs = os.time()
end

--- 获取今日已看广告次数
---@return number
function SB.GetAdsUsed()
    return GetPersist().adsUsed
end

--- 今日是否还能看广告
---@return boolean
function SB.CanWatchAd()
    return SB.GetAdsUsed() < SB.MAX_ADS
end

--- 今日剩余可看广告次数
---@return number
function SB.GetAdsRemaining()
    return SB.MAX_ADS - SB.GetAdsUsed()
end

--- 看广告成功后调用 —— 增加时长
function SB.OnAdWatched()
    local d = GetPersist()
    d.adsUsed = d.adsUsed + 1
    -- 动态加速时长：根据减负系统的 bonusHours 决定
    local bonusSecs = SB.BOOST_SECS  -- 默认 1h
    local ok, ARD = pcall(require, "Game.AdReliefData")
    if ok and ARD and ARD.GetBonusHours then
        bonusSecs = ARD.GetBonusHours() * 3600
    end
    SB.remaining = SB.remaining + bonusSecs
    SB.enabled = true
    d.remaining = SB.remaining
    d.lastTs = os.time()
    HeroData.Save()
    print("[SpeedBoost] Ad watched! adsUsed=" .. d.adsUsed
        .. " remaining=" .. string.format("%.0f", SB.remaining) .. "s")
end

--- 获取当前应用的速度倍率
---@return number 1 或 SPEED_MULT
function SB.GetMultiplier()
    if SB.enabled and SB.remaining > 0 then
        return SB.SPEED_MULT
    end
    return 1
end

--- 格式化剩余时间为 "Xh Ym" 或 "Ym Zs"
---@return string
function SB.FormatRemaining()
    local s = math.floor(SB.remaining)
    if s <= 0 then return "0s" end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%dh%02dm", h, m)
    elseif m > 0 then
        return string.format("%dm%02ds", m, sec)
    else
        return string.format("%ds", sec)
    end
end

return SB
