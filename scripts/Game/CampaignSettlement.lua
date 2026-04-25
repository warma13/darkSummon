-- Game/CampaignSettlement.lua
-- 主线关卡结算逻辑：通关奖励计算、失败统计（纯数据，无 UI 依赖）

local State    = require("Game.State")
local HeroData = require("Game.HeroData")
local ChestData = require("Game.ChestData")
local Currency = require("Game.Currency")

local CS = {}

-- ============================================================================
-- 通关结算
-- ============================================================================

--- 通关结算：计算并发放奖励、更新任务进度
---@param stageNum number 关卡编号
---@param score number 本关得分
---@return table result 结算结果（含各项奖励数值）
function CS.SettleStageClear(stageNum, score)
    -- 基础奖励（金币/精华/碎片等）
    HeroData.SettleRewards(stageNum, score)

    -- 通关产出宝箱
    ChestData.GrantStageDrop(stageNum)

    -- 通关产出虚空契约（对数曲线：floor(2 * ln(stage + 1))）
    local voidPact = math.floor(2 * math.log(stageNum + 1))
    if voidPact > 0 then
        Currency.Add("void_pact", voidPact)
    end

    -- 开服好礼任务追踪
    local ok, LGD = pcall(require, "Game.LaunchGiftData")
    if ok and LGD then LGD.AddProgress("stage", 1) end

    -- 每日任务追踪（通关 + 战斗）
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then
        DTD.AddProgress("stage", 1)
        DTD.AddProgress("battle", 1)
    end

    print("[CampaignSettlement] Stage " .. stageNum .. " clear! void_pact +" .. voidPact)

    return {
        stageNum = stageNum,
        score    = score,
        voidPact = voidPact,
    }
end

-- ============================================================================
-- 失败处理
-- ============================================================================

--- 失败统计：记录任务进度（无奖励）
---@param stageNum number 关卡编号
---@param wave number 失败时的波次
function CS.SettleGameOver(stageNum, wave)
    -- 每日任务追踪（战斗失败也计为一次战斗）
    local ok2, DTD = pcall(require, "Game.DailyTaskData")
    if ok2 and DTD then DTD.AddProgress("battle", 1) end

    print("[CampaignSettlement] Stage " .. stageNum .. " failed at wave " .. wave)
end

return CS
