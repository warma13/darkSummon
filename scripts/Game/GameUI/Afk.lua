-- Game/GameUI/Afk.lua
-- 挂机系统核心：数据初始化、收益计算、奖励发放、计时器更新
-- UI 子模块: AfkButtons.lua（左侧按钮）、AfkPanel.lua（收益弹窗）

return function(GameUI, ctx)

local Config         = require("Game.Config")
local Currency       = require("Game.Currency")
local HeroData       = require("Game.HeroData")
local ChestData      = require("Game.ChestData")
local Toast          = require("Game.Toast")
local RewardDisplay        = require("Game.RewardDisplay")
local RewardIcon            = require("Game.RewardIcon")
local TodayStr = require("Game.DateUtil").TodayStr
local LaborDayData = require("Game.LaborDayData")
local PrivilegeData = require("Game.PrivilegeData")
local DivineBlessDB = require("Game.DivineBlessData")

local FormatNum = ctx.FormatNum

-- ============================================================================
-- 左侧挂机奖励入口（实时计时 + 点击领取）
-- ============================================================================

-- 挂机计时起点（使用引擎单调时钟，防止玩家改系统时间）
-- Bootstrap 会在存档加载后用离线时长回拨此值
GameUI._afkStartTime = time.elapsedTime
-- 上次更新显示的秒数（避免每帧刷新文本）
GameUI._afkLastDisplaySec = -1

-- 累积在线时长（持久化，跨会话累加，每日重置）
GameUI._onlineSessionStart = time.elapsedTime
do
    local stats = HeroData.stats
    local today = TodayStr()
    if stats.onlineTimeDate ~= today then
        stats.onlineTimeDate = today
        stats.onlineTimeAccum = 0
    end
end

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

-- ============================================================================
-- 在线送好礼 — 里程碑奖励
-- ============================================================================

--- 里程碑配置（键用字符串避免反序列化问题）
--- threshold: 秒，reward: { type, id, amount }
local ONLINE_MILESTONES = {
    { key = "m1",   threshold = 60,     label = "1分钟",  reward = { type = "item", id = "nether_crystal_pack",        amount = 1  } },
    { key = "m5",   threshold = 300,    label = "5分钟",  reward = { type = "item", id = "nether_crystal_pack",        amount = 2  } },
    { key = "m10",  threshold = 600,    label = "10分钟", reward = { type = "item", id = "nether_crystal_pack",        amount = 3  } },
    { key = "m30",  threshold = 1800,   label = "30分钟", reward = { type = "item", id = "shadow_essence_bag",         amount = 2  } },
    { key = "m60",  threshold = 3600,   label = "1小时",  reward = { type = "item", id = "shadow_essence_bag",         amount = 4  } },
    { key = "m120", threshold = 7200,   label = "2小时",  reward = { type = "item", id = "recruit_ticket_select_box",  amount = 10 } },
    { key = "m180", threshold = 10800,  label = "3小时",  reward = { type = "item", id = "recruit_ticket_select_box",  amount = 20 } },
}

--- 获取今日已领取的里程碑表
local function GetTodayMilestones()
    local stats = HeroData.stats
    local today = TodayStr()
    if stats.onlineMilestoneDate ~= today then
        stats.onlineMilestoneDate = today
        stats.onlineMilestones = {}
    end
    if not stats.onlineMilestones then
        stats.onlineMilestones = {}
    end
    return stats.onlineMilestones
end

--- 领取里程碑奖励
---@param key string 里程碑 key
---@param reward table { type, id, amount }
local function ClaimMilestone(key, reward)
    local claimed = GetTodayMilestones()
    if claimed[key] then return false end
    claimed[key] = true
    Currency.GrantReward(reward, "OnlineMilestone")
    HeroData.Save()
    if ctx.uiRoot then
        local def = Config.CURRENCY and Config.CURRENCY[reward.id]
        local iDef = not def and Config.ITEMS and Config.ITEMS[reward.id] or nil
        local icon = (def and def.image) or (iDef and iDef.image) or "?"
        local name = (def and def.name) or (iDef and iDef.name) or reward.id
        RewardDisplay.Show(ctx.UI, ctx.uiRoot, {
            title = "在线好礼",
            rewards = {
                { icon = icon, name = name, amount = reward.amount },
            },
        })
    end
    return true
end

--- 获取今日累积在线时长（已持久化 + 本次会话）
local function GetTodayOnlineSeconds()
    local stats = HeroData.stats
    local today = TodayStr()
    if stats.onlineTimeDate ~= today then
        stats.onlineTimeDate = today
        stats.onlineTimeAccum = 0
    end
    local sessionElapsed = time.elapsedTime - GameUI._onlineSessionStart
    return (stats.onlineTimeAccum or 0) + sessionElapsed
end

--- 持久化当前在线时长到 stats（由 UpdateAfkTimer 定期调用）
local function SaveOnlineTime()
    local stats = HeroData.stats
    local today = TodayStr()
    if stats.onlineTimeDate ~= today then
        stats.onlineTimeDate = today
        stats.onlineTimeAccum = 0
        GameUI._onlineSessionStart = time.elapsedTime
    end
    stats.onlineTimeAccum = (stats.onlineTimeAccum or 0) + (time.elapsedTime - GameUI._onlineSessionStart)
    GameUI._onlineSessionStart = time.elapsedTime
end

--- 格式化时长为 HH:MM:SS（面板显示用）
---@param s number
---@return string
local function FormatHMS(s)
    s = math.floor(s)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    return string.format("%02d:%02d:%02d", h, m, sec)
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

--- 刷新里程碑区域 UI（弹窗打开时调用）
local function RefreshMilestoneUI()
    if not ctx.uiRoot then return end
    local area = ctx.uiRoot:FindById("idleMilestoneArea")
    if not area then return end

    area:ClearChildren()

    local elapsed = GetTodayOnlineSeconds()
    local claimed = GetTodayMilestones()
    -- 当前在线时长
    area:AddChild(ctx.UI.Label {
        text = "今日累积在线时长：" .. FormatAfkTime(math.floor(elapsed)),
        fontSize = 13,
        fontColor = { 180, 170, 200, 220 },
    })
    -- 分隔线
    area:AddChild(ctx.UI.Panel {
        width = "90%", height = 1,
        marginTop = 2, marginBottom = 2,
        backgroundColor = { 100, 70, 160, 100 },
    })

    -- 里程碑行（横向滚动排列）
    local items = {}
    for _, ms in ipairs(ONLINE_MILESTONES) do
        local isClaimed = claimed[ms.key] == true
        local isReady   = elapsed >= ms.threshold and not isClaimed
        local isLocked  = elapsed < ms.threshold

        local bgColor, borderColor, labelColor
        if isClaimed then
            bgColor     = { 40, 45, 55, 200 }
            borderColor = { 60, 60, 70, 150 }
            labelColor  = { 100, 100, 110, 180 }
        elseif isReady then
            bgColor     = { 40, 60, 30, 240 }
            borderColor = { 80, 200, 120, 220 }
            labelColor  = { 120, 255, 160, 255 }
        else
            bgColor     = { 30, 28, 40, 220 }
            borderColor = { 80, 60, 120, 150 }
            labelColor  = { 160, 140, 200, 200 }
        end

        items[#items + 1] = ctx.UI.Panel {
            width = 62,
            flexDirection = "column",
            alignItems = "center",
            justifyContent = "center",
            gap = 3,
            paddingTop = 6, paddingBottom = 6,
            backgroundColor = bgColor,
            borderRadius = 8,
            borderWidth = isReady and 2 or 1,
            borderColor = borderColor,
            pointerEvents = "auto",
            children = {
                RewardIcon.Create(ctx.UI, 36, ms.reward.id, ms.reward.amount, {
                    muted = isClaimed,
                    noTooltip = true,
                }),
                ctx.UI.Label {
                    text = isClaimed and "已领" or ms.label,
                    fontSize = 9,
                    fontColor = isClaimed and { 100, 100, 110, 180 } or { 160, 140, 200, 200 },
                },
            },
        }
    end

    area:AddChild(ctx.UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        flexWrap = "wrap",
        gap = 6,
        paddingLeft = 6, paddingRight = 6,
        children = items,
    })
end

--- 计算指定时长的挂机收益（基于当前关卡实际战斗掉落推算）
---@param seconds number 挂机秒数
---@return table rewards { seconds, nether_crystal, devour_stone, forge_iron, chestDrops }
local function CalcAfkRewardsByTime(seconds)
    -- 特权增益 + 神裔降临：挂机时长上限
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
        -- 用确定性种子避免预览面板每次刷新显示不同掉落
        local fullHours = math.floor(hours)
        local daySeed = os.time() - (os.time() % 86400)
        local oldSeed = math.random(1, 2^31 - 1)  -- 保存当前随机状态
        math.randomseed(daySeed + fullHours * 137)
        for _, rule in ipairs(Config.IDLE_CHEST_RANDOM) do
            for _ = 1, fullHours do
                if math.random() < rule.chancePerHour then
                    chestDrops[rule.id] = (chestDrops[rule.id] or 0) + 1
                end
            end
        end
        math.randomseed(oldSeed)  -- 恢复随机状态
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
        local daySeed = os.time() - (os.time() % 86400)
        local oldSeed = math.random(1, 2^31 - 1)
        math.randomseed(daySeed + fullHours * 251)
        for _, rule in ipairs(Config.IDLE_FRAGMENT_RANDOM) do
            for _ = 1, fullHours do
                if math.random() < rule.chancePerHour then
                    fragmentBoxDrops[rule.id] = (fragmentBoxDrops[rule.id] or 0) + 1
                end
            end
        end
        math.randomseed(oldSeed)
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
    -- 时间债务状态：返回惩罚标记，禁止领取
    if elapsed < 0 then
        return {
            timeTravelPenalty = true,
            penaltySeconds = math.ceil(-elapsed),
            seconds = 0,
            nether_crystal = 0,
            devour_stone = 0,
            forge_iron = 0,
        }
    end
    return CalcAfkRewardsByTime(elapsed)
end

-- CreateAfkButton 已拆分到 GameUI/AfkButtons.lua
require("Game.GameUI.AfkButtons")(GameUI, ctx)

--- 更新挂机计时显示（由 GameUI.Update 调用）
function GameUI.UpdateAfkTimer()
    if not ctx.uiRoot then return end

    -- 每30秒持久化在线时长
    local now = time.elapsedTime
    if not GameUI._lastOnlineSave or (now - GameUI._lastOnlineSave) >= 30 then
        GameUI._lastOnlineSave = now
        SaveOnlineTime()
    end

    local elapsed = time.elapsedTime - GameUI._afkStartTime
    local isDebt = (elapsed < 0)  -- 时间债务（时钟前拨惩罚）
    local maxSecs = Config.IDLE_MAX_SECONDS + PrivilegeData.GetIdleExtraSeconds() + DivineBlessDB.GetBuffValue("idle_extra")
    local capped = isDebt and math.floor(elapsed) or math.floor(math.min(elapsed, maxSecs))
    -- 仅秒数变化时才更新
    if capped == GameUI._afkLastDisplaySec then return end
    GameUI._afkLastDisplaySec = capped

    local panel = ctx.uiRoot:FindById("afkTimeLabel")
    if panel then
        local kids = panel:GetChildren()
        if kids then
            if isDebt then
                -- 时间债务状态：显示红色负数时间
                local absSecs = math.abs(capped)
                local txt = "-" .. FormatAfkTime(absSecs)
                for i = 1, #kids do kids[i]:SetText(txt) end
                kids[#kids]:SetFontColor({ 255, 60, 60, 255 })
            elseif GameUI._afkIconSwitch == 1 then
                -- 好礼图标 → 显示累积在线时长
                local onlineTxt = FormatAfkTime(math.floor(GetTodayOnlineSeconds()))
                for i = 1, #kids do kids[i]:SetText(onlineTxt) end
                kids[#kids]:SetFontColor({ 255, 200, 80, 255 })
            else
                -- 挂机图标 → 显示挂机时长
                local txt = FormatAfkTime(capped)
                for i = 1, #kids do kids[i]:SetText(txt) end
                if capped >= Config.IDLE_MIN_SECONDS then
                    kids[#kids]:SetFontColor({ 255, 220, 80, 255 })
                end
            end
        end
    end

    -- 双图标轮换（每10秒切换一次）—— 时间债务状态下固定显示挂机图标
    local ICON_SWITCH_INTERVAL = 10
    if not GameUI._afkIconSwitch then GameUI._afkIconSwitch = 0 end
    local switchPhase = isDebt and 0 or (math.floor(capped / ICON_SWITCH_INTERVAL) % 2)
    if switchPhase ~= GameUI._afkIconSwitch then
        GameUI._afkIconSwitch = switchPhase
        local icon1 = ctx.uiRoot:FindById("afkIcon1")
        local icon2 = ctx.uiRoot:FindById("afkIcon2")
        local btnSize = 56
        if icon1 and icon2 then
            if switchPhase == 0 then
                -- 显示挂机图标
                icon1:SetStyle({ left = 0 })
                icon2:SetStyle({ left = btnSize })
            else
                -- 显示在线好礼图标
                icon1:SetStyle({ left = -btnSize })
                icon2:SetStyle({ left = 0 })
            end
        end
        -- 底部文字切换
        if panel then
            local kids2 = panel:GetChildren()
            if kids2 then
                if isDebt then
                    local absSecs = math.abs(capped)
                    local txt2 = "-" .. FormatAfkTime(absSecs)
                    for i = 1, #kids2 do kids2[i]:SetText(txt2) end
                    kids2[#kids2]:SetFontColor({ 255, 60, 60, 255 })
                elseif switchPhase == 0 then
                    local txt2 = FormatAfkTime(capped)
                    for i = 1, #kids2 do kids2[i]:SetText(txt2) end
                else
                    local onlineTxt = FormatAfkTime(math.floor(GetTodayOnlineSeconds()))
                    for i = 1, #kids2 do kids2[i]:SetText(onlineTxt) end
                    kids2[#kids2]:SetFontColor({ 255, 200, 80, 255 })
                end
            end
        end
    end

    -- 弹窗打开时实时刷新
    local idlePanel = ctx.uiRoot:FindById("idleRewardPanel")
    if idlePanel and idlePanel:IsVisible() and GameUI._pendingIdleRewards and not GameUI._pendingIdleRewards.isOffline then
        -- 重新计算当前挂机收益（保留随机掉落，仅在整小时变化时重算）
        local prev = GameUI._pendingIdleRewards
        local newRewards = CalcAfkRewardsNow()
        local prevHours = prev and math.floor(prev.seconds / 3600) or -1
        local newHours = math.floor(newRewards.seconds / 3600)
        if prevHours == newHours and prev then
            newRewards.chestDrops = prev.chestDrops
            newRewards.fragmentBoxDrops = prev.fragmentBoxDrops
        end
        GameUI._pendingIdleRewards = newRewards

        if GameUI._idleTabIndex == 1 then
            -- tab1：刷新奖励文本（元素仅在 page1 挂载时存在）
            GameUI._refreshIdlePage1()
        elseif GameUI._idleTabIndex == 2 then
            -- tab2：每 5 秒刷新一次里程碑状态
            local nowMs = time.elapsedTime
            if not GameUI._lastMilestoneRefresh or (nowMs - GameUI._lastMilestoneRefresh) >= 5 then
                GameUI._lastMilestoneRefresh = nowMs
                RefreshMilestoneUI()
            end
        end
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
---@param laborMult? number 外部已消耗的劳动倍率，传入则不再自行消耗
local function GrantAfkRewards(rewards, laborMult)
    -- 劳动加倍（优先使用外部传入的倍率）
    if not laborMult then
        laborMult = LaborDayData.ConsumeDouble()
    end
    rewards.nether_crystal = math.floor(rewards.nether_crystal * laborMult)
    rewards.devour_stone   = math.floor(rewards.devour_stone * laborMult)
    rewards.forge_iron     = math.floor(rewards.forge_iron * laborMult)

    -- 特权增益：概率翻倍全部收益
    local doubleChance = PrivilegeData.GetDoubleChance()
    if doubleChance > 0 and math.random() < doubleChance then
        rewards.nether_crystal = rewards.nether_crystal * 2
        rewards.devour_stone   = rewards.devour_stone * 2
        rewards.forge_iron     = rewards.forge_iron * 2
        print("[Afk] Privilege double triggered!")
    end

    Currency.GrantReward({ type = "currency", id = "nether_crystal", amount = rewards.nether_crystal }, "Afk")
    Currency.GrantReward({ type = "currency", id = "devour_stone", amount = rewards.devour_stone }, "Afk")
    Currency.GrantReward({ type = "currency", id = "forge_iron", amount = rewards.forge_iron }, "Afk")

    if rewards.chestDrops then
        local chestMulti = DivineBlessDB.GetBuffValue("chest_multi")
        local chestBonus = 1.0 + PrivilegeData.GetChestDropBonus()
        local mult = math.max(1, math.floor(chestMulti * chestBonus))
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

    -- 记录领取时间（单调性保护：只升不降，防止时钟回拨覆盖）
    local ServerTime = require("Game.ServerTime")
    local oldClaimDay = HeroData.stats.afkLastClaimDay or 0
    local newClaimTime = ServerTime.ConsensusClampedNow(oldClaimDay)
    local oldClaimTime = HeroData.stats.afkLastClaimTime or 0
    HeroData.stats.afkLastClaimTime = math.max(oldClaimTime, newClaimTime)
    -- afkLastClaimDay 基于钳制后的时间计算，不直接用共识天
    local LAUNCH_EPOCH = ServerTime.GetLaunchEpoch()
    local newClaimDay = math.floor((math.max(oldClaimTime, newClaimTime) - LAUNCH_EPOCH) / 86400)
    newClaimDay = math.max(0, newClaimDay)
    HeroData.stats.afkLastClaimDay = math.max(oldClaimDay, newClaimDay)
    HeroData.lastSaveTime = math.max(oldClaimTime, newClaimTime)
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

--- 领取离线推关奖励并刷新战役（公共逻辑，isOffline/非isOffline 共用）
---@return table|nil pushResult 已消费的推关结果
---@return string pushSuffix 推关标题后缀（如 " (推进3关)"）
---@param laborMult? number 外部已消耗的劳动倍率，传入则推关奖励不再自行消耗翻倍次数
local function ClaimPendingPush(laborMult)
    local pushResult = GameUI._pendingOfflinePush
    if not pushResult or pushResult.pushed <= 0 then
        GameUI._pendingOfflinePush = nil
        return pushResult, ""
    end
    local okOP, OfflinePush = pcall(require, "Game.OfflinePush")
    if okOP and OfflinePush then
        OfflinePush.ClaimPushRewards(pushResult, laborMult)
    end
    GameUI._pendingOfflinePush = nil
    -- 推关后刷新当前主线关卡到新进度
    local BM = require("Game.BattleManager")
    if not BM.IsActive() or BM.GetMode() == "campaign" then
        local newStage = (HeroData.stats.bestStage or 0) + 1
        BM.Enter("campaign", {
            stageNum = newStage,
            onWin    = function() GameUI.DoStageClear() end,
            onLose   = function() GameUI.DoGameOver() end,
        })
        print("[Afk] Refreshed campaign to stage " .. newStage .. " after offline push")
    end
    return pushResult, " (推进" .. pushResult.pushed .. "关)"
end

--- 将推关额外奖励（虚空契约等）追加到 rewardItems
---@param rewardItems table[]
---@param pushResult table|nil
local function AppendPushRewardItems(rewardItems, pushResult)
    if not pushResult or pushResult.pushed <= 0 or not pushResult.stageRewards then return end
    local pr = pushResult.stageRewards
    if pr.void_pact and pr.void_pact > 0 then
        local vpDef = Config.CURRENCY and Config.CURRENCY["void_pact"]
        rewardItems[#rewardItems + 1] = {
            icon = vpDef and vpDef.image or "?",
            name = vpDef and vpDef.name or "虚空契约",
            amount = pr.void_pact,
        }
    end
end

--- 发放奖励并用 RewardDisplay 展示
---@param rewards table
---@param title string|nil
local function GrantAndShowRewards(rewards, title, laborMult)
    -- 发放
    GrantAfkRewards(rewards, laborMult)
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

-- ============================================================================
-- AfkCore: 暴露核心函数给 AfkPanel / AfkButtons 子模块
-- ============================================================================
local AfkCore = {
    CalcAfkRewardsNow     = CalcAfkRewardsNow,
    CalcAfkRewardsMax     = CalcAfkRewardsMax,
    BuildRewardItems      = BuildRewardItems,
    GrantAfkRewards       = GrantAfkRewards,
    GrantAndShowRewards   = GrantAndShowRewards,
    ClaimPendingPush      = ClaimPendingPush,
    AppendPushRewardItems = AppendPushRewardItems,
    RefreshMilestoneUI    = RefreshMilestoneUI,
    FormatHMS             = FormatHMS,
    CanAfkAdClaim         = CanAfkAdClaim,
    GetAfkAdRemaining     = GetAfkAdRemaining,
    RecordAfkAdClaim      = RecordAfkAdClaim,
    GetTodayOnlineSeconds = GetTodayOnlineSeconds,
    GetTodayMilestones    = GetTodayMilestones,
    ONLINE_MILESTONES     = ONLINE_MILESTONES,
    AFK_AD_DAILY_MAX      = AFK_AD_DAILY_MAX,
}

-- 面板 UI 已拆分到 GameUI/AfkPanel.lua
require("Game.GameUI.AfkPanel")(GameUI, ctx, AfkCore)

end
