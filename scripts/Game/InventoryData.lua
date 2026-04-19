-- Game/InventoryData.lua
-- 仓库物品数据管理

local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Config   = require("Game.Config")

local InventoryData = {}

-- ============================================================================
-- 物品定义
-- ============================================================================

---@class ItemDef
---@field id string
---@field name string
---@field desc string
---@field icon string       -- Currency icon id 或特殊标识
---@field rarity string     -- "N"|"R"|"SR"|"SSR"|"UR"
---@field stackable boolean
---@field use fun(amount: number): string  -- 使用函数，返回结果描述

--- 福袋随机金额（概率分布：600以上综合概率8%）
---@return number
local function RollBagAmount()
    local roll = math.random(1, 100)
    if roll <= 8 then
        return math.random(600, 1288)
    elseif roll <= 30 then
        return math.random(300, 599)
    elseif roll <= 65 then
        return math.random(200, 299)
    else
        return math.random(128, 199)
    end
end

--- 查找英雄信息（名称、头像路径）
---@param heroId string
---@return string name, string|nil avatarImage
local function FindHeroInfo(heroId)
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then
            local icon = td.icon or heroId
            return td.name or heroId, "image/avatars/avatar_" .. icon .. ".png"
        end
    end
    return heroId, nil
end

--- 冥晶礼包：等效4小时挂机冥晶收益（与挂机系统公式对齐）
---@return number
local function CalcCrystalReward()
    local stage = HeroData.stats and HeroData.stats.bestStage or 1
    if stage < 1 then stage = 1 end
    local crystalPerStage = Config.EstimateStageDrop(stage)  -- 第一个返回值为冥晶
    local stagesPer4h = (4 * 3600 / Config.IDLE_STAGE_SECONDS) * Config.IDLE_RATE
    return math.floor(crystalPerStage * stagesPer4h)
end

--- 物品模板表
InventoryData.ITEM_DEFS = {
    shadow_essence_bag = {
        id = "shadow_essence_bag",
        name = "暗影精粹福袋",
        desc = "打开可获得128~1288暗影精粹\n（600以上概率仅8%）",
        icon = "shadow_essence_bag",
        rarity = "SR",
        stackable = true,
        use = function(amount)
            local total = 0
            for _ = 1, amount do
                total = total + RollBagAmount()
            end
            Currency.Add("shadow_essence", total)
            return "获得暗影精粹 ×" .. total, {
                { icon = Currency.GetImage("shadow_essence"), name = "暗影精粹", amount = total },
            }
        end,
    },
    ur_shard_box = {
        id = "ur_shard_box",
        name = "万能UR碎片箱",
        desc = "打开可选择1个UR英雄获得碎片",
        icon = "ur_shard_box",
        rarity = "UR",
        stackable = true,
        useMode = "select_hero",  -- 自选英雄碎片模式
        selectPool = "UR",
        --- 定向使用：指定英雄和数量
        ---@param amount number 消耗箱子数量
        ---@param heroId string 目标英雄ID
        use = function(amount, heroId)
            HeroData.AddFragments(heroId, amount)
            local name, avatar = FindHeroInfo(heroId)
            local rewards = {
                { icon = "👤", name = name .. " 碎片", amount = amount, avatarImage = avatar },
            }
            return name .. "碎片 ×" .. amount, rewards
        end,
    },
    -- 随机UR碎片箱（随机1个UR碎片）
    random_ur_shard_box = {
        id = "random_ur_shard_box",
        name = "随机UR碎片箱",
        desc = "打开随机获得1个UR英雄碎片",
        icon = "random_ur_shard_box",
        rarity = "UR",
        stackable = true,
        use = function(amount)
            local urPool = Config.RECRUIT_POOL["UR"]
            local results = {}
            for _ = 1, amount do
                local heroId = urPool[math.random(1, #urPool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    -- R/SR/SSR 随机碎片礼包
    r_shard_random_box = {
        id = "r_shard_random_box",
        name = "R随机碎片礼包",
        desc = "打开随机获得1个R英雄碎片",
        icon = "r_shard_random_box",
        rarity = "R",
        stackable = true,
        use = function(amount)
            local pool = Config.RECRUIT_POOL["R"]
            local results = {}
            for _ = 1, amount do
                local heroId = pool[math.random(1, #pool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    sr_shard_random_box = {
        id = "sr_shard_random_box",
        name = "SR随机碎片礼包",
        desc = "打开随机获得1个SR英雄碎片",
        icon = "sr_shard_random_box",
        rarity = "SR",
        stackable = true,
        use = function(amount)
            local pool = Config.RECRUIT_POOL["SR"]
            local results = {}
            for _ = 1, amount do
                local heroId = pool[math.random(1, #pool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    ssr_shard_random_box = {
        id = "ssr_shard_random_box",
        name = "SSR随机碎片礼包",
        desc = "打开随机获得1个SSR英雄碎片",
        icon = "ssr_shard_random_box",
        rarity = "SSR",
        stackable = true,
        use = function(amount)
            local pool = Config.RECRUIT_POOL["SSR"]
            local results = {}
            for _ = 1, amount do
                local heroId = pool[math.random(1, #pool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    -- R/SR/SSR 自选碎片礼包（暂存仓库，使用时需要选择英雄，先给随机）
    r_shard_select_box = {
        id = "r_shard_select_box",
        name = "R自选碎片礼包",
        desc = "打开可选择1个R英雄获得碎片",
        icon = "r_shard_select_box",
        rarity = "R",
        stackable = true,
        use = function(amount)
            -- TODO: 实现选择UI，暂用随机
            local pool = Config.RECRUIT_POOL["R"]
            local results = {}
            for _ = 1, amount do
                local heroId = pool[math.random(1, #pool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    sr_shard_select_box = {
        id = "sr_shard_select_box",
        name = "SR自选碎片礼包",
        desc = "打开可选择1个SR英雄获得碎片",
        icon = "sr_shard_select_box",
        rarity = "SR",
        stackable = true,
        use = function(amount)
            local pool = Config.RECRUIT_POOL["SR"]
            local results = {}
            for _ = 1, amount do
                local heroId = pool[math.random(1, #pool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    ssr_shard_select_box = {
        id = "ssr_shard_select_box",
        name = "SSR自选碎片礼包",
        desc = "打开可选择1个SSR英雄获得碎片",
        icon = "ssr_shard_select_box",
        rarity = "SSR",
        stackable = true,
        use = function(amount)
            local pool = Config.RECRUIT_POOL["SSR"]
            local results = {}
            for _ = 1, amount do
                local heroId = pool[math.random(1, #pool)]
                HeroData.AddFragments(heroId, 1)
                results[heroId] = (results[heroId] or 0) + 1
            end
            local parts = {}
            local rewards = {}
            for heroId, count in pairs(results) do
                local name, avatar = FindHeroInfo(heroId)
                parts[#parts + 1] = name .. "碎片 ×" .. count
                rewards[#rewards + 1] = {
                    icon = "👤",
                    name = name .. " 碎片",
                    amount = count,
                    avatarImage = avatar,
                }
            end
            return table.concat(parts, "  "), rewards
        end,
    },
    -- 资源副本门票（不可手动使用，在副本入口自动消耗）
    dungeon_ticket = {
        id = "dungeon_ticket",
        name = "资源副本门票",
        desc = "每日免费次数用完后，消耗门票可额外挑战资源副本1次（在副本入口自动消耗）",
        icon = "dungeon_ticket",
        rarity = "R",
        stackable = true,
    },
    -- 货币福袋
    nether_crystal_pack = {
        id = "nether_crystal_pack",
        name = "冥晶礼包",
        desc = "使用获得当前挂机收益的4小时冥晶",
        icon = "nether_crystal_pack",
        rarity = "R",
        stackable = true,
        use = function(amount)
            local total = 0
            for _ = 1, amount do
                total = total + CalcCrystalReward()
            end
            Currency.Add("nether_crystal", total)
            return "获得冥晶 ×" .. total, {
                { icon = Currency.GetImage("nether_crystal"), name = "冥晶", amount = total },
            }
        end,
    },
    devour_stone_bag = {
        id = "devour_stone_bag",
        name = "噬魂石福袋",
        desc = "打开可获得50~500噬魂石",
        icon = "devour_stone_bag",
        rarity = "SR",
        stackable = true,
        use = function(amount)
            local total = 0
            for _ = 1, amount do
                total = total + math.random(50, 500)
            end
            Currency.Add("devour_stone", total)
            return "获得噬魂石 ×" .. total, {
                { icon = Currency.GetImage("devour_stone"), name = "噬魂石", amount = total },
            }
        end,
    },
    forge_iron_bag = {
        id = "forge_iron_bag",
        name = "锻魂铁福袋",
        desc = "打开可获得30~300锻魂铁",
        icon = "forge_iron_bag",
        rarity = "SR",
        stackable = true,
        use = function(amount)
            local total = 0
            for _ = 1, amount do
                total = total + math.random(30, 300)
            end
            Currency.Add("forge_iron", total)
            return "获得锻魂铁 ×" .. total, {
                { icon = Currency.GetImage("forge_iron"), name = "锻魂铁", amount = total },
            }
        end,
    },
}

-- ============================================================================
-- 数据存储
-- ============================================================================
-- inventory = { {id="shadow_essence_bag", count=3}, ... }

--- 初始化/加载
function InventoryData.Load()
    local saved = HeroData.activityData and HeroData.activityData.inventory
    if saved then
        InventoryData.items = saved
    else
        InventoryData.items = {}
    end
end

--- 保存
function InventoryData.Save()
    if not HeroData.activityData then
        HeroData.activityData = {}
    end
    HeroData.activityData.inventory = InventoryData.items
    HeroData.Save()
end

--- 获取物品数量
---@param itemId string
---@return number
function InventoryData.GetCount(itemId)
    if not InventoryData.items then InventoryData.Load() end
    for _, slot in ipairs(InventoryData.items) do
        if slot.id == itemId then return slot.count end
    end
    return 0
end

--- 添加物品
---@param itemId string
---@param amount number
function InventoryData.Add(itemId, amount)
    if amount <= 0 then return end
    -- 检查物品定义是否存在
    if not InventoryData.ITEM_DEFS[itemId] then
        print("[InventoryData] Unknown item: " .. itemId)
        return
    end
    -- 自动初始化（防止未调用 Load 时 items 为 nil）
    if not InventoryData.items then
        InventoryData.Load()
    end
    for _, slot in ipairs(InventoryData.items) do
        if slot.id == itemId then
            slot.count = slot.count + amount
            InventoryData.Save()
            return
        end
    end
    -- 新物品
    InventoryData.items[#InventoryData.items + 1] = { id = itemId, count = amount }
    InventoryData.Save()
end

--- 使用物品
---@param itemId string
---@param amount number
---@param ... any 额外参数（如 heroId）
---@return boolean success
---@return string msg
function InventoryData.Use(itemId, amount, ...)
    amount = amount or 1
    if not InventoryData.items then InventoryData.Load() end
    local def = InventoryData.ITEM_DEFS[itemId]
    if not def then return false, "物品不存在" end

    local count = InventoryData.GetCount(itemId)
    if count < amount then return false, "数量不足" end

    -- 扣减
    for _, slot in ipairs(InventoryData.items) do
        if slot.id == itemId then
            slot.count = slot.count - amount
            -- 清除空槽
            if slot.count <= 0 then
                for j, s in ipairs(InventoryData.items) do
                    if s.id == itemId then
                        table.remove(InventoryData.items, j)
                        break
                    end
                end
            end
            break
        end
    end

    local result, rewards = def.use(amount, ...)
    InventoryData.Save()
    return true, result, rewards
end

--- 获取所有物品（用于 UI 展示）
---@return table[]  { id, count, def }
function InventoryData.GetAll()
    if not InventoryData.items then InventoryData.Load() end
    local list = {}
    for _, slot in ipairs(InventoryData.items) do
        local def = InventoryData.ITEM_DEFS[slot.id]
        if def and slot.count > 0 then
            list[#list + 1] = {
                id = slot.id,
                count = slot.count,
                def = def,
            }
        end
    end
    return list
end

--- 仓库是否为空
---@return boolean
function InventoryData.IsEmpty()
    if not InventoryData.items then InventoryData.Load() end
    for _, slot in ipairs(InventoryData.items) do
        if slot.count > 0 then return false end
    end
    return true
end

return InventoryData
