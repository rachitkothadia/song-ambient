import Foundation
import CoreAudio
import Combine
import AmbientCore

enum CaptureState: Equatable, Sendable {
    case off, starting, waitingForProcess, listening, permissionDenied(OSStatus), failed(String, OSStatus)

    var running: Bool { self == .listening }

    func description(for source: AudioSource) -> String {
        switch self {
        case .off: "\(source.rawValue) capture is off"
        case .starting: "Starting \(source.rawValue) capture…"
        case .waitingForProcess: "Waiting for \(source.rawValue) audio"
        case .listening: source == .systemAudio ? "Listening to system output" : "Listening to \(source.rawValue) only"
        case .permissionDenied(let code):
            "Allow System Audio Recording for Song Ambient in Privacy & Security, then retry (\(code))."
        case .failed(let message, let code):
            "\(message) (\(code)). Check System Audio Recording permission and the output device, then retry."
        }
    }
}

@MainActor final class AudioCapture: ObservableObject {
    @Published private(set) var state = CaptureState.off
    @Published private(set) var features = AudioFeatures()
    var running: Bool { state.running }
    var level: Double { features.level }
    var bass: Double { features.bass }
    var beat: Int { features.beatIndex }
    var bands: [Double] { features.bands }
    private let capture = TapController()
    private var generation = 0
    private var revision = 0

    func start(_ source: AudioSource) {
        generation += 1
        revision = 0
        state = .starting
        features = AudioFeatures()
        let generation = self.generation
        capture.start(source) { [weak self] update in
            guard let self, self.generation == generation else { return }
            switch update {
            case .state(let revision, let state):
                guard revision >= self.revision else { return }
                if revision != self.revision {
                    self.revision = revision
                    // Clear the previous source immediately. During a Spotify route
                    // rebuild, preserve its existing presentation until fresh PCM arrives.
                    if source != .spotify || !state.running { self.features = AudioFeatures() }
                }
                self.state = state
            case .features(let revision, let features):
                guard self.revision == revision, self.running else { return }
                self.features = features
            }
        }
    }

    func stop(completion: (@MainActor @Sendable () -> Void)? = nil) {
        generation += 1
        state = .off
        features = AudioFeatures()
        capture.stop(completion: completion)
    }
}

private enum CaptureUpdate: Sendable {
    case state(Int, CaptureState)
    case features(Int, AudioFeatures)
}

private typealias CaptureSink = @MainActor @Sendable (CaptureUpdate) -> Void

// All HAL setup, monitoring and teardown run on this queue. Core Audio
// dispatches its IO block synchronously, so PCM uses a different queue.
private final class TapController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.songambient.audio.control", qos: .userInitiated)
    private let pcmQueue = DispatchQueue(label: "local.songambient.audio.pcm", qos: .userInitiated)
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private let outputSelectors = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
    private var source: AudioSource?
    private var sink: CaptureSink?
    private var revision = 0
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var started = false
    private var outputListeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var tapFormatListener: AudioObjectPropertyListenerBlock?
    private var rebuildWork: DispatchWorkItem?
    private var processMonitor: DispatchSourceTimer?
    private var silenceMonitor: DispatchSourceTimer?
    private var capturedProcesses: [AudioObjectID] = []

    func start(_ source: AudioSource, sink: @escaping CaptureSink) {
        queue.async {
            self.stopOnQueue()
            self.source = source
            self.sink = sink
            self.installOutputListeners()
            if source != .systemAudio { self.installProcessMonitor(for: source) }
            self.build()
        }
    }

    func stop(completion: (@MainActor @Sendable () -> Void)?) {
        queue.async {
            self.stopOnQueue()
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    private func stopOnQueue() {
        source = nil
        sink = nil
        rebuildWork?.cancel()
        rebuildWork = nil
        processMonitor?.cancel()
        processMonitor = nil
        capturedProcesses = []
        for (selector, listener) in outputListeners {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(system, &address, queue, listener)
        }
        outputListeners = []
        tearDown()
    }

    private func build(processes: [AudioObjectID]? = nil) {
        guard let source, let sink else { return }
        tearDown()
        revision += 1
        let revision = self.revision
        let description: CATapDescription
        if source == .systemAudio {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        } else {
            capturedProcesses = processes ?? AudioProcessSelection.available(for: source).map(\.id)
            guard !capturedProcesses.isEmpty else {
                publish(.waitingForProcess)
                return
            }
            description = CATapDescription(stereoMixdownOfProcesses: capturedProcesses)
        }
        description.name = "Song Ambient · \(source.rawValue)"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var result = AudioHardwareCreateProcessTap(description, &tap)
        guard result == noErr else { fail("Could not create the audio tap", result); return }

        var format = AudioStreamBasicDescription()
        var formatAddress = Self.address(kAudioTapPropertyFormat)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        result = AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &size, &format)
        guard result == noErr else { fail("Could not read the audio tap format", result); return }
        guard format.mSampleRate > 0, format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            fail("The output device did not provide 32-bit floating-point audio", kAudioDeviceUnsupportedFormatError)
            return
        }

        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Song Ambient Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        result = AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate)
        guard result == noErr else { fail("Could not create the private capture device", result); return }

        var frames: UInt32 = 0
        var framesAddress = Self.address(kAudioDevicePropertyBufferFrameSize)
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(aggregate, &framesAddress, 0, nil, &size, &frames)
        let pipeline = PCMPipeline(sampleRate: format.mSampleRate, frameCount: Int(frames)) { features in
            DispatchQueue.main.async { sink(.features(revision, features)) }
        }
        result = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, pcmQueue) { _, input, _, _, _ in
            pipeline.process(input)
        }
        guard result == noErr else { fail("Could not register the audio callback", result); return }
        result = AudioDeviceStart(aggregate, ioProc)
        guard result == noErr else { fail("Could not start system audio capture", result); return }
        started = true
        installFormatListener()
        if source != .spotify { installSilenceMonitor(for: pipeline) }
        publish(.listening)
    }

    private func installProcessMonitor(for source: AudioSource) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            guard let self, self.source == source else { return }
            let processes = AudioProcessSelection.available(for: source).map(\.id)
            if processes != self.capturedProcesses { self.build(processes: processes) }
        }
        processMonitor = timer
        timer.resume()
    }

    private func installSilenceMonitor(for pipeline: PCMPipeline) {
        let timer = DispatchSource.makeTimerSource(queue: pcmQueue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(15))
        timer.setEventHandler { pipeline.releaseIfStalled() }
        silenceMonitor = timer
        timer.resume()
    }

    private func installOutputListeners() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRebuild() }
        for selector in outputSelectors {
            var address = Self.address(selector)
            if AudioObjectAddPropertyListenerBlock(system, &address, queue, listener) == noErr {
                outputListeners.append((selector, listener))
            }
        }
    }

    private func installFormatListener() {
        let tap = self.tap
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.tap == tap else { return }
            self.scheduleRebuild()
        }
        var address = Self.address(kAudioTapPropertyFormat)
        if AudioObjectAddPropertyListenerBlock(tap, &address, queue, listener) == noErr { tapFormatListener = listener }
    }

    private func scheduleRebuild() {
        guard source != nil else { return }
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.build() }
        rebuildWork = work
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    private func publish(_ state: CaptureState) {
        guard let sink else { return }
        let revision = self.revision
        DispatchQueue.main.async { sink(.state(revision, state)) }
    }

    private func fail(_ message: String, _ code: OSStatus) {
        tearDown()
        publish(code == kAudioDevicePermissionsError ? .permissionDenied(code) : .failed(message, code))
    }

    private func tearDown() {
        silenceMonitor?.cancel()
        silenceMonitor = nil
        if let listener = tapFormatListener {
            var address = Self.address(kAudioTapPropertyFormat)
            AudioObjectRemovePropertyListenerBlock(tap, &address, queue, listener)
            tapFormatListener = nil
        }
        if let ioProc, aggregate != 0 {
            if started { AudioDeviceStop(aggregate, ioProc) }
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        started = false
        ioProc = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
