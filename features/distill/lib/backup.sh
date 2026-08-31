#!/usr/bin/env bash
# The state repo, and pushing it somewhere.
#
# One repo: the state dir. It exists so --undo still means something, since the
# memory tier is derived and can always be re-rendered from the corpus.
#
# Nothing outside this feature uses it, so it lives here rather than in core/ —
# the rule is that core/ holds what no single feature owns.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Git ──────────────────────────────────────────────────────────────────────
#
# One repo: the state dir. It exists so `--undo` still means something, since the
# memory tier is derived and can always be re-rendered from the corpus. Its
# remote comes from setup, so the corpus survives the machine without
# anyone opting in. This path never touches the repo this script ships in.

# Never let the network block a headless job. Without these an unreachable remote
# makes git sit on an SSH or credential prompt forever, and a launchd job has no
# terminal to answer it — the run hangs until the machine is rebooted.
distill_git_env() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/usr/bin/true
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
}

# distill_state_branch [OVERRIDE] — the branch this corpus lives on, named out
# loud.
#
# Nothing here used to name one, which worked only by luck. `git init` follows
# `init.defaultBranch`, so a Mac that sets it to `main` and a runner that sets
# nothing — and so gets `master` — disagree about what to fetch, check out and
# push, and the disagreement surfaces as a push that is rejected forever. Prefer
# what the remote already calls it, then what this repo is already on.
distill_state_branch() {
    local repo b="${1:-}"
    [ -n "$b" ] && {
        printf '%s\n' "$b"
        return 0
    }
    repo="$(distill_state_dir)"
    b="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    [ -n "$b" ] || b="$(git -C "$repo" config --get init.defaultBranch 2>/dev/null)"
    printf '%s\n' "${b:-main}"
}

# distill_remote_probe URL — one network call, two answers: has this remote
# anything in it yet, and what does it call its default branch?
#
# Exit 1 means empty, unreachable or unreadable — every caller treats those the
# same way, because none of them can fetch in any of those cases. Exit 0 prints
# the branch name (possibly empty, if the remote publishes no symbolic HEAD).
distill_remote_probe() {
    local url="$1" out
    [ -n "$url" ] || return 1
    distill_git_env
    out="$(git ls-remote --symref "$url" HEAD 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    printf '%s\n' "$out" |
        sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p' | head -n1
    return 0
}

# distill_state_wedged — is the corpus repo stuck mid-rebase or mid-merge?
#
# Left behind by the `push || pull --rebase || push` fallback this file used to
# use: when the rebase stopped, `.git/rebase-merge` stayed and HEAD was detached,
# so every later run committed onto a branch that no longer pointed anywhere and
# pushed nothing. It ran that way for two days on this machine, reporting a green
# tick throughout.
#
# Deliberately only detected, never repaired. `--abort` would restore the branch
# but overwrite the working copy of files an older layout tracked; `--quit` would
# keep the tree but drop whatever had not been replayed yet — and that can be
# corpus nobody else has. Both are judgement calls, so this says so and stops.
distill_state_wedged() {
    local repo gd
    repo="$(distill_state_dir)"
    gd="$(git -C "$repo" rev-parse --git-dir 2>/dev/null)" || return 1
    case "$gd" in /*) ;; *) gd="$repo/$gd" ;; esac

    if [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; then
        printf 'rebase\n'
        return 0
    fi
    [ -f "$gd/MERGE_HEAD" ] && {
        printf 'merge\n'
        return 0
    }
    [ -f "$gd/CHERRY_PICK_HEAD" ] && {
        printf 'cherry-pick\n'
        return 0
    }

    # The state the machine was actually found in: `rebase --quit` clears the
    # directory above but leaves HEAD detached, and a detached HEAD accepts
    # commits happily — they just belong to no branch and push nowhere. An
    # unborn branch is not detached, so check that HEAD resolves first.
    if git -C "$repo" rev-parse --quiet --verify HEAD >/dev/null 2>&1 &&
        ! git -C "$repo" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
        printf 'detached\n'
        return 0
    fi
    return 1
}

# distill_state_sync — reconcile with the remote, atomically or not at all.
#
# Merge, not rebase. Nobody reads this history — `--undo` walks back one commit
# and the memory tier is derived — so rebase buys nothing and has exactly one
# failure mode, the one above. A merge either succeeds or is undone whole by
# `--abort`. Extract shards are per-host, so in the ordinary two-Mac case the
# merge is a union of files that do not overlap.
distill_state_sync() {
    local repo branch wedge
    repo="$(distill_state_dir)"

    if wedge="$(distill_state_wedged)"; then
        distill_warn "the corpus repo is stuck mid-$wedge — not syncing until that is settled"
        return 1
    fi

    branch="$(distill_state_branch)"
    distill_git_env
    git -C "$repo" fetch --quiet origin "$branch" >/dev/null 2>&1 || return 1
    git -C "$repo" rev-parse --quiet --verify "origin/$branch" >/dev/null 2>&1 || return 0

    git -C "$repo" merge --quiet --ff-only "origin/$branch" >/dev/null 2>&1 && return 0

    if ! git -C "$repo" merge --quiet --no-edit "origin/$branch" >/dev/null 2>&1; then
        git -C "$repo" merge --abort >/dev/null 2>&1 || true
        distill_warn "the corpus and its remote have diverged in a way that needs a hand"
        return 1
    fi
    return 0
}

# distill_backup_state — is the corpus actually reaching its remote?
#
# The question `--status` never asked. It printed the remote's URL and called
# that a pass, so a push that had been failing for days still rendered as backed
# up. Read-only and offline — it compares what is committed against what was last
# known to be on the remote, so it is safe for `--status` and `chez doctor`.
#
# Prints one verdict: no-repo · no-remote · wedged · no-upstream · synced ·
# ahead N · behind N · diverged N M.
distill_backup_state() {
    local repo branch counts ahead behind
    repo="$(distill_state_dir)"

    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
        printf 'no-repo\n'
        return 0
    }
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || {
        printf 'no-remote\n'
        return 0
    }
    distill_state_wedged >/dev/null && {
        printf 'wedged\n'
        return 0
    }

    branch="$(distill_state_branch)"
    counts="$(git -C "$repo" rev-list --left-right --count \
        "origin/$branch...HEAD" 2>/dev/null)" || {
        printf 'no-upstream\n'
        return 0
    }
    [ -n "$counts" ] || {
        printf 'no-upstream\n'
        return 0
    }

    behind="${counts%%[[:space:]]*}"
    ahead="${counts##*[[:space:]]}"
    if [ "${behind:-0}" -gt 0 ] && [ "${ahead:-0}" -gt 0 ]; then
        printf 'diverged %s %s\n' "$ahead" "$behind"
    elif [ "${ahead:-0}" -gt 0 ]; then
        printf 'ahead %s\n' "$ahead"
    elif [ "${behind:-0}" -gt 0 ]; then
        printf 'behind %s\n' "$behind"
    else
        printf 'synced\n'
    fi
    return 0
}

# distill_state_restore — put an existing corpus back on a machine that has none.
#
# The half that was only ever described. Its absence is why a rebuilt Mac never
# came back: `git init` starts an unrelated history, so the first push is rejected
# as non-fast-forward and so is every one after it, forever, while the corpus it
# was meant to inherit sits on the remote untouched.
#
# Fetch and check out rather than `git clone`, because by the time this runs the
# state dir is not empty — cursor.json, logs/ and today's extracts are already in
# it, and clone refuses a non-empty target.
#
# Only for a repo with no commits of its own. One that already has a history is
# reconciled by distill_state_sync; if that history is unrelated to the remote's
# there is no safe automatic answer, so it says so rather than picking one.
distill_state_restore() {
    local repo branch remote
    repo="$(distill_state_dir)"

    git -C "$repo" rev-parse --quiet --verify HEAD >/dev/null 2>&1 && return 0

    remote="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 0
    [ -n "$remote" ] || return 0

    branch="$(distill_remote_probe "$remote")" || return 0
    branch="$(distill_state_branch "$branch")"

    distill_git_env
    git -C "$repo" fetch --quiet origin "$branch" >/dev/null 2>&1 || return 0
    git -C "$repo" rev-parse --quiet --verify "origin/$branch" >/dev/null 2>&1 || return 0

    # Git refuses this rather than overwriting an untracked file that the remote
    # also has — a same-host, same-day rebuild is the only way that happens, and
    # refusing is the right answer: the local copy is this machine's own work.
    git -C "$repo" checkout -q -B "$branch" --track "origin/$branch" >/dev/null 2>&1 || {
        distill_warn "could not restore the corpus from $remote without overwriting local work"
        return 0
    }
    info "restored the corpus from $remote"
    return 0
}
