-- Game/MailboxUI.lua
-- 邮件系统 UI：展示邮件列表，支持领取和清理

local MailboxData    = require("Game.MailboxData")
local Toast          = require("Game.Toast")
local Tooltip        = require("Game.Tooltip")
local RewardIconMod  = require("Game.RewardIcon")
local SlotSave       = require("Game.SlotSaveSystem")
local RewardDisplay  = require("Game.RewardDisplay")
local Config         = require("Game.Config")

local MailboxUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

--- 外部回调（关闭、一键领取等，由 GameUI 通过 SetCallbacks 注入）
local _callbacks = {}

-- 样式常量（暗紫主题）
local S = {
    bgPage     = { 12, 10, 25, 250 },
    bgHeader   = { 30, 22, 50, 240 },
    bgCard     = { 35, 28, 55, 220 },
    bgCardDim  = { 25, 20, 40, 180 },
    border     = { 80, 65, 120, 150 },
    borderGold = { 220, 180, 60, 200 },
    textTitle  = { 255, 220, 100, 255 },
    textWhite  = { 240, 235, 255, 255 },
    textNormal = { 220, 210, 240, 255 },
    textDim    = { 150, 140, 170, 200 },
    textGold   = { 255, 200, 60, 255 },
    textGreen  = { 100, 220, 120, 255 },
    accent     = { 180, 120, 255, 255 },
    red        = { 255, 80, 80, 255 },
    claimBg    = { 200, 100, 40, 255 },
    claimedBg  = { 60, 60, 60, 200 },
}

-- ============================================================================
-- 公开接口
-- ============================================================================

--- VirtualList 单行高度
local MAIL_ITEM_HEIGHT = 130

--- 缓存邮件数据供 VirtualList 使用
local mailListData = {}

--- 注入外部回调（onClose / onClaimAll）
function MailboxUI.SetCallbacks(cb)
    _callbacks = cb or {}
end

function MailboxUI.CreatePage(uiModule)
    UI = uiModule

    pageRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = S.bgPage,
        overflow = "hidden",
        children = {
            MailboxUI._BuildHeader(),
            -- VirtualList 容器
            UI.Panel {
                id = "mailListContainer",
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                flexBasis = 0,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 8, paddingBottom = 8,
            },
            -- 底部操作栏容器
            UI.Panel {
                id = "mailActionBar",
                width = "100%",
                flexShrink = 0,
                paddingBottom = 8,
            },
        },
    }
    return pageRoot
end

--- 创建邮件卡片模板（VirtualList createItem）
local function _CreateMailItem()
    local item = UI.Panel {
        width = "100%",
        height = MAIL_ITEM_HEIGHT,
        backgroundColor = S.bgCard,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = S.border,
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 10, paddingRight = 10,
        gap = 6,
    }

    -- 标题行
    local titleRow = UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        width = "100%",
    }
    local titleLeft = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, flexShrink = 1,
    }
    local titleLabel = UI.Label {
        id = "mailTitle", text = "", fontSize = 13,
        fontColor = S.textWhite, fontWeight = "bold",
    }
    titleLeft:AddChild(titleLabel)
    local timeLabel = UI.Label {
        id = "mailTime", text = "", fontSize = 10, fontColor = S.textDim,
    }
    titleRow:AddChild(titleLeft)
    titleRow:AddChild(timeLabel)
    item:AddChild(titleRow)

    -- 描述（最多2行，点击卡片查看完整内容）
    local descLabel = UI.Label {
        id = "mailDesc", text = "", fontSize = 11, fontColor = S.textDim,
        width = "100%", flexShrink = 1, maxLines = 2,
    }
    item:AddChild(descLabel)

    -- 奖励行 + 按钮
    local rewardRow = UI.Panel {
        id = "mailRewardRow",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        width = "100%",
    }
    local rewardIcons = UI.Panel {
        id = "mailRewardIcons",
        flexDirection = "row", gap = 4, pointerEvents = "auto",
    }
    rewardRow:AddChild(rewardIcons)

    local claimBtn = UI.Panel {
        id = "mailClaimBtn",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 6, paddingBottom = 6,
        borderRadius = 6,
        backgroundColor = S.claimBg,
        borderWidth = 1,
        borderColor = { 255, 160, 60, 200 },
        pointerEvents = "auto",
        children = {
            UI.Label {
                text = "领取", fontSize = 12,
                fontColor = { 255, 255, 255 }, fontWeight = "bold",
            },
        },
    }
    rewardRow:AddChild(claimBtn)
    item:AddChild(rewardRow)

    -- 缓存引用
    item._titleLabel = titleLabel
    item._timeLabel = timeLabel
    item._descLabel = descLabel
    item._rewardIcons = rewardIcons
    item._claimBtn = claimBtn
    item._rewardRow = rewardRow

    return item
end

--- 绑定邮件数据到卡片（VirtualList bindItem）
local function _BindMailItem(widget, data, index)
    local mail = data
    local claimed = mail.claimed

    -- 背景 & 透明度
    widget:SetStyle({
        backgroundColor = claimed and S.bgCardDim or S.bgCard,
        borderColor = claimed and { 50, 45, 60, 80 } or S.border,
        opacity = claimed and 0.5 or 1.0,
    })

    -- 标题
    widget._titleLabel:SetText(mail.title or "系统邮件")
    widget._titleLabel:SetStyle({
        fontColor = claimed and S.textDim or S.textWhite,
        fontWeight = claimed and "normal" or "bold",
    })

    -- 时间/状态
    local timeStr = ""
    if claimed then
        timeStr = "已领取"
    elseif mail.timestamp then
        timeStr = os.date("%m-%d %H:%M", mail.timestamp)
    end
    widget._timeLabel:SetText(timeStr)
    widget._timeLabel:SetStyle({
        fontColor = claimed and { 120, 200, 120, 180 } or S.textDim,
    })

    -- 描述
    widget._descLabel:SetText(mail.desc or "")
    widget._descLabel:SetVisible(mail.desc ~= nil and mail.desc ~= "")

    -- 奖励图标
    widget._rewardIcons:ClearChildren()
    if mail.rewards then
        for _, reward in ipairs(mail.rewards) do
            local iconId = reward.id
            if reward.type == "chest" then
                iconId = reward.id .. "_chest"
            end
            local icon = RewardIconMod.Create(UI, 32, iconId, reward.amount, {
                muted = claimed,
            })
            widget._rewardIcons:AddChild(icon)
        end
    end

    -- 领取按钮
    local showBtn = not claimed and mail.rewards and #mail.rewards > 0
    widget._claimBtn:SetVisible(showBtn)
    if showBtn then
        widget._claimBtn.props.onClick = function()
            local ok, msg = MailboxData.Claim(index)
            if ok then
                SlotSave.MarkDirty()
                MailboxUI.Refresh()
                local rewardItems = {}
                for _, r in ipairs(mail.rewards) do
                    local cdef = Config.CURRENCY[r.id]
                    -- fallback: 道具查 InventoryData.ITEM_DEFS → icon 字段二次查 CURRENCY
                    if not cdef and r.type == "item" then
                        local okI, InvD = pcall(require, "Game.InventoryData")
                        if okI and InvD.ITEM_DEFS then
                            local itemDef = InvD.ITEM_DEFS[r.id]
                            if itemDef then
                                local iconKey = itemDef.icon or r.id
                                local iconCdef = Config.CURRENCY[iconKey]
                                cdef = {
                                    name = itemDef.name,
                                    image = itemDef.image or (iconCdef and iconCdef.image),
                                    color = (iconCdef and iconCdef.color) or { 200, 170, 60 },
                                }
                            end
                        end
                    end
                    if r.type == "chest" then
                        local chestDef = Config.CHEST_TYPES_MAP and Config.CHEST_TYPES_MAP[r.id]
                        rewardItems[#rewardItems + 1] = {
                            icon = (chestDef and chestDef.image) or "📦",
                            name = (chestDef and chestDef.name) or r.id,
                            amount = r.amount,
                            borderColor = chestDef and chestDef.color or { 200, 170, 60 },
                        }
                    else
                        rewardItems[#rewardItems + 1] = {
                            icon = (cdef and cdef.image) or "💎",
                            name = (cdef and cdef.name) or r.id,
                            amount = r.amount,
                            borderColor = (cdef and cdef.color) or { 200, 170, 60 },
                        }
                    end
                end
                if #rewardItems > 0 then
                    RewardDisplay.Show(UI, pageRoot, {
                        title = mail.title or "邮件奖励",
                        rewards = rewardItems,
                    })
                end
            else
                Toast.Show(msg or "领取失败", "error")
            end
        end
    end

    -- 点击卡片弹出详情（onTap 区分拖动滚动，不误触）
    widget.props.pointerEvents = "auto"
    widget.props.onTap = function()
        MailboxUI._ShowDetail(mail, index)
    end
end

-- ============================================================================
-- 邮件详情弹窗
-- ============================================================================

function MailboxUI._ShowDetail(mail, index)
    if not pageRoot then return end

    local claimed = mail.claimed

    -- 遮罩
    local overlay = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
    }

    -- 弹窗主体
    local dialog = UI.Panel {
        width = "88%",
        maxHeight = "70%",
        backgroundColor = { 30, 24, 50, 250 },
        borderRadius = 12,
        borderWidth = 1,
        borderColor = S.border,
        paddingTop = 16, paddingBottom = 16,
        paddingLeft = 14, paddingRight = 14,
        gap = 10,
    }

    -- 标题行
    dialog:AddChild(UI.Panel {
        flexDirection = "row", justifyContent = "space-between",
        alignItems = "center", width = "100%",
        children = {
            UI.Label {
                text = mail.title or "系统邮件",
                fontSize = 15, fontColor = S.textWhite, fontWeight = "bold",
                flexShrink = 1,
            },
            UI.Label {
                text = mail.timestamp and os.date("%m-%d %H:%M", mail.timestamp) or "",
                fontSize = 10, fontColor = S.textDim,
            },
        },
    })

    -- 分割线
    dialog:AddChild(UI.Panel {
        width = "100%", height = 1, backgroundColor = { 80, 65, 120, 100 },
    })

    -- 完整描述（可滚动）
    if mail.desc and mail.desc ~= "" then
        local scrollDesc = UI.ScrollView {
            width = "100%",
            maxHeight = 160,
            children = {
                UI.Label {
                    text = mail.desc,
                    fontSize = 12, fontColor = S.textNormal,
                    width = "100%",
                },
            },
        }
        dialog:AddChild(scrollDesc)
    end

    -- 奖励
    if mail.rewards and #mail.rewards > 0 then
        local rewardRow = UI.Panel {
            flexDirection = "row", gap = 6, flexWrap = "wrap",
            width = "100%",
        }
        for _, reward in ipairs(mail.rewards) do
            local iconId = reward.id
            if reward.type == "chest" then iconId = reward.id .. "_chest" end
            rewardRow:AddChild(RewardIconMod.Create(UI, 40, iconId, reward.amount, {
                muted = claimed,
            }))
        end
        dialog:AddChild(rewardRow)
    end

    -- 底部按钮
    local btnRow = UI.Panel {
        flexDirection = "row", justifyContent = "center",
        gap = 12, width = "100%", marginTop = 4,
    }

    -- 关闭按钮
    btnRow:AddChild(UI.Button {
        text = "关闭", variant = "outline", fontSize = 13,
        paddingLeft = 24, paddingRight = 24,
        onClick = function()
            overlay:Remove()
        end,
    })

    -- 领取按钮（未领取时显示）
    if not claimed and mail.rewards and #mail.rewards > 0 then
        btnRow:AddChild(UI.Button {
            text = "领取", variant = "primary", fontSize = 13,
            paddingLeft = 24, paddingRight = 24,
            onClick = function()
                local ok, msg = MailboxData.Claim(index)
                if ok then
                    SlotSave.MarkDirty()
                    overlay:Remove()
                    MailboxUI.Refresh()
                    -- 奖励弹窗
                    local rewardItems = {}
                    for _, r in ipairs(mail.rewards) do
                        local cdef = Config.CURRENCY[r.id]
                        if not cdef and r.type == "item" then
                            local okI, InvD = pcall(require, "Game.InventoryData")
                            if okI and InvD.ITEM_DEFS then
                                local itemDef = InvD.ITEM_DEFS[r.id]
                                if itemDef then
                                    local iconKey = itemDef.icon or r.id
                                    local iconCdef = Config.CURRENCY[iconKey]
                                    cdef = {
                                        name = itemDef.name,
                                        image = itemDef.image or (iconCdef and iconCdef.image),
                                        color = (iconCdef and iconCdef.color) or { 200, 170, 60 },
                                    }
                                end
                            end
                        end
                        rewardItems[#rewardItems + 1] = {
                            icon = (cdef and cdef.image) or r.id,
                            name = (cdef and cdef.name) or r.id,
                            amount = r.amount,
                            borderColor = (cdef and cdef.color) or { 200, 170, 60 },
                        }
                    end
                    if #rewardItems > 0 then
                        RewardDisplay.Show(UI, pageRoot, {
                            title = mail.title or "邮件奖励",
                            rewards = rewardItems,
                        })
                    end
                else
                    Toast.Show(msg or "领取失败", "error")
                end
            end,
        })
    end

    dialog:AddChild(btnRow)
    overlay:AddChild(dialog)
    pageRoot:AddChild(overlay)
end

function MailboxUI.Refresh()
    if not pageRoot then return end

    -- 更新邮件数量
    local countLabel = pageRoot:FindById("mailCountLabel")
    local mails = MailboxData.GetAll()
    local unclaimed = MailboxData.GetUnclaimedCount()
    if countLabel then
        local hint = #mails > 3 and "  上滑查看更多" or ""
        countLabel:SetText("未读 " .. unclaimed .. " / 共 " .. #mails .. hint)
    end

    -- 列表容器
    local container = pageRoot:FindById("mailListContainer")
    if not container then return end
    container:ClearChildren()

    -- 底部操作栏
    local actionBar = pageRoot:FindById("mailActionBar")
    if actionBar then
        actionBar:ClearChildren()
    end

    if #mails == 0 then
        container:AddChild(MailboxUI._BuildEmptyState())
        -- 空状态也要保留返回按钮
        if actionBar then
            actionBar:AddChild(MailboxUI._BuildActionBar())
        end
        return
    end

    -- 用 VirtualList 渲染邮件
    mailListData = mails
    local vlist = UI.VirtualList {
        width = "100%",
        height = "100%",
        data = mailListData,
        itemHeight = MAIL_ITEM_HEIGHT,
        itemGap = 8,
        poolBuffer = 3,
        createItem = _CreateMailItem,
        bindItem = _BindMailItem,
    }
    container:AddChild(vlist)

    -- 底部操作栏
    if actionBar then
        actionBar:AddChild(MailboxUI._BuildActionBar())
    end

    Tooltip.Init(UI, pageRoot)
end

-- ============================================================================
-- 顶部标题
-- ============================================================================

function MailboxUI._BuildHeader()
    return UI.Panel {
        width = "100%",
        paddingTop = 14, paddingBottom = 10,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = S.bgHeader,
        borderBottomWidth = 1,
        borderColor = { 100, 80, 160, 80 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Panel {
                gap = 1,
                children = {
                    UI.Label {
                        text = "邮件",
                        fontSize = 18, fontColor = S.textTitle, fontWeight = "bold",
                    },
                    UI.Label {
                        id = "mailCountLabel",
                        text = "未读 0 / 共 0",
                        fontSize = 10, fontColor = S.textDim,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 空状态
-- ============================================================================

function MailboxUI._BuildEmptyState()
    return UI.Panel {
        width = "100%", height = 200,
        justifyContent = "center",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Label {
                text = "暂无邮件",
                fontSize = 14, fontColor = S.textDim,
            },
        },
    }
end

-- ============================================================================
-- 底部操作栏
-- ============================================================================

function MailboxUI._BuildActionBar()
    local hasUnclaimed = MailboxData.HasUnclaimed()
    local hasClaimed = false
    for _, m in ipairs(MailboxData.GetAll()) do
        if m.claimed then hasClaimed = true; break end
    end

    local buttons = {}

    -- 返回按钮
    buttons[#buttons + 1] = UI.Panel {
        paddingLeft = 20, paddingRight = 20,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = { 60, 50, 80, 200 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = S.border,
        pointerEvents = "auto",
        onClick = function()
            if _callbacks.onClose then _callbacks.onClose() end
        end,
        children = {
            UI.Label {
                text = "返回", fontSize = 12, fontColor = S.textNormal,
            },
        },
    }

    -- 一键领取按钮
    if hasUnclaimed then
        buttons[#buttons + 1] = UI.Panel {
            paddingLeft = 20, paddingRight = 20,
            paddingTop = 8, paddingBottom = 8,
            backgroundColor = S.claimBg,
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { 255, 160, 60, 200 },
            pointerEvents = "auto",
            onClick = function()
                if _callbacks.onClaimAll then _callbacks.onClaimAll() end
            end,
            children = {
                UI.Label {
                    text = "一键领取", fontSize = 12,
                    fontColor = { 255, 255, 255 }, fontWeight = "bold",
                },
            },
        }
    end

    -- 清理已读按钮
    if hasClaimed then
        buttons[#buttons + 1] = UI.Panel {
            paddingLeft = 20, paddingRight = 20,
            paddingTop = 8, paddingBottom = 8,
            backgroundColor = { 60, 50, 80, 200 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = S.border,
            pointerEvents = "auto",
            onClick = function()
                MailboxData.ClearClaimed()
                SlotSave.MarkDirty()
                Toast.Show("已清理", { 180, 170, 200 })
                MailboxUI.Refresh()
            end,
            children = {
                UI.Label {
                    text = "清理已读", fontSize = 12, fontColor = S.textDim,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 12,
        marginTop = 8,
        paddingBottom = 8,
        children = buttons,
    }
end

return MailboxUI
