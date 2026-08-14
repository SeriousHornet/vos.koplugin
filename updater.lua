local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local TrapWidget = require("ui/widget/trapwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local RELEASE_API = "https://api.github.com/repos/SeriousHornet/vos.koplugin/releases/latest"
local RELEASE_URL = "https://github.com/SeriousHornet/vos.koplugin/releases/tag/"

local Updater = {}

local function versionParts(version)
    local parts = {}
    for part in tostring(version):gsub("^v", ""):gmatch("%d+") do
        table.insert(parts, tonumber(part))
    end
    return parts
end

local function isNewer(candidate, current)
    local candidate_parts = versionParts(candidate)
    local current_parts = versionParts(current)
    for index = 1, math.max(#candidate_parts, #current_parts) do
        local candidate_part = candidate_parts[index] or 0
        local current_part = current_parts[index] or 0
        if candidate_part ~= current_part then
            return candidate_part > current_part
        end
    end
    return false
end

local function show(text)
    UIManager:show(InfoMessage:new { text = text })
end

function Updater.check(current_version)
    NetworkMgr:runWhenOnline(function()
        local progress = TrapWidget:new { text = _("Checking for updates...") }
        UIManager:show(progress)
        local completed, code, body = Trapper:dismissableRunInSubprocess(function()
            local https = require("ssl.https")
            local ltn12 = require("ltn12")
            local response = {}
            local __, status = https.request {
                url = RELEASE_API,
                headers = {
                    ["Accept"] = "application/vnd.github+json",
                    ["User-Agent"] = "KOReader-VOS/" .. current_version,
                },
                sink = ltn12.sink.table(response),
            }
            return status, table.concat(response)
        end, progress)
        UIManager:close(progress)

        if not completed then
            return
        end
        if code ~= 200 then
            show(_("Could not check for updates. No published release was found or GitHub could not be reached."))
            return
        end

        local json = require("json")
        local decoded, release = pcall(json.decode, body)
        local tag = decoded and release and release.tag_name
        if not tag then
            show(_("Could not read the latest release information."))
            return
        end

        if isNewer(tag, current_version) then
            show(
                T(
                    _("A new VOS version is available: %1\n\nInstalled version: %2\n\n%3"),
                    tag,
                    current_version,
                    RELEASE_URL .. tag
                )
            )
        else
            show(T(_("VOS is up to date.\n\nInstalled version: %1\nLatest release: %2"), current_version, tag))
        end
    end)
end

return Updater
