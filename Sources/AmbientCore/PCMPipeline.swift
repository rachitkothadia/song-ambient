import Accelerate
import CoreAudio
import Foundation

// Each tap owns one PCM pipeline. The IO block and silence timer are its only
// callers, both on the serial PCM queue. No audio buffers escape the callback.
package final class PCMPipeline: @unchecked Sendable {
    private let sampleRate: Double
    private let publish: @Sendable (AudioFeatures) -> Void
    private var mono: [Float]
    private var engine = BeatEngine()
    private var lastPublishedBeat = 0
    private var lastPublish = 0.0
    private var lastPCM = 0.0
    private var silencePublished = false
    private let fftSize = 512
    private let fft = vDSP_DFT_zop_CreateSetupD(nil, 512, .FORWARD)
    private var inputR = [Double](repeating: 0, count: 512)
    private var inputI = [Double](repeating: 0, count: 512)
    private var outputR = [Double](repeating: 0, count: 512)
    private var outputI = [Double](repeating: 0, count: 512)
    private let window: [Double] = (0..<512).map { index in
        let phase: Double = 2.0 * Double.pi * Double(index) / 511.0
        let cosine: Double = cos(phase)
        return 0.5 - 0.5 * cosine
    }

    package init(sampleRate: Double, frameCount: Int, publish: @escaping @Sendable (AudioFeatures) -> Void) {
        self.sampleRate = sampleRate
        self.publish = publish
        mono = [Float](repeating: 0, count: frameCount)
    }

    deinit { if let fft { vDSP_DFT_DestroySetupD(fft) } }

    package func process(_ list: UnsafePointer<AudioBufferList>, time: Double = ProcessInfo.processInfo.systemUptime) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var frames = Int.max
        for buffer in buffers where buffer.mData != nil && buffer.mDataByteSize > 0 {
            frames = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(1, Int(buffer.mNumberChannels)))
        }
        guard frames > 0, frames != Int.max else { return }
        if frames != mono.count { mono = [Float](repeating: 0, count: frames) }
        for frame in 0..<frames {
            var strongest: Float = 0
            for buffer in buffers where buffer.mDataByteSize > 0 {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = max(1, Int(buffer.mNumberChannels))
                for channel in 0..<channels {
                    let sample = samples[frame * channels + channel]
                    if abs(sample) > abs(strongest) { strongest = sample }
                }
            }
            // Preserve the original channel selection for antiphase and planar stereo.
            mono[frame] = strongest
            if frame < fftSize { inputR[frame] = Double(strongest) * window[frame] }
        }
        if frames < fftSize { for i in frames..<fftSize { inputR[i] = 0 } }
        lastPCM = time
        analyze(at: time)
    }

    package func releaseIfStalled(at now: Double = ProcessInfo.processInfo.systemUptime) {
        guard lastPCM > 0, now - lastPCM > 0.15, !silencePublished else { return }
        for index in mono.indices { mono[index] = 0 }
        for index in inputR.indices { inputR[index] = 0 }
        // When HAL stops delivering PCM, advance the same release envelopes with zeros.
        analyze(at: now)
    }

    private func analyze(at now: Double) {
        var snapshot = engine.analyze(mono, sampleRate: sampleRate, time: now)
        if snapshot.level == 0 && snapshot.bass == 0 {
            guard !silencePublished else { return }
            silencePublished = true
            publish(snapshot)
            return
        }
        silencePublished = false
        let hit = snapshot.beatIndex != lastPublishedBeat
        guard now - lastPublish >= 1.0 / 30 || hit else { return }
        lastPublish = now
        lastPublishedBeat = snapshot.beatIndex
        var spectrum = [Double](repeating: 0, count: 16)
        if let fft {
            vDSP_DFT_ExecuteD(fft, inputR, inputI, &outputR, &outputI)
            for b in 0..<16 {
                let lo = max(1, Int(pow(256.0, Double(b) / 16)))
                let hi = min(255, max(lo + 1, Int(pow(256.0, Double(b + 1) / 16))))
                var energy = 0.0
                for bin in lo..<hi { energy = max(energy, hypot(outputR[bin], outputI[bin])) }
                spectrum[b] = min(1, log1p(energy * 2) / 4)
            }
        }
        snapshot.bands = spectrum
        publish(snapshot)
    }
}
