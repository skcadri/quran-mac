---
owner: sohaib
updated: 2026-06-18
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
- Single source: `https://raw.githubusercontent.com/sufone/medina-mushaf/master/png-d150/<n>.png` (n = 1..604, ~1.8 MB each, **1240×1754**). The beautiful scans — the app is, and stays, these scans. Translation/memorization draw *on top* of them; we never swap the image.
- `PageStore` loads in this order: bundled `Pages/<n>.png` → on-disk cache (`~/Library/Application Support/Mushaf/pages/`) → network download (then cached). So the app runs immediately and goes offline as pages are visited.
- **For a true offline build**: drop a `Pages/` resource folder of all 604 (downscale first — full d150 set is ~1.1 GB; target ~150–250 MB) and add it to the target resources. `PageStore.bundledURL` already looks for it.

## Ayah overlays — translation & memorization (both on the scans)
Both features key off bundled **scan-aligned ayah boxes** (`MushafData`). `PageView` aspect-fits the 1240×1754 scan (`pageAspect`/`fittedRect`) and maps the normalized rects onto it.
- **Translation mode** — top-bar **character.bubble** button → `Reader.toggleTranslate()`, persisted as `translateMode`. Hover an ayah: `.onContinuousHover` → `MushafData.ayah(onPage:at:)` → highlight its per-line gold rects; the translation shows in a **tooltip bubble beside the ayah** (rendered in `ReaderView`, offset toward the opposite page, tail pointing back, scaled to the line height). The scan is untouched; off = original app.
  - The bubble is **interactive**: a 0.2s grace delay (`Reader.setHover`/`scheduleClearHover`/`cancelClearHover`) lets you mouse onto it; its text is `.textSelection(.enabled)`; the header has **Google** (`magnifyingglass`) and **Claude** (`sparkles`) buttons that `NSWorkspace.open` a search / `claude.ai/new?q=` prompt for that ayah (reference only). Hover state lives on `Reader` (`AyahHover`, positioned in the named `"spread"` coordinate space) so it's correct in windowed/fullscreen/sidebar layouts.
- **Memorization mode** — top-bar **eye.slash** button → `Reader.toggleMemorize()` (`memorizeMode`, not persisted — it's a per-session study tool). Each ayah's text is covered with opaque `Palette.pageCover`; **click an ayah to reveal/re-hide** it (`Reader.toggleReveal`, tracked in `Reader.revealed`). Leaving the mode clears reveals.
- **Data is bundled, generated, do-not-hand-edit** (`Sources/Mushaf/Resources/`, read via `Bundle.module`):
  - `boxes.json` — `{ "<page>": [ {s,a,r:[[x,y,w,h],…]} ] }`, rects **normalized 0…1** in the **scan** (1240×1754) space, one rect per line an ayah occupies. **Pages 1–2 are intentionally absent** (Al-Fatihah's decorative oval defeats the line-calibration; overlays simply don't activate there).
  - `translations.json` — `{ "<surah>:<ayah>": "English" }`, Saheeh International (via quran-json / Tanzil). Non-commercial; credit Tanzil/QUL if distributing.
- **How the boxes are generated** (one-time, offline; not in the app): a **from-scratch CV pipeline on the sufone scans themselves** — NOT mapped from any external glyph database. (Quran.com's `ayahinfo_1260.db` was tried and abandoned: it's a *different edition* with different line breaks — e.g. it puts al-Baqarah 12 on its own line while these scans wrap it — so its geometry never matches. Don't reach for it again.) The pipeline:
  1. **Ayah medallions** (which mark exactly where each ayah ends, in *this* edition) found by **multi-scale template matching** (`cv2.matchTemplate`, TM_CCOEFF_NORMED, scales 0.8–1.2) of one medallion template against the page; the medallion's ornate ring scores far above round Arabic letters. Take exactly **N** strongest, where N = ayahs ending on the page (from page→ayah metadata, standardized at the page level).
  2. **Text lines** detected by horizontal ink projection, then **tiny header/footer bands dropped and merged double-bands split** at their interior minimum (the mushaf is 15 lines; bands must end up ~one line tall or rects merge across lines).
  3. On **surah-start pages**, drop the ornamental **header band** (high ink-density, ~0.14) and **basmala band** (low density, ~0.05) so they aren't swallowed into the first ayah's box.
  4. Each ayah's region = the text flowing right-to-left/top-to-bottom **between consecutive medallions**, as per-line rects, **clamped to the per-parity text block** (odd `x∈[67,1044]`, even `x∈[195,1172]` — odd/even differ by the gutter margin) so nothing spills into the decorative border.
  - Validation: every page's medallion count is checked against its expected ayah count. Markers are numbered by matching reading-order to the page's ordered `(surah,ayah)` list (handles multi-surah pages like 604).
- Adding resources means `Bundle.module`; `build_app.sh` copies the SPM `Mushaf_Mushaf.bundle` into `Contents/Resources` so the packaged `.app` finds it.

## Quran metadata
- `QuranData.swift` is **auto-generated** — do not hand-edit. Surah list from quran.com `/chapters`; hizb starts from `/verses/by_hizb` (60); rub-al-hizb quarter starts from `/verses/by_rub_el_hizb` (240); juz starts are the standard fixed table.
  - Gotcha when refetching: quran.com ignores `per_page=1` and its JSON has a **duplicate `page_number` key**. Parse the **first** `page_number` occurrence (`grep -o … | head -1`), never a greedy `sed` (grabs the last verse's page → wrong).
- Spread rule: pages pair as **(1,2), (3,4), (5,6)…** — odd (lower) page on the **right**, even page on the **left** (RTL). No page shows alone. See `Reader.spread`. `next`/`prev` step the spread by 2 off `spread.right`.

## Conventions
- All colors come from `Palette` (light/dark) in `Theme.swift`. Never hardcode a `Color(hex:)` in a view — add it to `Palette`.
- Navigation goes through `Reader` (`go`/`next`/`prev`). The **bottom slider is always a flat page scrubber (1…604)** — do not make it unit-based. Surah/Juz/Hizb jumping lives in the **sidebar** (`Reader.navMode`); Hizb mode lists all 240 quarters (¼/½/¾ marks via `rubStartPages`). A 4th nav tab **★** (`NavUnit.bookmarks`) lists starred pages (sorted), with an empty state.
- **Persistence (UserDefaults, domain `com.sohaib.mushaf`):** `lastPage` is written in `Reader.go` and restored in the `currentPage` initializer (opens where you left off). `bookmarks` is a `[Int]` written on every toggle. The star button (bottom bar + immersive overlay) toggles the current page. `translateMode` (Bool) persists the Reading/Translation toggle.
- `PageView` loads via `PageStore.load`, which **coalesces concurrent loads of the same (page, mode)** (one shared `Task`) so the visible page never loses a race with prefetch and goes blank. `PageView.task` is keyed on `"<page>-<translateMode>"` so flipping the toggle reloads the right source; it also retries a few times so a transient network miss self-heals. Don't reintroduce a nil-on-in-flight guard.
- No page-turn animation (removed by request). If re-adding, keep it optional.
- Keyboard: ← / `a` = forward (RTL), → / `d` = back, space = forward, `f` = fullscreen. Fullscreen sets `Reader.immersive`, which hides all chrome; controls re-reveal on mouse move.
- **Nav chevrons match their corner**: chevron.left on the **left** (→ `next`, forward in RTL), chevron.right on the **right** (→ `prev`), in both the control bar and the immersive overlay. Don't swap them back.
- **Scroll wheel pages** through the Mushaf (down = forward). Local `.scrollWheel` `NSEvent` monitor in `ContentView.installScrollMonitor` → `Reader.handleScroll`. **No time-based rate limiting** (removed by request): mouse wheel = one notch → one spread instantly; trackpad (precise deltas) accumulates and steps proportionally to swipe distance. Scrolls over the left 298pt (sidebar) pass through so the list scrolls instead.
