# shellcheck shell=bash
#
# Shared bats setup. Every test runs against a throwaway $HOME.

setup_sandbox() {
  DOT_TMP=$(mktemp -d)
  export DOT_TMP

  export HOME="$DOT_TMP/home"
  export DOT_STATE="$DOT_TMP/state"
  export DOT_CONFIG="$DOT_TMP/config.toml"
  export DOT_DRY_RUN=0
  mkdir -p "$HOME"

  # Pinned, not inherited: a developer machine exporting these would make a
  # real apply `mkdir -p` outside the sandbox.
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"

  # A mise shim resolves runtimes under $HOME; against the empty sandbox a bare
  # `python3` tries to install one over the network.
  local kept=() dir
  while IFS= read -r dir; do
    if [[ $dir != */mise/shims ]]; then kept+=("$dir"); fi
  done < <(tr ':' '\n' <<<"$PATH")
  PATH=$(
    IFS=:
    printf '%s' "${kept[*]}"
  )
  export PATH

  # The library is loaded from the real repo; only $HOME is fake.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOT_ROOT
  # shellcheck source=../lib/dot.sh
  source "$DOT_ROOT/lib/dot.sh"

  DOT_N_LINKED=0 DOT_N_RELINKED=0 DOT_N_BACKED_UP=0 DOT_N_UNCHANGED=0
  DOT_FAILURES=0 DOT_WARNINGS=0

  # fs_backup_used answers from the filesystem, so ids must not be shared.
  export DOT_RUN_ID="test-$BATS_TEST_NUMBER"
}

teardown_sandbox() {
  [[ -n ${DOT_TMP:-} && -d $DOT_TMP ]] && rm -rf "$DOT_TMP"
  return 0
}

# home_snapshot -- sorted listing of $HOME with the CONTENT of every file, so
# diffing before/after proves nothing was written. ~/Library is pruned: brew
# and macOS write there on their own.
#
# The hash is the point. A path listing alone cannot see an in-place rewrite,
# which is exactly the bug the contract tests using this were written for:
# claude-code/remove.sh rewriting ~/.claude/settings.json during a dry run
# leaves every path where it was. Symlinks report their target instead, so a
# hook that quietly re-points one is caught too, and a dangling link does not
# become a read error.
home_snapshot() {
  local p
  find "$HOME" -path "$HOME/Library" -prune -o -print0 | sort -z |
    while IFS= read -r -d '' p; do
      if [[ -L $p ]]; then
        printf 'link %s -> %s\n' "$p" "$(readlink "$p")"
      elif [[ -f $p ]]; then
        printf 'file %s %s\n' "$p" "$(shasum -a 256 <"$p" | cut -d' ' -f1)"
      else
        printf 'node %s\n' "$p"
      fi
    done
}

# fixture_module NAME -- a module directory outside the repo.
fixture_module() {
  local dir="$DOT_TMP/modules/$1"
  mkdir -p "$dir/home"
  printf '%s\n' "$dir"
}

# fixture_file DIR REL CONTENT -- create a file inside a fixture's home/.
fixture_file() {
  local dir=$1 rel=$2 content=${3:-content}
  mkdir -p "$(dirname "$dir/home/$rel")"
  printf '%s\n' "$content" >"$dir/home/$rel"
}

# json_parses FILE -- strict JSON, or JSONC: `//` line comments and trailing
# commas, which is what cmux ships and what the VS Code family reads. The
# comment strip is anchored to the start of the line on purpose, so a "https://"
# inside a string value survives it.
json_parses() {
  jq -e . "$1" >/dev/null 2>&1 && return 0
  sed 's|^[[:space:]]*//.*$||' "$1" |
    perl -0pe 's/,(\s*[}\]])/$1/g' |
    jq -e . >/dev/null 2>&1
}
