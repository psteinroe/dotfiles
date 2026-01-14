# Ghostty Keybindings Guide

Custom nvim-like keybindings for ghostty.

## Split Navigation

| Action | Keybinding | Symbol |
|--------|------------|--------|
| Go to left pane | `Ctrl+H` | `⌃H` |
| Go to down pane | `Ctrl+J` | `⌃J` |
| Go to up pane | `Ctrl+K` | `⌃K` |
| Go to right pane | `Ctrl+L` | `⌃L` |

> Uses `performable:` prefix - keys pass through to nvim when it has focus.

## Split Management

| Action | Keybinding | Symbol |
|--------|------------|--------|
| New split right | `Cmd+D` | `⌘D` |
| New split down | `Cmd+Shift+D` | `⌘⇧D` |
| Toggle split zoom | `Cmd+Shift+Enter` | `⌘⇧↩` |
| Equalize splits | `Alt+Shift+=` | `⌥⇧=` |
| Close split | `Cmd+W` | `⌘W` |

## Split Resize

| Action | Keybinding | Symbol |
|--------|------------|--------|
| Resize left | `Cmd+Ctrl+H` | `⌘⌃H` |
| Resize down | `Cmd+Ctrl+J` | `⌘⌃J` |
| Resize up | `Cmd+Ctrl+K` | `⌘⌃K` |
| Resize right | `Cmd+Ctrl+L` | `⌘⌃L` |

## Tab Navigation

| Action | Keybinding | Symbol |
|--------|------------|--------|
| New tab | `Cmd+T` | `⌘T` |
| Previous tab | `Cmd+Shift+[` | `⌘⇧[` |
| Next tab | `Cmd+Shift+]` | `⌘⇧]` |
| Go to tab 1-9 | `Cmd+1` - `Cmd+9` | `⌘1`-`⌘9` |
| Close tab | `Cmd+W` | `⌘W` |

Also: `Ctrl+Tab` (next) / `Ctrl+Shift+Tab` (previous)

## Window

| Action | Keybinding | Symbol |
|--------|------------|--------|
| New window | `Cmd+N` | `⌘N` |
| Toggle fullscreen | `Cmd+Enter` | `⌘↩` |
| Close window | `Cmd+Shift+W` | `⌘⇧W` |
| Quit | `Cmd+Q` | `⌘Q` |

## Clipboard & Selection

| Action | Keybinding | Symbol |
|--------|------------|--------|
| Copy | `Cmd+C` | `⌘C` |
| Paste | `Cmd+V` | `⌘V` |
| Select all | `Cmd+A` | `⌘A` |
| Adjust selection | `Shift+Arrows` | `⇧↑↓←→` |

## Scrolling

| Action | Keybinding | Symbol |
|--------|------------|--------|
| Page up | `Cmd+Page Up` | `⌘PgUp` |
| Page down | `Cmd+Page Down` | `⌘PgDn` |
| Scroll to top | `Cmd+Home` | `⌘Home` |
| Scroll to bottom | `Cmd+End` | `⌘End` |
| Jump to prev prompt | `Cmd+Shift+Up` | `⌘⇧↑` |
| Jump to next prompt | `Cmd+Shift+Down` | `⌘⇧↓` |

## Font

| Action | Keybinding | Symbol |
|--------|------------|--------|
| Increase size | `Cmd+=` | `⌘=` |
| Decrease size | `Cmd+-` | `⌘-` |
| Reset size | `Cmd+0` | `⌘0` |

## Utility

| Action | Keybinding | Symbol |
|--------|------------|--------|
| Clear screen | `Cmd+K` | `⌘K` |
| Open config | `Cmd+,` | `⌘,` |
| Reload config | `Cmd+Shift+,` | `⌘⇧,` |
| Command palette | `Cmd+Shift+P` | `⌘⇧P` |
| Inspector | `Cmd+Alt+I` | `⌘⌥I` |

## Vim Mode (Future)

> Requires `activate_key_table` - not available in ghostty 1.2.x

When available, `Alt+V` will enter vim mode for scrollback navigation with `j/k` scrolling, `gg/G` jump, `/` search, etc.

---

## Comparison with Nvim

| Action | Ghostty | Nvim |
|--------|---------|------|
| Move left | `⌃H` | `<C-h>` |
| Move down | `⌃J` | `<C-j>` |
| Move up | `⌃K` | `<C-k>` |
| Move right | `⌃L` | `<C-l>` |

Split navigation matches nvim exactly for muscle memory consistency.
