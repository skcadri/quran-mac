import SwiftUI

enum NavUnit: String, CaseIterable, Identifiable {
    case surah = "Surah"
    case juz = "Juz"
    case hizb = "Hizb"
    case bookmarks = "★"
    var id: String { rawValue }
}

@MainActor
final class Reader: ObservableObject {
    @Published var currentPage: Int = {
        let p = UserDefaults.standard.integer(forKey: "lastPage")   // 0 if never saved
        return (1...QuranData.totalPages).contains(p) ? p : 1
    }()
    @Published var navMode: NavUnit = .juz
    @Published var showSidebar = true
    @Published var showControls = true
    @Published var immersive = false           // fullscreen, chrome hidden
    @Published var isDark = false
    @Published var bookmarks: Set<Int> = {
        let arr = UserDefaults.standard.array(forKey: "bookmarks") as? [Int] ?? []
        return Set(arr)
    }()

    var palette: Palette { isDark ? .dark : .light }

    // MARK: navigation
    /// Pages in the current spread, RTL: the odd (lower) page on the right, the even
    /// page on the left. So the first spread is (right: 1, left: 2), then (3,4), (5,6)…
    var spread: (left: Int?, right: Int) {
        let right = currentPage % 2 == 1 ? currentPage : currentPage - 1
        let left = right + 1 <= QuranData.totalPages ? right + 1 : nil
        return (left, right)
    }

    func go(to page: Int) {
        currentPage = max(1, min(QuranData.totalPages, page))
        UserDefaults.standard.set(currentPage, forKey: "lastPage")   // restore on next launch
        PageStore.shared.prefetch(around: currentPage)
    }

    func next() { go(to: min(QuranData.totalPages, spread.right + 2)) }
    func prev() { go(to: max(1, spread.right - 2)) }

    // MARK: scroll-wheel paging
    private var scrollAccum: CGFloat = 0
    /// Scroll down/forward (negative deltaY) advances, up goes back.
    /// Mouse wheel: one notch = one spread, instantly. Trackpad: step proportionally
    /// to the swipe distance so it tracks the finger. No time-based rate limiting.
    func handleScroll(deltaY: CGFloat, precise: Bool) {
        guard deltaY != 0 else { return }
        if precise {
            scrollAccum += deltaY
            let step: CGFloat = 40
            while abs(scrollAccum) >= step {
                if scrollAccum < 0 { next(); scrollAccum += step }
                else { prev(); scrollAccum -= step }
            }
        } else {
            scrollAccum = 0
            if deltaY < 0 { next() } else { prev() }
        }
    }

    // MARK: lookups
    func surah(forPage p: Int) -> Surah {
        var result = QuranData.surahs[0]
        for s in QuranData.surahs where s.startPage <= p { result = s }
        return result
    }
    func juz(forPage p: Int) -> Int {
        var j = 1
        for (i, start) in QuranData.juzStartPages.enumerated() where p >= start { j = i + 1 }
        return j
    }
    func hizb(forPage p: Int) -> Int {
        var h = 1
        for (i, start) in QuranData.hizbStartPages.enumerated() where p >= start { h = i + 1 }
        return h
    }
    /// 1-based rub-al-hizb (quarter) index for a page.
    func rub(forPage p: Int) -> Int {
        var r = 1
        for (i, start) in QuranData.rubStartPages.enumerated() where p >= start { r = i + 1 }
        return r
    }

    // MARK: bookmarks
    var isBookmarked: Bool { bookmarks.contains(currentPage) }
    func toggleBookmark() {
        if bookmarks.contains(currentPage) { bookmarks.remove(currentPage) }
        else { bookmarks.insert(currentPage) }
        UserDefaults.standard.set(Array(bookmarks), forKey: "bookmarks")
    }
}
