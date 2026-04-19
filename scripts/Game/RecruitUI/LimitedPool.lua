-- Game/RecruitUI/LimitedPool.lua
-- 限定池组件（货币栏、横幅、按钮区、详情弹窗、广告弹窗）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local RewardDisplay = require("Game.RewardDisplay")
local GachaResult = require("Game.RecruitUI.GachaResult")

local LimitedPool = {}

--- 限定池货币栏
---@param UI any
---@return any
function LimitedPool.CreateTokenBar(UI)
    local LBD = require("Game.LimitedBannerData")
    local tokens = LBD.GetTokens()
    local pityCount = LBD.GetPityCount()
    local pityMax = Config.LIMITED_BANNER.pity
    local remaining = LBD.GetRemainingDays()
    local safeTop = (UI.GetSafeAreaInsets().top or 0)

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = safeTop + 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 15, 20, 35, 200 },
        borderWidth = 1,
        borderColor = { 60, 100, 150, 120 },
        flexShrink = 0,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    Currency.IconWidget(UI, "frost_pact", 18),
                    UI.Label {
                        text = "霜誓契约: " .. tokens,
                        fontSize = 15,
                        fontColor = { 130, 210, 255, 255 },
                    },
                },
            },
            UI.Label {
                text = pityCount .. "/" .. pityMax .. "保底",
                fontSize = 12,
                fontColor = { 200, 220, 255, 200 },
            },
            UI.Label {
                text = remaining > 0 and ("剩余" .. remaining .. "天") or "已结束",
                fontSize = 12,
                fontColor = remaining > 0 and { 130, 210, 255, 180 } or { 255, 100, 100, 200 },
            },
        },
    }
end

--- 限定池横幅
---@param UI any
---@param showAdFrostFn function
---@param showDetailFn function
---@return any
function LimitedPool.CreateBanner(UI, showAdFrostFn, showDetailFn)
    local LBD = require("Game.LimitedBannerData")
    local banner = Config.LIMITED_BANNER

    -- 获取限定英雄信息
    local heroName = banner.heroId
    local heroColor = { 130, 210, 255 }
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == banner.heroId then
            heroName = td.name
            heroColor = td.color
            break
        end
    end

    local isActive = LBD.IsActive()

    -- 头像路径
    local avatarPath = "image/avatars/avatar_glacial.png"

    return UI.Panel {
        width = "100%",
        flex = 1,
        -- 冰霜主题渐变背景
        backgroundColor = { 10, 18, 35, 255 },
        justifyContent = "flex-start",
        alignItems = "center",
        overflow = "hidden",
        children = {
            -- 冰霜祭坛背景图
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "image/limited_banner_bg.png",
                backgroundFit = "cover",
                opacity = 0.7,
            },
            -- 左侧广告领霜誓契约入口
            UI.Panel {
                position = "absolute",
                left = 10, top = "40%",
                width = 52, height = 52,
                borderRadius = 12,
                backgroundColor = { 15, 30, 55, 220 },
                borderWidth = 2,
                borderColor = LBD.CanClaimAdFrost()
                    and { 100, 200, 255, 220 }
                    or { 50, 80, 110, 150 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                zIndex = 3,
                onClick = function(self)
                    showAdFrostFn()
                end,
                children = {
                    Currency.IconWidget(UI, "frost_pact", 28),
                    -- 底部"免费"小标签
                    UI.Panel {
                        position = "absolute",
                        bottom = -2, left = 0, right = 0,
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                paddingLeft = 3, paddingRight = 3,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = LBD.CanClaimAdFrost()
                                    and { 60, 180, 220, 255 }
                                    or { 40, 60, 80, 200 },
                                borderRadius = 4,
                                children = {
                                    UI.Label {
                                        text = "免费",
                                        fontSize = 9,
                                        fontColor = LBD.CanClaimAdFrost()
                                            and { 10, 20, 30, 255 }
                                            or { 100, 120, 140, 180 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 可领取红点
                    LBD.CanClaimAdFrost() and UI.Panel {
                        position = "absolute",
                        top = -2, right = -2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                    } or nil,
                },
            },
            -- 标题区（顶部）
            UI.Label {
                text = "限定祭坛",
                fontSize = 28,
                fontColor = { 130, 210, 255, 255 },
                fontWeight = "bold",
                marginTop = 16,
                marginBottom = 4,
                zIndex = 1,
            },
            -- 限定英雄名标签
            UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 30, 60, 100, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 130, 210, 255, 150 },
                zIndex = 1,
                children = {
                    UI.Label {
                        text = "UP " .. heroName,
                        fontSize = 18,
                        fontColor = heroColor,
                        fontWeight = "bold",
                    },
                },
            },
            -- 角色立绘区域（居中撑满剩余空间）
            UI.Panel {
                flex = 1,
                width = "100%",
                justifyContent = "center",
                alignItems = "center",
                zIndex = 1,
                children = {
                    -- 角色图片
                    UI.Panel {
                        width = 120, height = 150,
                        backgroundImage = avatarPath,
                        backgroundFit = "contain",
                    },
                },
            },
            -- 底部：进度条 + 详情按钮 一行排列
            UI.Panel {
                marginBottom = 12,
                width = "90%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 8,
                zIndex = 1,
                children = {
                    -- 保底进度条
                    UI.Panel {
                        flex = 1,
                        height = 18,
                        backgroundColor = { 20, 30, 50, 220 },
                        borderRadius = 9,
                        borderWidth = 1,
                        borderColor = { 80, 140, 200, 150 },
                        overflow = "hidden",
                        children = {
                            -- 进度填充
                            UI.Panel {
                                position = "absolute",
                                top = 0, left = 0, bottom = 0,
                                width = math.floor(LBD.GetPityCount() / banner.pity * 100) .. "%",
                                backgroundColor = { 80, 170, 230, 200 },
                                borderRadius = 9,
                            },
                            -- 进度文字
                            UI.Panel {
                                position = "absolute",
                                top = 0, left = 0, right = 0, bottom = 0,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = LBD.GetPityCount() .. "/" .. banner.pity .. " 保底UR",
                                        fontSize = 10,
                                        fontColor = { 255, 255, 255, 230 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 详情入口按钮
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        paddingLeft = 10, paddingRight = 10,
                        paddingTop = 4, paddingBottom = 4,
                        backgroundColor = { 0, 0, 0, 120 },
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = { 100, 170, 220, 150 },
                        onClick = function(self)
                            showDetailFn()
                        end,
                        children = {
                            UI.Label {
                                text = "详情",
                                fontSize = 11,
                                fontColor = { 160, 210, 255, 230 },
                            },
                            UI.Label {
                                text = ">",
                                fontSize = 11,
                                fontColor = { 120, 170, 210, 180 },
                            },
                        },
                    },
                },
            },
            -- 不活跃遮罩
            not isActive and UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 160 },
                justifyContent = "center",
                alignItems = "center",
                zIndex = 2,
                children = {
                    UI.Label {
                        text = "限定池已结束",
                        fontSize = 24,
                        fontColor = { 200, 200, 200, 200 },
                        fontWeight = "bold",
                    },
                },
            } or nil,
        },
    }
end

--- 限定池按钮区
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param currentTab string
---@param refreshFn function
---@return any
function LimitedPool.CreateButtonArea(UI, pageRoot, RARITY_COLORS, currentTab, refreshFn)
    local LBD = require("Game.LimitedBannerData")
    local banner = Config.LIMITED_BANNER
    local isActive = LBD.IsActive()
    local canSingle = isActive and LBD.CanAfford(banner.singleCost)
    local canTen = isActive and LBD.CanAfford(banner.tenCost)

    local buttons = {}

    -- 购买契约按钮
    buttons[#buttons + 1] = UI.Panel {
        width = 56, height = 56,
        borderRadius = 10,
        backgroundColor = { 30, 50, 80, 255 },
        borderWidth = 1,
        borderColor = { 100, 160, 220, 180 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        flexShrink = 0,
        onClick = function(self)
            GachaResult.ShowBuyPopup(UI, pageRoot, 1, "frost_pact", refreshFn)
        end,
        children = {
            Currency.IconWidget(UI, "frost_pact", 22),
            UI.Label {
                text = "购买",
                fontSize = 10,
                fontColor = { 130, 210, 255, 200 },
            },
        },
    }

    -- 单抽按钮
    buttons[#buttons + 1] = UI.Panel {
        flex = 1,
        height = 56,
        borderRadius = 10,
        backgroundColor = (canSingle) and { 30, 60, 100, 255 } or { 25, 30, 45, 200 },
        borderWidth = 1,
        borderColor = (canSingle) and { 100, 180, 240, 200 } or { 50, 60, 80, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            if not isActive then
                local Toast = require("Game.Toast")
                Toast.Show("限定池已结束", { 255, 100, 100 })
                return
            end
            if canSingle then
                GachaResult.DoLimitedRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 1, refreshFn)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 1, "frost_pact", refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "frost_pact", 16),
                    UI.Label {
                        text = tostring(banner.singleCost),
                        fontSize = 14,
                        fontColor = { 130, 210, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募一次",
                fontSize = 14,
                fontColor = (canSingle) and { 255, 255, 255, 255 } or { 100, 110, 130, 180 },
                fontWeight = "bold",
            },
        },
    }

    -- 十连按钮
    buttons[#buttons + 1] = UI.Panel {
        flex = 1,
        height = 56,
        borderRadius = 10,
        backgroundColor = (canTen) and { 40, 80, 140, 255 } or { 25, 30, 45, 200 },
        borderWidth = 1,
        borderColor = (canTen) and { 130, 210, 255, 220 } or { 50, 60, 80, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            if not isActive then
                local Toast = require("Game.Toast")
                Toast.Show("限定池已结束", { 255, 100, 100 })
                return
            end
            if canTen then
                GachaResult.DoLimitedRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 10, refreshFn)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 10, "frost_pact", refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "frost_pact", 16),
                    UI.Label {
                        text = tostring(banner.tenCost),
                        fontSize = 14,
                        fontColor = { 130, 210, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募十次",
                fontSize = 14,
                fontColor = (canTen) and { 255, 255, 255, 255 } or { 100, 110, 130, 180 },
                fontWeight = "bold",
            },
        },
    }

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 15, 20, 35, 230 },
        borderWidth = 1,
        borderColor = { 60, 100, 160, 120 },
        flexShrink = 0,
        children = buttons,
    }
end

--- 显示限定池详情弹窗
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param RARITY_BG table
function LimitedPool.ShowDetailPopup(UI, pageRoot, RARITY_COLORS, RARITY_BG)
    if not pageRoot or not UI then return end

    local old = pageRoot:FindById("limitedDetailPopup")
    if old then pageRoot:RemoveChild(old) end

    local LBD = require("Game.LimitedBannerData")
    local banner = Config.LIMITED_BANNER
    local listChildren = {}

    -- 限定英雄信息
    local heroName = banner.heroId
    local heroColor = { 130, 210, 255 }
    local heroSpecial = ""
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == banner.heroId then
            heroName = td.name
            heroColor = td.color
            heroSpecial = td.special or ""
            break
        end
    end

    -- UP 英雄卡片
    listChildren[#listChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        marginBottom = 6,
        backgroundColor = { 20, 40, 70, 220 },
        borderRadius = 8,
        borderWidth = 2,
        borderColor = { 130, 210, 255, 200 },
        children = {
            -- UP 标记
            UI.Panel {
                width = 36, height = 20,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 130, 210, 255, 255 },
                borderRadius = 4,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = "UP",
                        fontSize = 10,
                        fontColor = { 10, 20, 40, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 稀有度
            UI.Panel {
                width = 36, height = 20,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = RARITY_COLORS["UR"],
                borderRadius = 4,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = "UR",
                        fontSize = 10,
                        fontColor = { 20, 16, 32, 255 },
                    },
                },
            },
            UI.Label {
                text = heroName,
                fontSize = 15,
                fontColor = heroColor,
                fontWeight = "bold",
                flex = 1,
            },
            UI.Label {
                text = "限定专属",
                fontSize = 11,
                fontColor = { 130, 210, 255, 200 },
            },
        },
    }

    -- 技能说明
    local skills = Config.HERO_SKILLS and Config.HERO_SKILLS[banner.heroId]
    if skills then
        for _, skill in ipairs(skills) do
            listChildren[#listChildren + 1] = UI.Panel {
                width = "100%",
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 12, paddingRight = 12,
                marginBottom = 3,
                backgroundColor = { 20, 30, 50, 180 },
                borderRadius = 6,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        marginBottom = 3,
                        children = {
                            UI.Panel {
                                paddingLeft = 5, paddingRight = 5,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = skill.type == "active"
                                    and { 200, 120, 40, 200 }
                                    or { 60, 120, 180, 200 },
                                borderRadius = 3,
                                children = {
                                    UI.Label {
                                        text = skill.type == "active" and "主动" or "被动",
                                        fontSize = 9,
                                        fontColor = { 255, 255, 255, 255 },
                                    },
                                },
                            },
                            UI.Label {
                                text = skill.name,
                                fontSize = 13,
                                fontColor = { 200, 220, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Label {
                        text = skill.desc,
                        fontSize = 11,
                        fontColor = { 160, 180, 210, 200 },
                    },
                },
            }
        end
    end

    -- 分割线
    listChildren[#listChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 60, 100, 150, 100 },
        alignSelf = "center",
        marginTop = 8, marginBottom = 8,
    }

    -- 概率信息
    local rates = banner.rates
    local rateOrder = { "LR", "UR", "SSR", "SR", "R", "N" }
    local rateLabels = {}
    for _, r in ipairs(rateOrder) do
        if rates[r] then
            rateLabels[#rateLabels + 1] = UI.Panel {
                paddingLeft = 6, paddingRight = 6,
                paddingTop = 2, paddingBottom = 2,
                backgroundColor = { RARITY_COLORS[r][1], RARITY_COLORS[r][2], RARITY_COLORS[r][3], 40 },
                borderRadius = 4,
                children = {
                    UI.Label {
                        text = r .. " " .. rates[r] .. "%",
                        fontSize = 12,
                        fontColor = RARITY_COLORS[r],
                    },
                },
            }
        end
    end

    listChildren[#listChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        gap = 6,
        paddingBottom = 6,
        children = rateLabels,
    }

    listChildren[#listChildren + 1] = UI.Label {
        text = banner.pity .. "抽保底UR限定英雄 / 十连保底SSR",
        fontSize = 11,
        fontColor = { 150, 180, 210, 200 },
        alignSelf = "center",
        marginBottom = 6,
    }

    listChildren[#listChildren + 1] = UI.Label {
        text = "UR品质必定为限定英雄，提前获得后保底计数重置",
        fontSize = 10,
        fontColor = { 130, 160, 190, 160 },
        alignSelf = "center",
        marginBottom = 10,
    }

    -- 分割线
    listChildren[#listChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 60, 100, 150, 100 },
        alignSelf = "center",
        marginBottom = 10,
    }

    -- 非限定英雄列表（来自 fallbackPool）
    local rarityOrder2 = { "LR", "SSR", "SR", "R", "N" }
    for _, rarity in ipairs(rarityOrder2) do
        local pool = banner.fallbackPool[rarity]
        if pool then
            local fragRange = Config.RECRUIT_FRAGMENT_DROP[rarity]
            for _, heroId in ipairs(pool) do
                local hName = heroId
                local hColor = { 200, 200, 200 }
                for _, td in ipairs(Config.TOWER_TYPES) do
                    if td.id == heroId then
                        hName = td.name
                        hColor = td.color
                        break
                    end
                end

                local h = HeroData.Get(heroId)
                local frags = h and h.fragments or 0
                local unlocked = h and h.unlocked or false

                listChildren[#listChildren + 1] = UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    paddingTop = 5, paddingBottom = 5,
                    paddingLeft = 10, paddingRight = 10,
                    marginBottom = 2,
                    backgroundColor = RARITY_BG[rarity],
                    borderRadius = 6,
                    children = {
                        UI.Panel {
                            width = 36, height = 18,
                            justifyContent = "center",
                            alignItems = "center",
                            backgroundColor = RARITY_COLORS[rarity],
                            borderRadius = 4,
                            marginRight = 8,
                            children = {
                                UI.Label {
                                    text = rarity,
                                    fontSize = 10,
                                    fontColor = { 20, 16, 32, 255 },
                                },
                            },
                        },
                        UI.Label {
                            text = hName,
                            fontSize = 12,
                            fontColor = hColor,
                            flex = 1,
                        },
                        UI.Label {
                            text = fragRange.min .. "~" .. fragRange.max,
                            fontSize = 10,
                            fontColor = { 150, 140, 170, 180 },
                            marginRight = 6,
                        },
                        UI.Label {
                            text = (unlocked and "✓ " or "") .. frags,
                            fontSize = 10,
                            fontColor = unlocked and { 100, 220, 100, 255 } or { 180, 160, 140, 200 },
                        },
                    },
                }
            end
        end
    end

    local popup = UI.Panel {
        id = "limitedDetailPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 0, 0, 0, 210 },
        pointerEvents = "auto",
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%",
                alignItems = "center",
                paddingTop = 14, paddingBottom = 10,
                flexShrink = 0,
                backgroundColor = { 15, 25, 45, 255 },
                borderWidth = 1,
                borderColor = { 60, 120, 180, 120 },
                children = {
                    UI.Label {
                        text = "限定祭坛 · 详情",
                        fontSize = 18,
                        fontColor = { 130, 210, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 可滚动列表
            UI.ScrollView {
                width = "100%",
                flex = 1,
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 10, paddingRight = 10,
                children = listChildren,
            },
            -- 返回按钮
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
                flexShrink = 0,
                backgroundColor = { 15, 25, 45, 255 },
                borderWidth = 1,
                borderColor = { 60, 120, 180, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        paddingLeft = 14, paddingRight = 18,
                        paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 30, 60, 100, 255 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 80, 150, 220, 150 },
                        onClick = function(self)
                            local p = pageRoot:FindById("limitedDetailPopup")
                            if p then pageRoot:RemoveChild(p) end
                        end,
                        children = {
                            UI.Label {
                                text = "<",
                                fontSize = 14,
                                fontColor = { 130, 180, 220, 200 },
                            },
                            UI.Label {
                                text = "返回",
                                fontSize = 14,
                                fontColor = { 160, 210, 255, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    pageRoot:AddChild(popup)
end

--- 显示限定池广告领取霜誓契约弹窗
---@param UI any
---@param pageRoot any
---@param refreshFn function
function LimitedPool.ShowAdFrostDialog(UI, pageRoot, refreshFn)
    if not pageRoot or not UI then return end
    local LBD = require("Game.LimitedBannerData")

    local old = pageRoot:FindById("adFrostPopup")
    if old then pageRoot:RemoveChild(old) end

    local canClaim = LBD.CanClaimAdFrost()
    local remaining = LBD.GetAdFrostRemaining()
    local dailyMax = LBD.GetAdFrostDailyMax()
    local amount = LBD.GetAdFrostAmount()

    local function closePopup()
        local p = pageRoot:FindById("adFrostPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    local popup = UI.Panel {
        id = "adFrostPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self) closePopup() end,
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = { 15, 25, 50, 245 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 80, 180, 240, 180 },
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                gap = 14,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,
                children = {
                    UI.Label {
                        text = "免费霜誓契约",
                        fontSize = 18,
                        fontColor = { 100, 210, 255, 255 },
                        fontWeight = "bold",
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 180, 240, 60 } },
                    UI.Panel {
                        width = 72, height = 72,
                        borderRadius = 12,
                        backgroundColor = { 20, 40, 70, 255 },
                        borderWidth = 2,
                        borderColor = { 80, 170, 230, 200 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            Currency.IconWidget(UI, "frost_pact", 40),
                        },
                    },
                    UI.Label {
                        text = "霜誓契约 x" .. amount,
                        fontSize = 16,
                        fontColor = { 130, 220, 255, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "今日剩余 " .. remaining .. "/" .. dailyMax .. " 次",
                        fontSize = 13,
                        fontColor = canClaim
                            and { 160, 200, 230, 220 }
                            or { 120, 100, 100, 200 },
                    },
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 20, 40, 70, 150 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        children = {
                            UI.Label {
                                text = "看广告免费获取霜誓契约",
                                fontSize = 12,
                                fontColor = { 160, 200, 230, 200 },
                            },
                        },
                    },
                    canClaim and UI.Panel {
                        width = "100%",
                        height = 42,
                        borderRadius = 8,
                        backgroundColor = { 60, 160, 220 },
                        borderWidth = 1,
                        borderColor = { 100, 200, 255, 180 },
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 6,
                        onClick = function(self)
                            local AdHelper = require("Game.AdHelper")
                            AdHelper.ShowRewardAd(function()
                                local gained = LBD.ClaimAdFrost()
                                closePopup()
                                refreshFn()
                                local def = Config.CURRENCY["frost_pact"]
                                RewardDisplay.Show(UI, pageRoot, {
                                    title = "免费契约",
                                    rewards = {
                                        {
                                            icon = def and def.image or "?",
                                            name = def and def.name or "霜誓契约",
                                            amount = gained,
                                        },
                                    },
                                })
                            end)
                        end,
                        children = {
                            UI.Panel {
                                width = 18, height = 18,
                                backgroundImage = "image/icon_watch_ad.png",
                                backgroundFit = "contain",
                            },
                            UI.Label {
                                text = "看广告领取",
                                fontSize = 14,
                                fontColor = { 10, 20, 40 },
                                fontWeight = "bold",
                            },
                        },
                    } or UI.Panel {
                        width = "100%",
                        height = 42,
                        borderRadius = 8,
                        backgroundColor = { 40, 50, 65, 200 },
                        borderWidth = 1,
                        borderColor = { 60, 70, 85, 120 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "今日已达上限",
                                fontSize = 14,
                                fontColor = { 100, 120, 140, 180 },
                            },
                        },
                    },
                    UI.Button {
                        text = "关闭",
                        fontSize = 13,
                        variant = "outline",
                        width = "100%",
                        height = 34,
                        borderRadius = 8,
                        onClick = function(self) closePopup() end,
                    },
                },
            },
        },
    }

    pageRoot:AddChild(popup)
end

return LimitedPool
