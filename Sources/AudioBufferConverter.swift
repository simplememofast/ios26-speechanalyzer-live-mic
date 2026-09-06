//
//  AudioBufferConverter.swift
//  SpeechAnalyzerLiveMic
//
//  Converts AVAudioEngine mic buffers to the format SpeechAnalyzer requests.
//  AVAudioEngine's input node format (often 48 kHz, hardware-dependent) usually
//  does NOT match `SpeechAnalyzer.bestAvailableAudioFormat(...)`, and feeding a
//  mismatched buffer is the single most common reason "it compiles but no text
//  ever appears." Always convert.
//
//  This type is single-threaded by contract: create one per capture session and
//  only call `convert` from the audio tap thread.
//

import AVFoundation
import Foundation

// AVAudioConverter invokes its @Sendable input callback synchronously during
// convert(to:error:withInputFrom:). Keep the one-shot state behind a lock rather
// than mutating a captured local. The caller must not mutate the PCM buffer
// until conversion returns. This wrapper does not make the converter thread-safe.
private final class OneShotAudioInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let next = buffer
        buffer = nil
        return next
    }
}

/// Converts streaming PCM buffers. Use one instance on one audio processing thread.
public final class AudioBufferConverter {

    public enum Failure: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        // Already in the right format → pass through untouched.
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none   // no priming latency for streaming PCM
        }
        guard let converter else { throw Failure.cannotCreateConverter }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw Failure.cannotCreateBuffer
        }

        var nsError: NSError?
        let input = OneShotAudioInput(buffer)
        let status = converter.convert(to: output, error: &nsError) { _, statusPtr in
            // Supply the source buffer exactly once, then report "no data now".
            let next = input.take()
            statusPtr.pointee = next == nil ? .noDataNow : .haveData
            return next
        }
        guard status != .error else { throw Failure.conversionFailed(nsError) }
        return output
    }
}
