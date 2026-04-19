-- Game/AudioManager.lua
-- 音频管理模块：统一管理 BGM 和音效的播放、音量、静音

---@diagnostic disable: undefined-global
local cjson = cjson  -- 引擎内置全局变量
---@diagnostic enable: undefined-global

local AudioManager = {}

-- ============================================================
-- 配置：所有音频资源路径
-- ============================================================
local BGM = {
    main = "audio/music.ogg",
}

local SFX = {
    click       = "audio/sfx/sfx_click.ogg",
    click_tab   = "audio/sfx/click_tab.ogg",
    click_btn   = "audio/sfx/click_button.ogg",
    chest_open  = "audio/sfx/sfx_chest_open.ogg",
    recruit     = "audio/sfx/sfx_recruit.ogg",
    upgrade     = "audio/sfx/sfx_upgrade.ogg",
    deploy      = "audio/sfx/sfx_deploy.ogg",
    merge       = "audio/sfx/sfx_merge.ogg",
    wave_start  = "audio/sfx/sfx_wave_start.ogg",
    victory     = "audio/sfx/sfx_victory.ogg",
    defeat      = "audio/sfx/sfx_defeat.ogg",
    coin        = "audio/sfx/sfx_coin.ogg",
    attack      = "audio/sfx/sfx_attack.ogg",
    enemy_hit   = "audio/sfx/sfx_enemy_hit.ogg",
}

-- ============================================================
-- 内部状态
-- ============================================================
---@type Node
local bgmNode = nil
---@type SoundSource
local bgmSource = nil
---@type string
local currentBgmKey = ""

local sfxCache = {}     -- { key -> Sound }  预加载缓存

local settings = {
    bgmVolume  = 0.5,   -- BGM 音量 0~1
    sfxVolume  = 0.7,   -- 音效音量 0~1
    bgmMuted   = false,
    sfxMuted   = false,
}

---@type Scene
local sceneRef = nil

local SETTINGS_FILE = "audio_settings.json"

-- ============================================================
-- 持久化
-- ============================================================

--- 从本地文件加载音量设置
local function LoadSettings()
    if not fileSystem:FileExists(SETTINGS_FILE) then return end
    local f = File:new(SETTINGS_FILE, FILE_READ)
    if f:IsOpen() then
        local content = f:ReadString()
        f:Close()
        local ok, data = pcall(cjson.decode, content)
        if ok and type(data) == "table" then
            if data.bgmVolume  ~= nil then settings.bgmVolume  = data.bgmVolume end
            if data.sfxVolume  ~= nil then settings.sfxVolume  = data.sfxVolume end
            if data.bgmMuted   ~= nil then settings.bgmMuted   = data.bgmMuted end
            if data.sfxMuted   ~= nil then settings.sfxMuted   = data.sfxMuted end
        end
    else
        f:Close()
    end
end

--- 保存音量设置到本地文件
local function SaveSettings()
    local f = File:new(SETTINGS_FILE, FILE_WRITE)
    if f:IsOpen() then
        f:WriteString(cjson.encode({
            bgmVolume = settings.bgmVolume,
            sfxVolume = settings.sfxVolume,
            bgmMuted  = settings.bgmMuted,
            sfxMuted  = settings.sfxMuted,
        }))
        f:Close()
    end
end

-- ============================================================
-- 初始化
-- ============================================================

--- 获取音频场景（供外部 Update 驱动）
---@return Scene|nil
function AudioManager.GetScene()
    return sceneRef
end

--- 每帧更新（驱动音频场景，使 autoRemoveMode 生效）
---@param dt number
function AudioManager.Update(dt)
    if sceneRef then
        sceneRef:Update(dt)
    end
end

--- 初始化音频管理器（在 Start 中调用一次，自动创建内部 Scene）
function AudioManager.Init()
    -- 加载已保存的音量设置
    LoadSettings()

    -- 创建专用音频 Scene（纯 2D 游戏没有 3D scene）
    sceneRef = Scene()

    -- 创建 BGM 播放节点
    bgmNode = sceneRef:CreateChild("BGMNode")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = "Music"
    bgmSource.gain = settings.bgmVolume

    -- 设置主音量
    audio:SetMasterGain("Music", settings.bgmMuted and 0 or 1)
    audio:SetMasterGain("Effect", settings.sfxMuted and 0 or 1)

    -- 预加载所有音效
    local count = 0
    for key, path in pairs(SFX) do
        local snd = cache:GetResource("Sound", path)
        if snd then
            sfxCache[key] = snd
            count = count + 1
        else
            print("[AudioManager] Warning: SFX not found: " .. path)
        end
    end

    print("[AudioManager] Init OK, " .. count .. " sfx loaded")
end

-- ============================================================
-- BGM 控制
-- ============================================================

--- 播放 BGM（循环）
---@param key string|nil  BGM 名称（默认 "main"）
function AudioManager.PlayBGM(key)
    key = key or "main"
    if currentBgmKey == key and bgmSource and bgmSource.playing then
        return -- 已在播放
    end

    local path = BGM[key]
    if not path then
        print("[AudioManager] Unknown BGM: " .. key)
        return
    end

    local snd = cache:GetResource("Sound", path)
    if not snd then
        print("[AudioManager] BGM resource not found: " .. path)
        return
    end

    snd.looped = true
    bgmSource.gain = settings.bgmVolume
    bgmSource:Play(snd)
    currentBgmKey = key
end

--- 停止 BGM
function AudioManager.StopBGM()
    if bgmSource then
        bgmSource:Stop()
    end
    currentBgmKey = ""
end

--- 设置 BGM 音量
---@param vol number 0~1
function AudioManager.SetBGMVolume(vol)
    settings.bgmVolume = math.max(0, math.min(1, vol))
    if bgmSource then
        bgmSource.gain = settings.bgmVolume
    end
    SaveSettings()
end

--- 获取 BGM 音量
---@return number
function AudioManager.GetBGMVolume()
    return settings.bgmVolume
end

--- 静音/取消静音 BGM
---@param muted boolean
function AudioManager.SetBGMMuted(muted)
    settings.bgmMuted = muted
    audio:SetMasterGain("Music", muted and 0 or 1)
    SaveSettings()
end

---@return boolean
function AudioManager.IsBGMMuted()
    return settings.bgmMuted
end

-- ============================================================
-- 音效控制
-- ============================================================

--- 播放音效
---@param key string  音效名称（见 SFX 表）
---@param gain number|nil  音量覆盖（默认使用全局音效音量）
function AudioManager.PlaySFX(key, gain)
    if settings.sfxMuted then return end

    local snd = sfxCache[key]
    if not snd then
        -- 尝试动态加载
        local path = SFX[key]
        if path then
            snd = cache:GetResource("Sound", path)
            if snd then sfxCache[key] = snd end
        end
    end

    if not snd then
        print("[AudioManager] Unknown SFX: " .. tostring(key))
        return
    end

    local vol = gain or settings.sfxVolume

    -- 每次播放创建临时节点，播完自动移除
    local sfxNode = sceneRef:CreateChild("SFX")
    local src = sfxNode:CreateComponent("SoundSource")
    src.soundType = "Effect"
    src.gain = vol
    src.autoRemoveMode = REMOVE_NODE
    src:Play(snd)
end

--- 设置音效音量
---@param vol number 0~1
function AudioManager.SetSFXVolume(vol)
    settings.sfxVolume = math.max(0, math.min(1, vol))
    SaveSettings()
end

--- 获取音效音量
---@return number
function AudioManager.GetSFXVolume()
    return settings.sfxVolume
end

--- 静音/取消静音音效
---@param muted boolean
function AudioManager.SetSFXMuted(muted)
    settings.sfxMuted = muted
    audio:SetMasterGain("Effect", muted and 0 or 1)
    SaveSettings()
end

---@return boolean
function AudioManager.IsSFXMuted()
    return settings.sfxMuted
end

-- ============================================================
-- 便捷方法（常用场景快捷调用）
-- ============================================================

function AudioManager.PlayClick()      AudioManager.PlaySFX("click") end
function AudioManager.PlayClickTab()   AudioManager.PlaySFX("click_tab", settings.sfxVolume * 6) end
function AudioManager.PlayClickBtn()   AudioManager.PlaySFX("click_btn") end
function AudioManager.PlayChestOpen()  AudioManager.PlaySFX("chest_open") end
function AudioManager.PlayRecruit()    AudioManager.PlaySFX("recruit") end
function AudioManager.PlayUpgrade()    AudioManager.PlaySFX("upgrade") end
function AudioManager.PlayDeploy()     AudioManager.PlaySFX("deploy") end
function AudioManager.PlayMerge()      AudioManager.PlaySFX("merge") end
function AudioManager.PlayWaveStart()  AudioManager.PlaySFX("wave_start") end
function AudioManager.PlayVictory()    AudioManager.PlaySFX("victory") end
function AudioManager.PlayDefeat()     AudioManager.PlaySFX("defeat") end
function AudioManager.PlayCoin()       AudioManager.PlaySFX("coin") end
function AudioManager.PlayAttack()     AudioManager.PlaySFX("attack") end
function AudioManager.PlayEnemyHit()   AudioManager.PlaySFX("enemy_hit") end

-- ============================================================
-- 全局静音
-- ============================================================

--- 全部静音
function AudioManager.MuteAll()
    AudioManager.SetBGMMuted(true)
    AudioManager.SetSFXMuted(true)
end

--- 取消全部静音
function AudioManager.UnmuteAll()
    AudioManager.SetBGMMuted(false)
    AudioManager.SetSFXMuted(false)
end

return AudioManager
