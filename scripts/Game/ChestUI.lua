-- Game/ChestUI.lua
-- 宝箱页面 UI（对齐咸鱼之王宝箱界面）
-- 布局: 顶部积分进度条 → 中间大宝箱展示 → 底部宝箱选择栏

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local ChestData = require("Game.ChestData")
local Currency = require("Game.Currency")
local RewardDisplay = require("Game.RewardDisplay")
local RC = require("Game.RewardController")

local ChestUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type string
local selectedChest = "wood"  -- 当前选中的宝箱类型

-- 稀有度颜色（引用 Config 统一定义）
local RARITY_COLORS = Config.RARITY_COLORS

--- 获取货币显示名
---@param currType string
---@return string
local function GetCurrencyName(currType)
    local def = Config.CURRENCY[currType]
    if def then return def.name end
    return currType
end

--- 创建宝箱页面
---@param uiModule any
---@return any
function ChestUI.CreatePage(uiModule)
    UI = uiModule

    pageRoot = UI.Panel {
        id = "chestPage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 15, 12, 25, 255 },
        children = {},
    }

    ChestUI.Refresh()
    return pageRoot
end

--- 刷新页面内容
function ChestUI.Refresh()
    if not pageRoot or not UI then return end
    pageRoot:ClearChildren()

    -- 顶部标题
    pageRoot:AddChild(UI.Panel {
        width = "100%",
        paddingTop = 10, paddingBottom = 6,
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Label {
                text = "宝箱",
                fontSize = 20,
                fontColor = Config.COLORS.textPrimary,
                fontWeight = "bold",
            },
        },
    })

    -- 积分进度条
    pageRoot:AddChild(ChestUI.CreateScoreBar())
    -- 中间大宝箱展示区
    pageRoot:AddChild(ChestUI.CreateChestDisplay())
    -- 开箱按钮
    pageRoot:AddChild(ChestUI.CreateOpenButton())
    -- 底部宝箱选择栏
    pageRoot:AddChild(ChestUI.CreateChestSelector())
end

--- 积分进度条（左徽章 + 中进度条 + 右宝箱）
function ChestUI.CreateScoreBar()
    local info = ChestData.GetScoreProgress()
    local current = info.score
    local segStart = info.segStart
    local segEnd = info.segEnd
    local remaining = info.remaining
    local nextChestId = info.nextChestId
    local allClaimed = info.allClaimed

    local nextChestDef = nextChestId and ChestData.GetChestDef(nextChestId) or nil

    local segRange = math.max(1, segEnd - segStart)
    local segPct = math.min(1.0, math.max(0, (current - segStart) / segRange))

    -- 右侧宝箱显示
    local canClaim = (not allClaimed) and (current >= segEnd)
    local claimableCount = ChestData.GetClaimableCount()
    local batchClaim = claimableCount > 5  -- 超过5个里程碑可领取时显示一键领取
    local rightChild
    if nextChestDef then
        rightChild = UI.Panel {
            width = "20%", height = "100%",
            justifyContent = "center",
            alignItems = "center",
            gap = 2,
            paddingTop = 4, paddingBottom = 4,
            paddingLeft = 4, paddingRight = 4,
            children = {
                -- 宝箱图片
                UI.Panel {
                    width = "100%",
                    aspectRatio = 1,
                    children = {
                        UI.Panel {
                            position = "absolute",
                            top = 8, left = 0, right = 0, bottom = 0,
                            backgroundImage = "image/chest_base.png",
                            backgroundFit = "contain",
                        },
                        nextChestDef.image and UI.Panel {
                            position = "absolute",
                            top = 0, left = 4, right = 4, bottom = 4,
                            backgroundImage = nextChestDef.image,
                            backgroundFit = "contain",
                        } or UI.Label {
                            position = "absolute",
                            top = 2, left = 0, right = 0,
                            text = nextChestDef.emoji,
                            fontSize = 20,
                            textAlign = "center",
                        },
                    },
                },
                -- 领取按钮，通过控制层处理奖励展示
                UI.Button {
                    text = batchClaim and ("×" .. claimableCount) or "领取",
                    fontSize = 9,
                    height = 22,
                    width = "100%",
                    borderRadius = 4,
                    variant = "primary",
                    disabled = not canClaim,
                    onClick = function()
                        if batchClaim then
                            ChestUI.DoClaimAllMilestones()
                        else
                            ChestUI.DoClaimMilestone()
                        end
                    end,
                },
            },
        }
    else
        rightChild = UI.Panel {
            width = "20%", height = "100%",
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "已全部\n领取",
                    fontSize = 10,
                    fontColor = { 100, 200, 100, 200 },
                    textAlign = "center",
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 8, paddingBottom = 8,
        flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%",
                aspectRatio = 3.5,  -- 高度 = 宽度的约28%，左右区域更大
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = { 30, 25, 45, 220 },
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 80, 65, 110, 150 },
                overflow = "hidden",
                children = {
                    -- 左: 积分徽章 (20%)
                    UI.Panel {
                        width = "20%", height = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        paddingTop = 4, paddingBottom = 4,
                        paddingLeft = 4, paddingRight = 4,
                        children = {
                            UI.Panel {
                                width = "100%",
                                aspectRatio = 1,
                                backgroundImage = "image/score_badge.png",
                                backgroundFit = "contain",
                            },
                        },
                    },
                    -- 中: 进度信息 (60%)
                    UI.Panel {
                        width = "60%",
                        justifyContent = "center",
                        gap = 4,
                        paddingLeft = 4, paddingRight = 4,
                        children = {
                            -- 提示文字
                            UI.Label {
                                text = (not allClaimed)
                                    and ("还差" .. remaining .. "积分领取" .. (nextChestDef and nextChestDef.name or "奖励"))
                                    or "积分奖励已全部领取",
                                fontSize = 11,
                                fontColor = { 220, 200, 255, 220 },
                            },
                            -- 进度条
                            UI.Panel {
                                width = "100%",
                                height = 10,
                                backgroundColor = { 50, 40, 70, 200 },
                                borderRadius = 5,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = tostring(math.floor(segPct * 100)) .. "%",
                                        height = "100%",
                                        backgroundColor = { 80, 200, 100, 255 },
                                        borderRadius = 5,
                                    },
                                },
                            },
                            -- 积分数值
                            UI.Label {
                                text = "积分值 " .. current .. "/" .. segEnd,
                                fontSize = 10,
                                fontColor = { 160, 150, 180, 180 },
                            },
                        },
                    },
                    -- 右: 下一个宝箱
                    rightChild,
                },
            },
        },
    }
end

--- 中间大宝箱展示
function ChestUI.CreateChestDisplay()
    local def = ChestData.GetChestDef(selectedChest)
    if not def then return UI.Panel {} end

    local count = ChestData.GetCount(selectedChest)

    -- 掉落概率说明
    local dropDesc = {}
    for _, d in ipairs(def.drops) do
        local pctStr
        if d.chance >= 1.0 then
            pctStr = "必得 "
        else
            pctStr = math.floor(d.chance * 100) .. "%概率 "
        end
        if d.type == "fragment_random" then
            dropDesc[#dropDesc + 1] = pctStr .. d.rarity .. "碎片x" .. d.min .. "~" .. d.max
        else
            dropDesc[#dropDesc + 1] = pctStr .. GetCurrencyName(d.type) .. "x" .. d.min .. "~" .. d.max
        end
    end

    -- 找出最稀有碎片掉落的概率描述
    local rarityOrder = { N = 1, R = 2, SR = 3, SSR = 4, UR = 5, LR = 6 }
    local bestRarity = nil
    local bestRarityChance = 0
    for _, d in ipairs(def.drops) do
        if d.type == "fragment_random" then
            local order = rarityOrder[d.rarity] or 0
            if not bestRarity or order > (rarityOrder[bestRarity] or 0) then
                bestRarity = d.rarity
                bestRarityChance = d.chance
            end
        end
    end

    return UI.Panel {
        width = "100%",
        flex = 1,
        justifyContent = "center",
        alignItems = "center",
        gap = 8,
        children = {
            -- 宝箱名称
            UI.Label {
                text = def.name,
                fontSize = 22,
                fontColor = def.color,
                fontWeight = "bold",
            },
            -- 掉落概率说明（显示最稀有碎片概率）
            UI.Label {
                text = bestRarity
                    and ("抽到" .. bestRarity .. "概率 " ..
                        (bestRarityChance >= 1.0 and "100%" or (math.floor(bestRarityChance * 100) .. "%")))
                    or "开启获得资源",
                fontSize = 13,
                fontColor = { 200, 160, 255, 200 },
            },
            -- 大宝箱图片 + 底座（同位层叠）
            UI.Panel {
                width = 120, height = 120,
                children = {
                    -- 底座（底层，居中偏下）
                    UI.Panel {
                        position = "absolute",
                        top = 16, left = 0, right = 0, bottom = 0,
                        backgroundImage = "image/chest_base.png",
                        backgroundFit = "contain",
                    },
                    -- 宝箱图片（上层，居中偏上，盖住底座）
                    def.image and UI.Panel {
                        position = "absolute",
                        top = 0, left = 10, right = 10, bottom = 10,
                        backgroundImage = def.image,
                        backgroundFit = "contain",
                    } or UI.Label {
                        position = "absolute",
                        top = 10, left = 0, right = 0,
                        text = def.emoji,
                        fontSize = 56,
                        textAlign = "center",
                    },
                },
            },
            -- 数量
            UI.Label {
                text = "X" .. count,
                fontSize = 24,
                fontColor = Config.COLORS.textGold,
                fontWeight = "bold",
            },
            -- 掉落说明
            UI.Panel {
                alignItems = "center",
                gap = 2,
                children = (function()
                    local items = {}
                    for _, desc in ipairs(dropDesc) do
                        items[#items + 1] = UI.Label {
                            text = desc,
                            fontSize = 11,
                            fontColor = { 150, 140, 170, 180 },
                        }
                    end
                    return items
                end)(),
            },
        },
    }
end

--- 开箱按钮
function ChestUI.CreateOpenButton()
    local count = ChestData.GetCount(selectedChest)
    local canOpen = count > 0
    local openCount = count >= 10 and 10 or 1

    return UI.Panel {
        width = "100%",
        paddingLeft = 40, paddingRight = 40,
        paddingTop = 4, paddingBottom = 8,
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Button {
                text = canOpen and ("打开" .. openCount .. "个宝箱") or "宝箱不足",
                fontSize = 16,
                variant = canOpen and "primary" or "ghost",
                width = "100%",
                height = 48,
                onClick = function(self)
                    if not canOpen then return end
                    ChestUI.DoOpen(selectedChest, openCount)
                end,
            },
        },
    }
end

--- 底部宝箱选择栏（横排5个宝箱图标，带数量和红点）
function ChestUI.CreateChestSelector()
    local items = {}
    for _, ct in ipairs(Config.CHEST_TYPES) do
        local count = ChestData.GetCount(ct.id)
        local isSelected = (ct.id == selectedChest)

        items[#items + 1] = UI.Panel {
            flex = 1,
            alignItems = "center",
            gap = 2,
            paddingTop = 8, paddingBottom = 8,
            backgroundColor = isSelected and { 60, 40, 100, 200 } or { 0, 0, 0, 0 },
            borderRadius = 8,
            borderWidth = isSelected and 1 or 0,
            borderColor = ct.borderColor,
            pointerEvents = "auto",
            onClick = function(self)
                selectedChest = ct.id
                ChestUI.Refresh()
            end,
            children = {
                -- 宝箱图标 + 底座 + 红点（同位层叠）
                UI.Panel {
                    width = 48, height = 48,
                    children = {
                        -- 底座（底层，居中偏下）
                        UI.Panel {
                            position = "absolute",
                            top = 8, left = 0, right = 0, bottom = 0,
                            backgroundImage = "image/chest_base.png",
                            backgroundFit = "contain",
                        },
                        -- 宝箱图片（上层，居中偏上，盖住底座）
                        ct.image and UI.Panel {
                            position = "absolute",
                            top = 0, left = 4, right = 4, bottom = 6,
                            backgroundImage = ct.image,
                            backgroundFit = "contain",
                        } or UI.Label {
                            position = "absolute",
                            top = 2, left = 0, right = 0,
                            text = ct.emoji,
                            fontSize = 24,
                            textAlign = "center",
                        },
                        -- 红点（有宝箱时显示）
                        count > 0 and UI.Panel {
                            position = "absolute",
                            top = -2, right = -2,
                            width = 16, height = 16,
                            borderRadius = 8,
                            backgroundColor = { 220, 50, 50, 255 },
                            justifyContent = "center",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = "!",
                                    fontSize = 9,
                                    fontColor = { 255, 255, 255, 255 },
                                    fontWeight = "bold",
                                },
                            },
                        } or nil,
                    },
                },
                -- 数量
                UI.Label {
                    text = "X" .. count,
                    fontSize = 11,
                    fontColor = count > 0 and ct.color or { 80, 70, 100, 150 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        paddingLeft = 4, paddingRight = 4,
        paddingBottom = 4,
        backgroundColor = { 20, 16, 32, 230 },
        borderWidth = 1,
        borderColor = { 70, 55, 100, 120 },
        flexShrink = 0,
        children = items,
    }
end

--- 手动领取里程碑奖励（只展示奖励，不显示再抽按钮）
function ChestUI.DoClaimMilestone()
    local ok, reward = ChestData.ClaimMilestone()
    if not ok or not reward then
        ChestUI.Refresh()
        return
    end

    local AudioManager = require("Game.AudioManager")
    AudioManager.PlayChestOpen()

    RC.ShowFromDefs(UI, pageRoot, { reward }, "里程碑奖励",
        function() ChestUI.Refresh() end)
end

--- 一键领取全部可领取的里程碑奖励
function ChestUI.DoClaimAllMilestones()
    local ok, rewards = ChestData.ClaimAllMilestones()
    if not ok or #rewards == 0 then
        ChestUI.Refresh()
        return
    end

    local AudioManager = require("Game.AudioManager")
    AudioManager.PlayChestOpen()

    RC.ShowFromDefs(UI, pageRoot, rewards, "里程碑奖励",
        function() ChestUI.Refresh() end)
end

--- 执行开箱并显示结果
---@param chestId string
---@param count number
function ChestUI.DoOpen(chestId, count)
    local ok, result = ChestData.Open(chestId, count)
    if not ok then
        print("[ChestUI] Open failed: " .. tostring(result))
        ChestUI.Refresh()
        return
    end

    -- 播放开宝箱音效
    local AudioManager = require("Game.AudioManager")
    AudioManager.PlayChestOpen()

    -- 显示结果弹窗
    ChestUI.ShowResultPopup(result)
end

--- 获取货币图片路径（统一走 Currency 模块）
---@param currType string
---@return string|nil
local function GetCurrencyImage(currType)
    return Currency.GetImage(currType)
end

--- 通过 heroId 获取头像图片路径
---@param heroId string|nil
---@return string|nil
local function GetAvatarImage(heroId)
    if not heroId then return nil end
    local icon = heroId
    if heroId == "leader" then
        icon = Config.LEADER_HERO.icon or "leader"
    else
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == heroId then
                icon = td.icon or heroId
                break
            end
        end
    end
    return "image/avatars/avatar_" .. icon .. ".png"
end

--- 将开箱/里程碑 result 转为 RewardDisplay 的 rewards 格式
---@param result table
---@return table[]
local function BuildRewards(result)
    local rewards = {}

    for _, drop in ipairs(result.drops) do
        if drop.kind == "currency" then
            rewards[#rewards + 1] = {
                icon = GetCurrencyImage(drop.currType),
                name = GetCurrencyName(drop.currType),
                amount = drop.amount,
            }
        elseif drop.kind == "fragment" then
            local rc = RARITY_COLORS[drop.rarity] or { 200, 200, 200 }
            rewards[#rewards + 1] = {
                icon = "👤",
                name = drop.rarity .. " " .. drop.heroName,
                amount = drop.amount,
                borderColor = { rc[1], rc[2], rc[3], 200 },
                avatarImage = GetAvatarImage(drop.heroId),
                isNew = drop.isNew,
            }
        end
    end

    if result.milestoneRewards then
        for _, mr in ipairs(result.milestoneRewards) do
            if mr.type == "chest" then
                local cdef = ChestData.GetChestDef(mr.id)
                rewards[#rewards + 1] = {
                    icon = (cdef and cdef.image) or (cdef and cdef.emoji) or "📦",
                    name = cdef and cdef.name or mr.id,
                    amount = mr.amount,
                    borderColor = { 255, 200, 50, 200 },
                }
            else
                rewards[#rewards + 1] = {
                    icon = GetCurrencyImage(mr.id),
                    name = GetCurrencyName(mr.id),
                    amount = mr.amount,
                    borderColor = { 255, 200, 50, 200 },
                }
            end
        end
    end

    return rewards
end

--- 显示开箱结果弹窗（使用通用 RewardDisplay 组件）
---@param result table
function ChestUI.ShowResultPopup(result)
    if not pageRoot or not UI then return end

    local rewards = BuildRewards(result)

    -- 构建按钮
    local remainCount = ChestData.GetCount(selectedChest)
    local canReopen = remainCount > 0
    local reopenCount = math.min(remainCount, 10)

    local buttons = {
        {
            text = "确定",
            variant = canReopen and "outline" or "primary",
            onClick = function()
                RewardDisplay.Hide(pageRoot)
                ChestUI.Refresh()
            end,
        },
    }

    if canReopen then
        buttons[#buttons + 1] = {
            text = "再抽" .. reopenCount .. "次",
            variant = "primary",
            onClick = function()
                RewardDisplay.Hide(pageRoot)
                ChestUI.DoOpen(selectedChest, reopenCount)
            end,
        }
    end

    RewardDisplay.Show(UI, pageRoot, {
        title = "恭喜获得",
        rewards = rewards,
        buttons = buttons,
        hint = "点击确定返回宝箱界面",
    })
end

return ChestUI
