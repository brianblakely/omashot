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
o.bind("SUPER + SHIFT + F3", "Omashot capture screen", "omarchy-shell b.omashot captureScreen")
o.bind("SUPER + SHIFT + CTRL + F3", "Omashot capture window", "omarchy-shell b.omashot captureWindow")
o.bind("SUPER + SHIFT + F4", "Omashot capture to file", "omarchy-shell b.omashot captureToFile")
o.bind("SUPER + SHIFT + CTRL + F4", "Omashot capture to clipboard", "omarchy-shell b.omashot captureToClipboard")
o.bind("SUPER + SHIFT + F5", "Omashot", "omarchy-shell b.omashot show")
o.bind("SUPER + SHIFT + F6", "Omashot record", "omarchy-shell b.omashot record")
o.bind("SUPER + SHIFT + CTRL + F6", "Omashot stop recording", "omarchy-shell b.omashot stopRecording")
```

## Update

```bash
omarchy plugin update b.omashot
```
