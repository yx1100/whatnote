import AppKit

/// A paragraph holding only "---", "***" or "___" (three or more) is a Markdown divider.
/// The text stays in the note and is drawn as a thin horizontal line.
enum DividerLine {
    static let marker = "---"
    private static let expression = try? NSRegularExpression(pattern: #"^(?:-{3,}|\*{3,}|_{3,})$"#)

    /// Whether the paragraph content (without its line break) is a divider.
    static func isDivider(_ content: String) -> Bool {
        guard let expression else { return false }
        let range = NSRange(location: 0, length: (content as NSString).length)
        return expression.firstMatch(in: content, range: range) != nil
    }

    /// Divider paragraphs overlapping `range`, without their line breaks.
    static func ranges(in string: NSString, overlapping range: NSRange) -> [NSRange] {
        guard string.length > 0 else { return [] }
        let location = min(range.location, string.length - 1)
        let span = string.paragraphRange(for: NSRange(location: location, length: min(range.length, string.length - location)))
        var result: [NSRange] = []
        var cursor = span.location
        while cursor < NSMaxRange(span) {
            let paragraph = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            var content = paragraph
            while content.length > 0,
                  [0x0A, 0x0D, 0x2029].contains(string.character(at: NSMaxRange(content) - 1)) {
                content.length -= 1
            }
            if content.length > 0, isDivider(string.substring(with: content)) { result.append(content) }
            guard NSMaxRange(paragraph) > cursor else { break }
            cursor = NSMaxRange(paragraph)
        }
        return result
    }

    static func draw(in lineRect: NSRect) {
        let y = lineRect.midY.rounded() + 0.5
        let line = NSBezierPath()
        line.move(to: NSPoint(x: lineRect.minX + 2, y: y))
        line.line(to: NSPoint(x: lineRect.maxX - 2, y: y))
        line.lineWidth = 1
        NSColor.black.withAlphaComponent(0.22).setStroke()
        line.stroke()
    }
}
