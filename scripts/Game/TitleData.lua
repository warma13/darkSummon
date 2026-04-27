-- Game/TitleData.lua
-- 称号系统：定义、拥有状态、装备/卸下、加成计算、持久化
-- 设计原则：只有已装备的称号提供加成（区别于时装的图鉴收集加成）

local M = {}

local SaveRegistry = require("Game.SaveRegistry")

-- ============================================================================
-- 加成类型枚举
-- ============================================================================
-- 称号可以提供以下加成（只有装备中的称号生效）：
--   atkPct      全英雄攻击百分比  +0.02 = +2%
--   spdPct      全英雄攻速百分比  +0.01 = +1%
--   critRate    暴击率(绝对值)    +0.03 = +3%
--   critDmg     暴击伤害(绝对值)  +0.05 = +5%
--   armorPen    护甲穿透(绝对值)  +0.02 = +2%
--   scorePct    排行榜加分百分比  +0.05 = +5%

-- ============================================================================
-- 称号定义
-- ============================================================================

---@class TitleDef
---@field id string           唯一ID
---@field name string         称号名称
---@field desc string         获得方式说明
---@field rarity string       品质: N/R/SR/SSR/UR/LR
---@field color table         称号文字颜色 {r,g,b,a}
---@field borderColor table   卡片边框色
---@field bonuses table       加成表 { atkPct=0.02, critRate=0.01, ... }
---@field owned boolean       初始是否拥有（静态解锁）

M.TITLES = {
    -- ── 社区活动 ──
    {
        id         = "hero_designer",
        name       = "英雄设计师",
        desc       = "参与社区英雄设计活动获得",
        rarity     = "SR",
        color      = { 180, 130, 255, 255 },
        borderColor = { 140, 90, 220, 200 },
        bonuses    = { atkPct = 0.06, critRate = 0.04 },
        owned      = false,
    },
    {
        id         = "hero_designer_ex",
        name       = "优秀英雄设计师",
        desc       = "社区英雄设计活动优秀设计奖",
        rarity     = "SSR",
        color      = { 255, 200, 60, 255 },
        borderColor = { 220, 160, 30, 220 },
        bonuses    = { atkPct = 0.10, critRate = 0.06, critDmg = 0.08 },
        owned      = false,
    },
}

-- 快速按 ID 查找索引（模块加载时建立）
local _idxMap = {}
for i, def in ipairs(M.TITLES) do
    _idxMap[def.id] = i
end

-- ============================================================================
-- 运行时状态（持久化）
-- ============================================================================

---@type string|nil  当前装备的称号ID
local _equipped = nil

---@type table<string, number>  titleId -> 获得时间戳（os.time()）
local _ownedTitles = {}

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 根据ID查找称号定义
---@param id string
---@return TitleDef|nil
function M.Find(id)
    local idx = _idxMap[id]
    return idx and M.TITLES[idx] or nil
end

--- 检查称号是否已拥有
---@param id string
---@return boolean
function M.IsOwned(id)
    if _ownedTitles[id] then return true end
    local def = M.Find(id)
    return def and def.owned or false
end

--- 获得时间戳（未拥有返回nil）
---@param id string
---@return number|nil
function M.GetAcquiredTime(id)
    return _ownedTitles[id]
end

--- 获取当前装备的称号ID
---@return string|nil
function M.GetEquipped()
    return _equipped
end

--- 获取当前装备的称号定义
---@return TitleDef|nil
function M.GetEquippedDef()
    if not _equipped then return nil end
    return M.Find(_equipped)
end

--- 获取所有已拥有的称号列表（含定义和获得时间）
---@return table[] { def=TitleDef, acquiredTime=number }
function M.GetOwnedList()
    local list = {}
    for _, def in ipairs(M.TITLES) do
        if M.IsOwned(def.id) then
            list[#list + 1] = {
                def = def,
                acquiredTime = _ownedTitles[def.id] or 0,
            }
        end
    end
    return list
end

-- ============================================================================
-- 操作 API
-- ============================================================================

--- 解锁称号（由活动/成就/兑换码系统调用）
---@param id string
---@param timestamp number|nil  可选，默认 os.time()
---@return boolean 是否新解锁
function M.Unlock(id, timestamp)
    if M.IsOwned(id) then return false end
    local def = M.Find(id)
    if not def then
        print("[TitleData] WARNING: unknown title id '" .. tostring(id) .. "'")
        return false
    end
    _ownedTitles[id] = timestamp or os.time()
    def.owned = true
    M._save()
    print("[TitleData] Unlocked: " .. def.name)
    return true
end

--- 装备称号
---@param id string|nil  传 nil 卸下
function M.Equip(id)
    if id and not M.IsOwned(id) then return end
    _equipped = id
    M._save()
    -- 同步排行榜
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if ok and LB.SyncCampaignScore then
        LB.SyncCampaignScore()
    end
end

--- 卸下称号
function M.Unequip()
    M.Equip(nil)
end

--- 检查是否已装备某个称号
---@param id string
---@return boolean
function M.IsEquipped(id)
    return _equipped == id
end

-- ============================================================================
-- 加成计算（只有装备中的称号生效）
-- ============================================================================

--- 获取当前装备称号的所有加成
---@return table { atkPct=0, spdPct=0, critRate=0, critDmg=0, armorPen=0, scorePct=0 }
function M.GetEquippedBonuses()
    local result = { atkPct = 0, spdPct = 0, critRate = 0, critDmg = 0, armorPen = 0, scorePct = 0 }
    local def = M.GetEquippedDef()
    if not def or not def.bonuses then return result end
    for k, v in pairs(def.bonuses) do
        result[k] = (result[k] or 0) + v
    end
    return result
end

--- 快速获取攻击加成百分比（供 HeroSkills 调用）
---@return number
function M.GetGlobalAtkBonus()
    local def = M.GetEquippedDef()
    if not def or not def.bonuses then return 0 end
    return def.bonuses.atkPct or 0
end

--- 快速获取攻速加成百分比
---@return number
function M.GetGlobalSpdBonus()
    local def = M.GetEquippedDef()
    if not def or not def.bonuses then return 0 end
    return def.bonuses.spdPct or 0
end

--- 快速获取排行榜加分百分比
---@return number
function M.GetScorePctBonus()
    local def = M.GetEquippedDef()
    if not def or not def.bonuses then return 0 end
    return def.bonuses.scorePct or 0
end

-- ============================================================================
-- 持久化（本地 + SaveRegistry 云端双路径）
-- ============================================================================

local SAVE_FILE = "title_data.json"

function M._save()
    local ok, cjson = pcall(require, "cjson")
    if not ok then return end
    local f = File(SAVE_FILE, FILE_WRITE)
    if not f then return end
    f:WriteString(cjson.encode({ equipped = _equipped, owned = _ownedTitles }))
    f:Close()
end

function M._load()
    local ok, cjson = pcall(require, "cjson")
    if not ok then return end
    ---@diagnostic disable-next-line: undefined-global
    local fs = fileSystem
    if not fs:FileExists(SAVE_FILE) then return end
    local f = File(SAVE_FILE, FILE_READ)
    if not f then return end
    local raw = f:ReadString(f:GetSize())
    f:Close()
    local ok2, data = pcall(cjson.decode, raw)
    if not ok2 or type(data) ~= "table" then return end
    _equipped = data.equipped
    if type(data.owned) == "table" then
        for id, ts in pairs(data.owned) do
            _ownedTitles[id] = ts
        end
    end
    -- 同步 def.owned 标记
    for id, _ in pairs(_ownedTitles) do
        local def = M.Find(id)
        if def then def.owned = true end
    end
    -- 校验装备合法性
    if _equipped and not M.IsOwned(_equipped) then
        _equipped = nil
    end
end

-- ============================================================================
-- SaveRegistry 注册（云端持久化）
-- ============================================================================
SaveRegistry.Register("titleData", {
    group = "meta_game",
    order = 58,  -- 在 costumeData(57) 之后
    initDefault = function()
        _equipped = nil
        _ownedTitles = {}
    end,
    serialize = function()
        return { equipped = _equipped, owned = _ownedTitles }
    end,
    deserialize = function(saved)
        if saved and type(saved) == "table" then
            _equipped = saved.equipped
            if type(saved.owned) == "table" then
                for id, ts in pairs(saved.owned) do
                    _ownedTitles[id] = ts
                end
            end
        end
        -- 兼容：无云端数据时从本地加载
        if not saved or (not saved.equipped and not saved.owned) then
            M._load()
        end
        -- 同步 def.owned
        for id, _ in pairs(_ownedTitles) do
            local def = M.Find(id)
            if def then def.owned = true end
        end
        -- 校验
        if _equipped and not M.IsOwned(_equipped) then
            _equipped = nil
        end
    end,
})

-- 初始加载（非 SaveRegistry 路径兼容）
M._load()

return M
