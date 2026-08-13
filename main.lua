--[[--
Visual Overhaul Suite - Complete visual customization for KOReader
@module koplugin.visualoverhaul
--]] --

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FileManager = require("apps/filemanager/filemanager") -- ADD THIS
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

-- Modules
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

-- Main Plugin Class
local VisualOverhaul =
    WidgetContainer:extend {
    name = "visualoverhaul",
    is_doc_only = false
}

function VisualOverhaul:init()
    logger.info("Visual Overhaul Suite plugin loaded v1.0.0")

    -- Load settings
    self.settings = SettingsManager:new()
    self.settings:load()

    self.extra_modules = {
        UIFontModule:new {plugin = self, settings = self.settings},
        BrowserHideUnderline:new {plugin = self, settings = self.settings},
        BrowserUpFolder:new {plugin = self, settings = self.settings},
        MenuSizeModule:new {plugin = self, settings = self.settings},
        IncognitoModule:new {plugin = self, settings = self.settings},
        MenuTextOverrides:new {plugin = self, settings = self.settings},
        PageNumberSubtitles:new {plugin = self, settings = self.settings},
    }
    for _, module in ipairs(self.extra_modules) do
        logger.info("VisualOverhaul: Initializing Extras module", module.name)
        module:init()
    end

    -- Initialize modules based on settings
    if self.settings:isEnabled("navbar") then
        logger.info("VisualOverhaul: Initializing Navbar module")
        self.navbar =
            NavbarModule:new {
            plugin = self,
            settings = self.settings
        }
        self.navbar:init()
    end

    if
        self.settings:isEnabled("coverbrowser") or self.settings:isEnabled("hide_pagination") or
            self.settings:isEnabled("collection_star") or self.settings:isEnabled("hide_collection_star")
     then
        logger.info("VisualOverhaul: Initializing CoverBrowser module")
        self.coverbrowser =
            CoverBrowserModule:new {
            plugin = self,
            settings = self.settings
        }
        self.coverbrowser:init()
    end

    -- Register with menu
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function VisualOverhaul:addToMainMenu(menu_items)
    menu_items.visual_overhaul = {
        text = _("Visual Overhaul Suite (VOS)"),
        sorting_hint = "tools",
        sub_item_table = self.settings:getMainMenu(self)
    }
end

function VisualOverhaul:refresh()
    logger.info("VisualOverhaul: Refreshing...")

    for _, module in ipairs(self.extra_modules or {}) do
        if module.reinit then
            module:reinit()
        end
    end

    -- Reinitialize modules
    if self.settings:isEnabled("navbar") then
        if not self.navbar then
            logger.info("VisualOverhaul: Initializing Navbar module")
            self.navbar =
                NavbarModule:new {
                plugin = self,
                settings = self.settings
            }
            self.navbar:init()
        else
            self.navbar:reinit()
        end
    elseif self.navbar then
        self.navbar:reinit()
    end

    if
        self.coverbrowser or self.settings:isEnabled("coverbrowser") or
            self.settings:isEnabled("hide_pagination") or self.settings:isEnabled("collection_star") or
            self.settings:isEnabled("hide_collection_star")
     then
        if not self.coverbrowser then
            -- A module toggle was switched on at runtime; install the patches now.
            logger.info("VisualOverhaul: Initializing CoverBrowser module")
            self.coverbrowser =
                CoverBrowserModule:new {
                plugin = self,
                settings = self.settings
            }
            self.coverbrowser:init()
        end
        self.coverbrowser:reinit()
    end

    -- Force a complete UI refresh
    local fm = FileManager.instance
    if fm then
        -- Refresh file chooser
        if fm.file_chooser then
            fm.file_chooser:updateItems()
            -- Force redraw
            fm.file_chooser:free()
            fm.file_chooser:init()
        end

        -- Force dirty the whole window
        UIManager:setDirty(fm, "full")

        -- Also refresh any open menus
        for _, widget in ipairs(UIManager._window_stack) do
            if widget.updateItems then
                widget:updateItems()
            end
            UIManager:setDirty(widget, "full")
        end
    end

    -- Force a full screen redraw
    UIManager:setDirty(nil, "full")
end

return VisualOverhaul
