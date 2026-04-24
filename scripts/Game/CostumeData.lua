-- Game/CostumeData.lua
-- 时装数据层：定义所有时装，管理装备状态

local M = {}

local SAVE_FILE = "costume_equipped.json"
local HeroData     = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

-- ============================================================================
-- 时装定义
-- ============================================================================

-- 翅膀时装列表
M.WING_COSTUMES = {
    {
        id         = "wing_shadow",
        name       = "暗影之翼",
        desc       = "暗夜君主的专属翅膀，散发着神秘的紫金光芒，累积签到7次可得",
        type       = "wing",
        preview    = "image/wing_spritesheet_4frames_20260418025557.png",
        gridCols   = 2,
        gridRows   = 2,
        frameCount = 4,
        frames     = {1, 2, 3},   -- 使用第2/3/4帧
        iconFrame  = 3,           -- 图标显示第4帧（0-based）
        fps        = 1.2,
        owned      = false,       -- 初始未拥有，通过签到活动解锁
        rarity     = "SR",
        rarityColor = { 160, 100, 255, 255 },
        scoreBonus = 500,         -- 排行榜时装加分
        atkBonus   = 0.01,        -- 全英雄攻击加成（解锁即生效）
    },

}

-- 按 slot 分组（扩展时在此添加 ARMOR_COSTUMES / AURA_COSTUMES 等）
M.SLOTS = {
    { id = "wing", label = "翅膀", icon = "image/icon_wing_slot.png", costumes = M.WING_COSTUMES },
}

-- ============================================================================
-- 运行时状态（持久化到文件）
-- ============================================================================

---@type table<string, string|nil>  slot -> costumeId（已装备）
local _equipped = {
    wing = nil,
}

---@type table<string, boolean>  costumeId -> true（动态解锁，补充 owned=false 的初始状态）
local _unlockedExtra = {}

--- 获取指定槽位已装备的 costumeId
---@param slot string
---@return string|nil
function M.GetEquipped(slot)
    return _equipped[slot]
end

--- 获取指定槽位已装备的定义表
---@param slot string
---@return table|nil
function M.GetEquippedDef(slot)
    local id = _equipped[slot]
    if not id then return nil end
    for _, def in ipairs(M.WING_COSTUMES) do
        if def.id == id then return def end
    end
    return nil
end

--- 装备时装（slot = "wing", id = costumeId 或 nil=卸下）
---@param slot string
---@param id string|nil
function M.Equip(slot, id)
    _equipped[slot] = id
    M.Save()
    -- 装备变动时同步上传时装排行榜分数
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if ok then
        local bonus = M.GetTotalScoreBonus()
        LB.UploadCostume(bonus)
    end
end

--- 检查是否已装备
---@param slot string
---@param id string
---@return boolean
function M.IsEquipped(slot, id)
    return _equipped[slot] == id
end

--- 检查时装是否已拥有（静态 owned=true 或 动态解锁）
---@param id string
---@return boolean
function M.IsOwned(id)
    if _unlockedExtra[id] then return true end
    for _, slot in ipairs(M.SLOTS) do
        if slot.costumes then
            for _, def in ipairs(slot.costumes) do
                if def.id == id and def.owned then return true end
            end
        end
    end
    return false
end

--- 动态解锁时装（由签到/活动系统调用）
---@param id string
function M.Unlock(id)
    if _unlockedExtra[id] then return end  -- 已解锁
    _unlockedExtra[id] = true
    -- 同步到 def.owned（保持 GetGlobalAtkBonus/GetTotalScoreBonus 正常工作）
    for _, slot in ipairs(M.SLOTS) do
        if slot.costumes then
            for _, def in ipairs(slot.costumes) do
                if def.id == id then
                    def.owned = true
                end
            end
        end
    end
    M.Save()
    -- 解锁后同步排行榜加分
    local ok, LB = pcall(require, "Game.LeaderboardData")
    if ok then LB.UploadCostume(M.GetTotalScoreBonus()) end
end

--- 计算所有已解锁时装的全英雄攻击加成系数（解锁即生效，叠加）
--- 返回值示例：0.01 表示 +1%，使用时乘以基础攻击
---@return number
function M.GetGlobalAtkBonus()
    local total = 0
    for _, slot in ipairs(M.SLOTS) do
        if slot.costumes then
            for _, def in ipairs(slot.costumes) do
                if def.owned and def.atkBonus and def.atkBonus > 0 then
                    total = total + def.atkBonus
                end
            end
        end
    end
    return total
end

--- 计算所有已解锁时装的总加分（用于排行榜）
---@return number
function M.GetTotalScoreBonus()
    local total = 0
    for _, slot in ipairs(M.SLOTS) do
        if slot.costumes then
            for _, def in ipairs(slot.costumes) do
                if def.owned and def.scoreBonus and def.scoreBonus > 0 then
                    total = total + def.scoreBonus
                end
            end
        end
    end
    return total
end

-- ============================================================================
-- 持久化
-- ============================================================================

function M.Save()
    local ok, cjson = pcall(require, "cjson")
    if not ok then return end
    local f = File(SAVE_FILE, FILE_WRITE)
    if not f then return end
    f:WriteString(cjson.encode({ equipped = _equipped, unlocked = _unlockedExtra }))
    f:Close()
    -- 同步到云端
    HeroData.costumeData = { equipped = _equipped, unlocked = _unlockedExtra }
    HeroData.Save()
end

function M.Load()
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
    -- 兼容旧格式（直接存 equipped 的 slot->id 表）
    if data.equipped then
        for k, v in pairs(data.equipped) do _equipped[k] = v end
    else
        for k, v in pairs(data) do _equipped[k] = v end
    end
    -- 恢复动态解锁表，并同步 def.owned
    if type(data.unlocked) == "table" then
        for id, _ in pairs(data.unlocked) do
            _unlockedExtra[id] = true
            for _, slot in ipairs(M.SLOTS) do
                if slot.costumes then
                    for _, def in ipairs(slot.costumes) do
                        if def.id == id then def.owned = true end
                    end
                end
            end
        end
    end
    -- 校验已装备时装是否拥有，未拥有则卸下
    for slotId, costumeId in pairs(_equipped) do
        if costumeId and not M.IsOwned(costumeId) then
            _equipped[slotId] = nil
        end
    end
end

-- ============================================================================
-- 内部：将 _unlockedExtra 同步到 def.owned
-- ============================================================================
local function ApplyUnlocked()
    for id, _ in pairs(_unlockedExtra) do
        for _, slot in ipairs(M.SLOTS) do
            if slot.costumes then
                for _, def in ipairs(slot.costumes) do
                    if def.id == id then def.owned = true end
                end
            end
        end
    end
    -- 校验已装备时装是否拥有，未拥有则卸下
    for slotId, costumeId in pairs(_equipped) do
        if costumeId and not M.IsOwned(costumeId) then
            _equipped[slotId] = nil
        end
    end
end

-- ============================================================================
-- SaveRegistry 注册（云端持久化）
-- ============================================================================
SaveRegistry.Register("costumeData", {
    group = "meta_game",
    order = 57,  -- 在 costumeSignInData(56) 之后
    initDefault = function()
        _equipped = { wing = nil }
        _unlockedExtra = {}
        HeroData.costumeData = nil
    end,
    serialize = function()
        return { equipped = _equipped, unlocked = _unlockedExtra }
    end,
    deserialize = function(saved)
        if saved and type(saved) == "table" then
            -- 从云端恢复
            if saved.equipped then
                for k, v in pairs(saved.equipped) do _equipped[k] = v end
            end
            if type(saved.unlocked) == "table" then
                for id, _ in pairs(saved.unlocked) do
                    _unlockedExtra[id] = true
                end
            end
        end
        -- 兼容：如果云端没数据，从本地文件加载
        if not saved or (not saved.equipped and not saved.unlocked) then
            M.Load()
        end
        ApplyUnlocked()
        HeroData.costumeData = { equipped = _equipped, unlocked = _unlockedExtra }
    end,
})

-- 初始化时加载（非 SaveRegistry 流程的兼容路径）
M.Load()

return M
