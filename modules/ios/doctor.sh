#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

extensions="${DOT_MODULE_DIR:-$(dirname "$0")}/data/vscode-extensions"
coresim=${DOT_CORESIM_ROOT:-/Library/Developer/CoreSimulator}
has_runtime() { compgen -G "$coresim/Volumes/*/Library/Developer/CoreSimulator/Profiles/Runtimes/$1 *.simruntime" >/dev/null || compgen -G "$coresim/Profiles/Runtimes/$1 *.simruntime" >/dev/null; }
installed_extensions() { jq -r '.[].identifier.id // empty' "$HOME/.vscode/extensions/extensions.json" 2>/dev/null | tr '[:upper:]' '[:lower:]'; }
plugins="${DOT_MODULE_DIR:-$(dirname "$0")}/data/claude-plugins"
installed_plugins() { jq -r '.plugins // {} | to_entries[] | select(any(.value[]?; .scope == "user")) | .key' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; }

xcode_select=${DOT_XCODE_SELECT:-/usr/bin/xcode-select}
developer=$("$xcode_select" -p 2>/dev/null) || developer=''
xcode_ready() { [[ $developer == *.app/Contents/Developer && -x $developer/usr/bin/xcodebuild ]]; }
if xcode_ready; then
  app=${developer%/Contents/Developer}
  ok Xcode "${app##*/} selected"

  absent=()
  for platform in iOS watchOS; do
    has_runtime "$platform" || absent+=("$platform")
  done
  if ((${#absent[@]} == 0)); then
    ok runtimes 'iOS and watchOS simulators present'
  else
    fail runtimes "no ${absent[*]} simulator -- SweetPad lists no destination. Run: dot apply"
  fi
else
  fail Xcode "no working Xcode is selected (xcode-select -p: ${developer:-nothing}) -- nothing can build an app"
  dim 'install it (Apple ID, 10+ GB): xcodes install --latest --select --experimental-unxip'
  dim runtimes 'checked once Xcode is selected'
fi

have=$(installed_extensions) || have=''
missing=()
while IFS= read -r id; do
  if [[ -z $id || $id == '#'* ]]; then continue; fi
  grep -qxF "${id,,}" <<<"$have" || missing+=("$id")
done <"$extensions"

if ((${#missing[@]} == 0)); then
  ok extensions 'SweetPad and Swift installed in VS Code'
else
  fail extensions "not in VS Code: ${missing[*]} -- run: dot apply"
fi

claude=${DOT_CLAUDE_BIN:-claude}
have=$(installed_plugins) || have=''
names=() missing=()
while IFS= read -r id; do
  if [[ -z $id || $id == '#'* ]]; then continue; fi
  names+=("${id%@*}")
  grep -qxF "$id" <<<"$have" || missing+=("$id")
done <"$plugins"

if ((${#missing[@]} == 0)); then
  ok plugins "${names[*]} installed in Claude Code"
elif ! command -v "$claude" >/dev/null 2>&1; then
  dim plugins 'checked once the claude CLI is installed'
else
  fail plugins "not in Claude Code: ${missing[*]} -- run: dot apply"
fi
