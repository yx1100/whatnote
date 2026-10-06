# 随便记 Whatnote

<p align="center">
  <img src="Assets/Whatnote-icon.png" width="128" alt="随便记 app icon">
</p>

<p align="center">随手记下任何事的 macOS 桌面便签。</p>

英文名 **Whatnote** 取自 “whatnot”（随便什么东西）加 “note”（记）。

## 功能

- 液态玻璃界面，红、黄、蓝、绿四种便签颜色
- 便签随内容增多自动向下延长
- Markdown：标题、粗体、斜体、删除线、行内代码、代码块、链接、各类列表、核对清单、分隔线
- 可点按勾选的圆形核对清单
- 粘贴或拖入图片，网址自动成为链接
- 全局快捷键在任何 App 中新建便签
- 置顶便签显示在所有桌面
- 已完成的便签：悬停预览完整内容，可连续恢复或删除
- 数据保存在本机：`~/Library/Application Support/Whatnote/notes.json`

需要 Apple Silicon Mac，macOS 11 或更高版本。

## 界面

- **左上角**：完成
- **右上角**：颜色、新建便签、置顶、排列便签
- **底部**：粗体、项目符号列表、编号列表、核对清单、分隔线、代码块、插入图片
- **菜单栏**：新建便签、排列便签、已完成的便签、显示所有便签、设置…、退出随便记

拖动顶部空白处移动便签，拖动边缘调整大小，双击底边让便签高度正好容纳内容。

## 快捷键

| 功能 | 快捷键 | Markdown |
| --- | --- | --- |
| 新建便签（全局） | `⌃⌥⌘空格` | — |
| 新建便签 | `⌘N` | — |
| 关闭便签 | `⌘W`、连按两次 `Esc` | — |
| 设置 | `⌘,` | — |
| 粗体 | `⌘B` | `**文本**` |
| 斜体 | `⌘I` | `*文本*` |
| 链接 | `⌘K` | `[文字](网址)` |
| 项目符号列表 | `⇧⌘7` | `- ` |
| 编号列表 | `⇧⌘9` | `1. ` |
| 核对清单 | `⇧⌘L` | `- [ ] ` |
| 标记为已勾选 | `⇧⌘U` | — |
| 缩进 / 取消缩进 | `Tab` / `⇧Tab` | — |
| 标题 | — | `# `、`## `、`### ` |
| 删除线 | — | `~~文本~~` |
| 行内代码 | — | `` `代码` `` |
| 分隔线 | — | 单独一行 `---` |
| 代码块 | — | 单独一行 ```` ``` ```` 后回车 |

- 列表中回车继续下一项，空项上回车结束列表
- 代码块中回车在块内换行；单独一行 ```` ``` ```` 后回车或点代码块按钮结束
- 关闭便签即“完成”，便签移到“已完成的便签”
- 在“已完成的便签”中，鼠标停在一条上显示完整内容；恢复或删除（在删除按钮旁确认）后列表保持打开，可接着处理下一条

## 设置

- 全局新建便签快捷键
- 连按两次 Esc 关闭便签、按 ⌘W 关闭便签
- 登录时打开

## 构建

需要 Xcode。

```bash
git clone https://github.com/yx1100/whatnote.git
cd whatnote
./scripts/build-app.sh
open dist/Whatnote.app
```

运行检查：

```bash
for test_script in scripts/test-*.sh; do "$test_script"; done
```

生成 DMG：

```bash
MARKETING_VERSION=1.3.0 BUILD_NUMBER=6 ./scripts/build-app.sh
./scripts/make-dmg.sh 1.3.0
```

## 许可证

[MIT](LICENSE)，基于 [tonyjianchina/Deskbit](https://github.com/tonyjianchina/Deskbit)。
