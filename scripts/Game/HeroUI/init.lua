-- Game/HeroUI/init.lua
-- 英雄养成页面 - 核心模块
-- 主页：主角 + 上阵英雄列表 + 升级/进阶
-- 子模块通过 ctx (本模块) 访问共享状态

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local InventoryUI = require("Game.InventoryUI")

local HeroUI = {}

-- 子模块（CreatePage 中延迟加载）
local HeroCard = nil
local DeployPopup = nil
local CollectionPopup = nil
local HeroDetail = nil

--- 格式化大数字 (对齐咸鱼之王显示风格)
---@param n number
---@return string
local function FormatBigNum(n)
    if n >= 100000000 then
        return string.format("%.1f亿", n / 100000000)
    elseif n >= 10000 then
        return string.format("%.1f万", n / 10000)
    else
        return tostring(math.floor(n))
    end
end

-- ============================================================================
-- 咸鱼之王简约风配色
-- ============================================================================
local S = {
    -- 页面
    pageBg        = { 42, 30, 22, 255 },
    -- 货币栏
    currBg        = { 50, 36, 26, 240 },
    currBorder    = { 75, 55, 38, 100 },
    -- 卡片
    cardBg        = { 55, 42, 32, 240 },
    cardBorder    = { 80, 62, 44, 120 },
    cardLocked    = { 45, 38, 32, 200 },
    -- 文字
    white         = { 245, 238, 225, 255 },
    dim           = { 170, 155, 135, 200 },
    dimLocked     = { 130, 120, 110, 160 },
    gold          = { 255, 215, 80, 255 },
    powerYellow   = { 255, 220, 100, 255 },
    -- 进度条
    progBg        = { 30, 22, 16, 220 },
    progFill      = { 90, 180, 65, 255 },
    progFillMax   = { 210, 165, 45, 255 },
    -- 升级按钮
    btnGreen      = { 75, 165, 55, 255 },
    btnGreenDark  = { 60, 135, 45, 255 },
    btnDisabled   = { 65, 58, 48, 220 },
    btnAdvance    = { 200, 140, 40, 255 },
    btnText       = { 255, 255, 255, 255 },
    -- 头像等级徽章
    lvBadgeBg     = { 0, 0, 0, 180 },
    -- 收藏弹出层
    overlayBg     = { 0, 0, 0, 180 },
    popupBg       = { 42, 30, 22, 250 },
    popupBorder   = { 90, 70, 50, 200 },
    checkGreen    = { 60, 200, 80, 255 },
    checkBg       = { 40, 160, 60, 240 },
    lockOverlay   = { 0, 0, 0, 120 },
    deployedCount = { 255, 200, 80, 255 },
    deployFull    = { 255, 100, 80, 255 },
    -- 收藏按钮
    collectBtn    = { 180, 120, 50, 255 },
    collectBtnBorder = { 220, 160, 70, 255 },
}

-- 稀有度排序值（高品质在前）
local RARITY_ORDER = { LR = 6, UR = 5, SSR = 4, SR = 3, R = 2, N = 1 }

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type any
local collectionOverlay = nil  -- 上阵弹出层引用
---@type any
local collectionDetailOverlay = nil  -- 英雄收藏弹出层引用
---@type any
local heroDetailOverlay = nil  -- 英雄详情面板引用

-- ============================================================================
-- 公共访问器（供子模块通过 ctx 调用）
-- ============================================================================

function HeroUI.GetUI() return UI end
function HeroUI.GetPageRoot() return pageRoot end
function HeroUI.GetS() return S end
function HeroUI.GetRARITY_ORDER() return RARITY_ORDER end
function HeroUI.FormatBigNum(n) return FormatBigNum(n) end

function HeroUI.GetCollectionOverlay() return collectionOverlay end
function HeroUI.SetCollectionOverlay(v) collectionOverlay = v end

function HeroUI.GetCollectionDetailOverlay() return collectionDetailOverlay end
function HeroUI.SetCollectionDetailOverlay(v) collectionDetailOverlay = v end

function HeroUI.GetHeroDetailOverlay() return heroDetailOverlay end
function HeroUI.SetHeroDetailOverlay(v) heroDetailOverlay = v end

--- 委托到子模块的回调（延迟绑定，避免循环引用）
function HeroUI.ShowCollectionPopup()
    DeployPopup.ShowCollectionPopup(HeroUI)
end

function HeroUI.HideCollectionPopup()
    DeployPopup.HideCollectionPopup(HeroUI)
end

function HeroUI.ShowCollectionDetailPopup()
    CollectionPopup.ShowCollectionDetailPopup(HeroUI)
end

function HeroUI.HideCollectionDetailPopup()
    CollectionPopup.HideCollectionDetailPopup(HeroUI)
end

function HeroUI.ShowHeroDetail(heroId)
    -- 即将推出的英雄不开放详情页
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId and td.comingSoon then return end
    end
    HeroDetail.ShowHeroDetail(HeroUI, heroId)
end

function HeroUI.HideHeroDetail()
    HeroDetail.HideHeroDetail(HeroUI)
end

-- ============================================================================
-- 多级升级计算
-- ============================================================================

--- 计算批量升级的总金币消耗
---@param heroId string
---@param count number  期望升的级数
---@return number totalCost, number actualLevels
local function CalcBatchUpgradeCost(heroId, count)
    local h = HeroData.Get(heroId)
    if not h then return 0, 0 end
    local cap = HeroData.GetCurrentLevelCap(heroId)
    local curLevel = h.level
    local total = 0
    local actual = 0
    for i = 0, count - 1 do
        local lv = curLevel + i
        if lv >= cap then break end
        if lv >= Config.MAX_LEVEL then break end
        total = total + HeroData.GetLevelUpCost(lv)
        actual = actual + 1
    end
    return total, actual
end

--- 计算最佳多级升级方案
---@param heroId string
---@return table|nil
local function GetBestUpgradeTier(heroId)
    local gold = HeroData.currencies.nether_crystal or 0
    local tiers = { 100, 50, 10, 1 }
    for _, tier in ipairs(tiers) do
        local cost, actual = CalcBatchUpgradeCost(heroId, tier)
        if actual >= tier and gold >= cost then
            return { tier = tier, cost = cost, actual = actual }
        end
    end
    local cost1, actual1 = CalcBatchUpgradeCost(heroId, 1)
    if actual1 >= 1 and gold >= cost1 then
        return { tier = 1, cost = cost1, actual = 1 }
    end
    return nil
end

--- 执行批量升级
---@param heroId string
---@param count number
local function DoBatchLevelUp(heroId, count)
    for _ = 1, count do
        local ok, _ = HeroData.LevelUp(heroId)
        if not ok then break end
    end
end

-- ============================================================================
-- 进阶门槛计算
-- ============================================================================

--- 获取下一个进阶门槛等级
---@param heroId string
---@return number
local function GetNextGateLevel(heroId)
    local advLv = HeroData.GetAdvanceLevel(heroId)
    local nextIdx = advLv + 1
    local gate = Config.ADVANCE_GATES[nextIdx]
    if gate then return gate.level end
    return Config.MAX_LEVEL
end

--- 获取上一个已通过的门槛等级
---@param heroId string
---@return number
local function GetPrevGateLevel(heroId)
    local advLv = HeroData.GetAdvanceLevel(heroId)
    if advLv <= 0 then return 0 end
    local gate = Config.ADVANCE_GATES[advLv]
    if gate then return gate.level end
    return 0
end

-- ============================================================================
-- 通用：Toast 提示
-- ============================================================================
local Toast = require("Game.Toast")

local function ShowToast(msg)
    Toast.Show(msg)
end

-- ============================================================================
-- 通用：稀有度颜色
-- ============================================================================

--- 稀有度背景色
---@param rarity string
---@return table
function HeroUI.GetRarityColor(rarity)
    if rarity == "LR" then return { 180, 30, 30, 220 } end
    if rarity == "UR" then return { 200, 150, 30, 220 } end
    if rarity == "SSR" then return { 150, 55, 190, 200 } end
    if rarity == "SR" then return { 45, 115, 195, 200 } end
    if rarity == "N" then return { 130, 120, 110, 200 } end
    if rarity == "none" then return { 140, 90, 200, 220 } end
    return { 75, 125, 55, 200 } -- R
end

--- 稀有度边框色（更亮的版本）
---@param rarity string
---@return table
function HeroUI.GetRarityBorderColor(rarity)
    if rarity == "LR" then return { 255, 60, 60, 255 } end
    if rarity == "UR" then return { 255, 215, 60, 255 } end
    if rarity == "SSR" then return { 200, 100, 255, 255 } end
    if rarity == "SR" then return { 80, 160, 255, 255 } end
    if rarity == "N" then return { 170, 160, 150, 180 } end
    return { 100, 200, 80, 220 } -- R
end

-- ============================================================================
-- 主页：英雄列表（主角 + 上阵英雄 + 空阵位）
-- ============================================================================

--- 生成星级图标行（多行排列，每行最多5颗）
---@param starCount number  总星数
---@param tierColor table   星星颜色
---@return table[]  UI children
function HeroUI.CreateStarRows(starCount, tierColor)
    if starCount <= 0 then return {} end
    local rows = {}
    local remaining = starCount
    while remaining > 0 do
        local thisRow = math.min(remaining, 5)
        local stars = {}
        for i = 1, thisRow do
            stars[#stars + 1] = UI.Label {
                text = "★",
                fontSize = 7,
                fontColor = tierColor,
            }
        end
        rows[#rows + 1] = UI.Panel {
            flexDirection = "row",
            gap = 0,
            justifyContent = "center",
            children = stars,
        }
        remaining = remaining - thisRow
    end
    return rows
end

--- 创建空阵位占位卡片
local function CreateEmptySlot(slotIndex)
    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 40, 32, 26, 150 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 60, 50, 40, 100 },
        borderStyle = "dashed",
        children = {
            UI.Label {
                text = "空阵位",
                fontSize = 13,
                fontColor = S.dim,
            },
        },
    }
end

--- 创建单个英雄行（咸鱼之王横条风格 5:1）
local function CreateHeroRow(heroDef, isLeader)
    local heroId = heroDef.id
    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false
    local level = (h and h.level) or 1
    local fragments = (h and h.fragments) or 0

    -- 等级/门槛
    local nextGate = GetNextGateLevel(heroId)
    local prevGate = GetPrevGateLevel(heroId)
    local levelCap = HeroData.GetCurrentLevelCap(heroId)
    local atCap = (level >= levelCap)

    -- 进度条
    local gateSpan = math.max(1, nextGate - prevGate)
    local progressRatio = math.min(1.0, (level - prevGate) / gateSpan)

    -- 战力
    local stats = HeroData.GetHeroStats(heroId)
    -- 叠加装备加成到显示属性
    local EquipData = require("Game.EquipData")
    local eqBonus = EquipData.GetTotalBonus(heroId)
    stats.atk = stats.atk + (eqBonus.atk or 0)
    stats.critDmg = (stats.critDmg or 0) + (eqBonus.critDmg or 0)
    stats.dmgBonus = (stats.dmgBonus or 0) + (eqBonus.dmgBonus or 0)
    -- 元素伤害加成：加到英雄对应元素
    local heroElem = Config.HERO_ELEMENT[heroId]
    if heroElem and eqBonus.elemDmg and eqBonus.elemDmg > 0 then
        if not stats.elemDmgBonus then stats.elemDmgBonus = {} end
        stats.elemDmgBonus[heroElem] = (stats.elemDmgBonus[heroElem] or 0) + eqBonus.elemDmg
    end
    local power = stats.atk + stats.spd

    -- 头像图片
    local avatarIcon = heroDef.icon or heroId
    local avatarImage = "image/avatars/avatar_" .. avatarIcon .. ".png"

    -- 品质
    local rarity = heroDef.rarity or "R"
    local rarityColor = HeroUI.GetRarityColor(rarity)
    local rarityBorder = HeroUI.GetRarityBorderColor(rarity)

    -- 星级信息
    local tierInfo = HeroData.GetStarTierInfo(heroId)

    -- 头像边框颜色
    local frameColor = { 100, 75, 50, 200 }
    if isUnlocked then
        if isLeader then
            frameColor = { 210, 170, 50, 255 }
        else
            frameColor = { rarityBorder[1], rarityBorder[2], rarityBorder[3], 220 }
        end
    end

    -- ==================== 左侧：头像区 ====================
    -- 星级叠加在头像左上角
    local starOverlay = nil
    if isUnlocked and tierInfo.starInTier > 0 then
        local starRows = HeroUI.CreateStarRows(tierInfo.starInTier, tierInfo.color)
        starOverlay = UI.Panel {
            position = "absolute",
            top = 1, left = 1,
            gap = 0,
            children = starRows,
        }
    end

    local avatarSection = UI.Panel {
        height = "80%",
        aspectRatio = 1.0,
        flexShrink = 0,
        borderRadius = 6,
        borderWidth = 2,
        borderColor = frameColor,
        backgroundColor = {
            rarityColor[1], rarityColor[2], rarityColor[3],
            isUnlocked and 200 or 50,
        },
        backgroundImage = avatarImage,
        backgroundFit = "contain",
        opacity = isUnlocked and 1.0 or 0.3,
        overflow = "hidden",
        onClick = function(self)
            HeroUI.ShowHeroDetail(heroId)
        end,
        children = (function()
            local items = {}
            -- 星级（左上）
            if starOverlay then items[#items + 1] = starOverlay end
            -- 等级徽章（左下）
            if isUnlocked then
                items[#items + 1] = UI.Panel {
                    position = "absolute",
                    bottom = 0, left = 0,
                    paddingLeft = 4, paddingRight = 4,
                    paddingTop = 1, paddingBottom = 1,
                    borderTopRightRadius = 4,
                    backgroundColor = S.lvBadgeBg,
                    children = {
                        UI.Label {
                            text = "Lv." .. level,
                            fontSize = isLeader and 11 or 9,
                            fontColor = { 255, 255, 255, 230 },
                        },
                    },
                }
            end
            -- 元素图标（右下角）
            local elemId = Config.HERO_ELEMENT[heroId]
            local elemDef = elemId and Config.ELEMENTS[elemId]
            if elemDef then
                items[#items + 1] = UI.Panel {
                    position = "absolute",
                    bottom = 1, right = 1,
                    width = 18, height = 18,
                    backgroundImage = elemDef.icon,
                    backgroundFit = "contain",
                }
            end
            return items
        end)(),
    }

    -- ==================== 右侧：操作按钮 ====================
    local rightSection = nil
    local pendingGate = HeroData.GetPendingAdvanceGate(heroId)

    if not isUnlocked then
        local unlockCost = Config.RARITY_SHARD_COST[rarity] or 10
        rightSection = UI.Panel {
            width = "28%", flexShrink = 0,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = fragments .. "/" .. unlockCost, fontSize = 12, fontColor = S.dim },
                UI.Label { text = "未解锁", fontSize = 10, fontColor = S.dimLocked, marginTop = 2 },
            },
        }
    elseif atCap and pendingGate then
        local advDisabled = (HeroData.currencies.devour_stone or 0) < pendingGate.stones
        rightSection = UI.Panel {
            width = "28%", flexShrink = 0,
            justifyContent = "center", alignItems = "center",
            gap = 3,
            children = {
                -- 费用标签（绿底）
                UI.Panel {
                    width = "100%",
                    paddingTop = 3, paddingBottom = 3,
                    borderRadius = 4,
                    backgroundColor = advDisabled and S.btnDisabled or { 75, 140, 55, 255 },
                    flexDirection = "row",
                    justifyContent = "center", alignItems = "center",
                    gap = 2,
                    children = {
                        Currency.IconWidget(UI, "devour_stone", 11),
                        UI.Label { text = FormatBigNum(pendingGate.stones), fontSize = 11, fontColor = S.btnText, fontWeight = "bold" },
                    },
                },
                -- 进阶按钮
                UI.Panel {
                    width = "100%",
                    paddingTop = 5, paddingBottom = 5,
                    borderRadius = 6,
                    backgroundColor = advDisabled and S.btnDisabled or S.btnAdvance,
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if advDisabled then return end
                        local ok, msg = HeroData.Advance(heroId)
                        print("[HeroUI] Advance " .. heroId .. ": " .. msg)
                        HeroUI.Refresh()
                    end,
                    children = {
                        UI.Label { text = "进阶", fontSize = 14, fontColor = S.btnText, fontWeight = "bold" },
                    },
                },
            },
        }
    elseif atCap then
        rightSection = UI.Panel {
            width = "28%", flexShrink = 0,
            justifyContent = "center", alignItems = "center",
            gap = 3,
            children = {
                UI.Panel {
                    width = "100%",
                    paddingTop = 5, paddingBottom = 5,
                    borderRadius = 6,
                    backgroundColor = S.btnDisabled,
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        ShowToast("已达等级上限，不能超过角色等级")
                    end,
                    children = {
                        UI.Label { text = "升级", fontSize = 14, fontColor = { 120, 110, 100, 180 }, fontWeight = "bold" },
                    },
                },
            },
        }
    else
        local best = GetBestUpgradeTier(heroId)
        local canUpgrade = (best ~= nil)
        local btnLabel = "升级"
        local costNum = ""
        if best then
            costNum = FormatBigNum(best.cost)
            if best.tier > 1 then
                btnLabel = "升级" .. best.tier .. "次"
            end
        else
            local cost1, _ = CalcBatchUpgradeCost(heroId, 1)
            costNum = FormatBigNum(cost1)
        end

        rightSection = UI.Panel {
            width = "28%", flexShrink = 0,
            justifyContent = "center", alignItems = "center",
            gap = 3,
            children = {
                -- 费用标签（绿底圆角）
                UI.Panel {
                    width = "100%",
                    paddingTop = 3, paddingBottom = 3,
                    borderRadius = 4,
                    backgroundColor = canUpgrade and { 75, 140, 55, 255 } or S.btnDisabled,
                    flexDirection = "row",
                    justifyContent = "center", alignItems = "center",
                    gap = 2,
                    children = {
                        Currency.IconWidget(UI, "nether_crystal", 11),
                        UI.Label { text = costNum, fontSize = 11, fontColor = S.btnText, fontWeight = "bold" },
                    },
                },
                -- 升级按钮（深色底）
                UI.Panel {
                    width = "100%",
                    paddingTop = 5, paddingBottom = 5,
                    borderRadius = 6,
                    backgroundColor = canUpgrade and S.btnGreen or S.btnDisabled,
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        if not canUpgrade then return end
                        local b = GetBestUpgradeTier(heroId)
                        if b then
                            DoBatchLevelUp(heroId, b.tier)
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayUpgrade()
                            print("[HeroUI] BatchLevelUp " .. heroId .. " x" .. b.tier)
                        end
                        HeroUI.Refresh()
                    end,
                    children = {
                        UI.Label { text = btnLabel, fontSize = 14, fontColor = S.btnText, fontWeight = "bold" },
                    },
                },
            },
        }
    end

    -- ==================== 中间：信息区 ====================
    local nameColor = isUnlocked and S.white or S.dimLocked

    local middleSection = UI.Panel {
        flexGrow = 1, flexShrink = 1,
        gap = 3,
        children = {
            -- 名字行：名字 + 品质标签
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 5,
                children = {
                    UI.Label {
                        text = heroDef.name,
                        fontSize = 15,
                        fontColor = nameColor,
                        fontWeight = "bold",
                    },
                    heroDef.rarity ~= "none" and UI.Panel {
                        paddingLeft = 5, paddingRight = 5,
                        paddingTop = 1, paddingBottom = 1,
                        borderRadius = 3,
                        backgroundColor = HeroUI.GetRarityColor(heroDef.rarity),
                        children = {
                            UI.Label {
                                text = heroDef.rarity or "R",
                                fontSize = 9,
                                fontColor = { 255, 255, 255, 230 },
                                fontWeight = "bold",
                            },
                        },
                    } or nil,
                },
            },

            -- 进度条（圆角，内嵌文字）
            isUnlocked and UI.Panel {
                width = "100%",
                height = 18,
                borderRadius = 9,
                backgroundColor = S.progBg,
                children = {
                    -- 填充条
                    UI.Panel {
                        width = math.max(3, math.floor(progressRatio * 100)) .. "%",
                        height = "100%",
                        borderRadius = 9,
                        backgroundColor = atCap and S.progFillMax or S.progFill,
                    },
                    -- 进度文字（居中叠加，独立于填充条）
                    UI.Panel {
                        position = "absolute",
                        left = 0, right = 0, top = 0, bottom = 0,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = level .. "/" .. nextGate,
                                fontSize = 10,
                                fontColor = { 255, 255, 255, 230 },
                            },
                        },
                    },
                },
            } or UI.Panel {
                width = "100%", height = 18,
                justifyContent = "center",
                children = {
                    UI.Label {
                        text = "收集碎片解锁",
                        fontSize = 10,
                        fontColor = S.dimLocked,
                    },
                },
            },

            -- 战力值
            isUnlocked and UI.Label {
                text = "战力 " .. FormatBigNum(power),
                fontSize = 11,
                fontColor = S.powerYellow,
            } or nil,
        },
    }

    -- ==================== 组装卡片（5:1 横条） ====================
    local bg = isUnlocked and S.cardBg or S.cardLocked

    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = bg,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = S.cardBorder,
        paddingLeft = 6, paddingRight = 8,
        gap = 8,
        children = {
            avatarSection,
            middleSection,
            rightSection,
        },
    }
end

--- 创建英雄列表（主角 + 上阵英雄 + 空阵位）
local function CreateHeroList()
    local cards = {}
    -- 主角置顶
    cards[#cards + 1] = CreateHeroRow(Config.LEADER_HERO, true)

    -- 只显示已上阵的随从英雄
    local deployedList = HeroData.GetDeployedList()
    for _, heroId in ipairs(deployedList) do
        local heroDef = nil
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then
                heroDef = td
                break
            end
        end
        if heroDef then
            cards[#cards + 1] = CreateHeroRow(heroDef, false)
        end
    end

    -- 空阵位占位
    local emptySlots = Config.MAX_DEPLOYED - #deployedList
    for i = 1, emptySlots do
        cards[#cards + 1] = CreateEmptySlot(#deployedList + i)
    end

    return UI.Panel {
        flexGrow = 1, flexShrink = 1,
        flexBasis = 0,
        width = "100%",
        flexDirection = "column",
        gap = 5,
        paddingTop = 5, paddingBottom = 5,
        paddingLeft = 8, paddingRight = 8,
        children = cards,
    }
end

-- ============================================================================
-- 底部栏
-- ============================================================================

local function CreateBottomBar()
    local GameUI = require("Game.GameUI")
    local count = HeroData.GetDeployedCount()
    local maxDeploy = Config.MAX_DEPLOYED
    return UI.Panel {
        width = "100%",
        flexShrink = 0,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = 6, paddingBottom = 8,
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = { 30, 22, 16, 240 },
        borderTopWidth = 1,
        borderTopColor = { 75, 55, 38, 100 },
        children = {
            -- 左侧：操作按钮
            UI.Panel {
                flexDirection = "row",
                gap = 5,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 5, paddingBottom = 5,
                        borderRadius = 14,
                        backgroundColor = S.collectBtn,
                        borderWidth = 1,
                        borderColor = S.collectBtnBorder,
                        onClick = function(self)
                            HeroUI.ShowCollectionPopup()
                        end,
                        children = {
                            UI.Label { text = "上阵", fontSize = 11, fontColor = S.white, fontWeight = "bold" },
                            UI.Label { text = count .. "/" .. maxDeploy, fontSize = 10, fontColor = S.gold },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 5, paddingBottom = 5,
                        borderRadius = 14,
                        backgroundColor = { 100, 70, 140, 255 },
                        borderWidth = 1,
                        borderColor = { 150, 115, 190, 255 },
                        onClick = function(self)
                            HeroUI.ShowCollectionDetailPopup()
                        end,
                        children = {
                            UI.Label { text = "英雄收藏", fontSize = 11, fontColor = S.white, fontWeight = "bold" },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 5, paddingBottom = 5,
                        borderRadius = 14,
                        backgroundColor = { 140, 100, 50, 255 },
                        borderWidth = 1,
                        borderColor = { 190, 145, 70, 255 },
                        onClick = function(self)
                            InventoryUI.Show(UI, pageRoot)
                        end,
                        children = {
                            UI.Label { text = "仓库", fontSize = 11, fontColor = S.white, fontWeight = "bold" },
                        },
                    },
                },
            },
            -- 右侧：货币药丸
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    GameUI.CreateCurrencyChip(UI, "nether_crystal", "heroCrystalLabel", { 160, 100, 230 }),
                    GameUI.CreateCurrencyChip(UI, "devour_stone", "heroStoneLabel", { 100, 180, 80 }),
                },
            },
        },
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 标题栏："英雄" 标题
local function CreateTitleBar()
    return UI.Panel {
        id = "heroTitleBar",
        width = "100%",
        paddingTop = 4, paddingBottom = 6,
        paddingLeft = 14,
        borderBottomWidth = 1,
        borderBottomColor = { 75, 55, 38, 100 },
        flexShrink = 0,
        children = {
            UI.Label {
                text = "英雄",
                fontSize = 17,
                fontColor = S.gold,
                fontWeight = "bold",
            },
        },
    }
end

--- 创建英雄养成页面
---@param uiModule any
---@return any
function HeroUI.CreatePage(uiModule)
    UI = uiModule

    -- 延迟加载子模块，避免循环引用
    HeroCard = require("Game.HeroUI.HeroCard")
    DeployPopup = require("Game.HeroUI.DeployPopup")
    CollectionPopup = require("Game.HeroUI.CollectionPopup")
    HeroDetail = require("Game.HeroUI.HeroDetail")

    pageRoot = UI.Panel {
        id = "heroPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = S.pageBg,
        children = {},
    }
    HeroUI.Refresh()
    return pageRoot
end

--- 刷新页面（重建主页内容，不含弹出层）
function HeroUI.Refresh()
    if not pageRoot or not UI then return end
    -- 保存弹出层状态
    local wasPopupOpen = (collectionOverlay ~= nil)
    local wasDetailPopupOpen = (collectionDetailOverlay ~= nil)
    local wasInventoryOpen = InventoryUI.IsVisible()

    pageRoot:ClearChildren()
    collectionOverlay = nil
    collectionDetailOverlay = nil
    heroDetailOverlay = nil
    -- 仓库弹窗由 InventoryUI 模块管理，ClearChildren 已清除其 overlay
    if wasInventoryOpen then
        InventoryUI.Hide(pageRoot)
    end

    -- 通知子模块清理各自的状态
    if DeployPopup then DeployPopup.OnPageClear() end
    if CollectionPopup then CollectionPopup.OnPageClear() end
    if HeroDetail then HeroDetail.OnPageClear() end

    pageRoot:AddChild(CreateTitleBar())
    pageRoot:AddChild(CreateHeroList())
    pageRoot:AddChild(CreateBottomBar())

    -- 如果弹出层之前打开着，重新打开
    if wasPopupOpen then
        HeroUI.ShowCollectionPopup()
    elseif wasDetailPopupOpen then
        HeroUI.ShowCollectionDetailPopup()
    elseif wasInventoryOpen then
        InventoryUI.Show(UI, pageRoot)
    end
end

return HeroUI
