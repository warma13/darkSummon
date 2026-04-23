-- Game/SweepPopup.lua
-- 通用扫荡弹窗：选择扫荡次数 → 消耗门票 → 按上一轮成绩结算奖励
--
-- 用法：
--   local SweepPopup = require("Game.SweepPopup")
--   SweepPopup.Show(UI, root, S, {
--       title       = "冥晶矿洞 · 连续扫荡",
--       maxCount    = 5,               -- 可扫荡的最大次数（= 可用门票数）
--       sweepLabel  = "波",            -- 结算单位标签（"波" 或 "伤害"）
--       sweepValue  = "第 12 波",      -- 上次最高成绩显示
--       previewFn   = function(count)  -- 预览指定次数的总奖励
--           return { { icon = "...", name = "冥晶", amount = 12000 * count } }
--       end,
--       onConfirm   = function(count)  -- 确认扫荡回调（负责消耗门票+发放奖励+刷新UI）
--       end,
--   })

local SweepPopup = {}
local POPUP_ID = "sweepPopup"

--- 显示扫荡选择弹窗
---@param UI any
---@param root any      UI 根节点
---@param S table       样式表
---@param opts table    见文件头注释
function SweepPopup.Show(UI, root, S, opts)
    local title      = opts.title or "连续扫荡"
    local maxCount   = opts.maxCount or 1
    local sweepLabel = opts.sweepLabel or "成绩"
    local sweepValue = opts.sweepValue or "—"
    local previewFn  = opts.previewFn
    local onConfirm  = opts.onConfirm

    -- 移除旧弹窗
    local old = root:FindById(POPUP_ID)
    if old then root:RemoveChild(old) end

    -- 当前选择数量
    local selectedCount = math.min(maxCount, 1)

    -- ---- 构建弹窗内容 ----
    local function rebuild()
        local existing = root:FindById(POPUP_ID)
        if existing then root:RemoveChild(existing) end

        -- 奖励预览
        local previewChildren = {}
        if previewFn then
            local items = previewFn(selectedCount)
            for _, item in ipairs(items) do
                previewChildren[#previewChildren + 1] = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    paddingTop = 2, paddingBottom = 2,
                    children = {
                        item.icon and UI.Panel {
                            width = 18, height = 18,
                            backgroundImage = (type(item.icon) == "string" and (item.icon:find("%.png$") or item.icon:find("%.jpg$")))
                                and item.icon or nil,
                            pointerEvents = "none",
                            children = (type(item.icon) == "string" and not (item.icon:find("%.png$") or item.icon:find("%.jpg$")))
                                and { UI.Label { text = item.icon, fontSize = 14, pointerEvents = "none" } }
                                or nil,
                        } or nil,
                        UI.Label {
                            text = (item.name or "") .. " ×" .. (item.amount or 0),
                            fontSize = 13, fontColor = item.color or S.gold,
                            pointerEvents = "none",
                        },
                    },
                }
            end
        end

        -- 数量选择器
        local countSelector = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 16,
            paddingTop = 8, paddingBottom = 8,
            children = {
                UI.Panel {
                    width = 40, height = 40,
                    justifyContent = "center", alignItems = "center",
                    borderRadius = 20,
                    backgroundColor = selectedCount > 1 and { 80, 80, 120, 200 } or { 40, 40, 50, 120 },
                    onClick = selectedCount > 1 and function()
                        selectedCount = selectedCount - 1
                        rebuild()
                    end or nil,
                    children = {
                        UI.Label {
                            text = "−", fontSize = 22, fontWeight = "bold",
                            fontColor = selectedCount > 1 and S.white or S.dim,
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Label {
                    text = tostring(selectedCount),
                    fontSize = 32, fontWeight = "bold",
                    fontColor = S.white,
                    pointerEvents = "none",
                    width = 50,
                    textAlign = "center",
                },
                UI.Panel {
                    width = 40, height = 40,
                    justifyContent = "center", alignItems = "center",
                    borderRadius = 20,
                    backgroundColor = selectedCount < maxCount and { 80, 80, 120, 200 } or { 40, 40, 50, 120 },
                    onClick = selectedCount < maxCount and function()
                        selectedCount = selectedCount + 1
                        rebuild()
                    end or nil,
                    children = {
                        UI.Label {
                            text = "+", fontSize = 22, fontWeight = "bold",
                            fontColor = selectedCount < maxCount and S.white or S.dim,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }

        -- 快捷按钮行
        local quickButtons = {}
        local quickVals = { 1, 3, 5, maxCount }
        -- 去重 & 过滤
        local seen = {}
        local uniqueVals = {}
        for _, v in ipairs(quickVals) do
            if v >= 1 and v <= maxCount and not seen[v] then
                seen[v] = true
                uniqueVals[#uniqueVals + 1] = v
            end
        end
        for _, v in ipairs(uniqueVals) do
            local isActive = (selectedCount == v)
            quickButtons[#quickButtons + 1] = UI.Panel {
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 4, paddingBottom = 4,
                borderRadius = 12,
                backgroundColor = isActive and { 100, 80, 200, 200 } or { 50, 50, 60, 150 },
                borderWidth = isActive and 1 or 0,
                borderColor = isActive and { 140, 120, 255, 200 } or nil,
                onClick = function()
                    selectedCount = v
                    rebuild()
                end,
                children = {
                    UI.Label {
                        text = v == maxCount and ("全部" .. v) or tostring(v),
                        fontSize = 12,
                        fontColor = isActive and S.white or S.dim,
                        pointerEvents = "none",
                    },
                },
            }
        end

        local quickRow = #quickButtons > 1 and UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 8,
            children = quickButtons,
        } or nil

        -- 弹窗主体
        local popupContent = {
            -- 标题
            UI.Label {
                text = title, fontSize = 18, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
                alignSelf = "center",
            },
            -- 上次成绩
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 6,
                paddingTop = 4,
                children = {
                    UI.Label {
                        text = "上次" .. sweepLabel .. ":", fontSize = 12,
                        fontColor = S.dim, pointerEvents = "none",
                    },
                    UI.Label {
                        text = sweepValue, fontSize = 14, fontWeight = "bold",
                        fontColor = S.gold, pointerEvents = "none",
                    },
                },
            },
            -- 分割线
            UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 80, 100, 80 }, marginTop = 4 },
            -- 选择次数标签
            UI.Label {
                text = "选择扫荡次数", fontSize = 13,
                fontColor = S.dim, pointerEvents = "none",
                alignSelf = "center",
            },
            countSelector,
        }

        if quickRow then
            popupContent[#popupContent + 1] = quickRow
        end

        -- 预览奖励
        if #previewChildren > 0 then
            popupContent[#popupContent + 1] = UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 80, 100, 80 }, marginTop = 4 }
            popupContent[#popupContent + 1] = UI.Label {
                text = "预计获得", fontSize = 13, fontColor = S.dim,
                pointerEvents = "none", alignSelf = "center",
            }
            for _, pc in ipairs(previewChildren) do
                popupContent[#popupContent + 1] = pc
            end
        end

        -- 消耗提示
        popupContent[#popupContent + 1] = UI.Label {
            text = "消耗 " .. selectedCount .. " 张挑战券",
            fontSize = 11, fontColor = { 200, 160, 80 },
            pointerEvents = "none", alignSelf = "center",
            marginTop = 4,
        }

        -- 按钮行
        popupContent[#popupContent + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 16,
            marginTop = 6,
            children = {
                UI.Button {
                    text = "取消", fontSize = 14,
                    width = 100, height = 40,
                    borderRadius = 8,
                    variant = "outline",
                    onClick = function()
                        local p = root:FindById(POPUP_ID)
                        if p then root:RemoveChild(p) end
                    end,
                },
                UI.Button {
                    text = "扫荡 ×" .. selectedCount, fontSize = 14,
                    width = 130, height = 40,
                    borderRadius = 8,
                    variant = "primary",
                    onClick = function()
                        local p = root:FindById(POPUP_ID)
                        if p then root:RemoveChild(p) end
                        if onConfirm then
                            onConfirm(selectedCount)
                        end
                    end,
                },
            },
        }

        root:AddChild(UI.Panel {
            id = POPUP_ID,
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center", alignItems = "center",
            pointerEvents = "auto",
            onClick = function()
                local p = root:FindById(POPUP_ID)
                if p then root:RemoveChild(p) end
            end,
            children = {
                UI.Panel {
                    width = 310,
                    backgroundColor = { 30, 25, 45, 240 },
                    borderRadius = 12,
                    borderWidth = 1,
                    borderColor = { 120, 80, 200, 120 },
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 16, paddingBottom = 16,
                    flexDirection = "column",
                    gap = 6,
                    pointerEvents = "auto",
                    onClick = function() end, -- 阻止冒泡关闭
                    children = popupContent,
                },
            },
        })
    end

    rebuild()
end

return SweepPopup
