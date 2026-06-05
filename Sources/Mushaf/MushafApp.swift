import SwiftUI

@main
struct MushafApp: App {
    var body: some Scene {
        WindowGroup("Mushaf") {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .help) {}
        }
    }
}
