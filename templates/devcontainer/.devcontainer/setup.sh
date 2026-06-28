#!/usr/bin/env bash
# Installs CLI binaries that the personal extension set shells out to but
# doesn't bundle. Runs once on container create via postCreateCommand.
# Safe to re-run (all installs are guarded by command -v checks).
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
        echo "setup: need root or sudo to install packages" >&2
        return 1
    fi
}

if ! command -v apt-get >/dev/null 2>&1; then
    echo "setup: no apt-get (non-Debian base image); skipping" >&2
    exit 0
fi

# ripgrep — used by Todo-Tree and the editor's own search.
if ! command -v rg >/dev/null 2>&1; then
    run_root apt-get update
    run_root apt-get install -y --no-install-recommends ripgrep
fi

# Apple Silicon hosts run arm64 containers; Intel/CI run amd64.
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
        echo "setup: unsupported architecture: $arch" >&2
        exit 1
        ;;
esac

# shfmt — used by shell-format extension.
if ! command -v shfmt >/dev/null 2>&1; then
    run_root curl -fsSL -o /usr/local/bin/shfmt \
        "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_${shfmt_arch}"
    run_root chmod +x /usr/local/bin/shfmt
fi

# hadolint — used by hadolint extension.
if ! command -v hadolint >/dev/null 2>&1; then
    run_root curl -fsSL -o /usr/local/bin/hadolint \
        "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-${hadolint_arch}"
    run_root chmod +x /usr/local/bin/hadolint
fi

# The host user settings pin todo-tree.ripgrep.ripgrep to /opt/homebrew/bin/rg
# (the Homebrew path on macOS). Symlink rg there so Todo-Tree finds it without
# a per-project settings override.
if command -v rg >/dev/null 2>&1; then
    run_root mkdir -p /opt/homebrew/bin
    run_root ln -sf "$(command -v rg)" /opt/homebrew/bin/rg
fi
