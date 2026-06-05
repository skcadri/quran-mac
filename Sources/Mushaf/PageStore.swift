import SwiftUI
import AppKit

/// Loads Mushaf page images. Strategy:
///   1. bundled `Pages/<n>.png` if present (offline build),
///   2. on-disk cache in Application Support,
///   3. download from the remote scan set, then cache to disk.
/// This lets the app run immediately and become fully offline as pages are visited.
@MainActor
final class PageStore: ObservableObject {
    static let shared = PageStore()

    private let memory = NSCache<NSNumber, NSImage>()
    private let remoteBase = "https://raw.githubusercontent.com/sufone/medina-mushaf/master/png-d150"
    private var tasks: [Int: Task<NSImage?, Never>] = [:]   // coalesce concurrent loads of the same page

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Mushaf/pages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() { memory.countLimit = 24 }

    func cached(_ page: Int) -> NSImage? {
        if let img = memory.object(forKey: NSNumber(value: page)) { return img }
        if let img = loadFromDisk(page) {
            memory.setObject(img, forKey: NSNumber(value: page))
            return img
        }
        return nil
    }

    private func bundledURL(_ page: Int) -> URL? {
        Bundle.main.url(forResource: "\(page)", withExtension: "png", subdirectory: "Pages")
    }

    private func loadFromDisk(_ page: Int) -> NSImage? {
        if let b = bundledURL(page), let img = NSImage(contentsOf: b) { return img }
        let url = cacheDir.appendingPathComponent("\(page).png")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Async-load a page, caching to disk. Concurrent callers for the same page
    /// share one download and all receive the result (no nil-on-race).
    func load(_ page: Int) async -> NSImage? {
        guard page >= 1 && page <= QuranData.totalPages else { return nil }
        if let img = cached(page) { return img }
        if let existing = tasks[page] { return await existing.value }

        let base = remoteBase
        let dir = cacheDir
        let task = Task { () -> NSImage? in
            if let img = self.cached(page) { return img }
            guard let url = URL(string: "\(base)/\(page).png") else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try? data.write(to: dir.appendingPathComponent("\(page).png"))
                guard let img = NSImage(data: data) else { return nil }
                self.memory.setObject(img, forKey: NSNumber(value: page))
                return img
            } catch {
                return nil
            }
        }
        tasks[page] = task
        let result = await task.value
        tasks[page] = nil
        return result
    }

    /// Warm the cache for nearby pages so turning feels instant.
    func prefetch(around page: Int) {
        for p in [page - 2, page - 1, page + 1, page + 2, page + 3, page + 4] where p >= 1 && p <= QuranData.totalPages {
            if cached(p) == nil {
                Task { _ = await load(p) }
            }
        }
    }
}
