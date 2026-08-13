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
    return self.settings.settings.extras.auto_menu_size == true
end

function MenuSizeModule:init()
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
        text = _("Automatic menu sizing for DPI"),
        checked_func = function()
            return self:isEnabled()
        end,
        callback = function()
            self.settings.settings.extras.auto_menu_size = not self:isEnabled()
            self.settings:save()
            UIManager:askForRestart(_("Restart to apply the menu size change"))
        end,
    }
end

function MenuSizeModule:reinit()
end

return MenuSizeModule
