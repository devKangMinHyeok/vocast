# Vocast (macOS, SwiftUI)

Native macOS app for Vocast: a local, on-device voice studio. Clone your voice, narrate
scripts in that voice, and clean up audio, all on this Mac. No account, no server, works
offline after a one-time model download.

Built from the design handoff in `design_handoff_vocast/` (README + screens + prototype).

## Requirements

- macOS 14 or later, Apple Silicon.
- Xcode 16 or later (the project uses a file-system-synchronized group, Xcode 16+).

> Note on the deployment target: the handoff asked for macOS 12+, but it also asked for the
> native `.inspector()` panel and `@Observable` models, which require macOS 14. The target is
> set to macOS 14 to use those. To support macOS 12 later, replace the inspector with a custom
> trailing pane and switch the models to `ObservableObject`.

## Run

Open `Vocast.xcodeproj` in Xcode and run the `Vocast` scheme, or:

```
xcodebuild -project Vocast.xcodeproj -scheme Vocast -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build
```

The heavy work (profile build, narration render, denoise) is faked with async timers that
publish a live progress and ETA. There is no real model yet; the UI is the deliverable.

### Developer env flags

- `VOCAST_SKIP_ONBOARDING=1` launches straight into the main window (skips first-run onboarding).
- `VOCAST_QUIET=1` suppresses the system completion notification (the in-app toast still shows).

## Layout

Single resizable window with five areas driven by the sidebar selection: Studio, Voices,
Denoise, Tasks, Settings. A collapsible inspector on the right shows the quality scorecard
(Studio, Denoise) or the running job detail (Tasks). First launch runs the onboarding flow.

## Source map

| File | What it holds |
|---|---|
| `Theme.swift` | Semantic color/type/spacing/radius tokens (dark now, structured for a light theme later) |
| `Components.swift` | Reusable views: waveforms, level meter, buttons, pills, avatar, logo, progress |
| `Layouts.swift` | Segmented control, flow layout (karaoke), version pill |
| `ScorecardView.swift` | The quality scorecard (SIM / CER / MOS / PNS + sub-metrics + gate) |
| `Models.swift` | Per-area `@Observable` models + sample content |
| `AppModel.swift` | Root model + the job engine (async-timer jobs, ETA, toast, notifications) |
| `RootView.swift` | Three-pane shell (sidebar / detail / inspector), top bars, toast, inspector router |
| `Sidebar.swift` | Sidebar: wordmark, search, nav rows, offline chip |
| `StudioView.swift` | Editor, render, paragraph blocks, karaoke, transport |
| `VoicesView.swift` | Library, guided recording, build, similarity result, profile detail |
| `DenoiseView.swift` | Import, mode select, processing, A/B compare + quality report |
| `TasksView.swift` | Running / queued / done task center |
| `SettingsView.swift` | General, Models, Audio, Privacy, MCP server, About |
| `OnboardingView.swift` | First-run: welcome, model download, mic access, ready |
| `VocastApp.swift` | App entry, window, menu commands and shortcuts |

## Implementation notes

- Depth comes from a surface ladder plus 1px hairline borders, never drop shadows.
- The orange accent is used sparingly; green and red are reserved for status and data.
- The shell uses a custom three-pane `HStack` (fixed 232 sidebar, flexible detail, collapsible
  308 inspector) rather than `NavigationSplitView` + `.inspector()`, because the hidden-titlebar
  window would not honor the sidebar column width. Same visual result and native behaviors.
