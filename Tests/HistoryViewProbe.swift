import AppKit

@main
struct HistoryViewProbe {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        var first = StickyNote.fresh(index: 0)
        first.text = "完成的第一条便签"
        first.completedAt = Date(timeIntervalSince1970: 100)
        var second = StickyNote.fresh(index: 1)
        second.text = "☐ 完成的第二条便签，标题很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长"
        second.completedAt = Date(timeIntervalSince1970: 200)

        var restoredIDs: [UUID] = []
        var deletedID: UUID?
        var clearCount = 0
        let controller = HistoryPopoverViewController(
            notes: [second, first],
            onRestore: { restoredIDs.append($0) },
            onDelete: { deletedID = $0 },
            onClear: { clearCount += 1 }
        )
        controller.loadView()
        controller.view.frame = NSRect(origin: .zero, size: controller.preferredContentSize)
        controller.view.layoutSubtreeIfNeeded()

        // A long title is cut short; the popover keeps its fixed width.
        guard controller.preferredContentSize.width == HistoryPopoverViewController.width,
              controller.view.fittingSize.width == HistoryPopoverViewController.width,
              controller.preferredContentSize.height >= 180 else { exit(1) }
        var controls = descendants(of: controller.view).compactMap { $0 as? NSControl }
        var labels = controls.compactMap { $0.accessibilityLabel() }
        guard labels.filter({ $0 == "恢复便签" }).count == 2,
              labels.filter({ $0 == "删除便签" }).count == 2,
              labels.contains("删除所有已完成的便签"),
              texts(in: controller.view).contains("2 条") else { exit(2) }

        if let capturePath = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".png") }),
           let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: capturePath))
            }
        }

        // Deleting asks first; once confirmed the row goes and the list stays open.
        controls.first(where: { $0.accessibilityLabel() == "删除便签" })?.performClick(nil)
        guard controller.pendingDeleteID == second.id, deletedID == nil else { exit(3) }
        controller.confirmPendingDelete()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        controls = descendants(of: controller.view).compactMap { $0 as? NSControl }
        labels = controls.compactMap { $0.accessibilityLabel() }
        guard deletedID == second.id,
              controller.pendingDeleteID == nil,
              controller.notes.map(\.id) == [first.id],
              labels.filter({ $0 == "删除便签" }).count == 1,
              texts(in: controller.view).contains("1 条") else { exit(9) }

        controls.first(where: { $0.accessibilityLabel() == "删除所有已完成的便签" })?.performClick(nil)
        guard clearCount == 1 else { exit(10) }

        // Restoring removes the row and keeps the list open for the next one.
        controls.first(where: { $0.accessibilityLabel() == "恢复便签" })?.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard restoredIDs == [first.id],
              controller.notes.isEmpty,
              texts(in: controller.view).contains("没有已完成的便签"),
              texts(in: controller.view).contains("0 条"),
              (descendants(of: controller.view).compactMap { $0 as? NSControl }
                .first(where: { $0.accessibilityLabel() == "删除所有已完成的便签" }))?.isEnabled == false else { exit(7) }

        let emptyController = HistoryPopoverViewController(
            notes: [],
            onRestore: { _ in },
            onDelete: { _ in },
            onClear: {}
        )
        emptyController.loadView()
        guard texts(in: emptyController.view).contains("没有已完成的便签") else { exit(4) }

        let manyNotes = (0..<8).map { index -> StickyNote in
            var note = StickyNote.fresh(index: index)
            note.text = "历史便签 \(index + 1)"
            note.completedAt = Date(timeIntervalSince1970: TimeInterval(index))
            return note
        }
        let scrollingController = HistoryPopoverViewController(
            notes: manyNotes,
            onRestore: { _ in },
            onDelete: { _ in },
            onClear: {}
        )
        scrollingController.loadView()
        scrollingController.view.frame = NSRect(origin: .zero, size: scrollingController.preferredContentSize)
        scrollingController.view.layoutSubtreeIfNeeded()
        guard scrollingController.preferredContentSize.height == HistoryPopoverViewController.maximumHeight,
              let scrollView = descendants(of: scrollingController.view).compactMap({ $0 as? NSScrollView }).first,
              let documentView = scrollView.documentView,
              documentView.frame.height > scrollView.contentView.bounds.height else { exit(5) }

        // Titles skip list markers, dividers and blank lines.
        guard HistoryNoteTitle.title(for: "☐ 买牛奶") == "买牛奶",
              HistoryNoteTitle.title(for: "\n---\n• 第一项") == "第一项",
              HistoryNoteTitle.title(for: "  ") == "空白便签" else { exit(8) }

        print("history popover: pass")
    }

    @MainActor
    private static func texts(in root: NSView) -> [String] {
        descendants(of: root).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    @MainActor
    private static func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
