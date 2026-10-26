-- VOS rounded corners for SimpleUI home-screen covers.
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local SimpleUIRounded = { name = "simpleui_rounded" }

function SimpleUIRounded:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function SimpleUIRounded:isEnabled()
    return self.settings:isMasterEnabled()
        and self.settings.settings.coverbrowser
        and self.settings.settings.coverbrowser.rounded_corners
        and self.settings.settings.coverbrowser.rounded_corners.enabled
end

function SimpleUIRounded:cfg()
    return self.settings.settings.coverbrowser.rounded_corners
end

local _corner_cache = {}

local function getCornerCache(r)
    local dr = math.max(1, math.floor(r))
    if _corner_cache[dr] then return _corner_cache[dr] end
    local clip, r2 = {}, dr * dr
    for dy = 0, dr - 1 do
        for dx = 0, dr - 1 do
            clip[dy * dr + dx + 1] = (dx * dx + dy * dy) > r2
        end
    end
    _corner_cache[dr] = { clip = clip, dr = dr }
    return _corner_cache[dr]
end

local function applyCornerMask(bb, mask, sx, sy, r, dr, color, flip_x, flip_y)
    local step, idx = r / dr, 0
    for dy = 0, dr - 1 do
        local fy = flip_y and (dr - 1 - dy) or dy
        for dx = 0, dr - 1 do
            idx = idx + 1
            if mask[idx] then
                local fx = flip_x and (dr - 1 - dx) or dx
                if step <= 1.0 then
                    bb:setPixelClamped(sx + fx, sy + fy, color)
                else
                    local fx0, fx1 = math.floor(fx * step), math.floor((fx + 1) * step) - 1
                    local fy0, fy1 = math.floor(fy * step), math.floor((fy + 1) * step) - 1
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

local function clipRoundedRect(bb, x, y, w, h, r, color)
    if r <= 0 or w <= 0 or h <= 0 then return end
    r = math.min(math.floor(r), math.floor(w / 2), math.floor(h / 2))
    if r <= 0 then return end
    local cache = getCornerCache(r)
    local bb_w, bb_h = bb:getWidth(), bb:getHeight()
    local function safePixel(px, py)
        if px < 0 or py < 0 or px >= bb_w or py >= bb_h then
            return Blitbuffer.COLOR_WHITE
        end
        return bb:getPixel(px, py)
    end
    local colors = color and { color, color, color, color } or {
        safePixel(x - 1, y - 1), safePixel(x + w + 1, y - 1),
        safePixel(x - 1, y + h + 1), safePixel(x + w + 1, y + h + 1),
    }
    applyCornerMask(bb, cache.clip, x, y, r, cache.dr, colors[1], true, true)
    applyCornerMask(bb, cache.clip, x + w - r, y, r, cache.dr, colors[2], false, true)
    applyCornerMask(bb, cache.clip, x, y + h - r, r, cache.dr, colors[3], true, false)
    applyCornerMask(bb, cache.clip, x + w - r, y + h - r, r, cache.dr, colors[4], false, false)
end

local function colorFromHex(hex)
    if not hex then return Blitbuffer.COLOR_BLACK end
    return Blitbuffer.colorFromString(hex)
end

local function isImageWidget(widget)
    return type(widget) == "table"
        and widget.image ~= nil
        and type(widget.paintTo) == "function"
end

local function findCoverFrame(widget, seen)
    if type(widget) ~= "table" then return nil end
    seen = seen or {}
    if seen[widget] then return nil end
    seen[widget] = true
    for i = 1, #widget do
        if widget.bordersize ~= nil and isImageWidget(widget[i]) then
            return widget
        end
    end
    for i = 1, #widget do
        local found = findCoverFrame(widget[i], seen)
        if found then return found end
    end
    return nil
end

local function patchCover(self_ref, cover_widget)
    if not cover_widget or not self_ref:isEnabled() then return cover_widget end
    local frame = findCoverFrame(cover_widget)
    if not frame or type(frame.paintTo) ~= "function" then return cover_widget end
    if frame._vos_rounded_patched then return cover_widget end
    frame._vos_rounded_patched = true

    local original_paintTo = frame.paintTo
    frame.paintTo = function(self, bb, x, y, ...)
        original_paintTo(self, bb, x, y, ...)
        local dimen = self.dimen
        local w = (dimen and dimen.w) or self.width
        local h = (dimen and dimen.h) or self.height
        if not (w and h and w > 0 and h > 0) then return end

        local rc = self_ref:cfg()
        local radius = Screen:scaleBySize(rc.size or 0)
        local border_w = Screen:scaleBySize(rc.border_width or 0.5)
        local border_color = colorFromHex(rc.border_color)
        local border_radius = math.max(0, radius - Screen:scaleBySize(2))

        clipRoundedRect(bb, x, y, w, h, radius)
        if w > 2 and h > 2 and border_w > 0 then
            bb:paintBorder(x + 1, y + 1, w - 2, h - 2,
                border_w, border_color, border_radius, false)
        end
    end

    frame.bordersize = 0
    return cover_widget
end

-- Round the visible corners of SimpleUI's perspective-warped side covers.
local function roundWarpedCover(warped, self_ref)
    if not warped or not self_ref:isEnabled() or warped._vos_rounded_patched then
        return warped
    end

    local bb, tops, heights = warped.bb, warped.tops, warped.heights
    if not bb or not tops or not heights then return warped end

    local rc = self_ref:cfg()
    local radius = math.floor(Screen:scaleBySize(rc.size or 0))
    local w, h = bb:getWidth(), bb:getHeight()
    radius = math.min(radius, math.floor(w / 2), math.floor(h / 2))
    if radius < 1 then return warped end

    local white = Blitbuffer.COLOR_WHITE
    for x = 0, math.min(radius - 1, w - 1) do
        local left_dx = radius - x
        local top = tops[x + 1]
        local bottom = top + heights[x + 1] - 1
        for d = 0, radius - 1 do
            local dy = radius - d
            if left_dx * left_dx + dy * dy > radius * radius then
                local py_top = top + d
                local py_bottom = bottom - d
                if py_top >= 0 and py_top < h then
                    bb:setPixelClamped(x, py_top, white)
                end
                if py_bottom >= 0 and py_bottom < h then
                    bb:setPixelClamped(x, py_bottom, white)
                end
            end
        end
    end

    for x = math.max(0, w - radius), w - 1 do
        local right_dx = radius - (w - 1 - x)
        local top = tops[x + 1]
        local bottom = top + heights[x + 1] - 1
        for d = 0, radius - 1 do
            local dy = radius - d
            if right_dx * right_dx + dy * dy > radius * radius then
                local py_top = top + d
                local py_bottom = bottom - d
                if py_top >= 0 and py_top < h then
                    bb:setPixelClamped(x, py_top, white)
                end
                if py_bottom >= 0 and py_bottom < h then
                    bb:setPixelClamped(x, py_bottom, white)
                end
            end
        end
    end

    local border_color = colorFromHex(rc.border_color)
    local border_w = math.max(1, math.floor(Screen:scaleBySize(rc.border_width or 0.5)))
    for x = 0, math.min(radius - 1, w - 1) do
        local dx = radius - x
        local inset = math.floor(radius - math.sqrt(math.max(0, radius * radius - dx * dx)))
        local top = tops[x + 1]
        local bottom = top + heights[x + 1] - 1
        for bw = 0, border_w - 1 do
            local py_top = top + inset + bw
            local py_bottom = bottom - inset - bw
            if py_top >= 0 and py_top < h then
                bb:setPixelClamped(x, py_top, border_color)
            end
            if py_bottom >= 0 and py_bottom < h then
                bb:setPixelClamped(x, py_bottom, border_color)
            end
        end
    end
    for x = math.max(0, w - radius), w - 1 do
        local dx = radius - (w - 1 - x)
        local inset = math.floor(radius - math.sqrt(math.max(0, radius * radius - dx * dx)))
        local top = tops[x + 1]
        local bottom = top + heights[x + 1] - 1
        for bw = 0, border_w - 1 do
            local py_top = top + inset + bw
            local py_bottom = bottom - inset - bw
            if py_top >= 0 and py_top < h then
                bb:setPixelClamped(x, py_top, border_color)
            end
            if py_bottom >= 0 and py_bottom < h then
                bb:setPixelClamped(x, py_bottom, border_color)
            end
        end
    end

    warped._vos_rounded_patched = true
    return warped
end

local function patchCoverWarp(self_ref)
    local ok, CoverWarp = pcall(require, "engines/sui_cover_warp")
    if not ok or not CoverWarp or type(CoverWarp.warp) ~= "function"
        or CoverWarp._vos_rounded_patched then
        return
    end

    local original_warp = CoverWarp.warp
    CoverWarp.warp = function(...)
        local warped = original_warp(...)
        return roundWarpedCover(warped, self_ref)
    end
    CoverWarp._vos_rounded_patched = true
end

function SimpleUIRounded:init()
    local self_ref = self

    patchCoverWarp(self_ref)

    local ok, SH = pcall(require, "modules/module_books_shared")
    if not ok or not SH or SH._vos_rounded_patched then return end
    SH._vos_rounded_patched = true

    local function wrapCoverFunction(name)
        local original = SH[name]
        if type(original) ~= "function" then return end
        SH[name] = function(...)
            local result = original(...)
            return patchCover(self_ref, result)
        end
    end

    wrapCoverFunction("getBookCover")
    wrapCoverFunction("getCroppedBookCover")
end

function SimpleUIRounded:reinit()
end

return SimpleUIRounded
