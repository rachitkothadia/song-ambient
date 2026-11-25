import AmbientCore
import AppKit
import SwiftUI
import AVFoundation
import Combine

@MainActor final class PlayerController {
    private let model: AppModel
    private var panel: NSPanel?
    private var locked = false
    private var tokens = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    init(model: AppModel) {
        self.model = model
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setLocked(true) }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setLocked(false) }
        })
        model.$prefs.map(\.showPlayer).removeDuplicates().dropFirst().sink { [weak self] show in
            if show { self?.showPreview() } else if self?.locked != true { self?.panel?.orderOut(nil) }
        }.store(in: &tokens)
    }
    private func setLocked(_ value: Bool) {
        if locked && !value { panel?.close(); panel = nil }
        locked = value; update()
    }
    private func update() {
        if locked {
            panel?.orderOut(nil)
        } else if model.prefs.showPlayer { showPreview() } else { panel?.orderOut(nil) }
    }
    func showPreview() {
        guard !locked else { return }
        if panel == nil {
            let p = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true; p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = NSHostingView(rootView: PlayerCard(model: model, music: model.music, audio: model.audio, lyrics: model.lyrics, motion: model.motionArt, compact: true).padding(12).preferredColorScheme(.dark))
            panel = p
        }
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.level = .floating
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.midY - panel.frame.height))
        panel.orderFrontRegardless()
    }
    func hidePreview() { panel?.orderOut(nil) }
}

struct PlayerCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var music: MusicWatcher
    @ObservedObject var audio: AudioCapture
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var motion: MotionArtworkService
    var compact = false
    @State private var showLyrics = false
    @State private var expandedArtwork = false
    @State private var scrub = 0.0
    @State private var scrubbing = false
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 13) {
                Button {
                    expandedArtwork.toggle()
                    if expandedArtwork && model.prefs.animatedArtwork { motion.load(music: music, storefront: model.prefs.storefront) }
                } label: { cover.frame(width: compact ? 58 : 70, height: compact ? 58 : 70).clipShape(RoundedRectangle(cornerRadius: 12)) }
                .buttonStyle(.plain).help("Show album artwork")
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.audioSource == .systemAudio ? model.audioSource.rawValue : music.title).font(.system(size: compact ? 14 : 16, weight: .semibold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    if model.audioSource == .appleMusic && !music.album.isEmpty {
                        Text(music.album).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    if !compact { Text(model.audioSource.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 0)
                BarsView(audio: audio, playing: model.audioSource == .spotify ? music.playing : model.lightingActive).frame(width: 26, height: 22)
            }
            if expandedArtwork {
                cover.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                if !compact { Text(motion.status).font(.caption2).foregroundStyle(.secondary) }
            }
            VStack(spacing: 2) {
                Slider(value: Binding(get: { scrubbing ? scrub : music.position }, set: { scrub = $0 }), in: 0...max(1, music.duration), onEditingChanged: { editing in
                    if editing { scrub = music.position }
                    scrubbing = editing
                    if !editing { music.seek(scrub) }
                }).controlSize(.mini).tint(.white.opacity(0.9)).disabled(music.source == nil)
                HStack {
                    Text(Self.timestamp(scrubbing ? scrub : music.position))
                    Spacer()
                    if model.audioSource == .appleMusic {
                        Text(Self.timestamp(music.duration)).accessibilityLabel("Track duration").accessibilityValue(Self.timestamp(music.duration))
                    } else {
                        Text("−" + Self.timestamp(max(0, music.duration - (scrubbing ? scrub : music.position))))
                    }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 25) {
                Button { showLyrics.toggle(); if showLyrics { lyrics.load(music: music) } } label: { Image(systemName: "quote.bubble").font(.system(size: 14)).foregroundStyle(showLyrics ? .white : .gray) }.help("Word lyrics")
                Button { music.command("previous track") } label: { Image(systemName: "backward.fill").font(.system(size: 21)) }.help("Previous track")
                Button { music.command("playpause") } label: { Image(systemName: music.playing ? "pause.fill" : "play.fill").font(.system(size: 25)).frame(width: 30) }.help(music.playing ? "Pause" : "Play")
                Button { music.command("next track") } label: { Image(systemName: "forward.fill").font(.system(size: 21)) }.help("Next track")
                Button { model.prefs.showPlayer.toggle() } label: { Image(systemName: "rectangle.on.rectangle").font(.system(size: 14)).foregroundStyle(.gray) }.help("Floating player")
            }.buttonStyle(.plain).disabled(music.source == nil)
            if showLyrics {
                if lyrics.presentation.tokens.isEmpty {
                    HStack { if lyrics.loading { ProgressView().controlSize(.small) }; Text(lyrics.status).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 8)
                } else {
                    LyricCanvas(model:model,music:music,audio:audio,lyrics:lyrics,preview:true).frame(height:compact ? 150:190).clipShape(RoundedRectangle(cornerRadius:12))
                }
            }
        }
        .padding(compact ? 18 : 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.16), lineWidth: 0.8))
        .onChange(of: music.identity) { _, _ in if showLyrics { lyrics.load(music: music) } }
    }
    @ViewBuilder private var cover: some View {
        if expandedArtwork, let url = motion.url { LoopingVideo(url: url) }
        else if let image = music.artwork { Image(nsImage: image).resizable().scaledToFill().clipped() }
        else {
            ZStack { LinearGradient(colors: model.colors, startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "music.note").font(.system(size: 25)).foregroundStyle(.white.opacity(0.8)) }
        }
    }
    static func timestamp(_ value: Double) -> String {
        let seconds = Int(max(0, value.isFinite ? value : 0))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct BarsView: View {
    @ObservedObject var audio: AudioCapture
    var playing: Bool
    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5) { index in
                    Capsule().fill(.white.opacity(playing ? 0.85 : 0.3))
                        .frame(width: 2, height: max(3, proxy.size.height * (audio.running && playing ? audio.bands[index * 3] : 0.12)))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private final class VideoHostView: NSView {
    let video = AVPlayerLayer()
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.addSublayer(video); video.videoGravity = .resizeAspectFill }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); video.frame = bounds }
}

struct LoopingVideo: NSViewRepresentable {
    let url: URL
    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var url: URL?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { VideoHostView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? VideoHostView, context.coordinator.url != url else { return }
        context.coordinator.player?.pause()
        let player = AVQueuePlayer(); player.isMuted = true
        context.coordinator.player = player; context.coordinator.url = url
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        host.video.player = player; player.play()
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.player?.pause(); coordinator.looper = nil; coordinator.player = nil }
}
