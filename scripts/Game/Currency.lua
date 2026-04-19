-- Game/Currency.lua
-- 暗黑塔防游戏 - 货币体系管理
-- 7种货币：暗魂(战斗内) + 冥晶/噬魂石/虚空契约/暗影精华(战斗外) + 碎片

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local EventBus = require("Game.EventBus")

local Currency = {}

-- ============================================================================
-- 货币图标（统一管理）
-- ============================================================================

--- 创建货币图标 UI 组件（Panel + backgroundImage）
--- 需要外部传入 UI 模块
---@param UI any       UI 模块引用
---@param currencyId string  货币 ID
---@param size? number       图标尺寸（默认 16）
---@return any  UI.Panel 组件
function Currency.IconWidget(UI, currencyId, size)
    size = size or 16
    local def = Config.CURRENCY[currencyId]
    local img = def and def.image
    if img then
        return UI.Panel {
            width = size, height = size,
            backgroundImage = img,
            backgroundFit = "contain",
            pointerEvents = "none",
            flexShrink = 0,
        }
    end
    -- 无图片回退为文字
    return UI.Label {
        text = (def and def.name and string.sub(def.name, 1, 3)) or "?",
        fontSize = size - 2,
        fontColor = (def and def.color) and { def.color[1], def.color[2], def.color[3], 255 } or { 200, 200, 200, 255 },
        pointerEvents = "none",
    }
end

--- 获取货币图片路径
---@param currencyId string
---@return string|nil
function Currency.GetImage(currencyId)
    local def = Config.CURRENCY[currencyId]
    return def and def.image
end

-- ============================================================================
-- 货币定义（对齐 Config.CURRENCY）
-- ============================================================================

--- 战斗外货币 ID 列表
Currency.TYPES = {
    "nether_crystal",   -- 冥晶（升级用）
    "devour_stone",     -- 噬魂石（进阶用）
    "forge_iron",       -- 锻魂铁（装备用）
    "void_pact",        -- 虚空契约（招募用）
    "shadow_essence",   -- 暗影精粹（兑换用）
    "shadow_orb",       -- 幽影珠（高级货币）
    "pale_jade",        -- 粹玉（淬炼用）
    "rainbow_jade",     -- 封魂玉（锁定淬炼孔位）
    "frost_pact",       -- 霜誓契约（限定招募用）
    "rift_dust",        -- 裂隙之尘（符文洗练用）
    "rune_seal",        -- 符文封印（洗练锁定用）
    "abyss_crystal",    -- 深渊结晶（定向洗练用）
}

--- 获取货币显示信息
---@param currencyId string
---@return table  { name, icon, color, usage }
function Currency.GetInfo(currencyId)
    return Config.CURRENCY[currencyId] or { name = currencyId, icon = "unknown", color = { 200, 200, 200 } }
end

-- ============================================================================
-- 货币读写（统一走 HeroData.currencies）
-- ============================================================================

--- 获取货币余额
---@param currencyId string
---@return number
function Currency.Get(currencyId)
    if currencyId == "ad_ticket" then
        local ok, ARD = pcall(require, "Game.AdReliefData")
        if ok then return ARD.GetTickets() end
        return 0
    end
    return HeroData.currencies[currencyId] or 0
end

--- 设置货币余额
---@param currencyId string
---@param amount number
function Currency.Set(currencyId, amount)
    local newVal = math.max(0, math.floor(amount))
    HeroData.currencies[currencyId] = newVal
    EventBus.emit(EventBus.EVENT.CURRENCY_CHANGED, { type = currencyId, delta = 0, balance = newVal })
end

--- 增加货币
---@param currencyId string
---@param amount number
function Currency.Add(currencyId, amount)
    if amount <= 0 then return end
    if currencyId == "ad_ticket" then
        local ok, ARD = pcall(require, "Game.AdReliefData")
        if ok then ARD.AddTickets(amount) end
        return
    end
    local delta = math.floor(amount)
    local newVal = (HeroData.currencies[currencyId] or 0) + delta
    HeroData.currencies[currencyId] = newVal
    EventBus.emit(EventBus.EVENT.CURRENCY_CHANGED, { type = currencyId, delta = delta, balance = newVal })
end

--- 消耗货币（检查是否足够）
---@param currencyId string
---@param amount number
---@return boolean  success
function Currency.Spend(currencyId, amount)
    if currencyId == "ad_ticket" then
        local ok, ARD = pcall(require, "Game.AdReliefData")
        if ok then return ARD.SpendTickets(amount) end
        return false
    end
    local current = HeroData.currencies[currencyId] or 0
    if current < amount then
        return false
    end
    local delta = math.floor(amount)
    local newVal = current - delta
    HeroData.currencies[currencyId] = newVal
    EventBus.emit(EventBus.EVENT.CURRENCY_CHANGED, { type = currencyId, delta = -delta, balance = newVal })
    return true
end

--- 检查是否拥有足够的货币
---@param currencyId string
---@param amount number
---@return boolean
function Currency.Has(currencyId, amount)
    if currencyId == "ad_ticket" then
        local ok, ARD = pcall(require, "Game.AdReliefData")
        if ok then return ARD.GetTickets() >= amount end
        return false
    end
    return (HeroData.currencies[currencyId] or 0) >= amount
end

-- ============================================================================
-- 战斗内暗魂（dark_soul，不可被技能修改）
-- ============================================================================

--- 计算击杀暗魂掉落（纯粹由敌人类型决定，技能不能修改）
---@param enemyType string  "normal" / "elite" / "boss"
---@return number
function Currency.GetDarkSoulDrop(enemyType)
    return Config.DARK_SOUL_DROP[enemyType] or Config.DARK_SOUL_DROP.normal
end

--- 记录战斗内暗魂收集（暂存，结算时转化）
---@param amount number
function Currency.CollectDarkSoul(amount)
    local newVal = (HeroData.currencies.dark_soul or 0) + amount
    HeroData.currencies.dark_soul = newVal
    EventBus.emit(EventBus.EVENT.CURRENCY_CHANGED, { type = "dark_soul", delta = amount, balance = newVal })
end

--- 获取当前暗魂数量
---@return number
function Currency.GetDarkSouls()
    return HeroData.currencies.dark_soul or 0
end

-- ============================================================================
-- 碎片系统（英雄专属碎片 + 万能碎片）
-- ============================================================================

--- 添加英雄专属碎片
---@param heroId string
---@param amount number
function Currency.AddHeroShards(heroId, amount)
    HeroData.AddFragments(heroId, amount)
end

--- 获取英雄专属碎片数量
---@param heroId string
---@return number
function Currency.GetHeroShards(heroId)
    local h = HeroData.Get(heroId)
    return (h and h.fragments) or 0
end

--- 添加万能碎片（按品质分类存储）
---@param rarity string  "N" / "R" / "SR" / "SSR" / "UR" / "LR"
---@param amount number
function Currency.AddUniversalShards(rarity, amount)
    local key = "universal_shard_" .. rarity
    HeroData.currencies[key] = (HeroData.currencies[key] or 0) + amount
end

--- 获取万能碎片数量
---@param rarity string
---@return number
function Currency.GetUniversalShards(rarity)
    local key = "universal_shard_" .. rarity
    return HeroData.currencies[key] or 0
end

--- 使用万能碎片代替英雄碎片（用于升星）
---@param heroId string
---@param amount number  需要的碎片数量
---@return boolean success
---@return number usedCount
function Currency.UseUniversalShards(heroId, amount)
    -- 确定英雄品质
    local rarity = "R"
    for _, towerDef in ipairs(Config.TOWER_TYPES) do
        if towerDef.id == heroId then
            rarity = towerDef.rarity or "R"
            break
        end
    end

    local key = "universal_shard_" .. rarity
    local available = HeroData.currencies[key] or 0
    if available < amount then
        return false, 0
    end

    HeroData.currencies[key] = available - amount
    HeroData.AddFragments(heroId, amount)
    return true, amount
end

-- ============================================================================
-- 暗影精华兑换
-- ============================================================================

--- 执行暗影精华兑换
---@param exchangeIndex number  Config.ESSENCE_EXCHANGE 的索引
---@return boolean success
---@return string msg
function Currency.ExchangeEssence(exchangeIndex)
    local exchange = Config.ESSENCE_EXCHANGE[exchangeIndex]
    if not exchange then
        return false, "无效的兑换选项"
    end

    local cost = exchange.cost
    if not Currency.Has("shadow_essence", cost) then
        return false, "暗影精华不足(需要" .. cost .. ")"
    end

    Currency.Spend("shadow_essence", cost)

    if exchange.type == "universal_shard" then
        Currency.AddUniversalShards(exchange.rarity, exchange.amount)
        local info = Config.RARITY_COLORS[exchange.rarity]
        return true, "获得" .. exchange.rarity .. "万能碎片×" .. exchange.amount
    elseif exchange.type == "awakening_mat" then
        -- 觉醒材料（后续扩展）
        HeroData.currencies.awakening_mat = (HeroData.currencies.awakening_mat or 0) + exchange.amount
        return true, "获得觉醒材料×" .. exchange.amount
    end

    return false, "未知兑换类型"
end

-- ============================================================================
-- 结算货币转化（旧货币名→新货币名映射）
-- ============================================================================

--- 结算奖励中的货币映射
--- 旧系统: gold, diamonds, advanceStones, recruitTokens
--- 新系统: nether_crystal, devour_stone, void_pact
---@param rewards table  结算奖励表
function Currency.ApplySettleRewards(rewards)
    -- gold → nether_crystal（升级用）
    if rewards.gold then
        Currency.Add("nether_crystal", rewards.gold)
    end
    -- advanceStones → devour_stone（进阶用）
    if rewards.advanceStones then
        Currency.Add("devour_stone", rewards.advanceStones)
    end
    -- recruitTokens → void_pact（招募用）
    if rewards.recruitTokens then
        Currency.Add("void_pact", rewards.recruitTokens)
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 确保所有货币字段存在（旧存档迁移）
function Currency.EnsureFields()
    local defaults = {
        dark_soul = 0,
        nether_crystal = 0,
        devour_stone = 0,
        forge_iron = 0,
        void_pact = 0,
        shadow_essence = 0,
        awakening_mat = 0,
        pale_jade = 0,
        rainbow_jade = 0,
        frost_pact = 0,
        rift_dust = 0,
        rune_seal = 0,
        abyss_crystal = 0,
    }
    for key, default in pairs(defaults) do
        if HeroData.currencies[key] == nil then
            HeroData.currencies[key] = default
        end
    end
    -- 万能碎片
    for rarity, _ in pairs(Config.RARITY) do
        local key = "universal_shard_" .. rarity
        if HeroData.currencies[key] == nil then
            HeroData.currencies[key] = 0
        end
    end

    -- 迁移错误存储在 currencies 里的仓库道具（bug修复前遗留数据）
    local itemMigrations = { "random_ur_shard_box", "ssr_shard_random_box", "r_shard_random_box" }
    for _, itemId in ipairs(itemMigrations) do
        local count = HeroData.currencies[itemId]
        if count and count > 0 then
            local InventoryData = require("Game.InventoryData")
            InventoryData.Add(itemId, count)
            HeroData.currencies[itemId] = 0
            print("[Currency] 迁移仓库道具 " .. itemId .. " ×" .. count)
        end
    end

    -- 迁移旧货币到新货币（如果旧字段存在）
    if HeroData.currencies.gold and HeroData.currencies.gold > 0 then
        Currency.Add("nether_crystal", HeroData.currencies.gold)
        HeroData.currencies.gold = 0
    end
    if HeroData.currencies.diamonds and HeroData.currencies.diamonds > 0 then
        Currency.Add("shadow_essence", HeroData.currencies.diamonds)
        HeroData.currencies.diamonds = 0
    end
    if HeroData.currencies.advanceStones and HeroData.currencies.advanceStones > 0 then
        Currency.Add("devour_stone", HeroData.currencies.advanceStones)
        HeroData.currencies.advanceStones = 0
    end
    if HeroData.currencies.recruitTokens and HeroData.currencies.recruitTokens > 0 then
        Currency.Add("void_pact", HeroData.currencies.recruitTokens)
        HeroData.currencies.recruitTokens = 0
    end
end

-- ============================================================================
-- 统一奖励发放
-- ============================================================================

--- 统一发放奖励，自动按类型路由
--- currency → Currency.Add（直接加）
--- chest   → ChestData.Add（直接加）
--- item    → InventoryData.Add（放仓库）
---@param reward {type:string, id:string, amount:number}
---@return boolean success
function Currency.GrantReward(reward)
    if not reward or not reward.type or not reward.id then return false end
    local amount = reward.amount or 1

    if reward.type == "currency" then
        Currency.Add(reward.id, amount)
    elseif reward.type == "chest" then
        local ChestData = require("Game.ChestData")
        ChestData.Add(reward.id, amount)
        ChestData.Save()
    elseif reward.type == "item" then
        local InventoryData = require("Game.InventoryData")
        InventoryData.Add(reward.id, amount)
    else
        print("[Currency.GrantReward] Unknown reward type: " .. tostring(reward.type))
        return false
    end
    return true
end

--- 批量发放奖励列表
---@param rewards {type:string, id:string, amount:number}[]
function Currency.GrantRewards(rewards)
    if not rewards then return end
    for _, r in ipairs(rewards) do
        Currency.GrantReward(r)
    end
end

return Currency
