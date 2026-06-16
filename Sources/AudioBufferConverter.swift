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

final class AudioBufferConverter {

    enum Failure: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        // Already in the right format → pass through untouched.
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
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
        var fed = false
        let status = converter.convert(to: output, error: &nsError) { _, statusPtr in
            // Supply the source buffer exactly once, then report "no data now".
            defer { fed = true }
            statusPtr.pointee = fed ? .noDataNow : .haveData
            return fed ? nil : buffer
        }
        guard status != .error else { throw Failure.conversionFailed(nsError) }
        return output
    }
}
