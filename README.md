# Omashot

Omashot is a screenshot and screen-recording overlay inspired by macOS and Spectacle. It saves screenshots to the configured XDG directory: `Pictures` by default, and recordings to `Videos` by default.

## Annotations and Editing

Omashot uses Omarchy's built-in tools, which do what they do best. To annotate a screenshot, first select `Save: Editor` from the toolbar. All completed screen recordings open automatically in Omacut. If you have a workflow that involves Pinta or GIMP, you can change the editing tools used in `~/.config/omarchy/shell.json`.

## Install

```bash
omarchy plugin add https://github.com/brianblakely/omashot.git
```

## Usage

### Use Your Mouse

* Click the top edge of the screen to capture the whole screen.
* Click a window to capture it.
* Click and drag to create a capture region. Then press `Enter`.

### Quick Capture Hotkeys

* Press `Space` to capture the whole screen at any time.
* Press `Enter` to capture a highlighted window or a region.
* Press `Escape` to end a screen recording.

### Tweak Region Sizing and Position with the Keyboard

* Use the arrow keys or `HJKL` to move the region by one pixel.
* Hold `Shift` and a direction to grow the region.
* Hold `Shift+Ctrl` and a direction to shrink the region.
* Hold `Alt` while moving or resizing to use ten-pixel increments.

## Shortcuts

```lua
hl.unbind("PRINT")
o.bind("PRINT", "Omashot", "omarchy-shell b.omashot show")
```

## All Commands

* `omarchy-shell b.omashot show`
* `omarchy-shell b.omashot captureScreen`
* `omarchy-shell b.omashot captureWindow`
* `omarchy-shell b.omashot captureToFile`
* `omarchy-shell b.omashot captureToClipboard`
* `omarchy-shell b.omashot record`
* `omarchy-shell b.omashot stopRecording`

## Update

```bash
omarchy plugin update b.omashot
```

## Uninstall

```bash
omarchy plugin remove b.omashot
```
