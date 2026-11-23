import Foundation
import CoreGraphics

/// One printed word, or an ayah's end medallion, on a scan. `rect` is normalized 0…1 in the sufone scan
/// (1240×1754) space. `word` is tilawa's 1-based word index — the first engine word it shows, since a few
/// printed words count as two (بَعْدَمَا) — and 0 for the medallion.
struct WordBox {
    let surah: Int
    let ayah: Int
    let word: Int
    let rect: CGRect
    var isMedallion: Bool { word == 0 }
}

/// One ayah's footprint on a page: its per-line rectangles (normalized, like `WordBox`). An ayah wraps
/// lines, so `rects` usually has more than one rectangle. Derived from the word boxes.
struct AyahBox {
    let surah: Int
    let ayah: Int
    let rects: [CGRect]
}

/// Bundled word positions + English (Saheeh International) translations.
/// `words.json` is generated from the scans by `tools/wordgen` (see its CLAUDE.md); ayah boxes derive from it.
@MainActor
final class MushafData {
    static let shared = MushafData()

    /// page → text lines → words in reading order (right to left).
    private var linesByPage: [Int: [[WordBox]]] = [:]
    private var boxesByPage: [Int: [AyahBox]] = [:]
    /// "s:a" → the page an ayah is on (no ayah crosses a page in this mushaf) and its words, in order.
    private var ayahWords: [String: (page: Int, words: [WordBox])] = [:]
    private var translations: [String: String] = [:]

    private struct RawLine: Decodable { let y: Double; let h: Double; let w: [[Double]] }   // w: [s, a, word, x, width]

    private init() {
        if let url = Bundle.resources.url(forResource: "translations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            translations = dict
        }
        guard let url = Bundle.resources.url(forResource: "words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [RawLine]].self, from: data) else { return }
        for (key, rawLines) in raw {
            guard let page = Int(key) else { continue }
            let lines = rawLines.map { line in
                line.w.map { w in
                    WordBox(surah: Int(w[0]), ayah: Int(w[1]), word: Int(w[2]),
                            rect: CGRect(x: w[3], y: line.y, width: w[4], height: line.h))
                }
            }
            linesByPage[page] = lines
            // An ayah's rect on a line is the union of its words there.
            var order: [String] = []
            var rects: [String: [CGRect]] = [:]
            for line in lines {
                var onLine: [String: CGRect] = [:]
                var lineOrder: [String] = []
                for w in line {
                    let k = "\(w.surah):\(w.ayah)"
                    if onLine[k] == nil { lineOrder.append(k) }
                    onLine[k] = onLine[k].map { $0.union(w.rect) } ?? w.rect
                    ayahWords[k, default: (page, [])].words.append(w)
                }
                for k in lineOrder {
                    if rects[k] == nil { order.append(k) }
                    rects[k, default: []].append(onLine[k]!)
                }
            }
            boxesByPage[page] = order.map { k in
                let w = ayahWords[k]!.words[0]
                return AyahBox(surah: w.surah, ayah: w.ayah, rects: rects[k]!)
            }
        }
    }

    /// All ayahs with a footprint on this page, in reading order.
    func ayahs(onPage page: Int) -> [AyahBox] { boxesByPage[page] ?? [] }

    /// The page's text lines, each a run of words in reading order.
    func lines(onPage page: Int) -> [[WordBox]] { linesByPage[page] ?? [] }

    /// The ayah whose any line-rect contains the normalized point, if any. Line bands span nearly the whole
    /// line pitch, so the cursor never falls in a gap between lines.
    func ayah(onPage page: Int, at p: CGPoint) -> AyahBox? {
        boxesByPage[page]?.first { box in box.rects.contains { $0.contains(p) } }
    }

    /// The page an ayah is printed on.
    func page(surah: Int, ayah: Int) -> Int? { ayahWords["\(surah):\(ayah)"]?.page }

    /// Where engine word `word` (1-based) of an ayah is printed: the last box starting at or before it.
    func word(surah: Int, ayah: Int, word: Int) -> (page: Int, box: WordBox)? {
        guard let entry = ayahWords["\(surah):\(ayah)"],
              let box = entry.words.last(where: { !$0.isMedallion && $0.word <= word }) else { return nil }
        return (entry.page, box)
    }

    func translation(surah: Int, ayah: Int) -> String? {
        translations["\(surah):\(ayah)"]
    }
}

extension Bundle {
    /// Our bundled data (words, translations, tilawa bridge). Always use this, never `Bundle.module`:
    /// SwiftPM's accessor only looks next to the .app and in the absolute build folder, so an installed or
    /// copied app (e.g. /Applications) hits its fatalError once that folder is gone. `build_app.sh` puts the
    /// bundle in Contents/Resources; `swift run` finds it next to the executable.
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Mushaf_Mushaf.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
}
