#!/usr/bin/env bats
# Pin the critical packages each Brewfile module is expected to declare.
#
# Why this exists:
#   `brew-resolve` proves every name in a Brewfile is real, and `brew-check`
#   proves the runner already has them — neither proves that the file still
#   contains the packages this dotfiles stack actually assumes. A one-off
#   delete (`brew "ripgrep"` removed while debugging) would slip past every
#   other CI job because the file still parses and the remaining names still
#   resolve. These tests fail on that.
#
# Scope: load-bearing entries only — packages the shell, doctor, install
# scripts, or feature docs explicitly assume are present. Casual additions/
# removals (a personal app, a font tweak) are deliberately not pinned so the
# tests don't churn on every routine edit.
#
# Match mechanism: literal `<kind> "<name>"` substring (grep -F). That
# tolerates trailing comments, alphabetical reordering, and section moves,
# without false-matching `cask "1password"` against `cask "1password-cli"`
# (the closing quote anchors it).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CORE="$REPO_ROOT/packages/Brewfile"
    MAC_APPS="$REPO_ROOT/packages/Brewfile.mac-apps"
    WORK="$REPO_ROOT/packages/Brewfile.work"
    PERSONAL="$REPO_ROOT/packages/Brewfile.personal"
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

# Repo + git plumbing — `chezup`, `chezdoctor`, and the install wizard all
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

# Lint stack — pre-commit + CI both invoke shellcheck/shfmt; render-check
# depends on shellcheck being present locally.
@test "core Brewfile declares shellcheck" { declares "$CORE" brew shellcheck; }
@test "core Brewfile declares shfmt"      { declares "$CORE" brew shfmt; }

# ─── Negative invariants on core: runtimes belong to mise, not brew ────────

@test "core Brewfile does NOT declare node (mise owns Node)" {
    # README + cleanup script explicitly call out the migration: Homebrew
    # node was uninstalled and replaced by mise. Re-adding it would put a
    # stale binary on PATH ahead of mise's shim on fresh installs.
    not_declares "$CORE" brew node
}
@test "core Brewfile does NOT declare any temurin JDK (mise owns Java)" {
    # Matches `brew "temurin"`, `brew "temurin@21"`, `cask "temurin"`, etc.
    # Same migration reason as node — the cleanup script uninstalls these.
    ! grep -qE '^[[:space:]]*(brew|cask)[[:space:]]+"temurin' "$CORE"
}
@test "core Brewfile does NOT declare python directly (mise owns Python)" {
    not_declares "$CORE" brew python
}
@test "core Brewfile does NOT declare direnv (replaced by mise [env])" {
    # README: "mise.toml [env] section, not direnv". The cleanup script
    # uninstalls leftover direnv from the previous stack.
    not_declares "$CORE" brew direnv
}

# ─── Mac-apps module: AI tooling is the headline feature ───────────────────

@test "mac-apps Brewfile exists" {
    [ -f "$MAC_APPS" ]
}
@test "mac-apps Brewfile declares ollama" {
    # README "Local AI" row: "Ollama (run as a brew service) plus the Claude
    # and Claude Code apps." Doctor checks for the running service.
    declares "$MAC_APPS" brew ollama
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
    # The vscode-kubernetes extension (+ helm-intellisense) assumes helm on
    # PATH; without it VS Code downloads an unmanaged copy to ~/.vs-kubernetes.
    declares "$WORK" brew helm
}
@test "work Brewfile declares minikube" {
    # Same contract as helm — keep the local cluster CLI brew-managed instead
    # of letting the k8s extension fetch its own.
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
    # Casks here are pure preference — nothing else in the stack depends on
    # any specific entry, so we don't pin contents. The file existing at all
    # is the only invariant (chezmoi data wires the install path to it).
    [ -f "$PERSONAL" ]
}
