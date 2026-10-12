import AppKit

@main
struct FirstLaunchGuideProbe {
    static func main() {
        let guide = FirstLaunchGuide.text
        let attributedGuide = FirstLaunchGuide.attributedText

        precondition(guide == """
        欢迎使用随便记 👋

        快捷键
        ⌃⌥⌘空格  新建便签（在任何 App 中可用，可在设置中修改）
        ⌘B  粗体
        ⌘I  斜体
        ⌘K  添加链接
        ⌘7  项目符号列表
        ⌘8  编号列表
        ⌘9  核对清单
        ⇧⌘U  标记为已勾选
        ⌘W  关闭便签（也可连按两次 Esc）

        核对清单
        ☐ 点按左边的圆圈即可勾选
        在行首输入 [] 或 【】 加空格也能创建

        Markdown
        在行首输入 # 加空格变成标题，- 加空格变成项目符号，1. 加空格变成编号；单独一行输入 --- 变成分隔线，输入 ``` 后按回车开始代码块

        图片
        直接粘贴或拖入图片

        已完成的便签
        点按左上角的 ✓ 完成便签，之后可在菜单栏随便记图标 → 已完成的便签中恢复或删除
        """)
        verifyBold(in: attributedGuide, expected: ["\n快捷键\n", "\n核对清单\n", "\nMarkdown\n", "\n图片\n", "\n已完成的便签\n"])
        verifyRegular(in: attributedGuide, expected: ["欢迎使用", "随便记", "⌃⌥⌘空格", "粗体", "添加链接", "项目符号列表"])
        // The demo line is a real, clickable to-do item.
        precondition(TodoMarker.isCompleted(in: guide as NSString, at: (guide as NSString).range(of: "☐").location) == false)
        precondition(!guide.contains("**"))
        precondition(attributedGuide.string == guide)
        print("first-launch guide: pass")
    }

    private static func verifyBold(in guide: NSAttributedString, expected strings: [String]) {
        for string in strings {
            let range = (guide.string as NSString).range(of: string)
            precondition(range.location != NSNotFound)
            let location = string.hasPrefix("\n") ? range.location + 1 : range.location
            let font = guide.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            precondition(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, string)
        }
    }

    private static func verifyRegular(in guide: NSAttributedString, expected strings: [String]) {
        for string in strings {
            let range = (guide.string as NSString).range(of: string)
            precondition(range.location != NSNotFound)
            let font = guide.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            precondition(font.map { !NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, string)
        }
    }
}
