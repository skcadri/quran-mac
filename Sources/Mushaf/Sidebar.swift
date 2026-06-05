import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var reader: Reader
    @State private var query = ""

    private var p: Palette { reader.palette }

    var body: some View {
        VStack(spacing: 0) {
            // search
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(p.inkFaint)
                TextField("Search surah…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(p.ink)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.window))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.sidebarLine, lineWidth: 0.5))
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)

            // mode segmented control
            Picker("", selection: $reader.navMode) {
                ForEach(NavUnit.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider().overlay(p.sidebarLine)

            if reader.navMode == .bookmarks && reader.bookmarks.isEmpty {
                emptyBookmarks
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { row in
                                SidebarRow(row: row, active: row.isActive(reader))
                                    .id(row.id)
                                    .onTapGesture { reader.go(to: row.page) }
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .onChange(of: reader.currentPage) { _, _ in
                        if let active = rows.first(where: { $0.isActive(reader) }) {
                            withAnimation { proxy.scrollTo(active.id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(width: 298)
        .background(p.sidebar)
        .overlay(Rectangle().fill(p.sidebarLine).frame(width: 0.5), alignment: .trailing)
    }

    private var emptyBookmarks: some View {
        VStack(spacing: 8) {
            Image(systemName: "star").font(.system(size: 26)).foregroundStyle(p.inkFaint)
            Text("No bookmarks yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.inkSoft)
            Text("Tap the ☆ in the bottom bar to save the page you're reading.")
                .font(.system(size: 11)).foregroundStyle(p.inkFaint)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rows: [SidebarItem] {
        switch reader.navMode {
        case .surah:
            return QuranData.surahs
                .filter { query.isEmpty
                    || $0.english.localizedCaseInsensitiveContains(query)
                    || $0.meaning.localizedCaseInsensitiveContains(query)
                    || $0.arabic.contains(query)
                    || String($0.id) == query }
                .map { s in SidebarItem(id: "s\(s.id)", number: s.id, title: s.english,
                                   subtitle: "\(s.meaning) · \(s.ayahCount) ayah · \(s.place)",
                                   arabic: s.arabic, page: s.startPage,
                                   isActive: { r in r.surah(forPage: r.currentPage).id == s.id }) }
        case .juz:
            return (1...30).map { j in
                let page = QuranData.juzStartPages[j - 1]
                let s = QuranData.surahs.last { $0.startPage <= page } ?? QuranData.surahs[0]
                return SidebarItem(id: "j\(j)", number: j, title: "Juz \(j)",
                                   subtitle: "starts p.\(page) · \(s.english)",
                                   arabic: "", page: page,
                                   isActive: { r in r.juz(forPage: r.currentPage) == j })
            }
        case .hizb:
            // 240 quarters (rub al-hizb): each hizb is 4 — start, ¼, ½, ¾.
            let marks = ["", "¼", "½", "¾"]
            return (1...240).map { r in
                let page = QuranData.rubStartPages[r - 1]
                let hizb = (r - 1) / 4 + 1
                let quarter = (r - 1) % 4
                let s = QuranData.surahs.last { $0.startPage <= page } ?? QuranData.surahs[0]
                let title = quarter == 0 ? "Hizb \(hizb)" : "Hizb \(hizb) · \(marks[quarter])"
                return SidebarItem(id: "r\(r)", number: hizb, title: title,
                                   subtitle: "p.\(page) · \(s.english)",
                                   arabic: marks[quarter], page: page,
                                   isActive: { rd in rd.rub(forPage: rd.currentPage) == r })
            }
        case .bookmarks:
            return reader.bookmarks.sorted().map { pg in
                let s = QuranData.surahs.last { $0.startPage <= pg } ?? QuranData.surahs[0]
                return SidebarItem(id: "b\(pg)", number: pg, title: "Page \(pg)",
                                   subtitle: "\(s.english) · Juz \(reader.juz(forPage: pg))",
                                   arabic: s.arabic, page: pg,
                                   isActive: { rd in rd.currentPage == pg })
            }
        }
    }
}

struct SidebarItem: Identifiable {
    let id: String
    let number: Int
    let title: String
    let subtitle: String
    let arabic: String
    let page: Int
    let isActive: (Reader) -> Bool
    func isActive(_ r: Reader) -> Bool { isActive(r) }
}

struct SidebarRow: View {
    let row: SidebarItem
    let active: Bool
    @EnvironmentObject var reader: Reader
    @State private var hovering = false
    private var p: Palette { reader.palette }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Image(systemName: "seal")
                    .font(.system(size: 27, weight: .ultraLight))
                    .foregroundStyle(p.gold.opacity(active ? 0.9 : 0.5))
                Text("\(row.number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(active ? p.accent : p.ink)
                Text(row.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(p.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !row.arabic.isEmpty {
                Text(row.arabic)
                    .font(.custom("Geeza Pro", size: 18))
                    .foregroundStyle(active ? p.accent : p.inkSoft)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(active ? p.accentSoft : (hovering ? p.rowHover : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
