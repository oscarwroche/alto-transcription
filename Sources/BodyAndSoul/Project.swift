import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum NoteValue: Int, Codable, CaseIterable {
    case whole = 64, half = 32, quarter = 16, eighth = 8, sixteenth = 4, thirtySecond = 2, sixtyFourth = 1

    static let inputValues = allCases.filter { $0 != .sixtyFourth }

    func ticks(dotted: Bool) -> Int { dotted ? rawValue * 3 / 2 : rawValue }

    var label: String {
        switch self {
        case .whole: "Whole"
        case .half: "Half"
        case .quarter: "Quarter"
        case .eighth: "Eighth"
        case .sixteenth: "16th"
        case .thirtySecond: "32nd"
        case .sixtyFourth: "64th"
        }
    }

    var flags: Int {
        switch self {
        case .eighth: 1
        case .sixteenth: 2
        case .thirtySecond: 3
        case .sixtyFourth: 4
        default: 0
        }
    }
}

enum Accidental: String, Codable, CaseIterable {
    case flat = "♭", natural = "♮", sharp = "♯"
}

enum KeySignature: Int, Codable, CaseIterable {
    case cFlat = -7, gFlat, dFlat, aFlat, eFlat, bFlat, f, c, g, d, a, e, b, fSharp, cSharp

    private static let names = [
        "C♭ / A♭m", "G♭ / E♭m", "D♭ / B♭m", "A♭ / Fm", "E♭ / Cm", "B♭ / Gm", "F / Dm",
        "C / Am", "G / Em", "D / Bm", "A / F♯m", "E / C♯m", "B / G♯m", "F♯ / D♯m", "C♯ / A♯m"
    ]

    var label: String { Self.names[rawValue + 7] }
    var symbol: Accidental { rawValue < 0 ? .flat : .sharp }

    var positions: ArraySlice<Int> {
        let order = rawValue < 0 ? [4, 7, 3, 6, 2, 5, 1] : [8, 5, 9, 6, 3, 7, 4]
        return order.prefix(abs(rawValue))
    }

    func accidental(for pitch: Int) -> Accidental {
        positions.contains { ($0 - pitch).isMultiple(of: 7) } ? symbol : .natural
    }
}

struct ScoreEvent: Codable, Equatable {
    static let pitchRange = -4...16
    static let middleB = 4
    // Diatonic steps from written E4, the bottom line of the treble staff.
    var pitch: Int?
    var value: NoteValue = .quarter
    var dotted = false
    var accidental: Accidental?

    var ticks: Int { value.ticks(dotted: dotted) }

    func pitchLabel(in key: KeySignature = .c) -> String {
        guard let pitch else { return "Rest" }
        let index = pitch + 30
        let letter = Array("CDEFGAB")[index % 7]
        let signature = key.accidental(for: pitch)
        let symbol = accidental?.rawValue ?? (signature == .natural ? "" : signature.rawValue)
        return "\(letter)\(symbol)\(index / 7)"
    }

    static func nearestPitch(letter: Character, to pitch: Int) -> Int? {
        guard let letterIndex = "cdefgab".firstIndex(of: letter) else { return nil }
        let step = "cdefgab".distance(from: "cdefgab".startIndex, to: letterIndex)
        return pitchRange.filter { ($0 + 30) % 7 == step }
            .min { abs($0 - pitch) < abs($1 - pitch) }
    }
}

enum LoopMarker: String, CaseIterable {
    case start = "A"
    case end = "B"
}

struct PlaybackSettings: Codable, Equatable {
    static let minimumLoop = 0.05
    var speed = 1.0
    var a: Double?
    var b: Double?
    var looping = false

    func region(in duration: Double) -> Range<Double>? {
        guard let a, let b, a >= 0, b <= duration, a + Self.minimumLoop <= b else { return nil }
        return a..<b
    }

    subscript(marker: LoopMarker) -> Double? {
        switch marker {
        case .start: a
        case .end: b
        }
    }

    func moving(_ marker: LoopMarker, to time: Double, duration: Double) -> Self {
        var updated = self
        switch marker {
        case .start:
            let latest = b.map { max(0, ($0 - Self.minimumLoop).nextDown) } ?? duration
            updated.a = min(max(0, time), min(duration, latest))
        case .end:
            let earliest = a.map { $0 + Self.minimumLoop } ?? 0
            updated.b = min(duration, max(earliest, time))
        }
        if updated.region(in: duration) == nil { updated.looping = false }
        return updated
    }
}

struct AudioReference: Codable, Equatable {
    let path: String
    let bookmark: Data?

    init(_ url: URL) {
        path = url.path
        bookmark = try? url.bookmarkData(options: .minimalBookmark)
    }

    var url: URL {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                       relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.isReadableFile(atPath: resolved.path) {
                return resolved
            }
        }
        return URL(fileURLWithPath: path)
    }
}

enum Meter: String, Codable, CaseIterable {
    case threeFour = "3/4", fourFour = "4/4", fiveFour = "5/4", sixEight = "6/8"

    var numerator: Int {
        switch self {
        case .threeFour: 3
        case .fourFour: 4
        case .fiveFour: 5
        case .sixEight: 6
        }
    }

    var denominator: Int { self == .sixEight ? 8 : 4 }
    var ticks: Int { NoteValue.whole.rawValue / denominator * numerator }
}

struct Project: Codable, Equatable, FileDocument {
    static let contentType = UTType(exportedAs: "com.altotranscription.project", conformingTo: .json)
    static let readableContentTypes = [contentType]

    var version = 1
    var meter = Meter.fourFour
    var keySignature = KeySignature.c
    var instrument = ""
    var audio: AudioReference?
    var notes: [ScoreEvent] = []
    var playback = PlaybackSettings()

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        meter = try values.decode(Meter.self, forKey: .meter)
        keySignature = try values.decodeIfPresent(KeySignature.self, forKey: .keySignature) ?? .c
        instrument = try values.decodeIfPresent(String.self, forKey: .instrument) ?? ""
        audio = try values.decodeIfPresent(AudioReference.self, forKey: .audio)
        notes = try values.decode([ScoreEvent].self, forKey: .notes)
        playback = try values.decode(PlaybackSettings.self, forKey: .playback)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self = try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> Self {
        let project = try JSONDecoder().decode(Self.self, from: data)
        guard project.version == 1, (0.5...1).contains(project.playback.speed),
              [project.playback.a, project.playback.b].compactMap({ $0 }).allSatisfy({ (0...Double(UInt32.max)).contains($0) }),
              project.notes.allSatisfy({
                  NoteValue.inputValues.contains($0.value) && ($0.pitch.map(ScoreEvent.pitchRange.contains) ?? true)
              })
        else { throw CocoaError(.fileReadCorruptFile) }
        return project
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(self))
    }
}
