import Foundation

/// Finds cover art on the public iTunes Search API.
///
/// Music's scripting bridge exposes no artwork for catalog tracks streamed from
/// Apple Music ("URL track"s that aren't in the library), so we look the album
/// up instead. Lookups are async and cached: `url(...)` returns nil until the
/// answer arrives, and the next poll picks it up.
final class ArtworkLookup {
    static let shared = ArtworkLookup()

    private let lock = NSLock()
    /// key → resolved URL, or nil when the lookup found nothing.
    private var cache: [String: URL?] = [:]
    private var inFlight: Set<String> = []

    func url(artist: String, album: String, title: String) -> URL? {
        guard !artist.isEmpty else { return nil }
        let key = "\(artist)|\(album)|\(album.isEmpty ? title : "")".lowercased()

        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        if inFlight.insert(key).inserted {
            fetch(key: key, artist: artist, album: album, title: title)
        }
        return nil
    }

    private func fetch(key: String, artist: String, album: String, title: String) {
        // Without an album (radio, some streams) search the song instead.
        let byAlbum = !album.isEmpty
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(byAlbum ? album : title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: byAlbum ? "album" : "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let requestURL = comps.url else { return }

        URLSession.shared.dataTask(with: requestURL) { [weak self] data, _, error in
            guard let self else { return }
            var found: URL?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                found = Self.pick(results, artist: artist, name: byAlbum ? album : title, nameKey: byAlbum ? "collectionName" : "trackName")
            }
            self.lock.lock()
            self.inFlight.remove(key)
            // Don't cache network failures, so a later poll retries.
            if error == nil { self.cache[key] = found }
            self.lock.unlock()
        }.resume()
    }

    /// Best match: same name and artist, then same artist, then the top hit.
    private static func pick(_ results: [[String: Any]], artist: String, name: String, nameKey: String) -> URL? {
        func norm(_ s: Any?) -> String { ((s as? String) ?? "").lowercased() }
        let a = artist.lowercased(), n = name.lowercased()
        let best = results.first { norm($0[nameKey]) == n && norm($0["artistName"]) == a }
            ?? results.first { norm($0["artistName"]) == a }
            ?? results.first
        guard let small = best?["artworkUrl100"] as? String else { return nil }
        // The API hands out 100px thumbs; the CDN serves any size on request.
        return URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }
}
