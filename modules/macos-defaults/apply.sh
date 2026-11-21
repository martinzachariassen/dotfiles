#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

relogin='log out and back in for keyboard and text-substitution changes to fully apply'

pending=()
total=0
want() {
  local domain=$1 key=$2 type=$3 value=$4 expect=$4 got
  case "$type:$value" in
    bool:true) expect=1 ;;
    bool:false) expect=0 ;;
  esac
  total=$((total + 1))
  got=$(defaults read "$domain" "$key" 2>/dev/null) || got=''
  if [[ $got != "$expect" ]]; then pending+=("$domain"$'\t'"$key"$'\t'"$type"$'\t'"$value"); fi
}

while IFS=$'\t' read -r domain key type value _; do
  if [[ -z $domain || $domain == '#'* ]]; then continue; fi
  want "$domain" "$key" "$type" "$value"
done <"$data"

dock_autohide=false
if module_setting_bool macos-defaults dock_autohide true; then dock_autohide=true; fi
want com.apple.dock autohide bool "$dock_autohide"

tilesize=$(module_setting macos-defaults dock_tilesize 48)
# `defaults -int` stores non-numeric as 0, and tilesize 0 is a Dock with no icons.
if [[ $tilesize =~ ^[0-9]+$ ]] && ((tilesize > 0)); then
  want com.apple.dock tilesize int "$tilesize"
else
  fail defaults "dock_tilesize '$tilesize' is not a positive number -- left as it was"
fi

screenshot_dir=$(module_setting macos-defaults screenshot_dir 'Pictures/Screenshots')
screenshot_dir=${screenshot_dir/#\~\//$HOME/}
[[ $screenshot_dir == /* ]] || screenshot_dir="$HOME/$screenshot_dir"
want com.apple.screencapture location string "$screenshot_dir"
if [[ $DOT_DRY_RUN != 1 ]]; then mkdir -p "$screenshot_dir"; fi

if ((${#pending[@]} == 0)); then
  if ((DOT_FAILURES == 0)); then ok defaults "$(ui_count "$total" key) already set"; fi
  exit 0
fi

declare -A restart=() domains=()
keys=() global=0
for row in "${pending[@]}"; do
  IFS=$'\t' read -r domain key _ _ <<<"$row"
  keys+=("$key")
  domains[$domain]=1
  case $domain in
    com.apple.dock) restart[Dock]=1 ;;
    com.apple.finder) restart[Finder]=1 ;;
    com.apple.screencapture) restart[SystemUIServer]=1 ;;
    com.apple.WindowManager) restart[WindowManager]=1 ;;
    NSGlobalDomain) global=1 ;;
  esac
done

if ((${#keys[@]} <= 3)); then
  info defaults "write $(printf '%s, ' "${keys[@]}" | sed 's/, $//')"
else
  info defaults "write $(ui_count "${#keys[@]}" key) across $(ui_count "${#domains[@]}" domain)"
fi
if ((${#restart[@]})); then
  info restart "$(printf '%s\n' "${!restart[@]}" | sort | paste -sd ' ' -)"
fi

if [[ $DOT_DRY_RUN != 1 ]]; then
  for row in "${pending[@]}"; do
    IFS=$'\t' read -r domain key type value <<<"$row"
    defaults write "$domain" "$key" "-$type" "$value"
  done
  for app in "${!restart[@]}"; do
    killall "$app" >/dev/null 2>&1 || true
  done
  if ((DOT_FAILURES == 0)); then ok defaults 'written'; fi
fi

if ((global)); then dim "$relogin"; fi
