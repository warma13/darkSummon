-- Game/RecruitUI/LimitedPool.lua
-- 限定池组件（货币栏、横幅、按钮区、详情弹窗、广告弹窗）
-- 所有函数接受 bannerCfg 参数以支持多个限定池

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local RewardDisplay = require("Game.RewardDisplay")
local GachaResult = require("Game.RecruitUI.GachaResult")
local HeroAvatar = require("Game.HeroAvatar")

local LimitedPool = {}

-- 兼容 init.lua 调用，无实际逻辑
LimitedPool.StopArtworkAnim = function() end

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取限定池主题色（从英雄颜色派生）
local function GetThemeColor(bannerCfg)
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == bannerCfg.heroId then
            return td.color  -- { r, g, b }
        end
    end
    return { 130, 210, 255 }
end

--- 获取英雄名称
local function GetHeroName(heroId)
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then return td.name end
    end
    return heroId
end

--- 格式化解锁日期为 "M月D日"
local function FormatUnlockDate(dateStr)
    if not dateStr then return "" end
    local _, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
    if m then return tonumber(m) .. "月" .. tonumber(d) .. "日" end
    return dateStr
end

-- ============================================================================
-- 货币栏
-- ============================================================================

--- 限定池货币栏
---@param UI any
---@param bannerCfg table
---@return any
function LimitedPool.CreateTokenBar(UI, bannerCfg)
    local LBD    = require("Game.LimitedBannerData")
    local tokens = LBD.GetTokens(bannerCfg)
    local pityCount = LBD.GetPityCount(bannerCfg)
    local pityMax   = bannerCfg.pity
    local safeTop   = (UI.GetSafeAreaInsets().top or 0)

    local rightLabel
    if LBD.IsLocked(bannerCfg) then
        local days = LBD.GetUnlockDaysRemaining(bannerCfg)
        rightLabel = UI.Label {
            text = FormatUnlockDate(bannerCfg.unlockDate) .. "开放",
            fontSize = 12,
            fontColor = { 220, 180, 80, 220 },
        }
    else
        local remaining = LBD.GetRemainingDays(bannerCfg)
        rightLabel = UI.Label {
            text = remaining > 0 and ("剩余" .. remaining .. "天") or "已结束",
            fontSize = 12,
            fontColor = remaining > 0 and { 130, 210, 255, 180 } or { 255, 100, 100, 200 },
        }
    end

    local tc = GetThemeColor(bannerCfg)
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
                    Currency.IconWidget(UI, bannerCfg.currency, 18),
                    UI.Label {
                        text = (Config.CURRENCY[bannerCfg.currency] and Config.CURRENCY[bannerCfg.currency].name or bannerCfg.currency) .. ": " .. tokens,
                        fontSize = 15,
                        fontColor = { tc[1], tc[2], tc[3], 255 },
                    },
                },
            },
            UI.Label {
                text = pityCount .. "/" .. pityMax .. "保底",
                fontSize = 12,
                fontColor = { 200, 220, 255, 200 },
            },
            rightLabel,
        },
    }
end

-- ============================================================================
-- 限定池横幅
-- ============================================================================

---@param UI any
---@param bannerCfg table
---@param showAdFrostFn function
---@param showAdTicketFn function
---@param showDetailFn function
---@return any
function LimitedPool.CreateBanner(UI, bannerCfg, showAdFrostFn, showAdTicketFn, showDetailFn)
    local LBD = require("Game.LimitedBannerData")

    local heroName = GetHeroName(bannerCfg.heroId)
    local tc       = GetThemeColor(bannerCfg)
    local isActive = LBD.IsActive(bannerCfg)
    local isLocked = LBD.IsLocked(bannerCfg)
    local avatarPath = bannerCfg.avatar or HeroAvatar.GetPath(bannerCfg.heroId or bannerCfg.id)

    local canClaimFrost  = LBD.CanClaimAdFrost(bannerCfg)

    -- ── 普通流内容（跟 NormalPool 一致，无 zIndex）──────────────────────────

    local flowChildren = {
        -- 标题
        UI.Label {
            text  = "限定祭坛",
            fontSize  = 28,
            fontColor = { tc[1], tc[2], tc[3], 255 },
            fontWeight = "bold",
            marginTop = 16, marginBottom = 4,
        },
        -- UP 英雄名
        UI.Panel {
            paddingLeft = 16, paddingRight = 16,
            paddingTop = 4,  paddingBottom = 4,
            backgroundColor = { 30, 60, 100, 200 },
            borderRadius = 8,
            borderWidth  = 1,
            borderColor  = { tc[1], tc[2], tc[3], 150 },
            children = {
                UI.Label {
                    text = "UP " .. heroName,
                    fontSize  = 18,
                    fontColor = { tc[1], tc[2], tc[3], 255 },
                    fontWeight = "bold",
                },
            },
        },
        -- 立绘区域（撑开剩余高度）
        UI.Panel {
            flex = 1, width = "100%",
            justifyContent = "center",
            alignItems    = "center",
            children = {
                UI.Panel {
                    width = 120, height = 150,
                    backgroundImage = avatarPath,
                    backgroundFit   = "contain",
                },
            },
        },
        -- 底部保底进度条（仅活跃期）
        not isLocked and UI.Panel {
            marginBottom = 12,
            width = "90%",
            flexDirection = "row",
            alignItems    = "center",
            justifyContent = "center",
            gap = 8,
            children = {
                UI.Panel {
                    flex = 1, height = 18,
                    backgroundColor = { 20, 30, 50, 220 },
                    borderRadius = 9, borderWidth = 1,
                    borderColor  = { 80, 140, 200, 150 },
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            position = "absolute",
                            top = 0, left = 0, bottom = 0,
                            width = math.floor(LBD.GetPityCount(bannerCfg) / bannerCfg.pity * 100) .. "%",
                            backgroundColor = { tc[1], tc[2], tc[3], 200 },
                            borderRadius = 9,
                        },
                        UI.Panel {
                            position = "absolute",
                            top = 0, left = 0, right = 0, bottom = 0,
                            justifyContent = "center", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = LBD.GetPityCount(bannerCfg) .. "/" .. bannerCfg.pity .. " 保底UR",
                                    fontSize = 10,
                                    fontColor = { 255, 255, 255, 230 },
                                    fontWeight = "bold",
                                },
                            },
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 3,
                    paddingLeft = 10, paddingRight = 10,
                    paddingTop  = 4,  paddingBottom = 4,
                    backgroundColor = { 0, 0, 0, 120 },
                    borderRadius = 12, borderWidth = 1,
                    borderColor  = { 100, 170, 220, 150 },
                    onClick = function() showDetailFn() end,
                    children = {
                        UI.Label { text = "详情", fontSize = 11, fontColor = { 160, 210, 255, 230 } },
                        UI.Label { text = ">",   fontSize = 11, fontColor = { 120, 170, 210, 180 } },
                    },
                },
            },
        } or nil,
    }

    -- ── 绝对层（按 DOM 顺序叠放，后面的在上层，无需 zIndex）──────────────

    -- 全屏立绘（仅部分池有）
    local artworkPanel = bannerCfg.artworkImage and UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage       = bannerCfg.artworkImage,
        backgroundFit         = "contain",
        backgroundPosition    = "center center",
        opacity = isLocked and 0.45 or 1.0,
        pointerEvents = "none",
    } or nil

    -- 锁定 / 结束遮罩
    local lockOverlay = nil
    if isLocked then
        local remainText = LBD.FormatUnlockRemaining(bannerCfg)
        lockOverlay = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center", alignItems = "center",
            gap = 10,
            children = {
                UI.Label { text = "🔒", fontSize = 40 },
                UI.Label {
                    text = FormatUnlockDate(bannerCfg.unlockDate) .. " 开放",
                    fontSize = 22,
                    fontColor  = { 220, 200, 80, 255 },
                    fontWeight = "bold",
                },
                remainText ~= "" and UI.Label {
                    text = remainText,
                    fontSize  = 15,
                    fontColor = { 200, 200, 200, 200 },
                } or nil,
            },
        }
    elseif not isActive then
        lockOverlay = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 160 },
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "限定池已结束",
                    fontSize  = 24,
                    fontColor = { 200, 200, 200, 200 },
                    fontWeight = "bold",
                },
            },
        }
    end

    -- 左侧：看广告领专属货币（锁定期也可使用）
    local adFrostBtn = UI.Panel {
        position = "absolute",
        left = 10, top = "40%",
        width = 52, height = 52,
        borderRadius = 12,
        backgroundColor = { 15, 30, 55, 220 },
        borderWidth = 2,
        borderColor = canClaimFrost and { tc[1], tc[2], tc[3], 220 } or { 50, 80, 110, 150 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function() showAdFrostFn() end,
        children = {
            Currency.IconWidget(UI, bannerCfg.currency, 28),
            UI.Panel {
                position = "absolute",
                bottom = -2, left = 0, right = 0,
                alignItems = "center",
                children = {
                    UI.Panel {
                        paddingLeft = 3, paddingRight = 3,
                        paddingTop  = 1, paddingBottom = 1,
                        backgroundColor = canClaimFrost and { 60, 180, 220, 255 } or { 40, 60, 80, 200 },
                        borderRadius = 4,
                        children = {
                            UI.Label {
                                text = "广告",
                                fontSize  = 9,
                                fontColor = canClaimFrost and { 10, 20, 30, 255 } or { 100, 120, 140, 180 },
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
            canClaimFrost and UI.Panel {
                position = "absolute",
                top = -2, right = -2,
                width = 10, height = 10,
                borderRadius = 5,
                backgroundColor = { 255, 60, 60, 255 },
            } or nil,
        },
    }

    -- ── 组装（普通流 → 全屏立绘 → 遮罩 → 货币按钮） ────────────────────────
    -- 绝对元素按 DOM 顺序叠放，无需 zIndex，与 NormalPool 完全一致
    local children = {}
    for _, v in ipairs(flowChildren) do children[#children + 1] = v end
    children[#children + 1] = artworkPanel   -- 全屏立绘（可 nil）
    children[#children + 1] = lockOverlay    -- 遮罩（可 nil）
    children[#children + 1] = adFrostBtn    -- 货币按钮（可 nil）

    return UI.Panel {
        width = "100%",
        flex  = 1,
        backgroundImage = bannerCfg.bannerBg or "image/limited_banner_bg.png",
        backgroundFit   = "cover",
        justifyContent  = "flex-start",
        alignItems      = "center",
        overflow        = "hidden",
        children        = children,
    }
end

-- ============================================================================
-- 按钮区
-- ============================================================================

---@param UI any
---@param bannerCfg table
---@param pageRoot any
---@param RARITY_COLORS table
---@param currentTab string
---@param refreshFn function
---@return any
function LimitedPool.CreateButtonArea(UI, bannerCfg, pageRoot, RARITY_COLORS, currentTab, refreshFn)
    local LBD    = require("Game.LimitedBannerData")
    local isLocked = LBD.IsLocked(bannerCfg)
    local isActive = LBD.IsActive(bannerCfg)
    local canSingle = isActive and LBD.CanAfford(bannerCfg, bannerCfg.singleCost)
    local canTen    = isActive and LBD.CanAfford(bannerCfg, bannerCfg.tenCost)
    local tc = GetThemeColor(bannerCfg)

    -- 锁定状态：只显示解锁倒计时，无招募按钮
    if isLocked then
        local remainText = LBD.FormatUnlockRemaining(bannerCfg)
        return UI.Panel {
            width = "100%",
            height = 56,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { 15, 20, 35, 230 },
            borderWidth = 1,
            borderColor = { 60, 80, 100, 120 },
            flexShrink = 0,
            children = {
                UI.Label {
                    text = FormatUnlockDate(bannerCfg.unlockDate) .. " 开放"
                        .. (remainText ~= "" and ("（" .. remainText .. "）") or ""),
                    fontSize = 16,
                    fontColor = { 220, 200, 80, 220 },
                    fontWeight = "bold",
                },
            },
        }
    end

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
        onClick = function()
            GachaResult.ShowBuyPopup(UI, pageRoot, 1, bannerCfg.currency, refreshFn)
        end,
        children = {
            Currency.IconWidget(UI, bannerCfg.currency, 22),
            UI.Label { text = "购买", fontSize = 10, fontColor = { tc[1], tc[2], tc[3], 200 } },
        },
    }

    -- 单抽
    buttons[#buttons + 1] = UI.Panel {
        flex = 1, height = 56,
        borderRadius = 10,
        backgroundColor = canSingle and { 30, 60, 100, 255 } or { 25, 30, 45, 200 },
        borderWidth = 1,
        borderColor = canSingle and { tc[1], tc[2], tc[3], 200 } or { 50, 60, 80, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function()
            if not isActive then
                local Toast = require("Game.Toast")
                Toast.Show("限定池已结束", { 255, 100, 100 })
                return
            end
            if canSingle then
                GachaResult.DoLimitedRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 1, refreshFn, bannerCfg)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 1, bannerCfg.currency, refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, bannerCfg.currency, 16),
                    UI.Label {
                        text = tostring(bannerCfg.singleCost),
                        fontSize = 14,
                        fontColor = { tc[1], tc[2], tc[3], 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募一次",
                fontSize = 14,
                fontColor = canSingle and { 255, 255, 255, 255 } or { 100, 110, 130, 180 },
                fontWeight = "bold",
            },
        },
    }

    -- 十连
    buttons[#buttons + 1] = UI.Panel {
        flex = 1, height = 56,
        borderRadius = 10,
        backgroundColor = canTen and { 40, 80, 140, 255 } or { 25, 30, 45, 200 },
        borderWidth = 1,
        borderColor = canTen and { tc[1], tc[2], tc[3], 220 } or { 50, 60, 80, 100 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        onClick = function()
            if not isActive then
                local Toast = require("Game.Toast")
                Toast.Show("限定池已结束", { 255, 100, 100 })
                return
            end
            if canTen then
                GachaResult.DoLimitedRecruitAndShow(UI, pageRoot, RARITY_COLORS, currentTab, 10, refreshFn, bannerCfg)
            else
                GachaResult.ShowBuyPopup(UI, pageRoot, 10, bannerCfg.currency, refreshFn)
            end
        end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    Currency.IconWidget(UI, bannerCfg.currency, 16),
                    UI.Label {
                        text = tostring(bannerCfg.tenCost),
                        fontSize = 14,
                        fontColor = { tc[1], tc[2], tc[3], 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = "招募十次",
                fontSize = 14,
                fontColor = canTen and { 255, 255, 255, 255 } or { 100, 110, 130, 180 },
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

-- ============================================================================
-- 详情弹窗
-- ============================================================================

---@param UI any
---@param pageRoot any
---@param bannerCfg table
---@param RARITY_COLORS table
---@param RARITY_BG table
function LimitedPool.ShowDetailPopup(UI, pageRoot, bannerCfg, RARITY_COLORS, RARITY_BG)
    if not pageRoot or not UI then return end

    local old = pageRoot:FindById("limitedDetailPopup")
    if old then pageRoot:RemoveChild(old) end

    local LBD      = require("Game.LimitedBannerData")
    local heroName = GetHeroName(bannerCfg.heroId)
    local tc       = GetThemeColor(bannerCfg)
    local listChildren = {}

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
        borderColor = { tc[1], tc[2], tc[3], 200 },
        children = {
            UI.Panel {
                width = 36, height = 20,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { tc[1], tc[2], tc[3], 255 },
                borderRadius = 4, marginRight = 8,
                children = {
                    UI.Label { text = "UP", fontSize = 10, fontColor = { 10, 20, 40, 255 }, fontWeight = "bold" },
                },
            },
            UI.Panel {
                width = 36, height = 20,
                justifyContent = "center", alignItems = "center",
                backgroundColor = RARITY_COLORS["UR"],
                borderRadius = 4, marginRight = 8,
                children = {
                    UI.Label { text = "UR", fontSize = 10, fontColor = { 20, 16, 32, 255 } },
                },
            },
            UI.Label { text = heroName, fontSize = 15, fontColor = { tc[1], tc[2], tc[3], 255 }, fontWeight = "bold", flex = 1 },
            UI.Label { text = "限定专属", fontSize = 11, fontColor = { tc[1], tc[2], tc[3], 200 } },
        },
    }

    -- 锁定提示
    if LBD.IsLocked(bannerCfg) then
        listChildren[#listChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 8, paddingBottom = 8,
            paddingLeft = 12, paddingRight = 12,
            marginBottom = 6,
            backgroundColor = { 60, 50, 20, 200 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { 220, 180, 60, 150 },
            alignItems = "center",
            children = {
                UI.Label {
                    text = "🔒 " .. FormatUnlockDate(bannerCfg.unlockDate) .. " 正式开放，敬请期待",
                    fontSize = 13,
                    fontColor = { 220, 200, 80, 255 },
                },
            },
        }
    end

    -- 技能说明
    local skills = Config.HERO_SKILLS and Config.HERO_SKILLS[bannerCfg.heroId]
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
                            UI.Label { text = skill.name, fontSize = 13, fontColor = { 200, 220, 255, 255 }, fontWeight = "bold" },
                        },
                    },
                    UI.Label { text = skill.desc, fontSize = 11, fontColor = { 160, 180, 210, 200 } },
                },
            }
        end
    end

    -- 分割线
    listChildren[#listChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 60, 100, 150, 100 },
        alignSelf = "center", marginTop = 8, marginBottom = 8,
    }

    -- 概率信息
    local rates     = bannerCfg.rates
    local rateOrder = { "LR", "UR", "SSR", "SR", "R", "N" }
    local rateLabels = {}
    for _, r in ipairs(rateOrder) do
        if rates[r] then
            rateLabels[#rateLabels + 1] = UI.Panel {
                paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                backgroundColor = { RARITY_COLORS[r][1], RARITY_COLORS[r][2], RARITY_COLORS[r][3], 40 },
                borderRadius = 4,
                children = {
                    UI.Label { text = r .. " " .. rates[r] .. "%", fontSize = 12, fontColor = RARITY_COLORS[r] },
                },
            }
        end
    end
    listChildren[#listChildren + 1] = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        justifyContent = "center", gap = 6, paddingBottom = 6,
        children = rateLabels,
    }
    listChildren[#listChildren + 1] = UI.Label {
        text = bannerCfg.pity .. "抽保底UR限定英雄 / 十连保底SSR",
        fontSize = 11, fontColor = { 150, 180, 210, 200 },
        alignSelf = "center", marginBottom = 6,
    }
    listChildren[#listChildren + 1] = UI.Label {
        text = "UR品质必定为限定英雄，提前获得后保底计数重置",
        fontSize = 10, fontColor = { 130, 160, 190, 160 },
        alignSelf = "center", marginBottom = 10,
    }

    -- 分割线
    listChildren[#listChildren + 1] = UI.Panel {
        width = "90%", height = 1,
        backgroundColor = { 60, 100, 150, 100 },
        alignSelf = "center", marginBottom = 10,
    }

    -- 非限定英雄列表
    local rarityOrder2 = { "LR", "SSR", "SR", "R", "N" }
    for _, rarity in ipairs(rarityOrder2) do
        local pool = bannerCfg.fallbackPool[rarity]
        if pool then
            local fragRange = Config.RECRUIT_FRAGMENT_DROP[rarity]
            for _, heroId in ipairs(pool) do
                local hName = GetHeroName(heroId)
                local hColor = { 200, 200, 200 }
                for _, td in ipairs(Config.TOWER_TYPES) do
                    if td.id == heroId then hColor = td.color; break end
                end
                local h       = HeroData.Get(heroId)
                local frags   = h and h.fragments or 0
                local unlocked = h and h.unlocked or false
                listChildren[#listChildren + 1] = UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    paddingTop = 5, paddingBottom = 5, paddingLeft = 10, paddingRight = 10,
                    marginBottom = 2,
                    backgroundColor = RARITY_BG[rarity],
                    borderRadius = 6,
                    children = {
                        UI.Panel {
                            width = 36, height = 18, justifyContent = "center", alignItems = "center",
                            backgroundColor = RARITY_COLORS[rarity], borderRadius = 4, marginRight = 8,
                            children = { UI.Label { text = rarity, fontSize = 10, fontColor = { 20, 16, 32, 255 } } },
                        },
                        UI.Label { text = hName, fontSize = 12, fontColor = hColor, flex = 1 },
                        UI.Label {
                            text = fragRange.min .. "~" .. fragRange.max,
                            fontSize = 10, fontColor = { 150, 140, 170, 180 }, marginRight = 6,
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
            UI.Panel {
                width = "100%", alignItems = "center",
                paddingTop = 14, paddingBottom = 10,
                flexShrink = 0,
                backgroundColor = { 15, 25, 45, 255 },
                borderWidth = 1, borderColor = { 60, 120, 180, 120 },
                children = {
                    UI.Label {
                        text = "限定祭坛 · " .. GetHeroName(bannerCfg.heroId),
                        fontSize = 18,
                        fontColor = { tc[1], tc[2], tc[3], 255 },
                        fontWeight = "bold",
                    },
                },
            },
            UI.ScrollView {
                width = "100%", flex = 1,
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 10, paddingRight = 10,
                children = listChildren,
            },
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 10, paddingLeft = 12, paddingRight = 12,
                flexShrink = 0,
                backgroundColor = { 15, 25, 45, 255 },
                borderWidth = 1, borderColor = { 60, 120, 180, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        paddingLeft = 14, paddingRight = 18, paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 30, 60, 100, 255 },
                        borderRadius = 8, borderWidth = 1, borderColor = { 80, 150, 220, 150 },
                        onClick = function()
                            local p = pageRoot:FindById("limitedDetailPopup")
                            if p then pageRoot:RemoveChild(p) end
                        end,
                        children = {
                            UI.Label { text = "<", fontSize = 14, fontColor = { 130, 180, 220, 200 } },
                            UI.Label { text = "返回", fontSize = 14, fontColor = { 160, 210, 255, 255 } },
                        },
                    },
                },
            },
        },
    }
    pageRoot:AddChild(popup)
end

-- ============================================================================
-- 广告领取弹窗
-- ============================================================================

---@param UI any
---@param pageRoot any
---@param bannerCfg table
---@param refreshFn function
function LimitedPool.ShowAdFrostDialog(UI, pageRoot, bannerCfg, refreshFn)
    if not pageRoot or not UI then return end
    local LBD = require("Game.LimitedBannerData")

    local old = pageRoot:FindById("adFrostPopup")
    if old then pageRoot:RemoveChild(old) end

    local canClaim     = LBD.CanClaimAdFrost(bannerCfg)
    local remaining    = LBD.GetAdFrostRemaining(bannerCfg)
    local dailyMax     = LBD.GetAdFrostDailyMax()
    local amount       = LBD.GetAdFrostAmount()
    local currencyDef  = Config.CURRENCY[bannerCfg.currency]
    local currencyName = currencyDef and currencyDef.name or bannerCfg.currency

    local function closePopup()
        local p = pageRoot:FindById("adFrostPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    local popup = UI.Panel {
        id = "adFrostPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function() closePopup() end,
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = { 15, 25, 50, 245 },
                borderRadius = 14, borderWidth = 1, borderColor = { 80, 180, 240, 180 },
                paddingTop = 16, paddingBottom = 16, paddingLeft = 20, paddingRight = 20,
                gap = 14, alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    UI.Label { text = "广告" .. currencyName, fontSize = 18, fontColor = { 100, 210, 255, 255 }, fontWeight = "bold" },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 180, 240, 60 } },
                    UI.Panel {
                        width = 72, height = 72, borderRadius = 12,
                        backgroundColor = { 20, 40, 70, 255 },
                        borderWidth = 2, borderColor = { 80, 170, 230, 200 },
                        justifyContent = "center", alignItems = "center",
                        children = { Currency.IconWidget(UI, bannerCfg.currency, 40) },
                    },
                    UI.Label { text = currencyName .. " x" .. amount, fontSize = 16, fontColor = { 130, 220, 255, 255 }, fontWeight = "bold" },
                    UI.Label {
                        text = "今日剩余 " .. remaining .. "/" .. dailyMax .. " 次",
                        fontSize = 13,
                        fontColor = canClaim and { 160, 200, 230, 220 } or { 120, 100, 100, 200 },
                    },
                    canClaim and UI.Panel {
                        width = "100%", height = 42,
                        borderRadius = 8,
                        backgroundColor = { 60, 160, 220 },
                        borderWidth = 1, borderColor = { 100, 200, 255, 180 },
                        flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 6,
                        onClick = function()
                            local AdHelper = require("Game.AdHelper")
                            AdHelper.ShowRewardAd(function()
                                local gained = LBD.ClaimAdFrost(bannerCfg)
                                closePopup()
                                refreshFn()
                                local def = Config.CURRENCY[bannerCfg.currency]
                                RewardDisplay.Show(UI, pageRoot, {
                                    title = "广告契约",
                                    rewards = {
                                        { icon = def and def.image or "?", name = def and def.name or currencyName, amount = gained },
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
                            UI.Label { text = "看广告领取", fontSize = 14, fontColor = { 10, 20, 40 }, fontWeight = "bold" },
                        },
                    } or UI.Panel {
                        width = "100%", height = 42,
                        borderRadius = 8,
                        backgroundColor = { 40, 50, 65, 200 },
                        borderWidth = 1, borderColor = { 60, 70, 85, 120 },
                        justifyContent = "center", alignItems = "center",
                        children = { UI.Label { text = "今日已达上限", fontSize = 14, fontColor = { 100, 120, 140, 180 } } },
                    },
                    UI.Button {
                        text = "关闭", fontSize = 13, variant = "outline",
                        width = "100%", height = 34, borderRadius = 8,
                        onClick = function() closePopup() end,
                    },
                },
            },
        },
    }
    pageRoot:AddChild(popup)
end

-- ============================================================================
-- 广告领取招募券弹窗
-- ============================================================================

---@param UI any
---@param pageRoot any
---@param bannerCfg table
---@param refreshFn function
function LimitedPool.ShowAdTicketDialog(UI, pageRoot, bannerCfg, refreshFn)
    if not pageRoot or not UI then return end
    local LBD = require("Game.LimitedBannerData")

    local old = pageRoot:FindById("adTicketPopup")
    if old then pageRoot:RemoveChild(old) end

    local canClaim  = LBD.CanClaimAdTicket(bannerCfg)
    local remaining = LBD.GetAdTicketRemaining()
    local dailyMax  = LBD.GetAdTicketDailyMax()
    local amount    = LBD.GetAdTicketAmount()

    local function closePopup()
        local p = pageRoot:FindById("adTicketPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    local popup = UI.Panel {
        id = "adTicketPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function() closePopup() end,
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = { 22, 16, 40, 245 },
                borderRadius = 14, borderWidth = 1, borderColor = { 180, 120, 255, 180 },
                paddingTop = 16, paddingBottom = 16, paddingLeft = 20, paddingRight = 20,
                gap = 14, alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    UI.Label { text = "广告招募券", fontSize = 18, fontColor = { 200, 150, 255, 255 }, fontWeight = "bold" },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 180, 120, 255, 60 } },
                    UI.Panel {
                        width = 72, height = 72, borderRadius = 12,
                        backgroundColor = { 30, 20, 50, 255 },
                        borderWidth = 2, borderColor = { 160, 100, 220, 200 },
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 48, height = 48,
                                backgroundImage = "image/icon_recruit_ticket_select_box.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    UI.Label { text = "招募券自选包 x" .. amount, fontSize = 16, fontColor = { 210, 170, 255, 255 }, fontWeight = "bold" },
                    UI.Label {
                        text = "今日剩余 " .. remaining .. "/" .. dailyMax .. " 次",
                        fontSize = 13,
                        fontColor = canClaim and { 180, 160, 220, 220 } or { 130, 100, 130, 200 },
                    },
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 40, 30, 60, 150 },
                        borderRadius = 8,
                        paddingTop = 8, paddingBottom = 8,
                        paddingLeft = 10, paddingRight = 10,
                        children = {
                            UI.Label {
                                text = "两个限定池共享每日次数",
                                fontSize = 11,
                                fontColor = { 170, 150, 200, 200 },
                            },
                        },
                    },
                    canClaim and UI.Panel {
                        width = "100%", height = 42,
                        borderRadius = 8,
                        backgroundColor = { 140, 90, 200 },
                        borderWidth = 1, borderColor = { 200, 150, 255, 180 },
                        flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 6,
                        onClick = function()
                            local AdHelper = require("Game.AdHelper")
                            AdHelper.ShowRewardAd(function()
                                local gained = LBD.ClaimAdTicket(bannerCfg)
                                closePopup()
                                refreshFn()
                                local def = Config.CURRENCY["recruit_ticket_select_box"]
                                RewardDisplay.Show(UI, pageRoot, {
                                    title = "广告招募券",
                                    rewards = {
                                        { icon = def and def.image or "image/icon_recruit_ticket_select_box.png", name = "招募券自选包", amount = gained },
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
                            UI.Label { text = "看广告领取", fontSize = 14, fontColor = { 255, 240, 255 }, fontWeight = "bold" },
                        },
                    } or UI.Panel {
                        width = "100%", height = 42,
                        borderRadius = 8,
                        backgroundColor = { 50, 40, 65, 200 },
                        borderWidth = 1, borderColor = { 70, 60, 85, 120 },
                        justifyContent = "center", alignItems = "center",
                        children = { UI.Label { text = "今日已达上限", fontSize = 14, fontColor = { 110, 100, 130, 180 } } },
                    },
                    UI.Button {
                        text = "关闭", fontSize = 13, variant = "outline",
                        width = "100%", height = 34, borderRadius = 8,
                        onClick = function() closePopup() end,
                    },
                },
            },
        },
    }
    pageRoot:AddChild(popup)
end

return LimitedPool
