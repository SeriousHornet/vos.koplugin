-- Cover-grid enhancements and badges.

local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
local has_bookinfomanager = ok_bim and BookInfoManager ~= nil
local CenterContainer = require("ui/widget/container/centercontainer")
local CustomPositionContainer = require("ui/widget/container/custompositioncontainer")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local vosicons = require("modules/vosicons")
local Menu = require("ui/widget/menu")
local MenuTextOverrides = require("modules/menu_text_overrides")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")
local ReadCollection = require("readcollection")
local logger = require("logger")

local SETTINGS_MANAGER = nil

-- Cached small blitbuffers for folder cover files (decoded once, re-used on
-- every grid render, so large covers never hit the ImageCache nor re-decode).
local folder_cover_cache = {}

local function widgetSize(w)
    local s = w:getSize()
    return s.w, s.h
end
local MAX_IMG_W, MAX_IMG_H -- book-cover max cell size, set in init()

local function getCfg()
    return SETTINGS_MANAGER.settings.coverbrowser
end

local function masterEnabled()
    return SETTINGS_MANAGER and SETTINGS_MANAGER:isMasterEnabled()
end

-- These gates remain live because process-wide hooks cannot be uninstalled.
local function hidePaginationEnabled()
    return masterEnabled()
        and SETTINGS_MANAGER
        and SETTINGS_MANAGER.settings
        and SETTINGS_MANAGER.settings.enabled_modules
        and SETTINGS_MANAGER.settings.enabled_modules.hide_pagination == true
end

local function collectionStarEnabled()
    return masterEnabled()
        and SETTINGS_MANAGER
        and SETTINGS_MANAGER.settings
        and SETTINGS_MANAGER.settings.enabled_modules
        and SETTINGS_MANAGER.settings.enabled_modules.collection_star == true
end

local function hideNativeCollectionStarEnabled()
    return masterEnabled()
        and SETTINGS_MANAGER
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
        return { 0, 0, 0 }
    end
    return {
        tonumber(hex:sub(2, 3), 16),
        tonumber(hex:sub(4, 5), 16),
        tonumber(hex:sub(6, 7), 16),
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
        tmp_bb,
        x,
        y,
        0,
        0,
        w,
        h,
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
    paintRoundedRectRGB32(bb, x + inset, y + inset, fill_w, fill_h, background_rgb, fill_radius)
end

local function paintCircleRGB32(bb, center_x, center_y, radius, color_rgb)
    local size = 2 * radius + 1
    local tmp_bb = Blitbuffer.new(size, size)
    tmp_bb:paintCircle(radius, radius, radius, Blitbuffer.COLOR_WHITE)
    bb:colorblitFromRGB32(
        tmp_bb,
        center_x - radius,
        center_y - radius,
        0,
        0,
        size,
        size,
        Blitbuffer.ColorRGB32(color_rgb[1], color_rgb[2], color_rgb[3], 0xFF)
    )
    tmp_bb:free()
end

local ColorTextWidget = TextWidget:extend { _vos_rgb = nil }

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
        tmp_bb,
        x,
        y,
        0,
        0,
        size.w,
        size.h,
        Blitbuffer.ColorRGB32(self._vos_rgb[1], self._vos_rgb[2], self._vos_rgb[3], 0xFF)
    )
    tmp_bb:free()
end

--- Algorithmic rounded-corner mask (background-agnostic, no SVG files needed) ---

local _corner_cache = {}

local function getCornerCache(r)
    local dr = math.max(1, math.floor(r))
    if _corner_cache[dr] then return _corner_cache[dr] end

    local r2 = dr * dr
    local clip = {}
    for dy = 0, dr - 1 do
        for dx = 0, dr - 1 do
            local idx = dy * dr + dx + 1
            clip[idx] = (dx * dx + dy * dy) > r2
        end
    end
    _corner_cache[dr] = { clip = clip, dr = dr }
    return _corner_cache[dr]
end

local function applyCornerMask(bb, mask, sx, sy, r, dr, color, flip_x, flip_y)
    local step = r / dr
    local idx = 0
    for dy = 0, dr - 1 do
        local fy = flip_y and (dr - 1 - dy) or dy
        for dx = 0, dr - 1 do
            idx = idx + 1
            if mask[idx] then
                local fx = flip_x and (dr - 1 - dx) or dx
                if step <= 1.0 then
                    bb:setPixelClamped(sx + fx, sy + fy, color)
                else
                    local fx0 = math.floor(fx * step)
                    local fx1 = math.floor((fx + 1) * step) - 1
                    local fy0 = math.floor(fy * step)
                    local fy1 = math.floor((fy + 1) * step) - 1
                    for bfy = fy0, fy1 do
                        for bfx = fx0, fx1 do
                            bb:setPixelClamped(sx + bfx, sy + bfy, color)
                        end
                    end
                end
            end
        end
    end
end

--- Clip the four corners of a rectangle to a rounded shape.
--- When color is nil, samples the background pixel just outside each corner.
local function clipRoundedRect(bb, x, y, w, h, r, color)
    if r <= 0 then return end
    if 2 * r > w then r = math.floor(w / 2) end
    if 2 * r > h then r = math.floor(h / 2) end

    local cache = getCornerCache(r)
    local dr = cache.dr

    local colors = color and { color, color, color, color } or {
        bb:getPixel(x - 1, y - 1),
        bb:getPixel(x + w + 1, y - 1),
        bb:getPixel(x - 1, y + h + 1),
        bb:getPixel(x + w + 1, y + h + 1),
    }

    applyCornerMask(bb, cache.clip, x, y, r, dr, colors[1], true, true)
    applyCornerMask(bb, cache.clip, x + w - r, y, r, dr, colors[2], false, true)
    applyCornerMask(bb, cache.clip, x, y + h - r, r, dr, colors[3], true, false)
    applyCornerMask(bb, cache.clip, x + w - r, y + h - r, r, dr, colors[4], false, false)
end

local function paintRoundedCorners(bb, target, x, y, self_widget, c)
    local rc = c.rounded_corners
    local corner_radius = math.max(1, math.floor(
        math.min(Screen:scaleBySize(rc.size), target.dimen.w, target.dimen.h)))
    if corner_radius <= 0 then return end

    local fx = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local fy = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local fw, fh = target.dimen.w, target.dimen.h

    local pad = target.padding or 0
    local ix, iy = math.floor(fx + pad), math.floor(fy + pad)
    local iw, ih = math.max(1, fw - 2 * pad), math.max(1, fh - 2 * pad)

    clipRoundedRect(bb, fx, fy, fw, fh, corner_radius)

    local border_w = Screen:scaleBySize(rc.border_width or 0.5)
    local border_color = colorFromHex(rc.border_color)
    local border_radius = math.max(0, corner_radius - Screen:scaleBySize(2))
    bb:paintBorder(ix, iy, iw, ih, border_w, border_color, border_radius, false)
end

local function initSeriesBadge(self_widget, c)
    if not has_bookinfomanager then return end
    local bookinfo = BookInfoManager:getBookInfo(self_widget.filepath, false)
    if bookinfo and bookinfo.series and bookinfo.series_index then
        local scfg = c.series_indicator
        self_widget.series_index = bookinfo.series_index

        local border = scfg.border_thickness
        local series_text = ColorTextWidget:new {
            text = "#" .. self_widget.series_index,
            face = Font:getFace("cfont", scfg.font_size),
            bold = true,
            fgcolor = colorFromHex(scfg.text_color),
            _vos_rgb = rgbFromHex(scfg.text_color),
        }

        self_widget.series_badge = FrameContainer:new {
            linesize = Screen:scaleBySize(2),
            bordersize = 0,
            padding = Screen:scaleBySize(2) + border,
            margin = 0,
            series_text,
        }

        self_widget._series_badge_border = border
        self_widget._series_badge_radius = Screen:scaleBySize(scfg.border_corner_radius)
        self_widget._series_badge_border_rgb = rgbFromHex(scfg.border_color)
        self_widget._series_badge_background_rgb = rgbFromHex(scfg.background_color)
        self_widget.has_series_badge = true
    end
end

local function paintSeriesBadge(self_widget, bb, c)
    local target = self_widget[1] and self_widget[1][1] and self_widget[1][1][1]
    if not target or not target.dimen then
        return
    end

    local scfg = c.series_indicator
    local position = scfg.position or "top_right"
    local d_w = math.ceil(target.dimen.w / 5)
    local d_h = math.ceil(target.dimen.h / 10)
    local ix, iy

    if position == "top_left" then
        ix = 0
        iy = 5
    elseif position == "bottom_left" then
        ix = 0
        iy = target.dimen.h - d_h - 5
    elseif position == "bottom_right" then
        ix = target.dimen.w - d_w
        iy = target.dimen.h - d_h - 5
    else -- top_right (default)
        ix = BD.mirroredUILayout() and -math.floor(d_w) or (target.dimen.w - math.floor(d_w))
        iy = 5
    end

    local badge_size = self_widget.series_badge:getSize()
    local badge_x = math.floor(target.dimen.x + ix + (d_w - badge_size.w) / 2)
    local badge_y = math.floor(target.dimen.y + iy + (d_h - badge_size.h) / 2)

    paintRoundedBadgeRGB32(
        bb,
        badge_x,
        badge_y,
        badge_size.w,
        badge_size.h,
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

local function paintFadedFinished(bb, target, x, y, self_widget, c)
    if self_widget.status ~= "complete" then
        return
    end
    local tw, th = target.dimen.w, target.dimen.h
    local fx = x + math.floor((self_widget.width - tw) / 2)
    local fy = y + math.floor((self_widget.height - th) / 2)
    bb:lightenRect(fx, fy, tw, th, c.faded_finished.fading_amount)
end

local function paintProgressBar(bb, target, x, y, self_widget, c, corner_mark_size)
    local pf = self_widget.percent_finished
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

    local has_corner_icon = (self_widget.been_opened or self_widget.do_hint_opened)
        and (self_widget.status == "reading" or self_widget.status == "abandoned")
    if pcfg.position ~= "top" and has_corner_icon and corner_mark_size then
        right = right - (corner_mark_size + Screen:scaleBySize(pcfg.gap_to_icon))
    end

    local bar_w = math.max(1, right - left)

    if pcfg.dynamic_sizing then
        local pages
        if self_widget.filepath and has_bookinfomanager then
            local bookinfo = BookInfoManager:getBookInfo(self_widget.filepath, false)
            if bookinfo and bookinfo.pages then
                pages = tonumber(bookinfo.pages)
            end
            if not pages then
                -- CoverBrowser does not store pages for EPUB (crengine), so
                -- fall back to a page-count token in the filename, e.g. "P(170)".
                pages = self_widget.filepath:match("[Pp]%((%d+)%)")
                    or self_widget.filepath:match("(%d+)%s*[Pp]ages?")
                if pages then
                    pages = tonumber(pages)
                end
            end
        end
        if pages then
            local ppp = pcfg.pages_per_pixel or 3
            local max_w = pcfg.max_bar_width or 235
            local min_w = pcfg.min_bar_width or 25
            local dynamic_w = math.max(min_w, math.min(max_w, math.floor(pages / ppp + 0.5)))
            bar_w = math.min(bar_w, Screen:scaleBySize(dynamic_w))
        end
    end

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
            bb,
            bar_x - BORDER_W,
            bar_y - BORDER_W,
            bar_w + 2 * BORDER_W,
            BAR_H + 2 * BORDER_W,
            BORDER_W,
            rgbFromHex(pcfg.border_color),
            rgbFromHex(pcfg.track_color),
            BAR_RADIUS + BORDER_W
        )
        local fill_rgb = (self_widget.status == "abandoned") and pcfg.abandoned_color_rgb or pcfg.fill_color_rgb
        paintRoundedRectRGB32(bb, bar_x, bar_y, fill_w, BAR_H, fill_rgb, BAR_RADIUS)
    else
        paintRoundedBadgeRGB32(
            bb,
            bar_x - BORDER_W,
            bar_y - BORDER_W,
            bar_w + 2 * BORDER_W,
            BAR_H + 2 * BORDER_W,
            BORDER_W,
            rgbFromHex(pcfg.border_color),
            rgbFromHex(pcfg.track_color),
            BAR_RADIUS + BORDER_W
        )
        local fill_rgb = (self_widget.status == "abandoned") and rgbFromHex(pcfg.abandoned_color)
            or rgbFromHex(pcfg.fill_color)
        paintRoundedRectRGB32(bb, bar_x, bar_y, fill_w, BAR_H, fill_rgb, BAR_RADIUS)
    end
end

local percent_badge_cache = {}

local function getPercentBadgeImage(file, width, height)
    local key = file .. "|" .. width .. "x" .. height
    if percent_badge_cache[key] then
        return percent_badge_cache[key]
    end

    local image, straight_alpha
    if file:match("%.svg$") then
        if width >= height then
            image, straight_alpha = RenderImage:renderSVGImageFile(file, width)
        else
            image, straight_alpha = RenderImage:renderSVGImageFile(file, nil, height)
        end
    else
        image = RenderImage:renderImageFile(file, false)
    end
    if not image then
        return
    end
    if image:getWidth() ~= width or image:getHeight() ~= height then
        image = RenderImage:scaleBlitBuffer(image, width, height)
    end

    local cached = { image = image, straight_alpha = straight_alpha }
    percent_badge_cache[key] = cached
    return cached
end

local function clearPercentBadgeCache()
    for key, cached in pairs(percent_badge_cache) do
        cached.image:free()
        percent_badge_cache[key] = nil
    end
end

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

    local shows = (self_widget.do_hint_opened and self_widget.been_opened)
        or (self_widget.menu and self_widget.menu.name == "history")
        or (self_widget.menu and self_widget.menu.name == "collections")
    if not shows then
        return
    end

    local pcfg = c.percent_badge
    local corner_mark_size = Screen:scaleBySize(20)

    local percent_text = string.format("%d%%", math.floor(self_widget.percent_finished * 100))
    local font_size = pcfg.text_size
    local percent_widget = TextWidget:new {
        text = percent_text,
        font_size = font_size,
        face = Font:getFace("cfont", font_size),
        alignment = "center",
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        max_width = corner_mark_size,
        truncate_with_ellipsis = true,
    }

    local BADGE_W = Screen:scaleBySize(pcfg.badge_w)
    local BADGE_H = Screen:scaleBySize(pcfg.badge_h)
    local INSET_X = Screen:scaleBySize(pcfg.move_on_x)
    local INSET_Y = Screen:scaleBySize(pcfg.move_on_y)
    local TEXT_PAD = Screen:scaleBySize(6)

    local fx = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local fy = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local fw, fh = target.dimen.w, target.dimen.h

    local default_badge_file = vosicons.iconFile("percent.badge")
    local badge_file = pcfg.custom_icon_enabled and vosicons.userIconFile(pcfg.custom_icon_name) or default_badge_file
    local percent_badge = badge_file and getPercentBadgeImage(badge_file, BADGE_W, BADGE_H)
    if not percent_badge and default_badge_file and badge_file ~= default_badge_file then
        percent_badge = getPercentBadgeImage(default_badge_file, BADGE_W, BADGE_H)
    end
    if not percent_badge then
        percent_widget:free()
        return
    end

    local bx, by = getCornerPosition(pcfg.position, fx, fy, fw, fh, BADGE_W, BADGE_H, INSET_X, INSET_Y)
    bx, by = math.floor(bx), math.floor(by)

    if percent_badge.straight_alpha then
        bb:alphablitFrom(percent_badge.image, bx, by, 0, 0, BADGE_W, BADGE_H)
    else
        bb:pmulalphablitFrom(percent_badge.image, bx, by, 0, 0, BADGE_W, BADGE_H)
    end

    percent_widget.alignment = "center"
    percent_widget.truncate_with_ellipsis = false
    percent_widget.max_width = BADGE_W - 2 * TEXT_PAD

    local ts = percent_widget:getSize()
    local tx = bx + math.floor((BADGE_W - ts.w) / 2)
    local ty = by + math.floor((BADGE_H - ts.h) / 2) - Screen:scaleBySize(pcfg.bump_up)
    percent_widget:paintTo(bb, math.floor(tx), math.floor(ty))
    percent_widget:free()
end

local function paintPagesBadge(bb, target, x, y, self_widget, c)
    if
        self_widget.is_directory
        or self_widget.file_deleted
        or self_widget.status == "complete"
        or self_widget.been_opened
    then
        return
    end

    local pcfg = c.pages_badge
    local page_count

    if self_widget.filepath and has_bookinfomanager then
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
    local font_size = pcfg.font_size

    local border = pcfg.border_thickness
    local pages_text = ColorTextWidget:new {
        text = page_text,
        face = Font:getFace("cfont", font_size),
        alignment = "left",
        fgcolor = colorFromHex(pcfg.text_color),
        _vos_rgb = rgbFromHex(pcfg.text_color),
        bold = true,
        padding = 2,
    }

    local pages_badge_frame = FrameContainer:new {
        linesize = Screen:scaleBySize(2),
        bordersize = 0,
        padding = Screen:scaleBySize(2) + border,
        margin = 0,
        pages_text,
    }

    local cover_left = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local cover_top = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local cover_w, cover_h = target.dimen.w, target.dimen.h
    local badge_w = pages_badge_frame:getSize().w
    local badge_h = pages_badge_frame:getSize().h

    local x_offset = Screen:scaleBySize(pcfg.x_offset)
    local y_offset = Screen:scaleBySize(pcfg.y_offset)
    local pos_x, pos_y =
        getCornerPosition(pcfg.position, cover_left, cover_top, cover_w, cover_h, badge_w, badge_h, x_offset, y_offset)
    pos_x, pos_y = math.floor(pos_x), math.floor(pos_y)

    paintRoundedBadgeRGB32(
        bb,
        pos_x,
        pos_y,
        badge_w,
        badge_h,
        border,
        rgbFromHex(pcfg.border_color),
        rgbFromHex(pcfg.background_color),
        Screen:scaleBySize(pcfg.border_corner_radius)
    )

    pages_badge_frame:paintTo(bb, pos_x, pos_y)
    pages_badge_frame:free(true)
end

local STATUS_ICON_ALPHA_NAMES = {
    ["dogear.reading"] = true,
    ["dogear.abandoned"] = true,
    ["dogear.abandoned.rtl"] = true,
    ["dogear.complete"] = true,
    ["dogear.complete.rtl"] = true,
    ["star.white"] = true,
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

local function paintStatusIconsOverlay(bb, x, y, self_widget, c)
    local shows = self_widget.status == "complete"
        or self_widget.status == "abandoned"
        or (self_widget.do_hint_opened and self_widget.been_opened)
        or (
            self_widget.percent_finished
            and (self_widget.menu and (self_widget.menu.name == "history" or self_widget.menu.name == "collections"))
        )
    if not shows then
        return
    end

    local target = self_widget[1] and self_widget[1][1] and self_widget[1][1][1]
    if not target or not target.dimen then
        return
    end

    local scfg = c.status_icons
    local corner_mark_size = Screen:scaleBySize(scfg.size)
    local cover_x = x + math.floor((self_widget.width - target.dimen.w) / 2)
    local cover_y = y + math.floor((self_widget.height - target.dimen.h) / 2)
    local mark_x
    if scfg.position:match("_left$") then
        mark_x = cover_x
    elseif scfg.position:match("_right$") then
        mark_x = cover_x + target.dimen.w - corner_mark_size
    else
        mark_x = cover_x + math.floor((target.dimen.w - corner_mark_size) / 2)
    end
    local mark_y
    if scfg.position:match("^top_") then
        mark_y = cover_y
    elseif scfg.position:match("^bottom_") then
        mark_y = cover_y + target.dimen.h - corner_mark_size
    else
        mark_y = cover_y + math.floor((target.dimen.h - corner_mark_size) / 2)
    end

    local name, custom_name, rotation_angle
    if self_widget.status == "abandoned" then
        name = BD.mirroredUILayout() and "dogear.abandoned.rtl" or "dogear.abandoned"
        custom_name = scfg.hold_icon_name
    elseif self_widget.status == "complete" then
        name = BD.mirroredUILayout() and "dogear.complete.rtl" or "dogear.complete"
        custom_name = scfg.finished_icon_name
    else
        name = "dogear.reading"
        custom_name = scfg.reading_icon_name
        rotation_angle = BD.mirroredUILayout() and 270 or 0
    end
    local custom_file = scfg.custom_icon_enabled and vosicons.userIconFile(custom_name)
    local mark = IconWidget:new {
        icon = name,
        file = custom_file or vosicons.iconFile(name),
        rotation_angle = rotation_angle or 0,
        width = corner_mark_size,
        height = corner_mark_size,
        alpha = true,
    }
    mark:paintTo(bb, math.floor(mark_x), math.floor(mark_y))
    mark:free()
end

local function paintCollectionStar(bb, self_widget)
    if not self_widget.filepath then
        return
    end
    if self_widget.menu and self_widget.menu.name == "collections" then
        return
    end
    if not ReadCollection:isFileInCollections(self_widget.filepath) then
        return
    end

    local settings = SETTINGS_MANAGER.settings.collection_star

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

    local star = IconWidget:new {
        icon = "star.white",
        file = vosicons.iconFile("star.white"),
        width = icon_size,
        height = icon_size,
        alpha = true,
    }

    local icon_x = center_x - math.floor(icon_size / 2)
    local icon_y = center_y - math.floor(icon_size / 2)
    star:paintTo(bb, icon_x, icon_y)
    star:free()
end

local function installDescriptionHintOverride()
    if not has_bookinfomanager then return end
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

local FolderCoverSpec = {
    names = { ".cover", "cover" },
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

local function findFolderCoverFile(dir_path)
    for _, name in ipairs(FolderCoverSpec.names) do
        local base = dir_path .. "/" .. name
        for _, ext in ipairs(FolderCoverSpec.exts) do
            local fname = base .. ext
            if util.fileExists(fname) then
                return fname
            end
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
    return lower:match("/%.?cover%.[^/]+$") ~= nil or lower:match("/%.?folder%.[^/]+$") ~= nil
end

local function getFolderAspectDimensions(width, height, border_size, c)
    local available_w = width - 2 * Size.border.thin
    local available_h = height - 2 * Size.border.thin
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
    return { w = frame_w + 2 * border_size, h = frame_h + 2 * border_size }
end

local function getFolderEntries(menu, path)
    local saved_dummy = menu._dummy
    menu._dummy = true
    local ok, entries = pcall(menu.genItemTableFromPath, menu, path)
    menu._dummy = saved_dummy
    return ok and entries or nil
end

local function clearFolderCoverCache()
    folder_cover_cache = {}
end

-- Decode a folder cover file at most once per target size, scaled down to the
-- requested dimensions (so only a small blitbuffer is ever retained).
local function getCachedFolderCoverFile(cover_file, w, h)
    local key = cover_file .. "#" .. w .. "x" .. h
    local bb = folder_cover_cache[key]
    if not bb then
        local ok, rendered = pcall(RenderImage.renderImageFile, RenderImage, cover_file, false, w, h)
        if ok and rendered then
            bb = rendered
            folder_cover_cache[key] = bb
            local count = 0
            for _ in pairs(folder_cover_cache) do
                count = count + 1
            end
            if count > 128 then
                folder_cover_cache = {}
            end
        end
    end
    return bb
end

local function getCachedFolderCover(path, menu)
    if not has_bookinfomanager then return end
    local bookinfo = BookInfoManager:getBookInfo(path, true)
    if not (bookinfo and bookinfo.cover_bb) then
        return
    end
    if
        bookinfo.has_cover
        and bookinfo.cover_fetched
        and not bookinfo.ignore_cover
        and not BookInfoManager.isCachedCoverInvalid(bookinfo, menu.cover_specs)
    then
        return {
            data = bookinfo.cover_bb,
            width = bookinfo.cover_w,
            height = bookinfo.cover_h,
        }
    end
    bookinfo.cover_bb:free()
end

local function collectFolderCovers(menu, root_path, direct_entries, wanted)
    local covers = {}
    local queue = {}
    local queued = { [root_path] = true }
    local seen_files = {}
    local inspected_dirs = 0
    local inspected_files = 0
    local max_dirs = 64
    local max_files = 256
    local root_prefix = root_path .. "/"

    local function inspect(entries)
        for _, entry in ipairs(entries or {}) do
            local path = entry.path or entry.file
            if type(path) == "string" and (entry.is_file or entry.file) then
                if not seen_files[path] and not isCoverFile(path) and inspected_files < max_files then
                    seen_files[path] = true
                    inspected_files = inspected_files + 1
                    local cover = getCachedFolderCover(path, menu)
                    if cover then
                        table.insert(covers, cover)
                        if #covers >= wanted then
                            return true
                        end
                    end
                end
            elseif
                type(path) == "string"
                and path ~= root_path
                and path:sub(1, #root_prefix) == root_prefix
                and not queued[path]
            then
                queued[path] = true
                table.insert(queue, path)
            end
        end
    end

    if inspect(direct_entries) then
        return covers
    end
    local queue_index = 1
    while queue_index <= #queue and inspected_dirs < max_dirs and inspected_files < max_files do
        local path = queue[queue_index]
        queue_index = queue_index + 1
        inspected_dirs = inspected_dirs + 1
        if inspect(getFolderEntries(menu, path)) then
            break
        end
    end
    return covers
end

local function newFolderCoverCell(source, width, height)
    local cover_w = source.width or source.data:getWidth()
    local cover_h = source.height or source.data:getHeight()
    local max_w = math.max(1, width - 2 * Size.border.thin)
    local max_h = math.max(1, height - 2 * Size.border.thin)
    local scale_factor
    if has_bookinfomanager then
        local _, __, sf = BookInfoManager.getCachedCoverSize(cover_w, cover_h, max_w, max_h)
        scale_factor = sf
    else
        scale_factor = math.min(max_w / cover_w, max_h / cover_h)
    end
    local image = ImageWidget:new { image = source.data, scale_factor = scale_factor }
    source.data = nil
    local cover = FrameContainer:new {
        margin = 0,
        padding = 0,
        radius = Size.radius.default,
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_GRAY_3,
        background = Blitbuffer.COLOR_GRAY_3,
        image,
    }
    return CenterContainer:new { dimen = { w = width, h = height }, cover }
end

local function buildFolderCoverGroup(covers, style, dimen)
    local group = OverlapGroup:new { dimen = dimen }
    if style == "stack" then
        local cell_w = math.max(1, math.floor(dimen.w * 0.76))
        local cell_h = math.max(1, math.floor(dimen.h * 0.76))
        for index, source in ipairs(covers) do
            local position = #covers == 1 and 0.5 or (index - 1) / (#covers - 1)
            local cell = newFolderCoverCell(source, cell_w, cell_h)
            table.insert(
                group,
                CustomPositionContainer:new {
                    dimen = dimen,
                    horizontal_position = position,
                    vertical_position = position,
                    widget = cell,
                    cell,
                }
            )
        end
    else
        local gap = Size.padding.small
        local cell_w, cell_h, positions
        if #covers == 1 then
            cell_w = math.max(1, math.floor(dimen.w * 0.76))
            cell_h = math.max(1, math.floor(dimen.h * 0.76))
            positions = { { 0.5, 0.5 } }
        elseif #covers == 2 then
            cell_w = math.max(1, math.floor((dimen.w - gap) / 2))
            cell_h = math.max(1, math.floor(dimen.h * 0.8))
            positions = { { 0, 0.5 }, { 1, 0.5 } }
        elseif #covers == 3 then
            cell_w = math.max(1, math.floor((dimen.w - gap) / 2))
            cell_h = math.max(1, math.floor((dimen.h - gap) / 2))
            positions = { { 0, 0 }, { 1, 0 }, { 0.5, 1 } }
        else
            cell_w = math.max(1, math.floor((dimen.w - gap) / 2))
            cell_h = math.max(1, math.floor((dimen.h - gap) / 2))
            positions = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
        end
        for index, source in ipairs(covers) do
            local cell = newFolderCoverCell(source, cell_w, cell_h)
            table.insert(
                group,
                CustomPositionContainer:new {
                    dimen = dimen,
                    horizontal_position = positions[index][1],
                    vertical_position = positions[index][2],
                    widget = cell,
                    cell,
                }
            )
        end
    end
    return group
end

local function getFolderTextBox(self_widget, dimen, c)
    local text = MenuTextOverrides.cleanText(self_widget.text, SETTINGS_MANAGER.settings.extras.menu_text)
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
        directory = TextBoxWidget:new {
            text = text,
            face = Font:getFace("cfont", dir_font_size),
            width = dimen.w,
            alignment = "center",
            bold = true,
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

local function setFolderCover(self_widget, img, c, entries)
    local frame_dimen = getFolderAspectDimensions(self_widget.width, self_widget.height, 0, c)
    local rcfg = c.cover_aspect_ratio

    local image
    if img.file then
        local bb = getCachedFolderCoverFile(img.file, frame_dimen.w, frame_dimen.h)
        if bb then
            image = ImageWidget:new {
                image = bb,
                width = frame_dimen.w,
                height = frame_dimen.h,
                image_disposable = false, -- we own it via folder_cover_cache
                stretch_limit_percentage = rcfg.stretch_limit,
            }
        else
            -- Fallback: decode directly without caching in the ImageCache
            -- (a large cover would exceed it and abort).
            image = ImageWidget:new {
                file = img.file,
                width = frame_dimen.w,
                height = frame_dimen.h,
                stretch_limit_percentage = rcfg.stretch_limit,
                file_do_cache = false,
            }
        end
    elseif img.style == "collage" or img.style == "stack" then
        image = buildFolderCoverGroup(img.covers, img.style, frame_dimen)
    else
        image = ImageWidget:new {
            image = img.data,
            width = frame_dimen.w,
            height = frame_dimen.h,
            stretch_limit_percentage = rcfg.stretch_limit,
        }
        img.data = nil
    end

    local image_widget = FrameContainer:new { padding = 0, bordersize = 0, image, overlap_align = "center" }
    local image_size = image:getSize()

    local fcfg = c.folder_covers
    local folder_name_widget
    if fcfg.show_folder_name then
        local directory = getFolderTextBox(self_widget, { w = image_size.w, h = image_size.h }, c)
        local name_positions = { top = 0, center = 0.5, bottom = 1 }
        local name_frame = FrameContainer:new {
            padding = -1,
            bordersize = 1,
            AlphaContainer:new { alpha = 0.75, directory },
        }
        folder_name_widget = CustomPositionContainer:new {
            dimen = frame_dimen,
            horizontal_position = 0.5,
            vertical_position = name_positions[fcfg.folder_name_position] or 0.5,
            widget = name_frame,
            name_frame,
        }
    else
        folder_name_widget = VerticalSpan:new { width = 0 }
    end

    local nbitems_widget
    local file_count, folder_count = 0, 0
    if entries then
        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                if not isCoverFile(entry.path or entry.file) then
                    file_count = file_count + 1
                end
            else
                folder_count = folder_count + 1
            end
        end
    end
    local item_count = file_count > 0 and file_count or folder_count

    if item_count > 0 then
        local nbitems = TextWidget:new {
            text = tostring(item_count),
            face = Font:getFace("cfont", fcfg.file_count_size),
            bold = true,
            padding = 0,
        }
        local nb_size = math.max(nbitems:getSize().w, nbitems:getSize().h)
        local margin = Screen:scaleBySize(5)
        local count_positions = {
            top_left = { 0, 0 },
            top_center = { 0.5, 0 },
            top_right = { 1, 0 },
            center_left = { 0, 0.5 },
            center_right = { 1, 0.5 },
            bottom_left = { 0, 1 },
            bottom_center = { 0.5, 1 },
            bottom_right = { 1, 1 },
        }
        local count_position = count_positions[fcfg.file_count_position] or count_positions.bottom_right
        local count_badge = FrameContainer:new {
            padding = 2,
            bordersize = 1,
            radius = math.ceil(nb_size),
            background = Blitbuffer.COLOR_GRAY_E,
            CenterContainer:new { dimen = { w = nb_size, h = nb_size }, nbitems },
        }
        local count_dimen = {
            w = math.max(1, frame_dimen.w - margin * 2),
            h = math.max(1, frame_dimen.h - margin * 2),
        }
        nbitems_widget = CenterContainer:new {
            dimen = frame_dimen,
            CustomPositionContainer:new {
                dimen = count_dimen,
                horizontal_position = count_position[1],
                vertical_position = count_position[2],
                widget = count_badge,
                count_badge,
            },
        }
    else
        nbitems_widget = VerticalSpan:new { width = 0 }
    end

    self_widget._folder_frame_dimen = frame_dimen
    self_widget._folder_image_size = image_size

    local widget = CenterContainer:new {
        dimen = { w = self_widget.width, h = self_widget.height },
        CenterContainer:new {
            dimen = { w = self_widget.width, h = self_widget.height },
            OverlapGroup:new { dimen = frame_dimen, image_widget, folder_name_widget, nbitems_widget },
        },
    }

    if self_widget._underline_container[1] then
        self_widget._underline_container[1]:free()
    end
    self_widget._underline_container[1] = widget
end

local function updateFolderCover(self_widget, c)
    if self_widget._foldercover_processed or self_widget.menu.no_refresh_covers then
        return
    end
    if self_widget.entry.is_file or self_widget.entry.file then
        return
    end
    local dir_path = self_widget.entry and self_widget.entry.path
    if not dir_path then
        return
    end
    local entries = getFolderEntries(self_widget.menu, dir_path)

    local cover_file = findFolderCoverFile(dir_path)
    if cover_file then
        local ok = pcall(setFolderCover, self_widget, { file = cover_file }, c, entries)
        if ok then
            self_widget._foldercover_processed = true
            return
        end
    end

    if not entries then
        return
    end

    local style = c.folder_covers.style or "single"
    local wanted = style == "single" and 1 or 4
    local covers = collectFolderCovers(self_widget.menu, dir_path, entries, wanted)
    if #covers == 0 then
        return
    end
    if style == "single" then
        setFolderCover(self_widget, covers[1], c, entries)
    else
        setFolderCover(self_widget, { style = style, covers = covers }, c, entries)
    end
    self_widget._foldercover_processed = true
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

    local rc = c.rounded_corners
    local corner_radius = math.max(1, math.floor(
        math.min(Screen:scaleBySize(rc.size), image_size.w, image_size.h)))
    if corner_radius <= 0 then return end

    clipRoundedRect(bb, image_x, image_y, image_size.w, image_size.h, corner_radius)

    local cover_border = Screen:scaleBySize(c.folder_covers.folder_border)
    local border_color = colorFromHex(rc.border_color)
    local border_radius = math.max(0, corner_radius - Screen:scaleBySize(2))
    bb:paintBorder(image_x, image_y, image_size.w, image_size.h,
        cover_border, border_color, border_radius, false)
end

-- Folder covers repeatedly generate item tables. Keep a small per-chooser
-- cache so long browsing sessions cannot retain every directory ever seen.
local function installFileChooserCache()
    if FileChooser._vos_getlistitem_patched then
        return
    end
    FileChooser._vos_getlistitem_patched = true

    local orig_getListItem = FileChooser.getListItem
    local orig_clearSortingCache = FileChooser.clearSortingCache
    local max_cache_entries = 512

    function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
        if not masterEnabled() then
            return orig_getListItem(self, dirpath, f, fullpath, attributes, collate)
        end
        local cache = self._vos_list_item_cache
        if not cache then
            cache = { count = 0 }
            self._vos_list_item_cache = cache
        end
        local key = table.concat({
            tostring(dirpath),
            tostring(f),
            tostring(fullpath),
            tostring(attributes and attributes.mode),
            tostring(attributes and attributes.size),
            tostring(attributes and attributes.modification),
            tostring(collate),
            tostring(self.show_filter and self.show_filter.status),
        }, "\31")
        local item = cache[key]
        if item then
            return item
        end
        if cache.count >= max_cache_entries then
            cache = { count = 0 }
            self._vos_list_item_cache = cache
        end
        item = orig_getListItem(self, dirpath, f, fullpath, attributes, collate)
        cache[key] = item
        cache.count = cache.count + 1
        return item
    end

    function FileChooser:clearSortingCache(...)
        self._vos_list_item_cache = nil
        return orig_clearSortingCache(self, ...)
    end
end

-- Pagination widgets are retained so visibility can be toggled at runtime.

local hide_pagination_names = {
    filemanager = true,
    history = true,
    collections = true,
}

local function isHidePaginationMenu(menu)
    -- Match by name, or by full-screen fm-style menus (e.g. collections
    -- list has no name)
    return hide_pagination_names[menu.name]
        or (menu.covers_fullscreen and menu.is_borderless and menu.title_bar_fm_style)
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
            table.insert(removed, { index = i, widget = holder[i] })
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
            -- Reinitialization rebuilds the layout but retains instance fields.
            self._vos_pagination_ready = nil
            vosPreparePaginationState(self)
            vosSetPaginationHidden(self, hidePaginationEnabled())
        end
    end
end

-- Upvalue-preserving method wrapping
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
    local chunk = "local "
        .. names_src
        .. "\n"
        .. "local __vos_extra\n"
        .. "return function(...)\n"
        .. "    return __vos_extra.invoke("
        .. names_src
        .. ", ...)\n"
        .. "end\n"
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
        debug.setupvalue(wrapper, extra_slot, { invoke = invoke })
    end
    return wrapper
end

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
    local project_title_dir = userpatch.getUpValue(TRUE_ORIG_PAINTTO, "plugin_dir")
    local is_project_title_mosaic = type(project_title_dir) == "string"
        and project_title_dir:match("projecttitle%.koplugin") ~= nil

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
            local StretchingImageWidget = local_ImageWidget:extend {}

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
        else
            logger.warn("VisualOverhaul: could not find ImageWidget upvalue for stretching")
        end
    end

    MosaicMenuItem.init = preserveUpvalues(TRUE_ORIG_INIT, function(self)
        local enabled = masterEnabled()
        if enabled and self.width and self.height then
            local border_size = Size.border.thin
            MAX_IMG_W = self.width - 2 * border_size
            MAX_IMG_H = self.height - 2 * border_size
        end
        TRUE_ORIG_INIT(self)
        if not enabled then
            return
        end
        local c = getCfg()

        if self.is_directory or self.file_deleted then
            return
        end

        if c.series_indicator.style == "badge" then
            initSeriesBadge(self, c)
        end
    end)

    MosaicMenuItem.update = preserveUpvalues(TRUE_ORIG_UPDATE, function(self)
        TRUE_ORIG_UPDATE(self)
        if not masterEnabled() then
            return
        end
        local c = getCfg()
        if c.folder_covers.enabled then
            updateFolderCover(self, c)
        end
    end)

    MosaicMenuItem.paintTo = preserveUpvalues(TRUE_ORIG_PAINTTO, function(self, bb, x, y)
        local cb_enabled = masterEnabled()
        local star_enabled = collectionStarEnabled()
        local c = cb_enabled and getCfg() or nil
        local pt_cleanup = is_project_title_mosaic and c and c.projecttitle_cleanup or nil

        local function paintToOrig(bb, x, y)
            local suppress_status = pt_cleanup and pt_cleanup.hide_status_icons
            local suppress_progress = pt_cleanup and pt_cleanup.hide_progress_widgets
            local suppress_series = pt_cleanup and pt_cleanup.hide_series_indicator
            local suppress_border = pt_cleanup and pt_cleanup.hide_cover_borders
            local suppress_large_book = pt_cleanup and pt_cleanup.hide_large_book_icon
            local saved_been_opened = self.been_opened
            local saved_status = self.status
            local saved_percent_finished = self.percent_finished
            local saved_show_progress_bar = self.show_progress_bar
            local target = self[1] and self[1][1] and self[1][1][1]
            local saved_border_size = target and target.bordersize
            local orig_get_setting
            local orig_image_paint
            local orig_progress_paint
            local orig_is_in_collection

            if ((c and c.status_icons.enabled) or suppress_status) and self.been_opened then
                self.been_opened = false
            end
            if suppress_status then
                self.status = nil
            end
            if suppress_progress then
                self.percent_finished = nil
                self.show_progress_bar = false
            end
            if suppress_border and target then
                target.bordersize = 0
            end
            if suppress_series and has_bookinfomanager then
                orig_get_setting = BookInfoManager.getSetting
                BookInfoManager.getSetting = function(manager, setting_name, ...)
                    if setting_name == "series_mode" then
                        return nil
                    end
                    return orig_get_setting(manager, setting_name, ...)
                end
            end
            if suppress_status or suppress_large_book then
                orig_image_paint = ImageWidget.paintTo
                ImageWidget.paintTo = function(widget, ...)
                    local file = widget.file
                    if type(file) == "string" then
                        if
                            suppress_status
                            and (
                                file:match("/projecttitle%.koplugin/resources/trophy%.svg$")
                                or file:match("/projecttitle%.koplugin/resources/pause%.svg$")
                                or file:match("/projecttitle%.koplugin/resources/new%.svg$")
                            )
                        then
                            return
                        end
                        if suppress_large_book and file:match("/projecttitle%.koplugin/resources/large_book%.svg$") then
                            return
                        end
                    end
                    return orig_image_paint(widget, ...)
                end
            end
            if (c and c.progress_bar.hide_native) or suppress_progress then
                local ProgressWidget = require("ui/widget/progresswidget")
                orig_progress_paint = ProgressWidget.paintTo
                ProgressWidget.paintTo = function() end
            end
            if hideNativeCollectionStarEnabled() then
                orig_is_in_collection = ReadCollection.isFileInCollections
                ReadCollection.isFileInCollections = function()
                    return false
                end
            end

            local ok, result = xpcall(function()
                return TRUE_ORIG_PAINTTO(self, bb, x, y)
            end, debug.traceback)

            if orig_is_in_collection then
                ReadCollection.isFileInCollections = orig_is_in_collection
            end
            if orig_progress_paint then
                require("ui/widget/progresswidget").paintTo = orig_progress_paint
            end
            if orig_image_paint then
                ImageWidget.paintTo = orig_image_paint
            end
            if orig_get_setting then
                BookInfoManager.getSetting = orig_get_setting
            end
            if suppress_border and target then
                target.bordersize = saved_border_size
            end
            self.been_opened = saved_been_opened
            self.status = saved_status
            self.percent_finished = saved_percent_finished
            self.show_progress_bar = saved_show_progress_bar

            if not ok then
                error(result, 0)
            end
            return result
        end

        if not cb_enabled and not star_enabled then
            paintToOrig(bb, x, y)
            return
        end
        if not cb_enabled then
            paintToOrig(bb, x, y)
            if star_enabled then
                paintCollectionStar(bb, self)
            end
            return
        end

        paintToOrig(bb, x, y)

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
            paintRoundedCorners(bb, target, x, y, self, c)
        end

        if c.series_indicator.style == "badge" and self.has_series_badge and self.series_badge then
            paintSeriesBadge(self, bb, c)
        elseif c.series_indicator.style == "bar" and has_bookinfomanager then
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
            paintStatusIconsOverlay(bb, x, y, self, c)
        end

        if star_enabled then
            paintCollectionStar(bb, self)
        end
    end)

    MosaicMenuItem.free = preserveUpvalues(TRUE_ORIG_FREE, function(self)
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
        if TRUE_ORIG_FREE then
            TRUE_ORIG_FREE(self)
        end
    end)

    installIconAlphaOverride()
    installDescriptionHintOverride()
    installFileChooserCache()
end

local CoverBrowserModule = { name = "coverbrowser" }

function CoverBrowserModule:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function CoverBrowserModule:init()
    SETTINGS_MANAGER = self.settings
    patchMosaicMenuItem()
    installHidePaginationOverride()
end

-- Hooks are process-wide and installed idempotently. Reinitialization clears
-- plugin caches and updates retained pagination state before the UI rebuild.
function CoverBrowserModule:reinit()
    clearPercentBadgeCache()
    clearFolderCoverCache()
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    if fm then
        if fm.file_chooser then
            vosSetPaginationHidden(fm.file_chooser, hidePaginationEnabled())
            fm.file_chooser._vos_list_item_cache = nil
        end
    end
    for _, widget in ipairs(UIManager._window_stack) do
        if widget._vos_pagination_ready then
            vosSetPaginationHidden(widget, hidePaginationEnabled())
        end
    end
end

return CoverBrowserModule
