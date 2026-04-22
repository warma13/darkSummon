-- Game/HeroAvatar.lua
-- 统一英雄头像组件，消除多处重复的头像渲染代码

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")

local HeroAvatar = {}

---@type any
local UI = nil

-- ============================================================================
-- 预设定义
-- ============================================================================

local PRESETS = {
    -- 英雄列表横条：星级(左上) + 等级(左下) + 元素(右下)
    row = {
        fit = "contain",
        showStars = true,
        showLevel = true,
        showElem = true,
        levelPos = "BL",
        borderRadius = 6,
    },
    -- 卡片网格：稀有度(左上) + 等级(右上) + 元素(右下) + 锁定遮罩
    card = {
        fit = "contain",
        showRarity = true,
        showLevel = true,
        showElem = true,
        showLock = true,
        levelPos = "TR",
        borderRadius = 0, -- 卡片模式：仅上方圆角，由调用方控制
        borderRadiusTop = 6,
    },
    -- 选择器条：名称条(底部)，cover 铺满
    selector = {
        fit = "cover",
        showName = true,
        borderRadius = 8,
    },
    -- 极简图标：无叠加
    icon = {
        fit = "cover",
        borderRadius = 6,
    },
}

-- ============================================================================
-- 初始化
-- ============================================================================

--- UI.Init 之后调用一次
---@param uiModule any
function HeroAvatar.Init(uiModule)
    UI = uiModule
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 解析英雄头像图片路径
---@param heroId string
---@return string
function HeroAvatar.GetPath(heroId)
    -- 主角特殊处理
    if heroId == "leader" or (Config.LEADER_HERO and Config.LEADER_HERO.id == heroId) then
        local icon = Config.LEADER_HERO and Config.LEADER_HERO.icon or "leader"
        return "image/avatars/avatar_" .. icon .. ".png"
    end
    -- 普通英雄：查 TOWER_TYPES 获取 icon
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then
            return "image/avatars/avatar_" .. (td.icon or heroId) .. ".png"
        end
    end
    return "image/avatars/avatar_" .. heroId .. ".png"
end

--- 获取英雄定义
---@param heroId string
---@return table|nil
local function GetHeroDef(heroId)
    if Config.LEADER_HERO and Config.LEADER_HERO.id == heroId then
        return Config.LEADER_HERO
    end
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then return td end
    end
    return nil
end

-- ============================================================================
-- 叠加元素构建器
-- ============================================================================

--- 创建星级行（多行，每行最多5颗）
local function BuildStarOverlay(heroId)
    local tierInfo = HeroData.GetStarTierInfo(heroId)
    if not tierInfo or tierInfo.starInTier <= 0 then return nil end
    local rows = {}
    local remaining = tierInfo.starInTier
    while remaining > 0 do
        local thisRow = math.min(remaining, 5)
        local stars = {}
        for i = 1, thisRow do
            stars[#stars + 1] = UI.Label {
                text = "\xe2\x98\x85",
                fontSize = 7,
                fontColor = tierInfo.color,
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
    return UI.Panel {
        position = "absolute",
        top = 1, left = 1,
        gap = 0,
        children = rows,
    }
end

--- 创建等级徽章
local function BuildLevelBadge(level, pos, isLeader)
    if pos == "BL" then
        return UI.Panel {
            position = "absolute",
            bottom = 0, left = 0,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            borderTopRightRadius = 4,
            backgroundColor = { 0, 0, 0, 180 },
            children = {
                UI.Label {
                    text = "Lv." .. level,
                    fontSize = isLeader and 11 or 9,
                    fontColor = { 255, 255, 255, 230 },
                },
            },
        }
    else -- "TR"
        return UI.Panel {
            position = "absolute",
            top = 2, right = 2,
            paddingLeft = 3, paddingRight = 3,
            paddingTop = 1, paddingBottom = 1,
            borderRadius = 3,
            backgroundColor = { 0, 0, 0, 160 },
            children = {
                UI.Label {
                    text = "Lv." .. level,
                    fontSize = 8,
                    fontColor = { 255, 255, 255, 220 },
                },
            },
        }
    end
end

--- 创建稀有度角标
local function BuildRarityBadge(rarity, rarityColor)
    if rarity == "none" then return nil end
    return UI.Panel {
        position = "absolute",
        top = 2, left = 2,
        paddingLeft = 4, paddingRight = 4,
        paddingTop = 1, paddingBottom = 1,
        borderRadius = 3,
        backgroundColor = rarityColor,
        children = {
            UI.Label {
                text = rarity,
                fontSize = 8,
                fontColor = { 255, 255, 255, 240 },
                fontWeight = "bold",
            },
        },
    }
end

--- 创建元素图标
local function BuildElemIcon(heroId, size)
    local elemId = Config.HERO_ELEMENT[heroId]
    local elemDef = elemId and Config.ELEMENTS[elemId]
    if not elemDef then return nil end
    size = size or 16
    return UI.Panel {
        position = "absolute",
        bottom = 1, right = 1,
        width = size, height = size,
        backgroundImage = elemDef.icon,
        backgroundFit = "contain",
    }
end

--- 创建锁定遮罩
local function BuildLockMask(isComingSoon)
    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = isComingSoon and { 20, 10, 35, 200 } or { 0, 0, 0, 120 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            isComingSoon and UI.Label {
                text = "即将\n推出",
                fontSize = 11,
                fontColor = { 200, 170, 255, 240 },
                fontWeight = "bold",
                textAlign = "center",
            } or UI.Label { text = "🔒", fontSize = 18 },
        },
    }
end

--- 创建底部名称条
local function BuildNameBar(name, isSelected)
    return UI.Panel {
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        height = 20,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "none",
        children = {
            UI.Label {
                text = string.sub(name, 1, 6),
                fontSize = 10,
                fontColor = isSelected and { 255, 255, 255, 255 } or { 200, 190, 220, 230 },
                fontWeight = isSelected and "bold" or "normal",
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 创建英雄头像 UI 面板
---@param heroId string
---@param opts? table  见 PRESETS 和模块注释
---@return any UI.Panel
function HeroAvatar.Create(heroId, opts)
    assert(UI, "[HeroAvatar] must call HeroAvatar.Init(UI) first")
    opts = opts or {}

    -- 合并预设
    local presetName = opts.preset or "icon"
    local preset = PRESETS[presetName] or PRESETS.icon
    local function opt(key, default)
        if opts[key] ~= nil then return opts[key] end
        if preset[key] ~= nil then return preset[key] end
        return default
    end

    -- 英雄数据
    local heroDef = GetHeroDef(heroId)
    local isLeader = heroDef and heroDef.isLeader == true or false
    local rarity = (heroDef and heroDef.rarity) or "R"
    local h = HeroData.Get(heroId)
    local isUnlocked = opts.isUnlocked
    if isUnlocked == nil then
        isUnlocked = isLeader or (h and h.unlocked or false)
    end
    local level = (h and h.level) or 1
    local heroName = (heroDef and heroDef.name) or heroId
    local isComingSoon = opts.isComingSoon or false
    local isSelected = opts.selected or false

    -- 头像路径
    local avatarImage = HeroAvatar.GetPath(heroId)

    -- 颜色
    local rarityColor = Config.GetRarityColor(rarity, isUnlocked and 200 or 50)
    local rarityBorder = Config.GetRarityColor(rarity, 255)

    -- 边框颜色
    local borderColor
    if opts.borderColor then
        borderColor = opts.borderColor
    elseif isSelected then
        borderColor = { 160, 120, 255, 255 }
    elseif isLeader and isUnlocked then
        borderColor = { 210, 170, 50, 255 }
    elseif isUnlocked then
        borderColor = { rarityBorder[1], rarityBorder[2], rarityBorder[3], 220 }
    else
        borderColor = { 60, 50, 40, 100 }
    end

    -- 圆角
    local br = opt("borderRadius", 6)
    local brTop = preset.borderRadiusTop

    -- 构建叠加层 children
    local children = {}
    local fit = opt("fit", "cover")

    -- cover 模式用绝对定位子面板铺满
    if fit == "cover" then
        children[#children + 1] = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundImage = avatarImage,
            backgroundFit = "cover",
            pointerEvents = "none",
        }
    end

    -- 星级（左上）
    if opt("showStars", false) and isUnlocked then
        local starPanel = BuildStarOverlay(heroId)
        if starPanel then children[#children + 1] = starPanel end
    end

    -- 稀有度角标（左上）
    if opt("showRarity", false) then
        local badge = BuildRarityBadge(rarity, rarityColor)
        if badge then children[#children + 1] = badge end
    end

    -- 等级徽章
    if opt("showLevel", false) and isUnlocked then
        local pos = opt("levelPos", "BL")
        children[#children + 1] = BuildLevelBadge(level, pos, isLeader)
    end

    -- 元素图标（右下）
    if opt("showElem", false) then
        local elemSize = (presetName == "row") and 18 or 16
        local elem = BuildElemIcon(heroId, elemSize)
        if elem then children[#children + 1] = elem end
    end

    -- 锁定遮罩
    if opt("showLock", false) and not isUnlocked then
        children[#children + 1] = BuildLockMask(isComingSoon)
    end

    -- 底部名称条
    if opt("showName", false) then
        children[#children + 1] = BuildNameBar(heroName, isSelected)
    end

    -- 选中高亮光晕
    if isSelected then
        children[#children + 1] = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            borderRadius = math.max(0, br - 1),
            borderWidth = 1,
            borderColor = { 200, 170, 255, 100 },
            pointerEvents = "none",
        }
    end

    -- 面板属性
    local panelProps = {
        width = "100%",
        height = "100%",
        borderWidth = opts.borderWidth or 2,
        borderColor = borderColor,
        backgroundColor = rarityColor,
        opacity = opts.opacity or (isUnlocked and 1.0 or 0.3),
        overflow = "hidden",
        children = children,
    }

    -- backgroundImage 仅 contain 模式直接设在主面板
    if fit == "contain" then
        panelProps.backgroundImage = avatarImage
        panelProps.backgroundFit = "contain"
    end

    -- 圆角
    if brTop then
        panelProps.borderTopLeftRadius = brTop
        panelProps.borderTopRightRadius = brTop
    else
        panelProps.borderRadius = br
    end

    -- 点击
    if opts.onClick then
        panelProps.onClick = opts.onClick
    end

    return UI.Panel(panelProps)
end

return HeroAvatar
