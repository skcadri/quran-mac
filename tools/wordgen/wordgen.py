#!/usr/bin/env python3
"""Generate Sources/Mushaf/Resources/words.json: a rectangle for every word and ayah medallion on the 604
sufone scans. The app derives its ayah boxes from these too (see CLAUDE.md here).

The scans follow the QCF V2 (1421) layout, so Quran.com's word-by-word layout for that mushaf gives each
word's line, and its per-page font (one glyph per word) gives each word's share of the line. We scale those
advances onto the ink of each scanned line. Nothing from Quran.com ships in the app — only this geometry.

    python3 wordgen.py --work /tmp/wordgen                                 # all 604 pages → words.json + report
    python3 wordgen.py --work /tmp/wordgen --pages 1-5 --draw /tmp/draw    # overlays to eyeball, no write
"""
import argparse, json, re, sys, unicodedata, urllib.request
from pathlib import Path

import cv2
import numpy as np
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "Sources/Mushaf/Resources/words.json"
W, H = 1240, 1754
LAYOUT = ("https://api.qurancdn.com/api/qdc/verses/by_page/{p}?words=true&per_page=all&mushaf=1"
          "&word_fields=line_number,code_v2,text_uthmani")   # api.quran.com/api/v4 ignores mushaf=1 — never use it
FONT = "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p{p}.woff2"
SCAN = "https://raw.githubusercontent.com/sufone/medina-mushaf/master/png-d150/{p}.png"
REF = "https://tilawa.dev/v1/reference/ref-v2.json"   # the recitation engine's word list (same pin as TilawaEngine)

GRID0, PITCH = 263.5, 89.5   # 15-line grid: line n's centre ≈ GRID0 + (n-1)·PITCH (+ a per-page shift)
HALF = 44                    # half a line band: nearly the full pitch, so memorization covers hide tall letters
                             # and vowel marks too (36 let 2% of the ink peek out between lines)
BLOCK = {1: (67, 1044), 0: (195, 1172)}   # text block per page parity (odd pages sit right of the spine)
INK = 90                                  # a pixel is ink when every channel is below this
TEMPLATE = cv2.imread(str(HERE / "medallion_template.png"), cv2.IMREAD_GRAYSCALE).astype(np.float32)


def cached(path: Path, url: str) -> Path:
    if not path.exists() or path.stat().st_size == 0:
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "mushaf-wordgen"})
        path.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    return path


# ── words ────────────────────────────────────────────────────────────────────────────────────────────────

def letters(s: str) -> str:
    """Base Arabic letters only, so two Uthmani spellings of a word compare equal."""
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) == "Lo")


def ref_index(qdc_words: list[str], ref_words: list[str]) -> list[int]:
    """1-based index of each layout word's first engine word. The two texts split a few words differently
    (بَعْدَ مَا, إِلْ يَاسِينَ, …), so let a layout word absorb engine words until the letters match."""
    if len(qdc_words) == len(ref_words):
        return list(range(1, len(ref_words) + 1))
    out, j = [], 0
    for q in qdc_words:
        out.append(j + 1)
        target, got = letters(q), ""
        while j < len(ref_words) and len(got) < len(target):
            got += letters(ref_words[j]); j += 1
        if got != target:
            raise ValueError(f"can't align {q!r} with engine words near {j}")
    if j != len(ref_words):
        raise ValueError("engine has words left over")
    return out


def page_words(work: Path, p: int) -> list[dict]:
    """The page's words and medallions in reading order."""
    layout = json.loads(cached(work / f"qdc/{p}.json", LAYOUT.format(p=p)).read_text())
    font = TTFont(cached(work / f"fonts/p{p}.woff2", FONT.format(p=p)))
    cmap, hmtx = font.getBestCmap(), font["hmtx"]
    out = []
    for v in layout["verses"]:
        s, a = map(int, v["verse_key"].split(":"))
        for w in v["words"]:
            text = w.get("text_uthmani") or ""
            # 2:181's medallion is typed "word" in the API; a medallion is the one "word" made of digits.
            end = w["char_type_name"] == "end" or re.fullmatch(r"[٠-٩]+", text) is not None
            adv = sum(hmtx[cmap[ord(c)]][0] for c in w["code_v2"] if ord(c) in cmap)   # skips the odd space
            out.append(dict(s=s, a=a, pos=w["position"], line=w["line_number"], end=end, adv=adv, text=text))
    return out


# ── geometry ─────────────────────────────────────────────────────────────────────────────────────────────

def runs(cols: np.ndarray, gap: int) -> list[list[int]]:
    out = [[cols[0], cols[0]]]
    for c in cols[1:]:
        if c - out[-1][1] <= gap: out[-1][1] = c
        else: out.append([c, c])
    return out


def line_bands(ink: np.ndarray, lines: list[int], lo: int, hi: int) -> dict[int, tuple[int, int]]:
    """y-range of each line: the grid, shifted by the page's median offset between grid and ink."""
    rows = ink[:, lo:hi].sum(axis=1)
    shifts = []
    for ln in lines:
        mid = round(GRID0 + (ln - 1) * PITCH)
        inked = np.where(rows[mid - 44:mid + 44] >= 3)[0]
        if len(inked): shifts.append((inked[0] + inked[-1]) / 2 - 44)
    shift = float(np.median(shifts)) if shifts else 0.0
    return {ln: (round(GRID0 + (ln - 1) * PITCH + shift - HALF), round(GRID0 + (ln - 1) * PITCH + shift + HALF))
            for ln in lines}


def ink_extent(ink: np.ndarray, y0: int, y1: int, lo: int, hi: int):
    """Edges of the widest ink run in a band, bridging gaps under 30 px (the gaps between words)."""
    cols = np.where(ink[y0:y1, lo:hi].sum(axis=0) >= 2)[0]
    if len(cols) == 0: return None
    l, r = max(runs(cols, 30), key=lambda r: r[1] - r[0])
    return lo + int(l), lo + int(r) + 1


def rebalance(words: list[dict], lines: list[int], target: dict[int, float]):
    """The layout API occasionally files a word on the neighbouring line (p.27). Move boundary words
    between two justified lines while that brings both closer to the advance their ink implies."""
    by = lambda ln: [w for w in words if w["line"] == ln]
    err = lambda ln: sum(w["adv"] for w in by(ln)) - target[ln]
    moved = []
    for a, b in zip(lines, lines[1:]):
        if b != a + 1 or a not in target or b not in target: continue
        while True:
            ea, eb = err(a), err(b)
            if ea > 0 > eb:
                w = by(a)[-1]; new = abs(ea - w["adv"]) + abs(eb + w["adv"])
                if new >= abs(ea) + abs(eb) - 0.02 * target[a]: break
                w["line"] = b
            elif ea < 0 < eb:
                w = by(b)[0]; new = abs(ea + w["adv"]) + abs(eb - w["adv"])
                if new >= abs(ea) + abs(eb) - 0.02 * target[a]: break
                w["line"] = a
            else: break
            moved.append(f"{w['s']}:{w['a']}:{w['pos']} → line {w['line']}")
    order = {id(w): i for i, w in enumerate(words)}
    words.sort(key=lambda w: (w["line"], order[id(w)]))   # keep reading order within lines
    return moved


def find_medallion(gray: np.ndarray, cx: float, y0: int, y1: int) -> tuple[float, float]:
    """(x centre, match score) of the medallion nearest a predicted centre, by multi-scale template matching
    (its ornate ring scores far above any letter)."""
    X0 = max(0, int(cx) - 60)
    best = (0.0, -1.0)
    for sc in (0.8, 0.9, 1.0, 1.1, 1.2):
        t = cv2.resize(TEMPLATE, None, fx=sc, fy=sc)
        res = cv2.matchTemplate(gray[y0 - 8:y1 + 8, X0:X0 + 120], t, cv2.TM_CCOEFF_NORMED)
        _, score, _, loc = cv2.minMaxLoc(res)
        if score > best[1]: best = (X0 + loc[0] + t.shape[1] / 2, score)
    return best


def disc_lines(img: np.ndarray, lines: list[int]):
    """Pages 1–2 set Al-Fatihah and al-Baqarah 1–5 centred in a cream disc on their own tighter grid (layout
    lines 9–15; page 2's line 9 is the basmala). Fit that grid to the ink inside the disc."""
    bright = (img.min(axis=2) > 200).astype(np.uint8)
    _, lab = cv2.connectedComponents(bright, connectivity=4)
    disc = (lab == lab[H // 2, W // 2]).astype(np.uint8)
    cnts, _ = cv2.findContours(disc, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    disc = np.zeros_like(disc)
    cv2.drawContours(disc, [max(cnts, key=cv2.contourArea)], -1, 1, -1)
    ink = (img.max(axis=2) < 200) & (cv2.erode(disc, np.ones((15, 15), np.uint8)) > 0)   # grey medallions count
    rows = ink.sum(axis=1).astype(float)
    def score(y9, pitch):
        cs = [round(y9 + (ln - 9) * pitch) for ln in range(9, 16)]
        return sum(rows[c - 20:c + 20].sum() - 2 * rows[round(c + pitch / 2) - 5:round(c + pitch / 2) + 5].sum()
                   for c in cs)
    y9, pitch = max(((y, pt) for y in range(560, 760) for pt in np.arange(66, 80, 0.5)), key=lambda a: score(*a))
    half = pitch / 2 - 0.5
    bands = {ln: (round(y9 + (ln - 9) * pitch - half), round(y9 + (ln - 9) * pitch + half)) for ln in lines}
    return bands, {ln: ink_extent(ink, *bands[ln], 0, W) for ln in lines}


ANCHOR = 0.55   # template score above which a found medallion pins the line


def place_page(p: int, words: list[dict], img: np.ndarray):
    """Word rects (x0, y0, x1, y1) in scan px. Each line's advances are stretched over its ink, then pinned at
    every medallion found on it, so ayah boundaries are exact and drift can't build up along a line."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    lines = sorted({w["line"] for w in words})
    adv = lambda ln: sum(w["adv"] for w in words if w["line"] == ln)
    issues = []
    if p <= 2:
        bands, ext = disc_lines(img, lines)
        justified, L, R = set(), 0, 0
        scale = float(np.median([(e[1] - e[0]) / adv(ln) for ln, e in ext.items() if e]))
    else:
        ink = img.max(axis=2) < INK
        lo, hi = BLOCK[p % 2]
        bands = line_bands(ink, lines, lo, hi)
        ext = {ln: ink_extent(ink, *bands[ln], lo + 40, hi - 40) for ln in lines}   # text sits ~85 px inside the frame
        widest = max(e[1] - e[0] for e in ext.values() if e)
        full_ink = [ln for ln, e in ext.items() if e and e[1] - e[0] > 0.95 * widest]
        # Justified lines all span the same block; take its edges by consensus so a stray ornament can't stretch one.
        L = float(np.median([ext[ln][0] for ln in full_ink])); R = float(np.median([ext[ln][1] for ln in full_ink]))
        scale = float(np.median([(ext[ln][1] - ext[ln][0]) / adv(ln) for ln in full_ink]))   # px per font unit
        issues += rebalance(words, lines, {ln: (R - L) / scale for ln in full_ink})
        justified = {ln for ln in lines if adv(ln) * scale > 0.96 * (R - L)}
    placed, shifts = [], []
    for ln in lines:
        want = adv(ln) * scale
        if ln in justified:
            x0, x1 = L, R
        else:
            e = ext[ln]                                     # short or centred line: trust its own ink
            if e is None or abs((e[1] - e[0]) - want) > 0.05 * want:
                c = (e[0] + e[1]) / 2 if e else (L + R) / 2
                issues.append(f"line {ln}: short line ink {None if e is None else e[1] - e[0]}px vs {want:.0f}px")
                e = (c - want / 2, c + want / 2)
            x0, x1 = e
        ws = [w for w in words if w["line"] == ln]
        starts = np.cumsum([0] + [w["adv"] for w in ws])   # advance at each word's right edge, reading order
        k = (x1 - x0) / starts[-1]
        pins = [(0.0, x1), (float(starts[-1]), x0)]
        for i, w in enumerate(ws):
            if not w["end"]: continue
            mid = (starts[i] + starts[i + 1]) / 2
            fx, score = find_medallion(gray, x1 - mid * k, *bands[ln])
            shifts.append((w, fx - (x1 - mid * k), score))
            if score >= ANCHOR: pins.append((float(mid), fx))
        pins.sort()
        if any(b[1] >= a[1] for a, b in zip(pins, pins[1:])):   # found medallions out of order: don't trust them
            issues.append(f"line {ln}: medallion pins out of order"); pins = [pins[0], pins[-1]]
        xs = np.interp(starts, [a for a, _ in pins], [x for _, x in pins])
        for i, w in enumerate(ws):
            placed.append((w, (float(xs[i + 1]), bands[ln][0], float(xs[i]), bands[ln][1])))
    return placed, issues, shifts


# ── main ─────────────────────────────────────────────────────────────────────────────────────────────────

def parse_pages(spec: str) -> list[int]:
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        out += range(int(a), int(b or a) + 1)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", type=Path, required=True, help="download cache (layouts, fonts, scans)")
    ap.add_argument("--pages", default="1-604")
    ap.add_argument("--draw", type=Path, help="write an overlay PNG per page here")
    args = ap.parse_args()

    ref = {(a["s"], a["a"]): a["w"] for a in json.loads(cached(args.work / "ref-v2.json", REF).read_text())["ayahs"]}
    pages = parse_pages(args.pages)
    result, report = {}, {}
    for p in pages:
        words = page_words(args.work, p)
        img = cv2.imread(str(cached(args.work / f"scans/{p}.png", SCAN.format(p=p))))[:, :, :3]
        placed, issues, shifts = place_page(p, words, img)
        for key in {(w["s"], w["a"]) for w in words}:   # layout word → engine word index (medallions: 0)
            ws = [w for w in words if (w["s"], w["a"]) == key and not w["end"]]
            for w, i in zip(ws, ref_index([w["text"] for w in ws], ref[key])): w["ref"] = i
        lines = {}
        for w, (x0, y0, x1, y1) in placed:
            ln = lines.setdefault(w["line"], {"y": round(y0 / H, 4), "h": round((y1 - y0) / H, 4), "w": []})
            ln["w"].append([w["s"], w["a"], 0 if w["end"] else w["ref"], round(x0 / W, 4), round((x1 - x0) / W, 4)])
        result[str(p)] = [lines[k] for k in sorted(lines)]
        # A medallion we couldn't find wasn't pinned; one that moved a lot means the line's advances drifted.
        report[p] = {"issues": issues,
                     "medallions": [f"{w['s']}:{w['a']} moved {d:+.0f}px score {sc:.2f}" for w, d, sc in shifts
                                    if abs(d) > 12 or sc < ANCHOR]}
        if args.draw:
            args.draw.mkdir(parents=True, exist_ok=True)
            out = img.copy()
            for i, (w, (x0, y0, x1, y1)) in enumerate(placed):
                color = (40, 90, 220) if w["end"] else [(60, 160, 60), (200, 120, 30)][i % 2]
                cv2.rectangle(out, (int(x0), y0), (int(x1), y1), color, 2)
            cv2.imwrite(str(args.draw / f"{p}.png"), out)
        if p % 50 == 0: print("…", p, file=sys.stderr)

    (args.work / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False))
    flagged = {p: r for p, r in report.items() if r["issues"] or r["medallions"]}
    print(f"{len(pages)} pages, {sum(len(r['medallions']) for r in report.values())} medallions to look at "
          f"(unconfirmed or moved >12 px), on {len(flagged)} pages")
    for p, r in flagged.items(): print(" ", p, r)
    if args.draw is None and pages == parse_pages("1-604"):
        OUT.write_text(json.dumps(result, separators=(",", ":")))
        print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
