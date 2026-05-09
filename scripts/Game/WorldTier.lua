--- WorldTier.lua
--- 全局世界等级系统（类似暗黑4世界等级）
--- 提升怪物强度 → 提升奖励倍率，风险与回报并存

---@diagnostic disable-next-line: undefined-global
local cjson = cjson  -- 引擎内置全局变量

local WorldTier = {}

-- ============================================================================
-- 世界等级定义
-- ============================================================================
-- 每个等级: { id, name, color, desc, unlockStage,
--             hpMult, defMult, spdMult,         -- 怪物倍率
--             rewardMult, runeMult, dustMult }   -- 奖励倍率
WorldTier.TIERS = {
    {
        id = 1, name = "普通", color = { 180, 180, 180 },
        desc = "标准难度，适合推图探索",
        unlockStage = 1,
        hpMult = 1.0, defMult = 1.0, spdMult = 1.0,
        rewardMult = 1.0, runeMult = 1.0, dustMult = 1.0,
    },
    {
        id = 2, name = "困难", color = { 80, 180, 255 },
        desc = "怪物更强，奖励+30%",
        unlockStage = 500,
        hpMult = 2.0, defMult = 1.8, spdMult = 1.1,
        rewardMult = 1.3, runeMult = 1.2, dustMult = 1.3,
    },
    {
        id = 3, name = "噩梦", color = { 180, 100, 255 },
        desc = "恐怖强度，奖励+80%",
        unlockStage = 1500,
        hpMult = 5.0, defMult = 4.0, spdMult = 1.2,
        rewardMult = 1.8, runeMult = 1.5, dustMult = 1.8,
    },
    {
        id = 4, name = "炼狱", color = { 255, 140, 40 },
        desc = "极致考验，奖励+150%",
        unlockStage = 3000,
        hpMult = 12.0, defMult = 10.0, spdMult = 1.3,
        rewardMult = 2.5, runeMult = 2.0, dustMult = 2.5,
    },
    {
        id = 5, name = "深渊", color = { 255, 50, 50 },
        desc = "终极深渊，奖励+250%",
        unlockStage = 5000,
        hpMult = 30.0, defMult = 25.0, spdMult = 1.4,
        rewardMult = 3.5, runeMult = 3.0, dustMult = 3.5,
    },
}

-- ============================================================================
-- 状态
-- ============================================================================
local SETTINGS_FILE = "world_tier.json"
local currentTierId = 1

--- 当前世界等级定义
---@return table tier
function WorldTier.GetCurrent()
    return WorldTier.TIERS[currentTierId] or WorldTier.TIERS[1]
end

--- 当前世界等级 ID (1-5)
---@return number
function WorldTier.GetCurrentId()
    return currentTierId
end

-- ============================================================================
-- 倍率查询（给外部模块用的快捷接口）
-- ============================================================================

--- 怪物 HP 倍率
function WorldTier.GetHPMult()
    return WorldTier.GetCurrent().hpMult
end

--- 怪物 DEF 倍率
function WorldTier.GetDEFMult()
    return WorldTier.GetCurrent().defMult
end

--- 怪物速度倍率
function WorldTier.GetSpeedMult()
    return WorldTier.GetCurrent().spdMult
end

--- 通用奖励倍率（金币/材料/挂机收益）
function WorldTier.GetRewardMult()
    return WorldTier.GetCurrent().rewardMult
end

--- 符文掉率倍率
function WorldTier.GetRuneMult()
    return WorldTier.GetCurrent().runeMult
end

--- 符文尘倍率
function WorldTier.GetDustMult()
    return WorldTier.GetCurrent().dustMult
end

-- ============================================================================
-- 解锁判定
-- ============================================================================

--- 检查指定等级是否已解锁
---@param tierId number
---@param bestStage number 玩家最高通关关卡
---@return boolean
function WorldTier.IsUnlocked(tierId, bestStage)
    local tier = WorldTier.TIERS[tierId]
    if not tier then return false end
    return bestStage >= tier.unlockStage
end

--- 获取所有已解锁的等级列表
---@param bestStage number
---@return table[] 已解锁的 tier 列表
function WorldTier.GetUnlockedTiers(bestStage)
    local result = {}
    for _, tier in ipairs(WorldTier.TIERS) do
        if bestStage >= tier.unlockStage then
            result[#result + 1] = tier
        end
    end
    return result
end

-- ============================================================================
-- 设置 & 持久化
-- ============================================================================

--- 设置世界等级（需先检查解锁）
---@param tierId number
---@param bestStage number
---@return boolean success
function WorldTier.Set(tierId, bestStage)
    if not WorldTier.IsUnlocked(tierId, bestStage) then
        return false
    end
    currentTierId = tierId
    WorldTier.Save()
    -- 触发云端存档（WASM 环境本地文件不持久化，必须靠云端）
    local okSave, HeroData = pcall(require, "Game.HeroData")
    if okSave and HeroData and HeroData.Save then
        HeroData.Save()
    end
    return true
end

--- 加载存档
function WorldTier.Load()
    if not fileSystem:FileExists(SETTINGS_FILE) then return end
    local f = File:new(SETTINGS_FILE, FILE_READ)
    if f:IsOpen() then
        local content = f:ReadString()
        f:Close()
        local ok, data = pcall(cjson.decode, content)
        if ok and type(data) == "table" and data.tierId then
            local tid = math.max(1, math.min(#WorldTier.TIERS, data.tierId))
            currentTierId = tid
        end
    else
        f:Close()
    end
end

--- 保存存档
function WorldTier.Save()
    local f = File:new(SETTINGS_FILE, FILE_WRITE)
    if f:IsOpen() then
        local ok, json = pcall(cjson.encode, { tierId = currentTierId })
        if ok then f:WriteString(json) end
        f:Close()
    end
end

--- 初始化（游戏启动时调用）
function WorldTier.Init()
    WorldTier.Load()
    print("[WorldTier] Loaded tier=" .. currentTierId
        .. " (" .. WorldTier.GetCurrent().name .. ")"
        .. " hpMult=" .. WorldTier.GetHPMult()
        .. " rewardMult=" .. WorldTier.GetRewardMult())
end

-- ============================================================================
-- SaveRegistry 注册（云端持久化）
-- ============================================================================
local okReg, SaveRegistry = pcall(require, "Game.SaveRegistry")
if okReg and SaveRegistry and SaveRegistry.Register then
    SaveRegistry.Register("worldTier", {
        group = "core",
        order = 5,  -- 在大多数模块之前恢复
        initDefault = function()
            currentTierId = 1
        end,
        serialize = function()
            return { tierId = currentTierId }
        end,
        deserialize = function(saved)
            if saved and type(saved) == "table" and saved.tierId then
                currentTierId = math.max(1, math.min(#WorldTier.TIERS, saved.tierId))
            else
                currentTierId = 1
            end
            print("[WorldTier] Deserialized from cloud: tier=" .. currentTierId
                .. " (" .. WorldTier.GetCurrent().name .. ")")
        end,
    })
end

return WorldTier
