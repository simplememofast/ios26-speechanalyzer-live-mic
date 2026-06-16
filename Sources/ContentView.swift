//
//  ContentView.swift
//  SpeechAnalyzerLiveMic
//
//  Minimal UI: a mic button + a live caption that shows finalized text solid
//  and the volatile (in-flight) tail dimmed — the standard SpeechAnalyzer
//  two-tone pattern.
//

import SwiftUI

struct ContentView: View {
    @State private var session = SpeechSession()

    var body: some View {
        VStack(spacing: 28) {
            captionView
            micButton
            if let error = session.lastError {
                Text(message(for: error))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // Finalized text solid, volatile tail dimmed.
    private var captionView: some View {
        ScrollView {
            (Text(session.finalizedText)
                .foregroundStyle(.primary)
             + Text(session.volatileText)
                .foregroundStyle(.secondary))
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: 320)
    }

    private var micButton: some View {
        Button {
            session.toggle()
        } label: {
            Image(systemName: session.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(session.isRecording ? .red : .accentColor)
        }
        .disabled(session.state == .preparing)
        .overlay {
            if session.state == .preparing { ProgressView() }
        }
        .accessibilityLabel(session.isRecording ? "Stop transcription" : "Start transcription")
    }

    private func message(for failure: SpeechSession.Failure) -> String {
        switch failure {
        case .permissionDenied:   return "Microphone or speech permission was denied. Enable it in Settings."
        case .localeNotSupported: return "This language isn't supported for on-device transcription."
        case .assetUnavailable:   return "The language model couldn't be installed. Connect to the internet and try again (first run needs a download)."
        case .audioSetupFailed:   return "Couldn't start the microphone or analyzer."
        }
    }
}

#Preview {
    ContentView()
}
