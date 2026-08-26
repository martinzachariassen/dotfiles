#!/usr/bin/env bats
# Coverage for scripts/lib/modules.sh — the single answer to "which modules has
# THIS Mac been offered, and how is that list written back?", shared by chezup's
# new-module gate, and by `chezdistill --setup` when it enables claudeDistiller.
#
# The distinction the whole feature rests on is `unseen` vs `not enabled`: a
# module the user declined must never be offered again, so being asked about is
# recorded separately from being turned on.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LIB="$REPO_ROOT/scripts/lib/modules.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed (modules.sh needs it)"

    # Mirrors the shape of `chezmoi data`: a catalog of four, two enabled, one
    # of the remaining two already offered and declined.
    DATA='{"modules":["macApps","theme"],"modulesSeen":["macApps","theme","locale"],
        "moduleCatalog":{"macApps":"GUI and AI apps","theme":"Catppuccin Mocha",
        "locale":"Norwegian locale","claudeDistiller":"Nightly distillation"}}'

    CFG="$BATS_TEST_TMPDIR/chezmoi.toml"
    cat >"$CFG" <<'EOF'
sourceDir = "/repo"

[data]
    name        = "Test"
    profile     = "work"
    modules     = ["macApps", "theme"]
    modulesSeen = ["macApps", "theme", "locale"]
EOF
}

lib() { # lib EXPR — run an expression against the sourced library
    run bash -c ". '$LIB'; $1"
}

# A bare `! grep …` mid-body is exempt from set -e, so bats never sees it fail.
no_match_in() {
    if grep -qE "$2" <<<"$1"; then
        echo "unexpected match for: $2"
        return 1
    fi
}

# ── Reading ──────────────────────────────────────────────────────────────────

@test "modules_unseen is the catalog minus enabled minus seen" {
    lib "modules_unseen '$DATA'"
    [ "$status" -eq 0 ]
    [ "$output" = "claudeDistiller" ]
}

@test "modules_unseen excludes a module that was declined, not just installed" {
    # locale is in modulesSeen and NOT in modules — offered once, said no.
    # Re-offering it every run is the failure this key exists to prevent.
    lib "modules_unseen '$DATA'"
    no_match_in "$output" '^locale$'
}

@test "modules_unseen treats an absent modulesSeen as nothing seen" {
    # A config written before the key existed: everything not enabled is new.
    lib "modules_unseen '$(jq -c 'del(.modulesSeen)' <<<"$DATA")'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "claudeDistiller" ]
    [ "${lines[1]}" = "locale" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "modules_unseen is empty when the catalog holds nothing new" {
    lib "modules_unseen '$(jq -c '.modulesSeen += ["claudeDistiller"]' <<<"$DATA")'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "modules_unseen yields nothing for data with no catalog" {
    # Fail closed: an unresolvable catalog must offer nothing, never everything.
    lib "modules_unseen '{}'"
    [ -z "$output" ]
}

@test "modules_label reads the catalog description" {
    lib "modules_label '$DATA' claudeDistiller"
    [ "$output" = "Nightly distillation" ]
}

@test "modules_label is empty for a module with no catalog entry" {
    lib "modules_label '$DATA' nosuchmodule"
    [ -z "$output" ]
}

@test "modules_enabled and modules_seen read their own keys" {
    lib "modules_enabled '$DATA' | tr '\n' ' '"
    [ "$output" = "macApps theme " ]
    lib "modules_seen '$DATA' | tr '\n' ' '"
    [ "$output" = "macApps theme locale " ]
}

# ── Array rendering ──────────────────────────────────────────────────────────

@test "modules_toml_array matches what the config template renders" {
    # Byte-identical to .chezmoi.toml.tmpl's `[{{ range }}…]`, so a line written
    # here and a later `chezmoi init` don't fight over formatting.
    lib "modules_toml_array a b c"
    [ "$output" = '["a", "b", "c"]' ]
}

@test "modules_toml_array renders an empty list" {
    lib "modules_toml_array"
    [ "$output" = '[]' ]
}

@test "modules_toml_array drops duplicates" {
    # Callers append to whatever is saved, so the same module can arrive twice.
    lib "modules_toml_array macApps theme macApps"
    [ "$output" = '["macApps", "theme"]' ]
}

# ── Writing ──────────────────────────────────────────────────────────────────

@test "modules_write_list rewrites an existing line and nothing else" {
    lib "modules_write_list '$CFG' modules macApps theme claudeDistiller"
    [ "$status" -eq 0 ]
    grep -qF '    modules     = ["macApps", "theme", "claudeDistiller"]' "$CFG"
    # Alignment and every neighbouring line survive untouched.
    grep -qF '    modulesSeen = ["macApps", "theme", "locale"]' "$CFG"
    grep -qF '    profile     = "work"' "$CFG"
    [ "$(grep -c . "$CFG")" -eq 6 ]
}

@test "modules_write_list leaves no temp file behind" {
    lib "modules_write_list '$CFG' modules macApps"
    [ ! -e "$CFG.modules.tmp" ]
}

@test "modules_write_list inserts a missing key after the modules line" {
    # The upgrade path: a config generated before modulesSeen existed.
    grep -v modulesSeen "$CFG" >"$CFG.trimmed" && mv "$CFG.trimmed" "$CFG"
    lib "modules_write_list '$CFG' modulesSeen macApps claudeDistiller"
    [ "$status" -eq 0 ]
    grep -qF 'modulesSeen = ["macApps", "claudeDistiller"]' "$CFG"
    # Directly after `modules`, so the generated block keeps its shape.
    at_modules="$(grep -n -E '^[[:space:]]*modules[[:space:]]*=' "$CFG" | cut -d: -f1)"
    at_seen="$(grep -n -E '^[[:space:]]*modulesSeen[[:space:]]*=' "$CFG" | cut -d: -f1)"
    [ "$at_seen" -eq "$((at_modules + 1))" ]
}

@test "modules_write_list turns an empty list into a populated one" {
    printf 'sourceDir = "/repo"\n\n[data]\n    modules     = []\n' >"$CFG"
    lib "modules_write_list '$CFG' modules claudeDistiller"
    [ "$status" -eq 0 ]
    grep -qF '    modules     = ["claudeDistiller"]' "$CFG"
}

@test "modules_write_list does not confuse modules with modulesSeen" {
    # `modules` must not match the `modulesSeen` line, in either direction.
    lib "modules_write_list '$CFG' modules onlyone"
    grep -qF '    modules     = ["onlyone"]' "$CFG"
    grep -qF '    modulesSeen = ["macApps", "theme", "locale"]' "$CFG"
}

@test "modules_write_list fails on a config with no modules line to anchor to" {
    printf 'sourceDir = "/repo"\n\n[data]\n    name = "Test"\n' >"$CFG"
    lib "modules_write_list '$CFG' modulesSeen a"
    [ "$status" -ne 0 ]
}

@test "modules_write_list fails on a missing or unwritable file" {
    lib "modules_write_list '$BATS_TEST_TMPDIR/nope.toml' modules a"
    [ "$status" -ne 0 ]
    chmod 0444 "$CFG"
    lib "modules_write_list '$CFG' modules a"
    [ "$status" -ne 0 ]
    chmod 0644 "$CFG"
}

@test "modules.sh is idempotent when sourced twice" {
    # chezup, wizard.sh and distill.sh can pull it in alongside other libs.
    run bash -c ". '$LIB'; . '$LIB'; modules_unseen '$DATA'"
    [ "$status" -eq 0 ]
    [ "$output" = "claudeDistiller" ]
}
