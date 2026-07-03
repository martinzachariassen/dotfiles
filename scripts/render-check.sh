#!/usr/bin/env bash
# Render all chezmoi templates with deterministic stub data.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
PROFILE="${PROFILE:-personal}"
MAC_APPS="${MAC_APPS:-true}"
USE_ONE_PASSWORD="${USE_ONE_PASSWORD:-true}"

case "$PROFILE" in
    personal | work | minimal) ;;
    *)
        echo "PROFILE must be one of: personal, work, minimal" >&2
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

# Build the modules TOML array. Explicit MODULES (comma-separated) wins; else
# derive from MAC_APPS for back-compat. "none" or empty yields an empty list.
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

mkdir -p "$tmpdir/.config/chezmoi"
cat >"$tmpdir/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SOURCE_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    modules        = $modules_toml
    signingKey     = "ssh-ed25519 AAAAplaceholder"
    profile        = "$PROFILE"
    useOnePassword = $USE_ONE_PASSWORD

    [data.features]
        macApps   = $MAC_APPS
EOF

echo "Rendering chezmoi templates: profile=$PROFILE macApps=$MAC_APPS useOnePassword=$USE_ONE_PASSWORD"
render_output="$tmpdir/chezmoi-render.out"
if ! HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi apply --dry-run \
    --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
    --destination="$tmpdir" \
    --source="$SOURCE_DIR" \
    --no-pager \
    --color=false >"$render_output" 2>&1; then
    cat "$render_output"
    exit 1
fi

# The test fixture intentionally supplies a static chezmoi.toml while the repo
# contains .chezmoi.toml.tmpl. That warning is expected here; any other output
# is still shown so real render drift remains visible.
sed '/^chezmoi: warning: config file template has changed, run chezmoi init to regenerate config file$/d' "$render_output"

for template in "$SOURCE_DIR"/.chezmoiscripts/*.sh.tmpl; do
    [ -f "$template" ] || continue
    echo "Checking rendered bash syntax: ${template#"$SOURCE_DIR"/}"
    HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi execute-template \
        --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
        --destination="$tmpdir" \
        --source="$SOURCE_DIR" \
        --file "$template" | bash -n
done

if command -v zsh >/dev/null 2>&1; then
    echo "Checking rendered zsh syntax: dot_config/zsh/dot_zshrc.tmpl"
    HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi execute-template \
        --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
        --destination="$tmpdir" \
        --source="$SOURCE_DIR" \
        --file "$SOURCE_DIR/dot_config/zsh/dot_zshrc.tmpl" | zsh -n
    zsh -n "$SOURCE_DIR/dot_zshenv" "$SOURCE_DIR/dot_config/zsh/dot_zprofile"
else
    echo "Skipping rendered zsh syntax check: zsh not installed"
fi
