# Alto Transcription

A native SwiftUI app for transcribing solos by ear into written E♭ alto saxophone notation. It runs on macOS 14 or later and uses only Apple frameworks.

Build the app with Xcode 16 or later installed:

```sh
./Scripts/build-app.sh
swift test
```

Open `dist/Alto Transcription.app` to start with a blank score. Use **Open Project…** or **Recent Projects** to resume a project, or drag one recording from Finder onto the editor. **Import Audio…** opens the file picker. Once loaded, click the waveform to seek or drag across it to set and activate an A/B loop. Slow the recording to 50–100% using the speed slider. Use the magnifiers to zoom around the playhead and the slider below the zoomed waveform to pan. Click the zoom level to show the whole recording. Save with ⌘S and open saved `.alto` files through Finder or the File menu. Each project stores its notation and audio controls in JSON and references the original recording on disk. If macOS cannot locate the source, use **Relink Audio**.

| Shortcut | Action |
| --- | --- |
| ⌘I | Import or relink audio |
| Space | Play or pause |
| ⌥A / ⌥B | Set a loop marker at the playhead |
| ⌥L | Toggle the selected loop |
| A–G | Write or edit a note in the nearest octave |
| ↑ / ↓ | Move by one staff step |
| ← / → | Select the previous or next event |
| Home / End | Jump to the first event or the entry cursor |
| Return | Insert a note at the cursor |
| 1–6 | Set duration from whole to thirty-second |
| . | Toggle dotted duration |
| R | Insert a rest or toggle the selected event between note and rest |
| [ / ] / backslash | Set flat, sharp, or natural |
| Delete | Delete the selected event or the last event |

Click the empty space at the end of the score to write a note at that height. Click an existing event to select it and drag vertically to change its pitch. Use **Insert** or Return to add an event before the selection. The score uses written alto pitches in treble clef, with a C key signature and 4/4 by default. Use **Key** to choose a signature for the written part. Unmarked notes follow the signature, and accidentals override it. You can also select 3/4, 5/4, or 6/8. Durations that cross barlines are split automatically and pitched fragments are tied together. The app records the pitches you enter as written alto pitches. The source audio keeps its original pitch.

Scroll vertically through the wrapped score and click any note to edit it. Use **Score Zoom** to make the notation larger or smaller. The transport stays above the score while you scroll. The score and recording are independent, so you can replay or slow down any passage without moving the score selection.

Use **Clear Score…** to remove every note and rest while keeping the recording and project settings. Press ⌘Z to restore the score after clearing it. Use **Export PDF…** to save a printable copy of the notation. The PDF heading uses the recording filename without its extension. A project with no recording uses the project name. Longer scores wrap across staff lines and pages. Open the PDF in Preview to print it. Save the .alto project as well if you want to keep editing.

The test suite renders the production audio graph offline and exercises waveform generation, speed and pitch, repeated loop boundaries, seek, and project restoration.
