#!/usr/bin/env bats
# Coverage for features/brew/migrate-work-profile.sh — the one-time v1.0 step
# that retires the `profile` key without letting a single package fall out of
# the declared set.
#
# The failure this suite exists to catch is silent and destructive: v1.0 deleted
# features/brew/Brewfile.work, so on the Mac that ran that profile its fifteen
# packages are installed and declared by nothing. Undeclared is precisely what
# `chez mirror` offers to uninstall. Every test below is ultimately one
# question — after the migration, is each of those fifteen still declared?
#
# The overlay path comes from core/testing/helper, which pins CHEZ_CONFIG_DIR
# into the test's own tmpdir. Without that these tests would read (and append
# to) the real ~/.config/chez/Brewfile.local of whoever ran them.

setup() {
    load '../../../core/testing/helper'
    skip_unless jq "jq not installed (the resolver needs it)"

    MIGRATE="$REPO_ROOT/features/brew/migrate-work-profile.sh"
    OVERLAY="$CHEZ_CONFIG_DIR/Brewfile.local"
    CONFIG="$BATS_TEST_TMPDIR/chezmoi.toml"

    cat >"$CONFIG" <<'EOF'
sourceDir = "/somewhere/src"

[data]
    name    = "Test"
    email   = "test@example.com"
    profile = "work"
    modules = ["macApps"]
EOF

    # A brew that records every call and does nothing. The migration must never
    # reach for it: "nothing is uninstalled" is the promise the whole design
    # rests on, and a stub that logs is the only way to assert an absence.
    STUBS="$BATS_TEST_TMPDIR/stubs"
    BREW_LOG="$BATS_TEST_TMPDIR/brew.log"
    stub_bin "$STUBS" brew 'printf "%s\n" "$*" >>"$BREW_LOG"; exit 0'
}

# migrate PROFILE [CONFIG] — run the real script under the stubbed PATH.
migrate() {
    run env PATH="$STUBS:$PATH" BREW_LOG="$BREW_LOG" \
        bash "$MIGRATE" "$1" "${2-$CONFIG}"
}

# The fifteen the old tier declared, as `<kind> <name>` — the same key shape
# the script compares on. Pinned here rather than derived from the script, so
# an accidental edit to that list has to be an edit to this list too.
WORK_ENTRIES=(
    'tap Azure/kubelogin'
    'tap hashicorp/tap'
    'brew azure-cli'
    'brew Azure/kubelogin/kubelogin'
    'brew hashicorp/tap/terraform'
    'brew helm'
    'brew kubectx'
    'brew kubernetes-cli'
    'brew minikube'
    'cask gcloud-cli'
    'cask intellij-idea'
    'cask intune-company-portal'
    'cask microsoft-office'
    'cask microsoft-teams'
    'cask slack'
)

# declared_keys — the overlay's declarations as `<kind> <name>`, one per line.
declared_keys() {
    sed -nE 's/^[[:space:]]*(brew|cask|tap|mas|vscode)[[:space:]]+"([^"]+)".*/\1 \2/p' \
        "$OVERLAY"
}

assert_all_declared() {
    local e keys
    keys="$(declared_keys)"
    for e in "${WORK_ENTRIES[@]}"; do
        grep -qxF "$e" <<<"$keys" || {
            printf 'not declared after the migration: %s\n' "$e" >&2
            printf '%s\n' "$keys" >&2
            return 1
        }
    done
}

# ─── The packages ────────────────────────────────────────────────────────────

@test "every work package lands in the machine-local overlay" {
    migrate work
    [ "$status" -eq 0 ]
    assert_all_declared
}

@test "the overlay declares exactly the fifteen, and nothing else" {
    # An over-broad migration is its own bug: a stray line here is a package
    # this Mac would then install on every apply and never be offered to drop.
    migrate work
    [ "$status" -eq 0 ]
    [ "$(declared_keys | wc -l | tr -d ' ')" -eq "${#WORK_ENTRIES[@]}" ]
}

@test "the migration creates the overlay when the Mac has none" {
    [ ! -e "$OVERLAY" ]
    migrate work
    [ "$status" -eq 0 ]
    [ -f "$OVERLAY" ]
}

@test "an entry the Mac already adopted is not duplicated" {
    mkdir -p "$CHEZ_CONFIG_DIR"
    printf '%s\n' 'brew "helm"' >"$OVERLAY"
    migrate work
    [ "$status" -eq 0 ]
    [ "$(grep -cF 'brew "helm"' "$OVERLAY")" -eq 1 ]
    assert_all_declared
}

@test "a re-run adds nothing at all" {
    # The hook is `run_once`, so this should never happen — but `run_once` keys
    # on a hash, and `chezmoi state delete-bucket` is a documented remedy in
    # this repo. Idempotence is what makes that remedy safe to reach for.
    migrate work
    [ "$status" -eq 0 ]
    local first
    first="$(cat "$OVERLAY")"

    printf '    profile = "work"\n' >>"$CONFIG"
    migrate work
    [ "$status" -eq 0 ]
    [ "$(cat "$OVERLAY")" = "$first" ]
}

@test "a re-run does not re-append the section headings either" {
    migrate work
    printf '    profile = "work"\n' >>"$CONFIG"
    migrate work
    [ "$(grep -cF 'Cloud / Kubernetes / IaC' "$OVERLAY")" -eq 1 ]
    [ "$(grep -cF 'Work apps' "$OVERLAY")" -eq 1 ]
}

@test "nothing is installed and nothing is uninstalled" {
    migrate work
    [ "$status" -eq 0 ]
    [ ! -s "$BREW_LOG" ]
}

@test "a Mac on any other profile keeps its overlay untouched" {
    migrate personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to move"* ]] || return 1
    # Seeding the overlay is the brew-bundle hook's job; the migration has no
    # business creating one on a Mac with no work packages to put in it.
    [ ! -e "$OVERLAY" ]
}

# ─── The config key ──────────────────────────────────────────────────────────

@test "the retired profile key is removed" {
    migrate work
    [ "$status" -eq 0 ]
    no_match '^[[:space:]]*profile[[:space:]]*=' "$CONFIG"
}

@test "the key is removed on every profile, not just work" {
    migrate personal
    [ "$status" -eq 0 ]
    no_match '^[[:space:]]*profile[[:space:]]*=' "$CONFIG"
}

@test "every other answer in the config survives" {
    # Line surgery, not a re-init: `chezmoi init` would re-derive the lot, and
    # a wizard answer silently reset to its default is the quiet way to lose
    # someone's signing key.
    migrate work
    [ "$status" -eq 0 ]
    grep -qF 'name    = "Test"' "$CONFIG"
    grep -qF 'email   = "test@example.com"' "$CONFIG"
    grep -qF 'modules = ["macApps"]' "$CONFIG"
    grep -qF 'sourceDir = "/somewhere/src"' "$CONFIG"
}

@test "a config with no profile line is left byte-for-byte alone" {
    grep -vE '^[[:space:]]*profile[[:space:]]*=' "$CONFIG" >"$CONFIG.clean"
    mv "$CONFIG.clean" "$CONFIG"
    local before
    before="$(cat "$CONFIG")"
    migrate ""
    [ "$status" -eq 0 ]
    [ "$(cat "$CONFIG")" = "$before" ]
}

@test "no temp file is left behind" {
    migrate work
    [ ! -e "$CONFIG.retire-profile.tmp" ]
}

@test "a missing config file is a warning, not a failure" {
    # The hook runs `before`, so on a fresh Mac the config may not be where the
    # template said it would be. Failing there would abort the apply.
    migrate work "$BATS_TEST_TMPDIR/not-a-config.toml"
    [ "$status" -eq 0 ]
    assert_all_declared
}

@test "an unwritable config fails loudly and keeps the key" {
    [ "$(id -u)" -ne 0 ] || skip "running as root; every file is writable"
    chmod 444 "$CONFIG"
    migrate work
    chmod 644 "$CONFIG"
    [ "$status" -eq 1 ]
    grep -qE '^[[:space:]]*profile[[:space:]]*=' "$CONFIG"
    # Failing with the key still in place is the safe half: the resolver
    # refuses to produce a removal set while it is there.
    [[ "$output" == *"by hand"* ]] || return 1
}

# ─── The point of the whole exercise ─────────────────────────────────────────

@test "after migrating, the resolver stops refusing and counts the overlay" {
    migrate work
    [ "$status" -eq 0 ]
    run bash -c ". '$REPO_ROOT/features/brew/lib/tiers.sh'; brew_active_files \"\$1\"" _ \
        '{"modules":[],"brewfiles":{"core":"features/brew/Brewfile"}}'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${lines[1]}" = "$OVERLAY" ]
}

@test "after migrating, not one work package reads as untracked" {
    # The end-to-end assertion, and the only one that matters on the day: run
    # the migration, then ask the same question `chez mirror` asks.
    migrate work
    [ "$status" -eq 0 ]

    # Installed names as `brew leaves` prints them: tap-qualified and lowercased
    # even where the Brewfile spells the owner with a capital.
    local formulae casks
    formulae="$(printf '%s\n' azure-cli azure/kubelogin/kubelogin \
        hashicorp/tap/terraform helm kubectx kubernetes-cli minikube)"
    casks="$(printf '%s\n' gcloud-cli intellij-idea intune-company-portal \
        microsoft-office microsoft-teams slack)"

    run bash -c ". '$REPO_ROOT/features/brew/lib/tiers.sh'
        brew_untracked_of_kind brew \"\$1\" \"\$2\"" _ "$formulae" "$OVERLAY"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run bash -c ". '$REPO_ROOT/features/brew/lib/tiers.sh'
        brew_untracked_of_kind cask \"\$1\" \"\$2\"" _ "$casks" "$OVERLAY"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
