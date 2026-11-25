<div align="center">

<img src="Assets/SongAmbient-icon.png" width="104" alt="Song Ambient icon">

# Song Ambient

### Your music. Around your screen.

**Free, open-source audio-reactive edge lighting and animated lyrics for macOS.**

An independent, MIT-licensed alternative to Lumn. No app subscription. No activation key.

[![MIT license](https://img.shields.io/badge/license-MIT-8bdaff.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black.svg)](https://github.com/rachitkothadia/song-ambient/releases/latest)
[![Native Swift](https://img.shields.io/badge/native-Swift%20%2B%20Metal-f05138.svg)](Package.swift)
[![Download](https://img.shields.io/github/v/release/rachitkothadia/song-ambient?label=download&color=8bdaff)](https://github.com/rachitkothadia/song-ambient/releases/latest)

[**Upstream Spotify release for Apple silicon**](https://github.com/rachitkothadia/song-ambient/releases/latest) · [Build from source](#build-from-source) · [Report a bug](https://github.com/rachitkothadia/song-ambient/issues)

<img src="docs/hero.svg" width="100%" alt="Illustration: a glowing music-reactive desktop border surrounding a connected constellation of individual lyric words">

<sub>Constellation illustration. Actual colors, words and placement follow your settings and lyric data.</sub>

</div>

## Make your desktop part of the song

A bass hit should feel like a bass hit. Song Ambient analyzes audio from the source you choose on your Mac and turns it into light around your display. Open Lyrics Studio and let individual words fly, branch, bend, or connect into a constellation.

- Choose **System Audio**, **Apple Music**, or **Spotify** in Studio → Settings. All three feed the same audio analysis and six edge effects.
- **Six border effects.** Aurora, Comet, **Waves**, Spectrum, Ribbons and Minimal have different silhouettes. Waves is back, with traveling crests and bass-driven bounce.
- **Bass with a little spring.** Separate bass, mid and treble analysis, sixteen frequency bands, onset detection and damped rebound drive the lighting.
- **Nine lyric looks.** Ship, Fisheye, Visual, Fisheye Visual, Codestyle, Codestyle Visual, Branches, Web and Constellation render individual words.
- **A constellation that wanders.** Words visit random star positions with curved travel, varied distances and directions, and glowing connections.
- **Hinglish display.** Hindi script is romanized into Latin characters; existing English and Latin text stays intact.
- **A native Mac companion.** Resizable studio, full-screen stage, optional desktop lyrics and a floating player. Close the studio to remove its Dock icon and keep it in the menu bar.
- **Make it yours.** Custom or album-derived colors, seven fonts, lyric size and offset, display selection, glow, thickness and motion controls. Custom palette and music sync start enabled on a fresh install.

## Six ways to light the edges

| Effect | What you see |
| --- | --- |
| **Aurora** | Broad, soft, irregular swells of light |
| **Comet** | A bright traveling head with a fading tail |
| **Waves** | Rolling, sharply outlined crests that react to the music |
| **Spectrum** | Separated bars driven by measured frequency bands |
| **Ribbons** | Three fine, separated flowing strands |
| **Minimal** | A restrained, quiet hairline |

## Get started

1. [Build from source](#build-from-source) to use all three sources. Move the resulting `dist/SongAmbient.app` into Applications if you want to keep it there.
2. Open Song Ambient and choose **Studio → Settings → Audio Source**. Spotify is the default when no selection is saved.
3. Allow **System Audio Recording** when macOS prompts. If capture is off, click **Enable**. Choose **Retry** after granting access in **System Settings → Privacy & Security → Screen & System Audio Recording**.
4. For **Apple Music** or **Spotify**, open the matching desktop player and click **Connect** if automatic connection is off. Allow the selected player under **Privacy & Security → Automation** for track information and controls.

Requires **macOS 15 or newer**. The upstream 2.1.1 download is an ad-hoc-signed Apple silicon build with Spotify support. This branch uses the same local build and signing script.

Use **H** to hide/show stage controls and **Escape** to leave full screen. The menu bar orbit reopens the studio after you close it. Quit from its menu to stop the app completely.

## Audio sources

| Source | Audio capture | Playback information, artwork and controls |
| --- | --- | --- |
| **System Audio** | A global stereo Core Audio tap captures app output including browsers, games, local players and Spotify or Music. Lighting follows audio activity and falls quiet using the existing release envelopes. | Uses the saved custom palette. Track metadata and transport controls are unavailable for the system mix. |
| **Apple Music** | A stereo tap includes Music.app and Music-specific processes. Song Ambient checks for process changes so it can reconnect after Music restarts. | Music’s local Automation interface provides title, artist, album, elapsed time, duration and transport controls. When Music exposes artwork, the existing album palette uses it. The saved custom palette is the fallback. |
| **Spotify** | A stereo tap includes Spotify and its helpers. The rim requires connected, playing Spotify and non-silent PCM. | The existing Spotify Automation, artwork and lyric timing integrations remain available. |

Switching sources while capture is enabled reconfigures the tap live. The tap stays unmuted and separate from the normal output device. Changes to the default output or tap format trigger a rebuild. Capture requires no microphone, virtual driver or kernel extension.

Music’s ability to expose track data, artwork and PCM varies by track and macOS version. Music can report playback while the tap is silent, including when macOS restricts protected audio. The studio shows a capture hint in that case. Capture follows the audio macOS makes available through its public tap API. AirPods and other Bluetooth devices should be included in the output-switching checks below.

A denied Music Automation permission leaves audio-driven lighting available. Spotify requires Automation for its existing playback gate. Apple Music transport and metadata use the installed Music app, with no MusicKit token or added service.

## Honest timing, better words

Every style displays individual words, but the quality of synchronization depends on the recording's lyric data:

| Status | Meaning |
| --- | --- |
| **Word sync** | Real word timestamps from the provider or an imported file. Original timestamps and gaps are preserved. |
| **Word motion · estimated** | Only line or multiword segment timing is available. Words are visually paced within that interval; this is **not exact vocal alignment**. |
| **No timed lyrics** | No song text is invented. Try another recording or import a timed file. |

Recording selection is remembered for the current track. You can import UTF-8 enhanced LRC or Lyricsfile YAML; [the authored timing demo](Examples/Timing-Demo.lyricsfile.yaml) shows genuine word-level input. Estimated word timestamps are never written back to source data. An explicitly labeled demo lets you explore layouts without lyric availability.

Hindi romanization is approximate. LRCLIB coverage and recording matches vary. An optional, best-effort correction reads an unambiguous local Spotify crossfade setting for catalog-duration matching; it does not change Spotify settings, playback position or the displayed transport duration.

## Privacy and network use

- Audio analysis stays on your Mac. Audio is not recorded to disk or uploaded; the microphone is not captured.
- Spotify and Music playback information and controls use their local Apple Events interfaces.
- Automatic lyric lookup sends track title, artist, album and duration to **[LRCLIB](https://lrclib.net)**. Turn off automatic fetching in Settings to stop automatic lookups. Successful results and recording choices are cached locally under `~/Library/Application Support/SongAmbient/Lyrics`.
- Static artwork comes from Music’s local scripting interface or the HTTPS artwork URL supplied by Spotify. Optional animated artwork searches Apple's public catalog using track details; availability is not guaranteed.
- Preferences stay in macOS UserDefaults. There is no app account, analytics service or activation server.

In-app effect previews and the display lighting preview can run independently of live capture.

## Build from source

Install Apple's command-line developer tools or Xcode with **Swift 6 or newer**. A network connection is needed on the first build to resolve the pinned Yams dependency.

```sh
git clone --branch feature/multiple-audio-sources https://github.com/ACOPS1206/song-ambient.git
cd song-ambient
./script/build_and_run.sh
```

This produces an optimized, locally signed `dist/SongAmbient.app` and opens it. Build without launching:

```sh
./script/build_and_run.sh --build
```

The script builds for the host architecture. Intel builds are possible from source with a suitable macOS/Swift toolchain, but are **not validated in this release**. There is no Windows or Linux app.

## Checks and development

```sh
swift run SongAmbientChecks
# Report app-specific Core Audio processes and write six GPU previews:
swift run SongAmbientChecks --spotify-route --previews /tmp/songambient-edge-previews
swift run SongAmbientChecks --apple-music-route
# Permit a headless host to skip GPU checks if Metal is unavailable:
swift run SongAmbientChecks --allow-missing-metal
# Inspect UI without connection autostart or desktop overlays:
./script/build_and_run.sh --ui-check
```

Checks cover line/word timestamp precision, romanization, gaps and seeks, one-word presentation, random constellation geometry, source restoration and isolation, lighting gates, PCM parity, bass/onset/spring behavior, and actual Metal rendering with transparent centers and distinct effect output. GPU checks need a Metal-capable Mac; a headless environment without a Metal device cannot run them.

### Live macOS verification

1. In **Spotify**, play, pause, seek and skip tracks. Verify metadata, artwork, lyrics and that a separate browser tab cannot activate the rim while Spotify is paused.
2. In **Apple Music**, play a local file, then a streamed song. Verify that Music alone drives the rim, then test artwork palette, elapsed time, duration, pause, previous and next. Quit and reopen Music while leaving Song Ambient running. Test with Music Automation denied and re-enabled.
3. In **System Audio**, with Spotify closed or absent, play a browser video and a second app. Check output volume, silence and resumed playback. Switch between the built-in output and AirPods while audio is playing. Check the same test in full screen.
4. Cycle between all three sources while audio plays. Verify the previous source stops driving the rim, stop and re-enable capture, then quit and relaunch to verify that the source persists. Deny and re-enable system audio recording. To inspect resource cleanup, watch for Song Ambient’s private taps and aggregate devices in a Core Audio diagnostic tool during repeated switches and after quitting.
5. Try all six effects using the same preset and playback. Run the checks on a Metal-capable Mac for GPU output. GitHub Actions covers the macOS build and automated checks when enabled on the fork.

| Directory | Purpose |
| --- | --- |
| `Sources/AmbientCore` | Timing, word presentation, audio policy, beat processing and Metal shader source |
| `Sources/SongAmbient` | SwiftUI/AppKit app, media integration, audio capture, player and stage |
| `Checks` | Executable regression and GPU checks |
| `Examples` | Authored word-timing fixture |
| `Assets` | Original app icon, icon provenance and dependency notice |

Bug reports and pull requests are welcome. Include macOS version, hardware, effect/style, exact steps, and the timing status when reporting lyric problems. See [CONTRIBUTING.md](CONTRIBUTING.md).

## An open-source alternative to Lumn

Looking for an open-source version of [Lumn](https://www.trylumn.xyz)? **Song Ambient is an independent alternative**, with its own identity and MIT-licensed application implementation. It is not an official Lumn release, an endorsed fork, or the original product's source code. Similar feature ideas do not imply identical behavior or feature parity.

The project began with local reverse-engineering research into Lumn and public/reference UI evidence, followed by a new implementation and substantial renderer redesign. **Original app bundles, extracted assets, recovered code/IR and research archives are excluded from this repository and its release assets.** The earlier reconstructed private lock-screen bridge is also excluded; this release makes no lock-screen overlay claim.

## License and credits

[MIT](LICENSE). Free to use, study, change and redistribute under its terms.

Built with SwiftUI, AppKit, Core Audio, Accelerate and Metal. YAML parsing uses [Yams](https://github.com/jpsim/Yams), with its [MIT notice](Assets/Yams-LICENSE.txt) retained. The app icon is original generated artwork; see [icon provenance](Assets/ICON-PROMPT.md). Public lyric lookup is provided by LRCLIB.

The project license covers this repository's application code and original assets. Lyrics, album art, service content and trademarks remain with their respective owners and are not relicensed by this project. Song Ambient is not affiliated with Lumn, Spotify or Apple.
