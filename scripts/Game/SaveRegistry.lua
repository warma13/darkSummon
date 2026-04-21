-- Game/SaveRegistry.lua
-- 注册式模块化存档框架
-- 所有数据模块通过 Register() 自注册，由框架统一调度 init/serialize/deserialize
-- 消除 HeroData 作为"全局数据总线"的耦合，新增模块只需 1 处注册

local SafeTable = require("Game.SafeTable")

local SaveRegistry = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@class SaveModuleHandler
---@field key string           存档中的字段名（如 "chestData"）
---@field group string         所属分组: "core" | "currency" | "equip" | "meta_game"
---@field order number         初始化/恢复顺序（越小越先执行，默认 100）
---@field initDefault function 新玩家初始化: () -> void
---@field serialize function   序列化: () -> table|nil（返回要存入存档的数据）
---@field deserialize function 反序列化: (saved: table|nil) -> void
---@field validate function|nil 可选校验: () -> void（恢复后执行）
---@field migrate function|nil  可选迁移: (saveData: table) -> void（全量存档迁移）

---@type SaveModuleHandler[]
local modules = {}

--- 模块名 -> handler 映射（快速查找）
---@type table<string, SaveModuleHandler>
local moduleMap = {}

--- 是否已完成初始化/恢复
local initialized = false

--- 是否已执行模块预加载
local modulesLoaded = false

-- 存档版本号
local SAVE_VERSION = 2

-- ============================================================================
-- 模块预加载（确保所有数据模块的 Register 已执行）
-- ============================================================================

-- 所有需要自注册的数据模块路径（顺序不影响注册的 order 排序）
local DATA_MODULE_PATHS = {
    "Game.HeroData",
    "Game.ChestData",
    "Game.EquipData",
    "Game.RuneData",
    "Game.ActivityData",
    "Game.InventoryData",
    "Game.DailyTaskData",
    "Game.LaunchGiftData",
    "Game.WeeklyActivityData",
    "Game.MailboxData",
    "Game.WelfareData",
    "Game.ExchangeShopData",
    "Game.WorldBossData",
    "Game.LimitedBannerData",
    "Game.TrialTowerData",
    "Game.ResourceDungeonData",
    "Game.AdReliefData",
    "Game.CostumeSignInData",
    "Game.WeeklyPointsData",
    "Game.AchievementData",
}

--- 确保所有数据模块已加载（触发它们底部的 SaveRegistry.Register 调用）
--- 幂等：只在首次调用时实际执行 require
local function EnsureModulesLoaded()
    if modulesLoaded then return end
    modulesLoaded = true
    print("[SaveRegistry] EnsureModulesLoaded: loading " .. #DATA_MODULE_PATHS .. " data modules...")
    for _, path in ipairs(DATA_MODULE_PATHS) do
        local ok, err = pcall(require, path)
        if not ok then
            print("[SaveRegistry] ERROR loading '" .. path .. "': " .. tostring(err))
        end
    end
    print("[SaveRegistry] EnsureModulesLoaded: " .. #modules .. " modules registered")
end

-- ============================================================================
-- 注册 API
-- ============================================================================

--- 注册一个数据模块到存档系统
--- 在模块文件顶层 require 时调用，模块加载即注册
---@param key string 存档字段名（如 "chestData"、"equipData"）
---@param handler table { group, order?, initDefault, serialize, deserialize, validate?, migrate? }
function SaveRegistry.Register(key, handler)
    if moduleMap[key] then
        print("[SaveRegistry] WARNING: duplicate key '" .. key .. "', overwriting")
    end
    handler.key = key
    handler.order = handler.order or 100
    handler.group = handler.group or "meta_game"

    moduleMap[key] = handler

    -- 按 order 插入有序列表
    local inserted = false
    for i, m in ipairs(modules) do
        if handler.order < m.order then
            table.insert(modules, i, handler)
            inserted = true
            break
        end
    end
    if not inserted then
        modules[#modules + 1] = handler
    end

    print("[SaveRegistry] Registered '" .. key .. "' (group=" .. handler.group .. ", order=" .. handler.order .. ")")
end

-- ============================================================================
-- JSON 整数 key 修复（架构层统一处理）
-- ============================================================================
-- cjson 会将 Lua 整数 key（如 table[1]）编码为 JSON string key（"1"），
-- 解码后 table["1"] 与原始的 table[1] 不等价，导致业务逻辑查找失败。
-- 在 RestoreAll 入口处对整棵存档树做一次深度递归修复，
-- 所有模块的 deserialize 拿到的数据已经是规范化的，无需各自处理。

--- 递归将 table 中所有能转为整数的 string key 还原为 number key
---@param tbl any
---@return any
local function DeepNormalizeIntKeys(tbl)
    if type(tbl) ~= "table" then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        local nk = tonumber(k)
        -- 仅将整数形式的 string key（如 "1"、"42"）还原为 number
        -- 非整数（如 "1.5"）和非数字（如 "wood"）保持不变
        if nk and nk == math.floor(nk) then
            out[math.floor(nk)] = DeepNormalizeIntKeys(v)
        else
            out[k] = DeepNormalizeIntKeys(v)
        end
    end
    return out
end

-- ============================================================================
-- 生命周期 API（由 SlotSaveSystem 调用）
-- ============================================================================

--- 新玩家初始化：按 order 顺序调用所有模块的 initDefault
function SaveRegistry.InitAllDefaults()
    EnsureModulesLoaded()
    print("[SaveRegistry] InitAllDefaults: " .. #modules .. " modules")
    for _, m in ipairs(modules) do
        if m.initDefault then
            local ok, err = pcall(m.initDefault)
            if not ok then
                print("[SaveRegistry] ERROR initDefault '" .. m.key .. "': " .. tostring(err))
            end
        end
    end
    initialized = true
end

--- 从存档快照恢复所有模块数据
--- 按 order 顺序调用 deserialize，然后调用 validate
---@param saveData table 完整的存档数据（明文）
function SaveRegistry.RestoreAll(saveData)
    EnsureModulesLoaded()
    if not saveData then
        SaveRegistry.InitAllDefaults()
        return
    end

    print("[SaveRegistry] RestoreAll: " .. #modules .. " modules")

    -- 0. 统一修复 cjson 整数 key → string key 问题（一次性处理整棵树）
    saveData = DeepNormalizeIntKeys(saveData)

    -- 1. 全量迁移（按 order 顺序）
    for _, m in ipairs(modules) do
        if m.migrate then
            local ok, err = pcall(m.migrate, saveData)
            if not ok then
                print("[SaveRegistry] ERROR migrate '" .. m.key .. "': " .. tostring(err))
            end
        end
    end

    -- 2. 反序列化（按 order 顺序）
    for _, m in ipairs(modules) do
        if m.deserialize then
            local saved = saveData[m.key]
            local ok, err = pcall(m.deserialize, saved, saveData)
            if not ok then
                print("[SaveRegistry] ERROR deserialize '" .. m.key .. "': " .. tostring(err))
                -- 反序列化失败，回退到默认值
                if m.initDefault then
                    pcall(m.initDefault)
                end
            end
        end
    end

    -- 3. 校验（按 order 顺序）
    for _, m in ipairs(modules) do
        if m.validate then
            local ok, err = pcall(m.validate)
            if not ok then
                print("[SaveRegistry] ERROR validate '" .. m.key .. "': " .. tostring(err))
            end
        end
    end

    initialized = true
end

--- 收集所有模块数据为存档快照
---@return table saveData 完整存档数据
function SaveRegistry.SnapshotAll()
    EnsureModulesLoaded()
    local saveData = {
        saveVersion = SAVE_VERSION,
        lastSaveTime = os.time(),
    }

    for _, m in ipairs(modules) do
        if m.serialize then
            local ok, result = pcall(m.serialize)
            if ok and result ~= nil then
                if m.spread then
                    -- spread 模块：序列化结果展开到 saveData 顶层
                    for k, v in pairs(result) do
                        saveData[k] = v
                    end
                else
                    saveData[m.key] = result
                end
            elseif not ok then
                print("[SaveRegistry] ERROR serialize '" .. m.key .. "': " .. tostring(result))
            end
        end
    end

    return saveData
end

--- 按分组拆分存档数据（供 SlotSaveSystem 的云端分片使用）
---@param saveData table
---@return table groups { core={...}, currency={...}, equip={...}, meta_game={...} }
function SaveRegistry.SplitIntoGroups(saveData)
    EnsureModulesLoaded()
    local groups = {
        core = {},
        currency = {},
        equip = {},
        meta_game = {},
    }

    -- 分配注册模块的数据到对应分组
    for _, m in ipairs(modules) do
        if m.spread and m.fieldGroups then
            -- spread 模块：按 fieldGroups 映射分配各字段到不同分组
            for field, groupName in pairs(m.fieldGroups) do
                local value = saveData[field]
                if value ~= nil then
                    local g = groups[groupName]
                    if g then
                        g[field] = value
                    else
                        groups.meta_game[field] = value
                    end
                end
            end
        else
            local value = saveData[m.key]
            if value ~= nil then
                local g = groups[m.group]
                if g then
                    g[m.key] = value
                else
                    groups.meta_game[m.key] = value
                end
            end
        end
    end

    -- 保留顶层元数据到 core
    groups.core.saveVersion = saveData.saveVersion
    groups.core.lastSaveTime = saveData.lastSaveTime

    return groups
end

--- 将各组合并还原为完整 saveData
---@param groups table
---@return table saveData
function SaveRegistry.MergeGroups(groups)
    local data = {}
    for _, groupData in pairs(groups) do
        if type(groupData) == "table" then
            for k, v in pairs(groupData) do
                -- 后出现的覆盖先出现的（meta_game 中的 chestData 优先于 equip 中的旧兼容）
                data[k] = v
            end
        end
    end
    return data
end

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 获取已注册模块数量
---@return number
function SaveRegistry.GetModuleCount()
    return #modules
end

--- 获取所有已注册模块的 key 列表
---@return string[]
function SaveRegistry.GetModuleKeys()
    local keys = {}
    for _, m in ipairs(modules) do
        keys[#keys + 1] = m.key
    end
    return keys
end

--- 获取分组名列表
---@return string[]
function SaveRegistry.GetGroupNames()
    return { "core", "currency", "equip", "meta_game" }
end

--- 是否已完成初始化/恢复
---@return boolean
function SaveRegistry.IsInitialized()
    return initialized
end

--- 重置初始化状态（切换存档时调用）
function SaveRegistry.Reset()
    initialized = false
end

return SaveRegistry
