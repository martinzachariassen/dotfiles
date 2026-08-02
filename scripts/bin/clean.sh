#!/usr/bin/env bash
# clean.sh — reconcile untracked dotfiles to what chezmoi manages, across TWO
# scopes, removing only what you confirm. The file analogue of chezmirror (which
# does the same for Homebrew packages). Because ~/.config is a normal dot_config
# dir (not exact_), an apply never prunes it — this verb is what reconciles it.
#   scope 1 — the TOP LEVEL of $HOME: untracked ~/.* entries (keep-list keepHome).
#   scope 2 — ~/.config: untracked ~/.config/X children       (keep-list keepConfig).
#
# Scope is deliberately narrow and safe:
#   • scope 1 considers only entries whose name begins with "." — so ~/Library,
#     ~/Documents, ~/Developer and other user data are out of scope structurally;
#   • scope 2 considers every immediate child of ~/.config (its entries are mostly
#     non-dot: nvim, gh, …), still never descending past that immediate child;
#   • neither scope EVER descends into a directory — only whole children;
#   • config whose owning tool is still installed is KEPT automatically — the
#     tool's brew package is present, its command is on PATH (so mise/gcloud tools
#     count too), OR (for a VS Code extension-owned dir) its extension is installed;
#     uninstalling a tool / removing an extension re-surfaces its leftovers;
#   • nothing is removed without a confirmation (or an explicit --all / YES=1),
#     and never at all without a controlling terminal.
#
# Both keep-lists and the tool-ownership map are the single source of truth in
# src/.chezmoidata/cleanup.toml (.cleanup.keepHome / .keepConfig / .owners), read
# through chezmoi's own template engine — so the two scopes can't drift apart and
# need no jq. Most tools are matched by a stem heuristic (command -v
# <name-minus-dot>); the owners map holds only the aliases where the dir name and
# the tool's command/package/extension diverge (.kube -> kubectl, .m2 -> mvn,
# .sonarlint -> the sonarlint-vscode extension).
# Unlike a chezmoi hook this verb runs with a live stdin, so it talks to /dev/tty
# directly (no tty.sh).
#
# Env: DRY_RUN=1 preview without deleting (works headless); YES=1 accept-all.
#      CHEZCLEAN_TARGET overrides $HOME (tests only).

set -uo pipefail

TARGET="${CHEZCLEAN_TARGET:-$HOME}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DIR/../lib/log.sh" ]; then
    printf 'chezclean: missing %s\n' "$_DIR/../lib/log.sh" >&2
    exit 1
fi
# shellcheck source=../lib/log.sh
. "$_DIR/../lib/log.sh"
ui_init_logging

run() {
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ $*"
        return 0
    fi
    "$@"
}

# ─── pure helpers (unit-tested against stubbed inputs) ────────────────────────

# _clean_home_dotentries DIR — basenames of top-level entries in DIR beginning
# with "." (dirs, files, symlinks incl. dangling), excluding . and .., one per
# line, sorted. Never descends. Dangling symlinks count (they're cruft too).
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

# _clean_managed_top — top-level chezmoi-managed target components beginning with
# "." (e.g. .config, .zshenv, .ssh), one per line, sorted-unique. `chezmoi
# managed` lists target-relative paths; we keep only the first path segment.
_clean_managed_top() {
    chezmoi managed 2>/dev/null |
        sed 's#/.*##' |
        grep '^\.' |
        sort -u
}

# _clean_keep_home — the keep-list from the single source of truth, via chezmoi's
# template engine (no jq; can't drift from the ~/.config keep-list).
_clean_keep_home() {
    chezmoi execute-template '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# _clean_config_entries DIR — basenames of every immediate child of DIR, dot or
# not (~/.config holds mostly non-dot dirs like nvim/gh, plus a few dot ones such
# as .wrangler), excluding . and .., one per line, sorted-unique. Never descends;
# dangling symlinks count (cruft too). The ~/.config analogue of
# _clean_home_dotentries, which is $HOME-only and dot-only.
_clean_config_entries() {
    local dir="$1" path name
    [ -d "$dir" ] || return 0
    for path in "$dir"/* "$dir"/.*; do
        name="${path##*/}"
        case "$name" in
            . | ..) continue ;;
        esac
        # A glob that matches nothing yields the literal pattern; guard against it.
        [ -e "$path" ] || [ -L "$path" ] || continue
        printf '%s\n' "$name"
    done | sort -u
}

# _clean_managed_config — immediate children of ~/.config that chezmoi manages
# (e.g. nvim, gh, zsh), one per line, sorted-unique. `chezmoi managed` lists
# target-relative paths; keep those under .config/ and take the first segment
# after it. The ~/.config analogue of _clean_managed_top.
_clean_managed_config() {
    chezmoi managed 2>/dev/null |
        grep '^\.config/' |
        sed 's#^\.config/##; s#/.*##' |
        grep -v '^$' |
        sort -u
}

# _clean_keep_config — the ~/.config keep-list from the single source of truth,
# via chezmoi's template engine (no jq). Its consumer is this verb (scope 2) — the
# auth/state dirs (gh, op, gcloud, …) that must never be offered even though no
# "tool on PATH" signal covers them.
_clean_keep_config() {
    chezmoi execute-template '{{ range .cleanup.keepConfig }}{{ . }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# _clean_candidates MANAGED KEEP — read home dot-entries on stdin; emit those
# that chezmoi neither manages (MANAGED, newline list) nor the keep-list spares
# (KEEP, newline list). Pure: no filesystem, no chezmoi — fully stubbable.
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
# The three impure helpers below are each independently stubbable (chezmoi / brew
# / command -v); the pure classify logic underneath takes their output as plain
# newline lists, so it's unit-testable exactly like _clean_candidates.

# _clean_owners — rows "entry<TAB>package<TAB>binary<TAB>extension" for each
# cleanup.owners entry, via chezmoi's template engine (no jq). dig-guarded: a
# missing map renders nothing — a bare `range .cleanup.owners` would ERROR when the
# key is absent — so the feature is safe before/without the map. dig on each element
# gives default-safe optional fields. Always emits three tabs (so an empty field in
# the middle survives), which the parsers below rely on.
_clean_owners() {
    chezmoi execute-template '{{ range $e, $m := (dig "cleanup" "owners" (dict) .) }}{{ $e }}{{ "\t" }}{{ dig "package" "" $m }}{{ "\t" }}{{ dig "binary" "" $m }}{{ "\t" }}{{ dig "extension" "" $m }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# _clean_installed_vscode — installed VS Code extension IDs, lowercased and
# sorted-unique, one per line. Empty with rc 0 when `code` is absent, so a machine
# without VS Code simply degrades to the package/binary signals (same graceful
# pattern as _clean_installed_brew). The ONLY `code` call in the classify path.
_clean_installed_vscode() {
    command -v code >/dev/null 2>&1 || return 0
    code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

# _clean_installed_brew — installed formulae + casks, one per line. Empty with rc
# 0 when brew is absent, so a brew-less machine simply degrades to the binary
# check. No `shellenv` eval (brew is already on PATH for the interactive verb, and
# eval would shadow the test stub); `brew list` includes deps, unlike `leaves`.
_clean_installed_brew() {
    command -v brew >/dev/null 2>&1 || return 0
    brew list --formula -1 2>/dev/null || true
    brew list --cask -1 2>/dev/null || true
}

# _clean_present_bins — read command names on stdin; emit those `command -v`
# finds on PATH, sorted-unique. The ONLY command -v probing in the classify path
# (kept out of the pure logic). Sees mise/gcloud/npm shims because chezclean runs
# from the interactive login shell, where those dirs are already on PATH.
_clean_present_bins() {
    local n
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        command -v "$n" >/dev/null 2>&1 && printf '%s\n' "$n"
    done | sort -u
}

# _clean_stems — read entries on stdin; emit each entry's stem (name minus the
# leading dot, truncated at the first remaining dot: .terraform.d -> terraform).
_clean_stems() {
    local e s
    while IFS= read -r e; do
        [ -n "$e" ] || continue
        s="${e#.}"
        s="${s%%.*}"
        [ -n "$s" ] && printf '%s\n' "$s"
    done
}

# _clean_owner_binaries OWNERS — the non-empty binary field of each owner row (rows
# are entry<TAB>package<TAB>binary<TAB>extension), so the caller can probe those
# commands alongside candidate stems in one pass. Parsed with parameter expansion,
# not `read -r a b c d` with IFS=<tab>: <tab> is IFS-whitespace, so `read` would
# collapse an empty package/extension field (".m2<tab><tab>mvn<tab>") and read the
# binary into the wrong slot. A row needs its three tabs for a binary field to exist.
_clean_owner_binaries() {
    local row rest rest2 bin tab=$'\t'
    while IFS= read -r row; do
        case "$row" in *"$tab"*"$tab"*"$tab"*) ;; *) continue ;; esac
        rest="${row#*$tab}"     # drop entry
        rest2="${rest#*$tab}"   # drop package
        bin="${rest2%%"$tab"*}" # binary field (before the extension tab)
        [ -n "$bin" ] && printf '%s\n' "$bin"
    done <<<"$1"
}

# _clean_classify OWNERS BREWSET BINSET EXTSET — read candidate entries on stdin;
# emit "entry<TAB>verdict<TAB>label", verdict in keep|orphan|unknown. PURE: BREWSET,
# BINSET and EXTSET are newline lists (like _clean_candidates' MANAGED/KEEP), so
# classifying needs no tools and is fully unit-testable. Entries contain '.' (a
# regex metachar), so every membership test is an exact string compare (grep -qxF).
#   • mapped + (package∈BREWSET OR binary∈BINSET OR extension∈EXTSET) -> keep   (label = tool)
#   • mapped + none present                                           -> orphan (label = tool)
#   • unmapped + stem in BINSET                                       -> keep   (label = stem)
#   • unmapped + stem absent                                          -> unknown
_clean_classify() {
    local owners="$1" brewset="$2" binset="$3" extset="$4" tab=$'\t'
    local entry row rest rest2 pkg bin ext label found stem
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        found=0
        pkg=""
        bin=""
        ext=""
        # Parameter-expansion split (not `read a b c d`): <tab> is IFS-whitespace, so
        # `read` collapses an empty package/extension field (".m2<tab><tab>mvn<tab>")
        # — losing the binary. A valid owner row has exactly three tabs
        # (entry/package/binary/extension).
        while IFS= read -r row; do
            case "$row" in *"$tab"*"$tab"*"$tab"*) ;; *) continue ;; esac
            [ "${row%%"$tab"*}" = "$entry" ] || continue
            found=1
            rest="${row#*$tab}" # after entry
            pkg="${rest%%"$tab"*}"
            rest2="${rest#*$tab}" # after package
            bin="${rest2%%"$tab"*}"
            ext="${rest2#*$tab}" # extension = last field
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

# _clean_kind PATH — one-word type label for the preview.
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

# _clean_remove_one PATH — remove a top-level entry. rm -f for a symlink (never
# follow it), rm -rf otherwise. Routed through run() so DRY_RUN only prints.
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

# _clean_collect LABEL SCANDIR PATHPREFIX ENTRIES KEEP MANAGED OWNERS BREWSET \
#                EXTSET VERBOSE
# Reconcile ONE scope up to (but not including) removal: from the scope's raw
# ENTRIES (newline list), drop what chezmoi MANAGES and the KEEP-list spares,
# classify the rest against installed tooling (OWNERS/BREWSET/EXTSET + a per-scope
# command -v probe), report what tool-ownership spared (—verbose names them), and
# APPEND every still-offered entry to the global _CLEAN_OFFERED as
# "fullpath<TAB>display<TAB>verdict<TAB>label". Prints only human-facing log lines;
# the offered set is returned via the global so _clean_main can confirm/remove both
# scopes in one uniform pass. PATHPREFIX (""/".config/") disambiguates display
# names and the removal path across scopes.
_clean_collect() {
    local label="$1" scandir="$2" pathprefix="$3" entries="$4" keep="$5" managed="$6"
    local owners="$7" brewset="$8" extset="$9" verbose="${10}"
    local candidates probe binset classified offered kept_owned kcount count

    candidates="$(printf '%s\n' "$entries" | _clean_candidates "$managed" "$keep")"
    if [ -z "$candidates" ]; then
        ok "$label is clean — every entry is managed or kept"
        return 0
    fi

    # Classify each candidate against installed tooling: keep config whose owner is
    # present (brew package installed, its command on PATH, OR — for a VS Code
    # extension-owned dir — its extension in `code --list-extensions`), so only
    # orphaned or unknown leftovers are ever offered. Probe owner-binaries and
    # candidate stems together in one command -v pass.
    probe="$({
        _clean_owner_binaries "$owners"
        printf '%s\n' "$candidates" | _clean_stems
    } | sort -u)"
    binset="$(printf '%s\n' "$probe" | _clean_present_bins)"
    classified="$(printf '%s\n' "$candidates" | _clean_classify "$owners" "$brewset" "$binset" "$extset")"
    offered="$(printf '%s\n' "$classified" | awk -F'\t' '$2 == "orphan" || $2 == "unknown"')"
    kept_owned="$(printf '%s\n' "$classified" | awk -F'\t' '$2 == "keep" { print $1 "\t" $3 }')"

    # Reassure the user about what tool-ownership spared; --verbose lists them.
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
    # A dry-run deletes nothing, so preview the whole set unconditionally and
    # skip the terminal requirement — it's a safe read-only report anywhere.
    if [ "$DRY_RUN" = "1" ]; then
        all=1
        bulk_confirm=0
    fi

    if ! command -v chezmoi >/dev/null 2>&1; then
        fail "chezmoi is not on PATH — run install.sh, or brew install chezmoi"
        return 1
    fi

    # keepHome guards $HOME's top level, which ALWAYS holds critical dirs (.ssh,
    # auth) — an unreadable keep-list there would offer them for deletion, so it's
    # a hard, fail-closed error. keepConfig (scope 2) is checked below and merely
    # skips ~/.config if unreadable: scope 1 is independent and already validated.
    local keep_home keep_config
    keep_home="$(_clean_keep_home)"
    if [ -z "$keep_home" ]; then
        fail "empty keep-list (could not read .cleanup.keepHome) — refusing to touch \$HOME"
        return 1
    fi

    # Installed-tool signals, computed ONCE and shared by both scopes.
    local owners brewset extset
    owners="$(_clean_owners)"
    brewset="$(_clean_installed_brew)"
    extset="$(_clean_installed_vscode)"

    # Collect the offered set across both scopes into _CLEAN_OFFERED, then decide
    # and remove in one uniform pass — so there's ONE tty gate, ONE bulk confirm,
    # and ONE summary regardless of how many scopes surfaced something.
    _CLEAN_OFFERED=""

    # scope 1 — top level of $HOME (dot-only; keepHome).
    _clean_collect "\$HOME top level" "$TARGET" "" \
        "$(_clean_home_dotentries "$TARGET")" "$keep_home" "$(_clean_managed_top)" \
        "$owners" "$brewset" "$extset" "$verbose"

    # scope 2 — ~/.config (all children; keepConfig). Skipped fail-safe if its
    # keep-list is unreadable (never offer ~/.config/X with nothing spared).
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

    # No controlling terminal ⇒ remove nothing. DRY_RUN is exempt: it deletes
    # nothing, so it stays a safe preview that works headless (e.g. in CI).
    if [ "$DRY_RUN" != "1" ] && ! { : </dev/tty; } 2>/dev/null; then
        warn "no TTY — not removing. Re-run interactively, or use --all / YES=1."
        return 0
    fi

    # One bulk confirm for --all (YES=1 already cleared bulk_confirm).
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

    # Phase 1 — decide. Confirm each entry (unless accept-all); collect approvals.
    # Feed the list on fd 3, keeping stdin on the terminal so gum reads keypresses.
    # Rows are "fullpath<TAB>display<TAB>verdict<TAB>label" (display carries the
    # ~/.config/ prefix for scope 2; the label hints why an orphan surfaced).
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

    # Phase 2 — remove the approved set (full paths, so scope-agnostic).
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

# Run unless sourced (tests source the file to exercise the pure helpers).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    _clean_main "$@"
fi
