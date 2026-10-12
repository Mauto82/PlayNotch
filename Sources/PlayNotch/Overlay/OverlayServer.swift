import AppKit
import Foundation
import Network

/// Tiny localhost-only HTTP server that exposes the current track to OBS.
///
/// Add `http://127.0.0.1:8973/` as a Browser Source in OBS. Routes:
///   - `/`                 → the overlay page (HTML, polls the JSON below)
///   - `/now-playing.json` → current track snapshot
///   - `/artwork`          → current artwork as PNG (404 when none)
final class OverlayServer {
    static let shared = OverlayServer()
    static let port: UInt16 = 8973

    static var url: String { "http://127.0.0.1:\(port)/" }

    private let queue = DispatchQueue(label: "PlayNotch.OverlayServer")
    private var listener: NWListener?

    // State shared between the main thread (writer) and the server queue.
    private let lock = NSLock()
    private var json = Data("{\"playing\":false}".utf8)
    private var artworkPNG: Data?
    // Seeded from launch time so a page left open across app restarts never
    // mistakes a new cover for the one it already cached.
    private var artworkVersion = Int(Date().timeIntervalSince1970)

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("PlayNotch overlay server failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - State

    /// Publish the latest snapshot. `position` is the interpolated playback
    /// position at call time; the page extrapolates from `updatedAt`.
    func update(nowPlaying: NowPlaying?, position: Double, accent: NSColor?) {
        var payload: [String: Any] = ["playing": false]
        if let np = nowPlaying {
            lock.lock()
            let version = artworkVersion
            let hasArt = artworkPNG != nil
            lock.unlock()
            payload = [
                "playing": np.state == .playing,
                "active": true,
                "app": np.app.rawValue,
                "title": np.title,
                "artist": np.artist,
                "album": np.album,
                "duration": np.duration ?? 0,
                "position": position,
                "updatedAt": Date().timeIntervalSince1970 * 1000,
                "artwork": hasArt ? "/artwork?v=\(version)" : NSNull(),
                "accent": accent.flatMap(Self.hex) ?? NSNull(),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        lock.lock()
        json = data
        lock.unlock()
    }

    func updateArtwork(_ image: NSImage?) {
        let png = image.flatMap(Self.pngData)
        lock.lock()
        artworkPNG = png
        artworkVersion += 1
        lock.unlock()
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    // MARK: - HTTP

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
            let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
            self.respond(conn, path: path)
        }
    }

    private func respond(_ conn: NWConnection, path: String) {
        switch path {
        case "/", "/index.html":
            send(conn, status: "200 OK", type: "text/html; charset=utf-8", body: Data(OverlayPage.html.utf8))
        case "/now-playing.json":
            lock.lock(); let body = json; lock.unlock()
            send(conn, status: "200 OK", type: "application/json", body: body)
        case "/artwork":
            lock.lock(); let body = artworkPNG; lock.unlock()
            if let body {
                send(conn, status: "200 OK", type: "image/png", body: body)
            } else {
                send(conn, status: "404 Not Found", type: "text/plain", body: Data("no artwork".utf8))
            }
        default:
            send(conn, status: "404 Not Found", type: "text/plain", body: Data("not found".utf8))
        }
    }

    private func send(_ conn: NWConnection, status: String, type: String, body: Data) {
        let head = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(type)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}

/// Ready-made overlay URLs offered in the menu bar, one per layout.
struct OverlayPreset {
    let title: String
    let query: String

    var url: String { OverlayServer.url + query }

    static let all: [OverlayPreset] = [
        OverlayPreset(title: "Bar — lower third (700×200)", query: ""),
        OverlayPreset(title: "Bar, cover on right (700×200)", query: "?align=right"),
        OverlayPreset(title: "Pill — corner strip (600×90)", query: "?layout=pill"),
        OverlayPreset(title: "Square — side panel (300×300)", query: "?layout=square"),
        OverlayPreset(title: "Text only, transparent (600×120)", query: "?layout=text"),
        OverlayPreset(title: "Bar, transparent (700×200)", query: "?bg=0"),
    ]
}
