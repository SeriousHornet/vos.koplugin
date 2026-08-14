local BD = require("ui/bidi")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local SortWidget = require("ui/widget/sortwidget")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local time = require("ui/time")
local _ = require("gettext")

local FileManagerTitleBar = { name = "filemanager_titlebar" }

local separators = {
    bar = "|",
    bullet = "•",
    dot = "·",
    en_dash = "-",
    em_dash = "—",
    none = "",
}

local item_names = {
    wifi = "Wi-Fi",
    memory = "Memory",
    storage = "Storage",
    custom_text = "Custom text",
    clock = "Clock",
    battery = "Battery",
    frontlight = "Brightness level",
    frontlight_warmth = "Warmth level",
    up_time = "Up time",
    awake_time = "Time spent awake",
    suspend_time = "Time in suspend",
}

function FileManagerTitleBar:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function FileManagerTitleBar:cfg()
    return self.settings.settings.extras.filemanager_titlebar
end

function FileManagerTitleBar:isEnabled()
    return self:cfg().enabled == true
end

local function getSystemStat(manager)
    if not manager.systemstat then
        return
    end
    local userpatch = require("userpatch")
    return userpatch.getUpValue(manager.systemstat.addToMainMenu, "SystemStat")
end

local item_text = {
    custom_text = function(manager, cfg)
        return cfg.custom_text
    end,
    clock = function()
        return datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    end,
    wifi = function(manager, cfg)
        return NetworkMgr:isWifiOn() and "" or (cfg.wifi_show_disabled and "")
    end,
    battery = function()
        if not Device:hasBattery() then
            return
        end
        local powerd = Device:getPowerDevice()
        local level = powerd:getCapacity()
        local symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), level)
        local text = BD.wrap(symbol) .. BD.wrap(level .. "%")
        if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
            local aux_level = powerd:getAuxCapacity()
            local aux_symbol = powerd:getBatterySymbol(powerd:isAuxCharged(), powerd:isAuxCharging(), aux_level)
            text = text .. " " .. BD.wrap("+") .. BD.wrap(aux_symbol) .. BD.wrap(aux_level .. "%")
        end
        return text
    end,
    frontlight = function(manager, cfg)
        if not Device:hasFrontlight() then
            return
        end
        local powerd = Device:getPowerDevice()
        if not powerd:isFrontlightOn() then
            return cfg.frontlight_show_off and "☼" .. _("Off")
        end
        local intensity = powerd:frontlightIntensity()
        if Device:isCervantes() or Device:isKobo() then
            return string.format("☼%d%%", intensity)
        end
        return string.format("☼%d", intensity)
    end,
    frontlight_warmth = function(manager, cfg)
        if not Device:hasNaturalLight() then
            return
        end
        local powerd = Device:getPowerDevice()
        if not powerd:isFrontlightOn() then
            return cfg.frontlight_show_off and "💡" .. _("Off")
        end
        local warmth = powerd:frontlightWarmth()
        return warmth and string.format("💡%d%%", warmth)
    end,
    memory = function()
        local statm = io.open("/proc/self/statm", "r")
        if not statm then
            return
        end
        local _, resident = statm:read("*number", "*number")
        statm:close()
        return resident and string.format("%d", math.floor(resident / 256))
    end,
    storage = function(manager)
        local system_stat = getSystemStat(manager)
        if system_stat then
            system_stat.kv_pairs = {}
            system_stat:appendStorageInfo()
            return system_stat.kv_pairs[3] and system_stat.kv_pairs[3][2]
        end
    end,
    up_time = function(manager)
        local system_stat = getSystemStat(manager)
        if system_stat then
            local uptime = time.boottime_or_realtime_coarse() - system_stat.start_monotonic_time
            return "⏻" .. datetime.secondsToClockDuration("modern", time.to_s(uptime), true, false, true)
        end
    end,
    awake_time = function(manager)
        local system_stat = getSystemStat(manager)
        if system_stat and (Device:canSuspend() or Device:canStandby()) then
            local uptime = time.boottime_or_realtime_coarse() - system_stat.start_monotonic_time
            local suspend = Device:canSuspend() and Device.total_suspend_time or 0
            local standby = Device:canStandby() and Device.total_standby_time or 0
            return "☀️"
                .. datetime.secondsToClockDuration("modern", time.to_s(uptime - suspend - standby), true, false, true)
        end
    end,
    suspend_time = function(manager)
        local system_stat = getSystemStat(manager)
        if system_stat and Device:canSuspend() then
            return "⏾"
                .. datetime.secondsToClockDuration("modern", time.to_s(Device.total_suspend_time), true, false, true)
        end
    end,
}

function FileManagerTitleBar:update(manager)
    if not (manager and manager.title_bar) then
        return
    end
    UIManager:unschedule(manager.updateVOSTitleBar)
    if not self:isEnabled() then
        manager.title_bar:setTitle(manager.title or "")
        return
    end
    local cfg = self:cfg()
    if not cfg.show_path then
        manager.title_bar:setSubTitle("")
    end
    local values = {}
    for _, item in ipairs(cfg.order) do
        local generator = cfg.show[item] and item_text[item]
        local value = generator and generator(manager, cfg)
        if value and value ~= "" then
            table.insert(values, value)
        end
    end
    local spaces = string.rep(" ", cfg.separator_space)
    local separator = spaces .. (separators[cfg.separator] or cfg.separator_custom or "") .. spaces
    if manager._vos_titlebar_bold ~= cfg.bold then
        manager._vos_titlebar_bold = cfg.bold
        local default_face = manager.title_bar.fullscreen and manager.title_bar.title_face_fullscreen
            or manager.title_bar.title_face_not_fullscreen
        if cfg.bold then
            manager.title_bar.title_face = Font:getFace("smallinfofontbold", default_face.orig_size)
        else
            manager.title_bar.title_face = Font:getFace("x_smallinfofont", default_face.orig_size)
        end
        manager.title_bar:clear()
        manager.title_bar:init()
    end
    manager.title_bar:setTitle(table.concat(values, separator))
    if cfg.show.clock and cfg.auto_refresh_clock and not manager._suspended then
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), manager.updateVOSTitleBar, manager)
    end
end

local function wrapEvent(name, before)
    local original = FileManager[name]
    FileManager[name] = function(manager, ...)
        if before then
            before(manager)
        end
        local result = original and original(manager, ...)
        local module = FileManagerTitleBar.instance
        if module then
            module:update(manager)
        end
        return result
    end
end

function FileManagerTitleBar:init()
    FileManagerTitleBar.instance = self
    if FileManager.patched_vos_titlebar then
        return
    end
    FileManager.patched_vos_titlebar = true

    function FileManager:updateVOSTitleBar()
        local module = FileManagerTitleBar.instance
        if module then
            module:update(self)
        end
    end

    local orig_setupLayout = FileManager.setupLayout
    function FileManager:setupLayout(...)
        local result = orig_setupLayout(self, ...)
        self:updateVOSTitleBar()
        return result
    end
    wrapEvent("onPathChanged")
    wrapEvent("onSetRotationMode")
    wrapEvent("onResume", function(manager)
        manager._suspended = false
    end)
    wrapEvent("onSuspend", function(manager)
        manager._suspended = true
        UIManager:unschedule(manager.updateVOSTitleBar)
    end)
    wrapEvent("onNetworkConnected")
    wrapEvent("onNetworkDisconnected")
    wrapEvent("onCharging")
    wrapEvent("onNotCharging")
    wrapEvent("onTimeFormatChanged")
    wrapEvent("onFrontlightStateChanged")
    local orig_onClose = FileManager.onClose
    function FileManager:onClose(...)
        UIManager:unschedule(self.updateVOSTitleBar)
        return orig_onClose(self, ...)
    end
end

function FileManagerTitleBar:saveAndRefresh()
    self.settings:save()
    self:update(FileManager.instance)
end

function FileManagerTitleBar:textInput(title, value, callback)
    local dialog
    dialog = InputDialog:new {
        title = title,
        input = value,
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
                        callback(dialog:getInputText())
                        UIManager:close(dialog)
                        self:saveAndRefresh()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FileManagerTitleBar:getMenuItem()
    local cfg = self:cfg()
    local item_toggles = {
        {
            text = _("Arrange items"),
            keep_menu_open = true,
            callback = function()
                local items = {}
                for index = 1, #cfg.order do
                    local id = cfg.order[index]
                    table.insert(items, { text = _(item_names[id]), orig_item = id, dim = not cfg.show[id] })
                end
                UIManager:show(SortWidget:new {
                    title = _("Arrange title bar items"),
                    item_table = items,
                    callback = function()
                        for index, item in ipairs(items) do
                            cfg.order[index] = item.orig_item
                        end
                        self:saveAndRefresh()
                    end,
                })
            end,
        },
    }
    for index = 1, #cfg.order do
        local id = cfg.order[index]
        local item_id = id
        table.insert(item_toggles, {
            text = _(item_names[item_id]),
            checked_func = function()
                return cfg.show[item_id] == true
            end,
            callback = function()
                cfg.show[item_id] = not cfg.show[item_id]
                self:saveAndRefresh()
            end,
        })
    end
    local separator_items = {}
    local separator_order = { "dot", "bullet", "en_dash", "em_dash", "bar", "none" }
    for index = 1, #separator_order do
        local id = separator_order[index]
        local separator_id = id
        table.insert(separator_items, {
            text = separators[separator_id] == "" and _("None") or separators[separator_id],
            checked_func = function()
                return cfg.separator == separator_id
            end,
            callback = function()
                cfg.separator = separator_id
                self:saveAndRefresh()
            end,
        })
    end
    local function toggle(text, key)
        return {
            text = _(text),
            checked_func = function()
                return cfg[key] == true
            end,
            callback = function()
                cfg[key] = not cfg[key]
                self:saveAndRefresh()
            end,
        }
    end
    return {
        text = _("Title bar"),
        sub_item_table = {
            toggle("Enable title bar information", "enabled"),
            { text = _("Items"), sub_item_table = item_toggles },
            { text = _("Separator"), sub_item_table = separator_items },
            {
                text = _("Custom text"),
                callback = function()
                    self:textInput(_("Enter custom text"), cfg.custom_text, function(value)
                        cfg.custom_text = value
                    end)
                end,
            },
            {
                text = _("Custom separator"),
                callback = function()
                    self:textInput(_("Enter custom separator"), cfg.separator_custom, function(value)
                        cfg.separator_custom = value
                        cfg.separator = "custom"
                    end)
                end,
            },
            toggle("Show file browser path", "show_path"),
            toggle("Auto refresh clock", "auto_refresh_clock"),
            toggle("Show Wi-Fi when disabled", "wifi_show_disabled"),
            toggle("Show frontlight when off", "frontlight_show_off"),
            toggle("Bold font", "bold"),
        },
    }
end

function FileManagerTitleBar:reinit()
    self:update(FileManager.instance)
end

return FileManagerTitleBar
