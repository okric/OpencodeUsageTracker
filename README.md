# Opencode Dashboard (OpenCode Usage)

A native macOS menu bar app that shows your OpenCode model usage with no Node.js
dependencies. Sits in the menu bar as three compact usage bars per model, with a
full popover menu.

Forked conceptually from the DeepSeekUsageTracker app; same architecture:

- `Sources/App` — `@MainActor ObservableObject` model, app lifecycle, launch-at-login
- `Sources/Core` — scraper + Keychain store + `.env` migration
- `Sources/UI` — status item (the original three-bar view), menu, settings window
- `Tests/` — parser + Keychain unit tests

## How it works

1. Reads your OpenCode session cookie from the macOS **Keychain**
   (`com.opencode.dashboard` / `opencode.cookie`).
2. Fetches your workspace page (`https://opencode.ai/workspace/<wrk_id>/go`)
   with that cookie, every 5 minutes by default and on wake from sleep.
3. Scrapes the `data-slot="usage-item"` markup — a small dependency-free
   parser replaces the old cheerio-based Node script (`index.js`).
4. Shows up to three bars in the status item and a per-model menu.

## Setup

1. Build and run with Xcode (`OpencodeDashboard.xcodeproj`), or:

   ```
   xcodebuild -project OpencodeDashboard.xcodeproj -scheme OpencodeDashboard build
   ```

2. On first launch the app copies `OPENCODE_COOKIE` from this repo's old `.env`
   file into the Keychain if that file still exists. You can then delete `.env`.
   Or paste a fresh cookie in **Settings**:
   copy the `Cookie:` header value your browser sends on `opencode.ai`
   (DevTools → Network → any request → Request Headers).
3. Set the **Workspace URL** in Settings (it contains the `wrk_…` id). It
   defaults to the workspace used by the old Node script.

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
