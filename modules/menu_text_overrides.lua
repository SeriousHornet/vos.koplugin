local Menu = require("ui/widget/menu")
local _ = require("gettext")

local MenuTextOverrides = {name = "menu_text_overrides"}

function MenuTextOverrides:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MenuTextOverrides:cfg()
    return self.settings.settings.extras.menu_text
end

function MenuTextOverrides:init()
    MenuTextOverrides.instance = self
    if Menu.patched_vos_text_overrides then
        return
    end
    Menu.patched_vos_text_overrides = true
    local orig_getMenuText = Menu.getMenuText
    Menu.getMenuText = function(item)
        local text = orig_getMenuText(item)
        local module = MenuTextOverrides.instance
        if not text or not module then
            return text
        end
        local cfg = module:cfg()
        if cfg.replace_underscores then
            text = text:gsub("_", " ")
        end
        if cfg.restore_articles then
            local slash = text:sub(-1) == "/" and "/" or ""
            local base = slash ~= "" and text:sub(1, -2) or text
            local stem, article = base:match("^(.-),%s+(The|An|A)$")
            if stem and article then
                text = article .. " " .. stem .. slash
            end
        end
        return text
    end
end

function MenuTextOverrides:getMenuItem()
    return {
        text = _("Menu text cleanup"),
        sub_item_table = {
            {
                text = _("Replace underscores with spaces"),
                checked_func = function()
                    return self:cfg().replace_underscores == true
                end,
                callback = function()
                    self:cfg().replace_underscores = not self:cfg().replace_underscores
                    self.settings:save()
                    if self.plugin then
                        self.plugin:refresh()
                    end
                end,
            },
            {
                text = _("Restore trailing English articles"),
                checked_func = function()
                    return self:cfg().restore_articles == true
                end,
                callback = function()
                    self:cfg().restore_articles = not self:cfg().restore_articles
                    self.settings:save()
                    if self.plugin then
                        self.plugin:refresh()
                    end
                end,
            },
        },
    }
end

function MenuTextOverrides:reinit()
end

return MenuTextOverrides
