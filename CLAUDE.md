---
owner: sohaib
updated: 2026-06-04
---

# Mushaf — native macOS Quran reader

Native **SwiftUI** app (chosen over Tauri/Electron). Displays the real **Mushaf al-Madinah**
604-page scans as a right-to-left two-page spread. Swift 6 toolchain, Swift 5 language mode
(set in `Package.swift` — keep it; Swift 6 strict-concurrency churn isn't worth it here).

## App icon
- Source of truth is `design/icon.html` (inline SVG; green Mushaf cover + gold rub-el-hizb star + open book).
- Regenerate: extract the `<svg>` to `design/icon.svg`, render with `qlmanage -t -s 1024 -o design design/icon.svg` (**not** a browser screenshot — that loses alpha and Finder shows a white tile), then `sips`-resize into an `AppIcon.iconset` and `iconutil -c icns` → `design/AppIcon.icns`.
- `build_app.sh` copies `design/AppIcon.icns` into the bundle and sets `CFBundleIconFile`.

## Build & run
- `./build_app.sh` → builds release + wraps into `Mushaf.app` (ad-hoc signed). Then `open Mushaf.app`.
- `swift build` for a quick compile check; `swift run` launches a bare window (no dock identity — use the .app for fullscreen testing).
- This is an SPM executable, not an `.xcodeproj`. If you need Xcode features (asset catalog, notarized release), generate a project — don't hand-edit pbxproj.

## Page images
- Source of truth: `https://raw.githubusercontent.com/sufone/medina-mushaf/master/png-d150/<n>.png` (n = 1..604, ~1.8 MB each).
- `PageStore` loads in this order: bundled `Pages/<n>.png` → on-disk cache (`~/Library/Application Support/Mushaf/pages/`) → network download (then cached). So the app runs immediately and goes offline as pages are visited.
- **For a true offline build**: drop a `Pages/` resource folder of all 604 (downscale first — full d150 set is ~1.1 GB; target ~150–250 MB) and add it to the target resources. `PageStore.bundledURL` already looks for it.

## Quran metadata
- `QuranData.swift` is **auto-generated** — do not hand-edit. Surah list from quran.com `/chapters`; hizb starts from `/verses/by_hizb` (60); rub-al-hizb quarter starts from `/verses/by_rub_el_hizb` (240); juz starts are the standard fixed table.
  - Gotcha when refetching: quran.com ignores `per_page=1` and its JSON has a **duplicate `page_number` key**. Parse the **first** `page_number` occurrence (`grep -o … | head -1`), never a greedy `sed` (grabs the last verse's page → wrong).
- Spread rule: pages pair as **(1,2), (3,4), (5,6)…** — odd (lower) page on the **right**, even page on the **left** (RTL). No page shows alone. See `Reader.spread`. `next`/`prev` step the spread by 2 off `spread.right`.

## Conventions
- All colors come from `Palette` (light/dark) in `Theme.swift`. Never hardcode a `Color(hex:)` in a view — add it to `Palette`.
- Navigation goes through `Reader` (`go`/`next`/`prev`). The **bottom slider is always a flat page scrubber (1…604)** — do not make it unit-based. Surah/Juz/Hizb jumping lives in the **sidebar** (`Reader.navMode`); Hizb mode lists all 240 quarters (¼/½/¾ marks via `rubStartPages`). A 4th nav tab **★** (`NavUnit.bookmarks`) lists starred pages (sorted), with an empty state.
- **Persistence (UserDefaults, domain `com.sohaib.mushaf`):** `lastPage` is written in `Reader.go` and restored in the `currentPage` initializer (opens where you left off). `bookmarks` is a `[Int]` written on every toggle. The star button (bottom bar + immersive overlay) toggles the current page.
- `PageView` loads via `PageStore.load`, which **coalesces concurrent loads of the same page** (one shared `Task`) so the visible page never loses a race with prefetch and goes blank. `PageView.task` also retries a few times so a transient network miss self-heals. Don't reintroduce a nil-on-in-flight guard.
- No page-turn animation (removed by request). If re-adding, keep it optional.
- Keyboard: ← = forward (RTL), → = back, space = forward, `f` = fullscreen. Fullscreen sets `Reader.immersive`, which hides all chrome; controls re-reveal on mouse move.
- **Scroll wheel pages** through the Mushaf (down = forward). Local `.scrollWheel` `NSEvent` monitor in `ContentView.installScrollMonitor` → `Reader.handleScroll`. **No time-based rate limiting** (removed by request): mouse wheel = one notch → one spread instantly; trackpad (precise deltas) accumulates and steps proportionally to swipe distance. Scrolls over the left 298pt (sidebar) pass through so the list scrolls instead.
