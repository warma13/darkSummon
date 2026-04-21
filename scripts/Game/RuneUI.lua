-- Game/RuneUI.lua
-- 深渊符文系统 — 符文页面 UI
-- 布局: 英雄选择栏 → 已装备符文槽 → 套装效果 → 符文背包

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local RuneConfig = require("Game.Config_Runes")
local RuneData = require("Game.RuneData")
local Currency = require("Game.Currency")
local Tower = require("Game.Tower")

local RuneUI = {}

---@type any
local UI = nil
---@type any
local pageRoot = nil
---@type string|nil
local selectedHero = nil
---@type table|nil
local selectedRune = nil  -- 当前查看的符文（背包或已装备）
---@type string|nil
local selectedSource = nil  -- "bag" / "equipped"
---@type number|nil
local selectedSlotIdx = nil  -- 当前选中的槽位（用于装备操作）
---@type boolean
local _embedded = false  -- 是否嵌入在 EquipUI 的 tab 中
---@type function|nil
local _embeddedRefresh = nil  -- 嵌入模式下的外部刷新函数

--- 初始化
---@param uiModule any
function RuneUI.Init(uiModule)
    UI = uiModule
end

--- 创建符文页面
---@param uiModule any
---@return any
function RuneUI.CreatePage(uiModule)
    UI = uiModule
    _embedded = false
    _embeddedRefresh = nil

    if not selectedHero then
        if #HeroData.deployed > 0 then
            selectedHero = HeroData.deployed[1]
        end
    end

    pageRoot = UI.Panel {
        id = "runePage",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        backgroundColor = { 15, 12, 25, 255 },
        children = {},
    }

    RuneUI.Refresh()
    return pageRoot
end

--- 刷新页面
function RuneUI.Refresh()
    if not pageRoot or not UI then return end

    -- 嵌入模式下委托 EquipUI 整体刷新（保留 tab 栏）
    if _embedded and _embeddedRefresh then
        _embeddedRefresh()
        return
    end

    if not selectedHero or not HeroData.IsDeployed(selectedHero) then
        selectedHero = nil
        if #HeroData.deployed > 0 then
            selectedHero = HeroData.deployed[1]
        end
    end

    pageRoot:ClearChildren()

    -- 顶部标题 + 货币
    pageRoot:AddChild(RuneUI.CreateHeader())
    -- 英雄选择栏
    pageRoot:AddChild(RuneUI.CreateHeroSelector())

    if selectedHero then
        -- 已装备符文槽
        pageRoot:AddChild(RuneUI.CreateEquippedSlots())
        -- 套装效果
        pageRoot:AddChild(RuneUI.CreateSetBonusBar())
        -- 符文背包（始终显示）
        pageRoot:AddChild(RuneUI.CreateBagPanel())
        -- 底部货币栏
        pageRoot:AddChild(RuneUI.CreateBottomBar())

        -- 选中符文时弹窗覆盖详情
        if selectedRune then
            pageRoot:AddChild(RuneUI.CreateRuneDetailOverlay())
        end
    else
        pageRoot:AddChild(UI.Panel {
            width = "100%", flexGrow = 1,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "请先在英雄页上阵英雄",
                    fontSize = 14, fontColor = { 150, 140, 130, 180 },
                },
            },
        })
        -- 底部货币栏
        pageRoot:AddChild(RuneUI.CreateBottomBar())
    end
end

--- 嵌入式渲染：由 EquipUI tab 切换调用，跳过标题栏（tab 栏由 EquipUI 提供）
---@param parentPanel any  外部容器
---@param refreshFn function|nil  外部刷新回调（EquipUI.Refresh）
function RuneUI.RenderInto(parentPanel, refreshFn)
    if not UI then return end

    _embedded = true
    _embeddedRefresh = refreshFn

    -- 同步选中英雄
    if not selectedHero or not HeroData.IsDeployed(selectedHero) then
        selectedHero = nil
        if #HeroData.deployed > 0 then
            selectedHero = HeroData.deployed[1]
        end
    end

    -- 保存引用以便子组件刷新时可用
    pageRoot = parentPanel

    -- 英雄选择栏
    parentPanel:AddChild(RuneUI.CreateHeroSelector())

    if selectedHero then
        parentPanel:AddChild(RuneUI.CreateEquippedSlots())
        parentPanel:AddChild(RuneUI.CreateSetBonusBar())
        parentPanel:AddChild(RuneUI.CreateBagPanel())
        parentPanel:AddChild(RuneUI.CreateBottomBar())
        if selectedRune then
            parentPanel:AddChild(RuneUI.CreateRuneDetailOverlay())
        end
    else
        parentPanel:AddChild(UI.Panel {
            width = "100%", flexGrow = 1,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "请先在英雄页上阵英雄",
                    fontSize = 14, fontColor = { 150, 140, 130, 180 },
                },
            },
        })
        parentPanel:AddChild(RuneUI.CreateBottomBar())
    end
end

-- ============================================================================
-- 顶部标题
-- ============================================================================

function RuneUI.CreateHeader()
    return UI.Panel {
        width = "100%",
        paddingTop = 8, paddingBottom = 4,
        paddingLeft = 16, paddingRight = 16,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        flexShrink = 0,
        children = {
            UI.Label {
                text = "符文",
                fontSize = 20,
                fontColor = Config.COLORS.textPrimary,
                fontWeight = "bold",
            },
        },
    }
end

-- ============================================================================
-- 底部货币栏（与英雄页面风格一致）
-- ============================================================================

function RuneUI.CreateBottomBar()
    local GameUI = require("Game.GameUI")
    return UI.Panel {
        width = "100%",
        flexShrink = 0,
        flexDirection = "row",
        justifyContent = "flex-end",
        alignItems = "center",
        paddingTop = 6, paddingBottom = 8,
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = { 30, 22, 16, 240 },
        borderTopWidth = 1,
        borderTopColor = { 75, 55, 38, 100 },
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    GameUI.CreateCurrencyChip(UI, "rift_dust",      "runeDustLabel",    { 160, 120, 200 }),
                    GameUI.CreateCurrencyChip(UI, "rune_seal",      "runeSealLabel",    { 40, 200, 160 }),
                    GameUI.CreateCurrencyChip(UI, "abyss_crystal",  "runeCrystalLabel", { 200, 60, 255 }),
                },
            },
        },
    }
end

-- ============================================================================
-- 英雄选择栏（与 EquipUI 一致的模式）
-- ============================================================================

function RuneUI.CreateHeroSelector()
    local heroes = {}
    for _, heroId in ipairs(HeroData.deployed) do
        heroes[#heroes + 1] = heroId
    end

    local items = {}
    for _, heroId in ipairs(heroes) do
        local isSelected = (heroId == selectedHero)
        local heroName = heroId
        local heroIcon = nil
        if heroId == Config.LEADER_HERO.id then
            heroName = Config.LEADER_HERO.name
            heroIcon = Config.LEADER_HERO.icon
        else
            for _, td in ipairs(Config.TOWER_TYPES) do
                if td.id == heroId then
                    heroName = td.name
                    heroIcon = td.icon
                    break
                end
            end
        end
        local avatarPath = heroIcon and ("image/avatars/avatar_" .. heroIcon .. ".png") or nil

        items[#items + 1] = UI.Panel {
            flex = 1,
            aspectRatio = 1,
            alignItems = "center",
            justifyContent = "flex-end",
            backgroundColor = isSelected and { 80, 50, 140, 200 } or { 30, 25, 45, 150 },
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and { 160, 120, 255, 255 } or { 60, 50, 80, 200 },
            overflow = "hidden",
            pointerEvents = "auto",
            onClick = function(self)
                selectedHero = heroId
                selectedRune = nil
                RuneUI.Refresh()
            end,
            children = {
                avatarPath and UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    backgroundImage = avatarPath,
                    backgroundFit = "cover",
                    pointerEvents = "none",
                } or UI.Label { text = "👤", fontSize = 28, pointerEvents = "none" },
                -- 底部名称条
                UI.Panel {
                    position = "absolute",
                    bottom = 0, left = 0, right = 0,
                    height = 18,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 0, 0, 0, 180 },
                    pointerEvents = "none",
                    children = {
                        UI.Label {
                            text = string.sub(heroName, 1, 6),
                            fontSize = 9,
                            fontColor = isSelected and {255,255,255,255} or {200,190,220,230},
                            fontWeight = isSelected and "bold" or "normal",
                            pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        flexDirection = "row",
        gap = 6,
        children = items,
    }
end

-- ============================================================================
-- 已装备符文槽（3个槽位）
-- ============================================================================

function RuneUI.CreateEquippedSlots()
    local equipped = RuneData.GetEquipped(selectedHero)
    local slots = {}

    for i = 1, RuneConfig.MAX_SLOTS do
        local slotDef = RuneConfig.SLOT_DEFS[i]
        local rune = equipped[i]
        local unlocked = RuneData.IsSlotUnlocked(i)

        local children = {}
        if not unlocked then
            -- 锁定
            children = {
                UI.Label { text = "🔒", fontSize = 24, pointerEvents = "none" },
                UI.Label {
                    text = "第" .. slotDef.unlockStage .. "关",
                    fontSize = 8, fontColor = {120,110,140,180}, pointerEvents = "none",
                },
            }
        elseif rune then
            -- 已装备符文
            local series = RuneData.GetSeries(rune.seriesId)
            local quality = RuneData.GetQuality(rune.qualityId)
            children = {
                (series and series.icon) and UI.Panel {
                    width = 32, height = 32,
                    backgroundImage = series.icon, backgroundFit = "contain",
                    pointerEvents = "none",
                } or UI.Label { text = series and series.emoji or "🔮", fontSize = 22, pointerEvents = "none" },
                UI.Label {
                    text = quality.name,
                    fontSize = 9, fontColor = quality.color, pointerEvents = "none",
                },
            }
        else
            -- 空槽
            children = {
                UI.Label { text = "＋", fontSize = 24, fontColor = {100,90,130,200}, pointerEvents = "none" },
                UI.Label {
                    text = slotDef.name,
                    fontSize = 8, fontColor = {100,90,130,150}, pointerEvents = "none",
                },
            }
        end

        local isHighlight = (selectedSlotIdx == i and selectedSource == "equipped")
        local borderCol = {50,45,70,200}
        if rune then
            local q = RuneData.GetQuality(rune.qualityId)
            borderCol = {q.color[1], q.color[2], q.color[3], 200}
        end
        if isHighlight then
            borderCol = {255,200,80,255}
        end

        slots[#slots + 1] = UI.Panel {
            flex = 1,
            aspectRatio = 1,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = rune and {30,25,50,220} or {20,18,35,180},
            borderRadius = 8,
            borderWidth = isHighlight and 2 or 1,
            borderColor = borderCol,
            gap = 2,
            pointerEvents = unlocked and "auto" or "none",
            onClick = unlocked and function(self)
                if rune then
                    selectedRune = rune
                    selectedSource = "equipped"
                    selectedSlotIdx = i
                else
                    -- 空槽：选中以便从背包装备
                    selectedRune = nil
                    selectedSource = nil
                    selectedSlotIdx = i
                end
                RuneUI.Refresh()
            end or nil,
            children = children,
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        flexDirection = "row",
        gap = 8,
        children = slots,
    }
end

-- ============================================================================
-- 套装效果显示
-- ============================================================================

function RuneUI.CreateSetBonusBar()
    local sets = RuneData.GetSetBonuses(selectedHero)

    if #sets == 0 then
        return UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 4, paddingBottom = 4,
            flexShrink = 0,
            children = {
                UI.Label {
                    text = "装备同系列符文可激活套装效果",
                    fontSize = 11, fontColor = {100,90,130,150},
                },
            },
        }
    end

    local children = {}
    for _, setInfo in ipairs(sets) do
        local s = setInfo.series
        local color = s.tagColor
        local desc2 = setInfo.set2 and s.set2.desc or ""
        local desc3 = setInfo.set3 and s.set3.desc or ""

        children[#children + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Panel {
                    paddingLeft = 4, paddingRight = 4,
                    paddingTop = 1, paddingBottom = 1,
                    backgroundColor = {color[1], color[2], color[3], 200},
                    borderRadius = 3,
                    flexDirection = "row", alignItems = "center", gap = 2,
                    children = {
                        s.icon and UI.Panel {
                            width = 14, height = 14,
                            backgroundImage = s.icon, backgroundFit = "contain",
                            pointerEvents = "none",
                        } or UI.Label { text = s.emoji, fontSize = 10, fontColor = {20,16,32,255} },
                        UI.Label {
                            text = s.name .. " " .. setInfo.count .. "/" .. RuneConfig.MAX_SLOTS,
                            fontSize = 10, fontColor = {20,16,32,255},
                        },
                    },
                },
                setInfo.set2 and UI.Label {
                    text = "2件:" .. desc2,
                    fontSize = 10, fontColor = {100,255,100,255},
                } or nil,
                setInfo.set3 and UI.Label {
                    text = "3件:" .. desc3,
                    fontSize = 10, fontColor = {255,200,80,255},
                } or nil,
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 4, paddingBottom = 4,
        flexShrink = 0,
        gap = 2,
        children = children,
    }
end

-- ============================================================================
-- 符文背包网格
-- ============================================================================

function RuneUI.CreateBagPanel()
    local bag = RuneData.GetBag()
    local cur, cap = RuneData.GetBagCapacity()

    -- 像素计算：容器宽 = 逻辑屏幕宽 - 外层padding - bagPanel padding(8+8)
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local bagPadLR = 16  -- paddingLeft(8) + paddingRight(8)
    local itemSize = math.floor((logicalW - bagPadLR) / 5)

    local gridItems = {}
    for _, rune in ipairs(bag) do
        local series = RuneData.GetSeries(rune.seriesId)
        local quality = RuneData.GetQuality(rune.qualityId)
        local isSelected = (selectedRune and selectedRune.runeId == rune.runeId)
        gridItems[#gridItems + 1] = UI.Panel {
            width = itemSize, height = itemSize,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { quality.color[1], quality.color[2], quality.color[3], 35 },
            borderRadius = 6,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and {255,200,80,255} or {quality.color[1], quality.color[2], quality.color[3], 180},
            pointerEvents = "auto",
            onClick = function(self)
                selectedRune = rune
                selectedSource = "bag"
                RuneUI.Refresh()
            end,
            children = {
                -- 符文图标铺满格子（普通流式子元素撑起高度）
                (series and series.icon) and UI.Panel {
                    width = "100%", flexGrow = 1,
                    backgroundImage = series.icon, backgroundFit = "cover",
                    borderRadius = 6,
                    pointerEvents = "none",
                } or UI.Panel {
                    width = "100%", flexGrow = 1,
                    justifyContent = "center", alignItems = "center",
                    pointerEvents = "none",
                    children = {
                        UI.Label { text = series and series.emoji or "🔮", fontSize = 24, pointerEvents = "none" },
                    },
                },
                -- 底部品质名
                UI.Panel {
                    width = "100%", height = 14, flexShrink = 0,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { quality.color[1], quality.color[2], quality.color[3], 180 },
                    borderBottomLeftRadius = 5, borderBottomRightRadius = 5,
                    pointerEvents = "none",
                    children = {
                        UI.Label {
                            text = quality.name, fontSize = 8, fontWeight = "bold",
                            fontColor = {255,255,255,255}, pointerEvents = "none",
                        },
                    },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        flexDirection = "column",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4,
        children = {
            -- 标题行（固定不滚动）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingBottom = 4,
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = "符文背包 (" .. cur .. "/" .. cap .. ")",
                        fontSize = 13, fontColor = {180,170,200,220},
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 6,
                        children = {
                            UI.Button {
                                text = "分解白绿",
                                fontSize = 10, variant = "outline",
                                height = 26, paddingLeft = 8, paddingRight = 8,
                                onClick = function(self)
                                    local count, gained = RuneData.DecomposeByQuality(2) -- <=绿色
                                    local Toast = require("Game.Toast")
                                    if count > 0 then
                                        local dustGot = gained.rift_dust or 0
                                        Toast.Show("分解" .. count .. "个，获得裂隙之尘×" .. dustGot, {100,255,100})
                                    else
                                        Toast.Show("没有可分解的符文", {255,200,80})
                                    end
                                    RuneUI.Refresh()
                                end,
                            },
                        },
                    },
                },
            },
            -- 网格容器（可滚动）
            UI.Panel {
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                flexDirection = "row",
                flexWrap = "wrap",
                alignContent = "flex-start",
                overflow = "scroll",
                children = gridItems,
            },
        },
    }
end

-- ============================================================================
-- 符文详情面板
-- ============================================================================

function RuneUI.CreateRuneDetailOverlay()
    local rune = selectedRune
    if not rune then return UI.Panel {} end

    local series = RuneData.GetSeries(rune.seriesId)
    local quality = RuneData.GetQuality(rune.qualityId)
    local isEquipped = (selectedSource == "equipped")

    -- 词条列表
    local affixChildren = {}
    for i, affix in ipairs(rune.affixes) do
        affixChildren[#affixChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingTop = 2, paddingBottom = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = RuneData.FormatAffix(affix),
                            fontSize = 13, fontColor = {220,210,240,255},
                        },
                        UI.Label {
                            text = RuneData.FormatAffixRange(affix, rune.qualityId),
                            fontSize = 10, fontColor = {140,130,160,180},
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        affix.locked and UI.Label {
                            text = "🔒", fontSize = 12,
                        } or nil,
                        UI.Button {
                            text = affix.locked and "解锁" or "锁定",
                            fontSize = 9, variant = "outline",
                            height = 22, paddingLeft = 6, paddingRight = 6,
                            onClick = function(self)
                                RuneData.ToggleAffixLock(rune, i)
                                RuneUI.Refresh()
                            end,
                        },
                    },
                },
            },
        }
    end

    -- 操作按钮
    local buttons = {}
    if isEquipped then
        -- 卸下
        buttons[#buttons + 1] = UI.Button {
            text = "卸下", fontSize = 12, variant = "outline",
            flex = 1, height = 36,
            onClick = function(self)
                local ok, msg = RuneData.Unequip(selectedHero, selectedSlotIdx)
                local Toast = require("Game.Toast")
                Toast.Show(ok and "已卸下" or msg, ok and {100,255,100} or {255,100,80})
                if ok then Tower.RefreshAllStats() end
                selectedRune = nil
                RuneUI.Refresh()
            end,
        }
    else
        -- 装备（需要选中槽位）
        buttons[#buttons + 1] = UI.Button {
            text = "装备", fontSize = 12, variant = "primary",
            flex = 1, height = 36,
            onClick = function(self)
                -- 自动找空槽或第一个已解锁槽
                local targetSlot = selectedSlotIdx
                if not targetSlot then
                    local equipped = RuneData.GetEquipped(selectedHero)
                    for i = 1, RuneConfig.MAX_SLOTS do
                        if RuneData.IsSlotUnlocked(i) and not equipped[i] then
                            targetSlot = i
                            break
                        end
                    end
                    if not targetSlot then
                        -- 所有槽位都满了，替换第一个
                        for i = 1, RuneConfig.MAX_SLOTS do
                            if RuneData.IsSlotUnlocked(i) then
                                targetSlot = i
                                break
                            end
                        end
                    end
                end
                if not targetSlot then
                    local Toast = require("Game.Toast")
                    Toast.Show("没有可用槽位", {255,100,80})
                    return
                end
                local ok, msg = RuneData.Equip(selectedHero, targetSlot, rune.runeId)
                local Toast = require("Game.Toast")
                Toast.Show(ok and "装备成功" or msg, ok and {100,255,100} or {255,100,80})
                if ok then Tower.RefreshAllStats() end
                selectedRune = nil
                selectedSlotIdx = nil
                RuneUI.Refresh()
            end,
        }
    end

    -- 洗练
    buttons[#buttons + 1] = UI.Button {
        text = "洗练", fontSize = 12, variant = "outline",
        flex = 1, height = 36,
        onClick = function(self)
            local RuneReforgeUI = require("Game.RuneReforgeUI")
            RuneReforgeUI.Open(pageRoot, rune, function()
                Tower.RefreshAllStats()
                RuneUI.Refresh()
            end)
        end,
    }

    -- 分解（仅背包中的符文）
    if not isEquipped then
        buttons[#buttons + 1] = UI.Button {
            text = "分解", fontSize = 12, variant = "outline",
            flex = 1, height = 36,
            onClick = function(self)
                -- 高品质符文（传说/神话）弹窗确认
                if rune.qualityId == "red" or rune.qualityId == "orange" then
                    RuneUI._showDecomposeConfirm(rune)
                else
                    RuneUI._doDecompose(rune)
                end
            end,
        }
    end

    -- 套装效果预览
    local setChildren = {}
    if series then
        setChildren[#setChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 4,
            borderTopWidth = 1,
            borderColor = {60,50,90,100},
            gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        series.icon and UI.Panel {
                            width = 16, height = 16,
                            backgroundImage = series.icon, backgroundFit = "contain",
                            pointerEvents = "none",
                        } or UI.Label { text = series.emoji, fontSize = 11, fontColor = series.tagColor },
                        UI.Label {
                            text = series.name .. "套装效果",
                            fontSize = 11, fontColor = series.tagColor,
                        },
                    },
                },
                UI.Label {
                    text = "2件: " .. series.set2.desc,
                    fontSize = 10, fontColor = {180,170,200,200},
                },
                UI.Label {
                    text = "3件: " .. series.set3.desc,
                    fontSize = 10, fontColor = {180,170,200,200},
                },
            },
        }
    end

    -- 弹窗覆盖层
    return UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = {0, 0, 0, 160},
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self)
            selectedRune = nil
            selectedSlotIdx = nil
            RuneUI.Refresh()
        end,
        children = {
            -- 内容卡片
            UI.Panel {
                width = "90%",
                flexDirection = "column",
                backgroundColor = {30, 24, 50, 240},
                borderRadius = 12,
                borderWidth = 1,
                borderColor = {quality.color[1], quality.color[2], quality.color[3], 150},
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 10, paddingBottom = 10,
                gap = 4,
                pointerEvents = "auto",
                onClick = function(self) end,  -- 阻止点击穿透关闭
                children = {
                    -- 标题行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        flexShrink = 0,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 6,
                                children = {
                                    (series and series.icon) and UI.Panel {
                                        width = 28, height = 28,
                                        backgroundImage = series.icon, backgroundFit = "contain",
                                        pointerEvents = "none",
                                    } or UI.Label { text = series and series.emoji or "🔮", fontSize = 20 },
                                    UI.Label {
                                        text = (series and series.name or "") .. "符文",
                                        fontSize = 16, fontColor = quality.color, fontWeight = "bold",
                                    },
                                    UI.Panel {
                                        paddingLeft = 6, paddingRight = 6,
                                        paddingTop = 1, paddingBottom = 1,
                                        backgroundColor = {quality.color[1], quality.color[2], quality.color[3], 200},
                                        borderRadius = 4,
                                        children = {
                                            UI.Label {
                                                text = quality.name,
                                                fontSize = 10, fontColor = {20,16,32,255},
                                            },
                                        },
                                    },
                                },
                            },
                            UI.Button {
                                text = "✕", fontSize = 14, variant = "ghost",
                                width = 28, height = 28,
                                onClick = function(self)
                                    selectedRune = nil
                                    selectedSlotIdx = nil
                                    RuneUI.Refresh()
                                end,
                            },
                        },
                    },
                    -- 词条
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 2,
                        paddingTop = 4, paddingBottom = 4,
                        flexShrink = 0,
                        children = affixChildren,
                    },
                    -- 套装效果
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 2,
                        flexShrink = 0,
                        children = setChildren,
                    },
                    -- 操作按钮
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 8,
                        paddingTop = 8,
                        flexShrink = 0,
                        children = buttons,
                    },
                },
            },
        },
    }
end

--- 更新（预留帧刷新）
---@param dt number
function RuneUI.Update(dt)
    -- 暂无帧更新需求
end

-- ============================================================================
-- 分解逻辑 + 确认弹窗
-- ============================================================================

--- 执行分解
function RuneUI._doDecompose(rune)
    local ok, msg, gained = RuneData.Decompose(rune.runeId)
    local Toast = require("Game.Toast")
    if ok and gained then
        local parts = {}
        for currId, amount in pairs(gained) do
            local info = RuneConfig.CURRENCIES[currId]
            local name = info and info.name or currId
            parts[#parts + 1] = name .. "×" .. amount
        end
        Toast.Show("分解获得: " .. table.concat(parts, " "), {100,255,100})
    else
        Toast.Show(msg or "分解失败", {255,100,80})
    end
    selectedRune = nil
    RuneUI.Refresh()
end

--- 高品质符文分解确认弹窗
local decomposeConfirmOverlay = nil
function RuneUI._showDecomposeConfirm(rune)
    if decomposeConfirmOverlay then return end

    local quality = RuneData.GetQuality(rune.qualityId)
    local series = RuneData.GetSeries(rune.seriesId)
    local qName = quality and quality.name or "未知"
    local sName = series and series.name or "未知"
    local qColor = quality and quality.color or {255,255,255}

    local function closeConfirm()
        if decomposeConfirmOverlay and pageRoot then
            pageRoot:RemoveChild(decomposeConfirmOverlay)
            decomposeConfirmOverlay = nil
        end
    end

    -- 预览分解获得
    local decomposeLoot = RuneConfig.DECOMPOSE[rune.qualityId] or {}
    local lootChildren = {}
    for currId, amount in pairs(decomposeLoot) do
        local info = RuneConfig.CURRENCIES[currId]
        lootChildren[#lootChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                Currency.IconWidget(UI, currId, 16),
                UI.Label {
                    text = (info and info.name or currId) .. " +" .. amount,
                    fontSize = 13, fontColor = {220,210,200},
                },
            },
        }
    end

    local confirmCard = UI.Panel {
        width = 260,
        backgroundColor = { 40, 28, 18, 250 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { qColor[1], qColor[2], qColor[3], 200 },
        paddingTop = 16, paddingBottom = 14,
        paddingLeft = 16, paddingRight = 16,
        alignItems = "center",
        gap = 10,
        onClick = function(self) end,  -- 阻止穿透
        children = {
            UI.Label {
                text = "确认分解",
                fontSize = 17, fontColor = {255,120,100}, fontWeight = "bold",
            },
            UI.Label {
                text = qName .. " · " .. sName,
                fontSize = 14, fontColor = { qColor[1], qColor[2], qColor[3], 255 }, fontWeight = "bold",
            },
            UI.Label {
                text = "该符文品质较高，分解后无法恢复",
                fontSize = 12, fontColor = {200,180,160},
            },
            UI.Panel { width = "90%", height = 1, backgroundColor = {100,75,55,100} },
            UI.Label { text = "分解获得", fontSize = 13, fontColor = {255,200,100}, fontWeight = "bold" },
            UI.Panel { alignItems = "center", gap = 4, children = lootChildren },
            UI.Panel { width = "90%", height = 1, backgroundColor = {100,75,55,100} },
            UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 4,
                children = {
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = {80,60,45,220},
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self) closeConfirm() end,
                        children = {
                            UI.Label { text = "取消", fontSize = 14, fontColor = {200,180,160} },
                        },
                    },
                    UI.Panel {
                        paddingLeft = 20, paddingRight = 20,
                        paddingTop = 8, paddingBottom = 8,
                        borderRadius = 8,
                        backgroundColor = {160,50,40,240},
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self)
                            closeConfirm()
                            RuneUI._doDecompose(rune)
                        end,
                        children = {
                            UI.Label { text = "确认分解", fontSize = 14, fontColor = {255,255,255}, fontWeight = "bold" },
                        },
                    },
                },
            },
        },
    }

    decomposeConfirmOverlay = UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = {0,0,0,160},
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self) closeConfirm() end,
        children = { confirmCard },
    }
    pageRoot:AddChild(decomposeConfirmOverlay)
end

return RuneUI
