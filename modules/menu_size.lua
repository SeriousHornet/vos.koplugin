local Device = require("device")
local Menu = require("ui/widget/menu")
local TouchMenu = require("ui/widget/touchmenu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local MenuSizeModule = {
    name = "menu_size",
    original_touch_max = TouchMenu.max_per_page_default,
    original_menu_max = Menu.items_per_page_default,
}

function MenuSizeModule:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MenuSizeModule:isEnabled()
    return self.settings:isMasterEnabled() and self:isConfigured()
end

function MenuSizeModule:isConfigured()
    return self.settings.settings.extras.auto_menu_size == true
end

function MenuSizeModule:init()
    self:reinit()
end

function MenuSizeModule:reinit()
    TouchMenu.max_per_page_default = self.original_touch_max
    Menu.items_per_page_default = self.original_menu_max
    if not self:isEnabled() then
        return
    end
    local Screen = Device.screen
    local dpi = Screen:getDPI()
    Screen:clearDPI()
    local default_dpi = Screen:getDPI()
    Screen:setDPI(dpi)
    local ratio = math.min(dpi / default_dpi, 1)
    TouchMenu.max_per_page_default = math.floor(self.original_touch_max / ratio)
    Menu.items_per_page_default = math.floor(self.original_menu_max / ratio)
end

function MenuSizeModule:getMenuItem()
    return {
        text = _("Auto menu size"),
        checked_func = function()
            return self:isConfigured()
        end,
        callback = function()
            self.settings.settings.extras.auto_menu_size = not self:isConfigured()
            self.settings:save()
            self:reinit()
            UIManager:askForRestart(_("Restart to fully apply the menu size change"))
        end,
    }
end

return MenuSizeModule
