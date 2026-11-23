import SwiftUI

/// A single Mushaf page: shows the scan, with a soft shimmer while it loads.
/// `side` controls the gutter shadow so the spine reads correctly in a spread.
///
/// Overlays sit on the scan, keyed off the bundled, scan-aligned word boxes in `MushafData`:
///   - Translation mode: hover an ayah → highlight its lines + show the translation.
///   - Memorization mode: hide each ayah's text → click an ayah to reveal/re-hide it; reciting uncovers
///     it word by word.
///   - Recite mode: outline the word being recited, underline words with a mistake (`Recitation`).
struct PageView: View {
    let page: Int
    var side: Side = .single
    @EnvironmentObject var reader: Reader
    @EnvironmentObject var recitation: Recitation
    @State private var image: NSImage?
    @State private var hovered: AyahBox?

    enum Side { case left, right, single }

    /// Aspect of the sufone/medina-mushaf scans, 1240×1754.
    private let pageAspect: CGFloat = 1240.0 / 1754.0

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(reader.palette.chip)
                    .overlay(Shimmer())
                    .aspectRatio(pageAspect, contentMode: .fit)
            }
        }
        .background(Color(hex: 0xFDFCF7))
        .overlay(gutter)
        .overlay(ayahLayer)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.black.opacity(reader.isDark ? 0.5 : 0.16), lineWidth: 0.5)
        )
        .task(id: page) {
            // Retry a few times so a transient network miss self-heals instead of staying blank.
            for attempt in 0..<4 {
                if Task.isCancelled { return }
                if let img = await PageStore.shared.load(page) { image = img; return }
                try? await Task.sleep(nanoseconds: UInt64(0.6 * Double(attempt + 1) * 1_000_000_000))
            }
        }
    }

    // MARK: - overlays (translation hover, memorization covers, recite marks)

    @ViewBuilder private var ayahLayer: some View {
        if image != nil, reader.translateMode || reader.memorizeMode || recitation.marksVisible {
            GeometryReader { geo in
                let fit = fittedRect(in: geo.size)
                ZStack(alignment: .topLeading) {
                    if reader.memorizeMode { memorizeOverlay(fit) }
                    if recitation.marksVisible { reciteOverlay(fit) }
                    if reader.translateMode { translateOverlay(fit, geo: geo) }
                }
            }
        }
    }

    // MARK: translation (hover)

    @ViewBuilder private func translateOverlay(_ fit: CGRect, geo: GeometryProxy) -> some View {
        // Highlight the hovered ayah's lines (the card itself renders on the opposite page).
        if let h = hovered {
            ForEach(Array(h.rects.enumerated()), id: \.offset) { _, r in
                let fr = denormalize(r, in: fit)
                RoundedRectangle(cornerRadius: 2)
                    .fill(reader.palette.gold.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .stroke(reader.palette.gold.opacity(0.55), lineWidth: 1))
                    .frame(width: fr.width, height: fr.height)
                    .position(x: fr.midX, y: fr.midY)
            }
        }
        // Whole-page hover hit area.
        Color.clear.contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    let n = normalize(loc, in: fit)
                    let a = MushafData.shared.ayah(onPage: page, at: n)
                    hovered = a
                    if let a {
                        let line = a.rects.first(where: { $0.contains(n) }) ?? a.rects[0]
                        // Convert the hovered line's edges into the shared "spread" space.
                        let origin = geo.frame(in: .named("spread")).origin
                        let info = AyahHover(
                            page: page, surah: a.surah, ayah: a.ayah,
                            leftX: origin.x + fit.minX + line.minX * fit.width,
                            rightX: origin.x + fit.minX + line.maxX * fit.width,
                            centerY: origin.y + fit.minY + (line.minY + line.maxY) / 2 * fit.height,
                            lineH: line.height * fit.height)
                        reader.setHover(info)
                    } else if reader.hover?.page == page {
                        reader.scheduleClearHover()
                    }
                case .ended:
                    hovered = nil
                    if reader.hover?.page == page { reader.scheduleClearHover() }
                }
            }
    }

    // MARK: memorization (hide / click-to-reveal / uncover as recited)

    @ViewBuilder private func memorizeOverlay(_ fit: CGRect) -> some View {
        ForEach(covers()) { cover in
            let fr = denormalize(cover.rect, in: fit)
            RoundedRectangle(cornerRadius: 2)
                .fill(reader.palette.pageCover)
                .frame(width: fr.width, height: fr.height)
                .position(x: fr.midX, y: fr.midY)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: reader.revealedThrough)
        // Click anywhere on an ayah's lines to reveal / re-hide all of it.
        ForEach(Array(MushafData.shared.ayahs(onPage: page).enumerated()), id: \.offset) { _, box in
            ForEach(Array(box.rects.enumerated()), id: \.offset) { _, r in
                let fr = denormalize(r, in: fit)
                Color.clear
                    .frame(width: fr.width, height: fr.height)
                    .contentShape(Rectangle())
                    .onTapGesture { reader.toggleReveal(surah: box.surah, ayah: box.ayah) }
                    .position(x: fr.midX, y: fr.midY)
            }
        }
    }

    /// Each line's runs of still-hidden words, merged so no seams show between words. A run is keyed by its
    /// last (leftmost) word, which stays put while recitation uncovers the run from the right — so it shrinks
    /// smoothly instead of being replaced.
    private struct Cover: Identifiable { let id: String; let rect: CGRect }
    private func covers() -> [Cover] {
        var out: [Cover] = []
        for (l, line) in MushafData.shared.lines(onPage: page).enumerated() {
            var run: CGRect?
            for (i, w) in line.enumerated() {
                if reader.isRevealed(w) {
                    if let r = run { out.append(Cover(id: "\(l)-\(i - 1)", rect: r)) }
                    run = nil
                } else {
                    run = run.map { $0.union(w.rect) } ?? w.rect
                }
            }
            if let r = run { out.append(Cover(id: "\(l)-\(line.count - 1)", rect: r)) }
        }
        return out
    }

    // MARK: recite (the word being recited + words with a mistake; drawn over the covers, never hit-testable)

    @ViewBuilder private func reciteOverlay(_ fit: CGRect) -> some View {
        let p = reader.palette
        ZStack(alignment: .topLeading) {
            if let w = recitation.word, let at = MushafData.shared.word(surah: w.surah, ayah: w.ayah, word: w.word),
               at.page == page {
                let fr = denormalize(at.box.rect, in: fit).insetBy(dx: -2, dy: 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(p.accent.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.accent.opacity(0.75), lineWidth: 1.4))
                    .frame(width: fr.width, height: fr.height)
                    .position(x: fr.midX, y: fr.midY)
            }
            ForEach(recitation.mistakes) { m in
                if let at = MushafData.shared.word(surah: m.location.surah, ayah: m.location.ayah, word: m.location.word),
                   at.page == page {
                    let fr = denormalize(at.box.rect, in: fit)
                    Capsule().fill(p.pageMark.opacity(0.85))   // underline just below the word's descenders
                        .frame(width: fr.width * 0.9, height: max(1.5, fr.height * 0.045))
                        .position(x: fr.midX, y: fr.maxY - fr.height * 0.1)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: recitation.word)
    }

    // MARK: - image-fit geometry (image is shown aspect-fit, so it may be letterboxed)

    private func fittedRect(in size: CGSize) -> CGRect {
        var w = size.width, h = size.width / pageAspect
        if h > size.height { h = size.height; w = size.height * pageAspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func normalize(_ p: CGPoint, in r: CGRect) -> CGPoint {
        CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height)
    }

    private func denormalize(_ n: CGRect, in r: CGRect) -> CGRect {
        CGRect(x: r.minX + n.minX * r.width, y: r.minY + n.minY * r.height,
               width: n.width * r.width, height: n.height * r.height)
    }

    @ViewBuilder private var gutter: some View {
        switch side {
        case .left:
            LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .leading, endPoint: .init(x: 0.12, y: 0.5))
                .allowsHitTesting(false)
        case .right:
            LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .init(x: 0.88, y: 0.5), endPoint: .trailing)
                .allowsHitTesting(false)
        case .single:
            EmptyView()
        }
    }
}

struct Shimmer: View {
    @State private var x: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width)
                .offset(x: x * geo.size.width)
                .onAppear {
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { x = 1 }
                }
        }
        .clipped()
    }
}
