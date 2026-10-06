#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
probe_binary="$(mktemp /tmp/whatnote-other-apps-ui.XXXXXX)"
trap 'rm -f "$probe_binary"' EXIT

swiftc \
  "$project_dir/Sources/Whatnote/OtherAppsUI.swift" \
  "$project_dir/Tests/OtherAppsUIProbe.swift" \
  -o "$probe_binary"

"$probe_binary"
