-- Game/Config.lua
-- 暗黑塔防游戏 - 全局配置常量（门面模块）

local Config = {}

require("Game.Config_Core")(Config)
require("Game.Config_Enemies")(Config)
require("Game.Config_Heroes")(Config)
require("Game.Config_Meta")(Config)
require("Game.Config_Balance")(Config)
require("Game.Config_Relics")(Config)

return Config
