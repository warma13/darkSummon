-- Game/ServerSelectUI.lua
-- 区服选择界面

local Config = require("Game.Config")

local ServerSelectUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type function|nil
local onStartCallback = nil
---@type table|nil
local slotMeta = nil

-- 服务器列表数据
local SERVER_LIST = {
    { id = 1, name = "1服 - 征途之始", status = "流畅", tag = "推荐" },
}

local selectedServerId = 1

--- 格式化游戏时长（秒 → "Xh Xm"）
local function FormatPlayTime(seconds)
    if not seconds or seconds <= 0 then return "0m" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

--- 创建区服选择页面
---@param uiModule any
---@param onStart function  点击开始游戏的回调
---@param meta table|nil  存档元数据（来自 SlotSaveSystem）
---@return any
function ServerSelectUI.CreatePage(uiModule, onStart, meta)
    UI = uiModule
    onStartCallback = onStart
    slotMeta = meta

    pageRoot = UI.Panel {
        id = "serverSelectPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage = "image/首页背景.png",
        backgroundFit = "cover",
        backgroundColor = { 12, 8, 20, 255 },
        justifyContent = "center",
        alignItems = "center",
        visible = true,
    }

    ServerSelectUI.Refresh()
    ServerSelectUI.ShowAnnouncementPopup()
    return pageRoot
end

--- 刷新页面
function ServerSelectUI.Refresh()
    if not pageRoot or not UI then return end
    pageRoot:ClearChildren()

    -- 主卡片容器
    local card = UI.Panel {
        width = 320,
        flexDirection = "column",
        alignItems = "center",
        gap = 20,
        children = {
            BuildTitle(),
            BuildServerList(),
            BuildStartButton(),
        },
    }

    pageRoot:AddChild(card)

    -- 底部QQ群信息（绝对定位在底部）
    local qqBar = UI.Panel {
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        backgroundColor = { 8, 4, 16, 220 },
        paddingTop = 10, paddingBottom = 14,
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = "QQ群：1098942898",
                fontSize = 14,
                fontColor = { 200, 200, 255, 230 },
                textAlign = "center",
            },
            UI.Label {
                text = "进群领福利，反馈bug领奖励",
                fontSize = 11,
                fontColor = { 180, 180, 220, 170 },
                textAlign = "center",
            },
        },
    }
    pageRoot:AddChild(qqBar)

    -- 左上角公告按钮
    local announcementBtn = UI.Panel {
        position = "absolute",
        top = 40, left = 16,
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        backgroundColor = { 80, 50, 160, 200 },
        borderRadius = 14,
        borderWidth = 1,
        borderColor = { 160, 120, 255, 120 },
        paddingTop = 6, paddingBottom = 6,
        paddingLeft = 12, paddingRight = 12,
        pointerEvents = "auto",
        zIndex = 2,
        onClick = function(self)
            ServerSelectUI.ShowAnnouncementPopup()
        end,
        children = {
            UI.Label {
                text = "公告",
                fontSize = 13,
                fontColor = { 220, 200, 255, 255 },
            },
            -- 红点提示
            UI.Panel {
                width = 8, height = 8,
                borderRadius = 4,
                backgroundColor = { 255, 60, 60, 255 },
                marginLeft = 2,
            },
        },
    }
    pageRoot:AddChild(announcementBtn)
end

--- 构建标题区
function BuildTitle()
    return UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 6,
        paddingBottom = 10,
        children = {
            -- 装饰线
            UI.Panel {
                width = 200, height = 2,
                backgroundColor = { 120, 80, 200, 150 },
                borderRadius = 1,
            },
            UI.Label {
                text = "暗黑召唤：无尽征途",
                fontSize = 26,
                fontWeight = "bold",
                fontColor = { 220, 200, 255, 255 },
                textAlign = "center",
            },
            UI.Panel {
                width = 200, height = 2,
                backgroundColor = { 120, 80, 200, 150 },
                borderRadius = 1,
            },
        },
    }
end

--- 构建服务器列表
function BuildServerList()
    local children = {
        -- "选择区服"小标题
        UI.Panel {
            width = "100%",
            paddingLeft = 4, paddingBottom = 6,
            children = {
                UI.Label {
                    text = "选择区服",
                    fontSize = 14,
                    fontColor = { 160, 140, 200, 255 },
                },
            },
        },
    }

    for _, server in ipairs(SERVER_LIST) do
        children[#children + 1] = BuildServerItem(server)
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 8,
        children = children,
    }
end

--- 获取某个槽位的存档摘要
---@param slotId number
---@return table|nil  { leaderLevel, bestStage, heroCount, playTime, timestamp }
local function GetSlotSummary(slotId)
    if not slotMeta or not slotMeta.slots then return nil end
    return slotMeta.slots[tostring(slotId)]
end

--- 构建单个服务器条目
---@param server table
function BuildServerItem(server)
    local isSelected = (server.id == selectedServerId)

    local borderColor = isSelected
        and { 140, 100, 240, 255 }
        or  { 60, 50, 80, 180 }
    local bgColor = isSelected
        and { 50, 35, 80, 255 }
        or  { 30, 24, 45, 255 }

    -- 状态标签颜色
    local statusColor = { 80, 200, 120, 255 }  -- 流畅=绿色

    -- 右侧标签
    local tagChildren = {}
    if server.tag then
        tagChildren[#tagChildren + 1] = UI.Panel {
            paddingLeft = 6, paddingRight = 6,
            paddingTop = 2, paddingBottom = 2,
            backgroundColor = { 200, 120, 50, 255 },
            borderRadius = 4,
            children = {
                UI.Label {
                    text = server.tag,
                    fontSize = 10,
                    fontColor = { 255, 255, 255, 255 },
                },
            },
        }
    end

    -- 存档摘要（如果有）
    local summary = GetSlotSummary(server.id)
    local infoChildren = {
        UI.Label {
            text = server.status,
            fontSize = 12,
            fontColor = statusColor,
        },
        table.unpack(tagChildren),
    }

    -- 存档摘要行
    local summaryRow = nil
    if summary then
        summaryRow = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            paddingTop = 2,
            children = {
                UI.Label {
                    text = "Lv." .. (summary.leaderLevel or 1),
                    fontSize = 11,
                    fontColor = { 200, 180, 255, 200 },
                },
                UI.Label {
                    text = "第" .. (summary.bestStage or 0) .. "关",
                    fontSize = 11,
                    fontColor = { 180, 200, 160, 200 },
                },
                UI.Label {
                    text = (summary.heroCount or 0) .. "英雄",
                    fontSize = 11,
                    fontColor = { 200, 180, 140, 200 },
                },
                UI.Label {
                    text = FormatPlayTime(summary.playTime),
                    fontSize = 11,
                    fontColor = { 160, 160, 180, 180 },
                },
            },
        }
    end

    -- 名称列的子元素
    local nameColumnChildren = {
        UI.Label {
            text = server.name,
            fontSize = 16,
            fontColor = isSelected
                and { 230, 210, 255, 255 }
                or  { 180, 170, 200, 255 },
        },
        UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = infoChildren,
        },
    }
    if summaryRow then
        nameColumnChildren[#nameColumnChildren + 1] = summaryRow
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 14, paddingBottom = 14,
        backgroundColor = bgColor,
        borderWidth = isSelected and 2 or 1,
        borderColor = borderColor,
        borderRadius = 8,
        gap = 10,
        pointerEvents = "auto",
        onClick = function(self)
            selectedServerId = server.id
            ServerSelectUI.Refresh()
        end,
        children = {
            -- 选中标记
            UI.Panel {
                width = 18, height = 18,
                borderRadius = 9,
                borderWidth = 2,
                borderColor = isSelected and { 140, 100, 240, 255 } or { 80, 70, 110, 255 },
                backgroundColor = isSelected and { 140, 100, 240, 255 } or { 0, 0, 0, 0 },
                justifyContent = "center",
                alignItems = "center",
                children = isSelected and {
                    UI.Panel {
                        width = 8, height = 8,
                        borderRadius = 4,
                        backgroundColor = { 255, 255, 255, 255 },
                    },
                } or {},
            },
            -- 服务器名称 + 存档摘要
            UI.Panel {
                flex = 1,
                flexDirection = "column",
                gap = 4,
                children = nameColumnChildren,
            },
        },
    }
end

--- 构建开始游戏按钮
function BuildStartButton()
    return UI.Panel {
        width = "100%",
        paddingTop = 10,
        alignItems = "center",
        children = {
            UI.Panel {
                width = 220, height = 48,
                backgroundColor = { 120, 70, 220, 255 },
                borderRadius = 24,
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self)
                    if onStartCallback then
                        onStartCallback(selectedServerId)
                    end
                end,
                children = {
                    UI.Label {
                        text = "开始游戏",
                        fontSize = 18,
                        fontColor = { 255, 255, 255, 255 },
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

--- 显示更新公告弹窗
function ServerSelectUI.ShowAnnouncementPopup()
    if not pageRoot or not UI then return end

    local old = pageRoot:FindById("announcementPopup")
    if old then pageRoot:RemoveChild(old) end

    local function closePopup()
        local p = pageRoot:FindById("announcementPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    local popup = UI.Panel {
        id = "announcementPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self) closePopup() end,
        children = {
            UI.Panel {
                width = 310,
                backgroundColor = { 20, 14, 40, 250 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 160, 120, 255, 160 },
                paddingTop = 18, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                gap = 16,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,
                children = {
                    -- 标题
                    UI.Label {
                        text = "公告",
                        fontSize = 20,
                        fontColor = { 200, 170, 255, 255 },
                        fontWeight = "bold",
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 60 } },

                    -- 更新公告区
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "[ 更新公告 ]",
                                fontSize = 15,
                                fontColor = { 255, 180, 80, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                width = "100%",
                                backgroundColor = { 40, 30, 70, 200 },
                                borderRadius = 8,
                                paddingTop = 10, paddingBottom = 10,
                                paddingLeft = 12, paddingRight = 12,
                                gap = 6,
                                children = {
                                    UI.Label {
                                        text = "招募周开启，达成招募目标获得奖励。",
                                        fontSize = 13,
                                        fontColor = { 200, 200, 220, 220 },
                                    },
                                    UI.Label {
                                        text = "限定池「苍华极脉」已于4月22日开放。",
                                        fontSize = 13,
                                        fontColor = { 200, 200, 220, 220 },
                                    },
                                },
                            },
                        },
                    },

                    -- 官方QQ群区
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "[ 官方QQ群 ]",
                                fontSize = 15,
                                fontColor = { 100, 200, 130, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                width = "100%",
                                backgroundColor = { 20, 45, 35, 200 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 100, 200, 130, 80 },
                                paddingTop = 10, paddingBottom = 10,
                                paddingLeft = 12, paddingRight = 12,
                                gap = 4,
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "1098942898",
                                        fontSize = 16,
                                        fontColor = { 150, 230, 180, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "进群领福利，反馈bug领奖励",
                                        fontSize = 12,
                                        fontColor = { 180, 220, 190, 180 },
                                    },
                                },
                            },
                        },
                    },

                    -- 限时活动区
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "[ 限时活动 ]",
                                fontSize = 15,
                                fontColor = { 255, 100, 100, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                width = "100%",
                                backgroundColor = { 60, 20, 30, 200 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 255, 80, 80, 80 },
                                paddingTop = 10, paddingBottom = 10,
                                paddingLeft = 12, paddingRight = 12,
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "评价截图找群主领取",
                                        fontSize = 13,
                                        fontColor = { 255, 220, 180, 230 },
                                    },
                                    UI.Panel {
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 4,
                                        children = {
                                            UI.Label {
                                                text = "限定招募券·霜誓契约",
                                                fontSize = 13,
                                                fontColor = { 130, 210, 255, 255 },
                                                fontWeight = "bold",
                                            },
                                            UI.Label {
                                                text = " x100张",
                                                fontSize = 14,
                                                fontColor = { 255, 200, 60, 255 },
                                                fontWeight = "bold",
                                            },
                                        },
                                    },
                                },
                            },
                            -- 英雄设计师活动
                            UI.Panel {
                                width = "100%",
                                backgroundColor = { 20, 40, 60, 200 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 100, 180, 255, 80 },
                                paddingTop = 10, paddingBottom = 10,
                                paddingLeft = 12, paddingRight = 12,
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "英雄设计师活动",
                                        fontSize = 14,
                                        fontColor = { 255, 220, 100, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "在TapTap「暗影召唤师」论坛发帖，发表你关于LR英雄-永恒魔君的设计方案。",
                                        fontSize = 12,
                                        fontColor = { 220, 210, 230, 220 },
                                    },
                                    UI.Panel {
                                        flexDirection = "row",
                                        alignItems = "center",
                                        flexWrap = "wrap",
                                        gap = 4,
                                        children = {
                                            UI.Label {
                                                text = "奖励：",
                                                fontSize = 12,
                                                fontColor = { 180, 180, 200, 200 },
                                            },
                                            UI.Label {
                                                text = "大量限定抽奖券",
                                                fontSize = 12,
                                                fontColor = { 130, 210, 255, 255 },
                                                fontWeight = "bold",
                                            },
                                            UI.Label {
                                                text = " + 暗影精粹",
                                                fontSize = 12,
                                                fontColor = { 200, 130, 255, 255 },
                                                fontWeight = "bold",
                                            },
                                            UI.Label {
                                                text = " + 限定称号",
                                                fontSize = 12,
                                                fontColor = { 255, 200, 60, 255 },
                                                fontWeight = "bold",
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 关闭按钮
                    UI.Panel {
                        width = 160, height = 40,
                        backgroundColor = { 120, 70, 220, 255 },
                        borderRadius = 20,
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self) closePopup() end,
                        children = {
                            UI.Label {
                                text = "知道了",
                                fontSize = 15,
                                fontColor = { 255, 255, 255, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    pageRoot:AddChild(popup)
end

--- 显示/隐藏
function ServerSelectUI.Show()
    if pageRoot then pageRoot:SetVisible(true) end
end

function ServerSelectUI.Hide()
    if pageRoot then pageRoot:SetVisible(false) end
end

--- 获取选中的服务器ID
function ServerSelectUI.GetSelectedServer()
    return selectedServerId
end

return ServerSelectUI
