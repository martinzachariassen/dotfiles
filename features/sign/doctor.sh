#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_sign() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Two sections: who authors commits, and whether they are signed. They are
# adjacent because the second is meaningless without the first — an unsigned
# commit and a commit authored as "<>" are the same class of problem.

doctor_sign() {
    section "Commit author"
    git_email="$(git config --global user.email 2>/dev/null || true)"
    git_name="$(git config --global user.name 2>/dev/null || true)"
    if [ -n "$git_email" ]; then
        pass "git author: ${git_name:-?} <$git_email>"
    elif [ "$(git config --global user.useConfigOnly 2>/dev/null || true)" = "true" ]; then
        fail "no git email set — commits are blocked. Run \`chezsetup\` to add one"
        note "GitHub noreply address: github.com → Settings → Emails"
    else
        fail "no git email set, and nothing stops git inventing one — run \`chezsetup\`"
    fi

    section "Git signing (${SIGNING_MODE:-1password})"
    SSH_SIGN="${GIT_SIGNING_SSH_SIGN:-}"
    if [ "$SIGNING_MODE" = "off" ]; then
        note "signing disabled in setup (signingMode = off) — nothing to check"
    elif [ "$SIGNING_MODE" = "ssh-key" ]; then
        note "signing uses a plain SSH key (signingMode = ssh-key), not the 1Password agent"
    elif [ -z "$SSH_SIGN" ]; then
        warn "features/sign/lib.sh not readable — skipping the signing checks"
    elif [ -x "$SSH_SIGN" ]; then
        pass "op-ssh-sign present"
    else
        fail "op-ssh-sign missing — install 1Password app and enable SSH agent in Settings → Developer"
    fi
    gitkey=$(git config --global user.signingkey 2>/dev/null || true)
    if [ "$SIGNING_MODE" = "off" ]; then
        : # nothing configured by design
    elif [ -n "$gitkey" ]; then
        pass "git signing key configured"
        if [ "$(git config --global commit.gpgsign 2>/dev/null || true)" = "true" ]; then
            pass "git commit signing enabled"
        else
            warn "git commit.gpgsign is not true — run \`chezmoi apply\`"
        fi
        if [ "$(git config --global gpg.format 2>/dev/null || true)" = "ssh" ]; then
            pass "git SSH signing format configured"
        else
            warn "git gpg.format is not ssh — run \`chezmoi apply\`"
        fi
        # gpg.ssh.program is emitted only for signingMode = 1password (see
        # src/dot_config/git/config.tmpl); under ssh-key it is absent by design.
        if [ "$SIGNING_MODE" = "ssh-key" ]; then
            note "gpg.ssh.program not set — correct for signingMode = ssh-key"
        elif [ "$(git config --global gpg.ssh.program 2>/dev/null || true)" = "$SSH_SIGN" ]; then
            pass "git 1Password SSH signer configured"
        else
            warn "git gpg.ssh.program is not op-ssh-sign — run \`chezmoi apply\`"
        fi
        allowed_signers="$(git config --global --path gpg.ssh.allowedSignersFile 2>/dev/null || true)"
        if [ -n "$allowed_signers" ] && [ -f "$allowed_signers" ]; then
            pass "git allowed signers file present"
        else
            warn "git allowed signers file missing — run \`chezmoi apply\`"
        fi
    else
        warn "no git signing key set — run bootstrap-auth.sh after signing in to 1Password"
    fi
    # Smoke-test signing in a tmp repo (proves agent is reachable + key matches).
    # 1password mode only: the other modes have no agent to reach.
    if [ "$SIGNING_MODE" != "ssh-key" ] && [ "$SIGNING_MODE" != "off" ] &&
        [ -n "$SSH_SIGN" ] && [ -x "$SSH_SIGN" ] && [ -n "$gitkey" ]; then
        if git_signing_smoke_test; then
            pass "git signing works (commit -S succeeded)"
        else
            warn "git -S commit failed — is 1Password unlocked + SSH agent enabled?"
        fi
    fi
}
