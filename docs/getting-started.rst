Getting started
===================

Choose an integration route
-------------------------------

The library requires Swift 6 and Xcode 26 or later. The speech session is exposed
on iOS 26 or later. On macOS 13 or later, only the PCM buffer converter is exposed.
Do not expect the iOS microphone session to appear in a macOS target.

For an existing iOS app, add this repository in Xcode's Add Package Dependencies
window and select the SpeechAnalyzerLiveMic library product::

   https://github.com/simplememofast/ios26-speechanalyzer-live-mic.git

Import ``SpeechAnalyzerLiveMic`` in the host target. Own one ``SpeechSession``
on the main actor and display its ``finalizedText`` and ``volatileText`` fields.
Call ``toggle()`` from a recording button. Disable the button while the state
is ``preparing`` so users cannot start several preparation operations.

For the standalone sample, clone the repository and run ``xcodegen generate``
with XcodeGen installed, then open the generated project. Alternatively create
an iOS 26 SwiftUI app and copy the files from Sources. Avoid combining source
copies with the package in the same target.

Permissions belong to the host app
--------------------------------------

Add descriptive values for both of these keys to the host app's Info.plist:

* ``NSMicrophoneUsageDescription``
* ``NSSpeechRecognitionUsageDescription``

The sample includes example values in Sources/Info.plist. Adjust them to describe
what your application actually does. A Swift package cannot insert permission
usage descriptions into its host application's property list.

First launch and lifecycle
------------------------------

The session normalizes the requested locale and checks whether a corresponding
transcription model is installed. A missing model may need a network download;
on-device recognition does not imply that a fresh installation can always begin
offline. Surface ``lastError`` in your UI and allow a user to retry deliberately.

Call ``await session.stop()`` before leaving the recording screen. This sample
is foreground-oriented and does not implement your application's interruption,
background recording, or persistence policy. Verify those behaviors on supported
physical devices before shipping.
