import Foundation

/// The characters that end a paragraph in a note: "\n", "\r" and U+2029.
enum LineBreak {
    static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2029
    }
}
