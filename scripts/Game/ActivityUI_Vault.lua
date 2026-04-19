-- Game/ActivityUI_Vault.lua
-- 深渊金库 UI（分段利率版）

return function(ctx, Shared)

local VaultData = require("Game.VaultData")
local Currency  = require("Game.Currency")
local Toast     = require("Game.Toast")
local RC        = require("Game.RewardController")

local S        = Shared.S
local FormatNum = Shared.FormatNum

local Mod = {}

-- ============================================================================
-- 工具
-- ============================================================================

local function Row(children, extra)
    local t = extra or {}
    t.flexDirection = t.flexDirection or "row"
    t.alignItems    = t.alignItems    or "center"
    t.children      = children
    return ctx.UI.Panel(t)
end

-- 填充进度条
local function ProgressBar(filled, total, color)
    local pct = total > 0 and math.min(filled / total, 1.0) or 0
    return ctx.UI.Panel {
        width = "100%", height = 7,
        backgroundColor = { 30, 24, 50, 200 },
        borderRadius = 4,
        overflow = "hidden",
        children = {
            ctx.UI.Panel {
                width  = math.floor(pct * 100) .. "%",
                height = "100%",
                backgroundColor = color or { 100, 180, 255, 220 },
                borderRadius = 4,
            },
        },
    }
end

-- ============================================================================
-- 存入确认弹窗
-- ============================================================================

local confirmOverlay = nil  ---@type any
local confirmCb      = nil

local function HideDepositConfirm()
    if confirmOverlay then confirmOverlay:SetVisible(false) end
    confirmCb = nil
end

local function ShowDepositConfirm(amount, dailyAdd, onConfirm)
    local amtEl   = confirmOverlay:FindById("dcAmount")
    local dailyEl = confirmOverlay:FindById("dcDaily")
    if amtEl   then amtEl:SetText("存入 " .. FormatNum(amount) .. " 精粹") end
    if dailyEl then
        if dailyAdd > 0 then
            dailyEl:SetText("次日起每日收益增加 +" .. dailyAdd .. " 精粹")
        else
            dailyEl:SetText("存入后次日起开始计息")
        end
    end
    confirmCb = onConfirm
    confirmOverlay:SetVisible(true)
end

local function BuildConfirmOverlay()
    local overlay = ctx.UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = 100 .. "%",
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems     = "center",
        onClick = function() HideDepositConfirm() end,
        children = {
            ctx.UI.Panel {
                width  = "80%",
                paddingTop = 22, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                backgroundColor = { 32, 26, 50, 252 },
                borderRadius = 14,
                borderWidth  = 1,
                borderColor  = { 90, 78, 120, 180 },
                gap = 14,
                alignItems = "center",
                onClick = function() end,
                children = {
                    ctx.UI.Label {
                        text = "确认存入",
                        fontSize  = 16,
                        fontColor = { 230, 225, 245, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 110, 120 },
                    },
                    ctx.UI.Label {
                        id = "dcAmount",
                        text = "",
                        fontSize  = 20,
                        fontColor = { 255, 215, 80, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Label {
                        id = "dcDaily",
                        text = "",
                        fontSize  = 11,
                        fontColor = { 130, 220, 130, 230 },
                    },
                    ctx.UI.Label {
                        text      = "今日存入，明日起计息",
                        fontSize  = 10,
                        fontColor = { 140, 130, 160, 200 },
                    },
                    Row({
                        ctx.UI.Panel {
                            flex = 1,
                            paddingTop = 10, paddingBottom = 10,
                            alignItems = "center",
                            backgroundColor = { 45, 40, 62, 220 },
                            borderRadius = 8,
                            borderWidth  = 1,
                            borderColor  = { 75, 68, 98, 160 },
                            onClick = function() HideDepositConfirm() end,
                            children = {
                                ctx.UI.Label {
                                    text      = "取消",
                                    fontSize  = 13,
                                    fontColor = { 170, 160, 190, 230 },
                                },
                            },
                        },
                        ctx.UI.Panel {
                            flex = 1,
                            paddingTop = 10, paddingBottom = 10,
                            alignItems = "center",
                            backgroundColor = { 50, 120, 130, 220 },
                            borderRadius = 8,
                            borderWidth  = 1,
                            borderColor  = { 80, 195, 210, 200 },
                            onClick = function()
                                if confirmCb then confirmCb() end
                                HideDepositConfirm()
                            end,
                            children = {
                                ctx.UI.Label {
                                    text      = "确认",
                                    fontSize  = 13,
                                    fontColor = { 210, 248, 255, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                    }, { gap = 10, width = "100%" }),
                },
            },
        },
    }
    overlay:SetVisible(false)
    confirmOverlay = overlay
    return overlay
end

-- ============================================================================
-- 取出确认弹窗
-- ============================================================================

local withdrawOverlay = nil  ---@type any
local withdrawCb      = nil

local function HideWithdrawConfirm()
    if withdrawOverlay then withdrawOverlay:SetVisible(false) end
    withdrawCb = nil
end

local function ShowWithdrawConfirm(amount, onConfirm)
    local amtEl = withdrawOverlay:FindById("wdAmount")
    if amtEl then amtEl:SetText(FormatNum(amount) .. " 精粹") end
    withdrawCb = onConfirm
    withdrawOverlay:SetVisible(true)
end

local function BuildWithdrawConfirmOverlay()
    local overlay = ctx.UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = 100 .. "%",
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems     = "center",
        onClick = function() HideWithdrawConfirm() end,
        children = {
            ctx.UI.Panel {
                width  = "80%",
                paddingTop = 22, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                backgroundColor = { 32, 26, 50, 252 },
                borderRadius = 14,
                borderWidth  = 1,
                borderColor  = { 120, 80, 80, 180 },
                gap = 14,
                alignItems = "center",
                onClick = function() end,
                children = {
                    ctx.UI.Label {
                        text = "确认取出本金",
                        fontSize  = 16,
                        fontColor = { 255, 210, 200, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 110, 70, 70, 120 },
                    },
                    ctx.UI.Label {
                        id = "wdAmount",
                        text = "",
                        fontSize  = 22,
                        fontColor = { 120, 220, 120, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Label {
                        text      = "取出本金后，利息需单独领取",
                        fontSize  = 11,
                        fontColor = { 200, 170, 130, 220 },
                    },
                    ctx.UI.Label {
                        text      = "今日取出后，不可再次存入",
                        fontSize  = 10,
                        fontColor = { 160, 130, 130, 190 },
                    },
                    Row({
                        ctx.UI.Panel {
                            flex = 1,
                            paddingTop = 10, paddingBottom = 10,
                            alignItems = "center",
                            backgroundColor = { 45, 40, 62, 220 },
                            borderRadius = 8,
                            borderWidth  = 1,
                            borderColor  = { 75, 68, 98, 160 },
                            onClick = function() HideWithdrawConfirm() end,
                            children = {
                                ctx.UI.Label {
                                    text      = "取消",
                                    fontSize  = 13,
                                    fontColor = { 170, 160, 190, 230 },
                                },
                            },
                        },
                        ctx.UI.Panel {
                            flex = 1,
                            paddingTop = 10, paddingBottom = 10,
                            alignItems = "center",
                            backgroundColor = { 60, 130, 65, 220 },
                            borderRadius = 8,
                            borderWidth  = 1,
                            borderColor  = { 90, 200, 95, 200 },
                            onClick = function()
                                if withdrawCb then withdrawCb() end
                                HideWithdrawConfirm()
                            end,
                            children = {
                                ctx.UI.Label {
                                    text      = "确认取出",
                                    fontSize  = 13,
                                    fontColor = { 210, 255, 215, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                    }, { gap = 10, width = "100%" }),
                },
            },
        },
    }
    overlay:SetVisible(false)
    withdrawOverlay = overlay
    return overlay
end

-- ============================================================================
-- 分段利率行
-- ============================================================================

local TIER_COLORS = {
    { 100, 200, 255 },  -- 段位1 蓝
    { 130, 220, 130 },  -- 段位2 绿
    { 255, 205,  70 },  -- 段位3 金
}

local function BuildTierRow(tierIdx, tierStatus)
    local ts    = tierStatus[tierIdx]
    local color = TIER_COLORS[tierIdx]
    local ratePct = math.floor(ts.rate * 100)
    local daily = math.floor(ts.used * ts.rate)

    local fillPct = ts.cap > 0 and ts.used / ts.cap or 0
    local fillW   = math.floor(fillPct * 100)

    return ctx.UI.Panel {
        width = "100%",
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 14, paddingRight = 14,
        flexShrink = 0,
        gap = 5,
        children = {
            -- 标签行
            Row({
                ctx.UI.Label {
                    text      = "段位" .. tierIdx .. "  " .. ratePct .. "%/天",
                    fontSize  = 11,
                    fontColor = ts.used > 0 and { color[1], color[2], color[3], 230 } or { 90, 85, 110, 180 },
                    fontWeight = ts.used > 0 and "bold" or "normal",
                    flex = 1,
                },
                ctx.UI.Label {
                    text      = FormatNum(ts.used) .. "/" .. FormatNum(ts.cap),
                    fontSize  = 10,
                    fontColor = { 130, 125, 155, 200 },
                },
                ctx.UI.Panel { width = 6 },
                ctx.UI.Label {
                    text      = daily > 0 and ("+" .. daily .. "/天") or "--",
                    fontSize  = 11,
                    fontColor = daily > 0 and { color[1], color[2], color[3], 220 } or { 80, 78, 100, 160 },
                    fontWeight = daily > 0 and "bold" or "normal",
                },
            }),
            -- 进度条
            ctx.UI.Panel {
                width = "100%", height = 5,
                backgroundColor = { 30, 24, 50, 200 },
                borderRadius = 3,
                overflow = "hidden",
                children = {
                    ctx.UI.Panel {
                        width  = fillW .. "%",
                        height = "100%",
                        backgroundColor = { color[1], color[2], color[3], 200 },
                        borderRadius = 3,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 存入金额按钮
-- ============================================================================

local PRESET_AMOUNTS = { 500, 1000, 2000 }

local function BuildDepositButton(amount, maxDeposit, balance, totalDeposit)
    local canAfford = balance >= amount
    local canFit    = amount <= maxDeposit
    local active    = canAfford and canFit and maxDeposit > 0

    -- 预览：存入后新增的日利息
    local dailyAfter  = 0
    local dailyBefore = 0
    if active then
        local todayAmt = VaultData.GetTodayDeposited()
        -- 计息基准不含今日存入，所以预览按"原计息基准 + amount"
        local base = totalDeposit - todayAmt
        dailyBefore = math.floor(base * 0)  -- not needed, just diff
        -- TieredInterest is internal, recalculate manually
        local newBase = base + amount
        local function calcInterest(n)
            local interest = 0
            local rem = n
            for _, tier in ipairs(VaultData.TIERS) do
                local p = math.min(rem, tier.cap)
                interest = interest + p * tier.rate
                rem = rem - p
                if rem <= 0 then break end
            end
            return math.floor(interest)
        end
        dailyAfter  = calcInterest(newBase)
        dailyBefore = calcInterest(base)
    end
    local dailyDiff = dailyAfter - dailyBefore

    local borderC = active and { 80, 170, 220, 180 } or { 50, 45, 65, 100 }
    local bgC     = active and { 22, 50, 75, 200 }   or { 22, 20, 36, 140 }

    return ctx.UI.Panel {
        flex = 1,
        paddingTop = 12, paddingBottom = 12,
        alignItems = "center",
        gap = 4,
        backgroundColor = bgC,
        borderRadius = 10,
        borderWidth  = 1,
        borderColor  = borderC,
        pointerEvents = active and "auto" or "none",
        onClick = function()
            ShowDepositConfirm(amount, dailyDiff, function()
                local ok, msg = VaultData.Deposit(amount)
                if ok then
                    Toast.Show(msg, { 120, 210, 100 })
                else
                    Toast.Show(msg, { 255, 110, 80 })
                end
                ctx.RefreshContent()
            end)
        end,
        children = {
            ctx.UI.Label {
                text      = FormatNum(amount),
                fontSize  = 18,
                fontColor = active and { 180, 225, 255, 255 } or { 90, 85, 110, 180 },
                fontWeight = "bold",
            },
            ctx.UI.Label {
                text      = "精粹",
                fontSize  = 9,
                fontColor = { 110, 108, 130, 180 },
            },
            ctx.UI.Label {
                text = active and (dailyDiff > 0 and ("+" .. dailyDiff .. "/天") or "存入")
                              or (not canFit and (maxDeposit > 0 and "超出限额" or "已达上限")
                                             or "余额不足"),
                fontSize  = 10,
                fontColor = active and { 130, 210, 130, 220 }
                                   or { 80, 78, 100, 160 },
            },
        },
    }
end

-- ============================================================================
-- 主内容构建
-- ============================================================================

function Mod.BuildContent()
    confirmOverlay = nil
    confirmCb      = nil
    withdrawOverlay = nil
    withdrawCb      = nil

    VaultData.Load()
    VaultData.Settle()

    local totalDeposit  = VaultData.GetTotalDeposit()
    local dailyInterest = VaultData.GetDailyInterest()
    local pending       = VaultData.GetPendingInterest()
    local maxDeposit    = VaultData.GetMaxDeposit()
    local canDeposit    = VaultData.CanDeposit()
    local canCollect     = VaultData.CanCollect()
    local depositedToday = VaultData.DepositedToday()
    local canWithdraw    = totalDeposit > 0 and not depositedToday
    local withdrawnToday = VaultData.WithdrawnToday()
    local balance       = Currency.Get("shadow_essence")
    local tierStatus    = VaultData.GetTierStatus()
    local todayDeposited = VaultData.GetTodayDeposited()

    -- ── 顶部概览 ─────────────────────────────────────────────────────────
    local headerCard = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 16, paddingRight = 16,
        paddingTop  = 14, paddingBottom = 12,
        backgroundColor = { 35, 28, 55, 245 },
        borderBottomWidth = 1,
        borderColor = { 60, 50, 80, 100 },
        flexShrink = 0,
        gap = 10,
        children = {
            -- 标题 + 总量
            Row({
                ctx.UI.Label {
                    text = "深渊金库",
                    fontSize = 16,
                    fontColor = S.textPrimary,
                    fontWeight = "bold",
                    flex = 1,
                },
                ctx.UI.Label {
                    text = FormatNum(totalDeposit) .. " / " .. FormatNum(VaultData.VAULT_CAP),
                    fontSize = 12,
                    fontColor = S.goldAccent,
                    fontWeight = "bold",
                },
            }),
            -- 总量进度条
            ProgressBar(totalDeposit, VaultData.VAULT_CAP, { 100, 175, 255, 220 }),
            -- 统计行
            Row({
                ctx.UI.Panel {
                    flex = 1, alignItems = "center", gap = 2,
                    children = {
                        ctx.UI.Label {
                            text = dailyInterest > 0 and ("+" .. dailyInterest) or "--",
                            fontSize = 17,
                            fontColor = { 100, 235, 100, 255 },
                            fontWeight = "bold",
                        },
                        ctx.UI.Label { text = "当前日利息", fontSize = 9, fontColor = S.textMuted },
                    },
                },
                ctx.UI.Panel { width = 1, height = 28, backgroundColor = { 70, 60, 90, 120 } },
                ctx.UI.Panel {
                    flex = 1, alignItems = "center", gap = 2,
                    children = {
                        ctx.UI.Label {
                            text = pending > 0 and ("+" .. pending) or "0",
                            fontSize = 17,
                            fontColor = pending > 0 and { 255, 215, 80, 255 } or S.textSecondary,
                            fontWeight = "bold",
                        },
                        ctx.UI.Label { text = "待领利息", fontSize = 9, fontColor = S.textMuted },
                    },
                },
            }),
        },
    }

    -- ── 分段展示 ─────────────────────────────────────────────────────────
    local tierSection = ctx.UI.Panel {
        width = "100%",
        paddingTop = 8, paddingBottom = 4,
        flexShrink = 0,
        backgroundColor = { 28, 22, 44, 200 },
        borderBottomWidth = 1,
        borderColor = { 55, 48, 75, 100 },
        children = {
            BuildTierRow(1, tierStatus),
            BuildTierRow(2, tierStatus),
            BuildTierRow(3, tierStatus),
        },
    }

    -- ── 存入区 ───────────────────────────────────────────────────────────
    local depositStatusText, depositStatusColor
    if withdrawnToday then
        depositStatusText  = "今日已取出，明日方可重新存入"
        depositStatusColor = { 200, 160, 80, 210 }
    elseif depositedToday then
        depositStatusText  = "今日已存入 " .. FormatNum(todayDeposited) .. " 精粹，明日方可再存"
        depositStatusColor = { 100, 210, 110, 220 }
    elseif not canDeposit then
        if totalDeposit >= VaultData.VAULT_CAP then
            depositStatusText  = "金库已满，请取出后继续存入"
            depositStatusColor = { 220, 170, 70, 210 }
        else
            depositStatusText  = "今日可存 " .. FormatNum(VaultData.GetMaxDeposit()) .. " 精粹"
            depositStatusColor = { 100, 210, 110, 220 }
        end
    else
        local vaultRemain = VaultData.VAULT_CAP - totalDeposit
        local realRemain  = math.min(VaultData.DAILY_LIMIT, vaultRemain)
        depositStatusText  = "余额 " .. FormatNum(balance) .. "  ·  今日可存 " .. FormatNum(realRemain) .. " 精粹"
        depositStatusColor = S.textSecondary
    end

    local depositSection = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 14, paddingRight = 14,
        paddingTop  = 12, paddingBottom = 10,
        gap = 10,
        flexShrink = 0,
        children = {
            ctx.UI.Label {
                text      = "选择存入金额",
                fontSize  = 12,
                fontColor = S.textSecondary,
                fontWeight = "bold",
            },
            Row({
                BuildDepositButton(PRESET_AMOUNTS[1], maxDeposit, balance, totalDeposit),
                BuildDepositButton(PRESET_AMOUNTS[2], maxDeposit, balance, totalDeposit),
                BuildDepositButton(PRESET_AMOUNTS[3], maxDeposit, balance, totalDeposit),
            }, { gap = 8, width = "100%" }),
            ctx.UI.Label {
                text      = depositStatusText,
                fontSize  = 10,
                fontColor = depositStatusColor,
            },
        },
    }

    -- ── 底部按钮栏 ───────────────────────────────────────────────────────
    local bottomBar = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 14, paddingRight = 14,
        paddingTop  = 10, paddingBottom = 10,
        flexShrink = 0,
        borderTopWidth = 1,
        borderColor    = { 60, 50, 80, 80 },
        backgroundColor = { 22, 18, 36, 245 },
        children = {
            Row({
                -- 领取利息
                ctx.UI.Panel {
                    flex = 1,
                    paddingTop = 11, paddingBottom = 11,
                    alignItems = "center",
                    borderRadius = 8,
                    backgroundColor = canCollect and { 60, 50, 130, 220 } or { 30, 30, 48, 150 },
                    borderWidth  = 1,
                    borderColor  = canCollect and { 110, 90, 210, 200 } or { 50, 45, 65, 100 },
                    pointerEvents = canCollect and "auto" or "none",
                    gap = 2,
                    onClick = function()
                        local amt, msg = VaultData.CollectInterest()
                        if amt > 0 then
                            RC.ShowCurrency(ctx.UI, ctx.pageRoot,
                                "shadow_essence", amt, "利息收益",
                                function() ctx.RefreshContent() end)
                        else
                            Toast.Show(msg, { 160, 155, 175 })
                            ctx.RefreshContent()
                        end
                    end,
                    children = {
                        ctx.UI.Label {
                            text      = "领取利息",
                            fontSize  = 13,
                            fontColor = canCollect and { 180, 165, 255, 255 } or S.textMuted,
                            fontWeight = canCollect and "bold" or "normal",
                        },
                        ctx.UI.Label {
                            text      = canCollect and ("+" .. pending) or "暂无",
                            fontSize  = 9,
                            fontColor = canCollect and { 200, 190, 255, 200 } or S.textMuted,
                        },
                    },
                },
                -- 全部取出（仅取本金）
                ctx.UI.Panel {
                    flex = 1,
                    paddingTop = 11, paddingBottom = 11,
                    alignItems = "center",
                    borderRadius = 8,
                    backgroundColor = canWithdraw and { 50, 120, 60, 220 } or { 30, 30, 48, 150 },
                    borderWidth  = 1,
                    borderColor  = canWithdraw and { 85, 195, 95, 200 } or { 50, 45, 65, 100 },
                    pointerEvents = canWithdraw and "auto" or "none",
                    gap = 2,
                    onClick = function()
                        ShowWithdrawConfirm(totalDeposit, function()
                            local amt, msg = VaultData.WithdrawAll()
                            if amt > 0 then
                                Toast.Show(msg, { 120, 220, 100 })
                            else
                                Toast.Show(msg, { 160, 155, 175 })
                            end
                            ctx.RefreshContent()
                        end)
                    end,
                    children = {
                        ctx.UI.Label {
                            text      = "全部取出",
                            fontSize  = 13,
                            fontColor = canWithdraw and { 220, 255, 220, 255 } or S.textMuted,
                            fontWeight = canWithdraw and "bold" or "normal",
                        },
                        ctx.UI.Label {
                            text      = canWithdraw and FormatNum(totalDeposit) or "--",
                            fontSize  = 9,
                            fontColor = canWithdraw and { 180, 240, 180, 200 } or S.textMuted,
                        },
                    },
                },
            }, { gap = 10, width = "100%" }),
        },
    }

    -- ── 规则说明 ─────────────────────────────────────────────────────────
    local function RuleLine(text)
        return Row({
            ctx.UI.Label {
                text      = "·",
                fontSize  = 11,
                fontColor = { 110, 100, 140, 180 },
                marginTop = 1,
            },
            ctx.UI.Label {
                text      = text,
                fontSize  = 11,
                fontColor = { 150, 142, 172, 210 },
                flexShrink = 1,
            },
        }, { gap = 6, alignItems = "flex-start" })
    end

    local rulesPanel = ctx.UI.Panel {
        width = "100%",
        paddingLeft = 14, paddingRight = 14,
        paddingTop  = 6,  paddingBottom = 16,
        gap = 6,
        flexShrink = 0,
        children = {
            ctx.UI.Label {
                text      = "规则说明",
                fontSize  = 11,
                fontColor = { 100, 92, 128, 200 },
                fontWeight = "bold",
                marginBottom = 2,
            },
            RuleLine("总容量 6000 精粹，每日最多存入 2000 精粹，每天只能存入一次"),
            RuleLine("分段利率：0~2000 存量 10%/天，2001~4000 存量 5%/天，4001~6000 存量 1%/天"),
            RuleLine("今日存入，明日起开始计息；利息最多累积 2 天"),
            RuleLine("领取利息：仅领息，本金留在金库继续计息；存入当日不可领息，当日只可领一次"),
            RuleLine("全部取出：取回全部本金，利息须单独领取；存入当日不可取出"),
        },
    }

    -- ── 确认弹窗 ─────────────────────────────────────────────────────────
    local overlay        = BuildConfirmOverlay()
    local withdrawOvl    = BuildWithdrawConfirmOverlay()

    return { headerCard, tierSection, depositSection, bottomBar, rulesPanel, overlay, withdrawOvl }
end

return Mod
end
