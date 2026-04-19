-- Game/SaveManager.lua
-- 本地存档管理（File + cjson）

---@diagnostic disable: undefined-global

local SaveManager = {}

local SAVE_FILE = "hero_save.json"

--- 保存数据到本地文件
---@param data table
---@return boolean
function SaveManager.Save(data)
    local ok, jsonStr = pcall(cjson.encode, data)
    if not ok then
        print("[SaveManager] Encode failed: " .. tostring(jsonStr))
        return false
    end

    local file = File(SAVE_FILE, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[SaveManager] Failed to open file for write")
        return false
    end
    file:WriteString(jsonStr)
    file:Close()
    print("[SaveManager] Saved successfully")
    return true
end

--- 从本地文件读取数据
---@return table|nil
function SaveManager.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        print("[SaveManager] No save file found")
        return nil
    end

    local file = File(SAVE_FILE, FILE_READ)
    if not file or not file:IsOpen() then
        print("[SaveManager] Failed to open file for read")
        return nil
    end

    local jsonStr = file:ReadString()
    file:Close()

    if not jsonStr or jsonStr == "" then
        print("[SaveManager] Empty save file")
        return nil
    end

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok then
        print("[SaveManager] Decode failed: " .. tostring(data))
        return nil
    end

    print("[SaveManager] Loaded successfully")
    return data
end

--- 删除存档
function SaveManager.Delete()
    if fileSystem:FileExists(SAVE_FILE) then
        -- 写入空内容覆盖
        local file = File(SAVE_FILE, FILE_WRITE)
        if file and file:IsOpen() then
            file:WriteString("")
            file:Close()
        end
        print("[SaveManager] Save deleted")
    end
end

--- 检查存档是否存在
---@return boolean
function SaveManager.Exists()
    return fileSystem:FileExists(SAVE_FILE)
end

return SaveManager
