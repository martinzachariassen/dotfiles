#!/usr/bin/env bats
# Guards for the V2 data model: the wizard's inlined module list, the module
# catalog, and the Brewfile map (single sources of truth in .chezmoidata/).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMPL="$REPO_ROOT/src/.chezmoi.toml.tmpl"
    MODULES_DATA="$REPO_ROOT/src/.chezmoidata/modules.toml"
    PACKAGES_DATA="$REPO_ROOT/src/.chezmoidata/brew.toml"
    WIZ="$REPO_ROOT/features/setup/cli.sh"
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

# ─── modulesSeen: the key chez up's new-module gate reads and writes ─────────
# A key the template doesn't emit is wiped by the next `chezmoi init`, so this
# one has to be both emitted and round-tripped through `dig`. Without that,
# chez up would re-offer every declined module after any `chez setup` run.
@test "the config template emits and round-trips modulesSeen" {
    grep -qE '^ +modulesSeen += +\[\{\{ range' "$TMPL"
    grep -qF 'dig "modulesSeen"' "$TMPL"
}

# On a fresh init the wizard showed every box, so nothing is new; on a machine
# whose config predates the key, only what it already has counts as seen and
# the rest gets its one offer. `profile` discriminates the two — it has been in
# [data] since v1, so its absence uniquely means "never initialised".
@test "modulesSeen defaults to the whole catalog only on a fresh init" {
    grep -qF 'hasKey . "profile"' "$TMPL"
    grep -qF '$seenDefault = $allModules' "$TMPL"
    grep -qF '$seenDefault := $modules' "$TMPL"
}

# core/modules.sh rewrites these two lines in the *generated* config, so
# its rendering must be byte-identical to the template's or an edit and a later
# init would fight over formatting. Same range expression = same output.
@test "modules and modulesSeen render through the same array expression" {
    local shape
    shape="$(grep -E '^ +modules(Seen)? += +\[\{\{ range' "$TMPL" \
        | sed -E 's/^ +modules(Seen)? += +//; s/[$]modulesSeen/VAR/g; s/[$]modules/VAR/g' \
        | sort -u)"
    [ "$(printf '%s\n' "$shape" | grep -c .)" -eq 1 ]
    # …and that shape is what modules_toml_array emits.
    run bash -c ". '$REPO_ROOT/core/modules.sh'; modules_toml_array a b"
    [ "$output" = '["a", "b"]' ]
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

@test "brew.toml Brewfile paths all exist" {
    local path
    grep -oE '"[^"]+"' "$PACKAGES_DATA" | tr -d '"' | while IFS= read -r path; do
        [ -f "$REPO_ROOT/$path" ] || { echo "missing Brewfile: $path"; false; }
    done
}

# ─── sourceDir must follow the clone, not a hardcoded path ──────────────────
# install.sh, setup/cli.sh, converge/up.sh and the doctor runner all honour DOTFILES_DIR, and
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

# ─── the corpus remote ────────────────────────────────────────────────────────
#
# Blank means "local only", which is a permanent legitimate answer — so it must
# be PERSISTED, the way signingKey is, and not omitted the way email deliberately
# is. Omitting it would make chez setup re-ask forever on every local-only Mac.
@test "a blank corpusRemote is persisted as a real answer" {
    grep -q 'corpusRemote = {{ \$corpusRemote | quote }}' "$TMPL"
    # ...and is NOT wrapped in the emptiness guard email uses.
    run grep -c '{{- if \$corpusRemote }}' "$TMPL"
    [ "$output" = "0" ]
}

# It is asked unconditionally in the template even though the wizard only shows
# the question when claudeDistiller is on: gating the TEMPLATE would mean a Mac
# that enables the module later never gets asked at all.
@test "corpusRemote is prompted unconditionally in the template" {
    grep -q 'promptStringOnce . "corpusRemote"' "$TMPL"
}

# promptStringOnce with no default hands back the prompt MESSAGE when it cannot
# ask — which is every non-interactive path, CI included — so the message itself
# would be saved and then used as a git URL. The trailing "" is what stops that.
@test "corpusRemote has an explicit blank default" {
    grep -q 'promptStringOnce . "corpusRemote" "[^"]*" ""' "$TMPL"
    command -v chezmoi >/dev/null || skip "chezmoi not installed"
    run chezmoi execute-template --init <"$TMPL"
    [ "$status" -eq 0 ]
    [[ "$output" == *'corpusRemote = ""'* ]] || return 1
}

# The public repo must not carry anyone's private corpus URLs.
@test "no corpus remote is hardcoded in the data files" {
    run grep -rn "claude-memory" "$BATS_TEST_DIRNAME/../src/.chezmoidata/"
    [ "$status" -ne 0 ]
}
