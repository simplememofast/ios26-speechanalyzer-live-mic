# SpeechAnalyzer Live Mic — iOS 26 on-device speech-to-text, wired to a real microphone

A minimal, copy-pasteable SwiftUI sample that streams microphone audio into iOS 26's
**`SpeechAnalyzer`** / **`SpeechTranscriber`** and shows live transcription — finalized text
solid, in-flight (volatile) text dimmed.

It's deliberately small (one `SpeechSession` + one buffer converter + one view) and carries no
third-party SDKs. Everything runs **on-device**.

> **Status / honesty note.** This sample is reduced from a pipeline shipping in a real app
> (SimpleMemo's voice input, iOS 26). The code is annotated with `✅` where it matches that
> shipping implementation and `⚠️` where you should re-confirm against *your* iOS 26 SDK in
> Xcode. The reference was syntax-checked, **not** type-checked against the SDK on the machine
> that produced it — so do one real device build before quoting any signature as gospel. If you
> hit a signature that drifted, please open a PR.

---

## Requirements

- iOS 26.0+ (device or simulator). `SpeechAnalyzer` does not exist before iOS 26.
- Xcode 26+ with the iOS 26 SDK.
- A physical device is recommended (real mic + real model download behavior).

## Setup

### Option A — XcodeGen (1 command)

```sh
brew install xcodegen   # if needed
xcodegen generate
open SpeechAnalyzerLiveMic.xcodeproj
```

### Option B — manual (2 minutes, no tools)

1. Xcode → **New Project → iOS App** (SwiftUI). Set the deployment target to **iOS 26.0**.
2. Delete the generated `App.swift`/`ContentView.swift`, then drag in everything from `Sources/`.
3. Add two keys to your target's Info (or use the included `Sources/Info.plist`):
   - `NSMicrophoneUsageDescription`
   - `NSSpeechRecognitionUsageDescription`
4. Run on a device, tap the mic, talk.

---

## The mental model

`SpeechAnalyzer` is an orchestrator you attach **modules** to. For speech-to-text you attach a
`SpeechTranscriber`. Audio flows in as `AnalyzerInput`; results come out as an `AsyncSequence`:

```
 mic ─► AVAudioEngine.installTap ─► AVAudioConverter ─► AnalyzerInput
                                                            │
                                          SpeechAnalyzer([ SpeechTranscriber ])
                                                            │
                                          for try await result in transcriber.results
                                              result.text (AttributedString) / result.isFinal
```

That's the whole thing. Files:

| File | Role |
|---|---|
| `SpeechSession.swift` | The pipeline: permissions → locale → model → analyzer → results loop → mic tap. |
| `AudioBufferConverter.swift` | Mic format → the format `SpeechAnalyzer` asks for. (Skipping this = no text.) |
| `ContentView.swift` | Mic button + two-tone live caption. |
| `App.swift` | Entry point. |

---

## What the docs don't tell you (the gotchas)

### 1. You must convert the audio buffer
`AVAudioEngine`'s input node format (often 48 kHz, hardware-dependent) usually does **not** match
`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`. Feed a mismatched buffer and you get a
clean compile and **zero transcription**. Always run buffers through `AVAudioConverter` first
(see `AudioBufferConverter`). This is the #1 beginner trap.

### 2. The model downloads on first use — handle offline
Transcription is on-device, but the language model is a **system-shared asset** that may not be
installed yet. Check `SpeechTranscriber.installedLocales`, and if your locale is missing, run
`AssetInventory.assetInstallationRequest(supporting:)` → `downloadAndInstall()`. The shared asset
does **not** inflate your app bundle. But a **first run with no network can't download it** — so
surface that state instead of silently failing. (`SpeechSession` reports `.assetUnavailable`.)

### 3. Volatile vs. finalized results
With `reportingOptions: [.volatileResults]` you get fast partial results *while the user is still
speaking*; `result.isFinal` marks the committed text. The idiomatic UI: show volatile dimmed,
replace it when a final arrives, persist only finals. `result.text` is an `AttributedString` — add
`attributeOptions: [.audioTimeRange]` if you want per-word timing for highlighting / seek.

### 4. Availability gating
`SpeechAnalyzer` / `SpeechTranscriber` are iOS 26+. This sample deploys to 26.0 so no gating is
needed. If you add this to an app supporting older iOS, mark the speech types
`@available(iOS 26.0, *)` and gate the entry point with `if #available(iOS 26.0, *)`. (SimpleMemo
deploys to iOS 16+ and only renders the mic button on iOS 26+.)

### 5. No Custom Vocabulary
`SFSpeechRecognizer` had `contextualStrings` to bias recognition toward known terms.
`SpeechAnalyzer` (as of iOS 26.0) does **not** expose an equivalent. If your domain is full of
proper nouns, plan for that gap.

### 6. watchOS: SpeechAnalyzer isn't there — but voice input still is
`SpeechAnalyzer` is available on **iOS, iPadOS, macOS, visionOS, tvOS 26 — not watchOS**. That does
**not** mean "no voice on the Watch." You fall back to the watchOS **system dictation UI**
(SwiftUI `TextFieldLink`, or `presentTextInputController` in WatchKit), which hands you back
finished text. You lose the `SpeechAnalyzer` pipeline (volatile results, time ranges, your own
audio tap), but voice capture works. SimpleMemo ships exactly this split: `SpeechAnalyzer` on
iPhone, `TextFieldLink` dictation on the Watch.

```swift
// watchOS — no SpeechAnalyzer; the system handles dictation and returns text:
TextFieldLink(prompt: Text("Speak or type")) {
    Image(systemName: "mic.fill")
} onSubmit: { text in
    send(text)
}
```

### 7. Swift 6 strict concurrency around the audio tap
The microphone tap closure runs on a real-time audio thread. This sample captures only locals
(the `AsyncStream.Continuation`, the target `AVAudioFormat`, a fresh converter) and never touches
the `@MainActor` session inside it. Depending on your exact toolchain you may still need to satisfy
`Sendable` for the tap block — this is the spot most likely to need a small adjustment (e.g. an
`@unchecked Sendable` box). **Resolve this during your device build.**

### 8. First-result latency — measure it yourself
Beta-era reports described long first-result latency even with warm-up/allocation tuning. Numbers
move between betas and the shipping SDK, so **this repo intentionally ships no latency figure** —
measure on your own device and OS build before publishing one. (Warm-up tactics: install the model
ahead of time, and start the analyzer before the user's first word.)

---

## Migration from `SFSpeechRecognizer`

| `SFSpeechRecognizer` (old) | `SpeechAnalyzer` (iOS 26) |
|---|---|
| One object does session + recognition | `SpeechAnalyzer` orchestrator + composable modules (`SpeechTranscriber`, …) |
| `SFSpeechAudioBufferRecognitionRequest.append(_:)` | `AnalyzerInput(buffer:)` yielded into an `AsyncStream` |
| `partialResults` flag | `reportingOptions: [.volatileResults]` |
| delegate / result handler | `for try await result in transcriber.results` |
| `result.bestTranscription.formattedString` | `String(result.text.characters)` (`result.text` is `AttributedString`) |
| `contextualStrings` (custom vocab) | **no equivalent** (see Gotcha 5) |
| user must enable dictation/Siri in Settings | not required (`DictationTranscriber` available where needed) |
| works on watchOS | **not** on watchOS (use system dictation — Gotcha 6) |

---

## Where this ships

This exact pipeline (minus the email/send parts) powers the voice input in
**[Simple Memo - for Obsidian](https://simplememofast.com/voice-input/)**, a fast iPhone memo app
that emails notes to yourself and auto-appends them to Obsidian — fully on-device, no per-use API
cost. The spec page documents the on-device behavior and iOS 26 requirement.

## License

MIT — see [LICENSE](LICENSE). PRs welcome, especially signature corrections from real device builds.
