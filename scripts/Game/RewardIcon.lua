-- Game/RewardIcon.lua
-- 可复用奖励图标组件：货币图片铺满 + 右下角数量徽章 + 点击弹出浮窗
--
-- 两种用法：
-- 1. 独立图标（背包、特权页等）：固定尺寸，自带背景/边框
--    RewardIcon.Create(UI, 48, "shadow_essence", 100)
--
-- 2. 格子内嵌（签到、积天等）：铺满父容器，无自有背景
--    RewardIcon.Create(UI, "100%", "shadow_essence", 100, {
--        flexGrow = 1,           -- 填充剩余空间
--        backgroundColor = ...,  -- 可选：覆盖背景色
--    })

local Config       = require("Game.Config")
local Currency     = require("Game.Currency")
local FormatNumber = require("Game.FormatUtil").FormatNumber
local Tooltip = require("Game.Tooltip")

local RewardIcon = {}

-- 物品详细描述（浮窗自动查找）
local REWARD_DESC = {
    shadow_essence = "珍贵精华，可在商店兑换稀有碎片与材料",
    devour_stone   = "噬魂之石，英雄进阶突破的必需材料",
    forge_iron     = "锻造原料，用于装备强化升级",
    ur_shard_box   = "开启后可任选一个UR英雄碎片",
    void_pact      = "虚空契约，用于招募强力英雄",
    nether_crystal = "冥界结晶，英雄升级的核心资源",
    pale_jade      = "淬炼消耗材料，用于重随装备淬炼词条",
    rainbow_jade   = "淬炼稀有材料，锁定已有淬炼词条使其不被洗练覆盖",
    bronze_chest   = "青铜宝箱，开启可获得随机奖励",
    shadow_orb     = "幽影珠，可在神秘商店兑换物品",
    -- 福袋 & 礼包
    shadow_essence_bag  = "打开可获得128~1288暗影精粹（600以上概率仅8%）",
    nether_crystal_pack = "使用获得当前挂机收益的4小时冥晶",
    devour_stone_bag    = "打开可获得50~500噬魂石",
    forge_iron_bag      = "打开可获得30~300锻魂铁",
    -- 道具
    dungeon_ticket            = "每日免费次数用完后，消耗门票可额外挑战资源副本1次",
    boss_ticket               = "消耗后可额外挑战深渊主宰1次",
    recruit_ticket_select_box = "使用后可选择当前开放的招募池，获得对应招募券",
    -- 碎片箱
    random_ur_shard_box   = "打开随机获得1个UR英雄碎片",
    r_shard_random_box    = "打开随机获得1个R英雄碎片",
    sr_shard_random_box   = "打开随机获得1个SR英雄碎片",
    ssr_shard_random_box  = "打开随机获得1个SSR英雄碎片",
    r_shard_select_box    = "打开可选择1个R英雄获得碎片",
    sr_shard_select_box   = "打开可选择1个SR英雄获得碎片",
    ssr_shard_select_box  = "打开可选择1个SSR英雄获得碎片",
}

--- 创建奖励图标
---@param UI any       UI 库引用
---@param size any     图标尺寸: 数字(固定px) 或 "100%"(铺满)
---@param currencyId string  货币 ID
---@param amount number  数量
---@param opts? table  可选项
---   muted: bool         已领取/置灰
---   label: string       浮窗物品名（覆盖默认名称，不影响数量显示）
---   desc: string        浮窗描述（覆盖自动查找的描述）
---   flexGrow: number    flex 填充（用于格子内嵌模式）
---   backgroundColor: table  覆盖背景色（nil 则用默认）
---@return any widget
function RewardIcon.Create(UI, size, currencyId, amount, opts)
    opts = opts or {}
    local cdef = Config.CURRENCY[currencyId]
    -- fallback: 如果不在 CURRENCY 中，尝试从 InventoryData.ITEM_DEFS 查找
    if not cdef then
        local ok, InvData = pcall(require, "Game.InventoryData")
        if ok and InvData.ITEM_DEFS then
            local itemDef = InvData.ITEM_DEFS[currencyId]
            if itemDef then
                -- 构造兼容的 cdef 结构，用 icon 字段作为二次查找 key
                local iconKey = itemDef.icon or currencyId
                cdef = Config.CURRENCY[iconKey]  -- icon 可能指向 CURRENCY 中的 emoji/image
                if not cdef then
                    -- 构造临时 cdef
                    cdef = { name = itemDef.name, image = itemDef.image }
                else
                    -- 用道具自身名称覆盖
                    cdef = { name = itemDef.name, image = cdef.image, color = cdef.color }
                end
            end
        end
    end
    local img = opts.image or (cdef and cdef.image)
    local muted = opts.muted
    local displayName = opts.label or (cdef and cdef.name) or currencyId
    local desc = opts.desc or REWARD_DESC[currencyId] or ""
    local flexGrow = opts.flexGrow

    -- 背景色：flexGrow 模式不要背景，独立模式可自定义或用默认
    local bg = flexGrow and nil
        or opts.backgroundColor
        or { 50, 40, 70, 200 }

    -- flexGrow 模式下不加额外边框（由父格子提供）
    local borderW = flexGrow and 0 or 1
    local borderC = flexGrow and nil
        or (muted and { 60, 50, 80, 100 } or { 100, 80, 140, 150 })
    local borderR = flexGrow and 0 or 6

    -- 图标内容子项（图片 + 徽章），两种模式共用
    local onClickFn = (not opts.noTooltip) and function(self)
        Tooltip.Show({
            title = displayName .. " ×" .. FormatNumber(amount),
            desc = desc,
            anchor = self,
        })
    end or nil

    local iconChildren = {
        -- 图片铺满图标区域
        img and UI.Panel {
            width = "100%", height = "100%",
            backgroundImage = img,
            backgroundFit = "cover",
            borderRadius = flexGrow and 0 or 5,
        } or UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center",
            alignItems = "center",
            children = { Currency.IconWidget(UI, currencyId, type(size) == "number" and size * 0.7 or 28) },
        },
        -- 右下角数量徽章
        UI.Panel {
            position = "absolute",
            right = 0, bottom = 0,
            minWidth = "max-content",
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            backgroundColor = { 0, 0, 0, 200 },
            borderRadius = 4,
            children = {
                UI.Label {
                    text = "×" .. FormatNumber(amount),
                    fontSize = 10,
                    fontColor = muted and { 150, 140, 170, 180 } or { 255, 255, 255 },
                    fontWeight = "bold",
                    maxWidth = 200,
                },
            },
        },
    }

    if flexGrow then
        -- flexGrow 模式（格子内嵌）：
        -- 外层：填充剩余空间，居中对齐
        -- 内层：正方形图标（height=100% + aspectRatio=1），图片+徽章
        return UI.Panel {
            width = "100%",
            flexGrow = flexGrow,
            justifyContent = "center",
            alignItems = "center",
            overflow = "visible",
            backgroundColor = opts.backgroundColor,
            borderRadius = 0,
            children = {
                UI.Panel {
                    height = "90%",
                    aspectRatio = 1,
                    position = "relative",
                    overflow = "visible",
                    justifyContent = "center",
                    alignItems = "center",
                    onClick = onClickFn,
                    children = iconChildren,
                },
            },
        }
    else
        -- 固定尺寸模式（独立图标）
        return UI.Panel {
            width = size,
            height = size,
            position = "relative",
            overflow = "visible",
            backgroundColor = bg,
            borderRadius = borderR,
            borderWidth = borderW,
            borderColor = borderC,
            justifyContent = "center",
            alignItems = "center",
            onClick = onClickFn,
            children = iconChildren,
        }
    end
end

return RewardIcon
