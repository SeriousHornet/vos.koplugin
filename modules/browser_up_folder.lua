local BD = require("ui/bidi")
local FileChooser = require("ui/widget/filechooser")
local _ = require("gettext")

local BrowserUpFolder = { name = "browser_up_folder" }

function BrowserUpFolder:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function BrowserUpFolder:cfg()
    return self.settings.settings.extras
end

function BrowserUpFolder:isEnabled()
    return self.settings:isMasterEnabled()
end

local function changeLeftIcon(chooser, icon, callback)
    local titlebar = chooser.title_bar
    if not titlebar then
        return
    end
    titlebar.left_icon = icon
    titlebar.left_icon_tap_callback = callback
    if titlebar.left_button then
        titlebar.left_button:setIcon(icon)
        titlebar.left_button.callback = callback
    end
end

local function isEmptyDir(chooser, item)
    if not (item.attr and item.attr.mode == "directory") then
        return false
    end
    local sub_dirs, files = chooser:getList(item.path, {})
    if #files > 0 then
        return false
    end
    for _, sub_dir in ipairs(sub_dirs) do
        if not isEmptyDir(chooser, sub_dir) then
            return false
        end
    end
    return true
end

local function restoreLeftIcon(chooser)
    if chooser._vos_back_icon_applied then
        changeLeftIcon(chooser, chooser._vos_home_icon, chooser._vos_home_callback)
        chooser._vos_back_icon_applied = false
        chooser._vos_back_callback = nil
    end
end

function BrowserUpFolder:init()
    BrowserUpFolder.instance = self
    if FileChooser.patched_vos_browser_folders then
        return
    end
    FileChooser.patched_vos_browser_folders = true
    local orig_genItemTable = FileChooser.genItemTable
    function FileChooser:genItemTable(dirs, files, path)
        local item_table = orig_genItemTable(self, dirs, files, path)
        local module = BrowserUpFolder.instance
        if not module or self._dummy or self.name ~= "filemanager" then
            return item_table
        end
        if not module:isEnabled() then
            restoreLeftIcon(self)
            return item_table
        end

        local cfg = module:cfg()
        local items = {}
        local is_sub_folder = false
        for _, item in ipairs(item_table) do
            if item.path and item.path:find("\u{e257}/") then
                table.insert(items, item)
            elseif item.is_go_up and cfg.hide_up_folder then
                is_sub_folder = true
            elseif not (cfg.hide_empty_folders and isEmptyDir(self, item)) then
                table.insert(items, item)
            end
        end

        if cfg.hide_empty_folders and #items == 0 then
            self:onFolderUp()
            return
        end

        if not self._vos_back_icon_applied and self.title_bar then
            self._vos_home_icon = self.title_bar.left_icon
            self._vos_home_callback = self.title_bar.left_icon_tap_callback
        end
        if cfg.hide_up_folder and is_sub_folder then
            local icon = BD.mirroredUILayout() and "back.top.rtl" or "back.top"
            self._vos_back_callback = function()
                self:onFolderUp()
            end
            changeLeftIcon(self, icon, self._vos_back_callback)
            self._vos_back_icon_applied = true
        else
            restoreLeftIcon(self)
        end
        return items
    end
end

function BrowserUpFolder:getMenuItem()
    return {
        text = _("Browser folders"),
        sub_item_table = {
            {
                text = _("Hide up folder entry"),
                checked_func = function()
                    return self:cfg().hide_up_folder == true
                end,
                callback = function()
                    self:cfg().hide_up_folder = not self:cfg().hide_up_folder
                    self.settings:save()
                    if self.plugin then
                        self.plugin:refresh()
                    end
                end,
            },
            {
                text = _("Hide empty folders"),
                checked_func = function()
                    return self:cfg().hide_empty_folders == true
                end,
                callback = function()
                    self:cfg().hide_empty_folders = not self:cfg().hide_empty_folders
                    self.settings:save()
                    if self.plugin then
                        self.plugin:refresh()
                    end
                end,
            },
            {
                text = _("Hide last visited underline"),
                checked_func = function()
                    return self:cfg().hide_last_visited_underline == true
                end,
                callback = function()
                    self:cfg().hide_last_visited_underline = not self:cfg().hide_last_visited_underline
                    self.settings:save()
                    if self.plugin then
                        self.plugin:refresh()
                    end
                end,
            },
        },
    }
end

return BrowserUpFolder
