# Omashot

Omashot is a screenshot and screen-recording overlay, inspired by macOS and Spectacle.

## Annotations and Editing

Omashot uses Omarchy's built-in tools, which do what they do best. To annotate a screenshot, first select `Save: Editor` from the toolbar. If you have a workflow that involves Pinta, GIMP, et al, you can set `editorCommand` in `~/.config/omarchy/shell.json`.

All completed screen recordings open automatically in Omacut.

![Omashot UI](preview.png)
![Video trimming](preview2.png)
![Screenshot annotation](preview3.png)

## Install

```bash
omarchy plugin add https://github.com/brianblakely/omashot.git
```

## Usage

### Use Your Mouse

* Click the top edge of the screen to capture the whole screen.
* Click a window to capture it.
* Click and drag to create a capture region. Then press `Enter`.

### Measure a Region

Turn on `Measure` in the toolbar to use cursor crosshairs and see live pixel dimensions. The crosshairs become the pointer over the capture canvas. After drawing a region, you can constrain it to `1:1`, `16:9`, `16:10`, `21:9`, or `4:3`, show capped measurement lines from the region to the detected subject, or use `Auto-fit` to shrink the region to that subject.

### Quick Capture Hotkeys

* Press `Space` to capture the whole screen at any time.
* Press `Enter` to capture a highlighted window or a region.
* Press `Escape` to end a screen recording. When Keystroke Display is enabled, hold `Escape` for two seconds.

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
* `omarchy-shell b.omashot keystrokes true`
* `omarchy-shell b.omashot keystrokes false`

## Update

```bash
omarchy plugin update b.omashot
```

## Uninstall

```bash
omarchy plugin remove b.omashot
```
