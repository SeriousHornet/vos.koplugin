--[[--
Visual Overhaul Module (vos.lua) - unified coordinator for every cover-grid visual patch: rounded corners, stretched covers, series indicator, faded finished books, progress bar, percent/pages badges, status icons, disabled native widgets, and folder covers.
--]] --

local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BookInfoManager = require("bookinfomanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local CustomPositionContainer = require("ui/widget/container/custompositioncontainer")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen = require("device").screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local vosicons = require("modules/vosicons")
local Menu = require("ui/widget/menu")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")
local ReadCollection = require("readcollection")
local logger = require("logger")
local _ = require("gettext")

-- ===========================================================================
-- Module-level (singleton) state
-- ===========================================================================

local SETTINGS_MANAGER = nil
local MAX_IMG_W, MAX_IMG_H -- book-cover max cell size, set in init()
local FOLDER_ADJ_W, FOLDER_ADJ_H -- folder-cover adjusted size, set in init()

local function getCfg()
    return SETTINGS_MANAGER.settings.coverbrowser
end

-- Master kill-switch: mirrors enabled_modules.coverbrowser in settings.lua.
-- Every patch below checks it live, so toggling it off stops all CoverBrowser
-- rendering without needing to uninstall the (idempotent) patches.
local function masterEnabled()
    return SETTINGS_MANAGER
        and SETTINGS_MANAGER.settings
        and SETTINGS_MANAGER.settings.enabled_modules
        and SETTINGS_MANAGER.settings.enabled_modules.coverbrowser == true
end

-- Per-feature gates for the features formerly living in their own modules.
-- They mirror enabled_modules.hide_pagination / enabled_modules.collection_star
-- and are checked live, exactly like masterEnabled() above.
local function hidePaginationEnabled()
    return SETTINGS_MANAGER
        and SETTINGS_MANAGER.settings
        and SETTINGS_MANAGER.settings.enabled_modules
        and SETTINGS_MANAGER.settings.enabled_modules.hide_pagination == true
end

local function collectionStarEnabled()
    return SETTINGS_MANAGER
        and SETTINGS_MANAGER.settings
        and SETTINGS_MANAGER.settings.enabled_modules
        and SETTINGS_MANAGER.settings.enabled_modules.collection_star == true
end

local function hideNativeCollectionStarEnabled()
    return SETTINGS_MANAGER
        and SETTINGS_MANAGER.settings
        and SETTINGS_MANAGER.settings.enabled_modules
        and SETTINGS_MANAGER.settings.enabled_modules.hide_collection_star == true
end

local function colorFromHex(hex)
    if not hex then
        return Blitbuffer.COLOR_BLACK
    end
    return Blitbuffer.colorFromString(hex)
end

local function rgbFromHex(hex)
    if not hex or not hex:match("^#[0-9a-fA-F]+$") or #hex ~= 7 then
        return {0, 0, 0}
    end
    return {
        tonumber(hex:sub(2, 3), 16),
        tonumber(hex:sub(4, 5), 16),
        tonumber(hex:sub(6, 7), 16)
    }
end

local function paintRoundedRectRGB32(bb, x, y, w, h, color_rgb, radius)
    if not color_rgb then
        bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_BLACK, radius)
        return
    end
    local tmp_bb = Blitbuffer.new(w, h)
    tmp_bb:paintRoundedRect(0, 0, w, h, Blitbuffer.COLOR_WHITE, radius)
    bb:colorblitFromRGB32(
        tmp_bb, x, y, 0, 0, w, h,
        Blitbuffer.ColorRGB32(color_rgb[1], color_rgb[2], color_rgb[3], 0xFF)
    )
    tmp_bb:free()
end

local function paintRoundedBadgeRGB32(bb, x, y, w, h, border_w, border_rgb, background_rgb, radius)
    if border_w > 0 then
        paintRoundedRectRGB32(bb, x, y, w, h, border_rgb, radius)
    end
    local inset = math.max(0, border_w)
    local fill_w = math.max(1, w - 2 * inset)
    local fill_h = math.max(1, h - 2 * inset)
    local fill_radius = math.max(0, radius - inset)
    fill_radius = math.min(fill_radius, math.floor(math.min(fill_w, fill_h) / 2))
    paintRoundedRectRGB32(
        bb, x + inset, y + inset, fill_w, fill_h,
        background_rgb, fill_radius
    )
end

local function paintCircleRGB32(bb, center_x, center_y, radius, color_rgb)
    local size = 2 * radius + 1
    local tmp_bb = Blitbuffer.new(size, size)
    tmp_bb:paintCircle(radius, radius, radius, Blitbuffer.COLOR_WHITE)
    bb:colorblitFromRGB32(
        tmp_bb, center_x - radius, center_y - radius, 0, 0, size, size,
        Blitbuffer.ColorRGB32(color_rgb[1], color_rgb[2], color_rgb[3], 0xFF)
    )
    tmp_bb:free()
end

local ColorTextWidget = TextWidget:extend {_vos_rgb = nil}

function ColorTextWidget:paintTo(bb, x, y)
    if not self._vos_rgb or not Screen:isColorScreen() then
        TextWidget.paintTo(self, bb, x, y)
        return
    end
    local size = self:getSize()
    local tmp_bb = Blitbuffer.new(size.w, size.h)
    local original_color = self.fgcolor
    self.fgcolor = Blitbuffer.COLOR_WHITE
    TextWidget.paintTo(self, tmp_bb, 0, 0)
    self.fgcolor = original_color
    bb:colorblitFromRGB32(
        tmp_bb, x, y, 0, 0, size.w, size.h,
        Blitbuffer.ColorRGB32(self._vos_rgb[1], self._vos_rgb[2], self._vos_rgb[3], 0xFF)
    )
    tmp_bb:free()
end

-- ===========================================================================
-- Default settings + deep-fill (so this module works even if settings.lua
-- hasn't been updated with a matching "coverbrowser" defaults block yet)
-- ===========================================================================

local DEFAULTS = {
    rounded_corners = {enabled = true},

    -- Shared by stretch_covers (book covers) and folder_covers (folder
    -- images) - both used to duplicate this exact aspect-ratio math.
    cover_aspect_ratio = {ratio_w = 2, ratio_h = 3, stretch_limit = 50, fill = false},
    stretch_covers = {enabled = true},

    series_indicator = {
        style = "badge", -- "off" | "badge" | "bar"
        font_size = 11,
        border_thickness = 1,
        border_corner_radius = 9,
        text_color = "#000000",
        border_color = "#000000",
        background_color = "#E7E7E7"
    },

    faded_finished = {enabled = true, fading_amount = 0.5},

    progress_bar = {
        enabled = true,
        colored = false,
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

    percent_badge = {enabled = true, position = "top_right", text_size = 0.5, move_on_x = 5, move_on_y = -1, badge_w = 70, badge_h = 40, bump_up = 1},

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

    status_icons = {enabled = true},

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

-- Collection-star settings (formerly modules/collection_star.lua). Stored at
-- top level (settings.collection_star), not under coverbrowser, so the saved
-- settings stay compatible with the old standalone module.
local COLLECTION_STAR_DEFAULTS = {
    size = 20,
    x_offset = 6,
    y_offset = 6,
    position = "top_left", -- "top_left" | "top_right" | "bottom_left" | "bottom_right"
    use_background_circle = true,
    background_color = "#000000"
}

-- ===========================================================================
-- Shared rounded-corner SVG icons (used by both the generic rounded_corners
-- feature and folder_covers - loaded once at file scope, same as every
-- source patch did).
-- ===========================================================================

local function svgCornerWidget(icon)
    return IconWidget:new {icon = icon, file = vosicons.iconFile(icon), alpha = true}
end

local ROUND_CORNER_ICONS = {
    tl = svgCornerWidget("rounded.corner.tl"),
    tr = svgCornerWidget("rounded.corner.tr"),
    bl = svgCornerWidget("rounded.corner.bl"),
    br = svgCornerWidget("rounded.corner.br")
}

-- ===========================================================================
-- Feature: rounded corners
-- ===========================================================================

local function paintRoundedCorners(bb, target, x, y, self_widget)
    local TL, TR, BL, BR = ROUND_CORNER_ICONS.tl, ROUND_CORNER_ICONS.tr, ROUND_CORNER_ICONS.bl, ROUND_CORNER_ICONS.br
    if not (TL and TR and BL and BR) then
        return
    end

    local fx = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local fy = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local fw, fh = target.dimen.w, target.dimen.h

    local pad = target.padding or 0
    local ix, iy = math.floor(fx + pad), math.floor(fy + pad)
    local iw, ih = math.max(1, fw - 2 * pad), math.max(1, fh - 2 * pad)

    local cover_border = Screen:scaleBySize(0.5)
    if not self_widget.is_directory then
        bb:paintBorder(ix, iy, iw, ih, cover_border, Blitbuffer.COLOR_BLACK, 0, false)
    end

    local function sz(w)
        local s = w:getSize()
        return s.w, s.h
    end
    local tlw, tlh = sz(TL)
    local trw, trh = sz(TR)
    local blw, blh = sz(BL)
    local brw, brh = sz(BR)

    TL:paintTo(bb, fx, fy)
    TR:paintTo(bb, fx + fw - trw, fy)
    BL:paintTo(bb, fx, fy + fh - blh)
    BR:paintTo(bb, fx + fw - brw, fy + fh - brh)
end

-- ===========================================================================
-- Feature: series indicator - "badge" style or "bar" style
-- ===========================================================================

local function initSeriesBadge(self_widget, c)
    local bookinfo = BookInfoManager:getBookInfo(self_widget.filepath, false)
    if bookinfo and bookinfo.series and bookinfo.series_index then
        local scfg = c.series_indicator
        self_widget.series_index = bookinfo.series_index

        local border = scfg.border_thickness
        local series_text =
            ColorTextWidget:new {
            text = "#" .. self_widget.series_index,
            face = Font:getFace("cfont", scfg.font_size),
            bold = true,
            fgcolor = colorFromHex(scfg.text_color),
            _vos_rgb = rgbFromHex(scfg.text_color)
        }

        self_widget.series_badge =
            FrameContainer:new {
            linesize = Screen:scaleBySize(2),
            bordersize = 0,
            padding = Screen:scaleBySize(2) + border,
            margin = 0,
            series_text
        }

        self_widget._series_text = series_text
        self_widget._series_badge_border = border
        self_widget._series_badge_radius = Screen:scaleBySize(scfg.border_corner_radius)
        self_widget._series_badge_border_rgb = rgbFromHex(scfg.border_color)
        self_widget._series_badge_background_rgb = rgbFromHex(scfg.background_color)
        self_widget.has_series_badge = true
    end
end

local function paintSeriesBadge(self_widget, bb, x, y)
    local target = self_widget[1] and self_widget[1][1] and self_widget[1][1][1]
    if not target or not target.dimen then
        return
    end

    local d_w = math.ceil(target.dimen.w / 5)
    local d_h = math.ceil(target.dimen.h / 10)
    local ix = BD.mirroredUILayout() and -math.floor(d_w) or (target.dimen.w - math.floor(d_w))
    local iy = 5

    local badge_size = self_widget.series_badge:getSize()
    local badge_x = math.floor(target.dimen.x + ix + (d_w - badge_size.w) / 2)
    local badge_y = math.floor(target.dimen.y + iy + (d_h - badge_size.h) / 2)

    paintRoundedBadgeRGB32(
        bb, badge_x, badge_y, badge_size.w, badge_size.h,
        self_widget._series_badge_border,
        self_widget._series_badge_border_rgb,
        self_widget._series_badge_background_rgb,
        self_widget._series_badge_radius
    )

    self_widget.series_badge:paintTo(bb, badge_x, badge_y)
end

local function paintSeriesIndicatorBar(self_widget, bb, target, x)
    local d_w = Screen:scaleBySize(6)
    local d_h = math.ceil(target.dimen.h / 8)
    local ix

    if BD.mirroredUILayout() then
        ix = -d_w + 1
        local x_overflow_left = x - target.dimen.x + ix
        if x_overflow_left > 0 then
            self_widget.refresh_dimen = self_widget[1].dimen:copy()
            self_widget.refresh_dimen.x = self_widget.refresh_dimen.x - x_overflow_left
            self_widget.refresh_dimen.w = self_widget.refresh_dimen.w + x_overflow_left
        end
    else
        ix = target.dimen.w - 1
        local x_overflow_right = target.dimen.x + ix + d_w - x - self_widget.dimen.w
        if x_overflow_right > 0 then
            self_widget.refresh_dimen = self_widget[1].dimen:copy()
            self_widget.refresh_dimen.w = self_widget.refresh_dimen.w + x_overflow_right
        end
    end

    local iy = 40
    bb:paintRect(target.dimen.x + ix, target.dimen.y + iy, d_w, d_h, Blitbuffer.COLOR_GRAY)
    bb:paintBorder(target.dimen.x + ix, target.dimen.y + iy, d_w, d_h, 1)
end

-- ===========================================================================
-- Feature: faded finished books
-- ===========================================================================

local function paintFadedFinished(bb, target, x, y, self_widget, c)
    if self_widget.status ~= "complete" then
        return
    end
    local tw, th = target.dimen.w, target.dimen.h
    local fx = x + math.floor((self_widget.width - tw) / 2)
    local fy = y + math.floor((self_widget.height - th) / 2)
    bb:lightenRect(fx, fy, tw, th, c.faded_finished.fading_amount)
end

-- ===========================================================================
-- Feature: progress bar - mono or colored
-- ===========================================================================

local function paintProgressBar(bb, target, x, y, self_widget, c, corner_mark_size)
    local pf = self_widget.percent_finished
    -- Both source patches skip entirely once a book is complete.
    if not pf or self_widget.status == "complete" then
        return
    end

    local pcfg = c.progress_bar
    local fx = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local fy = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local fw, fh = target.dimen.w, target.dimen.h

    local b = target.bordersize or 0
    local pad = target.padding or 0
    local ix, iy = fx + b + pad, fy + b + pad
    local iw, ih = fw - 2 * (b + pad), fh - 2 * (b + pad)

    local INSET_X = Screen:scaleBySize(pcfg.inset_x)
    local INSET_Y = Screen:scaleBySize(pcfg.inset_y)
    local MOVE_X = Screen:scaleBySize(pcfg.move_on_x)
    local MOVE_Y = Screen:scaleBySize(pcfg.move_on_y)
    local left = ix + INSET_X + MOVE_X
    local right = ix + iw - INSET_X + MOVE_X

    local has_corner_icon =
        (self_widget.been_opened or self_widget.do_hint_opened) and
        (self_widget.status == "reading" or self_widget.status == "abandoned")
    if pcfg.position ~= "top" and has_corner_icon and corner_mark_size then
        right = right - (corner_mark_size + Screen:scaleBySize(pcfg.gap_to_icon))
    end

    local bar_w = math.max(1, right - left)
    local BAR_H = Screen:scaleBySize(pcfg.bar_h)
    local BAR_RADIUS = Screen:scaleBySize(pcfg.bar_radius)
    local bar_x = math.floor(left + 0.5)
    local bar_y
    if pcfg.position == "top" then
        bar_y = math.floor(iy + INSET_Y + MOVE_Y + 0.5)
    else
        bar_y = math.floor(iy + ih - INSET_Y - BAR_H + MOVE_Y + 0.5)
    end
    local BORDER_W = Screen:scaleBySize(pcfg.border_w)

    local p = math.max(0, math.min(1, pf))
    local fill_w = math.max(1, math.floor(bar_w * p + 0.5))

    if pcfg.colored then
        paintRoundedBadgeRGB32(
            bb, bar_x - BORDER_W, bar_y - BORDER_W,
            bar_w + 2 * BORDER_W, BAR_H + 2 * BORDER_W,
            BORDER_W, rgbFromHex(pcfg.border_color), rgbFromHex(pcfg.track_color),
            BAR_RADIUS + BORDER_W
        )
        local fill_rgb = (self_widget.status == "abandoned") and pcfg.abandoned_color_rgb or pcfg.fill_color_rgb
        paintRoundedRectRGB32(bb, bar_x, bar_y, fill_w, BAR_H, fill_rgb, BAR_RADIUS)
    else
        paintRoundedBadgeRGB32(
            bb, bar_x - BORDER_W, bar_y - BORDER_W,
            bar_w + 2 * BORDER_W, BAR_H + 2 * BORDER_W,
            BORDER_W, rgbFromHex(pcfg.border_color), rgbFromHex(pcfg.track_color),
            BAR_RADIUS + BORDER_W
        )
        local fill_rgb = (self_widget.status == "abandoned")
            and rgbFromHex(pcfg.abandoned_color) or rgbFromHex(pcfg.fill_color)
        paintRoundedRectRGB32(bb, bar_x, bar_y, fill_w, BAR_H, fill_rgb, BAR_RADIUS)
    end
end

-- ===========================================================================
-- Feature: percent badge
-- ===========================================================================

local function getCornerPosition(position, left, top, width, height, item_w, item_h, x_offset, y_offset)
    if position == "top_left" then
        return left + x_offset, top + y_offset
    elseif position == "bottom_left" then
        return left + x_offset, top + height - item_h - y_offset
    elseif position == "bottom_right" then
        return left + width - item_w - x_offset, top + height - item_h - y_offset
    end
    return left + width - item_w - x_offset, top + y_offset
end

local function paintPercentBadge(bb, target, x, y, self_widget, c)
    if self_widget.is_directory or self_widget.status == "complete" or not self_widget.percent_finished then
        return
    end

    local shows =
        (self_widget.do_hint_opened and self_widget.been_opened) or
        (self_widget.menu and self_widget.menu.name == "history") or
        (self_widget.menu and self_widget.menu.name == "collections")
    if not shows then
        return
    end

    local pcfg = c.percent_badge
    local corner_mark_size = Screen:scaleBySize(20)

    local percent_text = string.format("%d%%", math.floor(self_widget.percent_finished * 100))
    local font_size = math.floor(corner_mark_size * pcfg.text_size)
    local percent_widget =
        TextWidget:new {
        text = percent_text,
        font_size = font_size,
        face = Font:getFace("cfont", font_size),
        alignment = "center",
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        max_width = corner_mark_size,
        truncate_with_ellipsis = true
    }

    local BADGE_W = Screen:scaleBySize(pcfg.badge_w)
    local BADGE_H = Screen:scaleBySize(pcfg.badge_h)
    local INSET_X = Screen:scaleBySize(pcfg.move_on_x)
    local INSET_Y = Screen:scaleBySize(pcfg.move_on_y)
    local TEXT_PAD = Screen:scaleBySize(6)

    local fx = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local fy = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local fw, fh = target.dimen.w, target.dimen.h

    local percent_badge_icon = IconWidget:new {icon = "percent.badge", file = vosicons.iconFile("percent.badge"), alpha = true}
    percent_badge_icon.width = BADGE_W
    percent_badge_icon.height = BADGE_H

    local bx, by = getCornerPosition(
        pcfg.position, fx, fy, fw, fh, BADGE_W, BADGE_H, INSET_X, INSET_Y
    )
    bx, by = math.floor(bx), math.floor(by)

    percent_badge_icon:paintTo(bb, bx, by)

    percent_widget.alignment = "center"
    percent_widget.truncate_with_ellipsis = false
    percent_widget.max_width = BADGE_W - 2 * TEXT_PAD

    local ts = percent_widget:getSize()
    local tx = bx + math.floor((BADGE_W - ts.w) / 2)
    local ty = by + math.floor((BADGE_H - ts.h) / 2) - Screen:scaleBySize(pcfg.bump_up)
    percent_widget:paintTo(bb, math.floor(tx), math.floor(ty))
end

-- ===========================================================================
-- Feature: pages badge
-- ===========================================================================

local function paintPagesBadge(bb, target, x, y, self_widget, c)
    if self_widget.is_directory or self_widget.file_deleted or self_widget.status == "complete" or self_widget.been_opened then
        return
    end

    local pcfg = c.pages_badge
    local page_count

    if self_widget.filepath then
        local bookinfo = BookInfoManager:getBookInfo(self_widget.filepath, false)
        if bookinfo and bookinfo.pages then
            page_count = bookinfo.pages
        end
    end
    if not page_count and self_widget.text then
        page_count = self_widget.text:match("[Pp]%((%d+)%)")
    end
    if not page_count then
        return
    end

    local corner_mark_size = Screen:scaleBySize(10)
    local page_text = page_count .. " p."
    local font_size = math.floor(corner_mark_size * pcfg.font_size)

    local border = pcfg.border_thickness
    local pages_text =
        ColorTextWidget:new {
        text = page_text,
        face = Font:getFace("cfont", font_size),
        alignment = "left",
        fgcolor = colorFromHex(pcfg.text_color),
        _vos_rgb = rgbFromHex(pcfg.text_color),
        bold = true,
        padding = 2
    }

    local pages_badge_frame =
        FrameContainer:new {
        linesize = Screen:scaleBySize(2),
        bordersize = 0,
        padding = Screen:scaleBySize(2) + border,
        margin = 0,
        pages_text
    }

    local cover_left = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local cover_top = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local cover_w, cover_h = target.dimen.w, target.dimen.h
    local badge_w = pages_badge_frame:getSize().w
    local badge_h = pages_badge_frame:getSize().h

    local x_offset = Screen:scaleBySize(pcfg.x_offset)
    local y_offset = Screen:scaleBySize(pcfg.y_offset)
    local pos_x, pos_y = getCornerPosition(
        pcfg.position, cover_left, cover_top, cover_w, cover_h,
        badge_w, badge_h, x_offset, y_offset
    )
    pos_x, pos_y = math.floor(pos_x), math.floor(pos_y)

    paintRoundedBadgeRGB32(
        bb, pos_x, pos_y, badge_w, badge_h, border,
        rgbFromHex(pcfg.border_color),
        rgbFromHex(pcfg.background_color),
        Screen:scaleBySize(pcfg.border_corner_radius)
    )

    pages_badge_frame:paintTo(bb, pos_x, pos_y)
end

-- ===========================================================================
-- Feature: status icons
-- ===========================================================================

local STATUS_ICON_ALPHA_NAMES = {
    ["dogear.reading"] = true,
    ["dogear.abandoned"] = true,
    ["dogear.abandoned.rtl"] = true,
    ["dogear.complete"] = true,
    ["dogear.complete.rtl"] = true,
    ["star.white"] = true
}

local function installIconAlphaOverride()
    if IconWidget.patched_vos_alpha then
        return
    end
    IconWidget.patched_vos_alpha = true
    local orig_new = IconWidget.new
    function IconWidget:new(o)
        if masterEnabled() and o and STATUS_ICON_ALPHA_NAMES[o.icon] then
            o.alpha = true
        end
        return orig_new(self, o)
    end
end

local function paintStatusIconsOverlay(bb, x, y, self_widget)
    local shows =
        self_widget.status == "complete" or self_widget.status == "abandoned" or
        (self_widget.do_hint_opened and self_widget.been_opened) or
        (self_widget.percent_finished and
            (self_widget.menu and
                (self_widget.menu.name == "history" or
                    self_widget.menu.name == "collections")))
    if not shows then
        return
    end

    local target = self_widget[1] and self_widget[1][1] and self_widget[1][1][1]
    if not target or not target.dimen then
        return
    end

    local corner_mark_size = math.floor(math.min(self_widget.width, self_widget.height) / 8)
    local ix, iy
    if BD.mirroredUILayout() then
        ix = math.floor((self_widget.width - target.dimen.w) / 2)
    else
        ix = self_widget.width - math.ceil((self_widget.width - target.dimen.w) / 2) - corner_mark_size
    end
    iy = self_widget.height - math.ceil((self_widget.height - target.dimen.h) / 2) - corner_mark_size

    local mark
    if self_widget.status == "abandoned" then
        local name = BD.mirroredUILayout() and "dogear.abandoned.rtl" or "dogear.abandoned"
        mark = IconWidget:new(vosicons.icon(name, {
            width = corner_mark_size,
            height = corner_mark_size,
        }))
    elseif self_widget.status == "complete" then
        local name = BD.mirroredUILayout() and "dogear.complete.rtl" or "dogear.complete"
        mark = IconWidget:new(vosicons.icon(name, {
            width = corner_mark_size,
            height = corner_mark_size,
        }))
    else
        mark = IconWidget:new(vosicons.icon("dogear.reading", {
            rotation_angle = BD.mirroredUILayout() and 270 or 0,
            width = corner_mark_size,
            height = corner_mark_size,
        }))
    end
    if mark then
        mark:paintTo(bb, x + ix, y + iy)
    end
end

-- ===========================================================================
-- Feature: collection star
-- ===========================================================================

local function paintCollectionStar(bb, x, y, self_widget)
    if not self_widget.filepath then
        return
    end
    if self_widget.menu and self_widget.menu.name == "collections" then
        return
    end
    if not ReadCollection:isFileInCollections(self_widget.filepath) then
        return
    end

    local settings = (SETTINGS_MANAGER and SETTINGS_MANAGER.settings and SETTINGS_MANAGER.settings.collection_star) or COLLECTION_STAR_DEFAULTS

    local target = self_widget[1] and self_widget[1][1] and self_widget[1][1][1]
    if not target or not target.dimen then
        return
    end

    local radius = Screen:scaleBySize(settings.size / 2)
    local icon_size = Screen:scaleBySize(settings.size)
    local x_offset = Screen:scaleBySize(settings.x_offset)
    local y_offset = Screen:scaleBySize(settings.y_offset)

    local center_x, center_y
    if settings.position == "top_left" then
        center_x = target.dimen.x + x_offset + radius
        center_y = target.dimen.y + y_offset + radius
    elseif settings.position == "top_right" then
        center_x = target.dimen.x + target.dimen.w - x_offset - radius
        center_y = target.dimen.y + y_offset + radius
    elseif settings.position == "bottom_left" then
        center_x = target.dimen.x + x_offset + radius
        center_y = target.dimen.y + target.dimen.h - y_offset - radius
    else -- bottom_right
        center_x = target.dimen.x + target.dimen.w - x_offset - radius
        center_y = target.dimen.y + target.dimen.h - y_offset - radius
    end

    if settings.use_background_circle then
        paintCircleRGB32(bb, center_x, center_y, radius, rgbFromHex(settings.background_color))
    end

    local star =
        IconWidget:new {
        icon = "star.white",
        file = vosicons.iconFile("star.white"),
        width = icon_size,
        height = icon_size,
        alpha = true
    }

    local icon_x = center_x - math.floor(icon_size / 2)
    local icon_y = center_y - math.floor(icon_size / 2)
    star:paintTo(bb, icon_x, icon_y)
end

-- ===========================================================================
-- Feature: disable native description hint
-- ===========================================================================

local function installDescriptionHintOverride()
    if BookInfoManager.patched_vos_hint then
        return
    end
    BookInfoManager.patched_vos_hint = true
    local orig_getSetting = BookInfoManager.getSetting
    function BookInfoManager:getSetting(setting_name)
        if masterEnabled() and setting_name == "no_hint_description" and getCfg().disable_description_hint then
            return true
        end
        return orig_getSetting(self, setting_name)
    end
end

-- ===========================================================================
-- Feature: folder covers
-- ===========================================================================

local FolderCoverSpec = {name = ".cover", exts = {".jpg", ".jpeg", ".png", ".webp", ".gif"}}

local function findFolderCoverFile(dir_path)
    local path = dir_path .. "/" .. FolderCoverSpec.name
    for _, ext in ipairs(FolderCoverSpec.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then
            return fname
        end
    end
end

local function capitalizeWords(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local function isCoverFile(path)
    if not path then
        return false
    end
    local lower = path:lower()
    if lower:match("/%.cover%.") then
        return true
    end
    for _, ext in ipairs(FolderCoverSpec.exts) do
        if lower:sub(-#ext) == ext then
            return true
        end
    end
    return false
end

local function getFolderAspectDimensions(width, height, border_size, c)
    if FOLDER_ADJ_W and FOLDER_ADJ_H then
        return {w = FOLDER_ADJ_W + 2 * border_size, h = FOLDER_ADJ_H + 2 * border_size}
    end
    -- Fallback if init() hasn't run yet for this item.
    local available_w = width - 2 * border_size
    local available_h = height - 2 * border_size
    local rcfg = c.cover_aspect_ratio
    local ratio = rcfg.fill and (available_w / available_h) or (rcfg.ratio_w / rcfg.ratio_h)
    local frame_w, frame_h
    if available_w / available_h > ratio then
        frame_h = available_h
        frame_w = available_h * ratio
    else
        frame_w = available_w
        frame_h = available_w / ratio
    end
    return {w = frame_w + 2 * border_size, h = frame_h + 2 * border_size}
end

local function getFolderTextBox(self_widget, dimen, c)
    local text = self_widget.text
    if text:match("/$") then
        text = text:sub(1, -2)
    end
    text = BD.directory(capitalizeWords(text))

    local available_height = dimen.h
    local dir_font_size = c.folder_covers.folder_font_size
    local directory

    while true do
        if directory then
            directory:free(true)
        end
        directory =
            TextBoxWidget:new {
            text = text,
            face = Font:getFace("cfont", dir_font_size),
            width = dimen.w,
            alignment = "center",
            bold = true
        }
        if directory:getSize().h <= available_height then
            break
        end
        dir_font_size = dir_font_size - 1
        if dir_font_size < 10 then
            directory:free()
            directory.height = available_height
            directory.height_adjust = true
            directory.height_overflow_show_ellipsis = true
            directory:init()
            break
        end
    end
    return directory
end

local function setFolderCover(self_widget, img, c)
    local border_size = 0
    local frame_dimen = getFolderAspectDimensions(self_widget.width, self_widget.height, border_size, c)
    local image_width = frame_dimen.w - 2 * border_size
    local image_height = frame_dimen.h - 2 * border_size
    local rcfg = c.cover_aspect_ratio

    local image =
        img.file and
        ImageWidget:new {file = img.file, width = image_width, height = image_height, stretch_limit_percentage = rcfg.stretch_limit} or
        ImageWidget:new {image = img.data, width = image_width, height = image_height, stretch_limit_percentage = rcfg.stretch_limit}

    local image_widget = FrameContainer:new {padding = 0, bordersize = border_size, image, overlap_align = "center"}
    local image_size = image:getSize()
    local directory = getFolderTextBox(self_widget, {w = image_size.w, h = image_size.h}, c)

    local fcfg = c.folder_covers
    local folder_name_widget
    if fcfg.show_folder_name then
        local name_positions = {top = 0, center = 0.5, bottom = 1}
        local name_frame = FrameContainer:new {
            padding = -1,
            bordersize = 1,
            AlphaContainer:new {alpha = 0.75, directory}
        }
        folder_name_widget =
            CustomPositionContainer:new {
            dimen = frame_dimen,
            horizontal_position = 0.5,
            vertical_position = name_positions[fcfg.folder_name_position] or 0.5,
            widget = name_frame,
            name_frame
        }
    else
        folder_name_widget = VerticalSpan:new {width = 0}
    end

    local nbitems_widget
    local file_count, folder_count = 0, 0
    local entries = self_widget.menu:genItemTableFromPath(self_widget.entry.path)
    if entries then
        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                if not isCoverFile(entry.path) then
                    file_count = file_count + 1
                end
            else
                folder_count = folder_count + 1
            end
        end
    end
    local item_count = file_count > 0 and file_count or folder_count

    if item_count > 0 then
        local nbitems = TextWidget:new {text = tostring(item_count), face = Font:getFace("cfont", fcfg.file_count_size), bold = true, padding = 0}
        local nb_size = math.max(nbitems:getSize().w, nbitems:getSize().h)
        local margin = Screen:scaleBySize(5)
        local count_positions = {
            top_left = {0, 0},
            top_center = {0.5, 0},
            top_right = {1, 0},
            center_left = {0, 0.5},
            center_right = {1, 0.5},
            bottom_left = {0, 1},
            bottom_center = {0.5, 1},
            bottom_right = {1, 1}
        }
        local count_position = count_positions[fcfg.file_count_position] or count_positions.bottom_right
        local count_badge = FrameContainer:new {
            padding = 2,
            bordersize = 1,
            radius = math.ceil(nb_size),
            background = Blitbuffer.COLOR_GRAY_E,
            CenterContainer:new {dimen = {w = nb_size, h = nb_size}, nbitems}
        }
        local count_dimen = {
            w = math.max(1, frame_dimen.w - margin * 2),
            h = math.max(1, frame_dimen.h - margin * 2)
        }
        nbitems_widget =
            CenterContainer:new {
            dimen = frame_dimen,
            CustomPositionContainer:new {
                dimen = count_dimen,
                horizontal_position = count_position[1],
                vertical_position = count_position[2],
                widget = count_badge,
                count_badge
            }
        }
    else
        nbitems_widget = VerticalSpan:new {width = 0}
    end

    self_widget._folder_frame_dimen = frame_dimen
    self_widget._folder_image_size = image_size

    local widget =
        CenterContainer:new {
        dimen = {w = self_widget.width, h = self_widget.height},
        CenterContainer:new {
            dimen = {w = self_widget.width, h = self_widget.height},
            OverlapGroup:new {dimen = frame_dimen, image_widget, folder_name_widget, nbitems_widget}
        }
    }

    if self_widget._underline_container[1] then
        self_widget._underline_container[1]:free()
    end
    self_widget._underline_container[1] = widget
end

local function updateFolderCover(self_widget, c)
    if self_widget._foldercover_processed or self_widget.menu.no_refresh_covers or not self_widget.do_cover_image then
        return
    end
    if self_widget.entry.is_file or self_widget.entry.file or not self_widget.mandatory then
        return
    end
    local dir_path = self_widget.entry and self_widget.entry.path
    if not dir_path then
        return
    end
    self_widget._foldercover_processed = true

    local cover_file = findFolderCoverFile(dir_path)
    if cover_file then
        local success, w, h =
            pcall(
            function()
                local tmp_img = ImageWidget:new {file = cover_file, scale_factor = 1}
                tmp_img:_render()
                local ow, oh = tmp_img:getOriginalWidth(), tmp_img:getOriginalHeight()
                tmp_img:free()
                return ow, oh
            end
        )
        if success then
            setFolderCover(self_widget, {file = cover_file, w = w, h = h}, c)
            return
        end
    end

    self_widget.menu._dummy = true
    local entries = self_widget.menu:genItemTableFromPath(dir_path)
    self_widget.menu._dummy = false
    if not entries then
        return
    end

    for _, entry in ipairs(entries) do
        if entry.is_file or entry.file then
            local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
            if
                bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched and
                    not bookinfo.ignore_cover and
                    not BookInfoManager.isCachedCoverInvalid(bookinfo, self_widget.menu.cover_specs)
             then
                setFolderCover(self_widget, {data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h}, c)
                break
            end
        end
    end
end

local function paintFolderCorners(self_widget, bb, x, y, c)
    if not self_widget._folder_frame_dimen or not self_widget._folder_image_size then
        return
    end
    local frame_dimen = self_widget._folder_frame_dimen
    local image_size = self_widget._folder_image_size

    local fx = x + math.floor((self_widget.width - frame_dimen.w) / 2)
    local fy = y + math.floor((self_widget.height - frame_dimen.h) / 2)
    local image_x = fx + math.floor((frame_dimen.w - image_size.w) / 2)
    local image_y = fy + math.floor((frame_dimen.h - image_size.h) / 2)

    local cover_border = Screen:scaleBySize(c.folder_covers.folder_border)
    bb:paintBorder(image_x, image_y, image_size.w, image_size.h, cover_border, Blitbuffer.COLOR_BLACK, 0, false)

    local TL, TR, BL, BR = ROUND_CORNER_ICONS.tl, ROUND_CORNER_ICONS.tr, ROUND_CORNER_ICONS.bl, ROUND_CORNER_ICONS.br
    if not (TL and TR and BL and BR) then
        return
    end

    local function sz(w)
        local s = w:getSize()
        return s.w, s.h
    end
    local tlw, tlh = sz(TL)
    local trw, trh = sz(TR)
    local blw, blh = sz(BL)
    local brw, brh = sz(BR)

    TL:paintTo(bb, image_x, image_y)
    TR:paintTo(bb, image_x + image_size.w - trw, image_y)
    BL:paintTo(bb, image_x, image_y + image_size.h - blh)
    BR:paintTo(bb, image_x + image_size.w - brw, image_y + image_size.h - brh)
end

-- Caches FileChooser:getListItem results, keyed by its arguments. Folder
-- covers call self.menu:genItemTableFromPath() during paint/update, which
-- is expensive without this - matches the source patch's cache exactly,
-- including its one known limitation: entries are never invalidated for
-- the lifetime of the FileChooser instance (a read-status or collection
-- change won't refresh a cached row until you leave and re-enter the
-- folder). Kept as-is for fidelity; worth revisiting later.
local function installFileChooserCache()
    if FileChooser._vos_getlistitem_patched then
        return
    end
    FileChooser._vos_getlistitem_patched = true

    local orig_getListItem = FileChooser.getListItem
    local cached_list = {}

    local function toKey(...)
        local keys = {}
        for _, key in pairs({...}) do
            if type(key) == "table" then
                table.insert(keys, "table")
                for k, v in pairs(key) do
                    table.insert(keys, tostring(k))
                    table.insert(keys, tostring(v))
                end
            else
                table.insert(keys, tostring(key))
            end
        end
        return table.concat(keys, "")
    end

    function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
        if not masterEnabled() then
            return orig_getListItem(self, dirpath, f, fullpath, attributes, collate)
        end
        local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
        cached_list[key] = cached_list[key] or orig_getListItem(self, dirpath, f, fullpath, attributes, collate)
        return cached_list[key]
    end

    logger.info("VisualOverhaul: FileChooser.getListItem cache installed")
end

-- ===========================================================================
-- Feature: hide pagination (formerly modules/hide_pagination.lua) - strips
-- the "« < Page N of M > »" footer from filemanager/history/collections
-- menus. Reversible: the footer widgets are captured at construction and can
-- be re-inserted live, so toggling enabled_modules.hide_pagination takes
-- effect on the current FileManager/History/Collections menus without a
-- restart (see CoverBrowserModule:reinit).
-- ===========================================================================

local hide_pagination_names = {
    filemanager = true,
    history = true,
    collections = true
}

local function isHidePaginationMenu(menu)
    -- Match by name, or by full-screen fm-style menus (e.g. collections
    -- list has no name)
    return hide_pagination_names[menu.name] or
        (menu.covers_fullscreen and menu.is_borderless and menu.title_bar_fm_style)
end

-- Capture the footer/page_return widgets of a target Menu (stored on the
-- instance) without removing them, so the pagination can be toggled live.
local function vosPreparePaginationState(menu)
    if menu._vos_pagination_ready then
        return
    end
    -- Only Menus have a _recalculateDimen method. Non-Menu widgets (e.g. the
    -- FileManager itself, an InputContainer that wraps the FileChooser) must be
    -- skipped: capturing nil would crash later in vosSetPaginationHidden.
    if not menu._recalculateDimen then
        return
    end
    -- self[1] is FrameContainer, self[1][1] is the content OverlapGroup
    local holder = menu[1] and menu[1][1]
    if not holder then
        return
    end
    local removed = {}
    for i = 1, #holder do
        if holder[i] ~= menu.content_group then
            table.insert(removed, {index = i, widget = holder[i]})
        end
    end
    menu._vos_footer_holder = holder
    menu._vos_removed_footer = removed
    menu._vos_orig_recalculate = menu._recalculateDimen
    menu._vos_pagination_hidden = nil
    menu._vos_pagination_ready = true
end

local vosSetPaginationHidden
vosSetPaginationHidden = function(menu, hidden)
    vosPreparePaginationState(menu)
    if menu._vos_pagination_hidden == hidden then
        return
    end
    menu._vos_pagination_hidden = hidden
    local holder = menu._vos_footer_holder
    if not holder then
        return
    end
    if hidden then
        -- The OverlapGroup contains: content_group, page_return, footer
        -- Remove page_return and footer but keep content_group
        for i = #holder, 1, -1 do
            if holder[i] ~= menu.content_group then
                table.remove(holder, i)
            end
        end
        -- Recalculate to fill the space freed by removing the footer
        local orig = menu._vos_orig_recalculate
        menu._recalculateDimen = function(self_inner, no_recalculate_dimen)
            local saved_arrow = self_inner.page_return_arrow
            local saved_text = self_inner.page_info_text
            local saved_info = self_inner.page_info
            self_inner.page_return_arrow = nil
            self_inner.page_info_text = nil
            self_inner.page_info = nil
            orig(self_inner, no_recalculate_dimen)
            self_inner.page_return_arrow = saved_arrow
            self_inner.page_info_text = saved_text
            self_inner.page_info = saved_info
        end
    else
        -- Re-insert the pagination footer and restore the original recalc
        for _, pair in ipairs(menu._vos_removed_footer) do
            if not holder[pair.index] then
                pair.widget.dimen = (menu.inner_dimen or menu.dimen):copy()
                table.insert(holder, pair.index, pair.widget)
            end
        end
        menu._recalculateDimen = menu._vos_orig_recalculate
    end
    menu:_recalculateDimen()
end

local function installHidePaginationOverride()
    if Menu.patched_vos_pagination then
        return
    end
    Menu.patched_vos_pagination = true

    local orig_menu_init = Menu.init

    function Menu:init()
        orig_menu_init(self)
        if isHidePaginationMenu(self) then
            -- Invalidate any cached pagination state: main.lua's refresh() calls
            -- file_chooser:free() then file_chooser:init(), which rebuilds the
            -- layout without clearing the _vos_* fields. Without this, the
            -- re-init would keep using the stale (freed) OverlapGroup.
            self._vos_pagination_ready = nil
            vosPreparePaginationState(self)
            vosSetPaginationHidden(self, hidePaginationEnabled())
        end
    end

    logger.info("VisualOverhaul: Menu.init pagination-hide installed")
end

-- ===========================================================================
-- Upvalue-preserving method wrapping
-- ===========================================================================
-- Third-party userpatches (e.g. 2-browser-hide-underline.lua) locate module
-- internals by digging *named upvalues* out of MosaicMenuItem methods via
-- userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager"). Naively
-- replacing those methods with our own closures would hide the original
-- upvalues and crash such patches.
--
-- preserveUpvalues() therefore installs each of our hooks behind a thin
-- generated shell that carries one upvalue slot per name the original method
-- had, filled with the original values. Our real logic lives in a plain
-- closure reachable only through the shell's private `__vos_extra` slot, so
-- third-party upvalue diggers keep working untouched, no matter whether our
-- patch or theirs runs first.

local loadstring = loadstring or _G.loadstring

local function findUpvalueSlot(func_obj, wanted)
    local idx = 1
    while true do
        local name = debug.getupvalue(func_obj, idx)
        if not name then
            return nil
        end
        if name == wanted then
            return idx
        end
        idx = idx + 1
    end
end

local function preserveUpvalues(orig_fn, logic)
    if not loadstring or not orig_fn then
        return logic
    end

    local names = {}
    local n = 1
    while true do
        local name = debug.getupvalue(orig_fn, n)
        if not name then
            break
        end
        names[n] = name
        n = n + 1
    end
    if #names == 0 then
        return logic
    end

    -- The shell re-exposes the original method's upvalue slots (same names,
    -- same values) so third-party upvalue diggers keep working. It forwards
    -- the real call arguments to a private dispatcher (`__vos_extra.invoke`)
    -- which strips the upvalue-name prefix and calls `logic` with the method
    -- arguments in their natural order.
    --
    -- NOTE: the real arguments MUST be passed as the trailing `...` of the
    -- generated call. Lua 5.1 truncates a vararg used anywhere but the last
    -- position of an argument list to a single value, which would silently
    -- corrupt every argument after the first (e.g. paintTo's x/y).
    local names_src = table.concat(names, ", ")
    local chunk = "local " .. names_src .. "\n" ..
        "local __vos_extra\n" ..
        "return function(...)\n" ..
        "    return __vos_extra.invoke(" .. names_src .. ", ...)\n" ..
        "end\n"
    local factory = loadstring(chunk, "=vos.preserveUpvalues")
    if not factory then
        logger.warn("VisualOverhaul: failed to compile upvalue-preserving wrapper")
        return logic
    end
    local wrapper = factory()

    local nup = #names
    local invoke = function(...)
        local nargs = select("#", ...)
        local args = { ... }
        return logic(unpack(args, nup + 1, nargs))
    end

    for i = 1, #names do
        local value = select(2, debug.getupvalue(orig_fn, i))
        local slot = findUpvalueSlot(wrapper, names[i])
        if slot then
            debug.setupvalue(wrapper, slot, value)
        end
    end
    local extra_slot = findUpvalueSlot(wrapper, "__vos_extra")
    if extra_slot then
        debug.setupvalue(wrapper, extra_slot, {invoke = invoke})
    end
    return wrapper
end

-- ===========================================================================
-- Master patch: install one init/update/paintTo/free on MosaicMenuItem
-- ===========================================================================

local function patchMosaicMenuItem()
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        logger.warn("VisualOverhaul: could not find MosaicMenuItem")
        return
    end
    if MosaicMenuItem.patched_vos then
        return
    end
    MosaicMenuItem.patched_vos = true

    local TRUE_ORIG_INIT = MosaicMenuItem.init
    local TRUE_ORIG_UPDATE = MosaicMenuItem.update
    local TRUE_ORIG_PAINTTO = MosaicMenuItem.paintTo
    local TRUE_ORIG_FREE = MosaicMenuItem.free

    local CORNER_MARK_SIZE = userpatch.getUpValue(TRUE_ORIG_PAINTTO, "corner_mark_size") or Screen:scaleBySize(24)

    -- Shared aspect-ratio closure swap for book covers. Installed
    -- structurally once (debug.setupvalue can't be "undone" cleanly); its
    -- effect is gated live by stretch_covers.enabled inside .init below,
    -- so the setting stays toggleable at runtime.
    do
        local local_ImageWidget
        local n = 1
        while true do
            local name, value = debug.getupvalue(TRUE_ORIG_UPDATE, n)
            if not name then
                break
            end
            if name == "ImageWidget" then
                local_ImageWidget = value
                break
            end
            n = n + 1
        end

        if local_ImageWidget then
            local setupvalue_n = n
            local StretchingImageWidget = local_ImageWidget:extend({})

            StretchingImageWidget.init = function(self_img)
                if local_ImageWidget.init then
                    local_ImageWidget.init(self_img)
                end
                if not masterEnabled() then
                    return
                end
                local c = getCfg()
                if not c.stretch_covers.enabled or not MAX_IMG_W or not MAX_IMG_H then
                    return
                end
                self_img.scale_factor = nil
                self_img.stretch_limit_percentage = c.cover_aspect_ratio.stretch_limit
                local rcfg = c.cover_aspect_ratio
                local ratio = rcfg.fill and (MAX_IMG_W / MAX_IMG_H) or (rcfg.ratio_w / rcfg.ratio_h)
                if MAX_IMG_W / MAX_IMG_H > ratio then
                    self_img.height = MAX_IMG_H
                    self_img.width = MAX_IMG_H * ratio
                else
                    self_img.width = MAX_IMG_W
                    self_img.height = MAX_IMG_W / ratio
                end
            end

            debug.setupvalue(TRUE_ORIG_UPDATE, setupvalue_n, StretchingImageWidget)
            logger.info("VisualOverhaul: cover stretch swap installed")
        else
            logger.warn("VisualOverhaul: could not find ImageWidget upvalue for stretching")
        end
    end

    MosaicMenuItem.init = preserveUpvalues(TRUE_ORIG_INIT, function(self, ...)
        TRUE_ORIG_INIT(self)
        if not masterEnabled() then
            return
        end
        local c = getCfg()

        if self.width and self.height then
            local border_size = Size.border.thin
            MAX_IMG_W = self.width - 2 * border_size
            MAX_IMG_H = self.height - 2 * border_size

            if c.folder_covers.enabled then
                local rcfg = c.cover_aspect_ratio
                local ratio = rcfg.fill and (MAX_IMG_W / MAX_IMG_H) or (rcfg.ratio_w / rcfg.ratio_h)
                if MAX_IMG_W / MAX_IMG_H > ratio then
                    FOLDER_ADJ_H = MAX_IMG_H
                    FOLDER_ADJ_W = math.floor(MAX_IMG_H * ratio)
                else
                    FOLDER_ADJ_W = MAX_IMG_W
                    FOLDER_ADJ_H = math.floor(MAX_IMG_W / ratio)
                end
            end
        end

        if self.is_directory or self.file_deleted then
            return
        end

        if c.series_indicator.style == "badge" then
            initSeriesBadge(self, c)
        end
    end)

    MosaicMenuItem.update = preserveUpvalues(TRUE_ORIG_UPDATE, function(self, ...)
        TRUE_ORIG_UPDATE(self)
        if not masterEnabled() then
            return
        end
        local c = getCfg()
        if c.folder_covers.enabled then
            updateFolderCover(self, c)
        end
    end)

    MosaicMenuItem.paintTo = preserveUpvalues(TRUE_ORIG_PAINTTO, function(self, bb, x, y, ...)
        local cb_enabled = masterEnabled()
        local star_enabled = collectionStarEnabled()

        -- koreader's native CoverBrowser paints its own status dogear in the
        -- bottom-right corner whenever do_hint_opened && been_opened. Our
        -- status_icons overlay draws its own mark at the same spot, so when
        -- that feature is active we suppress the native one. The native code
        -- only gates that dogear on been_opened, so temporarily clearing it
        -- (and restoring it before our overlay reads it) is enough.
        local function paintToOrig(bb, x, y)
            local saved_been_opened
            local orig_is_in_collection
            if cb_enabled and getCfg().status_icons.enabled and self.been_opened then
                saved_been_opened = self.been_opened
                self.been_opened = false
            end
            if hideNativeCollectionStarEnabled() then
                orig_is_in_collection = ReadCollection.isFileInCollections
                ReadCollection.isFileInCollections = function()
                    return false
                end
            end
            TRUE_ORIG_PAINTTO(self, bb, x, y)
            if orig_is_in_collection then
                ReadCollection.isFileInCollections = orig_is_in_collection
            end
            if saved_been_opened then
                self.been_opened = saved_been_opened
            end
        end

        if not cb_enabled and not star_enabled then
            paintToOrig(bb, x, y)
            return
        end
        local c = getCfg()

        -- CoverBrowser enhancements are off, but the (independent)
        -- collection-star toggle is on: just draw the star over the plain
        -- cover. getCfg() is safe here (coverbrowser table is always
        -- deep-filled in init()).
        if not cb_enabled then
            paintToOrig(bb, x, y)
            if star_enabled then
                paintCollectionStar(bb, x, y, self)
            end
            return
        end

        if c.progress_bar.hide_native then
            local ProgressWidget = require("ui/widget/progresswidget")
            local orig_pw_paint = ProgressWidget.paintTo
            ProgressWidget.paintTo = function()
            end
            paintToOrig(bb, x, y)
            ProgressWidget.paintTo = orig_pw_paint
        else
            paintToOrig(bb, x, y)
        end

        local is_dir = self.is_directory or (self.entry and not (self.entry.is_file or self.entry.file))

        if is_dir then
            if c.folder_covers.enabled then
                paintFolderCorners(self, bb, x, y, c)
            end
            return
        end

        if self.file_deleted then
            return
        end

        local target = self[1] and self[1][1] and self[1][1][1]
        if not target or not target.dimen then
            return
        end

        if c.rounded_corners.enabled then
            paintRoundedCorners(bb, target, x, y, self)
        end

        if c.series_indicator.style == "badge" and self.has_series_badge and self.series_badge then
            paintSeriesBadge(self, bb, x, y)
        elseif c.series_indicator.style == "bar" then
            local bookinfo = BookInfoManager:getBookInfo(self.filepath, self.do_cover_image)
            if bookinfo and bookinfo.series then
                paintSeriesIndicatorBar(self, bb, target, x)
            end
        end

        if c.faded_finished.enabled then
            paintFadedFinished(bb, target, x, y, self, c)
        end

        if c.progress_bar.enabled then
            paintProgressBar(bb, target, x, y, self, c, CORNER_MARK_SIZE)
        end

        if c.percent_badge.enabled then
            paintPercentBadge(bb, target, x, y, self, c)
        end

        if c.pages_badge.enabled then
            paintPagesBadge(bb, target, x, y, self, c)
        end

        if c.status_icons.enabled then
            paintStatusIconsOverlay(bb, x, y, self)
        end

        if star_enabled then
            paintCollectionStar(bb, x, y, self)
        end
    end)

    MosaicMenuItem.free = preserveUpvalues(TRUE_ORIG_FREE, function(self, ...)
        if masterEnabled() then
            if self._series_text then
                self._series_text:free(true)
                self._series_text = nil
            end
            if self.series_badge then
                self.series_badge:free(true)
                self.series_badge = nil
            end
            self._series_badge_background_rgb = nil
            self._series_badge_border_rgb = nil
            self._series_badge_border = nil
            self._series_badge_radius = nil
            self.series_index = nil
            self.has_series_badge = nil
        end
        if TRUE_ORIG_FREE then
            TRUE_ORIG_FREE(self)
        end
    end)

    installIconAlphaOverride()
    installDescriptionHintOverride()
    installFileChooserCache()

    logger.info("VisualOverhaul: MosaicMenuItem patched")
end

-- ===========================================================================
-- Plugin-facing class
-- ===========================================================================

local CoverBrowserModule = {
    name = "coverbrowser",
    plugin = nil,
    settings = nil
}

function CoverBrowserModule:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function CoverBrowserModule:init()
    logger.info("CoverBrowserModule: Initializing")

    SETTINGS_MANAGER = self.settings
    SETTINGS_MANAGER.settings.coverbrowser = SETTINGS_MANAGER.settings.coverbrowser or {}
    deepFill(SETTINGS_MANAGER.settings.coverbrowser, DEFAULTS)
    SETTINGS_MANAGER.settings.collection_star = SETTINGS_MANAGER.settings.collection_star or {}
    deepFill(SETTINGS_MANAGER.settings.collection_star, COLLECTION_STAR_DEFAULTS)

    patchMosaicMenuItem()
    installHidePaginationOverride()
end

-- patchMosaicMenuItem() is idempotent and every feature reads settings
-- live, so there is nothing to re-patch here. main.lua's refresh() already
-- calls file_chooser:updateItems()/setDirty to force the next repaint to
-- pick up whatever changed.
function CoverBrowserModule:reinit()
    logger.info("CoverBrowserModule: Reinitializing")
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    if fm then
        vosSetPaginationHidden(fm, hidePaginationEnabled())
        if fm.file_chooser then
            vosSetPaginationHidden(fm.file_chooser, hidePaginationEnabled())
            fm.file_chooser:updateItems()
        end
    end
    for _, widget in ipairs(UIManager._window_stack) do
        if widget._vos_pagination_ready then
            vosSetPaginationHidden(widget, hidePaginationEnabled())
        end
        if widget.updateItems then
            widget:updateItems()
        end
    end
end

return CoverBrowserModule
