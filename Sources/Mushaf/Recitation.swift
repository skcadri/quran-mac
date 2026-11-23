import Foundation
@preconcurrency import AVFoundation
import AppKit

/// A word as tilawa's reference counts it (all 1-based). `word` indexes `Recitation.words(surah:ayah:)`.
struct WordRef: Codable, Hashable { let surah: Int; let ayah: Int; let word: Int }
struct AyahRef: Codable, Hashable { let surah: Int; let ayah: Int }

/// A confirmed memorization mistake (tilawa checks words only — never tajweed or pronunciation).
struct Mistake: Identifiable, Codable, Equatable {
    let id: String
    let errorClass: String
    let location: WordRef

    /// tilawa's own plain, non-judgmental wording (web/frontend/src/lib/explain.ts).
    static let wording: [String: (label: String, text: String)] = [
        "wrong_word": ("Different word", "It sounded like a different word here."),
        "omitted_word": ("Missed word", "This word seems to have been left out."),
        "added_word": ("Extra word", "An extra word seems to have been added here."),
        "skipped_passage": ("Skipped part", "Part of the passage seems to have been skipped from here."),
    ]
    var label: String { Self.wording[errorClass]?.label ?? "Check" }
    var text: String { Self.wording[errorClass]?.text ?? "" }
}

/// Recite mode: listens on the microphone, follows the reciter on the scans (current ayah outlined, pages
/// turn by themselves), reveals hidden ayahs in memorization mode as they're recited, and marks mistakes.
/// All recognition is on-device, by tilawa (`TilawaEngine`).
@MainActor
final class Recitation: ObservableObject {
    enum Phase: Equatable {
        case off
        case preparing(String, Double)   // label, 0…1
        case listening
        case finishing
        case failed(String)
    }
    enum Tracking: String { case acquiring, locked, ambiguous, lost }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var tracking: Tracking = .acquiring
    /// The most recently recited word, while following (cleared when the take ends).
    @Published private(set) var word: WordRef?
    @Published private(set) var mistakes: [Mistake] = []
    @Published private(set) var level: Double = 0   // mic level 0…1
    /// End-of-take summary; the scan keeps its mistake marks until this is dismissed.
    @Published private(set) var summary: Summary?
    /// Size of the pending one-time engine download, in MB (shown while downloading).
    @Published private(set) var downloadMB = 0

    struct Summary: Equatable { let recited: String; let mistakes: [Mistake] }

    weak var reader: Reader?

    private let engine = TilawaEngine()
    private var engineLoaded = false
    private var words: [String: [String]] = [:]   // "s:a" → Uthmani words, from tilawa's reference
    private var audio: AVAudioEngine?
    private var release: DispatchWorkItem?
    private var starting = false
    private var routeObserver: NSObjectProtocol?
    /// Keep the engine warm this long after a take (so "Recite again" is instant), then free its memory.
    private let idleRelease: TimeInterval = 300

    init() { engine.onMessage = { [weak self] in self?.handle($0) } }

    var isActive: Bool { phase != .off || summary != nil }
    /// Whether the scans should draw recitation marks (current ayah / mistakes).
    var marksVisible: Bool { word != nil || !mistakes.isEmpty }

    func isCurrent(surah: Int, ayah: Int) -> Bool { word?.surah == surah && word?.ayah == ayah }
    func hasMistake(surah: Int, ayah: Int) -> Bool {
        mistakes.contains { $0.location.surah == surah && $0.location.ayah == ayah }
    }
    func words(surah: Int, ayah: Int) -> [String] { words["\(surah):\(ayah)"] ?? [] }

    // MARK: start / stop

    func toggle() {
        switch phase {
        case .off, .failed: start()
        case .listening: stop()
        case .preparing: phase = .off   // a download in flight finishes in the background and stays cached
        case .finishing: break
        }
    }

    func start() {
        release?.cancel()
        summary = nil; mistakes = []; word = nil; tracking = .acquiring
        let downloading = TilawaEngine.missingBytes > 0
        downloadMB = TilawaEngine.missingBytes / 1_000_000
        phase = .preparing(downloading ? "Downloading" : "Loading", 0)
        guard !starting else { return }   // a cancelled start is still in flight; it picks this up
        starting = true
        Task {
            defer { starting = false }
            do {
                if downloading {
                    try await engine.ensureAssets { [weak self] p in self?.setProgress("Downloading", p) }
                }
                if words.isEmpty { words = await Self.loadWords() }
                if !engineLoaded {
                    setProgress("Loading", 0)
                    let backend = try await engine.load { [weak self] p in self?.setProgress("Loading", p) }
                    engineLoaded = true
                    Debug.log("engine loaded (\(backend))")
                }
                guard case .preparing = phase else { return }   // cancelled while preparing
                try await engine.start()
                if Debug.reciteFiles.isEmpty { try await startMicrophone() } else { feedFiles(Debug.reciteFiles) }
                phase = .listening
            } catch {
                stopMicrophone()
                if phase != .off { phase = .failed(error.localizedDescription) }   // stay quiet if cancelled
                scheduleRelease()
            }
        }
    }

    func stop() {
        guard phase == .listening else { return }
        stopMicrophone()
        phase = .finishing
        Task {
            let data = (try? await engine.stop()) ?? Data()
            struct Result: Decodable { let recited: [AyahRef]; let mistakes: [Mistake] }
            let result = try? JSONDecoder().decode(Result.self, from: data)
            let final = (result?.mistakes ?? mistakes).filter { Mistake.wording[$0.errorClass] != nil }
            mistakes = final
            word = nil
            summary = Summary(recited: Self.describe(result?.recited ?? []), mistakes: final)
            phase = .off
            scheduleRelease()
            Debug.log("summary: \(summary!.recited) — \(final.map { "\($0.errorClass)@\($0.location.surah):\($0.location.ayah):\($0.location.word)" })")
        }
    }

    func dismissSummary() { summary = nil; mistakes = [] }

    private func scheduleRelease() {
        release?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .off else { return }
            self.engine.unload()
            self.engineLoaded = false
            Debug.log("engine released")
        }
        release = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleRelease, execute: work)
    }

    /// Jump to the page holding a mistake.
    func show(_ m: Mistake) {
        let count = words(surah: m.location.surah, ayah: m.location.ayah).count
        if let page = MushafData.shared.page(surah: m.location.surah, ayah: m.location.ayah, word: m.location.word, of: count) {
            reader?.go(to: page)
        }
    }

    private func setProgress(_ label: String, _ p: Double) {
        if case .preparing = phase { phase = .preparing(label, p) }
    }

    // MARK: engine events

    private func handle(_ m: BridgeMessage) {
        switch m.type {
        case "position":
            tracking = Tracking(rawValue: m.state ?? "") ?? .acquiring
            // Only a confident lock moves anything: ambiguous candidates would flicker between similar ayahs.
            if tracking == .locked, let w = m.word { advance(to: w) }
        case "checker":
            guard let id = m.id, let cls = m.errorClass, let loc = m.location, Mistake.wording[cls] != nil else { return }
            if m.state == "confirmed", !mistakes.contains(where: { $0.id == id }) {
                mistakes.append(Mistake(id: id, errorClass: cls, location: loc))
                Debug.log("mistake \(cls) at \(loc.surah):\(loc.ayah):\(loc.word)")
            } else if m.state == "resolved" {
                mistakes.removeAll { $0.id == id }   // the reader corrected themselves
            }
        case "error", "terminated":
            Debug.log("engine \(m.type): \(m.message ?? "")")
            if m.type == "terminated" { engineLoaded = false }
            guard phase == .listening else { return }
            stopMicrophone()
            word = nil
            phase = .failed("Listening stopped unexpectedly. \(m.message ?? "")")
        default: break
        }
    }

    private func advance(to w: WordRef) {
        if let prev = word, (prev.surah, prev.ayah) != (w.surah, w.ayah),
           (w.surah, w.ayah) > (prev.surah, prev.ayah) {
            finished(prev.surah, prev.ayah)   // moved on to a later ayah
        }
        if word?.surah != w.surah || word?.ayah != w.ayah { Debug.log("at \(w.surah):\(w.ayah)") }
        word = w
        let count = words(surah: w.surah, ayah: w.ayah).count
        if count > 0, w.word >= count { finished(w.surah, w.ayah) }
        // Follow the reciter: turn to the spread holding this word.
        if let reader, let page = MushafData.shared.page(surah: w.surah, ayah: w.ayah, word: w.word, of: count),
           page != reader.spread.right, page != reader.spread.left {
            reader.go(to: page)
        }
    }

    /// An ayah has been recited through: in memorization mode, uncover it.
    private func finished(_ surah: Int, _ ayah: Int) {
        if reader?.memorizeMode == true { reader?.reveal(surah: surah, ayah: ayah) }
    }

    // MARK: microphone

    private func startMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw MicError.denied }
        default: throw MicError.denied
        }
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { throw MicError.unavailable }
        converter.downmix = true
        // Raw input: no voice processing (tilawa wants echo cancellation / noise suppression / AGC off).
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let samples = Self.convert(buffer, with: converter, to: outFormat) else { return }
            let level = Self.level(samples)
            DispatchQueue.main.async {
                guard let self, self.audio != nil else { return }   // the mic was stopped meanwhile
                self.engine.push(samples)
                self.level = level
            }
        }
        try audio.start()
        self.audio = audio
        // A new input device (AirPods, a USB mic) stops the engine: start over on the new route.
        routeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .listening else { return }
                self.stopMicrophone()
                Task { try? await self.startMicrophone() }
            }
        }
    }

    private func stopMicrophone() {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        audio?.inputNode.removeTap(onBus: 0)
        audio?.stop()
        audio = nil
        level = 0
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> [Float]? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData, out.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// RMS → 0…1 over −60…−10 dBFS, for the level dot.
    nonisolated private static func level(_ s: [Float]) -> Double {
        guard !s.isEmpty else { return 0 }
        let rms = sqrt(s.reduce(0) { $0 + Double($1 * $1) } / Double(s.count))
        let db = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (db + 60) / 50))
    }

    enum MicError: LocalizedError {
        case denied, unavailable
        var errorDescription: String? {
            switch self {
            case .denied: return "Microphone access is off. Allow Mushaf in System Settings › Privacy & Security › Microphone."
            case .unavailable: return "No microphone found."
            }
        }
    }

    // MARK: test input (MUSHAF_RECITE_FILES) — lets an agent without a microphone drive a real take

    private func feedFiles(_ paths: [String]) {
        Task {
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else { return }
            for path in paths {
                guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil,
                      let converter = AVAudioConverter(from: file.processingFormat, to: format),
                      let samples = Self.convert(buffer, with: converter, to: format) else {
                    Debug.log("can't read \(path)"); continue
                }
                Debug.log("feeding \(path) (\(samples.count / 16) ms)")
                for start in stride(from: 0, to: samples.count, by: 16_000) {
                    engine.push(Array(samples[start..<min(start + 16_000, samples.count)]))
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            stop()
        }
    }

    // MARK: text

    /// tilawa's reference words (ref-v2.json, already on disk once the engine is downloaded).
    nonisolated private static func loadWords() async -> [String: [String]] {
        await Task.detached {
            struct Ref: Decodable { struct A: Decodable { let s: Int; let a: Int; let w: [String] }; let ayahs: [A] }
            guard let data = try? Data(contentsOf: TilawaEngine.localURL("reference/ref-v2.json")),
                  let ref = try? JSONDecoder().decode(Ref.self, from: data) else { return [:] }
            return Dictionary(uniqueKeysWithValues: ref.ayahs.map { ("\($0.s):\($0.a)", $0.w) })
        }.value
    }

    /// "Al-Mulk 67:1–5, Al-Qalam 68:1" — consecutive ayahs collapsed into runs.
    private static func describe(_ recited: [AyahRef]) -> String {
        var runs: [String] = []
        var i = 0
        while i < recited.count {
            let first = recited[i]
            var last = first
            while i + 1 < recited.count, recited[i + 1].surah == first.surah, recited[i + 1].ayah == last.ayah + 1 {
                i += 1; last = recited[i]
            }
            i += 1
            let name = QuranData.surahs.indices.contains(first.surah - 1) ? QuranData.surahs[first.surah - 1].english : "Surah \(first.surah)"
            runs.append("\(name) \(first.surah):\(first.ayah)" + (last.ayah != first.ayah ? "–\(last.ayah)" : ""))
        }
        return runs.joined(separator: ", ")
    }
}

/// Environment hooks for testing without a microphone or screen. See CLAUDE.md › Recite mode.
enum Debug {
    static let env = ProcessInfo.processInfo.environment
    /// Colon-separated audio files fed to the engine instead of the mic; recitation starts at launch
    /// (in memorization mode too if MUSHAF_MEMORIZE is set).
    static let reciteFiles: [String] = (env["MUSHAF_RECITE_FILES"] ?? "").split(separator: ":").map(String.init)
    static let verbose = env["MUSHAF_DEBUG"] != nil || !reciteFiles.isEmpty
    static let launch = Date()
    static func log(_ s: String) {
        guard verbose else { return }
        print(String(format: "[recite %6.2fs] ", Date().timeIntervalSince(launch)) + s); fflush(stdout)
    }

    /// MUSHAF_SNAPSHOT=/tmp/shot → writes the window's own content to /tmp/shot-<n>.png every 2 s
    /// (no Screen Recording permission needed — it's our own view hierarchy).
    @MainActor static func startSnapshots(window: NSWindow) {
        guard let prefix = env["MUSHAF_SNAPSHOT"] else { return }
        var n = 0
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                n += 1
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(n).png"))
            }
        }
    }
}
