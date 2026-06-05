import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var reader = Reader()
    @State private var window: NSWindow?
    @State private var revealChrome = false
    @State private var hideWork: DispatchWorkItem?
    @State private var scrollMonitor: Any?

    private var p: Palette { reader.palette }

    var body: some View {
        ZStack(alignment: .top) {
            p.window.ignoresSafeArea()

            VStack(spacing: 0) {
                if !reader.immersive { topBar }

                HStack(spacing: 0) {
                    if reader.showSidebar && !reader.immersive {
                        Sidebar()
                            .transition(.move(edge: .leading))
                    }
                    ReaderView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if reader.showControls && !reader.immersive {
                    ControlBar()
                        .transition(.move(edge: .bottom))
                }
            }

            // Immersive: floating chrome that fades in on mouse movement.
            if reader.immersive {
                MouseMoveReporter { wake() }.allowsHitTesting(false)
                if revealChrome { immersiveOverlay.transition(.opacity) }
            }
        }
        .environmentObject(reader)
        .preferredColorScheme(reader.isDark ? .dark : .light)
        .background(WindowAccessor(
            onWindow: { window = $0 },
            onFullScreenChange: { full in
                withAnimation(.easeInOut(duration: 0.25)) { reader.immersive = full }
                if full { wake() }
            }
        ))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow)  { reader.next(); return .handled }
        .onKeyPress(.rightArrow) { reader.prev(); return .handled }
        .onKeyPress(.space)      { reader.next(); return .handled }
        .onKeyPress(keys: ["f"]) { _ in window?.toggleFullScreen(nil); return .handled }
        .onAppear {
            PageStore.shared.prefetch(around: reader.currentPage)
            installScrollMonitor()
        }
        .onDisappear {
            if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        }
        .ignoresSafeArea(edges: reader.immersive ? .all : [])
    }

    // MARK: - top bar (custom, leaves room for traffic lights)
    private var topBar: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 70)   // traffic lights live here
            Spacer()
            HStack(spacing: 4) {
                Text("Mushaf").fontWeight(.semibold).foregroundStyle(p.ink)
                Text("·").foregroundStyle(p.inkFaint)
                Text(reader.surah(forPage: reader.currentPage).english).foregroundStyle(p.inkSoft)
            }
            .font(.system(size: 13))
            Spacer()
            HStack(spacing: 4) {
                iconButton("sidebar.left", active: reader.showSidebar) {
                    withAnimation(.easeInOut(duration: 0.25)) { reader.showSidebar.toggle() }
                }
                iconButton("rectangle.bottomthird.inset.filled", active: reader.showControls) {
                    withAnimation(.easeInOut(duration: 0.25)) { reader.showControls.toggle() }
                }
                iconButton(reader.isDark ? "sun.max" : "moon") {
                    withAnimation { reader.isDark.toggle() }
                }
                iconButton("arrow.up.left.and.arrow.down.right") {
                    window?.toggleFullScreen(nil)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(p.titlebar)
        .overlay(Rectangle().fill(p.sidebarLine).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - immersive overlay (fades away, leaves only the Quran)
    private var immersiveOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Text(reader.surah(forPage: reader.currentPage).english + "  ·  Page \(reader.currentPage)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            .padding(.top, 12)
            Spacer()
            HStack(spacing: 16) {
                floatButton("chevron.right") { reader.prev() }
                floatButton(reader.isBookmarked ? "star.fill" : "star") { reader.toggleBookmark() }
                floatButton("arrow.down.right.and.arrow.up.left") { window?.toggleFullScreen(nil) }
                floatButton("chevron.left") { reader.next() }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 18)
        }
    }

    private func iconButton(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14))
                .frame(width: 30, height: 26)
                .foregroundStyle(active ? p.accent : p.inkSoft)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? p.accentSoft : .clear))
        }
        .buttonStyle(.plain)
    }

    private func floatButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17))
                .frame(width: 42, height: 42)
                .foregroundStyle(p.ink)
        }
        .buttonStyle(.plain)
    }

    /// Scroll wheel / trackpad pages through the Mushaf — except over the sidebar
    /// list (left 298pt), where scrolling should move the list itself.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if reader.showSidebar && !reader.immersive && event.locationInWindow.x < 298 {
                return event   // let the surah/juz/hizb list scroll
            }
            reader.handleScroll(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            return nil
        }
    }

    /// Reveal immersive chrome, then auto-hide after a pause.
    private func wake() {
        withAnimation(.easeOut(duration: 0.2)) { revealChrome = true }
        hideWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.4)) { revealChrome = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }
}
