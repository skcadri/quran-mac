---
owner: sohaib
updated: 2026-11-23
---

# tilawa bridge — builds `Sources/Mushaf/Resources/tilawa-bridge.js`

- `bridge.ts` is the only hand-written file. After editing it: `npm install && npm run build` here, then commit
  the regenerated `tilawa-bridge.js`. Never hand-edit the generated bundle.
- Keep the bridge a dumb pipe: drive `@tilawa/core/web`, dedupe position events, post JSON to
  `webkit.messageHandlers.tilawa`. UI logic, text and page mapping belong in Swift (`Recitation.swift`).
- `onnxruntime-web` must be the exact version tilawa.dev hosts under `/v1/runtime/ort/<version>/`
  (`curl https://tilawa.dev/v1/manifest.json` → `"ort"`). When bumping `@tilawa/core` or `onnxruntime-web`, update
  the pinned paths, byte sizes and sha256s in `TilawaEngine.assets` from that manifest in the same change.
- `providers: ["wasm"]` on purpose: single-thread WASM runs a take at ~7× real time; WebGPU adds startup cost and
  fallbacks for no gain on this model.
