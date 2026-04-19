-- Game/CostumeSignInUI.lua
-- 7天时装签到活动界面
-- 玩家每天手动点击"签到"按钮，签到即领奖

local CostumeSignInData = require("Game.CostumeSignInData")
local CostumeData       = require("Game.CostumeData")
local RewardIcon        = require("Game.RewardIcon")
local Toast             = require("Game.Toast")
local RC                = require("Game.RewardController")

local CostumeSignInUI = {}

---@type any
local _UI = nil
---@type any
local _pageRoot = nil
---@type fun()|nil
local _onBack = nil

-- 动画状态
local _previewPanel = nil
local _frameTimer   = 0
local _frameIdx     = 0

-- 签到按钮引用（供 Refresh 更新状态）
local _signInBtn    = nil
-- 格子容器引用（供 Refresh 重建卡片）
local _cardGrid     = nil

-- 预览区尺寸
local PREVIEW_SIZE = 110

-- ============================================================================
-- 工具：获取翅膀定义
-- ============================================================================
local function GetWingDef()
    for _, def in ipairs(CostumeData.WING_COSTUMES) do
        if def.id == "wing_shadow" then return def end
    end
    return CostumeData.WING_COSTUMES[1]
end

-- ============================================================================
-- 精灵图单帧截取
-- ============================================================================
local function FrameIcon(size, def, frameIdx)
    local cols   = def.gridCols or 2
    local rows   = def.gridRows or 2
    local fCol   = frameIdx % cols
    local fRow   = math.floor(frameIdx / cols)
    return _UI.Panel {
        position = "absolute",
        left     = -fCol * size,
        top      = -fRow * size,
        width    = size * cols,
        height   = size * rows,
        backgroundImage = def.preview,
        backgroundFit   = "fill",
    }
end

-- ============================================================================
-- 单天格子
-- ============================================================================
local function MakeDayCard(day, cardWidth, cardHeight)
    local reward   = CostumeSignInData.GetDayReward(day)
    local claimed  = CostumeSignInData.IsDayClaimed(day)
    local isLast   = (day == CostumeSignInData.MAX_SIGN_INS)
    local canToday = CostumeSignInData.CanSignInToday()
    local nextDay  = CostumeSignInData.GetNextSignInDay()
    local isToday  = canToday and (day == nextDay)
    local locked   = not claimed and not isToday

    -- 边框颜色
    local borderCol
    if isLast then
        borderCol = { 160, 100, 255, 220 }
    elseif isToday then
        borderCol = { 100, 220, 140, 220 }
    elseif claimed then
        borderCol = { 80, 80, 100, 140 }
    else
        borderCol = { 70, 55, 100, 140 }
    end

    -- 背景色
    local bgCol
    if claimed then
        bgCol = { 30, 25, 50, 160 }
    elseif isToday then
        bgCol = { 20, 55, 38, 210 }
    else
        bgCol = { 20, 16, 36, 200 }
    end

    local iconSz = isLast and 52 or 44

    -- 中间内容：已领取显示 ✓，否则显示奖励图标
    local centerWidget
    if claimed then
        centerWidget = _UI.Panel {
            width = iconSz, height = iconSz,
            justifyContent = "center",
            alignItems = "center",
            children = {
                _UI.Label {
                    text = "✓",
                    fontSize = isLast and 36 or 30,
                    fontWeight = "bold",
                    fontColor = { 80, 220, 120, 255 },
                },
            },
        }
    elseif reward then
        if reward.type == "costume" then
            local def = GetWingDef()
            centerWidget = _UI.Panel {
                width = iconSz, height = iconSz,
                overflow = "hidden",
                borderRadius = 6,
                children = { FrameIcon(iconSz, def, def.iconFrame or 0) },
            }
        else
            centerWidget = RewardIcon.Create(_UI, isLast and 52 or 48, reward.id, reward.amount, {})
        end
    else
        centerWidget = _UI.Panel { width = iconSz, height = iconSz }
    end

    -- 底部标签
    local bottomLabel = nil
    if claimed then
        bottomLabel = _UI.Label {
            text = "已领取",
            fontSize = 9,
            fontColor = { 80, 200, 110, 200 },
        }
    elseif reward and reward.type == "costume" then
        bottomLabel = _UI.Label {
            text = "时装",
            fontSize = 9,
            fontColor = { 255, 220, 100, 200 },
        }
    end

    return _UI.Panel {
        id = "signinDayCard" .. day,
        width  = cardWidth,
        height = cardHeight,
        backgroundColor = bgCol,
        borderRadius = 10,
        borderWidth  = isLast and 2 or 1,
        borderColor  = borderCol,
        justifyContent = "center",
        alignItems   = "center",
        gap = 3,
        children = {
            _UI.Label {
                text = "第" .. day .. "天",
                fontSize = 10,
                fontColor = isLast and { 255, 200, 60, 200 } or { 140, 120, 180, 200 },
            },
            centerWidget,
            bottomLabel,
            -- 未解锁：置灰遮罩
            _UI.Panel {
                id = "signinLock" .. day,
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 120 },
                borderRadius = 10,
                visible = locked,
            },
        },
    }
end

-- ============================================================================
-- 一行格子
-- ============================================================================
local function MakeRow(days, cardWidth, cardHeight)
    local children = {}
    for i, day in ipairs(days) do
        children[i] = MakeDayCard(day, cardWidth, cardHeight)
    end
    return _UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 8,
        children = children,
    }
end

-- ============================================================================
-- 重建格子（Refresh 时调用，确保已签到状态正确显示）
-- ============================================================================
local function RebuildCards()
    if not _cardGrid then return end
    _cardGrid:ClearChildren()
    _cardGrid:AddChild(MakeRow({ 1, 2, 3, 4 }, 76, 86))
    _cardGrid:AddChild(MakeRow({ 5, 6, 7 }, 84, 94))
end

-- ============================================================================
-- 创建页面
-- ============================================================================
function CostumeSignInUI.CreatePage(uiModule)
    _UI         = uiModule
    _frameTimer = 0
    _frameIdx   = 0

    local def = GetWingDef()

    -- 预览精灵图动画
    _previewPanel = _UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width  = PREVIEW_SIZE * (def.gridCols or 2),
        height = PREVIEW_SIZE * (def.gridRows or 2),
        backgroundImage = def.preview,
        backgroundFit   = "fill",
    }

    local previewWrap = _UI.Panel {
        width  = PREVIEW_SIZE,
        height = PREVIEW_SIZE,
        overflow = "hidden",
        borderRadius = 16,
        borderWidth  = 2,
        borderColor  = { 255, 200, 60, 200 },
        backgroundColor = { 20, 16, 40, 220 },
        children = { _previewPanel },
    }

    -- 签到按钮（初始状态由 Refresh 决定）
    _signInBtn = _UI.Button {
        id = "costumeSignInSignBtn",
        text = "签到",
        fontSize = 16,
        variant = "primary",
        height = 44,
        paddingLeft = 32, paddingRight = 32,
        onClick = function()
            local ok, msg, reward = CostumeSignInData.SignInToday()
            if ok and reward then
                RC.ShowFromDefs(_UI, _pageRoot, { reward }, "签到奖励", nil)
                CostumeSignInUI.Refresh()
            else
                Toast.Show(msg or "签到失败")
            end
        end,
    }

    _pageRoot = _UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 12, 8, 24, 245 },
        flexDirection = "column",
        alignItems = "center",
        children = {

            -- ── 顶部预览区 ──
            _UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                paddingTop = 20, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                gap = 18,
                children = {
                    previewWrap,
                    _UI.Panel {
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            _UI.Label {
                                text = "暗影之翼",
                                fontSize = 20,
                                fontColor = { 160, 100, 255, 255 },
                            },
                            _UI.Label {
                                text = "SR 翅膀时装",
                                fontSize = 12,
                                fontColor = { 170, 140, 220, 210 },
                            },
                            _UI.Label {
                                text = "累积签到7次即可获得",
                                fontSize = 11,
                                fontColor = { 180, 180, 210, 200 },
                            },
                            _UI.Label {
                                text = "攻击加成 +1% | 排行加分 +500",
                                fontSize = 10,
                                fontColor = { 140, 220, 150, 200 },
                            },
                        },
                    },
                },
            },

            -- ── 分割线 ──
            _UI.Panel {
                width = "88%", height = 1,
                backgroundColor = { 70, 50, 100, 70 },
                marginBottom = 12,
            },

            -- ── 签到格子区 ──
            (function()
                _cardGrid = _UI.Panel {
                    flex = 1,
                    width = "100%",
                    flexDirection = "column",
                    justifyContent = "center",
                    alignItems = "center",
                    paddingLeft = 12, paddingRight = 12,
                    gap = 10,
                    children = {
                        MakeRow({ 1, 2, 3, 4 }, 76, 86),
                        MakeRow({ 5, 6, 7 }, 84, 94),
                    },
                }
                return _cardGrid
            end)(),

            -- ── 底部操作栏 ──
            _UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingTop = 12, paddingBottom = 20,
                paddingLeft = 16, paddingRight = 16,
                backgroundColor = { 16, 10, 32, 240 },
                borderWidth = 1,
                borderColor = { 60, 45, 90, 100 },
                children = {
                    -- 左：返回按钮
                    _UI.Button {
                        text = "← 返回",
                        fontSize = 13,
                        variant = "outline",
                        height = 44,
                        paddingLeft = 14, paddingRight = 14,
                        onClick = function()
                            if _onBack then _onBack() end
                        end,
                    },
                    -- 中：签到按钮
                    _signInBtn,
                    -- 右：剩余天数
                    _UI.Label {
                        id = "costumeSignInRemain",
                        text = "剩余 " .. CostumeSignInData.GetRemainingDays() .. " 天",
                        fontSize = 11,
                        fontColor = { 160, 140, 200, 200 },
                    },
                },
            },
        },
    }

    -- 初始刷新按钮状态
    CostumeSignInUI.Refresh()

    return _pageRoot
end

-- ============================================================================
-- 刷新界面
-- ============================================================================
function CostumeSignInUI.Refresh()
    if not _pageRoot then return end

    -- 更新剩余天数
    local remainLabel = _pageRoot:FindById("costumeSignInRemain")
    if remainLabel then
        local active = CostumeSignInData.IsEventActive()
        local rem    = CostumeSignInData.GetRemainingDays()
        remainLabel:SetText(active and ("剩余 " .. rem .. " 天") or "活动已结束")
    end

    -- 更新签到按钮
    if _signInBtn then
        local allDone  = CostumeSignInData.GetLoginDays() >= CostumeSignInData.MAX_SIGN_INS
        local canSign  = CostumeSignInData.CanSignInToday()
        local signed   = CostumeSignInData.HasSignedInToday()

        if allDone then
            _signInBtn:SetText("已全部签到")
            _signInBtn:SetDisabled(true)
        elseif signed then
            _signInBtn:SetText("今日已签到")
            _signInBtn:SetDisabled(true)
        else
            _signInBtn:SetText("签到")
            _signInBtn:SetDisabled(not canSign)
        end
    end

    -- 重建所有格子（确保已签到 ✓ 正确显示）
    RebuildCards()
end

-- ============================================================================
-- 逐帧动画更新（由 GameUI.lua 在 Update 中调用）
-- ============================================================================
function CostumeSignInUI.Update(dt)
    if not _previewPanel then return end
    local def = GetWingDef()
    local frames = def.frames
    if not frames or #frames == 0 then return end
    local fps = def.fps or 1.2

    _frameTimer = _frameTimer + dt
    if _frameTimer >= (1.0 / fps) then
        _frameTimer = 0
        _frameIdx   = (_frameIdx + 1) % #frames
        local fIdx  = frames[_frameIdx + 1]
        local cols  = def.gridCols or 2
        local fCol  = fIdx % cols
        local fRow  = math.floor(fIdx / cols)
        _previewPanel:SetStyle({
            left = -fCol * PREVIEW_SIZE,
            top  = -fRow * PREVIEW_SIZE,
        })
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================
function CostumeSignInUI.SetOnBack(fn)
    _onBack = fn
end

return CostumeSignInUI
