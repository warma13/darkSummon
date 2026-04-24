-- Game/Renderer.lua
-- 暗黑塔防游戏 - NanoVG 渲染系统（门面模块）
-- 子模块: Renderer_Utils, Renderer_Towers, Renderer_Draw

local LootDrop = require("Game.LootDrop")

local Renderer = {}

-- NanoVG 上下文（由 main.lua 设置）
Renderer.vg = nil
Renderer.fontId = -1
Renderer.gridOffsetX = 0
Renderer.gridOffsetY = 0

-- 共享上下文（子模块间传递状态和工具函数）
local ctx = {}

-- 加载子模块（顺序重要：Utils → Towers → Draw）
require("Game.Renderer_Utils")(Renderer, ctx)
require("Game.Renderer_Towers")(Renderer, ctx)
require("Game.Renderer_Draw")(Renderer, ctx)

--- 主渲染函数
function Renderer.Render(vg, width, height)
    -- 更新暗影君主漂浮动画时间
    ctx.spriteFloatTime = ctx.spriteFloatTime + (1.0 / 60.0)

    -- 确保粒子纹理已加载
    ctx.EnsureParticleTextures(vg)

    -- 更新 debuff 粒子
    ctx.UpdateDebuffParticles(1.0 / 60.0)

    local ox = Renderer.gridOffsetX
    local oy = Renderer.gridOffsetY

    -- 1. 背景
    Renderer.DrawBackground(vg, width, height)

    -- 2. 路径
    Renderer.DrawPath(vg, ox, oy)

    -- 3. 网格
    Renderer.DrawGrid(vg, ox, oy)

    -- 4. 怪物数量指示器（网格上方）
    Renderer.DrawEnemyCount(vg, ox, oy)

    -- 4. 塔
    Renderer.DrawTowers(vg, ox, oy)

    -- 5. 敌人
    Renderer.DrawEnemies(vg)

    -- 6. 弹道
    Renderer.DrawProjectiles(vg)

    -- 7. 粒子
    Renderer.DrawParticles(vg)

    -- 7.5 掉落物（光柱+图标+飞行）
    LootDrop.Draw(vg)

    -- 8. 飘字
    Renderer.DrawFloatingTexts(vg)

    -- 9. 合成闪光
    Renderer.DrawMergeFlash(vg, ox, oy)

    -- 10. 拖拽视觉反馈
    Renderer.DrawDragOverlay(vg, ox, oy)

    -- 11. 技能闪光（最上层）
    Renderer.DrawSkillFlash(vg, width, height)

    -- 11.5 翠影秘境 BOSS 技能特效（施法描边、沉默冲击环、护盾光环）
    Renderer.DrawEmeraldBossSkillFX(vg, width, height)

    -- 11.6 憎恨之躯 BOSS 技能特效（3×3践踏区域、韧性条、嘲讽/壁垒光环）
    Renderer.DrawHatredBossSkillFX(vg, width, height)

    -- 12. BOSS 倒计时 + 血条（HUD 层）
    Renderer.DrawBossBar(vg, width)

    -- 13. BOSS 出场动画（最上层覆盖）
    Renderer.DrawBossIntro(vg, width, height)
end

return Renderer
