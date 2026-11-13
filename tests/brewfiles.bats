#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

brewfiles() {
  printf '%s\n' "$DOT_ROOT/core/Brewfile"
  find "$DOT_ROOT/modules" -name Brewfile -type f | sort
}

packages() {
  local f
  while IFS= read -r f; do
    sed -n -E 's/^brew "([^"]+)".*/formula \1/p; s/^cask "([^"]+)".*/cask \1/p' "$f"
  done < <(brewfiles) | sort -u
}

@test "every Brewfile line is brew, cask, tap, a comment or blank" {
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
