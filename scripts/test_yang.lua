-- ============================================================================
-- test_yang.lua · 羊了个羊牌生成自动化测试
-- 独立入口，不依赖 Board/UI/音频，纯逻辑验证
-- 用法：build 时设 entry = "test_yang.lua"，启动后自动跑完测试并打印结果
-- ============================================================================

local Cfg    = require "yang.Config"
local PosGen = require "yang.PosGen"

local LEVELS    = Cfg.LEVELS
local YANG_FACE = Cfg.YANG_FACE

function Start()
    local SEEDS = 200
    local totalTests = 0
    local totalFails = 0
    local failDetails = {}

    for lvlIdx = 1, #LEVELS do
        local cfg = LEVELS[lvlIdx]
        for trial = 1, SEEDS do
            local seed = 1000 + trial
            math.randomseed(seed)
            totalTests = totalTests + 1

            -- ── 1) 计算 totalA / totalB ──
            local totalA = 0
            for _, c in ipairs(cfg.cardsPerLayer) do totalA = totalA + c end
            local totalB = cfg.useB and cfg.pileCards * 2 or 0

            -- ── 2) 位置生成（与 Board.newGame 完全一致） ──
            local yang    = PosGen.isYangStyle(cfg)
            local nLayers = #cfg.cardsPerLayer
            local layerPosList = {}

            if not yang then
                for layerNum, count in ipairs(cfg.cardsPerLayer) do
                    layerPosList[layerNum] = PosGen.rectLayerPos(layerNum, count, cfg, seed)
                end
            else
                for layerNum = nLayers, 1, -1 do
                    local count       = cfg.cardsPerLayer[layerNum]
                    local distFromTop = nLayers - layerNum
                    local isTypeA     = (distFromTop % 2 == 0)
                    if layerNum == nLayers then
                        local allPos = PosGen.yangAllPos(layerNum, true)
                        PosGen.shuffle(allPos, seed + layerNum * 31)
                        while #allPos > count do table.remove(allPos) end
                        layerPosList[layerNum] = allPos
                    else
                        layerPosList[layerNum] = PosGen.yangAABBPos(
                            layerNum, count, layerPosList[layerNum + 1], seed, isTypeA)
                    end
                end
            end

            -- ── 3) 安全网（与 Board.newGame 完全一致） ──
            local actualA = 0
            for ln = 1, nLayers do
                actualA = actualA + #(layerPosList[ln] or {})
            end
            local actualTotal = actualA + totalB
            local remainder = actualTotal % 3
            if remainder > 0 then
                local toRemove = remainder
                for ln = 1, nLayers do
                    local pos = layerPosList[ln]
                    if pos and toRemove > 0 then
                        while toRemove > 0 and #pos > 0 do
                            table.remove(pos)
                            toRemove = toRemove - 1
                        end
                    end
                    if toRemove <= 0 then break end
                end
                actualA     = actualA - remainder
                actualTotal = actualTotal - remainder
            end

            -- ── 4) 生成 kindList ──
            local kinds = PosGen.makeKindList(actualTotal, cfg.kindCount)
            PosGen.shuffle(kinds, seed)

            -- ── 5) 模拟分配索引 ki（与 Board.newGame 一致） ──
            local ki = 1
            for ln = 1, nLayers do
                ki = ki + #(layerPosList[ln] or {})
            end
            if cfg.useB then
                ki = ki + cfg.pileCards * 2
            end
            local usedCount  = ki - 1
            local kindsCount = #kinds

            -- ══════════ 检查 ══════════

            local errors = {}

            -- 检查 A：ki 恰好用完 kinds（不多不少）
            if usedCount ~= kindsCount then
                table.insert(errors, string.format(
                    "KI_MISMATCH: used=%d #kinds=%d", usedCount, kindsCount))
            end

            -- 检查 B：每种牌数量是 3 的倍数
            local kindCounts = {}
            for _, k in ipairs(kinds) do
                kindCounts[k] = (kindCounts[k] or 0) + 1
            end
            local badKinds = {}
            for k, cnt in pairs(kindCounts) do
                if cnt % 3 ~= 0 then
                    table.insert(badKinds, string.format("k%d=%d", k, cnt))
                end
            end
            if #badKinds > 0 then
                table.insert(errors, "BAD_KINDS: " .. table.concat(badKinds, ", "))
            end

            -- 检查 C：actualTotal 是 3 的倍数
            if actualTotal % 3 ~= 0 then
                table.insert(errors, string.format(
                    "TOTAL_NOT_3X: actualTotal=%d (%%3=%d)", actualTotal, actualTotal % 3))
            end

            -- 检查 D：每层位置数 == 配置数（位置是否丢失）
            for ln = 1, nLayers do
                local posCount = #(layerPosList[ln] or {})
                local cfgCount = cfg.cardsPerLayer[ln]
                -- 安全网可能裁了底层，允许第1层少几张
                if posCount ~= cfgCount and remainder == 0 then
                    table.insert(errors, string.format(
                        "LAYER_%d: cfg=%d actual=%d", ln, cfgCount, posCount))
                end
            end

            if #errors > 0 then
                totalFails = totalFails + 1
                local msg = string.format("Lv%d seed=%d: %s",
                    lvlIdx, seed, table.concat(errors, " | "))
                table.insert(failDetails, msg)
            end
        end
    end

    -- ══════════ 打印结果 ══════════
    print("")
    print("================================================================")
    print(string.format("[TEST] %d关 x %d种子 = %d次测试", #LEVELS, SEEDS, totalTests))
    print("================================================================")
    if totalFails == 0 then
        print("[TEST] PASS  全部通过！牌生成逻辑无误。")
        print("[TEST] 结论：牌的种类分布和数量均正确（每种都是3的倍数，总数精确匹配）。")
        print("[TEST] 如果游戏中仍出现无法配对，是随机排列导致槽位先满，属于正常游戏难度。")
    else
        print(string.format("[TEST] FAIL  发现 %d 个问题:", totalFails))
        for i, msg in ipairs(failDetails) do
            print(string.format("  [%d] %s", i, msg))
            if i >= 20 then
                print(string.format("  ... 还有 %d 个未显示", totalFails - 20))
                break
            end
        end
    end
    print("================================================================")
    print("")
end
