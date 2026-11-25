import SwiftUI
import AppKit
import AmbientCore

struct MainWindowView:View {
    @ObservedObject var model:AppModel
    let audio:AudioCapture
    let music:MusicWatcher
    var body:some View {
        VStack(spacing:0){
            HStack(spacing:13){
                OrbitMark().foregroundStyle(LinearGradient(colors:[.cyan,.purple,.pink],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:35,height:35)
                VStack(alignment:.leading,spacing:3){Text("Song Ambient").font(.system(size:21,weight:.semibold,design:.rounded));Text("A little light. A whole new atmosphere.").font(.system(size:11)).foregroundStyle(.secondary)}
                Spacer()
                LiveStatus(model:model,music:music,audio:audio)
                Toggle("Lighting",isOn:$model.prefs.enabled).toggleStyle(.switch).labelsHidden().help("Toggle edge lighting")
            }.padding(.horizontal,24).padding(.top,18).padding(.bottom,13)
            HStack(spacing:6){
                ForEach(StudioTab.allCases,id:\.self){tab in
                    Button{model.selectedTab=tab}label:{Text(tab.rawValue).font(.system(size:12,weight:.semibold)).padding(.horizontal,16).padding(.vertical,9).background(model.selectedTab==tab ? Color.cyan.opacity(0.14):.clear,in:RoundedRectangle(cornerRadius:10)).foregroundStyle(model.selectedTab==tab ? .cyan:.secondary)}.buttonStyle(.plain)
                };Spacer()
                Text("2.1.1").font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary)
            }.padding(.horizontal,20).padding(.bottom,12)
            Divider().overlay(.white.opacity(0.025))
            Group{
                switch model.selectedTab {
                case .lighting: LightingPage(model:model,audio:audio,music:music)
                case .lyrics: LyricsStudioPage(model:model,music:music,audio:audio,lyrics:model.lyrics)
                case .settings: SettingsForm(model:model,music:music,audio:audio)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:760,minHeight:500)
            .background(Color(red:0.035,green:0.045,blue:0.065)).preferredColorScheme(.dark)
            .background(WindowAttachment(role:.studio))
    }
}

private struct LiveStatus:View {
    @ObservedObject var model:AppModel
    @ObservedObject var music:MusicWatcher
    @ObservedObject var audio:AudioCapture
    var body:some View{
        HStack(spacing:7){Circle().fill(audio.running ? .mint:.gray).frame(width:6,height:6);Text(music.playing ? "Playing · \(music.source?.rawValue ?? "Music")" : audio.running ? model.audioSource.rawValue : "Audio off").font(.system(size:10,weight:.medium)).lineLimit(1)}.padding(.horizontal,11).padding(.vertical,8).background(.white.opacity(0.045),in:Capsule())
    }
}

private struct LightingPage:View {
    @ObservedObject var model:AppModel
    let audio:AudioCapture
    let music:MusicWatcher
    var body:some View{
        GeometryReader{geometry in
            HStack(alignment:.top,spacing:18){
                ScrollView{
                    VStack(spacing:16){
                        LightingPreview(model:model,audio:audio,music:music)
                        PlayerCard(model:model,music:music,audio:audio,lyrics:model.lyrics,motion:model.motionArt,compact:true)
                        ConnectionCard(music:music,source:model.audioSource)
                    }.padding(.bottom,20)
                }.frame(width:max(285,min(400,geometry.size.width*0.42))).scrollIndicators(.hidden)
                ScrollView{
                    VStack(alignment:.leading,spacing:16){
                        StudioCard("EDGE EFFECT"){
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:100),spacing:7)],spacing:7){ForEach(RimStyle.allCases){style in
                                Button{model.prefs.rimStyle=style}label:{HStack(spacing:6){Image(systemName:style.symbol).frame(width:14);Text(style.rawValue).lineLimit(1);Spacer(minLength:0)}.font(.system(size:10,weight:.medium)).padding(9).background(model.prefs.rimStyle==style ? .cyan.opacity(0.17):.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8)).foregroundStyle(model.prefs.rimStyle==style ? .cyan:.secondary)}.buttonStyle(.plain)
                            }}
                            HStack{Text("Motion");Spacer();Picker("Motion",selection:$model.prefs.motion){ForEach(LightMotion.allCases,id:\.self){Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:130)}.padding(.top,5)
                            AudioControl(model:model,audio:audio,music:music)
                            ValueSlider(title:"Bass bounce",value:$model.prefs.bassBounce,range:0...2.5,unit:"×")
                            ValueSlider(title:"Flow speed",value:$model.prefs.animationSpeed,range:0.15...2,unit:"×")
                        }
                        StudioCard("PALETTE"){
                            Picker("Color source",selection:$model.prefs.overrideColor){Text("Custom palette").tag(true);Text("Album artwork").tag(false)}.pickerStyle(.segmented)
                            HStack(spacing:22){
                                WheelControl(label:"Primary",hex:manualHex(primary:true),brightness:manualBrightness(primary:true))
                                WheelControl(label:"Secondary",hex:manualHex(primary:false),brightness:manualBrightness(primary:false))
                            }.padding(.top,6)
                            HStack{Text("Editing a color selects Custom palette.").font(.system(size:10)).foregroundStyle(.secondary);Spacer();Picker("Gradient",selection:$model.prefs.gradient){Text("1 color").tag(1);Text("2 colors").tag(2)}.labelsHidden().frame(width:105)}
                        }
                        StudioCard("SHAPE & DISPLAY"){
                            ValueSlider(title:"Thickness",value:$model.prefs.thickness,range:1...20,unit:"pt")
                            ValueSlider(title:"Glow",value:$model.prefs.glow,range:0...80,unit:"pt")
                            Toggle("Wrap around the notch",isOn:$model.prefs.notch).toggleStyle(.switch)
                            DisplayChoices(model:model)
                        }
                    }.padding(.bottom,24)
                }.scrollIndicators(.visible)
            }.padding(20)
        }
    }
    private func manualHex(primary:Bool)->Binding<String>{Binding(get:{primary ? model.prefs.primary:model.prefs.secondary},set:{model.prefs.overrideColor=true;if primary{model.prefs.primary=$0}else{model.prefs.secondary=$0}})}
    private func manualBrightness(primary:Bool)->Binding<Double>{Binding(get:{primary ? model.prefs.primaryBrightness:model.prefs.secondaryBrightness},set:{model.prefs.overrideColor=true;if primary{model.prefs.primaryBrightness=$0}else{model.prefs.secondaryBrightness=$0}})}
}

private struct LightingPreview:View{
    @ObservedObject var model:AppModel
    let audio:AudioCapture
    let music:MusicWatcher
    var body:some View{
        ZStack{
            RoundedRectangle(cornerRadius:19).fill(LinearGradient(colors:[Color(red:0.075,green:0.095,blue:0.15),.black],startPoint:.topLeading,endPoint:.bottomTrailing))
            VStack(spacing:7){Text(model.prefs.rimStyle.rawValue).font(.system(size:24,weight:.light,design:.rounded));Text("Light that listens.").font(.system(size:11)).foregroundStyle(.secondary);Button("Preview on display"){model.previewLighting()}.controlSize(.small).padding(.top,5)}
            RimView(model:model,audio:audio,music:music,notchWidth:58,notchHeight:10,miniature:true)
        }.frame(height:176).clipShape(RoundedRectangle(cornerRadius:19)).overlay(RoundedRectangle(cornerRadius:19).stroke(.white.opacity(0.05)))
    }
}

struct StudioCard<Content:View>:View{
    let title:String
    @ViewBuilder var content:Content
    init(_ title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View{VStack(alignment:.leading,spacing:13){Text(title).font(.system(size:9,weight:.semibold)).tracking(1.7).foregroundStyle(.secondary);content}.font(.system(size:12)).padding(17).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(.white.opacity(0.055)))}
}

struct ValueSlider:View{
    let title:String
    @Binding var value:Double
    let range:ClosedRange<Double>
    let unit:String
    var body:some View{VStack(spacing:5){HStack{Text(title);Spacer();Text(unit=="pt" ? "\(Int(value)) pt":String(format:"%.1f×",value)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)};Slider(value:$value,in:range).controlSize(.small).tint(.cyan)}}
}

private struct AudioControl: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audio: AudioCapture
    @ObservedObject var music: MusicWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.audioSource.rawValue, systemImage: audio.running ? "waveform" : "speaker.slash").font(.system(size: 10))
                Spacer()
                if case .failed = audio.state { retry }
                if case .permissionDenied = audio.state { retry }
                Button(model.syncRequested ? "Stop" : "Enable") {
                    if model.syncRequested { model.stopAudio() } else { model.startAudio() }
                }.controlSize(.mini)
            }
            Text(audio.state.description(for: model.audioSource)).font(.system(size: 10))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.audioSource == .appleMusic, music.playing, audio.running, audio.level <= 0.001 {
                Text("Music is playing, but the tap is silent. Check the output device. macOS may restrict capture of some tracks.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                Meter(label: "BASS", value: audio.features.bass, color: .cyan)
                Meter(label: "MID", value: audio.features.mid, color: .purple)
                Meter(label: "AIR", value: audio.features.treble, color: .pink)
            }
        }.padding(10).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private var retry: some View {
        Button("Retry") { model.startAudio() }.controlSize(.mini)
    }
}
private struct Meter:View{
    let label:String,value:Double,color:Color
    var body:some View{VStack(alignment:.leading,spacing:4){Text(label).font(.system(size:8,weight:.medium)).foregroundStyle(.secondary);GeometryReader{g in ZStack(alignment:.leading){Capsule().fill(.white.opacity(0.04));Capsule().fill(color.opacity(0.7)).frame(width:max(0,g.size.width*value))}}.frame(height:3)}.frame(maxWidth:.infinity)}
}

struct ConnectionCard: View {
    @ObservedObject var music: MusicWatcher
    let source: AudioSource

    var body: some View {
        if source.playerBundleID != nil {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: music.connected ? "checkmark.circle.fill" : "link").foregroundStyle(music.connected ? .mint : .cyan)
                    Text(music.connected ? "Music connected" : "Music connection").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button(music.connected ? "Refresh" : "Connect") { music.connect() }.controlSize(.small)
                }
                Text(music.status).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !music.connected {
                    Button(source == .appleMusic ? "Open Music" : "Open Spotify") { music.openSelectedPlayer() }.controlSize(.mini)
                }
            }.padding(14).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
        }
    }
}

struct DisplayChoices:View{
    @ObservedObject var model:AppModel
    var body:some View{VStack(alignment:.leading,spacing:9){ForEach(model.screens,id:\.ambientID){screen in
        Toggle(isOn:Binding(get:{model.prefs.displays.isEmpty || model.prefs.displays.contains(screen.ambientID)},set:{selected in
            var ids=model.prefs.displays.isEmpty ? model.screens.map(\.ambientID):model.prefs.displays
            ids.removeAll{$0=="none" || $0==screen.ambientID};if selected{ids.append(screen.ambientID)};model.prefs.displays=ids.isEmpty ? ["none"]:ids
        })){Label(screen.localizedName,systemImage:"display").font(.system(size:11))}.toggleStyle(.checkbox)
    }}}
}

private struct LyricsStudioPage:View{
    @ObservedObject var model:AppModel
    let music:MusicWatcher,audio:AudioCapture
    @ObservedObject var lyrics:LyricsService
    @Environment(\.openWindow) private var openWindow
    @State private var versions=false
    var body:some View{
        HStack(alignment:.top,spacing:18){
            VStack(alignment:.leading,spacing:15){
                ZStack{Color.black;LyricCanvas(model:model,music:music,audio:audio,lyrics:lyrics,preview:true)}.clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.07))).frame(maxHeight:.infinity)
                HStack{Button{if WindowCoordinator.shared.prepareStage(display:model.prefs.stageDisplay){openWindow(id:"lyrics")}}label:{Label("Enter immersive lyrics",systemImage:"arrow.up.left.and.arrow.down.right").font(.system(size:12,weight:.semibold))}.buttonStyle(.borderedProminent).tint(.cyan)
                    Button("Import"){model.lyricsDemo=false;lyrics.importFile(for:music)}.help("Import timed lyrics");Button("Recordings"){versions=true}.disabled(!music.connected);Spacer();Button{model.lyricsDemo=false;lyrics.load(music:music,force:true)}label:{Image(systemName:"arrow.clockwise")}.help("Refresh lyrics")}
                HStack{Text(model.lyricsDemo ? "Word sync · DEMO":lyrics.timing).font(.system(size:10,weight:.semibold)).foregroundStyle(.cyan);Text(model.lyricsDemo ? "Authored animation sample":lyrics.provenance).font(.system(size:10)).foregroundStyle(.secondary);Spacer();Button(model.lyricsDemo ? "Use current song":"Preview demo"){model.demoStart=Date();model.lyricsDemo.toggle()}.controlSize(.mini)}
                Text(model.lyricsDemo ? "A timed sample to explore every style. Switch back to see your current song.":lyrics.status).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            ScrollView{LyricOptions(model:model).padding(.bottom,20)}.frame(width:270)
        }.padding(20).task{if !music.identity.isEmpty{lyrics.load(music:music)}}.sheet(isPresented:$versions){LyricVersions(model:model,music:music,lyrics:lyrics)}
    }
}

struct LyricOptions:View{
    @ObservedObject var model:AppModel
    var body:some View{
        VStack(spacing:15){
            StudioCard("LYRIC EXPERIENCE"){
                Picker("Style",selection:$model.prefs.lyricStyle){ForEach(LyricStyle.allCases){Label($0.rawValue,systemImage:$0.symbol).tag($0)}}
                Picker("Font",selection:$model.prefs.lyricFont){ForEach(LyricFont.allCases){Text($0.rawValue).tag($0)}}
                ValueSlider(title:"Text size",value:$model.prefs.lyricSize,range:24...76,unit:"pt")
                Button("Reset text size"){model.prefs.lyricSize=42}.controlSize(.small)
                Toggle("Keep screen awake",isOn:$model.prefs.keepAwake).toggleStyle(.switch)
                Toggle("Desktop lyrics",isOn:$model.prefs.desktopLyrics).toggleStyle(.switch).help("Non-lockscreen visibility: show a click-through lyric constellation on the desktop. Hidden when locked.")
            }
            StudioCard("LYRIC COLORS"){
                Toggle("Auto sync with lighting",isOn:$model.prefs.lyricAutoColor).toggleStyle(.switch)
                ColorPicker("Lyric text",selection:color(\.lyricText),supportsOpacity:false)
                ColorPicker("Highlight",selection:color(\.lyricHighlight),supportsOpacity:false)
                ColorPicker("Secondary text",selection:color(\.lyricSecondary),supportsOpacity:false)
                Button("Reset colors"){model.prefs.lyricText="EBEFF8";model.prefs.lyricHighlight="8BDAFF";model.prefs.lyricSecondary="8992AF";model.prefs.lyricAutoColor=true}.controlSize(.small)
            }
            StudioCard("DISPLAY & TIMING"){
                Picker("Display",selection:$model.prefs.stageDisplay){Text("Current display").tag("automatic");ForEach(model.screens,id:\.ambientID){Text($0.localizedName).tag($0.ambientID)}}
                    .onChange(of:model.prefs.stageDisplay){_,value in WindowCoordinator.shared.moveStage(to:value)}
                HStack{Text("Lyric offset");Spacer();Text(String(format:"%+.2f s",model.prefs.lyricsOffset)).font(.system(size:10,design:.monospaced));Stepper("Offset",value:$model.prefs.lyricsOffset,in:-60...60,step:0.05).labelsHidden()}
                Button("Reset offset"){model.prefs.lyricsOffset=0}.controlSize(.small)
                Text("Hindi displays in Latin. Exact word cues are used when available; line-only lyrics use estimated word pacing, never whole sentences.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private func color(_ key:WritableKeyPath<Preferences,String>)->Binding<Color>{Binding(get:{Color(hex:model.prefs[keyPath:key])},set:{model.prefs.lyricAutoColor=false;model.prefs[keyPath:key]=$0.hex})}
}

struct SettingsForm:View{
    @ObservedObject var model:AppModel
    @ObservedObject var music:MusicWatcher
    @ObservedObject var audio:AudioCapture
    var body:some View{
        ScrollView{
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:18){
                StudioCard("ON LAUNCH"){
                    Toggle("Connect to music automatically",isOn:$model.prefs.autoConnect)
                    Toggle("Start audio capture automatically",isOn:$model.prefs.autoSync)
                    Toggle("Fetch lyrics automatically",isOn:$model.prefs.autoLyrics)
                    Text("Lyrics requests send the current track details to LRCLIB. Audio analysis stays on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                StudioCard("PLAYER"){
                    Toggle("Floating player",isOn:$model.prefs.showPlayer)
                    Button("Preview player"){model.player?.showPreview()}
                    Toggle("Animated album artwork",isOn:$model.prefs.animatedArtwork)
                    TextField("Artwork region",text:$model.prefs.storefront)
                }
                StudioCard("AUDIO SOURCE"){
                    Picker("Audio Source",selection:Binding(get:{model.audioSource},set:{model.selectAudioSource($0)})){
                        ForEach(AudioSource.allCases,id:\.self){source in Text(source.rawValue).tag(source)}
                    }
                    AudioControl(model:model,audio:audio,music:music)
                    ConnectionCard(music:music,source:model.audioSource)
                    if music.crossfadeCorrection>0{Text(String(format:"Spotify crossfade: %.1f s · accounted for in lyric lookup",music.crossfadeCorrection)).font(.system(size:10)).foregroundStyle(.secondary)}
                    ForEach(music.diagnostics,id:\.self){Text($0).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                    Button("Open Privacy & Security"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security")!)}
                }
                StudioCard("YOUR WORKSPACE"){
                    Text("Close the studio to keep Song Ambient in the menu bar. Reopen it from the orbit icon.").font(.system(size:12)).foregroundStyle(.secondary)
                    DisplayChoices(model:model)
                    Text("Song Ambient 2.1.1").font(.system(size:11,weight:.semibold))
                }
            }.padding(20)
        }.toggleStyle(.switch)
    }
}
