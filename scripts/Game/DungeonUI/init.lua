-- Game/DungeonUI/init.lua
-- 副本页面入口 - 管理共享状态、路由视图、构建副本列表

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local TrialTowerData = require("Game.TrialTowerData")
local RD = require("Game.ResourceDungeonData")
local WB = require("Game.WorldBossData")
local AbyssRift = require("Game.AbyssRiftDungeon")
local EmeraldDungeonData = require("Game.EmeraldDungeonData")
local FormatNum = require("Game.FormatUtil").FormatNum

local LB = require("Game.LeaderboardData")

-- 子模块（延迟 require，避免循环）
local TrialTower
local ResourceDungeon
local WorldBoss
local AbyssRiftMod
local EmeraldDungeonMod

local DungeonUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

-- 当前视图状态
local currentView = "list"  -- "list" | "tower" | "resource_list" | "resource_detail" | "world_boss_detail" | "abyss_rift_detail" | "emerald_dungeon_detail"
local currentResourceKey = nil  -- 当前选中的资源副本 key

-- 严格点击判定：拖动超过阈值不触发 onClick
-- 用法：在 UI.Panel 中用 MakeTapClick(action) 展开替代 onClick
local _tapPressX, _tapPressY = 0, 0
local TAP_THRESHOLD = 10  -- 像素，超过此距离视为拖动

local function MakeTapClick(action)
    return {
        onPointerDown = function(event)
            _tapPressX = event.x
            _tapPressY = event.y
        end,
        onPointerUp = function(event)
            local dx = event.x - _tapPressX
            local dy = event.y - _tapPressY
            if dx * dx + dy * dy <= TAP_THRESHOLD * TAP_THRESHOLD then
                action()
            end
        end,
    }
end

-- 排名缓存（异步加载后更新 UI）
local rankCache = {
    tower = nil,
    dungeon = nil,
    world_boss = nil,
    -- 世界BOSS按难度每日排名：wb_diff_0/1/3/9（0=未上榜）
    wb_diff_0 = 0,
    wb_diff_1 = 0,
    wb_diff_3 = 0,
    wb_diff_9 = 0,
}

-- ============================================================================
-- 配色（共享）
-- ============================================================================
local S = {
    pageBg       = { 15, 12, 25, 255 },
    headerBg     = { 28, 20, 45, 255 },
    cardBg       = { 30, 24, 48, 240 },
    cardBorder   = { 70, 55, 100, 120 },
    cardHover    = { 45, 36, 68, 255 },
    towerAccent  = { 140, 100, 220, 255 },
    dailyAccent  = { 220, 160, 40, 255 },
    arenaAccent  = { 60, 180, 220, 255 },
    dreamAccent  = { 200, 80, 160, 255 },
    clearedBg    = { 45, 70, 45, 220 },
    clearedBorder= { 80, 140, 80, 180 },
    currentBg    = { 70, 45, 120, 255 },
    currentBorder= { 140, 100, 220, 255 },
    lockedBg     = { 35, 30, 50, 180 },
    lockedBorder = { 55, 45, 70, 100 },
    white        = { 245, 238, 225, 255 },
    dim          = { 150, 140, 160, 200 },
    gold         = { 255, 215, 80, 255 },
    green        = { 120, 220, 100, 255 },
    purple       = { 160, 120, 240, 255 },
    red          = { 220, 80, 80, 255 },
    btnPrimary   = { 100, 60, 200, 255 },
    btnDisabled  = { 50, 40, 70, 200 },
    comingSoon   = { 80, 70, 95, 200 },
}

-- ============================================================================
-- 副本定义
-- ============================================================================
local DUNGEON_DEFS = {
    {
        key = "emerald_dungeon",
        name = "翠影秘境",
        nameIcon = "image/emerald_certificate.png",
        desc = "限时活动：通关获取翠影凭证，兑换翎嫣招募券与稀有资源",
        accentColor = { 60, 180, 100, 255 },
        available = true,
        cover = "image/emerald_dungeon_banner.png",
        isEvent = true,
    },
    {
        key = "tower",
        name = "试练塔",
        desc = "逐层挑战，获取噬魂石与冥晶",
        accentColor = S.towerAccent,
        available = true,
        cover = "image/dungeon_trial_tower.png",
    },
    {
        key = "resource",
        name = "资源副本",
        desc = "挑战Boss，获取冥晶、噬魂石、锻魂铁和宝箱",
        accentColor = S.dailyAccent,
        available = true,
        cover = "image/dungeon_resource_cover.png",
    },
    {
        key = "world_boss",
        name = "世界BOSS",
        desc = "挑战深渊主宰，按伤害获取霜誓契约",
        accentColor = { 180, 50, 70, 255 },
        available = true,
        cover = "image/dungeon_world_boss_20260414134349.png",
        unlockFloor = 20,
    },
    {
        key = "abyss_rift",
        name = "深渊裂隙",
        desc = "探索裂隙深处，获取符文与洗练材料",
        accentColor = { 160, 80, 220, 255 },
        available = true,
        cover = "image/banner_abyss_rift_20260415162859.png",
        unlockStage = 20,
    },
}

-- ============================================================================
-- 辅助
-- ============================================================================

-- FormatNum → 使用 FormatUtil.FormatNum

-- ============================================================================
-- 公共访问器（供子模块使用）
-- ============================================================================

function DungeonUI.GetUI() return UI end
function DungeonUI.GetPageRoot() return pageRoot end
function DungeonUI.GetS() return S end
function DungeonUI.FormatNum(n) return FormatNum(n) end
function DungeonUI.GetRankCache() return rankCache end

function DungeonUI.SetView(view, resourceKey)
    currentView = view
    if resourceKey ~= nil then currentResourceKey = resourceKey end
    DungeonUI.Refresh()
end

function DungeonUI.GetCurrentResourceKey() return currentResourceKey end

-- ============================================================================
-- 页面创建 & 刷新
-- ============================================================================

function DungeonUI.CreatePage(uiModule)
    UI = uiModule

    -- 延迟加载子模块
    if not TrialTower then
        TrialTower = require("Game.DungeonUI.TrialTower")
        ResourceDungeon = require("Game.DungeonUI.ResourceDungeon")
        WorldBoss = require("Game.DungeonUI.WorldBoss")
        AbyssRiftMod = require("Game.DungeonUI.AbyssRift")
        EmeraldDungeonMod = require("Game.DungeonUI.EmeraldDungeon")
    end

    pageRoot = UI.Panel {
        id = "dungeonPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = S.pageBg,
        children = {},
    }

    DungeonUI.Refresh()
    return pageRoot
end

function DungeonUI.Refresh()
    if not pageRoot or not UI then return end
    pageRoot:ClearChildren()

    if currentView == "list" then
        DungeonUI.BuildListView()
        DungeonUI.FetchRanks()
    elseif currentView == "tower" then
        TrialTower.BuildDetailView(DungeonUI)
    elseif currentView == "resource_list" then
        ResourceDungeon.BuildListView(DungeonUI)
    elseif currentView == "resource_detail" then
        ResourceDungeon.BuildDetailView(DungeonUI)
    elseif currentView == "world_boss_detail" then
        WorldBoss.BuildDetailView(DungeonUI)
    elseif currentView == "abyss_rift_detail" then
        AbyssRiftMod.BuildDetailView(DungeonUI)
    elseif currentView == "emerald_dungeon_detail" then
        EmeraldDungeonMod.BuildDetailView(DungeonUI)
    end
end

--- 异步加载排名
function DungeonUI.FetchRanks()
    if not clientCloud then return end

    LB.FetchMyRank(LB.KEY_TOWER, function(rank, score)
        rankCache.tower = rank
        if pageRoot and currentView == "list" then
            local label = pageRoot:FindById("towerRankLabel")
            if label then
                label:SetText(rank and ("排名 第" .. rank .. "名") or "未上榜")
            end
        end
    end)

    LB.FetchMyRank(LB.KEY_DUNGEON, function(rank, score)
        rankCache.dungeon = rank
        if pageRoot and currentView == "list" then
            local label = pageRoot:FindById("dungeonRankLabel")
            if label then
                label:SetText(rank and ("排名 第" .. rank .. "名") or "未上榜")
            end
        end
    end)

    LB.FetchMyRank(LB.KEY_WORLD_BOSS, function(rank, score)
        rankCache.world_boss = rank
        if pageRoot and currentView == "list" then
            local label = pageRoot:FindById("worldBossRankLabel")
            if label then
                label:SetText(rank and ("  🏆 排名 第" .. rank .. "名") or "")
            end
        end
    end)

    -- 世界BOSS按难度的每日排名
    local diffLabels = { [0] = "普通", [1] = "困难", [3] = "噩梦", [9] = "地狱" }
    for _, dl in ipairs(LB.WB_DIFF_LEVELS) do
        local dailyKey = LB.GetWorldBossDiffDailyKey(dl)
        local cacheKey = "wb_diff_" .. dl
        LB.FetchMyRank(dailyKey, function(rank, score)
            -- 无有效分数时视为未上榜（API 可能对 score=0 也返回 rank=1）
            local validRank = (score and score > 0 and rank) and rank or 0
            rankCache[cacheKey] = validRank
            if pageRoot and currentView == "list" then
                local label = pageRoot:FindById("wbDiffRank_" .. dl)
                if label then
                    label:SetText(diffLabels[dl] .. " #" .. validRank)
                end
            end
        end)
    end
end

-- ============================================================================
-- 一级页面：副本列表
-- ============================================================================

function DungeonUI.BuildListView()
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = S.headerBg,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "副本",
                fontSize = 20,
                fontWeight = "bold",
                fontColor = S.white,
                pointerEvents = "none",
            },
        },
    })

    local cards = {}
    for _, def in ipairs(DUNGEON_DEFS) do
        cards[#cards + 1] = DungeonUI.BuildDungeonCard(def)
    end

    pageRoot:AddChild(UI.ScrollView {
        width = "100%",
        flex = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                paddingTop = 6, paddingBottom = 6,
                paddingLeft = 12, paddingRight = 12,
                gap = 10,
                children = cards,
            },
        },
    })
end

--- 构建单个副本卡片
function DungeonUI.BuildDungeonCard(def)
    local isAvailable = def.available

    if def.key == "world_boss" then
        local State = require("Game.State")
        if (State.currentStage or 1) < (def.unlockFloor or 20) then
            isAvailable = false
        end
    end

    if def.key == "abyss_rift" then
        if not AbyssRift.IsUnlocked() then
            isAvailable = false
        end
    end

    if def.key == "emerald_dungeon" then
        -- 活动副本始终可用（内部检查活动时间）
        isAvailable = EmeraldDungeonData.IsActive()
    end

    -- 进度信息
    local progressText = ""
    local progressColor = S.dim
    if def.key == "tower" and isAvailable then
        local data = TrialTowerData.GetData()
        local towerNum = TrialTowerData.GetTowerNum(data.currentFloor)
        local floorInTower = TrialTowerData.GetFloorInTower(data.currentFloor)
        progressText = "第" .. towerNum .. "塔 · " .. (floorInTower - 1) .. "/10"
        progressColor = S.gold
    elseif def.key == "resource" and isAvailable then
        local totalFree, totalTicket, totalAdRemain = 0, 0, 0
        local InventoryData = require("Game.InventoryData")
        local genericTickets = InventoryData.GetCount("dungeon_ticket")
        for _, rd in ipairs(RD.DUNGEON_DEFS) do
            totalFree = totalFree + RD.GetFreeRemaining(rd.key)
            local specific = RD.GetDungeonTicketCount(rd.key)
            totalTicket = totalTicket + specific
            totalAdRemain = totalAdRemain + RD.GetAdRemaining(rd.key)
        end
        totalTicket = totalTicket + genericTickets
        local totalRemain = totalFree + totalTicket
        if totalTicket > 0 then
            progressText = "免费" .. totalFree .. " 券" .. totalTicket
        elseif totalFree > 0 then
            progressText = "免费 " .. totalFree .. "/" .. (#RD.DUNGEON_DEFS * RD.FREE_ATTEMPTS)
        elseif totalAdRemain > 0 then
            progressText = "可领券" .. totalAdRemain
        else
            progressText = "已用完"
        end
        progressColor = totalRemain > 0 and S.green or (totalAdRemain > 0 and S.gold or S.red)
    elseif def.key == "world_boss" and isAvailable then
        local remaining = WB.GetRemainingAttempts()
        progressText = "今日 " .. remaining .. "/" .. WB.DAILY_ATTEMPTS
        progressColor = remaining > 0 and S.green or S.red
    elseif def.key == "abyss_rift" and isAvailable then
        local remaining = AbyssRift.GetRemaining()
        progressText = "今日 " .. remaining .. "/" .. AbyssRift.DAILY_FREE
        progressColor = remaining > 0 and S.green or S.red
    elseif def.key == "emerald_dungeon" and isAvailable then
        local tickets = EmeraldDungeonData.GetTickets()
        local adLeft = EmeraldDungeonData.GetAdRemaining()
        local remainDays = EmeraldDungeonData.GetRemainingDays()
        progressText = tickets .. "券 · 可领" .. adLeft .. " · 剩余" .. remainDays .. "天"
        progressColor = tickets > 0 and S.green or (adLeft > 0 and S.gold or S.red)
    elseif not isAvailable then
        if def.key == "world_boss" then
            progressText = "主线第" .. (def.unlockFloor or 20) .. "关解锁"
        elseif def.key == "abyss_rift" then
            progressText = "主线第" .. (def.unlockStage or 100) .. "关解锁"
        elseif def.key == "emerald_dungeon" then
            if not EmeraldDungeonData.IsTimeUnlocked() then
                local sec = EmeraldDungeonData.GetUnlockRemainingSec()
                local h = math.floor(sec / 3600)
                local m = math.floor((sec % 3600) / 60)
                progressText = string.format("%s 开启 %d时%d分", EmeraldDungeonData.GetUnlockTimeStr(), h, m)
            else
                progressText = "活动已结束"
            end
        else
            progressText = "即将开放"
        end
        progressColor = S.comingSoon
    end

    local accentColor = isAvailable and def.accentColor or S.comingSoon

    -- 奖励预览
    local rewardChildren = {}
    if def.key == "tower" and isAvailable then
        local data = TrialTowerData.GetData()
        local towerNum = TrialTowerData.GetTowerNum(data.currentFloor)
        local stones, gold = TrialTowerData.GetFloorReward(towerNum)
        rewardChildren = {
            Currency.IconWidget(UI, "devour_stone", 13),
            UI.Label { text = FormatNum(stones), fontSize = 11, fontColor = { 60, 160, 80 }, pointerEvents = "none" },
            UI.Label { text = " + ", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
            Currency.IconWidget(UI, "nether_crystal", 13),
            UI.Label { text = FormatNum(gold), fontSize = 11, fontColor = { 140, 80, 200 }, pointerEvents = "none" },
        }
    elseif def.key == "resource" and isAvailable then
        rewardChildren = {
            Currency.IconWidget(UI, "nether_crystal", 13),
            Currency.IconWidget(UI, "devour_stone", 13),
            Currency.IconWidget(UI, "forge_iron", 13),
            UI.Panel {
                width = 13, height = 13,
                backgroundImage = "image/tab_chest.png",
                backgroundFit = "contain",
                pointerEvents = "none",
                flexShrink = 0,
            },
        }
    elseif def.key == "world_boss" and isAvailable then
        rewardChildren = {
            Currency.IconWidget(UI, "recruit_ticket_select_box", 13),
            UI.Label { text = "招募券自选包", fontSize = 11, fontColor = { 130, 210, 255 }, pointerEvents = "none" },
            UI.Label { text = " 最高" .. WB.FormatDamage(WB.GetBestDamage()), fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
        }
    elseif def.key == "abyss_rift" and isAvailable then
        rewardChildren = {
            Currency.IconWidget(UI, "rift_dust", 13),
            UI.Label { text = "裂隙之尘", fontSize = 11, fontColor = { 160, 120, 200 }, pointerEvents = "none" },
            UI.Label { text = " + ", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
            Currency.IconWidget(UI, "rune_seal", 13),
            UI.Label { text = "符文封印", fontSize = 11, fontColor = { 40, 200, 160 }, pointerEvents = "none" },
        }
    elseif def.key == "emerald_dungeon" and isAvailable then
        rewardChildren = {
            UI.Panel {
                width = 14, height = 14,
                backgroundImage = "image/emerald_certificate.png",
                backgroundFit = "contain",
                pointerEvents = "none", flexShrink = 0,
            },
            UI.Label { text = "翠影凭证", fontSize = 11, fontColor = { 100, 220, 140 }, pointerEvents = "none" },
            UI.Label { text = " → ", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
            Currency.IconWidget(UI, "linyan_oath", 13),
            UI.Label { text = "翎嫣之誓", fontSize = 11, fontColor = { 100, 220, 140 }, pointerEvents = "none" },
        }
    end

    local bgImage = def.cover

    return UI.Panel {
        width = "100%",
        aspectRatio = 16 / 9,
        flexDirection = "row",
        backgroundColor = isAvailable and S.cardBg or { 25, 20, 38, 180 },
        backgroundImage = bgImage,
        backgroundScaleMode = bgImage and "aspectFill" or nil,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = isAvailable and S.cardBorder or { 50, 42, 65, 80 },
        overflow = "hidden",
        onPointerDown = isAvailable and function(event)
            _tapPressX = event.x
            _tapPressY = event.y
        end or nil,
        onPointerUp = isAvailable and function(event)
            local dx = event.x - _tapPressX
            local dy = event.y - _tapPressY
            if dx * dx + dy * dy <= TAP_THRESHOLD * TAP_THRESHOLD then
                if def.key == "tower" then
                    currentView = "tower"
                    DungeonUI.Refresh()
                elseif def.key == "resource" then
                    currentView = "resource_list"
                    DungeonUI.Refresh()
                elseif def.key == "world_boss" then
                    currentView = "world_boss_detail"
                    DungeonUI.Refresh()
                elseif def.key == "abyss_rift" then
                    currentView = "abyss_rift_detail"
                    DungeonUI.Refresh()
                elseif def.key == "emerald_dungeon" then
                    currentView = "emerald_dungeon_detail"
                    DungeonUI.Refresh()
                end
            end
        end or nil,
        children = {
            UI.Panel {
                width = 5,
                height = "100%",
                backgroundColor = accentColor,
            },
            UI.Panel {
                flex = 1,
                flexDirection = "column",
                paddingLeft = 12, paddingRight = 14,
                paddingTop = 10, paddingBottom = 8,
                gap = 4,
                backgroundColor = bgImage and { 15, 12, 25, 160 } or nil,
                children = (function()
                    local rows = {}
                    -- 1. 主标题行（大字 + 底条）
                    local titleChildren = {}
                    if def.nameIcon then
                        titleChildren[#titleChildren + 1] = UI.Panel {
                            width = 22, height = 22,
                            backgroundImage = def.nameIcon,
                            backgroundFit = "contain",
                            pointerEvents = "none", flexShrink = 0,
                        }
                    end
                    titleChildren[#titleChildren + 1] = UI.Label {
                        text = def.name,
                        fontSize = 20,
                        fontWeight = "bold",
                        fontColor = isAvailable and { 255, 255, 255, 255 } or S.dim,
                        pointerEvents = "none",
                    }
                    if def.isEvent then
                        titleChildren[#titleChildren + 1] = UI.Panel {
                            paddingLeft = 5, paddingRight = 5,
                            paddingTop = 1, paddingBottom = 1,
                            borderRadius = 6,
                            backgroundColor = { 255, 255, 255, 40 },
                            children = {
                                UI.Label {
                                    text = "限时",
                                    fontSize = 10,
                                    fontColor = { 255, 255, 255, 220 },
                                    pointerEvents = "none",
                                },
                            },
                        }
                    end
                    rows[#rows + 1] = UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        alignSelf = "flex-start",
                        gap = 6,
                        paddingLeft = 8, paddingRight = 10,
                        paddingTop = 4, paddingBottom = 4,
                        borderRadius = 6,
                        backgroundColor = { accentColor[1], accentColor[2], accentColor[3], isAvailable and 160 or 80 },
                        children = titleChildren,
                    }
                    -- 2. 进度 badge 行
                    rows[#rows + 1] = UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = def.desc,
                                fontSize = 12,
                                fontColor = S.dim,
                                pointerEvents = "none",
                                flex = 1,
                                flexShrink = 1,
                            },
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                borderRadius = 10,
                                backgroundColor = { progressColor[1], progressColor[2], progressColor[3], 40 },
                                flexShrink = 0,
                                marginLeft = 6,
                                children = {
                                    UI.Label {
                                        text = progressText,
                                        fontSize = 11,
                                        fontColor = progressColor,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    }
                    -- 3. 奖励行
                    if #rewardChildren > 0 then
                        rows[#rows + 1] = UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 3,
                            marginTop = 2,
                            children = rewardChildren,
                        }
                    end
                    -- 4. 排名行（按副本类型）
                    if def.key == "tower" and isAvailable then
                        rows[#rows + 1] = UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 4,
                            marginTop = 2,
                            children = {
                                UI.Label {
                                    text = "🏆",
                                    fontSize = 11,
                                    pointerEvents = "none",
                                },
                                UI.Label {
                                    id = "towerRankLabel",
                                    text = rankCache.tower and ("排名 第" .. rankCache.tower .. "名") or "加载中...",
                                    fontSize = 11,
                                    fontColor = S.gold,
                                    pointerEvents = "none",
                                },
                            },
                        }
                    elseif def.key == "resource" and isAvailable then
                        rows[#rows + 1] = UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 4,
                            marginTop = 2,
                            children = {
                                UI.Label {
                                    text = "🏆",
                                    fontSize = 11,
                                    pointerEvents = "none",
                                },
                                UI.Label {
                                    id = "dungeonRankLabel",
                                    text = rankCache.dungeon and ("排名 第" .. rankCache.dungeon .. "名") or "加载中...",
                                    fontSize = 11,
                                    fontColor = S.gold,
                                    pointerEvents = "none",
                                },
                            },
                        }
                    elseif def.key == "world_boss" and isAvailable then
                        local diffInfo = {
                            { level = 0, label = "普通", color = { 150, 220, 150 } },
                            { level = 1, label = "困难", color = { 255, 220, 100 } },
                            { level = 3, label = "噩梦", color = { 255, 160, 80 } },
                            { level = 9, label = "地狱", color = { 255, 80, 80 } },
                        }
                        local rankWidgets = {}
                        for _, di in ipairs(diffInfo) do
                            local cacheKey = "wb_diff_" .. di.level
                            local r = rankCache[cacheKey]
                            local txt = di.label .. " #" .. (r or 0)
                            rankWidgets[#rankWidgets + 1] = UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 2,
                                paddingLeft = 4, paddingRight = 4,
                                paddingTop = 2, paddingBottom = 2,
                                borderRadius = 6,
                                backgroundColor = { di.color[1], di.color[2], di.color[3], 30 },
                                children = {
                                    UI.Label {
                                        id = "wbDiffRank_" .. di.level,
                                        text = txt,
                                        fontSize = 10,
                                        fontColor = di.color,
                                        pointerEvents = "none",
                                    },
                                },
                            }
                        end
                        rows[#rows + 1] = UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 4,
                            marginTop = 2,
                            children = rankWidgets,
                        }
                    end
                    return rows
                end)(),
            },
            isAvailable and UI.Panel {
                width = 30,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "›",
                        fontSize = 24,
                        fontColor = S.dim,
                        pointerEvents = "none",
                    },
                },
            } or nil,
        },
    }
end

return DungeonUI
