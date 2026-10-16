import AppKit

/// To-do items are stored as "☐ " or "☑ " at the start of a paragraph, which keeps
/// the text portable and the Markdown handling simple, and are drawn as round checkboxes.
enum TodoMarker {
    static let pending: unichar = 0x2610
    static let completed: unichar = 0x2611
    static let characters = CharacterSet(charactersIn: "\u{2610}\u{2611}")

    /// nil unless `index` holds a to-do marker at the start of a paragraph;
    /// otherwise whether that item is checked.
    static func isCompleted(in string: NSString, at index: Int) -> Bool? {
        guard index >= 0, index + 1 < string.length, string.character(at: index + 1) == 0x20 else { return nil }
        if index > 0 {
            let previous = string.character(at: index - 1)
            guard previous == 0x0A || previous == 0x0D || previous == 0x2029 else { return nil }
        }
        switch string.character(at: index) {
        case pending: return false
        case completed: return true
        default: return nil
        }
    }
}

/// Bullets are stored as "• ", "∘ " or "▪ " (and the older "◦ ", "○ ") and drawn as small shapes
/// centered in the same marker box as a checkbox, so every kind of list starts at the same place.
enum BulletMarker {
    static let characters = CharacterSet(charactersIn: "\u{2022}\u{2218}\u{25AA}\u{25E6}\u{25CB}")

    enum Shape { case disc, ring, square }

    /// nil unless `index` holds a bullet at the start of a paragraph, followed by its space.
    static func shape(in string: NSString, at index: Int) -> Shape? {
        guard index >= 0, index + 1 < string.length, string.character(at: index + 1) == 0x20 else { return nil }
        if index > 0 {
            let previous = string.character(at: index - 1)
            guard previous == 0x0A || previous == 0x0D || previous == 0x2029 else { return nil }
        }
        switch string.character(at: index) {
        case 0x2022: return .disc
        case 0x2218, 0x25E6, 0x25CB: return .ring
        case 0x25AA: return .square
        default: return nil
        }
    }

    /// Draws into a flipped view, centered in `box` (the marker's checkbox-sized box).
    static func draw(_ shape: Shape, in box: NSRect, color: NSColor) {
        let size = (box.width * 0.45).rounded()
        let center = NSPoint(x: box.midX, y: box.midY)
        let rect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        color.set()
        switch shape {
        case .disc:
            NSBezierPath(ovalIn: rect).fill()
        case .ring:
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.6, dy: 0.6))
            ring.lineWidth = 1.2
            ring.stroke()
        case .square:
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
        }
    }
}

/// The marker that starts a list line: a to-do marker ("☐ "), a bullet ("• ") or a number
/// ("12. "). The space after it is drawn as a fixed gap, and the cursor never stops inside it.
enum ListMarker {
    /// Where an item's text starts, measured from the left edge of its marker. Circles, bullets
    /// and short numbers all share this column, so the text of different lists lines up the
    /// way it does in Notes or Word. A wider marker (a two-digit or nested number) pushes its
    /// own text further right, never closer than `minimumGap`.
    static let textColumn: CGFloat = 22
    static let minimumGap: CGFloat = 4
    private static let symbols: Set<unichar> = [
        0x2610, 0x2611, // ☐ ☑
        0x2022, 0x2218, 0x25AA, // • ∘ ▪
        0x25E6, 0x25CB // ◦ ○ (older bullets)
    ]

    /// Length of the marker, space included, at the start of the paragraph at `start`.
    static func length(in string: NSString, atParagraphStart start: Int) -> Int? {
        guard start < string.length else { return nil }
        if start + 1 < string.length, symbols.contains(string.character(at: start)), string.character(at: start + 1) == 0x20 {
            return 2
        }
        // "12. " or, nested, "1.2. ".
        var index = start
        while true {
            let groupStart = index
            while index < string.length, index - groupStart < 4, (0x30...0x39).contains(string.character(at: index)) { index += 1 }
            guard index > groupStart, index < string.length, string.character(at: index) == 0x2E else { return nil }
            index += 1
            guard index < string.length else { return nil }
            if string.character(at: index) == 0x20 { return index - start + 1 }
        }
    }

    /// Width of the marker itself, without the gap before the text.
    static func markerWidth(in string: NSString, atParagraphStart start: Int, markerLength: Int, font: NSFont) -> CGFloat {
        // Circles and bullets are drawn in a box the size of a checkbox.
        if markerLength == 2 { return TodoCheckbox.markerWidth(for: font) }
        let marker = string.substring(with: NSRange(location: start, length: markerLength - 1))
        return (marker as NSString).size(withAttributes: [.font: font]).width
    }

    /// Distance from the marker's left edge to the item's text, for the item at `start`.
    static func textOffset(in string: NSString, atParagraphStart start: Int, font: NSFont) -> CGFloat? {
        guard let markerLength = length(in: string, atParagraphStart: start) else { return nil }
        let width = markerWidth(in: string, atParagraphStart: start, markerLength: markerLength, font: font)
        return max(textColumn, width + minimumGap).rounded()
    }

    /// Plain text for other apps: checkboxes, bullets and nested numbers become standard
    /// Markdown ("- [ ] ", "- [x] ", "- ", indented "1. "), so Markdown editors recognize them.
    /// `todoLevels` gives each line's checklist indent level, where known.
    static func markdown(from text: String, todoLevels: [Int] = []) -> String {
        let bulletIndent = ["•": "", "∘": "  ", "▪": "    ", "◦": "  ", "○": "  "]
        return text.components(separatedBy: "\n").enumerated().map { index, line -> String in
            if let number = line.range(of: #"^\d{1,4}(?:\.\d{1,4})+\. "#, options: .regularExpression) {
                let parts = line[number].dropLast(2).split(separator: ".")
                return String(repeating: "   ", count: parts.count - 1) + "\(parts.last ?? "1"). " + line[number.upperBound...]
            }
            guard line.count >= 2, line.dropFirst().first == " ", let first = line.first else { return line }
            let rest = line.dropFirst(2)
            let todoIndent = String(repeating: "  ", count: index < todoLevels.count ? todoLevels[index] : 0)
            switch first {
            case "☐": return todoIndent + "- [ ] " + rest
            case "☑": return todoIndent + "- [x] " + rest
            default:
                guard let indent = bulletIndent[String(first)] else { return line }
                return indent + "- " + rest
            }
        }.joined(separator: "\n")
    }

    /// Markdown for copied rich text; checklist indents come from the paragraph styles.
    static func markdown(from text: NSAttributedString, indentStep: CGFloat = 18) -> String {
        let string = text.string as NSString
        var levels: [Int] = []
        var location = 0
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: min(location, max(0, string.length - 1)), length: 0))
            let style = string.length > 0
                ? text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                : nil
            levels.append(max(0, Int(round((style?.firstLineHeadIndent ?? 0) / indentStep))))
            location = NSMaxRange(paragraph)
        } while location < string.length
        return markdown(from: text.string, todoLevels: levels)
    }

    /// Whether the character at `index` is the space ending a list marker.
    static func isMarkerSpace(in string: NSString, at index: Int) -> Bool {
        guard index > 0, index < string.length, string.character(at: index) == 0x20 else { return false }
        let start = string.paragraphRange(for: NSRange(location: index, length: 0)).location
        return length(in: string, atParagraphStart: start).map { start + $0 - 1 == index } ?? false
    }
}

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

enum TodoCheckbox {
    /// Checkboxes keep the body-text size even on a line in a heading's larger font, such as
    /// a to-do started right under a heading.
    static func diameter(for font: NSFont) -> CGFloat {
        (min(font.pointSize, NoteAppearance.bodyFontSize) * 0.9).rounded()
    }

    /// Space the marker takes in the line: the circle plus a small gap before the following space.
    static func markerWidth(for font: NSFont) -> CGFloat {
        diameter(for: font) + 4
    }

    /// Where the checkbox for the marker glyph sits, in text container coordinates.
    static func rect(forGlyphAt glyphIndex: Int, layoutManager: NSLayoutManager) -> NSRect {
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyphIndex)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let markerFont = font(at: characterIndex, in: layoutManager.textStorage)
        // Center on the item's text, which follows the marker and its space.
        let textFont = font(at: characterIndex + 2, in: layoutManager.textStorage) ?? markerFont
        let size = diameter(for: markerFont ?? NoteAppearance.bodyFont())
        let baseline = lineRect.minY + location.y
        let centerY = baseline - (textFont ?? NoteAppearance.bodyFont()).pointSize * 0.33
        return NSRect(
            x: lineRect.minX + location.x,
            y: (centerY - size / 2).rounded(),
            width: size,
            height: size
        )
    }

    private static func font(at index: Int, in storage: NSTextStorage?) -> NSFont? {
        guard let storage, index >= 0, index < storage.length else { return nil }
        return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    /// Draws into a flipped view (text views are flipped: y grows downward).
    static func draw(isCompleted: Bool, in rect: NSRect, accent: NSColor) {
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
        guard isCompleted else {
            NoteAppearance.checkboxStrokeColor.setStroke()
            circle.lineWidth = 1.4
            circle.stroke()
            return
        }
        accent.setFill()
        circle.fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.52))
        check.line(to: NSPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.67))
        check.line(to: NSPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.35))
        check.lineWidth = max(1.5, rect.width * 0.11)
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.setStroke()
        check.stroke()
    }
}

/// Draws to-do markers as round checkboxes in place of the ☐ / ☑ glyphs,
/// and "---" paragraphs as divider lines.
/// The marker glyph is laid out as fixed-width whitespace, so the gap between
/// the circle and the text does not depend on which font happens to draw ☐.
final class NoteLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// Fill of checked circles; follows the note color.
    var checkboxAccent: NSColor = NoteAppearance.iconColor

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    /// Whether a character is a marker depends on its neighbors, so re-layout whole paragraphs.
    override func invalidateGlyphs(
        forCharacterRange charRange: NSRange,
        changeInLength delta: Int,
        actualCharacterRange actualCharRange: NSRangePointer?
    ) {
        guard let string = textStorage?.string as NSString?, charRange.location <= string.length else {
            super.invalidateGlyphs(forCharacterRange: charRange, changeInLength: delta, actualCharacterRange: actualCharRange)
            return
        }
        let length = min(charRange.length, string.length - charRange.location)
        var paragraphs = string.paragraphRange(for: NSRange(location: charRange.location, length: length))
        // Spacing and code-block padding depend on whether the neighboring paragraphs are code.
        if paragraphs.location > 0 {
            paragraphs = NSUnionRange(paragraphs, string.paragraphRange(for: NSRange(location: paragraphs.location - 1, length: 0)))
        }
        if NSMaxRange(paragraphs) < string.length {
            paragraphs = NSUnionRange(paragraphs, string.paragraphRange(for: NSRange(location: NSMaxRange(paragraphs), length: 0)))
        }
        super.invalidateGlyphs(
            forCharacterRange: NSUnionRange(charRange, paragraphs),
            changeInLength: delta,
            actualCharacterRange: actualCharRange
        )
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var properties: [NSLayoutManager.GlyphProperty]?
        for offset in 0..<glyphRange.length where isDrawnAsSpace(charIndexes[offset], in: storage) {
            if properties == nil {
                properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
            }
            properties?[offset] = .controlCharacter
        }
        guard let properties else { return 0 }
        properties.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            layoutManager.setGlyphs(
                glyphs,
                properties: base,
                characterIndexes: charIndexes,
                font: aFont,
                forGlyphRange: glyphRange
            )
        }
        return glyphRange.length
    }

    /// Spacing between wrapped lines and after each paragraph, uniform for every note.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        lineSpacingAfterGlyphAt glyphIndex: Int,
        withProposedLineFragmentRect rect: NSRect
    ) -> CGFloat {
        max(NoteAppearance.lineSpacing, paragraphStyle(atGlyph: glyphIndex, in: layoutManager)?.lineSpacing ?? 0)
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        paragraphSpacingAfterGlyphAt glyphIndex: Int,
        withProposedLineFragmentRect rect: NSRect
    ) -> CGFloat {
        let spacing = max(NoteAppearance.paragraphSpacing, paragraphStyle(atGlyph: glyphIndex, in: layoutManager)?.paragraphSpacing ?? 0)
        guard let storage = layoutManager.textStorage, storage.length > 0 else { return spacing }
        // Code lines sit close together; the block gets extra room above and below.
        let index = min(layoutManager.characterIndexForGlyph(at: glyphIndex), storage.length - 1)
        let next = NSMaxRange((storage.string as NSString).paragraphRange(for: NSRange(location: index, length: 0)))
        let isCode = CodeBlock.isCodeLine(in: storage, at: index)
        let nextIsCode = CodeBlock.isCodeLine(in: storage, at: next)
        if isCode, nextIsCode { return 0 }
        return isCode || nextIsCode ? spacing + CodeBlock.verticalPadding : spacing
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Code blocks go under the selection highlight that super draws.
        defer { super.drawBackground(forGlyphRange: glyphsToShow, at: origin) }
        guard let storage = textStorage, let container = textContainers.first else { return }
        let padding = container.lineFragmentPadding
        let lineHeight = defaultLineHeight(for: CodeBlock.font())
        func area(top: NSRect, bottom: NSRect) -> NSRect {
            NSRect(
                x: top.minX + padding,
                y: top.minY - CodeBlock.verticalPadding,
                width: top.width - 2 * padding,
                height: bottom.minY - top.minY + lineHeight + 2 * CodeBlock.verticalPadding
            )
        }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let areas = CodeBlock.blocks(in: storage, overlapping: characters).compactMap { block -> NSRect? in
            let glyphs = glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            return area(
                top: lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil),
                bottom: lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            )
        }
        for rect in areas {
            CodeBlock.draw(in: rect.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    private func paragraphStyle(atGlyph glyphIndex: Int, in layoutManager: NSLayoutManager) -> NSParagraphStyle? {
        guard let storage = layoutManager.textStorage, storage.length > 0 else { return nil }
        let index = min(layoutManager.characterIndexForGlyph(at: glyphIndex), storage.length - 1)
        return storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
    }

    /// To-do markers (drawn as checkboxes) and the space after any list marker (drawn as a
    /// fixed gap) are laid out as blank space of a set width.
    private func isDrawnAsSpace(_ charIndex: Int, in storage: NSTextStorage) -> Bool {
        let string = storage.string as NSString
        if TodoMarker.isCompleted(in: string, at: charIndex) != nil { return true }
        if BulletMarker.shape(in: string, at: charIndex) != nil { return !CodeBlock.isCodeLine(in: storage, at: charIndex) }
        return ListMarker.isMarkerSpace(in: string, at: charIndex) && !CodeBlock.isCodeLine(in: storage, at: charIndex)
    }

    /// A list item's first word stays on the item's first line, breaking inside the word when it
    /// is longer than the line, instead of jumping down and leaving the marker alone.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldBreakLineByWordBeforeCharacterAt charIndex: Int
    ) -> Bool {
        guard let storage = layoutManager.textStorage, charIndex > 0, charIndex < storage.length else { return true }
        let string = storage.string as NSString
        let start = string.paragraphRange(for: NSRange(location: charIndex, length: 0)).location
        guard start < charIndex, let markerLength = ListMarker.length(in: string, atParagraphStart: start),
              start + markerLength == charIndex else { return true }
        return false
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, isDrawnAsSpace(charIndex, in: storage) else { return action }
        return .whitespace
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect,
        glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        guard let storage = layoutManager.textStorage else { return .zero }
        if (storage.string as NSString).character(at: charIndex) == 0x20 {
            // The gap fills the space between the marker and the item's text column.
            let string = storage.string as NSString
            let start = string.paragraphRange(for: NSRange(location: charIndex, length: 0)).location
            let font = storage.attribute(.font, at: start, effectiveRange: nil) as? NSFont ?? NoteAppearance.bodyFont()
            let width = ListMarker.length(in: string, atParagraphStart: start).map {
                ListMarker.markerWidth(in: string, atParagraphStart: start, markerLength: $0, font: font)
            } ?? 0
            let offset = ListMarker.textOffset(in: string, atParagraphStart: start, font: font) ?? ListMarker.minimumGap
            return NSRect(x: glyphPosition.x, y: glyphPosition.y, width: max(ListMarker.minimumGap, offset - width), height: 0)
        }
        let font = storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont ?? NoteAppearance.bodyFont()
        return NSRect(x: glyphPosition.x, y: glyphPosition.y, width: TodoCheckbox.markerWidth(for: font), height: 0)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard glyphsToShow.length > 0, let storage = textStorage else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let string = storage.string as NSString
        // Glyph ranges drawn by hand instead of as text, in order.
        var replaced: [(glyphs: NSRange, draw: () -> Void)] = bulletMarkers(in: glyphsToShow, string: string).map { marker in
            (NSRange(location: marker.glyph, length: 1), {
                let box = TodoCheckbox.rect(forGlyphAt: marker.glyph, layoutManager: self)
                BulletMarker.draw(marker.shape, in: box.offsetBy(dx: origin.x, dy: origin.y), color: NoteAppearance.textColor)
            })
        }
        replaced += todoMarkers(in: glyphsToShow, string: string).map { marker in
            (NSRange(location: marker.glyph, length: 1), {
                let box = TodoCheckbox.rect(forGlyphAt: marker.glyph, layoutManager: self)
                TodoCheckbox.draw(
                    isCompleted: marker.isCompleted,
                    in: box.offsetBy(dx: origin.x, dy: origin.y),
                    accent: self.checkboxAccent
                )
            })
        }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for divider in DividerLine.ranges(in: string, overlapping: characters)
        where !CodeBlock.isCodeLine(in: storage, at: divider.location) {
            let glyphs = NSIntersectionRange(glyphRange(forCharacterRange: divider, actualCharacterRange: nil), glyphsToShow)
            guard glyphs.length > 0 else { continue }
            replaced.append((glyphs, {
                let lineRect = self.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let fullWidth = self.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let area = NSRect(x: fullWidth.minX + (self.textContainers.first?.lineFragmentPadding ?? 0),
                                  y: lineRect.minY,
                                  width: fullWidth.width - 2 * (self.textContainers.first?.lineFragmentPadding ?? 0),
                                  height: lineRect.height)
                DividerLine.draw(in: area.offsetBy(dx: origin.x, dy: origin.y))
            }))
        }
        guard !replaced.isEmpty else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        replaced.sort { $0.glyphs.location < $1.glyphs.location }

        var segmentStart = glyphsToShow.location
        for item in replaced {
            if item.glyphs.location > segmentStart {
                super.drawGlyphs(
                    forGlyphRange: NSRange(location: segmentStart, length: item.glyphs.location - segmentStart),
                    at: origin
                )
            }
            item.draw()
            segmentStart = max(segmentStart, NSMaxRange(item.glyphs))
        }
        let end = NSMaxRange(glyphsToShow)
        if end > segmentStart {
            super.drawGlyphs(forGlyphRange: NSRange(location: segmentStart, length: end - segmentStart), at: origin)
        }
    }

    private func bulletMarkers(in glyphRange: NSRange, string: NSString) -> [(glyph: Int, shape: BulletMarker.Shape)] {
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let searchEnd = NSMaxRange(characters)
        var searchStart = characters.location
        var markers: [(glyph: Int, shape: BulletMarker.Shape)] = []
        while searchStart < searchEnd {
            let found = string.rangeOfCharacter(
                from: BulletMarker.characters,
                options: [],
                range: NSRange(location: searchStart, length: searchEnd - searchStart)
            )
            guard found.location != NSNotFound else { break }
            if let shape = BulletMarker.shape(in: string, at: found.location),
               let storage = textStorage, !CodeBlock.isCodeLine(in: storage, at: found.location) {
                let glyph = glyphIndexForCharacter(at: found.location)
                if NSLocationInRange(glyph, glyphRange) { markers.append((glyph, shape)) }
            }
            searchStart = NSMaxRange(found)
        }
        return markers
    }

    private func todoMarkers(in glyphRange: NSRange, string: NSString) -> [(glyph: Int, isCompleted: Bool)] {
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let searchEnd = NSMaxRange(characters)
        var searchStart = characters.location
        var markers: [(glyph: Int, isCompleted: Bool)] = []
        while searchStart < searchEnd {
            let found = string.rangeOfCharacter(
                from: TodoMarker.characters,
                options: [],
                range: NSRange(location: searchStart, length: searchEnd - searchStart)
            )
            guard found.location != NSNotFound else { break }
            if let isCompleted = TodoMarker.isCompleted(in: string, at: found.location) {
                let glyph = glyphIndexForCharacter(at: found.location)
                if NSLocationInRange(glyph, glyphRange) { markers.append((glyph, isCompleted)) }
            }
            searchStart = NSMaxRange(found)
        }
        return markers
    }
}
