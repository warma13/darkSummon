-- Game/RecruitUI/GachaResult.lua
-- 抽卡结果展示 + 购买契约弹窗（常驻池/限定池共用）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local RecruitData = require("Game.RecruitData")
local Currency = require("Game.Currency")
local RewardDisplay = require("Game.RewardDisplay")
local HeroAvatar = require("Game.HeroAvatar")

local GachaResult = {}

--- 创建单个奖励卡片（与宝箱弹窗同风格）
---@param UI any
---@param emoji string
---@param name string
---@param amount number
---@param borderColor table
---@param avatarImage string|nil
---@param isNew boolean|nil
---@param isLimitedHero boolean|nil
---@return any
function GachaResult.CreateRewardCard(UI, emoji, name, amount, borderColor, avatarImage, isNew, isLimitedHero)
    local iconChild
    if avatarImage then
        iconChild = UI.Panel {
            width = "80%", aspectRatio = 1.0,
            borderRadius = 8,
            overflow = "hidden",
            backgroundImage = avatarImage,
            backgroundFit = "cover",
        }
    else
        iconChild = UI.Label {
            text = emoji,
            fontSize = 32,
        }
    end

    local bottomChild
    if isNew then
        bottomChild = UI.Label {
            text = "NEW!",
            fontSize = 14,
            fontColor = { 255, 255, 100, 255 },
            fontWeight = "bold",
        }
    else
        bottomChild = UI.Label {
            text = "x" .. amount,
            fontSize = 14,
            fontColor = { 255, 220, 80, 255 },
            fontWeight = "bold",
        }
    end

    -- 限定英雄特殊边框
    local cardBorderColor = borderColor
    local cardBorderWidth = isNew and 3 or 2
    if isLimitedHero then
        cardBorderColor = { 130, 210, 255, 255 }
        cardBorderWidth = 3
    end

    local cardChildren = {
        iconChild,
        UI.Panel {
            position = "absolute",
            bottom = -2, left = 0,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = { borderColor[1], borderColor[2], borderColor[3], 230 },
            borderRadius = 3,
            children = {
                UI.Label {
                    text = name,
                    fontSize = 8,
                    fontColor = { 20, 16, 32, 255 },
                },
            },
        },
        bottomChild,
        -- UP 标记
        isLimitedHero and UI.Panel {
            position = "absolute",
            top = -4, right = -4,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = { 130, 210, 255, 255 },
            borderRadius = 4,
            children = {
                UI.Label {
                    text = "UP",
                    fontSize = 8,
                    fontColor = { 10, 20, 40, 255 },
                    fontWeight = "bold",
                },
            },
        } or nil,
    }

    return UI.Panel {
        width = "30%",
        aspectRatio = 1.0,
        marginBottom = 10,
        backgroundColor = isNew and { 50, 45, 30, 240 } or { 40, 35, 30, 230 },
        borderRadius = 8,
        borderWidth = cardBorderWidth,
        borderColor = isNew and { 255, 220, 60, 255 } or cardBorderColor,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        children = cardChildren,
    }
end

--- 显示招募结果弹窗（常驻池 + 限定池共用）
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param currentTab string
---@param results table
---@param poolName string  "深渊祭坛" 或 "限定祭坛"
---@param refreshFn function
function GachaResult.ShowResultPopup(UI, pageRoot, RARITY_COLORS, currentTab, results, poolName, refreshFn)
    if not pageRoot or not UI then return end
    poolName = poolName or "深渊祭坛"

    local old = pageRoot:FindById("recruitResultPopup")
    if old then pageRoot:RemoveChild(old) end

    -- 聚合相同英雄：合并碎片数量，保留 isNew / isLimitedHero 标记
    local merged = {}       -- heroId -> aggregated entry
    local mergedOrder = {}  -- 保持首次出现顺序
    for _, r in ipairs(results) do
        local key = r.heroId or r.heroName
        if merged[key] then
            merged[key].fragments = merged[key].fragments + (r.fragments or 0)
        else
            merged[key] = {
                heroId   = r.heroId,
                heroName = r.heroName,
                rarity   = r.rarity,
                fragments = r.fragments or 0,
                isNew    = r.isNew,
                isLimitedHero = r.isLimitedHero,
            }
            mergedOrder[#mergedOrder + 1] = key
        end
        -- 只要有一次是 isNew，就标记
        if r.isNew then merged[key].isNew = true end
        if r.isLimitedHero then merged[key].isLimitedHero = true end
    end

    -- 按稀有度排序：LR > UR > SSR > SR > R > N
    local RARITY_ORDER = { LR = 6, UR = 5, SSR = 4, SR = 3, R = 2, N = 1 }
    table.sort(mergedOrder, function(a, b)
        local ra = RARITY_ORDER[merged[a].rarity] or 0
        local rb = RARITY_ORDER[merged[b].rarity] or 0
        if ra ~= rb then return ra > rb end
        return merged[a].fragments > merged[b].fragments
    end)

    local rewardCards = {}
    for _, key in ipairs(mergedOrder) do
        local r = merged[key]
        local rc = RARITY_COLORS[r.rarity] or { 200, 200, 200 }
        rewardCards[#rewardCards + 1] = GachaResult.CreateRewardCard(
            UI,
            "👤",
            r.rarity .. " " .. r.heroName,
            r.fragments,
            { rc[1], rc[2], rc[3], 200 },
            r.heroId and HeroAvatar.GetPath(r.heroId) or nil,
            r.isNew,
            r.isLimitedHero
        )
    end

    local popup = UI.Panel {
        id = "recruitResultPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 200 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%",
                alignItems = "center",
                paddingTop = 40,
                flexShrink = 0,
                children = {
                    UI.Panel {
                        paddingLeft = 14, paddingRight = 14,
                        paddingTop = 3, paddingBottom = 3,
                        backgroundColor = currentTab == "limited"
                            and { 60, 120, 180, 255 }
                            or { 140, 100, 220, 255 },
                        borderRadius = 4,
                        marginBottom = 6,
                        children = {
                            UI.Label {
                                text = poolName,
                                fontSize = 12,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        text = "恭喜获得",
                        fontSize = 28,
                        fontColor = { 255, 255, 255, 255 },
                        fontWeight = "bold",
                        marginBottom = 12,
                    },
                },
            },
            UI.ScrollView {
                width = "100%",
                flex = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "center",
                        gap = 8,
                        paddingLeft = 16, paddingRight = 16,
                        paddingTop = 4, paddingBottom = 12,
                        children = rewardCards,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                paddingLeft = 24, paddingRight = 24,
                paddingTop = 10, paddingBottom = 6,
                flexShrink = 0,
                children = {
                    UI.Button {
                        text = "确定",
                        fontSize = 16,
                        variant = "primary",
                        width = "100%",
                        height = 46,
                        onClick = function(self)
                            local p = pageRoot:FindById("recruitResultPopup")
                            if p then pageRoot:RemoveChild(p) end
                            refreshFn()
                        end,
                    },
                },
            },
            UI.Label {
                text = "点击确定返回招募界面",
                fontSize = 11,
                fontColor = { 180, 140, 100, 150 },
                marginTop = 2,
                marginBottom = 8,
                flexShrink = 0,
            },
        },
    }

    pageRoot:AddChild(popup)
end

--- 执行常驻池招募并展示结果
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param currentTab string
---@param pullCount number
---@param isFree boolean
---@param refreshFn function
function GachaResult.DoRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, pullCount, isFree, refreshFn)
    local ok, result = RecruitData.DoPull(pullCount, isFree)
    if ok then
        local AudioManager = require("Game.AudioManager")
        AudioManager.PlayRecruit()
        -- 招募周里程碑追踪
        local okRMD, RMD = pcall(require, "Game.RecruitMilestoneData")
        if okRMD and RMD then RMD.AddCount(pullCount) end
        -- 成就：累计招募次数追踪
        local okAch, AchData = pcall(require, "Game.AchievementData")
        if okAch and AchData then AchData.AddRecruitCount(pullCount) end
        GachaResult.ShowResultPopup(UI, pageRoot, RARITY_COLORS, currentTab, result, "深渊祭坛", refreshFn)
    else
        print("[RecruitUI] Pull failed: " .. tostring(result))
        refreshFn()
    end
end

--- 执行限定池招募并展示结果
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param currentTab string
---@param pullCount number
---@param refreshFn function
function GachaResult.DoLimitedRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, pullCount, refreshFn, bannerCfg)
    local LBD = require("Game.LimitedBannerData")
    local cfg = bannerCfg or require("Game.Config").LIMITED_BANNER
    local ok, result = LBD.DoPull(cfg, pullCount)
    if ok then
        local AudioManager = require("Game.AudioManager")
        AudioManager.PlayRecruit()
        -- 招募周里程碑追踪
        local okRMD, RMD = pcall(require, "Game.RecruitMilestoneData")
        if okRMD and RMD then RMD.AddCount(pullCount) end
        -- 成就：累计招募次数追踪
        local okAch, AchData = pcall(require, "Game.AchievementData")
        if okAch and AchData then AchData.AddRecruitCount(pullCount) end
        GachaResult.ShowResultPopup(UI, pageRoot, RARITY_COLORS, currentTab, result, "限定祭坛", refreshFn)
    else
        local Toast = require("Game.Toast")
        Toast.Show(tostring(result), { 255, 100, 100 })
        print("[RecruitUI] Limited pull failed: " .. tostring(result))
        refreshFn()
    end
end

--- 显示购买契约弹窗
---@param UI any
---@param pageRoot any
---@param defaultQty number
---@param currencyType string  "void_pact" 或 "frost_pact"
---@param refreshFn function
function GachaResult.ShowBuyPopup(UI, pageRoot, defaultQty, currencyType, refreshFn)
    if not pageRoot or not UI then return end
    currencyType = currencyType or "void_pact"

    local old = pageRoot:FindById("buyPactPopup")
    if old then pageRoot:RemoveChild(old) end

    local isLimited = (currencyType == "frost_pact")
    local UNIT_PRICE = isLimited and Config.LIMITED_BANNER.buyPrice or 300
    local BUY_CURRENCY = isLimited and Config.LIMITED_BANNER.buyCurrency or "shadow_essence"
    local PACT_NAME = isLimited and "霜誓契约" or "虚空契约"
    local MIN_QTY = 1
    local MAX_QTY = 99
    local qty = defaultQty or 1

    local qtyLabel, priceLabel, buyBtnLabel, buyBtn

    local function updateDisplay()
        local totalCost = qty * UNIT_PRICE
        local canAfford = Currency.Get(BUY_CURRENCY) >= totalCost
        if qtyLabel then qtyLabel:SetValue(tostring(qty)) end
        if priceLabel then priceLabel:SetText(tostring(totalCost)) end
        if buyBtnLabel then buyBtnLabel:SetText("购买 ×" .. qty) end
        if buyBtn then
            buyBtn:SetStyle({
                backgroundColor = canAfford
                    and (isLimited and { 40, 80, 140, 255 } or { 100, 70, 180, 255 })
                    or { 60, 55, 65, 200 },
                borderColor = canAfford
                    and (isLimited and { 100, 180, 240, 200 } or { 180, 140, 255, 200 })
                    or { 80, 75, 85, 120 },
            })
        end
        if priceLabel then
            priceLabel:SetStyle({
                fontColor = canAfford
                    and { 255, 220, 100, 255 }
                    or { 140, 130, 130, 180 },
            })
        end
        if buyBtnLabel then
            buyBtnLabel:SetStyle({
                fontColor = canAfford
                    and { 255, 255, 255, 255 }
                    or { 140, 130, 130, 180 },
            })
        end
    end

    local function changeQty(delta)
        qty = math.max(MIN_QTY, math.min(MAX_QTY, qty + delta))
        updateDisplay()
    end

    local function doBuy()
        local totalCost = qty * UNIT_PRICE
        if not Currency.Has(BUY_CURRENCY, totalCost) then
            local Toast = require("Game.Toast")
            Toast.Show("暗影精粹不足", { 255, 100, 80 })
            return
        end
        Currency.Spend(BUY_CURRENCY, totalCost)
        Currency.GrantReward({ type = "currency", id = currencyType, amount = qty }, "GachaBuyPact")
        local Toast = require("Game.Toast")
        Toast.Show("获得" .. PACT_NAME .. " ×" .. qty, isLimited and { 130, 210, 255 } or { 180, 140, 255 })
        local p = pageRoot:FindById("buyPactPopup")
        if p then pageRoot:RemoveChild(p) end
        refreshFn()
    end

    local function qtyBtn(text, delta)
        return UI.Panel {
            width = 40, height = 40,
            borderRadius = 8,
            backgroundColor = isLimited and { 30, 60, 100, 255 } or { 70, 55, 110, 255 },
            borderWidth = 1,
            borderColor = isLimited and { 80, 140, 200, 180 } or { 140, 110, 200, 180 },
            justifyContent = "center",
            alignItems = "center",
            pointerEvents = "auto",
            onClick = function() changeQty(delta) end,
            children = {
                UI.Label {
                    text = text,
                    fontSize = 22,
                    fontColor = { 255, 255, 255, 255 },
                    fontWeight = "bold",
                },
            },
        }
    end

    qtyLabel = UI.TextField {
        id = "buyQtyLabel",
        value = tostring(qty),
        fontSize = 18,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
        maxLength = 2,
        width = 60, height = 40,
        backgroundColor = { 35, 28, 55, 255 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { 80, 65, 120, 150 },
        onChange = function(self, value)
            local n = tonumber(value)
            if n then
                qty = math.max(MIN_QTY, math.min(MAX_QTY, math.floor(n)))
            end
            updateDisplay()
        end,
        onSubmit = function(self, value)
            local n = tonumber(value)
            if n then
                qty = math.max(MIN_QTY, math.min(MAX_QTY, math.floor(n)))
            end
            updateDisplay()
        end,
    }

    priceLabel = UI.Label {
        id = "buyPriceLabel",
        text = tostring(qty * UNIT_PRICE),
        fontSize = 16,
        fontColor = { 255, 220, 100, 255 },
        fontWeight = "bold",
    }

    buyBtnLabel = UI.Label {
        id = "buyBtnLabel",
        text = "购买 ×" .. qty,
        fontSize = 15,
        fontColor = { 255, 255, 255, 255 },
        fontWeight = "bold",
    }

    buyBtn = UI.Panel {
        width = "100%",
        borderRadius = 10,
        backgroundColor = isLimited and { 40, 80, 140, 255 } or { 100, 70, 180, 255 },
        borderWidth = 1,
        borderColor = isLimited and { 100, 180, 240, 200 } or { 180, 140, 255, 200 },
        justifyContent = "center",
        alignItems = "center",
        flexDirection = "column",
        gap = 1,
        paddingTop = 8, paddingBottom = 8,
        pointerEvents = "auto",
        onClick = function() doBuy() end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    Currency.IconWidget(UI, BUY_CURRENCY, 16),
                    priceLabel,
                },
            },
            buyBtnLabel,
        },
    }

    local function closePopup()
        local p = pageRoot:FindById("buyPactPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    local popup = UI.Panel {
        id = "buyPactPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        onClick = function() closePopup() end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = isLimited and { 15, 25, 45, 250 } or { 25, 20, 40, 250 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = isLimited and { 80, 150, 220, 200 } or { 120, 90, 180, 200 },
                paddingTop = 18, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                flexDirection = "column",
                alignItems = "center",
                gap = 14,
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "购买",
                        fontSize = 20,
                        fontColor = isLimited and { 130, 210, 255, 255 } or { 220, 180, 255, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "购买" .. PACT_NAME,
                        fontSize = 13,
                        fontColor = { 180, 160, 220, 200 },
                    },
                    UI.Panel {
                        width = 72, height = 72,
                        borderRadius = 12,
                        backgroundColor = isLimited and { 25, 45, 75, 255 } or { 50, 35, 70, 255 },
                        borderWidth = 2,
                        borderColor = isLimited and { 80, 160, 220, 200 } or { 200, 40, 40, 200 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            Currency.IconWidget(UI, currencyType, 40),
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 12,
                        children = {
                            qtyBtn("−", -1),
                            qtyLabel,
                            qtyBtn("+", 1),
                        },
                    },
                    buyBtn,
                },
            },
        },
    }

    pageRoot:AddChild(popup)
    updateDisplay()
end

return GachaResult
