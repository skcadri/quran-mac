# boxgen — regenerate Sources/Mushaf/Resources/boxes.json

From-scratch ayah-box detector for the sufone/medina-mushaf scans. NOT derived from any
external glyph database (those are different editions with different line breaks — see CLAUDE.md).

## Run
1. Download all scans to `scans/<n>.png` (n=1..604) from the png-d150 source.
2. The template is loaded from page 3's medallion; `process_all.py` currently reads it from
   `p3.png` at (301,892) — point it at `medallion_template.png` or `scans/3.png` instead.
3. `pip install opencv-python-headless numpy pillow`
4. `python3 process_all.py` → writes boxes.json + a `diags.json` validation report.

## Inputs
- `page_meta.json` — page → ordered list of `(surah,ayah)` ending on that page (marker count + numbering).
- `medallion_template.png` — 44×44 ayah-end medallion, matched multi-scale (0.8–1.2).

## Validation
Each page's detected medallion count must equal `len(page_meta[page])`. `diags.json` flags
pages with missing medallions or an ambiguous score gap (spot-check those).

Known gaps: pages 1–2 (Al-Fatihah oval) excluded; ~29 pages have a soft score-gap flag.
