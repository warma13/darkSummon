-- ============================================================================
-- yang/Config.lua  ·  关卡配置与常量
-- ============================================================================

local M = {}

-- ============================================================================
-- ★ 游戏配置总表 ── 所有可调参数集中于此，其余代码请勿改动
-- ============================================================================
local CONFIG = {

    -- ── 槽位 ─────────────────────────────────────────────────────────────────
    -- 底部槽位的最大容量，填满即判负。推荐 7，不建议超过 9。
    slotMax = 7,

    -- ── 道具默认次数 ──────────────────────────────────────────────────────────
    -- 默认 0 次，需看广告获取。
    shuffleUses = 0,    -- 打乱：重新随机所有未移除牌的图案
    undoUses    = 0,    -- 撤回：将最近一张入槽的牌退回原位
    moveOutUses = 0,    -- 移出：将槽位前三张暂存到上方区域

    -- ── 牌面图案 ──────────────────────────────────────────────────────────────
    -- img  →  assets/image/<img>.png（填文件名，不含扩展名）
    -- 替换图片：把对应 PNG 放入 assets/image/，修改 img 字段即可。
    -- 新增图案：在末尾追加一行 { img = "your_image" }。
    -- 删减图案：直接删除对应行（注意 kindCount 不能超过剩余总数）。
    kinds = {
        { img = "card_frost_sword"    },  -- 1  凛冬之剑
        { img = "card_nature_staff"   },  -- 2  自然法杖
        { img = "card_shadow_bow"     },  -- 3  暗影弓
        { img = "card_iron_shield"    },  -- 4  铁盾
        { img = "card_dark_helmet"    },  -- 5  暗金头盔
        { img = "card_blood_potion"   },  -- 6  血红药水
        { img = "card_mana_bottle"    },  -- 7  蓝色魔瓶
        { img = "card_gold_coin"      },  -- 8  金币
        { img = "card_shadow_essence" },  -- 9  暗影精粹
        { img = "card_treasure_chest" },  -- 10 宝箱
        { img = "card_mystery_gift"   },  -- 11 神秘礼包
        { img = "card_crown"          },  -- 12 皇冠
        { img = "card_dark_crystal"   },  -- 13 暗黑水晶
        { img = "card_shadow_dagger"  },  -- 14 暗影匕首
        { img = "card_holy_book"      },  -- 15 圣光之书
        { img = "card_flame_ring"     },  -- 16 火焰戒指
        { img = "card_poison_vial"    },  -- 17 毒液瓶
        { img = "card_wing_cloak"     },  -- 18 羽翼披风
        { img = "card_skull_key"      },  -- 19 骷髅钥匙
        { img = "card_moon_necklace"  },  -- 20 月光项链
        { img = "card_dragon_amulet"  },  -- 21 龙鳞护符
    },

    -- ── 关卡列表 ──────────────────────────────────────────────────────────────
    -- 每个条目对应一关，顺序即关卡顺序。
    -- 增加一行 = 多一关；删除一行 = 少一关。
    --
    -- 【必填】
    --   totalCards   本关牌总数，必须是 3 的倍数。
    --                ≤ 30  → 纯叠层小关（无侧边牌堆，适合入门关）
    --                > 30  → 自动生成两个侧边牌堆，各 12 张
    --
    -- 【选填，不填时自动推算】
    --   kindCount    本关使用的图案种数（范围 1 ~ #kinds，必须 ≤ kinds 条目数）
    --                不填时按 totalCards 自动计算：
    --                  ≤ 30  → 3 种
    --                  ≤ 90  → 5 种
    --                  ≤ 180 → 7 种
    --                  ≤ 300 → 10 种
    --                  > 300 → 13 种（最多用完 kinds 表）
    --
    --   shuffleUses  本关打乱道具次数（不填则用上方全局默认值）
    --   undoUses     本关撤回道具次数（不填则用上方全局默认值）
    --   moveOutUses  本关移出道具次数（不填则用上方全局默认值）
    --
    -- 示例（第3关手动限制图案种数、道具次数）：
    --   { totalCards = 240, kindCount = 6, shuffleUses = 1, undoUses = 2 },
    levels = {
        { totalCards = 18                   },  -- 第1关  入门
        { totalCards = 150,  kindCount = 10 },  -- 第2关
        { totalCards = 240,  kindCount = 10 },  -- 第3关
        { totalCards = 480,  kindCount = 13 },  -- 第4关
        { totalCards = 900,  kindCount = 15 },  -- 第5关
        { totalCards = 1500, kindCount = 21 },  -- 第6关
        { totalCards = 2100, kindCount = 25 },  -- 第7关
        { totalCards = 2700, kindCount = 30 },  -- 第8关
        { totalCards = 3600, kindCount = 35 },  -- 第9关
        { totalCards = 4500, kindCount = 40 },  -- 第10关
    },
}
-- ============================================================================
-- ★ 配置总表结束，以下为引擎内部逻辑，通常无需改动
-- ============================================================================

-- ── 导出全局常量 ──────────────────────────────────────────────────────────────
M.SLOT_MAX   = CONFIG.slotMax
M.KIND_CFG   = CONFIG.kinds
M.ANIM_SPLIT = 0.35  -- 动画前35%原地放大，后65%飞向目标

-- 全局道具默认值（Board.lua 通过 cfg.shuffleUses 等读取）
M.DEFAULT_SHUFFLE_USES  = CONFIG.shuffleUses
M.DEFAULT_UNDO_USES     = CONFIG.undoUses
M.DEFAULT_MOVE_OUT_USES = CONFIG.moveOutUses

-- ── 羊了个羊固定网格常量（42×42 牌面，21px 半格错位）────────────────────────
M.YANG_FACE = 42
M.YANG_HALF = 21
M.YANG_X_A = {  0,  42,  84, 126, 168, 210, 252 }
M.YANG_Y_A = {  0,  42,  84, 126, 168, 210, 252 }
M.YANG_X_B = { 21,  63, 105, 147, 189, 231, 273 }
M.YANG_Y_B = { 21,  63, 105, 147, 189, 231, 273 }

-- ── 关卡生成器（内部函数）────────────────────────────────────────────────────

local function autoKindCount(total)
    if total <= 30  then return 3  end
    if total <= 90  then return 5  end
    if total <= 180 then return 7  end
    if total <= 300 then return 10 end
    if total <= 500 then return 13 end
    if total <= 1000 then return 15 end
    return 21
end

local function genDescendLayers(totalA)
    local nL     = math.max(3, math.min(5, math.ceil(totalA / 6)))
    local sumR   = nL * (nL + 1) / 2
    local layers = {}
    local assigned = 0
    for i = 1, nL do
        local ratio = nL + 1 - i
        local n = math.max(3, math.floor(totalA * ratio / sumR / 3) * 3)
        layers[i] = n
        assigned  = assigned + n
    end
    layers[1] = math.max(3, layers[1] + (totalA - assigned))
    return layers
end

local function genSpindleLayers(totalA)
    local nL = math.max(4, math.min(20, math.ceil(totalA / 18)))
    if nL % 2 ~= 0 then nL = nL + 1 end
    local weights = {}
    local sumW    = 0
    for i = 1, nL do
        local w   = 0.2 + 0.8 * math.sin((i - 0.5) / nL * math.pi)
        weights[i] = w
        sumW       = sumW + w
    end
    local layers   = {}
    local assigned = 0
    for i = 1, nL do
        local n3 = math.max(1, math.floor(weights[i] / sumW * totalA / 3))
        layers[i] = n3 * 3
        assigned  = assigned + layers[i]
    end
    local peakIdx = math.ceil(nL / 2)
    layers[peakIdx] = math.max(3, layers[peakIdx] + (totalA - assigned))
    return layers
end

local function buildLevel(idx, d)
    local total     = d.totalCards
    local isSmall   = (total <= 30)
    local pileCards = isSmall and 0 or 12
    local totalA    = total - pileCards * 2
    local layers    = isSmall and genDescendLayers(totalA) or genSpindleLayers(totalA)
    -- kindCount：优先用手动配置，否则自动推算，最终不超过 kinds 表总数
    local kindCount = math.min(
        d.kindCount or autoKindCount(total),
        #CONFIG.kinds
    )
    local numCN = { "一","二","三","四","五","六","七","八","九","十" }
    local name  = "第" .. (numCN[idx] or tostring(idx)) .. "关"
    return {
        name          = name,
        kindCount     = kindCount,
        cardsPerLayer = layers,
        useB          = not isSmall,
        pileCards     = pileCards,
        seed          = isSmall and 42 or nil,
        totalCards    = total,
        -- 道具次数：优先用本关配置，否则用全局默认
        shuffleUses   = d.shuffleUses  or CONFIG.shuffleUses,
        undoUses      = d.undoUses     or CONFIG.undoUses,
        moveOutUses   = d.moveOutUses  or CONFIG.moveOutUses,
        -- 视觉参数（内部固定，通常无需修改）
        cardW=42, cardH=50, gridX=21, gridY=21,
        layerOff   = isSmall and 4 or 0,
        cardShadow = isSmall and 6 or 8,
        maxCols    = isSmall and 5 or 7,
        maxRows    = isSmall and 5 or 7,
    }
end

M.LEVELS = {}
for i, d in ipairs(CONFIG.levels) do
    M.LEVELS[i] = buildLevel(i, d)
end

return M
