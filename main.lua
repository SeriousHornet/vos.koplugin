--[[--
Visual Overhaul Suite - Complete visual customization for KOReader
@module koplugin.visualoverhaul
--]]
--

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

local VisualOverhaul = WidgetContainer:extend {
    name = "visualoverhaul",
    is_doc_only = false,
}

function VisualOverhaul:init()
    local heap_before = collectgarbage("count")
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
    self.lua_heap_delta_kb = collectgarbage("count") - heap_before
end

function VisualOverhaul:addToMainMenu(menu_items)
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

    -- Rebuild each visible list at most once. Avoid free/init and overlapping
    -- full-screen refreshes: these are expensive on e-ink devices.
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
