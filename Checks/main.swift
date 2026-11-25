import AmbientCore
import Foundation
import Metal
import AppKit
import CoreAudio
import Synchronization

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func timesEqual(_ actual: [Double], _ expected: [Double]) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy { abs($0 - $1) < 0.000001 }
}
let repeated = LyricsParser.parse("[00:01.2][00:07.023]Repeated line\n[00:03:45]Other line")
verify(repeated.map(\.text) == ["Repeated line", "Other line", "Repeated line"], "Multiple timestamps must repeat the supplied text in chronological order")
verify(timesEqual(repeated.map(\.time), [1.2, 3.45, 7.023]), "Provider timestamp precision must be preserved")
verify(Set(repeated.map(\.id)).count == 3, "Repeated lyric text must have distinct line identities")
let negative = LyricsParser.parse("[offset:-250]\n[00:00.100]First\n[01:02.50]\n[01:04]Last")
verify(timesEqual(negative.map(\.time), [0, 62.25, 63.75]), "Signed millisecond offsets and nonnegative playback coordinates")
verify(negative[1].text.isEmpty, "Timed instrumental lines must remain present")
verify(LyricsParser.parse("Untimed lyrics\n[ar:Someone]\n[ti:Song]").isEmpty, "Untimed text must not receive invented timestamps")
let positive = LyricsParser.parse("[offset:+1000]\n[00:10]A\n[00:20]B")
verify(timesEqual(positive.map(\.time), [11, 21]) && positive.count == 2, "Positive offsets must not interpolate extra lines")
print("Passed 7 lyric timing checks.")

let enhanced=LyricsParser.parse("[00:02.000]<00:02.125>Hello <00:02.875>world<00:03.250>")
verify(timesEqual(enhanced[0].words.map(\.time),[2.125,2.875]),"Enhanced LRC must preserve supplied word precision")
verify(enhanced[0].words.last?.end == 3.25,"An explicit terminal timestamp must stop the final word")
verify(repeated.allSatisfy(\.words.isEmpty),"Line-only lyrics must not receive invented word timing")
let yaml="""
version: '1.0'
metadata:
  title: Timing fixture
  offset_ms: 0
lines:
  - text: 'नमस्ते world'
    start_ms: 1200
    end_ms: 4000
    words:
      - text: 'नमस्ते '
        start_ms: 1250
        end_ms: 1700
      - text: world
        start_ms: 2250
        end_ms: 3000
"""
let rich=try LyricsParser.parseLyricsfile(yaml),words=LyricTimeline.words(in:rich)
verify(timesEqual(words.map(\.time),[1.25,2.25]),"Lyricsfile milliseconds must remain absolute")
verify(words[0].text.hasSuffix(" ") && words[0].end == 1.7,"Provider spacing and ends must be preserved")
verify(LyricTimeline.activeWord(in:words,at:1.4)==0 && LyricTimeline.activeWord(in:words,at:1.9)==nil && LyricTimeline.activeWord(in:words,at:3.1)==nil,"Word gaps and final ends must not keep highlighting")
verify(Hinglish.render("café दुनिया Love") .hasPrefix("café ") && Hinglish.render("café दुनिया Love").hasSuffix(" Love"),"Hinglish must preserve existing Latin text exactly")
verify(!Hinglish.render("दुनिया").unicodeScalars.contains{(0x0900...0x097F).contains($0.value)},"Hindi script must display in Latin")
verify(Hinglish.render("तुम दिल प्यार मैं हैं")=="tum dil pyar main hain","Hindi final schwa and vowel nasalization should read naturally")
do{_ = try LyricsParser.parseLyricsfile(yaml.replacingOccurrences(of:"offset_ms: 0",with:"offset_ms: 100"));fatalError("Undefined offset semantics must not be guessed")}catch LyricsParser.TimingError.unsupportedOffset{}
print("Passed 10 word-timing, gap, import, and Hinglish checks.")

func tone(_ hz:Double,_ amplitude:Double,_ block:Int)->[Float]{(0..<1024).map{Float(sin(Double(block*1024+$0)*2 * .pi*hz/48000)*amplitude)}}
var lowEngine=BeatEngine(),highEngine=BeatEngine(),low=AudioFeatures(),high=AudioFeatures()
for block in 0..<70{let time=Double(block)*1024/48000;low=lowEngine.analyze(tone(70,0.2,block),sampleRate:48000,time:time);high=highEngine.analyze(tone(5000,0.2,block),sampleRate:48000,time:time)}
verify(low.bass > high.bass*2,"Bass energy must distinguish a low kick from equal-amplitude treble")
verify(high.treble > low.treble*2,"Treble response must be separate from bass")
verify(low.beatIndex<=3,"Sustained tones must not fabricate repeated beats")
var silence=AudioFeatures()
for block in 70..<300{silence=lowEngine.analyze([Float](repeating:0,count:1024),sampleRate:48000,time:Double(block)*1024/48000)}
verify(silence.level==0 && silence.bass==0,"Silence must decay fully to zero")
var pulseEngine=BeatEngine(),pulse=AudioFeatures()
for block in 0..<180{let phase=block%24;let amplitude=phase<4 ? 0.3*exp(-Double(phase)*0.6):0;pulse=pulseEngine.analyze(tone(70,amplitude,block),sampleRate:48000,time:Double(block)*1024/48000)}
verify((6...9).contains(pulse.beatIndex),"Bass attacks must trigger distinct beat impulses")
var spring=BounceSpring();spring.impulse(1);var peak=0.0,minimum=0.0
for _ in 0..<240{let value=spring.step(delta:1.0/60,target:0);peak=max(peak,value);minimum=min(minimum,value)}
verify(peak>0.3 && minimum<0 && abs(spring.value)<0.001,"Bass spring must overshoot, rebound, and settle")
print("Passed 6 bass, onset, silence, and bounce checks.")

let lineSource=LyricsParser.parse("[00:00]Yeh raat aur hum\n[00:08]\n[00:10]One more star\n[00:16]")
let presentation=WordPresentation(lines:lineSource,seed:72)
verify(presentation.tokens.map(\.text)==["Yeh","raat","aur","hum","One","more","star"],"Line input must display individual words, never sentences")
verify(presentation.hasEstimatedWords,"Line-based pacing must be labeled estimated")
verify(presentation.frame(at:0.1,duration:18).index==0 && presentation.frame(at:7.5,duration:18).index==3,"Word selection must advance within a supplied line interval")
verify(presentation.frame(at:8.5,duration:18).index==nil && presentation.frame(at:16.5,duration:18).index==nil,"Instrumental lines must clear word motion")
verify(presentation.frame(at:0.1,duration:18).index==0,"Seeking backward must restore the earlier word")
verify(lineSource[0].words.isEmpty && lineSource.map(\.time)==[0,8,10,16],"Estimated display pacing must not manufacture provider word timestamps")
let exactPresentation=WordPresentation(lines:rich,seed:72)
verify(!exactPresentation.hasEstimatedWords && exactPresentation.frame(at:1.4,duration:5).exact,"Supplied single-word cues must retain exact sync")
verify(exactPresentation.frame(at:1.9,duration:5).index==nil,"Exact word gaps must stay empty")
let segmented=WordPresentation(lines:[LyricLine(time:0,end:4,text:"two words",id:0,words:[LyricWord(time:0,end:4,text:"two words",id:0)])])
verify(segmented.hasEstimatedWords && segmented.tokens.count==2,"A timed phrase must still show words and disclose estimated subword pacing")
verify(WordPresentation(lines:[]).frame(at:5,duration:10).index==nil,"Empty lyrics must not generate text")
let stars=ConstellationLayout.positions(count:150,seed:9527)
verify(stars.allSatisfy{(0.14...0.86).contains($0.x) && (0.23...0.75).contains($0.y)},"Constellation labels must stay within safe screen margins")
verify(stars==ConstellationLayout.positions(count:150,seed:9527),"Star positions must remain stable between frames")
verify(stars != ConstellationLayout.positions(count:150,seed:9528),"A new scene seed must create a different constellation")
let movements=zip(stars,stars.dropFirst()).map{($1.x-$0.x,$1.y-$0.y)}
verify(movements.contains{$0.0>0.1} && movements.contains{$0.0 < -0.1} && movements.contains{$0.1>0.1} && movements.contains{$0.1 < -0.1},"Constellations must move in all directions, not along a forward rail")
let distances=zip(stars,stars.dropFirst()).map{$0.distance(to:$1)}
verify((distances.max() ?? 0)-(distances.min() ?? 0)>0.3,"Consecutive words must use visibly different travel distances")
verify(SpotifyAudioPolicy.includes(bundleID:"com.spotify.client") && SpotifyAudioPolicy.includes(bundleID:"com.spotify.client.helper"),"Spotify and its audio helpers must be included")
verify(!SpotifyAudioPolicy.includes(bundleID:"net.whatsapp.WhatsApp") && !SpotifyAudioPolicy.includes(bundleID:"com.apple.Music"),"WhatsApp and Apple Music must be excluded from capture")
verify(!SpotifyAudioPolicy.shouldRender(playing:false,connected:true,spotifySource:true,capturing:true,level:1),"Paused Spotify must never light the display even if another app is loud")
verify(!SpotifyAudioPolicy.shouldRender(playing:true,connected:true,spotifySource:true,capturing:true,level:0),"Other apps cannot light the display when the Spotify tap is silent")
verify(SpotifyAudioPolicy.shouldRender(playing:true,connected:true,spotifySource:true,capturing:true,level:0.2),"Active Spotify audio must drive the display")
print("Passed word presentation, random constellation geometry, and Spotify isolation checks.")
verify(SpotifyTimingSettings.parseCrossfadeSeconds("audio.crossfade_v2=true\naudio.crossfade.time_v2=12000")==12,"Enabled crossfade must restore full recording length for lookup")
verify(SpotifyTimingSettings.parseCrossfadeSeconds("audio.crossfade_v2=false\naudio.crossfade.time_v2=12000")==0,"Disabled crossfade must not alter catalog matching")
verify(SpotifyTimingSettings.parseCrossfadeSeconds("audio.crossfade=true\naudio.crossfade.time=2500")==2.5,"Legacy crossfade settings must retain millisecond precision")
verify(SpotifyTimingSettings.parseCrossfadeSeconds("audio.crossfade_v2=true\naudio.crossfade.time_v2=nan")==0,"Malformed settings must not introduce guessed duration corrections")

verify(AudioSource.restored(from: nil) == .spotify && AudioSource.restored(from: "invalid") == .spotify,
       "Existing and invalid source preferences must default to Spotify")
for source in AudioSource.allCases {
    verify(AudioSource.restored(from: source.rawValue) == source, "Source selection must round-trip")
}
verify(AudioSource.appleMusic.includesProcess(bundleID: "com.apple.Music"), "Music must be included in its process tap")
verify(AudioSource.appleMusic.includesProcess(bundleID: "com.apple.Music.helper"), "Music-specific helpers must be included")
for bundleID in ["com.apple.Safari", "com.apple.MusicOther", "com.spotify.client", "com.apple.audio.MusicPlayback"] {
    verify(!AudioSource.appleMusic.includesProcess(bundleID: bundleID), "Apple Music must be isolated from other apps")
    verify(AudioSource.systemAudio.includesProcess(bundleID: bundleID), "System Audio must accept audio regardless of app")
}
for playing in [false, true] {
    for connected in [false, true] {
        for capturing in [false, true] {
            for level in [0.0, 0.001, 0.2] {
                let legacy = SpotifyAudioPolicy.shouldRender(playing: playing, connected: connected, spotifySource: true, capturing: capturing, level: level)
                verify(AudioSource.spotify.shouldRender(playing: playing, connected: connected, capturing: capturing, level: level) == legacy,
                       "The Spotify lighting gate must match the original")
                for source in [AudioSource.systemAudio, .appleMusic] {
                    verify(source.shouldRender(playing: playing, connected: connected, capturing: capturing, level: level) == (capturing && level > 0.001),
                           "New audio sources must gate on captured PCM independently of metadata")
                }
            }
        }
    }
}
verify(AudioSource.systemAudio.playerBundleID == nil, "System Audio must not require a player")
print("Passed source persistence, process isolation, and lighting gate checks.")

let sampleRate = 48_000.0
let referenceMono = tone(1250, 0.2, 0)
let interleaved = referenceMono.enumerated().flatMap { index, value -> [Float] in
    index.isMultiple(of: 2) ? [value, -value] : [0, value]
}
let recorded = Mutex<[AudioFeatures]>([])
let pcm = PCMPipeline(sampleRate: sampleRate, frameCount: referenceMono.count) { features in
    recorded.withLock { $0.append(features) }
}
interleaved.withUnsafeBytes { bytes in
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
        mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: UnsafeMutableRawPointer(mutating: bytes.baseAddress)
    ))
    pcm.process(&list, time: 1)
}
let received = recorded.withLock { $0.first! }
var baselineEngine = BeatEngine()
var baseline = baselineEngine.analyze(referenceMono, sampleRate: sampleRate, time: 1)
// Reproduce the original Hann window and logarithmic bins with an independent DFT.
let windowed: [Double] = (0..<512).map { index in
    let sample = Double(referenceMono[index])
    let phase: Double = 2.0 * Double.pi * Double(index) / 511.0
    let cosine: Double = cos(phase)
    let weight: Double = 0.5 - 0.5 * cosine
    return sample * weight
}
for band in 0..<16 {
    let lo = max(1, Int(pow(256.0, Double(band) / 16)))
    let hi = min(255, max(lo + 1, Int(pow(256.0, Double(band + 1) / 16))))
    let energy = (lo..<hi).map { bin -> Double in
        var real = 0.0, imaginary = 0.0
        for (index, sample) in windowed.enumerated() {
            let phase = 2 * Double.pi * Double(bin * index) / 512
            real += sample * cos(phase); imaginary += sample * sin(phase)
        }
        return hypot(real, imaginary)
    }.max() ?? 0
    baseline.bands[band] = min(1, log1p(energy * 2) / 4)
}
verify(timesEqual(received.bands, baseline.bands), "PCM must retain the original window, DFT bands, and magnitude scaling")
baseline.bands = received.bands
verify(received == baseline, "PCM must retain the original strongest-channel features from BeatEngine")
let left = stride(from: 0, to: interleaved.count, by: 2).map { interleaved[$0] }
let right = stride(from: 1, to: interleaved.count, by: 2).map { interleaved[$0] }
let planarRecorded = Mutex<AudioFeatures?>(nil)
let planarPCM = PCMPipeline(sampleRate: sampleRate, frameCount: 0) { features in
    planarRecorded.withLock { $0 = features }
}
let planar = AudioBufferList.allocate(maximumBuffers: 2)
defer { free(planar.unsafeMutablePointer) }
left.withUnsafeBytes { leftBytes in
    right.withUnsafeBytes { rightBytes in
        planar[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: UnsafeMutableRawPointer(mutating: leftBytes.baseAddress))
        planar[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightBytes.count), mData: UnsafeMutableRawPointer(mutating: rightBytes.baseAddress))
        planarPCM.process(planar.unsafePointer, time: 1)
    }
}
verify(planarRecorded.withLock { $0 } == received, "Planar and interleaved PCM must yield identical renderer features")
for tick in 2...30 { pcm.releaseIfStalled(at: 1 + Double(tick) / 10) }
verify(recorded.withLock { $0.last?.level } == 0, "A stalled tap must decay all the way to silence")
print("Passed PCM parity, planar stereo, and stalled-input release checks.")

if CommandLine.arguments.contains("--spotify-route") || CommandLine.arguments.contains("--apple-music-route") {
    let route: AudioSource = CommandLine.arguments.contains("--spotify-route") ? .spotify : .appleMusic
    let selected = AudioProcessSelection.available(for: route)
    print("\(route.rawValue) tap source count: \(selected.count)")
    if route == .spotify { print("Configured crossfade lookup correction: \(SpotifyTimingSettings.crossfadeSeconds()) seconds") }
    for source in selected { print("Selected process \(source.id): \(source.bundleID)") }
}
if CommandLine.arguments.contains("--allow-missing-metal"), MTLCreateSystemDefaultDevice() == nil {
    print("GPU checks skipped because this host has no Metal device.")
    exit(0)
}

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("No Metal device") }
let library = try device.makeLibrary(source: PlasmaShader.source, options: nil)
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "rimVertex")
descriptor.fragmentFunction = library.makeFunction(name: "rimFragment")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
let width = 192, height = 128
let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
textureDescriptor.usage = [.renderTarget, .shaderRead]
textureDescriptor.storageMode = .shared
let texture = device.makeTexture(descriptor: textureDescriptor)!
let pass = MTLRenderPassDescriptor()
pass.colorAttachments[0].texture = texture
pass.colorAttachments[0].loadAction = .clear
pass.colorAttachments[0].storeAction = .store
pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
var uniforms: [SIMD4<Float>] = [SIMD4(192,128,1,1), SIMD4(1,0.2,0.4,0), SIMD4(0.2,0.3,1,0), SIMD4(1.3,0.21,12,0.5), SIMD4(0,0,0.3,0.5),SIMD4(0.2,0.3,0.1,0.15),SIMD4(0,1.4,0.8,0)]
for _ in 0..<4{uniforms.append(SIMD4(0.1,0.2,0.4,0.7))}
var hashes=Set<Int>()
var coverage:[Int:Int]=[:]
for style in [1,2,3,4,8,9]{
uniforms[6].x=Float(style)
let command = queue.makeCommandBuffer()!
let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
encoder.setRenderPipelineState(pipeline)
uniforms.withUnsafeBufferPointer { encoder.setFragmentBytes($0.baseAddress!, length: $0.count * MemoryLayout<SIMD4<Float>>.stride, index: 0) }
encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
verify(command.status == .completed, "The GPU must finish the rim render")
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width*4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0) }
verify(pixels[(64*width+96)*4+3] == 0, "The screen center must remain fully transparent")
verify((0..<width*height).contains{let x=$0%width,y=$0/width;return (x<24 || y<24 || x>=width-24 || y>=height-24) && pixels[$0*4+3]>0}, "Every style must produce visible perimeter lighting")
var hasher=Hasher();hasher.combine(pixels);hashes.insert(hasher.finalize())
coverage[style]=stride(from:3,to:pixels.count,by:4).filter{pixels[$0]>32}.count
if let flag=CommandLine.arguments.firstIndex(of:"--previews"),CommandLine.arguments.indices.contains(flag+1){
    let folder=URL(fileURLWithPath:CommandLine.arguments[flag+1],isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
    for i in stride(from:0,to:pixels.count,by:4){bitmap.bitmapData![i]=pixels[i+2];bitmap.bitmapData![i+1]=pixels[i+1];bitmap.bitmapData![i+2]=pixels[i];bitmap.bitmapData![i+3]=255}
    try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("edge-\(style).png"))
}
}
verify(hashes.count==6,"All six effects must render distinct pixels")
verify(coverage[9]!<coverage[1]!/3,"Minimal must stay a hairline while Aurora has broad light")
verify(coverage[2]!<coverage[1]!/2,"Comet must remain a sparse traveling light, not another full band")
print("Passed GPU rendering, transparency, and distinct silhouette checks for 6 effects on \(device.name).")
