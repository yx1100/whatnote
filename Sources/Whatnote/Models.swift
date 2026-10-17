import AppKit

/// Note colors. Raw values match earlier versions so saved notes keep their color.
enum NoteColor: String, Codable, CaseIterable {
    case pink
    case yellow
    case blue
    case mint

    /// The note paper, also the fill of the color dot. Light tints keep black text at 10:1 contrast or better.
    var background: NSColor {
        switch self {
        case .blue: return Self.srgb(0xCFE6F5)
        case .mint: return Self.srgb(0xCDEEE6)
        case .yellow: return Self.srgb(0xF6F0BE)
        case .pink: return Self.srgb(0xFBD9D4)
        }
    }

    /// Deeper shade for the dot's ring, checked to-do circles and active buttons.
    var accent: NSColor {
        switch self {
        case .blue: return Self.srgb(0x2E7DA6)
        case .mint: return Self.srgb(0x2A8475)
        case .yellow: return Self.srgb(0x7F7A22)
        case .pink: return Self.srgb(0xC0625A)
        }
    }

    var title: String {
        switch self {
        case .blue: return "蓝色"
        case .mint: return "绿色"
        case .yellow: return "黄色"
        case .pink: return "粉色"
        }
    }

    private static func srgb(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct WindowFrame: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ frame: NSRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.size.width
        height = frame.size.height
    }

    var rect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}

struct StickyNote: Codable, Identifiable {
    var id: UUID
    var text: String
    var richTextData: Data?
    var color: NoteColor
    var frame: WindowFrame
    var isPinned: Bool
    /// A locked note cannot be moved, resized or edited; its to-do items can still be checked.
    var isLocked: Bool
    var isHidden: Bool
    var reminderDate: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    static func fresh(index: Int = 0, frame: NSRect? = nil) -> StickyNote {
        let size = NoteAppearance.defaultSize
        let initialFrame: NSRect
        if let frame {
            initialFrame = frame
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let offset = CGFloat((index % 6) * 26)
            let origin = NSPoint(
                x: screen.midX - size.width / 2 + offset,
                y: screen.midY - size.height / 2 - offset
            )
            initialFrame = NSRect(origin: origin, size: size)
        }
        return StickyNote(
            id: UUID(),
            text: "",
            richTextData: nil,
            color: NoteColor.allCases[index % NoteColor.allCases.count],
            frame: WindowFrame(initialFrame),
            isPinned: false,
            isLocked: false,
            isHidden: false,
            reminderDate: nil,
            completedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

extension StickyNote {
    /// Notes saved before a field existed decode with its default, so an update never loses notes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
        color = try container.decode(NoteColor.self, forKey: .color)
        frame = try container.decode(WindowFrame.self, forKey: .frame)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        reminderDate = try container.decodeIfPresent(Date.self, forKey: .reminderDate)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
