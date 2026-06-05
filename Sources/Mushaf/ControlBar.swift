import SwiftUI

struct ControlBar: View {
    @EnvironmentObject var reader: Reader
    private var p: Palette { reader.palette }

    /// Always a page scrubber over the whole Mushaf (1…604).
    private var pageBinding: Binding<Double> {
        Binding(
            get: { Double(reader.currentPage) },
            set: { reader.go(to: Int($0.rounded())) }
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            navButton("chevron.right") { reader.prev() }   // RTL: right = backward
            bookmarkButton

            VStack(spacing: 3) {
                HStack {
                    Text("Page \(QuranData.totalPages)").font(.system(size: 10.5)).foregroundStyle(p.inkFaint)
                    Spacer()
                    Text("Page 1").font(.system(size: 10.5)).foregroundStyle(p.inkFaint)
                }
                Slider(value: pageBinding, in: 1...Double(QuranData.totalPages), step: 1)
                    .controlSize(.small)
                    .tint(p.accent)
                    .environment(\.layoutDirection, .rightToLeft)   // page 1 on the right (RTL)
            }

            pageInfo
            navButton("chevron.left") { reader.next() }    // RTL: left = forward
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background(p.titlebar)
        .overlay(Rectangle().fill(p.sidebarLine).frame(height: 0.5), alignment: .top)
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(SoftButton(palette: p))
    }

    private var bookmarkButton: some View {
        Button { reader.toggleBookmark() } label: {
            Image(systemName: reader.isBookmarked ? "star.fill" : "star")
                .font(.system(size: 16))
                .foregroundStyle(reader.isBookmarked ? p.gold : p.inkSoft)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var pageInfo: some View {
        VStack(spacing: 1) {
            Text("Page \(reader.currentPage)")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
            Text("Juz \(reader.juz(forPage: reader.currentPage)) · Hizb \(reader.hizb(forPage: reader.currentPage))")
                .font(.system(size: 10.5)).foregroundStyle(p.inkFaint)
        }
        .frame(minWidth: 130)
    }
}

struct SoftButton: ButtonStyle {
    let palette: Palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .white : palette.ink)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(configuration.isPressed ? palette.accent : palette.window))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.sidebarLine, lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
