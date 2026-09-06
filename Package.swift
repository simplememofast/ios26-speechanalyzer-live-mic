// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeechAnalyzerLiveMic",
    platforms: [.iOS("26.0"), .macOS(.v13)],
    products: [
        .library(name: "SpeechAnalyzerLiveMic", targets: ["SpeechAnalyzerLiveMic"])
    ],
    targets: [
        .target(
            name: "SpeechAnalyzerLiveMic",
            path: "Sources",
            exclude: ["App.swift", "ContentView.swift", "Info.plist"]
        ),
        .testTarget(name: "SpeechAnalyzerLiveMicTests", dependencies: ["SpeechAnalyzerLiveMic"])
    ]
)
