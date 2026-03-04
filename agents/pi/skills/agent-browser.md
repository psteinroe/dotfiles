---
name: agent-browser
description: Browser automation CLI for AI agents. Use when the user needs to interact with websites, including navigating pages, filling forms, clicking buttons, taking screenshots, extracting data, testing web apps, or automating any browser task. Triggers include requests to "open a website", "fill out a form", "click a button", "take a screenshot", "scrape data from a page", "test this web app", "login to a site", "automate browser actions", or any task requiring programmatic web interaction.
allowed-tools: Bash(pnpx agent-browser:*)
---

# Browser Automation with agent-browser

## Core Workflow

Every browser automation follows this pattern:

1. **Navigate**: `pnpx agent-browser open <url>`
2. **Snapshot**: `pnpx agent-browser snapshot -i` (get element refs like `@e1`, `@e2`)
3. **Interact**: Use refs to click, fill, select
4. **Re-snapshot**: After navigation or DOM changes, get fresh refs

```bash
pnpx agent-browser open https://example.com/form
pnpx agent-browser snapshot -i
# Output: @e1 [input type="email"], @e2 [input type="password"], @e3 [button] "Submit"

pnpx agent-browser fill @e1 "user@example.com"
pnpx agent-browser fill @e2 "password123"
pnpx agent-browser click @e3
pnpx agent-browser wait --load networkidle
pnpx agent-browser snapshot -i  # Check result
```

## Command Chaining

Commands can be chained with `&&` in a single shell invocation. The browser persists between commands via a background daemon, so chaining is safe and more efficient than separate calls.

```bash
# Chain open + wait + snapshot in one call
pnpx agent-browser open https://example.com && pnpx agent-browser wait --load networkidle && pnpx agent-browser snapshot -i

# Chain multiple interactions
pnpx agent-browser fill @e1 "user@example.com" && pnpx agent-browser fill @e2 "password123" && pnpx agent-browser click @e3

# Navigate and capture
pnpx agent-browser open https://example.com && pnpx agent-browser wait --load networkidle && pnpx agent-browser screenshot page.png
```

**When to chain:** Use `&&` when you don't need to read the output of an intermediate command before proceeding (e.g., open + wait + screenshot). Run commands separately when you need to parse the output first (e.g., snapshot to discover refs, then interact using those refs).

## Essential Commands

```bash
# Navigation
pnpx agent-browser open <url>              # Navigate (aliases: goto, navigate)
pnpx agent-browser close                   # Close browser

# Snapshot
pnpx agent-browser snapshot -i             # Interactive elements with refs (recommended)
pnpx agent-browser snapshot -i -C          # Include cursor-interactive elements (divs with onclick, cursor:pointer)
pnpx agent-browser snapshot -s "#selector" # Scope to CSS selector

# Interaction (use @refs from snapshot)
pnpx agent-browser click @e1               # Click element
pnpx agent-browser click @e1 --new-tab     # Click and open in new tab
pnpx agent-browser fill @e2 "text"         # Clear and type text
pnpx agent-browser type @e2 "text"         # Type without clearing
pnpx agent-browser select @e1 "option"     # Select dropdown option
pnpx agent-browser check @e1               # Check checkbox
pnpx agent-browser press Enter             # Press key
pnpx agent-browser scroll down 500         # Scroll page

# Get information
pnpx agent-browser get text @e1            # Get element text
pnpx agent-browser get url                 # Get current URL
pnpx agent-browser get title               # Get page title

# Wait
pnpx agent-browser wait @e1                # Wait for element
pnpx agent-browser wait --load networkidle # Wait for network idle
pnpx agent-browser wait --url "**/page"    # Wait for URL pattern
pnpx agent-browser wait 2000               # Wait milliseconds

# Capture
pnpx agent-browser screenshot              # Screenshot to temp dir
pnpx agent-browser screenshot --full       # Full page screenshot
pnpx agent-browser screenshot --annotate   # Annotated screenshot with numbered element labels
pnpx agent-browser pdf output.pdf          # Save as PDF

# Diff (compare page states)
pnpx agent-browser diff snapshot                          # Compare current vs last snapshot
pnpx agent-browser diff snapshot --baseline before.txt    # Compare current vs saved file
pnpx agent-browser diff screenshot --baseline before.png  # Visual pixel diff
pnpx agent-browser diff url <url1> <url2>                 # Compare two pages
pnpx agent-browser diff url <url1> <url2> --wait-until networkidle  # Custom wait strategy
pnpx agent-browser diff url <url1> <url2> --selector "#main"  # Scope to element
```

## Common Patterns

### Form Submission

```bash
pnpx agent-browser open https://example.com/signup
pnpx agent-browser snapshot -i
pnpx agent-browser fill @e1 "Jane Doe"
pnpx agent-browser fill @e2 "jane@example.com"
pnpx agent-browser select @e3 "California"
pnpx agent-browser check @e4
pnpx agent-browser click @e5
pnpx agent-browser wait --load networkidle
```

### Authentication with State Persistence

```bash
# Login once and save state
pnpx agent-browser open https://app.example.com/login
pnpx agent-browser snapshot -i
pnpx agent-browser fill @e1 "$USERNAME"
pnpx agent-browser fill @e2 "$PASSWORD"
pnpx agent-browser click @e3
pnpx agent-browser wait --url "**/dashboard"
pnpx agent-browser state save auth.json

# Reuse in future sessions
pnpx agent-browser state load auth.json
pnpx agent-browser open https://app.example.com/dashboard
```

### Session Persistence

```bash
# Auto-save/restore cookies and localStorage across browser restarts
pnpx agent-browser --session-name myapp open https://app.example.com/login
# ... login flow ...
pnpx agent-browser close  # State auto-saved to ~/.agent-browser/sessions/

# Next time, state is auto-loaded
pnpx agent-browser --session-name myapp open https://app.example.com/dashboard

# Encrypt state at rest
export AGENT_BROWSER_ENCRYPTION_KEY=$(openssl rand -hex 32)
pnpx agent-browser --session-name secure open https://app.example.com

# Manage saved states
pnpx agent-browser state list
pnpx agent-browser state show myapp-default.json
pnpx agent-browser state clear myapp
pnpx agent-browser state clean --older-than 7
```

### Data Extraction

```bash
pnpx agent-browser open https://example.com/products
pnpx agent-browser snapshot -i
pnpx agent-browser get text @e5           # Get specific element text
pnpx agent-browser get text body > page.txt  # Get all page text

# JSON output for parsing
pnpx agent-browser snapshot -i --json
pnpx agent-browser get text @e1 --json
```

### Parallel Sessions

```bash
pnpx agent-browser --session site1 open https://site-a.com
pnpx agent-browser --session site2 open https://site-b.com

pnpx agent-browser --session site1 snapshot -i
pnpx agent-browser --session site2 snapshot -i

pnpx agent-browser session list
```

### Connect to Existing Chrome

```bash
# Auto-discover running Chrome with remote debugging enabled
pnpx agent-browser --auto-connect open https://example.com
pnpx agent-browser --auto-connect snapshot

# Or with explicit CDP port
pnpx agent-browser --cdp 9222 snapshot
```

### Visual Browser (Debugging)

```bash
pnpx agent-browser --headed open https://example.com
pnpx agent-browser highlight @e1          # Highlight element
pnpx agent-browser record start demo.webm # Record session
pnpx agent-browser profiler start         # Start Chrome DevTools profiling
pnpx agent-browser profiler stop trace.json # Stop and save profile (path optional)
```

### Local Files (PDFs, HTML)

```bash
# Open local files with file:// URLs
pnpx agent-browser --allow-file-access open file:///path/to/document.pdf
pnpx agent-browser --allow-file-access open file:///path/to/page.html
pnpx agent-browser screenshot output.png
```

### iOS Simulator (Mobile Safari)

```bash
# List available iOS simulators
pnpx agent-browser device list

# Launch Safari on a specific device
pnpx agent-browser -p ios --device "iPhone 16 Pro" open https://example.com

# Same workflow as desktop - snapshot, interact, re-snapshot
pnpx agent-browser -p ios snapshot -i
pnpx agent-browser -p ios tap @e1          # Tap (alias for click)
pnpx agent-browser -p ios fill @e2 "text"
pnpx agent-browser -p ios swipe up         # Mobile-specific gesture

# Take screenshot
pnpx agent-browser -p ios screenshot mobile.png

# Close session (shuts down simulator)
pnpx agent-browser -p ios close
```

**Requirements:** macOS with Xcode, Appium (`npm install -g appium && appium driver install xcuitest`)

**Real devices:** Works with physical iOS devices if pre-configured. Use `--device "<UDID>"` where UDID is from `xcrun xctrace list devices`.

## Diffing (Verifying Changes)

Use `diff snapshot` after performing an action to verify it had the intended effect. This compares the current accessibility tree against the last snapshot taken in the session.

```bash
# Typical workflow: snapshot -> action -> diff
pnpx agent-browser snapshot -i          # Take baseline snapshot
pnpx agent-browser click @e2            # Perform action
pnpx agent-browser diff snapshot        # See what changed (auto-compares to last snapshot)
```

For visual regression testing or monitoring:

```bash
# Save a baseline screenshot, then compare later
pnpx agent-browser screenshot baseline.png
# ... time passes or changes are made ...
pnpx agent-browser diff screenshot --baseline baseline.png

# Compare staging vs production
pnpx agent-browser diff url https://staging.example.com https://prod.example.com --screenshot
```

`diff snapshot` output uses `+` for additions and `-` for removals, similar to git diff. `diff screenshot` produces a diff image with changed pixels highlighted in red, plus a mismatch percentage.

## Timeouts and Slow Pages

The default Playwright timeout is 60 seconds for local browsers. For slow websites or large pages, use explicit waits instead of relying on the default timeout:

```bash
# Wait for network activity to settle (best for slow pages)
pnpx agent-browser wait --load networkidle

# Wait for a specific element to appear
pnpx agent-browser wait "#content"
pnpx agent-browser wait @e1

# Wait for a specific URL pattern (useful after redirects)
pnpx agent-browser wait --url "**/dashboard"

# Wait for a JavaScript condition
pnpx agent-browser wait --fn "document.readyState === 'complete'"

# Wait a fixed duration (milliseconds) as a last resort
pnpx agent-browser wait 5000
```

When dealing with consistently slow websites, use `wait --load networkidle` after `open` to ensure the page is fully loaded before taking a snapshot. If a specific element is slow to render, wait for it directly with `wait <selector>` or `wait @ref`.

## Session Management and Cleanup

When running multiple agents or automations concurrently, always use named sessions to avoid conflicts:

```bash
# Each agent gets its own isolated session
pnpx agent-browser --session agent1 open site-a.com
pnpx agent-browser --session agent2 open site-b.com

# Check active sessions
pnpx agent-browser session list
```

Always close your browser session when done to avoid leaked processes:

```bash
pnpx agent-browser close                    # Close default session
pnpx agent-browser --session agent1 close   # Close specific session
```

If a previous session was not closed properly, the daemon may still be running. Use `pnpx agent-browser close` to clean it up before starting new work.

## Ref Lifecycle (Important)

Refs (`@e1`, `@e2`, etc.) are invalidated when the page changes. Always re-snapshot after:

- Clicking links or buttons that navigate
- Form submissions
- Dynamic content loading (dropdowns, modals)

```bash
pnpx agent-browser click @e5              # Navigates to new page
pnpx agent-browser snapshot -i            # MUST re-snapshot
pnpx agent-browser click @e1              # Use new refs
```

## Annotated Screenshots (Vision Mode)

Use `--annotate` to take a screenshot with numbered labels overlaid on interactive elements. Each label `[N]` maps to ref `@eN`. This also caches refs, so you can interact with elements immediately without a separate snapshot.

```bash
pnpx agent-browser screenshot --annotate
# Output includes the image path and a legend:
#   [1] @e1 button "Submit"
#   [2] @e2 link "Home"
#   [3] @e3 textbox "Email"
pnpx agent-browser click @e2              # Click using ref from annotated screenshot
```

Use annotated screenshots when:
- The page has unlabeled icon buttons or visual-only elements
- You need to verify visual layout or styling
- Canvas or chart elements are present (invisible to text snapshots)
- You need spatial reasoning about element positions

## Semantic Locators (Alternative to Refs)

When refs are unavailable or unreliable, use semantic locators:

```bash
pnpx agent-browser find text "Sign In" click
pnpx agent-browser find label "Email" fill "user@test.com"
pnpx agent-browser find role button click --name "Submit"
pnpx agent-browser find placeholder "Search" type "query"
pnpx agent-browser find testid "submit-btn" click
```

## JavaScript Evaluation (eval)

Use `eval` to run JavaScript in the browser context. **Shell quoting can corrupt complex expressions** -- use `--stdin` or `-b` to avoid issues.

```bash
# Simple expressions work with regular quoting
pnpx agent-browser eval 'document.title'
pnpx agent-browser eval 'document.querySelectorAll("img").length'

# Complex JS: use --stdin with heredoc (RECOMMENDED)
pnpx agent-browser eval --stdin <<'EVALEOF'
JSON.stringify(
  Array.from(document.querySelectorAll("img"))
    .filter(i => !i.alt)
    .map(i => ({ src: i.src.split("/").pop(), width: i.width }))
)
EVALEOF

# Alternative: base64 encoding (avoids all shell escaping issues)
pnpx agent-browser eval -b "$(echo -n 'Array.from(document.querySelectorAll("a")).map(a => a.href)' | base64)"
```

**Why this matters:** When the shell processes your command, inner double quotes, `!` characters (history expansion), backticks, and `$()` can all corrupt the JavaScript before it reaches agent-browser. The `--stdin` and `-b` flags bypass shell interpretation entirely.

**Rules of thumb:**
- Single-line, no nested quotes -> regular `eval 'expression'` with single quotes is fine
- Nested quotes, arrow functions, template literals, or multiline -> use `eval --stdin <<'EVALEOF'`
- Programmatic/generated scripts -> use `eval -b` with base64

## Configuration File

Create `agent-browser.json` in the project root for persistent settings:

```json
{
  "headed": true,
  "proxy": "http://localhost:8080",
  "profile": "./browser-data"
}
```

Priority (lowest to highest): `~/.agent-browser/config.json` < `./agent-browser.json` < env vars < CLI flags. Use `--config <path>` or `AGENT_BROWSER_CONFIG` env var for a custom config file (exits with error if missing/invalid). All CLI options map to camelCase keys (e.g., `--executable-path` -> `"executablePath"`). Boolean flags accept `true`/`false` values (e.g., `--headed false` overrides config). Extensions from user and project configs are merged, not replaced.

## Deep-Dive Documentation

| Reference | When to Use |
|-----------|-------------|
| [references/commands.md](references/commands.md) | Full command reference with all options |
| [references/snapshot-refs.md](references/snapshot-refs.md) | Ref lifecycle, invalidation rules, troubleshooting |
| [references/session-management.md](references/session-management.md) | Parallel sessions, state persistence, concurrent scraping |
| [references/authentication.md](references/authentication.md) | Login flows, OAuth, 2FA handling, state reuse |
| [references/video-recording.md](references/video-recording.md) | Recording workflows for debugging and documentation |
| [references/profiling.md](references/profiling.md) | Chrome DevTools profiling for performance analysis |
| [references/proxy-support.md](references/proxy-support.md) | Proxy configuration, geo-testing, rotating proxies |

## Ready-to-Use Templates

| Template | Description |
|----------|-------------|
| [templates/form-automation.sh](templates/form-automation.sh) | Form filling with validation |
| [templates/authenticated-session.sh](templates/authenticated-session.sh) | Login once, reuse state |
| [templates/capture-workflow.sh](templates/capture-workflow.sh) | Content extraction with screenshots |

```bash
./templates/form-automation.sh https://example.com/form
./templates/authenticated-session.sh https://app.example.com/login
./templates/capture-workflow.sh https://example.com ./output
```
