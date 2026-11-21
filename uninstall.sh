#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 5)); then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
  fi
  echo "uninstall.sh needs bash 5 or newer; this is $BASH_VERSION." >&2
  exit 1
fi

set -euo pipefail

# shellcheck source=lib/dot.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/dot.sh"

__DOT_EXIT_WARN=0

BREW_UNINSTALL='https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh'

while (($#)); do
  case $1 in
    --dry-run) DOT_DRY_RUN=1 ;;
    *) die "unknown option '$1'" next 'bash uninstall.sh [--dry-run]' ;;
  esac
  shift
done
export DOT_DRY_RUN

[[ $(uname -s) == Darwin ]] || die 'This is macOS only.'
(($(id -u) != 0)) || die 'Do not run this as root.'

if [[ $DOT_DRY_RUN != 1 ]]; then
  [[ -t 0 ]] ||
    die 'Refusing to run unattended' next 'bash uninstall.sh --dry-run'

  "$BASH" "$0" --dry-run || die 'The preview failed; nothing was changed.'

  heading 'Confirm' 'there is no undo'
  say 'Everything listed above will be removed.'
  printf '\n  Type %sremove%s to continue: ' "$__C_BOLD" "$__C_RESET"
  read -r answer || answer=''
  [[ $answer == remove ]] || die 'Nothing was changed.'
fi

heading 'Modules' 'every one, enabled or not'
while IFS= read -r name; do
  [[ -f "$(modules_dir "$name")/remove.sh" ]] || continue
  step '' '' "$name" "$(module_desc "$name")"
  ui_nest
  module_remove "$name"
  ui_unnest
done < <(modules_all)

heading 'Links'
mapfile -t links < <(fs_repo_links)
if ((${#links[@]})); then
  for link in "${links[@]}"; do
    fs_unlink "$link"
  done
else
  say links 'none found'
fi

heading 'CLI'
shim="$HOME/.local/bin/dot"
if [[ -f $shim ]]; then
  if grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
    fs_discard "$shim"
  else
    warn 'left alone' "points at a different checkout: ${shim/#$HOME/\~}"
  fi
else
  say dot 'not installed'
fi

heading 'Config'
if [[ -f $DOT_CONFIG ]]; then
  fs_discard "$DOT_CONFIG"
  [[ $DOT_DRY_RUN == 1 ]] || rmdir "$(dirname "$DOT_CONFIG")" 2>/dev/null || true
else
  say config 'none found'
fi

heading 'Logs'
if [[ -n $(find "$DOT_STATE/logs" -mindepth 1 -name '*.log' -print -quit 2>/dev/null) ]]; then
  while IFS= read -r logfile; do
    fs_discard "$logfile"
  done < <(find "$DOT_STATE/logs" -maxdepth 1 -type f -name '*.log' | sort)
  [[ $DOT_DRY_RUN == 1 ]] || rmdir "$DOT_STATE/logs" 2>/dev/null || true
else
  say logs 'none found'
fi

heading 'Backups'
if [[ -n $(find "$DOT_STATE/backups" -mindepth 1 -print -quit 2>/dev/null) ]]; then
  warn 'kept' "${DOT_STATE/#$HOME/\~}/backups"
  dim 'Your own files, moved aside by an earlier apply. Nothing else has a copy.'
  dim 'Delete them yourself once you have looked.'
else
  say backups 'none to keep'
  if [[ -d $DOT_STATE ]]; then
    if [[ -n $(find "$DOT_STATE" -mindepth 1 -not -path "$DOT_STATE/backups" -not -path "$DOT_STATE/logs*" -print -quit 2>/dev/null) ]]; then
      warn 'left alone' "${DOT_STATE/#$HOME/\~} holds files this repo did not create"
    else
      info 'remove' "${DOT_STATE/#$HOME/\~}"
      [[ $DOT_DRY_RUN == 1 ]] || rmdir "$DOT_STATE/backups" "$DOT_STATE" 2>/dev/null || true
    fi
  fi
fi

heading 'Applications'

have_brew=0
# Without shellenv a bare `brew` lists no casks, and the run would then destroy
# Homebrew with every cask's .app stranded in /Applications.
if brew_load; then
  have_brew=1
elif [[ -d /opt/homebrew || -d /usr/local/Homebrew ]]; then
  fail homebrew 'looks installed but could not be loaded -- refusing to guess what it owns'
fi

remove_applications() {
  local cask
  local -a casks

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info services 'stop --all'
  else
    brew services stop --all >/dev/null 2>&1 || true
  fi

  mapfile -t casks < <(brew list --cask 2>/dev/null)
  if ((${#casks[@]} == 0)); then
    say casks 'none installed'
  elif [[ $DOT_DRY_RUN == 1 ]]; then
    for cask in "${casks[@]}"; do
      info 'uninstall' "$cask"
    done
    dim '--zap as well: application support, preferences and caches go too'
  elif brew uninstall --cask --zap --force "${casks[@]}"; then
    ok casks "removed $(ui_count "${#casks[@]}" application)"
  else
    while IFS= read -r cask; do
      fail casks "could not remove $cask -- remove it by hand, then re-run"
    done < <(brew list --cask 2>/dev/null)
  fi
}

if ((have_brew)); then
  remove_applications
else
  say casks 'Homebrew is not installed; nothing to remove'
fi

brew_headcount() {
  local installed repo bundle rc=0
  command -v brew >/dev/null 2>&1 || return 1

  installed=$(mktemp) repo=$(mktemp) bundle=$(mktemp)

  {
    brew list --formula 2>/dev/null | sort -u >"$installed" &&
      { cat "$DOT_ROOT"/core/Brewfile "$DOT_ROOT"/modules/*/Brewfile 2>/dev/null >"$bundle" || true; } &&
      brew bundle list --file "$bundle" 2>/dev/null | sort -u >"$repo"
  } || rc=1

  if ((rc == 0)); then
    printf '%s %s\n' \
      "$(wc -l <"$installed" | tr -d ' ')" \
      "$(comm -23 "$installed" "$repo" | wc -l | tr -d ' ')"
  fi

  rm -f "$installed" "$repo" "$bundle"
  return $rc
}

heading 'Homebrew and the repo'

if ((DOT_FAILURES > 0)); then
  die "$(ui_count "$DOT_FAILURES" problem) above -- stopping before Homebrew and the repo"
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  # `== 0`, not `!`: shfmt 3.13 and 3.14 format `(( ! x ))` in opposite ways.
  if ((have_brew == 0)); then
    dim 'Homebrew is not installed; nothing to uninstall.'
  elif read -r n_all n_foreign < <(brew_headcount); then
    info "uninstall Homebrew and all $n_all formulae it manages"
    ((n_foreign == 0)) ||
      warn "$n_foreign of those are named by no Brewfile here -- they go too"
  else
    info 'uninstall Homebrew and every package it manages'
  fi
  info 'remove' "$DOT_ROOT"
  heading 'Dry run'
  dim 'Nothing was changed.'
  exit 0
fi

# The last steps remove Homebrew, which owns this bash, and the repo, which
# holds this file, so they run from a throwaway script under /bin/bash.
handoff=$(mktemp -t dotfiles-uninstall)
cat >"$handoff" <<EOF
#!/bin/bash
set -u
EOF

if ((have_brew)); then
  cat >>"$handoff" <<EOF
echo
echo "==> Uninstalling Homebrew (it will ask for your password)"
# NONINTERACTIVE=1 implies --force: you already typed 'remove' once.
NONINTERACTIVE=1 /bin/bash -c "\$(curl -fsSL $BREW_UNINSTALL)"
EOF
fi

cat >>"$handoff" <<EOF
echo
echo "==> Removing $DOT_ROOT"
rm -rf "$DOT_ROOT"
echo
echo "==> Done."
echo "    Xcode Command Line Tools were left installed, on purpose."
echo "    Open a new terminal: this one still has the old PATH."
rm -f "\$0"
EOF

exec /bin/bash "$handoff"
