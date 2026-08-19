local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local SpinWidget = require("ui/widget/spinwidget")
local time = require("ui/time")
local _ = require("gettext")

local BrowserDoubleTap = { name = "browser_double_tap" }

function BrowserDoubleTap:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function BrowserDoubleTap:cfg()
    return self.settings.settings.extras.browser_double_tap
end

function BrowserDoubleTap:isEnabled()
    return self.settings:isMasterEnabled() and self:cfg().enabled
end

function BrowserDoubleTap:_handleDoubleTap(file_manager, item, orig_func)
    if not self:isEnabled() then
        return orig_func(item)
    end
    if file_manager.selected_files then
        return orig_func(item)
    end
    local is_file = item.is_file or (item.file and not item.is_go_up)
    if not is_file then
        return orig_func(item)
    end
    local cfg = self:cfg()
    local current_time = time.now()
    local timeout_fts = time.ms(cfg.timeout_ms)
    local time_since_last_tap_fts
    if file_manager._vos_last_tap_time then
        time_since_last_tap_fts = current_time - file_manager._vos_last_tap_time
    else
        time_since_last_tap_fts = timeout_fts * 2
    end
    local item_path = item.path or item.file
    if file_manager._vos_last_tap_file == item_path and time_since_last_tap_fts < timeout_fts then
        file_manager:openFile(item_path)
        file_manager._vos_last_tap_file = nil
        file_manager._vos_last_tap_time = nil
    else
        file_manager._vos_last_tap_file = item_path
        file_manager._vos_last_tap_time = current_time
    end
    return true
end

function BrowserDoubleTap:patchFileChooser(file_manager)
    local file_chooser = file_manager.file_chooser
    if not file_chooser or file_chooser._vos_dt_patched then
        return
    end
    if not file_chooser._orig_onFileSelect then
        file_chooser._orig_onFileSelect = file_chooser.onFileSelect
    end
    local self_ref = self
    function file_chooser:onFileSelect(item)
        return self_ref:_handleDoubleTap(self.ui, item, function(itm)
            return file_chooser._orig_onFileSelect(self, itm)
        end)
    end
    file_chooser._vos_dt_patched = true
end

function BrowserDoubleTap:patchCoverBrowser()
    local ok, MosaicMenu = pcall(require, "mosaicmenu")
    if not ok or not MosaicMenu or not MosaicMenu.onFileSelect then
        return
    end
    if MosaicMenu._vos_dt_patched then
        return
    end
    if not MosaicMenu._orig_onFileSelect then
        MosaicMenu._orig_onFileSelect = MosaicMenu.onFileSelect
    end
    local self_ref = self
    function MosaicMenu:onFileSelect(item)
        local file_manager = self.ui
        return self_ref:_handleDoubleTap(file_manager, item, function(itm)
            return MosaicMenu._orig_onFileSelect(self, itm)
        end)
    end
    MosaicMenu._vos_dt_patched = true
end

function BrowserDoubleTap:init()
    BrowserDoubleTap.instance = self
    local FileManager = require("apps/filemanager/filemanager")

    local orig_setupLayout = FileManager.setupLayout
    if not FileManager._vos_dt_setupLayout_patched then
        FileManager._vos_dt_setupLayout_patched = true
        function FileManager:setupLayout()
            orig_setupLayout(self)
            local mod = BrowserDoubleTap.instance
            if mod then
                mod:patchFileChooser(self)
            end
        end
    end

    local orig_init = FileManager.init
    if not FileManager._vos_dt_init_patched then
        FileManager._vos_dt_init_patched = true
        function FileManager:init()
            orig_init(self)
            local mod = BrowserDoubleTap.instance
            if mod then
                mod:patchCoverBrowser()
                mod:patchFileChooser(self)
            end
        end
    end

    self:patchCoverBrowser()
end

function BrowserDoubleTap:reinit()
    local fm = require("apps/filemanager/filemanager").instance
    if fm then
        if self:isEnabled() then
            self:patchFileChooser(fm)
        else
            self:unpatchFileChooser(fm)
        end
    end
end

function BrowserDoubleTap:unpatchFileChooser(file_manager)
    local file_chooser = file_manager and file_manager.file_chooser
    if not file_chooser or not file_chooser._vos_dt_patched then
        return
    end
    if file_chooser._orig_onFileSelect then
        file_chooser.onFileSelect = file_chooser._orig_onFileSelect
        file_chooser._orig_onFileSelect = nil
        file_chooser._vos_dt_patched = nil
    end
end

function BrowserDoubleTap:getMenuItem()
    local self_ref = self
    local cfg = self:cfg()
    return {
        text = _("Double-tap to open"),
        checked_func = function()
            return cfg.enabled
        end,
        sub_item_table = {
            {
                text = _("Require double-tap to open"),
                checked_func = function()
                    return cfg.enabled
                end,
                callback = function()
                    cfg.enabled = not cfg.enabled
                    self_ref.settings:save()
                    if self_ref.plugin then
                        self_ref.plugin:refresh()
                    end
                end,
            },
            {
                text = _("Double-tap timeout"),
                keep_menu_open = true,
                enabled_func = function()
                    return cfg.enabled
                end,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new {
                        title_text = _("Double-tap timeout (ms)"),
                        info_text = _("Maximum time between taps to register as double-tap"),
                        value = cfg.timeout_ms,
                        value_min = 200,
                        value_max = 1000,
                        value_step = 50,
                        value_hold_step = 100,
                        callback = function(spin)
                            cfg.timeout_ms = spin.value
                            self_ref.settings:save()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end,
            },
        },
    }
end

return BrowserDoubleTap
