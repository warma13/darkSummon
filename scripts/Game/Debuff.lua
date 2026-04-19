--- Debuff.lua — 统一负面效果系统
---
--- 职责：
---   1. 所有 Apply 前自动检查免疫，调用方无需知道"谁赋予了免疫"
---   2. 任何模块通过 GrantImmunity / RevokeImmunity 声明免疫（解耦）
---   3. Clear 统一清除关联字段
---
--- 覆盖范围
---   ┌─ 施加给塔（友方）
---   │   silence     silenceTimer           death_silence / BOSS 禁锢
---   │   shackle     shackled               WorldBoss 技能
---   └─ 施加给敌人
---       slow        slowTimer              减速（Enemy.ApplySlow）
---       chill       chillTimer             寒意（Enemy.ApplyChill）
---       dot         dotTimer               持续伤害（Enemy.ApplyDOT）
---       stun        stunTimer              眩晕（Debuff.Apply）
---       frozen      frozenTimer + frozen   冰冻（Debuff.Apply）
---       amp_damage  ampDamageTimer + val   易伤标记（Debuff.Apply）

local Debuff = {}

-- ============================================================================
-- 负面效果定义表
--   timerField : 计时器字段名（由各自的 tick 循环递减，到0消失）
--   flagField  : 布尔状态字段名
--   dataField  : 附带数值字段名（Apply 时写入 params.value，Clear 时置 nil）
-- ============================================================================
local DEFS = {
    -- ──── 施加给塔（友方）
    silence    = { timerField = "silenceTimer" },
    shackle    = { flagField  = "shackled" },

    -- ──── 施加给敌人：有专用 Apply 函数的（Enemy.ApplySlow/DOT/Chill）
    --        Debuff 系统负责免疫注册 + IsImmune 查询
    --        Apply / Tick / 速度还原等复杂域逻辑保留在 Enemy.lua
    slow       = { timerField = "slowTimer" },
    chill      = { timerField = "chillTimer" },
    dot        = { timerField = "dotTimer" },

    -- ──── 施加给敌人：通过 Debuff.Apply 统一施加的
    stun       = { timerField = "stunTimer" },
    frozen     = { timerField = "frozenTimer",    flagField = "frozen" },
    amp_damage = { timerField = "ampDamageTimer", dataField = "ampDamage" },
    -- armor_break / armor_reduce_dot 保留直接字段写入（叠层/单次逻辑复杂）
}

-- ============================================================================
-- 内部：获取实体的免疫表（懒初始化）
-- ============================================================================
local function imm(entity)
    if not entity._debuffImmune then entity._debuffImmune = {} end
    return entity._debuffImmune
end

-- ============================================================================
-- 免疫管理
-- ============================================================================

--- 授予免疫，同时立即清除实体身上已有的同类 debuff
---@param entity table
---@param id string
function Debuff.GrantImmunity(entity, id)
    imm(entity)[id] = true
    Debuff.Clear(entity, id)
end

--- 撤销免疫
---@param entity table
---@param id string
function Debuff.RevokeImmunity(entity, id)
    local t = rawget(entity, "_debuffImmune")
    if t then t[id] = nil end
end

--- 查询是否免疫
---@param entity table
---@param id string
---@return boolean
function Debuff.IsImmune(entity, id)
    local t = rawget(entity, "_debuffImmune")
    return t ~= nil and t[id] == true
end

--- 根据敌人 typeDef 批量注册静态免疫（Enemy.Create 时调用）
---@param entity table
---@param typeDef table
function Debuff.RegisterEnemyImmunities(entity, typeDef)
    -- immune_cc：免疫所有控制类 debuff
    if typeDef.passive == "immune_cc" then
        Debuff.GrantImmunity(entity, "slow")
        Debuff.GrantImmunity(entity, "chill")
        Debuff.GrantImmunity(entity, "dot")
        Debuff.GrantImmunity(entity, "stun")
        Debuff.GrantImmunity(entity, "frozen")
    end
    -- dotImmune：仅免疫 DOT
    if typeDef.dotImmune then
        Debuff.GrantImmunity(entity, "dot")
    end
end

--- void_aura 词缀免疫（ApplyAffixes 时调用）
---@param entity table
function Debuff.GrantVoidAuraImmunity(entity)
    Debuff.GrantImmunity(entity, "slow")
    Debuff.GrantImmunity(entity, "chill")
    Debuff.GrantImmunity(entity, "dot")
    Debuff.GrantImmunity(entity, "stun")
    Debuff.GrantImmunity(entity, "frozen")
end

-- ============================================================================
-- 施加 / 清除
-- ============================================================================

--- 尝试施加负面效果（免疫则忽略，返回 false）
---@param entity table
---@param id string      debuff 类型
---@param params table?  { duration?: number, value?: any }
---@return boolean  true=施加成功  false=免疫或类型未知
function Debuff.Apply(entity, id, params)
    if Debuff.IsImmune(entity, id) then return false end
    local def = DEFS[id]
    if not def then
        print("[Debuff] 未知类型: " .. tostring(id))
        return false
    end
    params = params or {}
    if def.timerField then
        local dur = params.duration or 1.0
        entity[def.timerField] = math.max(entity[def.timerField] or 0, dur)
    end
    if def.flagField then
        entity[def.flagField] = true
    end
    if def.dataField and params.value ~= nil then
        entity[def.dataField] = params.value
    end
    return true
end

--- 强制清除负面效果
---@param entity table
---@param id string
function Debuff.Clear(entity, id)
    local def = DEFS[id]
    if not def then return end
    if def.timerField then entity[def.timerField] = 0     end
    if def.flagField  then entity[def.flagField]  = false end
    if def.dataField  then entity[def.dataField]  = nil   end
end

--- 查询实体当前是否受到某 debuff 影响
---@param entity table
---@param id string
---@return boolean
function Debuff.Has(entity, id)
    local def = DEFS[id]
    if not def then return false end
    if def.timerField and (entity[def.timerField] or 0) > 0 then return true end
    if def.flagField  and entity[def.flagField]             then return true end
    return false
end

return Debuff
