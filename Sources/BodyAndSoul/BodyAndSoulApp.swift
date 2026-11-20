import SwiftUI
import Sparkle
import UniformTypeIdentifiers

@main
struct BodyAndSoulApp: App {
    private let updates: SPUStandardUpdaterController

    init() {
        // AppKit's document picker is useful for Open, but a fresh launch should start in the editor.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
        updates = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        DocumentGroup(newDocument: Project()) { configuration in
            ProjectView(project: configuration.$document,
                        title: configuration.fileURL?.deletingPathExtension().lastPathComponent ?? "Body and Soul")
                .frame(minWidth: 800, minHeight: 570)
        }
        .defaultSize(width: 940, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updates.updater)
            }
        }
    }
}

@MainActor
private final class UpdateAvailability: ObservableObject {
    @Published private(set) var canCheck = false

    init(_ updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
}

private struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @StateObject private var availability: UpdateAvailability

    init(updater: SPUUpdater) {
        self.updater = updater
        _availability = StateObject(wrappedValue: UpdateAvailability(updater))
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!availability.canCheck)
    }
}

private struct ProjectView: View {
    @Binding var project: Project
    let title: String
    @State private var audio = AudioTransport()
    @State private var droppedAudio: URL?
    @State private var audioDropTargeted = false

    private var pdfTitle: String {
        let recording = audio.loadedURL ?? project.audio.map { URL(fileURLWithPath: $0.path) }
        return recording?.deletingPathExtension().lastPathComponent ?? title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if project.audio == nil && project.notes.isEmpty {
                projectControls
            }
            AudioView(reference: $project.audio, settings: $project.playback,
                      droppedAudio: $droppedAudio, dropTargeted: audioDropTargeted, audio: audio)
            Divider()
            ScoreView(notes: $project.notes, meter: $project.meter, key: $project.keySignature,
                      instrument: $project.instrument, title: title, pdfTitle: pdfTitle)
        }
        .padding(22)
        .onDrop(of: [.fileURL], isTargeted: $audioDropTargeted, perform: receiveAudioDrop)
    }

    private func receiveAudioDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL else { return }
            Task { @MainActor in droppedAudio = url }
        }
        return true
    }

    private var projectControls: some View {
        HStack {
            Button("Open Project…") { NSDocumentController.shared.openDocument(nil) }
            Menu("Recent Projects") {
                let recent = NSDocumentController.shared.recentDocumentURLs
                if recent.isEmpty {
                    Text("No Recent Projects")
                }
                ForEach(recent, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        Task { @MainActor in
                            do {
                                _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
                            } catch {
                                NSApp.presentError(error)
                            }
                        }
                    }
                    .help(url.path)
                }
            }
            .fixedSize()
        }
    }
}
