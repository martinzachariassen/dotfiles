#!/usr/bin/env bats
# Tests for features/brew/lib/homebrew.sh, the shared Homebrew installer used by
# run_once_before_01-install-homebrew.sh.tmpl. install.sh keeps its own inline
# copy (it runs before the repo is cloned) — not covered here, see install.bats.

setup() {
    load '../../../core/testing/helper'
    HOMEBREW_LIB="$REPO_ROOT/features/brew/lib/homebrew.sh"
    [ -r "$HOMEBREW_LIB" ] || skip "homebrew.sh not found at $HOMEBREW_LIB"

    STUBS="$(mktemp -d)"
}

teardown() {
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

@test "homebrew.sh defines homebrew_install" {
    run bash -c "source '$HOMEBREW_LIB'; declare -F homebrew_install >/dev/null && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "homebrew.sh sets its source guard and is safe to re-source" {
    run bash -c "source '$HOMEBREW_LIB'; source '$HOMEBREW_LIB'; echo \"\${__DOTFILES_HOMEBREW_SH:-unset}\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "homebrew_install is a no-op when brew is already on PATH" {
    CURL_LOG="$STUBS/curl.log"
    cat >"$STUBS/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$STUBS/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CURL_LOG"
exit 0
EOF
    chmod +x "$STUBS/brew" "$STUBS/curl"

    run env PATH="$STUBS:$PATH" bash -c "source '$HOMEBREW_LIB'; homebrew_install"
    [ "$status" -eq 0 ]
    [ ! -f "$CURL_LOG" ]
}

@test "homebrew_install downloads and runs the installer when brew is missing" {
    CURL_LOG="$STUBS/curl.log"
    RAN_MARKER="$STUBS/installer-ran"
    # curl -o writes a fake installer script; the real one is never hit (network-free test).
    cat >"$STUBS/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CURL_LOG"
out=""
prev=""
for a in "\$@"; do
    [ "\$prev" = "-o" ] && out="\$a"
    prev="\$a"
done
cat > "\$out" <<'INNER'
#!/usr/bin/env bash
: > "$RAN_MARKER"
INNER
chmod +x "\$out"
exit 0
EOF
    chmod +x "$STUBS/curl"
    # No brew stub on PATH: command -v brew fails, so the install branch runs.
    run env PATH="$STUBS:/usr/bin:/bin" NONINTERACTIVE=1 bash -c "source '$HOMEBREW_LIB'; homebrew_install"
    [ "$status" -eq 0 ]
    grep -qF 'Homebrew/install/HEAD/install.sh' "$CURL_LOG"
    [ -f "$RAN_MARKER" ]
}
