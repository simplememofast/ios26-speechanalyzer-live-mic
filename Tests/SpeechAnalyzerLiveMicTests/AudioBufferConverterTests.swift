import AVFoundation
import XCTest
import SpeechAnalyzerLiveMic

final class AudioBufferConverterTests: XCTestCase {
    private func buffer(rate: Double, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) { channel[index] = sin(Float(index) * 0.1) * 0.25 }
        return buffer
    }

    func testMatchingFormatKeepsAudioAfterSourceBufferIsReused() throws {
        let input = try buffer(rate: 48_000, frames: 960)
        let originalSamples = Array(UnsafeBufferPointer(start: try XCTUnwrap(input.floatChannelData?[0]), count: 960))
        let output = try AudioBufferConverter().convert(input, to: input.format)
        let source = try XCTUnwrap(input.floatChannelData?[0])
        for index in 0..<960 { source[index] = 0 }
        input.frameLength = 0

        XCTAssertFalse(output === input)
        XCTAssertEqual(output.format, input.format)
        XCTAssertEqual(output.frameLength, 960)
        let copiedSamples = Array(UnsafeBufferPointer(start: try XCTUnwrap(output.floatChannelData?[0]), count: 960))
        XCTAssertEqual(copiedSamples, originalSamples)
    }

    func testMatchingInterleavedStereoKeepsBothChannelsAfterSourceIsReused() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32))
        input.frameLength = 32
        let source = try XCTUnwrap(input.int16ChannelData?[0])
        var expected: [Int16] = []
        for index in 0..<64 {
            let magnitude = Int16(index + 1)
            expected.append(index.isMultiple(of: 2) ? magnitude : -magnitude)
        }
        for index in expected.indices { source[index] = expected[index] }

        let output = try AudioBufferConverter().convert(input, to: format)
        for index in expected.indices { source[index] = 0 }
        XCTAssertEqual(output.format, format)
        XCTAssertEqual(output.frameLength, 32)
        let samples = Array(UnsafeBufferPointer(start: try XCTUnwrap(output.int16ChannelData?[0]), count: expected.count))
        XCTAssertEqual(samples, expected)
    }

    func testResamplingProducesRequestedFormatAndAudio() throws {
        let input = try buffer(rate: 48_000, frames: 4_800)
        let target = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let output = try AudioBufferConverter().convert(input, to: target)
        XCTAssertEqual(output.format, target)
        XCTAssertGreaterThan(output.frameLength, 0)
        XCTAssertLessThanOrEqual(output.frameLength, 1_600)
        let samples = try XCTUnwrap(output.floatChannelData?[0])
        XCTAssertTrue((0..<Int(output.frameLength)).contains { abs(samples[$0]) > 0.001 })
    }

    func testInputFormatChangeRecreatesConverter() throws {
        let converter = AudioBufferConverter()
        let target = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        _ = try converter.convert(buffer(rate: 48_000, frames: 4_800), to: target)
        let output = try converter.convert(buffer(rate: 44_100, frames: 4_410), to: target)
        XCTAssertEqual(output.format, target)
        XCTAssertGreaterThan(output.frameLength, 0)
        XCTAssertLessThanOrEqual(output.frameLength, 1_600)
    }
}
