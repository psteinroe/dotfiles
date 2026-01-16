---
name: pnpx agent-browser
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
---

# Browser Automation with pnpx agent-browser

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
pnpx agent-browser snapshot        # Full accessibility tree
pnpx agent-browser snapshot -i     # Interactive elements only (recommended)
pnpx agent-browser snapshot -c     # Compact output
pnpx agent-browser snapshot -d 3   # Limit depth to 3
```

### Interactions (use @refs from snapshot)
```bash
pnpx agent-browser click @e1           # Click
pnpx agent-browser dblclick @e1        # Double-click
pnpx agent-browser fill @e2 "text"     # Clear and type
pnpx agent-browser type @e2 "text"     # Type without clearing
pnpx agent-browser press Enter         # Press key
pnpx agent-browser press Control+a     # Key combination
pnpx agent-browser hover @e1           # Hover
pnpx agent-browser check @e1           # Check checkbox
pnpx agent-browser uncheck @e1         # Uncheck checkbox
pnpx agent-browser select @e1 "value"  # Select dropdown
pnpx agent-browser scroll down 500     # Scroll page
pnpx agent-browser scrollintoview @e1  # Scroll element into view
```

### Get information
```bash
pnpx agent-browser get text @e1        # Get element text
pnpx agent-browser get value @e1       # Get input value
pnpx agent-browser get title           # Get page title
pnpx agent-browser get url             # Get current URL
```

### Screenshots
```bash
pnpx agent-browser screenshot          # Screenshot to stdout
pnpx agent-browser screenshot path.png # Save to file
pnpx agent-browser screenshot --full   # Full page
```

### Wait
```bash
pnpx agent-browser wait @e1                     # Wait for element
pnpx agent-browser wait 2000                    # Wait milliseconds
pnpx agent-browser wait --text "Success"        # Wait for text
pnpx agent-browser wait --load networkidle      # Wait for network idle
```

### Semantic locators (alternative to refs)
```bash
pnpx agent-browser find role button click --name "Submit"
pnpx agent-browser find text "Sign In" click
pnpx agent-browser find label "Email" fill "user@test.com"
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
pnpx agent-browser open example.com --headed  # Show browser window
pnpx agent-browser console                    # View console messages
pnpx agent-browser errors                     # View page errors
```
