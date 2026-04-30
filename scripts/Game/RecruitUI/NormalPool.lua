-- Game/RecruitUI/NormalPool.lua
-- 常驻池组件（货币栏、横幅、按钮区、详情弹窗、广告弹窗）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local RecruitData = require("Game.RecruitData")
local Currency = require("Game.Currency")
local RewardDisplay = require("Game.RewardDisplay")
local GachaResult = require("Game.RecruitUI.GachaResult")

local NormalPool = {}

-- ============================================================================
-- 常驻池精选角色轮播配置
-- ============================================================================

local FEATURED_HEROES = {
    {
        heroId = "crimson_night",
        name   = "绯夜",
        color  = { 200, 50, 80 },
        image  = "image/绯夜_立绘_v5_20260422131608.png",
        bgColor = { 60, 20, 40, 200 },
        borderColor = { 200, 50, 80, 150 },
    },
    {
        heroId = "ember_wraith",
        name   = "烬殇",
        color  = { 255, 120, 30 },
        image  = "image/ember_wraith_artwork_20260426024033.png",
        bgColor = { 60, 30, 10, 200 },
        borderColor = { 255, 120, 30, 150 },
    },
}

-- 当前轮播索引（模块级状态）
local _featuredIndex = 1

--- 切换到下一个精选角色
function NormalPool.NextFeatured()
    _featuredIndex = _featuredIndex % #FEATURED_HEROES + 1
end

--- 切换到上一个精选角色
function NormalPool.PrevFeatured()
    _featuredIndex = (_featuredIndex - 2) % #FEATURED_HEROES + 1
end

--- 获取当前精选角色配置
---@return table
function NormalPool.GetCurrentFeatured()
    return FEATURED_HEROES[_featuredIndex]
end

--- 顶部招募令货币栏
---@param UI any
---@return any
function NormalPool.CreateTokenBar(UI)
    local tokens = HeroData.currencies.void_pact or 0
    local totalPulls = RecruitData.GetTotalPulls()
    local urPity = RecruitData.GetURPityCount()
    local lrPity = RecruitData.GetLRPityCount()
    local safeTop = (UI.GetSafeAreaInsets().top or 0)

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        paddingTop = safeTop + 8, paddingBottom = 8,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 20, 16, 32, 200 },
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        flexShrink = 0,
        gap = 6,
        children = {
            -- 第一行：货币 + 累计抽数
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            Currency.IconWidget(UI, "void_pact", 18),
                            UI.Label {
                                text = "虚空契约: " .. tokens,
                                fontSize = 15,
                                fontColor = { 255, 200, 50, 255 },
                            },
                        },
                    },
                    UI.Label {
                        text = "十连保底SSR",
                        fontSize = 12,
                        fontColor = { 200, 160, 255, 160 },
                    },
                    UI.Label {
                        text = "累计: " .. totalPulls .. "抽",
                        fontSize = 12,
                        fontColor = { 150, 140, 170, 180 },
                    },
                },
            },
            -- 第二行：UR/LR 保底进度条
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                alignItems = "center",
                children = {
                    -- UR 保底进度
                    UI.Panel {
                        flex = 1, flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = "UR",
                                fontSize = 10, fontWeight = "bold",
                                fontColor = Config.RARITY_COLORS.UR or { 255, 200, 50, 255 },
                            },
                            UI.Panel {
                                flex = 1, height = 8,
                                borderRadius = 4,
                                backgroundColor = { 40, 35, 55, 200 },
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = math.max(2, math.floor((urPity / 50) * 100)) .. "%",
                                        height = "100%",
                                        borderRadius = 4,
                                        backgroundColor = urPity >= 45
                                            and { 255, 180, 50, 255 }
                                            or  { 180, 140, 60, 200 },
                                    },
                                },
                            },
                            UI.Label {
                                text = urPity .. "/50",
                                fontSize = 10,
                                fontColor = urPity >= 45
                                    and { 255, 200, 60, 255 }
                                    or  { 150, 140, 170, 180 },
                            },
                        },
                    },
                    -- LR 保底进度
                    UI.Panel {
                        flex = 1, flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = "LR",
                                fontSize = 10, fontWeight = "bold",
                                fontColor = Config.RARITY_COLORS.LR or { 255, 80, 80, 255 },
                            },
                            UI.Panel {
                                flex = 1, height = 8,
                                borderRadius = 4,
                                backgroundColor = { 40, 35, 55, 200 },
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = math.max(2, math.floor((lrPity / 100) * 100)) .. "%",
                                        height = "100%",
                                        borderRadius = 4,
                                        backgroundColor = lrPity >= 81
                                            and { 255, 80, 80, 255 }
                                            or  { 180, 60, 60, 200 },
                                    },
                                },
                            },
                            UI.Label {
                                text = lrPity .. "/100",
                                fontSize = 10,
                                fontColor = lrPity >= 81
                                    and { 255, 100, 100, 255 }
                                    or  { 150, 140, 170, 180 },
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 池子横幅（大幅视觉区域，填满中间空间）
---@param UI any
---@param showAdPactFn function
---@param showDetailFn function
---@param showFateRitualFn function|nil
---@return any
function NormalPool.CreatePoolBanner(UI, showAdPactFn, showDetailFn, showFateRitualFn, refreshFn)
    local featured = NormalPool.GetCurrentFeatured()
    local fc = featured.color

    -- 构建底部指示点
    local dots = {}
    for i, hero in ipairs(FEATURED_HEROES) do
        local isActive = (i == _featuredIndex)
        dots[#dots + 1] = UI.Panel {
            width = isActive and 18 or 8,
            height = 8,
            borderRadius = 4,
            backgroundColor = isActive
                and { fc[1], fc[2], fc[3], 240 }
                or  { 180, 170, 200, 100 },
        }
    end

    return UI.Panel {
        width = "100%",
        flex = 1,
        backgroundImage = "image/recruit_pool_bg.png",
        backgroundFit = "cover",
        justifyContent = "flex-start",
        alignItems = "center",
        overflow = "hidden",
        children = {
            -- 标题
            UI.Label {
                text = "深渊祭坛",
                fontSize = 36,
                fontColor = { 220, 180, 255, 255 },
                fontWeight = "bold",
                marginTop = 16,
            },
            -- 当前精选角色名称标签
            UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = featured.bgColor,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = featured.borderColor,
                children = {
                    UI.Label {
                        text = featured.name,
                        fontSize = 18,
                        fontColor = { fc[1], fc[2], fc[3], 255 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 左侧切换箭头
            UI.Panel {
                position = "absolute",
                left = 4, top = "50%",
                width = 44, height = 64,
                borderRadius = 8,
                backgroundColor = { 10, 6, 20, 180 },
                borderWidth = 1,
                borderColor = { 120, 80, 200, 100 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self)
                    NormalPool.PrevFeatured()
                    if refreshFn then refreshFn() end
                end,
                children = {
                    UI.Label {
                        text = "<",
                        fontSize = 28,
                        fontColor = { 220, 200, 255, 240 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 右侧切换箭头
            UI.Panel {
                position = "absolute",
                right = 4, top = "50%",
                width = 44, height = 64,
                borderRadius = 8,
                backgroundColor = { 10, 6, 20, 180 },
                borderWidth = 1,
                borderColor = { 120, 80, 200, 100 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self)
                    NormalPool.NextFeatured()
                    if refreshFn then refreshFn() end
                end,
                children = {
                    UI.Label {
                        text = ">",
                        fontSize = 28,
                        fontColor = { 220, 200, 255, 240 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 底部指示点
            UI.Panel {
                position = "absolute",
                bottom = 52, left = 0, right = 0,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 6,
                pointerEvents = "none",
                children = dots,
            },
            -- 左侧广告领契约入口
            UI.Panel {
                position = "absolute",
                left = 10, top = "40%",
                width = 52, height = 52,
                borderRadius = 12,
                backgroundColor = { 40, 20, 60, 220 },
                borderWidth = 2,
                borderColor = RecruitData.CanClaimAdPact()
                    and { 255, 200, 60, 220 }
                    or { 80, 60, 100, 150 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self)
                    showAdPactFn()
                end,
                children = {
                    Currency.IconWidget(UI, "void_pact", 28),
                    -- 底部小标签
                    UI.Panel {
                        position = "absolute",
                        bottom = -2, left = 0, right = 0,
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                paddingLeft = 3, paddingRight = 3,
                                paddingTop = 1, paddingBottom = 1,
                                backgroundColor = RecruitData.CanClaimAdPact()
                                    and { 220, 160, 40, 255 }
                                    or { 60, 50, 70, 200 },
                                borderRadius = 4,
                                children = {
                                    UI.Label {
                                        text = "广告",
                                        fontSize = 9,
                                        fontColor = RecruitData.CanClaimAdPact()
                                            and { 30, 20, 10, 255 }
                                            or { 120, 110, 130, 180 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 可领取红点
                    RecruitData.CanClaimAdPact() and UI.Panel {
                        position = "absolute",
                        top = -2, right = -2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                    } or nil,
                },
            },
            -- 精选角色立绘（跟随轮播切换）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = featured.image,
                backgroundFit = "contain",
                backgroundPosition = "center center",
                pointerEvents = "none",
            },
            -- 命定仪轨入口按钮
            (function()
                local fateUR, fateLR = RecruitData.GetFateHeroes()
                local hasFate = (fateUR ~= nil or fateLR ~= nil)
                -- 查英雄名称
                local function heroName(heroId)
                    if not heroId then return nil end
                    for _, td in ipairs(Config.TOWER_TYPES) do
                        if td.id == heroId then return td.name end
                    end
                    return heroId
                end
                local subChildren = {}
                if hasFate then
                    if fateUR then
                        subChildren[#subChildren + 1] = UI.Label {
                            text = "UR " .. heroName(fateUR),
                            fontSize = 9,
                            fontColor = { 255, 220, 130, 200 },
                        }
                    end
                    if fateLR then
                        subChildren[#subChildren + 1] = UI.Label {
                            text = "LR " .. heroName(fateLR),
                            fontSize = 9,
                            fontColor = { 255, 140, 140, 200 },
                        }
                    end
                else
                    subChildren[#subChildren + 1] = UI.Label {
                        text = "当前未命定",
                        fontSize = 9,
                        fontColor = { 140, 120, 160, 160 },
                    }
                end
                return UI.Panel {
                    position = "absolute",
                    bottom = 10, left = 12,
                    flexDirection = "column",
                    alignItems = "center",
                    gap = 2,
                    paddingLeft = 10, paddingRight = 10,
                    paddingTop = 5, paddingBottom = 5,
                    backgroundColor = { 20, 10, 30, 180 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = hasFate
                        and { 200, 160, 80, 200 }
                        or  { 100, 80, 120, 150 },
                    onClick = function(self)
                        if showFateRitualFn then showFateRitualFn() end
                    end,
                    children = {
                        UI.Label {
                            text = "命定",
                            fontSize = 12,
                            fontColor = hasFate
                                and { 255, 220, 130, 240 }
                                or  { 160, 140, 180, 200 },
                            fontWeight = "bold",
                        },
                        table.unpack(subChildren),
                    },
                }
            end)(),
            -- 详情入口按钮
            UI.Panel {
                position = "absolute",
                bottom = 10, right = 12,
                flexDirection = "row",
                alignItems = "center",
                gap = 3,
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 5, paddingBottom = 5,
                backgroundColor = { 0, 0, 0, 120 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 160, 130, 220, 150 },
                onClick = function(self)
                    showDetailFn()
                end,
                children = {
                    UI.Label {
                        text = "详情",
                        fontSize = 12,
                        fontColor = { 200, 180, 255, 230 },
                    },
                    UI.Label {
                        text = ">",
                        fontSize = 12,
                        fontColor = { 160, 140, 200, 180 },
                    },
                },
            },
        },
    }
end

--- 底部按钮区（常驻池）
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param currentTab string
---@param refreshFn function
---@return any
function NormalPool.CreateButtonArea(UI, pageRoot, RARITY_COLORS, currentTab, refreshFn)
    local canSingle = RecruitData.CanAfford(Config.RECRUIT_SINGLE_COST)
    local canTen = RecruitData.CanAfford(Config.RECRUIT_TEN_COST)
    local canHundred = RecruitData.CanAfford(Config.RECRUIT_HUNDRED_COST)
    local canThousand = RecruitData.CanAfford(Config.RECRUIT_THOUSAND_COST)

    local buttons = {}

    -- 单抽按钮
    buttons[#buttons + 1] = UI.Panel {
        flex = 1,
        height = 56,
        borderRadius = 10,
        backgroundColor = canSingle and { 60, 50, 90, 255 } or { 40, 35, 55, 200 },
        borderWidth = 1,
        borderColor = canSingle and { 140, 100, 220, 200 } or { 60, 50, 80, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            if canSingle then
                GachaResult.DoRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 1, false, refreshFn)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 1, "void_pact", refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "void_pact", 16),
                    UI.Label {
                        text = tostring(Config.RECRUIT_SINGLE_COST),
                        fontSize = 14,
                        fontColor = { 255, 220, 80, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募一次",
                fontSize = 14,
                fontColor = canSingle and { 255, 255, 255, 255 } or { 120, 110, 140, 180 },
                fontWeight = "bold",
            },
        },
    }

    -- 十连按钮
    buttons[#buttons + 1] = UI.Panel {
        flex = 1,
        height = 56,
        borderRadius = 10,
        backgroundColor = canTen and { 140, 100, 40, 255 } or { 50, 42, 30, 200 },
        borderWidth = 1,
        borderColor = canTen and { 255, 200, 60, 200 } or { 80, 65, 40, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            if canTen then
                GachaResult.DoRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 10, false, refreshFn)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 10, "void_pact", refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "void_pact", 16),
                    UI.Label {
                        text = tostring(Config.RECRUIT_TEN_COST),
                        fontSize = 14,
                        fontColor = { 255, 220, 80, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募十次",
                fontSize = 14,
                fontColor = canTen and { 255, 255, 255, 255 } or { 120, 110, 140, 180 },
                fontWeight = "bold",
            },
        },
    }

    -- 百连按钮
    buttons[#buttons + 1] = UI.Panel {
        flex = 1,
        height = 56,
        borderRadius = 10,
        backgroundColor = canHundred and { 160, 60, 40, 255 } or { 50, 35, 30, 200 },
        borderWidth = 1,
        borderColor = canHundred and { 255, 120, 60, 200 } or { 80, 50, 40, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            if canHundred then
                GachaResult.DoRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 100, false, refreshFn)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 100, "void_pact", refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "void_pact", 16),
                    UI.Label {
                        text = tostring(Config.RECRUIT_HUNDRED_COST),
                        fontSize = 14,
                        fontColor = { 255, 220, 80, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募百次",
                fontSize = 14,
                fontColor = canHundred and { 255, 255, 255, 255 } or { 120, 110, 140, 180 },
                fontWeight = "bold",
            },
        },
    }

    -- 千连按钮
    buttons[#buttons + 1] = UI.Panel {
        flex = 1,
        height = 56,
        borderRadius = 10,
        backgroundColor = canThousand and { 120, 40, 140, 255 } or { 45, 25, 50, 200 },
        borderWidth = 1,
        borderColor = canThousand and { 220, 100, 255, 200 } or { 70, 40, 80, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function(self)
            if canThousand then
                GachaResult.DoRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 1000, false, refreshFn)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 1000, "void_pact", refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, "void_pact", 16),
                    UI.Label {
                        text = tostring(Config.RECRUIT_THOUSAND_COST),
                        fontSize = 14,
                        fontColor = { 255, 220, 80, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募千次",
                fontSize = 14,
                fontColor = canThousand and { 255, 255, 255, 255 } or { 120, 110, 140, 180 },
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
        backgroundColor = { 20, 16, 32, 230 },
        borderWidth = 1,
        borderColor = { 100, 70, 180, 120 },
        flexShrink = 0,
        children = buttons,
    }
end

--- 显示详情弹窗（英雄列表 + 概率说明）
---@param UI any
---@param pageRoot any
---@param RARITY_COLORS table
---@param RARITY_BG table
function NormalPool.ShowDetailPopup(UI, pageRoot, RARITY_COLORS, RARITY_BG)
    if not pageRoot or not UI then return end

    local old = pageRoot:FindById("detailPopup")
    if old then pageRoot:RemoveChild(old) end

    local listChildren = {}

    -- 绯夜英雄卡片
    local cnHeroId = "crimson_night"
    local cnName = "绯夜"
    local cnColor = { 200, 50, 80 }
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == cnHeroId then
            cnName = td.name
            cnColor = td.color
            break
        end
    end
    listChildren[#listChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 12, paddingRight = 12,
        marginBottom = 6,
        backgroundColor = { 50, 15, 30, 220 },
        borderRadius = 8,
        borderWidth = 2,
        borderColor = { cnColor[1], cnColor[2], cnColor[3], 200 },
        children = {
            UI.Panel {
                width = 36, height = 20,
                justifyContent = "center", alignItems = "center",
                backgroundColor = RARITY_COLORS["UR"],
                borderRadius = 4, marginRight = 8,
                children = {
                    UI.Label { text = "UR", fontSize = 10, fontColor = { 20, 16, 32, 255 } },
                },
            },
            UI.Label { text = cnName, fontSize = 15, fontColor = { cnColor[1], cnColor[2], cnColor[3], 255 }, fontWeight = "bold", flex = 1 },
            UI.Label { text = "常驻精选", fontSize = 11, fontColor = { cnColor[1], cnColor[2], cnColor[3], 200 } },
        },
    }

    -- 绯夜技能说明
    local cnSkills = Config.HERO_SKILLS and Config.HERO_SKILLS[cnHeroId]
    if cnSkills then
        listChildren[#listChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "flex-end",
            paddingRight = 12, marginBottom = 2,
            children = {
                UI.Label {
                    text = "* 以下为满星属性",
                    fontSize = 10, fontColor = { 200, 160, 120, 180 },
                },
            },
        }
        for _, skill in ipairs(cnSkills) do
            listChildren[#listChildren + 1] = UI.Panel {
                width = "100%",
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 12, paddingRight = 12,
                marginBottom = 3,
                backgroundColor = { 40, 15, 25, 180 },
                borderRadius = 6,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6, marginBottom = 3,
                        children = {
                            UI.Panel {
                                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                                backgroundColor = skill.type == "active"
                                    and { 200, 120, 40, 200 } or { 60, 120, 180, 200 },
                                borderRadius = 3,
                                children = {
                                    UI.Label {
                                        text = skill.type == "active" and "主动" or "被动",
                                        fontSize = 9, fontColor = { 255, 255, 255, 255 },
                                    },
                                },
                            },
                            UI.Label { text = skill.name, fontSize = 13, fontColor = { 220, 180, 200, 255 }, fontWeight = "bold" },
                        },
                    },
                    UI.Label { text = skill.buildDesc and skill.buildDesc(1.0) or skill.desc, fontSize = 11, fontColor = { 180, 150, 170, 200 } },
                },
            }
        end
    end

    -- 分割线
    listChildren[#listChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 120, 40, 60, 100 },
        alignSelf = "center",
        marginBottom = 10,
    }

    local rates = Config.RECRUIT_RATES
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
        paddingBottom = 8,
        children = rateLabels,
    }

    listChildren[#listChildren + 1] = UI.Label {
        text = "十连召唤保底至少1个SSR",
        fontSize = 11,
        fontColor = { 180, 160, 120, 200 },
        alignSelf = "center",
        marginBottom = 10,
    }

    listChildren[#listChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 80, 60, 120, 100 },
        alignSelf = "center",
        marginBottom = 10,
    }

    local rarityOrder = { "LR", "UR", "SSR", "SR", "R", "N" }
    for _, rarity in ipairs(rarityOrder) do
        local heroIds = Config.RECRUIT_POOL[rarity]
        if heroIds then
            local fragRange = Config.RECRUIT_FRAGMENT_DROP[rarity]
            for _, heroId in ipairs(heroIds) do
                local heroName = heroId
                local heroColor = { 200, 200, 200 }
                for _, td in ipairs(Config.TOWER_TYPES) do
                    if td.id == heroId then
                        heroName = td.name
                        heroColor = td.color
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
                    paddingTop = 6, paddingBottom = 6,
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
                            text = heroName,
                            fontSize = 13,
                            fontColor = heroColor,
                            flex = 1,
                        },
                        UI.Label {
                            text = fragRange.min .. "~" .. fragRange.max .. "碎片",
                            fontSize = 11,
                            fontColor = { 150, 140, 170, 180 },
                            marginRight = 8,
                        },
                        UI.Label {
                            text = (unlocked and "✓ " or "") .. frags .. "碎片",
                            fontSize = 11,
                            fontColor = unlocked and { 100, 220, 100, 255 } or { 180, 160, 140, 200 },
                        },
                    },
                }
            end
        end
    end

    local popup = UI.Panel {
        id = "detailPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 0, 0, 0, 210 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%",
                alignItems = "center",
                paddingTop = 14, paddingBottom = 10,
                flexShrink = 0,
                backgroundColor = { 25, 20, 40, 255 },
                borderWidth = 1,
                borderColor = { 100, 70, 160, 120 },
                children = {
                    UI.Label {
                        text = "深渊祭坛 · 详情",
                        fontSize = 18,
                        fontColor = { 220, 180, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.ScrollView {
                width = "100%",
                flex = 1,
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 10, paddingRight = 10,
                children = listChildren,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
                flexShrink = 0,
                backgroundColor = { 25, 20, 40, 255 },
                borderWidth = 1,
                borderColor = { 100, 70, 160, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        paddingLeft = 14, paddingRight = 18,
                        paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 60, 40, 80, 255 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 140, 100, 200, 150 },
                        onClick = function(self)
                            local p = pageRoot:FindById("detailPopup")
                            if p then pageRoot:RemoveChild(p) end
                        end,
                        children = {
                            UI.Label {
                                text = "<",
                                fontSize = 14,
                                fontColor = { 180, 160, 220, 200 },
                            },
                            UI.Label {
                                text = "返回",
                                fontSize = 14,
                                fontColor = { 200, 180, 240, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    pageRoot:AddChild(popup)
end

--- 显示广告领取虚空契约弹窗
---@param UI any
---@param pageRoot any
---@param refreshFn function
function NormalPool.ShowAdPactDialog(UI, pageRoot, refreshFn)
    if not pageRoot or not UI then return end

    local old = pageRoot:FindById("adPactPopup")
    if old then pageRoot:RemoveChild(old) end

    local canClaim = RecruitData.CanClaimAdPact()
    local remaining = RecruitData.GetAdPactRemaining()
    local dailyMax = RecruitData.GetAdPactDailyMax()
    local amount = RecruitData.GetAdPactAmount()

    local function closePopup()
        local p = pageRoot:FindById("adPactPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    local popup = UI.Panel {
        id = "adPactPopup",
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
                backgroundColor = { 30, 24, 50, 245 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 200, 150, 60, 180 },
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                gap = 14,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,
                children = {
                    UI.Label {
                        text = "广告契约",
                        fontSize = 18,
                        fontColor = { 255, 200, 60, 255 },
                        fontWeight = "bold",
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 200, 150, 60, 60 } },
                    UI.Panel {
                        width = 72, height = 72,
                        borderRadius = 12,
                        backgroundColor = { 50, 35, 70, 255 },
                        borderWidth = 2,
                        borderColor = { 200, 40, 40, 200 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            Currency.IconWidget(UI, "void_pact", 40),
                        },
                    },
                    UI.Label {
                        text = "虚空契约 x" .. amount,
                        fontSize = 16,
                        fontColor = { 255, 220, 100, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "今日剩余 " .. remaining .. "/" .. dailyMax .. " 次",
                        fontSize = 13,
                        fontColor = canClaim
                            and { 180, 170, 200, 220 }
                            or { 140, 100, 100, 200 },
                    },
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 50, 40, 70, 150 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        children = {
                            UI.Label {
                                text = "看广告获取虚空契约",
                                fontSize = 12,
                                fontColor = { 200, 190, 220, 200 },
                            },
                        },
                    },
                    canClaim and UI.Panel {
                        width = "100%",
                        height = 42,
                        borderRadius = 8,
                        backgroundColor = { 200, 160, 50 },
                        borderWidth = 1,
                        borderColor = { 255, 220, 100, 180 },
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 6,
                        onClick = function(self)
                            local AdHelper = require("Game.AdHelper")
                            AdHelper.ShowRewardAd(function()
                                local gained = RecruitData.ClaimAdPact()
                                closePopup()
                                refreshFn()
                                local def = Config.CURRENCY["void_pact"]
                                RewardDisplay.Show(UI, pageRoot, {
                                    title = "广告契约",
                                    rewards = {
                                        {
                                            icon = def and def.image or "?",
                                            name = def and def.name or "虚空契约",
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
                                fontColor = { 30, 20, 10 },
                                fontWeight = "bold",
                            },
                        },
                    } or UI.Panel {
                        width = "100%",
                        height = 42,
                        borderRadius = 8,
                        backgroundColor = { 60, 55, 65, 200 },
                        borderWidth = 1,
                        borderColor = { 80, 75, 85, 120 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "今日已达上限",
                                fontSize = 14,
                                fontColor = { 120, 110, 130, 180 },
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

--- 显示命定仪轨弹窗（选择命定英雄 + 保底进度）
---@param UI any
---@param pageRoot any
---@param refreshFn function
function NormalPool.ShowFateRitualPopup(UI, pageRoot, refreshFn)
    if not pageRoot or not UI then return end

    local old = pageRoot:FindById("fateRitualPopup")
    if old then pageRoot:RemoveChild(old) end

    local HeroAvatar = require("Game.HeroAvatar")
    local curUR, curLR = RecruitData.GetFateHeroes()
    local urPity = RecruitData.GetURPityCount()
    local lrPity = RecruitData.GetLRPityCount()

    local RARITY_COLORS = Config.RARITY_COLORS

    local function closePopup()
        local p = pageRoot:FindById("fateRitualPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    --- 查英雄名称和颜色
    local function getHeroInfo(heroId)
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then
                return td.name, td.color
            end
        end
        return heroId, { 200, 200, 200 }
    end

    --- 构建一个稀有度段（标题 + 英雄选择卡片 + 进度条）
    local function buildSection(rarity, pool, currentFate, pityCount, pityMax, setFn)
        local rc = RARITY_COLORS[rarity] or { 200, 200, 200, 255 }
        local cards = {}
        for _, heroId in ipairs(pool) do
            local heroName, heroColor = getHeroInfo(heroId)
            local isSelected = (currentFate == heroId)
            cards[#cards + 1] = UI.Panel {
                width = 90, alignItems = "center", gap = 4,
                paddingTop = 6, paddingBottom = 8,
                paddingLeft = 4, paddingRight = 4,
                backgroundColor = isSelected
                    and { rc[1], rc[2], rc[3], 40 }
                    or  { 40, 35, 55, 150 },
                borderRadius = 10,
                borderWidth = isSelected and 2 or 1,
                borderColor = isSelected
                    and { rc[1], rc[2], rc[3], 220 }
                    or  { 60, 50, 80, 100 },
                onClick = function(self)
                    if isSelected then
                        -- 取消选择
                        setFn(nil)
                    else
                        setFn(heroId)
                    end
                    closePopup()
                    NormalPool.ShowFateRitualPopup(UI, pageRoot, refreshFn)
                end,
                children = {
                    -- 英雄头像
                    UI.Panel {
                        width = 64, height = 64,
                        borderRadius = 8,
                        overflow = "hidden",
                        borderWidth = isSelected and 2 or 1,
                        borderColor = isSelected
                            and { rc[1], rc[2], rc[3], 255 }
                            or  { 80, 70, 100, 150 },
                        children = {
                            HeroAvatar.Create(heroId, {
                                preset = "icon",
                                size = 64,
                            }),
                        },
                    },
                    -- 英雄名称
                    UI.Label {
                        text = heroName,
                        fontSize = 12,
                        fontColor = { heroColor[1], heroColor[2], heroColor[3], 255 },
                        fontWeight = isSelected and "bold" or "normal",
                    },
                    -- 选中标记
                    isSelected and UI.Panel {
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 1, paddingBottom = 1,
                        backgroundColor = { rc[1], rc[2], rc[3], 200 },
                        borderRadius = 4,
                        children = {
                            UI.Label {
                                text = "命定",
                                fontSize = 9,
                                fontColor = { 20, 16, 32, 255 },
                                fontWeight = "bold",
                            },
                        },
                    } or nil,
                },
            }
        end

        -- 进度条
        local pctWidth = math.max(2, math.floor((pityCount / pityMax) * 100))

        return UI.Panel {
            width = "100%",
            marginBottom = 14,
            gap = 8,
            children = {
                -- 段标题
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Panel {
                            paddingLeft = 8, paddingRight = 8,
                            paddingTop = 2, paddingBottom = 2,
                            backgroundColor = { rc[1], rc[2], rc[3], 200 },
                            borderRadius = 4,
                            children = {
                                UI.Label {
                                    text = rarity,
                                    fontSize = 12,
                                    fontColor = { 20, 16, 32, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                        UI.Label {
                            text = "命定英雄",
                            fontSize = 14,
                            fontColor = { 220, 200, 255, 220 },
                        },
                        UI.Panel { flex = 1 },
                        UI.Label {
                            text = pityMax .. "抽保底",
                            fontSize = 11,
                            fontColor = { 150, 140, 170, 180 },
                        },
                    },
                },
                -- 英雄卡片行
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    gap = 10,
                    children = cards,
                },
                -- 保底进度
                UI.Panel {
                    width = "100%", gap = 3,
                    children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between",
                            children = {
                                UI.Label {
                                    text = "保底进度",
                                    fontSize = 11,
                                    fontColor = { 160, 150, 180, 200 },
                                },
                                UI.Label {
                                    text = pityCount .. "/" .. pityMax,
                                    fontSize = 11,
                                    fontColor = { rc[1], rc[2], rc[3], 230 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                        UI.Panel {
                            width = "100%", height = 10,
                            borderRadius = 5,
                            backgroundColor = { 40, 35, 55, 200 },
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = pctWidth .. "%",
                                    height = "100%",
                                    borderRadius = 5,
                                    backgroundColor = { rc[1], rc[2], rc[3], 220 },
                                },
                            },
                        },
                    },
                },
            },
        }
    end

    -- 当前命定英雄显示
    local fateStatusText = "当前未命定"
    if curUR or curLR then
        local parts = {}
        if curUR then
            local n = getHeroInfo(curUR)
            parts[#parts + 1] = "UR: " .. n
        end
        if curLR then
            local n = getHeroInfo(curLR)
            parts[#parts + 1] = "LR: " .. n
        end
        fateStatusText = "当前命定: " .. table.concat(parts, " | ")
    end

    local popup = UI.Panel {
        id = "fateRitualPopup",
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
                backgroundColor = { 25, 20, 40, 255 },
                borderWidth = 1,
                borderColor = { 200, 160, 80, 150 },
                gap = 4,
                children = {
                    UI.Label {
                        text = "命定仪轨",
                        fontSize = 18,
                        fontColor = { 255, 220, 130, 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "选择命定英雄，保底时必定获得",
                        fontSize = 12,
                        fontColor = { 180, 170, 200, 180 },
                    },
                },
            },
            -- 内容区域
            UI.ScrollView {
                width = "100%",
                flex = 1,
                paddingTop = 14, paddingBottom = 14,
                paddingLeft = 16, paddingRight = 16,
                children = {
                    -- 当前状态
                    UI.Panel {
                        width = "100%",
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 12, paddingRight = 12,
                        backgroundColor = { 40, 30, 60, 180 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 200, 160, 80, 100 },
                        marginBottom = 14,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = fateStatusText,
                                fontSize = 13,
                                fontColor = { 255, 220, 140, 220 },
                            },
                        },
                    },
                    -- UR 段
                    buildSection("UR", Config.RECRUIT_POOL.UR, curUR, urPity, 50,
                        RecruitData.SetFateHeroUR),
                    -- LR 段
                    buildSection("LR", Config.RECRUIT_POOL.LR, curLR, lrPity, 100,
                        RecruitData.SetFateHeroLR),
                    -- 规则说明
                    UI.Panel {
                        width = "100%",
                        paddingTop = 10, paddingBottom = 10,
                        paddingLeft = 10, paddingRight = 10,
                        backgroundColor = { 30, 25, 45, 180 },
                        borderRadius = 8,
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "规则说明",
                                fontSize = 13,
                                fontColor = { 200, 180, 240, 230 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "· UR英雄50抽保底，LR英雄100抽保底",
                                fontSize = 11,
                                fontColor = { 160, 150, 180, 200 },
                            },
                            UI.Label {
                                text = "· 保底触发时，必定获得命定英雄",
                                fontSize = 11,
                                fontColor = { 160, 150, 180, 200 },
                            },
                            UI.Label {
                                text = "· 自然获得UR/LR也会重置对应保底计数",
                                fontSize = 11,
                                fontColor = { 160, 150, 180, 200 },
                            },
                            UI.Label {
                                text = "· 可随时切换命定英雄，保底次数保留",
                                fontSize = 11,
                                fontColor = { 160, 150, 180, 200 },
                            },
                        },
                    },
                },
            },
            -- 底部关闭栏
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
                flexShrink = 0,
                backgroundColor = { 25, 20, 40, 255 },
                borderWidth = 1,
                borderColor = { 200, 160, 80, 150 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        paddingLeft = 14, paddingRight = 18,
                        paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 60, 40, 80, 255 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 200, 160, 80, 150 },
                        onClick = function(self)
                            closePopup()
                            if refreshFn then refreshFn() end
                        end,
                        children = {
                            UI.Label {
                                text = "<",
                                fontSize = 14,
                                fontColor = { 200, 180, 130, 200 },
                            },
                            UI.Label {
                                text = "返回",
                                fontSize = 14,
                                fontColor = { 255, 220, 140, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    pageRoot:AddChild(popup)
end

return NormalPool
