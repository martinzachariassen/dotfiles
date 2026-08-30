#!/usr/bin/env bash
# git-signing.sh — shared 1Password SSH-signing path + smoke test, used by
# doctor.sh and bootstrap-auth.sh.
# shellcheck disable=SC2034

[ -n "${__DOTFILES_GIT_SIGNING_SH:-}" ] && return 0
__DOTFILES_GIT_SIGNING_SH=1

GIT_SIGNING_SSH_SIGN=/Applications/1Password.app/Contents/MacOS/op-ssh-sign

# git_signing_smoke_test — commits --allow-empty -S in a throwaway repo to
# prove the SSH agent is reachable and the configured key matches. Cleans up
# its tmpdir regardless of outcome.
git_signing_smoke_test() {
    local tmpdir status=1
    tmpdir=$(mktemp -d)
    if (
        cd "$tmpdir" &&
            git init -q -b main &&
            git -c user.email=signing-smoke-test@local -c user.name="Signing Smoke Test" commit \
                --allow-empty --quiet -S -m signing-smoke-test 2>&1
    ) >/dev/null 2>&1; then
        status=0
    fi
    rm -rf "$tmpdir"
    return "$status"
}
