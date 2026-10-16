#!/bin/zsh
# Updates to a branch, runs every check, builds 随便记, and installs and opens the new version.
#
#   ./scripts/install.sh                                   # main
#   ./scripts/install.sh <branch>                           # a pull request’s branch
set -euo pipefail

main() {
  local project_dir="${0:A:h:h}"
  local branch="${1:-main}"
  local log_dir
  log_dir="$(mktemp -d /tmp/whatnote-install.XXXXXX)"
  cd "$project_dir"

  if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 "✗ 有未提交的本地修改，先处理后再运行："
    git status --short >&2
    exit 1
  fi

  print "→ 获取 $branch"
  git fetch --quiet origin "$branch"
  git checkout --quiet -B "$branch" "origin/$branch"
  print "  $(git log --oneline -1)"

  print "→ 运行检查"
  local -a failed=()
  local test_script name
  for test_script in scripts/test-*.sh; do
    name="${test_script:t:r}"
    if "$test_script" > "$log_dir/$name.log" 2>&1; then
      print "  ✓ ${name#test-}"
    else
      print "  ✗ ${name#test-}"
      failed+=("$name")
    fi
  done
  if (( ${#failed} )); then
    print -u2 "\n✗ 有检查没通过，把下面的输出发给 Claude："
    for name in "${failed[@]}"; do
      print -u2 "\n===== $name ====="
      cat "$log_dir/$name.log" >&2
    done
    exit 1
  fi

  print "→ 构建"
  if ! ./scripts/build-app.sh > "$log_dir/build.log" 2>&1; then
    print -u2 "\n✗ 构建失败，把下面的输出发给 Claude："
    cat "$log_dir/build.log" >&2
    exit 1
  fi

  print "→ 安装并打开"
  osascript -e 'tell application id "com.yx1100.whatnote" to quit' > /dev/null 2>&1 || true
  pkill -x Whatnote > /dev/null 2>&1 || true
  sleep 1
  rm -rf /Applications/Whatnote.app
  cp -R dist/Whatnote.app /Applications/
  open /Applications/Whatnote.app
  rm -rf "$log_dir"
  print "✓ 已安装并打开新版随便记（$branch）"
}

main "$@"
