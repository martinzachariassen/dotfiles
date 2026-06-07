#!/usr/bin/env bash
# Validate that every JSON and TOML config file in the source tree parses
# cleanly. Catches stray commas, missing quotes, unbalanced braces, and other
# hand-edit damage before a `chezmoi apply` writes them into $HOME.
#
# Scope:
#   *.toml          — strict TOML, via Python tomllib (3.11+).
#   *.json          — strict JSON, via `python3 -m json.tool`.
#   VS Code configs — JSONC (line + block comments, trailing commas allowed);
#                     validated by a small strip-then-load pass.
#
# Templates (*.json.tmpl, *.toml.tmpl) are NOT validated here — the chezmoi
# render-check job already proves them parseable as templates, and the rendered
# settings.json.tmpl is JSONC-validated by render-check.sh after `chezmoi
# execute-template`.
#
# Run from the repo root, or pass the source dir as $1.
#   bash scripts/lint-config.sh

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
cd "$SOURCE_DIR"

# VS Code's settings.json + keybindings.json are JSONC, not strict JSON.
VSCODE_DIR='./Library/Application Support/Code/User'

errors=0

validate_strict_json() {
    local f="$1"
    if ! python3 -m json.tool "$f" >/dev/null 2>/tmp/lint-config.err; then
        echo "::error file=${f#./}::invalid JSON"
        sed 's/^/  /' /tmp/lint-config.err >&2
        return 1
    fi
}

validate_jsonc() {
    local f="$1"
    if ! python3 - "$f" <<'PY' 2>/tmp/lint-config.err; then
import json, re, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()

# Strip // line and /* */ block comments while respecting string boundaries.
def strip(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    j += 2; continue
                if s[j] == '"':
                    j += 1; break
                j += 1
            out.append(s[i:j]); i = j
        elif c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            i = n if j == -1 else j
        elif c == "/" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*/", i + 2)
            if j == -1:
                raise SystemExit(f"unterminated /* */ comment in {path}")
            i = j + 2
        else:
            out.append(c); i += 1
    return "".join(out)

src = strip(src)
# Allow trailing commas before } or ] (VS Code tolerates these).
src = re.sub(r",(\s*[\]}])", r"\1", src)
try:
    json.loads(src)
except json.JSONDecodeError as e:
    raise SystemExit(f"invalid JSONC: {e}")
PY
        echo "::error file=${f#./}::$(cat /tmp/lint-config.err)"
        return 1
    fi
}

validate_toml() {
    local f="$1"
    if ! python3 - "$f" <<'PY' 2>/tmp/lint-config.err; then
import sys, tomllib
path = sys.argv[1]
try:
    with open(path, "rb") as fh:
        tomllib.load(fh)
except tomllib.TOMLDecodeError as e:
    raise SystemExit(f"invalid TOML: {e}")
PY
        echo "::error file=${f#./}::$(cat /tmp/lint-config.err)"
        return 1
    fi
}

run() {
    "$@" || errors=$((errors + 1))
}

# Walk git's view of the tree (`-c`ached + `-o`ther + `--exclude-standard`) so
# gitignored locals like .claude/settings.local.json never get linted, while
# still catching untracked new files in a working dir. Files are prefixed with
# `./` to match the find-style paths the rest of the script (and VSCODE_DIR)
# is written against.
list_paths() {
    local pattern="$1"
    git ls-files -co --exclude-standard -- "$pattern" | sed 's|^|./|' | sort
}

# ─── Strict JSON (everywhere except the VS Code JSONC dir) ────────────────────
while IFS= read -r f; do
    case "$f" in "${VSCODE_DIR}/"*) continue ;; esac
    echo "JSON   $f"
    run validate_strict_json "$f"
done < <(list_paths '*.json')

# ─── JSONC (VS Code config dir) ───────────────────────────────────────────────
while IFS= read -r f; do
    case "$f" in "${VSCODE_DIR}/"*) ;; *) continue ;; esac
    echo "JSONC  $f"
    run validate_jsonc "$f"
done < <(list_paths '*.json')

# ─── Strict TOML (everywhere) ────────────────────────────────────────────────
while IFS= read -r f; do
    echo "TOML   $f"
    run validate_toml "$f"
done < <(list_paths '*.toml')

rm -f /tmp/lint-config.err

if [ "$errors" -gt 0 ]; then
    echo
    echo "lint-config: $errors file(s) failed validation" >&2
    exit 1
fi
echo
echo "lint-config: all config files valid"
