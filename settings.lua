--[[--
Settings Manager for Visual Overhaul Suite
Handles loading, saving, and UI for all plugin settings
--]] --

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local SortWidget = require("ui/widget/sortwidget")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local Screen = require("device").screen
local _ = require("gettext")

local SettingsManager = {
    settings_file = nil,
    settings = nil
}

-- Backfill any keys missing from the saved settings. New defaults are added
-- here so older settings files keep working after an upgrade.
local function deepFill(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            deepFill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Generic menu-item builders ------------------------------------------------

local function checkboxItem(self, tree, key, text, plugin, enabled_func)
    return {
        text = _(text),
        checked_func = function()
            return tree[key] == true
        end,
        enabled_func = enabled_func,
        callback = function()
            tree[key] = not (tree[key] == true)
            self:save()
            if plugin then
                plugin:refresh()
            end
        end
    }
end

local function choiceItem(self, tree, key, text, choices, plugin, enabled_func)
    local items = {}
    for index, choice in ipairs(choices) do
        local value = choice.value
        local label = choice.label
        table.insert(
            items,
            {
                text = _(label),
                checked_func = function()
                    return tree[key] == value
                end,
                callback = function()
                    tree[key] = value
                    self:save()
                    if plugin then
                        plugin:refresh()
                    end
                end
            }
        )
    end
    return {
        text = _(text),
        enabled_func = enabled_func,
        sub_item_table = items
    }
end

local function numberItem(self, tree, key, text, plugin, opts)
    opts = opts or {}
    local min = opts.min or 0
    local max = opts.max or 100
    return {
        text = _(text),
        keep_menu_open = true,
        enabled_func = opts.enabled_func,
        callback = function(touchmenu)
            local dlg
            dlg =
                InputDialog:new {
                title = _(text),
                input = tostring(tree[key]),
                hint = opts.hint or _("Enter a number"),
                buttons = {
                    {
                        {text = _("Cancel"), callback = function()
                                UIManager:close(dlg)
                            end},
                        {
                            text = _("Set"),
                            is_enter_default = true,
                            callback = function()
                                local val = tonumber(dlg:getInputText())
                                if val and val >= min and val <= max then
                                    tree[key] = val
                                    self:save()
                                    UIManager:close(dlg)
                                    if touchmenu then
                                        touchmenu:updateItems()
                                    end
                                    if plugin then
                                        plugin:refresh()
                                    end
                                end
                            end
                        }
                    }
                }
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end
    }
end

local function colorItem(self, tree, key, text, plugin, opts)
    opts = opts or {}
    return {
        text = _(text),
        keep_menu_open = true,
        enabled_func = opts.enabled_func,
        callback = function(touchmenu)
            local dlg
            dlg =
                InputDialog:new {
                title = _(text),
                input = tree[key] or "#000000",
                hint = _("Color as #RRGGBB, e.g. #4CAF50"),
                buttons = {
                    {
                        {text = _("Cancel"), callback = function()
                                UIManager:close(dlg)
                            end},
                        {
                            text = _("Set"),
                            is_enter_default = true,
                            callback = function()
                                local val = dlg:getInputText():gsub("%s+", "")
                                if val:match("^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
                                    tree[key] = val
                                    if opts.rgb_key then
                                        tree[opts.rgb_key] = {
                                            tonumber(val:sub(2, 3), 16),
                                            tonumber(val:sub(4, 5), 16),
                                            tonumber(val:sub(6, 7), 16)
                                        }
                                    end
                                    self:save()
                                    UIManager:close(dlg)
                                    if touchmenu then
                                        touchmenu:updateItems()
                                    end
                                    if plugin then
                                        plugin:refresh()
                                    end
                                end
                            end
                        }
                    }
                }
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end
    }
end

function SettingsManager:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function SettingsManager:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/visual_overhaul.lua"
end

function SettingsManager:load()
    self:init()
    local ok, saved = pcall(dofile, self.settings_file)
    if ok and type(saved) == "table" then
        local pages_badge = saved.coverbrowser and saved.coverbrowser.pages_badge
        if pages_badge and pages_badge.move_from_border ~= nil then
            pages_badge.x_offset = pages_badge.x_offset or pages_badge.move_from_border
            pages_badge.y_offset = pages_badge.y_offset or pages_badge.move_from_border
        end
        local folder_covers = saved.coverbrowser and saved.coverbrowser.folder_covers
        if folder_covers and folder_covers.folder_name_position == nil
                and folder_covers.name_centered ~= nil then
            folder_covers.folder_name_position = folder_covers.name_centered and "center" or "top"
        end
        -- Backfill any keys introduced since this settings file was saved.
        deepFill(saved, self:loadDefaults())
        self.settings = saved
    else
        self:loadDefaults()
    end
    logger.info("VisualOverhaul: Settings loaded")
end

function SettingsManager:loadDefaults()
    self.settings = {
        -- Module toggles
        enabled_modules = {
            navbar = true,
            coverbrowser = true,
            progress_bar = false,
            pages_badge = false,
            percent_badge = false,
            series_badge = false,
            status_icons = false,
            collection_star = false,
            faded_finished = false,
            rounded_corners = false,
            hide_pagination = false,
            hide_collection_star = true
        },
        -- Navbar settings
        navbar = {
            size = "medium",
            show_labels = true,
            label_font_size = 14,
            show_top_border = true,
            show_top_gap = false,
            show_in_standalone = true,
            colored = false,
            active_color_index = 0,
            active_tab_styling = true,
            active_tab_bold = true,
            active_tab_underline = true,
            underline_above = true,
            books_label = "Books",
            manga_action = "rakuyomi",
            manga_folder = "",
            news_action = "quickrss",
            news_folder = "",
            show_tabs = {
                books = true,
                manga = true,
                news = true,
                continue = true,
                history = false,
                favorites = false,
                collections = false,
                zlib = false,
                annas = false,
                appstore = false,
                opds = false,
                exit = false,
                page_left = false,
                page_right = false,
                sleep = false,
                restart = false,
                stats = false
            },
            tab_order = {
                "page_left",
                "books",
                "manga",
                "news",
                "continue",
                "history",
                "favorites",
                "collections",
                "zlib",
                "annas",
                "appstore",
                "opds",
                "exit",
                "page_right",
                "sleep",
                "restart",
                "stats"
            },
            custom_tabs = {}
        },
        -- Progress bar settings
        progress_bar = {
            enabled = false,
            height = 9,
            radius = 3,
            inset_x = 6,
            inset_y = 12,
            gap_to_icon = 0,
            border_width = 0.5,
            track_color = "#F4F0EC",
            reading_color = "#4CAF50",
            abandoned_color = "#F44336",
            border_color = "#000000"
        },
        -- Collection-star overlay settings
        collection_star = {
            size = 20,
            x_offset = 6,
            y_offset = 6,
            position = "top_left",
            use_background_circle = true,
            background_color = "#000000"
        },
        -- Optional community-patch integrations
        extras = {
            ui_font_name = "Noto Sans",
            hide_last_visited_underline = true,
            hide_up_folder = true,
            hide_empty_folders = false,
            auto_menu_size = true,
            incognito_enabled = true,
            menu_text = {
                replace_underscores = true,
                restore_articles = true
            },
            page_subtitles = {
                filemanager = true,
                use_shortcut_names = true,
                pathchooser = true,
                history = true,
                collections = true
            }
        },
        -- CoverBrowser (vos.lua) cover enhancements + badges settings
        coverbrowser = {
            rounded_corners = {
                enabled = true
            },
            cover_aspect_ratio = {
                ratio_w = 2,
                ratio_h = 3,
                stretch_limit = 50,
                fill = false
            },
            stretch_covers = {
                enabled = true
            },
            series_indicator = {
                style = "badge", -- "off" | "badge" | "bar"
                font_size = 11,
                border_thickness = 1,
                border_corner_radius = 9,
                text_color = "#000000",
                border_color = "#000000",
                background_color = "#E7E7E7"
            },
            faded_finished = {
                enabled = true,
                fading_amount = 0.5
            },
            progress_bar = {
                enabled = true,
                colored = true,
                hide_native = true,
                position = "bottom",
                bar_h = 9,
                bar_radius = 3,
                inset_x = 6,
                inset_y = 12,
                move_on_x = 0,
                move_on_y = 0,
                gap_to_icon = 0,
                track_color = "#F4F0EC",
                fill_color = "#555555",
                abandoned_color = "#C0C0C0",
                fill_color_rgb = {0x4C, 0xAF, 0x50},
                abandoned_color_rgb = {0xF4, 0x43, 0x36},
                border_w = 0.5,
                border_color = "#000000"
            },
            percent_badge = {
                enabled = true,
                position = "top_right",
                text_size = 0.5,
                move_on_x = 5,
                move_on_y = -1,
                badge_w = 70,
                badge_h = 40,
                bump_up = 1
            },
            pages_badge = {
                enabled = false,
                position = "bottom_left",
                font_size = 0.95,
                border_thickness = 2,
                border_corner_radius = 12,
                text_color = "#FFFFFF",
                border_color = "#888888",
                background_color = "#333333",
                x_offset = 8,
                y_offset = 8
            },
            status_icons = {
                enabled = true
            },
            disable_description_hint = true,
            folder_covers = {
                enabled = true,
                show_folder_name = true,
                name_centered = true,
                folder_name_position = "center",
                file_count_position = "bottom_right",
                file_count_size = 14,
                folder_font_size = 20,
                folder_border = 0.5
            }
        }
    }
    return self.settings
end

function SettingsManager:save()
    local function serializeTable(tbl, indent)
        indent = indent or ""
        local result = "{\n"
        for k, v in pairs(tbl) do
            local key = type(k) == "string" and string.format("[%q]", k) or tostring(k)
            if type(v) == "table" then
                if #v > 0 then
                    result = result .. indent .. "  " .. key .. " = {\n"
                    for _, item in ipairs(v) do
                        if type(item) == "string" then
                            result = result .. indent .. "    " .. string.format("%q", item) .. ",\n"
                        elseif type(item) == "number" then
                            result = result .. indent .. "    " .. item .. ",\n"
                        elseif type(item) == "boolean" then
                            result = result .. indent .. "    " .. tostring(item) .. ",\n"
                        elseif type(item) == "table" then
                            result = result .. indent .. "    " .. serializeTable(item, indent .. "    ") .. ",\n"
                        end
                    end
                    result = result .. indent .. "  },\n"
                else
                    result = result .. indent .. "  " .. key .. " = " .. serializeTable(v, indent .. "  ") .. ",\n"
                end
            elseif type(v) == "string" then
                result = result .. indent .. "  " .. key .. " = " .. string.format("%q", v) .. ",\n"
            elseif type(v) == "boolean" then
                result = result .. indent .. "  " .. key .. " = " .. tostring(v) .. ",\n"
            elseif type(v) == "number" then
                result = result .. indent .. "  " .. key .. " = " .. v .. ",\n"
            end
        end
        result = result .. indent .. "}"
        return result
    end

    local content = "return " .. serializeTable(self.settings)
    local file = io.open(self.settings_file, "w")
    if file then
        file:write(content)
        file:close()
        logger.info("VisualOverhaul: Settings saved")
    end
end

function SettingsManager:isEnabled(module)
    return self.settings.enabled_modules[module] == true
end

function SettingsManager:setEnabled(module, enabled)
    self.settings.enabled_modules[module] = enabled
    self:save()
end

-- Main menu structure - this gets added to the plugin's sub_item_table
function SettingsManager:getMainMenu(plugin)
    local self_ref = self

    return {
        {
            text = _("Navigation Bar"),
            sub_item_table = self:getNavbarMenu(plugin)
        },
        {
            text = _("Enable Cover Enhancements & Badges"),
            checked_func = function()
                return self_ref:isEnabled("coverbrowser")
            end,
            callback = function()
                self_ref:setEnabled("coverbrowser", not self_ref:isEnabled("coverbrowser"))
                if plugin then
                    plugin:refresh()
                end
            end
        },
        {
            text = _("Cover Enhancements"),
            enabled_func = function()
                return self_ref:isEnabled("coverbrowser")
            end,
            sub_item_table = self:getCoverEnhancementsMenu(plugin)
        },
        {
            text = _("Badges"),
            enabled_func = function()
                return self_ref:isEnabled("coverbrowser")
            end,
            sub_item_table = self:getBadgesMenu(plugin)
        },
        {
            text = _("Clean up"),
            sub_item_table = self:getCleanupMenu(plugin)
        },
        {
            text = _("Extras"),
            sub_item_table_func = function()
                local items = {}
                for _, module in ipairs(plugin.extra_modules or {}) do
                    if module.getMenuItem then
                        table.insert(items, module:getMenuItem())
                    end
                end
                return items
            end
        },
        {
            text = _("Reset to Defaults"),
            callback = function(touchmenu_instance)
                UIManager:show(
                    ConfirmBox:new {
                        text = _("Reset all Visual Overhaul settings to defaults?"),
                        ok_text = _("Reset"),
                        ok_callback = function()
                            self_ref:loadDefaults()
                            self_ref:save()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                            UIManager:show(
                                InfoMessage:new {
                                    text = _("Settings reset to defaults"),
                                    timeout = 2
                                }
                            )
                            if plugin then
                                plugin:refresh()
                            end
                        end
                    }
                )
            end
        },
        {
            text = _("Refresh UI"),
            help_text = _("Apply changes without restarting KOReader"),
            separator = true,
            callback = function()
                if plugin then
                    plugin:refresh()
                end
                UIManager:show(
                    InfoMessage:new {
                        text = _("UI refreshed"),
                        timeout = 1
                    }
                )
            end
        },
        {
            text = _("About"),
            callback = function()
                UIManager:show(
                    InfoMessage:new {
                        text = _(
                            "Visual Overhaul Suite (VOS)\n\n" ..
                            "A comprehensive visual customization suite for KOReader.\n\n" ..
                            "Features:\n" ..
                            "  - Custom navigation bar with flexible tab arrangement\n" ..
                            "  - Cover enhancements: rounded corners, aspect ratio, series indicator, folder covers\n" ..
                            "  - Badges: progress bar, percentage, pages, status icons\n" ..
                            "  - Clean up: hide pagination and the description hint bar\n\n" ..
                            "Settings are stored in your KOReader settings directory (visual_overhaul.lua).\n" ..
                            "Use 'Reset to defaults' to restore the factory configuration."
                        )
                    }
                )
            end
        }
    }
end

-- "Clean up" section: UI elements that declutter the file browser.
function SettingsManager:getCleanupMenu(plugin)
    local self_ref = self
    local cb = self.settings.coverbrowser
    return {
        checkboxItem(self, cb, "disable_description_hint", "Disable description hint bar", plugin),
        {
            text = _("Hide pagination"),
            checked_func = function()
                return self_ref:isEnabled("hide_pagination")
            end,
            callback = function()
                self_ref:setEnabled("hide_pagination", not self_ref:isEnabled("hide_pagination"))
                if plugin then
                    plugin:refresh()
                end
            end
        },
        checkboxItem(self, cb.progress_bar, "hide_native", "Hide default progress bar", plugin),
        checkboxItem(
            self, self.settings.enabled_modules, "hide_collection_star",
            "Hide default collection star", plugin
        )
    }
end

function SettingsManager:getCoverEnhancementsMenu(plugin)
    local cb = self.settings.coverbrowser
    return {
        {
            text = _("Rounded corners"),
            sub_item_table = {
                checkboxItem(self, cb.rounded_corners, "enabled", "Enable rounded corners", plugin)
            }
        },
        {
            text = _("Cover aspect ratio"),
            sub_item_table = {
                numberItem(self, cb.cover_aspect_ratio, "ratio_w", "Aspect ratio width", plugin, {min = 1, max = 10}),
                numberItem(self, cb.cover_aspect_ratio, "ratio_h", "Aspect ratio height", plugin, {min = 1, max = 10}),
                numberItem(self, cb.cover_aspect_ratio, "stretch_limit", "Stretch limit (%)", plugin, {min = 0, max = 100}),
                checkboxItem(self, cb.cover_aspect_ratio, "fill", "Fill cover", plugin)
            }
        },
        {
            text = _("Stretch covers"),
            sub_item_table = {
                checkboxItem(self, cb.stretch_covers, "enabled", "Enable stretch covers", plugin)
            }
        },
        {
            text = _("Fade finished books"),
            sub_item_table = {
                checkboxItem(self, cb.faded_finished, "enabled", "Enable faded finished books", plugin),
                numberItem(self, cb.faded_finished, "fading_amount", "Fading amount", plugin, {min = 0, max = 1})
            }
        },
        {
            text = _("Folder covers"),
            sub_item_table = {
                checkboxItem(self, cb.folder_covers, "enabled", "Enable folder covers", plugin),
                checkboxItem(self, cb.folder_covers, "show_folder_name", "Show folder name", plugin),
                choiceItem(self, cb.folder_covers, "folder_name_position", "Folder name position", {
                    {label = "Top", value = "top"},
                    {label = "Center", value = "center"},
                    {label = "Bottom", value = "bottom"}
                }, plugin),
                choiceItem(self, cb.folder_covers, "file_count_position", "File count position", {
                    {label = "Top left", value = "top_left"},
                    {label = "Top center", value = "top_center"},
                    {label = "Top right", value = "top_right"},
                    {label = "Center left", value = "center_left"},
                    {label = "Center right", value = "center_right"},
                    {label = "Bottom left", value = "bottom_left"},
                    {label = "Bottom center", value = "bottom_center"},
                    {label = "Bottom right", value = "bottom_right"}
                }, plugin),
                numberItem(self, cb.folder_covers, "file_count_size", "File count size", plugin, {min = 6, max = 40}),
                numberItem(self, cb.folder_covers, "folder_font_size", "Folder font size", plugin, {min = 6, max = 60}),
                numberItem(self, cb.folder_covers, "folder_border", "Folder border", plugin, {min = 0, max = 10})
            }
        }
    }
end

function SettingsManager:getBadgesMenu(plugin)
    local self_ref = self
    local cb = self.settings.coverbrowser
    local star = self.settings.collection_star
    local function collectionStarEnabled()
        return self_ref:isEnabled("collection_star")
    end
    return {
        {
            text = _("Progress bar"),
            sub_item_table = {
                checkboxItem(self, cb.progress_bar, "enabled", "Enable progress bar", plugin),
				checkboxItem(self, cb.progress_bar, "colored", "Colored", plugin),
                {
                    text = _("Position"),
                    sub_item_table = {
                        {
                            text = _("Top"),
                            radio = true,
                            checked_func = function()
                                return cb.progress_bar.position == "top"
                            end,
                            callback = function()
                                cb.progress_bar.position = "top"
                                self_ref:save()
                                if plugin then
                                    plugin:refresh()
                                end
                            end
                        },
                        {
                            text = _("Bottom"),
                            radio = true,
                            checked_func = function()
                                return cb.progress_bar.position == "bottom"
                            end,
                            callback = function()
                                cb.progress_bar.position = "bottom"
                                self_ref:save()
                                if plugin then
                                    plugin:refresh()
                                end
                            end
                        },
                        numberItem(self, cb.progress_bar, "inset_y", "Distance from edge", plugin, {min = 0, max = 300}),
                        numberItem(self, cb.progress_bar, "move_on_x", "Move left/right", plugin, {min = -300, max = 300}),
                        numberItem(self, cb.progress_bar, "move_on_y", "Move up/down", plugin, {min = -300, max = 300}),
                        numberItem(self, cb.progress_bar, "gap_to_icon", "Gap to icon", plugin, {min = 0, max = 100}),
                        numberItem(self, cb.progress_bar, "inset_x", "Horizontal inset", plugin, {min = 0, max = 300})
                    }
                },
                {
                    text = _("Colors"),
                    sub_item_table = {
                        colorItem(self, cb.progress_bar, "track_color", "Background color", plugin),
                        colorItem(self, cb.progress_bar, "fill_color", "Fill color", plugin, {rgb_key = "fill_color_rgb"}),
                        colorItem(self, cb.progress_bar, "abandoned_color", "Abandoned color", plugin, {rgb_key = "abandoned_color_rgb"})
                    }
                },
                {
                    text = _("Shape"),
                    sub_item_table = {
                        numberItem(self, cb.progress_bar, "bar_h", "Bar height", plugin, {min = 1, max = 30}),
                        numberItem(self, cb.progress_bar, "bar_radius", "Bar radius", plugin, {min = 0, max = 15})
                    }
                }
            }
        },
        {
            text = _("Percentage badge"),
            sub_item_table = {
                checkboxItem(self, cb.percent_badge, "enabled", "Enable percentage badge", plugin),
                choiceItem(self, cb.percent_badge, "position", "Position", {
                    {label = "Top left", value = "top_left"},
                    {label = "Top right", value = "top_right"},
                    {label = "Bottom left", value = "bottom_left"},
                    {label = "Bottom right", value = "bottom_right"}
                }, plugin),
                numberItem(self, cb.percent_badge, "text_size", "Text size", plugin, {min = 0.1, max = 2}),
                numberItem(self, cb.percent_badge, "move_on_x", "Horizontal offset", plugin, {min = -300, max = 300}),
                numberItem(self, cb.percent_badge, "move_on_y", "Vertical offset", plugin, {min = -300, max = 300}),
                numberItem(self, cb.percent_badge, "badge_w", "Badge width", plugin, {min = 20, max = 200}),
                numberItem(self, cb.percent_badge, "badge_h", "Badge height", plugin, {min = 20, max = 200}),
                numberItem(self, cb.percent_badge, "bump_up", "Bump up", plugin, {min = 0, max = 10})
            }
        },
        {
            text = _("Pages badge"),
            sub_item_table = {
                checkboxItem(self, cb.pages_badge, "enabled", "Enable pages badge", plugin),
                choiceItem(self, cb.pages_badge, "position", "Position", {
                    {label = "Top left", value = "top_left"},
                    {label = "Top right", value = "top_right"},
                    {label = "Bottom left", value = "bottom_left"},
                    {label = "Bottom right", value = "bottom_right"}
                }, plugin),
                numberItem(self, cb.pages_badge, "font_size", "Font size", plugin, {min = 0.1, max = 2}),
                numberItem(self, cb.pages_badge, "border_thickness", "Border thickness", plugin, {min = 0, max = 10}),
                numberItem(self, cb.pages_badge, "border_corner_radius", "Border corner radius", plugin, {min = 0, max = 30}),
                numberItem(self, cb.pages_badge, "x_offset", "Horizontal offset", plugin, {min = -300, max = 300}),
                numberItem(self, cb.pages_badge, "y_offset", "Vertical offset", plugin, {min = -300, max = 300}),
                {
                    text = _("Colors"),
                    sub_item_table = {
                        colorItem(self, cb.pages_badge, "text_color", "Text color", plugin),
                        colorItem(self, cb.pages_badge, "background_color", "Background color", plugin),
                        colorItem(self, cb.pages_badge, "border_color", "Border color", plugin)
                    }
                }
            }
        },
		{
            text = _("Series indicator"),
            sub_item_table = {
                choiceItem(self, cb.series_indicator, "style", "Style", {
                    {label = "Off", value = "off"},
                    {label = "Badge", value = "badge"},
                    {label = "Flap", value = "bar"}
                }, plugin),
                numberItem(self, cb.series_indicator, "font_size", "Font size", plugin, {min = 6, max = 40}),
                numberItem(self, cb.series_indicator, "border_thickness", "Border thickness", plugin, {min = 0, max = 10}),
                numberItem(self, cb.series_indicator, "border_corner_radius", "Border corner radius", plugin, {min = 0, max = 30}),
                colorItem(self, cb.series_indicator, "text_color", "Text color", plugin),
                colorItem(self, cb.series_indicator, "border_color", "Border color", plugin),
                colorItem(self, cb.series_indicator, "background_color", "Background color", plugin)
            }
        },
        {
            text = _("Status icons"),
            sub_item_table = {
                checkboxItem(self, cb.status_icons, "enabled", "Enable status icons", plugin)
            }
        },
        {
            text = _("Collection star"),
            sub_item_table = {
                {
                    text = _("Enable collection star"),
                    checked_func = collectionStarEnabled,
                    callback = function()
                        self_ref:setEnabled("collection_star", not collectionStarEnabled())
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                choiceItem(self, star, "position", "Position", {
                    {label = "Top left", value = "top_left"},
                    {label = "Top right", value = "top_right"},
                    {label = "Bottom left", value = "bottom_left"},
                    {label = "Bottom right", value = "bottom_right"}
                }, plugin, collectionStarEnabled),
                numberItem(self, star, "size", "Size", plugin, {
                    min = 8,
                    max = 100,
                    enabled_func = collectionStarEnabled
                }),
                numberItem(self, star, "x_offset", "Horizontal offset", plugin, {
                    min = 0,
                    max = 100,
                    enabled_func = collectionStarEnabled
                }),
                numberItem(self, star, "y_offset", "Vertical offset", plugin, {
                    min = 0,
                    max = 100,
                    enabled_func = collectionStarEnabled
                }),
                checkboxItem(
                    self, star, "use_background_circle", "Use background circle", plugin,
                    collectionStarEnabled
                ),
                colorItem(self, star, "background_color", "Background color", plugin, {
                    enabled_func = function()
                        return collectionStarEnabled() and star.use_background_circle
                    end
                })
            }
        }
    }
end

function SettingsManager:getNavbarMenu(plugin)
    local self_ref = self
    local navbar = self.settings.navbar
    local kaleido_colors = {
        {name = "Default Blue", color = {0x33, 0x99, 0xFF}},
        {name = "Ocean Blue", color = {0x1E, 0x88, 0xE5}},
        {name = "Forest Green", color = {0x43, 0xA0, 0x47}},
        {name = "Sunset Orange", color = {0xFF, 0x6F, 0x00}},
        {name = "Royal Purple", color = {0x7B, 0x1F, 0xA2}},
        {name = "Coral Pink", color = {0xFF, 0x70, 0x43}},
        {name = "Mint Green", color = {0x00, 0x89, 0x7B}},
        {name = "Gold", color = {0xFF, 0xA7, 0x26}},
        {name = "Ruby Red", color = {0xE5, 0x39, 0x35}},
        {name = "Slate Blue", color = {0x5C, 0x6B, 0xC0}},
        {name = "Teal", color = {0x00, 0x97, 0xA7}}
    }

    return {
        {
            text = _("Enable NavBar"),
            checked_func = function()
                return self_ref:isEnabled("navbar")
            end,
            callback = function()
                self_ref:setEnabled("navbar", not self_ref:isEnabled("navbar"))
                if plugin then
                    plugin:refresh()
                end
            end
        },
        {
            text = _("Size"),
            sub_item_table = {
                {
                    text = "Tiny",
                    checked_func = function()
                        return navbar.size == "tiny"
                    end,
                    callback = function()
                        navbar.size = "tiny"
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "Small",
                    checked_func = function()
                        return navbar.size == "small"
                    end,
                    callback = function()
                        navbar.size = "small"
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "Medium",
                    checked_func = function()
                        return navbar.size == "medium"
                    end,
                    callback = function()
                        navbar.size = "medium"
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "Large",
                    checked_func = function()
                        return navbar.size == "large"
                    end,
                    callback = function()
                        navbar.size = "large"
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "Huge",
                    checked_func = function()
                        return navbar.size == "huge"
                    end,
                    callback = function()
                        navbar.size = "huge"
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                }
            }
        },
        {
            text = _("Show labels"),
            checked_func = function()
                return navbar.show_labels
            end,
            callback = function()
                navbar.show_labels = not navbar.show_labels
                self_ref:save()
                if plugin then
                    plugin:refresh()
                end
            end
        },
        {
            text = _("Label font size"),
            enabled_func = function()
                return navbar.show_labels
            end,
            sub_item_table = {
                {
                    text = "12",
                    checked_func = function()
                        return navbar.label_font_size == 12
                    end,
                    callback = function()
                        navbar.label_font_size = 12
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "14",
                    checked_func = function()
                        return navbar.label_font_size == 14
                    end,
                    callback = function()
                        navbar.label_font_size = 14
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "16",
                    checked_func = function()
                        return navbar.label_font_size == 16
                    end,
                    callback = function()
                        navbar.label_font_size = 16
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = "18",
                    checked_func = function()
                        return navbar.label_font_size == 18
                    end,
                    callback = function()
                        navbar.label_font_size = 18
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Custom"),
                    keep_menu_open = true,
                    callback = function(touchmenu)
                        local dlg
                        dlg =
                            InputDialog:new {
                            title = _("Font size"),
                            input = tostring(navbar.label_font_size),
                            hint = _("Enter font size (5-30)"),
                            buttons = {
                                {
                                    {text = _("Cancel"), callback = function()
                                            UIManager:close(dlg)
                                        end},
                                    {
                                        text = _("Set"),
                                        is_enter_default = true,
                                        callback = function()
                                            local size = tonumber(dlg:getInputText())
                                            if size and size >= 5 and size <= 30 then
                                                navbar.label_font_size = size
                                                self_ref:save()
                                                UIManager:close(dlg)
                                                if touchmenu then
                                                    touchmenu:updateItems()
                                                end
                                                if plugin then
                                                    plugin:refresh()
                                                end
                                            end
                                        end
                                    }
                                }
                            }
                        }
                        UIManager:show(dlg)
                        dlg:onShowKeyboard()
                    end
                }
            }
        },
        {
            text = _("Show top border"),
            checked_func = function()
                return navbar.show_top_border
            end,
            callback = function()
                navbar.show_top_border = not navbar.show_top_border
                self_ref:save()
                if plugin then
                    plugin:refresh()
                end
            end
        },
        {
            text = _("Show top gap"),
            checked_func = function()
                return navbar.show_top_gap
            end,
            callback = function()
                navbar.show_top_gap = not navbar.show_top_gap
                self_ref:save()
                if plugin then
                    plugin:refresh()
                end
            end
        },
        {
            text = _("Show in standalone views"),
            checked_func = function()
                return navbar.show_in_standalone
            end,
            callback = function()
                navbar.show_in_standalone = not navbar.show_in_standalone
                self_ref:save()
                if plugin then
                    plugin:refresh()
                end
            end
        },
        {
            text = _("Active tab"),
            sub_item_table = {
                {
                    text = _("Enable styling"),
                    checked_func = function()
                        return navbar.active_tab_styling
                    end,
                    callback = function()
                        navbar.active_tab_styling = not navbar.active_tab_styling
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Bold"),
                    enabled_func = function()
                        return navbar.active_tab_styling
                    end,
                    checked_func = function()
                        return navbar.active_tab_bold
                    end,
                    callback = function()
                        navbar.active_tab_bold = not navbar.active_tab_bold
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Underline"),
                    enabled_func = function()
                        return navbar.active_tab_styling
                    end,
                    checked_func = function()
                        return navbar.active_tab_underline
                    end,
                    callback = function()
                        navbar.active_tab_underline = not navbar.active_tab_underline
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text_func = function()
                        return _("Underline location: ") .. (navbar.underline_above and _("above") or _("below"))
                    end,
                    enabled_func = function()
                        return navbar.active_tab_styling and navbar.active_tab_underline
                    end,
                    callback = function()
                        navbar.underline_above = not navbar.underline_above
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Colored"),
                    enabled_func = function()
                        return navbar.active_tab_styling
                    end,
                    checked_func = function()
                        return navbar.colored
                    end,
                    callback = function()
                        navbar.colored = not navbar.colored
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text_func = function()
                        local color = kaleido_colors[navbar.active_color_index + 1] or kaleido_colors[1]
                        return _("Color: ") .. color.name
                    end,
                    enabled_func = function()
                        return navbar.active_tab_styling and navbar.colored and Screen:isColorScreen()
                    end,
                    sub_item_table = (function()
                        local items = {}
                        for i, color in ipairs(kaleido_colors) do
                            table.insert(
                                items,
                                {
                                    text = _(color.name),
                                    checked_func = function()
                                        return navbar.active_color_index == i - 1
                                    end,
                                    callback = function()
                                        navbar.active_color_index = i - 1
                                        self_ref:save()
                                        if plugin then
                                            plugin:refresh()
                                        end
                                    end
                                }
                            )
                        end
                        return items
                    end)()
                }
            }
        },
        {
            text = _("Tabs"),
            sub_item_table = {
                {
                    text = _("Arrange tabs"),
                    keep_menu_open = true,
                    callback = function(touchmenu)
                        local sort_items = {}
                        local custom_by_id = {}
                        for _, ct in ipairs(navbar.custom_tabs) do
                            custom_by_id[ct.id] = ct.label
                        end
                        for index, id in ipairs(navbar.tab_order) do
                            local label
                            if custom_by_id[id] then
                                label = custom_by_id[id]
                            elseif id == "books" then
                                label = self_ref:getBooksLabel()
                            elseif id == "page_left" then
                                label = _("Prev")
                            elseif id == "page_right" then
                                label = _("Next")
                            else
                                label = _(id:gsub("^%l", string.upper))
                            end
                            table.insert(
                                sort_items,
                                {
                                    text = label,
                                    orig_item = id,
                                    dim = not navbar.show_tabs[id]
                                }
                            )
                        end
                        UIManager:show(
                            SortWidget:new {
                                title = _("Arrange NavBar tabs"),
                                item_table = sort_items,
                                callback = function()
                                    for i, item in ipairs(sort_items) do
                                        navbar.tab_order[i] = item.orig_item
                                    end
                                    self_ref:save()
                                    if touchmenu then
                                        touchmenu:updateItems()
                                    end
                                    if plugin then
                                        plugin:refresh()
                                    end
                                end
                            }
                        )
                    end
                },
                -- Add individual tab toggles
                {
                    text = _("Books"),
                    checked_func = function()
                        return navbar.show_tabs.books
                    end,
                    callback = function()
                        navbar.show_tabs.books = not navbar.show_tabs.books
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Manga"),
                    checked_func = function()
                        return navbar.show_tabs.manga
                    end,
                    callback = function()
                        navbar.show_tabs.manga = not navbar.show_tabs.manga
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("News"),
                    checked_func = function()
                        return navbar.show_tabs.news
                    end,
                    callback = function()
                        navbar.show_tabs.news = not navbar.show_tabs.news
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Continue"),
                    checked_func = function()
                        return navbar.show_tabs.continue
                    end,
                    callback = function()
                        navbar.show_tabs.continue = not navbar.show_tabs.continue
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("History"),
                    checked_func = function()
                        return navbar.show_tabs.history
                    end,
                    callback = function()
                        navbar.show_tabs.history = not navbar.show_tabs.history
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Favorites"),
                    checked_func = function()
                        return navbar.show_tabs.favorites
                    end,
                    callback = function()
                        navbar.show_tabs.favorites = not navbar.show_tabs.favorites
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Collections"),
                    checked_func = function()
                        return navbar.show_tabs.collections
                    end,
                    callback = function()
                        navbar.show_tabs.collections = not navbar.show_tabs.collections
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Z-Lib"),
                    checked_func = function()
                        return navbar.show_tabs.zlib
                    end,
                    callback = function()
                        navbar.show_tabs.zlib = not navbar.show_tabs.zlib
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Anna's Archive"),
                    checked_func = function()
                        return navbar.show_tabs.annas
                    end,
                    callback = function()
                        navbar.show_tabs.annas = not navbar.show_tabs.annas
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("AppStore"),
                    checked_func = function()
                        return navbar.show_tabs.appstore
                    end,
                    callback = function()
                        navbar.show_tabs.appstore = not navbar.show_tabs.appstore
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("OPDS"),
                    checked_func = function()
                        return navbar.show_tabs.opds
                    end,
                    callback = function()
                        navbar.show_tabs.opds = not navbar.show_tabs.opds
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Reading Stats"),
                    checked_func = function()
                        return navbar.show_tabs.stats
                    end,
                    callback = function()
                        navbar.show_tabs.stats = not navbar.show_tabs.stats
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Exit"),
                    checked_func = function()
                        return navbar.show_tabs.exit
                    end,
                    callback = function()
                        navbar.show_tabs.exit = not navbar.show_tabs.exit
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Sleep"),
                    checked_func = function()
                        return navbar.show_tabs.sleep
                    end,
                    callback = function()
                        navbar.show_tabs.sleep = not navbar.show_tabs.sleep
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Restart"),
                    checked_func = function()
                        return navbar.show_tabs.restart
                    end,
                    callback = function()
                        navbar.show_tabs.restart = not navbar.show_tabs.restart
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Previous page"),
                    checked_func = function()
                        return navbar.show_tabs.page_left
                    end,
                    callback = function()
                        navbar.show_tabs.page_left = not navbar.show_tabs.page_left
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                },
                {
                    text = _("Next page"),
                    checked_func = function()
                        return navbar.show_tabs.page_right
                    end,
                    callback = function()
                        navbar.show_tabs.page_right = not navbar.show_tabs.page_right
                        self_ref:save()
                        if plugin then
                            plugin:refresh()
                        end
                    end
                }
            }
        },
        {
            text = _("Custom tabs"),
            sub_item_table_func = function()
                local items = {}

                -- List existing custom tabs
                for i, ct in ipairs(navbar.custom_tabs) do
                    local idx = i
                    table.insert(
                        items,
                        {
                            text_func = function()
                                local detail = ct.source == "folder" and "📁" or (ct.fm_key and "🔌" or "⚡")
                                return ct.label .. "  [" .. detail .. "]"
                            end,
                            checked_func = function()
                                return navbar.show_tabs[ct.id]
                            end,
                            callback = function()
                                navbar.show_tabs[ct.id] = not navbar.show_tabs[ct.id]
                                self_ref:save()
                                if plugin then
                                    plugin:refresh()
                                end
                            end,
                            hold_callback = function(touchmenu)
                                UIManager:show(
                                    ConfirmBox:new {
                                        text = _("Remove tab '") .. ct.label .. _("'?"),
                                        ok_callback = function()
                                            navbar.show_tabs[ct.id] = nil
                                            for j = #navbar.tab_order, 1, -1 do
                                                if navbar.tab_order[j] == ct.id then
                                                    table.remove(navbar.tab_order, j)
                                                end
                                            end
                                            table.remove(navbar.custom_tabs, idx)
                                            self_ref:save()
                                            if touchmenu then
                                                touchmenu:updateItems()
                                            end
                                            if plugin then
                                                plugin:refresh()
                                            end
                                        end
                                    }
                                )
                            end
                        }
                    )
                end

                -- Add folder tab option
                table.insert(
                    items,
                    {
                        text = _("+ Add folder tab"),
                        separator = true,
                        callback = function(touchmenu)
                            local path_chooser =
                                PathChooser:new {
                                select_file = false,
                                show_files = false,
                                path = G_reader_settings:readSetting("lastdir") or "/",
                                onConfirm = function(dir_path)
                                    local icon_dlg
                                    icon_dlg =
                                        InputDialog:new {
                                        title = _("Icon filename"),
                                        hint = _("e.g., appbar.filebrowser"),
                                        input = "appbar.filebrowser",
                                        buttons = {
                                            {
                                                {text = _("Cancel"), callback = function()
                                                        UIManager:close(icon_dlg)
                                                    end},
                                                {
                                                    text = _("Next"),
                                                    is_enter_default = true,
                                                    callback = function()
                                                        local icon = icon_dlg:getInputText() or "appbar.filebrowser"
                                                        UIManager:close(icon_dlg)
                                                        local util = require("util")
                                                        local folder_name = select(2, util.splitFilePathName(dir_path))
                                                        local label_dlg
                                                        label_dlg =
                                                            InputDialog:new {
                                                            title = _("Tab label"),
                                                            input = folder_name or "Folder",
                                                            buttons = {
                                                                {
                                                                    {text = _("Cancel"), callback = function()
                                                                            UIManager:close(label_dlg)
                                                                        end},
                                                                    {
                                                                        text = _("Add tab"),
                                                                        is_enter_default = true,
                                                                        callback = function()
                                                                            local label =
                                                                                label_dlg:getInputText() or folder_name or
                                                                                "Folder"
                                                                            UIManager:close(label_dlg)
                                                                            local new_id =
                                                                                "folder_" .. dir_path:gsub("[^%w]", "_")
                                                                            local new_ct = {
                                                                                id = new_id,
                                                                                label = label,
                                                                                icon = icon,
                                                                                source = "folder",
                                                                                folder_path = dir_path
                                                                            }
                                                                            local found = false
                                                                            for i, ct in ipairs(navbar.custom_tabs) do
                                                                                if ct.id == new_id then
                                                                                    navbar.custom_tabs[i] = new_ct
                                                                                    found = true
                                                                                    break
                                                                                end
                                                                            end
                                                                            if not found then
                                                                                table.insert(navbar.custom_tabs, new_ct)
                                                                                navbar.show_tabs[new_id] = true
                                                                                table.insert(navbar.tab_order, new_id)
                                                                            end
                                                                            self_ref:save()
                                                                            if touchmenu then
                                                                                touchmenu:updateItems()
                                                                            end
                                                                            if plugin then
                                                                                plugin:refresh()
                                                                            end
                                                                            UIManager:show(
                                                                                InfoMessage:new {
                                                                                    text = _(
                                                                                        "Folder tab added!"
                                                                                    ),
                                                                                    timeout = 2
                                                                                }
                                                                            )
                                                                        end
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        UIManager:show(label_dlg)
                                                        label_dlg:onShowKeyboard()
                                                    end
                                                }
                                            }
                                        }
                                    }
                                    UIManager:show(icon_dlg)
                                    icon_dlg:onShowKeyboard()
                                end
                            }
                            UIManager:show(path_chooser)
                        end
                    }
                )

                return items
            end
        },
        {
            text = _("Refresh NavBar"),
            separator = true,
            callback = function()
                if plugin then
                    plugin:refresh()
                end
            end
        }
    }
end

function SettingsManager:getBooksLabel()
    return self.settings.navbar.books_label ~= "" and self.settings.navbar.books_label or "Books"
end

return SettingsManager
