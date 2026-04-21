-- Game/DivineBlessData.lua
-- 神裔降临系统：每日随机 3 位初裔神供玩家自选加成，周末磐古自动降临

local HeroData     = require("Game.HeroData")
local SaveRegistry = require("Game.SaveRegistry")

local DB = {}

-- ============================================================================
-- 12 初裔神配置
-- ============================================================================

---@class DivineEntry
---@field id string
---@field name string       -- 全名（如"土嗣·磐古"）
---@field title string      -- 称号短名
---@field domain string     -- 神格领域
---@field color number[]    -- 主题色 RGB
---@field buffType string   -- 加成类型标识
---@field buffValue number  -- 加成数值
---@field desc string       -- 加成描述
---@field lore string       -- 世界观短文

DB.DIVINE_LIST = {
    {
        id = "aurion", name = "奥瑞恩", title = "光裔·长子",
        domain = "光系能量·秩序", color = { 255, 230, 130 },
        buffType = "atk_pct", buffValue = 0.10,
        desc = "全英雄攻击力 +10%",
        lore = "初裔长子奥瑞恩，光系能量与秩序的化身。其降临之时，所有召唤师的英雄将获得攻击之力的加持。",
    },
    {
        id = "xuanyuan", name = "暗嗣·玄渊", title = "暗影裔",
        domain = "暗影能量·深渊", color = { 120, 60, 180 },
        buffType = "darksoul_multi", buffValue = 1.5,
        desc = "暗魂掉落 ×1.5",
        lore = "暗嗣玄渊，司掌死亡与轮回。暗影界的深渊能量在其降临时涌动，使暗魂的汲取效率大幅提升。",
    },
    {
        id = "cangyan", name = "灵嗣·苍嫣", title = "灵魂裔",
        domain = "灵魂能量·共鸣", color = { 180, 140, 255 },
        buffType = "trial_ticket", buffValue = 1,
        desc = "试练塔挑战次数 +1",
        lore = "灵嗣苍嫣，灵魂契约与感知的守护者。其降临会在灵魂试炼之塔开启额外的通道，供召唤师磨砺意志。",
    },
    {
        id = "pangu", name = "土嗣·磐古", title = "大地裔",
        domain = "大地能量·积累", color = { 200, 160, 80 },
        buffType = "crystal_multi", buffValue = 1.5,
        desc = "冥晶收益 ×1.5",
        lore = "十二初裔之一，土嗣·磐古，司掌大地能量与矿脉积聚之道。每逢周末，磐古降临暗界，令冥晶汲取之速大幅提升。",
    },
    {
        id = "linghua", name = "风嗣·翎华", title = "自然裔",
        domain = "自然能量·流动", color = { 100, 220, 140 },
        buffType = "spd_pct", buffValue = 0.10,
        desc = "全英雄攻速 +10%",
        lore = "风嗣翎华，自然能量与流动的化身。风之加护令英雄出手如疾风，攻击速度显著提升。",
    },
    {
        id = "jinwang", name = "火嗣·烬王", title = "创造裔",
        domain = "创造能量·燃烧", color = { 255, 100, 50 },
        buffType = "crit_pct", buffValue = 0.15,
        desc = "全英雄暴击率 +15%",
        lore = "火嗣烬王，毁灭与重生之火的主宰。烈焰灌注英雄之魂，使每一击都有更高概率爆发致命伤害。",
    },
    {
        id = "shuangming", name = "冰嗣·霜鸣", title = "时间裔",
        domain = "时间能量·凝固", color = { 180, 220, 255 },
        buffType = "idle_extra", buffValue = 3600,
        desc = "挂机时间上限 +1h",
        lore = "冰嗣霜鸣，时间凝固之力的守护者。其降临使时间的流逝减缓，挂机收益的积累上限得以延长。",
    },
    {
        id = "chiyuan", name = "血嗣·赤渊", title = "生命裔",
        domain = "生命能量·流动", color = { 220, 60, 80 },
        buffType = "stone_multi", buffValue = 1.5,
        desc = "噬魂石掉落 ×1.5",
        lore = "血嗣赤渊，生命能量与情感的化身。鲜血的脉动使噬魂石的凝聚效率大幅提升。",
    },
    {
        id = "huanyuan", name = "梦嗣·幻渊", title = "意识裔",
        domain = "意识能量·虚实", color = { 160, 100, 220 },
        buffType = "chest_multi", buffValue = 2.0,
        desc = "主线和挂机宝箱掉落 ×2",
        lore = "梦嗣幻渊，虚实之间的行者。幻境之力扭曲了命运的编织，使宝箱在战斗中更频繁地出现。",
    },
    {
        id = "mingwu", name = "骨嗣·冥巫", title = "蜕变裔",
        domain = "肉体能量·蜕变", color = { 200, 200, 180 },
        buffType = "iron_multi", buffValue = 1.5,
        desc = "锻魂铁掉落 ×1.5",
        lore = "骨嗣冥巫，肉体蜕变与转化的主宰。骨与铁的共鸣使锻魂铁的产出大幅增加。",
    },
    {
        id = "xuwu", name = "空嗣·虚无", title = "虚空裔",
        domain = "虚空能量·消弭", color = { 140, 160, 200 },
        buffType = "boss_attempt", buffValue = 1,
        desc = "Boss挑战次数 +1",
        lore = "空嗣虚无，位面裂隙与消弭之力的化身。虚空的裂缝为召唤师打开了额外挑战世界Boss的通道。",
    },
    {
        id = "chuqi", name = "源嗣·初契", title = "源力裔",
        domain = "源力能量·完整", color = { 255, 215, 180 },
        buffType = "dungeon_attempt", buffValue = 1,
        desc = "资源副本次数 +1",
        lore = "源嗣初契，万物本源与平衡的守护者，最接近神母薇嫣的存在。其降临会令资源副本开启额外挑战次数。",
    },
}

-- 快查表：id → entry
DB._idMap = {}
for _, d in ipairs(DB.DIVINE_LIST) do
    DB._idMap[d.id] = d
end

-- 工作日可选池（排除磐古，磐古仅周末自动）
DB._weekdayPool = {}
for _, d in ipairs(DB.DIVINE_LIST) do
    if d.id ~= "pangu" then
        DB._weekdayPool[#DB._weekdayPool + 1] = d
    end
end

-- ============================================================================
-- 数据访问
-- ============================================================================

---@return table
function DB.EnsureData()
    if not HeroData.divineBlessData then
        HeroData.divineBlessData = {
            chosenDate = "",
            chosenId   = "",
        }
    end
    return HeroData.divineBlessData
end

--- 今天的日期 key
local TodayStr = require("Game.DateUtil").TodayStr
local TodayKey = require("Game.DateUtil").TodayKey

--- 是否为周末
---@return boolean
function DB.IsWeekend()
    local w = os.date("*t").wday
    return w == 1 or w == 7
end

-- ============================================================================
-- 每日随机：从 11 位工作日神裔中选 3 位（日期种子，全服统一）
-- ============================================================================

--- 简单 LCG 随机数生成器（与 math.random 隔离，避免污染全局种子）
local function lcgRandom(seed)
    local s = seed
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        if n then
            return (s % n) + 1
        end
        return s
    end
end

--- 获取今日可选的 3 位神裔
---@return DivineEntry[]
function DB.GetTodayOptions()
    -- 周末：磐古自动降临，无需选择
    if DB.IsWeekend() then
        return { DB._idMap["pangu"] }
    end

    -- 工作日：从 11 位中选 3 位
    local seed = tonumber(TodayKey())
    local rng = lcgRandom(seed)

    local pool = {}
    for i, d in ipairs(DB._weekdayPool) do
        pool[i] = d
    end

    local result = {}
    for i = 1, 3 do
        local idx = rng(#pool)
        result[i] = pool[idx]
        table.remove(pool, idx)
    end

    return result
end

-- ============================================================================
-- 选择 & 查询
-- ============================================================================

--- 玩家选择今日神裔（1~3 号）
---@param index number 1-based
---@return boolean ok, string msg
function DB.Choose(index)
    if DB.IsWeekend() then
        return false, "周末磐古自动降临，无需选择"
    end

    local options = DB.GetTodayOptions()
    if index < 1 or index > #options then
        return false, "无效选项"
    end

    local data = DB.EnsureData()
    local today = TodayStr()

    if data.chosenDate == today and data.chosenId ~= "" then
        return false, "今日已选择过神裔"
    end

    data.chosenDate = today
    data.chosenId = options[index].id

    local SlotSave = require("Game.SlotSaveSystem")
    SlotSave.MarkDirty()

    return true, options[index].name .. " 降临！" .. options[index].desc
end

--- 获取当前生效的加成（周末返回磐古，工作日返回玩家选择）
---@return DivineEntry|nil
function DB.GetActiveBlessing()
    -- 周末自动磐古
    if DB.IsWeekend() then
        return DB._idMap["pangu"]
    end

    -- 工作日：检查今日是否已选
    local data = DB.EnsureData()
    if data.chosenDate ~= TodayStr() or data.chosenId == "" then
        return nil
    end

    return DB._idMap[data.chosenId]
end

--- 今日是否已选择
---@return boolean
function DB.HasChosen()
    if DB.IsWeekend() then return true end
    local data = DB.EnsureData()
    return data.chosenDate == TodayStr() and data.chosenId ~= ""
end

--- 查询指定 buffType 的加成值（供各系统调用）
---@param buffType string
---@return number  -- 倍率类返回 1.5 等，加算类返回 0.10 等，次数类返回 1，无加成返回 0 或 1.0
function DB.GetBuffValue(buffType)
    local active = DB.GetActiveBlessing()
    if not active or active.buffType ~= buffType then
        -- 倍率类默认 1.0，次数/加算类默认 0
        if buffType == "crystal_multi" or buffType == "darksoul_multi"
           or buffType == "stone_multi" or buffType == "iron_multi"
           or buffType == "chest_multi" then
            return 1.0
        end
        return 0
    end
    return active.buffValue
end

-- ============================================================================
-- 存档
-- ============================================================================

SaveRegistry.Register("divineBlessData", {
    group = "meta_game",
    order = 80,
    serialize = function()
        return HeroData.divineBlessData
    end,
    deserialize = function(saved)
        HeroData.divineBlessData = saved or nil
    end,
})

return DB
