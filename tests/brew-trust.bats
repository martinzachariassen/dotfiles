#!/usr/bin/env bats
# Tests for the tap-trust helpers in scripts/lib/homebrew.sh.
#
# Why these exist: Homebrew 6.0 will not load formulae or casks from a
# non-official tap until the tap is trusted, and `brew bundle` skips the
# untrusted ones *without an error*. The failure mode is a package that is
# simply absent — nothing in the log to grep for — so every guarantee here is
# about detecting that state, not about brew's own exit status.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    HOMEBREW_LIB="$REPO_ROOT/scripts/lib/homebrew.sh"
    [ -r "$HOMEBREW_LIB" ] || skip "homebrew.sh not found at $HOMEBREW_LIB"

    STUBS="$(mktemp -d)"
    BREWFILE="$STUBS/Brewfile.test"
}

teardown() {
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

# A `brew` stub whose trust store is a plain file of tap names, one per line.
# `brew trust --tap X` appends; `brew trust --json v1` renders the same JSON
# shape real brew emits. TRUST_READONLY=1 makes writes silently no-op while
# still exiting 0 — the exact "asked politely, nothing recorded" case that the
# old exit-status-only check could not see.
make_brew_stub() {
    : >"$STUBS/trusted"
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
[ "\$1" = "trust" ] || exit 0
shift
if [ "\$1" = "--json" ]; then
    printf '{\n  "taps": [\n'
    first=1
    while IFS= read -r t; do
        [ -n "\$t" ] || continue
        [ "\$first" = 1 ] || printf ',\n'
        printf '    "%s"' "\$t"
        first=0
    done < "$STUBS/trusted"
    [ "\$first" = 1 ] || printf '\n'
    printf '  ],\n  "formulae": [],\n  "casks": [],\n  "commands": []\n}\n'
    exit 0
fi
if [ "\$1" = "--tap" ]; then
    [ "\${TRUST_READONLY:-0}" = 1 ] || printf '%s\n' "\$2" >> "$STUBS/trusted"
    exit 0
fi
exit 0
EOF
    chmod +x "$STUBS/brew"
}

# Run BODY with the stub brew on PATH and the lib sourced.
lib() {
    env PATH="$STUBS:/usr/bin:/bin" TRUST_READONLY="${TRUST_READONLY:-0}" \
        bash -c "source '$HOMEBREW_LIB'; $1"
}

# ─── brew_declared_taps ───────────────────────────────────────────────────────

@test "brew_declared_taps picks up explicit tap lines" {
    cat >"$BREWFILE" <<'EOF'
tap "hashicorp/tap"
brew "jq"
EOF
    run lib "brew_declared_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ "$output" = "hashicorp/tap" ]
}

# The bug this guards: a Brewfile may name a third-party formula fully-qualified
# without a matching `tap` line. Trusting only the explicit lines left that tap
# untrusted and its formula silently skipped.
@test "brew_declared_taps infers the tap from a fully-qualified formula" {
    cat >"$BREWFILE" <<'EOF'
brew "Azure/kubelogin/kubelogin"
EOF
    run lib "brew_declared_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ "$output" = "azure/kubelogin" ]
}

@test "brew_declared_taps infers the tap from a fully-qualified cask" {
    cat >"$BREWFILE" <<'EOF'
cask "someorg/sometap/somecask"
EOF
    run lib "brew_declared_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ "$output" = "someorg/sometap" ]
}

# Homebrew normalises tap names to lowercase in trust.json, so a case-sensitive
# comparison reported "Azure/kubelogin" as untrusted forever.
@test "brew_declared_taps lowercases and dedupes across files" {
    cat >"$BREWFILE" <<'EOF'
tap "Azure/kubelogin"
brew "Azure/kubelogin/kubelogin"
EOF
    other="$STUBS/Brewfile.other"
    cat >"$other" <<'EOF'
tap "azure/kubelogin"
EOF
    run lib "brew_declared_taps '$BREWFILE' '$other'"
    [ "$status" -eq 0 ]
    [ "$output" = "azure/kubelogin" ]
}

@test "brew_declared_taps ignores core formulae and casks" {
    cat >"$BREWFILE" <<'EOF'
brew "jq"
cask "slack"
mas "Xcode", id: 497799835
EOF
    run lib "brew_declared_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "brew_declared_taps skips files that do not exist" {
    run lib "brew_declared_taps '$STUBS/nope'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── brew_trusted_taps ────────────────────────────────────────────────────────

# The array header line is itself `  "taps": [`, which the naive value matcher
# captured as a tap literally named "taps".
@test "brew_trusted_taps does not report the JSON array header as a tap" {
    make_brew_stub
    printf 'hashicorp/tap\n' >"$STUBS/trusted"
    run lib "brew_trusted_taps"
    [ "$status" -eq 0 ]
    [ "$output" = "hashicorp/tap" ]
}

@test "brew_trusted_taps is empty when nothing is trusted" {
    make_brew_stub
    run lib "brew_trusted_taps"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── brew_untrusted_taps / brew_trust_taps ────────────────────────────────────

@test "brew_untrusted_taps reports a declared tap that is not trusted" {
    make_brew_stub
    cat >"$BREWFILE" <<'EOF'
tap "hashicorp/tap"
EOF
    run lib "brew_untrusted_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ "$output" = "hashicorp/tap" ]
}

@test "brew_untrusted_taps is empty once the tap is trusted" {
    make_brew_stub
    printf 'hashicorp/tap\n' >"$STUBS/trusted"
    cat >"$BREWFILE" <<'EOF'
tap "hashicorp/tap"
EOF
    run lib "brew_untrusted_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "brew_trust_taps trusts what is declared and then reports nothing left" {
    make_brew_stub
    cat >"$BREWFILE" <<'EOF'
tap "hashicorp/tap"
brew "Azure/kubelogin/kubelogin"
EOF
    run lib "brew_trust_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -qx 'hashicorp/tap' "$STUBS/trusted"
    grep -qx 'azure/kubelogin' "$STUBS/trusted"
}

# The regression that made the old code useless: `brew trust` exits 0 for a
# write that never lands, so trusting must be verified by re-reading the store.
@test "brew_trust_taps reports taps that did not take even though brew exited 0" {
    make_brew_stub
    cat >"$BREWFILE" <<'EOF'
tap "hashicorp/tap"
EOF
    TRUST_READONLY=1 run lib "brew_trust_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ "$output" = "hashicorp/tap" ]
}

@test "brew_trust_taps is a no-op with no declared taps" {
    make_brew_stub
    cat >"$BREWFILE" <<'EOF'
brew "jq"
EOF
    run lib "brew_trust_taps '$BREWFILE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -s "$STUBS/trusted" ]
}

# ─── brew_trust_store ─────────────────────────────────────────────────────────

# The split-store bug: brew keys trust.json off XDG_CONFIG_HOME, `curl | bash`
# installs run without it, and the zshenv this repo deploys always sets it — so
# trust granted during the first install lived in a file no later shell read.
@test "brew_trust_store defaults XDG_CONFIG_HOME to ~/.config" {
    run env -u XDG_CONFIG_HOME PATH="$STUBS:/usr/bin:/bin" HOME=/tmp/fakehome \
        bash -c "source '$HOMEBREW_LIB'; brew_trust_store"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/fakehome/.config/homebrew/trust.json" ]
}

@test "brew_trust_store respects an XDG_CONFIG_HOME that is already set" {
    run env XDG_CONFIG_HOME=/custom/cfg PATH="$STUBS:/usr/bin:/bin" HOME=/tmp/fakehome \
        bash -c "source '$HOMEBREW_LIB'; brew_trust_store"
    [ "$status" -eq 0 ]
    [ "$output" = "/custom/cfg/homebrew/trust.json" ]
}

@test "brew_trust_store exports XDG_CONFIG_HOME for later brew calls" {
    run env -u XDG_CONFIG_HOME PATH="$STUBS:/usr/bin:/bin" HOME=/tmp/fakehome \
        bash -c "source '$HOMEBREW_LIB'; brew_trust_store >/dev/null; env | grep '^XDG_CONFIG_HOME='"
    [ "$status" -eq 0 ]
    [ "$output" = "XDG_CONFIG_HOME=/tmp/fakehome/.config" ]
}
