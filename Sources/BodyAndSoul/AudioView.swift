import SwiftUI
import UniformTypeIdentifiers

struct AudioView: View {
    @Binding var reference: AudioReference?
    @Binding var settings: PlaybackSettings
    @Binding var droppedAudio: URL?
    let dropTargeted: Bool
    let audio: AudioTransport
    @State private var error: String?
    @State private var missingAudio = false
    @State private var zoom = 1
    @State private var visibleStart = 0.0
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var window: WaveformWindow {
        WaveformWindow(duration: audio.duration, zoom: zoom, start: visibleStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio").font(.headline)
                Text(audio.loadedURL?.lastPathComponent ?? reference.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "No file imported")
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                zoomControls
                Button(missingAudio ? "Relink Audio…" : "Import Audio…", action: chooseAudio)
                    .keyboardShortcut("i", modifiers: .command)
            }
            Waveform(audio: audio, settings: settings, window: window, dropTargeted: dropTargeted,
                     seek: seek, select: selectRegion, moveMarkers: { settings = $0 })
            if zoom > 1, window.maxStart > 0 {
                HStack {
                    Text(recordingTime(window.start))
                    Slider(value: Binding(get: { window.start }, set: { visibleStart = $0 }), in: 0...window.maxStart)
                        .accessibilityLabel("Pan waveform")
                    Text(recordingTime(window.end))
                }
                .controlSize(.small)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            transport
            if missingAudio {
                Label("The source couldn’t be opened. Relink it to restore playback.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let waveformError = audio.waveformError {
                Text("Waveform unavailable: \(waveformError)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Click to seek. Drag to set a loop, or grab A or B to move it. Space plays or pauses. ⌥A / ⌥B set markers. ⌥L toggles looping.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(tick) { _ in audio.refreshPosition() }
        .onChange(of: reference, initial: true) { _, reference in loadReference(reference) }
        .onChange(of: droppedAudio) { _, url in
            guard let url else { return }
            droppedAudio = nil
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType, !type.conforms(to: .audio) {
                error = "Drop an audio file such as an MP3, WAV, AIFF, or M4A."
                return
            }
            importAudio(url)
        }
        .onChange(of: audio.loadedURL) {
            zoom = 1
            visibleStart = 0
        }
        .onChange(of: settings) { _, settings in perform { try audio.configure(settings) } }
        .alert("Audio Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { setZoom(zoom / 2) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom == 1)
                .accessibilityLabel("Zoom out waveform")
                .help("Zoom out waveform")
            Button("\(zoom)×") { setZoom(1) }
                .disabled(zoom == 1)
                .accessibilityLabel("Reset waveform zoom")
                .accessibilityValue("\(zoom) times")
                .help("Show the whole recording")
                .monospacedDigit()
                .frame(minWidth: 32)
            Button { setZoom(zoom * 2) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom == WaveformWindow.maximumZoom)
                .accessibilityLabel("Zoom in waveform")
                .help("Zoom in around the playhead")
        }
        .controlSize(.small)
        .disabled(audio.loadedURL == nil)
    }

    private func setZoom(_ next: Int) {
        let center = (window.start...window.end).contains(audio.position) ?
            audio.position : (window.start + window.end) / 2
        visibleStart = window.centered(on: center, zoom: next).start
        zoom = next
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button { perform { try audio.toggle() } } label: {
                Image(systemName: audio.playing ? "pause.fill" : "play.fill")
                    .frame(width: 19)
            }
            .accessibilityLabel(audio.playing ? "Pause" : "Play")
            .help("Play or pause (Space)")
            .keyboardShortcut(.space, modifiers: [])
            .disabled(audio.loadedURL == nil)

            Text("\(recordingTime(audio.position)) / \(recordingTime(audio.duration))")
                .font(.callout.monospacedDigit())
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Button("A  \(settings.a.map(recordingTime) ?? "–")") { mark(start: true) }
                    .keyboardShortcut("a", modifiers: .option)
                    .help("Set loop start to the playhead (⌥A)")
                Button("B  \(settings.b.map(recordingTime) ?? "–")") { mark(start: false) }
                    .keyboardShortcut("b", modifiers: .option)
                    .help("Set loop end to the playhead (⌥B)")
                Button { settings.looping.toggle() } label: {
                    Label("Loop", systemImage: settings.looping ? "repeat.circle.fill" : "repeat")
                        .foregroundStyle(settings.looping ? Color.accentColor : .primary)
                }
                .keyboardShortcut("l", modifiers: .option)
                .help("Toggle the A/B loop (⌥L)")
                .accessibilityValue(settings.looping ? "On" : "Off")
                .disabled(settings.region(in: audio.duration) == nil)
            }
            .font(.callout.monospacedDigit())
            .disabled(audio.loadedURL == nil)
            Divider().frame(height: 20)
            HStack(spacing: 7) {
                Text("Speed").foregroundStyle(.secondary)
                Slider(value: $settings.speed, in: 0.5...1, step: 0.01)
                    .labelsHidden()
                    .accessibilityLabel("Playback speed")
                    .accessibilityValue(settings.speed.formatted(.percent))
                    .frame(width: 93)
                Text(settings.speed.formatted(.percent))
                    .monospacedDigit().frame(width: 43, alignment: .trailing)
            }
        }
    }

    private func loadReference(_ reference: AudioReference?) {
        guard let reference else {
            audio.unload()
            missingAudio = false
            return
        }
        let url = reference.url
        do {
            if audio.loadedURL != url { try audio.load(url) }
            try audio.configure(settings)
            missingAudio = false
        } catch {
            audio.unload()
            missingAudio = true
        }
    }

    private func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the recording for this transcription."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAudio(url)
    }

    private func importAudio(_ url: URL) {
        perform {
            try audio.load(url)
            var next = settings
            if !missingAudio && reference?.url != url {
                next.a = nil
                next.b = nil
                next.looping = false
            }
            if next.region(in: audio.duration) == nil { next.looping = false }
            settings = next
            reference = AudioReference(url)
            missingAudio = false
            try audio.configure(settings)
        }
    }

    private func mark(start: Bool) {
        audio.refreshPosition()
        var next = settings
        if start { next.a = audio.position } else { next.b = audio.position }
        if next.region(in: audio.duration) == nil { next.looping = false }
        settings = next
    }

    private func seek(_ seconds: Double) {
        perform {
            if settings.looping, settings.region(in: audio.duration)?.contains(seconds) != true {
                settings.looping = false
            }
            try audio.configure(settings, seekTo: seconds)
        }
    }

    private func selectRegion(_ a: Double, _ b: Double) {
        var next = settings
        next.a = a
        next.b = b
        guard next.region(in: audio.duration) != nil else {
            seek(a)
            return
        }
        next.looping = true
        settings = next
        perform {
            try audio.configure(next, seekTo: a)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }

}

func recordingTime(_ seconds: Double) -> String {
    let hundredths = Int(max(0, seconds) * 100)
    return String(format: "%d:%02d.%02d", hundredths / 6000, hundredths / 100 % 60, hundredths % 100)
}

struct WaveformWindow {
    static let maximumZoom = 32
    let duration: Double
    let zoom: Int
    let start: Double
    var span: Double { duration / Double(zoom) }
    var end: Double { start + span }
    var maxStart: Double { duration - span }

    init(duration: Double, zoom: Int, start: Double) {
        self.duration = duration
        self.zoom = zoom
        self.start = min(max(start, 0), duration - duration / Double(zoom))
    }

    func centered(on time: Double, zoom: Int) -> Self {
        Self(duration: duration, zoom: zoom, start: time - duration / Double(zoom) / 2)
    }

    func x(_ seconds: Double, width: CGFloat) -> CGFloat {
        width * (seconds - start) / span
    }

    func time(_ x: CGFloat, width: CGFloat) -> Double {
        start + span * min(max(x / width, 0), 1)
    }
}

private struct Waveform: View {
    private struct MarkerPosition {
        let marker: LoopMarker
        let x: CGFloat
        let badge: CGRect
    }

    let audio: AudioTransport
    let settings: PlaybackSettings
    let window: WaveformWindow
    let dropTargeted: Bool
    let seek: (Double) -> Void
    let select: (Double, Double) -> Void
    let moveMarkers: (PlaybackSettings) -> Void
    @GestureState private var drag: DragGesture.Value?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                Canvas { context, size in
                    guard window.span > 0 else { return }
                    let moved = drag.flatMap { resizedLoop(for: $0, width: width) }
                    let displayed = moved ?? settings
                    drawPeaks(in: context, size: size)
                    if let drag, moved == nil, abs(drag.translation.width) > 4 {
                        let end = min(max(drag.location.x, 0), width)
                        band(min(drag.startLocation.x, end), max(drag.startLocation.x, end),
                             in: context, height: size.height, opacity: 0.28)
                    } else if let region = displayed.region(in: audio.duration) {
                        let a = max(region.lowerBound, window.start)
                        let b = min(region.upperBound, window.end)
                        if a < b {
                            band(window.x(a, width: width), window.x(b, width: width),
                                 in: context, height: size.height, opacity: displayed.looping ? 0.22 : 0.09)
                        }
                    }
                    if (window.start...window.end).contains(audio.position) {
                        line(window.x(audio.position, width: width), in: context, height: size.height, color: .primary)
                    }
                    drawMarkers(displayed, in: context, size: size)
                }
                if dropTargeted || audio.loadedURL == nil || audio.waveformLoading {
                    Text(dropTargeted ? "Drop to load recording" :
                         audio.waveformLoading ? "Reading waveform…" : "Drop an audio file here or choose Import Audio…")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($drag) { value, state, _ in state = value }
                .onEnded { value in
                    guard audio.duration > 0, width > 0 else { return }
                    let a = window.time(value.startLocation.x, width: width)
                    let b = window.time(value.location.x, width: width)
                    if let moved = resizedLoop(for: value, width: width) {
                        moveMarkers(moved)
                    } else if abs(value.translation.width) > 4 {
                        select(min(a, b), max(a, b))
                    } else {
                        seek(b)
                    }
                })
        }
        .frame(height: 96)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.2),
                              lineWidth: dropTargeted ? 2 : 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio waveform")
        .accessibilityValue("\(audio.position.formatted(.number.precision(.fractionLength(1)))) seconds")
        .accessibilityAdjustableAction { direction in
            guard audio.duration > 0 else { return }
            seek(audio.position + (direction == .increment ? 5 : -5))
        }
    }

    private func resizedLoop(for drag: DragGesture.Value, width: CGFloat) -> PlaybackSettings? {
        guard abs(drag.translation.width) > 4 else { return nil }
        let positions = markers(settings, width: width)
        let position = positions.first { $0.badge.contains(drag.startLocation) } ??
            positions.filter { abs($0.x - drag.startLocation.x) <= 8 }
                .min { abs($0.x - drag.startLocation.x) < abs($1.x - drag.startLocation.x) }
        guard let position else { return nil }
        let time = window.time(position.x + drag.translation.width, width: width)
        return settings.moving(position.marker, to: time, duration: audio.duration)
    }

    private func markers(_ playback: PlaybackSettings, width: CGFloat) -> [MarkerPosition] {
        let badgeWidth: CGFloat = 18
        var positions: [MarkerPosition] = []
        for marker in LoopMarker.allCases {
            guard let time = playback[marker], (window.start...window.end).contains(time) else { continue }
            let x = window.x(time, width: width)
            let left = min(max(0, x - badgeWidth / 2), max(0, width - badgeWidth))
            let top: CGFloat = positions.contains { abs($0.badge.minX - left) < badgeWidth + 3 } ? 22 : 3
            positions.append(MarkerPosition(marker: marker, x: x,
                                            badge: CGRect(x: left, y: top, width: badgeWidth, height: 16)))
        }
        return positions
    }

    private func drawMarkers(_ playback: PlaybackSettings, in context: GraphicsContext, size: CGSize) {
        let positions = markers(playback, width: size.width)
        for position in positions {
            line(position.x, in: context, height: size.height, color: .accentColor, width: 3)
        }
        for position in positions {
            context.fill(Path(roundedRect: position.badge, cornerRadius: 3), with: .color(.accentColor))
            context.draw(Text(position.marker.rawValue).font(.caption2.bold()).foregroundStyle(.white),
                         at: CGPoint(x: position.badge.midX, y: position.badge.midY))
        }
    }

    private func drawPeaks(in context: GraphicsContext, size: CGSize) {
        let peaks = audio.waveform
        guard !peaks.isEmpty else { return }
        let first = min(peaks.count - 1, Int(window.start / audio.duration * Double(peaks.count)))
        let last = min(peaks.count, max(first + 1, Int(ceil(window.end / audio.duration * Double(peaks.count)))))
        let count = last - first
        let columns = min(count, max(1, Int(size.width * 1.5)))
        let amplitude = size.height * 0.46 / CGFloat(audio.waveformScale)
        let mid = size.height / 2
        var path = Path()
        for column in 0..<columns {
            let lower = first + column * count / columns
            let upper = first + (column + 1) * count / columns
            let peak = CGFloat(peaks[lower..<upper].max() ?? 0)
            let time = Double(lower + upper) / 2 / Double(peaks.count) * audio.duration
            let x = window.x(time, width: size.width)
            let height = max(0.5, peak * amplitude)
            path.move(to: CGPoint(x: x, y: mid - height))
            path.addLine(to: CGPoint(x: x, y: mid + height))
        }
        context.stroke(path, with: .color(.secondary), lineWidth: 0.8)
    }

    private func band(_ start: CGFloat, _ end: CGFloat, in context: GraphicsContext, height: CGFloat, opacity: Double) {
        context.fill(Path(CGRect(x: start, y: 0, width: end - start, height: height)),
                     with: .color(.accentColor.opacity(opacity)))
    }

    private func line(_ x: CGFloat, in context: GraphicsContext, height: CGFloat, color: Color, width: CGFloat = 1.3) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))
        context.stroke(path, with: .color(color), lineWidth: width)
    }
}
