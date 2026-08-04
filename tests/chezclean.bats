#!/usr/bin/env bats
# Tests for clean.sh (chezclean): reconciles untracked dotfiles across $HOME's
# top level and ~/.config to what chezmoi manages, removing only what's
# confirmed. Candidates = entries minus managed minus keep-list; a drift there
# could offer auth/state dirs for deletion, so these tests pin that computation
# plus the safety guards (no removal without confirm, nothing without a tty).
#
# Interactive/removing tests need a controlling terminal and are inverse-gated
# from the headless safety/dry-run tests. Run the full set locally with:
#     script -q /dev/null bats tests/chezclean.bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/bin/clean.sh"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"
    [ -x "$SCRIPT" ] || skip "clean.sh missing or not executable"

    # Fake $HOME mixing managed dirs, keep-listed dirs, and junk; candidates
    # must be exactly the junk.
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

    # Stub chezmoi: managed/execute-template read from files so tests can
    # rewrite them (e.g. force an empty keep-list).
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    MANAGED_OUT="$STUBS/managed.out"
    KEEP_OUT="$STUBS/keep.out"
    KEEPCONFIG_OUT="$STUBS/keepconfig.out"
    OWNERS_OUT="$STUBS/owners.out"
    BREW_FORMULAE_OUT="$STUBS/brew-formulae.out"
    BREW_CASKS_OUT="$STUBS/brew-casks.out"
    VSCODE_OUT="$STUBS/vscode-extensions.out"
    # managed lists target-relative paths; only the first segment matters
    # (.config/nvim → .config); the Library path has no leading dot, dropped.
    printf '%s\n' '.config' '.config/nvim' '.zshenv' '.ssh' 'Library/Application Support/x' >"$MANAGED_OUT"
    printf '%s\n' '.storecode' '.cache' '.config' '.ssh' >"$KEEP_OUT"
    # keepConfig (scope 2): auth/state dirs under ~/.config never offered for removal.
    printf '%s\n' 'gh' 'op' >"$KEEPCONFIG_OUT"
    # owners map: entry<TAB>package<TAB>binary<TAB>extension. .m2 has an empty
    # package (mise); .sonarlint/.codetogether have only an extension — the
    # literal tabs must survive parsing or those fields would be lost.
    printf '%s\t%s\t%s\t%s\n' \
        '.azure' 'azure-cli' 'az' '' \
        '.kube' 'kubernetes-cli' 'kubectl' '' \
        '.m2' '' 'mvn' '' \
        '.vscode' 'visual-studio-code' 'code' '' \
        '.sonarlint' '' '' 'sonarsource.sonarlint-vscode' \
        '.codetogether' '' '' 'genuitecllc.codetogether' >"$OWNERS_OUT"
    # kubernetes-cli installed (keeps .kube via package); no maven (so .m2 can
    # only be kept via its binary); no vscode cask (so .vscode is an orphan
    # unless `code` is on PATH).
    printf '%s\n' 'kubernetes-cli' 'git' >"$BREW_FORMULAE_OUT"
    printf '%s\n' 'some-cask' >"$BREW_CASKS_OUT"
    # sonarlint-vscode installed (keeps .sonarlint); codetogether absent (orphan).
    printf '%s\n' 'sonarsource.sonarlint-vscode' 'ms-python.python' >"$VSCODE_OUT"

    # execute-template disambiguated by template body — keepHome and owners
    # both go through it.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    managed) cat "$MANAGED_OUT" 2>/dev/null ;;
    execute-template)
        case "\$2" in
            *keepHome*) cat "$KEEP_OUT" 2>/dev/null ;;
            *keepConfig*) cat "$KEEPCONFIG_OUT" 2>/dev/null ;;
            *owners*) cat "$OWNERS_OUT" 2>/dev/null ;;
        esac
        ;;
    *) exit 0 ;;
esac
EOF

    # brew stub like chezmirror.bats: list --formula / --cask cat canned files.
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
case "\$2" in
    --formula) cat "$BREW_FORMULAE_OUT" 2>/dev/null ;;
    --cask) cat "$BREW_CASKS_OUT" 2>/dev/null ;;
esac
EOF

    # code stub: _clean_installed_vscode calls it directly, not via chezmoi.
    cat >"$STUBS/code" <<EOF
#!/usr/bin/env bash
[ "\$1" = --list-extensions ] && cat "$VSCODE_OUT" 2>/dev/null
EOF

    # stub mirrors real `gum confirm` (reads STDIN): one answer line per confirm.
    cat >"$STUBS/gum" <<'EOF'
#!/usr/bin/env bash
[ "$1" = confirm ] || exit 0
IFS= read -r ans || ans=""
[ "$ans" = yes ]
EOF

    # mvn/gradle stubs so their binary/stem reads as installed on a restricted PATH.
    for b in mvn gradle; do
        printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/$b"
    done

    chmod +x "$STUBS/chezmoi" "$STUBS/brew" "$STUBS/code" "$STUBS/gum" "$STUBS/mvn" "$STUBS/gradle"

    # Hermetic PATH for tool-ownership tests: stubs + curated coreutils only.
    # /usr/bin is NOT safe here — GitHub's ubuntu runners ship az/kubectl there,
    # which would flip the .azure/.kube orphan tests to "kept" on CI. Symlink
    # only the utilities clean.sh needs so nothing else on the host leaks in.
    COREBIN="$BATS_TEST_TMPDIR/corebin"
    mkdir -p "$COREBIN"
    local _u _p
    for _u in bash sh env dirname basename sed grep sort awk tr cat rm ln mkdir cut head tail; do
        _p="$(command -v "$_u" 2>/dev/null)" && ln -sf "$_p" "$COREBIN/$_u"
    done
    SYSPATH="$STUBS:$COREBIN"
}

# Mirrors clean.sh's own tty guard, for the tty-gated tests below.
have_tty() { { : </dev/tty; } >/dev/null 2>&1; }

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
    # .config deduped from two entries; Library/* dropped (no leading dot).
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
    for j in .deadlink .hawtjni .junkfile .lemminx; do
        [[ "$output" == *"$j"* ]] || {
            echo "candidate missing from preview: $j"
            echo "$output"
            return 1
        }
    done
    ! grep -qE '(^| )\.storecode ' <<<"$output"
    ! grep -qF 'Documents' <<<"$output"
    [[ "$output" == *"dry-run"* ]]
    [[ "$output" == *"removed 4 · kept 0"* ]]
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
    # YES=1 must never read stdin — a stray read would hang; </dev/null proves it.
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 4 · kept 0"* ]]
    for j in .deadlink .hawtjni .junkfile .lemminx; do
        [ ! -e "$FAKEHOME/$j" ] && [ ! -L "$FAKEHOME/$j" ]
    done
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
    # yes/no/yes/no over sorted candidates (.deadlink .hawtjni .junkfile .lemminx)
    # removes the first and third.
    run env PATH="$STUBS:$PATH" CHEZCLEAN_TARGET="$FAKEHOME" bash "$SCRIPT" <<<$'yes\nno\nyes\nno'
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 2 · kept 2"* ]]
    [ ! -L "$FAKEHOME/.deadlink" ]  # removed
    [ ! -e "$FAKEHOME/.junkfile" ]  # removed
    [ -d "$FAKEHOME/.hawtjni" ]     # kept (declined)
    [ -d "$FAKEHOME/.lemminx" ]     # kept (declined)
}

# ─── tool-ownership classification (pure units) ──────────────────────────────
# _clean_classify OWNERS BREWSET BINSET EXTSET reads candidates on stdin, emits
# "entry<TAB>verdict<TAB>label". Pure: the four lists stand in for the real
# probes, so verdicts are deterministic. Owner rows are 4-field.

@test "_clean_classify keeps a mapped entry whose brew package is installed" {
    run bash -c 'source "$1"; printf "%s\n" ".kube" | _clean_classify "$2" "$3" "$4" "$5"' \
        _ "$SCRIPT" $'.kube\tkubernetes-cli\tkubectl\t' $'kubernetes-cli' '' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.kube\tkeep\tkubernetes-cli' ]
}

@test "_clean_classify keeps a mapped entry via its binary even when brew lacks it" {
    # .m2's package is empty (mise); only its binary "mvn" can save it — pins
    # the brew-only-check bug.
    run bash -c 'source "$1"; printf "%s\n" ".m2" | _clean_classify "$2" "$3" "$4" "$5"' \
        _ "$SCRIPT" $'.m2\t\tmvn\t' '' $'mvn' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.m2\tkeep\tmvn' ]
}

@test "_clean_classify keeps an extension-owned entry when its extension is installed" {
    # .sonarlint is owned only by an extension (empty package+binary); also
    # proves empty middle tab fields don't shift it into the wrong slot.
    run bash -c 'source "$1"; printf "%s\n" ".sonarlint" | _clean_classify "$2" "$3" "$4" "$5"' \
        _ "$SCRIPT" $'.sonarlint\t\t\tsonarsource.sonarlint-vscode' '' '' $'sonarsource.sonarlint-vscode'
    [ "$status" -eq 0 ]
    [ "$output" = $'.sonarlint\tkeep\tsonarsource.sonarlint-vscode' ]
}

@test "_clean_classify marks a mapped entry orphan when neither package nor binary is present" {
    run bash -c 'source "$1"; printf "%s\n" ".azure" | _clean_classify "$2" "$3" "$4" "$5"' \
        _ "$SCRIPT" $'.azure\tazure-cli\taz\t' '' '' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.azure\torphan\tazure-cli' ]
}

@test "_clean_classify marks an extension-owned entry orphan when its extension is gone" {
    # Extension gone ⇒ its HOME dir surfaces as removable, labelled by extension ID.
    run bash -c 'source "$1"; printf "%s\n" ".sonarlint" | _clean_classify "$2" "$3" "$4" "$5"' \
        _ "$SCRIPT" $'.sonarlint\t\t\tsonarsource.sonarlint-vscode' '' '' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.sonarlint\torphan\tsonarsource.sonarlint-vscode' ]
}

@test "_clean_classify keeps an unmapped entry by the stem heuristic (first-dot cut)" {
    # stem cut at the FIRST dot: .terraform.d → terraform, .gradle → gradle.
    run bash -c 'source "$1"; printf "%s\n" "$2" | _clean_classify "$3" "$4" "$5" "$6"' \
        _ "$SCRIPT" $'.gradle\n.terraform.d' '' '' $'gradle\nterraform' ''
    [ "$status" -eq 0 ]
    [ "$output" = $'.gradle\tkeep\tgradle\n.terraform.d\tkeep\tterraform' ]
}

@test "_clean_classify marks an unmapped, unknown entry as unknown (empty label)" {
    run bash -c 'source "$1"; printf "%s\n" ".hawtjni" | _clean_classify "" "" "" ""' \
        _ "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == $'.hawtjni\tunknown'* ]]
}

@test "_clean_installed_vscode lists extensions lowercased + sorted, empty when code absent" {
    local d="$BATS_TEST_TMPDIR/vsc"
    mkdir -p "$d"
    # A `code` that lists mixed-case, unsorted IDs.
    cat >"$d/code" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --list-extensions ] && printf '%s\n' 'Zeta.One' 'alpha.Two'
EOF
    chmod +x "$d/code"
    run env PATH="$d:$COREBIN" bash -c 'source "$1"; _clean_installed_vscode' _ "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = $'alpha.two\nzeta.one' ]
    # No `code` on PATH ⇒ empty output, rc 0 (graceful degradation, like brew).
    run env PATH="$COREBIN" bash -c 'source "$1"; _clean_installed_vscode' _ "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_clean_stems strips the leading dot and cuts at the first remaining dot" {
    run bash -c 'source "$1"; printf "%s\n" "$2" | _clean_stems' \
        _ "$SCRIPT" $'.terraform.d\n.m2\n.claude\n.testcontainers.properties'
    [ "$status" -eq 0 ]
    [ "$output" = $'terraform\nm2\nclaude\ntestcontainers' ]
}

@test "_clean_owner_binaries yields each non-empty binary, incl. empty-package and extension-only rows" {
    # .m2 (empty package) must surface "mvn"; extension-only .sonarlint must
    # surface nothing — proves the 4-field tab parse doesn't collapse fields.
    local owners=$'.azure\tazure-cli\taz\t\n.kube\tkubernetes-cli\tkubectl\t\n.m2\t\tmvn\t\n.sonarlint\t\t\tsonarsource.sonarlint-vscode\n.vscode\tvisual-studio-code\tcode\t'
    run bash -c 'source "$1"; _clean_owner_binaries "$2"' _ "$SCRIPT" "$owners"
    [ "$status" -eq 0 ]
    [ "$output" = $'az\nkubectl\nmvn\ncode' ]
}

@test "_clean_present_bins emits only commands on PATH, sorted-unique" {
    local d="$BATS_TEST_TMPDIR/bins"
    mkdir -p "$d"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$d/mvn"
    chmod +x "$d/mvn"
    run env PATH="$d:$COREBIN" bash -c 'source "$1"; printf "%s\n" "$2" | _clean_present_bins' \
        _ "$SCRIPT" $'mvn\nbogus-xyz-absent\nmvn'
    [ "$status" -eq 0 ]
    [ "$output" = "mvn" ]  # present + deduped; the absent one dropped
}

# ─── tool-ownership integration (DRY_RUN, hermetic PATH) ─────────────────────
# $SYSPATH (stubs + coreutils only) so host tools can't flip a verdict; own
# target dir so the shared FAKEHOME tests stay intact.

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
    # No brew on PATH: .kube loses its brew owner (orphan), .m2 still kept via binary.
    local nb="$BATS_TEST_TMPDIR/nobrew"
    mkdir -p "$nb"
    cp "$STUBS/chezmoi" "$STUBS/mvn" "$nb/"
    chmod +x "$nb/chezmoi" "$nb/mvn"
    local t="$BATS_TEST_TMPDIR/nb-home"
    mkdir -p "$t/.kube" "$t/.m2" "$t/.hawtjni"
    run env PATH="$nb:$COREBIN" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".m2 (kept — mvn installed)"* ]]           # binary check survives
    [[ "$output" == *".kube (dir) — orphan · config for kubernetes-cli, not installed"* ]]
}

# ─── VS Code extension ownership (DRY_RUN, hermetic PATH) ─────────────────────
# The `code` stub on $SYSPATH reports sonarsource.sonarlint-vscode installed and
# genuitecllc.codetogether absent, so .sonarlint is kept and .codetogether orphans.

@test "keeps config owned by an installed VS Code extension (.sonarlint not offered)" {
    local t="$BATS_TEST_TMPDIR/sonar"
    mkdir -p "$t/.sonarlint" "$t/.hawtjni"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"kept 1 untracked entr"* ]]
    [[ "$output" == *"owned by installed tooling"* ]]
    [[ "$output" != *".sonarlint (dir)"* ]]   # never surfaced without -v
    [[ "$output" == *".hawtjni"* ]]           # the ownerless junk still offered
    [[ "$output" == *"removed 1 · kept 0"* ]]
    # -v names it and its owning extension.
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".sonarlint (kept — sonarsource.sonarlint-vscode installed)"* ]]
}

@test "offers an extension-owned dir as an orphan when its extension is gone (.codetogether)" {
    local t="$BATS_TEST_TMPDIR/ct"
    mkdir -p "$t/.codetogether"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".codetogether (dir) — orphan · config for genuitecllc.codetogether, not installed"* ]]
    [[ "$output" == *"removed 1 · kept 0"* ]]
}

# ─── scope 2: ~/.config reconciliation (DRY_RUN, hermetic PATH) ───────────────
# ~/.config is a normal dot_config dir (not exact_), so an apply never prunes
# it — this second scope does. keepConfig (gh, op) is the auth/state keep-list.

@test "scope 2: offers an untracked ~/.config child, spares keepConfig and managed children" {
    local t="$BATS_TEST_TMPDIR/cfg"
    mkdir -p "$t/.config/gh" "$t/.config/nvim" "$t/.config/randomcfg"
    ln -s "$t/.config/nowhere" "$t/.config/deadcfg"  # dangling — cruft, must be offered
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".config/randomcfg (dir) — untracked"* ]]
    [[ "$output" == *".config/deadcfg (symlink) — untracked"* ]]
    [[ "$output" != *".config/gh"* ]]    # keepConfig-spared, never surfaced
    [[ "$output" != *".config/nvim"* ]]  # chezmoi-managed, never surfaced
    [[ "$output" == *"removed 2 · kept 0"* ]]
}

@test "scope 2: keeps a ~/.config child whose tool is on PATH (stem heuristic)" {
    local t="$BATS_TEST_TMPDIR/cfg2"
    mkdir -p "$t/.config/gradle" "$t/.config/randomcfg"  # gradle stub is on $SYSPATH
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" -v </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".config/gradle (kept — gradle installed)"* ]]  # stem "gradle" on PATH
    [[ "$output" != *".config/gradle (dir) —"* ]]                    # never offered
    [[ "$output" == *".config/randomcfg"* ]]                         # the ownerless junk offered
    [[ "$output" == *"removed 1 · kept 0"* ]]
}

@test "scope 2: empty keepConfig skips ~/.config (refusal) but still reconciles \$HOME" {
    : >"$KEEPCONFIG_OUT"  # chezmoi execute-template yields nothing for keepConfig
    local t="$BATS_TEST_TMPDIR/cfg3"
    mkdir -p "$t/.config/junkcfg" "$t/.junktop"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping ~/.config"* ]]
    [[ "$output" == *"empty keep-list"* ]]
    [[ "$output" != *".config/junkcfg"* ]]  # ~/.config never reconciled
    [[ "$output" == *".junktop"* ]]          # scope 1 (keepHome) still runs
    [[ "$output" == *"removed 1 · kept 0"* ]]
    [ -d "$t/.config/junkcfg" ]              # untouched
}

@test "scope 2: YES=1 removes an untracked ~/.config child, spares keepConfig (needs a tty)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    local t="$BATS_TEST_TMPDIR/cfg4"
    mkdir -p "$t/.config/junkcfg" "$t/.config/gh"
    run env PATH="$SYSPATH" CHEZCLEAN_TARGET="$t" YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 1 · kept 0"* ]]
    [ ! -e "$t/.config/junkcfg" ]  # removed
    [ -d "$t/.config/gh" ]         # keepConfig-spared, untouched
}
