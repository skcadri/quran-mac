import Foundation
import CoreGraphics

/// One ayah's footprint on a page: its per-line rectangles, normalized 0…1 in the
/// sufone scan (1240×1754) space. An ayah wraps lines, so `rects`
/// usually has more than one rectangle.
struct AyahBox {
    let surah: Int
    let ayah: Int
    let rects: [CGRect]
}

/// Bundled ayah-position boxes + English (Saheeh International) translations.
/// `boxes.json` is generated from the scans themselves by `tools/boxgen` (see CLAUDE.md).
@MainActor
final class MushafData {
    static let shared = MushafData()

    private var boxesByPage: [Int: [AyahBox]] = [:]
    private var translations: [String: String] = [:]

    private struct RawBox: Decodable { let s: Int; let a: Int; let r: [[Double]] }

    private init() {
        if let url = Bundle.module.url(forResource: "translations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            translations = dict
        }
        if let url = Bundle.module.url(forResource: "boxes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: [RawBox]].self, from: data) {
            for (key, arr) in raw {
                guard let page = Int(key) else { continue }
                boxesByPage[page] = arr.map { b in
                    AyahBox(surah: b.s, ayah: b.a,
                            rects: b.r.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) })
                }
            }
        }
    }

    /// All ayahs with a footprint on this page (empty for pages 1–2, which have none).
    func ayahs(onPage page: Int) -> [AyahBox] { boxesByPage[page] ?? [] }

    /// The ayah whose any line-rect contains the normalized point, if any.
    ///
    /// Each line-rect is tight to the glyphs (~0.037 tall) but the lines sit on a
    /// ~0.051 pitch, so there's a ~0.014 dead band between consecutive lines where a
    /// strict `contains` matches nothing and the translation flickers as the cursor
    /// crosses it. We inflate each rect vertically by half the gap so adjacent lines
    /// meet at the midpoint between them — no dead zone — while leaving the horizontal
    /// extent (and the page margins / empty areas) untouched.
    private static let lineHitPad: CGFloat = 0.008  // ≈ half the inter-line gap, in normalized page height
    func ayah(onPage page: Int, at p: CGPoint) -> AyahBox? {
        boxesByPage[page]?.first { box in
            box.rects.contains { $0.insetBy(dx: 0, dy: -Self.lineHitPad).contains(p) }
        }
    }

    func translation(surah: Int, ayah: Int) -> String? {
        translations["\(surah):\(ayah)"]
    }
}
