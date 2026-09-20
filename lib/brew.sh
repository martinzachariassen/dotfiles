# shellcheck shell=bash
#
# Homebrew. Thin on purpose: `brew bundle` is already idempotent.

# The fallback path is an INPUT, like DOT_CODE_BIN in modules/git: without one,
# "Homebrew could not be loaded" is unreachable on any machine that has it --
# the branch where containers/remove.sh cannot prove a link is ours. install.sh
# keeps its own copy and its own name for it: it shares nothing, including this.
brew_load() {
  command -v brew >/dev/null 2>&1 && return 0
  local brew_bin=${DOT_BREW_BIN:-/opt/homebrew/bin/brew}
  if [[ -x $brew_bin ]]; then
    eval "$("$brew_bin" shellenv)"
    return 0
  fi
  return 1
}

# brew_missing FILE -- "<Formula|Cask> <name>" per package FILE names that is not
# installed. Returns 0 satisfied, 1 missing, 2 the check itself could not run.
#
# 2 is distinct on purpose: a check that could not run must never read as "all
# installed". `brew bundle check` rather than parsing the Brewfile here -- it is
# the only reader that agrees with `brew bundle` about what installed means.
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
    fail packages "Homebrew is not installed -- cannot install for $label"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info packages "brew bundle --file ${file#"$DOT_ROOT"/}"
    return 0
  fi

  # --no-upgrade: apply installs what is missing; upgrading is `brew upgrade`.
  # Quoted, not raw: brew's own hundreds of lines stay visible as they stream,
  # but at the weight of a footnote. The status comes back through PIPESTATUS.
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

# brew_unmanaged -- "<Formula|Cask> <name>" per package this machine has that no
# Brewfile in the repo names. The same three answers as brew_missing, and 2 is
# distinct for the same reason: a check that could not run must never read as
# "everything is accounted for".
#
# Every check above this one asks whether the repo made it onto the machine.
# This is the only one that looks the other way, and it answers a different
# question: what would the NEXT machine not get? A tool installed in week one
# and never written down is invisible until the rebuild that does not have it.
#
# EVERY Brewfile, not just the enabled ones. `dot add work-apps` still brings
# back what a disabled module names, so that package is not lost and listing it
# would mean a machine with one module switched off reports its whole Brewfile
# here. Only what no module at all names is a package that exists nowhere but
# on this disk.
#
# `leaves --installed-on-request` is what "by hand" means to brew: it drops
# dependencies, so a tool is named and its tree is not. A formula that LATER
# becomes something else's dependency falls out of that list -- brew leaves'
# own blind spot, and the price of not reading the install receipt of every keg.
brew_unmanaged() {
  command -v brew >/dev/null 2>&1 || return 2

  # LC_ALL=C throughout: comm compares bytes, and a sort that collated `-` or
  # `@` by locale rules instead would make it disagree with its own input.
  local named formulae casks out
  named=$(
    cat "$DOT_ROOT/core/Brewfile" "$DOT_ROOT"/modules/*/Brewfile 2>/dev/null |
      sed -n -E 's/^(brew|cask) "([^"]*\/)?([^"]+)".*/\3/p' | LC_ALL=C sort -u
  )
  # No Brewfile read at all would make every package on the machine unmanaged.
  # That is a broken checkout, not a finding.
  [[ -n $named ]] || return 2

  formulae=$(HOMEBREW_NO_AUTO_UPDATE=1 brew leaves --installed-on-request 2>/dev/null) || return 2
  casks=$(HOMEBREW_NO_AUTO_UPDATE=1 brew list --cask 2>/dev/null) || return 2

  out=$(
    comm -23 <(LC_ALL=C sort -u <<<"$formulae") <(printf '%s\n' "$named") |
      awk 'NF {print "Formula", $0}'
    comm -23 <(LC_ALL=C sort -u <<<"$casks") <(printf '%s\n' "$named") |
      awk 'NF {print "Cask", $0}'
  )

  [[ -n $out ]] || return 0
  printf '%s\n' "$out"
  return 1
}
