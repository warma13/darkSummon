-- Game/HeroUI/HeroDetail/EquipTab.lua
-- 英雄详情 - 装备 / 升星 / 皮肤 标签页

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local Toast = require("Game.Toast")

local EquipTab = {}

local function ShowToast(msg) Toast.Show(msg) end

-- ============================================================================
-- 装备标签页
-- ============================================================================

--- 构建装备标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
function EquipTab.BuildEquip(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local FormatBigNum = ctx.FormatBigNum

    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false

    if not isUnlocked then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "解锁英雄后可装备", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    -- 主角不参与装备系统
    if heroId == Config.LEADER_HERO.id then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "主角无装备", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    -- 未上阵英雄无装备
    if not HeroData.IsDeployed(heroId) then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "上阵后可查看装备", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    local EquipData = require("Game.EquipData")
    local heroLevel = (h and h.level) or 1
    local cards = {}

    for _, slotDef in ipairs(Config.EQUIP_SLOTS) do
        local info = EquipData.GetSlotInfo(heroId, slotDef.id)
        if info then
            local tier = info.tierDef
            local needBreak, breakInfo = EquipData.CheckBreakthrough(heroId, slotDef.id)
            local upgradeCost = EquipData.GetUpgradeCost(info.level)
            local isMaxLevel = (info.level >= Config.EQUIP_MAX_LEVEL)
            local isAtHeroCap = (info.level >= heroLevel)
            local isAtTierMax = needBreak

            -- 按钮逻辑
            local btnText, btnColor, btnClick
            if isMaxLevel then
                btnText = "满级"
                btnColor = S.btnDisabled
                btnClick = function() end
            elseif isAtTierMax then
                btnText = "突破"
                btnColor = S.btnAdvance
                btnClick = function()
                    EquipData.Breakthrough(heroId, slotDef.id)
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayUpgrade()
                    ctx.ShowHeroDetail(heroId)  -- 刷新
                end
            elseif isAtHeroCap then
                btnText = "升级"
                btnColor = S.btnDisabled
                btnClick = function() end
            else
                local canUpgrade = (HeroData.currencies.forge_iron or 0) >= upgradeCost
                btnText = "升级"
                btnColor = canUpgrade and S.btnGreen or S.btnDisabled
                btnClick = function()
                    EquipData.Upgrade(heroId, slotDef.id)
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayUpgrade()
                    ctx.ShowHeroDetail(heroId)
                end
            end

            cards[#cards + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = { 35, 25, 18, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = tier.borderColor,
                paddingTop = 5, paddingBottom = 5,
                paddingLeft = 6, paddingRight = 6,
                gap = 6,
                children = {
                    -- 装备图标
                    UI.Panel {
                        width = 40, height = 40,
                        flexShrink = 0,
                        borderRadius = 6,
                        backgroundColor = tier.bgColor,
                        borderWidth = 1,
                        borderColor = tier.color,
                        backgroundImage = "image/equip_" .. tier.id .. "_" .. slotDef.id .. ".png",
                        backgroundFit = "cover",
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                position = "absolute",
                                bottom = 0, left = 0,
                                paddingLeft = 3, paddingRight = 3,
                                backgroundColor = { 0, 0, 0, 180 },
                                borderTopRightRadius = 4,
                                children = {
                                    UI.Label { text = tostring(info.level), fontSize = 8, fontColor = tier.color, fontWeight = "bold" },
                                },
                            },
                        },
                    },
                    -- 装备名 + 属性
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        gap = 1,
                        children = (function()
                            local TemperData = require("Game.TemperData")
                            local temperBonus = TemperData.GetSlotBonus(heroId, slotDef.id)
                            local statText = slotDef.statName .. " +" .. (slotDef.fmt == "pct"
                                and string.format("%.1f%%", info.statBonus * 100)
                                or FormatBigNum(info.statBonus))
                            local labelChildren = {
                                UI.Label { text = info.fullName, fontSize = 12, fontColor = tier.color, fontWeight = "bold" },
                                UI.Label { text = statText, fontSize = 10, fontColor = S.gold },
                            }
                            -- 淬炼加成汇总：显示所有词条
                            local parts = {}
                            for statKey, val in pairs(temperBonus) do
                                if val > 0 then
                                    local name = statKey
                                    for _, attr in ipairs(Config.TEMPER_ATTRIBUTES) do
                                        if attr.id == statKey then name = attr.name; break end
                                    end
                                    if statKey == slotDef.stat and statKey ~= "atk" then
                                        name = slotDef.statName
                                    end
                                    parts[#parts + 1] = name .. "+" .. string.format("%.1f%%", val * 100)
                                end
                            end
                            if #parts > 0 then
                                labelChildren[#labelChildren + 1] = UI.Label {
                                    text = "淬炼: " .. table.concat(parts, " "),
                                    fontSize = 9, fontColor = { 100, 255, 100, 200 },
                                }
                            end
                            return labelChildren
                        end)(),
                    },
                    -- 操作按钮
                    UI.Panel {
                        width = 50, flexShrink = 0,
                        justifyContent = "center", alignItems = "center",
                        paddingTop = 5, paddingBottom = 5,
                        borderRadius = 6,
                        backgroundColor = btnColor,
                        onClick = btnClick,
                        children = {
                            UI.Label { text = btnText, fontSize = 11, fontColor = S.btnText, fontWeight = "bold" },
                        },
                    },
                },
            }
        end
    end

    -- 锻魂铁货币
    cards[#cards + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 4,
        marginTop = 4,
        children = {
            Currency.IconWidget(UI, "forge_iron", 14),
            UI.Label {
                text = FormatBigNum(HeroData.currencies.forge_iron or 0),
                fontSize = 12, fontColor = S.gold,
            },
        },
    }

    return UI.Panel {
        width = "100%",
        gap = 5,
        children = cards,
    }
end

-- ============================================================================
-- 升星标签页
-- ============================================================================

--- 构建升星标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
function EquipTab.BuildStarUp(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()

    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false

    if not isUnlocked then
        return UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            paddingTop = 30, paddingBottom = 30,
            children = {
                UI.Label { text = "解锁英雄后可升星", fontSize = 14, fontColor = S.dimLocked },
            },
        }
    end

    local star = h.star or 0
    local fragments = h.fragments or 0
    local tierInfo = HeroData.GetStarTierInfo(heroId)
    local isMaxStar = (star >= Config.MAX_HERO_STAR)

    -- 升星费用
    local starCost = 0
    local canStarUp = false
    if not isMaxStar then
        starCost = HeroData.GetStarUpCost(star)
        canStarUp = fragments >= starCost
    end

    -- 当前星段和下一星段信息
    local currentTierIdx = (star > 0) and HeroData.GetTierFromStar(star) or 0
    local nextTierIdx = (not isMaxStar) and HeroData.GetTierFromStar(star + 1) or currentTierIdx
    local nextTier = Config.STAR_TIERS[nextTierIdx]
    local isTierAdvance = (nextTierIdx > currentTierIdx)

    -- 当前星级显示行
    local CreateStarRows = ctx.CreateStarRows
    local currentStarRows = {}
    if star > 0 then
        currentStarRows = CreateStarRows(tierInfo.starInTier, tierInfo.color)
    end

    -- 下一星级预览
    local nextStarInTier = tierInfo.starInTier + 1
    local nextTierColor = tierInfo.color
    if isTierAdvance and nextTier then
        nextStarInTier = 1
        nextTierColor = nextTier.color
    end
    local nextStarRows = {}
    if not isMaxStar then
        nextStarRows = CreateStarRows(nextStarInTier, nextTierColor)
    end

    -- 碎片进度
    local progRatio = isMaxStar and 1.0 or math.min(1.0, fragments / math.max(1, starCost))

    local children = {}

    -- 星级变化区域：当前 → 下一级
    if not isMaxStar then
        children[#children + 1] = UI.Panel {
            width = "100%",
            backgroundColor = { 35, 25, 18, 200 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { 70, 55, 40, 150 },
            paddingTop = 12, paddingBottom = 12,
            paddingLeft = 10, paddingRight = 10,
            gap = 8,
            children = {
                -- 标题
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = tierInfo.name .. " " .. tierInfo.starInTier .. "星",
                            fontSize = 14, fontColor = tierInfo.color, fontWeight = "bold",
                        },
                        UI.Label {
                            text = "  →  ",
                            fontSize = 14, fontColor = S.dim,
                        },
                        UI.Label {
                            text = (isTierAdvance and nextTier) and (nextTier.name .. " 1星") or (tierInfo.name .. " " .. (tierInfo.starInTier + 1) .. "星"),
                            fontSize = 14,
                            fontColor = isTierAdvance and nextTierColor or tierInfo.color,
                            fontWeight = "bold",
                        },
                    },
                },

                -- 星级图形对比（当前 → 下一）
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    alignItems = "center",
                    gap = 12,
                    children = {
                        -- 当前星级
                        UI.Panel {
                            alignItems = "center",
                            gap = 2,
                            children = {
                                #currentStarRows > 0 and UI.Panel {
                                    alignItems = "center", gap = 0,
                                    children = currentStarRows,
                                } or UI.Label { text = "无星", fontSize = 12, fontColor = S.dim },
                            },
                        },
                        UI.Label { text = "→", fontSize = 18, fontColor = S.gold },
                        -- 下一星级
                        UI.Panel {
                            alignItems = "center",
                            gap = 2,
                            children = {
                                UI.Panel {
                                    alignItems = "center", gap = 0,
                                    children = nextStarRows,
                                },
                            },
                        },
                    },
                },

                -- 属性加成预览
                (function()
                    local baseStat = HeroData.GetHeroStats(heroId)
                    local nextAtk = baseStat.atk * (1 + 0.02)
                    local atkDiff = nextAtk - baseStat.atk
                    return UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "升星加成",
                                fontSize = 11, fontColor = S.dim,
                            },
                            UI.Label {
                                text = "攻击 +" .. string.format("%.0f", atkDiff) .. "  攻速 +2%",
                                fontSize = 12, fontColor = { 100, 255, 100, 255 },
                            },
                        },
                    }
                end)(),
            },
        }
    else
        children[#children + 1] = UI.Panel {
            width = "100%",
            backgroundColor = { 35, 25, 18, 200 },
            borderRadius = 8,
            paddingTop = 16, paddingBottom = 16,
            alignItems = "center",
            children = {
                UI.Panel { alignItems = "center", gap = 0, children = currentStarRows },
                UI.Label {
                    text = "已达最高星级",
                    fontSize = 14, fontColor = S.gold, fontWeight = "bold", marginTop = 8,
                },
            },
        }
    end

    -- 碎片进度条
    children[#children + 1] = UI.Panel {
        width = "100%",
        backgroundColor = { 35, 25, 18, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 70, 55, 40, 150 },
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 12, paddingRight = 12,
        gap = 6,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "英雄碎片", fontSize = 12, fontColor = S.dim },
                    UI.Label {
                        text = isMaxStar and tostring(fragments) or (fragments .. "/" .. starCost),
                        fontSize = 12,
                        fontColor = canStarUp and { 100, 255, 100, 255 } or S.white,
                        fontWeight = "bold",
                    },
                },
            },
            UI.Panel {
                width = "100%",
                height = 16,
                borderRadius = 8,
                backgroundColor = S.progBg,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = math.max(3, math.floor(progRatio * 100)) .. "%",
                        height = "100%",
                        borderRadius = 8,
                        backgroundColor = canStarUp and { 100, 255, 100, 255 } or { 200, 160, 60, 255 },
                    },
                },
            },
        },
    }

    -- 升星按钮
    if not isMaxStar then
        children[#children + 1] = UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 4,
            children = {
                UI.Panel {
                    width = "70%",
                    paddingTop = 10, paddingBottom = 10,
                    borderRadius = 10,
                    backgroundColor = canStarUp and S.btnGreen or S.btnDisabled,
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if not canStarUp then
                            ShowToast("碎片不足")
                            return
                        end
                        local ok, msg = HeroData.StarUp(heroId)
                        if ok then
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayUpgrade()
                            ShowToast("升星成功! " .. msg)
                        else
                            ShowToast(msg)
                        end
                        ctx.ShowHeroDetail(heroId)
                    end,
                    children = {
                        UI.Label {
                            text = isTierAdvance and "突破升星" or "升星",
                            fontSize = 16, fontColor = S.btnText, fontWeight = "bold",
                        },
                    },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        gap = 6,
        children = children,
    }
end

-- ============================================================================
-- 皮肤标签页（占位）
-- ============================================================================

--- 构建皮肤标签页内容
---@param ctx table
---@param heroId string
---@param heroDef table
function EquipTab.BuildSkin(ctx, heroId, heroDef)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    return UI.Panel {
        width = "100%",
        alignItems = "center", justifyContent = "center",
        paddingTop = 40, paddingBottom = 40,
        children = {
            UI.Label { text = "皮肤系统", fontSize = 16, fontColor = S.dim },
            UI.Label { text = "敬请期待", fontSize = 13, fontColor = S.dimLocked, marginTop = 6 },
        },
    }
end

return EquipTab
