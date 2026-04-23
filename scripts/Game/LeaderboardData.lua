-- Game/LeaderboardData.lua
-- 排行榜数据模块：主线关卡、试练塔、资源副本排行榜
-- 基于 clientCloud iscores 排行榜 API

local HeroData = require("Game.HeroData")
local Config = require("Game.Config")
local TodayKey = require("Game.DateUtil").TodayKey

local LB = {}

-- ============================================================================
-- 排行榜 key 定义（iscores 中的 key）
-- ============================================================================

LB.KEY_CAMPAIGN    = "lb_campaign_v3"  -- 主线最高全局波次（直接存 globalWave，无编码）
LB.KEY_TOWER       = "lb_tower"        -- 试练塔最高层
LB.KEY_DUNGEON     = "lb_dungeon"      -- 资源副本当天最高波次（每日重置上传）
LB.KEY_WORLD_BOSS  = "lb_world_boss_v3"   -- 世界BOSS最高伤害（历史，v3：scoreMult替代attrMult）
LB.KEY_ABYSS_NORMAL    = "lb_abyss_normal"     -- 深渊裂隙·普通最高波数
LB.KEY_ABYSS_HARD      = "lb_abyss_hard"       -- 深渊裂隙·困难最高波数
LB.KEY_ABYSS_NIGHTMARE = "lb_abyss_nightmare"  -- 深渊裂隙·噩梦最高波数
LB.KEY_COSTUME         = "lb_costume"          -- 时装战力总加分
LB.KEY_EMERALD_TOKEN    = "lb_emerald_token"    -- 翠影秘境累计凭证
LB.KEY_EMERALD_PROGRESS = "lb_emerald_progress" -- 翠影秘境最高进度 (tier*100+wave)

--- 获取世界BOSS每日排行榜 key（每天一个，格式：lb_wbv3_20260415）
---@return string
function LB.GetWorldBossDailyKey()
    return "lb_wbv3_" .. TodayKey()
end

--- 世界BOSS难度等级列表（与 WorldBossData.DIFFICULTY_LEVELS 对应）
LB.WB_DIFF_LEVELS = { 0, 1, 3, 9 }

--- 获取世界BOSS某难度的每日排行榜 key
--- 格式：lb_wbd0_20260423（难度0普通）、lb_wbd1_20260423（难度1困难）等
---@param diffLevel number 难度等级 0/1/3/9
---@return string
function LB.GetWorldBossDiffDailyKey(diffLevel)
    return "lb_wbd" .. diffLevel .. "_" .. TodayKey()
end

-- 本地缓存
LB._cache = {
    campaign   = nil,  -- { list, myRank, myScore, total, loadedCount }
    tower      = nil,
    dungeon    = nil,
    world_boss = nil,
}

-- (v3: 直接存 globalWave，无偏移编码)

-- ============================================================================
-- BOSS 伤害编码（v3：科学计数法 + 难度位 → 单个 32 位整数，保持排序正确）
-- 编码规则：encoded = exp * 10,000,000 + floor(mantissa * 100,000) * 10 + diffDigit
--   mantissa ∈ [1.0, 10.0)，exp = floor(log10(damage))
--   diffDigit: 难度标记位 0=普通 1=困难 2=噩梦 3=地狱
--   最低一位是难度标记，不影响排序（最多 ±3/10^7 误差，忽略不计）
-- 示例：1.5亿 困难 → exp=8, mantissa=1.5, diff=1 → 81,500,001
--       100亿 地狱 → exp=10, mantissa=1, diff=3 → 101,000,003
-- 最大支持 exp=213，远超游戏实际范围，完全不会溢出 32 位有符号整数
-- ============================================================================

--- 难度等级 → 编码数字映射
LB.DIFF_TO_DIGIT = { [0] = 0, [1] = 1, [3] = 2, [9] = 3 }
--- 编码数字 → 难度等级映射
LB.DIGIT_TO_DIFF = { [0] = 0, [1] = 1, [2] = 3, [3] = 9 }
--- 难度标签（用于显示）
LB.DIFF_LABELS = { [0] = "普通", [1] = "困难", [3] = "噩梦", [9] = "地狱" }
--- 难度颜色（用于显示）
LB.DIFF_COLORS = {
    [0] = { 150, 220, 150 },  -- 绿色
    [1] = { 255, 220, 100 },  -- 黄色
    [3] = { 255, 160, 80 },   -- 橙色
    [9] = { 255, 80, 80 },    -- 红色
}

--- 将 BOSS 加权伤害编码为可排序的 32 位整数（含难度标记）
---@param damage number 加权伤害值（原始伤害 × 难度倍率）
---@param difficultyLevel number|nil 难度等级 0/1/3/9，默认0
---@return number encoded 编码后的整数
function LB.EncodeBossScore(damage, difficultyLevel)
    if not damage or damage <= 0 then return 0 end
    local exp = math.floor(math.log(damage, 10))
    local mantissa = damage / (10 ^ exp)  -- [1.0, 10.0)
    -- 浮点误差修正：mantissa 可能因精度问题 >= 10
    if mantissa >= 10 then
        exp = exp + 1
        mantissa = mantissa / 10
    end
    local diffDigit = LB.DIFF_TO_DIGIT[difficultyLevel or 0] or 0
    return exp * 10000000 + math.floor(mantissa * 100000) * 10 + diffDigit
end

--- 将编码后的整数还原为近似伤害值和难度等级（用于显示）
---@param encoded number
---@return number damage 还原的伤害值
---@return number difficultyLevel 难度等级 0/1/3/9
function LB.DecodeBossScore(encoded)
    if not encoded or encoded <= 0 then return 0, 0 end
    local exp = math.floor(encoded / 10000000)
    local remainder = encoded % 10000000
    local diffDigit = remainder % 10
    local mantissa = math.floor(remainder / 10) / 100000  -- [1.0, 10.0)
    local damage = mantissa * (10 ^ exp)
    local diffLevel = LB.DIGIT_TO_DIFF[diffDigit] or 0
    return damage, diffLevel
end

-- ============================================================================
-- 分数上传
-- ============================================================================

--- 上传主线最高全局波次到排行榜（v3：直接存 globalWave）
---@param bestGlobalWave number
function LB.UploadCampaign(bestGlobalWave)
    if not bestGlobalWave or bestGlobalWave <= 0 then return end
    if not clientCloud then return end
    clientCloud:SetInt(LB.KEY_CAMPAIGN, bestGlobalWave, {
        ok = function()
            print("[LB] Campaign score uploaded: globalWave=" .. bestGlobalWave)
        end,
        error = function(code, reason)
            print("[LB] Campaign upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
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
        error = function(code, reason)
            print("[LB] Tower upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
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
        error = function(code, reason)
            print("[LB] Dungeon upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

--- 上传世界BOSS最高加权伤害（历史总榜，含难度标记）
---@param weightedDamage number 加权伤害（原始伤害 × 难度倍率）
---@param difficultyLevel number 产出该伤害的难度等级 0/1/3/9
function LB.UploadWorldBoss(weightedDamage, difficultyLevel)
    if not weightedDamage or weightedDamage <= 0 then return end
    if not clientCloud then return end
    local encoded = LB.EncodeBossScore(weightedDamage, difficultyLevel or 0)
    clientCloud:SetInt(LB.KEY_WORLD_BOSS, encoded, {
        ok = function()
            print("[LB] World Boss score uploaded: weighted=" .. weightedDamage
                .. " diff=" .. tostring(difficultyLevel) .. " (encoded=" .. encoded .. ")")
        end,
        error = function(code, reason)
            print("[LB] World Boss upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

--- 上传世界BOSS每日加权伤害（当日排行榜，每日换 key，含难度标记）
---@param weightedDamage number 加权伤害
---@param difficultyLevel number 难度等级
function LB.UploadWorldBossDaily(weightedDamage, difficultyLevel)
    if not weightedDamage or weightedDamage <= 0 then return end
    if not clientCloud then return end
    local dailyKey = LB.GetWorldBossDailyKey()
    local encoded = LB.EncodeBossScore(weightedDamage, difficultyLevel or 0)
    clientCloud:SetInt(dailyKey, encoded, {
        ok = function()
            print("[LB] World Boss daily score uploaded: weighted=" .. weightedDamage
                .. " diff=" .. tostring(difficultyLevel) .. " (encoded=" .. encoded .. ") key=" .. dailyKey)
        end,
        error = function(code, reason)
            print("[LB] World Boss daily upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

--- 上传世界BOSS按难度的每日排行榜（每个难度独立 key，原始伤害）
---@param rawDamage number 原始伤害（不乘 scoreMult）
---@param difficultyLevel number 难度等级 0/1/3/9
function LB.UploadWorldBossDiffDaily(rawDamage, difficultyLevel)
    if not rawDamage or rawDamage <= 0 then return end
    if not clientCloud then return end
    local dailyKey = LB.GetWorldBossDiffDailyKey(difficultyLevel or 0)
    -- 不含难度位编码（同难度内排序，无需标记）
    local encoded = LB.EncodeBossScore(rawDamage, 0)
    clientCloud:SetInt(dailyKey, encoded, {
        ok = function()
            print("[LB] World Boss diff daily uploaded: damage=" .. rawDamage
                .. " diff=" .. tostring(difficultyLevel) .. " key=" .. dailyKey)
        end,
        error = function(code, reason)
            print("[LB] World Boss diff daily upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
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
        error = function(code, reason)
            print("[LB] Abyss " .. difficultyId .. " upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
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
        error = function(code, reason)
            print("[LB] Costume upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
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

-- ============================================================================
-- 翠影秘境排行榜
-- ============================================================================

--- 翠影秘境难度名称（与 EmeraldDungeonData.DIFFICULTIES 对应）
local EMERALD_TIER_NAMES = {
    [1] = "初试", [2] = "磨砺", [3] = "试炼",
    [4] = "淬炼", [5] = "极境", [6] = "天罚",
}

--- 上传翠影秘境累计凭证到排行榜
---@param totalToken number
function LB.UploadEmeraldToken(totalToken)
    if not totalToken or totalToken <= 0 then return end
    if not clientCloud then return end
    clientCloud:SetInt(LB.KEY_EMERALD_TOKEN, totalToken, {
        ok = function()
            print("[LB] Emerald token uploaded: " .. totalToken)
        end,
        error = function(code, reason)
            print("[LB] Emerald token upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

--- 将翠影秘境进度编码为可排序整数：tier * 100 + wave
---@param tier number 难度等级 1-6
---@param wave number 通关波次
---@return number
function LB.EncodeEmeraldProgress(tier, wave)
    return (tier or 0) * 100 + (wave or 0)
end

--- 解码翠影秘境进度
---@param encoded number
---@return number tier, number wave
function LB.DecodeEmeraldProgress(encoded)
    if not encoded or encoded <= 0 then return 0, 0 end
    local tier = math.floor(encoded / 100)
    local wave = encoded % 100
    return tier, wave
end

--- 上传翠影秘境最高进度到排行榜
---@param tier number 难度等级 1-6
---@param wave number 通关波次
function LB.UploadEmeraldProgress(tier, wave)
    if not tier or tier <= 0 then return end
    if not clientCloud then return end
    local encoded = LB.EncodeEmeraldProgress(tier, wave)
    clientCloud:SetInt(LB.KEY_EMERALD_PROGRESS, encoded, {
        ok = function()
            print("[LB] Emerald progress uploaded: tier=" .. tier .. " wave=" .. wave .. " (encoded=" .. encoded .. ")")
        end,
        error = function(code, reason)
            print("[LB] Emerald progress upload FAILED: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

--- 格式化翠影秘境累计凭证
---@param score number
---@return string
function LB.FormatEmeraldToken(score)
    if not score or score <= 0 then return "—" end
    if score >= 100000 then
        return string.format("%.1f万", score / 10000)
    elseif score >= 10000 then
        return string.format("%.2f万", score / 10000)
    end
    return tostring(score)
end

--- 格式化翠影秘境进度（编码值 → 可读字符串）
---@param encoded number
---@return string
function LB.FormatEmeraldProgress(encoded)
    if not encoded or encoded <= 0 then return "—" end
    local tier, wave = LB.DecodeEmeraldProgress(encoded)
    local name = EMERALD_TIER_NAMES[tier] or ("T" .. tier)
    return name .. " 第" .. wave .. "波"
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
    -- 世界BOSS最高加权伤害（v3：scoreMult + 难度标记）
    local ok3, WBD = pcall(require, "Game.WorldBossData")
    if ok3 then
        local wData = WBD.GetData()
        local bestWeighted = wData.bestWeightedDamage or 0
        local bestDiff = wData.bestWeightedDifficulty or 0
        -- 兼容旧存档：如果没有加权分数，用原始 bestDamage（普通难度）
        if bestWeighted <= 0 then
            bestWeighted = wData.bestDamage or 0
            bestDiff = 0
        end
        if bestWeighted > 0 then
            LB.UploadWorldBoss(bestWeighted, bestDiff)
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
    -- 翠影秘境
    local ok5, ED = pcall(require, "Game.EmeraldDungeonData")
    if ok5 then
        local totalToken = ED.GetTotalTokenEarned()
        if totalToken > 0 then
            LB.UploadEmeraldToken(totalToken)
        end
        -- 计算最高进度（最高通关 tier + 该 tier 的 bestWaves）
        local bestTier, bestWave = ED.GetBestProgress()
        if bestTier > 0 then
            LB.UploadEmeraldProgress(bestTier, bestWave)
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

--- 格式化排行榜分数为可读字符串（v3：score 即 globalWave）
---@param score number 全局波次
---@return string
function LB.FormatStage(score)
    if not score or score <= 0 then return "—" end
    local stageNum = math.floor((score - 1) / Config.WAVES_PER_STAGE) + 1
    local waveInStage = score - (stageNum - 1) * Config.WAVES_PER_STAGE
    return "第" .. stageNum .. "关 第" .. waveInStage .. "波"
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

--- 格式化世界BOSS加权伤害为可读字符串（接收编码后的整数，内部解码）
--- 注意：不从编码中显示难度标签，因为旧v2数据末位是尾数不是难度位，会误判
---@param encoded number 编码后的排行榜整数
---@return string
function LB.FormatWorldBoss(encoded)
    if not encoded or encoded <= 0 then return "—" end
    local damage = LB.DecodeBossScore(encoded)
    if damage >= 10000000000000000 then
        return string.format("%.1f京", damage / 10000000000000000)
    elseif damage >= 1000000000000 then
        return string.format("%.1f兆", damage / 1000000000000)
    elseif damage >= 100000000 then
        return string.format("%.1f亿", damage / 100000000)
    elseif damage >= 10000 then
        return string.format("%.0f万", damage / 10000)
    else
        return tostring(math.floor(damage))
    end
end

return LB
