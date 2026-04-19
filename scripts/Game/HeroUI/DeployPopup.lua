-- Game/HeroUI/DeployPopup.lua
-- 上阵管理弹出层（上阵/下阵切换）

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")

local DeployPopup = {}

--- 收藏弹出层内容容器（用于局部刷新）
---@type any
local popupContentContainer = nil

--- 页面重建时清理局部状态
function DeployPopup.OnPageClear()
    popupContentContainer = nil
end

--- 刷新收藏弹出层网格内容（不重建整个弹出层）
function DeployPopup.RefreshCollectionContent(ctx)
    if not popupContentContainer then return end
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local HeroCardMod = require("Game.HeroUI.HeroCard")

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

--- 卡片点击处理：上阵/下阵切换
function DeployPopup.HandleCardClick(ctx, heroId, isUnlocked, isDeployed)
    if not isUnlocked then
        print("[HeroUI] " .. heroId .. " is locked")
        return
    end

    local ok, msg
    if isDeployed then
        ok, msg = HeroData.Undeploy(heroId)
    else
        ok, msg = HeroData.Deploy(heroId)
    end
    print("[HeroUI] " .. (isDeployed and "Undeploy" or "Deploy") .. " " .. heroId .. ": " .. msg)

    local success, AudioManager = pcall(require, "Game.AudioManager")
    if success and AudioManager then
        if ok then
            AudioManager.PlayUpgrade()
        end
    end

    -- 刷新弹出层内容
    DeployPopup.RefreshCollectionContent(ctx)
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
    local overlay = ctx.GetCollectionOverlay()
    if overlay then
        local pageRoot = ctx.GetPageRoot()
        pageRoot:RemoveChild(overlay)
        ctx.SetCollectionOverlay(nil)
        popupContentContainer = nil
        -- 关闭后刷新主页（上阵列表可能变化）
        ctx.Refresh()
    end
end

return DeployPopup
