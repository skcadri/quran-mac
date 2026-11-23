import SwiftUI

/// Floating card over the spread while reciting: engine status, where you are, the words of the current ayah
/// as you say them, and — once the take ends — a summary of what's worth a second look.
struct RecitationHUD: View {
    @EnvironmentObject var recitation: Recitation
    @EnvironmentObject var reader: Reader
    private var p: Palette { reader.palette }

    var body: some View {
        Group {
            if let s = recitation.summary { summaryCard(s) }
            else if recitation.phase != .off { liveCard }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: live

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                levelDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(p.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                if !recitation.mistakes.isEmpty {
                    Text(recitation.mistakes.count == 1 ? "1 to review" : "\(recitation.mistakes.count) to review")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(p.mistake)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(p.mistake.opacity(0.12)))
                }
                actionButton
            }
            if case .preparing(_, let fraction) = recitation.phase {
                ProgressView(value: fraction).progressViewStyle(.linear).tint(p.accent).controlSize(.small)
            }
            if let w = recitation.word { wordStrip(w) }
        }
        .modifier(Card(p: p))
    }

    private var title: String {
        switch recitation.phase {
        case .preparing("Downloading", _): return "Getting the recitation engine"
        case .preparing: return "Getting ready…"
        case .finishing: return "Finishing…"
        case .failed: return "Couldn't start reciting"
        case .off: return ""
        case .listening:
            guard let w = recitation.word else { return "Listening" }
            return "\(surahName(w.surah)) · \(w.surah):\(w.ayah)"
        }
    }

    private var subtitle: String {
        switch recitation.phase {
        case .preparing("Downloading", let f):
            return "One-time download, \(Int(f * 100))% of \(max(recitation.downloadMB, 1)) MB. Listening happens on this Mac."
        case .preparing: return "Loading the listening model"
        case .finishing: return "Checking the last words"
        case .failed(let message): return message
        case .off: return ""
        case .listening:
            switch recitation.tracking {
            case .ambiguous: return "A few places match. Keep going."
            case .lost: return "Lost your place. Keep reciting and it'll find it again."
            case .acquiring: return recitation.word == nil ? "Start reciting. Mushaf will find your place." : "Following along"
            case .locked: return "Following along"
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch recitation.phase {
        case .failed:
            Button("Try again") { recitation.start() }.controlSize(.small)
            closeButton { recitation.toggle(); recitation.dismissSummary() }
        case .finishing:
            ProgressView().controlSize(.small)
        default:
            Button { recitation.toggle() } label: {
                Image(systemName: "stop.fill").font(.system(size: 11))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
                    .background(Circle().fill(p.accent))
            }
            .buttonStyle(.plain)
            .help(recitation.phase == .listening ? "Stop (R)" : "Cancel")
        }
    }

    /// Pulses with the mic level while listening.
    private var levelDot: some View {
        ZStack {
            Circle().fill(p.accent.opacity(0.18)).frame(width: 26, height: 26)
                .scaleEffect(recitation.phase == .listening ? 0.7 + 0.6 * recitation.level : 0.7)
                .animation(.easeOut(duration: 0.12), value: recitation.level)
            Image(systemName: "mic.fill").font(.system(size: 12)).foregroundStyle(p.accent)
        }
        .frame(width: 30, height: 30)
    }

    /// The current ayah's words up to the one just recited (never ahead — this is a memorization aid).
    /// Recited words are soft, the current one sits in a pill, mistakes get a maroon underline.
    private func wordStrip(_ w: WordRef) -> some View {
        let words = recitation.words(surah: w.surah, ayah: w.ayah)
        let shown = 10
        let upTo = min(w.word, words.count)
        let from = max(0, upTo - shown)
        let flagged = Set(recitation.mistakes.filter { $0.location.surah == w.surah && $0.location.ayah == w.ayah }.map { $0.location.word })
        var text = AttributedString(from > 0 ? "… " : "")
        for i in from..<upTo {
            var word = AttributedString(words[i])
            if i == upTo - 1 {
                word.foregroundColor = p.accent
                word.backgroundColor = p.accentSoft
            } else {
                word.foregroundColor = p.inkSoft
            }
            if flagged.contains(i + 1) {
                word.foregroundColor = p.mistake
                word.underlineStyle = .init(pattern: .solid, color: p.mistake)
            }
            text += word
            text += AttributedString(" ")
        }
        if upTo == words.count, !words.isEmpty { text += AttributedString("۝\(Self.arabicDigits(w.ayah))") }
        return Text(text)
            .font(.custom("Geeza Pro", size: 21))
            .lineSpacing(4)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)   // Arabic reads from the right edge
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(nil, value: w)
    }

    // MARK: summary

    private func summaryCard(_ s: Recitation.Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: s.mistakes.isEmpty ? "checkmark.seal.fill" : "text.magnifyingglass")
                    .font(.system(size: 16)).foregroundStyle(s.mistakes.isEmpty ? p.accent : p.mistake)
                Text(headline(s)).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
                Spacer()
                Button("Recite again") { recitation.start() }.controlSize(.small)
                closeButton { recitation.dismissSummary() }
            }
            Text(s.recited.isEmpty
                 ? "Mushaf didn't find your place this time. Try a little longer, a little louder, or closer to the microphone."
                 : "You recited \(s.recited).")
                .font(.system(size: 12)).foregroundStyle(p.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !s.mistakes.isEmpty {
                ScrollView {
                    VStack(spacing: 2) { ForEach(s.mistakes) { mistakeRow($0) } }
                }
                .frame(maxHeight: min(CGFloat(s.mistakes.count) * 52, 220))
            }
            Text("Listening by Tilawa (tilawa.dev) · on-device · checks words, not tajweed")
                .font(.system(size: 9.5)).foregroundStyle(p.inkFaint)
        }
        .modifier(Card(p: p))
    }

    private func headline(_ s: Recitation.Summary) -> String {
        switch s.mistakes.count {
        case 0: return s.recited.isEmpty ? "Nothing heard yet" : "Nothing to look at again"
        case 1: return "One word is worth a second look"
        default: return "\(s.mistakes.count) words are worth a second look"
        }
    }

    private func mistakeRow(_ m: Mistake) -> some View {
        let words = recitation.words(surah: m.location.surah, ayah: m.location.ayah)
        let word = words.indices.contains(m.location.word - 1) ? words[m.location.word - 1] : ""
        return Button { recitation.show(m) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.mistake)
                        Text("\(surahName(m.location.surah)) \(m.location.surah):\(m.location.ayah)")
                            .font(.system(size: 11)).foregroundStyle(p.inkSoft)
                    }
                    Text(m.text).font(.system(size: 10.5)).foregroundStyle(p.inkFaint)
                }
                Spacer(minLength: 8)
                Text(word).font(.custom("Geeza Pro", size: 19)).foregroundStyle(p.ink)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(p.rowHover.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .help("Show on the page")
    }

    // MARK: bits

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22).foregroundStyle(p.inkSoft)
                .background(Circle().fill(p.chip))
        }
        .buttonStyle(.plain)
    }

    private func surahName(_ n: Int) -> String {
        QuranData.surahs.indices.contains(n - 1) ? QuranData.surahs[n - 1].english : "Surah \(n)"
    }

    static func arabicDigits(_ n: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(n).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    private struct Card: ViewModifier {
        let p: Palette
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(width: 480)
                .background(RoundedRectangle(cornerRadius: 16).fill(p.window))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(p.sidebarLine, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        }
    }
}
