-- Game/HeroUI/HeroCard.lua
-- 英雄卡片网格（收藏弹出层和英雄收藏弹出层共享）
-- 使用 VirtualList 按行虚拟化渲染，降低一次性创建的节点数

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local LBD = require("Game.LimitedBannerData")

local HeroAvatar = require("Game.HeroAvatar")

local HeroCard = {}

local COLS = 3            -- 每行卡片数
local ROW_HEIGHT = 170    -- 行高（px），含间距
local ROW_GAP = 6         -- 行间距
local CARD_GAP = 6        -- 卡内间距

-- 排序后的英雄列表缓存：mode -> { heroDef1, heroDef2, ... }
local sortedHeroesCache = {}
-- 按行分组的数据：mode -> { {heroDef1, heroDef2, heroDef3}, {heroDef4, ...}, ... }
local rowDataCache = {}
-- VirtualList 实例缓存：mode -> virtualList widget
local virtualListCache = {}
-- 卡片缓存（用于增量更新）：mode -> { heroId -> { rowIndex, colIndex } }
local cardIndexCache = {}

--- 清除指定模式的缓存
function HeroCard.ClearCache(mode)
    if mode then
        sortedHeroesCache[mode] = nil
        rowDataCache[mode] = nil
        virtualListCache[mode] = nil
        cardIndexCache[mode] = nil
    else
        sortedHeroesCache = {}
        rowDataCache = {}
        virtualListCache = {}
        cardIndexCache = {}
    end
end

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

--- 构建按行分组的数据 + 索引缓存
---@param ctx table
---@param mode string
---@return table[]  rowData
local function BuildRowData(ctx, mode)
    local sortedHeroes = HeroCard.GetSortedHeroes(ctx)
    sortedHeroesCache[mode] = sortedHeroes

    local rows = {}
    local idxCache = {}
    local row = {}
    for i, heroDef in ipairs(sortedHeroes) do
        row[#row + 1] = heroDef
        local rowIdx = math.ceil(i / COLS)
        local colIdx = ((i - 1) % COLS) + 1
        idxCache[heroDef.id] = { rowIndex = rowIdx, colIndex = colIdx }
        if #row >= COLS then
            rows[#rows + 1] = row
            row = {}
        end
    end
    if #row > 0 then
        rows[#rows + 1] = row
    end

    rowDataCache[mode] = rows
    cardIndexCache[mode] = idxCache
    return rows
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
            paddingTop = 2, paddingBottom = 3,
            paddingLeft = 2, paddingRight = 2,
            gap = 0,
            alignItems = "center",
            children = {
                UI.Label {
                    text = heroDef.name,
                    fontSize = 9,
                    fontColor = isUnlocked and S.white or S.dimLocked,
                    fontWeight = "bold",
                    textAlign = "center",
                    maxLines = 1,
                },
                isUnlocked and UI.Label {
                    text = "⚔ " .. ctx.FormatBigNum(power),
                    fontSize = 8,
                    fontColor = S.powerYellow,
                    maxLines = 1,
                } or (isComingSoon and UI.Label {
                    text = "敬请期待",
                    fontSize = 8,
                    fontColor = { 160, 130, 210, 180 },
                    maxLines = 1,
                } or UI.Label {
                    text = fragments .. "/" .. unlockCost,
                    fontSize = 8,
                    fontColor = S.dimLocked,
                    maxLines = 1,
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
        width = "100%",
        backgroundColor = cardBg,
        borderRadius = 6,
        borderWidth = 1.5,
        borderColor = borderColor,
        onTap = isComingSoon and nil or function(event, self)
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

--- 创建一行的行容器（VirtualList createItem 回调用）
--- 行容器包含 COLS 个卡片槽位
---@param UI any
---@return any rowPanel
local function CreateRowWidget(UI)
    local slots = {}
    for i = 1, COLS do
        slots[i] = UI.Panel {
            width = "31%",
            -- 占位，bindItem 时替换内容
        }
    end
    local row = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "flex-start",
        alignItems = "stretch",
        paddingLeft = 8, paddingRight = 8,
        gap = CARD_GAP,
        children = slots,
    }
    row._slots = slots
    return row
end

--- 绑定一行数据到行容器（VirtualList bindItem 回调用）
---@param widget any  行容器
---@param rowHeroes table  该行的英雄定义数组 { heroDef1, heroDef2, ... }
---@param index number  行索引（1-based）
---@param ctx table  HeroUI 模块
---@param mode string
local function BindRowWidget(widget, rowHeroes, index, ctx, mode)
    local UI = ctx.GetUI()
    -- 替换每个槽位的内容
    for i = 1, COLS do
        local slot = widget._slots[i]
        slot:ClearChildren()
        local heroDef = rowHeroes[i]
        if heroDef then
            -- 创建卡片并放入槽位
            local card = HeroCard.CreateHeroCard(ctx, heroDef, mode)
            -- 卡片宽度改为100%填满槽位
            card.props.width = "100%"
            slot:AddChild(card)
            slot.props.width = "31%"
        else
            -- 空槽位保持占位
            slot.props.width = "31%"
        end
    end
end

--- 创建英雄网格（使用 VirtualList 虚拟化渲染）
--- @param ctx table  HeroUI 模块
--- @param mode string|nil  "deploy"(默认) 或 "detail"
function HeroCard.CreateHeroGrid(ctx, mode)
    mode = mode or "deploy"
    local UI = ctx.GetUI()
    local rows = BuildRowData(ctx, mode)

    -- 初始可视行数：初始化时 layout 未就绪，需显式指定 viewportHeight
    local INITIAL_VISIBLE_ROWS = 6
    local vpHeight = INITIAL_VISIBLE_ROWS * (ROW_HEIGHT + ROW_GAP)

    local vlist = UI.VirtualList {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        data = rows,
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
            BindRowWidget(widget, rowData, index, ctx, mode)
        end,
    }
    virtualListCache[mode] = vlist

    return vlist
end

--- 替换网格中单张卡片（增量更新）
--- 对于 VirtualList 模式，通过 SetData 触发重新绑定可见行
--- @param ctx table  HeroUI 模块
--- @param heroId string
--- @param mode string|nil  "deploy"(默认) 或 "detail"
--- @return boolean  是否成功
function HeroCard.RefreshSingleCard(ctx, heroId, mode)
    mode = mode or "deploy"
    local vlist = virtualListCache[mode]
    local rows = rowDataCache[mode]
    if not vlist or not rows then return false end

    -- 重新构建行数据（排序可能因上阵状态改变）
    local newRows = BuildRowData(ctx, mode)

    -- 用 SetData 刷新 VirtualList，只重新绑定可见行
    vlist:SetData(newRows)
    return true
end

return HeroCard
