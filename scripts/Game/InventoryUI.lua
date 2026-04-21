-- Game/InventoryUI.lua
-- 仓库弹窗 UI：3列网格，可滚动，底部固定选中物品详情+使用按钮

local InventoryData  = require("Game.InventoryData")
local Currency       = require("Game.Currency")
local RewardIcon     = require("Game.RewardIcon")
local RewardDisplay  = require("Game.RewardDisplay")
local Config         = require("Game.Config")

local InventoryUI = {}

-- ============================================================================
-- 配色（与 HeroUI 暗色系一致）
-- ============================================================================
local S = {
    overlayBg   = { 0, 0, 0, 180 },
    popupBg     = { 42, 30, 22, 250 },
    popupBorder = { 90, 70, 50, 200 },
    white       = { 245, 238, 225, 255 },
    dim         = { 170, 155, 135, 200 },
    gold        = { 255, 215, 80, 255 },
    cardBg      = { 55, 42, 32, 240 },
    cardBorder  = { 80, 62, 44, 120 },
    selectedBorder = { 255, 200, 80, 255 },
    emptyText   = { 130, 120, 110, 160 },
    btnUse      = { 75, 165, 55, 255 },
    btnUseBorder = { 100, 200, 75, 200 },
    btnDisabled = { 65, 58, 48, 220 },
    detailBg    = { 35, 26, 18, 240 },
    detailBorder = { 75, 55, 38, 120 },
}

--- 稀有度边框颜色（引用 Config 统一定义）
local RARITY_COLORS = Config.RARITY_COLORS

-- ============================================================================
-- 状态
-- ============================================================================

---@type any
local UI = nil
---@type any
local overlay = nil
---@type any
local contentContainer = nil
---@type string|nil
local selectedItemId = nil
---@type any
local detailContainer = nil
---@type fun()|nil
local onCloseCallback = nil
local currentTab = "items"  -- "items" 道具 | "materials" 材料

-- ============================================================================
-- 内部：创建单个物品格子
-- ============================================================================

---@param item table {id, count, def}
---@param isSelected boolean
local function CreateItemCell(item, isSelected)
    local def = item.def
    local rarityCol = RARITY_COLORS[def.rarity] or RARITY_COLORS.N
    local borderCol = isSelected and S.selectedBorder or rarityCol

    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        aspectRatio = 1.0,
        backgroundColor = S.cardBg,
        borderRadius = 6,
        borderWidth = isSelected and 2.5 or 1.5,
        borderColor = borderCol,
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            selectedItemId = item.id
            RefreshInventoryContent()
        end,
        children = {
            -- 物品图标（铺满 + 右下角数量，禁用 tooltip）
            RewardIcon.Create(UI, "100%", def.icon, item.count, { noTooltip = true }),
            -- 稀有度标签（左上，仅英雄碎片礼包显示）
            item.id:find("shard") and UI.Panel {
                position = "absolute",
                top = 2, left = 2,
                paddingLeft = 3, paddingRight = 3,
                paddingTop = 1, paddingBottom = 1,
                borderRadius = 3,
                backgroundColor = { rarityCol[1], rarityCol[2], rarityCol[3], 160 },
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = def.rarity,
                        fontSize = 7,
                        fontColor = { 255, 255, 255, 240 },
                        fontWeight = "bold",
                    },
                },
            } or nil,
        },
    }
end

--- 创建空白占位格（保持3列对齐）
local function CreateEmptyCell()
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        aspectRatio = 1.0,
    }
end

-- ============================================================================
-- 通用数量选择弹窗（所有可使用礼包）
-- ============================================================================

local function ShowQuantityPopup(item)
    if not overlay or not UI then return end
    local def = item.def
    local maxAmount = InventoryData.GetCount(item.id)
    if maxAmount <= 0 then return end

    local selectAmount = 1
    local popupId = "quantitySelectPopup"

    local function closePopup()
        local p = overlay:FindById(popupId)
        if p then overlay:RemoveChild(p) end
    end

    local function refreshPopup()
        closePopup()

        -- 数量控制按钮
        local function numBtn(text, onClick, disabled)
            return UI.Panel {
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 4,
                backgroundColor = disabled and { 55, 45, 35, 200 } or { 75, 165, 55, 255 },
                borderWidth = 1,
                borderColor = disabled and { 70, 60, 50, 150 } or { 100, 200, 75, 200 },
                onClick = (not disabled) and onClick or nil,
                children = {
                    UI.Label {
                        text = text,
                        fontSize = 12,
                        fontColor = disabled and { 120, 110, 100, 180 } or { 255, 255, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            }
        end

        local popup = UI.Panel {
            id = popupId,
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center",
            alignItems = "center",
            onClick = function() end, -- 拦截穿透
            children = {
                UI.Panel {
                    width = "80%",
                    backgroundColor = { 42, 30, 22, 250 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = { 90, 70, 50, 200 },
                    flexDirection = "column",
                    overflow = "hidden",
                    children = {
                        -- 标题栏
                        UI.Panel {
                            width = "100%", height = 40, flexShrink = 0,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 55, 38, 25, 250 },
                            borderColor = { 90, 70, 50, 120 },
                            borderWidth = { bottom = 1 },
                            children = {
                                UI.Label {
                                    text = "使用数量",
                                    fontSize = 16,
                                    fontColor = { 255, 215, 80, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                        -- 物品信息
                        UI.Panel {
                            width = "100%", paddingTop = 12, paddingBottom = 6,
                            flexDirection = "row",
                            justifyContent = "center", alignItems = "center",
                            gap = 8,
                            flexShrink = 0,
                            children = {
                                Currency.IconWidget(UI, def.icon, 28),
                                UI.Label {
                                    text = def.name .. "（拥有 " .. maxAmount .. " 个）",
                                    fontSize = 13,
                                    fontColor = { 220, 210, 200, 255 },
                                },
                            },
                        },
                        -- 数量控制区
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 10, paddingBottom = 10,
                            flexDirection = "row",
                            justifyContent = "center", alignItems = "center",
                            gap = 6,
                            children = {
                                numBtn("-10", function()
                                    selectAmount = math.max(1, selectAmount - 10)
                                    refreshPopup()
                                end, selectAmount <= 1),
                                numBtn("-", function()
                                    selectAmount = math.max(1, selectAmount - 1)
                                    refreshPopup()
                                end, selectAmount <= 1),
                                -- 数量显示
                                UI.Panel {
                                    width = 50, height = 28,
                                    backgroundColor = { 30, 22, 16, 240 },
                                    borderRadius = 4,
                                    borderWidth = 1,
                                    borderColor = { 80, 62, 44, 150 },
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label {
                                            text = tostring(selectAmount),
                                            fontSize = 14,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                                numBtn("+", function()
                                    selectAmount = math.min(maxAmount, selectAmount + 1)
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                                numBtn("+10", function()
                                    selectAmount = math.min(maxAmount, selectAmount + 10)
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                                numBtn("最大", function()
                                    selectAmount = maxAmount
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                            },
                        },
                        -- 领取/关闭按钮
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 4, paddingBottom = 12,
                            justifyContent = "center", alignItems = "center",
                            flexDirection = "row", gap = 12,
                            children = {
                                UI.Panel {
                                    paddingLeft = 30, paddingRight = 30,
                                    paddingTop = 10, paddingBottom = 10,
                                    borderRadius = 8,
                                    backgroundColor = { 75, 165, 55, 255 },
                                    borderWidth = 1,
                                    borderColor = { 100, 200, 75, 200 },
                                    onClick = function()
                                        local ok, msg, rewards = InventoryData.Use(item.id, selectAmount)
                                        if not ok then
                                            print("[InventoryUI] Use failed: " .. (msg or ""))
                                            return
                                        end
                                        closePopup()
                                        if InventoryData.GetCount(item.id) <= 0 then
                                            selectedItemId = nil
                                        end
                                        if rewards and #rewards > 0 then
                                            RewardDisplay.Show(UI, overlay, {
                                                title = "使用 " .. def.name .. " ×" .. selectAmount,
                                                rewards = rewards,
                                                onClose = function()
                                                    RefreshInventoryContent()
                                                end,
                                            })
                                        else
                                            RefreshInventoryContent()
                                        end
                                    end,
                                    children = {
                                        UI.Label {
                                            text = "领取",
                                            fontSize = 15,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                                -- 关闭按钮
                                UI.Panel {
                                    paddingLeft = 20, paddingRight = 20,
                                    paddingTop = 10, paddingBottom = 10,
                                    borderRadius = 8,
                                    backgroundColor = { 120, 50, 40, 230 },
                                    borderWidth = 1,
                                    borderColor = { 160, 70, 60, 200 },
                                    onClick = function() closePopup() end,
                                    children = {
                                        UI.Label {
                                            text = "关闭",
                                            fontSize = 15,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }

        overlay:AddChild(popup)
    end

    refreshPopup()
end

-- ============================================================================
-- 英雄选择弹窗（万能碎片箱专用）
-- ============================================================================

local function ShowHeroSelectPopup(item)
    if not overlay or not UI then return end
    local def = item.def
    local pool = Config.RECRUIT_POOL[def.selectPool or "UR"] or {}
    local maxAmount = InventoryData.GetCount(item.id)
    if maxAmount <= 0 then return end

    ---@type string|nil
    local selectedHero = nil
    local selectAmount = 1

    -- 获取英雄显示信息
    local heroInfos = {}
    for _, heroId in ipairs(pool) do
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then
                heroInfos[#heroInfos + 1] = {
                    id = heroId,
                    name = td.name or heroId,
                    icon = td.icon or heroId,
                    avatar = "image/avatars/avatar_" .. (td.icon or heroId) .. ".png",
                }
                break
            end
        end
    end

    local popupId = "heroSelectPopup"

    local function closePopup()
        local p = overlay:FindById(popupId)
        if p then overlay:RemoveChild(p) end
    end

    local function refreshPopup()
        closePopup()

        -- 英雄网格：4列
        local gridChildren = {}
        for _, info in ipairs(heroInfos) do
            local isSel = (selectedHero == info.id)
            gridChildren[#gridChildren + 1] = UI.Panel {
                width = 72, height = 90,
                backgroundColor = isSel and { 80, 50, 30, 255 } or { 50, 38, 28, 240 },
                borderRadius = 6,
                borderWidth = isSel and 2.5 or 1,
                borderColor = isSel and { 255, 200, 80, 255 } or { 80, 62, 44, 120 },
                alignItems = "center",
                justifyContent = "center",
                gap = 2,
                onClick = function()
                    selectedHero = info.id
                    refreshPopup()
                end,
                children = {
                    -- 选中标记
                    UI.Panel {
                        position = "absolute", top = 3, left = 3,
                        width = 14, height = 14, borderRadius = 7,
                        borderWidth = 1.5,
                        borderColor = isSel and { 255, 200, 80, 255 } or { 120, 100, 80, 180 },
                        backgroundColor = isSel and { 255, 200, 80, 255 } or { 0, 0, 0, 0 },
                        justifyContent = "center", alignItems = "center",
                        children = isSel and {
                            UI.Label { text = "✓", fontSize = 9, fontColor = { 30, 20, 10, 255 }, fontWeight = "bold" },
                        } or {},
                    },
                    -- 头像
                    UI.Panel {
                        width = 44, height = 44, borderRadius = 6,
                        backgroundImage = info.avatar,
                        backgroundFit = "cover",
                    },
                    -- 名称
                    UI.Label {
                        text = info.name,
                        fontSize = 9,
                        fontColor = { 245, 238, 225, 255 },
                        textAlign = "center",
                    },
                },
            }
        end

        -- 数量控制按钮
        local function numBtn(text, onClick, disabled)
            return UI.Panel {
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 5, paddingBottom = 5,
                borderRadius = 4,
                backgroundColor = disabled and { 55, 45, 35, 200 } or { 75, 165, 55, 255 },
                borderWidth = 1,
                borderColor = disabled and { 70, 60, 50, 150 } or { 100, 200, 75, 200 },
                onClick = (not disabled) and onClick or nil,
                children = {
                    UI.Label {
                        text = text,
                        fontSize = 12,
                        fontColor = disabled and { 120, 110, 100, 180 } or { 255, 255, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            }
        end

        local canClaim = selectedHero and selectAmount > 0

        local popup = UI.Panel {
            id = popupId,
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center",
            alignItems = "center",
            onClick = function() end, -- 拦截穿透
            children = {
                UI.Panel {
                    width = "88%", maxHeight = "85%",
                    backgroundColor = { 42, 30, 22, 250 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = { 90, 70, 50, 200 },
                    flexDirection = "column",
                    overflow = "hidden",
                    children = {
                        -- 标题栏
                        UI.Panel {
                            width = "100%", height = 40, flexShrink = 0,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 55, 38, 25, 250 },
                            borderColor = { 90, 70, 50, 120 },
                            borderWidth = { bottom = 1 },
                            children = {
                                UI.Label {
                                    text = "提示",
                                    fontSize = 16,
                                    fontColor = { 255, 215, 80, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                        -- 说明文字
                        UI.Panel {
                            width = "100%", paddingTop = 10, paddingBottom = 6,
                            justifyContent = "center", alignItems = "center",
                            flexShrink = 0,
                            children = {
                                UI.Label {
                                    text = "请选择万能碎片要转化的英雄",
                                    fontSize = 13,
                                    fontColor = { 220, 210, 200, 255 },
                                },
                            },
                        },
                        -- 英雄网格（可滚动）
                        UI.Panel {
                            width = "100%", flexGrow = 1, flexShrink = 1,
                            paddingLeft = 10, paddingRight = 10,
                            paddingTop = 6, paddingBottom = 6,
                            overflow = "scroll",
                            children = {
                                UI.Panel {
                                    width = "100%",
                                    flexDirection = "row",
                                    flexWrap = "wrap",
                                    gap = 8,
                                    justifyContent = "center",
                                    children = gridChildren,
                                },
                            },
                        },
                        -- 数量控制区
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 8, paddingBottom = 8,
                            flexDirection = "row",
                            justifyContent = "center", alignItems = "center",
                            gap = 6,
                            children = {
                                numBtn("-10", function()
                                    selectAmount = math.max(1, selectAmount - 10)
                                    refreshPopup()
                                end, selectAmount <= 1),
                                numBtn("-", function()
                                    selectAmount = math.max(1, selectAmount - 1)
                                    refreshPopup()
                                end, selectAmount <= 1),
                                -- 数量显示
                                UI.Panel {
                                    width = 50, height = 28,
                                    backgroundColor = { 30, 22, 16, 240 },
                                    borderRadius = 4,
                                    borderWidth = 1,
                                    borderColor = { 80, 62, 44, 150 },
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label {
                                            text = tostring(selectAmount),
                                            fontSize = 14,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                                numBtn("+", function()
                                    selectAmount = math.min(maxAmount, selectAmount + 1)
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                                numBtn("+10", function()
                                    selectAmount = math.min(maxAmount, selectAmount + 10)
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                                numBtn("最大", function()
                                    selectAmount = maxAmount
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                            },
                        },
                        -- 领取按钮
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 4, paddingBottom = 12,
                            justifyContent = "center", alignItems = "center",
                            flexDirection = "row", gap = 12,
                            children = {
                                UI.Panel {
                                    paddingLeft = 30, paddingRight = 30,
                                    paddingTop = 10, paddingBottom = 10,
                                    borderRadius = 8,
                                    backgroundColor = canClaim and { 75, 165, 55, 255 } or { 65, 58, 48, 220 },
                                    borderWidth = 1,
                                    borderColor = canClaim and { 100, 200, 75, 200 } or { 80, 70, 60, 150 },
                                    onClick = canClaim and function()
                                        local ok, msg, rewards = InventoryData.Use(item.id, selectAmount, selectedHero)
                                        if not ok then
                                            print("[InventoryUI] Use failed: " .. (msg or ""))
                                            return
                                        end
                                        closePopup()
                                        if InventoryData.GetCount(item.id) <= 0 then
                                            selectedItemId = nil
                                        end
                                        if rewards and #rewards > 0 then
                                            RewardDisplay.Show(UI, overlay, {
                                                title = "使用 " .. def.name,
                                                rewards = rewards,
                                                onClose = function()
                                                    RefreshInventoryContent()
                                                end,
                                            })
                                        else
                                            RefreshInventoryContent()
                                        end
                                    end or nil,
                                    children = {
                                        UI.Label {
                                            text = "领取",
                                            fontSize = 15,
                                            fontColor = canClaim and { 255, 255, 255, 255 } or { 120, 110, 100, 180 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                                -- 关闭按钮
                                UI.Panel {
                                    paddingLeft = 20, paddingRight = 20,
                                    paddingTop = 10, paddingBottom = 10,
                                    borderRadius = 8,
                                    backgroundColor = { 120, 50, 40, 230 },
                                    borderWidth = 1,
                                    borderColor = { 160, 70, 60, 200 },
                                    onClick = function() closePopup() end,
                                    children = {
                                        UI.Label {
                                            text = "关闭",
                                            fontSize = 15,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }

        overlay:AddChild(popup)
    end

    refreshPopup()
end

-- ============================================================================
-- 招募池选择弹窗（招募券自选包专用）
-- ============================================================================

local function ShowPoolSelectPopup(item)
    if not overlay or not UI then return end
    local def = item.def
    local maxAmount = InventoryData.GetCount(item.id)
    if maxAmount <= 0 then return end

    ---@type string|nil
    local selectedPool = nil
    local selectAmount = 1

    -- 构建可选池子列表
    local poolOptions = {}
    -- 常驻池
    poolOptions[#poolOptions + 1] = {
        id       = "normal",
        name     = "常驻招募池",
        currency = "void_pact",
        subname  = Config.CURRENCY["void_pact"] and Config.CURRENCY["void_pact"].name or "虚空契约",
        img      = Currency.GetImage("void_pact"),
    }
    -- 限定池
    for _, banner in ipairs(Config.LIMITED_BANNERS) do
        local curr = banner.currency or "frost_pact"
        local cdef = Config.CURRENCY[curr]
        poolOptions[#poolOptions + 1] = {
            id       = banner.id,
            name     = banner.name,
            currency = curr,
            subname  = cdef and cdef.name or curr,
            img      = Currency.GetImage(curr),
        }
    end

    local popupId = "poolSelectPopup"

    local function closePopup()
        local p = overlay:FindById(popupId)
        if p then overlay:RemoveChild(p) end
    end

    local function numBtn(text, onClick, disabled)
        return UI.Panel {
            paddingLeft = 8, paddingRight = 8,
            paddingTop = 5, paddingBottom = 5,
            borderRadius = 4,
            backgroundColor = disabled and { 55, 45, 35, 200 } or { 75, 165, 55, 255 },
            borderWidth = 1,
            borderColor = disabled and { 70, 60, 50, 150 } or { 100, 200, 75, 200 },
            onClick = (not disabled) and onClick or nil,
            children = {
                UI.Label {
                    text = text,
                    fontSize = 12,
                    fontColor = disabled and { 120, 110, 100, 180 } or { 255, 255, 255, 255 },
                    fontWeight = "bold",
                },
            },
        }
    end

    local function refreshPopup()
        closePopup()

        local canClaim = (selectedPool ~= nil) and selectAmount > 0

        -- 池子选项卡
        local poolCards = {}
        for _, opt in ipairs(poolOptions) do
            local isSel = (selectedPool == opt.id)
            poolCards[#poolCards + 1] = UI.Panel {
                flexGrow = 1,
                flexBasis = 0,
                height = 72,
                backgroundColor = isSel and { 60, 35, 90, 255 } or { 35, 26, 50, 220 },
                borderRadius = 8,
                borderWidth = isSel and 2.5 or 1,
                borderColor = isSel and { 200, 150, 255, 255 } or { 80, 65, 110, 120 },
                flexDirection = "column",
                alignItems = "center",
                justifyContent = "center",
                gap = 4,
                onClick = function()
                    selectedPool = opt.id
                    refreshPopup()
                end,
                children = {
                    -- 货币图标
                    UI.Panel {
                        width = 28, height = 28,
                        backgroundImage = opt.img,
                        backgroundFit = "contain",
                        backgroundPosition = "center",
                    },
                    -- 池子名称
                    UI.Label {
                        text = opt.name,
                        fontSize = 10,
                        fontColor = isSel and { 220, 180, 255, 255 } or { 200, 190, 220, 220 },
                        fontWeight = isSel and "bold" or "normal",
                        textAlign = "center",
                    },
                    -- 对应票券名
                    UI.Label {
                        text = opt.subname,
                        fontSize = 8,
                        fontColor = isSel and { 180, 140, 255, 255 } or { 140, 130, 160, 180 },
                        textAlign = "center",
                    },
                    -- 选中标记
                    isSel and UI.Panel {
                        position = "absolute", top = 4, right = 4,
                        width = 14, height = 14, borderRadius = 7,
                        backgroundColor = { 200, 150, 255, 255 },
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = "✓", fontSize = 9, fontColor = { 255, 255, 255, 255 }, fontWeight = "bold" },
                        },
                    } or nil,
                },
            }
        end

        local popup = UI.Panel {
            id = popupId,
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center",
            alignItems = "center",
            onClick = function() end,
            children = {
                UI.Panel {
                    width = "88%",
                    backgroundColor = { 28, 20, 42, 252 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = { 100, 75, 140, 200 },
                    flexDirection = "column",
                    overflow = "hidden",
                    children = {
                        -- 标题
                        UI.Panel {
                            width = "100%", height = 42, flexShrink = 0,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 40, 28, 60, 250 },
                            borderWidth = { bottom = 1 },
                            borderColor = { 100, 75, 140, 120 },
                            children = {
                                UI.Label {
                                    text = "选择招募池",
                                    fontSize = 16,
                                    fontColor = { 200, 150, 255, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                        -- 提示文字
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 10, paddingBottom = 4,
                            paddingLeft = 12, paddingRight = 12,
                            justifyContent = "center", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = "选择后获得对应招募券 ×" .. selectAmount,
                                    fontSize = 12,
                                    fontColor = { 180, 165, 210, 220 },
                                },
                            },
                        },
                        -- 池子卡片行
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingLeft = 12, paddingRight = 12,
                            paddingTop = 6, paddingBottom = 6,
                            flexDirection = "row",
                            gap = 8,
                            children = poolCards,
                        },
                        -- 数量控制区
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 8, paddingBottom = 8,
                            flexDirection = "row",
                            justifyContent = "center", alignItems = "center",
                            gap = 6,
                            children = {
                                numBtn("-10", function()
                                    selectAmount = math.max(1, selectAmount - 10)
                                    refreshPopup()
                                end, selectAmount <= 1),
                                numBtn("-", function()
                                    selectAmount = math.max(1, selectAmount - 1)
                                    refreshPopup()
                                end, selectAmount <= 1),
                                UI.Panel {
                                    width = 50, height = 28,
                                    backgroundColor = { 25, 18, 38, 240 },
                                    borderRadius = 4,
                                    borderWidth = 1,
                                    borderColor = { 80, 60, 110, 150 },
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label {
                                            text = tostring(selectAmount),
                                            fontSize = 14,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                                numBtn("+", function()
                                    selectAmount = math.min(maxAmount, selectAmount + 1)
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                                numBtn("+10", function()
                                    selectAmount = math.min(maxAmount, selectAmount + 10)
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                                numBtn("最大", function()
                                    selectAmount = maxAmount
                                    refreshPopup()
                                end, selectAmount >= maxAmount),
                            },
                        },
                        -- 确认/关闭按钮
                        UI.Panel {
                            width = "100%", flexShrink = 0,
                            paddingTop = 4, paddingBottom = 14,
                            justifyContent = "center", alignItems = "center",
                            flexDirection = "row", gap = 12,
                            children = {
                                UI.Panel {
                                    paddingLeft = 30, paddingRight = 30,
                                    paddingTop = 10, paddingBottom = 10,
                                    borderRadius = 8,
                                    backgroundColor = canClaim and { 75, 165, 55, 255 } or { 65, 58, 48, 220 },
                                    borderWidth = 1,
                                    borderColor = canClaim and { 100, 200, 75, 200 } or { 80, 70, 60, 150 },
                                    onClick = canClaim and function()
                                        local ok, msg, rewards = InventoryData.Use(item.id, selectAmount, selectedPool)
                                        if not ok then
                                            print("[InventoryUI] Pool select use failed: " .. (msg or ""))
                                            return
                                        end
                                        closePopup()
                                        if InventoryData.GetCount(item.id) <= 0 then
                                            selectedItemId = nil
                                        end
                                        if rewards and #rewards > 0 then
                                            RewardDisplay.Show(UI, overlay, {
                                                title = "使用 " .. def.name .. " ×" .. selectAmount,
                                                rewards = rewards,
                                                onClose = function()
                                                    RefreshInventoryContent()
                                                end,
                                            })
                                        else
                                            RefreshInventoryContent()
                                        end
                                    end or nil,
                                    children = {
                                        UI.Label {
                                            text = "确认",
                                            fontSize = 15,
                                            fontColor = canClaim and { 255, 255, 255, 255 } or { 120, 110, 100, 180 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                                UI.Panel {
                                    paddingLeft = 20, paddingRight = 20,
                                    paddingTop = 10, paddingBottom = 10,
                                    borderRadius = 8,
                                    backgroundColor = { 80, 40, 100, 230 },
                                    borderWidth = 1,
                                    borderColor = { 120, 60, 150, 200 },
                                    onClick = function() closePopup() end,
                                    children = {
                                        UI.Label {
                                            text = "关闭",
                                            fontSize = 15,
                                            fontColor = { 255, 255, 255, 255 },
                                            fontWeight = "bold",
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }

        overlay:AddChild(popup)
    end

    refreshPopup()
end

-- ============================================================================
-- 底部详情栏
-- ============================================================================

---@param item table|nil {id, count, def}
local function CreateDetailBar(item)
    if not item then
        return UI.Panel {
            width = "100%",
            height = 56,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = S.detailBg,
            borderTopWidth = 1,
            borderTopColor = S.detailBorder,
            children = {
                UI.Label {
                    text = "点击物品查看详情",
                    fontSize = 12,
                    fontColor = S.emptyText,
                },
            },
        }
    end

    local def = item.def
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        backgroundColor = S.detailBg,
        borderTopWidth = 1,
        borderTopColor = S.detailBorder,
        gap = 8,
        flexShrink = 0,
        children = {
            -- 图标
            Currency.IconWidget(UI, def.icon, 32),
            -- 名称 + 描述
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = def.name .. " ×" .. item.count,
                        fontSize = 12,
                        fontColor = S.white,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = def.desc,
                        fontSize = 10,
                        fontColor = S.dim,
                    },
                },
            },
            -- 使用按钮（仅礼包类有 use 函数时显示）
            def.use and UI.Panel {
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 7, paddingBottom = 7,
                borderRadius = 8,
                backgroundColor = S.btnUse,
                borderWidth = 1,
                borderColor = S.btnUseBorder,
                flexShrink = 0,
                onClick = function(self)
                    -- 自选英雄碎片模式：弹出英雄选择弹窗
                    if def.useMode == "select_hero" then
                        ShowHeroSelectPopup(item)
                        return
                    end
                    -- 招募券自选包：弹出池子选择弹窗
                    if def.useMode == "select_pool" then
                        ShowPoolSelectPopup(item)
                        return
                    end
                    -- 其他礼包：弹出数量选择窗口
                    ShowQuantityPopup(item)
                end,
                children = {
                    UI.Label {
                        text = "使用",
                        fontSize = 13,
                        fontColor = { 255, 255, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            } or nil,
        },
    }
end

-- ============================================================================
-- 刷新仓库内容
-- ============================================================================

function RefreshInventoryContent()
    if not contentContainer then return end
    contentContainer:ClearChildren()

    -- 确保数据已加载
    if not InventoryData.items then
        InventoryData.Load()
    end

    local allItems = InventoryData.GetAll()

    -- 标题栏
    contentContainer:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        paddingTop = 6, paddingBottom = 6,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "仓库",
                fontSize = 16,
                fontColor = S.white,
                fontWeight = "bold",
            },
        },
    })

    if #allItems == 0 then
        -- 空仓库
        contentContainer:AddChild(UI.Panel {
            flexGrow = 1,
            width = "100%",
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "仓库空空如也",
                    fontSize = 14,
                    fontColor = S.emptyText,
                },
                UI.Label {
                    text = "通过每日特惠获取物品",
                    fontSize = 11,
                    fontColor = S.emptyText,
                    marginTop = 4,
                },
            },
        })
    else
        -- 分类：可使用的道具 vs 不可使用的材料
        local usableItems = {}
        local materialItems = {}
        for _, item in ipairs(allItems) do
            if item.def.use then
                usableItems[#usableItems + 1] = item
            else
                materialItems[#materialItems + 1] = item
            end
        end

        -- 如果当前 tab 对应的列表为空，自动切到有内容的 tab
        if currentTab == "items" and #usableItems == 0 and #materialItems > 0 then
            currentTab = "materials"
        elseif currentTab == "materials" and #materialItems == 0 and #usableItems > 0 then
            currentTab = "items"
        end

        --- 构建一个分类的3列网格行列表
        ---@param items table[]
        ---@return table[] rows, table|nil selectedItem
        local function BuildGrid(items)
            local rows = {}
            local selItem = nil
            for i = 1, #items, 3 do
                local rowChildren = {}
                for j = 0, 2 do
                    local item = items[i + j]
                    if item then
                        local isSelected = (item.id == selectedItemId)
                        if isSelected then selItem = item end
                        rowChildren[#rowChildren + 1] = CreateItemCell(item, isSelected)
                    else
                        rowChildren[#rowChildren + 1] = CreateEmptyCell()
                    end
                end
                rows[#rows + 1] = UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 6,
                    children = rowChildren,
                }
            end
            return rows, selItem
        end

        -- Tab 栏
        local function TabButton(label, count, tabKey)
            local isActive = (currentTab == tabKey)
            return UI.Panel {
                flexGrow = 1,
                flexBasis = 0,
                height = 34,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = isActive and { 80, 60, 45, 220 } or { 50, 38, 28, 140 },
                borderRadius = 6,
                borderWidth = isActive and 1.5 or 1,
                borderColor = isActive and S.gold or { 80, 62, 44, 120 },
                onClick = function()
                    if currentTab ~= tabKey then
                        currentTab = tabKey
                        selectedItemId = nil
                        RefreshInventoryContent()
                    end
                end,
                children = {
                    UI.Label {
                        text = label .. (count > 0 and (" " .. count) or ""),
                        fontSize = 13,
                        fontColor = isActive and S.gold or S.dim,
                        fontWeight = isActive and "bold" or "normal",
                        pointerEvents = "none",
                    },
                },
            }
        end

        contentContainer:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 2, paddingBottom = 6,
            flexShrink = 0,
            children = {
                TabButton("道具", #usableItems, "items"),
                TabButton("材料", #materialItems, "materials"),
            },
        })

        -- 当前 tab 内容
        local displayItems = currentTab == "items" and usableItems or materialItems
        local scrollChildren = {}
        local selectedItem = nil

        if #displayItems > 0 then
            local rows, selItem = BuildGrid(displayItems)
            if selItem then selectedItem = selItem end
            for _, row in ipairs(rows) do
                scrollChildren[#scrollChildren + 1] = row
            end
        else
            scrollChildren[#scrollChildren + 1] = UI.Panel {
                width = "100%", height = 120,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = currentTab == "items" and "暂无道具" or "暂无材料",
                        fontSize = 13, fontColor = S.emptyText,
                    },
                },
            }
        end

        -- 如果 selectedItemId 有值但物品已用完，清除选中
        if selectedItemId and not selectedItem then
            selectedItemId = nil
        end

        contentContainer:AddChild(UI.ScrollView {
            flexGrow = 1, flexBasis = 0,
            scrollY = true,
            width = "100%",
            children = {
                UI.Panel {
                    width = "100%",
                    paddingTop = 4, paddingBottom = 10,
                    paddingLeft = 10, paddingRight = 10,
                    gap = 6,
                    children = scrollChildren,
                },
            },
        })

        -- 底部详情栏
        contentContainer:AddChild(CreateDetailBar(selectedItem))
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 显示仓库弹窗
---@param uiModule any  UI 模块引用
---@param parentNode any  父节点（通常是 pageRoot）
---@param onClose? fun()  关闭回调
function InventoryUI.Show(uiModule, parentNode, onClose)
    UI = uiModule
    onCloseCallback = onClose

    if overlay then
        RefreshInventoryContent()
        return
    end

    -- 确保数据已加载
    InventoryData.Load()
    selectedItemId = nil

    -- 内容容器
    contentContainer = UI.Panel {
        flexGrow = 1, flexShrink = 1,
        width = "100%",
        flexDirection = "column",
    }

    -- 弹窗面板
    local popup = UI.Panel {
        position = "absolute",
        top = 10, left = 8, right = 8, bottom = 10,
        backgroundColor = S.popupBg,
        borderRadius = 12,
        borderWidth = 1,
        borderColor = S.popupBorder,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            contentContainer,
            -- 底部返回按钮
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
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
                        onClick = function(self)
                            InventoryUI.Hide(parentNode)
                        end,
                        children = {
                            UI.Label {
                                text = "<",
                                fontSize = 14,
                                fontColor = { 180, 160, 130, 200 },
                            },
                            UI.Label {
                                text = "返回",
                                fontSize = 14,
                                fontColor = S.white,
                            },
                        },
                    },
                },
            },
        },
    }

    -- 遮罩
    overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 100,
        backgroundColor = S.overlayBg,
        children = { popup },
    }

    RefreshInventoryContent()
    parentNode:AddChild(overlay)
end

--- 隐藏仓库弹窗
---@param parentNode any
function InventoryUI.Hide(parentNode)
    if overlay then
        parentNode:RemoveChild(overlay)
        overlay = nil
        contentContainer = nil
        selectedItemId = nil
        if onCloseCallback then
            onCloseCallback()
        end
    end
end

--- 仓库是否正在显示
---@return boolean
function InventoryUI.IsVisible()
    return overlay ~= nil
end

return InventoryUI
