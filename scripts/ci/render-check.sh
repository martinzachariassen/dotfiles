#!/usr/bin/env bash
# Render all chezmoi templates with deterministic stub data.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
# $SOURCE_DIR stays the repo root so .chezmoi.workingTree resolves; chezmoi's source is src/.
SRC_DIR="$SOURCE_DIR/src"
MAC_APPS="${MAC_APPS:-true}"
USE_ONE_PASSWORD="${USE_ONE_PASSWORD:-true}"

# The retired `profile` key, absent by default because no current template
# writes it. Set it and the stub config carries it, which is the only way to
# render the v0.8 migration hook's real body — with the key gone the hook
# renders to a bare `exit 0` and CI would never `bash -n` what it actually runs.
# One matrix row sets LEGACY_PROFILE=work for exactly that reason.
LEGACY_PROFILE="${LEGACY_PROFILE:-}"

case "$LEGACY_PROFILE" in
    "" | personal | work | minimal) ;;
    *)
        echo "LEGACY_PROFILE must be empty or one of: personal, work, minimal" >&2
        exit 2
        ;;
esac

case "$MAC_APPS" in
    true | false) ;;
    *)
        echo "MAC_APPS must be true or false" >&2
        exit 2
        ;;
esac

case "$USE_ONE_PASSWORD" in
    true | false) ;;
    *)
        echo "USE_ONE_PASSWORD must be true or false" >&2
        exit 2
        ;;
esac

# Explicit MODULES (comma-separated) wins; else derive from MAC_APPS. "none"/empty → [].
if [ -z "${MODULES+x}" ]; then
    MODULES=""
    [ "$MAC_APPS" = "true" ] && MODULES="macApps"
fi
[ "$MODULES" = "none" ] && MODULES=""
if [ -z "$MODULES" ]; then
    modules_toml="[]"
else
    modules_toml="$(printf '%s' "$MODULES" | awk -F, '{ out=""; for (i=1;i<=NF;i++) if ($i!="") { if (out!="") out=out", "; out=out"\""$i"\"" } printf "[%s]", out }')"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Emitted only when set: a `profile = ""` line would still be a profile key, and
# the resolver's fail-closed guard keys on the key's presence, not its value.
legacy_profile_line=""
if [ -n "$LEGACY_PROFILE" ]; then
    legacy_profile_line="    profile        = \"$LEGACY_PROFILE\""
fi

mkdir -p "$tmpdir/.config/chezmoi"
cat >"$tmpdir/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SRC_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    modules        = $modules_toml
    signingKey     = "ssh-ed25519 AAAAplaceholder"
$legacy_profile_line
    useOnePassword = $USE_ONE_PASSWORD

    [data.features]
        macApps   = $MAC_APPS
EOF

echo "Rendering chezmoi templates: modules=[${MODULES}] legacyProfile=${LEGACY_PROFILE:-none} macApps=$MAC_APPS useOnePassword=$USE_ONE_PASSWORD"
render_output="$tmpdir/chezmoi-render.out"
if ! HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi apply --dry-run \
    --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
    --destination="$tmpdir" \
    --source="$SRC_DIR" \
    --no-pager \
    --color=false >"$render_output" 2>&1; then
    cat "$render_output"
    exit 1
fi

# Drop the expected static-config-vs-.tmpl warning; keep all other output visible.
sed '/^chezmoi: warning: config file template has changed, run chezmoi init to regenerate config file$/d' "$render_output"

for template in "$SRC_DIR"/.chezmoiscripts/*.sh.tmpl; do
    [ -f "$template" ] || continue
    echo "Checking rendered bash syntax: ${template#"$SRC_DIR"/}"
    HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi execute-template \
        --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
        --destination="$tmpdir" \
        --source="$SRC_DIR" \
        --file "$template" | bash -n
done

if command -v zsh >/dev/null 2>&1; then
    echo "Checking rendered zsh syntax: dot_config/zsh/dot_zshrc.tmpl"
    HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi execute-template \
        --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
        --destination="$tmpdir" \
        --source="$SRC_DIR" \
        --file "$SRC_DIR/dot_config/zsh/dot_zshrc.tmpl" | zsh -n
    zsh -n "$SRC_DIR/dot_zshenv" "$SRC_DIR/dot_config/zsh/dot_zprofile"
else
    echo "Skipping rendered zsh syntax check: zsh not installed"
fi
