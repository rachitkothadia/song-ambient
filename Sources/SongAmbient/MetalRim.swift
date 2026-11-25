import SwiftUI
import MetalKit
import AmbientCore

struct MetalRim: NSViewRepresentable {
    @ObservedObject var model: AppModel
    @ObservedObject var audio: AudioCapture
    @ObservedObject var music: MusicWatcher
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var miniature: Bool
    func makeCoordinator() -> RimRenderer? { RimRenderer(metalDevice: MTLCreateSystemDefaultDevice()) }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.wantsLayer = true; view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator else { return }
        let prefs = model.prefs
        renderer.active = (prefs.enabled || model.preview) && !model.suspended && (miniature || model.preview || model.lightingActive)
        if renderer.motion != prefs.motion {renderer.spring=BounceSpring()}
        renderer.motion = prefs.motion
        renderer.level = prefs.motion == .music ? audio.level : 0
        renderer.bass = prefs.motion == .music ? audio.features.bass : 0
        renderer.mid = prefs.motion == .music ? audio.features.mid : 0
        renderer.treble = prefs.motion == .music ? audio.features.treble : 0
        renderer.bands=audio.bands
        renderer.bounceGain=prefs.bassBounce;renderer.speed=prefs.animationSpeed;renderer.style=prefs.rimStyle.shaderID
        if renderer.beat != audio.beat {
            renderer.beat=audio.beat;renderer.beatTime=CACurrentMediaTime()
            if prefs.motion == .music{renderer.spring.impulse(audio.features.beatStrength*prefs.bassBounce)}
        }
        renderer.thickness = Float(prefs.thickness)
        renderer.glow = Float(prefs.glow)
        renderer.notch = prefs.notch ? SIMD2(Float(notchWidth),Float(notchHeight)) : .zero
        renderer.corner = miniature ? 17 : 12
        let colors = model.colors
        renderer.hot = NSColor(colors[0]).usingColorSpace(.sRGB) ?? .systemPink
        renderer.deep = NSColor(colors[min(1,colors.count-1)]).usingColorSpace(.sRGB) ?? .systemIndigo
        let moving = renderer.active && (prefs.motion == .flow || prefs.motion == .music && audio.running && audio.level > 0.001)
        view.enableSetNeedsDisplay = !moving
        view.isPaused = !moving
        view.needsDisplay = true
    }
}

final class RimRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var active = false
    var motion = LightMotion.steady
    var level = 0.0
    var bass = 0.0, mid = 0.0, treble = 0.0
    var bounceGain = 1.4, speed = 0.8
    var style = 0
    var bands = [Double](repeating:0,count:16)
    var spring = BounceSpring()
    var beat = 0
    var beatTime = 0.0
    var thickness: Float = 4
    var glow: Float = 32
    var notch = SIMD2<Float>.zero
    var corner: Float = 12
    var hot = NSColor.systemPink
    var deep = NSColor.systemIndigo
    private var phase = 0.0
    private var lastTime = CACurrentMediaTime()
    private let origin = CACurrentMediaTime()
    private static var cached: (MTLDevice, MTLRenderPipelineState)?
    init?(metalDevice: MTLDevice?) {
        guard let device = metalDevice, let queue = device.makeCommandQueue() else { return nil }
        self.device = device; self.queue = queue
        do {
            if let cached = Self.cached { pipeline = cached.1 }
            else {
                let library = try device.makeLibrary(source: PlasmaShader.source, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "rimVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "rimFragment")
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                Self.cached = (device,pipeline)
            }
        } catch { return nil }
        super.init()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime(), dt = min(0.1,max(0,now-lastTime))
        lastTime = now
        if motion != .steady { phase=(phase+dt*speed*(motion == .flow ? 0.045 : 0.015+bass*0.12)).truncatingRemainder(dividingBy:1) }
        let pulse = Float(max(0,1-(now-beatTime)/0.38))
        let bounce=spring.step(delta:dt,target:bass*0.28)
        let bloom = motion == .music ? min(1,Float(bass)*0.65+pulse*0.2) : 0
        let scale = Float(view.drawableSize.width / max(1,view.bounds.width))
        var uniforms: [SIMD4<Float>] = [
            SIMD4(Float(view.bounds.width),Float(view.bounds.height),scale,active ? 1 : 0),
            SIMD4(Float(hot.redComponent*hot.alphaComponent),Float(hot.greenComponent*hot.alphaComponent),Float(hot.blueComponent*hot.alphaComponent),glow),
            SIMD4(Float(deep.redComponent*deep.alphaComponent),Float(deep.greenComponent*deep.alphaComponent),Float(deep.blueComponent*deep.alphaComponent),0),
            SIMD4(motion == .steady ? 0 : Float(now-origin)*Float(speed),Float(phase),corner,0.5),
            SIMD4(notch.x,notch.y,bloom,max(0.15,thickness/7)),
            SIMD4(Float(bass),Float(mid),Float(treble),Float(bounce)),
            SIMD4(Float(style),Float(bounceGain),Float(speed),0)
        ]
        for group in 0..<4 { uniforms.append(SIMD4(Float(bands[group*4]),Float(bands[group*4+1]),Float(bands[group*4+2]),Float(bands[group*4+3]))) }
        encoder.setRenderPipelineState(pipeline)
        uniforms.withUnsafeBufferPointer { encoder.setFragmentBytes($0.baseAddress!, length: $0.count * MemoryLayout<SIMD4<Float>>.stride, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); buffer.present(drawable); buffer.commit()
    }
}
