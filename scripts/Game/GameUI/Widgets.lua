-- Game/GameUI/Widgets.lua
-- UI 组件：StageBar、HUD、货币展示、资源商店

return function(GameUI, ctx)

local Config              = require("Game.Config")
local State               = require("Game.State")
local Currency            = require("Game.Currency")
local Toast               = require("Game.Toast")
local WeeklyActivityData  = require("Game.WeeklyActivityData")
local WelfareData         = require("Game.WelfareData")
local VaultData           = require("Game.VaultData")
local CostumeSignInData   = require("Game.CostumeSignInData")
local WeeklyActivityUI    = require("Game.WeeklyActivityUI")
local DivineBlessDB       = require("Game.DivineBlessData")

local FormatNum = ctx.FormatNum

function GameUI.CreateStageBar()
    local typeTag = ""
    if State.waveType == "boss" then typeTag = " BOSS"
    elseif State.waveType == "elite" then typeTag = " 精英" end
    local waveText = State.currentStage .. "-" .. State.currentWave .. typeTag

    local hasBlessing = (DivineBlessDB.GetActiveBlessing() ~= nil)
    local needChoose = not DivineBlessDB.HasChosen()

    return ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        paddingTop = 8, paddingBottom = 4,
        flexShrink = 0,
        children = {
            -- 左侧：神裔祝福入口（绝对定位，不影响中央关卡标签居中）
            ctx.UI.Panel {
                position = "absolute",
                left = 8,
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                paddingLeft = 7, paddingRight = 9,
                paddingTop = 5, paddingBottom = 5,
                backgroundColor = hasBlessing and { 48, 22, 85, 230 } or { 20, 16, 32, 190 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = hasBlessing and { 170, 90, 255, 200 } or { 70, 55, 100, 100 },
                onClick = function()
                    WeeklyActivityUI.SetSubTab("weekend_bonus")
                    GameUI.ShowWeeklyActivityOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = 15, height = 15,
                        backgroundImage = "image/icon_weekend_bonus.png",
                        backgroundFit   = "contain",
                        flexShrink = 0,
                    },
                    ctx.UI.Label {
                        text = "神裔降临",
                        fontSize = 11,
                        fontColor = hasBlessing and { 215, 155, 255, 255 } or { 125, 115, 148, 200 },
                    },
                    -- 生效中绿色圆点 / 未选红色圆点
                    hasBlessing and ctx.UI.Panel {
                        width = 5, height = 5,
                        borderRadius = 3,
                        backgroundColor = { 100, 235, 140, 255 },
                        flexShrink = 0,
                    } or needChoose and ctx.UI.Panel {
                        width = 5, height = 5,
                        borderRadius = 3,
                        backgroundColor = { 255, 80, 80, 255 },
                        flexShrink = 0,
                    } or nil,
                },
            },
            -- 中央：关卡标签（保持原样居中）
            ctx.UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 6, paddingBottom = 6,
                backgroundColor = { 20, 16, 32, 200 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 70, 55, 100, 120 },
                children = {
                    ctx.UI.Label {
                        id = "stageBarLabel",
                        text = waveText,
                        fontSize = 13,
                        fontColor = Config.COLORS.textSecondary,
                    },
                },
            },
        },
    }
end

--- 顶部 HUD（战斗页专用，绝对定位）
function GameUI.CreateHUD()
    local safeTop = (ctx.UI.GetSafeAreaInsets().top or 0) + 8

    local hasBlessing = (DivineBlessDB.GetActiveBlessing() ~= nil)
    local needChoose  = not DivineBlessDB.HasChosen()

    return ctx.UI.Panel {
        id = "hud",
        position = "absolute",
        top = safeTop, left = 8, right = 8,
        height = 40,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 20, 16, 32, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        pointerEvents = "box-none",   -- 背景不拦截事件，子元素可点击
        children = {
            -- 中央：关卡进度文字
            ctx.UI.Label {
                id = "waveLabel",
                text = "波次: 0",
                fontSize = 13,
                fontColor = Config.COLORS.textSecondary,
                pointerEvents = "none",
            },
            -- 左侧最左：设置齿轮按钮
            ctx.UI.Panel {
                position = "absolute",
                left = 4,
                width = 30, height = 30,
                borderRadius = 8,
                backgroundColor = { 30, 24, 50, 200 },
                borderWidth = 1,
                borderColor = { 100, 80, 140, 150 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function()
                    GameUI.ShowSettingsPopup()
                end,
                children = {
                    ctx.UI.Label {
                        text = "\u{2699}",
                        fontSize = 18,
                        fontColor = { 200, 190, 220, 255 },
                        pointerEvents = "none",
                    },
                },
            },
            -- 左侧次位：神裔祝福入口
            ctx.UI.Panel {
                position = "absolute",
                left = 40,
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                paddingLeft = 7, paddingRight = 9,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = hasBlessing and { 48, 22, 85, 230 } or { 28, 22, 44, 200 },
                borderRadius = 10,
                borderWidth = 1,
                borderColor = hasBlessing and { 170, 90, 255, 180 } or { 70, 55, 100, 100 },
                pointerEvents = "auto",
                onClick = function()
                    WeeklyActivityUI.SetSubTab("weekend_bonus")
                    GameUI.ShowWeeklyActivityOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = 14, height = 14,
                        backgroundImage = "image/icon_weekend_bonus.png",
                        backgroundFit   = "contain",
                        flexShrink = 0,
                    },
                    ctx.UI.Label {
                        text = "神裔降临",
                        fontSize = 10,
                        fontColor = hasBlessing and { 215, 155, 255, 255 } or { 120, 110, 145, 200 },
                        pointerEvents = "none",
                    },
                    hasBlessing and ctx.UI.Panel {
                        width = 5, height = 5,
                        borderRadius = 3,
                        backgroundColor = { 100, 235, 140, 255 },
                        flexShrink = 0,
                    } or needChoose and ctx.UI.Panel {
                        width = 5, height = 5,
                        borderRadius = 3,
                        backgroundColor = { 255, 80, 80, 255 },
                        flexShrink = 0,
                    } or nil,
                },
            },
        },
    }
end

--- 紧凑货币药丸（用 Panel 代替 Button 做"+"，避免 Button 默认 minWidth=64 撑大）
--- @param uiRef any UI 模块引用
--- @param currencyId string
--- @param labelId string
--- @param labelColor table
function GameUI.CreateCurrencyChip(uiRef, currencyId, labelId, labelColor)
    return uiRef.Panel {
        flexDirection = "row",
        alignItems = "center",
        height = 24,
        paddingLeft = 4, paddingRight = 6,
        backgroundColor = { 15, 12, 28, 210 },
        borderRadius = 12,
        borderWidth = 1,
        borderColor = { labelColor[1], labelColor[2], labelColor[3], 60 },
        gap = 4,
        children = {
            Currency.IconWidget(uiRef, currencyId, 16),
            uiRef.Label {
                id = labelId,
                text = FormatNum(Currency.Get(currencyId)),
                fontSize = 12,
                fontColor = { labelColor[1], labelColor[2], labelColor[3], 255 },
            },
        },
    }
end

--- 货币模块行：图标 + 数字 + "+" 按钮（公开组件，供其他页面复用）
function GameUI.CurrencyPill(currencyId, labelId, labelColor)
    return ctx.UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        height = 24,
        paddingLeft = 4, paddingRight = 6,
        backgroundColor = { 15, 12, 28, 210 },
        borderRadius = 12,
        borderWidth = 1,
        borderColor = { labelColor[1], labelColor[2], labelColor[3], 60 },
        gap = 4,
        children = {
            Currency.IconWidget(ctx.UI, currencyId, 16),
            ctx.UI.Label {
                id = labelId,
                text = "0",
                fontSize = 12,
                fontColor = { labelColor[1], labelColor[2], labelColor[3], 255 },
                minWidth = 36,
            },
        },
    }
end

--- 右上货币显示面板
function GameUI.CreateCurrencyDisplay()
    return ctx.UI.Panel {
        id = "currencyDisplay",
        position = "absolute",
        right = 8, top = "30%",
        flexDirection = "column",
        alignItems = "flex-end",
        gap = 4,
        children = {
            -- 退出副本按钮（仅副本模式显示）
            ctx.UI.Button {
                id = "exitDungeonBtn",
                text = "退出",
                fontSize = 11,
                variant = "outline",
                height = 26,
                paddingLeft = 10, paddingRight = 10,
                visible = false,
                onClick = function(self)
                    GameUI.ExitDungeonBattle()
                end,
            },
            GameUI.CurrencyPill("nether_crystal", "hudCrystalLabel", { 160, 100, 230 }),
            GameUI.CurrencyPill("shadow_essence", "hudEssenceLabel", { 180, 140, 255 }),
            -- 限时活动入口按钮（与左侧边栏按钮样式一致）
            ctx.UI.Panel {
                id = "weeklyActivityBtn",
                width = 56, height = 56,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 100, 160, 255, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                marginTop = 4,
                visible = WeeklyActivityData.IsActive(),
                onClick = function(self)
                    GameUI.ShowWeeklyActivityOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = 56, height = 56,
                        backgroundColor = { 20, 30, 60, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 32, height = 32,
                                backgroundImage = "image/限时活动图标.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = {
                            ctx.UI.Label {
                                text = "限时", fontSize = 11,
                                fontColor = { 100, 200, 255, 255 },
                            },
                        },
                    },
                    -- 红点（宝箱达标 或 限时福利有可领取）
                    ctx.UI.Panel {
                        id = "weeklyActivityRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = WeeklyActivityData.HasClaimable() or WelfareData.HasClaimable(),
                    },
                },
            },
            -- 深渊金库入口按钮
            ctx.UI.Panel {
                id = "vaultEntryBtn",
                width = 56, height = 56,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 180, 120, 255, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                marginTop = 4,
                onClick = function(self)
                    GameUI.ShowVaultOverlay()
                end,
                children = {
                    ctx.UI.Panel {
                        width = 56, height = 56,
                        backgroundColor = { 30, 15, 55, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 32, height = 32,
                                backgroundImage = "image/icon_vault.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = {
                            ctx.UI.Label {
                                text = "金库", fontSize = 11,
                                fontColor = { 200, 160, 255, 255 },
                            },
                        },
                    },
                    -- 红点（有待领利息时显示）
                    ctx.UI.Panel {
                        id = "vaultRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = false,
                    },
                },
            },
            -- 时装签到入口按钮（仅活动期间显示）
            ctx.UI.Panel {
                id = "costumeSignInBtn",
                width = 56, height = 56,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 160, 100, 255, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                marginTop = 4,
                visible = CostumeSignInData.IsEventActive(),
                onClick = function(self)
                    GameUI.ShowCostumeSignInOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = 56, height = 56,
                        backgroundColor = { 30, 18, 50, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 36, height = 36,
                                backgroundImage = "image/icon_costume.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = {
                            ctx.UI.Label {
                                text = "时装", fontSize = 11,
                                fontColor = { 200, 160, 255, 255 },
                            },
                        },
                    },
                    -- 红点（有可领取奖励时显示）
                    ctx.UI.Panel {
                        id = "costumeSignInRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = CostumeSignInData.HasClaimable(),
                    },
                },
            },
            -- 小游戏入口按钮（已隐藏）
            -- ctx.UI.Panel { id = "miniGameBtn", ... },
        },
    }
end

--- 资源商店弹窗
function GameUI.ShowResourceShop(focusCurrency)
    -- 如果已显示则关闭
    local existing = ctx.uiRoot and ctx.uiRoot:FindById("resourceShopOverlay")
    if existing then
        existing:Remove()
        return
    end
    if not ctx.uiRoot then return end

    local shopItems = {
        { id = "nether_crystal", name = "冥晶",   color = { 160, 100, 230 }, desc = "升级英雄等级",
          sources = { "击杀怪物掉落", "挂机离线收益", "开启朽木宝箱", "活动奖励" } },
        { id = "shadow_essence", name = "暗影精粹", color = { 180, 140, 255 }, desc = "兑换高级道具",
          sources = { "开启钻石宝箱", "积分里程碑奖励", "活动奖励" } },
        { id = "devour_stone",   name = "噬魂石",  color = { 60, 160, 80 },   desc = "英雄进阶",
          sources = { "击杀精英/BOSS", "挂机离线收益", "开启青铜/黄金/铂金宝箱" } },
        { id = "forge_iron",     name = "锻魂铁",  color = { 130, 160, 200 }, desc = "打造装备",
          sources = { "击杀BOSS掉落", "挂机离线收益" } },
        { id = "void_pact",      name = "虚空契约", color = { 200, 40, 40 },   desc = "招募英雄",
          sources = { "通关结算奖励", "积分里程碑奖励" } },
    }

    local itemChildren = {}
    for _, item in ipairs(shopItems) do
        local amount = Currency.Get(item.id)
        -- 来源文字
        local srcTexts = {}
        for i, s in ipairs(item.sources) do
            srcTexts[#srcTexts + 1] = ctx.UI.Label {
                text = "· " .. s,
                fontSize = 10,
                fontColor = { 180, 170, 200, 180 },
            }
        end

        itemChildren[#itemChildren + 1] = ctx.UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 8, paddingBottom = 8,
            backgroundColor = (focusCurrency == item.id)
                and { item.color[1], item.color[2], item.color[3], 30 }
                or { 30, 24, 50, 180 },
            borderRadius = 8,
            borderWidth = (focusCurrency == item.id) and 1 or 0,
            borderColor = { item.color[1], item.color[2], item.color[3], 100 },
            children = {
                -- 图标
                Currency.IconWidget(ctx.UI, item.id, 28),
                -- 信息列
                ctx.UI.Panel {
                    flexDirection = "column",
                    flexGrow = 1,
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        -- 名称 + 数量
                        ctx.UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                ctx.UI.Label {
                                    text = item.name,
                                    fontSize = 13,
                                    fontColor = { item.color[1], item.color[2], item.color[3], 255 },
                                    fontWeight = "bold",
                                },
                                ctx.UI.Label {
                                    text = FormatNum(amount),
                                    fontSize = 12,
                                    fontColor = { 220, 210, 240, 255 },
                                },
                            },
                        },
                        -- 用途
                        ctx.UI.Label {
                            text = item.desc,
                            fontSize = 10,
                            fontColor = { 140, 130, 170, 200 },
                        },
                        -- 获取途径
                        ctx.UI.Panel {
                            flexDirection = "column",
                            gap = 1,
                            marginTop = 2,
                            children = srcTexts,
                        },
                    },
                },
            },
        }
    end

    local overlay = ctx.UI.Panel {
        id = "resourceShopOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        onClick = function(self)
            self:Remove()
        end,
        children = {
            ctx.UI.Panel {
                width = 280,
                maxHeight = "80%",
                backgroundColor = { 25, 20, 45, 245 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 70, 180, 120 },
                paddingTop = 12, paddingBottom = 12,
                onClick = function() end,  -- 阻止冒泡关闭
                children = {
                    -- 标题
                    ctx.UI.Label {
                        text = "资源总览",
                        fontSize = 16,
                        fontColor = { 220, 200, 255, 255 },
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 10,
                        alignSelf = "center",
                    },
                    -- 资源列表
                    ctx.UI.Panel {
                        flexDirection = "column",
                        gap = 6,
                        paddingLeft = 8, paddingRight = 8,
                        children = itemChildren,
                    },
                    -- 关闭提示
                    ctx.UI.Label {
                        text = "点击空白处关闭",
                        fontSize = 10,
                        fontColor = { 120, 110, 150, 150 },
                        textAlign = "center",
                        marginTop = 10,
                        alignSelf = "center",
                    },
                },
            },
        },
    }

    ctx.uiRoot:AddChild(overlay)
end

--- 品质颜色（挂到 ctx 供其他子模块共享）
-- 使用半透明版本 (alpha=200) 用于卡片背景
local RARITY_COLORS = {}
for k, c in pairs(Config.RARITY_COLORS) do
    RARITY_COLORS[k] = { c[1], c[2], c[3], 200 }
end
ctx.RARITY_COLORS = RARITY_COLORS

--- 格式化数字

-- ============================================================================
-- 伤害战报面板
-- ============================================================================

local DamageStats = require("Game.DamageStats")

-- 伤害战报当前显示模式: false=全局, true=Boss
GameUI._dmgBossOnly = false

--- 打开/关闭伤害战报浮层（每次打开重新读取最新数据）
function GameUI.ShowDamageStatsPanel(show)
    if not ctx.uiRoot then return end

    -- 关闭：移除已有浮层
    local existing = ctx.uiRoot:FindById("damageStatsOverlay")
    if existing then
        existing:Remove()
        if not show then return end
    end
    if not show then return end

    local bossOnly = GameUI._dmgBossOnly

    -- 读取统计数据
    local list, totalDmg = DamageStats.GetSorted(bossOnly)

    -- 构建每行英雄条目
    local rows = {}
    for rank, s in ipairs(list) do
        if rank > 12 then break end  -- 最多显示 12 条

        local pct = (totalDmg > 0) and (s.totalDmg / totalDmg) or 0
        local pctStr = string.format("%.1f%%", pct * 100)
        local dmgStr = FormatNum(s.totalDmg)
        local c = s.color or { 180, 140, 255 }

        -- 星级文字
        local starStr = string.rep("★", math.min(s.star or 0, 5))

        rows[#rows + 1] = ctx.UI.Panel {
            flexDirection = "column",
            gap = 3,
            paddingTop = 6, paddingBottom = 6,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = rank == 1
                and { c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 80 }
                or { 15, 12, 28, 60 },
            borderRadius = 6,
            children = {
                -- 名称行
                ctx.UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "space-between",
                    children = {
                        ctx.UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                -- 排名角标
                                ctx.UI.Label {
                                    text = tostring(rank),
                                    fontSize = 10,
                                    fontColor = rank == 1 and { 255, 210, 60, 255 }
                                        or { 150, 140, 170, 200 },
                                    fontWeight = "bold",
                                    width = 14,
                                    textAlign = "center",
                                },
                                -- 英雄名 + 星级
                                ctx.UI.Label {
                                    text = (s.heroName or "未知"),
                                    fontSize = 13,
                                    fontColor = { c[1], c[2], c[3], 255 },
                                    fontWeight = "bold",
                                },
                                ctx.UI.Label {
                                    text = starStr,
                                    fontSize = 9,
                                    fontColor = { 255, 210, 60, 200 },
                                },
                            },
                        },
                        -- 右侧：伤害值 + 占比
                        ctx.UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                ctx.UI.Label {
                                    text = pctStr,
                                    fontSize = 11,
                                    fontColor = { 160, 145, 190, 200 },
                                },
                                ctx.UI.Label {
                                    text = dmgStr,
                                    fontSize = 14,
                                    fontColor = { 230, 215, 255, 255 },
                                    fontWeight = "bold",
                                    minWidth = 52,
                                    textAlign = "right",
                                },
                            },
                        },
                    },
                },
                -- 进度条
                ctx.UI.Panel {
                    height = 4,
                    backgroundColor = { 40, 35, 60, 200 },
                    borderRadius = 2,
                    overflow = "hidden",
                    children = {
                        ctx.UI.Panel {
                            width = string.format("%.1f%%", pct * 100),
                            height = 4,
                            backgroundColor = { c[1], c[2], c[3], 200 },
                            borderRadius = 2,
                        },
                    },
                },
                -- 暴击 + 击杀
                ctx.UI.Label {
                    text = string.format("暴击 %d 次  · 击杀 %d",
                        s.critCount, s.killCount),
                    fontSize = 10,
                    fontColor = { 140, 130, 165, 180 },
                },
            },
        }
    end

    -- 空数据提示
    if #rows == 0 then
        rows[1] = ctx.UI.Label {
            text = "本场暂无伤害数据\n开始战斗后自动记录",
            fontSize = 13,
            fontColor = { 160, 150, 190, 200 },
            textAlign = "center",
            marginTop = 20, marginBottom = 20,
        }
    end

    -- 总伤害摘要行
    local summaryLabel = bossOnly and "Boss伤害：" or "总伤害："
    local summaryText = totalDmg > 0
        and (summaryLabel .. FormatNum(totalDmg))
        or ""

    -- 刷新时直接还原到位，首次打开才触发滑入动画
    local initRight = GameUI._dmgIsRefresh and 0 or -300

    local overlay = ctx.UI.Panel {
        id = "damageStatsOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 0 },  -- 全透明遮罩
        pointerEvents = "auto",
        onClick = function(self) self:Remove() end,
        children = {
            ctx.UI.Panel {
                id = "dmgStatsCard",
                position = "absolute",
                top = 0, bottom = 0,
                right = initRight,
                width = 280,
                backgroundColor = { 18, 14, 35, 180 },
                borderWidth = 1,
                borderColor = { 80, 55, 130, 180 },
                onClick = function() end,  -- 阻止冒泡关闭
                children = {
                    -- 顶部：标题 + 总伤害 + 英雄列表（可滚动）
                    ctx.UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        overflow = "scroll",
                        paddingTop = 12,
                        paddingLeft = 12, paddingRight = 12,
                        gap = 8,
                        children = {
                            -- 标题行
                            ctx.UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                justifyContent = "space-between",
                                marginBottom = 2,
                                children = {
                                    ctx.UI.Label {
                                        text = "伤害战报",
                                        fontSize = 16,
                                        fontColor = { 220, 200, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                    ctx.UI.Panel {
                                        width = 26, height = 26,
                                        borderRadius = 13,
                                        backgroundColor = { 50, 38, 75, 220 },
                                        justifyContent = "center",
                                        alignItems = "center",
                                        pointerEvents = "auto",
                                        onClick = function()
                                            local ov = ctx.uiRoot and ctx.uiRoot:FindById("damageStatsOverlay")
                                            if ov then ov:Remove() end
                                        end,
                                        children = {
                                            ctx.UI.Label {
                                                text = "×",
                                                fontSize = 14,
                                                fontColor = { 200, 180, 230, 255 },
                                            },
                                        },
                                    },
                                },
                            },
                            -- 总伤害摘要
                            summaryText ~= "" and ctx.UI.Label {
                                text = summaryText,
                                fontSize = 11,
                                fontColor = { 160, 145, 200, 200 },
                                textAlign = "right",
                                alignSelf = "flex-end",
                            } or nil,
                            -- 英雄列表
                            ctx.UI.Panel {
                                flexDirection = "column",
                                gap = 4,
                                children = rows,
                            },
                        },
                    },
                    -- 底部固定：Boss / 全局 切换按钮
                    ctx.UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 8,
                        paddingTop = 8, paddingBottom = 10,
                        paddingLeft = 12, paddingRight = 12,
                        borderTopWidth = 1,
                        borderColor = { 60, 45, 100, 120 },
                        children = {
                            ctx.UI.Panel {
                                flexGrow = 1,
                                paddingTop = 6, paddingBottom = 6,
                                borderRadius = 4,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = (not bossOnly) and { 100, 70, 180, 220 } or { 40, 35, 60, 180 },
                                pointerEvents = "auto",
                                onClick = function()
                                    GameUI._dmgBossOnly = false
                                    GameUI._dmgIsRefresh = true
                                    GameUI.ShowDamageStatsPanel(true)
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "全局",
                                        fontSize = 12,
                                        fontColor = (not bossOnly) and { 255, 255, 255, 255 } or { 150, 140, 170, 200 },
                                        fontWeight = (not bossOnly) and "bold" or "normal",
                                    },
                                },
                            },
                            ctx.UI.Panel {
                                flexGrow = 1,
                                paddingTop = 6, paddingBottom = 6,
                                borderRadius = 4,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = bossOnly and { 180, 60, 60, 220 } or { 40, 35, 60, 180 },
                                pointerEvents = "auto",
                                onClick = function()
                                    GameUI._dmgBossOnly = true
                                    GameUI._dmgIsRefresh = true
                                    GameUI.ShowDamageStatsPanel(true)
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "Boss",
                                        fontSize = 12,
                                        fontColor = bossOnly and { 255, 255, 255, 255 } or { 150, 140, 170, 200 },
                                        fontWeight = bossOnly and "bold" or "normal",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    ctx.uiRoot:AddChild(overlay)

    -- 首次打开触发滑入动画
    if not GameUI._dmgIsRefresh then
        GameUI._dmgAnimating = true
        GameUI._dmgSlideOffset = 300
    end
end

end
