-- Game/HeroUI/HeroCard.lua
-- 英雄卡片网格（收藏弹出层和英雄收藏弹出层共享）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local LBD = require("Game.LimitedBannerData")

local HeroAvatar = require("Game.HeroAvatar")

local HeroCard = {}

--- 获取排序后的英雄列表（排除主角）
--- 排序优先级：已上阵 → 已解锁（按品质高→低） → 未解锁（按品质高→低）
---@param ctx table  HeroUI 模块
---@return table[]
function HeroCard.GetSortedHeroes(ctx)
    local RARITY_ORDER = ctx.GetRARITY_ORDER()
    local heroes = {}
    for _, td in ipairs(Config.TOWER_TYPES) do
        heroes[#heroes + 1] = td
    end
    table.sort(heroes, function(a, b)
        -- 即将推出 / 限定池未解锁排最末
        local aCs = (a.comingSoon or LBD.IsHeroPoolLocked(a.id)) and 1 or 0
        local bCs = (b.comingSoon or LBD.IsHeroPoolLocked(b.id)) and 1 or 0
        if aCs ~= bCs then return aCs < bCs end

        local aDeployed = HeroData.IsDeployed(a.id) and 1 or 0
        local bDeployed = HeroData.IsDeployed(b.id) and 1 or 0
        if aDeployed ~= bDeployed then return aDeployed > bDeployed end

        local aUnlocked = HeroData.IsUnlocked(a.id) and 1 or 0
        local bUnlocked = HeroData.IsUnlocked(b.id) and 1 or 0
        if aUnlocked ~= bUnlocked then return aUnlocked > bUnlocked end

        local ra = RARITY_ORDER[a.rarity] or 0
        local rb = RARITY_ORDER[b.rarity] or 0
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    return heroes
end

--- 创建单个英雄卡片（收藏网格用）
--- @param ctx table  HeroUI 模块
--- @param heroDef table
--- @param mode string|nil  "deploy"(默认) 或 "detail"
function HeroCard.CreateHeroCard(ctx, heroDef, mode)
    mode = mode or "deploy"
    local UI = ctx.GetUI()
    local S = ctx.GetS()

    local heroId = heroDef.id
    local isComingSoon = heroDef.comingSoon == true or LBD.IsHeroPoolLocked(heroId)
    local h = HeroData.Get(heroId)
    local isUnlocked = (not isComingSoon) and (h and h.unlocked or false)
    local isDeployed = (not isComingSoon) and HeroData.IsDeployed(heroId)
    local rarity = heroDef.rarity or "R"
    local fragments = (h and h.fragments) or 0
    local unlockCost = Config.RARITY_SHARD_COST[rarity] or 10

    local power = 0
    if isUnlocked then
        local stats = HeroData.GetHeroStats(heroId)
        power = stats.atk + stats.spd
    end

    local level = (h and h.level) or 1
    local cardWidth = "31%"
    local cardBg = isUnlocked and S.cardBg or S.cardLocked
    local borderColor = isUnlocked and ctx.GetRarityBorderColor(rarity) or { 60, 50, 40, 100 }

    local cardChildren = {
        -- 头像区域（使用统一组件）
        UI.Panel {
            width = "100%",
            aspectRatio = 1.0,
            children = {
                HeroAvatar.Create(heroId, {
                    preset = "card",
                    isUnlocked = isUnlocked,
                    isComingSoon = isComingSoon,
                    borderWidth = 0,
                }),
            },
        },

        -- 底部信息区域
        UI.Panel {
            width = "100%",
            paddingTop = 3, paddingBottom = 4,
            paddingLeft = 4, paddingRight = 4,
            gap = 1,
            alignItems = "center",
            children = {
                UI.Label {
                    text = heroDef.name,
                    fontSize = 10,
                    fontColor = isUnlocked and S.white or S.dimLocked,
                    fontWeight = "bold",
                    textAlign = "center",
                },
                isUnlocked and UI.Label {
                    text = "⚔ " .. ctx.FormatBigNum(power),
                    fontSize = 9,
                    fontColor = S.powerYellow,
                } or (isComingSoon and UI.Label {
                    text = "敬请期待",
                    fontSize = 9,
                    fontColor = { 160, 130, 210, 180 },
                } or UI.Label {
                    text = fragments .. "/" .. unlockCost,
                    fontSize = 9,
                    fontColor = S.dimLocked,
                }),
            },
        },
    }

    -- 上阵标记：暗色遮罩 + 大对勾覆盖整张卡（仅 deploy 模式）
    if isDeployed and mode == "deploy" then
        cardChildren[#cardChildren + 1] = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 140 },
            justifyContent = "center",
            alignItems = "center",
            zIndex = 10,
            children = {
                UI.Panel {
                    width = "60%",
                    aspectRatio = 1.0,
                    backgroundImage = "image/check_mark.png",
                    backgroundFit = "contain",
                },
            },
        }
    end

    return UI.Panel {
        width = cardWidth,
        backgroundColor = cardBg,
        borderRadius = 6,
        borderWidth = 1.5,
        borderColor = borderColor,
        onClick = isComingSoon and nil or function(self)
            if mode == "detail" then
                ctx.ShowHeroDetail(heroId)
            else
                local DeployPopup = require("Game.HeroUI.DeployPopup")
                DeployPopup.HandleCardClick(ctx, heroId, isUnlocked, isDeployed)
            end
        end,
        children = cardChildren,
    }
end

--- 创建英雄网格
--- @param ctx table  HeroUI 模块
--- @param mode string|nil  "deploy"(默认) 或 "detail"
function HeroCard.CreateHeroGrid(ctx, mode)
    mode = mode or "deploy"
    local UI = ctx.GetUI()
    local sortedHeroes = HeroCard.GetSortedHeroes(ctx)
    local cards = {}
    for _, heroDef in ipairs(sortedHeroes) do
        cards[#cards + 1] = HeroCard.CreateHeroCard(ctx, heroDef, mode)
    end

    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0,
        scrollY = true, width = "100%",
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "flex-start",
                paddingTop = 4, paddingBottom = 10,
                paddingLeft = 8, paddingRight = 8,
                gap = 6,
                children = cards,
            },
        },
    }
end

return HeroCard
