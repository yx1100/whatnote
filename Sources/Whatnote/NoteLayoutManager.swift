import AppKit

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
        if CodeBlock.isCodeLine(in: storage, at: charIndex) { return false }
        if ListMarker.isMarkerSpace(in: string, at: charIndex) { return true }
        return orderedMarkerStart(containing: charIndex, in: string) != nil
    }

    /// Start of the paragraph when `charIndex` is inside the number of a numbered item's marker.
    private func orderedMarkerStart(containing charIndex: Int, in string: NSString) -> Int? {
        guard charIndex >= 0, charIndex < string.length else { return nil }
        let start = string.paragraphRange(for: NSRange(location: charIndex, length: 0)).location
        guard let length = ListMarker.length(in: string, atParagraphStart: start), length > 2,
              charIndex < start + length - 1 else { return nil }
        return start
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
        if let start = orderedMarkerStart(containing: charIndex, in: storage.string as NSString) {
            // The whole number is drawn by hand from its first character; the rest take no room.
            let string = storage.string as NSString
            let font = storage.attribute(.font, at: start, effectiveRange: nil) as? NSFont ?? NoteAppearance.bodyFont()
            let width = charIndex == start
                ? ListMarker.length(in: string, atParagraphStart: start).map {
                    ListMarker.markerWidth(in: string, atParagraphStart: start, markerLength: $0, font: font)
                } ?? 0
                : 0
            return NSRect(x: glyphPosition.x, y: glyphPosition.y, width: width, height: 0)
        }
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
        for marker in orderedMarkers(in: glyphsToShow, string: string) {
            replaced.append((marker.glyphs, { [self] in
                let first = marker.glyphs.location
                let lineRect = lineFragmentRect(forGlyphAt: first, effectiveRange: nil)
                let location = self.location(forGlyphAt: first)
                let attributes = storage.attributes(at: marker.start, effectiveRange: nil)
                let font = attributes[.font] as? NSFont ?? NoteAppearance.bodyFont()
                let point = NSPoint(
                    x: origin.x + lineRect.minX + location.x + marker.shift,
                    y: origin.y + lineRect.minY + location.y - font.ascender
                )
                (marker.text as NSString).draw(at: point, withAttributes: [
                    .font: font,
                    .foregroundColor: attributes[.foregroundColor] ?? NoteAppearance.textColor
                ])
            }))
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

    /// The hand-drawn numbers of numbered items whose markers start in `glyphRange`.
    private func orderedMarkers(
        in glyphRange: NSRange,
        string: NSString
    ) -> [(start: Int, glyphs: NSRange, text: String, shift: CGFloat)] {
        guard let storage = textStorage, string.length > 0 else { return [] }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var markers: [(start: Int, glyphs: NSRange, text: String, shift: CGFloat)] = []
        var location = string.paragraphRange(for: NSRange(location: min(characters.location, string.length - 1), length: 0)).location
        while location < NSMaxRange(characters), location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraph)
            guard !CodeBlock.isCodeLine(in: storage, at: paragraph.location),
                  let length = ListMarker.length(in: string, atParagraphStart: paragraph.location), length > 2 else { continue }
            let font = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont ?? NoteAppearance.bodyFont()
            guard let layout = ListMarker.orderedLayout(
                in: string, atParagraphStart: paragraph.location, markerLength: length, font: font
            ) else { continue }
            let glyphs = NSIntersectionRange(
                self.glyphRange(
                    forCharacterRange: NSRange(location: paragraph.location, length: length - 1),
                    actualCharacterRange: nil
                ),
                glyphRange
            )
            guard glyphs.length > 0, glyphs.location == glyphIndexForCharacter(at: paragraph.location) else { continue }
            markers.append((paragraph.location, glyphs, layout.text, layout.shift))
        }
        return markers
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
