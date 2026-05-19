#!/usr/bin/env bash
# Render all chezmoi templates with deterministic stub data.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
PROFILE="${PROFILE:-both}"
MAC_APPS="${MAC_APPS:-true}"
AI="${AI:-false}"
USE_ONE_PASSWORD="${USE_ONE_PASSWORD:-true}"

case "$PROFILE" in
    personal|work|both) ;;
    *) echo "PROFILE must be one of: personal, work, both" >&2; exit 2 ;;
esac

case "$MAC_APPS" in
    true|false) ;;
    *) echo "MAC_APPS must be true or false" >&2; exit 2 ;;
esac

case "$AI" in
    true|false) ;;
    *) echo "AI must be true or false" >&2; exit 2 ;;
esac

case "$USE_ONE_PASSWORD" in
    true|false) ;;
    *) echo "USE_ONE_PASSWORD must be true or false" >&2; exit 2 ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/.config/chezmoi"
cat > "$tmpdir/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SOURCE_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    signingKey     = "ssh-ed25519 AAAAci-placeholder"
    profile        = "$PROFILE"
    useOnePassword = $USE_ONE_PASSWORD

    [data.features]
        macApps   = $MAC_APPS
        ai        = $AI
EOF

echo "Rendering chezmoi templates: profile=$PROFILE macApps=$MAC_APPS ai=$AI useOnePassword=$USE_ONE_PASSWORD"
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
