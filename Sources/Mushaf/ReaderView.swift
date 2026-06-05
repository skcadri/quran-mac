import SwiftUI

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
        return HStack(alignment: .top, spacing: 0) {
            if let left = spread.left { pageColumn(left, side: .left) }
            pageColumn(spread.right, side: spread.left == nil ? .single : .right)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(reader.isDark ? 0.55 : 0.28), radius: 22, x: 0, y: 18)
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
