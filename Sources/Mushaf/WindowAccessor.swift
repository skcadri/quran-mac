import SwiftUI
import AppKit

/// Grabs the hosting NSWindow so we can style the title bar and drive fullscreen,
/// and reports enter/exit-fullscreen so the UI can go fully immersive (chrome hidden).
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    var onFullScreenChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFullScreenChange) }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.setContentSize(NSSize(width: 1180, height: 760))
            window.minSize = NSSize(width: 720, height: 520)
            context.coordinator.observe(window)
            onWindow(window)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        let cb: (Bool) -> Void
        init(_ cb: @escaping (Bool) -> Void) { self.cb = cb }
        func observe(_ window: NSWindow) {
            let nc = NotificationCenter.default
            nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [cb] _ in cb(true) }
            nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [cb] _ in cb(false) }
        }
    }
}

/// Tracks live mouse movement inside a view (used to auto-reveal controls in fullscreen).
struct MouseMoveReporter: NSViewRepresentable {
    var onMove: () -> Void
    func makeNSView(context: Context) -> NSView { Tracking(onMove) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Tracking: NSView {
        let onMove: () -> Void
        init(_ onMove: @escaping () -> Void) { self.onMove = onMove; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
        }
        override func mouseMoved(with event: NSEvent) { onMove() }
    }
}
