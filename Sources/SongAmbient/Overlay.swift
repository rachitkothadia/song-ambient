import AppKit
import SwiftUI
import Combine
import Metal
import AmbientCore

final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class OverlayController {
    private let model: AppModel
    private var windows: [NSPanel] = []
    private var tokens = Set<AnyCancellable>()
    private var observer: NSObjectProtocol?
    init(model: AppModel) {
        self.model = model
        rebuild()
        model.$prefs.map(\.displays).removeDuplicates().dropFirst().sink { [weak self] _ in self?.rebuild() }.store(in: &tokens)
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
    }
    private func rebuild() {
        windows.forEach { $0.close() }; windows = []
        model.screens = NSScreen.screens
        for screen in NSScreen.screens where model.prefs.displays.isEmpty || model.prefs.displays.contains(screen.ambientID) {
            let panel = PassivePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.animationBehavior = .none
            let notchWidth: CGFloat
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notchWidth = max(0, right.minX - left.maxX)
            } else { notchWidth = 0 }
            let hosting = NSHostingView(rootView: RimView(model: model, audio: model.audio, music: model.music, notchWidth: notchWidth, notchHeight: screen.safeAreaInsets.top))
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting
            panel.orderFrontRegardless()
            windows.append(panel)
        }
    }
}

struct RimView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audio: AudioCapture
    @ObservedObject var music: MusicWatcher
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    var miniature = false
    @State private var lastBeat = Date.distantPast
    private var active: Bool { (model.prefs.enabled || model.preview) && !model.suspended && (miniature || model.preview || model.lightingActive) }
    private var moving: Bool { active && (model.prefs.motion == .flow || model.prefs.motion == .music && audio.running && audio.level > 0.001) }
    var body: some View {
        if MTLCreateSystemDefaultDevice() != nil {
            MetalRim(model: model, audio: audio, music: music, notchWidth: notchWidth, notchHeight: notchHeight, miniature: miniature)
                .allowsHitTesting(false).accessibilityHidden(true)
        } else {
            fallback
        }
    }
    private var fallback: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let beatPulse = max(0, 1 - context.date.timeIntervalSince(lastBeat) / 0.38)
            let energy = model.prefs.motion == .music ? audio.level : 0
            let phase = model.prefs.motion == .flow ? time * 16 : model.prefs.motion == .music ? time * (4 + energy * 25) : 0
            let width = model.prefs.thickness * (1 + beatPulse * 0.55 + energy * 0.35)
            let shape = RimShape(notchWidth: model.prefs.notch ? notchWidth : 0, notchHeight: model.prefs.notch ? notchHeight : 0, inset: max(1, width / 2), corner: miniature ? 17 : 12)
            let gradient = AngularGradient(colors: model.colors, center: .center, startAngle: .degrees(phase), endAngle: .degrees(phase + 360))
            ZStack {
                shape.stroke(gradient, lineWidth: width + model.prefs.glow * 0.65).blur(radius: model.prefs.glow * 0.55).opacity(0.6 + energy * 0.3)
                shape.stroke(gradient, lineWidth: width + model.prefs.glow * 0.16).blur(radius: model.prefs.glow * 0.16).opacity(0.8)
                shape.stroke(gradient, lineWidth: width)
                shape.stroke(.white.opacity(0.2 + beatPulse * 0.2), lineWidth: max(0.4, width * 0.15))
            }
            .opacity(active && (miniature || model.prefs.motion != .music || audio.running && audio.level > 0.001 || model.preview) ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onChange(of: audio.beat) { _, _ in lastBeat = Date() }
        .accessibilityHidden(true)
    }
}

struct RimShape: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var inset: CGFloat
    var corner: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = min(corner, r.height / 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        if notchWidth > 0, notchHeight > 0 {
            let left = rect.midX - notchWidth / 2, right = rect.midX + notchWidth / 2
            let d = notchHeight + inset, n: CGFloat = 7
            p.addLine(to: CGPoint(x: left - n, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: left, y: r.minY + n), control: CGPoint(x: left, y: r.minY))
            p.addLine(to: CGPoint(x: left, y: d - n))
            p.addQuadCurve(to: CGPoint(x: left + n, y: d), control: CGPoint(x: left, y: d))
            p.addLine(to: CGPoint(x: right - n, y: d))
            p.addQuadCurve(to: CGPoint(x: right, y: d - n), control: CGPoint(x: right, y: d))
            p.addLine(to: CGPoint(x: right, y: r.minY + n))
            p.addQuadCurve(to: CGPoint(x: right + n, y: r.minY), control: CGPoint(x: right, y: r.minY))
        }
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

extension NSScreen {
    var ambientID: String { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName }
}
