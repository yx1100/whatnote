import AppKit

@main
struct StorageProbe {
    @MainActor
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let legacyDirectoryName = ["Desktop", "Sticky"].joined()

        let migrationBase = root.appendingPathComponent("migration", isDirectory: true)
        let legacyDirectory = migrationBase.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        try manager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyFile = legacyDirectory.appendingPathComponent("notes.json")
        let savedNotes = Data("saved notes".utf8)
        try savedNotes.write(to: legacyFile)

        let migratedFile = NoteStorage.resolveFileURL(in: migrationBase, manager: manager)
        precondition(migratedFile == migrationBase.appendingPathComponent("Whatnote/notes.json"))
        let migratedNotes = try Data(contentsOf: migratedFile)
        precondition(migratedNotes == savedNotes)

        // Notes from the Deskbit era move to the new folder; the old copy stays as a backup.
        let renameBase = root.appendingPathComponent("rename", isDirectory: true)
        let deskbitDirectory = renameBase.appendingPathComponent("Deskbit", isDirectory: true)
        try manager.createDirectory(at: deskbitDirectory, withIntermediateDirectories: true)
        let deskbitNotes = Data("deskbit notes".utf8)
        try deskbitNotes.write(to: deskbitDirectory.appendingPathComponent("notes.json"))
        let renamedFile = NoteStorage.resolveFileURL(in: renameBase, manager: manager)
        precondition(renamedFile == renameBase.appendingPathComponent("Whatnote/notes.json"))
        let renamedNotes = try Data(contentsOf: renamedFile)
        precondition(renamedNotes == deskbitNotes)
        precondition(manager.fileExists(atPath: deskbitDirectory.appendingPathComponent("notes.json").path))

        let fallbackBase = root.appendingPathComponent("fallback", isDirectory: true)
        let fallbackLegacyDirectory = fallbackBase.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        try manager.createDirectory(at: fallbackLegacyDirectory, withIntermediateDirectories: true)
        let fallbackLegacyFile = fallbackLegacyDirectory.appendingPathComponent("notes.json")
        try savedNotes.write(to: fallbackLegacyFile)
        try manager.createDirectory(at: fallbackBase, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: fallbackBase.appendingPathComponent("Whatnote"))

        let fallbackFile = NoteStorage.resolveFileURL(in: fallbackBase, manager: manager)
        precondition(fallbackFile == fallbackLegacyFile)
        let fallbackNotes = try Data(contentsOf: fallbackFile)
        precondition(fallbackNotes == savedNotes)

        let firstLaunchBase = root.appendingPathComponent("first-launch", isDirectory: true)
        let firstLaunchStore = NoteStore(baseURL: firstLaunchBase, manager: manager)
        precondition(firstLaunchStore.isFirstLaunch)
        let attributedGuide = NSMutableAttributedString(string: "欢迎使用随便记")
        attributedGuide.addAttribute(
            .font,
            value: NoteAppearance.bodyFont(weight: .bold),
            range: NSRange(location: 0, length: 7)
        )
        let guide = firstLaunchStore.add(attributedText: attributedGuide)
        precondition(guide.text == "欢迎使用随便记")
        precondition(guide.richTextData != nil)

        let reopenedStore = NoteStore(baseURL: firstLaunchBase, manager: manager)
        precondition(!reopenedStore.isFirstLaunch)
        precondition(reopenedStore.activeNotes.map(\.text) == ["欢迎使用随便记"])
        let restoredGuide = RichTextCodec.decode(reopenedStore.activeNotes.first?.richTextData)
        let restoredFont = restoredGuide?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        precondition(restoredFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)

        // Notes saved before the lock existed still load (unlocked), and the lock is saved.
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","text":"旧便签","color":"yellow",\
        "frame":{"x":0,"y":0,"width":340,"height":260},"isPinned":false,"isHidden":false,\
        "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}]
        """
        let noteDecoder = JSONDecoder()
        noteDecoder.dateDecodingStrategy = .iso8601
        let noteEncoder = JSONEncoder()
        noteEncoder.dateEncodingStrategy = .iso8601
        let legacyNotes = try! noteDecoder.decode([StickyNote].self, from: Data(legacyJSON.utf8))
        precondition(legacyNotes.count == 1 && legacyNotes[0].text == "旧便签" && !legacyNotes[0].isLocked)
        var lockedNote = legacyNotes[0]
        lockedNote.isLocked = true
        let reloaded = try! noteDecoder.decode([StickyNote].self, from: noteEncoder.encode([lockedNote]))
        precondition(reloaded[0].isLocked && reloaded[0].unlockedFrame == nil)
        // Notes saved before text-size generations are generation 0 and are converted once.
        precondition(legacyNotes[0].fontGeneration == 0 && StickyNote.fresh().fontGeneration == NoteAppearance.fontGeneration)
        lockedNote.unlockedFrame = WindowFrame(NSRect(x: 10, y: 20, width: 340, height: 260))
        let withFrame = try! noteDecoder.decode([StickyNote].self, from: noteEncoder.encode([lockedNote]))
        precondition(withFrame[0].unlockedFrame?.rect == NSRect(x: 10, y: 20, width: 340, height: 260))

        print("storage migration and first-launch detection: pass")
    }
}
