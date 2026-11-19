import AVFoundation
import Testing
@testable import AltoTranscription

private let rate = 44_100.0

@Test @MainActor func slowedPlaybackPreservesPitchAndAdvancesAtHalfSpeed() async throws {
    let url = try makeRecording()
    defer { try? FileManager.default.removeItem(at: url) }
    let audio = AudioTransport()
    try audio.load(url)
    defer { audio.unload() }
    let buffer = try makeRenderBuffer(for: audio)
    try audio.configure(PlaybackSettings(speed: 0.5))
    try audio.toggle()

    let samples = try await render(audio, into: buffer, seconds: 1.6)
    audio.refreshPosition()
    #expect((0.65...0.95).contains(audio.position))
    let stableSamples = samples[Int(rate * 0.5)..<Int(rate * 1.4)]
    #expect(abs(frequency(stableSamples) - 440) < 12)
    try audio.toggle()
    #expect(!audio.playing)
    try audio.configure(PlaybackSettings(speed: 0.5), seekTo: 1.5)
    #expect(audio.position == 1.5)
    try audio.toggle()
    let tail = try await render(audio, into: buffer, seconds: 3.7)
    #expect(abs(frequency(tail[Int(rate * 0.4)..<Int(rate * 1.4)]) - 880) < 20)
    #expect(!audio.playing)
    #expect(audio.position == audio.duration)
}

@Test @MainActor func audioLoopsAcrossManyBoundariesAndCanExitTheRegion() async throws {
    let url = try makeRecording()
    defer { try? FileManager.default.removeItem(at: url) }
    let peaks = try AudioTransport.peaks(for: url)
    #expect(peaks.count == 1_600)
    #expect((0.44...0.46).contains(peaks.max() ?? 0))

    let audio = AudioTransport()
    try audio.load(url)
    defer { audio.unload() }
    let buffer = try makeRenderBuffer(for: audio)
    try audio.configure(PlaybackSettings(speed: 1, a: 0.1, b: 0.2, looping: true))
    try audio.toggle()

    let samples = try await render(audio, into: buffer, seconds: 1.8)
    audio.refreshPosition()
    #expect((0.1..<0.2).contains(audio.position))
    for start in stride(from: 0.3, to: 1.7, by: 0.05) {
        let slice = samples[Int(rate * start)..<Int(rate * (start + 0.025))]
        #expect((slice.map(abs).max() ?? 0) > 0.25)
        #expect(abs(frequency(slice) - 440) < 48)
    }

    try audio.configure(PlaybackSettings(), seekTo: 1.5)
    let outside = try await render(audio, into: buffer, seconds: 0.7)
    #expect(abs(frequency(outside[Int(rate * 0.3)..<Int(rate * 0.6)]) - 880) < 15)
    #expect(audio.playing)
}

private func makeRecording() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
    let frames = AVAudioFrameCount(rate * 3)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let samples = try #require(buffer.floatChannelData?[0])
    for frame in 0..<Int(frames) {
        let hz = frame < Int(rate) ? 440.0 : 880.0
        samples[frame] = 0.45 * Float(sin(2 * .pi * hz * Double(frame) / rate))
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

@MainActor private func makeRenderBuffer(for audio: AudioTransport) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
    try audio.enableOfflineRendering(format: format, frames: 512)
    return try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
}

@MainActor private func render(_ audio: AudioTransport, into buffer: AVAudioPCMBuffer,
                               seconds: Double) async throws -> [Float] {
    var samples: [Float] = []
    let frames = Int(rate * seconds)
    for _ in 0..<(frames / Int(buffer.frameCapacity) + 30) {
        if try audio.renderOffline(into: buffer) == .success {
            let channel = try #require(buffer.floatChannelData?[0])
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        await Task.yield()
        if samples.count >= frames { return samples }
    }
    Issue.record("The audio engine failed to render the requested duration")
    return samples + [Float](repeating: 0, count: max(0, frames - samples.count))
}

private func frequency(_ samples: ArraySlice<Float>) -> Double {
    let risingCrossings = zip(samples, samples.dropFirst()).count { $0 <= 0 && $1 > 0 }
    return Double(risingCrossings) * rate / Double(samples.count)
}
