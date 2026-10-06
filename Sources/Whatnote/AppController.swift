import AppKit
import UserNotifications

@MainActor
final class AppController: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate, AppStatusMenuTarget {
    private var controllers: [UUID: StickyWindowController] = [:]
    private var statusItem: NSStatusItem!
    private var historyPopover: NSPopover?
    private var historyDismissalMonitor: HistoryPopoverDismissalMonitor?
    private var historyPreview: HistoryPreviewController?
    private var preferencesWindowController: NSWindowController?
    private lazy var newNoteHotKey = GlobalHotKey { [weak self] in self?.createNote() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        configureMainMenu()
        configureStatusItem()
        newNoteHotKey.register(HotKeyPreferences.newNoteShortcut())

        let store = NoteStore.shared
        let notes = store.activeNotes
        if notes.isEmpty {
            if store.isFirstLaunch {
                let guide = store.add(attributedText: FirstLaunchGuide.attributedText)
                open(guide, focus: true)
            } else {
                createNote()
            }
        } else {
            notes.forEach { open($0) }
            if !notes.contains(where: { !$0.isHidden }) { showAllNotes() }
        }
    }

    func createNote(near sourceFrame: NSRect? = nil, in visibleFrame: NSRect? = nil) {
        let frame = sourceFrame.flatMap { source in
            visibleFrame.map {
                NoteCreationLayout.frame(near: source, size: NoteAppearance.defaultSize, in: $0)
            }
        }
        open(NoteStore.shared.add(frame: frame), focus: true)
    }

    func completeNote(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        controllers[id]?.close()
        controllers.removeValue(forKey: id)
        NoteStore.shared.complete(id: id)
        dismissHistoryPopover()
    }

    func show(noteID: UUID) {
        guard let note = NoteStore.shared.note(id: noteID), note.completedAt == nil else { return }
        if controllers[noteID] == nil { open(note) }
        controllers[noteID]?.showAndFocus()
    }

    private func open(_ note: StickyNote, focus: Bool = false) {
        let controller = StickyWindowController(note: note)
        controller.appController = self
        controllers[note.id] = controller
        if !note.isHidden {
            if focus { controller.showAndFocus() } else { controller.showWindow(nil) }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        // Match the visual weight of the system's menu bar icons.
        let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: "随便记")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""
        statusItem.button?.toolTip = "随便记"
        statusItem.menu = AppStatusMenu.make(target: self)
    }

    private func configureMainMenu() {
        NSApp.mainMenu = ApplicationMenu.make()
    }

    @objc func newNoteFromMenu() { createNote() }

    @objc func arrangeNotes() {
        let visibleNotes = NoteStore.shared.activeNotes.filter { !$0.isHidden }
        let notes = visibleNotes
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.createdAt < $1.createdAt
            }
        guard !notes.isEmpty,
              let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else { return }

        let sizes = notes.map { note in
            controllers[note.id]?.window?.frame.size ?? note.frame.rect.size
        }
        let area = NoteWindowLayout.usableFrame(in: screen.visibleFrame, avoiding: otherAppsUIFrames())
        let frames = NoteWindowLayout.alignedFrames(sizes: sizes, in: area)
        for (note, frame) in zip(notes, frames) {
            controllers[note.id]?.arrangeOnDesktop(to: frame)
        }
    }

    /// On-screen windows of other apps, such as the Dock or floating panels, in screen coordinates.
    /// Reading window bounds needs no extra permission.
    private func otherAppsUIFrames() -> [NSRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return windows.compactMap { info -> NSRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownProcess,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1 >= 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            // Window bounds are measured from the top of the main display; flip to AppKit's.
            return NSRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    func showHistory(relativeTo sourceView: NSView) {
        if historyPopover?.isShown == true {
            dismissHistoryPopover()
            return
        }
        presentHistory(relativeTo: sourceView)
    }

    private func presentHistory(relativeTo sourceView: NSView) {
        dismissHistoryPopover()
        let popover = NSPopover()
        // Stays open while notes are restored; a click outside it (or Esc) closes it.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        let preview = HistoryPreviewController()
        historyPreview = preview
        popover.contentViewController = HistoryPopoverViewController(
            notes: NoteStore.shared.completedNotes,
            onRestore: { [weak self] id in
                self?.restoreFromHistory(id: id)
            },
            onDelete: { id in
                // Already confirmed in the bubble next to the trash button.
                _ = NoteStore.shared.permanentlyDelete(id: id)
            },
            onClear: { [weak self] in
                self?.confirmClearHistory()
            },
            onHover: { [weak preview] note, row in
                preview?.hover(note, row: row)
            }
        )
        historyPopover = popover
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .minY)
        let dismissalMonitor = HistoryPopoverDismissalMonitor(
            popoverWindow: { [weak popover] in popover?.contentViewController?.view.window },
            relatedWindows: { [weak popover] in
                [(popover?.contentViewController as? HistoryPopoverViewController)?.confirmationWindow].compactMap { $0 }
            },
            onDismiss: { [weak self] in self?.dismissHistoryPopover() }
        )
        historyDismissalMonitor = dismissalMonitor
        dismissalMonitor.start()
    }

    /// Brings the note back on screen without taking focus from the popover, so the next
    /// 恢复 works with a single click.
    private func restoreFromHistory(id: UUID) {
        guard let note = NoteStore.shared.restore(id: id) else { return }
        let controller = StickyWindowController(note: note)
        controller.appController = self
        controllers[note.id] = controller
        controller.showWithoutFocus()
    }

    private func dismissHistoryPopover() {
        historyDismissalMonitor?.stop()
        historyDismissalMonitor = nil
        historyPreview?.hide()
        historyPreview = nil
        historyPopover?.close()
        historyPopover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === historyPopover else { return }
        historyDismissalMonitor?.stop()
        historyDismissalMonitor = nil
        historyPreview?.hide()
        historyPreview = nil
        historyPopover = nil
    }

    @objc func showHistoryFromMenu() {
        guard let sourceView = statusItem.button else { return }
        DispatchQueue.main.async { [weak self, weak sourceView] in
            guard let sourceView else { return }
            self?.showHistory(relativeTo: sourceView)
        }
    }

    @objc func showPreferencesFromMenu() {
        let windowController: NSWindowController
        if let existing = preferencesWindowController {
            windowController = existing
            (existing.contentViewController as? PreferencesViewController)?
                .update(shortcut: HotKeyPreferences.newNoteShortcut())
        } else {
            let viewController = PreferencesViewController(
                shortcut: HotKeyPreferences.newNoteShortcut(),
                applyShortcut: { [weak self] shortcut in
                    self?.applyNewNoteShortcut(shortcut) ?? false
                },
                onRecordingChanged: { [weak self] isRecording in
                    guard let self else { return }
                    // Release the current shortcut while recording so its key press reaches the recorder.
                    if isRecording {
                        self.newNoteHotKey.unregister()
                    } else {
                        self.newNoteHotKey.register(HotKeyPreferences.newNoteShortcut())
                    }
                }
            )
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 170),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "设置"
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = false
            // Panels hide when the app is deactivated; Settings should stay until closed.
            panel.hidesOnDeactivate = false
            panel.level = .normal
            panel.contentViewController = viewController
            panel.center()
            windowController = NSWindowController(window: panel)
            preferencesWindowController = windowController
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func applyNewNoteShortcut(_ shortcut: HotKeyShortcut?) -> Bool {
        guard newNoteHotKey.register(shortcut) else {
            newNoteHotKey.register(HotKeyPreferences.newNoteShortcut())
            return false
        }
        HotKeyPreferences.setNewNoteShortcut(shortcut)
        return true
    }

    private func confirmClearHistory() {
        dismissHistoryPopover()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "要删除所有已完成的便签吗？"
        alert.informativeText = "此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "全部删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NoteStore.shared.clearCompleted()
    }

    func beginDragging(noteID: UUID, event: NSEvent) {
        controllers[noteID]?.performWindowDrag(with: event)
    }

    /// Gathers every note onto the current desktop, including notes left on
    /// other desktops (Spaces) or on a display that is no longer connected.
    @objc func showAllNotes() {
        NSApp.activate(ignoringOtherApps: true)
        for note in NoteStore.shared.activeNotes {
            if controllers[note.id] == nil { open(note) }
            controllers[note.id]?.gatherToCurrentDesktop()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let value = response.notification.request.content.userInfo["noteID"] as? String
        if let value, let id = UUID(uuidString: value) {
            Task { @MainActor [weak self] in self?.show(noteID: id) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
