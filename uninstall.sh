#!/usr/bin/env bash
#
# Phase 0 in reverse. Not `dot uninstall`, even though `dot remove` exists: that
# one undoes a module and is reversible by `dot add`. This is not reversible by
# anything, and the most destructive thing here must not sit behind the command
# typed every day.
#
#   bash uninstall.sh --dry-run    print every intended change, make none
#   bash uninstall.sh              do it
#
# Left alone on purpose: Xcode CLT, the backup tree under $DOT_STATE, real
# files in $HOME, and macOS defaults (see modules/macos-defaults/remove.sh).

# One of five places that must agree on bash 5 (install.sh, core/Brewfile,
# bin/dot, lib/dot.sh). Re-exec rather than refuse: the shell that reaches for
# the uninstaller is the least likely to have sourced Homebrew's shellenv.
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

# Top level, not a hook: a kept backup tree must not turn into a non-zero exit.
__DOT_EXIT_WARN=0

BREW_UNINSTALL='https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh'

while (($#)); do
  case $1 in
    --dry-run) DOT_DRY_RUN=1 ;;
    *) die "unknown option '$1'. Try: bash uninstall.sh [--dry-run]" ;;
  esac
  shift
done
export DOT_DRY_RUN

[[ $(uname -s) == Darwin ]] || die 'This is macOS only.'
(($(id -u) != 0)) || die 'Do not run this as root.'

# --- Confirmation ------------------------------------------------------------
# The preview is this script under --dry-run, not a hand-written summary that
# could drift from it.
if [[ $DOT_DRY_RUN != 1 ]]; then
  [[ -t 0 ]] ||
    die 'Refusing to run unattended. Use --dry-run to see the plan.'

  "$BASH" "$0" --dry-run || die 'The preview failed; nothing was changed.'

  heading 'Confirm'
  say 'Everything listed above will be removed, and there is no undo.'
  printf '  Type %sremove%s to continue: ' "$__C_BOLD" "$__C_RESET"
  read -r answer || answer=''
  [[ $answer == remove ]] || die 'Nothing was changed.'
fi

# --- Modules ------------------------------------------------------------------
# Every module, enabled or not: a module switched off last month still left
# its files behind.
while IFS= read -r name; do
  [[ -f "$(modules_dir "$name")/remove.sh" ]] || continue
  heading "Module: $name"
  module_remove "$name"
done < <(modules_all)

# --- Links ---------------------------------------------------------------------
# The orphan scan with nothing enabled: every link into the repo is unclaimed.
heading 'Links'
mapfile -t links < <(fs_repo_links)
if ((${#links[@]})); then
  for link in "${links[@]}"; do
    fs_unlink "$link"
  done
else
  say 'None found.'
fi

# --- The CLI shim ---------------------------------------------------------------
# Generated, not linked, so the sweep cannot see it. The baked-in DOT_ROOT line
# is the proof of ownership; core/doctor.sh greps the same line. -f, not -x: a
# shim that lost its executable bit is still ours to remove.
heading 'CLI'
shim="$HOME/.local/bin/dot"
if [[ -f $shim ]]; then
  if grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
    fs_discard "$shim"
  else
    warn 'left alone  ~/.local/bin/dot points at a different checkout'
  fi
else
  say 'Not installed.'
fi

# --- Config ----------------------------------------------------------------------
heading 'Config'
if [[ -f $DOT_CONFIG ]]; then
  fs_discard "$DOT_CONFIG"
  # rmdir: the directory goes only if our config was the single thing in it.
  [[ $DOT_DRY_RUN == 1 ]] || rmdir "$(dirname "$DOT_CONFIG")" 2>/dev/null || true
else
  say 'None found.'
fi

# --- Logs -------------------------------------------------------------------------
# Before Backups, which removes $DOT_STATE itself and refuses while anything
# unexpected is still inside it.
heading 'Logs'
if [[ -n $(find "$DOT_STATE/logs" -mindepth 1 -name '*.log' -print -quit 2>/dev/null) ]]; then
  while IFS= read -r logfile; do
    fs_discard "$logfile"
  done < <(find "$DOT_STATE/logs" -maxdepth 1 -type f -name '*.log' | sort)
  [[ $DOT_DRY_RUN == 1 ]] || rmdir "$DOT_STATE/logs" 2>/dev/null || true
else
  say 'None found.'
fi

# --- Backups -----------------------------------------------------------------------
heading 'Backups'
if [[ -n $(find "$DOT_STATE/backups" -mindepth 1 -print -quit 2>/dev/null) ]]; then
  # A warning about something KEPT: the only copy of your replaced files.
  warn "kept  ${DOT_STATE/#$HOME/\~}/backups"
  dim 'Your own files, moved aside by an earlier apply. Nothing else has a copy.'
  dim 'Delete them yourself once you have looked.'
else
  say 'None to keep.'
  # rmdir, never rm -rf: a file nothing in this repo created keeps the
  # directory alive. Tested up front so a dry run prints the real run's words;
  # logs/ is excluded because a dry run has not removed it yet.
  if [[ -d $DOT_STATE ]]; then
    if [[ -n $(find "$DOT_STATE" -mindepth 1 -not -path "$DOT_STATE/backups" -not -path "$DOT_STATE/logs*" -print -quit 2>/dev/null) ]]; then
      warn "left alone  ${DOT_STATE/#$HOME/\~} holds files this repo did not create"
    else
      info "remove  ${DOT_STATE/#$HOME/\~}"
      [[ $DOT_DRY_RUN == 1 ]] || rmdir "$DOT_STATE/backups" "$DOT_STATE" 2>/dev/null || true
    fi
  fi
fi

# --- Applications ---------------------------------------------------------------
# Homebrew MOVES a cask's .app into /Applications, and its own uninstaller
# deletes only the prefix -- so casks must go by name while brew still works,
# or every GUI app is stranded with no tool left to remove it. Same for
# `brew services` and its launchd plists.
heading 'Applications'

# brew_load first. Run from a shell that never sourced shellenv, a bare `brew`
# once listed no casks and the run destroyed Homebrew regardless. `fail`, not
# `die`: it flows into the guard before the handoff like every other problem.
have_brew=0
if brew_load; then
  have_brew=1
elif [[ -d /opt/homebrew || -d /usr/local/Homebrew ]]; then
  fail 'Homebrew looks installed but could not be loaded -- refusing to guess what it owns'
fi

remove_applications() {
  local cask
  local -a casks

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info 'brew services stop --all'
  else
    brew services stop --all >/dev/null 2>&1 || true
  fi

  mapfile -t casks < <(brew list --cask 2>/dev/null)
  if ((${#casks[@]} == 0)); then
    say 'No applications installed.'
  elif [[ $DOT_DRY_RUN == 1 ]]; then
    for cask in "${casks[@]}"; do
      info "uninstall  $cask"
    done
    dim '--zap as well: application support, preferences and caches go too'
  elif brew uninstall --cask --zap --force "${casks[@]}"; then
    ok "removed ${#casks[@]} application(s)"
  else
    # `fail` so the guard below stops the run before Homebrew goes.
    while IFS= read -r cask; do
      fail "could not remove $cask -- remove it by hand, then re-run"
    done < <(brew list --cask 2>/dev/null)
  fi
}

if ((have_brew)); then
  remove_applications
else
  say 'Homebrew is not installed; nothing to remove.'
fi

# brew_headcount -- "<formulae installed> <formulae no Brewfile here names>".
# A count, because "every package it installed" reads as "this repo's
# packages" and the truth is every package on the machine. Formulae only: the
# casks were itemised above.
brew_headcount() {
  local installed repo bundle rc=0
  command -v brew >/dev/null 2>&1 || return 1

  installed=$(mktemp) repo=$(mktemp) bundle=$(mktemp)

  # Grouped so a failing step cannot skip the cleanup below.
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

# --- Handoff --------------------------------------------------------------------------
heading 'Homebrew and the repo'

# Everything above, `dot apply` can put back; nothing below can be.
if ((DOT_FAILURES > 0)); then
  die "$DOT_FAILURES problem(s) above -- stopping before Homebrew and the repo."
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  if ((! have_brew)); then
    dim 'Homebrew is not installed; nothing to uninstall.'
  elif read -r n_all n_foreign < <(brew_headcount); then
    info "uninstall Homebrew and all $n_all formulae it manages"
    ((n_foreign == 0)) ||
      warn "$n_foreign of those are named by no Brewfile here -- they go too"
  else
    info 'uninstall Homebrew and every package it manages'
  fi
  info "remove  $DOT_ROOT"
  heading 'Dry run'
  dim 'Nothing was changed.'
  exit 0
fi

# The last two steps remove Homebrew (which owns this bash) and $DOT_ROOT
# (which holds this file), so they run from a throwaway script under
# /bin/bash -- the one shell still there once Homebrew is gone.
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
