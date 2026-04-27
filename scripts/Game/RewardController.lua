-- Game/RewardController.lua
-- 奖励控制层：统一「reward def → 展示格式」转换 + RewardDisplay 调用
-- 作用：将 UI 层与数据层解耦，所有奖励展示通过此模块处理
--
-- 用法：
--   local RC = require("Game.RewardController")
--
--   -- 单个货币奖励
--   RC.ShowCurrency(UI, pageRoot, "shadow_essence", 100, "利息收益", onClose)
--
--   -- 从 reward defs 展示（{ type, id, amount } 格式）
--   RC.ShowFromDefs(UI, pageRoot, rewardDefs, "获得奖励", onClose)

local Config        = require("Game.Config")
local Currency      = require("Game.Currency")
local RewardDisplay = require("Game.RewardDisplay")

local RC = {}

-- ============================================================================
-- 奖励定义 → 展示格式转换
-- ============================================================================

--- 将单个奖励定义转为 RewardDisplay 所需格式
--- def: { type = "currency"|"item"|"chest", id = string, amount = number }
---@param def table
---@return table { icon, name, amount }
function RC.BuildEntry(def)
    local id     = def.id or ""
    local amount = def.amount or 1

    -- 优先用 Currency.GetImage（货币类型都有配置路径）
    local icon = Currency.GetImage(id)
    local name = ""

    if def.type == "currency" then
        local cd = Config.CURRENCY[id]
        name = cd and cd.name or id

    elseif def.type == "item" then
        if def.displayName then
            name = def.displayName
            icon = def.displayIcon or icon or "📦"
        else
            local ok, InventoryData = pcall(require, "Game.InventoryData")
            if ok then
                local item = InventoryData.ITEM_DEFS and InventoryData.ITEM_DEFS[id]
                name = item and item.name or id
            else
                name = id
            end
            if not icon then icon = "📦" end
        end

    elseif def.type == "chest" then
        local ok, ChestData = pcall(require, "Game.ChestData")
        if ok then
            local cd2 = ChestData.GetChestDef(id)
            if cd2 then
                name = cd2.name or "宝箱"
                icon = cd2.image or cd2.emoji or "📦"
            else
                name = "宝箱"
                icon = "📦"
            end
        else
            name = "宝箱"
            icon = "📦"
        end

    elseif def.type == "fragment" then
        local heroName = id
        for _, td in ipairs(Config.TOWER_TYPES) do
            if td.id == id then heroName = td.name; break end
        end
        name = heroName .. "碎片"
        if not icon then icon = "image/icon_fragment.png" end

    elseif def.type == "costume" then
        local ok2, CD = pcall(require, "Game.CostumeData")
        if ok2 and CD.SLOTS then
            for _, slot in ipairs(CD.SLOTS) do
                for _, cDef in ipairs(slot.costumes or {}) do
                    if cDef.id == id then
                        name = cDef.name or id
                        icon = cDef.preview or icon
                        break
                    end
                end
                if name ~= "" then break end
            end
        end
        if name == "" then name = id or "时装" end

    elseif def.type == "universal_shard" then
        name = (id or "?") .. "万能碎片"

    elseif def.type == "relic_shard" then
        -- 遗物碎片：id 是 relicId，需查 RelicData 获取名称
        local ok3, RelicData = pcall(require, "Game.RelicData")
        if ok3 and RelicData.RELIC_DEFS then
            local rd = RelicData.RELIC_DEFS[id]
            name = rd and (rd.name .. "碎片") or (id .. "碎片")
            icon = rd and rd.icon or icon
        else
            name = (id or "?") .. "碎片"
        end
        if not icon then icon = "image/icon_fragment.png" end

    elseif def.type == "rune" then
        -- 符文：id 是 seriesId，需查 Config_Runes 获取系列信息
        local ok4, RuneConfig = pcall(require, "Game.Config_Runes")
        if ok4 and RuneConfig.SERIES_MAP then
            local series = RuneConfig.SERIES_MAP[id]
            if series then
                name = series.name .. "符文"
                icon = series.icon or icon
            else
                name = (id or "?") .. "符文"
            end
        else
            name = (id or "?") .. "符文"
        end

    elseif def.type == "synth_result" then
        -- 合成结果（遗物自动合成产出）
        name = def.displayName or ("合成: " .. (id or "?"))
        icon = def.displayIcon or icon
        if def.borderColor then
            -- 将 borderColor 透传到展示格式
            return { icon = icon, name = name, amount = amount, borderColor = def.borderColor }
        end

    else
        name = id or ""
    end

    return { icon = icon, name = name, amount = amount }
end

--- 批量转换奖励定义列表
---@param defs table[]
---@return table[]
function RC.BuildList(defs)
    local result = {}
    for _, def in ipairs(defs or {}) do
        result[#result + 1] = RC.BuildEntry(def)
    end
    return result
end

--- 将相同 type+id 的奖励合并（叠加 amount），保持首次出现顺序
---@param defs table[]
---@return table[]
local function AggregateDefs(defs)
    local order = {}
    local map = {}
    for _, def in ipairs(defs or {}) do
        local key = (def.type or "") .. ":" .. (def.id or "")
        if map[key] then
            map[key].amount = (map[key].amount or 1) + (def.amount or 1)
        else
            local merged = { type = def.type, id = def.id, amount = def.amount or 1 }
            map[key] = merged
            order[#order + 1] = merged
        end
    end
    return order
end

--- 从货币 ID + 数量构建展示条目
---@param currencyId string
---@param amount number
---@return table
function RC.BuildCurrency(currencyId, amount)
    return RC.BuildEntry({ type = "currency", id = currencyId, amount = amount })
end

-- ============================================================================
-- 统一展示接口
-- ============================================================================

--- 展示奖励弹窗（有奖励用 RewardDisplay，无奖励直接回调）
---@param UI any           urhox-libs/UI 引用
---@param pageRoot any     父容器节点（供 RewardDisplay 挂载弹窗）
---@param rewards table[]  展示格式列表 { { icon, name, amount }, ... }
---@param title string     弹窗标题
---@param onClose function 关闭后的回调（通常是 Refresh）
function RC.Show(UI, pageRoot, rewards, title, onClose)
    if rewards and #rewards > 0 then
        RewardDisplay.Show(UI, pageRoot, {
            title   = title or "获得奖励",
            rewards = rewards,
            onClose = onClose,
        })
    else
        if onClose then onClose() end
    end
end

--- 快捷：展示单个货币奖励
---@param UI any
---@param pageRoot any
---@param currencyId string
---@param amount number
---@param title string
---@param onClose function
function RC.ShowCurrency(UI, pageRoot, currencyId, amount, title, onClose)
    local entry = RC.BuildCurrency(currencyId, amount)
    RC.Show(UI, pageRoot, { entry }, title, onClose)
end

--- 快捷：从奖励定义列表展示
---@param UI any
---@param pageRoot any
---@param defs table[]  { { type, id, amount }, ... } 格式
---@param title string
---@param onClose function
function RC.ShowFromDefs(UI, pageRoot, defs, title, onClose)
    local rewards = RC.BuildList(AggregateDefs(defs))
    RC.Show(UI, pageRoot, rewards, title, onClose)
end

return RC
