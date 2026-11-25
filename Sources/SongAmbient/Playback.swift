import AppKit
import Foundation
import Combine
import AmbientCore

@MainActor final class MusicWatcher: ObservableObject {
    @Published private(set) var title = "Nothing playing"
    @Published private(set) var artist = "Play a song in Spotify"
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var playing = false
    @Published private(set) var duration = 0.0
    @Published private(set) var catalogDuration = 0.0
    @Published private(set) var crossfadeCorrection = 0.0
    @Published private(set) var position = 0.0
    @Published private(set) var identity = ""
    @Published private(set) var source: AudioSource?
    @Published private(set) var status = "Waiting to connect"
    @Published private(set) var connected = false
    @Published private(set) var monitoring = false
    @Published private(set) var shuffle = false
    @Published private(set) var volume = 100.0
    @Published private(set) var diagnostics: [String] = []
    private let bridge = AppleEventBridge()
    private let queue = DispatchQueue(label: "local.songambient.playback")
    private var timer: Timer?
    private var anchor = Date(), anchorPosition = 0.0
    private var polling = false
    private var selected = AudioSource.spotify
    private var generation = 0
    private var denied = false
    private var artworkRequestID: String?
    private var artworkTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func select(_ source: AudioSource, connect shouldConnect: Bool) {
        guard selected != source else {
            if shouldConnect { connect() }
            return
        }
        selected = source; generation += 1; polling = false; denied = false
        monitoring = false
        timer?.invalidate(); timer = nil
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers = []
        clearTrack()
        diagnostics = []
        status = source == .systemAudio ? "System output supplies audio for lighting." : "Waiting to connect"
        if shouldConnect { connect() }
    }

    func connect() {
        guard let bundleID = selected.playerBundleID else { return }
        monitoring = true; denied = false; status = "Checking \(selected.rawValue)…"
        poll()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.position = self.currentTime(at: Date()); self.poll()
                }
            }
            if selected == .spotify {
                let observer = DistributedNotificationCenter.default().addObserver(
                    forName: .init("\(bundleID).PlaybackStateChanged"), object: nil, queue: .main
                ) { [weak self] _ in Task { @MainActor in self?.poll() } }
                observers.append(observer)
            }
        }
    }

    func currentTime(at date: Date) -> Double {
        let value = anchorPosition + (playing ? max(0,date.timeIntervalSince(anchor)) : 0)
        return max(0,duration > 0 ? min(duration,value) : value)
    }

    private func poll() {
        guard monitoring, !polling, let bundleID = selected.playerBundleID else { return }
        let player = selected
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            if player == .appleMusic { clearTrack() }
            if connected { connected = false }
            if playing { playing = false }
            let message = "Open \(player == .appleMusic ? "Music" : "Spotify desktop")."
            if status != message {
                status = message
                diagnostics = ["\(player.rawValue): not running"]
            }
            return
        }
        guard !denied else {
            if status != automationDeniedMessage {
                status = automationDeniedMessage
                diagnostics = [status]
            }
            return
        }
        polling = true
        let generation = self.generation
        let pid = app.processIdentifier
        queue.async { [weak self, bridge] in
            let result = bridge.read(player)
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.polling = false
                guard NSRunningApplication(processIdentifier: pid)?.isTerminated == false else { return }
                switch result {
                case .track(let track):
                    self.diagnostics = ["\(player.rawValue): reading playback"]
                    self.apply(track)
                case .empty:
                    if player == .appleMusic { self.clearTrack(keepingControlsFor: player) }
                    self.connected = false; self.playing = false
                    self.status = "\(player.rawValue): no accessible current track"
                    self.diagnostics = [self.status]
                case .failure(let code, let message):
                    if player == .appleMusic { self.clearTrack() }
                    self.denied = code == -1743
                    self.connected = false; self.playing = false
                    self.status = self.denied ? self.automationDeniedMessage : "\(message) (\(code))"
                    self.diagnostics = ["\(player.rawValue): \(self.status)"]
                }
            }
        }
    }

    private var automationDeniedMessage: String {
        "Automation permission denied. Allow \(selected.rawValue) in Privacy & Security → Automation, then Connect."
    }

    private func clearTrack(keepingControlsFor player: AudioSource? = nil) {
        if !identity.isEmpty { identity = "" }
        if artwork != nil { artwork = nil }
        artworkTask?.cancel(); artworkTask = nil; artworkRequestID = nil
        let prompt: String
        switch selected {
        case .systemAudio: prompt = "Play audio in any app"
        case .appleMusic: prompt = "Play a song in Music"
        case .spotify: prompt = "Play a song in Spotify"
        }
        if artist != prompt { artist = prompt }
        if title != "Nothing playing" { title = "Nothing playing" }
        if !album.isEmpty { album = "" }
        if playing { playing = false }
        if connected { connected = false }
        if source != player { source = player }
        if duration != 0 { duration = 0 }
        if catalogDuration != 0 { catalogDuration = 0 }
        if crossfadeCorrection != 0 { crossfadeCorrection = 0 }
        if position != 0 { position = 0 }
        if shuffle { shuffle = false }
        if volume != 100 { volume = 100 }
        anchorPosition = 0; anchor = Date()
    }

    private func apply(_ track: TrackSnapshot) {
        title = track.title; artist = track.artist; album = track.album; playing = track.playing
        duration = track.duration; position = track.position; anchorPosition = track.position; anchor = Date()
        crossfadeCorrection=track.crossfade
        catalogDuration=track.duration+track.crossfade
        source = track.source; connected = true; shuffle = track.shuffle; volume = track.volume
        status = "\(track.source.rawValue) · \(track.playing ? "Playing" : "Paused")"
        let nextID = "\(track.source.rawValue)|\(track.id)|\(track.title)|\(track.artist)|\(track.album)"
        guard identity != nextID else { return }
        identity = nextID; artwork = nil; artworkTask?.cancel(); artworkRequestID = nil
        if track.source == .appleMusic {
            loadMusicArtwork(for: track, identity: nextID)
        } else if let url = URL(string: track.artworkURL), url.scheme == "https" {
            artworkTask = Task {
                if let (data,_) = try? await URLSession.shared.data(from: url), !Task.isCancelled, identity == nextID { artwork = NSImage(data: data) }
            }
        }
    }

    private func loadMusicArtwork(for track: TrackSnapshot, identity: String) {
        let requestID = UUID().uuidString
        artworkRequestID = requestID
        queue.async { [weak self, bridge] in
            let data = bridge.musicArtwork(for: track)
            Task { @MainActor in
                guard let self, self.artworkRequestID == requestID, self.identity == identity, let data else { return }
                self.artwork = NSImage(data: data)
            }
        }
    }

    func command(_ command: String) {
        guard let source, let bundleID = source.playerBundleID,
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        let generation = self.generation
        queue.async { [weak self, bridge] in
            let error = bridge.command(command, source: source)
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let error { self.status = error }
                self.poll()
            }
        }
    }
    func seek(_ seconds: Double) {
        let value = max(0,min(duration,seconds)); anchorPosition = value; anchor = Date(); position = value
        command("set player position to \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value))")
    }
    func toggleShuffle() {
        let property = selected == .appleMusic ? "shuffle enabled" : "shuffling"
        command("set \(property) to \(shuffle ? "false" : "true")")
    }
    func setVolume(_ value: Double) { volume = value; command("set sound volume to \(Int(value))") }
    func openSelectedPlayer() {
        let source = selected
        guard let bundleID = source.playerBundleID else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { status = "\(source.rawValue) is not installed"; return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _,_ in
            Task { @MainActor in
                guard let self, self.selected == source else { return }
                self.connect()
            }
        }
    }
}

private struct TrackSnapshot: Sendable {
    let source: AudioSource
    let title: String, artist: String, album: String, artworkURL: String, id: String
    let duration: Double, position: Double, volume: Double
    let crossfade:Double
    let playing: Bool, shuffle: Bool
}
private enum PlaybackRead: Sendable { case track(TrackSnapshot), empty, failure(Int,String) }

// Accessed exclusively by the playback queue. No existence event is sent to
// Spotify: its shipping scripting dictionary doesn't implement that command.
private final class AppleEventBridge: @unchecked Sendable {
    private var scripts: [AudioSource:NSAppleScript] = [:]
    private var artworkScript: NSAppleScript?
    private var crossfade=0.0,lastTimingRead=Date.distantPast
    func read(_ source: AudioSource) -> PlaybackRead {
        guard let bundleID = source.playerBundleID else { return .empty }
        var error: NSDictionary?
        let script: NSAppleScript
        if let cached = scripts[source] { script = cached }
        else {
            guard let new = NSAppleScript(source: Self.script(source, bundleID: bundleID)), new.compileAndReturnError(&error) else { return failure(error) }
            scripts[source] = new; script = new
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1728 || code == -1719 { return .empty }
            return failure(error)
        }
        guard result.numberOfItems >= 10, let name = result.atIndex(1)?.stringValue, !name.isEmpty, name != "missing value" else { return .empty }
        let rawDuration = result.atIndex(4)?.doubleValue ?? 0
        let duration = source == .spotify ? rawDuration / 1000 : rawDuration
        if source == .spotify, Date().timeIntervalSince(lastTimingRead) > 30 {
            crossfade = SpotifyTimingSettings.crossfadeSeconds(); lastTimingRead = Date()
        }
        return .track(TrackSnapshot(source: source, title: name, artist: result.atIndex(2)?.stringValue ?? "", album: result.atIndex(3)?.stringValue ?? "", artworkURL: result.atIndex(7)?.stringValue ?? "", id: result.atIndex(8)?.stringValue ?? name, duration: duration, position: result.atIndex(5)?.doubleValue ?? 0, volume: result.atIndex(10)?.doubleValue ?? 100, crossfade:source == .spotify ? crossfade : 0, playing: result.atIndex(6)?.booleanValue ?? false, shuffle: result.atIndex(9)?.booleanValue ?? false))
    }
    func musicArtwork(for track: TrackSnapshot) -> Data? {
        var error: NSDictionary?
        if artworkScript == nil {
            let script = NSAppleScript(source: """
            if application id "com.apple.Music" is not running then return {}
            with timeout of 3 seconds
              tell application id "com.apple.Music"
                set t to current track
                set trackID to ""
                set trackArtist to ""
                set trackAlbum to ""
                try
                  set trackID to persistent ID of t as text
                end try
                try
                  set trackArtist to artist of t as text
                end try
                try
                  set trackAlbum to album of t as text
                end try
                set trackArt to missing value
                try
                  set trackArt to raw data of artwork 1 of t
                end try
                return {name of t as text, trackArtist, trackAlbum, trackID, trackArt}
              end tell
            end timeout
            """)
            guard script?.compileAndReturnError(&error) == true else { return nil }
            artworkScript = script
        }
        guard let result = artworkScript?.executeAndReturnError(&error), error == nil,
              result.atIndex(1)?.stringValue == track.title,
              result.atIndex(2)?.stringValue == track.artist,
              result.atIndex(3)?.stringValue == track.album,
              result.atIndex(4)?.stringValue == track.id else { return nil }
        return result.atIndex(5)?.data
    }

    func command(_ command: String, source: AudioSource) -> String? {
        guard let bundleID = source.playerBundleID else { return nil }
        var error: NSDictionary?
        NSAppleScript(source: """
        if application id "\(bundleID)" is not running then return
        with timeout of 5 seconds
          tell application id "\(bundleID)" to \(command)
        end timeout
        """)?.executeAndReturnError(&error)
        return error.map { "\(source.rawValue): \($0[NSAppleScript.errorMessage] as? String ?? "Playback command failed")" }
    }
    private func failure(_ error: NSDictionary?) -> PlaybackRead {
        .failure(error?[NSAppleScript.errorNumber] as? Int ?? 0,String((error?[NSAppleScript.errorMessage] as? String ?? "Cannot read playback").prefix(200)))
    }
    private static func script(_ source: AudioSource, bundleID: String) -> String {
        let readArtwork = source == .spotify ? """
            try
              set trackArt to artwork url of t
            end try
        """ : ""
        let id = source == .spotify ? "id of t" : "persistent ID of t"
        let shuffle = source == .spotify ? "shuffling" : "shuffle enabled"
        return """
        if application id "\(bundleID)" is not running then return {}
        with timeout of 8 seconds
          tell application id "\(bundleID)"
            set t to current track
            set trackTitle to name of t as text
            set trackArtist to ""
            set trackAlbum to ""
            set trackArt to ""
            set trackID to ""
            set shuffleState to false
            try
              set trackArtist to artist of t as text
            end try
            try
              set trackAlbum to album of t as text
            end try
            \(readArtwork)
            try
              set trackID to \(id) as text
            end try
            try
              set shuffleState to \(shuffle)
            end try
            return {trackTitle, trackArtist, trackAlbum, duration of t, player position, (player state is playing), trackArt, trackID, shuffleState, sound volume}
          end tell
        end timeout
        """
    }
}
