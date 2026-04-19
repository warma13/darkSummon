-- Game/TemperUI.lua
-- 装备淬炼界面（overlay 浮层，从装备页进入）
-- 显示：装备信息 → 5个孔位（属性+锁定） → 淬炼按钮 → 货币

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local TemperData = require("Game.TemperData")
local Currency = require("Game.Currency")

local TemperUI = {}

---@type any
local UI = nil
---@type any
local overlay = nil
---@type any
local parentNode = nil
---@type string
local curHero = nil
---@type string
local curSlot = nil
---@type fun()|nil
local onCloseCallback = nil

-- 结果提示
---@type string|nil
local resultMsg = nil
---@type table|nil
local resultColor = nil
---@type number
local resultTimer = 0

--- 格式化大数字
local function FormatNumber(n)
    if n >= 100000000 then
        return string.format("%.2f亿", n / 100000000)
    elseif n >= 10000 then
        return string.format("%.1f万", n / 10000)
    end
    return tostring(math.floor(n))
end

-- ============================================================================
-- 顶部装备信息栏
-- ============================================================================

local function CreateHeader()
    local info = require("Game.EquipData").GetSlotInfo(curHero, curSlot)
    if not info then
        return UI.Panel { height = 40 }
    end

    local tier = info.tierDef
    local temper = TemperData.GetTemper(curHero, curSlot)
    local attempts = temper and temper.totalAttempts or 0

    return UI.Panel {
        width = "100%",
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 12, paddingBottom = 8,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        flexShrink = 0,
        children = {
            -- 装备图标
            UI.Panel {
                width = 56, height = 56,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = tier.bgColor,
                borderRadius = 8,
                borderWidth = 2,
                borderColor = tier.color,
                overflow = "hidden",
                backgroundImage = "image/equip_" .. tier.id .. "_" .. curSlot .. ".png",
                backgroundFit = "cover",
            },
            -- 装备名称 + 属性
            UI.Panel {
                flex = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = info.fullName,
                        fontSize = 16,
                        fontColor = tier.color,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = info.slotDef.statName .. " +" .. (info.slotDef.fmt == "pct"
                            and string.format("%.1f%%", info.statBonus * 100)
                            or FormatNumber(info.statBonus)),
                        fontSize = 13,
                        fontColor = Config.COLORS.textGold,
                    },
                    UI.Label {
                        text = "累计淬炼: " .. attempts .. "次",
                        fontSize = 11,
                        fontColor = { 150, 140, 170, 180 },
                    },
                },
            },
            -- 关闭按钮
            UI.Button {
                text = "✕",
                fontSize = 18,
                width = 36, height = 36,
                variant = "ghost",
                onClick = function()
                    TemperUI.Close()
                end,
            },
        },
    }
end

-- ============================================================================
-- 孔位列表
-- ============================================================================

local function CreateSlotRow(slotIdx, slotData, unlocked, nextThreshold)
    -- 未解锁孔位
    if not unlocked then
        return UI.Panel {
            width = "100%",
            height = 44,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = { 20, 16, 32, 150 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { 50, 40, 70, 100 },
            children = {
                UI.Label {
                    text = "🔒 孔位" .. slotIdx,
                    fontSize = 13,
                    fontColor = { 100, 90, 120, 150 },
                },
                UI.Panel { flex = 1 },
                UI.Label {
                    text = nextThreshold and ("累计" .. nextThreshold .. "次解锁") or "",
                    fontSize = 11,
                    fontColor = { 100, 90, 120, 120 },
                },
            },
        }
    end

    -- 已解锁但空白
    if not slotData then
        return UI.Panel {
            width = "100%",
            height = 44,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = { 25, 20, 40, 180 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { 60, 50, 90, 120 },
            borderStyle = "dashed",
            children = {
                UI.Label {
                    text = "◇ 孔位" .. slotIdx .. " — 空",
                    fontSize = 13,
                    fontColor = { 130, 120, 150, 180 },
                },
            },
        }
    end

    -- 有属性
    local tierColor = slotData.tierColor or { 200, 200, 200 }
    local lockIcon = slotData.locked and "🔒" or "🔓"
    local valueText = TemperData.FormatSlotValue(slotData, curSlot)

    return UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 25, 20, 40, 220 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { tierColor[1], tierColor[2], tierColor[3], 150 },
        gap = 8,
        children = {
            -- 档位颜色条
            UI.Panel {
                width = 4, height = 28,
                borderRadius = 2,
                backgroundColor = tierColor,
                flexShrink = 0,
            },
            -- 档位名称
            UI.Label {
                text = "[" .. (slotData.tierName or "?") .. "]",
                fontSize = 12,
                fontColor = tierColor,
                fontWeight = "bold",
                width = 32,
                flexShrink = 0,
            },
            -- 属性值
            UI.Label {
                text = valueText,
                fontSize = 13,
                fontColor = { 240, 235, 250, 255 },
                fontWeight = "bold",
                flex = 1,
            },
            -- 锁定按钮
            UI.Button {
                text = lockIcon,
                fontSize = 14,
                width = 36, height = 32,
                variant = slotData.locked and "primary" or "ghost",
                borderRadius = 6,
                onClick = function()
                    local ok, msg = TemperData.ToggleLock(curHero, curSlot, slotIdx)
                    if ok then
                        print("[TemperUI] " .. msg)
                    end
                    TemperUI.Rebuild()
                end,
            },
        },
    }
end

local function CreateSlotsPanel()
    local temper = TemperData.GetTemper(curHero, curSlot)
    local unlockedCount = TemperData.GetUnlockedSlotCount(temper)
    local rows = {}

    for i = 1, Config.TEMPER_MAX_SLOTS do
        local isUnlocked = (i <= unlockedCount)
        local slotData = temper and temper.slots[i] or nil
        local nextThreshold = Config.TEMPER_SLOT_UNLOCK[i]
        rows[#rows + 1] = CreateSlotRow(i, slotData, isUnlocked, nextThreshold)
    end

    return UI.Panel {
        width = "100%",
        flex = 1,
        flexDirection = "column",
        gap = 6,
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 4, paddingBottom = 4,
        children = rows,
    }
end

-- ============================================================================
-- 淬炼按钮 + 货币
-- ============================================================================

local function CreateBottomPanel()
    local temper = TemperData.GetTemper(curHero, curSlot)

    -- 计算锁定数
    local lockedCount = 0
    if temper then
        for _, slot in pairs(temper.slots) do
            if slot and slot.locked then lockedCount = lockedCount + 1 end
        end
    end

    local jadeCost = Config.TEMPER_COST_JADE
    local rainbowCost = lockedCount
    local hasJade = Currency.Has("pale_jade", jadeCost)
    local hasRainbow = (rainbowCost == 0) or Currency.Has("rainbow_jade", rainbowCost)
    local canTemper = temper and hasJade and hasRainbow

    -- 结果提示文本
    local resultWidget = nil
    if resultMsg then
        resultWidget = UI.Panel {
            width = "100%",
            paddingTop = 2, paddingBottom = 4,
            alignItems = "center",
            children = {
                UI.Label {
                    text = resultMsg,
                    fontSize = 14,
                    fontColor = resultColor or { 255, 255, 255, 255 },
                    fontWeight = "bold",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexShrink = 0,
        flexDirection = "column",
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 4, paddingBottom = 12,
        gap = 6,
        children = {
            -- 结果提示
            resultWidget,
            -- 货币显示
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                gap = 20,
                children = {
                    -- 白玉
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            Currency.IconWidget(UI, "pale_jade", 16),
                            UI.Label {
                                text = FormatNumber(Currency.Get("pale_jade")),
                                fontSize = 13,
                                fontColor = Config.CURRENCY.pale_jade.color,
                            },
                        },
                    },
                    -- 彩玉
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            Currency.IconWidget(UI, "rainbow_jade", 16),
                            UI.Label {
                                text = FormatNumber(Currency.Get("rainbow_jade")),
                                fontSize = 13,
                                fontColor = Config.CURRENCY.rainbow_jade.color,
                            },
                        },
                    },
                },
            },
            -- 费用提示
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            UI.Label {
                                text = "消耗: ",
                                fontSize = 12,
                                fontColor = { 150, 140, 170, 180 },
                            },
                            Currency.IconWidget(UI, "pale_jade", 12),
                            UI.Label {
                                text = tostring(jadeCost),
                                fontSize = 12,
                                fontColor = hasJade and { 220, 240, 255, 255 } or { 255, 80, 60, 255 },
                            },
                        },
                    },
                    lockedCount > 0 and UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            UI.Label { text = "+", fontSize = 12, fontColor = { 150, 140, 170, 180 } },
                            Currency.IconWidget(UI, "rainbow_jade", 12),
                            UI.Label {
                                text = tostring(rainbowCost),
                                fontSize = 12,
                                fontColor = hasRainbow and { 255, 120, 220, 255 } or { 255, 80, 60, 255 },
                            },
                            UI.Label {
                                text = "(锁定)",
                                fontSize = 10,
                                fontColor = { 150, 140, 170, 150 },
                            },
                        },
                    } or nil,
                },
            },
            -- 淬炼按钮
            UI.Button {
                text = "淬  炼",
                fontSize = 18,
                fontWeight = "bold",
                width = "100%",
                height = 48,
                variant = canTemper and "primary" or "ghost",
                onClick = function()
                    if not canTemper then return end
                    local ok, msg, result = TemperData.DoTemper(curHero, curSlot)
                    if ok then
                        if result and result.hit then
                            resultMsg = "✦ 淬炼成功！"
                            resultColor = { 100, 255, 100, 255 }
                            local AudioManager = require("Game.AudioManager")
                            AudioManager.PlayUpgrade()
                        else
                            resultMsg = "淬炼失败，属性未变"
                            resultColor = { 255, 160, 80, 200 }
                        end
                    else
                        resultMsg = msg
                        resultColor = { 255, 80, 60, 255 }
                    end
                    resultTimer = 2.0
                    TemperUI.Rebuild()
                end,
            },
            -- 成功率提示
            UI.Label {
                text = "成功率 " .. math.floor(Config.TEMPER_SUCCESS_RATE * 100) .. "%",
                fontSize = 11,
                fontColor = { 120, 110, 140, 150 },
                textAlign = "center",
            },
        },
    }
end

-- ============================================================================
-- 解锁面板（未解锁淬炼时显示）
-- ============================================================================

local function CreateUnlockPanel()
    local canUnlock, reason = TemperData.CanUnlock(curHero, curSlot)

    return UI.Panel {
        width = "100%",
        flex = 1,
        justifyContent = "center",
        alignItems = "center",
        gap = 12,
        paddingLeft = 24, paddingRight = 24,
        children = {
            UI.Label {
                text = "⚒ 装备淬炼",
                fontSize = 20,
                fontColor = Config.COLORS.textGold,
                fontWeight = "bold",
            },
            UI.Label {
                text = "红色满级装备可开启淬炼\n为装备附加随机属性词条",
                fontSize = 13,
                fontColor = { 180, 170, 200, 200 },
                textAlign = "center",
            },
            -- 解锁条件列表
            UI.Panel {
                width = "100%",
                gap = 4,
                paddingTop = 8,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "解锁条件:",
                        fontSize = 13,
                        fontColor = { 150, 140, 170, 180 },
                    },
                    UI.Label {
                        text = "• 装备等级 Lv." .. Config.TEMPER_UNLOCK_LEVEL,
                        fontSize = 12,
                        fontColor = { 140, 130, 160, 180 },
                    },
                    UI.Label {
                        text = "• 红色品质",
                        fontSize = 12,
                        fontColor = { 140, 130, 160, 180 },
                    },
                    UI.Label {
                        text = "• 通过第" .. Config.TEMPER_UNLOCK_STAGE .. "关",
                        fontSize = 12,
                        fontColor = { 140, 130, 160, 180 },
                    },
                    UI.Label {
                        text = "• 消耗 " .. Config.TEMPER_UNLOCK_COST .. " 暗影精粹",
                        fontSize = 12,
                        fontColor = { 140, 130, 160, 180 },
                    },
                },
            },
            -- 解锁按钮
            UI.Panel {
                paddingTop = 12,
                children = {
                    UI.Button {
                        text = canUnlock and "开启淬炼" or reason,
                        fontSize = 15,
                        width = 180, height = 44,
                        variant = canUnlock and "primary" or "ghost",
                        onClick = function()
                            if not canUnlock then return end
                            local ok, msg = TemperData.Unlock(curHero, curSlot)
                            print("[TemperUI] Unlock: " .. msg)
                            TemperUI.Rebuild()
                        end,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化 UI 模块引用
---@param uiModule any
function TemperUI.Init(uiModule)
    UI = uiModule
end

--- 打开淬炼界面
---@param parent any   挂载的父节点
---@param heroId string
---@param slotId string
---@param onClose fun()|nil  关闭回调
function TemperUI.Open(parent, heroId, slotId, onClose)
    if not UI then return end
    curHero = heroId
    curSlot = slotId
    onCloseCallback = onClose
    parentNode = parent
    resultMsg = nil
    resultTimer = 0

    TemperUI.Rebuild()
end

--- 重建 overlay 内容
function TemperUI.Rebuild()
    if not UI or not parentNode then return end

    -- 移除旧 overlay
    if overlay then
        parentNode:RemoveChild(overlay)
        overlay = nil
    end

    local temper = TemperData.GetTemper(curHero, curSlot)
    local contentChildren = {}

    -- 标题栏
    contentChildren[#contentChildren + 1] = CreateHeader()

    -- 分隔线
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        alignSelf = "center",
        backgroundColor = { 80, 60, 120, 80 },
        flexShrink = 0,
    }

    if temper then
        -- 已解锁：孔位 + 淬炼按钮
        contentChildren[#contentChildren + 1] = CreateSlotsPanel()
        contentChildren[#contentChildren + 1] = CreateBottomPanel()
    else
        -- 未解锁：解锁面板
        contentChildren[#contentChildren + 1] = CreateUnlockPanel()
    end

    -- 创建 overlay
    overlay = UI.Panel {
        id = "temperOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        children = {
            -- 内容面板
            UI.Panel {
                width = "92%",
                maxWidth = 400,
                height = "80%",
                maxHeight = 520,
                flexDirection = "column",
                backgroundColor = { 20, 16, 35, 250 },
                borderRadius = 16,
                borderWidth = 1,
                borderColor = { 100, 80, 160, 150 },
                overflow = "hidden",
                children = contentChildren,
            },
        },
    }

    parentNode:AddChild(overlay)
end

--- 关闭淬炼界面
function TemperUI.Close()
    if overlay and parentNode then
        parentNode:RemoveChild(overlay)
        overlay = nil
    end
    curHero = nil
    curSlot = nil
    resultMsg = nil
    resultTimer = 0
    if onCloseCallback then
        onCloseCallback()
        onCloseCallback = nil
    end
end

--- 是否打开中
---@return boolean
function TemperUI.IsOpen()
    return overlay ~= nil
end

--- 每帧更新（清除提示文字定时器）
---@param dt number
function TemperUI.Update(dt)
    if resultTimer > 0 then
        resultTimer = resultTimer - dt
        if resultTimer <= 0 then
            resultMsg = nil
            resultColor = nil
            if overlay then
                TemperUI.Rebuild()
            end
        end
    end
end

return TemperUI
