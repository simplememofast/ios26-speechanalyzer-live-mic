Public API and audio ownership
==================================

SpeechSession (iOS 26+)
---------------------------

``SpeechSession(locale:)`` is an observable, main-actor-isolated class. The locale
defaults to the current locale. ``isLocaleSupported(_:)`` checks for a supported
equivalent locale; that check alone does not verify that a model is installed
or that microphone access has been granted.

The public state is read-only to callers:

* ``state``: idle, preparing, or recording.
* ``finalizedText``: accumulated finalized recognition results.
* ``volatileText``: the current provisional result, replaced as results change.
* ``liveText``: finalized and volatile text concatenated for display.
* ``lastError``: permissionDenied, localeNotSupported, assetUnavailable, or
  audioSetupFailed when setup fails.
* ``isRecording``: convenience access to the recording state.

``toggle()`` starts or stops via a task. ``start()`` and ``stop()`` are async
methods for callers that need to await those operations. Starting while the
session is not idle returns without starting another capture pipeline. Text is
reset as a new analyzer session is prepared.

On stop, the sample finishes the input stream and asks the analyzer to finalize.
It does not expose detailed recognition-stream errors, cancellation controls
for model installation, or a durable transcript store. Do not treat the display
fields as an audit log.

AudioBufferConverter (iOS and macOS)
----------------------------------------

``convert(_:to:)`` accepts an AVAudioPCMBuffer and an AVAudioFormat. If the formats
match, it returns a copy with independent PCM storage. Otherwise it uses AVAudioConverter and
returns a converted PCM buffer. The cached converter is rebuilt when either the
input or output format changes.

Use one converter instance on one audio-processing thread. Do not mutate the
input buffer until conversion returns. The result has independent PCM storage
on both paths, so reusing the input afterwards does not overwrite queued audio.
Do not mutate the returned buffer while an asynchronous consumer is using it.

For each conversion, a private holder supplies the input buffer once and then
reports noDataNow. Its lock protects the one-shot state used by the SDK's
Sendable callback. The holder's narrow unchecked Sendable conformance is not a
promise that the converter or AVAudioPCMBuffer may be shared freely between
concurrent callers.

Data flow
-------------

The microphone tap obtains PCM data, converts it to the analyzer-requested
format, and yields AnalyzerInput into an AsyncStream. Recognition results are
read on a task associated with the main-actor session. UI state is not changed
from the microphone tap callback.
