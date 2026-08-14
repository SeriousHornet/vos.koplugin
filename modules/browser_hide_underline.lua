local Blitbuffer = require("ffi/blitbuffer")
local userpatch = require("userpatch")

local BrowserHideUnderline = { name = "browser_hide_underline" }

function BrowserHideUnderline:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function BrowserHideUnderline:isEnabled()
    return self.settings:isMasterEnabled() and self:isConfigured()
end

function BrowserHideUnderline:isConfigured()
    return self.settings.settings.extras.hide_last_visited_underline == true
end

function BrowserHideUnderline:init()
    BrowserHideUnderline.instance = self
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem or MosaicMenuItem.patched_vos_hide_underline then
        return
    end
    MosaicMenuItem.patched_vos_hide_underline = true
    local orig_onFocus = MosaicMenuItem.onFocus
    function MosaicMenuItem:onFocus(...)
        local result = orig_onFocus and orig_onFocus(self, ...)
        local module = BrowserHideUnderline.instance
        if module and module:isEnabled() and self._underline_container then
            self._underline_container.color = Blitbuffer.COLOR_WHITE
        end
        return result == nil and true or result
    end
end

return BrowserHideUnderline
