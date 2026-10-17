import AppKit

enum NoteAppearance {
    static let defaultSize = NSSize(width: 340, height: 260)
    static let minimumSize = NSSize(width: 300, height: 200)
    static let bodyFontSize: CGFloat = 16
    static let cornerRadius: CGFloat = 16

    /// A locked note looks like a large desktop widget: fixed size, flat and a little see-through.
    static let lockedSize = NSSize(width: 344, height: 342)
    static let lockedCornerRadius: CGFloat = 25
    static let lockedPaperAlpha: CGFloat = 0.95

    /// Floating glass controls: the top strip doubles as the drag handle,
    /// and text scrolls underneath both bars.
    static let topBarHeight: CGFloat = 44
    static let bottomBarHeight: CGFloat = 44
    static let capsuleHeight: CGFloat = 30
    static let barMargin: CGFloat = 7

    static let textColor = NSColor.black.withAlphaComponent(0.82)
    static let iconColor = NSColor.black.withAlphaComponent(0.72)
    static let checkboxStrokeColor = NSColor.black.withAlphaComponent(0.45)

    static func bodyFont(weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: bodyFontSize, weight: weight)
    }

    /// The font to type or show text in: `font`, unless it is missing or AppKit's small default
    /// (every note font is at least 15 pt), in which case the body font.
    static func noteFont(_ font: NSFont?) -> NSFont {
        guard let font, font.pointSize >= 13 else { return bodyFont() }
        return font
    }

    /// Apple Symbols draws the to-do circle and list bullets, but its Latin letters are small.
    static func isSymbolFont(_ font: NSFont?) -> Bool { font?.familyName == "Apple Symbols" }

    /// Gives text without a note font the body font, and letters and digits drawn in the symbol
    /// font (markers and spaces keep it). Returns whether anything changed.
    @discardableResult
    static func repairFonts(in text: NSMutableAttributedString) -> Bool {
        var repairs: [NSRange] = []
        let string = text.string as NSString
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if noteFont(value as? NSFont) !== value as? NSFont {
                repairs.append(range)
            } else if isSymbolFont(value as? NSFont) {
                for index in range.location..<NSMaxRange(range)
                where CharacterSet.alphanumerics.contains(Unicode.Scalar(string.character(at: index)) ?? " ") {
                    repairs.append(NSRange(location: index, length: 1))
                }
            }
        }
        for range in repairs { text.addAttribute(.font, value: bodyFont(), range: range) }
        return !repairs.isEmpty
    }

    /// Line and paragraph spacing, applied by the note's layout manager to every paragraph.
    static let lineSpacing: CGFloat = 3
    static let paragraphSpacing: CGFloat = 8
}
