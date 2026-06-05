import SwiftUI

/// A single Mushaf page: shows the scan, with a soft shimmer while it loads.
/// `side` controls the gutter shadow so the spine reads correctly in a spread.
struct PageView: View {
    let page: Int
    var side: Side = .single
    @EnvironmentObject var reader: Reader
    @State private var image: NSImage?

    enum Side { case left, right, single }

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
                    .aspectRatio(0.62, contentMode: .fit)
            }
        }
        .background(Color(hex: 0xFDFCF7))
        .overlay(gutter)
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
