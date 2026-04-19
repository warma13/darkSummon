-- Game/TaskCard.lua
-- 可复用任务卡组件：展示任务描述、进度条、奖励标签、领取按钮

local TaskCard = {}

-- 默认样式
local DEFAULT_STYLES = {
    bgCard     = { 30, 24, 50, 220 },
    bgDone     = { 30, 40, 30, 200 },
    bgBar      = { 40, 30, 60, 200 },
    bgBadge    = { 50, 35, 80, 220 },
    borderGold = { 220, 180, 60, 200 },
    badgeBorder = { 120, 90, 180, 100 },
    textNormal = { 220, 210, 240, 255 },
    textDim    = { 150, 140, 170, 200 },
    textGreen  = { 100, 220, 120, 255 },
    barFill    = { 160, 100, 240, 255 },
    barGreen   = { 80, 180, 80, 255 },
    red        = { 255, 80, 80, 255 },
    accent     = { 180, 120, 255, 255 },
}

--- 创建进度条
---@param UI any
---@param current number
---@param total number
---@param fillColor table
---@param bgColor table
---@return any
local function ProgressBar(UI, current, total, fillColor, bgColor)
    local h = 8
    local pct = total > 0 and math.min(1, current / total) or 0
    return UI.Panel {
        width = "100%", height = h,
        backgroundColor = bgColor,
        borderRadius = h / 2,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = math.floor(pct * 100) .. "%",
                height = "100%",
                backgroundColor = fillColor,
                borderRadius = h / 2,
            },
        },
    }
end

--- 创建任务卡
---@param UI any        UI 模块
---@param opts table    配置项
---   opts.desc: string          任务描述
---   opts.current: number       当前进度
---   opts.target: number        目标进度
---   opts.claimed: boolean      是否已领取
---   opts.rewardLabel: string   奖励上方小标题（如 "积分"、"奖励"）
---   opts.rewardValue: string   奖励数值文本（如 "+15"、"x200"）
---   opts.rewardColor: table    奖励数值颜色
---   opts.onClaim: function     点击领取回调
---   opts.buttonRight: boolean  按钮放右侧（默认 false，放左侧）
---   opts.styles: table|nil     样式覆盖
---@return any widget
function TaskCard.Create(UI, opts)
    local S = {}
    for k, v in pairs(DEFAULT_STYLES) do S[k] = v end
    if opts.styles then
        for k, v in pairs(opts.styles) do S[k] = v end
    end

    local current = opts.current or 0
    local target = opts.target or 1
    local claimed = opts.claimed or false
    local done = current >= target
    local capped = math.min(current, target)
    local buttonRight = opts.buttonRight or false

    -- 进度条颜色
    local barColor = claimed and S.textDim or (done and S.barGreen or S.barFill)

    -- 按钮状态（未完成时不显示按钮）
    local showBtn = claimed or done
    local btnText, btnVariant, btnDisabled
    if claimed then
        btnText = "已领取"
        btnVariant = "outline"
        btnDisabled = true
    elseif done then
        btnText = "领取"
        btnVariant = "primary"
        btnDisabled = false
    end

    -- 奖励文字徽章
    local badgeWidget = UI.Panel {
        paddingLeft = 6, paddingRight = 6,
        paddingTop = 3, paddingBottom = 3,
        backgroundColor = S.bgBadge,
        borderRadius = 4,
        borderWidth = 1,
        borderColor = S.badgeBorder,
        alignItems = "center",
        children = {
            UI.Label {
                text = opts.rewardLabel or "奖励",
                fontSize = 9, fontColor = S.textDim,
            },
            UI.Label {
                text = opts.rewardValue or "",
                fontSize = 13,
                fontColor = opts.rewardColor or S.accent,
                fontWeight = "bold",
            },
        },
    }

    -- 按钮组件（含红点），未完成时不显示
    local btnChildren = {}
    if showBtn then
        if done and not claimed then
            btnChildren[#btnChildren + 1] = UI.Panel {
                width = 8, height = 8, borderRadius = 4,
                backgroundColor = S.red,
            }
        end
        btnChildren[#btnChildren + 1] = UI.Button {
            text = btnText,
            fontSize = buttonRight and 13 or 11,
            width = buttonRight and 64 or 56,
            height = buttonRight and 30 or 24,
            borderRadius = buttonRight and 6 or 5,
            variant = btnVariant,
            disabled = btnDisabled,
            onClick = (not claimed and done and opts.onClaim) and function()
                opts.onClaim()
            end or nil,
        }
    end

    if buttonRight then
        -- ========== 按钮在右侧：徽章 | 描述+进度 | 按钮 ==========
        return UI.Panel {
            width = "100%",
            backgroundColor = claimed and S.bgDone or S.bgCard,
            borderRadius = 8,
            padding = 10,
            gap = 6,
            borderWidth = (done and not claimed) and 1 or 0,
            borderColor = S.borderGold,
            children = {
                -- 上行：徽章 + 描述 + 按钮
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "space-between",
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 8,
                            flexShrink = 1,
                            children = {
                                badgeWidget,
                                UI.Label {
                                    text = opts.desc or "",
                                    fontSize = 14,
                                    fontColor = claimed and S.textDim or S.textNormal,
                                },
                            },
                        },
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = btnChildren,
                        },
                    },
                },
                -- 下行：进度条 + 数字
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1,
                            children = {
                                ProgressBar(UI, capped, target, barColor, S.bgBar),
                            },
                        },
                        UI.Label {
                            text = capped .. "/" .. target,
                            fontSize = 11,
                            fontColor = done and S.textGreen or S.textDim,
                            width = 40,
                            textAlign = "right",
                        },
                    },
                },
            },
        }
    else
        -- ========== 按钮在左侧：(徽章+按钮) | 描述+进度 ==========
        return UI.Panel {
            width = "100%",
            backgroundColor = claimed and S.bgDone or S.bgCard,
            borderRadius = 8,
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 6, paddingRight = 10,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            borderWidth = (done and not claimed) and 1 or 0,
            borderColor = S.borderGold,
            children = {
                -- 左列：奖励徽章 + 按钮
                UI.Panel {
                    width = 60,
                    flexShrink = 0,
                    alignItems = "center",
                    gap = 4,
                    children = {
                        badgeWidget,
                        UI.Panel {
                            alignItems = "center",
                            children = btnChildren,
                        },
                    },
                },
                -- 右列：描述 + 进度条
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 5,
                    children = {
                        UI.Label {
                            text = opts.desc or "",
                            fontSize = 14,
                            fontColor = claimed and S.textDim or S.textNormal,
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 8,
                            children = {
                                UI.Panel {
                                    flexGrow = 1, flexShrink = 1,
                                    children = {
                                        ProgressBar(UI, capped, target, barColor, S.bgBar),
                                    },
                                },
                                UI.Label {
                                    text = capped .. "/" .. target,
                                    fontSize = 11,
                                    fontColor = done and S.textGreen or S.textDim,
                                    width = 40,
                                    textAlign = "right",
                                },
                            },
                        },
                    },
                },
            },
        }
    end
end

return TaskCard
