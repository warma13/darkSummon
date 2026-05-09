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
    { id = 1, name = "1服 - 征途之始", status = "流畅" },
    { id = 2, name = "2服 - 暗影新途", status = "流畅", tag = "推荐" },
}

--- 从云端元数据中找出最近登录的服务器（timestamp 最大的 slot）
---@param meta table|nil
---@return number serverId
local function GetLastServerFromMeta(meta)
    if meta and meta.slots then
        local bestId, bestTs = nil, 0
        for slotIdStr, slot in pairs(meta.slots) do
            local ts = slot.timestamp or 0
            if ts > bestTs then
                bestTs = ts
                bestId = tonumber(slotIdStr)
            end
        end
        if bestId then
            -- 验证该服务器在列表中存在
            for _, s in ipairs(SERVER_LIST) do
                if s.id == bestId then return bestId end
            end
        end
    end
    -- 新玩家/无存档：默认最新服
    return SERVER_LIST[#SERVER_LIST].id
end

local selectedServerId = SERVER_LIST[#SERVER_LIST].id

-- 加载状态：loading / ready / error
local loadState = "loading"
local loadErrorMsg = nil
---@type function|nil
local retryCallback = nil

--- 设置加载状态（外部调用）
---@param state string  "loading" | "ready" | "error"
---@param errMsg string|nil  错误信息（state="error"时使用）
function ServerSelectUI.SetLoadState(state, errMsg)
    loadState = state
    loadErrorMsg = errMsg
    ServerSelectUI.Refresh()
end

--- 设置重试回调
function ServerSelectUI.SetRetryCallback(fn)
    retryCallback = fn
end

--- 更新存档元数据（SlotSave加载完成后调用）
--- 同时根据 timestamp 自动选中上次登录的服务器
function ServerSelectUI.UpdateSlotMeta(meta)
    slotMeta = meta
    selectedServerId = GetLastServerFromMeta(meta)
end

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
        pointerEvents = "auto",  -- 全屏遮罩，拦截底层点击
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
            BuildServerSelector(),
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
                text = "暗影召唤：超越征途",
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

--- 获取某个槽位的存档摘要
---@param slotId number
---@return table|nil  { leaderLevel, bestStage, heroCount, playTime, timestamp }
local function GetSlotSummary(slotId)
    if not slotMeta or not slotMeta.slots then return nil end
    return slotMeta.slots[tostring(slotId)]
end

--- 根据 id 找到服务器数据
---@param id number
---@return table|nil
local function FindServerById(id)
    for _, s in ipairs(SERVER_LIST) do
        if s.id == id then return s end
    end
    return nil
end

--- 获取最新服务器ID（列表中 id 最大的）
---@return number
local function GetNewestServerId()
    local maxId = SERVER_LIST[1].id
    for _, s in ipairs(SERVER_LIST) do
        if s.id > maxId then maxId = s.id end
    end
    return maxId
end

--- 判断玩家是否可以进入该服务器
--- 最新服务器所有人都可进；老服务器仅有存档的玩家可进
---@param serverId number
---@return boolean canEnter
local function CanEnterServer(serverId)
    if serverId == GetNewestServerId() then return true end
    return GetSlotSummary(serverId) ~= nil
end

--- 构建当前选中服务器的显示框（点击打开选服弹窗）
function BuildServerSelector()
    local server = FindServerById(selectedServerId) or SERVER_LIST[1]
    local summary = GetSlotSummary(server.id)
    local statusColor = { 80, 200, 120, 255 }

    -- 存档摘要行
    local summaryChildren = {}
    if summary then
        summaryChildren = {
            UI.Panel {
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
            },
        }
    end

    -- 状态 + 标签行
    local statusRowChildren = {
        -- 绿点
        UI.Panel {
            width = 8, height = 8,
            borderRadius = 4,
            backgroundColor = statusColor,
        },
        UI.Label {
            text = server.status,
            fontSize = 12,
            fontColor = statusColor,
        },
    }
    if server.tag then
        statusRowChildren[#statusRowChildren + 1] = UI.Panel {
            paddingLeft = 6, paddingRight = 6,
            paddingTop = 2, paddingBottom = 2,
            backgroundColor = { 200, 120, 50, 255 },
            borderRadius = 4,
            marginLeft = 4,
            children = {
                UI.Label {
                    text = server.tag,
                    fontSize = 10,
                    fontColor = { 255, 255, 255, 255 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
        children = {
            -- "选择区服"小标题
            UI.Panel {
                width = "100%",
                paddingLeft = 4, paddingBottom = 2,
                children = {
                    UI.Label {
                        text = "选择区服",
                        fontSize = 14,
                        fontColor = { 160, 140, 200, 255 },
                    },
                },
            },
            -- 显示框：当前选中服务器
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 14, paddingBottom = 14,
                backgroundColor = { 50, 35, 80, 255 },
                borderWidth = 2,
                borderColor = { 140, 100, 240, 255 },
                borderRadius = 8,
                gap = 10,
                pointerEvents = "auto",
                onClick = function(self)
                    ShowServerPickerPopup()
                end,
                children = {
                    -- 服务器信息
                    UI.Panel {
                        flex = 1,
                        flexDirection = "column",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = server.name,
                                fontSize = 16,
                                fontColor = { 230, 210, 255, 255 },
                            },
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                children = statusRowChildren,
                            },
                            table.unpack(summaryChildren),
                        },
                    },
                    -- 右侧展开箭头
                    UI.Label {
                        text = "▼",
                        fontSize = 14,
                        fontColor = { 160, 140, 220, 200 },
                    },
                },
            },
        },
    }
end

--- 显示服务器选择弹窗
function ShowServerPickerPopup()
    if not pageRoot or not UI then return end

    -- 移除已有弹窗
    local old = pageRoot:FindById("serverPickerPopup")
    if old then pageRoot:RemoveChild(old) end

    local function closePopup()
        local p = pageRoot:FindById("serverPickerPopup")
        if p then pageRoot:RemoveChild(p) end
    end

    -- 构建服务器列表条目
    local newestId = GetNewestServerId()
    local listChildren = {}
    for _, server in ipairs(SERVER_LIST) do
        local isSelected = (server.id == selectedServerId)
        local summary = GetSlotSummary(server.id)
        local canEnter = CanEnterServer(server.id)
        local isLocked = not canEnter  -- 老服无存档，锁定

        -- 锁定状态用灰色，否则正常
        local statusColor = isLocked
            and { 100, 100, 100, 180 }
            or  { 80, 200, 120, 255 }
        local statusText = isLocked and "已满" or server.status

        -- 状态 + 标签
        local tagChildren = {}
        if server.tag and not isLocked then
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

        local infoRowChildren = {
            UI.Panel {
                width = 8, height = 8,
                borderRadius = 4,
                backgroundColor = isLocked and { 180, 60, 60, 200 } or statusColor,
            },
            UI.Label {
                text = statusText,
                fontSize = 12,
                fontColor = isLocked and { 180, 60, 60, 200 } or statusColor,
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

        -- 名称颜色：锁定灰色，选中高亮，普通次亮
        local nameColor = isLocked
            and { 120, 110, 130, 180 }
            or  (isSelected and { 230, 210, 255, 255 } or { 200, 190, 220, 255 })

        local nameColChildren = {
            UI.Label {
                text = server.name,
                fontSize = 16,
                fontColor = nameColor,
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = infoRowChildren,
            },
        }
        if summaryRow then
            nameColChildren[#nameColChildren + 1] = summaryRow
        end

        -- 条目背景/边框：锁定时暗淡
        local itemBg = isLocked and { 25, 20, 35, 255 }
            or (isSelected and { 50, 35, 80, 255 } or { 30, 24, 45, 255 })
        local itemBorder = isLocked and { 50, 45, 60, 120 }
            or (isSelected and { 140, 100, 240, 255 } or { 60, 50, 80, 120 })

        -- 选中圆点：锁定时也暗淡
        local radioOuter = isLocked and { 60, 55, 70, 150 }
            or (isSelected and { 140, 100, 240, 255 } or { 80, 70, 110, 255 })
        local radioBg = isSelected and not isLocked
            and { 140, 100, 240, 255 } or { 0, 0, 0, 0 }

        listChildren[#listChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 14, paddingRight = 14,
            paddingTop = 12, paddingBottom = 12,
            backgroundColor = itemBg,
            borderWidth = (isSelected and not isLocked) and 2 or 1,
            borderColor = itemBorder,
            borderRadius = 8,
            gap = 10,
            pointerEvents = "auto",
            onClick = function(self)
                if isLocked then
                    local Toast = require("Game.Toast")
                    Toast.Show("服务器人数已满")
                    return
                end
                selectedServerId = server.id
                closePopup()
                ServerSelectUI.Refresh()
            end,
            children = {
                -- 选中圆点
                UI.Panel {
                    width = 18, height = 18,
                    borderRadius = 9,
                    borderWidth = 2,
                    borderColor = radioOuter,
                    backgroundColor = radioBg,
                    justifyContent = "center",
                    alignItems = "center",
                    children = (isSelected and not isLocked) and {
                        UI.Panel {
                            width = 8, height = 8,
                            borderRadius = 4,
                            backgroundColor = { 255, 255, 255, 255 },
                        },
                    } or {},
                },
                -- 服务器信息
                UI.Panel {
                    flex = 1,
                    flexDirection = "column",
                    gap = 4,
                    children = nameColChildren,
                },
            },
        }
    end

    local popup = UI.Panel {
        id = "serverPickerPopup",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        zIndex = 10,
        onClick = function(self) closePopup() end,
        children = {
            UI.Panel {
                width = 320,
                backgroundColor = { 20, 14, 40, 250 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 160, 120, 255, 160 },
                paddingTop = 18, paddingBottom = 18,
                paddingLeft = 16, paddingRight = 16,
                gap = 12,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end, -- 阻止冒泡关闭
                children = {
                    -- 标题
                    UI.Label {
                        text = "选择区服",
                        fontSize = 18,
                        fontColor = { 200, 170, 255, 255 },
                        fontWeight = "bold",
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 60 } },
                    -- 服务器列表
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 8,
                        children = listChildren,
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },
                    -- 关闭按钮
                    UI.Panel {
                        width = 140, height = 36,
                        backgroundColor = { 60, 45, 90, 200 },
                        borderRadius = 18,
                        borderWidth = 1,
                        borderColor = { 140, 100, 240, 100 },
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self) closePopup() end,
                        children = {
                            UI.Label {
                                text = "关闭",
                                fontSize = 14,
                                fontColor = { 200, 180, 255, 230 },
                            },
                        },
                    },
                },
            },
        },
    }

    pageRoot:AddChild(popup)
end

--- 构建开始游戏按钮（根据加载状态显示不同内容）
function BuildStartButton()
    -- 加载中状态
    if loadState == "loading" then
        return UI.Panel {
            width = "100%",
            paddingTop = 10,
            alignItems = "center",
            gap = 8,
            children = {
                UI.Panel {
                    width = 220, height = 48,
                    backgroundColor = { 60, 45, 90, 200 },
                    borderRadius = 24,
                    borderWidth = 1,
                    borderColor = { 100, 80, 140, 100 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "正在加载存档...",
                            fontSize = 16,
                            fontColor = { 180, 170, 220, 200 },
                            textAlign = "center",
                        },
                    },
                },
            },
        }
    end

    -- 加载失败状态
    if loadState == "error" then
        return UI.Panel {
            width = "100%",
            paddingTop = 10,
            alignItems = "center",
            gap = 10,
            children = {
                UI.Label {
                    text = loadErrorMsg or "存档加载超时",
                    fontSize = 13,
                    fontColor = { 255, 140, 100, 220 },
                    textAlign = "center",
                },
                UI.Panel {
                    width = 220, height = 48,
                    backgroundColor = { 200, 100, 50, 255 },
                    borderRadius = 24,
                    justifyContent = "center",
                    alignItems = "center",
                    pointerEvents = "auto",
                    onClick = function(self)
                        if retryCallback then
                            retryCallback()
                        end
                    end,
                    children = {
                        UI.Label {
                            text = "重新加载",
                            fontSize = 18,
                            fontColor = { 255, 255, 255, 255 },
                            textAlign = "center",
                        },
                    },
                },
            },
        }
    end

    -- 正常就绪状态
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
                                        text = "憎恨之地开启。",
                                        fontSize = 13,
                                        fontColor = { 200, 200, 220, 220 },
                                    },
                                    UI.Label {
                                        text = "进行了一些优化。修复了一些bug。",
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
                                    UI.Label {
                                        text = "进群领福利，招募券100抽",
                                        fontSize = 13,
                                        fontColor = { 255, 200, 60, 255 },
                                        fontWeight = "bold",
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
