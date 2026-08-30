#!/usr/bin/env bats
# Pin the global mise runtime declarations (Java 25, Kotlin, Node LTS, Python,
# Maven, Gradle). Nothing else in CI guards these — render-check only parses
# templates, lint-config only validates TOML — so a silent drop while editing
# config.toml would break per-project builds on the next apply undetected.
#
# Parses the TOML structurally (python3's tomllib) rather than grepping for
# substrings, so reordering/reformatting won't false-fail.

setup() {
    load '../../../core/testing/helper'
    MISE_TMPL="$REPO_ROOT/src/dot_config/mise/config.toml.tmpl"

    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed — needed to parse TOML"
    fi
    if ! python3 -c "import tomllib" 2>/dev/null; then
        skip "python3 tomllib not available (needs 3.11+)"
    fi

    # config.toml is a chezmoi template (JVM runtimes gated by jvmStack).
    # Render the fully-enabled form by stripping Go-template directive lines,
    # so the tests can pin the "active stack" without needing chezmoi here.
    MISE_TOML="$BATS_TEST_TMPDIR/mise-config.toml"
    grep -v '^{{' "$MISE_TMPL" >"$MISE_TOML"
}

# Print the JSON-encoded value of a dotted key from MISE_TOML, or empty if
# missing. Lists/scalars both work.
_mise_get() {
    python3 - "$MISE_TOML" "$1" <<'PY'
import json, sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
for key in sys.argv[2].split("."):
    if not isinstance(data, dict) or key not in data:
        sys.exit(0)
    data = data[key]
print(json.dumps(data))
PY
}

# ─── File presence + shape ─────────────────────────────────────────────────

@test "mise config.toml.tmpl exists" {
    [ -f "$MISE_TMPL" ]
}

@test "mise config.toml parses as valid TOML" {
    run python3 -c "import tomllib; tomllib.load(open('$MISE_TOML', 'rb'))"
    [ "$status" -eq 0 ]
}

@test "mise config.toml declares a [tools] table" {
    tools="$(_mise_get tools)"
    [ -n "$tools" ]
}

# ─── Java: the current LTS Temurin version must be installed ───────────────

@test "mise declares Java" {
    java="$(_mise_get tools.java)"
    [ -n "$java" ]
}

@test "mise declares Java with temurin-25" {
    # Configured as a list so VS Code's java.configuration.runtimes can pick it up.
    java="$(_mise_get tools.java)"
    echo "tools.java = $java" >&2
    echo "$java" | grep -q '"temurin-25"'
}

# ─── Node: must be present (the wizard installs LTS by default) ────────────

@test "mise declares Node" {
    node="$(_mise_get tools.node)"
    [ -n "$node" ]
    # Reject obviously broken values like an empty string or `false`.
    [ "$node" != '""' ]
    [ "$node" != 'false' ]
}

# ─── Python: must be present ────────────────────────────────────────────────

@test "mise declares Python" {
    python="$(_mise_get tools.python)"
    [ -n "$python" ]
    [ "$python" != '""' ]
}

# ─── JVM build tools: managed by mise, not Homebrew ────────────────────────

@test "mise declares Kotlin" {
    # The jvmStack module advertises Kotlin (modules.toml, docs/packages.md) and
    # the editors assume kotlinc is on PATH — starship's [kotlin] module, nvim's
    # Kotlin LSP extra, and jetbrains.kotlin-server. It was missing from this
    # file until 2026-08 precisely because nothing asserted it.
    kotlin="$(_mise_get tools.kotlin)"
    [ -n "$kotlin" ]
    [ "$kotlin" != '""' ]
}

@test "mise declares Maven" {
    maven="$(_mise_get tools.maven)"
    [ -n "$maven" ]
}

@test "mise declares Gradle" {
    gradle="$(_mise_get tools.gradle)"
    [ -n "$gradle" ]
}
