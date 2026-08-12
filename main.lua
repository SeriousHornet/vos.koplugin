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
            self.settings:isEnabled("collection_star")
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
        text = _("Visual Overhaul Suite"),
        sorting_hint = "tools",
        sub_item_table = self.settings:getMainMenu(self)
    }
end

function VisualOverhaul:refresh()
    logger.info("VisualOverhaul: Refreshing...")

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
            self.settings:isEnabled("hide_pagination") or self.settings:isEnabled("collection_star")
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
