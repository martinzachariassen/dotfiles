#!/usr/bin/env bash
# obsidian-apply.sh — converge an Obsidian vault to the canonical config.
#
# Sourced by .chezmoiscripts/run_after_02d-obsidian-apply.sh.tmpl; never run
# directly. Reads canonical config + templates from ~/.config/obsidian/ and
# seeds the active vault's .obsidian/ overlay.
#
# Design rules (see docs/lifecycle.md):
#   - State-based, not hash-gated. Runs every apply. Presence-only check, so a
#     clean machine is a quick no-op. Freshness is chezbump's job.
#   - Continue-on-error: one failed plugin download doesn't block the rest.
#   - Seed, don't overwrite: config files and templates already present in the
#     vault are left alone. Obsidian's UI is the source of truth for runtime
#     state; this script only fills gaps.
#   - bash 3.2 only (macOS stock). No declare -A, ${var^^}, mapfile.
#
# Public API:
#   obsidian_apply  — entrypoint, does the whole convergence
#   OB_FAILURES     — array of "what: detail (rc=N)" failure lines

# Source guard.
[ -n "${__DOTFILES_OBSIDIAN_APPLY_SH:-}" ] && return 0
__DOTFILES_OBSIDIAN_APPLY_SH=1

# shellcheck disable=SC2034  # consumed by the entry-point script after sourcing
OB_FAILURES=()

OB_CONFIG_DIR="${OB_CONFIG_DIR:-$HOME/.config/obsidian}"
OB_REGISTRY="$HOME/Library/Application Support/obsidian/obsidian.json"

# ob_seed_copy SRC DST LABEL — create DST's parent dir and copy SRC→DST. On
# failure (read-only vault, full disk, perms) records LABEL in OB_FAILURES and
# returns 1 so the caller skips its success message. Never aborts the run under
# `set -e` — the whole module's contract is continue-on-error.
ob_seed_copy() {
    local src="$1" dst="$2" label="$3" rc=0
    mkdir -p "$(dirname "$dst")" && cp "$src" "$dst" || rc=$?
    if [ "$rc" -ne 0 ]; then
        OB_FAILURES+=("seed: $label (rc=$rc)")
        return 1
    fi
    return 0
}

# ─── Vault discovery ──────────────────────────────────────────────────────────

# obsidian_find_vault — print the active vault's absolute path, or nothing.
# The registry stores all known vaults; we prefer the one marked "open": true,
# falling back to the first entry. Empty output means "no vault configured" —
# callers should treat it as "Obsidian not set up yet, nothing to do."
obsidian_find_vault() {
    [ -f "$OB_REGISTRY" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    python3 - "$OB_REGISTRY" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
vaults = (data or {}).get("vaults") or {}
if not vaults:
    sys.exit(0)
# Prefer the vault flagged open=true; fall back to first.
chosen = None
for v in vaults.values():
    if v.get("open"):
        chosen = v
        break
if chosen is None:
    chosen = next(iter(vaults.values()))
print(chosen.get("path", ""))
PY
}

# ─── Theme ────────────────────────────────────────────────────────────────────

# obsidian_install_theme VAULT — ensure the configured theme is on disk.
# theme.txt is "<name>|<owner/repo>"; we fetch manifest.json + theme.css from
# the repo's default branch (themes don't always publish releases).
obsidian_install_theme() {
    local vault="$1" line name repo themedir rc=0
    [ -f "$OB_CONFIG_DIR/theme.txt" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in '' | '#'*) continue ;; esac
        name="${line%%|*}"
        repo="${line##*|}"
        themedir="$vault/.obsidian/themes/$name"
        if [ -f "$themedir/theme.css" ]; then
            printf "  ${DIM}theme${RESET} %s: ${GREEN}present${RESET}\n" "$name"
            continue
        fi
        printf "  ${BLUE}theme${RESET} %s: downloading from %s\n" "$name" "$repo"
        mkdir -p "$themedir"
        rc=0
        curl -fsSL --retry 2 -o "$themedir/manifest.json" \
            "https://raw.githubusercontent.com/$repo/main/manifest.json" || rc=$?
        curl -fsSL --retry 2 -o "$themedir/theme.css" \
            "https://raw.githubusercontent.com/$repo/main/theme.css" || rc=$?
        if [ "$rc" -ne 0 ]; then
            printf "  ${RED}${FAIL_MARK}${RESET} theme %s: download failed (rc=%d)\n" "$name" "$rc"
            OB_FAILURES+=("theme: $name (rc=$rc)")
        else
            printf "  ${GREEN}${OK_MARK}${RESET} theme %s installed\n" "$name"
        fi
    done <"$OB_CONFIG_DIR/theme.txt"
}

# ─── Plugins ──────────────────────────────────────────────────────────────────

# obsidian_install_plugins VAULT — ensure every plugin in plugins.txt is on
# disk. Skips any plugin whose main.js already exists (presence check, not
# version check — freshness is chezbump's job).
#
# Each line is "<id>|<owner/repo>" or "<id>|<owner/repo>|<tag>". With a tag we
# fetch from that exact release (download/<tag>); without one we fetch
# /releases/latest/download. Use a tag when the repo's latest release is a beta
# whose manifest id differs from the community-store id (e.g. Calendar 2.x).
obsidian_install_plugins() {
    local vault="$1" line id repo tag dir base rc=0
    [ -f "$OB_CONFIG_DIR/plugins.txt" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in '' | '#'*) continue ;; esac
        # Split on |. Bash 3.2: no read -ra into associative; use cut.
        id="$(printf '%s' "$line" | cut -d'|' -f1)"
        repo="$(printf '%s' "$line" | cut -d'|' -f2)"
        tag="$(printf '%s' "$line" | cut -d'|' -f3)"
        dir="$vault/.obsidian/plugins/$id"
        if [ -f "$dir/main.js" ]; then
            printf "  ${DIM}plugin${RESET} %s: ${GREEN}present${RESET}\n" "$id"
            continue
        fi
        if [ -n "$tag" ]; then
            base="https://github.com/$repo/releases/download/$tag"
            printf "  ${BLUE}plugin${RESET} %s: downloading %s@%s\n" "$id" "$repo" "$tag"
        else
            base="https://github.com/$repo/releases/latest/download"
            printf "  ${BLUE}plugin${RESET} %s: downloading %s\n" "$id" "$repo"
        fi
        mkdir -p "$dir"
        rc=0
        curl -fsSL --retry 2 -o "$dir/manifest.json" "$base/manifest.json" || rc=$?
        curl -fsSL --retry 2 -o "$dir/main.js" "$base/main.js" || rc=$?
        # styles.css is optional — don't fail if 404.
        curl -fsSL --retry 2 -o "$dir/styles.css" "$base/styles.css" 2>/dev/null || rm -f "$dir/styles.css"
        if [ "$rc" -ne 0 ]; then
            printf "  ${RED}${FAIL_MARK}${RESET} plugin %s: download failed (rc=%d)\n" "$id" "$rc"
            OB_FAILURES+=("plugin: $id (rc=$rc)")
        else
            printf "  ${GREEN}${OK_MARK}${RESET} plugin %s installed\n" "$id"
        fi
    done <"$OB_CONFIG_DIR/plugins.txt"
}

# ─── Config + templates (seed-only) ───────────────────────────────────────────

# obsidian_seed_config VAULT — copy every file under vault-config/ into the
# vault's .obsidian/, preserving subdirs. Existing files are left alone.
obsidian_seed_config() {
    local vault="$1" src dst rel placed=0
    [ -d "$OB_CONFIG_DIR/vault-config" ] || return 0
    while IFS= read -r src; do
        rel="${src#"$OB_CONFIG_DIR/vault-config/"}"
        dst="$vault/.obsidian/$rel"
        if [ -e "$dst" ]; then
            continue
        fi
        if ob_seed_copy "$src" "$dst" ".obsidian/$rel"; then
            printf "  ${GREEN}seed${RESET} .obsidian/%s\n" "$rel"
            placed=$((placed + 1))
        fi
    done < <(find "$OB_CONFIG_DIR/vault-config" -type f)
    if [ "$placed" -eq 0 ]; then
        printf "  %sconfig: every canonical file already in vault%s\n" "$DIM" "$RESET"
    fi
}

# obsidian_seed_home VAULT — copy Home.md to the vault root if absent. The
# Homepage plugin opens this on launch (see plugins/homepage/data.json). Once
# in place we never overwrite — your dashboard edits are yours to keep.
obsidian_seed_home() {
    local vault="$1" src="$OB_CONFIG_DIR/Home.md" dst="$1/Home.md"
    [ -f "$src" ] || return 0
    if [ -e "$dst" ]; then
        printf "  %sHome.md: already in vault%s\n" "$DIM" "$RESET"
        return 0
    fi
    if ob_seed_copy "$src" "$dst" "Home.md"; then
        printf "  %sseed%s Home.md\n" "$GREEN" "$RESET"
    fi
}

# obsidian_seed_vault_guide VAULT — copy vault-guide.md to "99 Meta/Vault Guide.md"
# if absent. Linked from Home as the user-facing how-to. Same seed-only policy.
obsidian_seed_vault_guide() {
    local vault="$1" src="$OB_CONFIG_DIR/vault-guide.md"
    local dst="$vault/99 Meta/Vault Guide.md"
    [ -f "$src" ] || return 0
    if [ -e "$dst" ]; then
        printf "  %sVault Guide.md: already in vault%s\n" "$DIM" "$RESET"
        return 0
    fi
    if ob_seed_copy "$src" "$dst" "99 Meta/Vault Guide.md"; then
        printf "  %sseed%s 99 Meta/Vault Guide.md\n" "$GREEN" "$RESET"
    fi
}

# obsidian_seed_templates VAULT — copy every template into "99 Meta/_templates/".
obsidian_seed_templates() {
    local vault="$1" src dst name placed=0
    local tdir="$vault/99 Meta/_templates"
    [ -d "$OB_CONFIG_DIR/templates" ] || return 0
    for src in "$OB_CONFIG_DIR/templates/"*.md; do
        [ -f "$src" ] || continue
        name="$(basename "$src")"
        dst="$tdir/$name"
        if [ -e "$dst" ]; then
            continue
        fi
        if ob_seed_copy "$src" "$dst" "99 Meta/_templates/$name"; then
            printf "  ${GREEN}seed${RESET} 99 Meta/_templates/%s\n" "$name"
            placed=$((placed + 1))
        fi
    done
    if [ "$placed" -eq 0 ]; then
        printf "  %stemplates: every canonical template already in vault%s\n" "$DIM" "$RESET"
    fi
}

# obsidian_seed_readmes VAULT — seed each PARA folder's "_README.md" from
# folder-readmes/. Source files are named after their target folder verbatim
# (e.g. "20 Projects.md" → "20 Projects/_README.md"), so no lookup table is
# needed. mkdir -p also lays down the top-level folder structure on a fresh
# vault. Seed-only: an existing README is left untouched.
obsidian_seed_readmes() {
    local vault="$1" src name dst placed=0
    local rdir="$OB_CONFIG_DIR/folder-readmes"
    [ -d "$rdir" ] || return 0
    for src in "$rdir/"*.md; do
        [ -f "$src" ] || continue
        name="$(basename "$src" .md)" # e.g. "20 Projects"
        dst="$vault/$name/_README.md"
        if [ -e "$dst" ]; then
            continue
        fi
        if ob_seed_copy "$src" "$dst" "$name/_README.md"; then
            printf "  ${GREEN}seed${RESET} %s/_README.md\n" "$name"
            placed=$((placed + 1))
        fi
    done
    if [ "$placed" -eq 0 ]; then
        printf "  %sreadmes: every folder README already in vault%s\n" "$DIM" "$RESET"
    fi
}

# obsidian_seed_scripts VAULT — copy every user script into "99 Meta/_scripts/".
# These are QuickAdd/Templater helpers (e.g. file-note.js, the "File this…"
# mover) referenced by path from plugin config. Seed-only, same as templates.
obsidian_seed_scripts() {
    local vault="$1" src dst name placed=0
    local sdir="$vault/99 Meta/_scripts"
    [ -d "$OB_CONFIG_DIR/scripts" ] || return 0
    for src in "$OB_CONFIG_DIR/scripts/"*.js; do
        [ -f "$src" ] || continue
        name="$(basename "$src")"
        dst="$sdir/$name"
        if [ -e "$dst" ]; then
            continue
        fi
        if ob_seed_copy "$src" "$dst" "99 Meta/_scripts/$name"; then
            printf "  ${GREEN}seed${RESET} 99 Meta/_scripts/%s\n" "$name"
            placed=$((placed + 1))
        fi
    done
    if [ "$placed" -eq 0 ]; then
        printf "  %sscripts: every canonical user script already in vault%s\n" "$DIM" "$RESET"
    fi
}

# obsidian_seed_bases VAULT — copy every .base file to the vault root. Bases are
# core Obsidian database views (table/board over notes by property). Linked from
# Home for at-a-glance oversight. Seed-only, same policy as Home.md.
obsidian_seed_bases() {
    local vault="$1" src dst name placed=0
    [ -d "$OB_CONFIG_DIR/bases" ] || return 0
    for src in "$OB_CONFIG_DIR/bases/"*.base; do
        [ -f "$src" ] || continue
        name="$(basename "$src")"
        dst="$vault/$name"
        if [ -e "$dst" ]; then
            continue
        fi
        if ob_seed_copy "$src" "$dst" "$name"; then
            printf "  ${GREEN}seed${RESET} %s\n" "$name"
            placed=$((placed + 1))
        fi
    done
    if [ "$placed" -eq 0 ]; then
        printf "  %sbases: every canonical base already in vault%s\n" "$DIM" "$RESET"
    fi
}

# ─── Entry point ──────────────────────────────────────────────────────────────

# obsidian_apply — the full convergence. Returns 0 even when individual fetches
# fail; callers inspect OB_FAILURES.
obsidian_apply() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "! obsidian: curl missing, skipping"
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "! obsidian: python3 missing, skipping"
        return 0
    fi
    local vault
    vault="$(obsidian_find_vault)"
    if [ -z "$vault" ]; then
        echo "  ${DIM}no vault registered yet — open Obsidian and add one, then re-run \`chezup\`${RESET}"
        return 0
    fi
    if [ ! -d "$vault" ]; then
        echo "! obsidian: registered vault path doesn't exist: $vault"
        echo "  fix the path in ~/Library/Application Support/obsidian/obsidian.json or remove the entry"
        return 0
    fi
    printf "  ${DIM}vault:${RESET} %s\n" "$vault"
    obsidian_install_theme "$vault"
    obsidian_install_plugins "$vault"
    obsidian_seed_config "$vault"
    obsidian_seed_templates "$vault"
    obsidian_seed_scripts "$vault"
    obsidian_seed_bases "$vault"
    obsidian_seed_readmes "$vault"
    obsidian_seed_home "$vault"
    obsidian_seed_vault_guide "$vault"
    return 0
}
