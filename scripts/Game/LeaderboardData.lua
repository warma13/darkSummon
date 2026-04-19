-- Game/LeaderboardData.lua
-- 排行榜数据模块：主线关卡、试练塔、资源副本排行榜
-- 基于 clientCloud iscores 排行榜 API

local HeroData = require("Game.HeroData")
local Config = require("Game.Config")

local LB = {}

-- ============================================================================
-- 排行榜 key 定义（iscores 中的 key）
-- ============================================================================

LB.KEY_CAMPAIGN    = "lb_campaign"     -- 主线最高关卡（新版上传 globalWave）
LB.KEY_TOWER       = "lb_tower"        -- 试练塔最高层
LB.KEY_DUNGEON     = "lb_dungeon"      -- 资源副本当天最高波次（每日重置上传）
LB.KEY_WORLD_BOSS  = "lb_world_boss_v2"   -- 世界BOSS最高伤害（历史，v2编码）
LB.KEY_ABYSS_NORMAL    = "lb_abyss_normal"     -- 深渊裂隙·普通最高波数
LB.KEY_ABYSS_HARD      = "lb_abyss_hard"       -- 深渊裂隙·困难最高波数
LB.KEY_ABYSS_NIGHTMARE = "lb_abyss_nightmare"  -- 深渊裂隙·噩梦最高波数
LB.KEY_COSTUME         = "lb_costume"          -- 时装战力总加分

--- 获取世界BOSS每日排行榜 key（每天一个，格式：lb_wb_daily_20260415）
---@return string
function LB.GetWorldBossDailyKey()
    return "lb_wbv2_" .. os.date("%Y%m%d")
end

-- 本地缓存
LB._cache = {
    campaign   = nil,  -- { list, myRank, myScore, total, loadedCount }
    tower      = nil,
    dungeon    = nil,
    world_boss = nil,
}

-- v2 分数偏移量：新格式分数 = globalWave + SCORE_OFFSET
-- 旧格式分数（bestStage）不带偏移，天然 < SCORE_OFFSET
LB.SCORE_OFFSET = 100000

-- ============================================================================
-- BOSS 伤害编码（科学计数法 → 单个 32 位整数，保持排序正确）
-- 编码规则：encoded = exp * 10,000,000 + floor(mantissa * 1,000,000)
--   mantissa ∈ [1.0, 10.0)，exp = floor(log10(damage))
-- 示例：1.5亿 → exp=8, mantissa=1.5 → 81,500,000
--       15亿  → exp=9, mantissa=1.5 → 91,500,000
--       100亿 → exp=10, mantissa=1  → 101,000,000
-- 最大支持 exp=213，远超游戏实际范围，完全不会溢出 32 位有符号整数
-- ============================================================================

--- 将 BOSS 伤害编码为可排序的 32 位整数
---@param damage number 原始伤害值（可超过 2^31）
---@return number encoded 编码后的整数
function LB.EncodeBossScore(damage)
    if not damage or damage <= 0 then return 0 end
    local exp = math.floor(math.log(damage, 10))
    local mantissa = damage / (10 ^ exp)  -- [1.0, 10.0)
    -- 浮点误差修正：mantissa 可能因精度问题 >= 10
    if mantissa >= 10 then
        exp = exp + 1
        mantissa = mantissa / 10
    end
    return math.floor(exp * 10000000 + mantissa * 1000000)
end

--- 将编码后的整数还原为近似伤害值（用于显示）
---@param encoded number
---@return number damage 还原的伤害值
function LB.DecodeBossScore(encoded)
    if not encoded or encoded <= 0 then return 0 end
    local exp = math.floor(encoded / 10000000)
    local mantissa = (encoded % 10000000) / 1000000  -- [1.0, 10.0)
    return mantissa * (10 ^ exp)
end

-- ============================================================================
-- 分数上传
-- ============================================================================

--- 上传主线最高全局波次到排行榜（自动加偏移量标记为 v2 格式）
---@param bestGlobalWave number
function LB.UploadCampaign(bestGlobalWave)
    if not bestGlobalWave or bestGlobalWave <= 0 then return end
    if not clientCloud then return end
    local encoded = bestGlobalWave + LB.SCORE_OFFSET
    clientCloud:SetInt(LB.KEY_CAMPAIGN, encoded, {
        ok = function()
            print("[LB] Campaign score uploaded: globalWave=" .. bestGlobalWave .. " (encoded=" .. encoded .. ")")
        end,
    })
end

--- 上传试练塔最高层到排行榜
---@param floor number
function LB.UploadTower(floor)
    if not floor or floor <= 0 then return end
    if not clientCloud then return end
    clientCloud:SetInt(LB.KEY_TOWER, floor, {
        ok = function()
            print("[LB] Tower score uploaded: " .. floor)
        end,
    })
end

--- 上传资源副本当天最高波次
---@param wave number
function LB.UploadDungeon(wave)
    if not wave or wave <= 0 then return end
    if not clientCloud then return end
    clientCloud:SetInt(LB.KEY_DUNGEON, wave, {
        ok = function()
            print("[LB] Dungeon score uploaded: " .. wave)
        end,
    })
end

--- 上传世界BOSS最高伤害（历史总榜）
---@param bestDamage number
function LB.UploadWorldBoss(bestDamage)
    if not bestDamage or bestDamage <= 0 then return end
    if not clientCloud then return end
    local encoded = LB.EncodeBossScore(bestDamage)
    clientCloud:SetInt(LB.KEY_WORLD_BOSS, encoded, {
        ok = function()
            print("[LB] World Boss score uploaded: " .. bestDamage .. " (encoded=" .. encoded .. ")")
        end,
    })
end

--- 上传世界BOSS每日伤害（当日排行榜，每日换 key）
---@param damage number 本场伤害
function LB.UploadWorldBossDaily(damage)
    if not damage or damage <= 0 then return end
    if not clientCloud then return end
    local dailyKey = LB.GetWorldBossDailyKey()
    local encoded = LB.EncodeBossScore(damage)
    clientCloud:SetInt(dailyKey, encoded, {
        ok = function()
            print("[LB] World Boss daily score uploaded: " .. damage .. " (encoded=" .. encoded .. ") key=" .. dailyKey)
        end,
        error = function(code, reason)
            print("[LB] World Boss daily upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

--- 深渊裂隙难度 ID → 排行榜 key 映射
LB.ABYSS_KEY_MAP = {
    normal    = LB.KEY_ABYSS_NORMAL,
    hard      = LB.KEY_ABYSS_HARD,
    nightmare = LB.KEY_ABYSS_NIGHTMARE,
}

--- 上传深渊裂隙最高通关波数
---@param difficultyId string "normal"/"hard"/"nightmare"
---@param wave number 通关波数 (1-15)
function LB.UploadAbyss(difficultyId, wave)
    if not wave or wave <= 0 then return end
    if not clientCloud then return end
    local key = LB.ABYSS_KEY_MAP[difficultyId]
    if not key then return end
    clientCloud:SetInt(key, wave, {
        ok = function()
            print("[LB] Abyss " .. difficultyId .. " score uploaded: wave " .. wave)
        end,
    })
end

--- 上传时装战力总加分到排行榜
---@param bonus number 时装总加分
function LB.UploadCostume(bonus)
    if not bonus or bonus <= 0 then return end
    if not clientCloud then return end
    clientCloud:SetInt(LB.KEY_COSTUME, bonus, {
        ok = function()
            print("[LB] Costume score uploaded: " .. bonus)
        end,
    })
end

--- 格式化时装战力加分
---@param score number
---@return string
function LB.FormatCostume(score)
    if not score or score <= 0 then return "—" end
    return score .. " 战力"
end

--- 格式化深渊裂隙波数
---@param wave number
---@return string
function LB.FormatAbyss(wave)
    if not wave or wave <= 0 then return "—" end
    if wave >= 15 then return "通关" end
    return "第" .. wave .. "波"
end

--- 同步所有排行榜分数（游戏初始化 / Save 时调用）
function LB.SyncAll()
    if not clientCloud then return end
    local bestGlobalWave = (HeroData.stats and HeroData.stats.bestGlobalWave) or 0
    -- 兼容旧存档：如果 bestGlobalWave 为 0 但 bestStage > 0，从 bestStage 推算
    if bestGlobalWave <= 0 then
        local bestStage = (HeroData.stats and HeroData.stats.bestStage) or 0
        bestGlobalWave = bestStage * Config.WAVES_PER_STAGE
    end
    if bestGlobalWave > 0 then
        LB.UploadCampaign(bestGlobalWave)
    end
    local ok1, TTD = pcall(require, "Game.TrialTowerData")
    if ok1 then
        local tData = TTD.GetData()
        local floor = (tData.currentFloor or 1) - 1  -- currentFloor 是下一层，所以 -1 = 已通关层
        if floor > 0 then
            LB.UploadTower(floor)
        end
    end
    -- 资源副本取所有副本中最高的 bestWave
    local ok2, RD = pcall(require, "Game.ResourceDungeonData")
    if ok2 then
        local maxWave = 0
        for _, def in ipairs(RD.DUNGEON_DEFS) do
            local w = RD.GetBestWave(def.key)
            if w > maxWave then maxWave = w end
        end
        if maxWave > 0 then
            LB.UploadDungeon(maxWave)
        end
    end
    -- 世界BOSS最高伤害
    local ok3, WBD = pcall(require, "Game.WorldBossData")
    if ok3 then
        local bestDmg = WBD.GetBestDamage()
        if bestDmg > 0 then
            LB.UploadWorldBoss(bestDmg)
        end
    end
    -- 时装战力总加分
    local ok4, CD = pcall(require, "Game.CostumeData")
    if ok4 then
        local bonus = CD.GetTotalScoreBonus()
        if bonus > 0 then
            LB.UploadCostume(bonus)
        end
    end
end

-- ============================================================================
-- 排行榜查询
-- ============================================================================

--- 加载排行榜列表
---@param key string      排行榜 key
---@param start number    起始位置 (0-based)
---@param count number    获取数量
---@param callback function(list, myRank, myScore, total)
function LB.FetchRankList(key, start, count, callback)
    if not clientCloud then
        if callback then callback(nil) end
        return
    end

    -- 将排名 key 作为附加字段传入，确保 iscore 中包含该 key 的值
    clientCloud:GetRankList(key, start, count, {
        ok = function(rankList)
            local list = {}
            local userIds = {}
            for i, item in ipairs(rankList) do
                local scoreVal = 0
                -- 方法1：直接从 iscore 表中取排名 key
                if item.iscore then
                    local v = item.iscore[key]
                    if v and type(v) == "number" and v ~= 0 then
                        scoreVal = v
                    end
                end
                -- 方法2：遍历 iscore 找最大非零值（兼容 key 不匹配或动态 key 场景）
                if scoreVal == 0 and item.iscore then
                    local ok2, _ = pcall(function()
                        for k, v in pairs(item.iscore) do
                            if type(v) == "number" and v > scoreVal then
                                scoreVal = v
                            end
                        end
                    end)
                end
                list[#list + 1] = {
                    rank = start + i,
                    userId = item.userId or item.player,
                    score = scoreVal or 0,
                    isMe = (item.userId or item.player) == clientCloud.userId,
                    nickname = nil,
                }
                userIds[#userIds + 1] = item.userId or item.player
            end
            -- 获取昵称
            if #userIds > 0 then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, entry in ipairs(list) do
                            entry.nickname = map[entry.userId] or "玩家"
                        end
                        if callback then callback(list) end
                    end,
                    onError = function()
                        -- 昵称查询失败，使用默认
                        for _, entry in ipairs(list) do
                            entry.nickname = "玩家"
                        end
                        if callback then callback(list) end
                    end,
                })
            else
                if callback then callback(list) end
            end
        end,
        error = function()
            if callback then callback(nil) end
        end,
    })
end

--- 获取自己的排名
---@param key string
---@param callback function(rank, score)  rank=nil 表示未上榜
function LB.FetchMyRank(key, callback)
    if not clientCloud then
        if callback then callback(nil, 0) end
        return
    end
    print("[LB] FetchMyRank key=" .. key)
    clientCloud:GetUserRank(clientCloud.userId, key, {
        ok = function(rank, scoreValue)
            print("[LB] FetchMyRank result: rank=" .. tostring(rank) .. " score=" .. tostring(scoreValue))
            if callback then callback(rank, scoreValue or 0) end
        end,
        error = function(code, reason)
            print("[LB] FetchMyRank error: " .. tostring(code) .. " " .. tostring(reason))
            if callback then callback(nil, 0) end
        end,
    })
end

--- 获取排行榜总人数
---@param key string
---@param callback function(total)
function LB.FetchRankTotal(key, callback)
    if not clientCloud then
        if callback then callback(0) end
        return
    end
    clientCloud:GetRankTotal(key, {
        ok = function(total)
            if callback then callback(total or 0) end
        end,
        error = function()
            if callback then callback(0) end
        end,
    })
end

-- ============================================================================
-- 主线关卡号显示格式化（关卡号 → "大关-小关"）
-- ============================================================================

--- 格式化排行榜分数为可读字符串
--- 通过 SCORE_OFFSET 区分新旧格式：
---   >= SCORE_OFFSET → v2 新格式（globalWave），显示 "第X关 第Y波"
---   < SCORE_OFFSET  → v1 旧格式（bestStage），显示 "第X关"
---@param score number 排行榜分数
---@return string
function LB.FormatStage(score)
    if not score or score <= 0 then return "—" end
    if score >= LB.SCORE_OFFSET then
        -- v2 新格式：解码 globalWave
        local globalWave = score - LB.SCORE_OFFSET
        if globalWave <= 0 then return "—" end
        local stageNum = math.floor((globalWave - 1) / Config.WAVES_PER_STAGE) + 1
        local waveInStage = globalWave - (stageNum - 1) * Config.WAVES_PER_STAGE
        return "第" .. stageNum .. "关 第" .. waveInStage .. "波"
    else
        -- v1 旧格式：直接是 bestStage
        return "第" .. score .. "关"
    end
end

--- 格式化试练塔层数为 "第X层" 格式
---@param floor number
---@return string
function LB.FormatTower(floor)
    if not floor or floor <= 0 then return "—" end
    return "第" .. floor .. "层"
end

--- 格式化资源副本波次为 "第X波" 格式
---@param wave number
---@return string
function LB.FormatDungeon(wave)
    if not wave or wave <= 0 then return "—" end
    return "第" .. wave .. "波"
end

--- 格式化世界BOSS伤害为可读字符串（接收编码后的整数，内部解码）
---@param encoded number 编码后的排行榜整数
---@return string
function LB.FormatWorldBoss(encoded)
    if not encoded or encoded <= 0 then return "—" end
    local damage = LB.DecodeBossScore(encoded)
    if damage >= 100000000 then
        return string.format("%.1f亿", damage / 100000000)
    elseif damage >= 10000 then
        return string.format("%.0f万", damage / 10000)
    else
        return tostring(math.floor(damage))
    end
end

return LB
