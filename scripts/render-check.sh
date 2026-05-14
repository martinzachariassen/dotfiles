#!/usr/bin/env bash
# Render all chezmoi templates with deterministic stub data.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/.config/chezmoi"
cat > "$tmpdir/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SOURCE_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    signingKey     = "ssh-ed25519 AAAAci-placeholder"
    profile        = "both"
    useOnePassword = true

    [data.features]
        macApps   = true
EOF

HOME="$tmpdir" chezmoi apply --dry-run --verbose --source="$SOURCE_DIR"
