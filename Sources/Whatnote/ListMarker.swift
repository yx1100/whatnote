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

    /// Numbers ("3.", "1.2.") are drawn by hand, shifted right so the number itself (not its
    /// period) is centered on the same axis as the circle of a task or the dot of a bullet.
    /// Numbers too wide for that start at the left edge. `width` runs from the left edge to the
    /// end of the period.
    static func orderedLayout(
        in string: NSString,
        atParagraphStart start: Int,
        markerLength: Int,
        font: NSFont
    ) -> (text: String, shift: CGFloat, width: CGFloat)? {
        guard markerLength > 2 else { return nil }
        let text = string.substring(with: NSRange(location: start, length: markerLength - 1))
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let full = (text as NSString).size(withAttributes: attributes).width
        let number = (String(text.dropLast()) as NSString).size(withAttributes: attributes).width
        let shift = max(0, TodoCheckbox.diameter(for: font) / 2 - number / 2)
        return (text, shift, shift + full)
    }

    /// Width of the marker itself, without the gap before the text.
    static func markerWidth(in string: NSString, atParagraphStart start: Int, markerLength: Int, font: NSFont) -> CGFloat {
        if let ordered = orderedLayout(in: string, atParagraphStart: start, markerLength: markerLength, font: font) {
            return ordered.width
        }
        // Circles and bullets are drawn in a box the size of a checkbox.
        return TodoCheckbox.markerWidth(for: font)
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
