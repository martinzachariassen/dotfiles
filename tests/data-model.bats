#!/usr/bin/env bats
# Guards for the V2 data model: the wizard's inlined module list, the module
# catalog, and the Brewfile map (single sources of truth in .chezmoidata/).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMPL="$REPO_ROOT/.chezmoi.toml.tmpl"
    MODULES_DATA="$REPO_ROOT/.chezmoidata/modules.toml"
    PACKAGES_DATA="$REPO_ROOT/.chezmoidata/packages.toml"
}

# The config template is rendered before .chezmoidata loads, so it must list the
# module names literally. That list MUST match the catalog keys, or a prompted
# module would have no label (and vice versa).
@test "wizard \$allModules matches [moduleCatalog] keys" {
    local tmpl_names catalog_names
    tmpl_names="$(grep -F '$allModules := list' "$TMPL" \
        | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u)"
    catalog_names="$(awk -F' *= *' '/^\[moduleCatalog\]/{f=1;next} /^\[/{f=0} f&&NF>1{print $1}' \
        "$MODULES_DATA" | sort -u)"
    [ -n "$tmpl_names" ]
    [ "$tmpl_names" = "$catalog_names" ]
}

# Every profile-default module name must be a real module.
@test "profile default module sets reference known modules" {
    local known defaults bad
    known="$(awk -F' *= *' '/^\[moduleCatalog\]/{f=1;next} /^\[/{f=0} f&&NF>1{print $1}' "$MODULES_DATA")"
    defaults="$(grep -E '\$defaults = list' "$TMPL" | grep -oE '"[a-zA-Z]+"' | tr -d '"' | sort -u)"
    bad=""
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        printf '%s\n' "$known" | grep -qx "$m" || bad="$bad $m"
    done <<<"$defaults"
    [ -z "$bad" ] || { echo "unknown modules in defaults:$bad"; false; }
}

# Every Brewfile path in the package catalog must exist on disk.
@test "packages.toml Brewfile paths all exist" {
    local path
    grep -oE '"[^"]+"' "$PACKAGES_DATA" | tr -d '"' | while IFS= read -r path; do
        [ -f "$REPO_ROOT/$path" ] || { echo "missing Brewfile: $path"; false; }
    done
}
