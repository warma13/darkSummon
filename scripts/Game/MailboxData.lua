-- Game/MailboxData.lua
-- 邮件系统：存储待领取的奖励邮件

local HeroData = require("Game.HeroData")
local Currency = require("Game.Currency")
local SaveRegistry = require("Game.SaveRegistry")

local MailboxData = {}

-- ============================================================================
-- 数据访问
-- ============================================================================

--- 确保数据结构存在
---@return table[]
function MailboxData.EnsureData()
    if not HeroData.mailboxData then
        HeroData.mailboxData = {}
    end
    return HeroData.mailboxData
end

--- 添加一封邮件
---@param mail { title:string, desc:string, rewards:{type:string,id:string,amount:number}[], timestamp?:number }
function MailboxData.Add(mail)
    local mails = MailboxData.EnsureData()
    mail.timestamp = mail.timestamp or os.time()
    mail.claimed = false
    table.insert(mails, 1, mail)  -- 新邮件在最前面
    -- 限制最多 50 封
    while #mails > 50 do
        table.remove(mails)
    end
end

--- 获取所有邮件
---@return table[]
function MailboxData.GetAll()
    return MailboxData.EnsureData()
end

--- 获取未领取邮件数
---@return number
function MailboxData.GetUnclaimedCount()
    local mails = MailboxData.EnsureData()
    local count = 0
    for _, m in ipairs(mails) do
        if not m.claimed then count = count + 1 end
    end
    return count
end

--- 是否有未领取邮件（红点）
---@return boolean
function MailboxData.HasUnclaimed()
    return MailboxData.GetUnclaimedCount() > 0
end

--- 领取单封邮件
---@param index number
---@return boolean success, string msg
function MailboxData.Claim(index)
    local mails = MailboxData.EnsureData()
    local mail = mails[index]
    if not mail then return false, "邮件不存在" end
    if mail.claimed then return false, "已领取" end

    mail.claimed = true
    if mail.rewards then
        Currency.GrantRewards(mail.rewards)
    end
    HeroData.Save()
    return true, "领取成功"
end

--- 一键领取所有
---@return number claimedCount
function MailboxData.ClaimAll()
    local mails = MailboxData.EnsureData()
    local count = 0
    for _, m in ipairs(mails) do
        if not m.claimed and m.rewards then
            m.claimed = true
            Currency.GrantRewards(m.rewards)
            count = count + 1
        end
    end
    if count > 0 then HeroData.Save() end
    return count
end

--- 发送一次性系统邮件（防重复：相同 id 只发一次）
---@param id string  唯一标识符
---@param mail table  邮件内容
function MailboxData.SendOnce(id, mail)
    local mails = MailboxData.EnsureData()
    mails._sentIds = mails._sentIds or {}
    if mails._sentIds[id] then return end
    MailboxData.Add(mail)
    mails._sentIds[id] = true
    HeroData.Save()
    print("[MailboxData] SendOnce: " .. id)
end

--- 清理已领取邮件
function MailboxData.ClearClaimed()
    local mails = MailboxData.EnsureData()
    local i = 1
    while i <= #mails do
        if mails[i].claimed then
            table.remove(mails, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- SaveRegistry 自注册
-- ============================================================================
SaveRegistry.Register("mailboxData", {
    group = "meta_game",
    order = 70,
    serialize = function()
        return HeroData.mailboxData
    end,
    deserialize = function(saved, _saveData)
        HeroData.mailboxData = saved or nil
        -- 一次性补偿邮件（id 固定，不会重复发送）
        MailboxData.SendOnce("comp_20260419_signin_reset", {
            title = "签到补偿",
            desc = "因系统问题导致签到天数异常，附上暗影精粹×500作为补偿，感谢您的支持！",
            rewards = {
                { type = "currency", id = "shadow_essence", amount = 500 },
            },
        })
        MailboxData.SendOnce("update_20260420_v1031", {
            title = "v1.0.31 更新奖励",
            desc = "感谢您的持续支持！本次更新带来了多项体验优化，请收下这份奖励。",
            rewards = {
                { type = "item", id = "shadow_essence_bag", amount = 3 },
                { type = "item", id = "nether_crystal_pack", amount = 3 },
            },
        })
        MailboxData.SendOnce("comp_20260423_boss_difficulty", {
            title = "世界BOSS难度系统上线补偿",
            desc = "世界BOSS难度系统正式上线！为感谢各位召唤师的支持，附上深渊主宰挑战券×2，祝您挑战顺利！",
            rewards = {
                { type = "item", id = "boss_ticket", amount = 2 },
            },
        })
        MailboxData.SendOnce("comp_20260423_server_compensation", {
            title = "全服补偿",
            desc = "亲爱的召唤师，感谢您的支持与理解，附上补偿奖励，请注意查收！",
            rewards = {
                { type = "currency", id = "void_pact", amount = 20 },
                { type = "currency", id = "shadow_essence", amount = 1000 },
                { type = "item", id = "boss_ticket", amount = 1 },
            },
        })
        MailboxData.SendOnce("comp_20260425_v1063", {
            title = "v1.0.63 更新补偿",
            desc = "亲爱的召唤师，本次更新修复了遗物和憎恨之地相关问题，附上补偿奖励，感谢您的支持！",
            rewards = {
                { type = "item", id = "hatred_ticket", amount = 2 },
                { type = "currency", id = "shadow_essence", amount = 1000 },
                { type = "item", id = "recruit_ticket_select_box", amount = 10 },
            },
        })

        MailboxData.SendOnce("comp_20260429_resource_gift", {
            title = "资源补给礼包",
            desc = "亲爱的召唤师，附上藏书阁挑战券与精粹资源，助您提升实力，请注意查收！",
            rewards = {
                { type = "item", id = "dungeon_ticket_skill_book", amount = 6 },
                { type = "currency", id = "shadow_essence", amount = 2000 },
                { type = "currency", id = "pale_jade", amount = 2000 },
            },
        })

        -- ── 一次性重置所有技能标签为0 ──
        do
            local mails = MailboxData.EnsureData()
            mails._sentIds = mails._sentIds or {}
            if not mails._sentIds["reset_skill_tags_20260429"] then
                HeroData.skillTags = {}
                mails._sentIds["reset_skill_tags_20260429"] = true
                HeroData.Save()
                print("[MailboxData] Reset all skill tags to 0")
            end
        end

        -- ── 社区英雄设计活动奖励（按用户ID定向发放）──
        local myId = clientCloud and clientCloud.userId and tostring(clientCloud.userId) or ""

        -- 参与奖
        local participantIds = {
            ["346333596"] = true,
            ["1211202246"] = true,
            ["1366174619"] = true,
            ["1840951947"] = true,
            ["293191593"] = true,
        }
        if participantIds[myId] then
            MailboxData.SendOnce("event_hero_design_participant", {
                title = "英雄设计活动·参与奖",
                desc = "感谢您参与社区英雄设计活动！附上参与奖励，请注意查收。",
                rewards = {
                    { type = "currency", id = "linyan_oath", amount = 40 },
                    { type = "currency", id = "shadow_essence", amount = 5000 },
                    { type = "fragment", id = "eternal_archfiend", amount = 10 },
                    { type = "title", id = "hero_designer" },
                },
            })
        end

        -- 测试账号：发放两个称号
        if myId == "1779057459" then
            MailboxData.SendOnce("test_hero_design_titles", {
                title = "英雄设计活动·称号发放",
                desc = "发放英雄设计师 & 优秀英雄设计师两个称号。",
                rewards = {
                    { type = "title", id = "hero_designer" },
                    { type = "title", id = "hero_designer_ex" },
                },
            })
        end

        -- 优秀设计奖
        local excellentIds = {
            ["1005540212"] = true,
            ["2135680770"] = true,
        }
        if excellentIds[myId] then
            MailboxData.SendOnce("event_hero_design_excellent", {
                title = "英雄设计活动·优秀设计奖",
                desc = "恭喜您荣获社区英雄设计活动优秀设计奖！附上丰厚奖励，请注意查收。",
                rewards = {
                    { type = "currency", id = "linyan_oath", amount = 400 },
                    { type = "currency", id = "shadow_essence", amount = 50000 },
                    { type = "fragment", id = "eternal_archfiend", amount = 100 },
                    { type = "title", id = "hero_designer_ex" },
                },
            })
        end
    end,
})

return MailboxData
