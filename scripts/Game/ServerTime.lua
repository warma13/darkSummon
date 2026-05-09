-- Game/ServerTime.lua
-- 防改时间作弊 —— 去中心化共识方案（递进式 + Anchor）
--
-- 编码: score = gameDay * 10000 + voteCount
--   高位 = 游戏天数(从上线日起 day0)，天然递增
--   低4位 = 当天投票序号(近似唯一投票人数)
--
-- 数据存储：
--   共享排行榜 lb_server_time  → 所有人可见的投票数据
--   私有云变量 st_anchor        → 每个玩家自己的"已确认共识天"（跨会话持久）
--
-- 投票规则（Anchor 机制）：
--   老玩家（有 anchor）→ 只能投 anchor 或 anchor+1，改时钟无法绕过
--   回归玩家（anchor 远落后）→ 共识强时允许投 consensusDay 或 +1
--   新玩家（无 anchor）→ 有共识时只能投 consensusDay 或 +1；无共识时 myGameDay≤1
--   每次共识确定后更新 anchor → 下次重启继续锚定
--
-- 共识推进（递进式）：
--   首次启动 → 票数最多的天作为初始共识（平票取更小天，保守策略）
--   后续只允许 +1 递进 → 下一天有足够票数(≥MIN_ADVANCE)才推进
--   永不回退
--
-- 验证：
--   ahead = 玩家天数 - 共识天
--   -1 ≤ ahead ≤ MAX_AHEAD → 合法
--   ahead < -1 或 > MAX_AHEAD → 异常
--
-- 对外接口：
--   Now()          → 可信 Unix 秒（单调时钟推算）
--   GetLBTime()    → 共识时间（合法=Now(), 异常=共识天0点）
--   IsTimeValid()  → true/false/nil
--   GetGameDay()   → 共识天数 (0-based)

local ST = {}

local LB_KEY = "lb_server_time"
local SCALE = 10000           -- 低4位给投票序号 (max 9999)
local FETCH_COUNT = 20        -- 拉取前20名做共识

-- 推进到下一天所需的最低票数
local MIN_ADVANCE = 3

-- 玩家超前共识天的最大容忍（天）
-- ahead ∈ [-1, MAX_AHEAD] 视为合法
local MAX_AHEAD = 7

-- 上线日 UTC 0点（gameDay 0 = 这一天）
-- 2026-05-08 00:00:00 UTC
local LAUNCH_EPOCH = os.time({ year = 2026, month = 5, day = 8, hour = 0, min = 0, sec = 0 })

-- ============================================================================
-- 内部状态
-- ============================================================================
local anchorOsTime = nil
local anchorElapsed = nil

local consensusDay = nil       -- 共识天数 (0-based)，会话内只增不减
local consensusVotes = 0       -- 共识天的票数
local totalEntries = 0         -- top N 总条目数
local lbReady = false
local timeValid = nil          -- true/false/nil
local myGameDay = nil          -- 自己算出的天数
local lastVotedDay = -1        -- 本会话已投票的天（每天只投一次）
local anchorDay = nil          -- 私有云变量：上次确认的共识天（跨会话持久）
local ANCHOR_KEY = "st_anchor" -- 私有云变量 key

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 校准（云存档加载成功后调用）
function ST.Calibrate()
    anchorOsTime = os.time()
    anchorElapsed = time.elapsedTime
    myGameDay = math.max(0, calcGameDay())
    print("[ServerTime] Calibrated: " .. os.date("%Y-%m-%d %H:%M:%S", anchorOsTime)
        .. " gameDay=" .. myGameDay)

    if not clientCloud then return end

    -- 先读私有云变量 anchor，再拉排行榜投票
    clientCloud:Get(ANCHOR_KEY, {
        ok = function(values, iscores)
            local v = iscores[ANCHOR_KEY]
            if v and v >= 0 then
                anchorDay = v
                print("[ServerTime] Loaded anchor: day=" .. anchorDay)
            else
                anchorDay = nil
                print("[ServerTime] No anchor (new player)")
            end
            ST._fetchAndVote()
        end,
        error = function(code, reason)
            print("[ServerTime] Anchor read failed: " .. tostring(reason) .. ", proceeding without anchor")
            anchorDay = nil
            ST._fetchAndVote()
        end,
    })
end

--- 可信时间（Unix 秒）
---@return integer
function ST.Now()
    if anchorOsTime and anchorElapsed then
        return math.floor(anchorOsTime + (time.elapsedTime - anchorElapsed))
    end
    return os.time()
end

function ST.IsCalibrated()
    return anchorOsTime ~= nil
end

-- ============================================================================
-- 去中心化共识
-- ============================================================================

--- 从 os.time() 计算游戏天数
---@param t? integer  Unix秒，默认 os.time()
---@return integer     gameDay (0-based)
function calcGameDay(t)
    t = t or os.time()
    return math.floor((t - LAUNCH_EPOCH) / 86400)
end

--- 找票数最多的天
---@param dayCounts table<integer,integer>
---@return integer|nil day
---@return integer count
local function findMostVotedDay(dayCounts)
    local bestDay, bestCount = nil, 0
    for d, c in pairs(dayCounts) do
        -- 票数更多；平票取更小的天（保守策略，防作弊者拉高）
        if c > bestCount or (c == bestCount and bestDay and d < bestDay) then
            bestDay = d
            bestCount = c
        end
    end
    return bestDay, bestCount
end

--- 拉取排行榜 → 解析临时共识 → 基于 anchor 决定投票 → 最终共识
function ST._fetchAndVote()
    clientCloud:GetRankList(LB_KEY, 0, FETCH_COUNT, {
        ok = function(rankList)
            ---------------------------------------------------------
            -- 1) 解析排行榜数据
            ---------------------------------------------------------
            local dayCounts = {}     -- day → 条目数(唯一玩家数)
            local maxVote = 0        -- myGameDay 当天最大投票序号
            local alreadyVoted = false
            local myUserId = clientCloud and clientCloud.userId and tostring(clientCloud.userId) or ""
            for _, entry in ipairs(rankList) do
                local s = (entry.iscore and entry.iscore[LB_KEY]) or 0
                local d = math.floor(s / SCALE)
                local v = s % SCALE
                dayCounts[d] = (dayCounts[d] or 0) + 1
                if d == myGameDay and v > maxVote then
                    maxVote = v
                end
                -- 自己已经在当天投过票
                local uid = entry.userId and tostring(entry.userId) or ""
                if uid == myUserId and d == myGameDay then
                    alreadyVoted = true
                end
            end

            ---------------------------------------------------------
            -- 2) 解析临时共识（用于新玩家/回归玩家参考）
            ---------------------------------------------------------
            local tempConsensus, tempVotes = findMostVotedDay(dayCounts)
            local hasStrongConsensus = tempConsensus and tempVotes >= MIN_ADVANCE

            ---------------------------------------------------------
            -- 3) 投票决策（基于 anchor）
            ---------------------------------------------------------
            local shouldVote = (myGameDay ~= lastVotedDay) and (not alreadyVoted)

            if shouldVote then
                if anchorDay then
                    -- 老玩家：只能投 anchor 或 anchor+1
                    -- 回归玩家宽容：共识强且 myGameDay 在共识附近时也放行
                    local anchorOk = (myGameDay == anchorDay or myGameDay == anchorDay + 1)
                    local returnOk = hasStrongConsensus
                        and (myGameDay == tempConsensus or myGameDay == tempConsensus + 1)
                    if not anchorOk and not returnOk then
                        shouldVote = false
                        print(string.format(
                            "[ServerTime] Vote rejected: myDay=%d anchor=%d consensus=%s (anti-cheat)",
                            myGameDay, anchorDay, tostring(tempConsensus)))
                    end
                else
                    -- 新玩家（无 anchor）
                    if hasStrongConsensus then
                        -- 排行榜有强共识：只允许投共识天或 +1
                        if myGameDay ~= tempConsensus and myGameDay ~= tempConsensus + 1 then
                            shouldVote = false
                            print(string.format(
                                "[ServerTime] New player vote rejected: myDay=%d consensus=%d (anti-cheat)",
                                myGameDay, tempConsensus))
                        end
                    elseif tempConsensus then
                        -- 有数据但不够强：保守，只允许投共识天或 +1
                        if myGameDay ~= tempConsensus and myGameDay ~= tempConsensus + 1 then
                            shouldVote = false
                            print(string.format(
                                "[ServerTime] New player vote rejected (weak consensus): myDay=%d consensus=%d",
                                myGameDay, tempConsensus))
                        end
                    else
                        -- 排行榜完全空（上线首日）：只允许 Day 0-1
                        if myGameDay > 1 then
                            shouldVote = false
                            print(string.format(
                                "[ServerTime] Empty LB, myDay=%d > 1, vote rejected (anti-cheat)", myGameDay))
                        end
                    end
                end
            end

            ---------------------------------------------------------
            -- 4) 执行投票
            ---------------------------------------------------------
            if shouldVote then
                local myVote = maxVote + 1
                clientCloud:SetInt(LB_KEY, myGameDay * SCALE + myVote)
                lastVotedDay = myGameDay
                dayCounts[myGameDay] = (dayCounts[myGameDay] or 0) + 1
                print(string.format("[ServerTime] Voted: gameDay=%d vote=%d", myGameDay, myVote))
            else
                if alreadyVoted then lastVotedDay = myGameDay end
                print(string.format("[ServerTime] No vote this round (myDay=%d)", myGameDay))
            end

            ---------------------------------------------------------
            -- 5) 最终共识解析
            ---------------------------------------------------------
            local total = #rankList + (shouldVote and 1 or 0)
            ST._resolveConsensus(dayCounts, total)

            ---------------------------------------------------------
            -- 6) 共识确定后更新 anchor
            ---------------------------------------------------------
            if consensusDay and consensusDay ~= anchorDay then
                anchorDay = consensusDay
                clientCloud:SetInt(ANCHOR_KEY, anchorDay)
                print("[ServerTime] Anchor updated: day=" .. anchorDay)
            end
        end,
        error = function(code, reason)
            print("[ServerTime] Fetch failed: " .. tostring(reason))
        end,
    })
end

--- 共识判定（递进式）
---@param dayCounts table<integer,integer>  day → 条目数
---@param total integer 总条目数
function ST._resolveConsensus(dayCounts, total)
    totalEntries = total

    if consensusDay == nil then
        -----------------------------------------------------------------
        -- 首次 Bootstrap：票数最多的天作为初始共识
        -- 作弊投票已在 _fetchAndVote 中被 anchor 机制过滤
        -----------------------------------------------------------------
        local bestDay, bestCount = findMostVotedDay(dayCounts)
        if bestDay then
            consensusDay = bestDay
            consensusVotes = bestCount
            print(string.format("[ServerTime] Bootstrap consensus: day=%d votes=%d/%d",
                consensusDay, consensusVotes, total))
        else
            lbReady = false
            timeValid = nil
            print("[ServerTime] No votes available, no consensus")
            return
        end
    end

    -----------------------------------------------------------------
    -- 递进：只允许从当前共识天推进到 +1
    -- 条件：下一天在排行榜中有 ≥ MIN_ADVANCE 条记录
    -----------------------------------------------------------------
    local advanced = false
    local nextDay = consensusDay + 1
    local nextCount = dayCounts[nextDay] or 0
    if nextCount >= MIN_ADVANCE then
        consensusDay = nextDay
        consensusVotes = nextCount
        advanced = true
        print(string.format("[ServerTime] Advanced consensus: day=%d votes=%d/%d",
            consensusDay, consensusVotes, total))
    else
        -- 不满足推进条件，保持当前共识
        -- 更新当前共识天的票数（可能有变化）
        consensusVotes = dayCounts[consensusDay] or 0
    end

    lbReady = true

    -----------------------------------------------------------------
    -- 验证：玩家本地天 vs 共识天
    -- ahead ∈ [-1, MAX_AHEAD] → 合法
    --   -1 容忍：共识刚推进，玩家还在前一天（时序边界）
    --   MAX_AHEAD 容忍：游戏不活跃期间回归的诚实玩家
    -----------------------------------------------------------------
    local ahead = (myGameDay or 0) - consensusDay
    if consensusVotes >= MIN_ADVANCE then
        timeValid = (ahead >= -1 and ahead <= MAX_AHEAD)
    else
        -- 共识票数不足，无法判定
        timeValid = nil
    end

    print(string.format(
        "[ServerTime] Consensus: day=%d votes=%d/%d | myDay=%d ahead=%d | valid=%s",
        consensusDay, consensusVotes, total,
        myGameDay or -1, ahead, tostring(timeValid)))
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 共识时间（Unix 秒）
--- 合法 → Now()（精确到秒）
--- 异常 → 共识天的0点（作弊惩罚：冻结到共识天）
--- 数据不足 → nil（调用方应 fallback）
---@return integer|nil
function ST.GetLBTime()
    if not lbReady or not consensusDay then return nil end
    if timeValid == true then return ST.Now() end
    if timeValid == false then return LAUNCH_EPOCH + consensusDay * 86400 end
    return nil  -- timeValid == nil，数据不足，不给时间
end

--- 共识天数 (0-based, day0=上线日)
---@return integer|nil
function ST.GetGameDay()
    return consensusDay
end

--- 共识票数
---@return integer
function ST.GetConsensusVotes()
    return consensusVotes
end

--- 共识占比
---@return number  0.0~1.0
function ST.GetConsensusRatio()
    return consensusVotes / math.max(1, totalEntries)
end

--- 合法性
---@return boolean|nil  true=合法, false=异常, nil=数据不足
function ST.IsTimeValid()
    return timeValid
end

--- 共识是否就绪
---@return boolean
function ST.IsLBReady()
    return lbReady
end

--- 上线日 epoch（供外部模块换算）
---@return integer
function ST.GetLaunchEpoch()
    return LAUNCH_EPOCH
end

--- MAX_AHEAD 容忍天数（供外部模块引用）
---@return integer
function ST.GetMaxAhead()
    return MAX_AHEAD
end

--- 排行榜总条目数（参与共识的玩家数）
---@return integer
function ST.GetTotalEntries()
    return totalEntries
end

--- 共识钳制的当前时间（Unix 秒）
--- 用 os.time() 算具体秒数，但用两层上限钳制：
---   Layer 1: 共识天上限 = (consensusDay + MAX_AHEAD + 1) 天末尾
---   Layer 2: 本地天上限 = (lastClaimDay + MAX_AHEAD + 1) 天末尾（独立于共识，防共识未就绪时退化）
--- 两层取最小值，保证即使共识异步未回也有硬上限
---@param lastClaimDay? integer  上次领取时的游戏天数（来自存档 afkLastClaimDay），nil 时跳过 Layer 2
---@return integer
function ST.ConsensusClampedNow(lastClaimDay)
    local osNow = ST.Now()

    -- Layer 1: 共识天上限（排行榜就绪时可用）
    local cap1 = math.huge
    if lbReady and consensusDay then
        cap1 = LAUNCH_EPOCH + (consensusDay + MAX_AHEAD + 1) * 86400
    end

    -- Layer 2: 本地存档天上限（不依赖共识，始终可用）
    local cap2 = math.huge
    if lastClaimDay and lastClaimDay >= 0 then
        cap2 = LAUNCH_EPOCH + (lastClaimDay + MAX_AHEAD + 1) * 86400
    end

    local cap = math.min(cap1, cap2)
    if cap < math.huge then
        return math.min(osNow, cap)
    end
    return osNow
end

return ST
