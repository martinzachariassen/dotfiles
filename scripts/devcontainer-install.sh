#!/usr/bin/env bash
# Dev-container provisioning for the global `dotfiles.*` route.
#
# VS Code clones this repo into every container it opens and runs this script
# (see dotfiles.repository / dotfiles.installCommand in the VS Code user
# settings). Its job is to install the few CLI binaries the globally-installed
# extensions shell out to but don't bundle, so Todo-Tree, shell-format and
# hadolint behave the same inside a container as on the Mac:
#   ripgrep  -> gruntfuggly.todo-tree (and the editor's own search)
#   shfmt    -> foxundermoon.shell-format
#   hadolint -> exiasr.hadolint
# The linters that bundle their own engine (ShellCheck, ruff, prettier, eslint)
# need nothing here. Language runtimes (Java/Python/Node) are NOT installed —
# the container image owns those, not this script.
#
# Always runs inside a Linux container. Kept resilient: a non-Debian base image
# warns and exits 0 rather than blocking the container from opening.
set -euo pipefail

# Pinned for reproducibility — bump deliberately, not on every rebuild.
SHFMT_VERSION="v3.10.0"
HADOLINT_VERSION="v2.12.0"

# Most devcontainer base images run as a non-root user with passwordless sudo,
# but some run as root with no sudo installed. Handle both.
run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "devcontainer-install: need root or sudo to install packages" >&2
        return 1
    fi
}

if ! command -v apt-get >/dev/null 2>&1; then
    echo "devcontainer-install: no apt-get (non-Debian base image); skipping" >&2
    exit 0
fi

# ripgrep ships in the Debian/Ubuntu repos.
if ! command -v rg >/dev/null 2>&1; then
    run_root apt-get update
    run_root apt-get install -y --no-install-recommends ripgrep
fi

# Apple Silicon hosts run arm64 containers; Intel/CI run amd64. The shfmt and
# hadolint projects spell the architecture differently, so map per tool.
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
        echo "devcontainer-install: unsupported architecture: $arch" >&2
        exit 1
        ;;
esac

if ! command -v shfmt >/dev/null 2>&1; then
    run_root curl -fsSL -o /usr/local/bin/shfmt \
        "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_${shfmt_arch}"
    run_root chmod +x /usr/local/bin/shfmt
fi

if ! command -v hadolint >/dev/null 2>&1; then
    run_root curl -fsSL -o /usr/local/bin/hadolint \
        "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-${hadolint_arch}"
    run_root chmod +x /usr/local/bin/hadolint
fi

# Compatibility shim. The host VS Code settings pin `todo-tree.ripgrep.ripgrep`
# to /opt/homebrew/bin/rg (the marketplace VSIX ships without a bundled rg), and
# VS Code shares that user setting into every container, where that path doesn't
# exist. Point it at the real rg here so Todo-Tree works globally without a
# per-project settings override.
if command -v rg >/dev/null 2>&1; then
    run_root mkdir -p /opt/homebrew/bin
    run_root ln -sf "$(command -v rg)" /opt/homebrew/bin/rg
fi
