--- 兑换码配置表
--- 每个条目：code, desc, color, reward(function), allowedUser(可选)
local Currency  = require("Game.Currency")
local ChestData = require("Game.ChestData")

local CODES = {
    -- ========== 全服通用 ==========
    {
        code = "FROST100",
        desc = "霜誓契约 x100",
        color = { 130, 210, 255 },
        reward = function()
            Currency.Add("frost_pact", 100)
        end,
    },
    {
        code = "WOOD100",
        desc = "朽木宝箱 x100",
        color = { 160, 130, 80 },
        reward = function()
            ChestData.Add("wood", 100)
            ChestData.Save()
        end,
    },
    {
        code = "WORLDBOSS",
        desc = "暗影精粹 x3000",
        color = { 180, 100, 255 },
        reward = function()
            Currency.Add("shadow_essence", 3000)
        end,
    },
    {
        code = "RUNERIFT",
        desc = "霜誓契约 x30",
        color = { 130, 210, 255 },
        reward = function()
            Currency.Add("frost_pact", 30)
        end,
    },
    {
        code = "CHEST2025",
        desc = "朽木宝箱 x100 + 青铜宝箱 x50",
        color = { 160, 130, 80 },
        reward = function()
            ChestData.Add("wood", 100)
            ChestData.Add("bronze", 50)
            ChestData.Save()
        end,
    },

    -- ========== VIP 专属 ==========
    {
        code = "VIP1915921944",
        desc = "暗影精粹 x3000",
        color = { 180, 100, 255 },
        allowedUser = 1915921944,
        reward = function()
            Currency.Add("shadow_essence", 3000)
        end,
    },
    {
        code = "VIP1296664190",
        desc = "冥晶 x500000 + 暗影精粹 x1000",
        color = { 255, 180, 60 },
        allowedUser = 1296664190,
        reward = function()
            Currency.Add("nether_crystal", 500000)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP1779057459",
        desc = "符文大礼包：裂隙之尘×10000 + 封印×100 + 结晶×50 + 神话符文×6",
        color = { 255, 50, 50 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("rift_dust", 10000)
            Currency.Add("rune_seal", 100)
            Currency.Add("abyss_crystal", 50)
            local RuneData = require("Game.RuneData")
            local RuneConfig = require("Game.Config_Runes")
            for _, s in ipairs(RuneConfig.SERIES) do
                local rune = RuneData.Generate(100)
                rune.qualityId = "red"
                rune.seriesId  = s.id
                rune.maxAffixes = 4
                RuneData.AddToBag(rune)
            end
        end,
    },
    {
        code = "VIP80503484",
        desc = "霜誓契约 x10",
        color = { 130, 210, 255 },
        allowedUser = 80503484,
        reward = function()
            Currency.Add("frost_pact", 10)
        end,
    },
    {
        code = "VIP1699603952",
        desc = "铂金宝箱 x50",
        color = { 200, 220, 255 },
        allowedUser = 1699603952,
        reward = function()
            ChestData.Add("platinum", 50)
            ChestData.Save()
        end,
    },
    {
        code = "VIP346333596",
        desc = "专属奖励：暗影精粹 ×2000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 2000) end,
    },
    {
        code = "VIP881479440",
        desc = "专属奖励：暗影精粹 ×3000",
        color = { 255, 215, 0 },
        allowedUser = 881479440,
        reward = function() Currency.Add("shadow_essence", 3000) end,
    },
    {
        code = "VIP1699603952B",
        desc = "专属奖励：暗影精粹 ×5000",
        color = { 255, 215, 0 },
        allowedUser = 1699603952,
        reward = function() Currency.Add("shadow_essence", 5000) end,
    },
    {
        code = "VIP748065890",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 748065890,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP191390351",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 191390351,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP1006084432",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 1006084432,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP221406954",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 221406954,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "RUNE2025",
        desc = "符文豪华礼包：每系列每品质各1枚（36枚） + 大量货币",
        color = { 255, 215, 0 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("rift_dust", 50000)
            Currency.Add("rune_seal", 500)
            Currency.Add("abyss_crystal", 200)
            local RuneData = require("Game.RuneData")
            local RuneConfig = require("Game.Config_Runes")
            local qualities = {"white","green","blue","purple","orange","red"}
            for _, s in ipairs(RuneConfig.SERIES) do
                for _, qid in ipairs(qualities) do
                    local rune = RuneData.Generate(100)
                    rune.qualityId = qid
                    rune.seriesId  = s.id
                    if qid == "red" then rune.maxAffixes = 4
                    elseif qid == "orange" then rune.maxAffixes = 3
                    else rune.maxAffixes = 2 end
                    RuneData.AddToBag(rune)
                end
            end
        end,
    },
    {
        code = "VIP1564171575",
        desc = "专属奖励：铂金宝箱 ×1000",
        color = { 200, 220, 255 },
        allowedUser = 1564171575,
        reward = function()
            ChestData.Add("platinum", 1000)
            ChestData.Save()
        end,
    },
    {
        code = "VIP274791815",
        desc = "专属奖励：冥晶 ×3000000 + 暗影精粹 ×1000",
        color = { 255, 180, 60 },
        allowedUser = 274791815,
        reward = function()
            Currency.Add("nether_crystal", 3000000)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP897945791",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 897945791,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP346333596B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP420284230",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 420284230,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP897945791B",
        desc = "专属奖励：冥晶礼包 ×15 + 免广告券 ×5 + 暗影精粹 ×1000",
        color = { 140, 80, 200 },
        allowedUser = 897945791,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("nether_crystal_pack", 15)
            Currency.Add("ad_ticket", 5)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP346333596C",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP274791815B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 274791815,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP1564171575",
        desc = "专属奖励：试练塔挑战券 ×1000",
        color = { 80, 200, 220 },
        allowedUser = 1564171575,
        reward = function()
            local TTD = require("Game.TrialTowerData")
            TTD.AddTickets(1000)
        end,
    },
    {
        code = "VIP1564171575B",
        desc = "专属奖励：试练塔挑战券 ×1000",
        color = { 80, 200, 220 },
        allowedUser = 1564171575,
        reward = function()
            local TTD = require("Game.TrialTowerData")
            TTD.AddTickets(1000)
        end,
    },
    {
        code = "VIP1564171575D",
        desc = "专属奖励：憎恨之地挑战券 ×100",
        color = { 160, 40, 50 },
        allowedUser = 1564171575,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("hatred_ticket", 100)
        end,
    },
    {
        code = "VIP1564171575C",
        desc = "专属奖励：虚空契约 ×1000",
        color = { 160, 100, 255 },
        allowedUser = 1564171575,
        reward = function()
            Currency.Add("void_pact", 1000)
        end,
    },
    {
        code = "VIP1779057459B",
        desc = "专属奖励：冥晶 ×100000000",
        color = { 255, 180, 60 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("nether_crystal", 100000000)
        end,
    },
    {
        code = "VIP1779057459C",
        desc = "专属奖励：免广告券 ×100000000",
        color = { 100, 220, 180 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("ad_ticket", 100000000)
        end,
    },
    {
        code = "VIP1779057459D",
        desc = "专属奖励：招募券自选包 ×1000",
        color = { 255, 160, 60 },
        allowedUser = 1779057459,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("recruit_ticket_select_box", 1000)
        end,
    },
    {
        code = "VIP1779057459E",
        desc = "专属奖励：冥晶矿洞挑战券 ×1",
        color = { 140, 80, 200 },
        allowedUser = 1779057459,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("dungeon_ticket_crystal", 1)
        end,
    },
    {
        code = "VIP420284230B",
        desc = "专属奖励：招募自选包 ×6 + 暗影精粹 ×2000",
        color = { 255, 160, 60 },
        allowedUser = 420284230,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("recruit_ticket_select_box", 6)
            Currency.Add("shadow_essence", 2000)
        end,
    },
    {
        code = "VIP502127674",
        desc = "专属奖励：招募自选包 ×128 + 暗影精粹 ×1000",
        color = { 255, 160, 60 },
        allowedUser = 502127674,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("recruit_ticket_select_box", 128)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP1261081970",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 1261081970,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP346333596D",
        desc = "专属奖励：暗影精粹 ×4000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 4000) end,
    },
    {
        code = "VIP978257249",
        desc = "专属奖励：暗影精粹 ×2000",
        color = { 255, 215, 0 },
        allowedUser = 978257249,
        reward = function() Currency.Add("shadow_essence", 2000) end,
    },
    {
        code = "VIP1779057459F",
        desc = "专属奖励：翠影秘境券 ×1000",
        color = { 60, 180, 100 },
        allowedUser = 1779057459,
        reward = function()
            local ED = require("Game.EmeraldDungeonData")
            ED.AddTickets(1000)
        end,
    },
    {
        code = "VIP502127674B",
        desc = "专属奖励：深渊裂隙挑战券 ×3 + 暗影精粹 ×1000",
        color = { 140, 80, 200 },
        allowedUser = 502127674,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("abyss_ticket", 3)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP978257249B",
        desc = "专属奖励：暗影精粹 ×3000",
        color = { 255, 215, 0 },
        allowedUser = 978257249,
        reward = function() Currency.Add("shadow_essence", 3000) end,
    },
    {
        code = "VIP346333596E",
        desc = "专属奖励：暗影精粹 ×2000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 2000) end,
    },
    {
        code = "VIP1840951947",
        desc = "专属奖励：暗影精粹 ×4000",
        color = { 255, 215, 0 },
        allowedUser = 1840951947,
        reward = function() Currency.Add("shadow_essence", 4000) end,
    },
    {
        code = "VIP1261081970B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 1261081970,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP897945791C",
        desc = "专属奖励：暗影精粹 ×2000",
        color = { 255, 215, 0 },
        allowedUser = 897945791,
        reward = function() Currency.Add("shadow_essence", 2000) end,
    },
    {
        code = "VIP2135680770",
        desc = "专属奖励：暗影精粹 ×7000",
        color = { 255, 215, 0 },
        allowedUser = 2135680770,
        reward = function() Currency.Add("shadow_essence", 7000) end,
    },
    {
        code = "VIP978257249C",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 978257249,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP502127674C",
        desc = "专属奖励：暗影精粹 ×2000",
        color = { 255, 215, 0 },
        allowedUser = 502127674,
        reward = function() Currency.Add("shadow_essence", 2000) end,
    },
    {
        code = "VIP2135680770B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 2135680770,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP1840951947B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 1840951947,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP1779057459G",
        desc = "专属奖励：冥晶 ×5000亿 + 锻魂铁 ×1000万",
        color = { 255, 180, 60 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("nether_crystal", 500000000000)
            Currency.Add("forge_iron", 10000000)
        end,
    },
    {
        code = "VIP1779057459H",
        desc = "专属奖励：白玉 ×1亿 + 彩玉 ×1亿",
        color = { 180, 120, 255 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("pale_jade", 100000000)
            Currency.Add("rainbow_jade", 100000000)
        end,
    },
}

return CODES
