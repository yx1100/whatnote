#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
probe_binary="$(mktemp /tmp/whatnote-history-preview.XXXXXX)"
trap 'rm -f "$probe_binary"' EXIT

swiftc \
  "$project_dir/Sources/Whatnote/NoteAppearance.swift" \
  "$project_dir/Sources/Whatnote/Models.swift" \
  "$project_dir/Sources/Whatnote/RichTextCodec.swift" \
  "$project_dir/Sources/Whatnote/NoteMedia.swift" \
  "$project_dir/Sources/Whatnote/DividerLine.swift" \
  "$project_dir/Sources/Whatnote/LineBreak.swift" \
  "$project_dir/Sources/Whatnote/ListMarker.swift" \
  "$project_dir/Sources/Whatnote/NoteLayoutManager.swift" \
  "$project_dir/Sources/Whatnote/TodoCheckbox.swift" \
  "$project_dir/Sources/Whatnote/CodeBlock.swift" \
  "$project_dir/Sources/Whatnote/HistoryPreview.swift" \
  "$project_dir/Tests/HistoryPreviewProbe.swift" \
  -o "$probe_binary"

"$probe_binary"
