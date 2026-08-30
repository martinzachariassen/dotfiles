#!/usr/bin/env bash
# Materialize mise's global toolchain: `mise activate` puts tools on PATH but
# never installs a missing version, so download them eagerly here.
#
# Invoked by run_after_02b-mise-install.sh.tmpl, which keeps the darwin guard.
# run_after rather than run_onchange on purpose: a runtime can go missing while
# config.toml stays put, so this re-converges on every apply.

set -euo pipefail

# Put Homebrew's bin on PATH so a non-login apply still finds mise. The path is
# absolute because chezmoi runs hooks without a login shell; it is overridable so
# the tests can decide for themselves whether mise is reachable.
BREW_BIN="${BREW_BIN:-/opt/homebrew/bin/brew}"
if [ -x "$BREW_BIN" ]; then
    eval "$("$BREW_BIN" shellenv)"
fi

echo "▶ mise runtimes"

if ! command -v mise >/dev/null 2>&1; then
    echo "! mise not on PATH yet — skipping global install."
    echo "  Re-run \`chezup\` after brew bundle finishes to install runtimes."
    exit 0
fi

if [ -z "$(cd "$HOME" && mise ls --missing 2>/dev/null)" ]; then
    echo "  ✓ global runtimes already installed: $(cd "$HOME" && mise current 2>/dev/null | tr '\n' ' ')"
    exit 0
fi

# A real count, from mise itself — not a guess. mise renders its own per-tool
# progress below, so this only frames it rather than wrapping it in a second bar.
missing="$(cd "$HOME" && mise ls --missing 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
missing_n="$(printf '%s' "$missing" | wc -w | tr -d ' ')"
echo "→ Installing $missing_n missing runtime(s): $missing"
echo "  Downloads only what's missing; mise shows its own progress per tool."

if (cd "$HOME" && mise install); then
    echo "✓ mise runtimes installed: $(cd "$HOME" && mise current 2>/dev/null | tr '\n' ' ')"
else
    echo "! mise install failed (network?). Re-run \`chezup\` or \`mise install\` to retry."
    exit 0
fi
