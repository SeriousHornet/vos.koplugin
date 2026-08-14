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

function IncognitoModule:isConfigured()
    return self.settings.settings.extras.incognito_enabled == true
end

function IncognitoModule:isEnabled()
    return self.settings:isMasterEnabled() and self:isConfigured()
end

function IncognitoModule:isActive()
    return self:isEnabled() and self.active
end

function IncognitoModule:finishActive()
    if self._restore_reader_hooks then
        self._restore_reader_hooks()
        self._restore_reader_hooks = nil
    end
    if self.document then
        self.document.is_pic = self._document_was_pic
        self.document = nil
        self._document_was_pic = nil
    end
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

function IncognitoModule:init()
    IncognitoModule.instance = self

    local ReadHistory = require("readhistory")
    if not ReadHistory.patched_vos_incognito then
        ReadHistory.patched_vos_incognito = true
        local orig_addItem = ReadHistory.addItem
        function ReadHistory:addItem(file, ...)
            local module = IncognitoModule.instance
            if module and module:isActive() and file == module.file then
                return
            end
            return orig_addItem(self, file, ...)
        end

        local orig_updateLastBookTime = ReadHistory.updateLastBookTime
        function ReadHistory:updateLastBookTime(...)
            local module = IncognitoModule.instance
            if module and module:isActive() then
                return
            end
            return orig_updateLastBookTime(self, ...)
        end

        local orig_reload = ReadHistory.reload
        function ReadHistory:reload(...)
            local result = orig_reload(self, ...)
            local module = IncognitoModule.instance
            if module and module:isActive() then
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
            if document and module and module:isActive() and file == module.file then
                module.document = document
                module._document_was_pic = document.is_pic
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
            if module and module:isActive() and file == module.file then
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
                    if module:isEnabled() then
                        module:open(file)
                    end
                end,
            },
        }
    end)
end

function IncognitoModule:open(file)
    if not self:isEnabled() then
        return
    end
    self._open_generation = (self._open_generation or 0) + 1
    local generation = self._open_generation
    self.active = true
    self.file = file
    local dialog = UIManager:getTopmostVisibleWidget()
    if dialog then
        UIManager:close(dialog)
    end

    UIManager:scheduleIn(0.1, function()
        if generation ~= self._open_generation or not self:isActive() or self.file ~= file then
            return
        end
        local ReaderUI = require("apps/reader/readerui")
        local orig_init = ReaderUI.init
        local orig_onClose = ReaderUI.onClose
        local orig_showFileManager = ReaderUI.showFileManager
        local wrapped_init
        local wrapped_onClose
        local wrapped_showFileManager
        local function restoreHooks()
            if ReaderUI.init == wrapped_init then
                ReaderUI.init = orig_init
            end
            if ReaderUI.onClose == wrapped_onClose then
                ReaderUI.onClose = orig_onClose
            end
            if ReaderUI.showFileManager == wrapped_showFileManager then
                ReaderUI.showFileManager = orig_showFileManager
            end
        end
        local function finish()
            self:finishActive()
        end
        self._restore_reader_hooks = restoreHooks
        wrapped_init = function(reader, ...)
            if ReaderUI.init == wrapped_init then
                ReaderUI.init = orig_init
            end
            orig_init(reader, ...)
            if self:isActive() and reader.doc_settings then
                local settings = reader.doc_settings
                local orig_flush = settings.flush
                settings.flush = function(doc_settings, ...)
                    if self:isActive() then
                        return
                    end
                    return orig_flush(doc_settings, ...)
                end
            end
        end
        ReaderUI.init = wrapped_init

        wrapped_onClose = function(reader, ...)
            restoreHooks()
            local result = orig_onClose(reader, ...)
            finish()
            return result
        end
        ReaderUI.onClose = wrapped_onClose
        wrapped_showFileManager = function(reader, ...)
            restoreHooks()
            finish()
            return orig_showFileManager(reader, ...)
        end
        ReaderUI.showFileManager = wrapped_showFileManager
        if generation ~= self._open_generation or not self:isActive() then
            finish()
            return
        end
        ReaderUI:showReader(file)
    end)
end

function IncognitoModule:reinit()
    if not self:isEnabled() then
        self._open_generation = (self._open_generation or 0) + 1
        self:finishActive()
    end
end

function IncognitoModule:getMenuItem()
    return {
        text = _("Enable incognito opening"),
        checked_func = function()
            return self:isConfigured()
        end,
        callback = function()
            self.settings.settings.extras.incognito_enabled = not self:isConfigured()
            self.settings:save()
            if self.plugin then
                self.plugin:refresh()
            end
        end,
    }
end

return IncognitoModule
