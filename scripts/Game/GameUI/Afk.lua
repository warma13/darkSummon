-- Game/GameUI/Afk.lua
-- 挂机系统：挂机按钮、挂机收益、离线奖励面板

return function(GameUI, ctx)

local Config         = require("Game.Config")
local Currency       = require("Game.Currency")
local HeroData       = require("Game.HeroData")
local ChestData      = require("Game.ChestData")
local Toast          = require("Game.Toast")
local LaunchGiftData       = require("Game.LaunchGiftData")
local DailyTaskData        = require("Game.DailyTaskData")
local MailboxData          = require("Game.MailboxData")
local RewardDisplay        = require("Game.RewardDisplay")
local ActivityData         = require("Game.ActivityData")
local AccumulatedRewardData = require("Game.AccumulatedRewardData")
local DailyDealData        = require("Game.DailyDealData")
local AdReliefData         = require("Game.AdReliefData")
local TodayStr = require("Game.DateUtil").TodayStr

local FormatNum = ctx.FormatNum

-- ============================================================================
-- 左侧挂机奖励入口（实时计时 + 点击领取）
-- ============================================================================

-- 挂机计时起点（使用引擎单调时钟，防止玩家改系统时间）
GameUI._afkStartTime = time.elapsedTime
-- 上次更新显示的秒数（避免每帧刷新文本）
GameUI._afkLastDisplaySec = -1

-- ============================================================================
-- 立即领取每日广告次数限制
-- ============================================================================
local AFK_AD_DAILY_MAX = 10

--- 重置每日计数（跨天）
local function ResetAfkAdIfNeeded()
    local stats = HeroData.stats
    local today = TodayStr()
    if stats.afkAdDate ~= today then
        stats.afkAdCount = 0
        stats.afkAdDate = today
    end
end

--- 今日剩余次数
local function GetAfkAdRemaining()
    ResetAfkAdIfNeeded()
    return math.max(0, AFK_AD_DAILY_MAX - (HeroData.stats.afkAdCount or 0))
end

--- 是否还能看广告立即领取
local function CanAfkAdClaim()
    return GetAfkAdRemaining() > 0
end

--- 记录一次广告领取
local function RecordAfkAdClaim()
    ResetAfkAdIfNeeded()
    HeroData.stats.afkAdCount = (HeroData.stats.afkAdCount or 0) + 1
end

--- 格式化挂机时长
---@param secs number
---@return string
local function FormatAfkTime(secs)
    secs = math.floor(secs)
    if secs >= 3600 then
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        return string.format("%dh%02dm", h, m)
    elseif secs >= 60 then
        local m = math.floor(secs / 60)
        local s = secs % 60
        return string.format("%dm%02ds", m, s)
    else
        return string.format("%ds", secs)
    end
end

--- 计算指定时长的挂机收益（基于当前关卡实际战斗掉落推算）
---@param seconds number 挂机秒数
---@return table rewards { seconds, nether_crystal, devour_stone, forge_iron, chestDrops }
local function CalcAfkRewardsByTime(seconds)
    -- 特权增益 + 神裔降临：挂机时长上限
    local PrivilegeData = require("Game.PrivilegeData")
    local DivineBlessDB = require("Game.DivineBlessData")
    local maxSeconds = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds() + DivineBlessDB.GetBuffValue("idle_extra")
    local capped = math.min(seconds, maxSeconds)
    local hours = capped / 3600

    -- 基于当前关卡的每关掉落估算
    local stage = HeroData.stats and HeroData.stats.bestStage or 1
    if stage < 1 then stage = 1 end
    local crystalPerStage, stonePerStage, ironPerStage = Config.EstimateStageDrop(stage)

    -- 挂机关数 = 挂机时长 / 一关平均时长 × 效率系数
    local stagesCleared = (capped / Config.IDLE_STAGE_SECONDS) * Config.IDLE_RATE

    -- 宝箱掉落
    local chestDrops = {}
    if Config.IDLE_CHEST_DROPS then
        for _, rule in ipairs(Config.IDLE_CHEST_DROPS) do
            if hours >= rule.minHours then
                for id, count in pairs(rule.chests) do
                    chestDrops[id] = (chestDrops[id] or 0) + count
                end
            end
        end
    end
    if Config.IDLE_CHEST_RANDOM then
        local fullHours = math.floor(hours)
        for _, rule in ipairs(Config.IDLE_CHEST_RANDOM) do
            for _ = 1, fullHours do
                if math.random() < rule.chancePerHour then
                    chestDrops[rule.id] = (chestDrops[rule.id] or 0) + 1
                end
            end
        end
    end

    -- 基础收益
    local crystal = math.floor(crystalPerStage * stagesCleared)
    local stone   = math.floor(stonePerStage * stagesCleared)
    local iron    = math.floor(ironPerStage * stagesCleared)

    -- 特权增益：冥晶+10%
    crystal = math.floor(crystal * PrivilegeData.GetCrystalBonusRate())

    -- 神裔降临：冥晶加成（周末磐古自动 / 工作日可选）
    local crystalMulti = DivineBlessDB.GetBuffValue("crystal_multi")
    if crystalMulti > 1.0 then
        crystal = math.floor(crystal * crystalMulti)
    end

    -- 特权增益：10%概率翻倍（预览不触发，仅实际领取时触发）

    -- 随机碎片箱掉落（每小时判定一次，掉落碎片箱道具）
    local fragmentBoxDrops = {}  -- { [itemId] = count }
    if Config.IDLE_FRAGMENT_RANDOM then
        local fullHours = math.floor(hours)
        for _, rule in ipairs(Config.IDLE_FRAGMENT_RANDOM) do
            for _ = 1, fullHours do
                if math.random() < rule.chancePerHour then
                    fragmentBoxDrops[rule.id] = (fragmentBoxDrops[rule.id] or 0) + 1
                end
            end
        end
    end

    return {
        seconds = capped,
        nether_crystal = crystal,
        devour_stone = stone,
        forge_iron = iron,
        chestDrops = chestDrops,
        fragmentBoxDrops = fragmentBoxDrops,
    }
end

--- 计算当前挂机收益（基于实时累计时间）
local function CalcAfkRewardsNow()
    local elapsed = time.elapsedTime - GameUI._afkStartTime
    return CalcAfkRewardsByTime(elapsed)
end

--- 创建左侧功能按钮组（招募 + 挂机）
function GameUI.CreateAfkButton()
    local btnSize = 56
    local sk = { 0, 0, 0, 255 }  -- 描边色

    --- 创建带黑边描边的文字（4方向偏移黑色 + 白色正文）
    local function outlineLabel(txt, fontSize, fc, panelId)
        local offsets = { {-1,0}, {1,0}, {0,-1}, {0,1} }
        local children = {}
        for _, o in ipairs(offsets) do
            children[#children + 1] = ctx.UI.Label {
                text = txt, fontSize = fontSize, fontColor = sk, fontWeight = "bold",
                position = "absolute", left = o[1], top = o[2],
                width = "100%", textAlign = "center",
            }
        end
        children[#children + 1] = ctx.UI.Label {
            text = txt, fontSize = fontSize, fontColor = fc, fontWeight = "bold",
            width = "100%", textAlign = "center",
        }
        return ctx.UI.Panel {
            id = panelId,
            position = "relative", width = "100%", alignItems = "center",
            children = children,
        }
    end

    return ctx.UI.Panel {
        id = "leftSideButtons",
        position = "absolute",
        left = 6, top = "30%",
        width = btnSize,
        flexDirection = "column",
        alignItems = "center",
        gap = 8,
        pointerEvents = "box-none",
        children = {
            -- 排行榜入口按钮
            ctx.UI.Panel {
                id = "leaderboardBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 220, 200, 60, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    local LeaderboardUI = require("Game.LeaderboardUI")
                    LeaderboardUI.Show()
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 40, 35, 20, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 32, height = 32,
                                backgroundImage = "image/icon_leaderboard.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("排行", 11, { 255, 220, 80 }) },
                    },
                },
            },
            -- 每日任务入口按钮
            ctx.UI.Panel {
                id = "dailyTaskBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 180, 120, 255, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowDailyTaskOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 40, 25, 60, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 32, height = 32,
                                backgroundImage = "image/icon_dailytask.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("任务", 11, { 200, 160, 255 }) },
                    },
                    -- 红点
                    ctx.UI.Panel {
                        id = "dailyTaskRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = DailyTaskData.HasClaimable(),
                    },
                },
            },
            -- 开服好礼入口按钮（不活跃时从布局中移除，避免留空位）
            LaunchGiftData.IsActive() and ctx.UI.Panel {
                id = "launchGiftBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 220, 180, 60, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowLaunchGiftOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 60, 30, 20, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 32, height = 32,
                                backgroundImage = "image/开服好礼图标.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("新人", 11, { 255, 220, 100 }) },
                    },
                    -- 红点
                    ctx.UI.Panel {
                        id = "launchGiftRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = LaunchGiftData.HasClaimable(),
                    },
                },
            } or nil,
            -- 邮件入口按钮
            ctx.UI.Panel {
                id = "mailboxBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 120, 200, 160, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowMailboxOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 20, 40, 35, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 28, height = 28,
                                backgroundImage = "image/icon_mail.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("邮件", 11, { 120, 220, 160 }) },
                    },
                    -- 红点
                    ctx.UI.Panel {
                        id = "mailboxRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = MailboxData.HasUnclaimed(),
                    },
                },
            },
            -- 招募入口按钮
            ctx.UI.Panel {
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 200, 80, 80, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowRecruitOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundImage = "image/icon_recruit.png",
                        backgroundSize = "cover",
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("招募", 11, { 255, 255, 255 }) },
                    },
                },
            },
            -- 挂机奖励按钮
            ctx.UI.Panel {
                id = "afkButton",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 120, 80, 200, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ClaimAfkReward()
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundImage = "image/icon_idle.png",
                        backgroundSize = "cover",
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = {
                            outlineLabel("0s", 11, { 140, 220, 140 }, "afkTimeLabel"),
                        },
                    },
                },
            },
            -- 活动入口按钮
            ctx.UI.Panel {
                id = "activityBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 220, 160, 40, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowActivityOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundImage = "image/icon_activity.png",
                        backgroundSize = "cover",
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("活动", 11, { 255, 255, 255 }) },
                    },
                    -- 红点（初始隐藏，数据加载后由 RefreshActivityRedDot 更新）
                    ctx.UI.Panel {
                        id = "activityRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = false,
                    },
                },
            },
            -- 兑换商店入口按钮
            ctx.UI.Panel {
                id = "exchangeShopBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 180, 140, 255, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowExchangeShopOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 35, 25, 55, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 30, height = 30,
                                backgroundImage = "image/icon_exchange_shop.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("兑换", 11, { 180, 140, 255 }) },
                    },
                    -- 红点
                    ctx.UI.Panel {
                        id = "exchangeShopRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = false,
                    },
                },
            },
            -- 减负中心入口按钮
            ctx.UI.Panel {
                id = "adReliefBtn",
                width = btnSize, height = btnSize,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 100, 220, 180, 180 },
                overflow = "hidden",
                pointerEvents = "auto",
                onClick = function(self)
                    GameUI.ShowAdReliefOverlay(true)
                end,
                children = {
                    ctx.UI.Panel {
                        width = btnSize, height = btnSize,
                        backgroundColor = { 20, 40, 40, 220 },
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            ctx.UI.Panel {
                                width = 30, height = 30,
                                backgroundImage = "image/currency_ad_ticket.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    ctx.UI.Panel {
                        position = "absolute",
                        bottom = 2, left = 0, right = 0,
                        alignItems = "center",
                        children = { outlineLabel("减负", 11, { 100, 220, 180 }) },
                    },
                    -- 红点
                    ctx.UI.Panel {
                        id = "adReliefRedDot",
                        position = "absolute",
                        top = 2, right = 2,
                        width = 10, height = 10,
                        borderRadius = 5,
                        backgroundColor = { 255, 60, 60, 255 },
                        visible = AdReliefData.HasClaimable(),
                    },
                },
            },
        },
    }
end

--- 更新挂机计时显示（由 GameUI.Update 调用）
function GameUI.UpdateAfkTimer()
    if not ctx.uiRoot then return end
    local elapsed = time.elapsedTime - GameUI._afkStartTime
    local PrivilegeData = require("Game.PrivilegeData")
    local DivineBlessDB = require("Game.DivineBlessData")
    local maxSecs = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds() + DivineBlessDB.GetBuffValue("idle_extra")
    local capped = math.floor(math.min(elapsed, maxSecs))
    -- 仅秒数变化时才更新
    if capped == GameUI._afkLastDisplaySec then return end
    GameUI._afkLastDisplaySec = capped

    local panel = ctx.uiRoot:FindById("afkTimeLabel")
    if panel then
        local txt = FormatAfkTime(capped)
        local kids = panel:GetChildren()
        if kids then
            for i = 1, #kids do
                kids[i]:SetText(txt)
            end
            -- 可领取时前景 Label（最后一个）变金色，描边保持黑色
            if capped >= Config.IDLE_MIN_SECONDS then
                kids[#kids]:SetFontColor({ 255, 220, 80, 255 })
            end
        end
    end

    -- 弹窗打开时实时刷新时间和奖励数值
    local idlePanel = ctx.uiRoot:FindById("idleRewardPanel")
    if idlePanel and idlePanel:IsVisible() and GameUI._pendingIdleRewards and not GameUI._pendingIdleRewards.isOffline then
        -- 重新计算当前挂机收益
        local rewards = CalcAfkRewardsNow()
        GameUI._pendingIdleRewards = rewards

        -- 刷新时间显示
        local secs = rewards.seconds
        local function fmtHMS(s)
            s = math.floor(s)
            local h = math.floor(s / 3600)
            local m = math.floor((s % 3600) / 60)
            local sec = s % 60
            return string.format("%02d:%02d:%02d", h, m, sec)
        end
        local remainSecs = math.max(0, maxSecs - secs)
        local timeStr = "挂机 " .. fmtHMS(secs) .. "  剩余 " .. fmtHMS(remainSecs)

        local timeLabel = ctx.uiRoot:FindById("idleTimeLabel")
        if timeLabel then timeLabel:SetText(timeStr) end

        -- 刷新奖励数值
        local crystalLabel = ctx.uiRoot:FindById("idleCrystalLabel")
        if crystalLabel then crystalLabel:SetText("冥晶: +" .. rewards.nether_crystal) end
        local stoneLabel = ctx.uiRoot:FindById("idleStoneLabel")
        if stoneLabel then stoneLabel:SetText("噬魂石: +" .. rewards.devour_stone) end
        local ironLabel = ctx.uiRoot:FindById("idleIronLabel")
        if ironLabel then ironLabel:SetText("锻魂铁: +" .. rewards.forge_iron) end
    end
end

--- 计算满时长挂机收益（广告立即领取用）
---@return table rewards
local function CalcAfkRewardsMax()
    return CalcAfkRewardsByTime(Config.IDLE_MAX_SECONDS)
end

--- 将挂机奖励转换为 RewardDisplay 格式
---@param rewards table
---@return table[] rewardItems
local function BuildRewardItems(rewards)
    local items = {}
    -- 货币
    local currencyList = {
        { id = "nether_crystal", amount = rewards.nether_crystal },
        { id = "devour_stone",   amount = rewards.devour_stone },
        { id = "forge_iron",     amount = rewards.forge_iron },
    }
    for _, c in ipairs(currencyList) do
        if c.amount and c.amount > 0 then
            local def = Config.CURRENCY[c.id]
            items[#items + 1] = {
                icon = def and def.image or "?",
                name = def and def.name or c.id,
                amount = c.amount,
            }
        end
    end
    -- 宝箱
    if rewards.chestDrops then
        for id, count in pairs(rewards.chestDrops) do
            if count > 0 then
                local cdef = ChestData.GetChestDef(id)
                items[#items + 1] = {
                    icon = (cdef and cdef.image) or "📦",
                    name = (cdef and cdef.name) or id,
                    amount = count,
                }
            end
        end
    end
    -- 碎片箱道具
    if rewards.fragmentBoxDrops then
        for itemId, count in pairs(rewards.fragmentBoxDrops) do
            if count > 0 then
                -- 从 Config.CURRENCY（包含道具定义）获取信息
                local itemDef = Config.CURRENCY and Config.CURRENCY[itemId]
                local itemName = (itemDef and itemDef.name) or itemId
                local itemImage = itemDef and itemDef.image
                items[#items + 1] = {
                    icon = itemImage or "📦",
                    name = itemName,
                    amount = count,
                }
            end
        end
    end
    return items
end

--- 实际发放挂机奖励（货币+宝箱，统一走 GrantReward）
---@param rewards table
local function GrantAfkRewards(rewards)
    Currency.GrantReward({ type = "currency", id = "nether_crystal", amount = rewards.nether_crystal }, "Afk")
    Currency.GrantReward({ type = "currency", id = "devour_stone", amount = rewards.devour_stone }, "Afk")
    Currency.GrantReward({ type = "currency", id = "forge_iron", amount = rewards.forge_iron }, "Afk")

    if rewards.chestDrops then
        local DivineBlessDB = require("Game.DivineBlessData")
        local chestMulti = DivineBlessDB.GetBuffValue("chest_multi")
        local mult = (chestMulti > 1.0) and math.floor(chestMulti) or 1
        for id, count in pairs(rewards.chestDrops) do
            if count > 0 then
                Currency.GrantReward({ type = "chest", id = id, amount = count * mult }, "Afk")
            end
        end
    end

    -- 发放碎片箱道具到背包
    if rewards.fragmentBoxDrops then
        for itemId, count in pairs(rewards.fragmentBoxDrops) do
            if count > 0 then
                Currency.GrantReward({ type = "item", id = itemId, amount = count }, "Afk")
            end
        end
    end

    -- 记录领取时间（持久化，登录时用于恢复离线挂机时长）
    HeroData.stats.afkLastClaimTime = os.time()
    HeroData.lastSaveTime = os.time()
    HeroData.Save()

    print("[GameUI] AFK rewards granted: crystal+" .. rewards.nether_crystal
        .. " stone+" .. rewards.devour_stone
        .. " iron+" .. rewards.forge_iron
        .. " fragBoxes+" .. (rewards.fragmentBoxDrops and next(rewards.fragmentBoxDrops) and "yes" or "0")
        .. " (" .. math.floor(rewards.seconds / 60) .. " min)")

    -- 每日任务：领取挂机收益
    local ok, DTD = pcall(require, "Game.DailyTaskData")
    if ok and DTD then DTD.AddProgress("idle", 1) end
end

--- 发放奖励并用 RewardDisplay 展示
---@param rewards table
---@param title string|nil
local function GrantAndShowRewards(rewards, title)
    -- 发放
    GrantAfkRewards(rewards)
    -- 重置挂机计时
    GameUI._afkStartTime = time.elapsedTime
    GameUI._afkLastDisplaySec = -1
    GameUI._pendingIdleRewards = nil
    -- 关闭挂机弹窗
    GameUI.ShowPanel("idleRewardPanel", false)
    -- UpdateHUD 由 Currency.Add("nether_crystal") 触发 EventBus 自动调用
    -- 用 RewardDisplay 展示
    local rewardItems = BuildRewardItems(rewards)
    if #rewardItems > 0 and ctx.uiRoot then
        RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
            title = title or "挂机收益",
            rewards = rewardItems,
        })
    end
end

--- 点击挂机按钮：打开预览弹窗（不自动发放）
function GameUI.ClaimAfkReward()
    local rewards = CalcAfkRewardsNow()
    -- 显示预览弹窗（不发放奖励，领取时再判断最低时长）
    GameUI.ShowIdleRewards(rewards)
end

-- ============================================================================
-- 挂机离线收益弹窗
-- ============================================================================

--- 创建挂机收益面板（全屏遮罩 + 居中卡片）
function GameUI.CreateIdleRewardPanel()
    local function closePanel()
        GameUI.ShowPanel("idleRewardPanel", false)
    end

    return ctx.UI.Panel {
        id = "idleRewardPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        onClick = function(self)
            -- 点击外部遮罩关闭
            closePanel()
        end,
        children = {
            ctx.UI.Panel {
                width = 280,
                paddingTop = 24, paddingBottom = 24,
                paddingLeft = 20, paddingRight = 20,
                gap = 8,
                backgroundColor = { 20, 25, 50, 245 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 140, 80, 200, 200 },
                alignItems = "center",
                pointerEvents = "auto",
                children = {
                    -- 右上角 X 关闭按钮
                    ctx.UI.Panel {
                        position = "absolute",
                        top = 4, right = 4,
                        width = 32, height = 32,
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self)
                            closePanel()
                        end,
                        children = {
                            ctx.UI.Label {
                                text = "✕",
                                fontSize = 18,
                                fontColor = { 180, 160, 200, 200 },
                            },
                        },
                    },
                    ctx.UI.Label {
                        id = "idleTitleLabel",
                        text = "挂机收益",
                        fontSize = 24,
                        fontColor = { 200, 170, 255, 255 },
                    },
                    ctx.UI.Label {
                        id = "idleTimeLabel",
                        text = "",
                        fontSize = 13,
                        fontColor = { 160, 150, 180, 200 },
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 4, marginBottom = 4,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    -- 奖励行：冥晶
                    ctx.UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            Currency.IconWidget(ctx.UI, "nether_crystal", 20),
                            ctx.UI.Label {
                                id = "idleCrystalLabel",
                                text = "冥晶: +0",
                                fontSize = 15,
                                fontColor = { 140, 80, 200, 255 },
                            },
                        },
                    },
                    -- 奖励行：噬魂石
                    ctx.UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            Currency.IconWidget(ctx.UI, "devour_stone", 20),
                            ctx.UI.Label {
                                id = "idleStoneLabel",
                                text = "噬魂石: +0",
                                fontSize = 15,
                                fontColor = { 60, 160, 80, 255 },
                            },
                        },
                    },
                    -- 奖励行：锻魂铁
                    ctx.UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            Currency.IconWidget(ctx.UI, "forge_iron", 20),
                            ctx.UI.Label {
                                id = "idleIronLabel",
                                text = "锻魂铁: +0",
                                fontSize = 15,
                                fontColor = { 130, 160, 200, 255 },
                            },
                        },
                    },
                    -- 宝箱掉落区域（动态填充）
                    ctx.UI.Panel {
                        id = "idleChestDropArea",
                        width = "100%",
                        alignItems = "center",
                        gap = 4,
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 4, marginBottom = 4,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    -- 按钮行：领取 + 立即领取
                    ctx.UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 10,
                        children = {
                            -- 领取按钮
                            ctx.UI.Panel {
                                id = "idleClaimBtn",
                                paddingLeft = 24, paddingRight = 24,
                                paddingTop = 10, paddingBottom = 10,
                                backgroundColor = { 120, 80, 200, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 180, 140, 255, 180 },
                                alignItems = "center",
                                justifyContent = "center",
                                onClick = function(self)
                                    local pendingRewards = GameUI._pendingIdleRewards
                                    if pendingRewards then
                                        if pendingRewards.isOffline then
                                            HeroData.ClaimIdleRewards(pendingRewards)
                                            GameUI._pendingIdleRewards = nil
                                            GameUI.ShowPanel("idleRewardPanel", false)
                                            -- UpdateHUD 由 ClaimIdleRewards→Currency.Add("nether_crystal") 触发 EventBus 自动调用
                                            -- 用 RewardDisplay 展示离线奖励
                                            local rewardItems = BuildRewardItems(pendingRewards)
                                            if #rewardItems > 0 and ctx.uiRoot then
                                                RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
                                                    title = "离线收益",
                                                    rewards = rewardItems,
                                                })
                                            end
                                        else
                                            -- 挂机领取：检查最低时长
                                            local elapsed = time.elapsedTime - GameUI._afkStartTime
                                            if elapsed < Config.IDLE_MIN_SECONDS then
                                                Toast.Show("挂机不足" .. Config.IDLE_MIN_SECONDS .. "秒，无法领取")
                                                return
                                            end
                                            GrantAndShowRewards(pendingRewards, "挂机收益")
                                        end
                                    end
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "领取",
                                        fontSize = 16,
                                        fontColor = { 255, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            -- 立即领取按钮（看广告领满时长收益）
                            ctx.UI.Panel {
                                id = "idleAdClaimBtn",
                                paddingLeft = 16, paddingRight = 16,
                                paddingTop = 10, paddingBottom = 10,
                                backgroundColor = { 200, 160, 50 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 255, 220, 100, 180 },
                                flexDirection = "column",
                                alignItems = "center",
                                justifyContent = "center",
                                gap = 2,
                                onClick = function(self)
                                    if not CanAfkAdClaim() then
                                        Toast.Show("今日立即领取次数已用完", { 255, 100, 80 })
                                        return
                                    end
                                    local AdHelper = require("Game.AdHelper")
                                    AdHelper.ShowRewardAd(function()
                                        RecordAfkAdClaim()
                                        local maxRewards = CalcAfkRewardsMax()
                                        -- 广告领取：只发放奖励，不重置挂机计时
                                        GrantAfkRewards(maxRewards)
                                        GameUI._pendingIdleRewards = nil
                                        GameUI.ShowPanel("idleRewardPanel", false)
                                        local rewardItems = BuildRewardItems(maxRewards)
                                        if #rewardItems > 0 and ctx.uiRoot then
                                            RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
                                                title = "满时长挂机收益",
                                                rewards = rewardItems,
                                            })
                                        end
                                    end)
                                end,
                                children = {
                                    ctx.UI.Panel {
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 4,
                                        children = {
                                            ctx.UI.Panel {
                                                width = 16, height = 16,
                                                backgroundImage = "image/icon_watch_ad.png",
                                                backgroundFit = "contain",
                                            },
                                            ctx.UI.Label {
                                                id = "idleAdClaimText",
                                                text = "立即领取",
                                                fontSize = 14,
                                                fontColor = { 30, 20, 10 },
                                                fontWeight = "bold",
                                            },
                                        },
                                    },
                                    ctx.UI.Label {
                                        id = "idleAdClaimCount",
                                        text = "",
                                        fontSize = 10,
                                        fontColor = { 60, 40, 10, 200 },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 显示挂机收益弹窗
---@param rewards table  HeroData.CalcIdleRewards() 的返回值
function GameUI.ShowIdleRewards(rewards)
    if not rewards or not ctx.uiRoot then return end

    -- 暂存待领取奖励
    GameUI._pendingIdleRewards = rewards

    -- 格式化时长（HH:MM:SS 格式）
    local secs = rewards.seconds
    local function fmtHMS(s)
        s = math.floor(s)
        local h = math.floor(s / 3600)
        local m = math.floor((s % 3600) / 60)
        local sec = s % 60
        return string.format("%02d:%02d:%02d", h, m, sec)
    end

    local PrivilegeData = require("Game.PrivilegeData")
    local maxSecs = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds()
    local remainSecs = math.max(0, maxSecs - secs)

    local prefix = rewards.isOffline and "离线" or "挂机"
    local timeStr = prefix .. " " .. fmtHMS(secs) .. "  剩余 " .. fmtHMS(remainSecs)

    -- 更新文本
    local titleLabel = ctx.uiRoot:FindById("idleTitleLabel")
    if titleLabel then titleLabel:SetText(rewards.isOffline and "离线收益" or "挂机收益") end

    local timeLabel = ctx.uiRoot:FindById("idleTimeLabel")
    if timeLabel then timeLabel:SetText(timeStr) end

    local crystalLabel = ctx.uiRoot:FindById("idleCrystalLabel")
    if crystalLabel then crystalLabel:SetText("冥晶: +" .. rewards.nether_crystal) end

    local stoneLabel = ctx.uiRoot:FindById("idleStoneLabel")
    if stoneLabel then stoneLabel:SetText("噬魂石: +" .. rewards.devour_stone) end

    local ironLabel = ctx.uiRoot:FindById("idleIronLabel")
    if ironLabel then ironLabel:SetText("锻魂铁: +" .. rewards.forge_iron) end

    -- 填充宝箱掉落
    local chestArea = ctx.uiRoot:FindById("idleChestDropArea")
    if chestArea then
        chestArea:ClearChildren()
        if rewards.chestDrops then
            local hasChest = false
            for id, count in pairs(rewards.chestDrops) do
                if count > 0 then
                    hasChest = true
                    local cdef = ChestData.GetChestDef(id)
                    local chestName = cdef and cdef.name or id
                    local chestColor = cdef and cdef.color or { 200, 200, 200, 255 }
                    chestArea:AddChild(ctx.UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            (cdef and cdef.image) and ctx.UI.Panel {
                                width = 20, height = 20,
                                backgroundImage = cdef.image,
                                backgroundFit = "contain",
                            } or ctx.UI.Label {
                                text = (cdef and cdef.emoji) or "📦",
                                fontSize = 16,
                            },
                            ctx.UI.Label {
                                text = chestName .. ": +" .. count,
                                fontSize = 15,
                                fontColor = chestColor,
                            },
                        },
                    })
                end
            end
            if hasChest then
                -- 加一条分隔线在宝箱区域前
                chestArea:AddChild(ctx.UI.Panel {
                    width = "90%", height = 1,
                    marginTop = 2, marginBottom = 2,
                    backgroundColor = { 100, 70, 160, 80 },
                })
            end
        end
    end

    -- 立即领取按钮：离线收益时隐藏，或每日次数用完时置灰
    local adClaimBtn = ctx.uiRoot:FindById("idleAdClaimBtn")
    if adClaimBtn then
        if rewards.isOffline then
            adClaimBtn:SetVisible(false)
        else
            adClaimBtn:SetVisible(true)
            local canClaim = CanAfkAdClaim()
            local remaining = GetAfkAdRemaining()
            adClaimBtn:SetStyle({
                backgroundColor = canClaim and { 200, 160, 50 } or { 60, 55, 65, 200 },
                borderColor = canClaim and { 255, 220, 100, 180 } or { 80, 75, 85, 120 },
            })
            local adText = ctx.uiRoot:FindById("idleAdClaimText")
            if adText then
                adText:SetText(canClaim and "立即领取" or "今日已达上限")
                adText:SetFontColor(canClaim and { 30, 20, 10 } or { 120, 110, 130, 180 })
            end
            local adCount = ctx.uiRoot:FindById("idleAdClaimCount")
            if adCount then
                adCount:SetText("今日剩余 " .. remaining .. "/" .. AFK_AD_DAILY_MAX .. " 次")
                adCount:SetFontColor(canClaim and { 60, 40, 10, 200 } or { 100, 90, 100, 150 })
            end
        end
    end

    GameUI.ShowPanel("idleRewardPanel", true)
end

--- 每帧更新 UI 状态

end
