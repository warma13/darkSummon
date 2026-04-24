-- Game/HeroUI/DeployPopup.lua
-- 上阵管理弹出层（上阵/下阵切换 + 无损交换）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Toast = require("Game.Toast")

local DeployPopup = {}

--- 收藏弹出层内容容器（用于局部刷新）
---@type any
local popupContentContainer = nil

-- 无损交换状态
local swapSourceHeroId = nil   -- 交换发起方英雄ID
local swapConfirmOverlay = nil -- 确认弹窗
local swapHintBanner = nil     -- 提示条

--- 页面重建时清理局部状态
function DeployPopup.OnPageClear()
    popupContentContainer = nil
    swapSourceHeroId = nil
    swapConfirmOverlay = nil
    swapHintBanner = nil
    local HeroCardMod = require("Game.HeroUI.HeroCard")
    HeroCardMod.ClearCache("deploy")
end

--- 更新上阵计数显示（增量）
local function UpdateDeployCount(ctx)
    if not popupContentContainer then return end
    local S = ctx.GetS()
    local countLabel = popupContentContainer:FindById("deploy_count_label")
    if not countLabel then return end
    local count = HeroData.GetDeployedCount()
    local maxDeploy = Config.MAX_DEPLOYED
    local isFull = count >= maxDeploy
    countLabel:SetText(count .. "/" .. maxDeploy)
    countLabel:SetFontColor(isFull and S.deployFull or S.deployedCount)
end

--- 刷新收藏弹出层网格内容（不重建整个弹出层）
function DeployPopup.RefreshCollectionContent(ctx)
    if not popupContentContainer then return end
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local HeroCardMod = require("Game.HeroUI.HeroCard")

    -- 清除旧缓存
    HeroCardMod.ClearCache("deploy")
    popupContentContainer:ClearChildren()

    -- 上阵信息栏
    local count = HeroData.GetDeployedCount()
    local maxDeploy = Config.MAX_DEPLOYED
    local isFull = count >= maxDeploy
    local countColor = isFull and S.deployFull or S.deployedCount

    popupContentContainer:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = 4, paddingBottom = 6,
        paddingLeft = 12, paddingRight = 12,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "英雄收藏",
                fontSize = 15,
                fontColor = S.white,
                fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label { text = "上阵", fontSize = 11, fontColor = S.dim },
                    UI.Label {
                        id = "deploy_count_label",
                        text = count .. "/" .. maxDeploy,
                        fontSize = 13,
                        fontColor = countColor,
                        fontWeight = "bold",
                    },
                },
            },
        },
    })

    -- 英雄网格
    popupContentContainer:AddChild(HeroCardMod.CreateHeroGrid(ctx))
end

--- 获取英雄名称
---@param heroId string
---@return string
local function GetHeroName(heroId)
    for _, td in ipairs(Config.TOWER_TYPES) do
        if td.id == heroId then return td.name end
    end
    if Config.LEADER_HERO and Config.LEADER_HERO.id == heroId then
        return Config.LEADER_HERO.name or heroId
    end
    return heroId
end

--- 关闭交换确认弹窗
local function CloseSwapConfirm(ctx)
    if swapConfirmOverlay then
        local pageRoot = ctx.GetPageRoot()
        if pageRoot then pageRoot:RemoveChild(swapConfirmOverlay) end
        swapConfirmOverlay = nil
    end
end

--- 取消交换模式
local function CancelSwapMode(ctx)
    swapSourceHeroId = nil
    if swapHintBanner and popupContentContainer then
        popupContentContainer:RemoveChild(swapHintBanner)
        swapHintBanner = nil
    end
end

--- 进入交换选择模式（显示提示条）
local function EnterSwapMode(ctx, sourceHeroId)
    swapSourceHeroId = sourceHeroId
    local UI = ctx.GetUI()
    local heroName = GetHeroName(sourceHeroId)

    swapHintBanner = UI.Panel {
        width = "100%",
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 60, 120, 180, 220 },
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Label {
                text = "选择要与「" .. heroName .. "」交换的英雄",
                fontSize = 12, fontColor = { 255, 255, 255 },
                flexShrink = 1,
            },
            UI.Panel {
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = { 255, 255, 255, 50 },
                borderRadius = 6,
                onClick = function(self)
                    CancelSwapMode(ctx)
                end,
                children = {
                    UI.Label { text = "取消", fontSize = 11, fontColor = { 255, 255, 255 } },
                },
            },
        },
    }

    -- 插入到内容容器顶部（上阵信息栏之后）
    if popupContentContainer then
        popupContentContainer:InsertChild(swapHintBanner, 2)
    end
end

--- 执行交换并刷新
local function ExecuteSwap(ctx, targetHeroId)
    local sourceId = swapSourceHeroId
    CancelSwapMode(ctx)

    local ok, msg = HeroData.SwapProgression(sourceId, targetHeroId)
    if ok then
        -- 交换上阵状态：让目标英雄替换源英雄的阵位
        local srcDeployed = HeroData.IsDeployed(sourceId)
        local tgtDeployed = HeroData.IsDeployed(targetHeroId)
        if srcDeployed and not tgtDeployed then
            HeroData.Undeploy(sourceId)
            HeroData.Deploy(targetHeroId)
        elseif not srcDeployed and tgtDeployed then
            HeroData.Undeploy(targetHeroId)
            HeroData.Deploy(sourceId)
        end
        -- 两个都在阵 / 都不在阵 → 不动

        local success, AudioManager = pcall(require, "Game.AudioManager")
        if success and AudioManager then AudioManager.PlayUpgrade() end
        Toast.Show("交换成功！")
    else
        Toast.Show(msg or "交换失败")
    end

    -- 全量刷新网格（两张卡都变了）
    DeployPopup.RefreshCollectionContent(ctx)
end

--- 显示交换确认弹窗
local function ShowSwapConfirm(ctx, heroId)
    if swapConfirmOverlay then return end
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local heroName = GetHeroName(heroId)
    local h = HeroData.Get(heroId)
    local heroLevel = (h and h.level) or 1

    local confirmPanel = UI.Panel {
        width = 240,
        backgroundColor = { 40, 30, 22, 250 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { 80, 140, 200, 200 },
        paddingTop = 16, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        alignItems = "center",
        gap = 10,
        children = {
            UI.Label { text = "无损交换", fontSize = 17, fontColor = { 100, 180, 255 }, fontWeight = "bold" },
            UI.Label { text = heroName .. " (Lv." .. heroLevel .. ")", fontSize = 14, fontColor = { 255, 220, 160 }, fontWeight = "bold" },
            UI.Label { text = "交换等级、进阶和装备", fontSize = 12, fontColor = { 180, 165, 145 } },
            UI.Label { text = "星级不受影响", fontSize = 11, fontColor = { 140, 130, 115 } },
            UI.Panel { width = "90%", height = 1, backgroundColor = { 100, 75, 55, 100 } },
            UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 4,
                children = {
                    -- 下阵按钮
                    UI.Panel {
                        paddingLeft = 18, paddingRight = 18,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = { 80, 60, 45, 220 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            CloseSwapConfirm(ctx)
                            -- 执行正常下阵
                            local ok, msg = HeroData.Undeploy(heroId)
                            if ok then
                                local success, AudioManager = pcall(require, "Game.AudioManager")
                                if success and AudioManager then AudioManager.PlayUpgrade() end
                            end
                            local HeroCardMod = require("Game.HeroUI.HeroCard")
                            local refreshed = HeroCardMod.RefreshSingleCard(ctx, heroId, "deploy")
                            if refreshed then
                                UpdateDeployCount(ctx)
                            else
                                DeployPopup.RefreshCollectionContent(ctx)
                            end
                        end,
                        children = {
                            UI.Label { text = "下阵", fontSize = 14, fontColor = { 200, 180, 160 } },
                        },
                    },
                    -- 交换按钮
                    UI.Panel {
                        paddingLeft = 18, paddingRight = 18,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = { 50, 110, 180, 240 },
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            CloseSwapConfirm(ctx)
                            EnterSwapMode(ctx, heroId)
                        end,
                        children = {
                            UI.Label { text = "交换", fontSize = 14, fontColor = { 255, 255, 255 }, fontWeight = "bold" },
                        },
                    },
                },
            },
        },
    }

    swapConfirmOverlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            CloseSwapConfirm(ctx)
        end,
        children = { confirmPanel },
    }
    pageRoot:AddChild(swapConfirmOverlay)
end

--- 卡片点击处理：上阵/下阵切换 + 无损交换
function DeployPopup.HandleCardClick(ctx, heroId, isUnlocked, isDeployed)
    if not isUnlocked then
        print("[HeroUI] " .. heroId .. " is locked")
        return
    end

    -- 交换模式：点击第二个英雄完成交换
    if swapSourceHeroId then
        if heroId == swapSourceHeroId then
            CancelSwapMode(ctx)
            return
        end
        ExecuteSwap(ctx, heroId)
        return
    end

    -- 已上阵的英雄 → 显示交换/下阵确认弹窗
    if isDeployed then
        ShowSwapConfirm(ctx, heroId)
        return
    end

    -- 未上阵 → 正常上阵
    local ok, msg = HeroData.Deploy(heroId)
    print("[HeroUI] Deploy " .. heroId .. ": " .. msg)

    local success, AudioManager = pcall(require, "Game.AudioManager")
    if success and AudioManager then
        if ok then AudioManager.PlayUpgrade() end
    end

    if not ok then return end

    -- 增量刷新：只更新被点击的卡片 + 上阵计数
    local HeroCardMod = require("Game.HeroUI.HeroCard")
    local refreshed = HeroCardMod.RefreshSingleCard(ctx, heroId, "deploy")
    if refreshed then
        UpdateDeployCount(ctx)
    else
        DeployPopup.RefreshCollectionContent(ctx)
    end
end

--- 显示英雄收藏弹出层
function DeployPopup.ShowCollectionPopup(ctx)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local pageRoot = ctx.GetPageRoot()

    if ctx.GetCollectionOverlay() then
        -- 已经打开则刷新
        DeployPopup.RefreshCollectionContent(ctx)
        return
    end

    -- 创建内容容器
    popupContentContainer = UI.Panel {
        flexGrow = 1, flexShrink = 1,
        width = "100%",
        flexDirection = "column",
    }

    -- 弹出面板
    local popup = UI.Panel {
        position = "absolute",
        top = 10, left = 8, right = 8, bottom = 10,
        backgroundColor = S.popupBg,
        borderRadius = 12,
        borderWidth = 1,
        borderColor = S.popupBorder,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 内容容器
            popupContentContainer,
            -- 底部返回按钮
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
                flexShrink = 0,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        paddingLeft = 14, paddingRight = 18,
                        paddingTop = 6, paddingBottom = 6,
                        backgroundColor = { 80, 60, 45, 230 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 140, 110, 70, 150 },
                        onClick = function(self)
                            DeployPopup.HideCollectionPopup(ctx)
                        end,
                        children = {
                            UI.Label {
                                text = "<",
                                fontSize = 14,
                                fontColor = { 180, 160, 130, 200 },
                            },
                            UI.Label {
                                text = "返回",
                                fontSize = 14,
                                fontColor = S.white,
                            },
                        },
                    },
                },
            },
        },
    }

    -- 半透明遮罩（点击关闭）
    local overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 100,
        backgroundColor = S.overlayBg,
        children = { popup },
    }

    ctx.SetCollectionOverlay(overlay)

    -- 填充内容
    DeployPopup.RefreshCollectionContent(ctx)

    -- 添加到页面
    pageRoot:AddChild(overlay)
end

--- 隐藏英雄收藏弹出层
function DeployPopup.HideCollectionPopup(ctx)
    -- 清理交换状态
    CloseSwapConfirm(ctx)
    swapSourceHeroId = nil
    swapHintBanner = nil

    local overlay = ctx.GetCollectionOverlay()
    if overlay then
        local pageRoot = ctx.GetPageRoot()
        pageRoot:RemoveChild(overlay)
        ctx.SetCollectionOverlay(nil)
        popupContentContainer = nil
        local HeroCardMod = require("Game.HeroUI.HeroCard")
        HeroCardMod.ClearCache("deploy")
        -- 关闭后刷新主页（上阵列表可能变化）
        ctx.Refresh()
    end
end

return DeployPopup
