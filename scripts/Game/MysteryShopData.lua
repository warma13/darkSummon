-- Game/MysteryShopData.lua
-- 神秘商店数据：幽影珠兑换时装
-- 网格显示，与精粹商店风格一致
-- v1.1

local Currency    = require("Game.Currency")
local CostumeData = require("Game.CostumeData")
local HeroData    = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local M = {}

--- 商品定义
--- cost: 幽影珠花费
--- costumeId: 对应 CostumeData 中的时装 ID
--- slot: 装备槽位（用于自动装备）
M.SHOP_ITEMS = {
    {
        id         = "mystery_weapon_void_scepter",
        name       = "虚空权杖",
        desc       = "来自深渊的暗影权杖",
        icon       = "image/weapon_void_scepter_20260430064038.png",
        cost       = 100,
        costumeId  = "weapon_void_scepter",
        slot       = "weapon",
        rarity     = "SSR",
        rarityColor = { 255, 180, 50, 255 },
    },
    {
        id         = "mystery_weapon_magic_broom",
        name       = "魔法扫帚",
        desc       = "缠绕紫色魔法光带的扫帚，帚尾散发星光粒子",
        icon       = "image/weapon_magic_broom_20260430094920.png",
        cost       = 80,
        costumeId  = "weapon_magic_broom",
        slot       = "weapon",
        rarity     = "SR",
        rarityColor = { 160, 120, 255, 255 },
    },
    {
        id         = "mystery_weapon_dragon_blade",
        name       = "龙骨巨剑",
        desc       = "由远古龙骨铸成的巨剑，剑身缠绕不灭龙魂之火",
        icon       = "image/weapon_dragon_blade_20260430091553.png",
        cost       = 120,
        costumeId  = "weapon_dragon_blade",
        slot       = "weapon",
        rarity     = "SSR",
        rarityColor = { 200, 60, 60, 255 },
    },
    {
        id         = "mystery_aura_divine_ring",
        name       = "神圣光环",
        desc       = "紫金色神秘能量光环，散发古老符文之力",
        icon       = "image/aura_divine_ring_20260430082349.png",
        cost       = 100,
        costumeId  = "aura_divine_ring",
        slot       = "aura",
        rarity     = "SSR",
        rarityColor = { 200, 160, 255, 255 },
    },
    {
        id         = "mystery_particle_starfly",
        name       = "星光流萤",
        desc       = "环绕角色飞舞的冰蓝星光粒子，攻击时星辉爆发",
        icon       = "image/particle_glow_20260430105243.png",
        cost       = 90,
        costumeId  = "particle_starfly",
        slot       = "particle",
        rarity     = "SR",
        rarityColor = { 120, 200, 255, 255 },
    },
}

-- ── 持久化 ──────────────────────────────────────────────────────────────────
local SAVE_KEY = "mystery_shop"

local function getRecords()
    if not HeroData.mysteryShopData then
        HeroData.mysteryShopData = { bought = {} }
    end
    return HeroData.mysteryShopData
end

SaveRegistry.Register(SAVE_KEY, {
    group = "meta_game",
    order = 75,
    serialize = function()
        return HeroData.mysteryShopData
    end,
    deserialize = function(saved, _saveData)
        HeroData.mysteryShopData = saved or nil
    end,
})

--- 是否已购买
function M.IsBought(itemId)
    local rec = getRecords()
    return rec.bought[itemId] == true
end

--- 购买
function M.Purchase(itemId)
    local item
    for _, it in ipairs(M.SHOP_ITEMS) do
        if it.id == itemId then item = it; break end
    end
    if not item then return false, "商品不存在" end

    if M.IsBought(itemId) then
        return false, "已拥有该时装"
    end

    if not Currency.Has("shadow_orb", item.cost) then
        return false, "幽影珠不足（需要" .. item.cost .. "）"
    end

    -- 扣币
    Currency.Spend("shadow_orb", item.cost)

    -- 解锁时装
    CostumeData.Unlock(item.costumeId)

    -- 记录已购买
    local rec = getRecords()
    rec.bought[itemId] = true

    HeroData.Save(true)

    return true, "兑换成功！获得 " .. item.name

end

--- 是否有可购买商品（红点用）
function M.HasAvailable()
    for _, item in ipairs(M.SHOP_ITEMS) do
        if not M.IsBought(item.id) and Currency.Has("shadow_orb", item.cost) then
            return true
        end
    end
    return false
end

return M
