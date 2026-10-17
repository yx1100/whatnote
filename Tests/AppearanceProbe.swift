import AppKit

@main
struct AppearanceProbe {
    static func main() {
        guard NoteAppearance.defaultSize == NSSize(width: 340, height: 260) else { exit(1) }
        guard NoteAppearance.minimumSize == NSSize(width: 300, height: 200) else { exit(2) }
        guard NoteAppearance.bodyFontSize == 16 else { exit(3) }

        let font = NoteAppearance.bodyFont()
        guard font.pointSize == 16 else { exit(4) }

        // Notes of an earlier text-size generation are converted once: the old 13 and 18 pt body sizes, and
        // the headings of every earlier version (22, 19, 17 and 32, 24, 20 and 28, 23, 21).
        for (body, heading, newHeading) in [
            (CGFloat(13), CGFloat(20), CGFloat(24)), (16, 22, 24), (16, 19, 22), (16, 17, 20), (16, 32, 24),
            (16, 24, 22), (16, 28, 24), (16, 23, 22), (16, 21, 20), (18, 26, 24)
        ] {
            let legacy = NSMutableAttributedString(string: "标题", attributes: [.font: NSFont.systemFont(ofSize: heading)])
            legacy.append(NSAttributedString(string: "旧便签", attributes: [.font: NSFont.systemFont(ofSize: body)]))
            guard NoteAppearance.upgradeLegacyFontSizes(in: legacy, from: 0),
                  (legacy.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == newHeading,
                  (legacy.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize == 16,
                  !NoteAppearance.upgradeLegacyFontSizes(in: legacy, from: NoteAppearance.fontGeneration) else { exit(7) }
        }
        // A note already of today's generation is left alone, even where an old size equals a new one.
        let current = NSMutableAttributedString(string: "标题", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        current.append(NSAttributedString(string: "二级", attributes: [.font: NSFont.systemFont(ofSize: 22)]))
        current.append(NSAttributedString(string: "正文", attributes: [.font: NoteAppearance.bodyFont()]))
        guard !NoteAppearance.upgradeLegacyFontSizes(in: current, from: NoteAppearance.fontGeneration) else { exit(8) }
        guard StickyNote.fresh().fontGeneration == NoteAppearance.fontGeneration else { exit(10) }
        let note = StickyNote.fresh()
        guard note.frame.rect.size == NoteAppearance.defaultSize else { exit(5) }
        let requestedFrame = NSRect(x: 1512, y: 240, width: 300, height: 200)
        guard StickyNote.fresh(frame: requestedFrame).frame.rect == requestedFrame else { exit(6) }
        print("appearance defaults: pass")
    }
}
