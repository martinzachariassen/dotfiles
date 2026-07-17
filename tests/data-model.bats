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

# The config template is rendered before .chezmoidata loads, so it must list the
# module names literally. That list MUST match the catalog keys, or a prompted
# module would have no label (and vice versa).
@test "wizard \$allModules matches [moduleCatalog] keys" {
    local tmpl_names catalog_names
    tmpl_names="$(grep -F '$allModules := list' "$TMPL" \
        | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u)"
    catalog_names="$(awk -F' *= *' '/^\[moduleCatalog\]/{f=1;next} /^\[/{f=0} f&&$1~/^[A-Za-z]/{print $1}' \
        "$MODULES_DATA" | sort -u)"
    [ -n "$tmpl_names" ]
    [ "$tmpl_names" = "$catalog_names" ]
}

# Every profile-default module name must be a real module.
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

# scripts/bin/wizard.sh composes each profile's default module set from
# [profileDefaults] in modules.toml (base ∪ extra, gated by inherit); the config
# template restates the same effective sets literally (it renders before
# .chezmoidata loads). They MUST agree per profile, or the wizard and a raw
# `chezmoi init --prompt` would pre-check different boxes. We compare against the
# wizard's own profile_defaults so the composition rule lives in exactly one place.
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

# Every module name across the profileDefaults tables (base + per-profile extra)
# must be a real catalog module. The inherit table holds bare bools, not quoted
# names, so it contributes nothing to this scan.
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

# Every Brewfile path in the package catalog must exist on disk.
@test "packages.toml Brewfile paths all exist" {
    local path
    grep -oE '"[^"]+"' "$PACKAGES_DATA" | tr -d '"' | while IFS= read -r path; do
        [ -f "$REPO_ROOT/$path" ] || { echo "missing Brewfile: $path"; false; }
    done
}
