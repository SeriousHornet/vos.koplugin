# Visual Overhaul Suite (VOS) for KOReader

Visual Overhaul Suite is a KOReader plugin for customizing the file browser, cover grid, navigation, menus, and related interface elements from one settings menu.

VOS combines the functionality of the earlier [SeriousHornet/KOReader.patches](https://github.com/SeriousHornet/KOReader.patches) collection into an installable plugin. Its resources are bundled, settings are applied through the UI, and all changes can be previewed without restarting KOReader.

Fully compatible with popular UIs like SimpleUI, Project: Title, Bookshelf.

If you have been using any of my [patches](https://github.com/SeriousHornet/KOReader.patches) previously, you can now remove them and install this plugin. Don't worry about the custom settings you set on those patches, you can configure everything in the VOS menu now.

## Screenshots
### Folder with books
<img width="637" height="832" alt="pic1" src="https://github.com/user-attachments/assets/cd8cadc4-4a10-4d37-b470-84d2bc16a9dc" />

### Folder with folders with books
<img width="638" height="833" alt="pic2" src="https://github.com/user-attachments/assets/ceb5a6cc-28a6-4e58-bfff-bef1665cc582" />

### Finished books
<img width="638" height="833" alt="pic3" src="https://github.com/user-attachments/assets/bc4f76e0-6b91-4a71-b717-f713b7f6fdb9" />

### Folder with books in a series
<img width="628" height="463" alt="pic4" src="https://github.com/user-attachments/assets/769e0de8-0673-4207-b3d1-6fed0d607e4e" />

### VOS Menu
<img width="638" height="460" alt="pic5" src="https://github.com/user-attachments/assets/e33ddb4a-71ed-410e-a7f6-8df61ef91394" />

### Quicksettings
<img width="638" height="346" alt="pic6" src="https://github.com/user-attachments/assets/36ce9ccf-4b3a-4bfd-8c63-5440ffb0a410" />

## Features

### Bottom Navigation Bar

- Configurable bottom navigation bar for the file browser
- Adjustable size, labels, active-tab styling, and tab order
- Built-in tabs for common KOReader views and optional plugin integrations
- Custom folder tabs with user-provided SVG or PNG icons
- Optional navigation bars in supported standalone views

**Compatible with SimpleUI's Navbar. When SimpleUI is installed, VOS leaves its navigation bar untouched to avoid conflicting with it.**

### Cover Grid Enhancements

VOS enhances KOReader's mosaic cover view with:

- DPI-aware rounded corners for book and folder covers
- Configurable cover aspect ratio, fill behavior, and stretching
- Folder artwork, folder names, and item-count badges
- Adjustable fading for finished books

A folder can provide its own artwork as `.cover.jpg`, `.cover.jpeg`, `.cover.png`, `.cover.webp`, or `.cover.gif`. If no folder artwork exists, VOS can use an available cached cover from a book inside that folder.

### Badges and Status

- Rounded **reading-progress bar** with optional dynamic length based on book size
- Percentage badge with adjustable dimensions, placement, and an optional custom SVG or PNG icon
- Page-count badge with configurable colors, border, and position
- Numbered series badges with configurable colors, border, and position or flap-style series indicators
- Resizable and repositionable reading, hold/abandoned, and finished status icons with optional custom SVG or PNG artwork
- Configurable collection star

Page and series badges depend on metadata available to KOReader. The page badge can also read a `P(123)` or `p(123)` marker from a file's name text.

### Clean up tools

Adds options to disable default Coverbrowser/Project: Title's widgets so new widgets can be applied.
- Disable the description hint bar
- Disable pagination in supported file-browser views (https://github.com/qewer33/koreader-patches/blob/main/2-hide-pagination.lua)
- Disable KOReader's default cover progress bar
- Disable the default collection star

### Extras

Adds commonly used community patches for KOReader. Credits to patches' authors for creating the functionality, I merely absorbed it under VOS.
 
- Select a UI font with matching regular and bold files. Credits: [@sebdelsol](https://github.com/sebdelsol/KOReader.patches/blob/main/2--ui-font.lua)
- Hide empty folders or the up-folder entry. Credits: [@sebdelsol](https://github.com/sebdelsol/KOReader.patches/blob/main/2-browser-up-folder.lua)
- Hide the last-visited underline. Credits: [@sebdelsol](https://github.com/sebdelsol/KOReader.patches/blob/main/2-browser-hide-underline.lua)
- Replace underscores and restore trailing English articles in displayed names. Credits: [@joshuacant](https://github.com/joshuacant/KOReader.patches/blob/main/2-menutext-overrides.lua)
- Show page numbers in file-browser subtitles. Credits: [@zenixlabs](https://github.com/zenixlabs/koreader-frankenpatches-public/blob/main/2-pageno-in-subtitle.lua)
- Add a configurable Quick Settings menu tab. Credits: [@qewer33](https://github.com/qewer33/koreader-patches/blob/main/2-quick-settings.lua)
- Customize file-browser title-bar information. Credits: [@sebdelsol](https://github.com/sebdelsol/KOReader.patches/blob/main/2-filemanager-titlebar.lua)
- Adjust menu sizing for device DPI. Credits: [@sebdelsol](https://github.com/sebdelsol/KOReader.patches/blob/main/2-menu-size.lua)
- Open a document in incognito mode. Credits: [@Craftwork2720](https://github.com/Craftwork2720/KOReader.patches/blob/main/2-incognito.lua)

## Installation

1. Download the latest VOS release from the [Releases page](https://github.com/SeriousHornet/vos.koplugin/releases).
2. Extract the plugin to KOReader's `plugins` directory.
3. Confirm that the resulting path is `koreader/plugins/vos.koplugin/` and contains `_meta.lua` and `main.lua` directly.
4. Restart KOReader.
5. If necessary, enable **Visual Overhaul Suite (VOS)** in KOReader's plugin manager and restart again.

Open VOS from KOReader's **Tools** menu.

Do not place VOS files in `koreader/patches`, and do not copy the bundled SVG files to `koreader/icons`.

## Configuration

The first VOS menu item is a suite-wide On/Off switch. Turning it off disables VOS effects while retaining all configured values and keeping every settings menu accessible.

Most settings are saved and refreshed immediately. Use **Refresh UI** if a visible view has not rebuilt yet. KOReader may request a restart after changes to:

- UI font
- Quick Settings tab availability
- Automatic menu sizing

VOS stores its configuration in KOReader's settings directory:

```text
koreader/settings/visual_overhaul.lua
```

The exact base path depends on the device and KOReader installation.

Custom navigation-tab icons, percentage-badge, and status icons belong in KOReader's user icons directory as SVG or PNG files. The icon name can be entered with or without its extension.

## Updates

Use **VOS > About > Check for Updates** to compare the installed version with the latest published GitHub release. The checker reports availability and provides option to download and install updates automatically.

To update manually, replace the existing `vos.koplugin` directory with the new release and restart KOReader. Your settings file is stored separately and is preserved.

## Uninstallation

Disable VOS in KOReader's plugin manager, restart KOReader, and remove the `koreader/plugins/vos.koplugin` directory. The separate `settings/visual_overhaul.lua` file may also be removed if you do not want to keep your configuration.

## Compatibility

VOS is developed against KOReader 2026.07 "Sailing Walrus". It relies on KOReader's internal file-browser and Cover Browser structures, so future KOReader releases may require compatibility updates.

Cover effects apply to the mosaic cover grid and may not appear in classic list views or unrelated third-party layouts. Some navigation and Quick Settings actions require the corresponding optional plugin or device capability.

VOS uses process-wide hooks for several integrations. Other patches or plugins that replace the same KOReader methods may conflict even though VOS preserves known named upvalues where possible.

## Troubleshooting

### The VOS menu is missing

- Verify that the directory is named `vos.koplugin` and is not nested inside another extracted folder.
- Enable VOS in KOReader's plugin manager.
- Restart KOReader and check the log for `visualoverhaul` errors.

### Cover changes are not visible

- Confirm that Cover Browser is using mosaic view.
- Use **VOS > Refresh UI**.
- Allow KOReader to fetch and cache book covers before expecting folder-cover fallbacks.

### Restore defaults

Open **VOS > About > Reset to Defaults**. For manual recovery, close KOReader before editing or removing `settings/visual_overhaul.lua`.

## Credits

VOS grew from the author's KOReader user-patch collection. Thanks to [joshuacant](https://github.com/joshuacant), [sebdelsol](https://github.com/sebdelsol), and Reddit user `u/medinauta` for code and structural ideas used in the original patches, and to the KOReader contributors for the platform VOS builds on.
