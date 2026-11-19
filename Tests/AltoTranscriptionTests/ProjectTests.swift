import Foundation
import PDFKit
import Testing
@testable import AltoTranscription

@Test func projectRoundTripKeepsWrittenNotesAndPlaybackSettings() throws {
    let url = URL(fileURLWithPath: "/tmp/solo.wav")
    var project = Project()
    #expect(project.meter == .fourFour)
    project.meter = .threeFour
    project.keySignature = .g
    project.audio = AudioReference(url)
    project.notes = [
        ScoreEvent(pitch: -3, value: .eighth, dotted: true, accidental: .flat),
        ScoreEvent(pitch: nil, value: .sixteenth),
        ScoreEvent(pitch: 8, value: .quarter, accidental: .natural)
    ]
    project.playback = PlaybackSettings(speed: 0.65, a: 1.25, b: 3.5, looping: true)
    let bytes = try JSONEncoder().encode(project)
    let restored = try Project.decode(bytes)

    #expect(restored == project)
    #expect(restored.audio?.url.path == url.path)
    #expect(restored.notes[0].pitchLabel() == "B♭3")
    #expect(restored.playback.region(in: 4) == 1.25..<3.5)
    #expect(restored.playback.region(in: 3) == nil)

    project.playback.speed = 0.25
    let badSpeed = try JSONEncoder().encode(project)
    #expect(throws: CocoaError.self) { try Project.decode(badSpeed) }
}

@Test func splitNotesAndRestsAtFourFourBarlines() {
    let notes = [
        ScoreEvent(pitch: 0, value: .half, dotted: true),
        ScoreEvent(pitch: 1, value: .eighth, dotted: true),
        ScoreEvent(pitch: 2, value: .thirtySecond, dotted: true),
        ScoreEvent(pitch: 3, value: .thirtySecond),
        ScoreEvent(pitch: nil, value: .whole)
    ]
    let layout = ScoreLayout(notes)
    #expect(layout.barlines.count == 2)
    let crossing = layout.fragments.filter { $0.index == 3 }
    #expect(crossing.map(\.value) == [.sixtyFourth, .sixtyFourth])
    #expect(crossing.map(\.tiedFromPrevious) == [false, true])
    #expect(layout.fragments.filter { $0.index == 4 }.allSatisfy { $0.pitch == nil })
    #expect(layout.fragments.reduce(0) { $0 + $1.value.ticks(dotted: $1.dotted) } ==
            notes.reduce(0) { $0 + $1.ticks })
    #expect(layout.index(at: layout.appendX, entryIndex: notes.count) == notes.count)
    #expect(ScoreLayout.pitch(at: ScoreLayout.y(for: 8)) == 8)
    let waltz = ScoreLayout(Array(repeating: ScoreEvent(pitch: 0), count: 3), meter: .threeFour)
    #expect(waltz.barlines.count == 1)
}

@Test func writtenAccidentalsCarryAndResetInTheMeasure() {
    let notes = [
        ScoreEvent(pitch: 0, accidental: .sharp),
        ScoreEvent(pitch: 0, accidental: .sharp),
        ScoreEvent(pitch: 0),
        ScoreEvent(pitch: 0, accidental: .sharp),
        ScoreEvent(pitch: 0, accidental: .sharp)
    ]
    let layout = ScoreLayout(notes)
    #expect(layout.fragments.map(\.accidental) == [.sharp, nil, .natural, .sharp, .sharp])
    #expect(ScoreEvent.nearestPitch(letter: "c", to: ScoreEvent.middleB) == 5)
}


@Test func previousProjectsOpenWithoutNewSettings() throws {
    let old = Data(#"{"version":1,"meter":"4/4","notes":[],"playback":{"speed":1,"looping":false}}"#.utf8)
    let project = try Project.decode(old)
    #expect(project.keySignature == .c)
}

@Test func writtenKeySuppliesDefaultAccidentalsAcrossOctaves() {
    let notes = [
        ScoreEvent(pitch: 1),
        ScoreEvent(pitch: 1, accidental: .natural),
        ScoreEvent(pitch: 1),
        ScoreEvent(pitch: 8),
        ScoreEvent(pitch: 8)
    ]
    #expect(notes[0].pitchLabel(in: .g) == "F♯4")
    #expect(ScoreLayout(notes, key: .g).fragments.map(\.accidental) == [nil, .natural, .sharp, nil, nil])
    #expect(ScoreEvent(pitch: 4).pitchLabel(in: .f) == "B♭4")
}

@Test func legacySyncSettingsAreIgnoredAndDoNotChangeTheScoreOrPlayback() throws {
    let data = Data(#"{"version":1,"meter":"4/4","keySignature":-2,"notes":[{"pitch":4,"value":16,"dotted":false}],"playback":{"speed":0.72,"a":2,"b":4,"looping":true},"sync":{"enabled":true,"bpm":96,"barOne":2}}"#.utf8)
    let project = try Project.decode(data)
    #expect(project.keySignature == .bFlat)
    #expect(project.notes.first?.pitchLabel(in: project.keySignature) == "B♭4")
    #expect(project.playback.region(in: 5) == 2..<4)
    let saved = try JSONEncoder().encode(project)
    #expect(!String(decoding: saved, as: UTF8.self).contains(#""sync""#))
}

@Test func zoomedWaveformCoordinatesUseOriginalAudioTime() {
    let full = WaveformWindow(duration: 180, zoom: 1, start: 0)
    let close = full.centered(on: 98, zoom: 32)
    #expect(close.time(400, width: 800) == 98)
    #expect(close.x(98, width: 800) == 400)
    #expect(close.time(-20, width: 800) == close.start)
    #expect(full.centered(on: 0, zoom: 8).start == 0)
    #expect(full.centered(on: 180, zoom: 8).end == 180)
}

@Test @MainActor func scoresWrapAndExportToMultiplePrintablePages() throws {
    let notes = Array(repeating: ScoreEvent(pitch: 8, value: .sixteenth), count: 80)
    let layout = ScoreLayout(notes, key: .bFlat, spacing: 0.78)
    let rows = layout.wrappedRows(width: 548)
    #expect(rows.count > 4)
    #expect(rows.flatMap(\.fragments).map(\.index) == Array(notes.indices))
    for row in rows {
        let first = try #require(row.fragments.first)
        #expect(row.index(at: first.x) == first.index)
        #expect(first.bar == first.index / 16 + 1)
    }
    #expect(rows.allSatisfy { row in row.barlines.allSatisfy { $0 <= 532 } })
    let data = try ScorePDF.render(notes, meter: .fourFour, key: .bFlat, title: "Alto PDF Check")
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount == (rows.count + 3) / 4)
    #expect(pdf.page(at: 0)?.string?.contains("alto saxophone") == true)
}

@Test func narrowEditorWrapsTheEntryWithoutAddingAPrintRow() throws {
    let notes = Array(repeating: ScoreEvent(pitch: 1, value: .quarter), count: 4)
    let layout = ScoreLayout(notes)
    let print = layout.wrappedRows(width: 300)
    let editor = layout.wrappedRows(width: 300, includeEntry: true)
    let entry = try #require(editor.last)
    #expect(print.count == 1)
    #expect(editor.count == 2)
    #expect(editor.first?.index(at: 280) == 3)
    #expect(entry.firstBar == 2)
    #expect(entry.fragments.isEmpty)
    #expect(entry.index(at: entry.appendX, entryIndex: notes.count) == 4)
    let wide = try #require(layout.wrappedRows(width: 650, includeEntry: true).last)
    #expect(wide.fragments.count == 4)
    #expect(wide.index(at: wide.appendX, entryIndex: notes.count) == 4)
}
