Troubleshooting
===================

Permission denied
---------------------

Check that both permission usage descriptions are in the built host app, then
check its microphone and speech settings. The sample reports permissionDenied
when either authorization step fails. A package build cannot test those prompts.

Unsupported language or unavailable model
---------------------------------------------

A locale string accepted by Foundation is not necessarily supported by
SpeechTranscriber. The sample requests an equivalent supported locale and
reports localeNotSupported if it cannot find one. If a supported model cannot
be installed, it reports assetUnavailable. Retry with connectivity on a device
that supports that model; do not promise every language to users.

Audio buffers arrive but no words appear
--------------------------------------------

Inspect the microphone input format and the value returned by
SpeechAnalyzer.bestAvailableAudioFormat. The sample converts buffers before
yielding them. Verify that conversion returns nonempty data and that the stream
is still open. Also check microphone authorization, the selected input device,
model availability, and whether the results task has ended.

Changing audio routes
-------------------------

AudioBufferConverter recreates its conversion object if an input or output
format changes. This does not restart AVAudioEngine or implement route-change
handling for your app. Test headphones, interruptions, and stop/start behavior
on the hardware your application supports.

What this sample does not diagnose
--------------------------------------

The sample intentionally exposes a small set of setup errors. It suppresses
individual conversion failures in the tap and does not expose detailed runtime
recognition errors. For production diagnostics, add structured error reporting
without placing raw transcripts or audio into diagnostic logs by default.

There is no verified latency or recognition-accuracy guarantee in this release.
Measure your own device, locale, and cold/warm model conditions before making
such a claim.
