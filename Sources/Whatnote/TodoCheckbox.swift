import AppKit

/// The round checkbox drawn in place of a task marker.
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
