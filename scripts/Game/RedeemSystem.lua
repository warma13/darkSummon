--- 兑换码系统
--- 负责兑换码的查找、验证、执行
local HeroData = require("Game.HeroData")
local SlotSave = require("Game.SlotSaveSystem")
local Toast    = require("Game.Toast")

local REDEEM_CODES = require("Game.Config_RedeemCodes")

local RedeemSystem = {}

--- 尝试兑换一个兑换码
---@param codeStr string 用户输入的兑换码
---@return boolean success
function RedeemSystem.TryRedeem(codeStr)
    local code = (codeStr or ""):match("^%s*(.-)%s*$")  -- trim
    if code == "" then
        Toast.Show("请输入兑换码")
        return false
    end
    code = code:upper()  -- 统一大写比对

    -- 查找匹配的兑换码
    local found = nil
    for _, def in ipairs(REDEEM_CODES) do
        if def.code == code then
            found = def
            break
        end
    end
    if not found then
        Toast.Show("无效的兑换码")
        return false
    end

    -- 检查用户限制
    if found.allowedUser then
        local myId = clientCloud and clientCloud.userId
        if not myId or tostring(myId) ~= tostring(found.allowedUser) then
            Toast.Show("该兑换码不属于当前账号")
            return false
        end
    end

    -- 检查是否已使用
    if not HeroData.redeemData then HeroData.redeemData = {} end
    if HeroData.redeemData[found.code] then
        Toast.Show("该兑换码已使用过")
        return false
    end

    -- 执行奖励
    found.reward()
    HeroData.redeemData[found.code] = true
    SlotSave.MarkDirty()
    Toast.Show(found.desc .. " 兑换成功!")
    return true
end

return RedeemSystem
