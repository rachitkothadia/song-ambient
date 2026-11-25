public enum AudioSource: String, CaseIterable, Codable, Sendable {
    case systemAudio = "System Audio"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"

    public static func restored(from savedValue: String?) -> AudioSource {
        savedValue.flatMap(Self.init(rawValue:)) ?? .spotify
    }

    public var playerBundleID: String? {
        switch self {
        case .systemAudio: nil
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    public func includesProcess(bundleID: String) -> Bool {
        switch self {
        case .systemAudio: true
        case .appleMusic: bundleID == "com.apple.Music" || bundleID.hasPrefix("com.apple.Music.")
        case .spotify: SpotifyAudioPolicy.includes(bundleID: bundleID)
        }
    }

    public func shouldRender(playing: Bool, connected: Bool, capturing: Bool, level: Double) -> Bool {
        switch self {
        case .spotify:
            SpotifyAudioPolicy.shouldRender(playing: playing, connected: connected, spotifySource: true, capturing: capturing, level: level)
        case .systemAudio, .appleMusic:
            capturing && level > 0.001
        }
    }
}
