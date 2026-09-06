Validation and development
==============================

Checks run for the package refactor
---------------------------------------

On 2026-09-06, Xcode 26.6 built the library for the generic iOS Simulator
destination in Swift 6 mode without code signing. On macOS, three XCTest cases
passed: matching-format passthrough, resampling with nonzero output, and a
changed input sample rate while retaining the same output format.

The package manifest is checked with ``swift package dump-package``. Repeat
local tests with::

   swift test
   xcodebuild -scheme SpeechAnalyzerLiveMic \
     -destination 'generic/platform=iOS Simulator' \
     CODE_SIGNING_ALLOWED=NO build

Limits of these checks
--------------------------

The tests generate deterministic PCM samples; they do not record microphone
audio. The simulator build checks compilation and linking, not recognition
behavior. The package refactor has not been re-tested on a physical iOS device.
Model downloads, permissions, interruptions, speech accuracy, and latency
remain device-validation work for an integrating application.

Build these documents
-------------------------

Use Python 3.12 or later in a virtual environment::

   python -m venv .venv-docs
   .venv-docs/bin/python -m pip install -r docs/requirements.txt
   .venv-docs/bin/python -m sphinx -W --keep-going -b html docs docs/_build/html

The repository includes a Read the Docs configuration that builds these text
documents on Linux. It does not attempt to compile Apple-framework Swift source
on Linux. The documentation build has no microphone or app-account dependency.
