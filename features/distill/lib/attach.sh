#!/usr/bin/env bash
# Attaching a corpus to this Mac.
#
# --remote: pointing a state repo at a backup, adopting one that already exists,
# and refusing one whose scope does not match.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Attaching a corpus ───────────────────────────────────────────────────────

# distill_remote_survey URL — what is at the other end, before anything is
# changed. Prints "<populated> <branch> <scope> <id>"; populated is 0 or 1.
#
# The scope is read from either schema — a corpus written before the rename
# stamps it as `profile`, and surveying one as unstamped would wave it straight
# past the leak boundary below.
distill_remote_survey() {
    local url="$1" branch json scratch

    if ! branch="$(distill_remote_probe "$url")"; then
        printf '0  \n'
        return 0
    fi
    branch="$(distill_state_branch "$branch")"

    # Into a throwaway repo, not the state dir. `--remote` with no argument has to
    # answer before anything is created, and `-n` must not leave a git repo behind
    # on a machine that has none — surveying through the real one made a populated
    # corpus read as empty on exactly the machine most likely to be asking.
    scratch="$(mktemp -d)" || {
        printf '0 %s  \n' "$branch"
        return 0
    }
    distill_git_env
    if git -C "$scratch" init -q -b main >/dev/null 2>&1 &&
        git -C "$scratch" fetch --quiet --depth 1 "$url" "$branch" >/dev/null 2>&1; then
        json="$(git -C "$scratch" show FETCH_HEAD:corpus.json 2>/dev/null)"
        rm -rf "$scratch"
        printf '1 %s %s %s\n' "$branch" \
            "$(printf '%s' "$json" | jq -r '[.scope, .profile]
                | map(select(type == "string" and . != "")) | first // empty' 2>/dev/null)" \
            "$(printf '%s' "$json" | jq -r '.id // empty' 2>/dev/null)"
        return 0
    fi
    rm -rf "$scratch"
    printf '0 %s  \n' "$branch"
}

# distill_remote_detach — stop pushing, keep everything.
#
# Nothing is rewritten and nothing is deleted, so re-attaching later is the same
# one command. The marker is what stops the next run silently re-adopting.
distill_remote_detach() {
    local repo
    repo="$(distill_state_dir)"
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 0
    git -C "$repo" remote remove origin >/dev/null 2>&1 || true
    git -C "$repo" config distill.detached true >/dev/null 2>&1 || true
    ok "detached — the corpus stays here and stops being pushed anywhere"
    info "re-attach whenever with: chez distill --remote <url>"
    return 0
}

# distill_remote_attach URL — point this Mac's corpus at a backup repo.
#
# Four shapes, decided by what is at each end rather than by a flag:
#
#   remote empty                     push what is here, and this becomes the corpus
#   remote has a corpus, local none  check it out — the replacement-Mac restore
#   same corpus id, new URL          it only moved; re-point and carry on
#   both populated                   replay this Mac's shards onto the remote's
#                                    history
#
# The last is the interesting one, and it is a data replay rather than a history
# merge: nobody reads this git history, so origin's is taken as the base and this
# machine's extracts land on top as one commit. No unrelated-histories merge, no
# conflict markers, and nothing that can leave a rebase half-finished.
distill_remote_attach() {
    local url="$1" repo branch populated rscope rid mine tmp f base shard moved=0
    local local_populated=0
    repo="$(distill_state_dir)"
    mine="$(distill_scope)"

    distill_state_repo_init || return 1
    if distill_state_wedged >/dev/null; then
        fail "the corpus repo is stuck mid-operation — settle that first"
        return 1
    fi

    read -r populated branch rscope rid <<<"$(distill_remote_survey "$url")"
    branch="$(distill_state_branch "$branch")"

    # The leak boundary, checked before a single byte is sent.
    if [ -n "$rscope" ] && [ -n "$mine" ] && [ "$rscope" != "$mine" ]; then
        fail "that corpus is stamped $rscope and this is a $mine Mac — refusing"
        explain \
            "hits are counted over the whole corpus, so a rule seen twice in $rscope" \
            "sessions would be promoted into this Mac's MAIN.md. Keep one repo each."
        return 1
    fi

    git -C "$repo" remote remove origin >/dev/null 2>&1 || true
    git -C "$repo" remote add origin "$url" >/dev/null 2>&1 || {
        fail "could not point the corpus at $url"
        return 1
    }
    # A pushurl pinned to the PREVIOUS remote would silently keep pushing there.
    git -C "$repo" config --unset remote.origin.pushurl >/dev/null 2>&1 || true
    git -C "$repo" config --unset distill.detached >/dev/null 2>&1 || true
    distill_state_repo_pushurl

    if [ "${populated:-0}" != "1" ]; then
        distill_corpus_seed
        distill_state_repo_init >/dev/null || true
        git -C "$repo" add -A >/dev/null 2>&1 || true
        git -C "$repo" diff --cached --quiet 2>/dev/null ||
            git -C "$repo" commit -q -m "chore(corpus): start this corpus" >/dev/null 2>&1 || true
        git -C "$repo" push -q -u origin "HEAD:$branch" >/dev/null 2>&1 || {
            fail "could not push to $url"
            return 1
        }
        ok "attached — this Mac's corpus now backs up to $url"
        return 0
    fi

    distill_git_env
    git -C "$repo" fetch --quiet origin "$branch" >/dev/null 2>&1 || {
        fail "could not fetch $url"
        return 1
    }

    # Same corpus, new address: exactly the repo-rename case. Nothing to merge.
    if [ -n "$rid" ] && [ "$rid" = "$(distill_corpus_id)" ]; then
        git -C "$repo" branch --set-upstream-to "origin/$branch" >/dev/null 2>&1 || true
        distill_state_sync || true
        git -C "$repo" push -q -u origin "HEAD:$branch" >/dev/null 2>&1 || true
        ok "same corpus at a new address — re-pointed to $url"
        return 0
    fi

    # "Populated" means holding corpus data, NOT holding commits. A Mac that ran
    # local-only has shards on disk and no history at all, and its work counts
    # exactly as much as a committed machine's — classifying on HEAD would send it
    # down the restore path and quietly drop everything it had collected.
    local_populated=0
    for f in "$repo"/extracts/*.json; do
        [ -f "$f" ] && {
            local_populated=1
            break
        }
    done

    # Nothing of our own to keep: adopt origin's tree wholesale. --force is safe
    # and necessary here — the only untracked files in the way are the scaffolding
    # (README.md, .gitignore, Pinned.md, corpus.json) that state_repo_init just
    # generated, and the remote's copies of those are the ones that should win.
    if [ "$local_populated" = "0" ]; then
        git -C "$repo" checkout -q -B "$branch" --force "origin/$branch" >/dev/null 2>&1 || {
            fail "could not check out the corpus from $url"
            return 1
        }
        git -C "$repo" branch --set-upstream-to "origin/$branch" >/dev/null 2>&1 || true
        distill_state_repo_init >/dev/null || true
        ok "restored the corpus from $url"
        return 0
    fi

    # Both populated — replay. Keep this machine's shards aside, adopt origin's
    # history wholesale, then put them back, unioning any the two share.
    tmp="$(mktemp -d)" || return 1
    [ -d "$repo/extracts" ] && cp -R "$repo/extracts" "$tmp/extracts" 2>/dev/null
    git -C "$repo" rev-parse --quiet --verify HEAD >/dev/null 2>&1 &&
        git -C "$repo" tag -f "chezdistill/pre-attach" HEAD >/dev/null 2>&1

    if ! git -C "$repo" checkout -q -B "$branch" --force "origin/$branch" >/dev/null 2>&1; then
        rm -rf "$tmp"
        fail "could not adopt the history at $url"
        return 1
    fi
    git -C "$repo" branch --set-upstream-to "origin/$branch" >/dev/null 2>&1 || true

    mkdir -p "$repo/extracts"
    for f in "$tmp/extracts"/*.json; do
        [ -f "$f" ] || continue
        shard="$(basename "$f")"
        base="$repo/extracts/$shard"
        if [ -f "$base" ]; then
            distill_extract_union "$base" "$f" "$base" || {
                rm -rf "$tmp"
                fail "could not merge $shard"
                return 1
            }
        else
            cp "$f" "$base" 2>/dev/null || continue
        fi
        moved=$((moved + 1))
    done
    rm -rf "$tmp"

    distill_state_repo_init >/dev/null || true
    distill_guard_secrets || {
        fail "not pushing — the sweep found something. This Mac's corpus is at the tag chezdistill/pre-attach"
        return 1
    }

    git -C "$repo" add -A >/dev/null 2>&1 || true
    if ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
        git -C "$repo" commit -q -m "chore(corpus): replay $(distill_host) onto the shared corpus" \
            >/dev/null 2>&1 || true
    fi
    git -C "$repo" push -q -u origin "HEAD:$branch" >/dev/null 2>&1 || {
        fail "merged locally but could not push to $url — retry, or run chezdistill"
        return 1
    }
    ok "joined the corpus at $url — $moved shard(s) of this Mac's carried over"
    return 0
}
