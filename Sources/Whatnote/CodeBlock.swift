import AppKit

/// Fenced code blocks (```). A code line is a paragraph whose first-line and head indents
/// are both `inset`; lists and plain text never indent that way. Unlike custom attributes,
/// indents survive saving as RTF.
enum CodeBlock {
    static let inset: CGFloat = 10
    /// Space between the code text and the edge of its background, above and below.
    static let verticalPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 8
    static let background = NSColor.black.withAlphaComponent(0.06)
    private static let fenceExpression = try? NSRegularExpression(pattern: #"^\s*```[^`\s]*\s*$"#)

    static func font() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: NoteAppearance.bodyFontSize - 1, weight: .regular)
    }

    static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = inset
        style.headIndent = inset
        style.tailIndent = -inset
        return style
    }

    static func attributes() -> [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: NoteAppearance.textColor, .paragraphStyle: paragraphStyle()]
    }

    static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [.font: NoteAppearance.bodyFont(), .foregroundColor: NoteAppearance.textColor, .paragraphStyle: NSParagraphStyle.default]
    }

    static func isCodeStyle(_ style: NSParagraphStyle?) -> Bool {
        guard let style else { return false }
        return abs(style.firstLineHeadIndent - inset) < 0.5 && abs(style.headIndent - inset) < 0.5
    }

    static func isCodeLine(in storage: NSAttributedString, at location: Int) -> Bool {
        guard location >= 0, location < storage.length else { return false }
        return isCodeStyle(storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
    }

    /// A line holding only an opening or closing fence, such as "```" or "```swift".
    static func isFence(_ line: String) -> Bool {
        guard let fenceExpression else { return false }
        return fenceExpression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Character ranges of whole code blocks (runs of code lines) touching `range`.
    static func blocks(in storage: NSAttributedString, overlapping range: NSRange) -> [NSRange] {
        let string = storage.string as NSString
        guard string.length > 0 else { return [] }
        var cursor = string.paragraphRange(for: NSRange(location: min(range.location, string.length - 1), length: 0)).location
        // Start from the top of a block that begins above the range.
        while cursor > 0, isCodeLine(in: storage, at: cursor) {
            let previous = string.paragraphRange(for: NSRange(location: cursor - 1, length: 0)).location
            guard isCodeLine(in: storage, at: previous) else { break }
            cursor = previous
        }
        let end = max(NSMaxRange(range), range.location + 1)
        var blocks: [NSRange] = []
        var current: NSRange?
        while cursor < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            if isCodeLine(in: storage, at: cursor) {
                current = current.map { NSUnionRange($0, paragraph) } ?? paragraph
            } else {
                if let block = current { blocks.append(block) }
                current = nil
                if cursor >= end { break }
            }
            cursor = NSMaxRange(paragraph)
            if current == nil, cursor >= end { break }
        }
        if let current { blocks.append(current) }
        return blocks
    }

    static func draw(in rect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}
