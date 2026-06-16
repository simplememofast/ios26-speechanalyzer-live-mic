//
//  App.swift
//  SpeechAnalyzerLiveMic
//
//  This sample targets iOS 26.0, so SpeechAnalyzer symbols are always available
//  and no `@available` gymnastics are needed here.
//
//  Integrating into an app that supports OLDER iOS? Then:
//    • mark SpeechSession / your speech UI `@available(iOS 26.0, *)`, and
//    • gate the entry point: `if #available(iOS 26.0, *) { … }`.
//  SimpleMemo does exactly this — it deploys to iOS 16+ and only surfaces the
//  mic button on iOS 26+. See README › Gotchas › Availability gating.
//

import SwiftUI

@main
struct SpeechAnalyzerLiveMicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
