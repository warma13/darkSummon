-- Game/RewardDisplay.lua
-- 通用奖励展示弹窗组件
-- 用途：宝箱开启结果、活动领取奖励、成就达成奖励 等
--
-- 用法：
--   local RewardDisplay = require("Game.RewardDisplay")
--   RewardDisplay.Show(UI, parentRoot, {
--       title = "恭喜获得",          -- 可选，默认 "恭喜获得"
--       rewards = {                  -- 奖励列表
--           { icon = "image/xx.png", name = "冥晶", amount = 100 },
--           { icon = "👤", name = "SSR 炎龙", amount = 3, borderColor = {255,200,50}, avatarImage = "image/avatars/xx.png", isNew = true },
--       },
--       buttons = {                  -- 按钮列表（可选，默认一个"确定"按钮）
--           { text = "确定", variant = "primary", onClick = function() end },
--           { text = "再抽10次", variant = "primary", onClick = function() end },
--       },
--       hint = "点击确定返回",       -- 底部提示文字（可选）
--       onClose = function() end,    -- 点击确定/关闭后的回调
--   })

local Config = require("Game.Config")

local RewardDisplay = {}

local POPUP_ID = "rewardDisplayPopup"


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

--- 创建单个奖励卡片
---@param UI any
---@param reward table  { icon, name, amount, borderColor?, avatarImage?, isNew? }
---@return any
local function CreateRewardCard(UI, reward)
    local icon = reward.icon
    local name = reward.name or ""
    local amount = reward.amount or 0
    local borderColor = reward.borderColor or { 200, 170, 60, 200 }
    local avatarImage = reward.avatarImage
    local isNew = reward.isNew

    -- 图标区域
    -- icon 可以是：直接图片路径("image/xxx.png")、货币ID("void_pact")、emoji("🎫")
    local iconImg = nil
    if icon and type(icon) == "string" then
        if icon:find("%.png$") or icon:find("%.jpg$") then
            iconImg = icon
        else
            -- 尝试作为货币 ID 查找图片
            local cdef = Config.CURRENCY and Config.CURRENCY[icon]
            if cdef and cdef.image then
                iconImg = cdef.image
            end
        end
    end

    local iconChild
    if avatarImage then
        iconChild = UI.Panel {
            width = 48, height = 48,
            borderRadius = 24,
            overflow = "hidden",
            backgroundImage = avatarImage,
            backgroundFit = "cover",
        }
    elseif iconImg then
        iconChild = UI.Panel {
            width = 48, height = 48,
            backgroundImage = iconImg,
            backgroundFit = "contain",
        }
    else
        iconChild = UI.Label {
            text = icon or "?",
            fontSize = 32,
        }
    end

    -- 底部数量/NEW
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
            text = FormatNumber(amount),
            fontSize = 14,
            fontColor = { 255, 220, 80, 255 },
            fontWeight = "bold",
        }
    end

    local cardChildren = {
        iconChild,
        -- 名称标签
        UI.Panel {
            position = "absolute",
            bottom = -2, left = 0,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = { 60, 100, 40, 230 },
            borderRadius = 3,
            children = {
                UI.Label {
                    text = name,
                    fontSize = 8,
                    fontColor = { 255, 255, 255, 255 },
                },
            },
        },
        bottomChild,
    }

    -- NEW 角标
    if isNew then
        cardChildren[#cardChildren + 1] = UI.Panel {
            position = "absolute",
            top = -4, right = -4,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = { 220, 50, 50, 255 },
            borderRadius = 3,
            children = {
                UI.Label {
                    text = "NEW",
                    fontSize = 8,
                    fontColor = { 255, 255, 255, 255 },
                    fontWeight = "bold",
                },
            },
        }
    end

    return UI.Panel {
        width = "30%",
        aspectRatio = 1.0,
        marginBottom = 10,
        backgroundColor = isNew and { 50, 45, 30, 240 } or { 40, 35, 30, 230 },
        borderRadius = 8,
        borderWidth = isNew and 3 or 2,
        borderColor = isNew and { 255, 220, 60, 255 } or borderColor,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        children = cardChildren,
    }
end

--- 显示奖励弹窗
---@param UI any         UI 库引用
---@param parentRoot any 父容器节点
---@param opts table     配置项
function RewardDisplay.Show(UI, parentRoot, opts)
    opts = opts or {}
    local title = opts.title or "恭喜获得"
    local rewards = opts.rewards or {}
    local buttons = opts.buttons
    local hint = opts.hint
    local onClose = opts.onClose

    -- 移除旧弹窗
    local old = parentRoot:FindById(POPUP_ID)
    if old then parentRoot:RemoveChild(old) end

    -- 构建奖励卡片
    local rewardCards = {}
    for _, r in ipairs(rewards) do
        rewardCards[#rewardCards + 1] = CreateRewardCard(UI, r)
    end

    -- 统一关闭函数（前向声明，让默认按钮和背景点击都走同一路径）
    local dismissPopup
    dismissPopup = function()
        RewardDisplay.Hide(parentRoot)
        if onClose then onClose() end
    end

    -- 默认按钮：确定
    if not buttons or #buttons == 0 then
        buttons = {
            { text = "确定", variant = "primary", onClick = dismissPopup },
        }
    end

    -- 构建按钮组
    local btnWidgets = {}
    for _, btn in ipairs(buttons) do
        btnWidgets[#btnWidgets + 1] = UI.Button {
            text = btn.text or "确定",
            fontSize = 16,
            variant = btn.variant or "primary",
            flex = 1,
            height = 46,
            onClick = function(self)
                if btn.onClick then
                    btn.onClick()
                else
                    dismissPopup()
                end
            end,
        }
    end

    -- 底部附加区（hint 提示，用 panel 包裹避免 nil 空洞）
    local extraChildren = {}
    if hint then
        extraChildren[#extraChildren + 1] = UI.Label {
            text = hint,
            fontSize = 11,
            fontColor = { 180, 140, 100, 150 },
            marginTop = 2,
            marginBottom = 4,
            flexShrink = 0,
        }
    end
    local extraPanel = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        flexShrink = 0,
        children = extraChildren,
    }

    local popup = UI.Panel {
        id = POPUP_ID,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 200 },
        pointerEvents = "auto",
        onClick = dismissPopup,
        children = {
            -- 顶部标题区
            UI.Panel {
                width = "100%",
                alignItems = "center",
                paddingTop = 40,
                flexShrink = 0,
                children = {
                    -- "奖励" 标签
                    UI.Panel {
                        paddingLeft = 14, paddingRight = 14,
                        paddingTop = 3, paddingBottom = 3,
                        backgroundColor = { 80, 160, 60, 255 },
                        borderRadius = 4,
                        marginBottom = 6,
                        children = {
                            UI.Label {
                                text = "奖励",
                                fontSize = 12,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        text = title,
                        fontSize = 28,
                        fontColor = { 255, 255, 255, 255 },
                        fontWeight = "bold",
                        marginBottom = 12,
                    },
                },
            },
            -- 中间可滚动网格
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
            -- 底部按钮区
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 12,
                paddingLeft = 24, paddingRight = 24,
                paddingTop = 10, paddingBottom = 6,
                flexShrink = 0,
                justifyContent = "center",
                children = btnWidgets,
            },
            extraPanel,
        },
    }

    parentRoot:AddChild(popup)
end

--- 隐藏奖励弹窗
---@param parentRoot any
function RewardDisplay.Hide(parentRoot)
    local p = parentRoot:FindById(POPUP_ID)
    if p then parentRoot:RemoveChild(p) end
end

return RewardDisplay
