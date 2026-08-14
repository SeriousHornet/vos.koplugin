local BD = require("ui/bidi")
local FileManager = require("apps/filemanager/filemanager")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local PathChooser = require("ui/widget/pathchooser")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local PageNumberSubtitles = { name = "page_number_subtitles" }

function PageNumberSubtitles:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function PageNumberSubtitles:cfg()
    return self.settings.settings.extras.page_subtitles
end

local function pageText(menu)
    if not menu or not menu.page_num or menu.page_num == 0 then
        return ""
    end
    return T(_("Page %1 of %2"), menu.page, menu.page_num)
end

function PageNumberSubtitles:updateFileManagerSubtitle(manager, path)
    if not (manager and manager.title_bar and manager.file_chooser) then
        return
    end
    local titlebar_cfg = self.settings.settings.extras.filemanager_titlebar
    if titlebar_cfg and titlebar_cfg.enabled and not titlebar_cfg.show_path then
        manager.title_bar:setSubTitle("")
        return
    end
    path = manager.file_chooser.path or path or filemanagerutil.getDefaultDir()
    local cfg = self:cfg()
    if not cfg.filemanager then
        local label = BD.directory(filemanagerutil.abbreviate(path))
        if manager.folder_shortcuts:hasFolderShortcut(path) then
            label = "☆ " .. label
        end
        manager.title_bar:setSubTitle(label)
        return
    end
    local label
    if cfg.use_shortcut_names and manager.folder_shortcuts:hasFolderShortcut(path) then
        local shortcut = manager.folder_shortcuts.folder_shortcuts[path]
        label = shortcut and BD.directory(shortcut.text)
    end
    if not label then
        local abbreviated = BD.directory(filemanagerutil.abbreviate(path))
        local parts = util.splitToArray(abbreviated, "/")
        label = parts[#parts] or abbreviated
    end
    local pages = pageText(manager.file_chooser)
    manager.title_bar:setSubTitle(pages ~= "" and label .. " - " .. pages or label)
end

local function updatePathChooserSubtitle(chooser)
    local module = PageNumberSubtitles.instance
    if not (module and chooser.title_bar) then
        return
    end
    local path = BD.directory(filemanagerutil.abbreviate(chooser.path or ""))
    local pages = module:cfg().pathchooser and pageText(chooser) or ""
    chooser.title_bar:setSubTitle(pages ~= "" and path .. " (" .. pages .. ")" or path, true)
end

local function installListSubtitle(owner, expected_name, key)
    local menu = owner and owner.booklist_menu
    if not (menu and menu.name == expected_name and menu.title_bar) then
        return
    end
    if menu.patched_vos_page_subtitle_instance then
        return
    end
    menu.patched_vos_page_subtitle_instance = true
    menu._vos_base_subtitle = menu.title_bar.subtitle_widget and menu.title_bar.subtitle_widget.text or ""
    local orig_switchItemTable = menu.switchItemTable
    function menu:switchItemTable(title, item_table, select_number, itemmatch, subtitle)
        if subtitle then
            self._vos_base_subtitle = subtitle
        end
        return orig_switchItemTable(self, title, item_table, select_number, itemmatch, subtitle)
    end
    local orig_updatePageInfo = menu.updatePageInfo
    function menu:updatePageInfo(...)
        local result = orig_updatePageInfo(self, ...)
        local module = PageNumberSubtitles.instance
        local subtitle = module and module:cfg()[key] and pageText(self) or self._vos_base_subtitle
        self.title_bar:setSubTitle(subtitle, true)
        return result
    end
    local module = PageNumberSubtitles.instance
    if module and module:cfg()[key] then
        menu.title_bar:setSubTitle(pageText(menu), true)
    end
end

function PageNumberSubtitles:init()
    PageNumberSubtitles.instance = self

    if not FileManager.patched_vos_page_subtitles then
        FileManager.patched_vos_page_subtitles = true
        local orig_onPathChanged = FileManager.onPathChanged
        function FileManager:onPathChanged(path)
            local result = orig_onPathChanged and orig_onPathChanged(self, path)
            local module = PageNumberSubtitles.instance
            if module then
                module:updateFileManagerSubtitle(self, path)
            end
            return result
        end

        local orig_setupLayout = FileManager.setupLayout
        function FileManager:setupLayout(...)
            local result = orig_setupLayout(self, ...)
            local chooser = self.file_chooser
            if chooser and not chooser.patched_vos_page_subtitles then
                chooser.patched_vos_page_subtitles = true
                local orig_updatePageInfo = chooser.updatePageInfo
                function chooser:updatePageInfo(...)
                    local update_result = orig_updatePageInfo(self, ...)
                    local module = PageNumberSubtitles.instance
                    if module then
                        module:updateFileManagerSubtitle(self.ui, self.path)
                    end
                    return update_result
                end
                local orig_onGotoPage = chooser.onGotoPage
                function chooser:onGotoPage(page)
                    local goto_result = orig_onGotoPage(self, page)
                    local module = PageNumberSubtitles.instance
                    if module then
                        module:updateFileManagerSubtitle(self.ui, self.path)
                    end
                    return goto_result
                end
                local orig_switchItemTable = chooser.switchItemTable
                function chooser:switchItemTable(...)
                    local switch_result = orig_switchItemTable(self, ...)
                    local module = PageNumberSubtitles.instance
                    if module then
                        module:updateFileManagerSubtitle(self.ui, self.path)
                    end
                    return switch_result
                end
            end
            return result
        end
    end

    if not PathChooser.patched_vos_page_subtitles then
        PathChooser.patched_vos_page_subtitles = true
        local orig_init = PathChooser.init
        function PathChooser:init(...)
            local result = orig_init(self, ...)
            if not self.patched_vos_page_subtitle_instance then
                self.patched_vos_page_subtitle_instance = true
                local orig_updatePageInfo = self.updatePageInfo
                function self:updatePageInfo(...)
                    local update_result = orig_updatePageInfo(self, ...)
                    updatePathChooserSubtitle(self)
                    return update_result
                end
                local orig_onGotoPage = self.onGotoPage
                function self:onGotoPage(page)
                    local goto_result = orig_onGotoPage(self, page)
                    updatePathChooserSubtitle(self)
                    return goto_result
                end
                local orig_switchItemTable = self.switchItemTable
                function self:switchItemTable(...)
                    local switch_result = orig_switchItemTable(self, ...)
                    updatePathChooserSubtitle(self)
                    return switch_result
                end
            end
            updatePathChooserSubtitle(self)
            return result
        end
    end

    if not FileManagerHistory.patched_vos_page_subtitles then
        FileManagerHistory.patched_vos_page_subtitles = true
        local orig_onShowHist = FileManagerHistory.onShowHist
        function FileManagerHistory:onShowHist(...)
            local result = orig_onShowHist(self, ...)
            installListSubtitle(self, "history", "history")
            return result
        end
    end

    if not FileManagerCollection.patched_vos_page_subtitles then
        FileManagerCollection.patched_vos_page_subtitles = true
        local orig_onShowColl = FileManagerCollection.onShowColl
        function FileManagerCollection:onShowColl(...)
            local result = orig_onShowColl(self, ...)
            installListSubtitle(self, "collections", "collections")
            return result
        end
    end
end

function PageNumberSubtitles:getMenuItem()
    local function toggleItem(text, key)
        return {
            text = _(text),
            checked_func = function()
                return self:cfg()[key] == true
            end,
            callback = function()
                self:cfg()[key] = not self:cfg()[key]
                self.settings:save()
                if self.plugin then
                    self.plugin:refresh()
                end
            end,
        }
    end
    return {
        text = _("Page numbers in subtitles"),
        sub_item_table = {
            toggleItem("File browser", "filemanager"),
            toggleItem("Use shortcut names", "use_shortcut_names"),
            toggleItem("Path chooser", "pathchooser"),
            toggleItem("History", "history"),
            toggleItem("Collections", "collections"),
        },
    }
end

return PageNumberSubtitles
