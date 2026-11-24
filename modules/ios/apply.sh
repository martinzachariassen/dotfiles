#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

extensions="${DOT_MODULE_DIR:-$(dirname "$0")}/data/vscode-extensions"
coresim=${DOT_CORESIM_ROOT:-/Library/Developer/CoreSimulator}
# Xcode 27 mounts runtimes as cryptexes under /var/run, gone until CoreSimulator mounts them; its binary plist registry persists.
has_runtime() { compgen -G "$coresim/Volumes/*/Library/Developer/CoreSimulator/Profiles/Runtimes/$1 *.simruntime" >/dev/null || compgen -G "$coresim/Profiles/Runtimes/$1 *.simruntime" >/dev/null || grep -aqE "com\.apple\.CoreSimulator\.SimRuntime\.$1-[0-9]" "$coresim/Images/images.plist" 2>/dev/null; }
installed_extensions() { jq -r '.[].identifier.id // empty' "$HOME/.vscode/extensions/extensions.json" 2>/dev/null | tr '[:upper:]' '[:lower:]'; }
plugins="${DOT_MODULE_DIR:-$(dirname "$0")}/data/claude-plugins"
installed_plugins() { jq -r '.plugins // {} | to_entries[] | select(any(.value[]?; .scope == "user")) | .key' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; }

have=$(installed_extensions) || have=''
wanted=0 missing=()
while IFS= read -r id; do
  if [[ -z $id || $id == '#'* ]]; then continue; fi
  wanted=$((wanted + 1))
  grep -qxF "${id,,}" <<<"$have" || missing+=("$id")
done <"$extensions"

if ((${#missing[@]} == 0)); then
  ok extensions "$(ui_count "$wanted" 'VS Code extension') installed"
elif [[ $DOT_DRY_RUN != 1 ]] && ! command -v code >/dev/null 2>&1; then
  fail extensions 'the code CLI is missing -- the visual-studio-code cask did not install. Run: dot apply'
else
  for id in "${missing[@]}"; do
    info extension "$id"
    if [[ $DOT_DRY_RUN == 1 ]]; then continue; fi
    began=$(ui_now)
    # VS Code's Electron ignores NODE_OPTIONS when another program starts it, so Node's warnings are dropped here.
    if code --install-extension "$id" 2>&1 |
      awk '/^\(node:[0-9]+\) |--trace-deprecation|^Installing extensions?|successfully installed/ { next } { print; fflush() }' |
      ui_quote; then
      ok installed "extension $id"$'\t'"$(ui_duration $(($(ui_now) - began)))"
    else
      fail extension "$id did not install -- try: code --install-extension $id"
    fi
  done
fi

claude=${DOT_CLAUDE_BIN:-claude}
have=$(installed_plugins) || have=''
wanted=0 missing=()
while IFS= read -r id; do
  if [[ -z $id || $id == '#'* ]]; then continue; fi
  wanted=$((wanted + 1))
  grep -qxF "$id" <<<"$have" || missing+=("$id")
done <"$plugins"

if ((${#missing[@]} == 0)); then
  ok plugins "$(ui_count "$wanted" 'Claude Code plugin') installed"
elif ! command -v "$claude" >/dev/null 2>&1; then
  dim plugins "${missing[*]} waits for the claude CLI (the claude-code module)"
else
  for id in "${missing[@]}"; do
    info plugin "$id"
    if [[ $DOT_DRY_RUN == 1 ]]; then continue; fi
    began=$(ui_now)
    if "$claude" plugin install "$id" --scope user 2>&1 |
      awk '/[Ii]nstall(ed|ing) plugin/ { next } { print; fflush() }' |
      ui_quote; then
      ok installed "plugin $id"$'\t'"$(ui_duration $(($(ui_now) - began)))"
    else
      fail plugin "$id did not install -- try: claude plugin install $id"
    fi
  done
fi

xcode_select=${DOT_XCODE_SELECT:-/usr/bin/xcode-select}
developer=$("$xcode_select" -p 2>/dev/null) || developer=''
xcode_ready() { [[ $developer == *.app/Contents/Developer && -x $developer/usr/bin/xcodebuild ]]; }
if ! xcode_ready; then
  warn Xcode 'not selected -- simulator runtimes wait for it'
  dim 'install it (Apple ID, 10+ GB): xcodes install --latest --select --experimental-unxip'
  dim 'then run: dot apply'
  exit 0
fi

absent=()
for platform in iOS watchOS; do
  has_runtime "$platform" || absent+=("$platform")
done
if ((${#absent[@]} == 0)); then
  ok runtimes 'iOS and watchOS simulators present'
  exit 0
fi

for platform in "${absent[@]}"; do
  info runtime "$platform simulator (several GB)"
  if [[ $DOT_DRY_RUN == 1 ]]; then continue; fi
  # Progress arrives as \r-separated percentages; quoting each would flood the run.
  if "$developer/usr/bin/xcodebuild" -downloadPlatform "$platform" 2>&1 | tr '\r' '\n' | awk '!/[0-9]%/ { print; fflush() }' | ui_quote; then
    ok runtime "$platform simulator installed"
  else
    fail runtime "$platform did not download -- try: xcodebuild -downloadPlatform $platform"
  fi
done
