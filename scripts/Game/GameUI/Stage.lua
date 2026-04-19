-- Game/GameUI/Stage.lua
-- 关卡流程：自动合并、波次就绪、游戏结束、通关结算、菜单

return function(GameUI, ctx)

local Config   = require("Game.Config")
local State    = require("Game.State")
local Tower    = require("Game.Tower")
local Wave     = require("Game.Wave")
local Currency = require("Game.Currency")
local HeroData = require("Game.HeroData")
local ChestData = require("Game.ChestData")

local AudioManager = require("Game.AudioManager")
local Renderer = require("Game.Renderer")
local IdleScreen = require("Game.IdleScreen")
local FormatNum = ctx.FormatNum

function GameUI.AutoMerge()
    local merged = false
    -- 从低星开始找第一个可合成的配对
    for star = 1, Config.MAX_STAR - 1 do
        for i = 1, #State.towers do
            local t1 = State.towers[i]
            if t1 and t1.star == star and t1.star < Config.MAX_STAR then
                for j = i + 1, #State.towers do
                    local t2 = State.towers[j]
                    if t2 and t2.typeIndex == t1.typeIndex and t2.star == t1.star then
                        if Tower.CanMerge(t1, t2) then
                            local result = Tower.Merge(t1, t2)
                            if result then
                                merged = true
                                break
                            end
                        end
                    end
                end
            end
            if merged then break end
        end
        if merged then break end
    end
    if not merged then
        print("[UI] No mergeable pair found")
    end
    GameUI.UpdateHUD()
end

--- 波次准备面板
function GameUI.CreateWaveReadyPanel()
    return ctx.UI.Panel {
        id = "waveReadyPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            ctx.UI.Panel {
                padding = 24,
                gap = 12,
                backgroundColor = { 20, 16, 32, 230 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 70, 160, 150 },
                alignItems = "center",
                pointerEvents = "auto",
                children = {
                    ctx.UI.Label {
                        id = "nextWaveLabel",
                        text = "准备下一波",
                        fontSize = 18,
                        fontColor = Config.COLORS.textPrimary,
                    },
                    ctx.UI.Button {
                        text = "开始波次",
                        variant = "primary",
                        fontSize = 16,
                        onClick = function(self)
                            Wave.StartNext()
                            State.phase = State.PHASE_PLAYING
                            GameUI.ShowPanel("waveReadyPanel", false)
                            GameUI.UpdateHUD()
                        end,
                    },
                }
            }
        }
    }
end

--- 失败面板（无奖励）
function GameUI.CreateGameOverPanel()
    return ctx.UI.Panel {
        id = "gameOverPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        children = {
            ctx.UI.Panel {
                width = 260,
                paddingTop = 24, paddingBottom = 24,
                paddingLeft = 20, paddingRight = 20,
                gap = 12,
                backgroundColor = { 30, 20, 45, 245 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 200, 50, 50, 200 },
                alignItems = "center",
                children = {
                    ctx.UI.Label {
                        text = "挑战失败",
                        fontSize = 26,
                        fontColor = { 220, 50, 50, 255 },
                    },
                    ctx.UI.Label {
                        id = "failStageLabel",
                        text = "第1关",
                        fontSize = 16,
                        fontColor = Config.COLORS.textSecondary,
                    },
                    ctx.UI.Label {
                        id = "failWaveLabel",
                        text = "进度: 0/20",
                        fontSize = 14,
                        fontColor = Config.COLORS.textSecondary,
                    },
                    -- 提示
                    ctx.UI.Label {
                        text = "通关才有奖励，提升英雄再来!",
                        fontSize = 12,
                        fontColor = { 180, 140, 100, 200 },
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 2, marginBottom = 2,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    ctx.UI.Button {
                        text = "重新挑战",
                        variant = "primary",
                        fontSize = 16,
                        onClick = function(self)
                            GameUI.RetryStage()
                        end,
                    },
                }
            }
        }
    }
end

--- 通关结算面板（有奖励）
function GameUI.CreateStageClearPanel()
    return ctx.UI.Panel {
        id = "stageClearPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        children = {
            ctx.UI.Panel {
                width = 280,
                paddingTop = 24, paddingBottom = 24,
                paddingLeft = 20, paddingRight = 20,
                gap = 10,
                backgroundColor = { 20, 25, 50, 245 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 255, 200, 50, 200 },
                alignItems = "center",
                children = {
                    ctx.UI.Label {
                        id = "clearTitleLabel",
                        text = "通关!",
                        fontSize = 28,
                        fontColor = Config.COLORS.textGold,
                    },
                    ctx.UI.Label {
                        id = "clearStageLabel",
                        text = "第1关",
                        fontSize = 16,
                        fontColor = Config.COLORS.textPrimary,
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 4, marginBottom = 4,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    ctx.UI.Label {
                        text = "通关奖励",
                        fontSize = 16,
                        fontColor = { 180, 160, 220, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearGoldLabel",
                        text = "冥晶: +0",
                        fontSize = 14,
                        fontColor = { 255, 215, 0, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearDiamondLabel",
                        text = "暗影精华: +0",
                        fontSize = 14,
                        fontColor = { 100, 200, 255, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearTokenLabel",
                        text = "虚空契约: +0",
                        fontSize = 14,
                        fontColor = { 200, 180, 100, 255 },
                    },
                    ctx.UI.Label {
                        id = "clearFragLabel",
                        text = "碎片: +0",
                        fontSize = 14,
                        fontColor = { 180, 120, 255, 255 },
                    },
                    -- 分隔线
                    ctx.UI.Panel {
                        width = "90%", height = 1,
                        marginTop = 4, marginBottom = 4,
                        backgroundColor = { 100, 70, 160, 100 },
                    },
                    ctx.UI.Button {
                        text = "下一关",
                        variant = "primary",
                        fontSize = 16,
                        onClick = function(self)
                            GameUI.NextStage()
                        end,
                    },
                }
            }
        }
    }
end

--- 设置按钮 + 弹窗（手动保存、返回区服选择、兑换码）
-- 注意：齿轮按钮已移至 CreateHUD() 内部，此处仅保留空容器供兼容调用
function GameUI.CreateMenuPanel()
    return ctx.UI.Panel {
        id = "menuPanel",
        pointerEvents = "none",
    }
end

--- 兑换码定义（全服通用，每个账号只能兑换一次）
local REDEEM_CODES = {
    {
        code = "FROST100",
        desc = "霜誓契约 x100",
        color = { 130, 210, 255 },
        reward = function()
            Currency.Add("frost_pact", 100)
        end,
    },
    {
        code = "WOOD100",
        desc = "朽木宝箱 x100",
        color = { 160, 130, 80 },
        reward = function()
            ChestData.Add("wood", 100)
            ChestData.Save()
        end,
    },
    {
        code = "VIP1915921944",
        desc = "暗影精粹 x3000",
        color = { 180, 100, 255 },
        allowedUser = 1915921944,
        reward = function()
            Currency.Add("shadow_essence", 3000)
        end,
    },
    {
        code = "VIP1296664190",
        desc = "冥晶 x500000 + 暗影精粹 x1000",
        color = { 255, 180, 60 },
        allowedUser = 1296664190,
        reward = function()
            Currency.Add("nether_crystal", 500000)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "WORLDBOSS",
        desc = "暗影精粹 x3000",
        color = { 180, 100, 255 },
        reward = function()
            Currency.Add("shadow_essence", 3000)
        end,
    },
    {
        code = "VIP1779057459",
        desc = "符文大礼包：裂隙之尘×10000 + 封印×100 + 结晶×50 + 神话符文×6",
        color = { 255, 50, 50 },
        allowedUser = 1779057459,
        reward = function()
            -- 三种符文货币
            Currency.Add("rift_dust", 10000)
            Currency.Add("rune_seal", 100)
            Currency.Add("abyss_crystal", 50)
            -- 每个系列各一枚神话(红)符文
            local RuneData = require("Game.RuneData")
            local RuneConfig = require("Game.Config_Runes")
            for _, s in ipairs(RuneConfig.SERIES) do
                local rune = RuneData.Generate(100)
                rune.qualityId = "red"
                rune.seriesId  = s.id
                rune.maxAffixes = 4
                RuneData.AddToBag(rune)
            end
        end,
    },
    {
        code = "VIP80503484",
        desc = "霜誓契约 x10",
        color = { 130, 210, 255 },
        allowedUser = 80503484,
        reward = function()
            Currency.Add("frost_pact", 10)
        end,
    },
    {
        code = "RUNERIFT",
        desc = "霜誓契约 x30",
        color = { 130, 210, 255 },
        reward = function()
            Currency.Add("frost_pact", 30)
        end,
    },
    {
        code = "VIP1699603952",
        desc = "铂金宝箱 x50",
        color = { 200, 220, 255 },
        allowedUser = 1699603952,
        reward = function()
            ChestData.Add("platinum", 50)
            ChestData.Save()
        end,
    },
    {
        code = "CHEST2025",
        desc = "朽木宝箱 x100 + 青铜宝箱 x50",
        color = { 160, 130, 80 },
        reward = function()
            ChestData.Add("wood", 100)
            ChestData.Add("bronze", 50)
            ChestData.Save()
        end,
    },
    {
        code = "VIP346333596",
        desc = "专属奖励：暗影精粹 ×2000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 2000) end,
    },
    {
        code = "VIP881479440",
        desc = "专属奖励：暗影精粹 ×3000",
        color = { 255, 215, 0 },
        allowedUser = 881479440,
        reward = function() Currency.Add("shadow_essence", 3000) end,
    },
    {
        code = "VIP1699603952B",
        desc = "专属奖励：暗影精粹 ×5000",
        color = { 255, 215, 0 },
        allowedUser = 1699603952,
        reward = function() Currency.Add("shadow_essence", 5000) end,
    },
    {
        code = "VIP748065890",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 748065890,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP191390351",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 191390351,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP1006084432",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 1006084432,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP221406954",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 221406954,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "RUNE2025",
        desc = "符文豪华礼包：每系列每品质各1枚（36枚） + 大量货币",
        color = { 255, 215, 0 },
        allowedUser = 1779057459,
        reward = function()
            Currency.Add("rift_dust", 50000)
            Currency.Add("rune_seal", 500)
            Currency.Add("abyss_crystal", 200)
            local RuneData = require("Game.RuneData")
            local RuneConfig = require("Game.Config_Runes")
            local qualities = {"white","green","blue","purple","orange","red"}
            for _, s in ipairs(RuneConfig.SERIES) do
                for _, qid in ipairs(qualities) do
                    local rune = RuneData.Generate(100)
                    rune.qualityId = qid
                    rune.seriesId  = s.id
                    if qid == "red" then rune.maxAffixes = 4
                    elseif qid == "orange" then rune.maxAffixes = 3
                    else rune.maxAffixes = 2 end
                    RuneData.AddToBag(rune)
                end
            end
        end,
    },
    {
        code = "VIP1564171575",
        desc = "专属奖励：铂金宝箱 ×1000",
        color = { 200, 220, 255 },
        allowedUser = 1564171575,
        reward = function()
            ChestData.Add("platinum", 1000)
            ChestData.Save()
        end,
    },
    {
        code = "VIP274791815",
        desc = "专属奖励：冥晶 ×3000000 + 暗影精粹 ×1000",
        color = { 255, 180, 60 },
        allowedUser = 274791815,
        reward = function()
            Currency.Add("nether_crystal", 3000000)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP897945791",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 897945791,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP346333596B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP420284230",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 420284230,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP897945791B",
        desc = "专属奖励：冥晶礼包 ×15 + 免广告券 ×5 + 暗影精粹 ×1000",
        color = { 140, 80, 200 },
        allowedUser = 897945791,
        reward = function()
            local Inv = require("Game.InventoryData")
            Inv.Add("nether_crystal_pack", 15)
            Currency.Add("ad_ticket", 5)
            Currency.Add("shadow_essence", 1000)
        end,
    },
    {
        code = "VIP346333596C",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 346333596,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP274791815B",
        desc = "专属奖励：暗影精粹 ×1000",
        color = { 255, 215, 0 },
        allowedUser = 274791815,
        reward = function() Currency.Add("shadow_essence", 1000) end,
    },
    {
        code = "VIP1564171575",
        desc = "专属奖励：试练塔挑战券 ×1000",
        color = { 80, 200, 220 },
        allowedUser = 1564171575,
        reward = function()
            local TTD = require("Game.TrialTowerData")
            TTD.AddTickets(1000)
        end,
    },
    {
        code = "VIP1564171575B",
        desc = "专属奖励：试练塔挑战券 ×1000",
        color = { 80, 200, 220 },
        allowedUser = 1564171575,
        reward = function()
            local TTD = require("Game.TrialTowerData")
            TTD.AddTickets(1000)
        end,
    },
    {
        code = "VIP1564171575C",
        desc = "专属奖励：虚空契约 ×1000",
        color = { 160, 100, 255 },
        allowedUser = 1564171575,
        reward = function()
            Currency.Add("void_pact", 1000)
        end,
    },
}

--- 显示设置弹窗
function GameUI.ShowSettingsPopup()
    if not ctx.uiRoot or not ctx.UI then return end

    local old = ctx.uiRoot:FindById("settingsModal")
    if old then ctx.uiRoot:RemoveChild(old) end

    local SlotSave = require("Game.SlotSaveSystem")
    local Toast    = require("Game.Toast")

    if not HeroData.redeemData then HeroData.redeemData = {} end

    local function closeModal()
        local m = ctx.uiRoot and ctx.uiRoot:FindById("settingsModal")
        if m then ctx.uiRoot:RemoveChild(m) end
    end

    -- 兑换码输入值
    local redeemInput = ""

    local function tryRedeem()
        local code = redeemInput:match("^%s*(.-)%s*$")  -- trim
        if code == "" then
            Toast.Show("请输入兑换码")
            return
        end
        code = code:upper()  -- 统一大写比对
        -- 查找匹配的兑换码
        local found = nil
        for _, def in ipairs(REDEEM_CODES) do
            if def.code == code then
                found = def
                break
            end
        end
        if not found then
            Toast.Show("无效的兑换码")
            return
        end
        if found.allowedUser then
            local myId = clientCloud and clientCloud.userId
            if not myId or tostring(myId) ~= tostring(found.allowedUser) then
                Toast.Show("该兑换码不属于当前账号")
                return
            end
        end
        if HeroData.redeemData[found.code] then
            Toast.Show("该兑换码已使用过")
            return
        end
        found.reward()
        HeroData.redeemData[found.code] = true
        SlotSave.MarkDirty()
        Toast.Show(found.desc .. " 兑换成功!")
        closeModal()
    end

    local modal = ctx.UI.Panel {
        id = "settingsModal",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        zIndex = 50,
        onClick = function(self) closeModal() end,
        children = {
            ctx.UI.Panel {
                width = 300,
                backgroundColor = { 20, 14, 40, 250 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 160, 120, 255, 160 },
                paddingTop = 18, paddingBottom = 18,
                paddingLeft = 20, paddingRight = 20,
                gap = 14,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function(self) end,
                children = {
                    -- 标题
                    ctx.UI.Label {
                        text = "设置",
                        fontSize = 20,
                        fontColor = { 200, 170, 255, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 60 } },

                    -- 音乐音量
                    ctx.UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            ctx.UI.Label {
                                text = "音乐音量",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Slider {
                                value = math.floor(AudioManager.GetBGMVolume() * 100),
                                min = 0, max = 100,
                                width = "100%",
                                height = 28,
                                onChange = function(self, v)
                                    AudioManager.SetBGMVolume(v / 100)
                                end,
                            },
                        },
                    },
                    -- 音效音量
                    ctx.UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            ctx.UI.Label {
                                text = "音效音量",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Slider {
                                value = math.floor(AudioManager.GetSFXVolume() * 100),
                                min = 0, max = 100,
                                width = "100%",
                                height = 28,
                                onChange = function(self, v)
                                    AudioManager.SetSFXVolume(v / 100)
                                end,
                            },
                        },
                    },

                    -- 背景遮罩透明度
                    ctx.UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            ctx.UI.Label {
                                text = "背景遮罩",
                                fontSize = 13,
                                fontColor = { 180, 160, 220, 255 },
                            },
                            ctx.UI.Slider {
                                value = math.floor(Renderer.bgOverlayAlpha / 255 * 100),
                                min = 0, max = 100,
                                width = "100%",
                                height = 28,
                                onChange = function(self, v)
                                    Renderer.SetBgOverlayAlpha(math.floor(v / 100 * 255))
                                end,
                            },
                        },
                    },

                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 手动保存
                    ctx.UI.Button {
                        text = "手动保存",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            if SlotSave.GetActiveSlot() > 0 then
                                SlotSave.SaveNow()
                                Toast.Show("存档已保存")
                            else
                                Toast.Show("当前无活跃存档")
                            end
                        end,
                    },
                    -- 返回区服选择
                    ctx.UI.Button {
                        text = "返回区服选择",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            closeModal()
                            GameUI.ReturnToServerSelect()
                        end,
                    },
                    -- 待机模式
                    ctx.UI.Button {
                        text = "待机模式",
                        fontSize = 14,
                        width = "100%",
                        height = 40,
                        borderRadius = 8,
                        variant = "outline",
                        onClick = function(self)
                            closeModal()
                            IdleScreen.Show()
                        end,
                    },

                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 兑换码区域
                    ctx.UI.Label {
                        text = "[ 兑换码 ]",
                        fontSize = 15,
                        fontColor = { 255, 200, 60, 255 },
                        fontWeight = "bold",
                    },
                    ctx.UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            ctx.UI.TextField {
                                id = "redeemCodeInput",
                                value = "",
                                placeholder = "请输入兑换码",
                                fontSize = 14,
                                fontColor = { 255, 255, 255, 255 },
                                textAlign = "center",
                                maxLength = 20,
                                flex = 1,
                                height = 40,
                                backgroundColor = { 35, 28, 55, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 100, 80, 160, 180 },
                                onChange = function(self, value)
                                    redeemInput = value or ""
                                end,
                                onSubmit = function(self, value)
                                    redeemInput = value or ""
                                    tryRedeem()
                                end,
                            },
                            ctx.UI.Panel {
                                width = 64, height = 40,
                                borderRadius = 8,
                                backgroundColor = { 120, 70, 220, 255 },
                                justifyContent = "center",
                                alignItems = "center",
                                pointerEvents = "auto",
                                onClick = function(self)
                                    tryRedeem()
                                end,
                                children = {
                                    ctx.UI.Label {
                                        text = "兑换",
                                        fontSize = 14,
                                        fontColor = { 255, 255, 255, 255 },
                                    },
                                },
                            },
                        },
                    },

                    ctx.UI.Panel { width = "100%", height = 1, backgroundColor = { 160, 120, 255, 40 } },

                    -- 关闭按钮
                    ctx.UI.Panel {
                        width = 140, height = 38,
                        backgroundColor = { 80, 50, 130, 200 },
                        borderRadius = 19,
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self) closeModal() end,
                        children = {
                            ctx.UI.Label {
                                text = "关闭",
                                fontSize = 14,
                                fontColor = { 220, 210, 240, 255 },
                            },
                        },
                    },
                },
            },
        },
    }

    ctx.uiRoot:AddChild(modal)
end

--- 显示/隐藏面板
function GameUI.ShowPanel(panelId, visible)
    if not ctx.uiRoot then return end
    local panel = ctx.uiRoot:FindById(panelId)
    if panel then
        panel:SetVisible(visible)
    end
end

--- 隐藏所有弹出面板
local function HideAllPanels()
    GameUI.ShowPanel("gameOverPanel", false)
    GameUI.ShowPanel("stageClearPanel", false)
    GameUI.ShowPanel("idleRewardPanel", false)
    GameUI.ShowPanel("waveReadyPanel", false)
    -- menuPanel（设置按钮）始终可见，不在此隐藏
end

--- 开始一个关卡（通过 BattleManager.Enter 统一启动）
local function StartStage(stageNum)
    HideAllPanels()
    local BM = require("Game.BattleManager")
    BM.Enter("campaign", {
        stageNum = stageNum,
        onWin    = function() GameUI.DoStageClear() end,
        onLose   = function() GameUI.DoGameOver() end,
    })
    print("[GameUI] Starting stage " .. stageNum)
end

--- 重新挑战当前关（失败后调用）
function GameUI.RetryStage()
    StartStage(State.currentStage)
end

--- 重新开始游戏（从第1关开始，兼容旧调用）
function GameUI.RestartGame()
    StartStage(1)
end

--- 进入下一关（通关后调用）
function GameUI.NextStage()
    StartStage(State.currentStage + 1)
end

--- 通关结算：计算奖励并显示通关面板
function GameUI.DoStageClear()
    local stageNum = State.currentStage
    local rewards = HeroData.SettleRewards(stageNum, State.score)
    State.settleRewards = rewards

    -- 通关产出宝箱
    ChestData.GrantStageDrop(stageNum)

    -- 开服好礼任务追踪
    local ok, LGD = pcall(require, "Game.LaunchGiftData")
    if ok and LGD then LGD.AddProgress("stage", 1) end
    -- 每日任务追踪（通关 + 战斗）
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then
        DTD.AddProgress("stage", 1)
        DTD.AddProgress("battle", 1)
    end

    if ctx.uiRoot then
        local tl = ctx.uiRoot:FindById("clearStageLabel")
        if tl then tl:SetText("第" .. stageNum .. "关") end

        local gl = ctx.uiRoot:FindById("clearGoldLabel")
        if gl then gl:SetText("冥晶: +" .. rewards.nether_crystal) end

        local dl = ctx.uiRoot:FindById("clearDiamondLabel")
        if dl then
            if rewards.shadow_essence > 0 then
                dl:SetText("暗影精华: +" .. rewards.shadow_essence)
                dl:SetVisible(true)
            else
                dl:SetVisible(false)
            end
        end

        local tl2 = ctx.uiRoot:FindById("clearTokenLabel")
        if tl2 then
            if rewards.void_pact and rewards.void_pact > 0 then
                tl2:SetText("虚空契约: +" .. rewards.void_pact)
                tl2:SetVisible(true)
            else
                tl2:SetVisible(false)
            end
        end

        local fl = ctx.uiRoot:FindById("clearFragLabel")
        if fl then
            if rewards.totalFragments > 0 then
                local fragParts = {}
                for heroId, count in pairs(rewards.fragments) do
                    local heroName = heroId
                    for _, td in ipairs(Config.TOWER_TYPES) do
                        if td.id == heroId then heroName = td.name; break end
                    end
                    fragParts[#fragParts + 1] = heroName .. "x" .. count
                end
                fl:SetText("碎片: +" .. rewards.totalFragments .. " (" .. table.concat(fragParts, ", ") .. ")")
                fl:SetVisible(true)
            else
                fl:SetVisible(false)
            end
        end
    end

    -- 不显示通关弹窗，直接进入下一关
    print("[GameUI] Stage " .. stageNum .. " clear! nether_crystal+" .. rewards.nether_crystal .. " shadow_essence+" .. rewards.shadow_essence .. " frags+" .. rewards.totalFragments)
    GameUI.NextStage()
end

--- 自动召唤：用光所有金币填满格子
local function AutoSummonAll()
    local count = 0
    while true do
        local canSummon = Tower.CanSummon()
        if not canSummon then break end
        local t = Tower.Summon()
        if not t then break end
        count = count + 1
    end
    print("[GameUI] Auto-summoned " .. count .. " towers")
    return count
end

--- 自动合成：循环合成直到无法继续（从低星开始）
local function AutoMergeAll()
    local totalMerged = 0
    local merged = true
    while merged do
        merged = false
        for star = 1, Config.MAX_STAR - 1 do
            for i = 1, #State.towers do
                local t1 = State.towers[i]
                if t1 and t1.star == star and t1.star < Config.MAX_STAR then
                    for j = i + 1, #State.towers do
                        local t2 = State.towers[j]
                        if t2 and t2.typeIndex == t1.typeIndex and t2.star == t1.star then
                            if Tower.CanMerge(t1, t2) then
                                local result = Tower.Merge(t1, t2)
                                if result then
                                    totalMerged = totalMerged + 1
                                    merged = true
                                    break
                                end
                            end
                        end
                    end
                end
                if merged then break end
            end
            if merged then break end
        end
    end
    print("[GameUI] Auto-merged " .. totalMerged .. " pairs")
    return totalMerged
end

--- 失败处理：记录任务进度，重置并重新开始当前关卡
function GameUI.DoGameOver()
    -- 每日任务追踪（战斗失败也计为一次战斗）
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("battle", 1) end

    local failedStage = State.currentStage
    local failedWave  = State.currentWave
    print("[GameUI] Stage " .. failedStage .. " failed at wave " .. failedWave .. ", restarting same stage")

    -- 重置并重新开始（BattleManager.Enter 内部处理 Reset/Leader/Wave 等全部逻辑）
    StartStage(failedStage)
end


end
