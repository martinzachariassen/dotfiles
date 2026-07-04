#!/usr/bin/env bats
# Pin the global mise runtime declarations.
#
# Why this exists:
#   The "active development stack" — Java 21 + 25, Node LTS, Python 3.x, Maven,
#   Gradle — is part of the repo's contract. A silent drop (an accidental delete
#   while editing config.toml) would break per-project builds on the next fresh
#   apply, but nothing else in CI guards it: render-check only parses templates,
#   lint-config only checks that the TOML is valid, and the chezmoi-scripts
#   dynamic check doesn't read this file.
#
# These tests parse the TOML structurally (via python3's tomllib) rather than
# grepping for substrings, so reordering or reformatting the file won't
# false-fail.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    MISE_TMPL="$REPO_ROOT/src/dot_config/mise/config.toml.tmpl"

    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed — needed to parse TOML"
    fi
    if ! python3 -c "import tomllib" 2>/dev/null; then
        skip "python3 tomllib not available (needs 3.11+)"
    fi

    # config.toml is now a chezmoi template (the JVM runtimes are gated by the
    # jvmStack module). Render its fully-enabled form by stripping the Go-template
    # directive lines ({{ ... }}); the JVM runtimes are then all present, which is
    # exactly the "active stack" contract these tests pin — without needing
    # chezmoi in the test environment.
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

# ─── Java: both LTS-relevant Temurin versions must be installed ────────────

@test "mise declares Java" {
    java="$(_mise_get tools.java)"
    [ -n "$java" ]
}

@test "mise declares Java with both temurin-21 and temurin-25" {
    # Java is configured as a list so multiple JDKs install side-by-side and
    # VS Code's java.configuration.runtimes can pick either. Dropping one
    # silently breaks projects that still pin to it.
    java="$(_mise_get tools.java)"
    echo "tools.java = $java" >&2
    echo "$java" | grep -q '"temurin-21"'
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

# ─── Python: pinned to a single major.minor line ───────────────────────────

@test "mise declares Python" {
    python="$(_mise_get tools.python)"
    [ -n "$python" ]
}

@test "mise's Python version is major.minor pinned (not 'latest' or 'system')" {
    # The comment in config.toml is explicit: "major-pinned so patch releases
    # install cleanly while a deliberate major bump stays a code change." A
    # drift to "latest" would defeat that.
    python="$(_mise_get tools.python)"
    echo "tools.python = $python" >&2
    echo "$python" | grep -qE '^"[0-9]+\.[0-9]+"$'
}

# ─── JVM build tools: managed by mise, not Homebrew ────────────────────────

@test "mise declares Maven" {
    maven="$(_mise_get tools.maven)"
    [ -n "$maven" ]
}

@test "mise declares Gradle" {
    gradle="$(_mise_get tools.gradle)"
    [ -n "$gradle" ]
}
