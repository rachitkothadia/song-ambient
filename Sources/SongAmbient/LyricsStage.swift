import SwiftUI
import AppKit
import AmbientCore

struct LyricsStage:View {
    @ObservedObject var model:AppModel
    @ObservedObject var music:MusicWatcher
    let audio:AudioCapture
    @ObservedObject var lyrics:LyricsService
    @Environment(\.openWindow) private var openWindow
    @State private var options=false
    @State private var chrome=true
    @FocusState private var stageFocused:Bool
    var body:some View{
        ZStack{
            LyricCanvas(model:model,music:music,audio:audio,lyrics:lyrics).ignoresSafeArea()
            if chrome{
                VStack{
                    HStack(spacing:13){
                        Button{WindowCoordinator.shared.closeStage();openWindow(id:"main")}label:{Image(systemName:"arrow.left")}.help("Back to studio")
                        OrbitMark().frame(width:22,height:22).foregroundStyle(.cyan)
                        VStack(alignment:.leading,spacing:2){Text(model.lyricsDemo ? "Constellation demo":music.title).font(.system(size:12,weight:.semibold)).lineLimit(1);Text(model.lyricsDemo ? "Authored timing sample":music.artist).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)}
                        Spacer()
                        Text((model.lyricsDemo ? "Word sync · DEMO":lyrics.timing)+" · Hinglish").font(.system(size:10)).foregroundStyle(.secondary)
                        Menu{ForEach(LyricStyle.allCases){style in Button{model.prefs.lyricStyle=style}label:{Label(style.rawValue,systemImage:model.prefs.lyricStyle==style ? "checkmark":style.symbol)}}}label:{Label(model.prefs.lyricStyle.rawValue,systemImage:model.prefs.lyricStyle.symbol)}.menuStyle(.borderlessButton).fixedSize()
                        Button{options.toggle()}label:{Image(systemName:"slider.horizontal.3")}.popover(isPresented:$options,arrowEdge:.top){ScrollView{LyricOptions(model:model).padding(18)}.frame(width:330,height:600).preferredColorScheme(.dark)}
                        Button{chrome=false}label:{Image(systemName:"eye.slash")}.help("Hide controls · H")
                    }.buttonStyle(.plain).padding(15).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16))
                    Spacer()
                    if model.lyricsDemo{Button("Use current song"){model.lyricsDemo=false}.buttonStyle(.bordered).padding(14).background(.ultraThinMaterial,in:Capsule())}else{StageTransport(model:model,music:music,lyrics:lyrics)}
                }.padding(22)
            }
        }.background(Color.black.ignoresSafeArea()).frame(minWidth:760,maxWidth:.infinity,minHeight:500,maxHeight:.infinity).preferredColorScheme(.dark)
            .background(WindowAttachment(role:.stage))
            .focusable().focused($stageFocused).focusEffectDisabled()
            .onKeyPress(.space) {
                guard model.audioSource != .systemAudio else { return .ignored }
                music.command("playpause")
                return .handled
            }
            .onKeyPress(.escape){WindowCoordinator.shared.exitFullScreen();return .handled}
            .onKeyPress("h"){chrome.toggle();return .handled}
            .onTapGesture(count:2){chrome.toggle()}
            .onAppear{chrome=true;stageFocused=true;model.stageVisible=true;WindowCoordinator.shared.setKeepStageAwake(model.prefs.keepAwake);if !music.identity.isEmpty{lyrics.load(music:music)}}
            .onChange(of:chrome){_,value in if !value{stageFocused=true}}
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.willCloseNotification)){note in
                if (note.object as? NSWindow)?.title == "Song Ambient · Lyrics" {model.stageVisible=false}
            }
    }
}

private struct StageTransport:View{
    @ObservedObject var model:AppModel
    @ObservedObject var music:MusicWatcher
    @ObservedObject var lyrics:LyricsService
    @State private var drag=0.0
    @State private var dragging=false
    var body:some View{
        VStack(spacing:9){
            if lyrics.loading{ProgressView().controlSize(.small)}
            if !lyrics.status.isEmpty && lyrics.words.isEmpty{Text(lyrics.status).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)}
            HStack(spacing:20){
                Group {
                    Button{music.toggleShuffle()}label:{Image(systemName:"shuffle").foregroundStyle(music.shuffle ? .cyan:.secondary)}.help("Shuffle")
                    Button{music.command("previous track")}label:{Image(systemName:"backward.fill")}
                    Button{music.command("playpause")}label:{Image(systemName:music.playing ? "pause.fill":"play.fill").font(.system(size:22)).frame(width:26)}
                    Button{music.command("next track")}label:{Image(systemName:"forward.fill")}
                    Text(PlayerCard.timestamp(music.position)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                    Slider(value:Binding(get:{dragging ? drag:music.position},set:{drag=$0}),in:0...max(1,music.duration),onEditingChanged:{value in if value{drag=music.position};dragging=value;if !value{music.seek(drag)}}).tint(.white).frame(maxWidth:320)
                    Text(PlayerCard.timestamp(music.duration)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                }.disabled(model.audioSource == .systemAudio)
                Button{lyrics.importFile(for:music)}label:{Image(systemName:"square.and.arrow.down")}.help("Import timed lyrics")
                Button{lyrics.load(music:music,force:true)}label:{Image(systemName:"arrow.clockwise")}.help("Refresh lyrics")
            }.buttonStyle(.plain).controlSize(.small)
        }.padding(17).frame(maxWidth:830).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:19))
    }
}
