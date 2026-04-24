-- Game/DungeonUI/HatredLand.lua
-- 憎恨之地详情页 UI + 挑战逻辑

local Config = require("Game.Config")
local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local HL = require("Game.HatredLandData")
local HatredBossSkills = require("Game.HatredBossSkills")
local Toast = require("Game.Toast")
local RewardDisplay = require("Game.RewardDisplay")
local AdHelper = require("Game.AdHelper")
local SweepPopup = require("Game.SweepPopup")

local HatredLand = {}

-- ============================================================================
-- 详情页
-- ============================================================================

function HatredLand.BuildDetailView(ctx)
    local UI = ctx.GetUI()
    local pageRoot = ctx.GetPageRoot()
    local S = ctx.GetS()

    local data = HL.GetData()
    local bestDamage = HL.GetBestDamage()
    local remaining = HL.GetRemainingAttempts()
    local cfg = HL.CONFIG
    local selectedDiff = HL.GetSelectedDifficulty()

    -- 标题栏
    pageRoot:AddChild(UI.Panel {
        width = "100%", height = 50,
        flexDirection = "row", alignItems = "center",
        backgroundColor = S.headerBg, flexShrink = 0,
        children = {
            UI.Panel {
                width = 50, height = 50,
                justifyContent = "center", alignItems = "center",
                onClick = function() ctx.SetView("list") end,
                children = { UI.Label { text = "‹", fontSize = 22, fontColor = S.dim, pointerEvents = "none" } },
            },
            UI.Label {
                text = "憎恨之地", fontSize = 20, fontWeight = "bold",
                fontColor = S.white, pointerEvents = "none",
            },
            UI.Panel { flex = 1 },
            UI.Panel {
                paddingLeft = 8, paddingRight = 12, paddingTop = 3, paddingBottom = 3,
                children = {
                    UI.Label {
                        text = "剩余 " .. remaining .. " 次",
                        fontSize = 12,
                        fontColor = remaining > 0 and S.green or S.red,
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    local contentChildren = {}

    -- BOSS 信息卡
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 8, flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                backgroundColor = S.cardBg, borderRadius = 8,
                borderWidth = 1, borderColor = { 180, 40, 60, 80 },
                paddingLeft = 14, paddingRight = 14, paddingTop = 12, paddingBottom = 12,
                children = {
                    UI.Panel {
                        flexDirection = "column", gap = 4,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 6,
                                children = {
                                    UI.Label {
                                        text = "憎恨化身", fontSize = 18, fontWeight = "bold",
                                        fontColor = { 180, 40, 60 }, pointerEvents = "none",
                                    },
                                },
                            },
                            UI.Label {
                                text = "HP: 无限  |  DEF: " .. ctx.FormatNum(cfg.bossDEF * (HL.GetDifficultyDef(selectedDiff).attrMult)),
                                fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                            },
                            UI.Label {
                                text = "无限时长 · 5大技能 · 每秒掉落" .. cfg.darkSoulDrain .. "暗魂",
                                fontSize = 11, fontColor = S.dim, pointerEvents = "none",
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column", alignItems = "flex-end", gap = 4,
                        children = {
                            UI.Label { text = "最高伤害", fontSize = 11, fontColor = S.dim, pointerEvents = "none" },
                            UI.Label {
                                text = bestDamage > 0 and HL.FormatDamage(bestDamage) or "—",
                                fontSize = 16, fontWeight = "bold",
                                fontColor = bestDamage > 0 and S.gold or S.dim,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
        },
    }

    -- 难度选择器
    local diffButtons = {}
    for _, d in ipairs(HL.DIFFICULTY_LEVELS) do
        local isSelected = (d.level == selectedDiff)
        local isUnlocked = HL.IsDifficultyUnlocked(d.level)
        local diffLevel = d.level

        local diffColors = {
            [0] = { 120, 180, 120 },
            [1] = { 200, 180, 80 },
            [3] = { 220, 120, 60 },
            [9] = { 220, 50, 50 },
        }
        local color = diffColors[d.level] or S.dim

        diffButtons[#diffButtons + 1] = UI.Panel {
            flex = 1, height = 40,
            justifyContent = "center", alignItems = "center",
            backgroundColor = isSelected and { color[1], color[2], color[3], 60 } or { 30, 30, 40, 120 },
            borderRadius = 6, borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and color or { 60, 60, 70, 100 },
            opacity = isUnlocked and 1.0 or 0.4,
            onClick = isUnlocked and function()
                HL.SetSelectedDifficulty(diffLevel)
                ctx.Refresh()
            end or nil,
            children = {
                UI.Label {
                    text = d.label, fontSize = 12,
                    fontWeight = isSelected and "bold" or "normal",
                    fontColor = isSelected and color or (isUnlocked and S.white or S.dim),
                    pointerEvents = "none",
                },
                UI.Label {
                    text = isUnlocked and ("Lv." .. d.level) or "锁定",
                    fontSize = 9, fontColor = isSelected and color or S.dim,
                    pointerEvents = "none",
                },
            },
        }
    end

    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 6, flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%", backgroundColor = S.cardBg, borderRadius = 8,
                paddingLeft = 10, paddingRight = 10, paddingTop = 8, paddingBottom = 8,
                flexDirection = "column", gap = 6,
                children = {
                    UI.Label { text = "难度选择", fontSize = 13, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                    UI.Panel { width = "100%", flexDirection = "row", gap = 6, children = diffButtons },
                    UI.Label {
                        text = (function()
                            local diff = HL.GetDifficultyDef(selectedDiff)
                            if selectedDiff == 0 then
                                return "原始难度，适合入门挑战"
                            else
                                local multStr
                                if diff.attrMult >= 10000000000 then
                                    multStr = string.format("%.0f亿", diff.attrMult / 100000000)
                                elseif diff.attrMult >= 10000 then
                                    multStr = string.format("%.0f万", diff.attrMult / 10000)
                                else
                                    multStr = tostring(diff.attrMult)
                                end
                                return "全属性×" .. multStr .. "  技能CD-" .. diff.cdReduction .. "秒  暗魂+" .. diff.darkSoulBonus .. "/秒"
                            end
                        end)(),
                        fontSize = 10, fontColor = S.dim, pointerEvents = "none",
                    },
                },
            },
        },
    }

    -- BOSS 技能说明
    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 6, flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%", backgroundColor = S.cardBg, borderRadius = 8,
                paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
                flexDirection = "column", gap = 6,
                children = {
                    UI.Label { text = "BOSS 技能", fontSize = 13, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
                    UI.Label {
                        text = "深渊召唤 · 每20秒召唤精英怪，每次+1只(最多10只)，属性逐次增强",
                        fontSize = 11, fontColor = { 200, 140, 60 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "憎恨壁垒 · 每25秒获得护盾+防御永久翻倍，可无限叠加",
                        fontSize = 11, fontColor = { 80, 160, 220 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "怨恨嘲讽 · 每15秒嘲讽，攻击者攻速叠加降低",
                        fontSize = 11, fontColor = { 220, 60, 60 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "毁灭践踏 · 每30秒锁定3×3区域，3秒后降低英雄1星",
                        fontSize = 11, fontColor = { 180, 60, 180 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "终焉毁灭 · 每45秒选定区域摧毁英雄，范围随成功释放次数增长(最大5x5)",
                        fontSize = 11, fontColor = { 255, 40, 40 }, pointerEvents = "none",
                    },
                    UI.Label {
                        text = "提示：集火打断韧性条可阻止践踏和毁灭，韧性与防御成正比",
                        fontSize = 10, fontColor = S.dim, pointerEvents = "none",
                    },
                },
            },
        },
    }

    -- 奖励档位
    local tierRows = {}
    tierRows[#tierRows + 1] = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between", paddingBottom = 4,
        children = {
            UI.Label { text = "累计伤害", fontSize = 12, fontWeight = "bold", fontColor = S.white, pointerEvents = "none" },
            UI.Label { text = "遗物奖励", fontSize = 12, fontWeight = "bold", fontColor = { 255, 215, 100 }, pointerEvents = "none" },
        },
    }

    local samplePoints = HL.GetRewardSamplePoints(selectedDiff)
    for i, pt in ipairs(samplePoints) do
        local threshold = pt[1]
        local essenceAmt = pt[2]
        local shardAmt = pt[3]
        local reached = bestDamage >= threshold

        tierRows[#tierRows + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between",
            paddingTop = 3, paddingBottom = 3,
            backgroundColor = reached and { 45, 70, 45, 120 } or nil,
            borderRadius = 4, paddingLeft = 4, paddingRight = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label { text = reached and "V" or "", fontSize = 10, fontColor = reached and S.green or S.dim, fontWeight = reached and "bold" or "normal", width = 12, pointerEvents = "none" },
                        UI.Label { text = HL.FormatDamage(threshold), fontSize = 12, fontColor = reached and S.green or S.white, pointerEvents = "none" },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 2,
                            children = {
                                Currency.IconWidget(UI, "relic_essence", 12),
                                UI.Label { text = tostring(essenceAmt), fontSize = 11, fontColor = reached and { 255, 215, 100 } or S.dim, pointerEvents = "none" },
                            },
                        },
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 2,
                            children = {
                                UI.Label { text = "碎片", fontSize = 10, fontColor = reached and { 180, 160, 220 } or S.dim, pointerEvents = "none" },
                                UI.Label { text = "x" .. shardAmt, fontSize = 11, fontColor = reached and { 180, 160, 220 } or S.dim, pointerEvents = "none" },
                            },
                        },
                    },
                },
            },
        }
    end

    -- 公式说明
    tierRows[#tierRows + 1] = UI.Panel {
        width = "100%", paddingTop = 4, flexDirection = "column", gap = 2,
        children = {
            UI.Label { text = "伤害越高奖励越多，增速逐渐放缓", fontSize = 10, fontColor = S.dim, pointerEvents = "none" },
            UI.Label { text = "达标后每次额外掉落随机部位遗物碎片，集满可合成遗物", fontSize = 10, fontColor = { 150, 200, 255, 180 }, pointerEvents = "none" },
        },
    }

    contentChildren[#contentChildren + 1] = UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 6, flexShrink = 0,
        children = {
            UI.Panel {
                width = "100%", backgroundColor = S.cardBg, borderRadius = 8,
                paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
                flexDirection = "column", children = tierRows,
            },
        },
    }

    pageRoot:AddChild(UI.ScrollView {
        width = "100%", flex = 1, children = contentChildren,
    })

    -- 底部按钮
    pageRoot:AddChild(HatredLand._BuildChallengeButton(UI, S, ctx, remaining))
end

function HatredLand._BuildChallengeButton(UI, S, ctx, remaining)
    local freeRemaining = HL.GetFreeRemaining()
    local adRemaining = HL.GetAdRemaining()
    local ticketCount = HL.GetTicketCount()

    local actionChildren = {
        UI.Button {
            text = "返回", fontSize = 14,
            width = 70, height = 46, borderRadius = 8, variant = "outline",
            onClick = function() ctx.SetView("list") end,
        },
    }

    if freeRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "挑战憎恨化身", fontSize = 15,
            flex = 1, height = 46, borderRadius = 8, variant = "primary",
            onClick = function() HatredLand.OnChallenge(UI, S, ctx, false) end,
        }
    elseif ticketCount > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "使用挑战券 (剩" .. ticketCount .. "张)", fontSize = 14,
            flex = 1, height = 46, borderRadius = 8, variant = "primary",
            onClick = function() HatredLand.OnTicketChallenge(UI, S, ctx) end,
        }
    elseif adRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "领取挑战券后挑战", fontSize = 13,
            flex = 1, height = 46, borderRadius = 8, variant = "outline",
        }
    else
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "今日次数已用完", fontSize = 13,
            flex = 1, height = 46, borderRadius = 8, variant = "outline",
        }
    end

    if adRemaining > 0 then
        actionChildren[#actionChildren + 1] = UI.Button {
            text = "📺领券(" .. adRemaining .. ")", fontSize = 12,
            width = 90, height = 46, borderRadius = 8, variant = "outline",
            onClick = function() HatredLand.OnAdGetTicket(UI, S, ctx) end,
        }
    end

    actionChildren[#actionChildren + 1] = UI.Button {
        text = "扫荡", fontSize = 13,
        width = 80, height = 46, borderRadius = 8, variant = "outline",
        onClick = function() HatredLand.OnSweep(UI, S, ctx) end,
    }

    return UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12, paddingTop = 10, paddingBottom = 10,
        flexShrink = 0, gap = 10,
        children = actionChildren,
    }
end

-- ============================================================================
-- 挑战逻辑
-- ============================================================================

function HatredLand.OnAdGetTicket(UI, S, ctx)
    if HL.GetAdRemaining() <= 0 then
        Toast.Show("今日广告领券次数已达上限", { 255, 200, 80 })
        return
    end
    AdHelper.ShowRewardAd(function()
        HL.ConsumeAdForTicket()
        ctx.Refresh()
    end)
end

function HatredLand.OnTicketChallenge(UI, S, ctx)
    if not HL.ConsumeTicket() then return end
    HatredLand.OnChallenge(UI, S, ctx, true)
end

function HatredLand.OnChallenge(UI, S, ctx, skipConsume)
    if #HeroData.GetDeployedList() < Config.MAX_DEPLOYED then
        Toast.Show("需要上阵" .. Config.MAX_DEPLOYED .. "名英雄才能挑战", S.red)
        return
    end

    if not skipConsume then
        if not HL.ConsumeAttempt() then return end
    end

    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("boss", 1) end

    local BM = require("Game.BattleManager")
    local GameUI = require("Game.GameUI")
    local State = require("Game.State")

    local cfg = HL.CONFIG
    local challengeDifficulty = HL.GetSelectedDifficulty()
    local diffDef = HL.GetDifficultyDef(challengeDifficulty)

    local bossDef = HL.CreateBossDef()
    bossDef.baseDEF = (bossDef.baseDEF or cfg.bossDEF) * diffDef.attrMult

    local waves = {
        {
            {
                type = bossDef.id or "hatred_body",
                typeDef = bossDef,
                delay = 0,
                isElite = false,
                affixes = {},
                prescaled = true,
            },
        },
    }

    local label = "憎恨之地 · 憎恨化身" .. (challengeDifficulty > 0 and (" [" .. diffDef.label .. "]") or "")

    local function handleResult(result, isExit)
        HatredBossSkills.Cleanup()
        State.worldBossActive = false
        local totalDamage = result.totalDamage or State.worldBossTotalDamage

        local rewards = HL.ClaimReward(totalDamage, challengeDifficulty)
        local rewardItems = {}
        if rewards then
            if rewards.essence > 0 then
                local essenceDef = Config.CURRENCY["relic_essence"]
                rewardItems[#rewardItems + 1] = {
                    icon = essenceDef and essenceDef.image or "",
                    name = essenceDef and essenceDef.name or "遗物精华",
                    amount = rewards.essence,
                    borderColor = { 200, 150, 255, 200 },
                }
            end
            if rewards.shards > 0 then
                rewardItems[#rewardItems + 1] = {
                    icon = "",
                    name = "部位碎片",
                    amount = rewards.shards,
                    borderColor = { 150, 200, 255, 200 },
                }
            end
            -- 遗物碎片掉落
            if rewards.relicDrop then
                local rd = rewards.relicDrop
                local slotName = ""
                for _, s in ipairs(Config.RELIC_SLOTS) do
                    if s.id == rd.slotId then slotName = s.name; break end
                end
                rewardItems[#rewardItems + 1] = {
                    icon = "",
                    name = slotName .. "碎片",
                    amount = rd.shards,
                    borderColor = { 150, 200, 255, 200 },
                }
                -- 自动合成通知
                if rd.synthResult then
                    local sr = rd.synthResult
                    local qColor = Config.RELIC_QUALITY_COLOR[sr.quality] or { 180, 180, 180 }
                    rewardItems[#rewardItems + 1] = {
                        icon = "",
                        name = "合成: " .. sr.relicName .. " (" .. (Config.RELIC_QUALITY_NAME[sr.quality] or "?") .. ")",
                        amount = 1,
                        borderColor = { qColor[1], qColor[2], qColor[3], 200 },
                    }
                end
            end
        end

        local title = label .. (isExit and " 退出" or " 挑战结束") .. "\n伤害: " .. HL.FormatDamage(totalDamage)

        if #rewardItems > 0 then
            local root = GameUI.GetUIRoot()
            if root then
                RewardDisplay.Show(UI, root, {
                    title = title,
                    rewards = rewardItems,
                    onClose = function() GameUI.ExitDungeonBattle() end,
                })
                return
            end
        else
            Toast.Show("伤害: " .. HL.FormatDamage(totalDamage) .. (isExit and "" or " · 未达奖励阈值"), S.dim)
        end
        GameUI.ExitDungeonBattle()
    end

    GameUI.EnterDungeonBattle({
        mode = "world_boss",
        waves = waves,
        totalWaves = 1,
        stageNum = 1,
        label = label,
        waveInterval = 0,
        autoAdvanceWave = false,
        bossTimerEnabled = true,
        overloadEnabled = false,
        worldBossDuration = cfg.totalDuration,
        worldBossDarkSoulDrain = cfg.darkSoulDrain + diffDef.darkSoulBonus,
        initialDarkSoul = Config.INITIAL_DARK_SOUL,

        onStart = function()
            State.worldBossActive = true
            HatredBossSkills.Init(bossDef.bossSkills)
        end,
        onUpdate = function(dt)
            HatredBossSkills.Update(dt)
        end,

        onWin = function(result) handleResult(result, false) end,
        onExit = function(result) handleResult(result, true) end,
        onLose = function(result)
            local BM_ = require("Game.BattleManager")
            if BM_.config then BM_.config.onExit = nil end
            handleResult(result, false)
        end,
    })
end

-- ============================================================================
-- 扫荡
-- ============================================================================

function HatredLand.OnSweep(UI, S, ctx)
    local bestDamage = HL.GetBestDamage()
    if bestDamage <= 0 then
        Toast.Show("需要先挑战一次才能扫荡", { 255, 200, 80 })
        return
    end

    local ticketCount = HL.GetTicketCount()
    if ticketCount <= 0 then
        Toast.Show("没有可用的挑战券", { 255, 200, 80 })
        return
    end

    local GameUI = require("Game.GameUI")
    local root = GameUI.GetUIRoot()
    if not root then return end

    local selectedDiff = HL.GetSelectedDifficulty()

    SweepPopup.Show(UI, root, S, {
        title = "憎恨之地 · 连续扫荡",
        maxCount = ticketCount,
        sweepLabel = "最高伤害",
        sweepValue = HL.FormatDamage(bestDamage),
        previewFn = function(count)
            local calc = HL.CalcRewards(bestDamage, selectedDiff)
            local items = {}
            if calc.essence > 0 or calc.shards > 0 then
                if calc.essence > 0 then
                    local essenceDef = Config.CURRENCY["relic_essence"]
                    items[#items + 1] = {
                        icon = essenceDef and essenceDef.image or "",
                        name = essenceDef and essenceDef.name or "遗物精华",
                        amount = calc.essence * count,
                        color = { 200, 150, 255 },
                    }
                end
                if calc.shards > 0 then
                    items[#items + 1] = {
                        icon = "",
                        name = "部位碎片",
                        amount = calc.shards * count,
                        color = { 150, 200, 255 },
                    }
                end
            else
                items[#items + 1] = {
                    icon = "", name = "伤害未达奖励阈值", amount = 0, color = S.dim,
                }
            end
            return items
        end,
        onConfirm = function(count)
            local successCount = 0
            local totalEssence = 0
            local totalShards = 0
            local slotShards = {}   -- { [slotId] = totalShardCount }
            local synthResults = {} -- 合成结果列表
            for i = 1, count do
                if not HL.ConsumeTicket() then
                    Toast.Show("挑战券不足，已扫荡 " .. successCount .. " 次", { 255, 200, 80 })
                    break
                end
                local rewards = HL.ClaimReward(bestDamage, selectedDiff)
                if rewards then
                    totalEssence = totalEssence + (rewards.essence or 0)
                    totalShards = totalShards + (rewards.shards or 0)
                    -- 汇总遗物碎片掉落
                    if rewards.relicDrop then
                        local rd = rewards.relicDrop
                        slotShards[rd.slotId] = (slotShards[rd.slotId] or 0) + rd.shards
                        if rd.synthResult then
                            synthResults[#synthResults + 1] = rd.synthResult
                        end
                    end
                end
                successCount = successCount + 1
            end

            local ok2, DTD = pcall(require, "Game.DailyTaskData")
            if ok2 and DTD then DTD.AddProgress("boss", successCount) end

            if successCount > 0 then
                local rewardItems = {}
                if totalEssence > 0 then
                    local essenceDef = Config.CURRENCY["relic_essence"]
                    rewardItems[#rewardItems + 1] = {
                        icon = essenceDef and essenceDef.image or "",
                        name = essenceDef and essenceDef.name or "遗物精华",
                        amount = totalEssence,
                        borderColor = { 200, 150, 255, 200 },
                    }
                end
                if totalShards > 0 then
                    rewardItems[#rewardItems + 1] = {
                        icon = "",
                        name = "部位碎片",
                        amount = totalShards,
                        borderColor = { 150, 200, 255, 200 },
                    }
                end
                -- 各部位遗物碎片
                for slotId, cnt in pairs(slotShards) do
                    local slotName = ""
                    for _, s in ipairs(Config.RELIC_SLOTS) do
                        if s.id == slotId then slotName = s.name; break end
                    end
                    rewardItems[#rewardItems + 1] = {
                        icon = "",
                        name = slotName .. "碎片",
                        amount = cnt,
                        borderColor = { 150, 200, 255, 200 },
                    }
                end
                -- 合成通知
                for _, sr in ipairs(synthResults) do
                    local qColor = Config.RELIC_QUALITY_COLOR[sr.quality] or { 180, 180, 180 }
                    local qName = Config.RELIC_QUALITY_NAME[sr.quality] or "?"
                    rewardItems[#rewardItems + 1] = {
                        icon = "",
                        name = "合成: " .. sr.relicName .. " (" .. qName .. ")",
                        amount = 1,
                        borderColor = { qColor[1], qColor[2], qColor[3], 200 },
                    }
                end

                if #rewardItems > 0 then
                    RewardDisplay.Show(UI, root, {
                        title = "憎恨之地 扫荡 x" .. successCount .. " 完成!\n伤害: " .. HL.FormatDamage(bestDamage) .. " / 次",
                        rewards = rewardItems,
                        onClose = function() ctx.Refresh() end,
                    })
                else
                    Toast.Show("扫荡完成 x" .. successCount .. "（未达奖励阈值）", S.dim)
                    ctx.Refresh()
                end
            else
                Toast.Show("扫荡失败", S.dim)
                ctx.Refresh()
            end
        end,
    })
end

return HatredLand
