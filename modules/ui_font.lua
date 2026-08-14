local Font = require("ui/font")
local FontList = require("fontlist")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local UIFontModule = {
    name = "ui_font",
    default_name = "Noto Sans",
    regular_default = "NotoSans-Regular.ttf",
    bold_default = "NotoSans-Bold.ttf",
}

function UIFontModule:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

local function getBoldPath(path)
    if not path then
        return
    end
    local bold, replacements = path:gsub("%-Regular%.", "-Bold.", 1)
    return replacements > 0 and bold or nil
end

function UIFontModule:getSetting()
    return self.settings.settings.extras.ui_font_name or self.default_name
end

function UIFontModule:setSetting(name)
    self.settings.settings.extras.ui_font_name = name
    self.settings:save()
end

function UIFontModule:init()
    UIFontModule.instance = self
    local cre = require("document/credocument"):engineInit()
    local paths = {}
    for _, path in ipairs(FontList:getFontList()) do
        paths[path] = true
    end

    self.font_list = {}
    self.fonts = {}
    for _, name in ipairs(cre.getFontFaces()) do
        local regular = cre.getFontFaceFilenameAndFaceIndex(name)
        local bold = getBoldPath(regular)
        if regular and bold and paths[regular] and paths[bold] then
            table.insert(self.font_list, name)
            self.fonts[name] = { regular = regular, bold = bold }
        end
    end
    table.sort(self.font_list)

    self.replacements = {}
    for key, path in pairs(Font.fontmap) do
        if path == self.regular_default then
            self.replacements[key] = "regular"
        elseif path == self.bold_default then
            self.replacements[key] = "bold"
        end
    end
    self:patchTouchMenuItems()
    self:apply()
end

function UIFontModule:patchTouchMenuItems()
    local TouchMenu = require("ui/widget/touchmenu")
    if TouchMenu.patched_vos_ui_font then
        return
    end
    TouchMenu.patched_vos_ui_font = true
    local orig_updateItems = TouchMenu.updateItems
    function TouchMenu:updateItems(...)
        local module = UIFontModule.instance
        if module and self.item_table then
            for _, item in ipairs(self.item_table) do
                if not item.font_func and not item._vos_ui_font then
                    item._vos_ui_font = true
                    item.font_func = function(size)
                        local current = UIFontModule.instance
                        return current and current:getFace(size)
                    end
                end
            end
        end
        return orig_updateItems(self, ...)
    end
end

function UIFontModule:getFace(size, bold)
    local selected = self.fonts[self:getSetting()] or self.fonts[self.default_name]
    if not selected then
        return
    end
    return Font:getFace(bold and selected.bold or selected.regular, size)
end

function UIFontModule:apply()
    local name = self:getSetting()
    local selected = self.fonts[name] or self.fonts[self.default_name]
    if not selected then
        return
    end
    if not self.fonts[name] then
        self:setSetting(self.default_name)
    end
    for key, font_type in pairs(self.replacements) do
        Font.fontmap[key] = selected[font_type]
    end

    local TouchMenu = require("ui/widget/touchmenu")
    TouchMenu.fface = Font:getFace("ffont")
end

function UIFontModule:getMenuItem()
    return {
        text_func = function()
            return T(_("UI font: %1"), self:getSetting())
        end,
        sub_item_table_func = function()
            local items = {}
            for _, font_name in ipairs(self.font_list) do
                local name = font_name
                table.insert(items, {
                    text = name,
                    checked_func = function()
                        return self:getSetting() == name
                    end,
                    font_func = function(size)
                        return Font:getFace(self.fonts[name].regular, size)
                    end,
                    callback = function()
                        if self:getSetting() ~= name then
                            self:setSetting(name)
                            UIManager:askForRestart(_("Restart to apply the UI font change"))
                        end
                    end,
                })
            end
            return items
        end,
    }
end

return UIFontModule
