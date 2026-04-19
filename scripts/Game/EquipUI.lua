-- Game/EquipUI.lua
-- 装备页面 UI（对齐咸鱼之王装备界面）
-- 布局: 顶部英雄选择栏 → 装备列表（4件） → 套装加成 → 一键升级

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local EquipData = require("Game.EquipData")
local Currency = require("Game.Currency")
local TemperUI = require("Game.TemperUI")
local TemperData = require("Game.TemperData")

local RuneUI = require("Game.RuneUI")

local EquipUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type string
local selectedHero = nil  -- 当前查看装备的英雄ID
---@type string
local currentTab = "equip"  -- "equip" | "rune"

--- 格式化大数字
---@param n number
---@return string
local function FormatNumber(n)
    if n >= 100000000 then
        return string.format("%.2f亿", n / 100000000)
    elseif n >= 10000 then
        return string.format("%.1f万", n / 10000)
    end
    return tostring(n)
end

--- 创建装备页面
---@param uiModule any
---@return any
function EquipUI.CreatePage(uiModule)
    UI = uiModule
    TemperUI.Init(UI)

    -- 默认选中第一个已上阵英雄（主角不参与装备）
    if not selectedHero then
        if #HeroData.deployed > 0 then
            selectedHero = HeroData.deployed[1]
        end
    end

    pageRoot = UI.Panel {
        id = "equipPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 15, 12, 25, 255 },
        children = {},
    }

    EquipUI.Refresh()
    return pageRoot
end

--- 刷新页面内容
function EquipUI.Refresh()
    if not pageRoot or not UI then return end

    -- 确保有默认选中（切页回来或首次上阵后）
    if not selectedHero or not HeroData.IsDeployed(selectedHero) then
        selectedHero = nil
        if #HeroData.deployed > 0 then
            selectedHero = HeroData.deployed[1]
        end
    end

    pageRoot:ClearChildren()

    -- 根据当前 tab 渲染不同内容
    if currentTab == "rune" then
        -- 符文页面：直接委托 RuneUI 填充内容
        RuneUI.Init(UI)
        RuneUI.RenderInto(pageRoot, EquipUI.Refresh)
    else
        -- 装备页面
        -- 英雄选择栏（横向滚动，已上阵英雄 + 主角）
        pageRoot:AddChild(EquipUI.CreateHeroSelector())

        if selectedHero then
            -- 装备列表（4件装备卡片）
            pageRoot:AddChild(EquipUI.CreateEquipList())
            -- 套装加成信息
            pageRoot:AddChild(EquipUI.CreateSetBonusBar())
            -- 底部按钮栏
            pageRoot:AddChild(EquipUI.CreateBottomButtons())
        else
            -- 无上阵英雄提示
            pageRoot:AddChild(UI.Panel {
                width = "100%",
                flexGrow = 1,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "请先在英雄页上阵英雄",
                        fontSize = 14,
                        fontColor = { 150, 140, 130, 180 },
                    },
                },
            })
        end
    end

    -- 底部 Tab 栏 + 货币（紧贴主标签栏上方）
    pageRoot:AddChild(EquipUI.CreateTabBar())
end

--- 创建 Tab 标签 helper
---@param label string
---@param tabKey string
local function _CreateTab(label, tabKey)
    local isActive = (currentTab == tabKey)
    return UI.Panel {
        flex = 1,
        height = 32,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = isActive and { 80, 50, 160, 240 } or { 30, 25, 50, 150 },
        borderRadius = 6,
        borderWidth = isActive and 2 or 1,
        borderColor = isActive and { 160, 120, 255, 255 } or { 60, 50, 90, 100 },
        pointerEvents = "auto",
        onClick = function(self)
            if currentTab ~= tabKey then
                currentTab = tabKey
                EquipUI.Refresh()
            end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = 15,
                fontColor = isActive and { 255, 255, 255, 255 } or { 140, 130, 160, 200 },
                fontWeight = isActive and "bold" or "normal",
                pointerEvents = "none",
            },
        },
    }
end

--- 顶部 Tab 栏 + 右侧货币
function EquipUI.CreateTabBar()
    -- 根据当前 tab 决定显示哪种货币
    local currencyWidget
    if currentTab == "rune" then
        -- 符文货币由 RuneUI 底部栏显示，此处不重复
        currencyWidget = UI.Panel {}
    else
        currencyWidget = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            children = {
                Currency.IconWidget(UI, "forge_iron", 16),
                UI.Label {
                    text = "锻魂铁 " .. FormatNumber(HeroData.currencies.forge_iron or 0),
                    fontSize = 14,
                    fontColor = Config.CURRENCY.forge_iron.color,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingTop = 8, paddingBottom = 4,
        paddingLeft = 12, paddingRight = 12,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        flexShrink = 0,
        gap = 10,
        children = {
            -- 左侧 Tab 按钮组
            UI.Panel {
                flexDirection = "row",
                gap = 6,
                width = 160,
                children = {
                    _CreateTab("装备", "equip"),
                    _CreateTab("符文", "rune"),
                },
            },
            -- 右侧货币
            currencyWidget,
        },
    }
end

--- 英雄选择栏（全身头像，占满一行，平均分）
function EquipUI.CreateHeroSelector()
    local heroes = {}
    -- 只加已上阵英雄（主角不参与装备系统）
    for _, heroId in ipairs(HeroData.deployed) do
        heroes[#heroes + 1] = heroId
    end

    local items = {}
    for _, heroId in ipairs(heroes) do
        local isSelected = (heroId == selectedHero)
        local heroName = heroId
        local heroIcon = nil
        local heroRarity = "N"
        -- 查找英雄信息
        if heroId == Config.LEADER_HERO.id then
            heroName = Config.LEADER_HERO.name
            heroIcon = Config.LEADER_HERO.icon
            heroRarity = Config.LEADER_HERO.rarity or "SSR"
        else
            for _, td in ipairs(Config.TOWER_TYPES) do
                if td.id == heroId then
                    heroName = td.name
                    heroIcon = td.icon
                    heroRarity = td.rarity or "N"
                    break
                end
            end
        end

        local rarityColor = HeroData.GetRarityColor and HeroData.GetRarityColor(heroRarity) or { 60, 50, 80, 200 }
        local rarityBorder = HeroData.GetRarityBorderColor and HeroData.GetRarityBorderColor(heroRarity) or { 80, 70, 100, 255 }
        local avatarPath = heroIcon and ("image/avatars/avatar_" .. heroIcon .. ".png") or nil

        items[#items + 1] = UI.Panel {
            flex = 1,
            aspectRatio = 1,
            alignItems = "center",
            justifyContent = "flex-end",
            backgroundColor = isSelected and { 80, 50, 140, 200 } or { 30, 25, 45, 150 },
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and { 160, 120, 255, 255 } or rarityBorder,
            overflow = "hidden",
            pointerEvents = "auto",
            onClick = function(self)
                selectedHero = heroId
                EquipUI.Refresh()
            end,
            children = {
                -- 全身头像（覆盖整个卡片）
                avatarPath and UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    backgroundImage = avatarPath,
                    backgroundFit = "cover",
                    pointerEvents = "none",
                } or UI.Label {
                    text = "👤",
                    fontSize = 32,
                    pointerEvents = "none",
                },
                -- 底部名称条
                UI.Panel {
                    position = "absolute",
                    bottom = 0, left = 0, right = 0,
                    height = 20,
                    justifyContent = "center",
                    alignItems = "center",
                    backgroundColor = { 0, 0, 0, 180 },
                    pointerEvents = "none",
                    children = {
                        UI.Label {
                            text = string.sub(heroName, 1, 6),
                            fontSize = 10,
                            fontColor = isSelected and { 255, 255, 255, 255 } or { 200, 190, 220, 230 },
                            fontWeight = isSelected and "bold" or "normal",
                            pointerEvents = "none",
                        },
                    },
                },
                -- 选中高亮边框光效
                isSelected and UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    borderRadius = 7,
                    borderWidth = 1,
                    borderColor = { 200, 170, 255, 100 },
                    pointerEvents = "none",
                } or nil,
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 6,
        flexShrink = 0,
        flexDirection = "row",
        gap = 6,
        children = items,
    }
end

--- 装备列表（4件装备卡片）
function EquipUI.CreateEquipList()
    local cards = {}

    -- 无上阵英雄时显示提示
    if not selectedHero then
        return UI.Panel {
            width = "100%",
            flex = 1,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "请先在英雄页上阵英雄",
                    fontSize = 14,
                    fontColor = { 150, 140, 130, 180 },
                },
            },
        }
    end

    for _, slotDef in ipairs(Config.EQUIP_SLOTS) do
        local info = EquipData.GetSlotInfo(selectedHero, slotDef.id)
        if info then
            cards[#cards + 1] = EquipUI.CreateEquipCard(slotDef, info)
        end
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        flexDirection = "column",
        gap = 6,
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        children = cards,
    }
end

--- 单件装备卡片（对齐咸鱼之王布局）
---@param slotDef table  部位定义
---@param info table  装备信息
function EquipUI.CreateEquipCard(slotDef, info)
    local tier = info.tierDef
    local needBreak, breakInfo = EquipData.CheckBreakthrough(selectedHero, slotDef.id)
    local upgradeCost = EquipData.GetUpgradeCost(info.level)
    local hero = HeroData.heroes[selectedHero]
    local heroLevel = (hero and hero.level) or 1
    local isMaxLevel = (info.level >= Config.EQUIP_MAX_LEVEL)
    local isAtHeroCap = (info.level >= heroLevel)
    local isAtTierMax = needBreak

    -- 套装进度
    local setInfo = EquipData.GetSetInfo(selectedHero)
    local sameCount = 0
    local equips = EquipData.GetHeroEquips(selectedHero)
    for _, s in ipairs(Config.EQUIP_SLOTS) do
        local e = equips[s.id]
        if e and e.tierIdx >= info.tierIdx then
            sameCount = sameCount + 1
        end
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 4, paddingBottom = 4,
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = { 25, 20, 40, 220 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = tier.borderColor,
        gap = 8,
        children = {
            -- 左: 装备图标+等级 (30%)
            UI.Panel {
                width = "30%",
                height = "100%",
                flexShrink = 0,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = tier.bgColor,
                borderRadius = 6,
                borderWidth = 2,
                borderColor = tier.color,
                overflow = "hidden",
                backgroundImage = "image/equip_" .. tier.id .. "_" .. slotDef.id .. ".png",
                backgroundFit = "cover",
                children = {
                    -- 等级标签（左下角）
                    UI.Panel {
                        position = "absolute",
                        bottom = 0, left = 0,
                        paddingLeft = 4, paddingRight = 4,
                        paddingTop = 1, paddingBottom = 1,
                        borderTopRightRadius = 4,
                        backgroundColor = { 0, 0, 0, 180 },
                        children = {
                            UI.Label {
                                text = tostring(info.level),
                                fontSize = 9,
                                fontColor = tier.color,
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
            -- 中: 属性信息 (50%)
            UI.Panel {
                width = "50%",
                flexShrink = 0,
                gap = 2,
                children = {
                    -- 装备名
                    UI.Label {
                        text = info.fullName,
                        fontSize = 14,
                        fontColor = tier.color,
                        fontWeight = "bold",
                    },
                    -- 属性加成
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = slotDef.statName,
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 200 },
                            },
                            UI.Label {
                                text = "+" .. (slotDef.fmt == "pct"
                                    and string.format("%.1f%%", info.statBonus * 100)
                                    or FormatNumber(info.statBonus)),
                                fontSize = 14,
                                fontColor = Config.COLORS.textGold,
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 套装进度
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Panel {
                                paddingLeft = 4, paddingRight = 4,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = tier.color,
                                borderRadius = 3,
                                children = {
                                    UI.Label {
                                        text = tier.name .. "套装",
                                        fontSize = 9,
                                        fontColor = { 20, 16, 32, 255 },
                                    },
                                },
                            },
                            UI.Label {
                                text = sameCount .. "/4",
                                fontSize = 11,
                                fontColor = sameCount >= 4 and { 100, 255, 100, 255 } or { 150, 140, 170, 180 },
                            },
                        },
                    },
                },
            },
            -- 右: 升级/淬炼按钮 (20%)
            EquipUI.CreateCardButtons(slotDef, info, isMaxLevel, isAtTierMax, isAtHeroCap, needBreak, breakInfo, upgradeCost),
        },
    }
end

--- 装备卡片右侧按钮区（单按钮，按状态切换文本和行为）
function EquipUI.CreateCardButtons(slotDef, info, isMaxLevel, isAtTierMax, isAtHeroCap, needBreak, breakInfo, upgradeCost)
    local isMaxTier = (info.tierIdx >= #Config.EQUIP_TIERS)
    local temper = isMaxTier and TemperData.GetTemper(selectedHero, slotDef.id) or nil
    local isTemperUnlocked = (temper ~= nil)

    -- 确定按钮文本、样式、点击行为
    local btnText, btnVariant, btnClick, costWidget

    if isMaxTier and isTemperUnlocked then
        -- 已解锁淬炼
        btnText = "淬炼"
        btnVariant = "outline"
        btnClick = function(self)
            TemperUI.Open(pageRoot, selectedHero, slotDef.id, function()
                EquipUI.Refresh()
            end)
        end
    elseif isMaxTier and isMaxLevel then
        -- 红色满级，未解锁淬炼
        btnText = "解锁淬炼"
        local canUnlock = TemperData.CanUnlock(selectedHero, slotDef.id)
        btnVariant = canUnlock and "primary" or "outline"
        btnClick = function(self)
            local ok, msg = TemperData.Unlock(selectedHero, slotDef.id)
            local Toast = require("Game.Toast")
            if ok then
                Toast.Show("淬炼已解锁!", { 180, 140, 255 })
            else
                Toast.Show(msg, { 255, 100, 80 })
            end
            EquipUI.Refresh()
        end
        costWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2,
            children = {
                Currency.IconWidget(UI, "shadow_essence", 10),
                UI.Label {
                    text = tostring(Config.TEMPER_UNLOCK_COST),
                    fontSize = 8,
                    fontColor = { 180, 140, 255, 180 },
                },
            },
        }
    elseif isMaxLevel then
        btnText = "满级"
        btnVariant = "ghost"
        btnClick = function(self)
            local Toast = require("Game.Toast")
            Toast.Show("已达最高等级", { 255, 200, 80 })
        end
    elseif isAtHeroCap then
        -- 英雄等级限制：置灰显示升级+费用
        btnText = "升级"
        btnVariant = "ghost"
        btnClick = function(self)
            local Toast = require("Game.Toast")
            Toast.Show("装备等级不能超过英雄等级", { 255, 200, 80 })
        end
        costWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2,
            children = {
                Currency.IconWidget(UI, "forge_iron", 11),
                UI.Label {
                    text = tostring(upgradeCost),
                    fontSize = 9,
                    fontColor = { 130, 160, 200, 100 },
                },
            },
        }
    elseif isAtTierMax then
        local breakCost = breakInfo and breakInfo.cost or 0
        local canBreak = (HeroData.currencies.forge_iron or 0) >= breakCost
        btnText = "突破"
        btnVariant = canBreak and "outline" or "ghost"
        btnClick = function(self)
            if not canBreak then
                local Toast = require("Game.Toast")
                Toast.Show("锻魂铁不足，需要 " .. breakCost, { 255, 100, 80 })
                return
            end
            local ok, msg = EquipData.Breakthrough(selectedHero, slotDef.id)
            if ok then
                local AudioManager = require("Game.AudioManager")
                AudioManager.PlayUpgrade()
            else
                local Toast = require("Game.Toast")
                Toast.Show(msg, { 255, 100, 80 })
            end
            EquipUI.Refresh()
        end
        costWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2,
            children = {
                Currency.IconWidget(UI, "forge_iron", 11),
                UI.Label {
                    text = tostring(breakCost),
                    fontSize = 9,
                    fontColor = canBreak and { 130, 160, 200, 180 } or { 130, 160, 200, 100 },
                },
            },
        }
    else
        -- 自动选最佳升级档位（100→50→10→1）
        local best = EquipData.GetBestUpgradeTier(selectedHero, slotDef.id)
        local canUpgrade = (best ~= nil)
        btnText = "升级"
        if best and best.tier > 1 then
            btnText = "升级" .. best.tier .. "次"
        end
        btnVariant = canUpgrade and "primary" or "ghost"
        local costNum = 0
        if best then
            costNum = best.cost
        else
            costNum = upgradeCost
        end
        btnClick = function(self)
            if not canUpgrade then
                local Toast = require("Game.Toast")
                Toast.Show("锻魂铁不足", { 255, 100, 80 })
                return
            end
            local b = EquipData.GetBestUpgradeTier(selectedHero, slotDef.id)
            if b then
                local upgraded, cost = EquipData.UpgradeMulti(selectedHero, slotDef.id, b.tier)
                if upgraded > 0 then
                    local AudioManager = require("Game.AudioManager")
                    AudioManager.PlayUpgrade()
                end
            end
            EquipUI.Refresh()
        end
        costWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2,
            children = {
                Currency.IconWidget(UI, "forge_iron", 11),
                UI.Label {
                    text = FormatNumber(costNum),
                    fontSize = 9,
                    fontColor = canUpgrade and { 130, 160, 200, 180 } or { 130, 160, 200, 100 },
                },
            },
        }
    end

    -- 判断是否为不可操作状态（视觉置灰）
    local btnDisabled = (btnVariant == "ghost")

    return UI.Panel {
        width = "20%",
        flexShrink = 0,
        justifyContent = "center",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Button {
                text = btnText,
                fontSize = 11,
                variant = btnDisabled and "outline" or btnVariant,
                width = "100%", height = 32,
                backgroundColor = btnDisabled and { 50, 45, 65, 180 } or nil,
                textColor = btnDisabled and { 120, 110, 100, 160 } or nil,
                borderColor = btnDisabled and { 70, 60, 90, 120 } or nil,
                onClick = btnClick,
            },
            costWidget,
        },
    }
end

--- 套装加成信息栏
function EquipUI.CreateSetBonusBar()
    local setInfo = EquipData.GetSetInfo(selectedHero)
    local tier = setInfo.tierDef

    local bonusTexts = {}
    if setInfo.isComplete and setInfo.bonuses then
        for k, v in pairs(setInfo.bonuses) do
            local name = k
            if k == "atk_pct" then name = "攻击" end
            bonusTexts[#bonusTexts + 1] = name .. "+" .. math.floor(v * 100) .. "%"
        end
    end

    local bonusStr = #bonusTexts > 0 and table.concat(bonusTexts, "  ") or "未激活"

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6, paddingBottom = 6,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        backgroundColor = { 20, 18, 35, 200 },
        borderWidth = 1,
        borderColor = { 60, 50, 90, 100 },
        flexShrink = 0,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Panel {
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 2, paddingBottom = 2,
                        backgroundColor = setInfo.isComplete and tier.color or { 60, 50, 80, 150 },
                        borderRadius = 4,
                        children = {
                            UI.Label {
                                text = tier.name .. "套装",
                                fontSize = 11,
                                fontColor = setInfo.isComplete and { 20, 16, 32, 255 } or { 120, 110, 140, 200 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        text = bonusStr,
                        fontSize = 12,
                        fontColor = setInfo.isComplete and { 100, 255, 100, 255 } or { 100, 90, 120, 150 },
                    },
                },
            },
        },
    }
end

--- 底部按钮栏（一键升级）
function EquipUI.CreateBottomButtons()
    return UI.Panel {
        width = "100%",
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 6, paddingBottom = 8,
        flexDirection = "row",
        gap = 10,
        flexShrink = 0,
        children = {
            UI.Button {
                text = "一键升级",
                fontSize = 15,
                variant = "primary",
                flex = 1,
                height = 44,
                onClick = function(self)
                    local upgraded, cost = EquipData.UpgradeAllSlots(selectedHero)
                    if upgraded > 0 then
                        local Toast = require("Game.Toast")
                        Toast.Show("升级 " .. upgraded .. " 次，消耗锻魂铁 ×" .. cost, { 100, 255, 100 })
                        local AudioManager = require("Game.AudioManager")
                        AudioManager.PlayUpgrade()
                    else
                        local Toast = require("Game.Toast")
                        Toast.Show("无法升级：等级已达上限或锻魂铁不足", { 255, 200, 80 })
                    end
                    EquipUI.Refresh()
                end,
            },
        },
    }
end

--- 每帧更新（传递给淬炼面板）
---@param dt number
function EquipUI.Update(dt)
    TemperUI.Update(dt)
end

return EquipUI
