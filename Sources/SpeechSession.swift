//
//  SpeechSession.swift
//  SpeechAnalyzerLiveMic
//
//  Minimal live-microphone transcription with iOS 26's SpeechAnalyzer.
//  Observable, SwiftUI-friendly. No third-party SDKs, fully on-device.
//
//  Verified: this sample builds and runs on a shipping iOS 26 device
//  (Xcode 26, Swift 6 strict concurrency). ✅ marks calls that also match
//  SimpleMemo's shipping voice-input pipeline.
//
//  Requires: iOS 26.0+. Info.plist needs NSMicrophoneUsageDescription and
//  NSSpeechRecognitionUsageDescription.
//

import Foundation
import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class SpeechSession {

    enum State: Equatable { case idle, preparing, recording }

    enum Failure: Error, Equatable {
        case permissionDenied      // mic or speech authorization missing
        case localeNotSupported    // this language has no on-device model
        case assetUnavailable      // model could not be installed (e.g. offline first run)
        case audioSetupFailed      // microphone / analyzer start failed
    }

    // Observed by SwiftUI.
    private(set) var state: State = .idle
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var lastError: Failure?

    /// Finalized text plus the in-flight volatile tail. Render `volatileText`
    /// dimmed and `finalizedText` solid for the classic live-caption look.
    var liveText: String { finalizedText + volatileText }

    var isRecording: Bool { state == .recording }

    // MARK: Internals

    private let requestedLocale: Locale
    private let audioEngine = AVAudioEngine()

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    init(locale: Locale = .current) {
        self.requestedLocale = locale
    }

    /// Whether this device + locale can transcribe. Call only after you have
    /// gated on iOS 26 availability at the call site (`if #available(iOS 26, *)`).
    static func isLocaleSupported(_ locale: Locale = .current) async -> Bool {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil   // ✅
    }

    func toggle() {
        switch state {
        case .recording: Task { await stop() }
        case .idle:      Task { await start() }
        case .preparing: break
        }
    }

    // MARK: Start

    func start() async {
        guard state == .idle else { return }
        state = .preparing
        lastError = nil

        // 1) Permissions: speech recognition + microphone.
        guard await Self.requestSpeechPermission(),
              await Self.requestMicPermission() else {
            return fail(.permissionDenied)
        }

        // 2) Normalize the requested locale to one with an on-device model.
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {  // ✅
            return fail(.localeNotSupported)
        }

        // 3) Build the transcriber module.
        //    .volatileResults streams partial text *while you are still speaking*.
        let transcriber = SpeechTranscriber(            // ✅ shipping initializer shape
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []                        // add .audioTimeRange to get per-word timing
        )
        self.transcriber = transcriber

        // 4) Make sure the language model asset is installed (downloads on first use).
        do {
            try await ensureModelInstalled(for: transcriber, locale: locale)
        } catch {
            teardown()
            return fail(.assetUnavailable)
        }

        // 5) Create the analyzer and discover the PCM format it wants.
        let analyzer = SpeechAnalyzer(modules: [transcriber])                                 // ✅
        self.analyzer = analyzer
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])  // ✅

        // 6) Subscribe to results. volatile -> replace tail; final -> append + clear tail.
        finalizedText = ""
        volatileText = ""
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {     // ✅ AsyncSequence of results
                    let piece = String(result.text.characters)    // ✅ result.text is AttributedString
                    if result.isFinal {                           // ✅
                        self.finalizedText += piece
                        self.volatileText = ""
                    } else {
                        self.volatileText = piece
                    }
                }
            } catch {
                // Reached when the stream is finalized / cancelled on stop(). Ignore.
            }
        }

        // 7) Wire the input stream, then start the analyzer.
        let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream()   // ✅
        self.inputBuilder = builder
        do {
            try await analyzer.start(inputSequence: sequence)               // ✅
        } catch {
            teardown()
            return fail(.audioSetupFailed)
        }

        // 8) Start the microphone tap and begin feeding buffers.
        do {
            try setupAudioSession()
            try startMicrophone()
        } catch {
            await stop()
            return fail(.audioSetupFailed)
        }

        state = .recording
    }

    // MARK: Stop

    func stop() async {
        guard state != .idle else { return }

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        inputBuilder?.finish()
        inputBuilder = nil

        // Flush whatever audio is still buffered and let the analyzer emit final results.
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()   // ✅ flush buffered audio + emit final results

        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        analyzerFormat = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        state = .idle
    }

    // MARK: Model asset (the offline-first-run gotcha)

    private func ensureModelInstalled(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })  // ✅
        if installed.contains(locale.identifier(.bcp47)) { return }

        // Not installed yet: download + install. The model is a SYSTEM-SHARED asset,
        // so it does NOT count against your app's bundle size.
        // On a first run with NO network, this throws — handle it (we surface .assetUnavailable).
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {  // ✅
            try await request.downloadAndInstall()   // ✅  request has a `.progress` you can show in UI
        }

        let nowInstalled = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        if !nowInstalled.contains(locale.identifier(.bcp47)) {
            throw Failure.assetUnavailable
        }
    }

    // MARK: Microphone

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .record + .measurement minimizes input processing/AGC for better recognition;
        // .duckOthers lowers other audio while you dictate.
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)   // ✅
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startMicrophone() throws {
        guard let builder = inputBuilder, let target = analyzerFormat else {
            throw Failure.audioSetupFailed
        }
        // The tap runs on a real-time audio thread. We capture only locals
        // (the continuation + the target format + a fresh converter) and never
        // touch `self` from inside it, so there is no @MainActor hop per buffer.
        // ✅ Compiles clean under Swift 6 strict concurrency (verified on a device
        // build) precisely because the closure stays off the main actor and
        // captures nothing actor-isolated. See README › Gotchas #7.
        let converter = AudioBufferConverter()
        let input = audioEngine.inputNode
        let micFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            // Convert the mic buffer to the format SpeechAnalyzer asked for, THEN yield.
            // Format mismatch here (skipping conversion) is the most common beginner bug.
            guard let converted = try? converter.convert(buffer, to: target) else { return }
            builder.yield(AnalyzerInput(buffer: converted))   // ✅
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: Teardown / errors

    private func teardown() {
        inputBuilder?.finish()
        inputBuilder = nil
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        analyzerFormat = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ failure: Failure) {
        teardown()
        lastError = failure
        state = .idle
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }   // ✅
        }
    }

    private static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }   // ✅ iOS 17+ API
        }
    }
}
