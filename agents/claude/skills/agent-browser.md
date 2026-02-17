---
name: agent-browser
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
allowed-tools: Bash(pnpx agent-browser:*)
---

# Browser Automation with agent-browser

## Quick start

```bash
pnpx agent-browser open <url>        # Navigate to page
pnpx agent-browser snapshot -i       # Get interactive elements with refs
pnpx agent-browser click @e1         # Click element by ref
pnpx agent-browser fill @e2 "text"   # Fill input by ref
pnpx agent-browser close             # Close browser
```

## Core workflow

1. Navigate: `pnpx agent-browser open <url>`
2. Snapshot: `pnpx agent-browser snapshot -i` (returns elements with refs like `@e1`, `@e2`)
3. Interact using refs from the snapshot
4. Re-snapshot after navigation or significant DOM changes

## Commands

### Navigation
```bash
pnpx agent-browser open <url>      # Navigate to URL
pnpx agent-browser back            # Go back
pnpx agent-browser forward         # Go forward
pnpx agent-browser reload          # Reload page
pnpx agent-browser close           # Close browser
```

### Snapshot (page analysis)
```bash
pnpx agent-browser snapshot            # Full accessibility tree
pnpx agent-browser snapshot -i         # Interactive elements only (recommended)
pnpx agent-browser snapshot -c         # Compact output
pnpx agent-browser snapshot -d 3       # Limit depth to 3
pnpx agent-browser snapshot -s "#main" # Scope to CSS selector
```

### Interactions (use @refs from snapshot)
```bash
pnpx agent-browser click @e1           # Click
pnpx agent-browser dblclick @e1        # Double-click
pnpx agent-browser focus @e1           # Focus element
pnpx agent-browser fill @e2 "text"     # Clear and type
pnpx agent-browser type @e2 "text"     # Type without clearing
pnpx agent-browser press Enter         # Press key
pnpx agent-browser press Control+a     # Key combination
pnpx agent-browser keydown Shift       # Hold key down
pnpx agent-browser keyup Shift         # Release key
pnpx agent-browser hover @e1           # Hover
pnpx agent-browser check @e1           # Check checkbox
pnpx agent-browser uncheck @e1         # Uncheck checkbox
pnpx agent-browser select @e1 "value"  # Select dropdown
pnpx agent-browser scroll down 500     # Scroll page
pnpx agent-browser scrollintoview @e1  # Scroll element into view
pnpx agent-browser drag @e1 @e2        # Drag and drop
pnpx agent-browser upload @e1 file.pdf # Upload files
```

### Get information
```bash
pnpx agent-browser get text @e1        # Get element text
pnpx agent-browser get html @e1        # Get innerHTML
pnpx agent-browser get value @e1       # Get input value
pnpx agent-browser get attr @e1 href   # Get attribute
pnpx agent-browser get title           # Get page title
pnpx agent-browser get url             # Get current URL
pnpx agent-browser get count ".item"   # Count matching elements
pnpx agent-browser get box @e1         # Get bounding box
```

### Check state
```bash
pnpx agent-browser is visible @e1      # Check if visible
pnpx agent-browser is enabled @e1      # Check if enabled
pnpx agent-browser is checked @e1      # Check if checked
```

### Screenshots & PDF
```bash
pnpx agent-browser screenshot          # Screenshot to stdout
pnpx agent-browser screenshot path.png # Save to file
pnpx agent-browser screenshot --full   # Full page
pnpx agent-browser pdf output.pdf      # Save as PDF
```

### Video recording
```bash
pnpx agent-browser record start ./demo.webm    # Start recording (uses current URL + state)
pnpx agent-browser click @e1                   # Perform actions
pnpx agent-browser record stop                 # Stop and save video
pnpx agent-browser record restart ./take2.webm # Stop current + start new recording
```
Recording creates a fresh context but preserves cookies/storage from your session. If no URL is provided, it automatically returns to your current page. For smooth demos, explore first, then start recording.

### Wait
```bash
pnpx agent-browser wait @e1                     # Wait for element
pnpx agent-browser wait 2000                    # Wait milliseconds
pnpx agent-browser wait --text "Success"        # Wait for text
pnpx agent-browser wait --url "**/dashboard"    # Wait for URL pattern
pnpx agent-browser wait --load networkidle      # Wait for network idle
pnpx agent-browser wait --fn "window.ready"     # Wait for JS condition
```

### Mouse control
```bash
pnpx agent-browser mouse move 100 200      # Move mouse
pnpx agent-browser mouse down left         # Press button
pnpx agent-browser mouse up left           # Release button
pnpx agent-browser mouse wheel 100         # Scroll wheel
```

### Semantic locators (alternative to refs)
```bash
pnpx agent-browser find role button click --name "Submit"
pnpx agent-browser find text "Sign In" click
pnpx agent-browser find label "Email" fill "user@test.com"
pnpx agent-browser find first ".item" click
pnpx agent-browser find nth 2 "a" text
```

### Browser settings
```bash
pnpx agent-browser set viewport 1920 1080      # Set viewport size
pnpx agent-browser set device "iPhone 14"      # Emulate device
pnpx agent-browser set geo 37.7749 -122.4194   # Set geolocation
pnpx agent-browser set offline on              # Toggle offline mode
pnpx agent-browser set headers '{"X-Key":"v"}' # Extra HTTP headers
pnpx agent-browser set credentials user pass   # HTTP basic auth
pnpx agent-browser set media dark              # Emulate color scheme
```

### Cookies & Storage
```bash
pnpx agent-browser cookies                     # Get all cookies
pnpx agent-browser cookies set name value      # Set cookie
pnpx agent-browser cookies clear               # Clear cookies
pnpx agent-browser storage local               # Get all localStorage
pnpx agent-browser storage local key           # Get specific key
pnpx agent-browser storage local set k v       # Set value
pnpx agent-browser storage local clear         # Clear all
```

### Network
```bash
pnpx agent-browser network route <url>              # Intercept requests
pnpx agent-browser network route <url> --abort      # Block requests
pnpx agent-browser network route <url> --body '{}'  # Mock response
pnpx agent-browser network unroute [url]            # Remove routes
pnpx agent-browser network requests                 # View tracked requests
pnpx agent-browser network requests --filter api    # Filter requests
```

### Tabs & Windows
```bash
pnpx agent-browser tab                 # List tabs
pnpx agent-browser tab new [url]       # New tab
pnpx agent-browser tab 2               # Switch to tab
pnpx agent-browser tab close           # Close tab
pnpx agent-browser window new          # New window
```

### Frames
```bash
pnpx agent-browser frame "#iframe"     # Switch to iframe
pnpx agent-browser frame main          # Back to main frame
```

### Dialogs
```bash
pnpx agent-browser dialog accept [text]  # Accept dialog
pnpx agent-browser dialog dismiss        # Dismiss dialog
```

### JavaScript
```bash
pnpx agent-browser eval "document.title"   # Run JavaScript
```

## Example: Form submission

```bash
pnpx agent-browser open https://example.com/form
pnpx agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Submit" [ref=e3]

pnpx agent-browser fill @e1 "user@example.com"
pnpx agent-browser fill @e2 "password123"
pnpx agent-browser click @e3
pnpx agent-browser wait --load networkidle
pnpx agent-browser snapshot -i  # Check result
```

## Example: Authentication with saved state

```bash
# Login once
pnpx agent-browser open https://app.example.com/login
pnpx agent-browser snapshot -i
pnpx agent-browser fill @e1 "username"
pnpx agent-browser fill @e2 "password"
pnpx agent-browser click @e3
pnpx agent-browser wait --url "**/dashboard"
pnpx agent-browser state save auth.json

# Later sessions: load saved state
pnpx agent-browser state load auth.json
pnpx agent-browser open https://app.example.com/dashboard
```

## Sessions (parallel browsers)

```bash
pnpx agent-browser --session test1 open site-a.com
pnpx agent-browser --session test2 open site-b.com
pnpx agent-browser session list
```

## JSON output (for parsing)

Add `--json` for machine-readable output:
```bash
pnpx agent-browser snapshot -i --json
pnpx agent-browser get text @e1 --json
```

## Debugging

```bash
pnpx agent-browser open example.com --headed              # Show browser window
pnpx agent-browser console                                # View console messages
pnpx agent-browser errors                                 # View page errors
pnpx agent-browser record start ./debug.webm             # Record from current page
pnpx agent-browser record stop                            # Save recording
pnpx agent-browser --cdp 9222 snapshot                   # Connect via CDP
pnpx agent-browser console --clear                       # Clear console
pnpx agent-browser errors --clear                        # Clear errors
pnpx agent-browser highlight @e1                         # Highlight element
pnpx agent-browser trace start                           # Start recording trace
pnpx agent-browser trace stop trace.zip                  # Stop and save trace
```
