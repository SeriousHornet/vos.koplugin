--[[
Helpers to draw VOS's own SVG icons straight from the plugin's
resources/ folder, instead of relying on IconWidget's name resolution
(which only finds icons copied into koreader's root icons/ dir).
]]

local lfs = require("libs/libkoreader-lfs")

-- This file lives at <plugin_root>/modules/, so walk up one level to find
-- the plugin's own resources/ directory.
local MODULE_DIR = debug.getinfo(1, "S").source:match("^@(.+[/\\])[^/\\]+$") or "./"
local VOS_RESOURCE_DIR =
    (MODULE_DIR:match("^(.*)[/\\]modules[/\\]$") or MODULE_DIR:sub(1, -2)) ..
    "/resources/"

-- Return the absolute path of <name>.svg inside resources/ if it exists,
-- nil otherwise (so IconWidget falls back to name resolution / defaults).
local function iconFile(name)
    local path = VOS_RESOURCE_DIR .. name .. ".svg"
    if lfs.attributes(path, "mode") == "file" then
        return path
    end
    return nil
end

-- Build the IconWidget options for a VOS icon: explicit `file` wins,
-- `icon` remains set as fallback and for any name-based patching.
local function icon(name)
    return {icon = name, file = iconFile(name)}
end

return {
    resourceDir = VOS_RESOURCE_DIR,
    iconFile = iconFile,
    icon = icon,
}
