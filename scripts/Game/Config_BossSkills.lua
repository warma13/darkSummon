-- Game/Config_BossSkills.lua
-- Boss 技能统一注册表
-- 每个副本的 Boss 技能配置集中定义在此，供 BossSkillManager 查表调度

local Config_BossSkills = {}

-- ============================================================================
-- 通用技能定义 (供无专属技能的副本复用)
-- ============================================================================

--- 通用技能池：6 个可组合的通用技能
--- 每个技能格式: { id, name, color, desc, defaults }
Config_BossSkills.GENERIC_POOL = {
    -- 1. 暗影束缚 — 随机禁锢 N 个英雄，持续数秒不能攻击
    shackle = {
        id       = "shackle",
        name     = "暗影束缚",
        color    = { 120, 40, 180 },
        desc     = "禁锢随机英雄，使其无法攻击",
        defaults = {
            interval   = 15.0,   -- CD
            count      = 2,      -- 禁锢数量
            duration   = 3.0,    -- 持续时间
        },
    },
    -- 2. 灵魂吞噬 — 全体英雄攻击力降低 X%，持续数秒
    devour = {
        id       = "devour",
        name     = "灵魂吞噬",
        color    = { 60, 180, 80 },
        desc     = "削弱全体英雄攻击力",
        defaults = {
            interval      = 18.0,
            atkReduction  = 0.25,   -- 攻击力降低 25%
            duration      = 5.0,
        },
    },
    -- 3. 虚空脉冲 — 随机区域 AOE，命中英雄短暂眩晕（停止攻击 1 秒）
    pulse = {
        id       = "pulse",
        name     = "虚空脉冲",
        color    = { 40, 120, 220 },
        desc     = "随机区域脉冲，命中英雄短暂眩晕",
        defaults = {
            interval   = 12.0,
            radius     = 1,       -- 以格为单位的半径
            stunTime   = 1.0,     -- 眩晕持续
        },
    },
    -- 4. 黑暗庇护 — Boss 短时间获得护盾，减少受到的伤害
    shield = {
        id       = "shield",
        name     = "黑暗庇护",
        color    = { 200, 160, 40 },
        desc     = "Boss 获得临时护盾，减少伤害",
        defaults = {
            interval     = 20.0,
            duration     = 4.0,
            reduction    = 0.50,   -- 减伤 50%
        },
    },
    -- 5. 亡灵召唤 — 召唤 N 个小怪增援
    summon = {
        id       = "summon",
        name     = "亡灵召唤",
        color    = { 160, 60, 160 },
        desc     = "召唤亡灵增援",
        defaults = {
            interval   = 22.0,
            count      = 3,       -- 每次召唤数量
            hpMult     = 1.5,     -- 小怪 HP 倍率
        },
    },
    -- 6. 诅咒领域 — 全体英雄攻速降低 X%，持续数秒
    curse = {
        id       = "curse",
        name     = "诅咒领域",
        color    = { 180, 40, 60 },
        desc     = "降低全体英雄攻击速度",
        defaults = {
            interval      = 16.0,
            spdReduction  = 0.20,   -- 攻速降低 20%
            duration      = 4.0,
        },
    },
}

-- ============================================================================
-- 副本 → Boss 技能映射
-- ============================================================================
-- skillModule: 专属技能模块路径 (nil 则使用通用技能)
-- genericSkills: 使用通用技能池中的哪些技能 (仅 skillModule=nil 时生效)
-- scaleFn: 可选，根据副本难度/关卡动态调整技能参数
-- ============================================================================

Config_BossSkills.DUNGEON_MAP = {
    -- ========== 已有专属技能的副本 ==========
    world_boss = {
        skillModule  = "Game.WorldBossSkills",
        label        = "世界BOSS",
    },
    hatred_land = {
        skillModule  = "Game.HatredBossSkills",
        label        = "憎恨之地",
    },
    emerald_dungeon = {
        skillModule  = "Game.EmeraldBossSkills",
        label        = "翠影秘境",
    },
    garbage_boss = {
        skillModule  = "Game.GarbageBossSkills",
        label        = "垃圾BOSS",
    },

    -- ========== 无专属技能 → 使用通用技能 ==========
    trial_tower = {
        skillModule   = nil,
        label         = "试炼塔",
        genericSkills = { "shackle", "devour" },
        --- 根据层数缩放技能参数
        ---@param floor number 当前层数
        ---@return table overrides { [skillId] = { field=value, ... } }
        scaleFn = function(floor)
            local t = math.min(floor / 100, 1.0) -- 0~1 线性缩放因子
            return {
                shackle = {
                    interval = 15.0 - 3.0 * t,     -- 15s → 12s
                    count    = 2 + math.floor(t * 2), -- 2 → 4
                    duration = 3.0 + 1.0 * t,       -- 3s → 4s
                },
                devour = {
                    interval     = 18.0 - 4.0 * t,  -- 18s → 14s
                    atkReduction = 0.25 + 0.15 * t,  -- 25% → 40%
                    duration     = 5.0 + 2.0 * t,    -- 5s → 7s
                },
            }
        end,
    },
    resource_dungeon = {
        skillModule   = nil,
        label         = "资源副本",
        genericSkills = { "pulse", "shield" },
        ---@param diffLevel number 难度等级
        ---@return table overrides
        scaleFn = function(diffLevel)
            local t = math.min(diffLevel / 5, 1.0)
            return {
                pulse = {
                    interval = 12.0 - 2.0 * t,     -- 12s → 10s
                    radius   = 1 + math.floor(t),    -- 1 → 2
                    stunTime = 1.0 + 0.5 * t,       -- 1s → 1.5s
                },
                shield = {
                    interval  = 20.0 - 4.0 * t,    -- 20s → 16s
                    duration  = 4.0 + 2.0 * t,     -- 4s → 6s
                    reduction = 0.50 + 0.10 * t,   -- 50% → 60%
                },
            }
        end,
    },
    temper_trial = {
        skillModule   = nil,
        label         = "淬魂试炼",
        genericSkills = { "shackle", "shield", "curse" },
        ---@param diffLevel number 难度等级
        ---@return table overrides
        scaleFn = function(diffLevel)
            local t = math.min((tonumber(diffLevel) or 0) / 4, 1.0)
            return {
                shackle = {
                    interval = 15.0 - 3.0 * t,      -- 15s → 12s
                    count    = 2 + math.floor(t * 2), -- 2 → 4
                    duration = 3.0 + 1.5 * t,        -- 3s → 4.5s
                },
                shield = {
                    interval  = 20.0 - 5.0 * t,     -- 20s → 15s
                    duration  = 4.0 + 2.0 * t,      -- 4s → 6s
                    reduction = 0.50 + 0.15 * t,    -- 50% → 65%
                },
                curse = {
                    interval     = 16.0 - 4.0 * t,  -- 16s → 12s
                    spdReduction = 0.20 + 0.15 * t,  -- 20% → 35%
                    duration     = 4.0 + 2.0 * t,    -- 4s → 6s
                },
            }
        end,
    },
    abyss_rift = {
        skillModule   = nil,
        label         = "深渊裂隙",
        genericSkills = { "summon", "curse", "shackle" },
        ---@param difficultyId number 难度 ID
        ---@return table overrides
        scaleFn = function(difficultyId)
            local t = math.min((tonumber(difficultyId) or 1) / 5, 1.0)
            return {
                summon = {
                    interval = 22.0 - 4.0 * t,     -- 22s → 18s
                    count    = 3 + math.floor(t * 3), -- 3 → 6
                    hpMult   = 1.5 + 1.0 * t,       -- 1.5 → 2.5
                },
                curse = {
                    interval     = 16.0 - 3.0 * t,  -- 16s → 13s
                    spdReduction = 0.20 + 0.10 * t,  -- 20% → 30%
                    duration     = 4.0 + 2.0 * t,    -- 4s → 6s
                },
                shackle = {
                    interval = 15.0 - 3.0 * t,
                    count    = 1 + math.floor(t * 2),
                    duration = 2.5 + 1.0 * t,
                },
            }
        end,
    },
}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取副本的 Boss 技能配置
---@param dungeonMode string 副本模式标识 (如 "trial_tower")
---@return table|nil entry DUNGEON_MAP 中的配置条目
function Config_BossSkills.Get(dungeonMode)
    return Config_BossSkills.DUNGEON_MAP[dungeonMode]
end

--- 判断副本是否有专属技能模块
---@param dungeonMode string
---@return boolean
function Config_BossSkills.HasDedicatedModule(dungeonMode)
    local entry = Config_BossSkills.DUNGEON_MAP[dungeonMode]
    return entry ~= nil and entry.skillModule ~= nil
end

--- 构建通用技能的最终参数（合并默认值 + 缩放覆盖）
---@param dungeonMode string
---@param scaleParam number 传给 scaleFn 的难度参数
---@return table mechanics { [skillId] = { merged params } }
function Config_BossSkills.BuildGenericMechanics(dungeonMode, scaleParam)
    local entry = Config_BossSkills.DUNGEON_MAP[dungeonMode]
    if not entry or entry.skillModule then return {} end

    local pool = Config_BossSkills.GENERIC_POOL
    local mechanics = {}

    -- 从通用池取默认值
    for _, skillId in ipairs(entry.genericSkills or {}) do
        local def = pool[skillId]
        if def then
            local params = {}
            for k, v in pairs(def.defaults) do
                params[k] = v
            end
            params._id    = def.id
            params._name  = def.name
            params._color = def.color
            params._desc  = def.desc
            mechanics[skillId] = params
        end
    end

    -- 应用缩放覆盖
    if entry.scaleFn and scaleParam then
        local overrides = entry.scaleFn(scaleParam)
        if overrides then
            for skillId, ov in pairs(overrides) do
                if mechanics[skillId] then
                    for k, v in pairs(ov) do
                        mechanics[skillId][k] = v
                    end
                end
            end
        end
    end

    return mechanics
end

return Config_BossSkills
