# Omasnap

Omasnap is a screenshot and screen-recording overlay inspired by macOS and Spectacle. It saves screenshots to the configured XDG directory: `Pictures` by default, and recordings to `Videos` by default. Completed recordings open automatically in Omacut.

## Install

```bash
omarchy plugin add https://github.com/brianblakely/omasnap.git
```

## Usage

* Press `Space` to capture the screen.
* Press `Enter` to capture the focused window.
* Use the arrow keys or `HJKL` to move a region by one pixel.
* Hold `Shift` to grow the addressed edge.
* Hold `Shift+Ctrl` to shrink the addressed edge.
* With the mouse, click the bar to select the screen, click a window to select it, or drag a region.

## Shortcuts

```lua
hl.unbind("PRINT")
o.bind("PRINT", "Omasnap", "omarchy-shell b.omasnap show")
o.bind("SUPER + SHIFT + F3", "Omasnap capture screen", "omarchy-shell b.omasnap captureScreen")
o.bind("SUPER + SHIFT + CTRL + F3", "Omasnap capture window", "omarchy-shell b.omasnap captureWindow")
o.bind("SUPER + SHIFT + F4", "Omasnap capture to file", "omarchy-shell b.omasnap captureToFile")
o.bind("SUPER + SHIFT + CTRL + F4", "Omasnap capture to clipboard", "omarchy-shell b.omasnap captureToClipboard")
o.bind("SUPER + SHIFT + F5", "Omasnap", "omarchy-shell b.omasnap show")
o.bind("SUPER + SHIFT + F6", "Omasnap record", "omarchy-shell b.omasnap record")
o.bind("SUPER + SHIFT + CTRL + F6", "Omasnap stop recording", "omarchy-shell b.omasnap stopRecording")
```

## Update

```bash
omarchy plugin update b.omasnap
```
