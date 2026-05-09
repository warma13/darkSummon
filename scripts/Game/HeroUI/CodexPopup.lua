-- Game/HeroUI/CodexPopup.lua
-- 图鉴弹窗：5列网格卡片 + VirtualList + 分类筛选 + 星级 + 底部收集进度

local Config = require("Game.Config")
local CodexData = require("Game.CodexData")
local HeroData = require("Game.HeroData")
local HeroAvatar = require("Game.HeroAvatar")

local CodexPopup = {}

---@type any
local _overlay = nil
---@type any
local _ctx = nil
---@type any
local _vlist = nil  -- VirtualList 实例

-- 当前状态
local _mainTab = "hero"    -- "hero" | "relic"
local _subFilter = "all"   -- hero: "all"|faction, relic: "all"|slot

-- 布局常量
local COLS = 5
local ROW_HEIGHT = 130    -- 行高（含卡片+间距）
local ROW_GAP = 5
local CARD_GAP = 4
local CARD_WIDTH_PCT = "18.4%"  -- 每张卡片宽度百分比 (约 (100-4间距*4)/5)

-- ============================================================================
-- 阵营/部位筛选定义
-- ============================================================================

local FACTION_TABS = {
    { id = "all",       name = "全部",  color = { 140, 110, 70 } },
    { id = "undead",    name = "亡灵",  color = { 100, 150, 200 } },
    { id = "demon",     name = "恶魔",  color = { 200, 70, 70 } },
    { id = "elemental", name = "元素",  color = { 80, 180, 140 } },
    { id = "human",     name = "人类",  color = { 200, 170, 80 } },
}

local SLOT_TABS = {
    { id = "all",   name = "全部",     color = { 140, 110, 70 } },
    { id = "power", name = "神之力",   color = { 220, 80, 60 } },
    { id = "heart", name = "神之心",   color = { 230, 110, 150 } },
    { id = "eye",   name = "神之眼",   color = { 80, 150, 230 } },
    { id = "will",  name = "神之意志", color = { 150, 110, 230 } },
}

local RARITY_ORDER = { LR = 6, UR = 5, SSR = 4, SR = 3, R = 2, N = 1 }

-- ============================================================================
-- 行数据缓存
-- ============================================================================

---@type table[]|nil
local _rowData = nil  -- { {item1,item2,...}, {item3,...}, ... }

-- ============================================================================
-- 内部：重建弹窗（切换标签时调用）
-- ============================================================================

local function Rebuild()
    local ctx = _ctx
    if not ctx then return end
    local pageRoot = ctx.GetPageRoot()
    if not pageRoot then return end
    if _overlay then
        pageRoot:RemoveChild(_overlay)
        _overlay = nil
        _vlist = nil
        _rowData = nil
    end
    CodexPopup.Show(ctx)
end

-- ============================================================================
-- 星级显示
-- ============================================================================

---@param UI any
---@param heroId string
---@param totalStar number
---@return any
local function BuildHeroStarRow(UI, heroId, totalStar)
    local stars = {}
    if totalStar <= 0 then
        for i = 1, 5 do
            stars[#stars + 1] = UI.Label {
                text = "☆", fontSize = 7,
                fontColor = { 80, 70, 60, 120 },
            }
        end
    else
        local tierInfo = HeroData.GetStarTierInfo(heroId)
        local starInTier = tierInfo and tierInfo.starInTier or math.min(totalStar, 5)
        local tierColor = (tierInfo and tierInfo.color) or { 255, 220, 80 }
        for i = 1, 5 do
            if i <= starInTier then
                stars[#stars + 1] = UI.Label {
                    text = "★", fontSize = 7,
                    fontColor = { tierColor[1], tierColor[2], tierColor[3], 255 },
                }
            else
                stars[#stars + 1] = UI.Label {
                    text = "☆", fontSize = 7,
                    fontColor = { 80, 70, 60, 120 },
                }
            end
        end
    end
    return UI.Panel {
        flexDirection = "row", gap = 0,
        justifyContent = "center",
        children = stars,
    }
end

---@param UI any
---@param star number
---@return any
local function BuildRelicStarRow(UI, star)
    star = star or 0
    local stars = {}
    for i = 1, 5 do
        if i <= star then
            stars[#stars + 1] = UI.Label {
                text = "★", fontSize = 7,
                fontColor = { 255, 220, 80, 255 },
            }
        else
            stars[#stars + 1] = UI.Label {
                text = "☆", fontSize = 7,
                fontColor = { 80, 70, 60, 120 },
            }
        end
    end
    return UI.Panel {
        flexDirection = "row", gap = 0,
        justifyContent = "center",
        children = stars,
    }
end

-- ============================================================================
-- 筛选标签栏
-- ============================================================================

---@param UI any
---@param tabs table[]
---@param currentFilter string
---@return any
local function BuildFilterTabs(UI, tabs, currentFilter)
    local children = {}
    for _, tab in ipairs(tabs) do
        local isActive = tab.id == currentFilter
        children[#children + 1] = UI.Panel {
            paddingLeft = 8, paddingRight = 8,
            paddingTop = 4, paddingBottom = 4,
            borderRadius = 5,
            backgroundColor = isActive
                and { tab.color[1], tab.color[2], tab.color[3], 230 }
                or { 50, 40, 32, 200 },
            borderWidth = isActive and 0 or 1,
            borderColor = { 80, 60, 42, 120 },
            pointerEvents = "auto",
            onClick = function()
                _subFilter = tab.id
                Rebuild()
            end,
            children = {
                UI.Label {
                    text = tab.name,
                    fontSize = 10,
                    fontColor = isActive
                        and { 255, 255, 255, 255 }
                        or { 180, 170, 160, 200 },
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 5,
        paddingLeft = 8, paddingRight = 8,
        children = children,
    }
end

-- ============================================================================
-- 英雄卡片（单张，width=100% 填满槽位）
-- ============================================================================

---@param UI any
---@param heroDef table
---@param bonus number
---@return any
local function CreateHeroCard(UI, heroDef, bonus)
    local heroId = heroDef.id
    local h = HeroData.Get(heroId)
    local isUnlocked = h and h.unlocked or false
    local totalStar = (h and h.star) or 0
    local rarity = heroDef.rarity or "N"
    local rarityColor = Config.GetRarityColor(rarity, isUnlocked and 220 or 60)

    return UI.Panel {
        width = "100%",
        backgroundColor = isUnlocked and { 50, 42, 35, 245 } or { 35, 28, 22, 200 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = isUnlocked
            and { rarityColor[1], rarityColor[2], rarityColor[3], 240 }
            or { 60, 50, 40, 100 },
        overflow = "hidden",
        children = {
            -- 头像
            UI.Panel {
                width = "100%",
                aspectRatio = 1.0,
                children = {
                    HeroAvatar.Create(heroId, {
                        preset = "card",
                        isUnlocked = isUnlocked,
                        borderWidth = 0,
                    }),
                },
            },
            -- 名字
            UI.Panel {
                width = "100%",
                paddingTop = 2, paddingBottom = 1,
                alignItems = "center",
                backgroundColor = { 30, 24, 18, 220 },
                children = {
                    UI.Label {
                        text = heroDef.name,
                        fontSize = 8,
                        fontColor = isUnlocked
                            and { 245, 238, 225, 255 }
                            or { 100, 90, 80, 160 },
                        fontWeight = "bold",
                        maxLines = 1,
                    },
                },
            },
            -- 星级
            UI.Panel {
                width = "100%",
                paddingTop = 1, paddingBottom = 1,
                alignItems = "center",
                backgroundColor = { 30, 24, 18, 220 },
                children = {
                    BuildHeroStarRow(UI, heroId, totalStar),
                },
            },
            -- 加成
            UI.Panel {
                width = "100%",
                paddingTop = 0, paddingBottom = 3,
                alignItems = "center",
                backgroundColor = { 30, 24, 18, 220 },
                children = {
                    UI.Label {
                        text = bonus > 0
                            and string.format("+%.1f%%", bonus * 100)
                            or "—",
                        fontSize = 7,
                        fontColor = bonus > 0
                            and { 120, 220, 120, 255 }
                            or { 80, 70, 60, 120 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 遗物卡片（单张，width=100% 填满槽位）
-- ============================================================================

---@param UI any
---@param relicDef table
---@param isOwned boolean
---@param star number
---@param bonus number
---@return any
local function CreateRelicCard(UI, relicDef, isOwned, star, bonus)
    local qualityColor = Config.RELIC_QUALITY_COLOR[relicDef.minQuality] or { 100, 200, 100 }
    local qualityName = Config.RELIC_QUALITY_NAME[relicDef.minQuality] or ""

    local imageChildren = {}
    if relicDef.image then
        imageChildren[#imageChildren + 1] = UI.Panel {
            width = "80%", height = "80%",
            backgroundImage = relicDef.image,
            backgroundFit = "contain",
            opacity = isOwned and 1.0 or 0.3,
        }
    else
        imageChildren[#imageChildren + 1] = UI.Label {
            text = "?", fontSize = 20,
            fontColor = { 80, 70, 60, 120 },
        }
    end
    -- 品质角标
    imageChildren[#imageChildren + 1] = UI.Panel {
        position = "absolute",
        top = 1, left = 1,
        paddingLeft = 2, paddingRight = 2,
        paddingTop = 0, paddingBottom = 0,
        borderRadius = 2,
        backgroundColor = { qualityColor[1], qualityColor[2], qualityColor[3], 200 },
        children = {
            UI.Label {
                text = qualityName,
                fontSize = 6,
                fontColor = { 255, 255, 255, 230 },
                fontWeight = "bold",
            },
        },
    }
    -- 未拥有遮罩
    if not isOwned then
        imageChildren[#imageChildren + 1] = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 130 },
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "🔒", fontSize = 14 },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = isOwned and { 50, 42, 35, 245 } or { 35, 28, 22, 200 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = isOwned
            and { qualityColor[1], qualityColor[2], qualityColor[3], 220 }
            or { 60, 50, 40, 100 },
        overflow = "hidden",
        children = {
            -- 遗物图片
            UI.Panel {
                width = "100%",
                aspectRatio = 1.0,
                overflow = "hidden",
                backgroundColor = isOwned
                    and { math.floor(qualityColor[1] * 0.15), math.floor(qualityColor[2] * 0.15), math.floor(qualityColor[3] * 0.15), 200 }
                    or { 20, 16, 12, 200 },
                justifyContent = "center", alignItems = "center",
                children = imageChildren,
            },
            -- 名字
            UI.Panel {
                width = "100%",
                paddingTop = 2, paddingBottom = 1,
                alignItems = "center",
                backgroundColor = { 30, 24, 18, 220 },
                children = {
                    UI.Label {
                        text = relicDef.name,
                        fontSize = 8,
                        fontColor = isOwned
                            and { 245, 238, 225, 255 }
                            or { 100, 90, 80, 160 },
                        fontWeight = "bold",
                        maxLines = 1,
                    },
                },
            },
            -- 星级
            UI.Panel {
                width = "100%",
                paddingTop = 1, paddingBottom = 1,
                alignItems = "center",
                backgroundColor = { 30, 24, 18, 220 },
                children = {
                    BuildRelicStarRow(UI, star),
                },
            },
            -- 加成
            UI.Panel {
                width = "100%",
                paddingTop = 0, paddingBottom = 3,
                alignItems = "center",
                backgroundColor = { 30, 24, 18, 220 },
                children = {
                    UI.Label {
                        text = bonus > 0
                            and string.format("+%.1f%%", bonus * 100)
                            or "—",
                        fontSize = 7,
                        fontColor = bonus > 0
                            and { 120, 220, 120, 255 }
                            or { 80, 70, 60, 120 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- VirtualList 行容器（createItem / bindItem）
-- ============================================================================

--- 创建空行容器（5 个槽位）
---@param UI any
---@return any
local function CreateRowWidget(UI)
    local slots = {}
    for i = 1, COLS do
        slots[i] = UI.Panel {
            width = CARD_WIDTH_PCT,
        }
    end
    local row = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "flex-start",
        alignItems = "stretch",
        paddingLeft = 6, paddingRight = 6,
        gap = CARD_GAP,
        children = slots,
    }
    row._slots = slots
    return row
end

--- 绑定英雄行数据
---@param widget any
---@param rowItems table   { heroDef1, heroDef2, ... }
---@param UI any
local function BindHeroRow(widget, rowItems, UI)
    for i = 1, COLS do
        local slot = widget._slots[i]
        slot:ClearChildren()
        local item = rowItems[i]
        if item then
            local h = HeroData.Get(item.id)
            local star = (h and h.star) or 0
            local bonus = star * CodexData.ATK_PER_HERO_STAR
            local card = CreateHeroCard(UI, item, bonus)
            card.props.width = "100%"
            slot:AddChild(card)
            slot.props.width = CARD_WIDTH_PCT
        else
            slot.props.width = CARD_WIDTH_PCT
        end
    end
end

--- 绑定遗物行数据
---@param widget any
---@param rowItems table   { {id=, def=}, ... }
---@param UI any
local function BindRelicRow(widget, rowItems, UI)
    local RelicData = require("Game.RelicData")
    for i = 1, COLS do
        local slot = widget._slots[i]
        slot:ClearChildren()
        local item = rowItems[i]
        if item then
            local isOwned = RelicData.IsOwned(item.id)
            local star = 0
            if isOwned then
                local _level, s = RelicData.GetProgress(item.id)
                star = s or 0
            end
            local bonus = star * CodexData.ATK_PER_RELIC_STAR
            local card = CreateRelicCard(UI, item.def, isOwned, star, bonus)
            card.props.width = "100%"
            slot:AddChild(card)
            slot.props.width = CARD_WIDTH_PCT
        else
            slot.props.width = CARD_WIDTH_PCT
        end
    end
end

-- ============================================================================
-- 构建行数据
-- ============================================================================

--- 构建英雄行数据（排序 + 分组为5列行）
---@return table[]
local function BuildHeroRowData()
    local heroes = {}
    for _, td in ipairs(Config.TOWER_TYPES) do
        if _subFilter == "all" or td.faction == _subFilter then
            heroes[#heroes + 1] = td
        end
    end
    table.sort(heroes, function(a, b)
        local ha = HeroData.Get(a.id)
        local hb = HeroData.Get(b.id)
        local aUnlocked = (ha and ha.unlocked) and 1 or 0
        local bUnlocked = (hb and hb.unlocked) and 1 or 0
        if aUnlocked ~= bUnlocked then return aUnlocked > bUnlocked end
        local ra = RARITY_ORDER[a.rarity] or 0
        local rb = RARITY_ORDER[b.rarity] or 0
        if ra ~= rb then return ra > rb end
        local aStar = (ha and ha.star) or 0
        local bStar = (hb and hb.star) or 0
        if aStar ~= bStar then return aStar > bStar end
        return a.name < b.name
    end)
    -- 分行
    local rows = {}
    local row = {}
    for _, td in ipairs(heroes) do
        row[#row + 1] = td
        if #row >= COLS then
            rows[#rows + 1] = row
            row = {}
        end
    end
    if #row > 0 then rows[#rows + 1] = row end
    return rows
end

--- 构建遗物行数据
---@return table[]
local function BuildRelicRowData()
    local RelicData = require("Game.RelicData")
    local QUALITY_ORDER = {}
    for i, q in ipairs(Config.RELIC_QUALITIES) do
        QUALITY_ORDER[q.id] = i
    end
    local relics = {}
    for relicId, relicDef in pairs(Config.RELICS) do
        if _subFilter == "all" or relicDef.slot == _subFilter then
            relics[#relics + 1] = { id = relicId, def = relicDef }
        end
    end
    table.sort(relics, function(a, b)
        local aOwned = RelicData.IsOwned(a.id) and 1 or 0
        local bOwned = RelicData.IsOwned(b.id) and 1 or 0
        if aOwned ~= bOwned then return aOwned > bOwned end
        local qa = QUALITY_ORDER[a.def.minQuality] or 0
        local qb = QUALITY_ORDER[b.def.minQuality] or 0
        if qa ~= qb then return qa > qb end
        return a.def.name < b.def.name
    end)
    -- 分行
    local rows = {}
    local row = {}
    for _, r in ipairs(relics) do
        row[#row + 1] = r
        if #row >= COLS then
            rows[#rows + 1] = row
            row = {}
        end
    end
    if #row > 0 then rows[#rows + 1] = row end
    return rows
end

-- ============================================================================
-- 收集统计
-- ============================================================================

---@return number unlocked, number total
local function GetHeroCollectionCount()
    local total = #Config.TOWER_TYPES
    local unlocked = 0
    for _, td in ipairs(Config.TOWER_TYPES) do
        if HeroData.IsUnlocked(td.id) then unlocked = unlocked + 1 end
    end
    return unlocked, total
end

---@return number owned, number total
local function GetRelicCollectionCount()
    local RelicData = require("Game.RelicData")
    local total = 0
    local owned = 0
    for relicId, _ in pairs(Config.RELICS) do
        total = total + 1
        if RelicData.IsOwned(relicId) then owned = owned + 1 end
    end
    return owned, total
end

-- ============================================================================
-- 显示/隐藏
-- ============================================================================

--- 显示图鉴弹窗
---@param ctx table  HeroUI context
function CodexPopup.Show(ctx)
    if _overlay then return end
    _ctx = ctx
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    if not pageRoot then return end

    local function close()
        if _overlay then
            pageRoot:RemoveChild(_overlay)
            _overlay = nil
            _vlist = nil
            _rowData = nil
        end
    end

    -- 总加成
    local totalAtk, detail = CodexData.GetTotalBonus()

    -- 筛选标签
    local filterTabs
    if _mainTab == "hero" then
        filterTabs = BuildFilterTabs(UI, FACTION_TABS, _subFilter)
        _rowData = BuildHeroRowData()
    else
        filterTabs = BuildFilterTabs(UI, SLOT_TABS, _subFilter)
        _rowData = BuildRelicRowData()
    end

    -- 收集统计
    local heroUnlocked, heroTotal = GetHeroCollectionCount()
    local relicOwned, relicTotal = GetRelicCollectionCount()

    -- VirtualList 初始可见行估算（固定 6 行足够覆盖常见屏幕）
    local INITIAL_VISIBLE_ROWS = 6
    local vpHeight = INITIAL_VISIBLE_ROWS * (ROW_HEIGHT + ROW_GAP)

    local isHeroTab = _mainTab == "hero"

    _vlist = UI.VirtualList {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        data = _rowData,
        itemHeight = ROW_HEIGHT,
        itemGap = ROW_GAP,
        viewportHeight = vpHeight,
        poolBuffer = 2,
        paddingTop = 4,
        paddingBottom = 10,
        createItem = function()
            return CreateRowWidget(UI)
        end,
        bindItem = function(widget, rowData, index)
            if isHeroTab then
                BindHeroRow(widget, rowData, UI)
            else
                BindRelicRow(widget, rowData, UI)
            end
        end,
    }

    _overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 25, 18, 12, 252 },
        pointerEvents = "auto",
        zIndex = 100,
        children = {
            UI.Panel {
                width = "100%", height = "100%",
                paddingTop = 8,
                gap = 4,
                children = {
                    -- ====== 顶部标题栏 ======
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        paddingLeft = 10, paddingRight = 8,
                        children = {
                            UI.Label {
                                text = "图鉴",
                                fontSize = 16, fontWeight = "bold",
                                fontColor = { 255, 220, 80, 255 },
                            },
                            UI.Panel { flexGrow = 1 },
                            UI.Label {
                                text = string.format("全局攻击 +%.1f%%", totalAtk * 100),
                                fontSize = 11, fontWeight = "bold",
                                fontColor = { 120, 220, 120, 255 },
                            },
                        },
                    },

                    -- ====== 星级明细 ======
                    UI.Panel {
                        width = "100%",
                        paddingLeft = 10, paddingRight = 10,
                        children = {
                            UI.Label {
                                text = string.format(
                                    "英雄 %d★ (+%.1f%%)   遗物 %d★ (+%.1f%%)",
                                    detail.heroStars, detail.heroAtkPct * 100,
                                    detail.relicStars, detail.relicAtkPct * 100
                                ),
                                fontSize = 9,
                                fontColor = { 180, 170, 160, 200 },
                            },
                        },
                    },

                    -- ====== 筛选标签 ======
                    filterTabs,

                    -- ====== 分隔线 ======
                    UI.Panel {
                        width = "94%", height = 1,
                        alignSelf = "center",
                        backgroundColor = { 80, 60, 42, 120 },
                    },

                    -- ====== VirtualList 网格 ======
                    _vlist,

                    -- ====== 底部标签栏 ======
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        backgroundColor = { 35, 28, 20, 252 },
                        borderTopWidth = 1,
                        borderColor = { 80, 60, 42, 150 },
                        children = {
                            -- 英雄标签
                            UI.Panel {
                                flexGrow = 1,
                                paddingTop = 6, paddingBottom = 8,
                                alignItems = "center",
                                justifyContent = "center",
                                backgroundColor = _mainTab == "hero"
                                    and { 60, 48, 32, 255 } or nil,
                                pointerEvents = "auto",
                                onClick = function()
                                    if _mainTab ~= "hero" then
                                        _mainTab = "hero"
                                        _subFilter = "all"
                                        Rebuild()
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = "英雄已收集",
                                        fontSize = 9,
                                        fontColor = _mainTab == "hero"
                                            and { 255, 220, 80, 255 }
                                            or { 140, 130, 120, 180 },
                                    },
                                    UI.Label {
                                        text = heroUnlocked .. "/" .. heroTotal,
                                        fontSize = 15, fontWeight = "bold",
                                        fontColor = _mainTab == "hero"
                                            and { 255, 255, 255, 255 }
                                            or { 140, 130, 120, 180 },
                                    },
                                },
                            },
                            -- 分隔
                            UI.Panel {
                                width = 1, height = "50%",
                                alignSelf = "center",
                                backgroundColor = { 80, 60, 42, 150 },
                            },
                            -- 遗物标签
                            UI.Panel {
                                flexGrow = 1,
                                paddingTop = 6, paddingBottom = 8,
                                alignItems = "center",
                                justifyContent = "center",
                                backgroundColor = _mainTab == "relic"
                                    and { 50, 38, 60, 255 } or nil,
                                pointerEvents = "auto",
                                onClick = function()
                                    if _mainTab ~= "relic" then
                                        _mainTab = "relic"
                                        _subFilter = "all"
                                        Rebuild()
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = "遗物已收集",
                                        fontSize = 9,
                                        fontColor = _mainTab == "relic"
                                            and { 180, 140, 255, 255 }
                                            or { 140, 130, 120, 180 },
                                    },
                                    UI.Label {
                                        text = relicOwned .. "/" .. relicTotal,
                                        fontSize = 15, fontWeight = "bold",
                                        fontColor = _mainTab == "relic"
                                            and { 255, 255, 255, 255 }
                                            or { 140, 130, 120, 180 },
                                    },
                                },
                            },
                        },
                    },

                    -- ====== 底部返回按钮 ======
                    UI.Panel {
                        width = "100%",
                        paddingTop = 6, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        flexShrink = 0,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 4,
                                paddingLeft = 14, paddingRight = 18,
                                paddingTop = 6, paddingBottom = 6,
                                backgroundColor = { 80, 60, 45, 230 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 140, 110, 70, 150 },
                                pointerEvents = "auto",
                                onClick = function() close() end,
                                children = {
                                    UI.Label {
                                        text = "<",
                                        fontSize = 14,
                                        fontColor = { 180, 160, 130, 200 },
                                    },
                                    UI.Label {
                                        text = "返回",
                                        fontSize = 14,
                                        fontColor = { 245, 238, 225, 255 },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
    pageRoot:AddChild(_overlay)
end

--- 隐藏图鉴弹窗
---@param ctx table
function CodexPopup.Hide(ctx)
    if not _overlay then return end
    local pageRoot = ctx and ctx.GetPageRoot() or (_ctx and _ctx.GetPageRoot())
    if pageRoot then
        pageRoot:RemoveChild(_overlay)
    end
    _overlay = nil
    _vlist = nil
    _rowData = nil
    _ctx = nil
end

--- 页面清理回调
function CodexPopup.OnPageClear()
    _overlay = nil
    _vlist = nil
    _rowData = nil
    _ctx = nil
    _mainTab = "hero"
    _subFilter = "all"
end

--- 是否打开
---@return boolean
function CodexPopup.IsVisible()
    return _overlay ~= nil
end

return CodexPopup
