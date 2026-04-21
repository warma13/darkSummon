-- Game/DungeonUI/init.lua
-- 副本页面入口 - 管理共享状态、路由视图、构建副本列表

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local TrialTowerData = require("Game.TrialTowerData")
local RD = require("Game.ResourceDungeonData")
local WB = require("Game.WorldBossData")
local AbyssRift = require("Game.AbyssRiftDungeon")

local LB = require("Game.LeaderboardData")

-- 子模块（延迟 require，避免循环）
local TrialTower
local ResourceDungeon
local WorldBoss
local AbyssRiftMod

local DungeonUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil

-- 当前视图状态
local currentView = "list"  -- "list" | "tower" | "resource_list" | "resource_detail" | "world_boss_detail" | "abyss_rift_detail"
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

local function FormatNum(n)
    if n >= 10000 then return string.format("%.1f万", n / 10000) end
    return tostring(math.floor(n))
end

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
        for _, rd in ipairs(RD.DUNGEON_DEFS) do
            totalFree = totalFree + RD.GetFreeRemaining(rd.key)
            totalTicket = totalTicket + RD.GetTotalTicketCount(rd.key)
            totalAdRemain = totalAdRemain + RD.GetAdRemaining(rd.key)
        end
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
    elseif not isAvailable then
        if def.key == "world_boss" then
            progressText = "主线第" .. (def.unlockFloor or 20) .. "关解锁"
        elseif def.key == "abyss_rift" then
            progressText = "主线第" .. (def.unlockStage or 100) .. "关解锁"
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
        local rankText = rankCache.world_boss and ("  🏆 排名 第" .. rankCache.world_boss .. "名") or ""
        rewardChildren = {
            Currency.IconWidget(UI, "frost_pact", 13),
            UI.Label { text = "霜誓契约", fontSize = 11, fontColor = { 130, 210, 255 }, pointerEvents = "none" },
            UI.Label { text = " 最高" .. WB.FormatDamage(WB.GetBestDamage()), fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
            UI.Label { id = "worldBossRankLabel", text = rankText, fontSize = 11, fontColor = S.gold, pointerEvents = "none" },
        }
    elseif def.key == "abyss_rift" and isAvailable then
        rewardChildren = {
            Currency.IconWidget(UI, "rift_dust", 13),
            UI.Label { text = "裂隙之尘", fontSize = 11, fontColor = { 160, 120, 200 }, pointerEvents = "none" },
            UI.Label { text = " + ", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
            Currency.IconWidget(UI, "rune_seal", 13),
            UI.Label { text = "符文封印", fontSize = 11, fontColor = { 40, 200, 160 }, pointerEvents = "none" },
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
                paddingTop = 14, paddingBottom = 14,
                gap = 6,
                backgroundColor = bgImage and { 15, 12, 25, 160 } or nil,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = def.name,
                                fontSize = 17,
                                fontWeight = "bold",
                                fontColor = isAvailable and S.white or S.dim,
                                pointerEvents = "none",
                            },
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                borderRadius = 10,
                                backgroundColor = { progressColor[1], progressColor[2], progressColor[3], 40 },
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
                    },
                    UI.Label {
                        text = def.desc,
                        fontSize = 12,
                        fontColor = S.dim,
                        pointerEvents = "none",
                    },
                    #rewardChildren > 0 and UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        marginTop = 2,
                        children = rewardChildren,
                    } or nil,
                    (def.key == "tower" and isAvailable) and UI.Panel {
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
                    } or nil,
                    (def.key == "resource" and isAvailable) and UI.Panel {
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
                    } or nil,
                },
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
