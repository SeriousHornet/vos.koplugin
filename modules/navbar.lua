-- Hooks and active navigation state are process-wide so recreated FileManager
-- instances share one navbar configuration.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local vosicons = require("modules/vosicons")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

-- Global hooks always read the latest settings manager.
local SETTINGS_MANAGER = nil
local function cfg()
    return SETTINGS_MANAGER.settings.navbar
end

local function navbarEnabled()
    return SETTINGS_MANAGER ~= nil
        and SETTINGS_MANAGER:isMasterEnabled()
        and SETTINGS_MANAGER:isEnabled("navbar")
end

local active_tab = "books"
local GLOBAL_PATCHED = false
local qrss_hooked = false
local standalone_views = setmetatable({}, { __mode = "k" })

local navbar_icon_size
local navbar_font
local navbar_font_bold
local navbar_v_padding
local navbar_h_padding = Screen:scaleBySize(10)
local navbar_top_gap = Screen:scaleBySize(10)
local underline_thickness = Screen:scaleBySize(2)
local corner_dead_zone = math.floor(Screen:getWidth() / 12)

local size_presets = {
    tiny = { icon = 16, font = "xx_smallinfofont", bold_font = "smallinfofontbold", padding = 2, font_size = 12 },
    small = { icon = 22, font = "xx_smallinfofont", bold_font = "x_smallinfofont", padding = 3, font_size = 14 },
    medium = { icon = 30, font = "x_smallinfofont", bold_font = "smallinfofontbold", padding = 4, font_size = 18 },
    large = { icon = 40, font = "smallinfofont", bold_font = "smallinfofontbold", padding = 6, font_size = 22 },
    huge = { icon = 50, font = "infofont", bold_font = "tfont", padding = 8, font_size = 26 },
}

local kaleido_colors = {
    { name = "Ocean Blue", color = { 0x1E, 0x88, 0xE5 } },
    { name = "Forest Green", color = { 0x43, 0xA0, 0x47 } },
    { name = "Sunset Orange", color = { 0xFF, 0x6F, 0x00 } },
    { name = "Royal Purple", color = { 0x7B, 0x1F, 0xA2 } },
    { name = "Coral Pink", color = { 0xFF, 0x70, 0x43 } },
    { name = "Mint Green", color = { 0x00, 0x89, 0x7B } },
    { name = "Gold", color = { 0xFF, 0xA7, 0x26 } },
    { name = "Ruby Red", color = { 0xE5, 0x39, 0x35 } },
    { name = "Slate Blue", color = { 0x5C, 0x6B, 0xC0 } },
    { name = "Teal", color = { 0x00, 0x97, 0xA7 } },
}

local function updateLayoutConstants()
    local c = cfg()
    local size_preset = size_presets[c.size] or size_presets.medium
    navbar_icon_size = Screen:scaleBySize(size_preset.icon)

    local font_size = c.label_font_size or size_preset.font_size
    navbar_font = Font:getFace(size_preset.font, font_size)
    navbar_font_bold = Font:getFace(size_preset.bold_font, font_size)
    navbar_v_padding = Screen:scaleBySize(size_preset.padding)

    if c.active_color_index == 0 then
        c.active_tab_color = { 0x33, 0x99, 0xFF }
    elseif kaleido_colors[c.active_color_index] then
        c.active_tab_color = kaleido_colors[c.active_color_index].color
    end
end

-- Tab definitions

local function getBooksLabel()
    local c = cfg()
    return c.books_label ~= "" and c.books_label or "Books"
end

local tabs = {
    { id = "books", label = "Books", icon = "tab_books" },
    { id = "manga", label = _("Manga"), icon = "tab_manga" },
    { id = "news", label = _("News"), icon = "tab_news" },
    { id = "continue", label = _("Continue"), icon = "tab_continue" },
    { id = "history", label = _("History"), icon = "tab_history" },
    { id = "favorites", label = _("Favorites"), icon = "tab_favorites" },
    { id = "collections", label = _("Collections"), icon = "tab_collections" },
    { id = "zlib", label = _("Z-Lib"), icon = "appbar.search" },
    { id = "annas", label = _("Anna's"), icon = "appbar.search" },
    { id = "appstore", label = _("AppStore"), icon = "tab_collections" },
    { id = "opds", label = _("OPDS"), icon = "appbar.filebrowser" },
    { id = "exit", label = _("Exit"), icon = "tab_exit" },
    { id = "page_left", label = _("Prev"), icon = "tab_left" },
    { id = "page_right", label = _("Next"), icon = "tab_right" },
    { id = "sleep", label = _("Sleep"), icon = "tab_sleep" },
    { id = "restart", label = _("Restart"), icon = "tab_restart" },
    { id = "stats", label = _("Stats"), icon = "tab_stats" },
}

local tabs_by_id = {}
for _, tab in ipairs(tabs) do
    tabs_by_id[tab.id] = tab
end

-- Rebuilds the custom-tab entries in `tabs`/`tabs_by_id` from cfg().custom_tabs.
-- Safe to call repeatedly (e.g. after the settings menu adds/removes a tab).
local function registerCustomTabs()
    for i = #tabs, 1, -1 do
        if tabs[i].is_custom then
            table.remove(tabs, i)
        end
    end
    local stale_custom_ids = {}
    for k, v in pairs(tabs_by_id) do
        if v.is_custom then
            table.insert(stale_custom_ids, k)
        end
    end
    for _, k in ipairs(stale_custom_ids) do
        tabs_by_id[k] = nil
    end
    local c = cfg()
    for _, ct in ipairs(c.custom_tabs) do
        if ct.id and ct.label then
            local entry = { id = ct.id, label = ct.label, icon = ct.icon or "appbar.search", is_custom = true }
            table.insert(tabs, entry)
            tabs_by_id[ct.id] = entry
            if c.show_tabs[ct.id] == nil then
                c.show_tabs[ct.id] = true
            end
        end
    end
    for j = #c.tab_order, 1, -1 do
        local id = c.tab_order[j]
        if not tabs_by_id[id] then
            table.remove(c.tab_order, j)
            c.show_tabs[id] = nil
        end
    end
end

-- Forward declarations (mutually referencing functions defined further down)
local injectNavbar
local injectStandaloneNavbar
local hookQuickRSSInit
local createNavBar
local getTabCallback

local function setActiveTab(tab_id)
    if not navbarEnabled() then
        return
    end
    if active_tab == tab_id then
        return
    end
    active_tab = tab_id
    updateLayoutConstants()
    local fm = FileManager.instance
    if fm then
        injectNavbar(fm)
        UIManager:setDirty(fm, "ui")
    end
end

-- Tab callbacks

local function onTabBooks()
    local fm = FileManager.instance
    if not fm then
        return
    end
    local home_dir = G_reader_settings:readSetting("home_dir")
        or require("apps/filemanager/filemanagerutil").getDefaultDir()
    fm.file_chooser.path_items[home_dir] = nil
    fm.file_chooser:changeToPath(home_dir)
end

local function onTabManga()
    local fm = FileManager.instance
    if not fm then
        return
    end
    local c = cfg()

    if c.manga_action == "folder" and c.manga_folder ~= "" then
        if lfs.attributes(c.manga_folder, "mode") == "directory" then
            fm.file_chooser:changeToPath(c.manga_folder)
        else
            UIManager:show(InfoMessage:new { text = _("Manga folder not found: ") .. c.manga_folder })
        end
        return
    end

    local rakuyomi = fm.rakuyomi
    if rakuyomi then
        rakuyomi:openLibraryView()
    else
        UIManager:show(InfoMessage:new { text = _("Rakuyomi plugin is not installed.") })
    end
end

local function onTabNews()
    local fm = FileManager.instance
    if not fm then
        return
    end
    local c = cfg()

    if c.news_action == "folder" and c.news_folder ~= "" then
        if lfs.attributes(c.news_folder, "mode") == "directory" then
            fm.file_chooser:changeToPath(c.news_folder)
        else
            UIManager:show(InfoMessage:new { text = _("News folder not found: ") .. c.news_folder })
        end
        return
    end

    hookQuickRSSInit()
    local ok, QuickRSSUI = pcall(require, "modules/ui/feed_view")
    if ok and QuickRSSUI then
        UIManager:show(QuickRSSUI:new {})
    else
        UIManager:show(InfoMessage:new { text = _("QuickRSS plugin is not installed.") })
    end
end

local function onTabContinue()
    local last_file = G_reader_settings:readSetting("lastfile")
    if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new { text = _("Cannot open last document") })
        return
    end
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(last_file)
end

local function onTabHistory()
    local fm = FileManager.instance
    if fm and fm.history then
        fm.history:onShowHist()
    end
end

local function onTabFavorites()
    local fm = FileManager.instance
    if fm and fm.collections then
        fm.collections:onShowColl()
    end
end

local function onTabCollections()
    local fm = FileManager.instance
    if fm and fm.collections then
        fm.collections:onShowCollList()
    end
end

local function onTabExit()
    local fm = FileManager.instance
    UIManager:show(ConfirmBox:new {
        text = _("Exit KOReader?"),
        ok_text = _("Exit"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            if fm then
                fm:onClose()
            end
        end,
    })
end

local function onTabPageLeft()
    local fm = FileManager.instance
    if fm and fm.file_chooser then
        fm.file_chooser:onPrevPage()
    end
end

local function onTabPageRight()
    local fm = FileManager.instance
    if fm and fm.file_chooser then
        fm.file_chooser:onNextPage()
    end
end

local function onTabSleep()
    UIManager:show(ConfirmBox:new {
        text = _("Put device to sleep?"),
        ok_text = _("Sleep"),
        ok_callback = function()
            if Device:canSuspend() then
                UIManager:broadcastEvent(Event:new("RequestSuspend"))
            elseif Device:canPowerOff() then
                UIManager:broadcastEvent(Event:new("RequestPowerOff"))
            end
        end,
    })
end

local function onTabRestart()
    UIManager:show(ConfirmBox:new {
        text = _("Restart KOReader?"),
        ok_text = _("Restart"),
        ok_callback = function()
            UIManager:restartKOReader()
        end,
    })
end

-- Reading Insights is exposed through its FileManager registration.
local function onTabStats()
    local fm = FileManager.instance
    local reading_insights = fm and fm.readinginsights
    if reading_insights then
        setActiveTab("stats")
        UIManager:sendEvent(Event:new("ShowReadingInsightsPopup"))
    else
        UIManager:show(
            InfoMessage:new { text = _("Reading insights plugin (readinginsights.koplugin) is not installed.") }
        )
    end
end

local function onTabZlib()
    local fm = FileManager.instance
    if not fm then
        return
    end

    local zlibrary = fm["Z-library"] or fm["zlibrary"] or fm["Zlibrary"] or fm["z-library"]
    if zlibrary then
        zlibrary:showMultiSearchDialog()
        return
    end
    for k, v in pairs(fm) do
        if type(k) == "string" and k:lower():find("z.lib") and type(v) == "table" and v.showMultiSearchDialog then
            v:showMultiSearchDialog()
            return
        end
    end
    UIManager:show(InfoMessage:new { text = _("zlibrary.koplugin is not installed.") })
end

local function onTabAnnas()
    local fm = FileManager.instance
    if not fm then
        return
    end

    local annas = fm["Anna's Archive"] or fm["annas"] or fm["annasarchive"]
    if not annas then
        for k, v in pairs(fm) do
            if type(k) == "string" and k:lower():find("anna") and type(v) == "table" and v.showSearchDialog then
                annas = v
                break
            end
        end
    end
    if annas then
        if annas.showSearchDialog then
            annas:showSearchDialog()
        elseif annas.onZlibrarySearch then
            annas:onZlibrarySearch()
        elseif annas.showMultiSearchDialog then
            annas:showMultiSearchDialog()
        else
            UIManager:show(InfoMessage:new { text = _("Could not open Anna's Archive plugin.") })
        end
    else
        UIManager:show(InfoMessage:new { text = _("annas.koplugin is not installed.") })
    end
end

local function onTabAppStore()
    local fm = FileManager.instance
    if not fm then
        return
    end
    local appstore = fm.appstore
    if appstore then
        appstore:showBrowser()
    else
        UIManager:show(InfoMessage:new { text = _("appstore.koplugin is not installed.") })
    end
end

local function onTabOpds()
    local fm = FileManager.instance
    if not fm then
        return
    end

    local opds = fm.opds
    if not opds then
        UIManager:show(
            InfoMessage:new { text = _("OPDS plugin is not enabled.\nEnable it in Settings > Plugins."), timeout = 4 }
        )
        return
    end

    local servers = opds.servers or {}

    local function openFullBrowser()
        opds:onShowOPDSCatalog()
    end

    local function openServer(server)
        local OPDSBrowser = require("opdsbrowser")
        local browser
        browser = OPDSBrowser:new {
            servers = opds.servers,
            downloads = opds.downloads,
            settings = opds.settings,
            pending_syncs = opds.pending_syncs,
            title = server.title,
            is_popout = false,
            is_borderless = true,
            title_bar_fm_style = true,
            _manager = opds,
            file_downloaded_callback = function(file)
                opds:showFileDownloadedDialog(file)
            end,
            close_callback = function()
                if browser.download_list then
                    browser.download_list.close_callback()
                end
                UIManager:close(browser)
                opds.opds_browser = nil
                if opds.last_downloaded_file then
                    if fm.file_chooser then
                        local util = require("util")
                        local pathname = util.splitFilePathName(opds.last_downloaded_file)
                        fm.file_chooser:changeToPath(pathname, opds.last_downloaded_file)
                    end
                    opds.last_downloaded_file = nil
                end
            end,
        }
        opds.opds_browser = browser
        UIManager:show(browser)
        browser:updateCatalog(server.url, server.username, server.password)
    end

    if #servers == 0 then
        openFullBrowser()
        return
    end
    if #servers == 1 then
        openServer(servers[1])
        return
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons = {}
    for _, server in ipairs(servers) do
        local s = server
        table.insert(buttons, {
            {
                text = s.title,
                align = "left",
                callback = function()
                    UIManager:close(dialog)
                    openServer(s)
                end,
            },
        })
    end
    table.insert(buttons, {})
    table.insert(buttons, {
        {
            text = _("All catalogs"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                openFullBrowser()
            end,
        },
    })

    dialog = ButtonDialog:new {
        title = _("Open OPDS catalog"),
        title_align = "center",
        buttons = buttons,
        shrink_unneeded_width = true,
    }
    UIManager:show(dialog)
end

-- Custom tab callback: folder tabs, Dispatcher-registered actions, and
-- direct plugin-method calls (fm_key/fm_method), matching the three ways
-- the settings UI can define a custom tab.
local function onTabCustom(tab_id)
    local c = cfg()
    local ct
    for _, entry in ipairs(c.custom_tabs) do
        if entry.id == tab_id then
            ct = entry
            break
        end
    end
    if not ct then
        return
    end

    if ct.source == "folder" and ct.folder_path then
        local fm = FileManager.instance
        if fm and fm.file_chooser then
            if lfs.attributes(ct.folder_path, "mode") == "directory" then
                fm.file_chooser:changeToPath(ct.folder_path)
                setActiveTab(ct.id)
            else
                UIManager:show(InfoMessage:new { text = _("Folder not found: ") .. ct.folder_path, timeout = 3 })
            end
        end
        return
    end

    if ct.source == "dispatcher" and ct.dispatcher_action then
        local action = Dispatcher.settingsList and Dispatcher.settingsList[ct.dispatcher_action]
        if action then
            UIManager:sendEvent(Event:new(action.event, action.arg))
            return
        end
    end

    if ct.fm_key and ct.fm_method then
        local fm = FileManager.instance
        local plugin = fm and fm[ct.fm_key]
        if plugin and type(plugin[ct.fm_method]) == "function" then
            plugin[ct.fm_method](plugin)
            return
        end
        UIManager:show(InfoMessage:new { text = _("Plugin not available: ") .. ct.fm_key, timeout = 3 })
        return
    end

    -- Legacy dispatcher_action field (older custom-tab configs saved it
    -- without a `source` key)
    if ct.dispatcher_action then
        local action = Dispatcher.settingsList and Dispatcher.settingsList[ct.dispatcher_action]
        if action then
            UIManager:sendEvent(Event:new(action.event, action.arg))
            return
        end
    end

    UIManager:show(InfoMessage:new { text = _("Custom tab action not configured correctly."), timeout = 3 })
end

local tab_callbacks = {
    books = onTabBooks,
    manga = onTabManga,
    news = onTabNews,
    continue = onTabContinue,
    history = onTabHistory,
    favorites = onTabFavorites,
    collections = onTabCollections,
    zlib = onTabZlib,
    annas = onTabAnnas,
    appstore = onTabAppStore,
    opds = onTabOpds,
    exit = onTabExit,
    page_left = onTabPageLeft,
    page_right = onTabPageRight,
    sleep = onTabSleep,
    restart = onTabRestart,
    stats = onTabStats,
}

getTabCallback = function(tab_id)
    if tab_callbacks[tab_id] then
        return tab_callbacks[tab_id]
    end
    local c = cfg()
    for _, ct in ipairs(c.custom_tabs) do
        if ct.id == tab_id then
            return function()
                onTabCustom(tab_id)
            end
        end
    end
    return nil
end

-- Colored text/icon widgets (for the active-tab color setting)

local ColorTextWidget = TextWidget:extend {}

function ColorTextWidget:paintTo(bb, x, y)
    self:updateSize()
    if self._is_empty then
        return
    end
    if not self.fgcolor or Blitbuffer.isColor8(self.fgcolor) or not Screen:isColorScreen() then
        TextWidget.paintTo(self, bb, x, y)
        return
    end
    if not self.use_xtext then
        TextWidget.paintTo(self, bb, x, y)
        return
    end
    if not self._xshaping then
        self._xshaping =
            self._xtext:shapeLine(self._shape_start, self._shape_end, self._shape_idx_to_substitute_with_ellipsis)
    end
    local text_width = bb:getWidth() - x
    if self.max_width and self.max_width < text_width then
        text_width = self.max_width
    end
    local pen_x = 0
    local baseline = self.forced_baseline or self._baseline_h
    for _, xglyph in ipairs(self._xshaping) do
        if pen_x >= text_width then
            break
        end
        local face = self.face.getFallbackFont(xglyph.font_num)
        local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
        bb:colorblitFromRGB32(
            glyph.bb,
            x + pen_x + glyph.l + xglyph.x_offset,
            y + baseline - glyph.t - xglyph.y_offset,
            0,
            0,
            glyph.bb:getWidth(),
            glyph.bb:getHeight(),
            self.fgcolor
        )
        pen_x = pen_x + xglyph.x_advance
    end
end

local ColorIconWidget = IconWidget:extend { _tint_color = nil }

function ColorIconWidget:paintTo(bb, x, y)
    if not self._tint_color or not Screen:isColorScreen() then
        IconWidget.paintTo(self, bb, x, y)
        return
    end
    if self.hide then
        return
    end
    local size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new { x = x, y = y, w = size.w, h = size.h }
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    self._bb:invert()
    bb:colorblitFromRGB32(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h, self._tint_color)
    self._bb:invert()
end

-- Build a single tab / the full navbar

local function createTabWidget(tab, tab_w, is_active)
    local c = cfg()
    local styled = is_active and c.active_tab_styling
    local use_color = styled and c.colored and Screen:isColorScreen()
    local active_color
    if use_color then
        local col = c.active_tab_color
        if col and type(col) == "table" then
            active_color = Blitbuffer.ColorRGB32(col[1], col[2], col[3], 0xFF)
        end
    end

    local use_bold = styled and c.active_tab_bold

    -- Let KOReader resolve custom icons from <data>/icons. Built-in VOS tabs
    -- keep using the plugin resources so they do not require copied files.
    local icon_file = tab.is_custom and vosicons.userIconFile(tab.icon) or vosicons.iconFile(tab.icon)
    local icon
    if active_color then
        icon = ColorIconWidget:new {
            icon = tab.icon,
            file = icon_file,
            width = navbar_icon_size,
            height = navbar_icon_size,
            _tint_color = active_color,
        }
    else
        icon = IconWidget:new {
            icon = tab.icon,
            file = icon_file,
            width = navbar_icon_size,
            height = navbar_icon_size,
        }
    end

    local label
    if active_color then
        label = ColorTextWidget:new {
            text = tab.label,
            face = use_bold and navbar_font_bold or navbar_font,
            fgcolor = active_color,
        }
    else
        label = TextWidget:new { text = tab.label, face = use_bold and navbar_font_bold or navbar_font }
    end

    local icon_label_group
    if c.show_labels then
        icon_label_group = VerticalGroup:new { align = "center", icon, label }
    else
        icon_label_group = VerticalGroup:new { align = "center", icon }
    end

    local show_underline = styled and c.active_tab_underline
    local underline
    if show_underline then
        local underline_color = Blitbuffer.COLOR_BLACK
        if c.colored then
            local col = c.active_tab_color
            if col and type(col) == "table" then
                underline_color = Blitbuffer.ColorRGB32(col[1], col[2], col[3], 0xFF)
            end
        end
        if c.colored and Screen:isColorScreen() then
            local Widget = require("ui/widget/widget")
            local color_line = Widget:new { dimen = Geom:new { w = tab_w, h = underline_thickness } }
            function color_line:paintTo(bb, x, y)
                bb:paintRectRGB32(x, y, self.dimen.w, self.dimen.h, underline_color)
            end
            underline = color_line
        else
            underline = LineWidget:new {
                dimen = Geom:new { w = tab_w, h = underline_thickness },
                background = underline_color,
            }
        end
    else
        underline = VerticalSpan:new { width = underline_thickness }
    end

    local v_pad = c.show_labels and navbar_v_padding or navbar_v_padding * 2

    local children
    if c.underline_above then
        children = {
            align = "center",
            underline,
            VerticalSpan:new { width = v_pad },
            icon_label_group,
            VerticalSpan:new { width = v_pad },
        }
    else
        children = {
            align = "center",
            VerticalSpan:new { width = v_pad },
            icon_label_group,
            VerticalSpan:new { width = v_pad },
            underline,
        }
    end

    return CenterContainer:new {
        dimen = Geom:new { w = tab_w, h = icon_label_group:getSize().h + v_pad * 2 + underline_thickness },
        VerticalGroup:new(children),
    }
end

local function getVisibleTabs()
    local c = cfg()
    local visible = {}
    for _, tab_id in ipairs(c.tab_order) do
        if (tab_id == "books" or c.show_tabs[tab_id]) and tabs_by_id[tab_id] then
            table.insert(visible, tabs_by_id[tab_id])
        end
    end
    return visible
end

createNavBar = function()
    local c = cfg()
    tabs_by_id["books"].label = getBooksLabel()

    local visible_tabs = getVisibleTabs()
    if #visible_tabs == 0 then
        return nil
    end

    local screen_w = Screen:getWidth()
    local inner_w = screen_w - navbar_h_padding * 2
    local tab_w = math.floor(inner_w / #visible_tabs)

    local row = HorizontalGroup:new {}
    for _, tab in ipairs(visible_tabs) do
        table.insert(row, createTabWidget(tab, tab_w, tab.id == active_tab))
    end

    local row_with_padding = HorizontalGroup:new {
        HorizontalSpan:new { width = navbar_h_padding },
        row,
        HorizontalSpan:new { width = navbar_h_padding },
    }
    local row_h = row_with_padding:getSize().h

    local visual_children = {}

    if c.show_top_border then
        local separator = LineWidget:new {
            dimen = Geom:new { w = inner_w, h = Size.line.medium },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
        local separator_and_row = OverlapGroup:new {
            dimen = Geom:new { w = screen_w, h = row_h },
            allow_mirroring = false,
            CenterContainer:new { dimen = Geom:new { w = screen_w, h = Size.line.medium }, separator },
            row_with_padding,
        }
        if c.show_top_gap then
            table.insert(visual_children, VerticalSpan:new { width = navbar_top_gap })
        end
        table.insert(visual_children, separator_and_row)
    else
        if c.show_top_gap then
            table.insert(visual_children, VerticalSpan:new { width = navbar_top_gap })
        end
        table.insert(visual_children, row_with_padding)
    end

    local visual = VerticalGroup:new(visual_children)

    local navbar = InputContainer:new {
        dimen = Geom:new { w = screen_w, h = visual:getSize().h },
        ges_events = {
            TapNavBar = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new { x = 0, y = 0, w = screen_w, h = Screen:getHeight() },
                },
            },
        },
    }

    navbar.onTapNavBar = function(self, _, ges)
        if not navbarEnabled() then
            return false
        end
        if not self.dimen or not self.dimen:contains(ges.pos) then
            return false
        end
        if ges.pos.x < corner_dead_zone or ges.pos.x > screen_w - corner_dead_zone then
            return false
        end
        local tap_x = ges.pos.x - navbar_h_padding
        local idx = math.floor(tap_x / tab_w) + 1
        idx = math.max(1, math.min(#visible_tabs, idx))
        local tapped_id = visible_tabs[idx].id
        local cb = getTabCallback(tapped_id)
        if cb then
            cb()
        end
        local c2 = cfg()
        local stays_in_browser = tapped_id == "books"
            or (tapped_id == "manga" and c2.manga_action == "folder" and c2.manga_folder ~= "")
            or (tapped_id == "news" and c2.news_action == "folder" and c2.news_folder ~= "")
            or (tapped_id:match("^folder_") ~= nil)
        if stays_in_browser and tapped_id ~= active_tab then
            setActiveTab(tapped_id)
        end
        return true
    end

    navbar[1] = visual
    return navbar
end

-- Injection into FileManager / standalone views

local function getNavbarHeight()
    local nb = createNavBar()
    if not nb then
        return 0
    end
    local height = nb:getSize().h
    nb:free(true)
    return height
end

local standalone_view_names = { history = true, collections = true, library_view = true }
local standalone_nexttick_tab_ids = { library_view = "manga" }

local function isStandaloneNavbarView(menu)
    if standalone_view_names[menu.name] then
        return true
    end
    if not menu.name and menu.covers_fullscreen and menu.is_borderless and menu.title_bar_fm_style then
        return true
    end
    return false
end

local _skip_standalone_navbar = false

injectNavbar = function(fm)
    if not navbarEnabled() then
        return
    end
    -- SimpleUI owns and deeply wraps the FileManager layout with its own
    -- top/bottom navigation containers. Replacing that tree would discard
    -- SimpleUI's layout, so let it remain the sole navbar provider.
    if fm._navbar_container then
        return
    end
    local fm_ui = fm[1]
    if not fm_ui then
        return
    end

    local file_chooser = fm.file_chooser
    if fm._navbar_injected then
        local old_navbar = fm_ui[1] and fm_ui[1][2]
        if old_navbar then
            old_navbar:free(true)
        end
    end
    if not file_chooser then
        return
    end

    fm._navbar_injected = true

    local navbar = createNavBar()
    if not navbar then
        fm_ui[1] = file_chooser
        return
    end

    local navbar_h = navbar:getSize().h
    local new_height = Screen:getHeight() - navbar_h
    if file_chooser.height ~= new_height and file_chooser.dimen and file_chooser.inner_dimen then
        local chrome = file_chooser.dimen.h - file_chooser.inner_dimen.h
        file_chooser.height = new_height
        file_chooser.dimen.h = new_height
        file_chooser.inner_dimen.h = new_height - chrome
        file_chooser:updateItems()
    end
    if fm.dimen then
        local border = fm.inner_dimen and math.max(0, fm.dimen.h - fm.inner_dimen.h) or 0
        fm.dimen.h = new_height
        if fm.inner_dimen then
            fm.inner_dimen.h = new_height - border
        end
    end
    if fm.height then
        fm.height = new_height
    end

    fm_ui[1] = VerticalGroup:new { align = "left", file_chooser, navbar }
end

-- Reverse of injectNavbar: restore the FileManager layout to its pre-injection
-- state (file chooser directly inside the FrameContainer at full height).
local function uninjectNavbar(fm)
    local fm_ui = fm[1]
    if not fm_ui or not fm._navbar_injected then
        return
    end
    fm._navbar_injected = false
    local file_chooser = fm_ui[1] and fm_ui[1][1]
    if not file_chooser then
        return
    end
    fm_ui[1] = file_chooser
    if fm.height then
        fm.height = Screen:getHeight()
    end
    if fm.dimen then
        local border = fm.inner_dimen and math.max(0, fm.dimen.h - fm.inner_dimen.h) or 0
        fm.dimen.h = Screen:getHeight()
        if fm.inner_dimen then
            fm.inner_dimen.h = Screen:getHeight() - border
        end
    end
    if file_chooser.dimen and file_chooser.inner_dimen then
        local chrome = math.max(0, file_chooser.dimen.h - file_chooser.inner_dimen.h)
        file_chooser.height = Screen:getHeight()
        file_chooser.dimen.h = Screen:getHeight()
        file_chooser.inner_dimen.h = Screen:getHeight() - chrome
    end
    if file_chooser.updateItems then
        file_chooser:updateItems()
    end
end

local function uninjectStandaloneNavbar(menu)
    if not menu or not menu._vos_navbar_original_child then
        return
    end
    menu[1] = menu._vos_navbar_original_child
    if menu._vos_navbar_original_child_height then
        menu[1].height = menu._vos_navbar_original_child_height
        menu._vos_navbar_original_child_height = nil
    end
    menu._vos_navbar_original_child = nil
    if menu._vos_navbar_original_height then
        menu.height = menu._vos_navbar_original_height
        if menu.dimen then
            menu.dimen.h = menu._vos_navbar_original_height
        end
        menu._vos_navbar_original_height = nil
    end
    if menu._vos_navbar_borderless_captured then
        menu.is_borderless = menu._vos_navbar_original_borderless
        menu._vos_navbar_original_borderless = nil
        menu._vos_navbar_borderless_captured = nil
    end
end

injectStandaloneNavbar = function(menu, view_tab_id)
    if not navbarEnabled() or not cfg().show_in_standalone then
        return
    end
    if not menu or not menu[1] then
        return
    end
    if menu._vos_navbar_original_child then
        uninjectStandaloneNavbar(menu)
    end

    local saved_active = active_tab
    active_tab = view_tab_id
    local navbar = createNavBar()
    active_tab = saved_active
    if not navbar then
        return
    end

    navbar.onTapNavBar = function(self_nb, _, ges)
        if not navbarEnabled() then
            return false
        end
        if not self_nb.dimen or not self_nb.dimen:contains(ges.pos) then
            return false
        end
        local screen_w = Screen:getWidth()
        if ges.pos.x < corner_dead_zone or ges.pos.x > screen_w - corner_dead_zone then
            return false
        end
        local vis_tabs = getVisibleTabs()
        if #vis_tabs == 0 then
            return false
        end
        local inner_w = screen_w - navbar_h_padding * 2
        local tab_w_local = math.floor(inner_w / #vis_tabs)
        local tap_x = ges.pos.x - navbar_h_padding
        local idx = math.floor(tap_x / tab_w_local) + 1
        idx = math.max(1, math.min(#vis_tabs, idx))
        local tapped_id = vis_tabs[idx].id

        if tapped_id == view_tab_id then
            return true
        end

        if menu.close_callback then
            menu.close_callback()
        elseif menu.onClose then
            menu:onClose()
        else
            UIManager:close(menu)
        end

        setActiveTab(tapped_id)
        local cb = getTabCallback(tapped_id)
        if cb then
            cb()
        end
        return true
    end

    menu._vos_navbar_original_child = menu[1]
    -- Menu.init was deliberately given the reduced height by our global hook;
    -- the native layout to restore when disabled is the full screen.
    menu._vos_navbar_original_height = Screen:getHeight()
    menu._vos_navbar_tab_id = view_tab_id
    standalone_views[menu] = true
    menu.dimen.h = Screen:getHeight()

    local FrameContainer = require("ui/widget/container/framecontainer")
    menu[1] = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        VerticalGroup:new { align = "left", menu[1], navbar },
    }
end

hookQuickRSSInit = function()
    if qrss_hooked then
        return
    end
    local ok, QuickRSSUI_class = pcall(require, "modules/ui/feed_view")
    if not ok or not QuickRSSUI_class then
        return
    end
    qrss_hooked = true

    local ok_ai, ArticleItemModule = pcall(require, "modules/ui/article_item")
    local QRSS_ITEM_HEIGHT = ok_ai and ArticleItemModule.ITEM_HEIGHT

    local orig_qrss_init = QuickRSSUI_class.init
    function QuickRSSUI_class:init()
        orig_qrss_init(self)

        if not navbarEnabled() or not cfg().show_in_standalone then
            return
        end

        local navbar_h = getNavbarHeight()
        if navbar_h <= 0 then
            return
        end

        local original_child_height = self[1].height
        local original_list_h = self.list_h
        local original_items_per_page = self.items_per_page
        self[1].height = original_child_height - navbar_h
        self.list_h = self.list_h - navbar_h
        if QRSS_ITEM_HEIGHT then
            self.items_per_page = math.max(1, math.floor(self.list_h / QRSS_ITEM_HEIGHT))
        end

        local saved_active = active_tab
        active_tab = "news"
        local navbar = createNavBar()
        active_tab = saved_active
        if not navbar then
            return
        end

        navbar.onTapNavBar = function(self_nb, _, ges)
            if not navbarEnabled() then
                return false
            end
            if not self_nb.dimen or not self_nb.dimen:contains(ges.pos) then
                return false
            end
            local screen_w = Screen:getWidth()
            if ges.pos.x < corner_dead_zone or ges.pos.x > screen_w - corner_dead_zone then
                return false
            end
            local vis_tabs = getVisibleTabs()
            if #vis_tabs == 0 then
                return false
            end
            local inner_w = screen_w - navbar_h_padding * 2
            local tab_w_local = math.floor(inner_w / #vis_tabs)
            local tap_x = ges.pos.x - navbar_h_padding
            local idx = math.floor(tap_x / tab_w_local) + 1
            idx = math.max(1, math.min(#vis_tabs, idx))
            local tapped_id = vis_tabs[idx].id
            if tapped_id == "news" then
                return true
            end
            self:onClose()
            setActiveTab(tapped_id)
            local cb = getTabCallback(tapped_id)
            if cb then
                cb()
            end
            return true
        end

        local FrameContainer = require("ui/widget/container/framecontainer")
        self._vos_navbar_original_child = self[1]
        self._vos_navbar_original_child_height = original_child_height
        self._vos_navbar_original_list_h = original_list_h
        self._vos_navbar_original_items_per_page = original_items_per_page
        self._vos_navbar_is_qrss = true
        standalone_views[self] = true
        self[1] = FrameContainer:new {
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            margin = 0,
            VerticalGroup:new { align = "left", self[1], navbar },
        }

        self.dimen = Geom:new { w = Screen:getWidth(), h = Screen:getHeight() }

        if #self.articles > 0 then
            self:_populateItems()
        end
    end

    local orig_qrss_onClose = QuickRSSUI_class.onClose
    function QuickRSSUI_class:onClose()
        orig_qrss_onClose(self)
        setActiveTab("books")
    end
end

-- Installs every global monkey-patch exactly once, no matter how many times
-- NavbarModule:init() is called across this KOReader session.
local function installGlobalHooks()
    if GLOBAL_PATCHED then
        return
    end
    GLOBAL_PATCHED = true

    -- Shrink the FileManager (and, if enabled, standalone History/Collections/
    -- Rakuyomi) menu height to make room for the navbar before it lays out.
    local orig_menu_init = Menu.init
    function Menu:init()
        if navbarEnabled() and self.name == "filemanager" and not self.height then
            self.height = Screen:getHeight() - getNavbarHeight()
        elseif
            navbarEnabled()
            and cfg().show_in_standalone
            and not _skip_standalone_navbar
            and isStandaloneNavbarView(self)
        then
            self.height = Screen:getHeight() - getNavbarHeight()
            if not self._vos_navbar_borderless_captured then
                self._vos_navbar_original_borderless = self.is_borderless
                self._vos_navbar_borderless_captured = true
            end
            if not self.is_borderless then
                self.is_borderless = true
            end
        end
        orig_menu_init(self)
        local nexttick_tab_id = standalone_nexttick_tab_ids[self.name]
        if nexttick_tab_id and navbarEnabled() and cfg().show_in_standalone then
            local menu = self
            UIManager:nextTick(function()
                if navbarEnabled() and cfg().show_in_standalone then
                    injectStandaloneNavbar(menu, nexttick_tab_id)
                end
            end)
        end
    end

    -- Auto-switch the active tab when the file browser's path changes
    -- (e.g. user drills into the manga/news folder directly).
    local orig_onPathChanged = FileManager.onPathChanged
    function FileManager:onPathChanged(path)
        if orig_onPathChanged then
            orig_onPathChanged(self, path)
        end
        if not navbarEnabled() then
            return
        end

        local function startsWith(str, prefix)
            return str:sub(1, #prefix) == prefix
        end

        local c = cfg()
        local new_tab
        if c.manga_action == "folder" and c.manga_folder ~= "" then
            if path == c.manga_folder or startsWith(path, c.manga_folder .. "/") then
                new_tab = "manga"
            end
        end
        if not new_tab and c.news_action == "folder" and c.news_folder ~= "" then
            if path == c.news_folder or startsWith(path, c.news_folder .. "/") then
                new_tab = "news"
            end
        end
        if not new_tab then
            local home_dir = G_reader_settings:readSetting("home_dir")
                or require("apps/filemanager/filemanagerutil").getDefaultDir()
            if path == home_dir or startsWith(path, home_dir .. "/") then
                new_tab = "books"
            end
        end
        if not new_tab then
            for _, ct in ipairs(c.custom_tabs) do
                if ct.source == "folder" and ct.folder_path then
                    if path == ct.folder_path or startsWith(path, ct.folder_path .. "/") then
                        new_tab = ct.id
                        break
                    end
                end
            end
        end

        if new_tab and new_tab ~= active_tab then
            active_tab = new_tab
            injectNavbar(self)
            UIManager:setDirty(self, "full")
        end
    end

    local orig_setupLayout = FileManager.setupLayout
    function FileManager:setupLayout()
        orig_setupLayout(self)
        self._navbar_injected = false
        local fm = self
        UIManager:nextTick(function()
            if navbarEnabled() then
                injectNavbar(fm)
                UIManager:setDirty(fm, "ui")
            end
        end)
    end

    local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
    local orig_onShowHist = FileManagerHistory.onShowHist
    function FileManagerHistory:onShowHist(search_info)
        local result = orig_onShowHist(self, search_info)
        if navbarEnabled() and cfg().show_in_standalone and self.booklist_menu then
            injectStandaloneNavbar(self.booklist_menu, "history")
        end
        return result
    end

    local FileManagerCollection = require("apps/filemanager/filemanagercollection")
    local orig_onShowColl = FileManagerCollection.onShowColl
    function FileManagerCollection:onShowColl(collection_name)
        local from_coll_list = self.coll_list ~= nil
        local result = orig_onShowColl(self, collection_name)
        if navbarEnabled() and cfg().show_in_standalone and self.booklist_menu then
            injectStandaloneNavbar(self.booklist_menu, from_coll_list and "collections" or "favorites")
        end
        return result
    end

    local orig_onShowCollList = FileManagerCollection.onShowCollList
    function FileManagerCollection:onShowCollList(file_or_selected_collections, caller_callback, no_dialog)
        if file_or_selected_collections ~= nil then
            _skip_standalone_navbar = true
        end
        local result = orig_onShowCollList(self, file_or_selected_collections, caller_callback, no_dialog)
        _skip_standalone_navbar = false
        if navbarEnabled() and cfg().show_in_standalone and self.coll_list and file_or_selected_collections == nil then
            injectStandaloneNavbar(self.coll_list, "collections")
        end
        return result
    end
end

local NavbarModule = { name = "navbar" }

function NavbarModule:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function NavbarModule:init()
    SETTINGS_MANAGER = self.settings
    registerCustomTabs()
    updateLayoutConstants()
    installGlobalHooks()

    self.fm = FileManager.instance
    if self.fm then
        UIManager:nextTick(function()
            if navbarEnabled() then
                injectNavbar(self.fm)
            end
        end)
    end
end

-- Called by main.lua's refresh(): recompute config-derived layout and
-- reinject into the current FileManager (global hooks are never reinstalled,
-- installGlobalHooks() is idempotent).
function NavbarModule:reinit()
    registerCustomTabs()
    updateLayoutConstants()
    local fm = FileManager.instance
    if fm then
        if navbarEnabled() then
            injectNavbar(fm)
        else
            uninjectNavbar(fm)
        end
        UIManager:setDirty(fm, "ui")
    end
    local standalone_enabled = navbarEnabled() and cfg().show_in_standalone
    if not standalone_enabled then
        for view in pairs(standalone_views) do
            if view._vos_navbar_original_list_h then
                view.list_h = view._vos_navbar_original_list_h
                view._vos_navbar_original_list_h = nil
            end
            if view._vos_navbar_original_items_per_page then
                view.items_per_page = view._vos_navbar_original_items_per_page
                view._vos_navbar_original_items_per_page = nil
            end
            uninjectStandaloneNavbar(view)
            if view._vos_navbar_is_qrss and view._populateItems and view.articles and #view.articles > 0 then
                view:_populateItems()
            end
            UIManager:setDirty(view, "ui")
        end
    else
        for view in pairs(standalone_views) do
            if not view._vos_navbar_original_child
                and not view._vos_navbar_is_qrss
                and view._vos_navbar_tab_id
            then
                injectStandaloneNavbar(view, view._vos_navbar_tab_id)
                UIManager:setDirty(view, "ui")
            end
        end
    end
end

return NavbarModule
