# SpeechAnalyzer Live Mic

A small Swift package and SwiftUI example for streaming microphone audio into iOS 26's `SpeechAnalyzer` and `SpeechTranscriber`.

The package exposes an observable `SpeechSession` on iOS and a PCM `AudioBufferConverter` on iOS and macOS. The speech session uses Apple's on-device transcription model; its first use may require downloading a language asset. This repository does not implement email delivery, note storage, or Obsidian integration.

## Requirements

- Xcode 26+ and Swift 6.
- iOS 26+ for `SpeechSession` and the example app.
- macOS 13+ for the buffer converter and its automated tests. The iOS audio session is not exposed on macOS.
- A supported device and language model for microphone transcription. Compile success alone does not establish device or locale support.

## Use the Swift package

In Xcode, add this repository under **File → Add Package Dependencies**, then add the `SpeechAnalyzerLiveMic` library to your iOS target:

```text
https://github.com/simplememofast/ios26-speechanalyzer-live-mic.git
```

Import the module and own one session in your view:

```swift
import SwiftUI
import SpeechAnalyzerLiveMic

struct DictationView: View {
    @State private var session = SpeechSession()

    var body: some View {
        VStack {
            Text(session.finalizedText)
            Text(session.volatileText).foregroundStyle(.secondary)
            Button(session.isRecording ? "Stop" : "Start") {
                session.toggle()
            }
            .disabled(session.state == .preparing)
        }
    }
}
```

Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` to the host app's Info.plist. The library cannot provide host-app permission descriptions. Stop the session before dismissing its recording UI; decide how your app handles backgrounding and interruptions.

## Run the complete example

With [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:

```sh
xcodegen generate
open SpeechAnalyzerLiveMic.xcodeproj
```

Alternatively, create an iOS 26 SwiftUI app, replace its generated app/view with the files in `Sources/`, and add the permission keys from `Sources/Info.plist`. Use either the source-copy route or the package route, so the types are not defined twice.

## Audio flow

```text
AVAudioEngine microphone tap
  → AudioBufferConverter
  → AsyncStream<AnalyzerInput>
  → SpeechAnalyzer + SpeechTranscriber
  → finalizedText / volatileText
```

`SpeechSession` normalizes the locale, checks model installation, requests the analyzer's audio format, and converts microphone PCM buffers before yielding them. Volatile text is replaced as recognition changes; final text is appended.

## Concurrency and scope

`SpeechSession` is main-actor isolated. Its audio tap captures local pipeline objects and does not update observable state from the tap callback. `AudioBufferConverter` must be used from one processing thread per instance. Its private one-shot input holder uses a lock and a narrow `@unchecked Sendable` conformance for the SDK's input callback; this does **not** make the converter or PCM buffers generally safe to share across threads. Do not mutate an input buffer until conversion returns.

This remains a learning sample. It does not provide a production interruption/background policy, exhaustive microphone lifecycle tests, or a latency guarantee. Review those concerns before integrating it into a shipping app.

## Validation

On 2026-09-06, the package passed:

- `swift package dump-package` (valid package manifest).
- `swift test` on macOS: three converter tests covering passthrough, resampling with nonzero output, and a changed input sample rate.
- An iOS Simulator library build with Xcode 26.6, Swift 6 mode, without code signing.

These checks do not exercise a physical microphone, model download, speech accuracy, or transcription latency. The package refactor has not been re-tested on a physical iOS device.

```sh
swift test
xcodebuild -scheme SpeechAnalyzerLiveMic \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Documentation and related project

The [documentation sources](docs/index.rst) cover setup, API usage, troubleshooting, and verification. Build them with `python -m sphinx -W --keep-going -b html docs docs/_build/html` after installing `docs/requirements.txt` in a virtual environment.

Maintained by the SimpleMemo developer, 株式会社ユリカ. The related app's [voice input page](https://simplememofast.com/en/voice-input/) describes the product context behind this sample. The sample is free and does not require a SimpleMemo account or subscription.

## License

MIT — see [LICENSE](LICENSE).
