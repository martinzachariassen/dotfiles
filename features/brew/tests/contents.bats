#!/usr/bin/env bats
# Pin the critical packages each Brewfile module is expected to declare.
#
# brew-resolve/brew-check prove names are real and installed, not that the
# file still contains what this stack assumes — a one-off delete would slip
# past every other CI job. Scope: load-bearing entries only (what the shell,
# doctor, or install scripts explicitly assume); casual app/font additions
# aren't pinned so the tests don't churn on routine edits.
#
# Match mechanism: literal `<kind> "<name>"` substring (grep -F) — tolerates
# reordering/comments without false-matching "1password" on "1password-cli".

setup() {
    load '../../../core/testing/helper'
    CORE="$REPO_ROOT/features/brew/Brewfile"
    MAC_APPS="$REPO_ROOT/features/brew/Brewfile.mac-apps"
    WORK="$REPO_ROOT/features/brew/Brewfile.work"
    PERSONAL="$REPO_ROOT/features/brew/Brewfile.personal"
}

# 0 if FILE has a line declaring `KIND "NAME"`, ignoring trailing comments.
declares() {
    local file="$1" kind="$2" name="$3"
    grep -Fq "${kind} \"${name}\"" "$file"
}

# Convenience for negative assertions — same matcher, inverted exit.
not_declares() {
    local file="$1" kind="$2" name="$3"
    ! grep -Fq "${kind} \"${name}\"" "$file"
}

# ─── Core Brewfile: every fresh-Mac install gets these ─────────────────────

@test "core Brewfile exists" {
    [ -f "$CORE" ]
}

# Repo + git plumbing — `chez up`, `chez doctor`, and the install wizard all
# rely on chezmoi/git/gh/jq being on PATH.
@test "core Brewfile declares chezmoi" { declares "$CORE" brew chezmoi; }
@test "core Brewfile declares git"     { declares "$CORE" brew git; }
@test "core Brewfile declares gh"      { declares "$CORE" brew gh; }
@test "core Brewfile declares jq"      { declares "$CORE" brew jq; }

# Runtime manager — without mise, none of the language runtimes activate.
@test "core Brewfile declares mise" { declares "$CORE" brew mise; }

# Shell + terminal contract — the dotfiles' look/feel breaks without these.
@test "core Brewfile declares starship"        { declares "$CORE" brew starship; }
@test "core Brewfile declares zellij"          { declares "$CORE" brew zellij; }
@test "core Brewfile declares ghostty"         { declares "$CORE" cask ghostty; }
@test "core Brewfile declares 1password GUI"   { declares "$CORE" cask 1password; }
@test "core Brewfile declares 1password-cli"   { declares "$CORE" cask 1password-cli; }
@test "core Brewfile declares JetBrainsMono Nerd Font" {
    # Ghostty's font config references this — drop it and the terminal falls
    # back to the system mono with broken Nerd-Font glyphs.
    declares "$CORE" cask font-jetbrains-mono-nerd-font
}

# Modern CLI replacements — the zshrc aliases (bat, eza, fd, …) assume these.
@test "core Brewfile declares bat"     { declares "$CORE" brew bat; }
@test "core Brewfile declares eza"     { declares "$CORE" brew eza; }
@test "core Brewfile declares fd"      { declares "$CORE" brew fd; }
@test "core Brewfile declares fzf"     { declares "$CORE" brew fzf; }
@test "core Brewfile declares ripgrep" { declares "$CORE" brew ripgrep; }
@test "core Brewfile declares zoxide"  { declares "$CORE" brew zoxide; }

# Containers — the LaunchAgent invokes colima by absolute path and the plugin
# symlinks under dot_docker/cli-plugins point into these formulae's prefixes,
# so dropping any of them leaves a registered agent or a dangling link behind.
@test "core Brewfile declares colima"         { declares "$CORE" brew colima; }
@test "core Brewfile declares docker CLI"     { declares "$CORE" brew docker; }
@test "core Brewfile declares docker-compose" { declares "$CORE" brew docker-compose; }
@test "core Brewfile declares docker-buildx"  { declares "$CORE" brew docker-buildx; }

@test "core Brewfile does NOT declare docker-desktop (colima replaced it)" {
    # Both would install a `docker` binary and fight over ~/.docker/cli-plugins.
    not_declares "$CORE" cask docker-desktop
}

# Lint stack — pre-commit + CI both invoke shellcheck/shfmt; render-check
# depends on shellcheck being present locally.
@test "core Brewfile declares shellcheck" { declares "$CORE" brew shellcheck; }
@test "core Brewfile declares shfmt"      { declares "$CORE" brew shfmt; }

# ─── Negative invariants on core: runtimes belong to mise, not brew ────────

@test "core Brewfile does NOT declare node (mise owns Node)" {
    # Re-adding it would put a stale binary on PATH ahead of mise's shim.
    not_declares "$CORE" brew node
}
@test "core Brewfile does NOT declare any temurin JDK (mise owns Java)" {
    # Matches brew/cask "temurin", "temurin@21", etc. — same migration as node.
    ! grep -qE '^[[:space:]]*(brew|cask)[[:space:]]+"temurin' "$CORE"
}
@test "core Brewfile does NOT declare python directly (mise owns Python)" {
    not_declares "$CORE" brew python
}
@test "core Brewfile does NOT declare direnv (replaced by mise [env])" {
    not_declares "$CORE" brew direnv
}

# ─── Mac-apps module: AI tooling is the headline feature ───────────────────

@test "mac-apps Brewfile exists" {
    [ -f "$MAC_APPS" ]
}
@test "mac-apps Brewfile declares the Claude desktop app" {
    declares "$MAC_APPS" cask claude
}
@test "mac-apps Brewfile declares Claude Code" {
    declares "$MAC_APPS" cask claude-code
}

# ─── Work module: cloud/k8s stack ──────────────────────────────────────────

@test "work Brewfile exists" {
    [ -f "$WORK" ]
}
@test "work Brewfile declares kubectl" {
    declares "$WORK" brew kubernetes-cli
}
@test "work Brewfile declares helm" {
    # Terminal-side companion to kubectl; the VS Code extensions that used to
    # justify it were dropped 2026-08, the CLI stands on its own.
    declares "$WORK" brew helm
}
@test "work Brewfile declares minikube" {
    # Same story as helm — the local cluster CLI stays brew-managed so its
    # version is pinned with the rest of the toolchain.
    declares "$WORK" brew minikube
}
@test "work Brewfile declares kubectx" {
    declares "$WORK" brew kubectx
}
@test "work Brewfile declares Azure kubelogin" {
    # Tapped name — the literal "Azure/kubelogin/kubelogin" must appear.
    declares "$WORK" brew Azure/kubelogin/kubelogin
}
@test "work Brewfile declares terraform from hashicorp/tap" {
    # Tapped name — the literal "hashicorp/tap/terraform" must appear.
    declares "$WORK" brew hashicorp/tap/terraform
}
@test "work Brewfile declares azure-cli" {
    declares "$WORK" brew azure-cli
}
@test "work Brewfile declares gcloud-cli" {
    declares "$WORK" cask gcloud-cli
}

# Not a casual app addition: a work Mac that isn't enrolled in Intune loses
# access to the corporate resources the rest of this tier exists to reach.
@test "work Brewfile declares intune-company-portal" {
    declares "$WORK" cask intune-company-portal
}

# Microsoft 365 footgun: the suite cask `conflicts_with` every standalone
# Office cask. If both are listed `brew bundle` fails outright on a clean
# install — a real foot-cannon documented inline in the Brewfile.
@test "work Brewfile declares the microsoft-office suite" {
    declares "$WORK" cask microsoft-office
}
@test "work Brewfile does NOT also declare standalone Office apps that conflict with the suite" {
    not_declares "$WORK" cask microsoft-outlook
    not_declares "$WORK" cask microsoft-word
    not_declares "$WORK" cask microsoft-excel
    not_declares "$WORK" cask microsoft-powerpoint
    not_declares "$WORK" cask microsoft-onenote
    not_declares "$WORK" cask onedrive
}

# ─── Personal module: minimal, just verify file exists ─────────────────────

@test "personal Brewfile exists" {
    # Casks here are pure preference; only existence is pinned.
    [ -f "$PERSONAL" ]
}

# ─── The machine-local seed template ───────────────────────────────────────
#
# Copied verbatim to ~/.config/chez/Brewfile.local on every Mac's first apply,
# so anything it declares is something every Mac silently installs. It must
# stay a pure comment block: the file exists to explain the hatch, not to use
# it. See features/adopt/README.md.

@test "the Brewfile.local template declares nothing" {
    local template="$REPO_ROOT/features/brew/Brewfile.local.template"
    [ -f "$template" ]
    no_match '^[[:space:]]*(brew|cask|tap|mas|vscode) ' "$template"
}

@test "the CI Brewfile sweeps skip the template" {
    # Both scripts glob features/brew/Brewfile.*, which now matches the
    # template. Resolving a file with no entries is only noise today, but the
    # skip is what keeps it from becoming a checked package list by accident.
    grep -qF '*.lock.json | *.template' "$REPO_ROOT/scripts/ci/brew-resolve.sh"
    grep -qF '*.lock.json | *.template' "$REPO_ROOT/scripts/ci/brew-check-modules.sh"
}
