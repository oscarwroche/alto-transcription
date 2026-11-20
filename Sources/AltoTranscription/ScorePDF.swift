import SwiftUI

enum ScorePDF {
    @MainActor
    static func render(_ notes: [ScoreEvent], meter: Meter, key: KeySignature, title: String,
                       instrument: String) throws -> Data {
        let output = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &page, [
                kCGPDFContextTitle: title
              ] as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }

        let margin: CGFloat = 32
        let width = page.width - margin * 2
        let rowHeight: CGFloat = 158
        let rows = ScoreLayout(notes, meter: meter, key: key, spacing: 0.78).wrappedRows(width: width)
        let rowsPerPage = 4
        let instrumentLabel = instrument.trimmingCharacters(in: .whitespacesAndNewlines)

        for first in stride(from: 0, to: rows.count, by: rowsPerPage) {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(page)

            draw(in: context, x: margin, y: 731) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                    if !instrumentLabel.isEmpty {
                        Text(instrumentLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .frame(width: width, height: 43, alignment: .topLeading)
            }

            for (offset, row) in rows[first..<min(first + rowsPerPage, rows.count)].enumerated() {
                draw(in: context, x: margin, y: 544 - CGFloat(offset) * rowHeight) {
                    StaffDrawing(layout: row, cursor: nil).frame(width: width, height: ScoreLayout.height)
                }
            }
            draw(in: context, x: margin, y: 24) {
                Text("\(first / rowsPerPage + 1) / \((rows.count + rowsPerPage - 1) / rowsPerPage)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(width: width, alignment: .trailing)
            }

            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    @MainActor
    private static func draw<Content: View>(in context: CGContext, x: CGFloat, y: CGFloat,
                                            @ViewBuilder content: () -> Content) {
        let renderer = ImageRenderer(content: content().environment(\.colorScheme, .light))
        renderer.render { _, draw in
            context.saveGState()
            context.translateBy(x: x, y: y)
            draw(context)
            context.restoreGState()
        }
    }
}
