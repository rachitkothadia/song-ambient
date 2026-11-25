import SwiftUI
import AppKit

@main struct SongAmbientApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("Song Ambient", id: "main") {
            MainWindowView(model: model, audio: model.audio, music: model.music)
                .task { if model.overlay == nil { model.start() }; delegate.model = model }
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.automatic)
        Window("Lyrics Studio",id:"lyrics") {
            LyricsStage(model:model,music:model.music,audio:model.audio,lyrics:model.lyrics)
        }.defaultSize(width:1100,height:720).windowResizability(.automatic).defaultLaunchBehavior(.suppressed).restorationBehavior(.disabled)
        MenuBarExtra {
            MenuContent(model: model)
        }label:{Image(nsImage:Branding.menuIcon).renderingMode(.template)}
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { OrbitMark().frame(width:20,height:20).foregroundStyle(.cyan);Text("Song Ambient").font(.headline); Spacer(); Toggle("Lighting", isOn: $model.prefs.enabled).labelsHidden().toggleStyle(.switch) }
            PlayerCard(model: model, music: model.music, audio: model.audio, lyrics: model.lyrics, motion: model.motionArt, compact: true)
            Button("Open studio…") { WindowCoordinator.shared.revealStudio();openWindow(id:"main") }
            Button("Immersive lyrics…") { if WindowCoordinator.shared.prepareStage(display:model.prefs.stageDisplay){openWindow(id:"lyrics")} }
            Picker("Lyric style",selection:$model.prefs.lyricStyle){ForEach(LyricStyle.allCases){Text($0.rawValue).tag($0)}}
            Picker("Border",selection:$model.prefs.rimStyle){ForEach(RimStyle.allCases){Text($0.rawValue).tag($0)}}
            Toggle("Keep screen awake in lyrics",isOn:$model.prefs.keepAwake)
            Toggle("Non-lockscreen lyric visibility",isOn:$model.prefs.desktopLyrics)
            Button("Preview lighting") { model.previewLighting() }
            if model.audioSource.playerBundleID != nil {
                Button("Connect \(model.audioSource.rawValue)") { model.music.connect() }
            }
            Divider()
            Button("Quit Song Ambient") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }.padding(16).frame(width: 350).preferredColorScheme(.dark)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url=Bundle.main.url(forResource:"SongAmbient",withExtension:"icns"),let image=NSImage(contentsOf:url){NSApp.applicationIconImage=image}
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.audio.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
