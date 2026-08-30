#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_check_source_repo() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Is there a repo here at all, and is it behind origin? Everything after this
# check assumes a working tree, so it runs first.

doctor_check_source_repo() {
    section "Source repo"
    if [ -d "$SOURCE_DIR/.git" ]; then
        pass "repo at $SOURCE_DIR"
        if (cd "$SOURCE_DIR" && git fetch -q origin 2>/dev/null); then
            local_head=$(cd "$SOURCE_DIR" && git rev-parse @ 2>/dev/null || echo "")
            remote_head=$(cd "$SOURCE_DIR" && git rev-parse '@{u}' 2>/dev/null || echo "")
            if [ -n "$local_head" ] && [ "$local_head" = "$remote_head" ]; then
                pass "repo in sync with origin"
            elif [ -n "$local_head" ] && [ -n "$remote_head" ]; then
                warn "repo behind/ahead of origin — run \`chezup\` to sync"
            fi
        fi
        if (cd "$SOURCE_DIR" && [ -n "$(git status --porcelain 2>/dev/null)" ]); then
            warn "repo has uncommitted changes — run \`cd $SOURCE_DIR && git status\`"
        else
            pass "repo working tree clean"
        fi
    else
        fail "repo missing at $SOURCE_DIR — re-run install.sh"
    fi
}
