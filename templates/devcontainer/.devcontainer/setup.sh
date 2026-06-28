#!/usr/bin/env bash
# Install the CLI binaries the VS Code extensions need but don't ship
# themselves. shellcheck/ruff/prettier/eslint all bundle their own engine, so
# only these three need installing:
#   ripgrep  -> gruntfuggly.todo-tree (and the editor's search)
#   shfmt    -> foxundermoon.shell-format
#   hadolint -> exiasr.hadolint
set -euo pipefail

# Pinned for reproducibility — bump deliberately, not on every rebuild.
SHFMT_VERSION="v3.10.0"
HADOLINT_VERSION="v2.12.0"

# Apple Silicon hosts run arm64 containers; CI/Intel run amd64. The two
# projects spell the architecture differently, so map per tool.
arch="$(dpkg --print-architecture)" # amd64 | arm64
case "$arch" in
    amd64)
        shfmt_arch="amd64"
        hadolint_arch="x86_64"
        ;;
    arm64)
        shfmt_arch="arm64"
        hadolint_arch="arm64"
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 1
        ;;
esac

sudo apt-get update
sudo apt-get install -y --no-install-recommends ripgrep

sudo curl -fsSL -o /usr/local/bin/shfmt \
    "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_${shfmt_arch}"
sudo curl -fsSL -o /usr/local/bin/hadolint \
    "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-${hadolint_arch}"
sudo chmod +x /usr/local/bin/shfmt /usr/local/bin/hadolint
