#!/usr/bin/env bats
# Guards for the V2 data model: the wizard's inlined module list, the module
# catalog, and the Brewfile map (single sources of truth in .chezmoidata/).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMPL="$REPO_ROOT/src/.chezmoi.toml.tmpl"
    MODULES_DATA="$REPO_ROOT/src/.chezmoidata/modules.toml"
    PACKAGES_DATA="$REPO_ROOT/src/.chezmoidata/packages.toml"
    WIZ="$REPO_ROOT/scripts/bin/wizard.sh"
}

# Rendered before .chezmoidata loads, so the template lists module names
# literally — must match catalog keys or a prompted module has no label.
@test "wizard \$allModules matches [moduleCatalog] keys" {
    local tmpl_names catalog_names
    tmpl_names="$(grep -F '$allModules := list' "$TMPL" \
        | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u)"
    catalog_names="$(awk -F' *= *' '/^\[moduleCatalog\]/{f=1;next} /^\[/{f=0} f&&$1~/^[A-Za-z]/{print $1}' \
        "$MODULES_DATA" | sort -u)"
    [ -n "$tmpl_names" ]
    [ "$tmpl_names" = "$catalog_names" ]
}

@test "profile default module sets reference known modules" {
    local known defaults bad
    known="$(awk -F' *= *' '/^\[moduleCatalog\]/{f=1;next} /^\[/{f=0} f&&$1~/^[A-Za-z]/{print $1}' "$MODULES_DATA")"
    defaults="$(grep -E '\$defaults = list' "$TMPL" | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u)"
    bad=""
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        printf '%s\n' "$known" | grep -qx "$m" || bad="$bad $m"
    done <<<"$defaults"
    [ -z "$bad" ] || { echo "unknown modules in defaults:$bad"; false; }
}

# wizard.sh composes defaults from [profileDefaults] (base ∪ extra, gated by
# inherit); the template must restate the same per-profile set or the wizard
# and a raw `chezmoi init --prompt` would pre-check different boxes.
@test "[profileDefaults] mirrors the template's \$defaults per profile" {
    local p tmpl data
    for p in personal work minimal; do
        tmpl="$(sed -nE '/eq [$]profile "'"$p"'"/{n;p;}' "$TMPL" \
            | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u | tr '\n' ' ')"
        data="$(WIZARD_LIB_ONLY=1 bash -c "source '$WIZ'; profile_defaults '$p'" \
            | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
        [ "$tmpl" = "$data" ] || {
            echo "profile $p: template=[$tmpl] data=[$data]"
            false
        }
    done
}

# The inherit table holds bare bools, not quoted names, so it contributes
# nothing to this scan.
@test "[profileDefaults] entries reference known modules" {
    local known bad m
    known="$(awk -F' *= *' '/^\[moduleCatalog\]/{f=1;next} /^\[/{f=0} f&&$1~/^[A-Za-z]/{print $1}' "$MODULES_DATA")"
    bad=""
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        printf '%s\n' "$known" | grep -qx "$m" || bad="$bad $m"
    done < <(awk '/^\[profileDefaults/{f=1;next} /^\[/{f=0} f' "$MODULES_DATA" \
        | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u)
    [ -z "$bad" ] || { echo "unknown modules in profileDefaults:$bad"; false; }
}

@test "packages.toml Brewfile paths all exist" {
    local path
    grep -oE '"[^"]+"' "$PACKAGES_DATA" | tr -d '"' | while IFS= read -r path; do
        [ -f "$REPO_ROOT/$path" ] || { echo "missing Brewfile: $path"; false; }
    done
}

# ─── sourceDir must follow the clone, not a hardcoded path ──────────────────
# install.sh, wizard.sh, chezup.sh and doctor.sh all honour DOTFILES_DIR, and
# docs/install.md advertises it. A hardcoded sourceDir made the wizard write a
# config pointing at a directory that need not exist, breaking every later bare
# `chezmoi` call on a non-default clone.
@test "sourceDir is derived from the checkout, not hardcoded" {
    grep -qF 'sourceDir = {{ .chezmoi.workingTree | quote }}' "$TMPL"
    ! grep -qE 'sourceDir.*Developer/personal/dotfiles' "$TMPL"
}

# ─── Docs must not promise behaviour install.sh does not have ───────────────
# README and docs/install.md described a timestamped backup of legacy dotfiles
# and a SKIP_BACKUP=1 escape hatch. Neither ever existed, while the first apply
# really does delete ~/.zshrc, ~/.gitconfig and friends via the remove_* entries.
@test "no doc advertises an install.sh backup that does not exist" {
    if grep -rqF 'SKIP_BACKUP' "$REPO_ROOT/install.sh"; then
        skip "install.sh implements SKIP_BACKUP — the docs may describe it"
    fi
    ! grep -rqF 'SKIP_BACKUP' "$REPO_ROOT/README.md" "$REPO_ROOT/docs"
}

# The remove_* sources are what makes the "no backup" warning load-bearing.
@test "the legacy dotfiles the docs name are really declared for removal" {
    for f in dot_zshrc dot_gitconfig dot_bash_profile dot_bashrc dot_profile dot_zprofile; do
        [ -f "$REPO_ROOT/src/remove_$f" ] || {
            echo "docs/install.md names ~/.${f#dot_} as removed, but src/remove_$f is gone"
            return 1
        }
    done
}
