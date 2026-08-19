local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local InfoMessage = require("ui/widget/infomessage")
local DataStorage = require("datastorage")
local _ = require("gettext")
local Screen = require("device").screen

local ExcludeFolders = { name = "exclude_folders" }

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/vos_exclude_folders.lua"

function ExcludeFolders:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function ExcludeFolders:cfg()
    return self.settings.settings.extras.exclude_folders
end

function ExcludeFolders:isEnabled()
    return self.settings:isMasterEnabled() and self:cfg().enabled
end

function ExcludeFolders:_loadLists()
    local s = LuaSettings:open(SETTINGS_FILE)
    return {
        history          = s:readSetting("history",          {}),
        statistics       = s:readSetting("statistics",       {}),
        history_files    = s:readSetting("history_files",    {}),
        statistics_files = s:readSetting("statistics_files", {}),
        _s = s,
    }
end

function ExcludeFolders:_saveLists(cfg)
    cfg._s:saveSetting("history",          cfg.history)
    cfg._s:saveSetting("statistics",       cfg.statistics)
    cfg._s:saveSetting("history_files",    cfg.history_files)
    cfg._s:saveSetting("statistics_files", cfg.statistics_files)
    cfg._s:flush()
end

function ExcludeFolders._normalizePath(path)
    return (path or ""):gsub("//+", "/"):gsub("/$", "")
end

function ExcludeFolders._isExcludedBy(filepath, folders)
    if not filepath or filepath == "" then return false end
    local fp = ExcludeFolders._normalizePath(filepath)
    for _, folder in ipairs(folders) do
        local nf = ExcludeFolders._normalizePath(folder)
        if nf:sub(1, 1) == "/" then
            if fp == nf or fp:sub(1, #nf + 1) == nf .. "/" then
                return true
            end
        else
            if fp:find(nf, 1, true) then
                return true
            end
        end
    end
    return false
end

function ExcludeFolders._isExcludedFile(filepath, files)
    if not filepath or filepath == "" then return false end
    local fp = ExcludeFolders._normalizePath(filepath)
    for _, f in ipairs(files) do
        if fp == ExcludeFolders._normalizePath(f) then return true end
    end
    return false
end

function ExcludeFolders._addToList(list, entry)
    for _, v in ipairs(list) do
        if v == entry then return false end
    end
    table.insert(list, entry)
    return true
end

function ExcludeFolders._isDirectMatch(filepath, list)
    local fp = ExcludeFolders._normalizePath(filepath)
    for _, v in ipairs(list) do
        if fp == ExcludeFolders._normalizePath(v) then return true end
    end
    return false
end

function ExcludeFolders:init()
    ExcludeFolders.instance = self

    local ReadHistory = require("readhistory")
    if not ReadHistory.patched_vos_exclude then
        ReadHistory.patched_vos_exclude = true
        local orig_addItem = ReadHistory.addItem
        ReadHistory.addItem = function(self_rh, file, ts, no_flush)
            local mod = ExcludeFolders.instance
            if mod and mod:isEnabled() then
                local cfg = mod:_loadLists()
                if ExcludeFolders._isExcludedBy(file, cfg.history)
                    or ExcludeFolders._isExcludedFile(file, cfg.history_files) then
                    return
                end
            end
            return orig_addItem(self_rh, file, ts, no_flush)
        end

        local orig_updateLastBookTime = ReadHistory.updateLastBookTime
        ReadHistory.updateLastBookTime = function(self_rh, no_flush)
            if not self_rh.hist or not self_rh.hist[1] then
                return
            end
            return orig_updateLastBookTime(self_rh, no_flush)
        end

        local orig_reload = ReadHistory.reload
        ReadHistory.reload = function(self_rh, force_read)
            orig_reload(self_rh, force_read)
            local mod = ExcludeFolders.instance
            if mod and mod:isEnabled() then
                local cfg = mod:_loadLists()
                local filtered = {}
                for _, item in ipairs(self_rh.hist) do
                    if not ExcludeFolders._isExcludedBy(item.file, cfg.history)
                        and not ExcludeFolders._isExcludedFile(item.file, cfg.history_files) then
                        table.insert(filtered, item)
                    end
                end
                if #filtered ~= #self_rh.hist then
                    self_rh.hist = filtered
                end
            end
        end

        do
            local cfg = self:_loadLists()
            local filtered, removed = {}, 0
            for _, item in ipairs(ReadHistory.hist) do
                if not ExcludeFolders._isExcludedBy(item.file, cfg.history)
                    and not ExcludeFolders._isExcludedFile(item.file, cfg.history_files) then
                    table.insert(filtered, item)
                else
                    removed = removed + 1
                end
            end
            if removed > 0 then
                ReadHistory.hist = filtered
            end
        end
    end

    local DocumentRegistry = require("document/documentregistry")
    if not DocumentRegistry.patched_vos_exclude then
        DocumentRegistry.patched_vos_exclude = true
        local orig_openDocument = DocumentRegistry.openDocument
        DocumentRegistry.openDocument = function(self_dr, file, provider)
            local doc = orig_openDocument(self_dr, file, provider)
            local mod = ExcludeFolders.instance
            if doc and mod and mod:isEnabled() then
                local cfg = mod:_loadLists()
                if ExcludeFolders._isExcludedBy(file, cfg.statistics)
                    or ExcludeFolders._isExcludedFile(file, cfg.statistics_files) then
                    doc.is_pic = true
                end
            end
            return doc
        end
    end

    local FileManager = require("apps/filemanager/filemanager")
    FileManager:addFileDialogButtons("vos_exclude_folders", function(file, is_file)
        local mod = ExcludeFolders.instance
        if not mod or not mod:isEnabled() then
            return
        end
        local cfg = mod:_loadLists()
        local hist_key = is_file and "history_files"    or "history"
        local stat_key = is_file and "statistics_files" or "statistics"
        local in_history    = is_file and ExcludeFolders._isExcludedFile(file, cfg.history_files)
                                  or ExcludeFolders._isExcludedBy(file, cfg.history)
        local in_statistics = is_file and ExcludeFolders._isExcludedFile(file, cfg.statistics_files)
                                  or ExcludeFolders._isExcludedBy(file, cfg.statistics)
        local direct_history    = is_file and ExcludeFolders._isExcludedFile(file, cfg.history_files)
                                      or ExcludeFolders._isDirectMatch(file, cfg.history)
        local direct_statistics = is_file and ExcludeFolders._isExcludedFile(file, cfg.statistics_files)
                                      or ExcludeFolders._isDirectMatch(file, cfg.statistics)
        local inh_history    = in_history    and not direct_history
        local inh_statistics = in_statistics and not direct_statistics
        local kind = is_file and _("file") or _("folder")

        local function toggleList(list_key, is_excluded)
            local c = mod:_loadLists()
            if is_excluded then
                for i, v in ipairs(c[list_key]) do
                    if ExcludeFolders._normalizePath(v) == ExcludeFolders._normalizePath(file) then
                        table.remove(c[list_key], i)
                        break
                    end
                end
            else
                local entry = (not is_file and file:sub(-1) ~= "/") and (file .. "/") or file
                ExcludeFolders._addToList(c[list_key], entry)
            end
            mod:_saveLists(c)
        end

        return {
            {
                text    = in_history and _("✓ Ignored in History") or _("Ignore in History"),
                enabled = not inh_history,
                callback = function()
                    local dialog = UIManager:getTopmostVisibleWidget()
                    if dialog then UIManager:close(dialog) end
                    toggleList(hist_key, in_history)
                    if not in_history then
                        UIManager:show(InfoMessage:new {
                            text = kind .. _(" added to exclusion list. Existing entries will be removed on next History open."),
                        })
                    end
                end,
            },
            {
                text    = in_statistics and _("✓ Ignored in Statistics") or _("Ignore in Statistics"),
                enabled = not inh_statistics,
                callback = function()
                    local dialog = UIManager:getTopmostVisibleWidget()
                    if dialog then UIManager:close(dialog) end
                    toggleList(stat_key, in_statistics)
                end,
            },
        }
    end)

    local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
    if not FileManagerHistory._vos_exclude_patched then
        FileManagerHistory._vos_exclude_patched = true
        local orig_onShowHist = FileManagerHistory.onShowHist
        FileManagerHistory.onShowHist = function(self_fh, ...)
            local mod = ExcludeFolders.instance
            if mod and mod:isEnabled() then
                local ok_rh, ReadHistory2 = pcall(require, "readhistory")
                if ok_rh and ReadHistory2 then
                    ReadHistory2:reload(true)
                end
            end
            return orig_onShowHist(self_fh, ...)
        end
    end

    self:_patchReaderMenu()
end

function ExcludeFolders:_patchReaderMenu()
    local ReaderMenu = require("apps/reader/modules/readermenu")
    if ReaderMenu._vos_exclude_menu_patched then
        return
    end
    ReaderMenu._vos_exclude_menu_patched = true
    local self_ref = self
    local orig_setUpdateItemTable = ReaderMenu.setUpdateItemTable
    ReaderMenu.setUpdateItemTable = function(self_menu)
        local order = require("ui/elements/reader_menu_order")
        table.insert(order.tools, "vos_exclude_current_book")
        self_menu.menu_items.vos_exclude_current_book = {
            text = _("Exclude this book\u{2026}"),
            sub_item_table = {
                {
                    text = _("Ignore in History"),
                    checked_func = function()
                        local file = self_menu.ui and self_menu.ui.document and self_menu.ui.document.file
                        if not file then return false end
                        local cfg = self_ref:_loadLists()
                        return ExcludeFolders._isExcludedFile(file, cfg.history_files)
                            or ExcludeFolders._isExcludedBy(file, cfg.history)
                    end,
                    enabled_func = function()
                        local file = self_menu.ui and self_menu.ui.document and self_menu.ui.document.file
                        if not file then return false end
                        local cfg = self_ref:_loadLists()
                        local in_history = ExcludeFolders._isExcludedFile(file, cfg.history_files)
                            or ExcludeFolders._isExcludedBy(file, cfg.history)
                        return not (in_history and not ExcludeFolders._isExcludedFile(file, cfg.history_files))
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local file = self_menu.ui and self_menu.ui.document and self_menu.ui.document.file
                        if not file then return end
                        local c = self_ref:_loadLists()
                        local in_history = ExcludeFolders._isExcludedFile(file, c.history_files)
                            or ExcludeFolders._isExcludedBy(file, c.history)
                        if in_history then
                            for i, v in ipairs(c.history_files) do
                                if v == file then table.remove(c.history_files, i); break end
                            end
                        else
                            ExcludeFolders._addToList(c.history_files, file)
                        end
                        self_ref:_saveLists(c)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
                {
                    text = _("Ignore in Statistics"),
                    checked_func = function()
                        local file = self_menu.ui and self_menu.ui.document and self_menu.ui.document.file
                        if not file then return false end
                        local cfg = self_ref:_loadLists()
                        return ExcludeFolders._isExcludedFile(file, cfg.statistics_files)
                            or ExcludeFolders._isExcludedBy(file, cfg.statistics)
                    end,
                    enabled_func = function()
                        local file = self_menu.ui and self_menu.ui.document and self_menu.ui.document.file
                        if not file then return false end
                        local cfg = self_ref:_loadLists()
                        local in_stat = ExcludeFolders._isExcludedFile(file, cfg.statistics_files)
                            or ExcludeFolders._isExcludedBy(file, cfg.statistics)
                        return not (in_stat and not ExcludeFolders._isExcludedFile(file, cfg.statistics_files))
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local file = self_menu.ui and self_menu.ui.document and self_menu.ui.document.file
                        if not file then return end
                        local c = self_ref:_loadLists()
                        local in_stat = ExcludeFolders._isExcludedFile(file, c.statistics_files)
                            or ExcludeFolders._isExcludedBy(file, c.statistics)
                        if in_stat then
                            for i, v in ipairs(c.statistics_files) do
                                if v == file then table.remove(c.statistics_files, i); break end
                            end
                        else
                            ExcludeFolders._addToList(c.statistics_files, file)
                        end
                        self_ref:_saveLists(c)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                        UIManager:show(InfoMessage:new {
                            text = _("Change will take effect after reopening the book."),
                        })
                    end,
                },
            },
        }
        orig_setUpdateItemTable(self_menu)
    end
end

function ExcludeFolders:reinit()
    if not self:isEnabled() then
        return
    end
end

function ExcludeFolders:_showExcludeMenu(active_tab)
    active_tab = active_tab or "history"
    local self_ref = self
    local TAB = {
        history    = { label = _("Excluded from History"),    tab = _("History"),    folder_key = "history",    file_key = "history_files"    },
        statistics = { label = _("Excluded from Statistics"), tab = _("Statistics"), folder_key = "statistics", file_key = "statistics_files" },
    }
    local tab_order = { "history", "statistics" }

    local function buildItems()
        local t          = TAB[active_tab]
        local folder_key = t.folder_key
        local file_key   = t.file_key
        local cfg        = self_ref:_loadLists()
        local folders    = cfg[folder_key]
        local files      = cfg[file_key]
        local items      = {}

        local tab_parts = {}
        for _, key in ipairs(tab_order) do
            local marker = (key == active_tab) and "\u{25cf} " or "\u{25cb} "
            tab_parts[#tab_parts + 1] = marker .. TAB[key].tab
        end
        items[#items + 1] = {
            text  = table.concat(tab_parts, "     "),
            callback = function()
                active_tab = (active_tab == "history") and "statistics" or "history"
                menu:switchItemTable(TAB[active_tab].label, buildItems())
            end,
        }
        items[#items + 1] = {
            text     = "",
            dim      = true,
            callback = function() end,
        }

        for i, path in ipairs(folders) do
            items[#items + 1] = {
                text = "\u{25b8} " .. path,
                callback = function()
                    UIManager:show(ConfirmBox:new {
                        text        = _("Remove from exclusion list?") .. "\n\n" .. path,
                        ok_text     = _("Remove"),
                        ok_callback = function()
                            local c = self_ref:_loadLists()
                            table.remove(c[folder_key], i)
                            self_ref:_saveLists(c)
                            menu:switchItemTable(t.label, buildItems())
                        end,
                    })
                end,
            }
        end

        for i, path in ipairs(files) do
            items[#items + 1] = {
                text = "" .. path,
                callback = function()
                    UIManager:show(ConfirmBox:new {
                        text        = _("Remove from exclusion list?") .. "\n\n" .. path,
                        ok_text     = _("Remove"),
                        ok_callback = function()
                            local c = self_ref:_loadLists()
                            table.remove(c[file_key], i)
                            self_ref:_saveLists(c)
                            menu:switchItemTable(t.label, buildItems())
                        end,
                    })
                end,
            }
        end

        if #folders == 0 and #files == 0 then
            items[#items + 1] = {
                text     = _("(nothing excluded yet)"),
                dim      = true,
                callback = function() end,
            }
        end

        items[#items + 1] = {
            text = _("\u{ff0b} Add folder path\u{2026}"),
            callback = function()
                local input
                input = InputDialog:new {
                    title       = _("Exclude folder"),
                    description = _("Any path fragment will match \u{2014} e.g. 'Comics' excludes all folders and files containing that name."),
                    input_hint  = _("/path/to/folder"),
                    buttons = {{
                        { text = _("Cancel"), callback = function() UIManager:close(input) end },
                        {
                            text             = _("Add"),
                            is_enter_default = true,
                            callback = function()
                                local path = input:getInputText()
                                    :gsub("//+", "/"):gsub("/$", "")
                                UIManager:close(input)
                                if path ~= "" then
                                    local c = self_ref:_loadLists()
                                    if ExcludeFolders._addToList(c[folder_key], path) then
                                        self_ref:_saveLists(c)
                                    else
                                        UIManager:show(InfoMessage:new { text = _("Already in the list.") })
                                    end
                                end
                                menu:switchItemTable(t.label, buildItems())
                            end,
                        },
                    }},
                }
                UIManager:show(input)
                input:onShowKeyboard()
            end,
        }

        return items
    end

    local title = TAB[active_tab].label
    menu = Menu:new {
        title         = title,
        item_table    = buildItems(),
        is_borderless = true,
        is_popout     = false,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        onMenuSelect  = function(_, item) item.callback() end,
        onMenuHold    = function() end,
    }
    UIManager:show(menu)
end

function ExcludeFolders:getMenuItem()
    local self_ref = self
    return {
        text = _("Exclude from History & Statistics"),
        callback = function()
            self_ref:_showExcludeMenu("history")
        end,
    }
end

return ExcludeFolders
