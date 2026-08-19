-- Applies VOS rounded-corner settings to SimpleUI book covers.
-- Self-contained: includes its own corner-mask primitives so it works
-- independently of the mosaic-menu code path in modules/vos.lua.

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

--- Algorithmic rounded-corner mask (background-agnostic).

local _corner_cache = {}

local function getCornerCache(r)
    local dr = math.max(1, math.floor(r))
    if _corner_cache[dr] then return _corner_cache[dr] end
    local r2 = dr * dr
    local clip = {}
    for dy = 0, dr - 1 do
        for dx = 0, dr - 1 do
            clip[dy * dr + dx + 1] = (dx * dx + dy * dy) > r2
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

local function colorFromHex(hex)
    local Blitbuffer = require("ffi/blitbuffer")
    if not hex then return Blitbuffer.COLOR_BLACK end
    return Blitbuffer.colorFromString(hex)
end

--- Patch SimpleUI's getBookCover to apply rounded corners.

function SimpleUIRounded:init()
    local ok, SH = pcall(require, "modules/module_books_shared")
    if not ok or not SH then return end
    if SH._vos_rounded_patched then return end
    SH._vos_rounded_patched = true

    local self_ref = self
    local orig_getBookCover = SH.getBookCover

    function SH.getBookCover(filepath, w, h)
        local fc = orig_getBookCover(filepath, w, h)
        if not fc then return nil end
        if not self_ref:isEnabled() then return fc end

        local img = fc[1]
        if not img then return fc end

        if img._vos_rounded_patched then return fc end
        img._vos_rounded_patched = true

        local rc = self_ref:cfg()
        local corner_radius = Screen:scaleBySize(rc.size)
        local border_w = Screen:scaleBySize(rc.border_width or 0.5)
        local border_color = colorFromHex(rc.border_color)
        local border_radius = math.max(0, corner_radius - Screen:scaleBySize(2))

        local orig_img_paintTo = img.paintTo
        function img:paintTo(bb, x, y)
            orig_img_paintTo(self, bb, x, y)

            local fw, fh = fc.dimen.w, fc.dimen.h
            local fx = x + math.floor((self.width - fw) / 2)
            local fy = y + math.floor((self.height - fh) / 2)

            local pad = fc.padding or 0
            local ix = math.floor(fx + pad)
            local iy = math.floor(fy + pad)
            local iw = math.max(1, fw - 2 * pad)
            local ih = math.max(1, fh - 2 * pad)

            clipRoundedRect(bb, fx, fy, fw, fh, corner_radius)
            bb:paintBorder(ix, iy, iw, ih, border_w, border_color, border_radius, false)
        end

        fc.bordersize = 0
        return fc
    end
end

function SimpleUIRounded:reinit()
end

return SimpleUIRounded
