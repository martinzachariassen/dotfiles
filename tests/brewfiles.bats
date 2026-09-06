#!/usr/bin/env bats
#
# The Brewfiles against Homebrew itself. A package renamed, deprecated or
# withdrawn upstream is the one failure this repo cannot prevent and could not
# see: brew follows a rename through its oldnames table in silence, right up to
# the day the alias is dropped -- and then a fresh install fails on the one
# machine with no tooling on it yet.
#
# Split in two on purpose. The shape check is offline and runs with `make
# check`. The audit talks to Homebrew, so it is opt-in (`make brew-audit`) and
# scheduled in CI: upstream changes without anyone touching this repo, so it
# must never be able to fail a pull request about something else.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

brewfiles() {
  printf '%s\n' "$DOT_ROOT/core/Brewfile"
  find "$DOT_ROOT/modules" -name Brewfile -type f | sort
}

# packages -- "<formula|cask> <name>", the same two line shapes brew bundle
# reads. Anything else is caught by the shape test below, so this stays a sed.
packages() {
  local f
  while IFS= read -r f; do
    sed -n -E 's/^brew "([^"]+)".*/formula \1/p; s/^cask "([^"]+)".*/cask \1/p' "$f"
  done < <(brewfiles) | sort -u
}

@test "every Brewfile line is brew, cask, tap, a comment or blank" {
  # packages() would silently drop anything else, and so would this repo's
  # idea of what it installs.
  local f line bad=()
  while IFS= read -r f; do
    while IFS= read -r line; do
      case $line in
        '' | '#'*) ;;
        'brew "'*'"'* | 'cask "'*'"'* | 'tap "'*'"'*) ;;
        *) bad+=("${f#"$DOT_ROOT"/}: $line") ;;
      esac
    done <"$f"
  done < <(brewfiles)

  [ ${#bad[@]} -eq 0 ] || {
    printf 'unrecognised Brewfile line:\n'
    printf '  %s\n' "${bad[@]}"
    return 1
  }
}

@test "every package names something Homebrew still has, under that name" {
  [ -n "${DOT_BREW_AUDIT:-}" ] || skip 'talks to Homebrew -- run: make brew-audit'
  command -v brew >/dev/null 2>&1 || skip 'Homebrew is not installed'

  local kind name json problem bad=()
  while read -r kind name; do
    if ! json=$(brew info --json=v2 "--$kind" "$name" 2>/dev/null); then
      bad+=("$kind $name -- GONE, Homebrew does not know this name")
      continue
    fi

    # A rename is the quiet one: brew resolves the old name through its
    # oldnames table and installs the right thing, so nothing fails until the
    # alias is dropped. full_name/token is what brew actually resolved to.
    problem=$(jq -r --arg n "$name" '
      (.formulae[0] // .casks[0]) as $p
      | [ (if ($p.full_name // $p.token) != $n
             then "RENAMED to " + ($p.full_name // $p.token) else empty end),
          (if $p.disabled then "DISABLED, it will stop installing" else empty end),
          (if $p.deprecated then "DEPRECATED"
             + (if ($p.deprecation_reason // "") != "" then ": " + $p.deprecation_reason else "" end)
             else empty end) ]
      | join("; ")' <<<"$json" 2>/dev/null) || problem="could not read brew's JSON"

    [ -z "$problem" ] || bad+=("$kind $name -- $problem")
  done < <(packages)

  [ ${#bad[@]} -eq 0 ] || {
    printf 'Homebrew no longer agrees with these Brewfile lines:\n'
    printf '  %s\n' "${bad[@]}"
    printf 'Fix the Brewfile before a fresh install hits it.\n'
    return 1
  }
}
