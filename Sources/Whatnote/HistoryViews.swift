import AppKit

/// The 已完成的便签 popover: a fixed-width list of completed notes. Restoring or deleting a
/// note removes its row and keeps the popover open, so several notes can be handled in a row.
/// Deleting one note is confirmed in a small bubble next to its trash button.
@MainActor
final class HistoryPopoverViewController: NSViewController {
    static let width: CGFloat = 320
    static let maximumHeight: CGFloat = 420
    private static let minimumHeight: CGFloat = 180
    private static let rowHeight: CGFloat = 56
    private static let rowSpacing: CGFloat = 6
    /// The header above the list and the 全部删除 button below it.
    private static let chromeHeight: CGFloat = 85
    private static let emptyListHeight: CGFloat = 92

    private(set) var notes: [StickyNote]
    private let onRestore: (UUID) -> Void
    /// Called once the deletion is confirmed.
    private let onDelete: (UUID) -> Void
    private let onClear: () -> Void
    /// The note under the mouse and its row, or nil when the mouse leaves the rows.
    private let onHover: (StickyNote?, NSView?) -> Void

    private let countLabel = NSTextField(labelWithString: "")
    private let list = NSStackView()
    private let clearButton = NSButton(title: "全部删除", target: nil, action: nil)
    private var heightConstraint: NSLayoutConstraint?
    private var documentHeightConstraint: NSLayoutConstraint?
    private var hoveredNoteID: UUID?
    private var confirmation: NSPopover?
    /// The note whose deletion is waiting for confirmation.
    private(set) var pendingDeleteID: UUID?

    /// The delete confirmation bubble's window, while it is open. Clicks there belong to the list.
    var confirmationWindow: NSWindow? { confirmation?.contentViewController?.view.window }

    init(
        notes: [StickyNote],
        onRestore: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onClear: @escaping () -> Void,
        onHover: @escaping (StickyNote?, NSView?) -> Void = { _, _ in }
    ) {
        self.notes = notes
        self.onRestore = onRestore
        self.onDelete = onDelete
        self.onClear = onClear
        self.onHover = onHover
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: Self.width, height: Self.height(forNoteCount: notes.count))
    }

    required init?(coder: NSCoder) { nil }

    static func height(forNoteCount count: Int) -> CGFloat {
        min(maximumHeight, max(minimumHeight, chromeHeight + listHeight(forNoteCount: count)))
    }

    private static func listHeight(forNoteCount count: Int) -> CGFloat {
        guard count > 0 else { return emptyListHeight }
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing + 4
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "已完成的便签")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [title, NSView(), countLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        let document = FlippedHistoryDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = Self.rowSpacing
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scrollView.documentView = document

        clearButton.target = self
        clearButton.action = #selector(clearHistory)
        clearButton.isBordered = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setAccessibilityLabel("删除所有已完成的便签")
        root.addSubview(clearButton)

        let height = root.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
        let documentHeight = document.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height
        documentHeightConstraint = documentHeight
        NSLayoutConstraint.activate([
            // A fixed width: long titles are cut short instead of widening the popover.
            root.widthAnchor.constraint(equalToConstant: Self.width),
            height,
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentHeight,
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 2),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -2),
            list.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            list.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -2),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            header.heightAnchor.constraint(equalToConstant: 24),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),
            clearButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            clearButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -9),
            clearButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        view = root
        reloadRows()
    }

    private func reloadRows() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if notes.isEmpty {
            let empty = NSTextField(labelWithString: "没有已完成的便签")
            empty.alignment = .center
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .tertiaryLabelColor
            empty.translatesAutoresizingMaskIntoConstraints = false
            list.addArrangedSubview(empty)
            empty.heightAnchor.constraint(equalToConstant: 88).isActive = true
        } else {
            for note in notes {
                let row = HistoryNoteRowView(
                    note: note,
                    onRestore: { [weak self] id in self?.restore(id) },
                    onDelete: { [weak self] id, button in self?.askToDelete(id, from: button) },
                    onHover: { [weak self] row, isHovered in self?.rowHoverChanged(row, isHovered: isHovered) }
                )
                list.addArrangedSubview(row)
                row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            }
        }

        countLabel.stringValue = "\(notes.count) 条"
        clearButton.isEnabled = !notes.isEmpty
        clearButton.attributedTitle = NSAttributedString(string: "全部删除", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: notes.isEmpty ? NSColor.tertiaryLabelColor : NSColor.systemRed
        ])

        let height = Self.height(forNoteCount: notes.count)
        preferredContentSize = NSSize(width: Self.width, height: height)
        heightConstraint?.constant = height
        documentHeightConstraint?.constant = max(Self.listHeight(forNoteCount: notes.count), height - Self.chromeHeight)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        cancelPendingDelete()
    }

    private func restore(_ id: UUID) {
        onRestore(id)
        removeRow(id)
    }

    private func askToDelete(_ id: UUID, from button: NSView) {
        closeConfirmation()
        pendingDeleteID = id
        guard button.window != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = DeleteConfirmationViewController(
            onConfirm: { [weak self] in self?.confirmPendingDelete() },
            onCancel: { [weak self] in self?.cancelPendingDelete() }
        )
        confirmation = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func confirmPendingDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        closeConfirmation()
        onDelete(id)
        removeRow(id)
    }

    private func cancelPendingDelete() {
        pendingDeleteID = nil
        closeConfirmation()
    }

    private func closeConfirmation() {
        guard let popover = confirmation else { return }
        confirmation = nil
        // Its buttons may still be handling the click that closes it.
        DispatchQueue.main.async { popover.close() }
    }

    private func removeRow(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if hoveredNoteID != nil {
            hoveredNoteID = nil
            onHover(nil, nil)
        }
        // The row's button is still handling the click, so hide the row now and rebuild the
        // list once the click is done.
        list.arrangedSubviews.first { ($0 as? HistoryNoteRowView)?.note.id == id }?.isHidden = true
        DispatchQueue.main.async { [weak self] in self?.reloadRows() }
    }

    private func rowHoverChanged(_ row: HistoryNoteRowView, isHovered: Bool) {
        if isHovered {
            hoveredNoteID = row.note.id
            onHover(row.note, row)
        } else if hoveredNoteID == row.note.id {
            hoveredNoteID = nil
            onHover(nil, nil)
        }
    }

    @objc private func clearHistory() { onClear() }
}

/// The title shown for a completed note: its first line with text, without a list marker.
enum HistoryNoteTitle {
    private static let markers: Set<Character> = ["☐", "☑", "•", "∘", "▪", "◦", "○"]

    static func title(for text: String) -> String {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine).replacingOccurrences(of: "\u{FFFC}", with: "🖼")
            if let first = line.first, markers.contains(first), line.dropFirst().first == " " {
                line = String(line.dropFirst(2))
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !isDivider(trimmed) else { continue }
            return trimmed
        }
        return "空白便签"
    }

    private static func isDivider(_ line: String) -> Bool {
        guard line.count >= 3, let first = line.first, "-*_".contains(first) else { return false }
        return line.allSatisfy { $0 == first }
    }
}

private final class FlippedHistoryDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A completed note drawn as a small note of its own color, with 恢复 and delete buttons.
@MainActor
private final class HistoryNoteRowView: NSView {
    let note: StickyNote
    private let onRestore: (UUID) -> Void
    /// Asks to delete the note; the view is the trash button, where the confirmation appears.
    private let onDelete: (UUID, NSView) -> Void
    private let onHover: (HistoryNoteRowView, Bool) -> Void
    private var isHovered = false { didSet { updateBorder() } }
    private var hoverArea: NSTrackingArea?

    init(
        note: StickyNote,
        onRestore: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID, NSView) -> Void,
        onHover: @escaping (HistoryNoteRowView, Bool) -> Void
    ) {
        self.note = note
        self.onRestore = onRestore
        self.onDelete = onDelete
        self.onHover = onHover
        super.init(frame: .zero)
        // Rows are light paper whatever the system appearance.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = note.color.background.cgColor
        layer?.borderWidth = 1
        updateBorder()

        let title = NSTextField(labelWithString: HistoryNoteTitle.title(for: note.text))
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = NoteAppearance.textColor
        title.lineBreakMode = .byTruncatingTail
        title.allowsExpansionToolTips = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let completed = NSTextField(labelWithString: Self.formattedDate(note.completedAt))
        completed.font = .systemFont(ofSize: 11)
        completed.textColor = NSColor.black.withAlphaComponent(0.5)
        completed.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [title, completed])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(labels)

        let restore = HistoryRestoreButton(accent: note.color.accent, target: self, action: #selector(restoreNote))
        restore.toolTip = "恢复便签"
        restore.setAccessibilityLabel("恢复便签")
        addSubview(restore)

        let delete = HistoryDeleteButton(target: self, action: #selector(deleteNote(_:)))
        delete.toolTip = "删除"
        delete.setAccessibilityLabel("删除便签")
        addSubview(delete)

        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: restore.leadingAnchor, constant: -8),
            restore.trailingAnchor.constraint(equalTo: delete.leadingAnchor, constant: -4),
            restore.centerYAnchor.constraint(equalTo: centerYAnchor),
            restore.widthAnchor.constraint(equalToConstant: 52),
            restore.heightAnchor.constraint(equalToConstant: 24),
            delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            delete.centerYAnchor.constraint(equalTo: centerYAnchor),
            delete.widthAnchor.constraint(equalToConstant: 26),
            delete.heightAnchor.constraint(equalToConstant: 26)
        ])

        let hoverArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(hoverArea)
        self.hoverArea = hoverArea
    }

    required init?(coder: NSCoder) { nil }

    // Subviews such as the labels pass their own enter and exit events up to the row; only
    // the row's own area says whether the mouse is on the row.
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === hoverArea, !isHovered else { return }
        isHovered = true
        onHover(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hoverArea, isHovered else { return }
        isHovered = false
        onHover(self, false)
    }

    private func updateBorder() {
        layer?.borderColor = note.color.accent.withAlphaComponent(isHovered ? 0.55 : 0.18).cgColor
    }

    @objc private func restoreNote() { onRestore(note.id) }
    @objc private func deleteNote(_ sender: NSButton) { onDelete(note.id, sender) }

    private static func formattedDate(_ date: Date?) -> String {
        guard let date else { return "完成时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
        return formatter.string(from: date)
    }
}

/// The bubble asking to confirm deleting one note: a short question and two equal buttons.
@MainActor
private final class DeleteConfirmationViewController: NSViewController {
    private static let size = NSSize(width: 200, height: 104)
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.size
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))

        let title = NSTextField(labelWithString: "删除这条便签？")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        let detail = NSTextField(labelWithString: "删除后无法恢复")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center

        let cancel = BubbleButton(
            title: "取消",
            fill: NSColor.labelColor.withAlphaComponent(0.1),
            textColor: .labelColor,
            target: self,
            action: #selector(cancel)
        )
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityLabel("取消删除")
        let delete = BubbleButton(
            title: "删除",
            fill: .systemRed,
            textColor: .white,
            target: self,
            action: #selector(confirm)
        )
        delete.keyEquivalent = "\r"
        delete.setAccessibilityLabel("确认删除")

        for view in [title, detail, cancel, delete] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            cancel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            cancel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            cancel.heightAnchor.constraint(equalToConstant: 28),
            delete.leadingAnchor.constraint(equalTo: cancel.trailingAnchor, constant: 8),
            delete.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            delete.bottomAnchor.constraint(equalTo: cancel.bottomAnchor),
            delete.heightAnchor.constraint(equalTo: cancel.heightAnchor),
            delete.widthAnchor.constraint(equalTo: cancel.widthAnchor)
        ])
        view = root
    }

    @objc private func confirm() { onConfirm() }
    @objc private func cancel() { onCancel() }
}

/// A filled capsule button for the confirmation bubble; it draws its own title so the
/// popover's translucent background cannot wash it out.
private final class BubbleButton: NSButton {
    private let label: String
    private let fill: NSColor
    private let textColor: NSColor
    private var isHovered = false { didSet { needsDisplay = true } }

    init(title: String, fill: NSColor, textColor: NSColor, target: AnyObject, action: Selector) {
        label = title
        self.fill = fill
        self.textColor = textColor
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = ""
        isBordered = false
        focusRingType = .none
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }

    override var allowsVibrancy: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        fill.setFill()
        capsule.fill()
        if isHighlighted || isHovered {
            NSColor.black.withAlphaComponent(isHighlighted ? 0.18 : 0.08).setFill()
            capsule.fill()
        }
        let title = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: textColor
        ])
        let size = title.size()
        title.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// 恢复: a small white capsule with the note's accent color.
private final class HistoryRestoreButton: NSButton {
    private static let label = "恢复"
    private let accent: NSColor
    private var isHovered = false { didSet { needsDisplay = true } }

    init(accent: NSColor, target: AnyObject, action: Selector) {
        self.accent = accent
        super.init(frame: .zero)
        self.target = target
        self.action = action
        // Drawn below; an empty title keeps AppKit from drawing a second one on top.
        title = ""
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The popover's translucent background would otherwise wash the capsule out to white.
    override var allowsVibrancy: Bool { false }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(isHighlighted ? 0.95 : (isHovered ? 0.8 : 0.55)).setFill()
        capsule.fill()
        accent.withAlphaComponent(isHovered ? 0.5 : 0.3).setStroke()
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: bounds.height / 2 - 0.5,
            yRadius: bounds.height / 2 - 0.5
        )
        outline.lineWidth = 1
        outline.stroke()
        let label = NSAttributedString(string: Self.label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: accent
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// Delete: a quiet trash icon that turns red under the mouse.
private final class HistoryDeleteButton: NSButton {
    private var isHovered = false { didSet { refresh() } }

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除便签")?
            .withSymbolConfiguration(configuration)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var allowsVibrancy: Bool { false }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.systemRed.withAlphaComponent(0.12).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        }
        super.draw(dirtyRect)
    }

    private func refresh() {
        contentTintColor = isHovered ? .systemRed : NSColor.black.withAlphaComponent(0.42)
        needsDisplay = true
    }
}
