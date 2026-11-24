#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

extensions="${DOT_MODULE_DIR:-$(dirname "$0")}/data/vscode-extensions"
coresim=${DOT_CORESIM_ROOT:-/Library/Developer/CoreSimulator}
platforms=(iOS watchOS)
# Xcode 27 mounts runtimes as cryptexes under /var/run, gone until CoreSimulator mounts them; its binary plist registry persists.
has_runtime() { compgen -G "$coresim/Volumes/*/Library/Developer/CoreSimulator/Profiles/Runtimes/$1 *.simruntime" >/dev/null || compgen -G "$coresim/Profiles/Runtimes/$1 *.simruntime" >/dev/null || grep -aqE "com\.apple\.CoreSimulator\.SimRuntime\.$1-[0-9]" "$coresim/Images/images.plist" 2>/dev/null; }
installed_extensions() { jq -r '.[].identifier.id // empty' "$HOME/.vscode/extensions/extensions.json" 2>/dev/null | tr '[:upper:]' '[:lower:]'; }
plugins="${DOT_MODULE_DIR:-$(dirname "$0")}/data/claude-plugins"
installed_plugins() { jq -r '.plugins // {} | to_entries[] | select(any(.value[]?; .scope == "user")) | .key' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; }

# uninstall.sh runs this on every Mac, and Xcode is on many that never enabled ios; the still-linked file is the proof it ran.
[[ $(readlink "$HOME/.swift-format" 2>/dev/null) == "${DOT_MODULE_DIR:-$(dirname "$0")}/home/.swift-format" ]] || exit 0

have=$(installed_extensions) || have=''
kept=()
while IFS= read -r id; do
  if [[ -z $id || $id == '#'* ]]; then continue; fi
  if grep -qxF "${id,,}" <<<"$have"; then kept+=("$id"); fi
done <"$extensions"

if ((${#kept[@]} > 0)); then
  warn 'left alone' "VS Code extensions: ${kept[*]}"
  for id in "${kept[@]}"; do dim "  code --uninstall-extension $id"; done
fi

have=$(installed_plugins) || have=''
kept=()
while IFS= read -r id; do
  if [[ -z $id || $id == '#'* ]]; then continue; fi
  if grep -qxF "$id" <<<"$have"; then kept+=("$id"); fi
done <"$plugins"

if ((${#kept[@]} > 0)); then
  warn 'left alone' "Claude Code plugins: ${kept[*]}"
  for id in "${kept[@]}"; do dim "  claude plugin uninstall $id"; done
fi

present=()
for platform in "${platforms[@]}"; do
  if has_runtime "$platform"; then present+=("$platform"); fi
done
if ((${#present[@]} > 0)); then
  warn 'left alone' "${present[*]} simulator runtimes -- several GB each"
  dim '  xcrun simctl runtime list, then: xcrun simctl runtime delete <id>'
fi

xcode_select=${DOT_XCODE_SELECT:-/usr/bin/xcode-select}
developer=$("$xcode_select" -p 2>/dev/null) || developer=''
xcode_ready() { [[ $developer == *.app/Contents/Developer && -x $developer/usr/bin/xcodebuild ]]; }
if xcode_ready; then
  app=${developer%/Contents/Developer}
  warn 'left alone' "${app/#$HOME/\~} -- over 10 GB"
  dim '  xcodes installed, then: xcodes uninstall <version>'
fi
