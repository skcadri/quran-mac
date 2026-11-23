// Mushaf ⇄ tilawa bridge. Runs inside a hidden WKWebView (see Sources/Mushaf/TilawaEngine.swift).
// Swift owns the microphone, the asset cache and all UI; this file only drives @tilawa/core and
// posts its events back. Rebuild with `npm run build` (writes Sources/Mushaf/Resources/tilawa-bridge.js).
import { ayahsRecited, memoryStorage } from "@tilawa/core";
import type { EngineEvent, Tilawa, TilawaSession } from "@tilawa/core";
import { createTilawa } from "@tilawa/core/web";

type Msg = Record<string, unknown> & { type: string };
const post = (m: Msg) => (window as any).webkit?.messageHandlers?.tilawa?.postMessage(JSON.parse(JSON.stringify(m)));

let tilawa: Tilawa | null = null;
let session: TilawaSession | null = null;
let events: EngineEvent[] = [];
let lastPosition = "";

async function load(assetBase: string) {
  if (tilawa) return tilawa.model;
  tilawa = await createTilawa({
    assetBase,
    storage: memoryStorage(),   // Swift already keeps the files on disk; don't duplicate them in WebKit
    tier: "full",
    providers: ["wasm"],
    onProgress: (p) => post({ type: "progress", stage: p.stage, fraction: p.fraction }),
  });
  return tilawa.model;
}

function start() {
  if (!tilawa) throw new Error("not loaded");
  session?.dispose();
  events = [];
  lastPosition = "";
  const s = tilawa.startFreeRecitation();
  session = s;
  s.subscribe((e) => {
    if (s !== session) return;
    events.push(e);
    if (e.type === "position") {
      // ~25 position events a second; forward only when the state or the best word changes.
      const top = e.observed[0]?.word;
      const key = `${e.state}|${top ? `${top.surah}:${top.ayah}:${top.word}` : ""}`;
      if (key === lastPosition) return;
      lastPosition = key;
      post({ type: "position", state: e.state, word: top ?? null, timeMs: e.timeMs });
    } else if (e.type === "checker") {
      post({ type: "checker", id: e.id, state: e.state, errorClass: e.errorClass, location: e.location, timeMs: e.timeMs });
    }
  });
}

function push(b64: string) {
  const s = session;
  if (!s || s.state !== "active") return;
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  s.pushAudio(new Float32Array(bytes.buffer), 16000).catch((e) => post({ type: "error", message: String(e?.message ?? e) }));
}

async function stop() {
  const s = session;
  if (!s) return { recited: [], mistakes: [] };
  if (s.state === "active") await s.end();
  const result = { recited: ayahsRecited(events), mistakes: s.mistakes(), audioMs: s.now() };
  s.dispose();
  if (session === s) session = null;
  return result;
}

(window as any).tilawaBridge = { load, start, push, stop };
post({ type: "boot" });
