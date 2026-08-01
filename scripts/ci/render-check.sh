#!/usr/bin/env bash
# Render all chezmoi templates with deterministic stub data.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
# $SOURCE_DIR stays the repo root so .chezmoi.workingTree resolves for hooks that
# reach root-level scripts/ + packages/; chezmoi's source is the src/ subdir.
SRC_DIR="$SOURCE_DIR/src"
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

mkdir -p "$tmpdir/.config/chezmoi"
cat >"$tmpdir/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SRC_DIR"

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
    echo "Checking rendered zsh syntax: exact_dot_config/zsh/dot_zshrc.tmpl"
    HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" chezmoi execute-template \
        --config="$tmpdir/.config/chezmoi/chezmoi.toml" \
        --destination="$tmpdir" \
        --source="$SRC_DIR" \
        --file "$SRC_DIR/exact_dot_config/zsh/dot_zshrc.tmpl" | zsh -n
    zsh -n "$SRC_DIR/dot_zshenv" "$SRC_DIR/exact_dot_config/zsh/dot_zprofile"
else
    echo "Skipping rendered zsh syntax check: zsh not installed"
fi
