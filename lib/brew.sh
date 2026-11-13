# shellcheck shell=bash

brew_load() {
  command -v brew >/dev/null 2>&1 && return 0
  local brew_bin=${DOT_BREW_BIN:-/opt/homebrew/bin/brew}
  if [[ -x $brew_bin ]]; then
    eval "$("$brew_bin" shellenv)"
    return 0
  fi
  return 1
}

# 0 satisfied, 1 missing, 2 could not check -- never read 2 as installed.
brew_missing() {
  local file=$1 out status=0
  [[ -f $file ]] || return 0
  command -v brew >/dev/null 2>&1 || return 2

  out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" --no-upgrade --verbose 2>&1) ||
    status=1
  ((status)) || return 0

  # Not the leading arrow: a multibyte glyph matches nothing under a C locale.
  out=$(sed -n -E 's/^.*(Formula|Cask) ([^ ]+) needs to be installed\.$/\1 \2/p' <<<"$out")
  [[ -n $out ]] || return 2
  printf '%s\n' "$out"
  return 1
}

brew_bundle() {
  local file=$1
  local label=${2:-$(basename "$(dirname "$file")")}
  [[ -f $file ]] || return 0

  if ! brew_load; then
    fail packages "Homebrew is not installed -- cannot install for $label"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info packages "brew bundle --file ${file#"$DOT_ROOT"/}"
    return 0
  fi

  brew bundle --file "$file" --no-upgrade 2>&1 | ui_quote
  if ((PIPESTATUS[0] == 0)); then return 0; fi

  fail packages "brew bundle failed for $label"

  local missing status=0
  missing=$(brew_missing "$file") || status=$?
  case $status in
    1)
      while IFS= read -r line; do dim 'still missing' "$line"; done <<<"$missing"
      if grep -q '^Cask ' <<<"$missing"; then
        dim 'a cask already in /Applications by hand: brew install --cask --adopt <name>'
      fi
      ;;
    2) dim 'brew could not say what is missing -- see its output above' ;;
  esac
  return 1
}

brew_check() {
  local file=$1
  local label=${2:-$(basename "$(dirname "$file")")}
  local missing status=0

  [[ -f $file ]] || return 0
  if ! brew_load; then
    fail packages "Homebrew is not installed -- cannot check $label"
    return 1
  fi

  missing=$(brew_missing "$file") || status=$?
  case $status in
    0) ok packages 'all installed' ;;
    1) while IFS= read -r line; do
      fail packages "$line is not installed -- run: dot apply"
    done <<<"$missing" ;;
    2) warn packages 'could not be checked -- brew bundle check did not answer' ;;
  esac
}

brew_unmanaged() {
  command -v brew >/dev/null 2>&1 || return 2

  # Two lists, never one: `brew "docker"` must not vouch for a hand-installed
  # `cask "docker"`.
  local files named_brew named_cask formulae casks out
  files=$(cat "$DOT_ROOT/core/Brewfile" "$DOT_ROOT"/modules/*/Brewfile 2>/dev/null)
  named_brew=$(sed -n -E 's/^brew "([^"]*\/)?([^"]+)".*/\2/p' <<<"$files" | LC_ALL=C sort -u)
  named_cask=$(sed -n -E 's/^cask "([^"]*\/)?([^"]+)".*/\2/p' <<<"$files" | LC_ALL=C sort -u)

  [[ -n $named_brew || -n $named_cask ]] || return 2

  formulae=$(HOMEBREW_NO_AUTO_UPDATE=1 brew leaves --installed-on-request 2>/dev/null) || return 2
  casks=$(HOMEBREW_NO_AUTO_UPDATE=1 brew list --cask 2>/dev/null) || return 2

  out=$(
    comm -23 <(LC_ALL=C sort -u <<<"$formulae") <(printf '%s\n' "$named_brew") |
      awk 'NF {print "Formula", $0}'
    comm -23 <(LC_ALL=C sort -u <<<"$casks") <(printf '%s\n' "$named_cask") |
      awk 'NF {print "Cask", $0}'
  )

  [[ -n $out ]] || return 0
  printf '%s\n' "$out"
  return 1
}
