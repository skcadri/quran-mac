import SwiftUI
import AppKit

struct ReaderView: View {
    @EnvironmentObject var reader: Reader
    private var p: Palette { reader.palette }

    var body: some View {
        VStack(spacing: 0) {
            if !reader.immersive { topLabel }
            spreadArea
        }
        .background(p.readingBackground)
    }

    private var topLabel: some View {
        let s = reader.surah(forPage: reader.currentPage)
        return HStack(spacing: 8) {
            Text("Juz \(reader.juz(forPage: reader.currentPage))")
            dot
            Text(s.english)
            dot
            Text(s.place.capitalized)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(p.inkSoft)
        .frame(height: 40)
    }

    private var dot: some View {
        Circle().fill(p.inkFaint).frame(width: 3, height: 3)
    }

    private var spreadArea: some View {
        let spread = reader.spread
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {
                    if let left = spread.left { pageColumn(left, side: .left) }
                    pageColumn(spread.right, side: spread.left == nil ? .single : .right)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(reader.isDark ? 0.55 : 0.28), radius: 22, x: 0, y: 18)

                tooltip(in: geo.size, spread: spread)
                    .animation(.easeOut(duration: 0.13), value: reader.hover != nil)
            }
            .coordinateSpace(name: "spread")
        }
    }

    /// Translation bubble: sits beside the hovered line, offset toward the *opposite* page
    /// (left when hovering the right page, and vice-versa), with a tail pointing back at the ayah.
    /// It may overlap the gutter / opposite page — that's intended; it just never covers the ayah.
    @ViewBuilder private func tooltip(in size: CGSize, spread: (left: Int?, right: Int)) -> some View {
        if let h = reader.hover, let text = MushafData.shared.translation(surah: h.surah, ayah: h.ayah) {
            // Scale the whole bubble to the rendered Arabic line height (≈0.85 windowed → larger fullscreen).
            let s = min(max(h.lineH / 30, 1.0), 2.0)
            let bw = 290 * s
            let tailW = 9 * s
            let totalW = bw + tailW
            let gap = 5 * s
            let toLeft = (spread.left == nil) || (h.page == spread.right)   // right page → bubble on the left
            let cx = toLeft ? (h.leftX - gap - totalW / 2) : (h.rightX + gap + totalW / 2)

            let perLine = max(20, Int((bw - 34 * s) / (7.0 * s)))
            let nLines = max(1, Int(ceil(Double(text.count) / Double(perLine))))
            let bh = CGFloat(50 + nLines * 19) * s
            let cxc = min(max(cx, totalW / 2 + 8), size.width - totalW / 2 - 8)
            let cyc = min(max(h.centerY, bh / 2 + 8), size.height - bh / 2 - 8)

            sideBubble(h, text, width: bw, tailRight: toLeft, s: s)
                .position(x: cxc, y: cyc)
                .onHover { inside in inside ? reader.cancelClearHover() : reader.scheduleClearHover() }
                .transition(.opacity)
        }
    }

    private func sideBubble(_ h: AyahHover, _ text: String, width: CGFloat, tailRight: Bool, s: CGFloat) -> some View {
        let name = (1...QuranData.surahs.count).contains(h.surah) ? QuranData.surahs[h.surah - 1].english : "Surah \(h.surah)"
        let body = VStack(alignment: .leading, spacing: 5 * s) {
            HStack(spacing: 8 * s) {
                Text("\(name) · Ayah \(h.ayah)".uppercased())
                    .font(.system(size: 10.5 * s, weight: .bold)).tracking(0.5 * s)
                    .foregroundStyle(p.gold)
                Spacer(minLength: 6 * s)
                linkButton("magnifyingglass", s: s) {
                    openURL("https://www.google.com/search?q=", "Quran \(h.surah):\(h.ayah) Surah \(name) meaning tafsir")
                }
                linkButton("sparkles", s: s) {
                    openURL("https://claude.ai/new?q=", "Explain the meaning, context, and tafsir of Qur'an \(h.surah):\(h.ayah) (Surah \(name), ayah \(h.ayah)).")
                }
            }
            Text(text)
                .font(.system(size: 13.5 * s)).lineSpacing(2 * s)
                .foregroundStyle(p.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14 * s).padding(.vertical, 11 * s)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11 * s).fill(p.window))
        .overlay(RoundedRectangle(cornerRadius: 11 * s).stroke(p.sidebarLine, lineWidth: 0.5))
        let tail = Triangle(direction: tailRight ? .right : .left).fill(p.window).frame(width: 9 * s, height: 18 * s)
        return HStack(spacing: -1) {
            if tailRight { body; tail } else { tail; body }
        }
        .shadow(color: .black.opacity(0.28), radius: 16, x: (tailRight ? -3 : 3) * s, y: 6)
    }

    private func linkButton(_ icon: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(p.inkSoft)
                .frame(width: 20 * s, height: 20 * s)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Open `base + percent-encoded(query)` in the default browser (Claude links route to the app if installed).
    private func openURL(_ base: String, _ query: String) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: base + q) { NSWorkspace.shared.open(url) }
    }

    private func pageColumn(_ page: Int, side: PageView.Side) -> some View {
        VStack(spacing: 6) {
            PageView(page: page, side: side)
            Text("\(page)")
                .font(.system(size: 11))
                .foregroundStyle(p.inkFaint)
        }
    }
}

/// Small tail for the translation tooltip, pointing toward the hovered ayah.
struct Triangle: Shape {
    enum Direction { case up, down, left, right }
    var direction: Direction
    func path(in r: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .up:    path.move(to: CGPoint(x: r.midX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case .down:  path.move(to: CGPoint(x: r.midX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        case .right: path.move(to: CGPoint(x: r.maxX, y: r.midY)); path.addLine(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case .left:  path.move(to: CGPoint(x: r.minX, y: r.midY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        path.closeSubpath()
        return path
    }
}
