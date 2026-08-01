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
    OWNERS_OUT="$STUBS/owners.out"
    BREW_FORMULAE_OUT="$STUBS/brew-formulae.out"
    BREW_CASKS_OUT="$STUBS/brew-casks.out"
    # chezmoi managed lists target-relative paths; only the first "." segment
    # matters. Include a subpath (.config/nvim → .config) and a non-dot Library
    # path (dropped) to prove the parser.
    printf '%s\n' '.config' '.config/nvim' '.zshenv' '.ssh' 'Library/Application Support/x' >"$MANAGED_OUT"
    printf '%s\n' '.storecode' '.cache' '.config' '.ssh' >"$KEEP_OUT"
    # Tool-ownership map: entry<TAB>package<TAB>binary. .m2 has an EMPTY package
    # (Maven comes from mise, not brew) — the literal tab<tab> must survive parsing
    # or the binary "mvn" would be lost, so build the rows with real tabs.
    printf '%s\t%s\t%s\n' \
        '.azure' 'azure-cli' 'az' \
        '.kube' 'kubernetes-cli' 'kubectl' \
        '.m2' '' 'mvn' \
        '.vscode' 'visual-studio-code' 'code' >"$OWNERS_OUT"
    # Installed brew set: kubernetes-cli present (keeps .kube via its package); NO
    # maven (so .m2 can only be kept via its binary, proving brew-only would misfire);
    # visual-studio-code cask absent (so .vscode is an orphan unless `code` is on PATH).
    printf '%s\n' 'kubernetes-cli' 'git' >"$BREW_FORMULAE_OUT"
    printf '%s\n' 'some-cask' >"$BREW_CASKS_OUT"

    # Stub chezmoi: `managed`, and `execute-template` disambiguated by the template
    # body — keepHome and owners both go through execute-template.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    managed) cat "$MANAGED_OUT" 2>/dev/null ;;
    execute-template)
        case "\$2" in
            *keepHome*) cat "$KEEP_OUT" 2>/dev/null ;;
            *owners*) cat "$OWNERS_OUT" 2>/dev/null ;;
        esac
        ;;
    *) exit 0 ;;
esac
EOF

    # Stub brew like chezmirror.bats: list --formula / --cask cat canned files.
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
case "\$2" in
    --formula) cat "$BREW_FORMULAE_OUT" 2>/dev/null ;;
    --cask) cat "$BREW_CASKS_OUT" 2>/dev/null ;;
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

    # Minimal tool stubs so a candidate's binary/stem can be "installed" on a
    # restricted PATH: mvn = Maven from mise (keeps .m2), gradle = the stem heuristic.
    for b in mvn gradle; do
        printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/$b"
    done

    chmod +x "$STUBS/chezmoi" "$STUBS/brew" "$STUBS/gum" "$STUBS/mvn" "$STUBS/gradle"

    # Hermetic PATH for the tool-ownership tests: stubs + coreutils only, so real
    # az/kubectl/code on the host can't leak in and flip an "orphan" into a "keep".
    SYSPATH="$STUBS:/usr/bin:/bin"
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

# ─── tool-ownership classification (pure units) ──────────────────────────────
# _clean_classify OWNERS BREWSET BINSET reads candidate entries on stdin and
# emits "entry<TAB>verdict<TAB>label". It's pure: the three lists stand in for
# the map / installed-brew / on-PATH probes, so verdicts are fully deterministic.

@test "_clean_classify keeps a mapped entry whose brew package is installed" {
    run bash -c 'source "$1"; printf "%s\n" ".kube" | _clean_classify "$2" "$3" "$4"' \
        _ "$SCRIPT" $'.kube\tkubernetes-cli\tkubectl' $'kubernetes-cli' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.kube\tkeep\tkubernetes-cli' ]
}

@test "_clean_classify keeps a mapped entry via its binary even when brew lacks it" {
    # .m2's package is empty (Maven from mise); only the binary "mvn" can save it.
    # A brew-only check (empty BREWSET) would wrongly offer it — this pins the fix.
    run bash -c 'source "$1"; printf "%s\n" ".m2" | _clean_classify "$2" "$3" "$4"' \
        _ "$SCRIPT" $'.m2\t\tmvn' '' $'mvn'
    [ "$status" -eq 0 ]
    [ "$output" = $'.m2\tkeep\tmvn' ]
}

@test "_clean_classify marks a mapped entry orphan when neither package nor binary is present" {
    run bash -c 'source "$1"; printf "%s\n" ".azure" | _clean_classify "$2" "$3" "$4"' \
        _ "$SCRIPT" $'.azure\tazure-cli\taz' '' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.azure\torphan\tazure-cli' ]
}

@test "_clean_classify keeps an unmapped entry by the stem heuristic (first-dot cut)" {
    # .terraform.d → stem "terraform" (cut at the FIRST dot), .gradle → "gradle".
    run bash -c 'source "$1"; printf "%s\n" "$2" | _clean_classify "$3" "$4" "$5"' \
        _ "$SCRIPT" $'.gradle\n.terraform.d' '' '' $'gradle\nterraform'
    [ "$status" -eq 0 ]
    [ "$output" = $'.gradle\tkeep\tgradle\n.terraform.d\tkeep\tterraform' ]
}

@test "_clean_classify marks an unmapped, unknown entry as unknown (empty label)" {
    run bash -c 'source "$1"; printf "%s\n" ".hawtjni" | _clean_classify "" "" ""' \
        _ "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == $'.hawtjni\tunknown'* ]]
}

@test "_clean_stems strips the leading dot and cuts at the first remaining dot" {
    run bash -c 'source "$1"; printf "%s\n" "$2" | _clean_stems' \
        _ "$SCRIPT" $'.terraform.d\n.m2\n.claude\n.testcontainers.properties'
    [ "$status" -eq 0 ]
    [ "$output" = $'terraform\nm2\nclaude\ntestcontainers' ]
}

@test "_clean_owner_binaries yields each non-empty binary, incl. an empty-package row" {
    # The .m2 row (empty package) must still surface "mvn": proves the tab-tab
    # parse doesn't collapse the middle field.
    local owners=$'.azure\tazure-cli\taz\n.kube\tkubernetes-cli\tkubectl\n.m2\t\tmvn\n.vscode\tvisual-studio-code\tcode'
    run bash -c 'source "$1"; _clean_owner_binaries "$2"' _ "$SCRIPT" "$owners"
    [ "$status" -eq 0 ]
    [ "$output" = $'az\nkubectl\nmvn\ncode' ]
}

@test "_clean_present_bins emits only commands on PATH, sorted-unique" {
    local d="$BATS_TEST_TMPDIR/bins"
    mkdir -p "$d"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$d/mvn"
    chmod +x "$d/mvn"
    run env PATH="$d:/usr/bin:/bin" bash -c 'source "$1"; printf "%s\n" "$2" | _clean_present_bins' \
        _ "$SCRIPT" $'mvn\nbogus-xyz-absent\nmvn'
    [ "$status" -eq 0 ]
    [ "$output" = "mvn" ]  # present + deduped; the absent one dropped
}

# ─── tool-ownership integration (DRY_RUN, hermetic PATH) ─────────────────────
# These use $SYSPATH (stubs + coreutils only) so host-installed tools can't flip
# a verdict, and their own target dir so the shared FAKEHOME tests stay intact.

@test "keeps config owned by an installed brew package (.kube not offered)" {
    local t="$BATS_TEST_TMPDIR/kube"
    mkdir -p "$t/.kube" "$t/.hawtjni"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"kept 1 untracked entr"* ]]
    [[ "$output" == *"owned by installed tooling"* ]]
    [[ "$output" != *".kube"* ]]            # never surfaced without -v
    [[ "$output" == *".hawtjni"* ]]         # the orphan-less junk still offered
    [[ "$output" == *"removed 1 · kept 0"* ]]
    # -v names it and its owning package.
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".kube (kept — kubernetes-cli installed)"* ]]
}

@test "keeps config owned by a PATH binary from mise even when brew lacks it (.m2 via mvn)" {
    local t="$BATS_TEST_TMPDIR/m2"
    mkdir -p "$t/.m2" "$t/.hawtjni"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    # brew canned files omit maven, so this can only be the binary check.
    [[ "$output" == *".m2 (kept — mvn installed)"* ]]
    [[ "$output" != *"rm -rf $t/.m2"* ]]    # never scheduled for removal
    [[ "$output" == *".hawtjni"* ]]
}

@test "offers an orphan whose tool is gone, annotated with the package (.azure)" {
    local t="$BATS_TEST_TMPDIR/az"
    mkdir -p "$t/.azure"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".azure (dir) — orphan · config for azure-cli, not installed"* ]]
    [[ "$output" == *"removed 1 · kept 0"* ]]
}

@test "keeps a tool matched only by the stem heuristic (.gradle → gradle on PATH)" {
    local t="$BATS_TEST_TMPDIR/gr"
    mkdir -p "$t/.gradle" "$t/.hawtjni"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".gradle (kept — gradle installed)"* ]]
    [[ "$output" != *"rm -rf $t/.gradle"* ]]
}

@test "degrades gracefully when brew is absent — still classifies via binaries" {
    # A brew-less machine: no `brew` on PATH. .kube loses its (brew) owner and
    # becomes an orphan; .m2 is still kept by its binary. Must not error.
    local nb="$BATS_TEST_TMPDIR/nobrew"
    mkdir -p "$nb"
    cp "$STUBS/chezmoi" "$STUBS/mvn" "$nb/"
    chmod +x "$nb/chezmoi" "$nb/mvn"
    local t="$BATS_TEST_TMPDIR/nb-home"
    mkdir -p "$t/.kube" "$t/.m2" "$t/.hawtjni"
    run env PATH="$nb:/usr/bin:/bin" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".m2 (kept — mvn installed)"* ]]           # binary check survives
    [[ "$output" == *".kube (dir) — orphan · config for kubernetes-cli, not installed"* ]]
}
