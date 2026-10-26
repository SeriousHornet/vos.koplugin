-- Automatic series folders for VOS from KOReader's existing book metadata.

local FileChooser = require("ui/widget/filechooser")
local _ = require("gettext")
local logger = require("logger")

local SeriesFolders = { name = "series_folders" }
local active_group = nil
local cache_by_path = {}

function SeriesFolders:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function SeriesFolders:cfg()
    return self.settings.settings.extras.series_folders
end

function SeriesFolders:isEnabled()
    return self.settings:isMasterEnabled() and self:cfg().enabled == true
end

local function isDirectory(item)
    return item.is_directory or (item.attr and item.attr.mode == "directory") or item.mode == "directory"
end

local function getSeries(item, book_info)
    local props = item.doc_props
    if not props and book_info and item.path then
        local ok, result = pcall(book_info.getDocProps, book_info, item.path)
        if ok then props = result end
        item.doc_props = props
    end
    if type(props) ~= "table" then return nil end
    local name = props.series
    if type(name) ~= "string" or name == "" or name == "\u{FFFF}" then return nil end
    return name, tonumber(props.series_index) or 0
end

local function makeVirtualPath(parent, name)
    return (parent or "") .. ".__vos_series__" .. name
end

function SeriesFolders:groupItems(items, chooser)
    if not self:isEnabled() or not items or items.is_in_vos_series or chooser.show_current_dir_for_hold then
        return items
    end

    local book_info = self.book_info
    if not book_info then return items end

    local groups, output = {}, {}
    local books_with_series, total_books = 0, 0
    for _, item in ipairs(items) do
        if item.is_go_up then
            output[#output + 1] = item
        elseif item.is_file and item.path then
            total_books = total_books + 1
            local name, index = getSeries(item, book_info)
            if name then
                books_with_series = books_with_series + 1
                local group = groups[name]
                if not group then
                    group = {
                        text = name,
                        path = makeVirtualPath(chooser.path, name),
                        is_directory = true,
                        is_file = false,
                        mode = "directory",
                        attr = { mode = "directory" },
                        is_vos_series_folder = true,
                        series_books = {},
                        sort_percent = item.sort_percent or 0,
                        percent_finished = item.percent_finished or 0,
                        opened = item.opened or false,
                        doc_props = { display_title = name, series = name },
                    }
                    groups[name] = group
                    output[#output + 1] = group
                end
                group.series_books[#group.series_books + 1] = { item = item, index = index }
            else
                output[#output + 1] = item
            end
        else
            output[#output + 1] = item
        end
    end

    local group_count = 0
    for _, group in pairs(groups) do
        group_count = group_count + 1
        if #group.series_books < 2 then
            for i, entry in ipairs(output) do
                if entry == group then output[i] = group.series_books[1].item; break end
            end
            groups[group.text] = nil
        else
            table.sort(group.series_books, function(a, b)
                if a.index == b.index then
                    return (a.item.text or a.item.path or "") < (b.item.text or b.item.path or "")
                end
                if a.index == 0 then return false end
                if b.index == 0 then return true end
                return a.index < b.index
            end)
            group.mandatory = tostring(#group.series_books) .. " 📁"
            local books = {}
            for _, entry in ipairs(group.series_books) do books[#books + 1] = entry.item end
            group.series_books = books
            cache_by_path[group.path] = group.series_books
        end
    end
    if group_count == 1 and total_books > 0 and books_with_series == total_books then
        return items
    end

    local collate, collate_id = chooser:getCollate()
    local sort_fn = chooser:getSortingFunction(collate, G_reader_settings:isTrue("reverse_collate"))
    local mixed = G_reader_settings:isTrue("collate_mixed") and collate.can_collate_mixed
    if mixed then
        local up, rest = nil, {}
        for _, item in ipairs(output) do
            if item.is_go_up then up = item else rest[#rest + 1] = item end
        end
        pcall(table.sort, rest, sort_fn)
        output = {}
        if up then output[#output + 1] = up end
        for _, item in ipairs(rest) do output[#output + 1] = item end
    else
        local up, dirs, files = nil, {}, {}
        for _, item in ipairs(output) do
            if item.is_go_up then up = item
            elseif isDirectory(item) then dirs[#dirs + 1] = item
            else files[#files + 1] = item end
        end
        pcall(table.sort, dirs, sort_fn)
        output = {}
        if up then output[#output + 1] = up end
        for _, item in ipairs(dirs) do output[#output + 1] = item end
        for _, item in ipairs(files) do output[#output + 1] = item end
    end
    for key in pairs(items) do items[key] = nil end
    for i, item in ipairs(output) do items[i] = item end
    return items
end

function SeriesFolders:open(chooser, group)
    if not (chooser and group and group.series_books) then return end
    active_group = { name = group.text, parent = chooser.path, path = group.path }
    local view = {}
    for _, book in ipairs(group.series_books) do view[#view + 1] = book end
    view.is_in_vos_series = true
    view.parent_path = chooser.path
    view.series_name = group.text
    chooser:switchItemTable(nil, view, nil, nil, group.text)
end

function SeriesFolders:init()
    SeriesFolders.instance = self
    local ok, mosaic = pcall(require, "mosaicmenu")
    if ok and mosaic then
        local upvalue = require("userpatch").getUpValue
        local builder = mosaic._simpleui_native_build or mosaic._updateItemsBuildUI
        local item_class = builder and upvalue(builder, "MosaicMenuItem")
        self.book_info = item_class and upvalue(item_class.update, "BookInfoManager")
    end

    if not FileChooser._vos_series_hooks then
        FileChooser._vos_series_hooks = true
        local original_switch = FileChooser.switchItemTable
        FileChooser.switchItemTable = function(chooser, title, items, ...)
            local mod = SeriesFolders.instance
            if mod and items and not items.is_in_vos_series then
                items = mod:groupItems(items, chooser)
            end
            return original_switch(chooser, title, items, ...)
        end
        local original_select = FileChooser.onMenuSelect
        FileChooser.onMenuSelect = function(chooser, item, ...)
            local mod = SeriesFolders.instance
            if mod and mod:isEnabled() and item and item.is_vos_series_folder then
                mod:open(chooser, item)
                return true
            end
            return original_select(chooser, item, ...)
        end
        local original_up = FileChooser.onFolderUp
        FileChooser.onFolderUp = function(chooser, ...)
            if chooser.item_table and chooser.item_table.is_in_vos_series then
                local parent = chooser.item_table.parent_path
                active_group = nil
                if parent then chooser:changeToPath(parent); return true end
            end
            return original_up(chooser, ...)
        end
        local original_change = FileChooser.changeToPath
        FileChooser.changeToPath = function(chooser, path, ...)
            if chooser.item_table and chooser.item_table.is_in_vos_series then
                path = chooser.item_table.parent_path or path
                active_group = nil
            end
            return original_change(chooser, path, ...)
        end
        local original_refresh = FileChooser.refreshPath
        FileChooser.refreshPath = function(chooser, ...)
            local result = original_refresh(chooser, ...)
            local mod = SeriesFolders.instance
            if mod and mod:isEnabled() and active_group and chooser.item_table then
                for _, item in ipairs(chooser.item_table) do
                    if item.is_vos_series_folder and item.text == active_group.name then
                        mod:open(chooser, item)
                        break
                    end
                end
            end
            return result
        end
    end
end

function SeriesFolders:getMenuItem()
    return {
        text = _("Automatic series folders"),
        checked_func = function() return self:cfg().enabled == true end,
        callback = function()
            self:cfg().enabled = not self:cfg().enabled
            self.settings:save()
            if self.plugin then self.plugin:refresh() end
        end,
    }
end

return SeriesFolders
