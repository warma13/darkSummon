------------------------------------------------------------------------
-- WaveGenerator.lua  —— 副本通用波次生成工具
-- 提取各副本 GenerateWaveEnemies 的公共逻辑，消除重复代码。
-- 各副本仍然自己决定波次规则，只调用这里的工具函数。
------------------------------------------------------------------------
local Config = require("Game.Config")

local WG = {}

------------------------------------------------------------------------
--- 根据等效关卡号构建当前可用的敌人角色池
---@param stageNum number 等效关卡号（已 floor）
---@return string[] availRoles 角色 ID 列表
------------------------------------------------------------------------
function WG.BuildRolePool(stageNum)
    local globalWave = stageNum * Config.WAVES_PER_STAGE
    local availRoles = {}
    for _, roleId in ipairs(Config.ROLE_IDS) do
        local role = Config.ENEMY_ROLES[roleId]
        if role then
            local unlockWave = Config.ROLE_UNLOCK_WAVE[role.unlockOrder] or 1
            if globalWave >= unlockWave then
                availRoles[#availRoles + 1] = roleId
            end
        end
    end
    if #availRoles == 0 then
        availRoles = { "minion", "infantry" }
    end
    return availRoles
end

------------------------------------------------------------------------
--- 从角色池中批量生成普通敌人
---@param stageNum number   等效关卡号（已 floor）
---@param count number      生成数量
---@param hpScale number    HP 缩放系数
---@param spdScale number   速度缩放系数
---@param tags? table       额外字段，如 { isAbyssRift = true }
---@param availRoles? string[] 角色池（不传则自动构建）
---@return table[] enemies  敌人定义列表
------------------------------------------------------------------------
function WG.GenerateBatch(stageNum, count, hpScale, spdScale, tags, availRoles)
    availRoles = availRoles or WG.BuildRolePool(stageNum)
    local enemies = {}
    for i = 1, count do
        local roleId = availRoles[((i - 1) % #availRoles) + 1]
        local def = Config.BuildEnemyDef(stageNum, roleId)
        if def then
            def.baseHP = def.baseHP * hpScale
            def.speed  = def.speed * spdScale
            def.isDungeonEnemy = true
            -- 附加自定义标签
            if tags then
                for k, v in pairs(tags) do
                    def[k] = v
                end
            end
            enemies[#enemies + 1] = def
        end
    end
    return enemies
end

------------------------------------------------------------------------
--- 创建 Boss 定义
---@param stageNum number    等效关卡号
---@param hpScale number     HP 缩放系数
---@param spdScale number    速度缩放系数
---@param bossHPMult number  Boss 额外 HP 倍率（如 5.0 / 6.0）
---@param bossSpeedFactor number Boss 速度因子（如 0.6 / 0.7）
---@param tags? table        额外字段
---@return table|nil bossDef
------------------------------------------------------------------------
function WG.CreateBoss(stageNum, hpScale, spdScale, bossHPMult, bossSpeedFactor, tags)
    local bossDef = Config.BuildBossDef(stageNum)
    if not bossDef then return nil end
    bossDef.baseHP = bossDef.baseHP * hpScale * (bossHPMult or 1)
    bossDef.speed  = bossDef.speed * spdScale * (bossSpeedFactor or 0.7)
    bossDef.isDungeonEnemy = true
    bossDef.isDungeonBoss  = true
    if tags then
        for k, v in pairs(tags) do
            bossDef[k] = v
        end
    end
    return bossDef
end

------------------------------------------------------------------------
--- 将列表尾部的若干敌人标记为精英（Emerald / Abyss 模式）
---@param enemies table[]   敌人列表（就地修改）
---@param eliteCount number 精英数量
---@param hpMult number     精英 HP 倍率（如 2.5）
---@param spdMult number    精英速度倍率（如 0.8 = 减速，1.3 = 加速）
------------------------------------------------------------------------
function WG.MarkElitesTail(enemies, eliteCount, hpMult, spdMult)
    for i = math.max(1, #enemies - eliteCount + 1), #enemies do
        if enemies[i] then
            enemies[i].baseHP = enemies[i].baseHP * hpMult
            enemies[i].speed  = enemies[i].speed * spdMult
            enemies[i].isElite = true
        end
    end
end

------------------------------------------------------------------------
--- 将列表头部的若干敌人标记为精英（TrialTower 模式）
---@param enemies table[]   敌人列表（就地修改）
---@param eliteCount number 精英数量
---@param hpMult number     精英 HP 倍率
---@param spdMult number    精英速度倍率
------------------------------------------------------------------------
function WG.MarkElitesFront(enemies, eliteCount, hpMult, spdMult)
    for i = 1, math.min(eliteCount, #enemies) do
        if enemies[i] then
            enemies[i].baseHP = enemies[i].baseHP * hpMult
            enemies[i].speed  = enemies[i].speed * spdMult
            enemies[i].isElite = true
        end
    end
end

return WG
