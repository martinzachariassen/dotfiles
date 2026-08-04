#!/usr/bin/env bash
# lint-config.sh — parse every JSON/TOML config before `chezmoi apply` writes them into $HOME.
# Templates (*.tmpl) are covered by render-check instead.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
cd "$SOURCE_DIR"

VSCODE_DIR='./src/Library/Application Support/Code/User'

errors=0

# JSONC, not strict JSON: the VS Code user dir plus any devcontainer.json.
is_jsonc() {
    case "$1" in
        "${VSCODE_DIR}/"* | */devcontainer.json) return 0 ;;
        *) return 1 ;;
    esac
}

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

# Strip // and /* */ comments, respecting string boundaries.
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
# VS Code tolerates trailing commas before } or ].
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

# cached + untracked so gitignored locals stay unlinted; `./` prefix matches VSCODE_DIR.
list_paths() {
    local pattern="$1"
    git ls-files -co --exclude-standard -- "$pattern" | sed 's|^|./|' | sort
}

while IFS= read -r f; do
    is_jsonc "$f" && continue
    echo "JSON   $f"
    run validate_strict_json "$f"
done < <(list_paths '*.json')

while IFS= read -r f; do
    is_jsonc "$f" || continue
    echo "JSONC  $f"
    run validate_jsonc "$f"
done < <(list_paths '*.json')

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
