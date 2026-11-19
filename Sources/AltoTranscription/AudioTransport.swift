import AVFoundation
import Observation

@MainActor @Observable
final class AudioTransport {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let downmix = AVAudioMixerNode()
    private var file: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var region: Range<AVAudioFramePosition>?
    private var generation = 0

    private(set) var duration = 0.0
    private(set) var position = 0.0
    private(set) var playing = false
    private(set) var loadedURL: URL?
    private(set) var waveform: [Float] = []
    private(set) var waveformScale: Float = 1
    private(set) var waveformLoading = false
    private(set) var waveformError: String?
    @ObservationIgnored private var waveformWork: Task<[Float], Error>?

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(downmix)
        timePitch.pitch = 0
    }

    func load(_ url: URL) throws {
        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat
        guard newFile.length > 0, newFile.length <= AVAudioFramePosition(AVAudioFrameCount.max),
              format.sampleRate > 0, format.channelCount > 0,
              let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [
                NSLocalizedDescriptionKey: "This audio file is empty or exceeds the supported playback length."
            ])
        }

        unload()
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(downmix)
        engine.disconnectNodeOutput(timePitch)
        if format.channelCount > 2 {
            engine.connect(player, to: downmix, format: format)
            engine.connect(downmix, to: timePitch, format: stereo)
        } else {
            engine.connect(player, to: timePitch, format: format)
        }
        engine.connect(timePitch, to: engine.mainMixerNode, format: format.channelCount > 2 ? stereo : format)

        file = newFile
        loadedURL = url
        duration = Double(newFile.length) / format.sampleRate
        waveformLoading = true
        let worker = Task.detached(priority: .utility) { try Self.peaks(for: url) }
        waveformWork = worker
        Task { [weak self] in
            let result = await worker.result
            guard let self, !worker.isCancelled else { return }
            switch result {
            case .success(let peaks):
                self.waveform = peaks
                self.waveformScale = max(0.05, peaks.max() ?? 1)
            case .failure(let error): self.waveformError = error.localizedDescription
            }
            self.waveformLoading = false
            self.waveformWork = nil
        }
    }

    func unload() {
        stop()
        engine.stop()
        waveformWork?.cancel()
        waveformWork = nil
        waveform = []
        waveformLoading = false
        waveformError = nil
        file = nil
        loadedURL = nil
        region = nil
        duration = 0
        position = 0
    }

    func configure(_ settings: PlaybackSettings, seekTo seconds: Double? = nil) throws {
        timePitch.rate = Float(settings.speed)
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let next = settings.looping ? settings.region(in: duration).flatMap { bounds -> Range<AVAudioFramePosition>? in
            let a = AVAudioFramePosition((bounds.lowerBound * sampleRate).rounded())
            let b = min(file.length, AVAudioFramePosition((bounds.upperBound * sampleRate).rounded()))
            return a < b ? a..<b : nil
        } : nil
        if next != region {
            refreshPosition()
            region = next
        } else if seconds == nil {
            return
        }
        if let seconds { position = min(max(seconds, 0), duration) }
        if let next, !next.contains(frame(at: position)) {
            position = Double(next.lowerBound) / sampleRate
        }
        if playing {
            if position >= duration { stop() } else { try start() }
        }
    }

    func toggle() throws {
        if playing {
            refreshPosition()
            stop()
        } else if file != nil {
            try start()
        }
    }

    func refreshPosition() {
        guard playing else { return }
        guard engine.isRunning else {
            stop()
            return
        }
        guard let file, let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime),
              playerTime.isSampleTimeValid, playerTime.sampleTime >= 0 else { return }
        let sampleRate = file.processingFormat.sampleRate
        let elapsed = AVAudioFramePosition(Double(playerTime.sampleTime) * sampleRate / playerTime.sampleRate)
        let sourceFrame: AVAudioFramePosition
        if let region {
            sourceFrame = region.lowerBound +
                (startFrame - region.lowerBound + elapsed) % (region.upperBound - region.lowerBound)
        } else {
            sourceFrame = min(file.length, startFrame + elapsed)
        }
        position = Double(sourceFrame) / sampleRate
    }

    private func frame(at seconds: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((seconds * (file?.processingFormat.sampleRate ?? 0)).rounded())
    }

    private func start() throws {
        stop()
        guard let file else { return }
        timePitch.reset()
        if !engine.isRunning { try engine.start() }
        let start = frame(at: position)
        if let region {
            startFrame = region.contains(start) ? start : region.lowerBound
            // Queue repeats ahead so the render thread never waits for a UI timer at B.
            enqueueLoop(file, start: startFrame, region: region, generation: generation)
            for _ in 0..<3 {
                enqueueLoop(file, start: region.lowerBound, region: region, generation: generation)
            }
        } else {
            startFrame = start < file.length ? start : 0
            let current = generation
            player.scheduleSegment(file, startingFrame: startFrame,
                                   frameCount: AVAudioFrameCount(file.length - startFrame),
                                   at: nil, completionCallbackType: engine.isInManualRenderingMode ? .dataRendered : .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.stop()
                    self.position = self.duration
                }
            }
        }
        position = Double(startFrame) / file.processingFormat.sampleRate
        player.play()
        playing = true
    }

    private func enqueueLoop(_ file: AVAudioFile, start: AVAudioFramePosition,
                             region: Range<AVAudioFramePosition>, generation: Int) {
        player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(region.upperBound - start),
                               at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation, let file = self.file else { return }
                self.enqueueLoop(file, start: region.lowerBound, region: region, generation: generation)
            }
        }
    }

    private func stop() {
        generation += 1
        player.stop()
        playing = false
    }

    // Manual rendering exercises the production graph without requiring a speaker.
    func enableOfflineRendering(format: AVAudioFormat, frames: AVAudioFrameCount) throws {
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frames)
    }

    func renderOffline(into buffer: AVAudioPCMBuffer) throws -> AVAudioEngineManualRenderingStatus {
        try engine.renderOffline(buffer.frameCapacity, to: buffer)
    }

    nonisolated static func peaks(for url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let target = Int(min(200_000, max(1_600, ceil(duration * 180))))
        let binCount = min(Int(file.length), target)
        let capacity: AVAudioFrameCount = 16_384
        guard binCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity),
              let channels = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }

        var peaks = [Float](repeating: 0, count: binCount)
        let channelsCount = Int(file.processingFormat.channelCount)
        let length = file.length
        var frame: AVAudioFramePosition = 0
        while frame < length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(capacity), length - frame)))
            guard buffer.frameLength > 0 else { break }
            for offset in 0..<Int(buffer.frameLength) {
                let bin = min(binCount - 1, Int((frame + Int64(offset)) * Int64(binCount) / length))
                for channel in 0..<channelsCount {
                    peaks[bin] = max(peaks[bin], abs(channels[channel][offset]))
                }
            }
            frame += Int64(buffer.frameLength)
        }
        return peaks
    }
}
