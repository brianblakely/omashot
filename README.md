# Omashot

Omashot is a screenshot and screen-recording overlay inspired by macOS and Spectacle. It saves screenshots to the configured XDG directory: `Pictures` by default, and recordings to `Videos` by default. Completed recordings open automatically in Omacut.

## Install

```bash
omarchy plugin add https://github.com/brianblakely/omashot.git
```

## Usage

* Press `Space` to capture the screen.
* Press `Enter` to capture the focused window.
* Press `Escape` during a recording to stop and save it.
* Use the arrow keys or `HJKL` to move a region by one pixel.
* Hold `Alt` while moving or resizing to use ten-pixel increments.
* Hold `Shift` to grow the addressed edge.
* Hold `Shift+Ctrl` to shrink from the edge opposite the pressed direction.
* With the mouse, click the bar to select the screen, click a window to select it, or drag a region.

## Shortcuts

```lua
hl.unbind("PRINT")
o.bind("PRINT", "Omashot", "omarchy-shell b.omashot show")
```

## All Commands

* omarchy-shell b.omashot show
* omarchy-shell b.omashot captureScreen
* omarchy-shell b.omashot captureWindow
* omarchy-shell b.omashot captureToFile
* omarchy-shell b.omashot captureToClipboard
* omarchy-shell b.omashot record
* omarchy-shell b.omashot stopRecording

## Update

```bash
omarchy plugin update b.omashot
```

## Uninstall

```bash
omarchy plugin remove b.omashot
```
