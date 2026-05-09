-- Game/FeatureGate.lua
-- 功能关卡解锁系统：各功能按通关关卡数解锁

local HeroData = require("Game.HeroData")

local FeatureGate = {}

--- 功能解锁配置：功能名 → 需要通关的关卡数
FeatureGate.UNLOCK_STAGES = {
    auto_play       = 3,   -- 自动召唤/合成/布阵
    speed_boost     = 10,  -- x2加速
    recruit         = 2,   -- 招募
    idle            = 10,  -- 离线挂机
    activity        = 3,   -- 活动
    exchange        = 30,  -- 兑换（原文：通关第三十关）
    ad_relief       = 4,   -- 免广卡
    emerald_dungeon = 20,  -- 翠影秘境
    trial_tower     = 15,  -- 试练塔
    resource_dungeon = 20, -- 资源副本
    weekly_activity = 5,   -- 限时
    vault           = 30,  -- 金库
    costume         = 4,   -- 时装
    mini_game       = 10,  -- 小游戏
}

--- 获取玩家当前最高通关关卡
---@return number
function FeatureGate.GetBestStage()
    local best = 0
    if HeroData.stats and HeroData.stats.bestStage then
        best = HeroData.stats.bestStage
    end
    -- 当前所在关卡 - 1 = 已通关的关卡数（在第4关说明已通关3关）
    local ok, State = pcall(require, "Game.State")
    if ok and State then
        local cleared = (State.currentStage or 1) - 1
        if cleared > best then best = cleared end
    end
    return best
end

--- 判断指定功能是否已解锁
---@param featureKey string 功能名（对应 UNLOCK_STAGES 中的 key）
---@return boolean
function FeatureGate.IsUnlocked(featureKey)
    local required = FeatureGate.UNLOCK_STAGES[featureKey]
    if not required then return true end  -- 未配置的功能默认解锁
    return FeatureGate.GetBestStage() >= required
end

--- 获取功能解锁需要的关卡数
---@param featureKey string
---@return number
function FeatureGate.GetRequiredStage(featureKey)
    return FeatureGate.UNLOCK_STAGES[featureKey] or 0
end

--- 获取功能锁定提示文本
---@param featureKey string
---@return string
function FeatureGate.GetLockText(featureKey)
    local required = FeatureGate.UNLOCK_STAGES[featureKey]
    if not required then return "" end
    return "通关第" .. required .. "关解锁"
end

return FeatureGate
