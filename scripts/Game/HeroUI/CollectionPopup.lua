-- Game/HeroUI/CollectionPopup.lua
-- 英雄收藏弹出层（查看详情，点击进入英雄详情面板）

local CollectionPopup = {}

--- 详情弹出层内容容器
---@type any
local detailPopupContentContainer = nil

--- 页面重建时清理局部状态
function CollectionPopup.OnPageClear()
    detailPopupContentContainer = nil
    local HeroCardMod = require("Game.HeroUI.HeroCard")
    HeroCardMod.ClearCache("detail")
end

--- 刷新英雄收藏弹出层内容
function CollectionPopup.RefreshCollectionDetailContent(ctx)
    if not detailPopupContentContainer then return end
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local HeroCardMod = require("Game.HeroUI.HeroCard")

    HeroCardMod.ClearCache("detail")
    detailPopupContentContainer:ClearChildren()

    -- 标题栏
    detailPopupContentContainer:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        paddingTop = 4, paddingBottom = 6,
        paddingLeft = 12, paddingRight = 12,
        flexShrink = 0,
        children = {
            UI.Label { text = "英雄收藏", fontSize = 15, fontColor = S.white, fontWeight = "bold" },
        },
    })

    -- 英雄网格（detail 模式）
    detailPopupContentContainer:AddChild(HeroCardMod.CreateHeroGrid(ctx, "detail"))
end

--- 显示英雄收藏弹出层
function CollectionPopup.ShowCollectionDetailPopup(ctx)
    local UI = ctx.GetUI()
    local S = ctx.GetS()
    local pageRoot = ctx.GetPageRoot()

    if ctx.GetCollectionDetailOverlay() then
        CollectionPopup.RefreshCollectionDetailContent(ctx)
        return
    end

    detailPopupContentContainer = UI.Panel {
        flexGrow = 1, flexShrink = 1,
        width = "100%",
        flexDirection = "column",
    }

    local popup = UI.Panel {
        position = "absolute",
        top = 10, left = 8, right = 8, bottom = 10,
        backgroundColor = S.popupBg,
        borderRadius = 12,
        borderWidth = 1,
        borderColor = { 150, 115, 190, 200 },
        flexDirection = "column",
        overflow = "hidden",
        children = {
            detailPopupContentContainer,
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
                            CollectionPopup.HideCollectionDetailPopup(ctx)
                        end,
                        children = {
                            UI.Label { text = "<", fontSize = 14, fontColor = { 180, 160, 130, 200 } },
                            UI.Label { text = "返回", fontSize = 14, fontColor = S.white },
                        },
                    },
                },
            },
        },
    }

    local overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        zIndex = 100,
        backgroundColor = S.overlayBg,
        children = { popup },
    }

    ctx.SetCollectionDetailOverlay(overlay)
    CollectionPopup.RefreshCollectionDetailContent(ctx)
    pageRoot:AddChild(overlay)
end

--- 隐藏英雄收藏弹出层
function CollectionPopup.HideCollectionDetailPopup(ctx)
    local overlay = ctx.GetCollectionDetailOverlay()
    if overlay then
        local pageRoot = ctx.GetPageRoot()
        pageRoot:RemoveChild(overlay)
        ctx.SetCollectionDetailOverlay(nil)
        detailPopupContentContainer = nil
        local HeroCardMod = require("Game.HeroUI.HeroCard")
        HeroCardMod.ClearCache("detail")
    end
end

return CollectionPopup
