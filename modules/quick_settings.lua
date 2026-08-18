local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Math = require("optmath")
local NetworkMgr = require("ui/network/manager")
local ProgressWidget = require("ui/widget/progresswidget")
local Screen = Device.screen
local TextWidget = require("ui/widget/textwidget")
local TouchMenu = require("ui/widget/touchmenu")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local vosicons = require("modules/vosicons")
local _ = require("gettext")
local T = require("ffi/util").template

local QuickSettings = { name = "quick_settings" }
local quick_icons = {
    quicksettings = true,
    quick_wifi = true,
    quick_nightmode = true,
    quick_rotate = true,
    quick_usb = true,
    quick_search = true,
    quick_rss = true,
    quick_cloud = true,
    quick_streak = true,
    quick_restart = true,
    quick_exit = true,
    quick_sleep = true,
    quick_screenshot = true,
}

local button_order = {
    "wifi",
    "night",
    "rotate",
    "usb",
    "search",
    "quickrss",
    "cloud",
    "zlibrary",
    "calibre",
    "notion",
    "streak",
    "opds",
    "restart",
    "exit",
    "sleep",
    "screenshot",
}

local button_names = {
    wifi = "Wi-Fi",
    night = "Night mode",
    rotate = "Rotate",
    usb = "USB",
    search = "File search",
    quickrss = "QuickRSS",
    cloud = "Cloud storage",
    zlibrary = "Z-Library",
    calibre = "Calibre",
    notion = "Notion",
    streak = "Streak",
    opds = "OPDS",
    restart = "Restart",
    exit = "Exit",
    sleep = "Sleep",
    screenshot = "Screenshot",
}

function QuickSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function QuickSettings:cfg()
    return self.settings.settings.extras.quick_settings
end

function QuickSettings:isEnabled()
    return self.settings:isMasterEnabled() and self:cfg().enabled == true
end

local function currentUI()
    local ReaderUI = require("apps/reader/readerui")
    local FileManager = require("apps/filemanager/filemanager")
    return ReaderUI.instance or FileManager.instance
end

local function showMissing(name)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new { text = T(_("%1 plugin is not installed."), name) })
end

local button_defs = {
    wifi = {
        icon = "quick_wifi",
        label = "Wi-Fi",
        label_func = function()
            if NetworkMgr:isWifiOn() then
                local network = NetworkMgr:getCurrentNetwork()
                if network and network.ssid then
                    return network.ssid
                end
            end
            return _("Wi-Fi")
        end,
        active_func = function()
            return NetworkMgr:isWifiOn()
        end,
        callback = function(menu)
            if NetworkMgr:isWifiOn() then
                NetworkMgr:toggleWifiOff()
            else
                NetworkMgr:toggleWifiOn()
            end
            UIManager:scheduleIn(1, function()
                if menu.item_table and menu.item_table.panel then
                    menu:updateItems(1)
                end
            end)
        end,
    },
    night = {
        icon = "quick_nightmode",
        label = "Night",
        active_func = function()
            return G_reader_settings:isTrue("night_mode")
        end,
        callback = function(menu)
            local enabled = G_reader_settings:isTrue("night_mode")
            Screen:toggleNightMode()
            UIManager:ToggleNightMode(not enabled)
            G_reader_settings:saveSetting("night_mode", not enabled)
            menu:updateItems(1)
            UIManager:setDirty("all", "full")
        end,
    },
    rotate = {
        icon = "quick_rotate",
        label = "Rotate",
        callback = function()
            UIManager:broadcastEvent(Event:new("SwapRotation"))
        end,
    },
    usb = {
        icon = "quick_usb",
        label = "USB",
        callback = function()
            if Device:canToggleMassStorage() then
                UIManager:broadcastEvent(Event:new("RequestUSBMS"))
            end
        end,
    },
    search = {
        icon = "quick_search",
        label = "Search",
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowFileSearch"))
        end,
    },
    quickrss = {
        icon = "quick_rss",
        label = "QuickRSS",
        callback = function()
            local ok, QuickRSSUI = pcall(require, "modules/ui/feed_view")
            if not ok then
                showMissing("QuickRSS")
                return
            end
            local view = QuickRSSUI:new {}
            UIManager:show(view)
            view:_fetch()
        end,
    },
    cloud = {
        icon = "quick_cloud",
        label = "Cloud",
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowCloudStorage"))
        end,
    },
    zlibrary = {
        icon = "quick_search",
        label = "Z-Lib",
        callback = function()
            UIManager:broadcastEvent(Event:new("ZlibrarySearch"))
        end,
    },
    calibre = {
        icon = "quick_wifi",
        label = "Calibre",
        active_func = function()
            local wireless = package.loaded.wireless
            return wireless and wireless.calibre_socket ~= nil
        end,
        callback = function(menu)
            local wireless = package.loaded.wireless
            local event = wireless and wireless.calibre_socket and "CloseWirelessConnection"
                or "StartWirelessConnection"
            UIManager:broadcastEvent(Event:new(event))
            UIManager:scheduleIn(1, function()
                menu:updateItems(1)
            end)
        end,
    },
    notion = {
        icon = "quick_cloud",
        label = "Notion",
        callback = function()
            local ui = currentUI()
            if ui and ui.NotionSync then
                ui.NotionSync:onSyncAllBooksRequested()
            else
                showMissing("NotionSync")
            end
        end,
    },
    streak = {
        icon = "quick_streak",
        label = "Streak",
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowReadingStreakCalendar"))
        end,
    },
    opds = {
        icon = "quick_cloud",
        label = "OPDS",
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowOPDSCatalog"))
        end,
    },
    restart = {
        icon = "quick_restart",
        label = "Restart",
        callback = function()
            UIManager:show(ConfirmBox:new {
                text = _("Are you sure you want to restart KOReader?"),
                ok_text = _("Restart"),
                ok_callback = function()
                    UIManager:broadcastEvent(Event:new("Restart"))
                end,
            })
        end,
    },
    exit = {
        icon = "quick_exit",
        label = "Exit",
        callback = function()
            UIManager:show(ConfirmBox:new {
                text = _("Are you sure you want to exit KOReader?"),
                ok_text = _("Exit"),
                ok_callback = function()
                    UIManager:broadcastEvent(Event:new("Exit"))
                end,
            })
        end,
    },
    sleep = {
        icon = "quick_sleep",
        label = "Sleep",
        callback = function()
            if Device:canSuspend() then
                UIManager:broadcastEvent(Event:new("RequestSuspend"))
            elseif Device:canPowerOff() then
                UIManager:broadcastEvent(Event:new("RequestPowerOff"))
            end
        end,
    },
    screenshot = {
        icon = "quick_screenshot",
        label = "Screenshot",
        callback = function(menu)
            local DataStorage = require("datastorage")
            local util = require("util")
            menu:closeMenu()
            UIManager:scheduleIn(0.2, function()
                local directory = DataStorage:getFullDataDir() .. "/screenshots"
                util.makePath(directory)
                Screen:shot(directory .. "/screenshot_" .. os.date("%Y%m%d_%H%M%S") .. ".png")
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new { text = _("Screenshot saved"), timeout = 2 })
            end)
        end,
    },
}

local function actionButton(menu, definition, size)
    local icon_size = math.floor(size * 0.5)
    local icon = IconWidget:new(vosicons.icon(definition.icon, { width = icon_size, height = icon_size }))
    local active = definition.active_func and definition.active_func()
    local circle = FrameContainer:new {
        width = size,
        height = size,
        radius = math.floor(size / 2),
        bordersize = Screen:scaleBySize(2),
        background = active and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
        padding = 0,
        CenterContainer:new { dimen = Geom:new { w = size - 4, h = size - 4 }, icon },
    }
    local label = definition.label_func and definition.label_func() or _(definition.label)
    return VerticalGroup:new {
        align = "center",
        circle,
        VerticalSpan:new { width = Screen:scaleBySize(2) },
        TextWidget:new { text = label, face = Font:getFace("xx_smallinfofont"), max_width = size + 4 },
    },
        {
            widget = circle,
            callback = function()
                definition.callback(menu)
            end,
        }
end

local function addSlider(panel, refs, menu, label, state, use_buttons)
    local width = menu.item_width - Screen:scaleBySize(20)
    local small_width = Screen:scaleBySize(40)
    local max_width = Screen:scaleBySize(50)
    local gap = Screen:scaleBySize(4)
    local slider_width = width - small_width * 2 - max_width - gap * 3
    local minus =
        Button:new { text = "−", width = small_width, show_parent = menu.show_parent, callback = function() end }
    local value_label = TextWidget:new {
        text = _(label) .. ": " .. state.cur,
        face = Font:getFace("ffont"),
        max_width = width,
    }
    local stride = math.max(1, math.ceil((state.max - state.min + 1) / 25))
    local progress
    local function refresh()
        value_label:setText(_(label) .. ": " .. state.cur)
        UIManager:setDirty(menu.show_parent, "ui")
    end
    local function setValue(value)
        value = math.max(state.min, math.min(state.max, value))
        state.set(value)
        state.cur = state.get()
        if use_buttons then
            progress:setPosition(math.floor(state.cur / stride), progress.default_position)
        else
            progress:setPercentage((state.cur - state.min) / math.max(1, state.max - state.min))
        end
        refresh()
    end
    if use_buttons then
        progress = ButtonProgressWidget:new {
            width = slider_width,
            height = minus:getSize().h,
            font_size = 20,
            padding = 0,
            thin_grey_style = false,
            num_buttons = math.max(1, math.ceil((state.max - state.min) / stride)),
            position = math.floor(state.cur / stride),
            default_position = math.floor(state.cur / stride),
            callback = function(index)
                setValue(math.min(state.max, Math.round(index * stride)))
            end,
            show_parent = menu.show_parent,
            enabled = true,
        }
    else
        progress = ProgressWidget:new {
            width = slider_width,
            height = minus:getSize().h,
            percentage = (state.cur - state.min) / math.max(1, state.max - state.min),
            last = state.max,
        }
        refs.progress = progress
        refs.progress_state = state
        refs.setProgress = setValue
    end
    minus.callback = function()
        setValue(state.cur - 1)
    end
    local plus = Button:new {
        text = "＋",
        width = small_width,
        show_parent = menu.show_parent,
        callback = function()
            setValue(state.cur + 1)
        end,
    }
    local maximum = Button:new {
        text = _("Max"),
        width = max_width,
        show_parent = menu.show_parent,
        callback = function()
            setValue(state.max)
        end,
    }
    table.insert(panel, value_label)
    table.insert(panel, VerticalSpan:new { width = Screen:scaleBySize(8) })
    table.insert(
        panel,
        HorizontalGroup:new {
            align = "center",
            minus,
            HorizontalSpan:new { width = gap },
            progress,
            HorizontalSpan:new { width = gap },
            plus,
            HorizontalSpan:new { width = gap },
            maximum,
        }
    )
end

function QuickSettings:createPanel(menu)
    local cfg = self:cfg()
    local refs = { buttons = {} }
    local panel = VerticalGroup:new { align = "center", VerticalSpan:new { width = Screen:scaleBySize(12) } }
    local visible = {}
    for index = 1, #cfg.button_order do
        local id = cfg.button_order[index]
        if cfg.show_buttons[id] and button_defs[id] then
            table.insert(visible, button_defs[id])
        end
    end
    if #visible > 0 then
        local size = Screen:scaleBySize(64)
        local inner_width = menu.item_width - Screen:scaleBySize(20)
        local gap = math.max(0, math.floor((inner_width - #visible * size) / math.max(1, #visible - 1)))
        local row = HorizontalGroup:new { align = "center" }
        for index, definition in ipairs(visible) do
            local widget, ref = actionButton(menu, definition, size)
            table.insert(row, widget)
            table.insert(refs.buttons, ref)
            if index < #visible then
                table.insert(row, HorizontalSpan:new { width = gap })
            end
        end
        table.insert(panel, CenterContainer:new { dimen = Geom:new { w = menu.item_width, h = row:getSize().h }, row })
        table.insert(panel, VerticalSpan:new { width = Screen:scaleBySize(8) })
    end
    local powerd = Device:getPowerDevice()
    if cfg.show_frontlight and Device:hasFrontlight() then
        addSlider(panel, refs, menu, "Frontlight", {
            min = powerd.fl_min,
            max = powerd.fl_max,
            cur = powerd:frontlightIntensity(),
            get = function()
                return powerd:frontlightIntensity()
            end,
            set = function(value)
                powerd:setIntensity(value)
            end,
        }, false)
    end
    if cfg.show_warmth and Device:hasNaturalLight() then
        table.insert(panel, VerticalSpan:new { width = Screen:scaleBySize(14) })
        addSlider(panel, refs, menu, "Warmth", {
            min = powerd.fl_warmth_min,
            max = powerd.fl_warmth_max,
            cur = powerd:toNativeWarmth(powerd:frontlightWarmth()),
            get = function()
                return powerd:toNativeWarmth(powerd:frontlightWarmth())
            end,
            set = function(value)
                powerd:setWarmth(powerd:fromNativeWarmth(value))
            end,
        }, true)
    end
    table.insert(panel, VerticalSpan:new { width = Screen:scaleBySize(8) })
    menu._vos_quick_settings_refs = refs
    return panel
end

local function handleGesture(menu, gesture)
    local module = QuickSettings.instance
    if not (module and module:isEnabled()) then
        return false
    end
    local refs = menu._vos_quick_settings_refs
    if not refs then
        return false
    end
    if refs.progress and refs.progress.dimen and gesture.pos:intersectWith(refs.progress.dimen) then
        local percentage = refs.progress:getPercentageFromPosition(gesture.pos)
        if percentage then
            local state = refs.progress_state
            refs.setProgress(Math.round(state.min + percentage * (state.max - state.min)))
            return true
        end
    end
    for index = 1, #refs.buttons do
        local ref = refs.buttons[index]
        if ref.widget.dimen and gesture.pos:intersectWith(ref.widget.dimen) then
            ref.callback()
            return true
        end
    end
    return false
end

local function hasQuickSettingsTab(menu)
    local tabs = menu.tab_item_table or {}
    for index = 1, #tabs do
        local tab = tabs[index]
        if tab.vos_quick_settings then
            return true
        end
    end
    return false
end

function QuickSettings:patchTouchMenu()
    if TouchMenu.patched_vos_quick_settings then
        return
    end
    TouchMenu.patched_vos_quick_settings = true
    local orig_init = TouchMenu.init
    function TouchMenu:init(...)
        local module = QuickSettings.instance
        if module and module:isEnabled() and module:cfg().open_on_start and hasQuickSettingsTab(self) then
            self.last_index = 1
        end
        return orig_init(self, ...)
    end
    local orig_updateItems = TouchMenu.updateItems
    function TouchMenu:updateItems(target_page, target_item_id)
        local module = QuickSettings.instance
        if
            not (module and module:isEnabled())
            or not (self.item_table and self.item_table.panel and self.item_table.vos_quick_settings)
        then
            self._vos_quick_settings_refs = nil
            return orig_updateItems(self, target_page, target_item_id)
        end
        self.item_group:clear()
        self.layout = {}
        table.insert(self.item_group, self.bar)
        table.insert(self.layout, self.bar.icon_widgets)
        table.insert(self.item_group, self.item_table.panel(self))
        table.insert(self.item_group, self.footer_top_margin)
        table.insert(self.item_group, self.footer)
        self.page_info_text:setText("")
        self.page_info_left_chev:showHide(false)
        self.page_info_right_chev:showHide(false)
        local text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        local powerd = Device:getPowerDevice()
        if Device:hasBattery() then
            local level = powerd:getCapacity()
            local symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), level)
            text = BD.wrap(text) .. " " .. BD.wrap("⌁") .. BD.wrap(symbol) .. BD.wrap(level .. "%")
        end
        self.time_info:setText(text)
        local old_dimen = self.dimen:copy()
        self.dimen.w = self.width
        self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
        self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)
        local keep_background = old_dimen and self.dimen.h >= old_dimen.h
        UIManager:setDirty((self.is_fresh or keep_background) and self.show_parent or "all", function()
            local refresh_type = self.is_fresh and "flashui" or "ui"
            self.is_fresh = false
            return refresh_type, old_dimen and old_dimen:combine(self.dimen) or self.dimen
        end)
    end
    local orig_onTapCloseAllMenus = TouchMenu.onTapCloseAllMenus
    function TouchMenu:onTapCloseAllMenus(arg, gesture)
        local module = QuickSettings.instance
        if
            module
            and module:isEnabled()
            and self.item_table
            and self.item_table.vos_quick_settings
            and handleGesture(self, gesture)
        then
            return true
        end
        return orig_onTapCloseAllMenus(self, arg, gesture)
    end
    local orig_onSwipe = TouchMenu.onSwipe
    function TouchMenu:onSwipe(arg, gesture)
        local module = QuickSettings.instance
        if
            module
            and module:isEnabled()
            and self.item_table
            and self.item_table.vos_quick_settings
            and handleGesture(self, gesture)
        then
            return true
        end
        return orig_onSwipe and orig_onSwipe(self, arg, gesture)
    end
end

function QuickSettings:patchIcons()
    if IconWidget.patched_vos_quick_settings then
        return
    end
    IconWidget.patched_vos_quick_settings = true
    local orig_new = IconWidget.new
    function IconWidget:new(options)
        local module = QuickSettings.instance
        if module and module:isEnabled() and options and not options.file and quick_icons[options.icon] then
            local file = vosicons.iconFile(options.icon)
            if file then
                options.file = file
                options.alpha = true
            end
        end
        return orig_new(self, options)
    end
end

local function removeQuickSettingsTab(menu)
    if not menu then
        return
    end
    local tabs = menu.tab_item_table or {}
    for index = #tabs, 1, -1 do
        if tabs[index].vos_quick_settings then
            table.remove(tabs, index)
        end
    end
    menu._vos_quick_settings_refs = nil
end

function QuickSettings:syncMenu(menu)
    if not menu then
        return
    end
    removeQuickSettingsTab(menu)
    if self:isEnabled() and menu.tab_item_table then
        local icon_name = "quicksettings"
        local cfg = self:cfg()
        if cfg.custom_icon_enabled and cfg.custom_icon_name ~= "" then
            icon_name = cfg.custom_icon_name
        end
        table.insert(menu.tab_item_table, 1, {
            icon = icon_name,
            remember = false,
            vos_quick_settings = true,
            panel = function(touch_menu)
                return QuickSettings.instance:createPanel(touch_menu)
            end,
        })
    end
end

function QuickSettings:patchMenus()
    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    local ReaderMenu = require("apps/reader/modules/readermenu")
    local function patch(class)
        local orig_setUpdateItemTable = class.setUpdateItemTable
        function class:setUpdateItemTable(...)
            local result = orig_setUpdateItemTable(self, ...)
            local module = QuickSettings.instance
            if module and module:isEnabled() and self.tab_item_table and not hasQuickSettingsTab(self) then
                local icon_name = "quicksettings"
                local cfg = module:cfg()
                if cfg.custom_icon_enabled and cfg.custom_icon_name ~= "" then
                    icon_name = cfg.custom_icon_name
                end
                table.insert(self.tab_item_table, 1, {
                    icon = icon_name,
                    remember = false,
                    vos_quick_settings = true,
                    panel = function(menu)
                        local current = QuickSettings.instance
                        return current:createPanel(menu)
                    end,
                })
            end
            return result
        end
    end
    if not FileManagerMenu.patched_vos_quick_settings then
        FileManagerMenu.patched_vos_quick_settings = true
        patch(FileManagerMenu)
    end
    if not ReaderMenu.patched_vos_quick_settings then
        ReaderMenu.patched_vos_quick_settings = true
        patch(ReaderMenu)
    end
end

function QuickSettings:init()
    QuickSettings.instance = self
    self:patchIcons()
    self:patchTouchMenu()
    self:patchMenus()
end

function QuickSettings:reinit()
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    local owners = {
        FileManager.instance and FileManager.instance.menu,
        ReaderUI.instance and ReaderUI.instance.menu,
    }
    for _, owner in pairs(owners) do
        self:syncMenu(owner)
        local touch_menu = owner and owner.menu_container and owner.menu_container[1]
        if touch_menu then
            local showing_quick_settings = touch_menu.item_table and touch_menu.item_table.vos_quick_settings
            if self:isEnabled() and owner and owner.tab_item_table then
                touch_menu.tab_item_table = owner.tab_item_table
            else
                removeQuickSettingsTab(touch_menu)
                if showing_quick_settings and touch_menu.tab_item_table[1] then
                    touch_menu:switchMenuTab(1)
                end
            end
        end
    end
end

function QuickSettings:getMenuItem()
    local cfg = self:cfg()
    local toggles = {}
    table.insert(toggles, {
        text = _("Arrange buttons"),
        keep_menu_open = true,
        callback = function()
            local SortWidget = require("ui/widget/sortwidget")
            local items = {}
            for index = 1, #cfg.button_order do
                local id = cfg.button_order[index]
                table.insert(items, { text = _(button_names[id]), orig_item = id, dim = not cfg.show_buttons[id] })
            end
            UIManager:show(SortWidget:new {
                title = _("Arrange quick settings buttons"),
                item_table = items,
                callback = function()
                    for index, item in ipairs(items) do
                        cfg.button_order[index] = item.orig_item
                    end
                    self.settings:save()
                end,
            })
        end,
    })
    for index = 1, #cfg.button_order do
        local id = cfg.button_order[index]
        if button_names[id] then
            table.insert(toggles, {
                text = _(button_names[id]),
                checked_func = function()
                    return cfg.show_buttons[id] == true
                end,
                callback = function()
                    cfg.show_buttons[id] = not cfg.show_buttons[id]
                    self.settings:save()
                end,
            })
        end
    end
    local function toggle(text, key, restart)
        return {
            text = _(text),
            checked_func = function()
                return cfg[key] == true
            end,
            callback = function()
                cfg[key] = not cfg[key]
                self.settings:save()
                if restart then
                    UIManager:askForRestart(_("Restart to apply the quick settings tab change"))
                end
            end,
        }
    end
    local DataStorage = require("datastorage")
    local InputDialog = require("ui/widget/inputdialog")
    return {
        text = _("Quicksettings"),
        sub_item_table = {
            toggle("Enable Quicksettings", "enabled", true),
            {
                text = _("Custom icon"),
                sub_item_table = {
                    {
                        text = _("Enable custom icon"),
                        checked_func = function()
                            return cfg.custom_icon_enabled == true
                        end,
                        callback = function()
                            cfg.custom_icon_enabled = not cfg.custom_icon_enabled
                            self.settings:save()
                        end,
                    },
                    {
                        text_func = function()
                            if cfg.custom_icon_name ~= "" then
                                return T(_("%1: %2"), _("Icon name"), cfg.custom_icon_name)
                            end
                            return _("Icon name")
                        end,
                        callback = function(touchmenu)
                            local dialog
                            dialog = InputDialog:new {
                                title = _("Icon name"),
                                input = cfg.custom_icon_name,
                                hint = T(
                                    _("Place %1.svg or %1.png in %2, then enter %1 with or without the extension."),
                                    "my_icon",
                                    DataStorage:getDataDir() .. "/icons"
                                ),
                                buttons = {
                                    {
                                        {
                                            text = _("Cancel"),
                                            callback = function()
                                                UIManager:close(dialog)
                                            end,
                                        },
                                        {
                                            text = _("Set"),
                                            is_enter_default = true,
                                            callback = function()
                                                cfg.custom_icon_name = dialog:getInputText() or ""
                                                self.settings:save()
                                                UIManager:close(dialog)
                                                if touchmenu then
                                                    touchmenu:updateItems()
                                                end
                                            end,
                                        },
                                    },
                                },
                            }
                            UIManager:show(dialog)
                            dialog:onShowKeyboard()
                        end,
                    },
                },
            },
            { text = _("Buttons"), sub_item_table = toggles },
            toggle("Show frontlight slider", "show_frontlight"),
            toggle("Show warmth slider", "show_warmth"),
            toggle("Always open on this tab", "open_on_start"),
        },
    }
end

return QuickSettings
