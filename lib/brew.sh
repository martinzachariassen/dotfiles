# shellcheck shell=bash
#
# Homebrew. Thin on purpose: `brew bundle` is already idempotent.

# The fallback path is an INPUT, like DOT_CODE_BIN in modules/git: without one,
# "Homebrew could not be loaded" is unreachable on any machine that has it, and
# that is the branch where containers/remove.sh decides it cannot prove a link
# is ours. install.sh hardcodes the same path on purpose -- it shares nothing.
brew_load() {
  command -v brew >/dev/null 2>&1 && return 0
  local brew_bin=${DOT_BREW_BIN:-/opt/homebrew/bin/brew}
  if [[ -x $brew_bin ]]; then
    eval "$("$brew_bin" shellenv)"
    return 0
  fi
  return 1
}

# brew_missing FILE -- "<Formula|Cask> <name>" per package FILE names that is
# not installed. Returns 0 satisfied, 1 something is missing, 2 the check
# itself could not run (no brew, unreadable Brewfile, a failed tap fetch).
#
# 2 is distinct on purpose: a check that could not run must never read as "all
# installed". `brew bundle check` rather than parsing the Brewfile here -- it
# is the only reader that agrees with `brew bundle` about what installed means.
# HOMEBREW_NO_AUTO_UPDATE because a check may not mutate the machine.
brew_missing() {
  local file=$1 out status=0
  [[ -f $file ]] || return 0
  command -v brew >/dev/null 2>&1 || return 2

  out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" --no-upgrade --verbose 2>&1) ||
    status=1
  ((status)) || return 0

  # Matched without the leading arrow: it is a multibyte glyph, and a C locale
  # would make this silently match nothing.
  out=$(sed -n -E 's/^.*(Formula|Cask) ([^ ]+) needs to be installed\.$/\1 \2/p' <<<"$out")
  [[ -n $out ]] || return 2
  printf '%s\n' "$out"
  return 1
}

# brew_bundle FILE [LABEL] -- a missing Brewfile is success: modules need none.
brew_bundle() {
  local file=$1
  local label=${2:-$(basename "$(dirname "$file")")}
  [[ -f $file ]] || return 0

  if ! brew_load; then
    fail "Homebrew is not installed; cannot install packages for $label"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info "brew bundle --file ${file#"$DOT_ROOT"/}"
    return 0
  fi

  # --no-upgrade: apply installs what is missing; upgrading is `brew upgrade`.
  brew bundle --file "$file" --no-upgrade && return 0

  fail "brew bundle failed for $label"

  # brew's own output is hundreds of lines above by now, and "failed" alone is
  # not something a user can act on. Name the packages that are still absent.
  local missing status=0
  missing=$(brew_missing "$file") || status=$?
  case $status in
    1)
      while IFS= read -r line; do dim "still missing: $line"; done <<<"$missing"
      if grep -q '^Cask ' <<<"$missing"; then
        dim 'a cask already in /Applications by hand: brew install --cask --adopt <name>'
      fi
      ;;
    2) dim 'brew could not say what is missing -- see its output above' ;;
  esac
  return 1
}

# brew_check FILE [LABEL] -- doctor's read-only counterpart to brew_bundle. A
# module whose packages half-installed used to report green, because doctor
# never looked at anything but symlinks.
brew_check() {
  local file=$1
  local label=${2:-$(basename "$(dirname "$file")")}
  local missing status=0

  [[ -f $file ]] || return 0
  if ! brew_load; then
    fail "packages     Homebrew is not installed; cannot check $label"
    return 1
  fi

  missing=$(brew_missing "$file") || status=$?
  case $status in
    0) ok 'packages     all installed' ;;
    1) while IFS= read -r line; do
      fail "packages     $line is not installed -- run: dot apply"
    done <<<"$missing" ;;
    2) warn 'packages     could not be checked -- brew bundle check did not answer' ;;
  esac
}
