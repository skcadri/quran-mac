---
owner: sohaib
updated: 2026-11-23
---

# wordgen — builds `Sources/Mushaf/Resources/words.json`

One rect per printed word and ayah medallion on all 604 scans. The app derives its ayah boxes (translation hover,
memorization covers, recite marks) from this file — there is no other position data. Never hand-edit the output.

## Run
```
python3 -m venv /tmp/wordgen/.venv && /tmp/wordgen/.venv/bin/pip install fonttools brotli opencv-python-headless numpy
/tmp/wordgen/.venv/bin/python tools/wordgen/wordgen.py --work /tmp/wordgen          # ~1 min once downloads are cached
/tmp/wordgen/.venv/bin/python tools/wordgen/wordgen.py --work /tmp/wordgen --pages 50,604 --draw /tmp/wordgen/draw
```
`--work` caches the layouts, page fonts, scans and tilawa's `ref-v2.json` (≈350 MB). Keep it out of the repo.
`--draw` writes overlay PNGs and never writes `words.json`; only a full 1–604 run does.

## Rules
- Line breaks come from `api.qurancdn.com/api/qdc/…&mushaf=1` (QCF V2 = these scans). Never use
  `api.quran.com/api/v4` (it ignores `mushaf` and returns the 1405 layout) or `ayahinfo_1260.db` (a different
  edition) — neither matches the scans.
- Word widths come from the QCF V2 page fonts' advances. The fonts and text are only measured here; never ship
  them in the app.
- Word numbers in the output are **tilawa's** (`ref-v2.json`), so they match engine events. Medallions are 0. A
  printed word that tilawa counts as two (2:181, 8:6, 13:37, 37:130) carries its first engine index.
- Pages 1–2 are a centred disc (`disc_lines`); 3–604 sit on the 15-line grid (`line_bands`).

## Checks a run must pass
- The report lists medallions that weren't found (score < 0.55) or moved > 12 px when pinned. A clean run
  finds 6,235 of 6,236 (26:189 scores just under the bar and stays 2 px off) and pins 12 pages by 12–29 px
  (p.50 is the worst). Anything new there needs `--draw` and a look.
- Rebalance notes (`2:181:5 → line 15`) mean the API filed a word on the wrong line; p.27 is the known one.
- Spot-check `--draw` on 1, 2, 27, 50, 187, 604 after any change to the placement code.
