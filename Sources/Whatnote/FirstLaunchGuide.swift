import AppKit

enum FirstLaunchGuide {
    static var text: String { attributedText.string }

    static var attributedText: NSAttributedString {
        let regularFont = NoteAppearance.bodyFont()
        let boldFont = NoteAppearance.bodyFont(weight: .bold)
        let result = NSMutableAttributedString(
            string: "欢迎使用随便记 👋\n\n**快捷键**\n⌃⌥⌘空格  新建便签（在任何 App 中可用，可在设置中修改）\n⌘B  粗体\n⌘I  斜体\n⌘K  添加链接\n⌘7  项目符号列表\n⌘8  编号列表\n⌘9  核对清单\n⇧⌘U  标记为已勾选\n⌘W  关闭便签（也可连按两次 Esc）\n\n**核对清单**\n☐ 点按左边的圆圈即可勾选\n在行首输入 [] 或 【】 加空格也能创建\n\n**Markdown**\n在行首输入 # 加空格变成标题，- 加空格变成项目符号，1. 加空格变成编号；单独一行输入 --- 变成分隔线，输入 ``` 后按回车开始代码块\n\n**图片**\n直接粘贴或拖入图片\n\n**已完成的便签**\n点按左上角的 ✓ 完成便签，之后可在菜单栏随便记图标 → 已完成的便签中恢复或删除",
            attributes: [
                .font: regularFont,
                .foregroundColor: NoteAppearance.textColor
            ]
        )
        let fullRange = NSRange(location: 0, length: result.length)
        guard let expression = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#) else {
            return result
        }

        for match in expression.matches(in: result.string, range: fullRange).reversed() {
            let innerRange = NSRange(location: match.range.location + 2, length: match.range.length - 4)
            let replacement = NSMutableAttributedString(attributedString: result.attributedSubstring(from: innerRange))
            replacement.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: replacement.length))
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result
    }
}
