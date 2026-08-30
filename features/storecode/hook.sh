#!/usr/bin/env bash
# Installs storecode, the work-only security tool. It ships via its OWN
# installer, never Homebrew — this is the one place that installs it.
#
# Invoked by run_onchange_after_05-storecode.sh.tmpl, which keeps the darwin and
# work-profile guards and passes the two render-time values: the destination
# home, and the install command from src/.chezmoidata/storecode.toml.

set -euo pipefail

home="${1:-$HOME}"
install_cmd="${2-}"

if command -v storecode >/dev/null 2>&1 || [ -e "$home/.storecode" ]; then
    echo "✓ storecode already installed"
    exit 0
fi

if [ -z "$install_cmd" ]; then
    echo "◆ storecode: not installed, and no installer is configured yet."
    echo "  Set [storecode].installCmd in src/.chezmoidata/storecode.toml to the"
    echo "  work installer (e.g. a 'curl -fsSL …/install.sh | bash' one-liner),"
    echo "  then run 'chezup'. storecode is intentionally not a Homebrew package;"
    echo "  ~/.storecode is kept automatically by chezclean."
    exit 0
fi

echo "◆ storecode: installing…"
if eval "$install_cmd"; then
    echo "✓ storecode installed"
else
    echo "  ! storecode install failed — run it manually: $install_cmd" >&2
    exit 1
fi
