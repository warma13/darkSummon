-- Game/SafeTable.lua
-- 内存值混淆代理表（反 GameGuardian 等内存搜索工具）
--
-- 原理：在内存中不存储明文数值，而是存储经过 XOR + 偏移变换的混淆值。
-- 每次游戏启动随机生成密钥，使得同一数值在不同会话中的内存表示不同。
-- 对外接口完全透明：proxy.forge_iron = 500 / print(proxy.forge_iron) 照常使用。
--
-- Create()     — 浅层混淆，适用于纯数值平铺表（currencies, stats）
-- CreateDeep() — 递归混淆，子 table 自动包装（heroes, equipData, chestData）

local SafeTable = {}

-- ============================================================================
-- Create: 浅层混淆（不处理子 table，子 table 原样存储）
-- ============================================================================

--- 创建浅层混淆代理表
---@param initialData? table  初始明文数据
---@return table proxy  代理表（读写透明）
---@return fun():table snapshot  获取明文快照（用于存档）
function SafeTable.Create(initialData)
    local sessionKey = math.random(100000, 999999)
    local salt = math.random(10000, 99999)

    local storage = {}     -- key -> 混淆后的数值
    local plainStore = {}  -- key -> 非数值（string/bool/table）

    local function encode(v)
        return (math.floor(v) + salt) ~ sessionKey
    end

    local function decode(v)
        return (v ~ sessionKey) - salt
    end

    local proxy = {}
    local mt = {
        __index = function(_, k)
            if plainStore[k] ~= nil then return plainStore[k] end
            local raw = storage[k]
            if raw == nil then return nil end
            return decode(raw)
        end,

        __newindex = function(_, k, v)
            if v == nil then
                storage[k] = nil
                plainStore[k] = nil
                return
            end
            if type(v) == "number" then
                plainStore[k] = nil
                storage[k] = encode(v)
            else
                storage[k] = nil
                plainStore[k] = v
            end
        end,

        __pairs = function(_)
            local allKeys = {}
            for k in pairs(storage) do allKeys[k] = "enc" end
            for k in pairs(plainStore) do allKeys[k] = "plain" end
            local k = nil
            return function()
                local nk, src = next(allKeys, k)
                k = nk
                if nk == nil then return nil end
                if src == "enc" then
                    return nk, decode(storage[nk])
                else
                    return nk, plainStore[nk]
                end
            end
        end,

        __len = function(_)
            local n = 0
            for _ in pairs(storage) do n = n + 1 end
            for _ in pairs(plainStore) do n = n + 1 end
            return n
        end,
    }
    setmetatable(proxy, mt)

    if initialData then
        for k, v in pairs(initialData) do
            proxy[k] = v
        end
    end

    local function snapshot()
        local t = {}
        for k, v in pairs(proxy) do
            t[k] = v
        end
        return t
    end

    return proxy, snapshot
end

-- ============================================================================
-- CreateDeep: 递归混淆（子 table 自动包装为新的 SafeTable）
-- ============================================================================

--- 创建递归混淆代理表
--- 当写入一个 table 值时，自动递归包装为子 SafeTable。
--- snapshot() 递归输出完整的明文嵌套结构。
---@param initialData? table  初始明文数据
---@return table proxy  代理表（读写透明）
---@return fun():table snapshot  获取明文快照（递归展开，用于存档）
function SafeTable.CreateDeep(initialData)
    local sessionKey = math.random(100000, 999999)
    local salt = math.random(10000, 99999)

    local storage = {}        -- key -> 混淆后的数值
    local plainStore = {}     -- key -> 非数值非 table（string/bool）
    local childProxies = {}   -- key -> 子代理表
    local childSnapshots = {} -- key -> 子 snapshot 函数

    local function encode(v)
        return (math.floor(v) + salt) ~ sessionKey
    end

    local function decode(v)
        return (v ~ sessionKey) - salt
    end

    local proxy = {}
    local mt = {
        __index = function(_, k)
            if childProxies[k] ~= nil then return childProxies[k] end
            if plainStore[k] ~= nil then return plainStore[k] end
            local raw = storage[k]
            if raw == nil then return nil end
            return decode(raw)
        end,

        __newindex = function(_, k, v)
            if v == nil then
                storage[k] = nil
                plainStore[k] = nil
                childProxies[k] = nil
                childSnapshots[k] = nil
                return
            end
            if type(v) == "number" then
                childProxies[k] = nil
                childSnapshots[k] = nil
                plainStore[k] = nil
                storage[k] = encode(v)
            elseif type(v) == "table" then
                -- 子 table 递归包装
                storage[k] = nil
                plainStore[k] = nil
                local cp, cs = SafeTable.CreateDeep(v)
                childProxies[k] = cp
                childSnapshots[k] = cs
            else
                -- string / boolean
                childProxies[k] = nil
                childSnapshots[k] = nil
                storage[k] = nil
                plainStore[k] = v
            end
        end,

        __pairs = function(_)
            local allKeys = {}
            for k in pairs(storage) do allKeys[k] = "enc" end
            for k in pairs(plainStore) do allKeys[k] = "plain" end
            for k in pairs(childProxies) do allKeys[k] = "child" end
            local k = nil
            return function()
                local nk, src = next(allKeys, k)
                k = nk
                if nk == nil then return nil end
                if src == "enc" then
                    return nk, decode(storage[nk])
                elseif src == "child" then
                    return nk, childProxies[nk]
                else
                    return nk, plainStore[nk]
                end
            end
        end,

        __len = function(_)
            local n = 0
            for _ in pairs(storage) do n = n + 1 end
            for _ in pairs(plainStore) do n = n + 1 end
            for _ in pairs(childProxies) do n = n + 1 end
            return n
        end,
    }
    setmetatable(proxy, mt)

    if initialData then
        for k, v in pairs(initialData) do
            proxy[k] = v
        end
    end

    --- 递归快照：子 table 通过子 snapshot 展开为普通 table
    local function snapshot()
        local t = {}
        for k in pairs(storage) do
            t[k] = decode(storage[k])
        end
        for k, v in pairs(plainStore) do
            t[k] = v
        end
        for k in pairs(childSnapshots) do
            t[k] = childSnapshots[k]()
        end
        return t
    end

    return proxy, snapshot
end

return SafeTable
