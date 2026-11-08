# OpenCode Usage (OpencodeDashboard)

A native macOS menu bar app that shows your OpenCode Go usage with no Node.js
dependencies and no browser cookie. Sits in the menu bar as three compact bars
(Rolling / Weekly / Monthly usage windows), with a full menu.

Architecture (shared with DeepSeekUsageTracker):

- `Sources/App` — `@MainActor ObservableObject` model, app lifecycle, launch-at-login
- `Sources/Core` — CLI credential store + console usage API client
- `Sources/UI` — status item (three-bar view), menu, settings window
- `Tests/` — unit tests

## How it works

1. Reads the device-linked workspace credential from the **OpenCode CLI**
   (`~/.local/share/opencode/opencode.db`, `auth.json` fallback). Secrets are
   never copied — the app reads the current token in memory on every refresh,
   so CLI-side renewals are picked up automatically.
2. Calls the same console endpoints the CLI uses:
   - `GET {console-origin}/zen/go/v1/usage` → Rolling/Weekly/Monthly windows
     (percent + reset time) authenticated with `Authorization: Bearer` +
     `x-opencode-org-id`.
   - `GET {console}/api/policies/current-budgets` → spend budgets
     (authenticated with `Authorization: Bearer` + `x-org-id`).
3. Shows the three windows as bars in the status item and a per-window menu
   with reset times, budgets, and the last-updated stamp.

Note: the plain `sk-…` API keys in the CLI's `auth.json` are rejected by these
endpoints — a device link (`opencode` → `/connect`) is required.

## Setup

1. Install the [OpenCode CLI](https://opencode.ai) and link the device
   (run `opencode`, then use `/connect`).
2. Build and run with Xcode, or:

   ```
   xcodebuild -project OpencodeDashboard.xcodeproj -scheme OpencodeDashboard build
   ```

3. If the CLI has several workspaces, pick one in Settings.

## Tests

```
xcodebuild -project OpencodeDashboard.xcodeproj -scheme OpencodeDashboard test
```

## Icon

`Scripts/make-icon.swift` renders the app icon (three usage bars on a dark
tile) straight into the asset catalog:

```
swift Scripts/make-icon.swift Sources/Icon.xcassets/AppIcon.appiconset
```
