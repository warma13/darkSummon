-- Game/EventBus.lua
-- 游戏业务事件总线（轻量，无引擎依赖）
--
-- 解耦模块间的直接调用：
--   发布方  emit("currency.changed", { type, delta, balance })
--   订阅方  on("currency.changed", function(data) ... end)
--
-- 设计原则：
--   1. 零外部依赖，可被任意模块 require
--   2. emit 时遍历副本，防止回调内修改 listeners 导致跳过
--   3. on() 返回取消订阅函数，避免野指针

local EventBus = {}

-- listeners[event] = { fn, fn, ... }
local listeners = {}

--- 订阅事件
---@param event string    事件名，如 "currency.changed" / "data.saved"
---@param fn function     回调函数，接受一个 data table（可为 nil）
---@return function       调用此函数可取消订阅
function EventBus.on(event, fn)
    if not listeners[event] then listeners[event] = {} end
    local list = listeners[event]
    list[#list + 1] = fn
    return function()
        for i = 1, #list do
            if list[i] == fn then
                table.remove(list, i)
                return
            end
        end
    end
end

--- 发布事件（同步广播，回调按订阅顺序执行）
---@param event string   事件名
---@param data? table    附加数据（可省略）
function EventBus.emit(event, data)
    local list = listeners[event]
    if not list or #list == 0 then return end
    -- 遍历副本，防止回调内 on/off 修改原表
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        snapshot[i](data)
    end
end

--- 清除某事件的全部监听器（测试或场景切换时使用）
---@param event string
function EventBus.clear(event)
    listeners[event] = nil
end

--- 清除所有监听器
function EventBus.clearAll()
    listeners = {}
end

-- ============================================================================
-- 事件名常量（集中定义，避免拼写错误）
-- ============================================================================

EventBus.EVENT = {
    -- 货币变化（data: { type, delta, balance }）
    -- type    = 货币 ID，如 "dark_soul" / "nether_crystal"
    -- delta   = 本次变化量（正=增加 负=消耗 0=Set覆盖）
    -- balance = 变化后的余额
    CURRENCY_CHANGED = "currency.changed",

    -- 存档完成（data: { immediate }）
    -- 由 HeroData.Save() 发出，TabNav 等模块订阅后刷新红点
    DATA_SAVED = "data.saved",
}

return EventBus
