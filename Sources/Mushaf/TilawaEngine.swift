import Foundation
import WebKit
import CryptoKit

/// Hosts tilawa's recitation engine (`@tilawa/core`, github.com/yazinsai/tilawa) in a hidden WKWebView.
///
/// Split of responsibilities:
///   - Swift: downloads + verifies the engine assets once (pinned, immutable tilawa.dev paths), keeps them on
///     disk, serves them to the web view through the `mushaf://` scheme, owns the microphone and all UI.
///   - JS (`Resources/tilawa-bridge.js`, built from `tools/tilawa-bridge`): runs the unmodified engine
///     (onnxruntime-web, WASM) and posts position/checker events back.
@MainActor
final class TilawaEngine: NSObject {
    struct Asset: Sendable { let path: String; let bytes: Int; let sha256: String }

    /// Immutable paths under https://tilawa.dev/v1/ (see tilawa's docs/self-hosting.md). Bump together with
    /// the `@tilawa/core` / `onnxruntime-web` versions in tools/tilawa-bridge/package.json.
    nonisolated static let assets: [Asset] = [
        Asset(path: "models/spliced-clean/1-int8/model.onnx", bytes: 67_759_744,
              sha256: "714e98addee73b1b8781ad7d99b6d3c745acd9116638baf4e12891f53a15af1b"),
        Asset(path: "reference/ref-v2.json", bytes: 4_749_281,
              sha256: "f236384ea91e81ad554ba2777bc4073c3ff41e34120343a8a474571c577b7727"),
        Asset(path: "runtime/ort/1.30.0/ort-wasm-simd-threaded.jsep.mjs", bytes: 46_851,
              sha256: "709853412fd1ffc34247af1e73569227b5b79629c5ca3f59cc39cf7e500e4947"),
        Asset(path: "runtime/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm", bytes: 28_312_028,
              sha256: "3ad23231b5bd6d9dda55a7f84606315e0bf35b6750c28ee993c987c54cacab0f"),
    ]
    nonisolated static let remoteBase = URL(string: "https://tilawa.dev/v1/")!
    nonisolated static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Mushaf/tilawa/v1", isDirectory: true)
    }()
    nonisolated static func localURL(_ path: String) -> URL { cacheDir.appendingPathComponent(path) }

    /// Bytes still to download before the engine can start (0 once everything is cached).
    static var missingBytes: Int {
        assets.filter { !FileManager.default.fileExists(atPath: localURL($0.path).path) }.reduce(0) { $0 + $1.bytes }
    }

    /// Every message the bridge posts (`type` + payload), decoded loosely.
    var onMessage: ((BridgeMessage) -> Void)?

    private var webView: WKWebView?
    private var bootWaiter: CheckedContinuation<Void, Never>?
    private var booted = false

    // MARK: assets

    /// Download whatever is missing, verifying size + sha256. `progress` gets 0…1 over all missing bytes.
    func ensureAssets(progress: @escaping (Double) -> Void) async throws {
        let missing = Self.assets.filter { !FileManager.default.fileExists(atPath: Self.localURL($0.path).path) }
        let total = Double(missing.reduce(0) { $0 + $1.bytes })
        var done = 0.0
        for asset in missing {
            let base = done
            let tmp = try await download(Self.remoteBase.appendingPathComponent(asset.path)) { fraction in
                progress(total > 0 ? (base + fraction * Double(asset.bytes)) / total : 1)
            }
            let ok = await Task.detached { () -> Bool in
                guard let data = try? Data(contentsOf: tmp, options: .alwaysMapped), data.count == asset.bytes else { return false }
                return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == asset.sha256
            }.value
            guard ok else {
                try? FileManager.default.removeItem(at: tmp)
                throw EngineError.integrity(asset.path)
            }
            let dest = Self.localURL(asset.path)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            done += Double(asset.bytes)
        }
        progress(1)
    }

    private func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        return try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                if let error { return cont.resume(throwing: error) }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return cont.resume(throwing: EngineError.download(url.lastPathComponent))
                }
                // The system deletes `tmp` when this handler returns: move it somewhere we own first.
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do { try FileManager.default.moveItem(at: tmp, to: keep); cont.resume(returning: keep) }
                catch { cont.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in
                let f = p.fractionCompleted
                DispatchQueue.main.async { progress(f) }
            }
            task.resume()
        }
    }

    // MARK: engine

    /// Create the web view (once) and load the model. Returns the ONNX backend name.
    func load(progress: @escaping (Double) -> Void) async throws -> String {
        if webView == nil { await boot() }
        progressHandler = progress
        defer { progressHandler = nil }
        let result = try await call("return (await tilawaBridge.load(base)).backend", ["base": "mushaf://localhost/v1/"])
        return result as? String ?? "?"
    }
    private var progressHandler: ((Double) -> Void)?

    func start() async throws { _ = try await call("tilawaBridge.start()") }

    /// Drop the web view; its WebContent process (model + engine, several hundred MB) goes with it.
    /// The next `load` boots a fresh one from the disk cache in about a second.
    func unload() {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        booted = false
    }

    /// Mono 16 kHz samples. Fire-and-forget: the engine queues pushes in call order.
    func push(_ samples: [Float]) {
        guard let webView else { return }
        let b64 = samples.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
        webView.callAsyncJavaScript("tilawaBridge.push(b)", arguments: ["b": b64], in: nil, in: .page, completionHandler: nil)
    }

    /// Ends the take: drains the model, decides open mistakes, returns the take's summary as JSON data.
    func stop() async throws -> Data {
        let json = try await call("return JSON.stringify(await tilawaBridge.stop())")
        return (json as? String ?? "{}").data(using: .utf8) ?? Data()
    }

    private func call(_ js: String, _ args: [String: Any] = [:]) async throws -> Any? {
        guard let webView else { throw EngineError.notLoaded }
        return try await webView.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .page)
    }

    private func boot() async {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(), forURLScheme: "mushaf")
        let relay = MessageRelay { [weak self] body in self?.received(body) }
        config.userContentController.add(relay, name: "tilawa")
        config.userContentController.add(relay, name: "log")
        config.userContentController.addUserScript(WKUserScript(source: """
            for (const k of ["log", "warn", "error"]) {
              const orig = console[k];
              console[k] = (...a) => { try { webkit.messageHandlers.log.postMessage(k + ": " + a.map(String).join(" ")); } catch {} orig(...a); };
            }
            addEventListener("error", (e) => webkit.messageHandlers.log.postMessage("error: " + e.message));
            addEventListener("unhandledrejection", (e) => webkit.messageHandlers.log.postMessage("error: " + (e.reason?.message ?? e.reason)));
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        view.isInspectable = true
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: URL(string: "mushaf://localhost/app/index.html")!))
        if !booted { await withCheckedContinuation { bootWaiter = $0 } }
    }

    private func received(_ body: Any) {
        if let line = body as? String {   // console relay
            if !line.hasPrefix("log:") || Debug.verbose { NSLog("[tilawa] %@", line) }
            return
        }
        guard let dict = body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let msg = try? JSONDecoder().decode(BridgeMessage.self, from: data) else { return }
        switch msg.type {
        case "boot":
            booted = true
            bootWaiter?.resume(); bootWaiter = nil
        case "progress":
            progressHandler?(msg.fraction ?? 0)
        default:
            onMessage?(msg)
        }
    }

    enum EngineError: LocalizedError {
        case notLoaded, download(String), integrity(String)
        var errorDescription: String? {
            switch self {
            case .notLoaded: return "The recitation engine isn't loaded."
            case .download(let f): return "Couldn't download \(f). Check your connection and try again."
            case .integrity(let f): return "\(f) didn't download correctly. Try again."
            }
        }
    }
}

extension TilawaEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[tilawa] page failed: %@", error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[tilawa] page failed: %@", error.localizedDescription)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[tilawa] web content process terminated")
        unload()
        onMessage?(BridgeMessage(type: "terminated"))
    }
}

/// One message from the bridge. Position: `state` + `word`. Checker: `id`, `state`, `errorClass`, `location`.
struct BridgeMessage: Decodable {
    let type: String
    var state: String?
    var word: WordRef?
    var id: String?
    var errorClass: String?
    var location: WordRef?
    var message: String?
    var fraction: Double?
    var stage: String?
}

/// Serves `mushaf://localhost/app/*` (the bridge page) and `mushaf://localhost/v1/*` (cached engine assets).
private final class SchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path
        Debug.log("serve \(path)")
        var data: Data?
        if path == "/app/index.html" {
            data = Data(#"<!doctype html><meta charset="utf-8"><script type="module" src="/app/tilawa-bridge.js"></script>"#.utf8)
        } else if path == "/app/tilawa-bridge.js" {
            data = Bundle.resources.url(forResource: "tilawa-bridge", withExtension: "js").flatMap { try? Data(contentsOf: $0) }
        } else if path.hasPrefix("/v1/") {
            let rel = String(path.dropFirst(4))
            if TilawaEngine.assets.contains(where: { $0.path == rel }) {
                data = try? Data(contentsOf: TilawaEngine.localURL(rel), options: .alwaysMapped)
            }
        }
        guard let data else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!)
            task.didFinish()
            return
        }
        let type: String = switch url.pathExtension {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "wasm": "application/wasm"
        case "json": "application/json"
        default: "application/octet-stream"
        }
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": type, "Content-Length": "\(data.count)",
                                                       "Access-Control-Allow-Origin": "*"])!)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    let handler: (Any) -> Void
    init(_ handler: @escaping (Any) -> Void) { self.handler = handler }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        DispatchQueue.main.async { self.handler(body) }
    }
}
