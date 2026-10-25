--[[ Helpers to draw VOS's own SVG icons straight from the plugin's resources.
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local MODULE_DIR = debug.getinfo(1, "S").source:match("^@(.+[/\\])[^/\\]+$") or "./"
local VOS_RESOURCE_DIR = (MODULE_DIR:match("^(.*)[/\\]modules[/\\]$") or MODULE_DIR:sub(1, -2)) .. "/resources/"
local icon_files = {}

local function userIconFile(name)
    if not name or name == "" then
        return
    end
    local base = DataStorage:getDataDir() .. "/icons/" .. name
    if name:match("%.svg$") or name:match("%.png$") then
        return lfs.attributes(base, "mode") == "file" and base or nil
    end
    for __, extension in ipairs { ".svg", ".png" } do
        local path = base .. extension
        if lfs.attributes(path, "mode") == "file" then
            return path
        end
    end
end

local function iconFile(name)
    if icon_files[name] ~= nil then
        return icon_files[name] or nil
    end
    local path = VOS_RESOURCE_DIR .. name .. ".svg"
    if lfs.attributes(path, "mode") == "file" then
        icon_files[name] = path
        return path
    end
    path = VOS_RESOURCE_DIR .. "extra/" .. name .. ".svg"
    if lfs.attributes(path, "mode") == "file" then
        icon_files[name] = path
        return path
    end
    icon_files[name] = false
    return nil
end

local function icon(name, extra)
    local o = { icon = name, file = iconFile(name), alpha = true }
    if extra then
        for k, v in pairs(extra) do
            o[k] = v
        end
    end
    return o
end

return {
    resourceDir = VOS_RESOURCE_DIR,
    userIconFile = userIconFile,
    iconFile = iconFile,
    icon = icon,
}
