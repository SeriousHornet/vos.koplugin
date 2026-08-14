local UIManager = require("ui/uimanager")
local _ = require("gettext")

local IncognitoModule = {
    name = "incognito",
    active = false,
}

function IncognitoModule:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function IncognitoModule:isEnabled()
    return self.settings.settings.extras.incognito_enabled == true
end

function IncognitoModule:init()
    IncognitoModule.instance = self

    local ReadHistory = require("readhistory")
    if not ReadHistory.patched_vos_incognito then
        ReadHistory.patched_vos_incognito = true
        local orig_addItem = ReadHistory.addItem
        function ReadHistory:addItem(file, ...)
            local module = IncognitoModule.instance
            if module and module.active and file == module.file then
                return
            end
            return orig_addItem(self, file, ...)
        end

        local orig_updateLastBookTime = ReadHistory.updateLastBookTime
        function ReadHistory:updateLastBookTime(...)
            local module = IncognitoModule.instance
            if module and module.active then
                return
            end
            return orig_updateLastBookTime(self, ...)
        end

        local orig_reload = ReadHistory.reload
        function ReadHistory:reload(...)
            local result = orig_reload(self, ...)
            local module = IncognitoModule.instance
            if module and module.active then
                local filtered = {}
                for _, item in ipairs(self.hist) do
                    if item.file ~= module.file then
                        table.insert(filtered, item)
                    end
                end
                self.hist = filtered
            end
            return result
        end
    end

    local DocumentRegistry = require("document/documentregistry")
    if not DocumentRegistry.patched_vos_incognito then
        DocumentRegistry.patched_vos_incognito = true
        local orig_openDocument = DocumentRegistry.openDocument
        function DocumentRegistry:openDocument(file, ...)
            local document = orig_openDocument(self, file, ...)
            local module = IncognitoModule.instance
            if document and module and module.active and file == module.file then
                document.is_pic = true
            end
            return document
        end
    end

    local ReadCollection = require("readcollection")
    if not ReadCollection.patched_vos_incognito then
        ReadCollection.patched_vos_incognito = true
        local orig_updateLastBookTime = ReadCollection.updateLastBookTime
        function ReadCollection:updateLastBookTime(file, ...)
            local module = IncognitoModule.instance
            if module and module.active and file == module.file then
                return
            end
            return orig_updateLastBookTime(self, file, ...)
        end
    end

    local FileManager = require("apps/filemanager/filemanager")
    FileManager:addFileDialogButtons("vos_incognito", function(file, is_file)
        local module = IncognitoModule.instance
        if not module or not module:isEnabled() or not is_file then
            return
        end
        return {
            {
                text = _("Open incognito"),
                callback = function()
                    module:open(file)
                end,
            },
        }
    end)
end

function IncognitoModule:open(file)
    self.active = true
    self.file = file
    local dialog = UIManager:getTopmostVisibleWidget()
    if dialog then
        UIManager:close(dialog)
    end

    UIManager:scheduleIn(0.1, function()
        local ReaderUI = require("apps/reader/readerui")
        local orig_init = ReaderUI.init
        local orig_onClose = ReaderUI.onClose
        local orig_showFileManager = ReaderUI.showFileManager
        local function restoreHooks()
            ReaderUI.init = orig_init
            ReaderUI.onClose = orig_onClose
            ReaderUI.showFileManager = orig_showFileManager
        end
        local function finish()
            local closed_file = self.file
            self.active = false
            self.file = nil
            if closed_file then
                local BookList = require("ui/widget/booklist")
                if BookList.resetBookInfoCache then
                    BookList.resetBookInfoCache(closed_file)
                end
            end
        end
        ReaderUI.init = function(reader, ...)
            ReaderUI.init = orig_init
            orig_init(reader, ...)
            if self.active and reader.doc_settings then
                local settings = reader.doc_settings
                local orig_flush = settings.flush
                settings.flush = function(doc_settings, ...)
                    if self.active then
                        return
                    end
                    return orig_flush(doc_settings, ...)
                end
            end
        end

        ReaderUI.onClose = function(reader, ...)
            restoreHooks()
            local result = orig_onClose(reader, ...)
            finish()
            return result
        end
        ReaderUI.showFileManager = function(reader, ...)
            restoreHooks()
            finish()
            return orig_showFileManager(reader, ...)
        end
        ReaderUI:showReader(file)
    end)
end

function IncognitoModule:getMenuItem()
    return {
        text = _("Enable incognito opening"),
        checked_func = function()
            return self:isEnabled()
        end,
        callback = function()
            self.settings.settings.extras.incognito_enabled = not self:isEnabled()
            self.settings:save()
        end,
    }
end

return IncognitoModule
