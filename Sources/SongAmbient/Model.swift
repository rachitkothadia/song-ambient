import AppKit
import SwiftUI
import Combine
import AmbientCore

enum LightMotion: String, CaseIterable, Codable {
    case steady = "Steady", flow = "Flow", music = "Music Sync"
}

struct Preferences: Codable, Equatable {
    var enabled = true
    var gradient = 2
    var motion = LightMotion.music
    var notch = true
    var thickness = 4.0
    var glow = 32.0
    var overrideColor = true
    var primary = "E74686"
    var secondary = "5465F6"
    var primaryBrightness = 0.8
    var secondaryBrightness = 0.85
    var displays: [String] = []
    var showPlayer = false
    var lyricsOffset = 0.0
    var storefront = "us"
    var animatedArtwork = true
    var rimStyle = RimStyle.aurora
    var bassBounce = 1.4
    var animationSpeed = 0.8
    var autoConnect = true
    var autoSync = true
    var autoLyrics = true
    var lyricStyle = LyricStyle.constellation
    var lyricFont = LyricFont.sfPro
    var lyricSize = 42.0
    var lyricAutoColor = true
    var lyricText = "EBEFF8"
    var lyricHighlight = "8BDAFF"
    var lyricSecondary = "8992AF"
    var stageDisplay = "automatic"
    var keepAwake = false
    var desktopLyrics = false

    static func restored(from data: Data?) -> Preferences {
        guard let data,
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Preferences()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(saved) { _, saved in saved }),
              let value = try? JSONDecoder().decode(Preferences.self, from: merged) else { return Preferences() }
        return value
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var prefs: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(data, forKey: "preferences.v1") }
        }
    }
    @Published var preview = false
    @Published var suspended = false
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var palette: [Color] = [.pink, .indigo]
    @Published private(set) var syncRequested = false
    @Published private(set) var audioSource: AudioSource
    @Published var selectedTab = StudioTab.lighting
    @Published var stageVisible = false
    @Published var lyricsDemo = false
    var demoStart=Date()
    let music = MusicWatcher()
    let audio = AudioCapture()
    let lyrics = LyricsService()
    let motionArt = MotionArtworkService()
    var overlay: OverlayController?
    var player: PlayerController?
    var desktop: DesktopLyricsController?
    private var tokens = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var previewTask: Task<Void, Never>?
    private var started = false

    init() {
        var restored = Preferences.restored(from: UserDefaults.standard.data(forKey: "preferences.v1"))
        if !UserDefaults.standard.bool(forKey: "defaults.v2") {
            restored.overrideColor = true; restored.motion = .music; restored.enabled = true
            UserDefaults.standard.set(true, forKey: "defaults.v2")
        }
        prefs = restored
        audioSource = AudioSource.restored(from: UserDefaults.standard.string(forKey: "audioSource"))
        music.select(audioSource, connect: false)
        if let data=try? JSONEncoder().encode(restored){UserDefaults.standard.set(data,forKey:"preferences.v1")}
        WindowCoordinator.shared.onStageVisibility={[weak self] visible in self?.stageVisible=visible}
        $prefs.map(\.keepAwake).removeDuplicates().sink{WindowCoordinator.shared.setKeepStageAwake($0)}.store(in:&tokens)
        music.$artwork.compactMap { $0 }.sink { [weak self] in self?.palette = Palette.colors(from: $0) }.store(in: &tokens)
        music.$identity.removeDuplicates().dropFirst().sink { [weak self] identity in
            Task { @MainActor in
                guard let self, self.music.identity == identity else { return }
                self.lyrics.clear(); self.motionArt.clear()
                if self.prefs.autoLyrics, !identity.isEmpty { self.lyrics.load(music: self.music) }
            }
        }.store(in: &tokens)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.suspended = true; self.audio.stop()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.suspended = false
                if self.syncRequested { self.audio.start(self.audioSource) }
            }
        })
    }

    var colors: [Color] {
        let usesCustom = prefs.overrideColor || audioSource == .systemAudio || (audioSource == .appleMusic && music.artwork == nil)
        let base = usesCustom ? [Color(hex: prefs.primary), Color(hex: prefs.secondary)] : palette
        let first = base[0].opacity(prefs.primaryBrightness)
        let second = base[min(1, base.count - 1)].opacity(prefs.secondaryBrightness)
        return prefs.gradient == 1 ? [first, first] : [first, second, first]
    }

    func start() {
        guard !started else { return }
        started = true
        if !ProcessInfo.processInfo.arguments.contains("--no-overlay") { overlay = OverlayController(model: self) }
        player = PlayerController(model: self)
        desktop = DesktopLyricsController(model:self)
        if prefs.showPlayer { player?.showPreview() }
        if !ProcessInfo.processInfo.arguments.contains("--test-ui") {
            if prefs.autoConnect { music.connect() }
            if prefs.autoSync { startAudio() }
        }
    }

    func previewLighting() {
        previewTask?.cancel()
        preview = true
        previewTask = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            preview = false
        }
    }

    func startMusicSync() {
        prefs.motion = .music
        startAudio()
    }

    func selectAudioSource(_ source: AudioSource) {
        guard audioSource != source else { return }
        audioSource = source
        UserDefaults.standard.set(source.rawValue, forKey: "audioSource")
        music.select(source, connect: prefs.autoConnect || (source == .spotify && syncRequested))
        if syncRequested && !suspended { audio.start(source) }
    }

    func startAudio() {
        syncRequested = true
        if audioSource == .spotify && !music.monitoring { music.connect() }
        if !suspended { audio.start(audioSource) }
    }

    func stopAudio() {
        syncRequested = false
        audio.stop()
    }

    var lightingActive: Bool {
        audioSource.shouldRender(playing: music.playing, connected: music.connected && music.source == audioSource,
                                 capturing: audio.running, level: audio.level)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0xE74686
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .systemPink
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

enum Palette {
    static func colors(from image: NSImage) -> [Color] {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return [.pink, .indigo] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40))
        NSGraphicsContext.restoreGraphicsState()
        var weights = [Double](repeating: 0, count: 24)
        var sums = [SIMD3<Double>](repeating: .zero, count: 24)
        for y in 0..<40 {
            for x in 0..<40 {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let s = c.saturationComponent, b = c.brightnessComponent
                guard b > 0.12, s > 0.15, c.alphaComponent > 0.5 else { continue }
                let index = min(23, Int(c.hueComponent * 24)), w = Double(s * b)
                weights[index] += w
                sums[index] += SIMD3(c.redComponent, c.greenComponent, c.blueComponent) * w
            }
        }
        let ranked = weights.indices.sorted { weights[$0] > weights[$1] }
        guard let first = ranked.first, weights[first] > 0 else { return [.pink, .indigo] }
        let second = ranked.first { min(abs($0 - first), 24 - abs($0 - first)) >= 4 && weights[$0] > 0 } ?? first
        return [first, second].map { index in
            let rgb = sums[index] / max(weights[index], 0.001)
            let c = NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
            return Color(nsColor: NSColor(hue: c.hueComponent, saturation: max(0.55, c.saturationComponent), brightness: max(0.72, c.brightnessComponent), alpha: 1))
        }
    }
}
