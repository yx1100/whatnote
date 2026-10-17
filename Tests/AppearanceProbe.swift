import AppKit

@main
struct AppearanceProbe {
    static func main() {
        guard NoteAppearance.defaultSize == NSSize(width: 340, height: 260) else { exit(1) }
        guard NoteAppearance.minimumSize == NSSize(width: 300, height: 200) else { exit(2) }
        guard NoteAppearance.bodyFontSize == 16 else { exit(3) }

        let font = NoteAppearance.bodyFont()
        guard font.pointSize == 16 else { exit(4) }

        // Notes written at the old 13 and 18 pt body sizes, and with the earlier 22, 19 and 17 pt headings, are converted once.
        for (body, heading, newHeading) in [
            (CGFloat(13), CGFloat(20), CGFloat(28)), (16, 22, 28), (16, 19, 23), (16, 17, 21),
            (16, 32, 28), (16, 24, 23), (16, 20, 21), (18, 26, 28)
        ] {
            let legacy = NSMutableAttributedString(string: "标题", attributes: [.font: NSFont.systemFont(ofSize: heading)])
            legacy.append(NSAttributedString(string: "旧便签", attributes: [.font: NSFont.systemFont(ofSize: body)]))
            guard NoteAppearance.upgradeLegacyFontSizes(in: legacy),
                  (legacy.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == newHeading,
                  (legacy.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize == 16,
                  !NoteAppearance.upgradeLegacyFontSizes(in: legacy) else { exit(7) }
        }
        // Text already at today's sizes is left alone.
        let current = NSMutableAttributedString(string: "标题", attributes: [.font: NSFont.systemFont(ofSize: 28)])
        current.append(NSAttributedString(string: "二级", attributes: [.font: NSFont.systemFont(ofSize: 23)]))
        current.append(NSAttributedString(string: "三级", attributes: [.font: NSFont.systemFont(ofSize: 21)]))
        current.append(NSAttributedString(string: "正文", attributes: [.font: NoteAppearance.bodyFont()]))
        guard !NoteAppearance.upgradeLegacyFontSizes(in: current) else { exit(8) }
        // A note made only of a level 2 heading is no 24 pt body note.
        let onlyHeading = NSMutableAttributedString(string: "标题", attributes: [.font: NSFont.systemFont(ofSize: 23)])
        guard !NoteAppearance.upgradeLegacyFontSizes(in: onlyHeading) else { exit(9) }
        let note = StickyNote.fresh()
        guard note.frame.rect.size == NoteAppearance.defaultSize else { exit(5) }
        let requestedFrame = NSRect(x: 1512, y: 240, width: 300, height: 200)
        guard StickyNote.fresh(frame: requestedFrame).frame.rect == requestedFrame else { exit(6) }
        print("appearance defaults: pass")
    }
}
