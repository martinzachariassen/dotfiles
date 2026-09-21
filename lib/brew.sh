# shellcheck shell=bash
#
# Homebrew. Thin on purpose: `brew bundle` is already idempotent.

# The fallback path is an input, so "Homebrew could not be loaded" is reachable
# on a machine that has it. install.sh keeps its own copy and its own name for
# it: it shares nothing, including this.
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
# not installed. Returns 0 satisfied, 1 missing, 2 the check could not run.
#
# 2 is distinct on purpose: a check that could not run must never read as "all
# installed". `brew bundle check` rather than parsing the Brewfile here -- it
# is the only reader that agrees with `brew bundle` about what installed means.
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
    fail packages "Homebrew is not installed -- cannot install for $label"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info packages "brew bundle --file ${file#"$DOT_ROOT"/}"
    return 0
  fi

  # --no-upgrade: apply installs what is missing; upgrading is `brew upgrade`.
  # Quoted, so brew's hundreds of lines stay visible as they stream but at the
  # weight of a footnote. The status comes back through PIPESTATUS.
  brew bundle --file "$file" --no-upgrade 2>&1 | ui_quote
  if ((PIPESTATUS[0] == 0)); then return 0; fi

  fail packages "brew bundle failed for $label"

  # brew's own output is hundreds of lines above by now, and "failed" alone is
  # not something a user can act on. Name the packages that are still absent.
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

# brew_check FILE [LABEL] -- doctor's read-only counterpart to brew_bundle.
# Without it a half-installed module reports green: doctor would be looking at
# nothing but symlinks.
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

# brew_unmanaged -- "<Formula|Cask> <name>" per package this machine has that
# no Brewfile in the repo names, with the same three answers as brew_missing.
# The one check that looks the other way: what would the NEXT machine not get?
# See docs/architecture.md.
#
# EVERY Brewfile, not just the enabled ones: `dot add work-apps` still brings
# back what a disabled module names, so listing those would make a machine with
# one module switched off report that module's whole Brewfile.
#
# `leaves --installed-on-request` is what "by hand" means to brew: it drops
# dependencies, so a tool is named and its tree is not.
brew_unmanaged() {
  command -v brew >/dev/null 2>&1 || return 2

  # LC_ALL=C throughout: comm compares bytes, and a sort that collated `-` or
  # `@` by locale rules instead would make it disagree with its own input.
  #
  # Two lists, and never one. `brew "docker"` and `cask "docker"` are different
  # packages that happen to share a word, so a single set would let a Brewfile
  # naming either of them vouch for a hand-installed other.
  local files named_brew named_cask formulae casks out
  files=$(cat "$DOT_ROOT/core/Brewfile" "$DOT_ROOT"/modules/*/Brewfile 2>/dev/null)
  named_brew=$(sed -n -E 's/^brew "([^"]*\/)?([^"]+)".*/\2/p' <<<"$files" | LC_ALL=C sort -u)
  named_cask=$(sed -n -E 's/^cask "([^"]*\/)?([^"]+)".*/\2/p' <<<"$files" | LC_ALL=C sort -u)

  # No Brewfile read at all would make every package on the machine unmanaged.
  # That is a broken checkout, not a finding.
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
