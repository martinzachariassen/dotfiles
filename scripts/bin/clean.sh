#!/usr/bin/env bash
# chezclean — reconcile untracked dotfiles to what chezmoi manages, across two
# scopes: $HOME's top level (dot-entries) and ~/.config (all children). Removes
# only what you confirm. Config whose owning tool is still installed is kept
# automatically (brew package, PATH command, or VS Code extension present).
#
# Keep-lists and the tool-ownership map live in src/.chezmoidata/cleanup.toml.
# Env: DRY_RUN=1 preview only; YES=1 accept-all. CHEZCLEAN_TARGET overrides $HOME (tests).

set -uo pipefail

TARGET="${CHEZCLEAN_TARGET:-$HOME}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DIR/../../core/ui.sh" ]; then
    printf 'chezclean: missing %s\n' "$_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
ui_init_logging
# shellcheck source=../../core/dry-run.sh
. "$_DIR/../../core/dry-run.sh"

# ─── pure helpers (unit-tested against stubbed inputs) ────────────────────────

# Top-level dot-entries in DIR, sorted. Never descends.
_clean_home_dotentries() {
    local dir="$1" path name
    [ -d "$dir" ] || return 0
    for path in "$dir"/.*; do
        name="${path##*/}"
        case "$name" in
            . | ..) continue ;;
        esac
        # A glob that matches nothing yields the literal pattern; guard against it.
        [ -e "$path" ] || [ -L "$path" ] || continue
        printf '%s\n' "$name"
    done | sort
}

# Top-level chezmoi-managed path segments beginning with ".", sorted-unique.
_clean_managed_top() {
    chezmoi managed 2>/dev/null |
        sed 's#/.*##' |
        grep '^\.' |
        sort -u
}

# The $HOME keep-list, via chezmoi's template engine.
_clean_keep_home() {
    chezmoi execute-template '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# Every immediate child of DIR, dot or not, sorted-unique. Never descends.
_clean_config_entries() {
    local dir="$1" path name
    [ -d "$dir" ] || return 0
    for path in "$dir"/* "$dir"/.*; do
        name="${path##*/}"
        case "$name" in
            . | ..) continue ;;
        esac
        [ -e "$path" ] || [ -L "$path" ] || continue
        printf '%s\n' "$name"
    done | sort -u
}

# Immediate children of ~/.config that chezmoi manages, sorted-unique.
_clean_managed_config() {
    chezmoi managed 2>/dev/null |
        grep '^\.config/' |
        sed 's#^\.config/##; s#/.*##' |
        grep -v '^$' |
        sort -u
}

# The ~/.config keep-list, via chezmoi's template engine.
_clean_keep_config() {
    chezmoi execute-template '{{ range .cleanup.keepConfig }}{{ . }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# Entries chezmoi neither manages nor the keep-list spares.
_clean_candidates() {
    local managed="$1" keep="$2" entry
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        printf '%s\n' "$managed" | grep -qxF -- "$entry" && continue
        printf '%s\n' "$keep" | grep -qxF -- "$entry" && continue
        printf '%s\n' "$entry"
    done
}

# ─── tool-ownership: keep config whose owning tool is still installed ─────────

# Owner rows "entry<TAB>package<TAB>binary<TAB>extension" from cleanup.owners.
_clean_owners() {
    chezmoi execute-template '{{ range $e, $m := (dig "cleanup" "owners" (dict) .) }}{{ $e }}{{ "\t" }}{{ dig "package" "" $m }}{{ "\t" }}{{ dig "binary" "" $m }}{{ "\t" }}{{ dig "extension" "" $m }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# Installed VS Code extension IDs, lowercased. Empty (rc 0) if `code` is absent.
_clean_installed_vscode() {
    command -v code >/dev/null 2>&1 || return 0
    code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

# Installed brew formulae + casks. Empty (rc 0) if brew is absent.
_clean_installed_brew() {
    command -v brew >/dev/null 2>&1 || return 0
    brew list --formula -1 2>/dev/null || true
    brew list --cask -1 2>/dev/null || true
}

# Of the command names on stdin, those found on PATH.
_clean_present_bins() {
    local n
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        command -v "$n" >/dev/null 2>&1 && printf '%s\n' "$n"
    done | sort -u
}

# Each entry's stem: leading dot and anything after the next dot stripped
# (.terraform.d -> terraform).
_clean_stems() {
    local e s
    while IFS= read -r e; do
        [ -n "$e" ] || continue
        s="${e#.}"
        s="${s%%.*}"
        [ -n "$s" ] && printf '%s\n' "$s"
    done
}

# The binary field of each owner row. Parsed by hand, not `read`, since IFS
# treats tab as whitespace and would swallow an empty package/extension field.
_clean_owner_binaries() {
    local row rest rest2 bin tab=$'\t'
    while IFS= read -r row; do
        case "$row" in *"$tab"*"$tab"*"$tab"*) ;; *) continue ;; esac
        rest="${row#*$tab}"
        rest2="${rest#*$tab}"
        bin="${rest2%%"$tab"*}"
        [ -n "$bin" ] && printf '%s\n' "$bin"
    done <<<"$1"
}

# Classify each candidate as keep|orphan|unknown against installed tooling.
# Pure: owners/brewset/binset/extset are plain newline lists.
_clean_classify() {
    local owners="$1" brewset="$2" binset="$3" extset="$4" tab=$'\t'
    local entry row rest rest2 pkg bin ext label found stem
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        found=0
        pkg=""
        bin=""
        ext=""
        while IFS= read -r row; do
            case "$row" in *"$tab"*"$tab"*"$tab"*) ;; *) continue ;; esac
            [ "${row%%"$tab"*}" = "$entry" ] || continue
            found=1
            rest="${row#*$tab}"
            pkg="${rest%%"$tab"*}"
            rest2="${rest#*$tab}"
            bin="${rest2%%"$tab"*}"
            ext="${rest2#*$tab}"
            break
        done <<<"$owners"
        if [ "$found" -eq 1 ]; then
            label="${pkg:-${bin:-$ext}}"
            if { [ -n "$pkg" ] && printf '%s\n' "$brewset" | grep -qxF -- "$pkg"; } ||
                { [ -n "$bin" ] && printf '%s\n' "$binset" | grep -qxF -- "$bin"; } ||
                { [ -n "$ext" ] && printf '%s\n' "$extset" | grep -qxF -- "$ext"; }; then
                printf '%s\t%s\t%s\n' "$entry" keep "$label"
            else
                printf '%s\t%s\t%s\n' "$entry" orphan "$label"
            fi
        else
            stem="${entry#.}"
            stem="${stem%%.*}"
            if [ -n "$stem" ] && printf '%s\n' "$binset" | grep -qxF -- "$stem"; then
                printf '%s\t%s\t%s\n' "$entry" keep "$stem"
            else
                printf '%s\t%s\t%s\n' "$entry" unknown ""
            fi
        fi
    done
}

# One-word type label for the preview.
_clean_kind() {
    if [ -L "$1" ]; then
        printf 'symlink'
    elif [ -d "$1" ]; then
        printf 'dir'
    elif [ -f "$1" ]; then
        printf 'file'
    else
        printf 'other'
    fi
}

# Remove a top-level entry: rm -f for a symlink (never follow it), rm -rf otherwise.
_clean_remove_one() {
    if [ -L "$1" ]; then
        run rm -f "$1"
    else
        run rm -rf "$1"
    fi
}

_clean_help() {
    cat <<'EOF'
usage: chezclean [--all|-a | --yes|-y] [--dry-run|-n] [--verbose|-v]

  Reconcile untracked dotfiles to what chezmoi manages, across two scopes — the
  top level of $HOME (keep-list keepHome) and ~/.config (keep-list keepConfig) —
  and remove only what you confirm. An entry is KEPT automatically while its
  owning tool is still installed — the tool's brew package is present, its command
  is on PATH (so mise/gcloud tools count too), OR its VS Code extension is
  installed. Uninstall the tool / remove the extension and its config re-surfaces
  as removable. Offered entries are labelled "orphan" (a known tool, now gone) or
  "untracked" (no known owner).

  (no flag)     confirm each candidate individually
  --all, -a     remove the whole set after ONE confirmation (alias: --yes, -y)
  --dry-run, -n preview what would be removed; delete nothing (also DRY_RUN=1)
  --verbose, -v also list the entries kept because their tool is installed

  YES=1 chezclean   accept-all with no prompt (still needs a terminal).
  Keep an entry for good: add it to keepHome / keepConfig in
  src/.chezmoidata/cleanup.toml; map a tool's config dir to its command in
  cleanup.owners (e.g. .kube -> kubectl).
EOF
}

# Reconcile one scope: drop managed/kept entries, classify the rest against
# installed tooling, log what was spared, and append still-offered entries to
# the global _CLEAN_OFFERED as "fullpath<TAB>display<TAB>verdict<TAB>label".
_clean_collect() {
    local label="$1" scandir="$2" pathprefix="$3" entries="$4" keep="$5" managed="$6"
    local owners="$7" brewset="$8" extset="$9" verbose="${10}"
    local candidates probe binset classified offered kept_owned kcount count

    candidates="$(printf '%s\n' "$entries" | _clean_candidates "$managed" "$keep")"
    if [ -z "$candidates" ]; then
        ok "$label is clean — every entry is managed or kept"
        return 0
    fi

    probe="$({
        _clean_owner_binaries "$owners"
        printf '%s\n' "$candidates" | _clean_stems
    } | sort -u)"
    binset="$(printf '%s\n' "$probe" | _clean_present_bins)"
    classified="$(printf '%s\n' "$candidates" | _clean_classify "$owners" "$brewset" "$binset" "$extset")"
    offered="$(printf '%s\n' "$classified" | awk -F'\t' '$2 == "orphan" || $2 == "unknown"')"
    kept_owned="$(printf '%s\n' "$classified" | awk -F'\t' '$2 == "keep" { print $1 "\t" $3 }')"

    kcount="$(printf '%s\n' "$kept_owned" | grep -c .)"
    if [ "$kcount" -gt 0 ]; then
        info "kept $kcount untracked entr$([ "$kcount" -eq 1 ] && printf y || printf ies) in $label owned by installed tooling$([ "$verbose" -eq 1 ] || printf ' (-v to list)')"
        if [ "$verbose" -eq 1 ]; then
            local ke kl
            while IFS=$'\t' read -r ke kl; do
                [ -n "$ke" ] || continue
                dim "    $pathprefix$ke (kept — $kl installed)"
            done <<<"$kept_owned"
        fi
    fi

    if [ -z "$offered" ]; then
        ok "$label is clean — every entry is managed, kept, or owned by an installed tool"
        return 0
    fi

    count="$(printf '%s\n' "$offered" | grep -c .)"
    info "$count untracked entr$([ "$count" -eq 1 ] && printf y || printf ies) under $label with no installed owner:"
    local pname pverdict plabel pann
    while IFS=$'\t' read -r pname pverdict plabel; do
        [ -n "$pname" ] || continue
        case "$pverdict" in
            orphan) pann="orphan · config for ${plabel}, not installed" ;;
            *) pann="untracked" ;;
        esac
        dim "    $pathprefix$pname ($(_clean_kind "$scandir/$pname")) — $pann"
        _CLEAN_OFFERED+="$scandir/$pname"$'\t'"$pathprefix$pname"$'\t'"$pverdict"$'\t'"$plabel"$'\n'
    done <<<"$offered"
    hr
}

# ─── main ─────────────────────────────────────────────────────────────────────
_clean_main() {
    local all=0 bulk_confirm=1 verbose=0 arg
    [ "$ASSUME_YES" = "1" ] && {
        all=1
        bulk_confirm=0
    }
    for arg in "$@"; do
        case "$arg" in
            -a | --all | -y | --yes) all=1 ;;
            -n | --dry-run) DRY_RUN=1 ;;
            -v | --verbose) verbose=1 ;;
            -h | --help)
                _clean_help
                return 0
                ;;
            *)
                fail "unknown option: $arg (try --help)"
                return 2
                ;;
        esac
    done
    if [ "$DRY_RUN" = "1" ]; then
        all=1
        bulk_confirm=0
    fi

    if ! command -v chezmoi >/dev/null 2>&1; then
        fail "chezmoi is not on PATH — run install.sh, or brew install chezmoi"
        return 1
    fi

    echo
    printf '%s%s%s  %sUntracked dotfiles%s\n' "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
    explain \
        "Looks for dotfiles in ~ and ~/.config that this repo does not manage," \
        "then offers to delete them one at a time." \
        "Config belonging to a tool you still have installed is kept automatically." \
        "Nothing is removed without your confirmation."

    # keepHome guards $HOME's top level, so an unreadable keep-list is fail-closed.
    local keep_home keep_config
    keep_home="$(_clean_keep_home)"
    if [ -z "$keep_home" ]; then
        fail "empty keep-list (could not read .cleanup.keepHome) — refusing to touch \$HOME"
        return 1
    fi

    local owners brewset extset
    owners="$(_clean_owners)"
    brewset="$(_clean_installed_brew)"
    extset="$(_clean_installed_vscode)"

    _CLEAN_OFFERED=""

    _clean_collect "\$HOME top level" "$TARGET" "" \
        "$(_clean_home_dotentries "$TARGET")" "$keep_home" "$(_clean_managed_top)" \
        "$owners" "$brewset" "$extset" "$verbose"

    # Skipped fail-safe if its keep-list is unreadable.
    keep_config="$(_clean_keep_config)"
    if [ -n "$keep_config" ]; then
        _clean_collect "~/.config" "$TARGET/.config" ".config/" \
            "$(_clean_config_entries "$TARGET/.config")" "$keep_config" "$(_clean_managed_config)" \
            "$owners" "$brewset" "$extset" "$verbose"
    elif [ -d "$TARGET/.config" ]; then
        warn "skipping ~/.config — empty keep-list (could not read .cleanup.keepConfig)"
    fi

    if [ -z "$_CLEAN_OFFERED" ]; then
        return 0
    fi
    local count
    count="$(printf '%s' "$_CLEAN_OFFERED" | grep -c .)"

    # DRY_RUN deletes nothing, so it's exempt from the terminal requirement.
    if [ "$DRY_RUN" != "1" ] && ! { : </dev/tty; } 2>/dev/null; then
        warn "no TTY — not removing. Re-run interactively, or use --all / YES=1."
        return 0
    fi

    if [ "$all" -eq 1 ] && [ "$bulk_confirm" -eq 1 ]; then
        local ok_batch
        if command -v gum >/dev/null 2>&1; then
            gum confirm "Remove ALL $count untracked entr$([ "$count" -eq 1 ] && printf y || printf ies)?" && ok_batch=1 || ok_batch=0
        else
            local reply
            printf '%s  Remove ALL %s untracked entr%s? [y/N] ' "$(line_prefix)" "$count" "$([ "$count" -eq 1 ] && printf y || printf ies)" >/dev/tty
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in y | Y | yes | YES) ok_batch=1 ;; *) ok_batch=0 ;; esac
        fi
        [ "$ok_batch" -eq 1 ] || {
            info "aborted — nothing removed"
            return 0
        }
    fi

    # Phase 1 — decide. Feed the list on fd 3, keeping stdin on the terminal so
    # gum reads keypresses.
    local approved="" kept=0 fpath display verdict label hint reply ok_one
    while IFS=$'\t' read -r fpath display verdict label <&3; do
        [ -n "$fpath" ] || continue
        hint=""
        [ "$verdict" = orphan ] && hint=" · ${label} not installed"
        if [ "$all" -eq 1 ]; then
            ok_one=1
        elif command -v gum >/dev/null 2>&1; then
            gum confirm "Remove $display ($(_clean_kind "$fpath")$hint)?" && ok_one=1 || ok_one=0
        else
            printf '%s  Remove %s (%s%s)? [y/N] ' "$(line_prefix)" "$display" "$(_clean_kind "$fpath")" "$hint" >/dev/tty
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in y | Y | yes | YES) ok_one=1 ;; *) ok_one=0 ;; esac
        fi
        if [ "$ok_one" -eq 1 ]; then
            approved+="$fpath"$'\n'
        else
            kept=$((kept + 1))
        fi
    done 3<<<"$_CLEAN_OFFERED"

    # Phase 2 — remove the approved set.
    local removed=0
    while IFS= read -r fpath; do
        [ -n "$fpath" ] || continue
        if _clean_remove_one "$fpath"; then
            removed=$((removed + 1))
        else
            warn "could not remove $fpath — remove it by hand"
        fi
    done <<<"$approved"

    hr
    ok "removed $removed · kept $kept"
    return 0
}

# Tests source this file to exercise the pure helpers, so only run when executed.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    _clean_main "$@"
fi
