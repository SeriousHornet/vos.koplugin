-- Visual Overhaul Suite — Complete visual customization for KOReader.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local SettingsManager = require("settings")
local NavbarModule = require("modules/navbar")
local CoverBrowserModule = require("modules/vos")
local UIFontModule = require("modules/ui_font")
local BrowserHideUnderline = require("modules/browser_hide_underline")
local BrowserUpFolder = require("modules/browser_up_folder")
local MenuSizeModule = require("modules/menu_size")
local IncognitoModule = require("modules/incognito")
local MenuTextOverrides = require("modules/menu_text_overrides")
local PageNumberSubtitles = require("modules/page_number_subtitles")
local QuickSettingsModule = require("modules/quick_settings")
local FileManagerTitleBar = require("modules/titlebar")
local ExcludeFoldersModule = require("modules/exclude_folders")
local BrowserDoubleTapModule = require("modules/browser_double_tap")
local SimpleUIRoundedModule = require("modules/simpleui_rounded")

local VisualOverhaul = WidgetContainer:extend {
    name = "vos",
    is_doc_only = false,
}

function VisualOverhaul:init()
    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled") or {}
    if plugins_disabled.visualoverhaul then
        plugins_disabled.visualoverhaul = nil
        plugins_disabled.vos = true
        G_reader_settings:saveSetting("plugins_disabled", plugins_disabled)
    end

    self.settings = SettingsManager:new()
    self.settings:load()
    self.extra_modules = {
        UIFontModule:new { plugin = self, settings = self.settings },
        BrowserHideUnderline:new { plugin = self, settings = self.settings },
        BrowserUpFolder:new { plugin = self, settings = self.settings },
        MenuSizeModule:new { plugin = self, settings = self.settings },
        IncognitoModule:new { plugin = self, settings = self.settings },
        MenuTextOverrides:new { plugin = self, settings = self.settings },
        PageNumberSubtitles:new { plugin = self, settings = self.settings },
        QuickSettingsModule:new { plugin = self, settings = self.settings },
        FileManagerTitleBar:new { plugin = self, settings = self.settings },
        ExcludeFoldersModule:new { plugin = self, settings = self.settings },
        BrowserDoubleTapModule:new { plugin = self, settings = self.settings },
        SimpleUIRoundedModule:new { plugin = self, settings = self.settings },
    }
    for _, module in ipairs(self.extra_modules) do
        module:init()
    end

    self.navbar = NavbarModule:new {
        plugin = self,
        settings = self.settings,
    }
    self.navbar:init()

    self.coverbrowser = CoverBrowserModule:new {
        plugin = self,
        settings = self.settings,
    }
    self.coverbrowser:init()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    local ok_upd, updater = pcall(require, "vos_updater")
    if ok_upd and updater and updater.scheduleAutoCheck then
        updater.scheduleAutoCheck()
    end
end

function VisualOverhaul:addToMainMenu(menu_items)
    local order = require("ui/elements/filemanager_menu_order").filemanager_settings
    for index = #order, 1, -1 do
        if order[index] == "visual_overhaul" then
            table.remove(order, index)
        end
    end
    local display_mode_index
    for index, id in ipairs(order) do
        if id == "filemanager_display_mode" then
            display_mode_index = index
            break
        end
    end
    if display_mode_index then
        table.insert(order, display_mode_index, "visual_overhaul")
    end
    menu_items.visual_overhaul = {
        text = _("Visual Overhaul Suite (VOS)"),
        sorting_hint = "tools",
        sub_item_table = self.settings:getMainMenu(self),
    }
end

function VisualOverhaul:refresh()
    for _, module in ipairs(self.extra_modules or {}) do
        if module.reinit then
            module:reinit()
        end
    end

    if self.navbar then
        self.navbar:reinit()
    end

    if self.coverbrowser then
        self.coverbrowser:reinit()
    end

    local fm = FileManager.instance
    if fm then
        local updated = {}
        if fm.file_chooser then
            fm.file_chooser:updateItems()
            updated[fm.file_chooser] = true
        end
        UIManager:setDirty(fm, "ui")
        for _, widget in ipairs(UIManager._window_stack) do
            if widget.updateItems and not updated[widget] then
                widget:updateItems()
                updated[widget] = true
            end
            UIManager:setDirty(widget, "ui")
        end
    end
end

return VisualOverhaul
