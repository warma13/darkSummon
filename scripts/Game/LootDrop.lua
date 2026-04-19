-- Game/LootDrop.lua
-- 掉落物模块：敌人死亡后生成地面掉落物 → 光柱+图标 → 飞向货币栏 → 加数值

local Config = require("Game.Config")
local State = require("Game.State")
local Currency = require("Game.Currency")

local LootDrop = {}

-- 掉落物配置
local STAY_TIME = 0.5    -- 地面停留时间
local FLY_TIME  = 0.5    -- 飞行时间
local PILLAR_HEIGHT = 60 -- 光柱高度
local ICON_SIZE = 20     -- 图标大小
local SCATTER_RANGE = 20 -- 随机散布范围

-- NanoVG 图片缓存
local imageCache = {}

--- 加载货币图片
---@param vg userdata
---@param currType string
---@return number  NanoVG image handle, 0 if failed
local function LoadCurrencyImage(vg, currType)
    if imageCache[currType] then return imageCache[currType] end
    local def = Config.CURRENCY[currType]
    if def and def.image then
        local img = nvgCreateImage(vg, def.image, 0)
        imageCache[currType] = img
        return img
    end
    imageCache[currType] = 0
    return 0
end

--- 生成掉落物
---@param currType string  货币类型 "nether_crystal" / "devour_stone" / "forge_iron"
---@param amount number    数量
---@param x number         屏幕坐标X（敌人死亡位置）
---@param y number         屏幕坐标Y
function LootDrop.Spawn(currType, amount, x, y)
    if amount <= 0 then return end

    local def = Config.CURRENCY[currType]
    if not def then return end

    -- 随机偏移，多个掉落物不重叠
    local ox = (math.random() - 0.5) * SCATTER_RANGE
    local oy = (math.random() - 0.5) * SCATTER_RANGE * 0.5

    -- 飞行目标
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local targetX, targetY
    if currType == "dark_soul" then
        -- 暗魂飞向底部左侧暗魂图标 (bottomBar: bottom=4, left=16)
        targetX = 40
        targetY = screenH - 30
    else
        -- 其他货币飞向右侧货币栏
        targetX = screenW - 40
        targetY = screenH * 0.30 + 10
    end

    -- 出现延迟：同一敌人多个掉落错开
    local delay = math.random() * 0.15

    -- 暗魂掉落更快（boss每秒都在掉），其他掉落正常节奏
    local stayT = (currType == "dark_soul") and 0.25 or STAY_TIME
    local flyT  = (currType == "dark_soul") and 0.4  or FLY_TIME

    local drop = {
        type     = currType,
        amount   = amount,
        color    = def.color,
        -- 位置
        x        = x + ox,
        y        = y + oy,
        startX   = x + ox,
        startY   = y + oy,
        targetX  = targetX,
        targetY  = targetY,
        -- 时间
        elapsed  = 0,
        delay    = delay,
        stayTime = stayT,
        flyTime  = flyT,
        -- 状态
        collected = false,
    }

    State.lootDrops[#State.lootDrops + 1] = drop
end

--- 更新所有掉落物
---@param dt number
function LootDrop.Update(dt)
    for i = #State.lootDrops, 1, -1 do
        local d = State.lootDrops[i]
        d.elapsed = d.elapsed + dt

        local t = d.elapsed - d.delay
        if t < 0 then
            -- 还在延迟中
        elseif t < d.stayTime then
            -- 阶段1: 停留，不移动
        elseif t < d.stayTime + d.flyTime then
            -- 阶段2: 飞行
            local flyT = (t - d.stayTime) / d.flyTime
            -- ease-in-out: 先慢后快再慢
            local eased = flyT * flyT * (3 - 2 * flyT)
            d.x = d.startX + (d.targetX - d.startX) * eased
            -- 抛物线弧度：中间点向上偏移
            local arcHeight = -40
            local arc = 4 * arcHeight * flyT * (1 - flyT)
            d.y = d.startY + (d.targetY - d.startY) * eased + arc
        else
            -- 到达目标，发放货币
            if not d.collected then
                if d.type == "dark_soul" then
                    Currency.CollectDarkSoul(d.amount)
                else
                    Currency.Add(d.type, d.amount)
                end
                d.collected = true
            end
            table.remove(State.lootDrops, i)
        end
    end
end

--- 渲染所有掉落物（NanoVG）
---@param vg userdata
function LootDrop.Draw(vg)
    for _, d in ipairs(State.lootDrops) do
        local t = d.elapsed - d.delay
        if t < 0 then goto continue end

        local r, g, b = d.color[1], d.color[2], d.color[3]
        local alpha = 255

        if t < d.stayTime then
            -- 阶段1: 停留 — 光柱 + 图标
            local stayProgress = t / d.stayTime

            -- 弹跳出现（前0.15秒）
            local iconScale = 1.0
            if t < 0.15 then
                local pop = t / 0.15
                iconScale = 1.0 + 0.3 * math.sin(pop * math.pi)
            end

            -- 光柱：向上渐变光束，呼吸闪烁
            local breath = 0.6 + 0.4 * math.sin(t * 8)
            local pillarAlpha = breath * 180

            -- 光柱渐变（从底部到顶部透明）
            local px = d.x
            local py = d.y
            local pillarH = PILLAR_HEIGHT * (0.5 + 0.5 * stayProgress)
            local pillarW = 8

            local topPaint = nvgLinearGradient(vg,
                px, py, px, py - pillarH,
                nvgRGBA(r, g, b, math.floor(pillarAlpha)),
                nvgRGBA(r, g, b, 0))
            nvgBeginPath(vg)
            nvgRect(vg, px - pillarW / 2, py - pillarH, pillarW, pillarH)
            nvgFillPaint(vg, topPaint)
            nvgFill(vg)

            -- 底部光晕
            local glowPaint = nvgRadialGradient(vg,
                px, py, 2, 16,
                nvgRGBA(r, g, b, math.floor(pillarAlpha * 0.6)),
                nvgRGBA(r, g, b, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, 16)
            nvgFillPaint(vg, glowPaint)
            nvgFill(vg)

            -- 图标（货币图片）
            local imgSize = ICON_SIZE * iconScale
            local img = LoadCurrencyImage(vg, d.type)
            if img and img > 0 then
                local imgPaint = nvgImagePattern(vg,
                    px - imgSize / 2, py - imgSize - 4 - imgSize / 2 + imgSize / 2,
                    imgSize, imgSize, 0, img, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, px - imgSize / 2, py - imgSize - 4, imgSize, imgSize, 3)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                -- Fallback: 圆形图标
                nvgBeginPath(vg)
                nvgCircle(vg, px, py - ICON_SIZE / 2 - 4, imgSize / 2)
                nvgFillColor(vg, nvgRGBA(r, g, b, 220))
                nvgFill(vg)
            end

        else
            -- 阶段2: 飞行
            local flyT = (t - d.stayTime) / d.flyTime
            -- 缩小 + 淡出
            local scale = 1.0 - flyT * 0.6
            alpha = math.floor(255 * (1.0 - flyT * 0.5))
            local imgSize = ICON_SIZE * scale

            -- 拖尾光效
            if flyT < 0.8 then
                local trailPaint = nvgRadialGradient(vg,
                    d.x, d.y, 2, 12 * scale,
                    nvgRGBA(r, g, b, math.floor(alpha * 0.4)),
                    nvgRGBA(r, g, b, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, d.x, d.y, 12 * scale)
                nvgFillPaint(vg, trailPaint)
                nvgFill(vg)
            end

            -- 飞行中的图标
            local img = LoadCurrencyImage(vg, d.type)
            if img and img > 0 then
                local imgPaint = nvgImagePattern(vg,
                    d.x - imgSize / 2, d.y - imgSize / 2,
                    imgSize, imgSize, 0, img, alpha / 255)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, d.x - imgSize / 2, d.y - imgSize / 2, imgSize, imgSize, 2)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgCircle(vg, d.x, d.y, imgSize / 2)
                nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
                nvgFill(vg)
            end
        end

        ::continue::
    end
end

--- 立即结算所有未收集的掉落物（切关卡前调用，防止丢失奖励）
function LootDrop.CollectAll()
    for i = #State.lootDrops, 1, -1 do
        local d = State.lootDrops[i]
        if not d.collected then
            Currency.Add(d.type, d.amount)
            d.collected = true
        end
    end
    State.lootDrops = {}
end

--- 清理图片缓存
function LootDrop.ClearCache()
    imageCache = {}
end

return LootDrop
