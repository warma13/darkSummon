-- Game/SlotSaveSystem.lua
-- 多槽位云端存档系统（云端持久化、本地仅会话内缓存）
-- ⚠️ WASM 环境下本地文件不持久化，页面关闭后丢失
-- 云端存档是唯一的持久化手段，必须保证云端保存的频率和可靠性
-- 设计文档: docs/多槽位云端存档系统设计.md

---@diagnostic disable: undefined-global

local SaveManager = require("Game.SaveManager")
local SaveRegistry = require("Game.SaveRegistry")

local SlotSaveSystem = {}

-- ============================================================================
-- 常量
-- ============================================================================

local SAVE_VERSION = 1         -- 存档数据版本号
local SHARD_FORMAT = 2         -- 分片格式版本号
local MAX_SLOTS = 10           -- 最大槽位数
local CHUNK_SIZE = 8192        -- 单片最大字节数 (8KB，留余量给JSON开销)
local SAVE_INTERVAL = 30       -- 自动保存间隔（秒）— WASM 无本地持久化，需更频繁云端保存
local DIRTY_DELAY = 2          -- 脏标记延迟保存（秒）— 数据变更后尽快上传云端
local MAX_RETRY = 3            -- 最大重试次数
local RETRY_INTERVALS = { 3, 9, 27 }  -- 指数退避间隔

-- 数据组名列表（决定分组顺序和 key 名）
local GROUP_NAMES = { "core", "currency", "equip", "meta_game" }

-- ============================================================================
-- 内部状态
-- ============================================================================

local meta = nil               -- save_meta 数据
local activeSlot = 0           -- 当前活跃槽位 (0=未选择)
local headCache = {}           -- slotId -> head 数据缓存
local saveConfirmed = false    -- 存档已加载确认（开始自动保存循环）

-- 每个槽位的存档序号（云端写入成功后才递增，用于防止旧数据覆盖新数据）
-- confirmedSeq[slotId] = 最后一次成功写入云端的 saveSeq
local confirmedSeq = {}
local playTime = 0             -- 本次累计游戏时长（秒）
local healthy = true           -- 存档健康状态

-- 定时器
local autoSaveTimer = 0        -- 自动保存计时器
local dirtyTimer = -1          -- 脏标记计时器 (-1=未激活)
local savingInProgress = false -- 是否正在保存中（防止云端重入）
local pendingSave = false      -- 云端保存期间是否有新的保存请求
local saveStartTime = 0        -- 云端保存开始时间戳（用于超时保护）
local CLOUD_SAVE_TIMEOUT = 15  -- 云端保存超时时间（秒）
local saveGeneration = 0       -- 每次新的云端保存递增；回调时比对，用于丢弃超时后延迟到达的旧回调

-- 重试队列
local retryQueue = {}          -- { { fn, retryCount, nextRetryTime } }

-- 初始化状态
local initState = "none"       -- "none" | "loading" | "ready" | "error"
local initRetryCount = 0
local initRetryTimer = -1
local initCallback = nil

-- ============================================================================
-- DJB2 校验
-- ============================================================================

--- 计算字符串的 DJB2 哈希
---@param str string
---@return number
local function CalcChecksum(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash << 5) + hash + string.byte(str, i)) & 0xFFFFFFFF
    end
    return hash
end

-- ============================================================================
-- 数据分组（业务层定义）
-- ============================================================================

--- 将完整 saveData 拆分为功能组（委托给 SaveRegistry）
---@param saveData table
---@return table groups  { core={...}, currency={...}, equip={...}, meta_game={...} }
local function SplitIntoGroups(saveData)
    return SaveRegistry.SplitIntoGroups(saveData)
end

--- 将各组合并还原为完整 saveData（委托给 SaveRegistry）
---@param groups table
---@return table saveData
local function MergeGroups(groups)
    return SaveRegistry.MergeGroups(groups)
end

-- ============================================================================
-- 分片编码/解码
-- ============================================================================

--- 将分组数据编码为云端 key-value 对 + head 数据
---@param slotId number
---@param groups table
---@param saveSeq number|nil  存档序号（每次成功写入后递增）
---@return table kvPairs  { key = jsonStr }
---@return table headData  分片索引+校验
local function EncodeChunkedGroups(slotId, groups, saveSeq)
    local kvPairs = {}
    local headKeys = {}
    local prefix = "s_" .. slotId .. "_"

    for _, groupName in ipairs(GROUP_NAMES) do
        local groupData = groups[groupName]
        if groupData then
            local ok, jsonStr = pcall(cjson.encode, groupData)
            if not ok then
                print("[SlotSave] !! Encode FAILED for group " .. groupName .. ": " .. tostring(jsonStr))
                -- 打印该组所有 key 的类型，帮助定位哪个字段导致编码失败
                for k, v in pairs(groupData) do
                    local vt = type(v)
                    if vt == "table" then
                        local subOk, subJson = pcall(cjson.encode, v)
                        print("[SlotSave]   field '" .. k .. "': table, encode=" .. (subOk and "OK("..#subJson.."B)" or "FAIL:"..tostring(subJson)))
                    else
                        print("[SlotSave]   field '" .. k .. "': " .. vt)
                    end
                end
                -- 中止本次保存，保留云端旧数据，避免写入空数据导致数据丢失
                print("[SlotSave] !! ABORTING save to protect existing cloud data")
                return nil, nil
            else
                if groupName == "equip" or groupName == "meta_game" then
                    print("[SlotSave] Encode OK for group " .. groupName .. " (" .. #jsonStr .. " bytes)")
                end
            end

            local len = #jsonStr
            if len <= CHUNK_SIZE then
                -- 单片
                local key = prefix .. groupName
                kvPairs[key] = jsonStr
                headKeys[groupName] = {
                    cs = CalcChecksum(jsonStr),
                    len = len,
                }
            else
                -- 多片
                local chunks = {}
                local csArr = {}
                local lenArr = {}
                local pos = 1
                local chunkIdx = 0
                while pos <= len do
                    local endPos = math.min(pos + CHUNK_SIZE - 1, len)
                    local chunk = string.sub(jsonStr, pos, endPos)
                    local key = prefix .. groupName .. "_" .. chunkIdx
                    kvPairs[key] = chunk
                    csArr[#csArr + 1] = CalcChecksum(chunk)
                    lenArr[#lenArr + 1] = #chunk
                    chunkIdx = chunkIdx + 1
                    pos = endPos + 1
                end
                headKeys[groupName] = {
                    chunks = chunkIdx,
                    cs = csArr,
                    len = lenArr,
                }
            end
        end
    end

    local headData = {
        format = SHARD_FORMAT,
        version = SAVE_VERSION,
        timestamp = os.time(),
        saveSeq = saveSeq or 1,
        slotId = slotId,
        keys = headKeys,
    }

    return kvPairs, headData
end

--- 收集加载时需要读取的所有 key
---@param slotId number
---@param head table  head 数据
---@return table keys  key 列表
local function CollectGroupKeys(slotId, head)
    local keys = {}
    local prefix = "s_" .. slotId .. "_"
    if head and head.keys then
        for groupName, info in pairs(head.keys) do
            if info.chunks then
                for i = 0, info.chunks - 1 do
                    keys[#keys + 1] = prefix .. groupName .. "_" .. i
                end
            else
                keys[#keys + 1] = prefix .. groupName
            end
        end
    end
    return keys
end

--- 从云端返回的 values 解码分组数据
---@param slotId number
---@param head table
---@param values table  云端 values
---@return table|nil groups  解码后的分组数据
---@return boolean checksumOk  校验是否通过
local function DecodeChunkedGroups(slotId, head, values)
    local groups = {}
    local prefix = "s_" .. slotId .. "_"
    local allOk = true

    for groupName, info in pairs(head.keys) do
        local jsonStr
        if info.chunks then
            -- 多片拼接
            local parts = {}
            for i = 0, info.chunks - 1 do
                local key = prefix .. groupName .. "_" .. i
                local chunk = values[key]
                if not chunk then
                    print("[SlotSave] Missing chunk " .. key)
                    allOk = false
                    break
                end
                -- 校验每片
                if type(info.cs) == "table" and info.cs[i + 1] then
                    local actual = CalcChecksum(chunk)
                    if actual ~= info.cs[i + 1] then
                        print("[SlotSave] Checksum mismatch for " .. key)
                        allOk = false
                    end
                end
                parts[#parts + 1] = chunk
            end
            jsonStr = table.concat(parts)
        else
            -- 单片
            local key = prefix .. groupName
            jsonStr = values[key]
            if jsonStr then
                local actual = CalcChecksum(jsonStr)
                if actual ~= info.cs then
                    print("[SlotSave] Checksum mismatch for " .. key)
                    allOk = false
                end
            end
        end

        if jsonStr and jsonStr ~= "" then
            local ok, decoded = pcall(cjson.decode, jsonStr)
            if ok then
                groups[groupName] = decoded
            else
                print("[SlotSave] Decode failed for group " .. groupName .. ": " .. tostring(decoded))
                allOk = false
            end
        end
    end

    return groups, allOk
end

-- ============================================================================
-- 本地缓存
-- ============================================================================

--- 保存到本地缓存文件
---@param slotId number
---@param saveData table
local function SaveLocal(slotId, saveData)
    local fileName = "slot_" .. slotId .. "_cache.json"
    local ok, jsonStr = pcall(cjson.encode, saveData)
    if not ok then
        print("[SlotSave] Local encode failed: " .. tostring(jsonStr))
        return
    end
    local file = File(fileName, FILE_WRITE)
    if file and file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
    else
        print("[SlotSave] Local write failed for " .. fileName)
    end
end

--- 从本地缓存读取
---@param slotId number
---@return table|nil
local function LoadLocal(slotId)
    local fileName = "slot_" .. slotId .. "_cache.json"
    if not fileSystem:FileExists(fileName) then return nil end
    local file = File(fileName, FILE_READ)
    if not file or not file:IsOpen() then return nil end
    local jsonStr = file:ReadString()
    file:Close()
    if not jsonStr or jsonStr == "" then return nil end
    local ok, data = pcall(cjson.decode, jsonStr)
    if ok then return data end
    return nil
end

-- ============================================================================
-- Meta 摘要
-- ============================================================================

--- 构建当前槽位的摘要信息（由业务层数据填充）
---@return table
local function BuildMetaSlot()
    local HeroData = require("Game.HeroData")
    local Config = require("Game.Config")

    -- 统计已解锁英雄数
    local heroCount = 0
    if HeroData.heroes then
        for _, h in pairs(HeroData.heroes) do
            if h and h.unlocked then
                heroCount = heroCount + 1
            end
        end
    end

    -- 主角等级
    local leaderLevel = 1
    if HeroData.heroes and HeroData.heroes[Config.LEADER_HERO.id] then
        leaderLevel = HeroData.heroes[Config.LEADER_HERO.id].level or 1
    end

    return {
        leaderLevel = leaderLevel,
        bestStage = (HeroData.stats and HeroData.stats.bestStage) or 0,
        heroCount = heroCount,
        playTime = playTime,
        timestamp = os.time(),
    }
end

--- 保存 meta 到云端
---@param onComplete function|nil
local function SaveMeta(onComplete)
    if not meta then return end
    local ok, metaJson = pcall(cjson.encode, meta)
    if not ok then
        print("[SlotSave] Meta encode failed")
        if onComplete then onComplete(false) end
        return
    end
    clientCloud:Set("save_meta", meta, {
        ok = function()
            print("[SlotSave] Meta saved to cloud")
            if onComplete then onComplete(true) end
        end,
        error = function(code, reason)
            print("[SlotSave] Meta save failed: " .. tostring(reason))
            if onComplete then onComplete(false) end
        end,
    })
end

-- ============================================================================
-- 版本迁移框架
-- ============================================================================

local MIGRATIONS = {
    -- [1] = function(data) ... end,  -- v1 → v2（预留）
}

--- 执行版本迁移
---@param data table
local function RunVersionMigrations(data)
    local ver = data.version or 0
    while ver < SAVE_VERSION do
        local fn = MIGRATIONS[ver]
        if fn then
            fn(data)
            ver = ver + 1
            data.version = ver
        else
            break
        end
    end
end

-- ============================================================================
-- 核心保存逻辑
-- ============================================================================

--- 执行完整保存流程（本地+云端）
--- 本地保存永远执行，云端保存受 savingInProgress 保护
local function DoSave()
    if activeSlot <= 0 or not saveConfirmed then return end

    local HeroData = require("Game.HeroData")
    local saveData = HeroData.GetSaveSnapshot()
    saveData.version = SAVE_VERSION

    -- 1. 本地保存始终执行（不受云端锁阻塞）
    SaveLocal(activeSlot, saveData)

    -- 2. 云端保存：如果正在上传中，标记 pending 等待完成后重试
    if savingInProgress then
        pendingSave = true
        return
    end
    savingInProgress = true
    pendingSave = false
    saveStartTime = os.time()
    saveGeneration = saveGeneration + 1
    local currentGen = saveGeneration  -- 闭包捕获：回调时用于判断是否为最新请求

    -- 3. 分组+分片编码（saveSeq = 上次确认序号 + 1）
    local nextSeq = (confirmedSeq[activeSlot] or 0) + 1
    local groups = SplitIntoGroups(saveData)
    local kvPairs, headData = EncodeChunkedGroups(activeSlot, groups, nextSeq)

    -- 编码失败：中止云端保存，保留旧数据，等待下次重试
    if not kvPairs then
        print("[SlotSave] Cloud save SKIPPED due to encode failure, will retry on next dirty cycle")
        savingInProgress = false
        local okT, Toast = pcall(require, "Game.Toast")
        if okT and Toast and Toast.Show then
            Toast.Show("云端保存失败，稍后自动重试", {255, 100, 80})
        end
        -- 标记 dirty 以便下次自动保存周期重试
        if dirtyTimer < 0 then
            dirtyTimer = DIRTY_DELAY
        end
        return
    end

    -- 4. 构建 BatchSet
    local batch = clientCloud:BatchSet()
    -- head
    local headKey = "s_" .. activeSlot .. "_head"
    batch:Set(headKey, headData)
    -- 所有分组 key
    for key, value in pairs(kvPairs) do
        batch:Set(key, value)
    end

    -- 5. 更新 meta 摘要
    local slotMeta = BuildMetaSlot()
    if not meta then
        meta = { version = 1, activeSlot = activeSlot, slots = {} }
    end
    meta.slots[tostring(activeSlot)] = slotMeta
    meta.activeSlot = activeSlot
    batch:Set("save_meta", meta)

    -- 6. 提交
    batch:Save("slot_" .. activeSlot .. "_save", {
        ok = function()
            -- ⚠️ 如果这不是最新的保存请求（超时后新请求已发出），说明是延迟到达的旧回调
            -- 旧回调不应清除 savingInProgress / saveStartTime（那是新请求的锁），也不应覆盖更高的 seq
            if currentGen ~= saveGeneration then
                -- 仅在 seq 更高时更新 confirmedSeq（尽量保留有效信息）
                if nextSeq > (confirmedSeq[activeSlot] or 0) then
                    confirmedSeq[activeSlot] = nextSeq
                    print("[SlotSave] Stale ok callback (gen mismatch): seq=" .. nextSeq .. " still higher, updated confirmedSeq")
                else
                    print("[SlotSave] Stale ok callback ignored (gen=" .. currentGen .. " < current=" .. saveGeneration .. ", seq=" .. nextSeq .. " stale)")
                end
                return
            end
            savingInProgress = false
            saveStartTime = 0
            headCache[activeSlot] = headData
            -- 只在序号不低于当前已确认序号时才更新（双重保障）
            if nextSeq >= (confirmedSeq[activeSlot] or 0) then
                confirmedSeq[activeSlot] = nextSeq
            end
            print("[SlotSave] Cloud save OK (slot " .. activeSlot .. ", seq=" .. nextSeq .. ")")
            -- 云端保存成功提示
            local okT, Toast = pcall(require, "Game.Toast")
            if okT and Toast and Toast.Show then
                Toast.Show("云端存档已保存", {120, 200, 80})
            end
            -- 如果云端保存期间有新的数据变更，立即用最新数据再保存一次
            if pendingSave then
                pendingSave = false
                DoSave()
            end
        end,
        error = function(code, reason)
            -- 旧回调的错误直接忽略，不干扰当前正在进行的新请求
            if currentGen ~= saveGeneration then
                print("[SlotSave] Stale error callback ignored (gen=" .. currentGen .. " < current=" .. saveGeneration .. ")")
                return
            end
            savingInProgress = false
            saveStartTime = 0
            print("[SlotSave] Cloud save failed: " .. tostring(reason) .. " (code=" .. tostring(code) .. ")")
            -- 如果有挂起的保存请求，立即用最新数据重试（优先于旧数据重试）
            if pendingSave then
                pendingSave = false
                DoSave()
            else
                -- 没有挂起请求，加入重试队列
                if #retryQueue < MAX_RETRY then
                    retryQueue[#retryQueue + 1] = {
                        fn = DoSave,
                        retryCount = 0,
                        nextRetryTime = os.time() + RETRY_INTERVALS[1],
                    }
                end
            end
        end,
    })
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 初始化存档系统（启动时调用一次）
---@param onMetaReady function  回调 (meta, isNewPlayer, err)
function SlotSaveSystem.Init(onMetaReady)
    initCallback = onMetaReady
    initState = "loading"
    initRetryCount = 0

    print("[SlotSave] Init: loading save_meta from cloud...")

    clientCloud:Get("save_meta", {
        ok = function(values, iscores)
            local cloudMeta = values.save_meta
            if cloudMeta and type(cloudMeta) == "table" and cloudMeta.slots then
                -- 有 meta，老玩家
                meta = cloudMeta
                initState = "ready"
                print("[SlotSave] Init: meta loaded, " .. SlotSaveSystem.GetSlotCount() .. " slots")
                if onMetaReady then
                    onMetaReady(meta, false, nil)
                end
            else
                -- 无 meta，检查旧格式迁移
                print("[SlotSave] Init: no meta, checking old format...")
                SlotSaveSystem._TryMigrateOldFormat(onMetaReady)
            end
        end,
        error = function(code, reason)
            print("[SlotSave] Init: cloud read failed: " .. tostring(reason))
            initRetryCount = initRetryCount + 1
            if initRetryCount <= MAX_RETRY then
                local delay = RETRY_INTERVALS[initRetryCount] or 27
                print("[SlotSave] Init: retry #" .. initRetryCount .. " in " .. delay .. "s")
                initRetryTimer = delay
                initState = "loading"
            else
                initState = "error"
                healthy = false
                -- 尝试从本地缓存恢复 meta
                meta = { version = 1, activeSlot = 0, slots = {} }
                if onMetaReady then
                    onMetaReady(meta, true, "cloud_error")
                end
            end
        end,
    })
end

--- 尝试旧格式迁移（内部方法）
---@param onMetaReady function
function SlotSaveSystem._TryMigrateOldFormat(onMetaReady)
    -- ⚠️ 安全检查：先确认 slot 1 的 head 是否已存在
    -- 如果存在说明数据已迁移过（save_meta 是单独丢失），直接重建 meta 并加载，严禁用旧数据覆盖
    clientCloud:Get("s_1_head", {
        ok = function(headValues, iscores)
            local existingHead = headValues["s_1_head"]
            if existingHead and type(existingHead) == "table" and existingHead.keys then
                -- slot 1 数据完好，save_meta 单独丢失了 → 重建 meta 并直接加载
                local cloudSeq = existingHead.saveSeq or 0
                print("[SlotSave] save_meta lost but slot 1 head exists (seq=" .. cloudSeq .. "), rebuilding meta...")
                meta = { version = 1, activeSlot = 1, slots = {
                    ["1"] = { leaderLevel = 0, timestamp = existingHead.timestamp or 0, recovered = true }
                }}
                initState = "ready"
                -- 直接通知上层加载 slot 1（不做迁移，不覆盖数据）
                if onMetaReady then
                    onMetaReady(meta, false, nil)
                end
                return
            end

            -- slot 1 不存在，才真正执行旧格式迁移
            SlotSaveSystem._DoLegacyMigration(onMetaReady)
        end,
        error = function(code, reason)
            -- 读 head 失败，保守处理：不做迁移，当成新玩家
            print("[SlotSave] Cannot read s_1_head (" .. tostring(reason) .. "), treating as new player")
            meta = { version = 1, activeSlot = 0, slots = {} }
            initState = "ready"
            if onMetaReady then
                onMetaReady(meta, true, nil)
            end
        end,
    })
end

--- 执行旧格式迁移（内部）—— 仅在确认 slot 1 无数据时调用
---@param onMetaReady function
function SlotSaveSystem._DoLegacyMigration(onMetaReady)
    clientCloud:Get("hero_save", {
        ok = function(values, iscores)
            local oldData = values.hero_save
            if oldData and type(oldData) == "table" and oldData.heroes then
                -- 有旧云端存档，迁移到槽位 1
                print("[SlotSave] Found old cloud save, migrating to slot 1...")
                SlotSaveSystem._MigrateOldData(oldData, 1, onMetaReady)
            else
                -- 尝试本地旧存档
                local localData = SaveManager.Load()
                if localData and localData.heroes then
                    print("[SlotSave] Found old local save, migrating to slot 1...")
                    SlotSaveSystem._MigrateOldData(localData, 1, onMetaReady)
                else
                    -- 纯新玩家
                    print("[SlotSave] New player, creating empty meta")
                    meta = { version = 1, activeSlot = 0, slots = {} }
                    initState = "ready"
                    if onMetaReady then
                        onMetaReady(meta, true, nil)
                    end
                end
            end
        end,
        error = function(code, reason)
            -- 旧 key 读取失败，当做新玩家
            meta = { version = 1, activeSlot = 0, slots = {} }
            initState = "ready"
            if onMetaReady then
                onMetaReady(meta, true, nil)
            end
        end,
    })
end

--- 执行旧数据迁移（内部方法）
---@param oldData table
---@param slotId number
---@param onMetaReady function
function SlotSaveSystem._MigrateOldData(oldData, slotId, onMetaReady)
    -- 先反序列化到运行时（执行字段迁移）
    local HeroData = require("Game.HeroData")
    HeroData.RestoreFromSnapshot(oldData)

    -- 再序列化为新格式
    local saveData = HeroData.GetSaveSnapshot()
    saveData.version = SAVE_VERSION

    -- 保存本地
    SaveLocal(slotId, saveData)

    -- 分组+分片编码（迁移存档从 seq=1 开始）
    local groups = SplitIntoGroups(saveData)
    local kvPairs, headData = EncodeChunkedGroups(slotId, groups, 1)

    -- 构建 meta
    activeSlot = slotId
    saveConfirmed = true
    confirmedSeq[slotId] = 1

    local slotMeta = BuildMetaSlot()
    slotMeta.migratedFrom = "old_format"
    meta = {
        version = 1,
        activeSlot = slotId,
        slots = {
            [tostring(slotId)] = slotMeta,
        },
    }

    -- 云端写入
    local batch = clientCloud:BatchSet()
    batch:Set("s_" .. slotId .. "_head", headData)
    for key, value in pairs(kvPairs) do
        batch:Set(key, value)
    end
    batch:Set("save_meta", meta)
    batch:Save("migrate_old_to_slot_" .. slotId, {
        ok = function()
            headCache[slotId] = headData
            initState = "ready"
            print("[SlotSave] Migration complete: old -> slot " .. slotId)
            if onMetaReady then
                onMetaReady(meta, false, nil)
            end
        end,
        error = function(code, reason)
            -- 本地已保存，不阻塞
            initState = "ready"
            print("[SlotSave] Migration cloud write failed (local ok): " .. tostring(reason))
            if onMetaReady then
                onMetaReady(meta, false, nil)
            end
        end,
    })
end

--- 加载存档槽位
---@param slotId number
---@param onComplete function  回调 (success, isNewSlot)
function SlotSaveSystem.LoadSlot(slotId, onComplete)
    print("[SlotSave] LoadSlot(" .. slotId .. ")...")

    -- 检查是否为空槽位（新建存档）
    if meta and not meta.slots[tostring(slotId)] then
        print("[SlotSave] Slot " .. slotId .. " is empty, creating new...")
        SlotSaveSystem.CreateNewSlot(slotId, function(success)
            if onComplete then onComplete(success, true) end
        end)
        return
    end

    -- 读取 head
    local headKey = "s_" .. slotId .. "_head"
    clientCloud:Get(headKey, {
        ok = function(values, iscores)
            local head = values[headKey]
            if head and type(head) == "table" and head.keys then
                -- 序号保护：如果云端 saveSeq < 本地已确认序号，说明云端是旧数据，优先用本地缓存
                local cloudSeq = head.saveSeq or 0
                local localSeq = confirmedSeq[slotId] or 0
                if localSeq > 0 and cloudSeq < localSeq then
                    print("[SlotSave] WARNING: cloud saveSeq(" .. cloudSeq .. ") < local confirmedSeq(" .. localSeq .. "), using local cache to prevent rollback")
                    local localData = LoadLocal(slotId)
                    if localData then
                        SlotSaveSystem._FinalizeLoad(slotId, localData, onComplete)
                        return
                    end
                    -- 本地没有缓存，只能接受云端数据（不理想但不能阻塞）
                    print("[SlotSave] WARNING: no local cache, accepting cloud data despite lower seq")
                end
                -- 分片格式：批量读取所有分组
                SlotSaveSystem._LoadShardedSlot(slotId, head, onComplete)
            else
                -- 无 head 或格式不对，尝试旧格式回退
                print("[SlotSave] No valid head for slot " .. slotId .. ", trying fallback...")
                SlotSaveSystem._LoadFallback(slotId, onComplete)
            end
        end,
        error = function(code, reason)
            print("[SlotSave] Head read failed: " .. tostring(reason))
            -- 尝试本地缓存
            local localData = LoadLocal(slotId)
            if localData then
                print("[SlotSave] Using local cache for slot " .. slotId)
                SlotSaveSystem._FinalizeLoad(slotId, localData, onComplete)
            else
                if onComplete then onComplete(false, false) end
            end
        end,
    })
end

--- 加载分片格式的存档（内部方法）
---@param slotId number
---@param head table
---@param onComplete function
function SlotSaveSystem._LoadShardedSlot(slotId, head, onComplete)
    local groupKeys = CollectGroupKeys(slotId, head)

    if #groupKeys == 0 then
        print("[SlotSave] No group keys to load")
        SlotSaveSystem._LoadFallback(slotId, onComplete)
        return
    end

    -- BatchGet 所有分组 key
    local batchGet = clientCloud:BatchGet()
    for _, key in ipairs(groupKeys) do
        batchGet:Key(key)
    end

    batchGet:Fetch({
        ok = function(values, iscores)
            local groups, checksumOk = DecodeChunkedGroups(slotId, head, values)
            if not checksumOk then
                print("[SlotSave] Checksum failed, trying fallback...")
                -- 校验失败但有数据，仍尝试使用
                if next(groups) then
                    local saveData = MergeGroups(groups)
                    SlotSaveSystem._FinalizeLoad(slotId, saveData, onComplete)
                else
                    SlotSaveSystem._LoadFallback(slotId, onComplete)
                end
                return
            end

            local saveData = MergeGroups(groups)
            headCache[slotId] = head
            print("[SlotSave] Sharded load OK for slot " .. slotId)
            SlotSaveSystem._FinalizeLoad(slotId, saveData, onComplete)
        end,
        error = function(code, reason)
            print("[SlotSave] BatchGet failed: " .. tostring(reason))
            -- 尝试本地缓存
            local localData = LoadLocal(slotId)
            if localData then
                print("[SlotSave] Using local cache for slot " .. slotId)
                SlotSaveSystem._FinalizeLoad(slotId, localData, onComplete)
            else
                if onComplete then onComplete(false, false) end
            end
        end,
    })
end

--- 旧格式回退加载（内部方法）
---@param slotId number
---@param onComplete function
function SlotSaveSystem._LoadFallback(slotId, onComplete)
    -- 尝试本地缓存
    local localData = LoadLocal(slotId)
    if localData then
        print("[SlotSave] Fallback: using local cache")
        SlotSaveSystem._FinalizeLoad(slotId, localData, onComplete)
        return
    end

    -- 尝试旧格式 hero_save key
    clientCloud:Get("hero_save", {
        ok = function(values, iscores)
            local oldData = values.hero_save
            if oldData and type(oldData) == "table" then
                print("[SlotSave] Fallback: using old cloud save")
                SlotSaveSystem._FinalizeLoad(slotId, oldData, onComplete)
            else
                -- 真正没有任何数据
                print("[SlotSave] Fallback: no data found, creating new slot")
                SlotSaveSystem.CreateNewSlot(slotId, function(success)
                    if onComplete then onComplete(success, true) end
                end)
            end
        end,
        error = function()
            print("[SlotSave] Fallback: all attempts failed")
            if onComplete then onComplete(false, false) end
        end,
    })
end

--- 完成加载：版本迁移 + 反序列化 + 设置活跃槽位（内部方法）
---@param slotId number
---@param saveData table
---@param onComplete function
function SlotSaveSystem._FinalizeLoad(slotId, saveData, onComplete)
    -- 版本迁移
    RunVersionMigrations(saveData)

    -- 反序列化到运行时
    local HeroData = require("Game.HeroData")
    HeroData.RestoreFromSnapshot(saveData)

    -- 计算离线时长
    local lastTime = saveData.lastSaveTime or 0
    local offlineSecs = 0
    if lastTime > 0 then
        offlineSecs = os.time() - lastTime
    end

    -- 设置活跃状态
    activeSlot = slotId
    saveConfirmed = true
    autoSaveTimer = 0
    dirtyTimer = -1
    -- 从 meta 摘要恢复已累积的游玩时长
    local prevPlayTime = 0
    if meta and meta.slots and meta.slots[tostring(slotId)] then
        prevPlayTime = meta.slots[tostring(slotId)].playTime or 0
    end
    playTime = prevPlayTime
    healthy = true

    -- 从 headCache 恢复 saveSeq（下次保存从此序号 +1 开始，防止旧存档回滚）
    if headCache[slotId] and headCache[slotId].saveSeq then
        local loadedSeq = headCache[slotId].saveSeq
        if loadedSeq > (confirmedSeq[slotId] or 0) then
            confirmedSeq[slotId] = loadedSeq
            print("[SlotSave] Restored saveSeq=" .. loadedSeq .. " for slot " .. slotId)
        end
    end

    -- 保存本地缓存
    SaveLocal(slotId, saveData)

    print("[SlotSave] Slot " .. slotId .. " loaded (offline " .. math.floor(offlineSecs / 60) .. " min)")

    if onComplete then onComplete(true, false) end
end

--- 新建存档
---@param slotId number
---@param onComplete function|nil  回调 (success)
function SlotSaveSystem.CreateNewSlot(slotId, onComplete)
    print("[SlotSave] Creating new slot " .. slotId)

    local HeroData = require("Game.HeroData")
    HeroData.InitDefault()

    activeSlot = slotId
    saveConfirmed = true
    autoSaveTimer = 0
    dirtyTimer = -1
    playTime = 0
    healthy = true

    local saveData = HeroData.GetSaveSnapshot()
    saveData.version = SAVE_VERSION

    -- 本地保存
    SaveLocal(slotId, saveData)

    -- 分组+分片编码（新槽位从 seq=1 开始）
    confirmedSeq[slotId] = 0  -- 重置，云端确认后设为 1
    local groups = SplitIntoGroups(saveData)
    local kvPairs, headData = EncodeChunkedGroups(slotId, groups, 1)

    -- 更新 meta
    local slotMeta = BuildMetaSlot()
    slotMeta.createdAt = os.time()
    if not meta then
        meta = { version = 1, activeSlot = slotId, slots = {} }
    end
    meta.slots[tostring(slotId)] = slotMeta
    meta.activeSlot = slotId

    -- 云端写入
    local batch = clientCloud:BatchSet()
    batch:Set("s_" .. slotId .. "_head", headData)
    for key, value in pairs(kvPairs) do
        batch:Set(key, value)
    end
    batch:Set("save_meta", meta)
    batch:Save("create_slot_" .. slotId, {
        ok = function()
            headCache[slotId] = headData
            confirmedSeq[slotId] = 1  -- 新槽位首次云端写入确认
            print("[SlotSave] New slot " .. slotId .. " created and saved (seq=1)")
            if onComplete then onComplete(true) end
        end,
        error = function(code, reason)
            -- 本地已保存，不阻塞
            print("[SlotSave] New slot cloud save failed (local ok): " .. tostring(reason))
            if onComplete then onComplete(true) end
        end,
    })
end

--- 删除存档
---@param slotId number
---@param onComplete function|nil  回调 (success)
function SlotSaveSystem.DeleteSlot(slotId, onComplete)
    if slotId == activeSlot then
        print("[SlotSave] Cannot delete active slot")
        if onComplete then onComplete(false) end
        return
    end

    print("[SlotSave] Deleting slot " .. slotId)

    -- 从 meta 移除
    if meta and meta.slots then
        meta.slots[tostring(slotId)] = nil
    end
    headCache[slotId] = nil
    confirmedSeq[slotId] = nil

    -- 构建删除列表
    local batch = clientCloud:BatchSet()
    batch:Delete("s_" .. slotId .. "_head")
    for _, groupName in ipairs(GROUP_NAMES) do
        batch:Delete("s_" .. slotId .. "_" .. groupName)
        -- 保守删除可能的分片后缀
        for i = 0, 9 do
            batch:Delete("s_" .. slotId .. "_" .. groupName .. "_" .. i)
        end
    end
    batch:Set("save_meta", meta)
    batch:Save("delete_slot_" .. slotId, {
        ok = function()
            headCache[slotId] = nil
            print("[SlotSave] Slot " .. slotId .. " deleted")
            if onComplete then onComplete(true) end
        end,
        error = function(code, reason)
            print("[SlotSave] Delete cloud failed: " .. tostring(reason))
            if onComplete then onComplete(false) end
        end,
    })
end

--- 保存并卸载当前存档（切换存档前调用）
---@param onComplete function|nil
function SlotSaveSystem.SaveAndUnload(onComplete)
    if activeSlot <= 0 then
        if onComplete then onComplete(true) end
        return
    end

    -- 立即保存
    SlotSaveSystem.SaveNow()

    -- 重置状态
    local oldSlot = activeSlot
    activeSlot = 0
    saveConfirmed = false
    dirtyTimer = -1
    autoSaveTimer = 0
    playTime = 0

    -- 重新拉取 meta
    clientCloud:Get("save_meta", {
        ok = function(values)
            if values.save_meta and type(values.save_meta) == "table" then
                meta = values.save_meta
            end
            print("[SlotSave] Unloaded slot " .. oldSlot .. ", meta refreshed")
            if onComplete then onComplete(true) end
        end,
        error = function()
            print("[SlotSave] Unload: meta refresh failed (using cached)")
            if onComplete then onComplete(true) end
        end,
    })
end

--- 常规保存（由定时器触发）
function SlotSaveSystem.Save()
    if activeSlot <= 0 or not saveConfirmed then return end
    dirtyTimer = -1
    autoSaveTimer = 0
    DoSave()
end

--- 立即保存（关键事件后调用）
function SlotSaveSystem.SaveNow()
    if activeSlot <= 0 or not saveConfirmed then return end
    dirtyTimer = -1
    autoSaveTimer = 0
    DoSave()
end

--- 标记数据为脏（延迟合并保存）
function SlotSaveSystem.MarkDirty()
    if activeSlot <= 0 or not saveConfirmed then return end
    if dirtyTimer < 0 then
        dirtyTimer = DIRTY_DELAY
    end
end

--- 每帧更新
---@param dt number
function SlotSaveSystem.Update(dt)
    -- Init 重试计时
    if initState == "loading" and initRetryTimer > 0 then
        initRetryTimer = initRetryTimer - dt
        if initRetryTimer <= 0 then
            initRetryTimer = -1
            SlotSaveSystem.Init(initCallback)
        end
        return
    end

    if not saveConfirmed then return end

    -- 云端保存超时保护：超过 CLOUD_SAVE_TIMEOUT 秒仍未回调，强制解锁
    if savingInProgress and saveStartTime > 0 then
        if os.time() - saveStartTime >= CLOUD_SAVE_TIMEOUT then
            print("[SlotSave] WARNING: Cloud save timed out after " .. CLOUD_SAVE_TIMEOUT .. "s, force unlocking")
            -- ⚠️ 提升 generation：使当前飞行中的回调变为"旧回调"，到达时不会清除新请求的锁
            saveGeneration = saveGeneration + 1
            savingInProgress = false
            saveStartTime = 0
            -- 预消耗一个 seq（双重保障）：确保超时请求的回调中 nextSeq <= 当前 confirmedSeq，
            -- 即使 generation check 因某种极端情况失效，seq guard 仍可阻止旧数据覆盖新 seq
            if activeSlot > 0 then
                confirmedSeq[activeSlot] = (confirmedSeq[activeSlot] or 0) + 1
                print("[SlotSave] Pre-consumed seq for slot " .. activeSlot .. ": confirmedSeq now=" .. confirmedSeq[activeSlot])
            end
            -- 超时后如果有挂起的保存，立即用最新数据重试
            if pendingSave then
                pendingSave = false
                DoSave()
            end
        end
    end

    -- 累计游戏时长
    playTime = playTime + dt

    -- 脏标记定时器
    if dirtyTimer > 0 then
        dirtyTimer = dirtyTimer - dt
        if dirtyTimer <= 0 then
            dirtyTimer = -1
            DoSave()
            autoSaveTimer = 0  -- 脏保存后重置自动保存计时
        end
    end

    -- 自动保存定时器
    autoSaveTimer = autoSaveTimer + dt
    if autoSaveTimer >= SAVE_INTERVAL then
        autoSaveTimer = 0
        DoSave()
    end

    -- 重试队列
    local now = os.time()
    local i = 1
    while i <= #retryQueue do
        local item = retryQueue[i]
        if now >= item.nextRetryTime then
            item.retryCount = item.retryCount + 1
            if item.retryCount > MAX_RETRY then
                -- 超过最大重试，放弃
                table.remove(retryQueue, i)
                print("[SlotSave] Retry exhausted, giving up")
            else
                -- 执行重试
                table.remove(retryQueue, i)
                item.fn()
            end
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 获取 meta 数据
---@return table|nil
function SlotSaveSystem.GetMeta()
    return meta
end

--- 获取当前活跃槽位
---@return number  0=未选择
function SlotSaveSystem.GetActiveSlot()
    return activeSlot
end

--- 获取已用槽位数
---@return number
function SlotSaveSystem.GetSlotCount()
    if not meta or not meta.slots then return 0 end
    local count = 0
    for _ in pairs(meta.slots) do
        count = count + 1
    end
    return count
end

--- 获取最大槽位数
---@return number
function SlotSaveSystem.GetMaxSlots()
    return MAX_SLOTS
end

--- 获取累计游戏时长（秒）
---@return number
function SlotSaveSystem.GetPlayTime()
    return playTime
end

--- 存档是否健康
---@return boolean
function SlotSaveSystem.IsSaveHealthy()
    return healthy
end

return SlotSaveSystem
