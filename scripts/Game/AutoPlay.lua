-- Game/AutoPlay.lua
-- 自动战斗系统：自动召唤/合成/布阵的开关、计时器、广告解锁
-- 开关跨局保留；计时器每局通过 ResetTimers() 重置（由 State.Reset 调用）

local AutoPlay = {}

-- ——— 开关（跨局持久，不随 Reset 清零） ———
AutoPlay.autoSummon = false
AutoPlay.autoMerge  = false
AutoPlay.autoDeploy = false

-- ——— 计时器（每局重置） ———
AutoPlay.autoSummonTimer = 0
AutoPlay.autoMergeTimer  = 0
AutoPlay.autoDeployTimer = 0

--- 每局开始时重置计时器（State.Reset 中调用）
function AutoPlay.ResetTimers()
    AutoPlay.autoSummonTimer = 0
    AutoPlay.autoMergeTimer  = 0
    AutoPlay.autoDeployTimer = 0
end

--- 检查今日是否已通过广告解锁指定自动功能
---@param key string "autoSummon" | "autoMerge" | "autoDeploy"
---@return boolean
function AutoPlay.IsUnlockedToday(key)
    local HeroData = require("Game.HeroData")
    local today = os.date("%Y-%m-%d")
    return HeroData.stats[key .. "AdDate"] == today
end

--- 记录今日已通过广告解锁指定自动功能
---@param key string "autoSummon" | "autoMerge" | "autoDeploy"
function AutoPlay.RecordAdUnlock(key)
    local HeroData = require("Game.HeroData")
    HeroData.stats[key .. "AdDate"] = os.date("%Y-%m-%d")
    HeroData.Save()
end

return AutoPlay
