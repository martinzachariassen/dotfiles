#!/usr/bin/env bash
# chez adopt — record something this Mac already has, so the repo stops calling
# it drift.
#
#   chez adopt <pkg>…          declare an installed Homebrew package in the repo
#   chez adopt --local <pkg>…  declare it for THIS Mac only
#   chez adopt <path>…         hand an existing dotfile to chezmoi
#
# The counterpart of the removal verbs: adopting is how a package stops being
# offered for uninstall, and deleting the line again is how it starts being
# offered. That round trip is the whole point — a machine is allowed to differ
# from the repo, as long as the difference is written down somewhere.
#
# Env: DRY_RUN=1 print what would be written and change nothing.

set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${DOTFILES_DIR:-$(cd "$_DIR/../.." && pwd)}"

if [ ! -r "$ROOT/core/ui.sh" ]; then
    printf 'chez adopt: missing %s\n' "$ROOT/core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$ROOT/core/ui.sh"
ui_init_logging
# shellcheck source=../../core/dry-run.sh
. "$ROOT/core/dry-run.sh"
# shellcheck source=../../core/paths.sh
. "$ROOT/core/paths.sh"
# tiers.sh owns the overlay's path, its seeding and the declared set this verb
# checks against. It refuses to load without core/paths.sh, and adopt without it
# would write to a path it guessed — the one file that must never be guessed.
# shellcheck source=../brew/lib/tiers.sh
if ! . "$ROOT/features/brew/lib/tiers.sh"; then
    printf 'chez adopt: could not load %s — this checkout is incomplete\n' \
        "$ROOT/features/brew/lib/tiers.sh" >&2
    exit 1
fi

usage() {
    cat <<'EOF'
usage: chez adopt [--local] [--formula|--cask] <package|path>…

  <package>     an INSTALLED Homebrew formula or cask, added to the repo's
                Brewfile so every machine gets it
  --local       add it to this Mac's overlay instead, so only this Mac keeps it
  --formula     treat the names as formulae (only needed when a name is both)
  --cask        treat the names as casks
  <path>        an existing file or directory, handed to `chezmoi add`

  --dry-run     print what would be written and change nothing

An argument that exists on disk is treated as a path; anything else is treated
as a package name. Adopting the same thing twice is a no-op.
EOF
}

# ─── pure helpers (unit-tested against stubbed inputs) ────────────────────────

# _adopt_bare NAME — the comparison key, matching brew_bare_names: a Brewfile
# may declare a tap formula qualified or bare, and `brew list` never does.
_adopt_bare() { printf '%s\n' "${1##*/}" | tr '[:upper:]' '[:lower:]'; }

# _adopt_entry KIND NAME — the Brewfile line, in this repo's style.
_adopt_entry() {
    case "$1" in
        cask) printf 'cask "%s"\n' "$2" ;;
        *) printf 'brew "%s"\n' "$2" ;;
    esac
}

# _adopt_declared_in FILE KIND NAME — does FILE already declare it?
#
# Compared on the bare name so a qualified declaration counts. Adopting a second
# copy of something already declared is the failure mode `brew bundle add` has:
# it appends unconditionally, and two `brew "jq"` lines in one Brewfile is drift
# that looks like configuration.
_adopt_declared_in() {
    local file="$1" kind="$2" want
    want="$(_adopt_bare "$3")"
    [ -f "$file" ] || return 1
    local key='brew'
    [ "$kind" = cask ] && key='cask'
    grep -hE "^[[:space:]]*${key} \"" "$file" 2>/dev/null |
        sed -E "s/^[[:space:]]*${key} \"([^\"]+)\".*/\1/" |
        awk -F/ 'NF { print tolower($NF) }' |
        grep -qx -- "$want"
}

# ─── argument handling ───────────────────────────────────────────────────────

TARGET_LOCAL=0
FORCE_KIND=""
ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        --local) TARGET_LOCAL=1 ;;
        --formula | --brew) FORCE_KIND="formula" ;;
        --cask) FORCE_KIND="cask" ;;
        --dry-run) DRY_RUN=1 ;;
        --)
            shift
            while [ $# -gt 0 ]; do
                ARGS+=("$1")
                shift
            done
            break
            ;;
        -*)
            fail "unknown flag: $1"
            usage >&2
            exit 2
            ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done

if [ "${#ARGS[@]}" -eq 0 ]; then
    usage >&2
    exit 2
fi

REPO_BREWFILE="$ROOT/features/brew/Brewfile"
OVERLAY="$(chez_local_brewfile)"
if [ "$TARGET_LOCAL" = "1" ]; then
    TARGET_FILE="$OVERLAY"
    TARGET_LABEL="${OVERLAY/#$HOME/\~}"
else
    TARGET_FILE="$REPO_BREWFILE"
    TARGET_LABEL="features/brew/Brewfile"
fi

explain \
    "Adopting records what this Mac already has. It installs nothing, removes" \
    "nothing, and never touches a package you do not name."

# ─── classify and act ────────────────────────────────────────────────────────

# The set every package is checked against, so "already declared" means the same
# thing here as it does to chez doctor. Unresolvable is not fatal — adopt only
# ever ADDS, so the worst a missed tier costs is a duplicate warning we skip.
ACTIVE_FILES=()
while IFS= read -r _rel; do
    [ -n "$_rel" ] || continue
    _abs="$(brew_resolve_file "$ROOT" "$_rel")"
    [ -n "$_abs" ] && ACTIVE_FILES+=("$_abs")
done < <(brew_active_files 2>/dev/null)

adopted=0
skipped=0
failed=0

adopt_path() {
    local p="$1"
    if ! command -v chezmoi >/dev/null 2>&1; then
        fail "chezmoi is not on PATH — cannot adopt $p"
        failed=$((failed + 1))
        return 1
    fi
    if chezmoi managed 2>/dev/null | grep -qxF "${p#"$HOME"/}"; then
        info "$p is already managed by chezmoi"
        skipped=$((skipped + 1))
        return 0
    fi
    if run chezmoi add -- "$p"; then
        ok "$p → chezmoi (commit it in $ROOT)"
        adopted=$((adopted + 1))
    else
        fail "chezmoi could not adopt $p"
        failed=$((failed + 1))
    fi
}

adopt_pkg() {
    local name="$1" bare kind is_formula=0 is_cask=0 f
    bare="$(_adopt_bare "$name")"

    if ! command -v brew >/dev/null 2>&1; then
        fail "brew is not on PATH — cannot adopt $name"
        failed=$((failed + 1))
        return 1
    fi

    brew list --formula --versions -- "$bare" >/dev/null 2>&1 && is_formula=1
    brew list --cask --versions -- "$bare" >/dev/null 2>&1 && is_cask=1

    if [ -n "$FORCE_KIND" ]; then
        kind="$FORCE_KIND"
    elif [ "$is_formula" = 1 ] && [ "$is_cask" = 1 ]; then
        # docker ships as both, and the two are separate namespaces — guessing
        # would declare the wrong one and leave the other permanently untracked.
        fail "$name is installed as BOTH a formula and a cask — say which with --formula or --cask"
        failed=$((failed + 1))
        return 1
    elif [ "$is_cask" = 1 ]; then
        kind="cask"
    elif [ "$is_formula" = 1 ]; then
        kind="formula"
    else
        # Adopt captures reality; it does not place orders. Accepting an
        # uninstalled name would let a typo into the repo Brewfile, where it
        # breaks `brew bundle install` on every OTHER machine and not on this one.
        fail "$name is not installed — install it first, then adopt it"
        explain "  brew install $name && chez adopt $name"
        failed=$((failed + 1))
        return 1
    fi

    # The count guard is not decoration: bash 3.2 — Apple's /bin/bash, and what
    # a Mac runs before Homebrew's bash exists — expands "${arr[@]}" on an EMPTY
    # array as an unbound variable under `set -u`. The tier set is legitimately
    # empty when brew_active_files cannot resolve (no jq yet, no chezmoi yet),
    # which is exactly the half-installed machine this verb has to survive.
    if [ "${#ACTIVE_FILES[@]}" -gt 0 ]; then
        for f in "${ACTIVE_FILES[@]}"; do
            if _adopt_declared_in "$f" "$kind" "$name"; then
                info "$name is already declared in ${f/#$ROOT\//}"
                skipped=$((skipped + 1))
                return 0
            fi
        done
    fi

    if [ "$TARGET_LOCAL" = "1" ] && [ "$DRY_RUN" != "1" ]; then
        brew_seed_local_brewfile "$ROOT" || {
            fail "could not create $TARGET_LABEL"
            failed=$((failed + 1))
            return 1
        }
    fi

    local line
    line="$(_adopt_entry "$kind" "$name")"
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ append '$line' to $TARGET_LABEL"
        adopted=$((adopted + 1))
        return 0
    fi
    if printf '%s\n' "$line" >>"$TARGET_FILE"; then
        ok "$line → $TARGET_LABEL"
        adopted=$((adopted + 1))
    else
        fail "could not write to $TARGET_LABEL"
        failed=$((failed + 1))
    fi
}

for arg in "${ARGS[@]}"; do
    # Exists on disk ⇒ a path. A tap-qualified formula also contains slashes, so
    # the slash cannot be the test; existence can, and the two never collide in
    # practice (there is no ./azure/kubelogin/kubelogin).
    if [ -e "$arg" ] || [ -L "$arg" ]; then
        adopt_path "$arg"
    else
        adopt_pkg "$arg"
    fi
done

echo
if [ "$adopted" -gt 0 ] && [ "$TARGET_LOCAL" != "1" ]; then
    info "commit the Brewfile so your other Macs get it too"
elif [ "$adopted" -gt 0 ]; then
    info "this stays on this Mac — delete the line to hand the package back"
fi
say "adopted $adopted, already declared $skipped, failed $failed"
[ "$failed" -eq 0 ]
