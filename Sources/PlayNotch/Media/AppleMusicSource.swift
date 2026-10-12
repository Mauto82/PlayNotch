import Foundation

/// Apple Music (Music.app) via AppleScript. Has a rich scripting dictionary,
/// including raw artwork data.
final class AppleMusicSource: MediaSource {
    let app: MediaApp = .appleMusic
    private let bundleID = "com.apple.Music"

    func isRunning() -> Bool {
        AppleScriptRunner.isRunning(bundleID: bundleID)
    }

    func fetch() -> NowPlaying? {
        guard isRunning() else { return nil }

        // Pull the core fields in one round-trip, tab-separated.
        let script = """
        tell application "Music"
            if it is not running then return ""
            try
                set pstate to player state as string
            on error
                return ""
            end try
            set theVol to (sound volume as string)
            try
                set theShuf to (shuffle enabled as string)
            on error
                set theShuf to "false"
            end try
            try
                set theRep to (song repeat as string)
            on error
                set theRep to "off"
            end try
            if player position is missing value then
                set pos to "0"
            else
                set pos to (player position as string)
            end if
            try
                set t to current track
                set theTitle to name of t
                set theArtist to artist of t
                set theAlbum to album of t
                set theDur to ((duration of t) as string)
            on error
                return pstate & tab & "" & tab & "" & tab & "" & tab & "0" & tab & pos & tab & theVol & tab & theShuf & tab & theRep & tab & "false"
            end try
            -- Favorite state: `loved` is broken on recent Music versions
            -- (raises a descriptor-type error), so prefer `favorited` and keep
            -- it in its own try so it can never blank the whole track read.
            set theLoved to "false"
            try
                set theLoved to (favorited of t as string)
            on error
                try
                    set theLoved to (loved of t as string)
                end try
            end try
            -- Radio/stream entries are "URL track"s: they can't be favorited
            -- (or added to the library), so the UI should hide the heart.
            set theFavoritable to "true"
            try
                if (class of t as string) is "URL track" then set theFavoritable to "false"
            end try
            return pstate & tab & theTitle & tab & theArtist & tab & theAlbum & tab & theDur & tab & pos & tab & theVol & tab & theShuf & tab & theRep & tab & theLoved & tab & theFavoritable
        end tell
        """

        guard let raw = AppleScriptRunner.string(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 11 else { return nil }

        let state: PlaybackState
        switch parts[0] {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }

        let title = parts[1]
        guard !title.isEmpty else { return nil }

        // Streamed catalog tracks expose no artwork over AppleScript; fall
        // back to looking the album up online.
        let artworkData = fetchArtwork()
        let artworkURL = artworkData == nil
            ? ArtworkLookup.shared.url(artist: parts[2], album: parts[3], title: title)
            : nil

        return NowPlaying(
            app: .appleMusic,
            title: title,
            artist: parts[2],
            album: parts[3],
            state: state,
            duration: AppleScriptRunner.double(parts[4]),
            position: AppleScriptRunner.double(parts[5]),
            artworkURL: artworkURL,
            artworkData: artworkData,
            volume: AppleScriptRunner.double(parts[6]).map { $0 / 100 },
            isShuffle: parts[7] == "true",
            repeatMode: Self.parseRepeat(parts[8]),
            // Hide the heart entirely for non-favoritable entries (radio/stream).
            isFavorite: parts[10] == "true" ? (parts[9] == "true") : nil
        )
    }

    private static func parseRepeat(_ s: String) -> RepeatMode {
        switch s {
        case "all": return .all
        case "one": return .one
        default: return .off
        }
    }

    /// Artwork comes back as raw image data from the scripting bridge.
    private func fetchArtwork() -> Data? {
        let script = """
        tell application "Music"
            try
                if (count of artworks of current track) is 0 then return missing value
                return data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """
        // `missing value` comes back as a 4-byte type descriptor ('msng'),
        // not an empty one — don't mistake it for image bytes.
        guard let descriptor = AppleScriptRunner.run(script),
              descriptor.descriptorType != typeType else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    func playPause() { AppleScriptRunner.run(#"tell application "Music" to playpause"#) }
    func nextTrack() { AppleScriptRunner.run(#"tell application "Music" to next track"#) }
    func previousTrack() { AppleScriptRunner.run(#"tell application "Music" to previous track"#) }

    func seek(to seconds: Double) {
        AppleScriptRunner.run(#"tell application "Music" to set player position to \#(seconds)"#)
    }

    func setVolume(_ value: Double) {
        let v = Int((min(max(value, 0), 1) * 100).rounded())
        AppleScriptRunner.run(#"tell application "Music" to set sound volume to \#(v)"#)
    }

    func toggleShuffle() {
        AppleScriptRunner.run(#"tell application "Music" to set shuffle enabled to not (shuffle enabled)"#)
    }

    func cycleRepeat() {
        AppleScriptRunner.run("""
        tell application "Music"
            set r to song repeat
            if r is off then
                set song repeat to all
            else if r is all then
                set song repeat to one
            else
                set song repeat to off
            end if
        end tell
        """)
    }

    func toggleFavorite() {
        // Favoriting works only for tracks that are in the library. A catalog
        // track played straight from search/browse isn't, so setting
        // `favorited` on it silently no-ops. Mirror what the Music app does:
        // add the track to the library first, then favorite it. Radio/stream
        // "URL track"s can't be favorited at all — we skip them here (and the
        // UI hides the heart via `favoritable`).
        AppleScriptRunner.run("""
        tell application "Music"
            set t to current track
            if (class of t as string) is "URL track" then return
            set newState to not (favorited of t)
            -- Ensure the track is in the library so the flag can stick.
            try
                duplicate t to library playlist 1
            end try
            try
                set favorited of t to newState
            on error
                try
                    set loved of t to newState
                end try
            end try
        end tell
        """)
    }

    func activate() {
        AppleScriptRunner.run(#"tell application "Music" to activate"#)
    }
}
