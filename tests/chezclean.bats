#!/usr/bin/env bats
# Behavioural tests for clean.sh — the chezclean verb that mirrors the TOP LEVEL
# of $HOME to what chezmoi manages: it surfaces untracked ~/.* entries (minus the
# keepHome list) and removes only what you confirm. The file analogue of
# chezmirror (which does the same for Homebrew packages).
#
# Why this exists:
#   The dangerous, subtle bit is the candidate set: home entry, MINUS every
#   chezmoi-managed top-level component, MINUS the keep-list. A drift in any of
#   the three (a managed dir parsed wrong, an empty keep-list read as "keep
#   nothing") would offer auth/state/user dirs for deletion. These tests pin the
#   pure candidate computation, the keep-list/managed filtering, the symlink-safe
#   removal, and — most importantly — the safety guards: nothing is removed
#   without a confirmation, and NOTHING at all without a controlling terminal.
#
#   The interactive/removing paths need a controlling terminal (clean.sh reads
#   confirms via a live tty / gum), so those tests are inverse-gated: the safety
#   + dry-run tests run headless (CI); the confirm/remove tests run only under a
#   real or pseudo tty. Run the full set locally with:
#       script -q /dev/null bats tests/chezclean.bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/bin/clean.sh"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"
    [ -x "$SCRIPT" ] || skip "clean.sh missing or not executable"

    # A fake $HOME whose top level mixes managed dirs, keep-listed dirs, and pure
    # junk. Candidates must be exactly the junk: not managed, not on keepHome.
    FAKEHOME="$BATS_TEST_TMPDIR/home"
    mkdir -p \
        "$FAKEHOME/.config" \
        "$FAKEHOME/.storecode" \
        "$FAKEHOME/.cache" \
        "$FAKEHOME/.hawtjni" \
        "$FAKEHOME/.lemminx"
    : >"$FAKEHOME/.zshenv"     # managed file
    : >"$FAKEHOME/.junkfile"   # untracked file
    ln -s "$FAKEHOME/never-exists" "$FAKEHOME/.deadlink"  # dangling symlink (cruft)
    # A non-dot entry must be structurally out of scope (never a candidate).
    mkdir -p "$FAKEHOME/Documents"

    # Stub chezmoi: `managed` and `execute-template` (keepHome) read from files so
    # individual tests can rewrite them (e.g. to force an empty keep-list).
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    MANAGED_OUT="$STUBS/managed.out"
    KEEP_OUT="$STUBS/keep.out"
    # chezmoi managed lists target-relative paths; only the first "." segment
    # matters. Include a subpath (.config/nvim → .config) and a non-dot Library
    # path (dropped) to prove the parser.
    printf '%s\n' '.config' '.config/nvim' '.zshenv' '.ssh' 'Library/Application Support/x' >"$MANAGED_OUT"
    printf '%s\n' '.storecode' '.cache' '.config' '.ssh' >"$KEEP_OUT"

    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    managed) cat "$MANAGED_OUT" 2>/dev/null ;;
    execute-template) cat "$KEEP_OUT" 2>/dev/null ;;
    *) exit 0 ;;
esac
EOF

    # Real \`gum confirm\` reads keypresses from STDIN; the stub mirrors that so the
    # confirm-loop tests can drive it: one answer line per confirm, "yes" ⇒ 0.
    cat >"$STUBS/gum" <<'EOF'
#!/usr/bin/env bash
[ "$1" = confirm ] || exit 0
IFS= read -r ans || ans=""
[ "$ans" = yes ]
EOF
    chmod +x "$STUBS/chezmoi" "$STUBS/gum"
}

# Can this process open a controlling terminal? Mirrors clean.sh's own guard so
# the tty-gated tests agree with production behaviour.
have_tty() { { : </dev/tty; } >/dev/null 2>&1; }

# Run the whole script under the stubbed PATH against the fake $HOME.
run_clean() { # run_clean [args...] — extra env via caller's `run env` if needed
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" bash "$SCRIPT" "$@"
}

# ─── pure helpers (sourced in a subshell so clean.sh's set -u never leaks) ────

@test "_clean_candidates offers only entries neither managed nor kept" {
    local managed keep entries
    managed=$'.config\n.ssh\n.zshenv'
    keep=$'.storecode\n.cache\n.config\n.ssh'
    entries=$'.cache\n.config\n.deadlink\n.hawtjni\n.junkfile\n.lemminx\n.ssh\n.storecode\n.zshenv'
    run bash -c 'source "$1"; printf "%s\n" "$2" | _clean_candidates "$3" "$4"' \
        _ "$SCRIPT" "$entries" "$managed" "$keep"
    [ "$status" -eq 0 ]
    [ "$output" = $'.deadlink\n.hawtjni\n.junkfile\n.lemminx' ]
}

@test "_clean_candidates keeps a managed entry even if it's not on the keep-list" {
    # .zshenv is managed but NOT on keepHome — being managed alone must spare it.
    run bash -c 'source "$1"; printf "%s\n" "$2" | _clean_candidates "$3" "$4"' \
        _ "$SCRIPT" $'.zshenv\n.junkfile' $'.zshenv' $'.cache'
    [ "$status" -eq 0 ]
    [ "$output" = ".junkfile" ]
}

@test "_clean_home_dotentries lists dot entries only, sorted, dangling links included" {
    local d="$BATS_TEST_TMPDIR/le"
    mkdir -p "$d/.adir" "$d/notdotdir"
    : >"$d/.afile"
    : >"$d/notdotfile"
    ln -s "$d/missing" "$d/.dead"  # dangling — must still be listed
    run bash -c 'source "$1"; _clean_home_dotentries "$2"' _ "$SCRIPT" "$d"
    [ "$status" -eq 0 ]
    [ "$output" = $'.adir\n.afile\n.dead' ]
}

@test "_clean_home_dotentries never lists . or .. and is empty for a missing dir" {
    run bash -c 'source "$1"; _clean_home_dotentries "$2/does-not-exist"' _ "$SCRIPT" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_clean_managed_top reduces managed paths to unique top-level dot segments" {
    run env PATH="$STUBS:$PATH" bash -c 'source "$1"; _clean_managed_top' _ "$SCRIPT"
    [ "$status" -eq 0 ]
    # .config (from both .config and .config/nvim, deduped), .ssh, .zshenv;
    # the Library/* path is dropped (no leading dot).
    [ "$output" = $'.config\n.ssh\n.zshenv' ]
}

@test "_clean_kind labels dir/file/symlink/other" {
    local d="$BATS_TEST_TMPDIR/kind"
    mkdir -p "$d/.dir"
    : >"$d/.file"
    ln -s "$d/.file" "$d/.link"
    run bash -c 'source "$1"; for x in .dir .file .link .none; do _clean_kind "$2/$x"; echo; done' \
        _ "$SCRIPT" "$d"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "dir" ]
    [ "${lines[1]}" = "file" ]
    [ "${lines[2]}" = "symlink" ]
    [ "${lines[3]}" = "other" ]
}

@test "_clean_remove_one honours DRY_RUN (previews, deletes nothing)" {
    mkdir -p "$FAKEHOME/.keepme"
    run bash -c 'source "$1"; DRY_RUN=1; _clean_remove_one "$2/.keepme"' _ "$SCRIPT" "$FAKEHOME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]]
    [ -d "$FAKEHOME/.keepme" ]  # untouched
}

@test "_clean_remove_one removes a symlink without following it (rm -f, not the target)" {
    local d="$BATS_TEST_TMPDIR/rm"
    mkdir -p "$d"
    : >"$d/target"
    ln -s "$d/target" "$d/.lnk"
    run bash -c 'source "$1"; DRY_RUN=0; _clean_remove_one "$2/.lnk"' _ "$SCRIPT" "$d"
    [ "$status" -eq 0 ]
    [ ! -L "$d/.lnk" ]   # link gone
    [ -e "$d/target" ]   # its target survived (never followed)
}

# ─── dry-run: safe, headless preview ─────────────────────────────────────────

@test "DRY_RUN previews the untracked set and deletes nothing (works headless)" {
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    # Exactly the junk is surfaced…
    for j in .deadlink .hawtjni .junkfile .lemminx; do
        [[ "$output" == *"$j"* ]] || {
            echo "candidate missing from preview: $j"
            echo "$output"
            return 1
        }
    done
    # …and the managed / keep-listed / non-dot entries are NOT.
    ! grep -qE '(^| )\.storecode ' <<<"$output"
    ! grep -qF 'Documents' <<<"$output"
    [[ "$output" == *"dry-run"* ]]
    [[ "$output" == *"removed 4 · kept 0"* ]]
    # Nothing was actually deleted.
    [ -d "$FAKEHOME/.hawtjni" ]
    [ -L "$FAKEHOME/.deadlink" ]
    [ -f "$FAKEHOME/.junkfile" ]
}

@test "reports a clean top level when nothing is untracked" {
    local clean="$BATS_TEST_TMPDIR/clean"
    mkdir -p "$clean/.config" "$clean/.storecode"  # all managed or kept
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$clean" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
}

# ─── safety guards ───────────────────────────────────────────────────────────

@test "refuses to remove without a controlling terminal (no-TTY safety)" {
    have_tty && skip "has a controlling tty; see the confirm/remove tests instead"
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no TTY"* ]]
    # It previewed the untracked set but removed NOTHING.
    [[ "$output" == *".hawtjni"* ]]
    [ -d "$FAKEHOME/.hawtjni" ]
    [ -f "$FAKEHOME/.junkfile" ]
    [ -L "$FAKEHOME/.deadlink" ]
}

@test "refuses to touch \$HOME when the keep-list reads empty (fail-safe)" {
    : >"$KEEP_OUT"  # chezmoi execute-template yields nothing
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty keep-list"* ]]
    [ -d "$FAKEHOME/.hawtjni" ]  # nothing removed
}

@test "--help prints usage and removes nothing" {
    run_clean --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezclean"* ]]
    [[ "$output" == *"--all"* ]]
    [ -d "$FAKEHOME/.hawtjni" ]
}

@test "rejects an unknown option (exit 2, removes nothing)" {
    run_clean --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]]
    [ -d "$FAKEHOME/.hawtjni" ]
}

# ─── accept-all + interactive paths (need a controlling terminal) ────────────

@test "YES=1 removes the whole untracked set with no prompt (needs a tty)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # No stdin: YES=1 must not read any answer. A stray read would hang;
    # </dev/null proves it never reads.
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 4 · kept 0"* ]]
    for j in .deadlink .hawtjni .junkfile .lemminx; do
        [ ! -e "$FAKEHOME/$j" ] && [ ! -L "$FAKEHOME/$j" ]
    done
    # Managed + keep-listed + user data untouched.
    [ -d "$FAKEHOME/.config" ]
    [ -d "$FAKEHOME/.storecode" ]
    [ -d "$FAKEHOME/Documents" ]
}

@test "--all removes the whole set after ONE confirmation (gum)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" bash "$SCRIPT" --all <<<$'yes'
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 4 · kept 0"* ]]
    [ ! -e "$FAKEHOME/.hawtjni" ]
    [ ! -L "$FAKEHOME/.deadlink" ]
}

@test "--all aborts cleanly when the bulk confirm is declined" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" bash "$SCRIPT" --all <<<$'no'
    [ "$status" -eq 0 ]
    [[ "$output" == *"aborted"* ]]
    [ -d "$FAKEHOME/.hawtjni" ]  # nothing removed
}

@test "per-item confirm removes only the approved entries, one at a time" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # Candidates, sorted: .deadlink .hawtjni .junkfile .lemminx.
    # Answer yes / no / yes / no ⇒ remove .deadlink and .junkfile; keep the rest.
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" bash "$SCRIPT" <<<$'yes\nno\nyes\nno'
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 2 · kept 2"* ]]
    [ ! -L "$FAKEHOME/.deadlink" ]  # removed
    [ ! -e "$FAKEHOME/.junkfile" ]  # removed
    [ -d "$FAKEHOME/.hawtjni" ]     # kept (declined)
    [ -d "$FAKEHOME/.lemminx" ]     # kept (declined)
}
