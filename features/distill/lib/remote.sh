#!/usr/bin/env bash
# Which corpus is this Mac's.
#
# Resolving the seed against what git already believes. `git remote origin` is
# the authority once a Mac is attached; the prompted seed only ever bootstraps.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Which corpus is this Mac's? ──────────────────────────────────────────────
#
# Not a table in this repo. This repo is PUBLIC, and a table of corpus URLs here
# is two private repo names shipped to everyone who clones it, plus a default a
# fork inherits and cannot use. Every other per-person value — name, email,
# signing key — is prompted and defaults to blank for exactly that reason.
#
# So there are three layers and only one of them is authoritative:
#
#   corpusRemote (prompted, blank)  a SEED, used only to point a state repo that
#                                   has no origin. Never consulted again.
#   git remote origin               THE AUTHORITY. Already per-machine, already
#                                   persistent, already outside this repo.
#   corpus.json                     identity, and the guard — see above.
#
# That split is what makes an already-attached Mac need no answer at all: origin
# is set, so it IS the answer, and nothing has to write back into a chezmoi
# config that is generated. Blank is a real, permanent answer meaning local only.

# distill_remote_seed — the URL setup was given for this Mac, if any. Read like
# distill_profile, from the prompted answers rather than the .distill table, so
# it must stay a TOP-LEVEL key: prompted answers and .chezmoidata share one flat
# namespace and have to stay disjoint.
distill_remote_seed() {
    if [ -n "${DISTILL_CORPUS_REMOTE:-}" ]; then
        printf '%s\n' "$DISTILL_CORPUS_REMOTE"
        return 0
    fi
    _distill_data | jq -r '.corpusRemote // empty' 2>/dev/null
}

# distill_remote_id URL — host/owner/repo, lowercased.
#
# No longer a guard — corpus.json is. It survives as a string normaliser with two
# callers: the state README, which is tracked and would otherwise flap between
# two Macs spelling one remote differently, and the advisory that notices the
# seed naming a different repo than origin. Do not promote it back into a safety
# check: comparing URLs is precisely what failed when the repo was renamed.
distill_remote_id() {
    local u="$1"
    u="${u%.git}"
    u="${u%/}"
    u="${u#https://}"
    u="${u#http://}"
    u="${u#ssh://}"
    u="${u#git://}"
    u="${u#*@}" # git@host, or a token baked into an https URL
    u="${u/://}"
    printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'
}

# distill_remote_adopt — point a remote-less state repo at the seed setup was
# given. Never overwrites: origin is the authority, and an origin that is already
# set was set by someone.
distill_remote_adopt() {
    local repo url
    repo="$(distill_state_dir)"
    [ -z "$(git -C "$repo" remote 2>/dev/null)" ] || return 0
    # `chez distill --remote none` is a decision, not a gap to be filled in. Without
    # this the next run would silently re-attach what was just detached.
    distill_corpus_detached && return 0
    url="$(distill_remote_seed)"
    [ -n "$url" ] || return 0
    git -C "$repo" remote add origin "$url" >/dev/null 2>&1 || return 0
    info "corpus backup set to $url"
}

# distill_remote_drift — the seed names one repo and origin is another.
#
# Advisory, never a refusal. The most likely person to answer the prompt is
# someone whose Mac is ALREADY attached, where the seed is by design ignored —
# so without this the answer would silently do nothing. Compared through
# distill_remote_id so two spellings of one repo do not read as drift.
distill_remote_drift() {
    local cur seed
    cur="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null)" || return 1
    seed="$(distill_remote_seed)"
    [ -n "$cur" ] && [ -n "$seed" ] || return 1
    [ "$(distill_remote_id "$cur")" = "$(distill_remote_id "$seed")" ] && return 1
    printf '%s\n' "$seed"
    return 0
}

# distill_state_repo_pushurl — push this repo over the URL it was cloned from.
#
# A global `url.git@github.com:.pushinsteadof https://github.com/` rewrites every
# HTTPS push to SSH, and this machine's SSH key lives behind 1Password. At 01:00
# the Mac is asleep or locked, so the agent is locked, so the push fails and the
# corpus quietly stops leaving the machine until someone runs the job by hand —
# which is the opposite of what a backup is for.
#
# Pinning the push URL to the fetch URL opts this one repo out of that rewrite.
# It is set only when the remote is already HTTPS and no push URL was configured,
# so an SSH remote is left exactly as the user set it up.
distill_state_repo_pushurl() {
    local repo fetch
    repo="$(distill_state_dir)"
    fetch="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 0
    case "$fetch" in https://*) ;; *) return 0 ;; esac
    [ -z "$(git -C "$repo" config --get remote.origin.pushurl 2>/dev/null)" ] || return 0
    git -C "$repo" config remote.origin.pushurl "$fetch" >/dev/null 2>&1 || true
}

# distill_commit_local MESSAGE — commit the state dir, and push to the profile's
# corpus remote. The commit is what matters and it is made first, so the network
# can never cost you a night's work: a failed push is reported and retried by the
# next run, never treated as a failed run.
#
# Only state is tracked, not memory. MAIN.md, Topics/ and Candidates.md are a
# pure function of the extract corpus, so reverting the inputs and
# re-rendering puts the memory tier back exactly — which is what `--undo` does.
# Versioning derived output alongside its input would just be two copies of the
# same decision, free to disagree.
distill_commit_local() {
    local repo="" msg="$1" branch="" wedge=""
    repo="$(distill_state_dir)"
    [ "${DRY_RUN:-0}" = "1" ] && {
        dim "dry-run \$ git -C $repo commit -m '$msg'"
        return 0
    }
    [ -d "$repo" ] || return 0

    distill_state_repo_init || return 0

    # Before `add -A`, not after. A wedged repo takes commits without complaint —
    # onto a detached HEAD, or on top of a half-finished rebase — and that is
    # precisely how two days of nightly runs ended up on a branch that did not
    # exist. Leaving the work uncommitted on disk loses nothing: the corpus is
    # the files, and the next run commits them once the repo is untangled.
    if wedge="$(distill_state_wedged)"; then
        distill_warn "the corpus repo is stuck mid-$wedge — not committing onto it"
        info "settle it by hand, then the next run picks up where this one stopped:"
        info "  git -C $repo status"
        return 0
    fi

    git -C "$repo" add -A >/dev/null 2>&1 || true
    if ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
        git -C "$repo" commit -q -m "$msg" >/dev/null 2>&1 || {
            distill_warn "could not commit the state repo"
            return 0
        }
    fi

    # Only if one was configured. Offline is not an error here either: the commit
    # is already made, and the next run carries it.
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || return 0
    distill_git_env

    # -u every time, not just the first: a repo created by `git init` and pointed
    # at a remote by hand has no upstream at all, and without one `git push` has
    # nothing to push to and the old fallback's `pull --rebase` failed outright
    # with "no tracking information". That is the whole of why a rebuilt Mac never
    # re-attached to its corpus.
    branch="$(distill_state_branch)"
    git -C "$repo" push -q -u origin "$branch" >/dev/null 2>&1 && return 0

    # Rejected almost always means the other Mac pushed first. Reconcile and retry
    # once; anything left after that is for a human, not for 01:00.
    distill_state_sync || {
        info "state push deferred — the next run will carry it"
        return 0
    }
    git -C "$repo" push -q -u origin "$branch" >/dev/null 2>&1 ||
        info "state push deferred — the next run will carry it"
    return 0
}

# distill_render_state_readme — the repo explaining itself, on GitHub.
#
# This one is not for you and not for Claude: it is for whoever opens the remote
# on a machine that has none of this set up, which in practice is you on a
# replacement Mac. A backup you cannot interpret is not a backup, and the restore
# procedure is two commands that are impossible to guess from the file names.
#
# Deterministic like every other render, so a run that changed nothing produces
# no commit.
distill_render_state_readme() {
    local out="${1:-$(distill_state_dir)/README.md}" remote title
    # Read back from git rather than a config key, so the clone line in the
    # README can never name a remote this repo does not actually push to.
    remote="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
    # Normalised, because this file is TRACKED. Two Macs on one corpus that spell
    # the same remote differently — one `git@github.com:…`, one `https://…` —
    # would otherwise rewrite this line against each other on every run: a commit
    # each night that changes nothing, and a merge conflict in the one file that
    # has no business having one.
    [ -n "$remote" ] && remote="https://$(distill_remote_id "$remote")"
    # There is one of these repo per profile (…-personal, …-work), and a heading
    # that names the wrong one on the wrong remote is worse than no heading.
    title="$(basename "${remote:-claude-memory}" .git)"
    mkdir -p "$(dirname "$out")"
    {
        printf '# %s\n\n' "$title"
        printf 'The corpus behind my Claude Code memory. Written by `chez distill`, a\n'
        printf 'nightly job in [dotfiles](https://github.com/martinzachariassen/dotfiles);\n'
        printf 'nothing here is edited by hand.\n\n'

        printf 'Each night the job reads the Claude Code sessions written since it last\n'
        printf 'looked, asks a model what is worth keeping, and stores the answer. The\n'
        printf 'rules Claude actually loads (`MAIN.md`, `Topics/`) are **not** in this\n'
        printf 'repo — they are regenerated from what is, so keeping both would be two\n'
        printf 'copies of one decision, free to disagree.\n\n'

        printf '## What is in here\n\n'
        printf -- '| Path | What it is |\n|---|---|\n'
        printf -- '| `extracts/<date>.<host>.json` | Every item the model kept, with a short quote as evidence. One file per day **per Mac**, so two machines never write the same path. **The source of truth** — everything else is derived from this. |\n'
        printf -- '| `Pinned.md` | The hand-written rules. Copied here because they are the one thing that cannot be regenerated. |\n\n'

        printf 'That is the whole repo, and the rule is simple: if a machine can regenerate\n'
        printf 'it or nobody else can use it, it is not here. Deliberately absent are\n'
        printf '`cursor.json` (how far *this* Mac has read), `spend.jsonl` (what *this* Mac\n'
        printf 'was billed), `runs.jsonl` (what *this* Mac did at 01:00) and `logs/`. All\n'
        printf 'three files are append-only, so tracking them would make two Macs conflict\n'
        printf 'on every line and quietly stop the backup that matters.\n\n'

        printf '## Restoring onto a new Mac\n\n'
        printf 'Set the dotfiles up first, then:\n\n'
        printf '```sh\n'
        printf 'git clone %s \\\n' "${remote:-<this repo>}"
        printf '    ~/.local/state/chezdistill\n'
        printf 'chez distill --render\n'
        printf '```\n\n'
        printf '`--render` makes no model calls and costs nothing. It rebuilds `MAIN.md`,\n'
        printf '`Topics/` and `Candidates.md` from the extracts, so the new machine starts\n'
        printf 'with the memory the old one had rather than an empty one.\n\n'

        printf '## Why it is private\n\n'
        printf 'Each item carries a short quote from the conversation it came from, as\n'
        printf 'evidence for why it was kept. That is transcript text. Quotes are stripped\n'
        printf 'from items older than the retention window, but the recent ones are real,\n'
        printf 'so this repo stays private and every push is scanned by `gitleaks` first.\n'
    } >"$out"
}

# distill_state_repo_init — created on first use, and pointed at the corpus its
# it was attached to (`chez distill --remote`), so a replacement Mac fetches the corpus
# instead of starting from an empty memory and nobody has to remember a
# `git remote add`. A remote already set by hand is left alone unless it is
# another profile's, which is refused — see distill_corpus_check_local.
#
# What is tracked is exactly what cannot be regenerated: the extract corpus and
# `Pinned.md`. Everything else here is per-machine telemetry and is excluded —
# `cursor.json` ("how far has THIS Mac read"), `spend.jsonl` (what THIS Mac was
# billed), `runs.jsonl` (what THIS Mac did at 01:00) and `logs/` (launchd noise,
# and the one thing here that grows without bound).
#
# That split is not only about tidiness. All three telemetry files are append-only,
# so two Macs pushing to one remote would conflict on every line of them, and the
# rebase-then-push fallback below would fail silently and stop backing up the one
# thing that mattered. Tracking only the corpus makes the shared case work.
#
# Identity and signing are pinned locally rather than inherited. A global
# `commit.gpgsign = true` backed by 1Password's op-ssh-sign raises a GUI approval
# prompt, and a launchd job at 01:00 has nobody to approve it — the commit would
# hang or fail every night. Nothing here is published or attributed to anyone, so
# there is nothing for a signature to attest to.
distill_state_repo_init() {
    local repo pat
    repo="$(distill_state_dir)"
    mkdir -p "$repo" || return 1
    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        # `-b main` rather than whatever init.defaultBranch happens to be. This
        # repo is private plumbing, so the name only has to be PREDICTABLE: an
        # empty remote publishes no branch to follow, and inheriting the local
        # default there means one machine creates the corpus on `main` and
        # another on `master`, on a remote whose HEAD names only one of them. A
        # remote that already has a branch is still followed, whatever it calls
        # it — see distill_remote_probe.
        git -C "$repo" init -q -b main >/dev/null 2>&1 ||
            git -C "$repo" init -q >/dev/null 2>&1 || {
            distill_warn "could not init the state repo at $repo — --undo will not work"
            return 1
        }
    fi
    git -C "$repo" config commit.gpgsign false >/dev/null 2>&1 || true
    git -C "$repo" config user.name chezdistill >/dev/null 2>&1 || true
    git -C "$repo" config user.email chezdistill@localhost >/dev/null 2>&1 || true
    # Adopt before checking: a repo with no origin is not in conflict with
    # anything, it just doesn't know where it lives yet.
    distill_remote_adopt
    distill_state_repo_pushurl
    distill_state_restore
    distill_render_state_readme
    distill_seed_pinned
    # After the restore, so a corpus that already has an identity keeps it and
    # only a genuinely new one is stamped.
    distill_corpus_seed
    distill_corpus_check_local || return 1
    # Ensure each rule, rather than only writing the file when absent: a repo
    # initialised by an older version keeps its old .gitignore forever, and a
    # rule added later would never reach it. Untrack too — .gitignore has no
    # effect on a path that is already in the index.
    for pat in 'logs/' 'cursor.json' 'runs.jsonl' 'spend.jsonl' '*.tmp'; do
        grep -qxF "$pat" "$repo/.gitignore" 2>/dev/null && continue
        printf '%s\n' "$pat" >>"$repo/.gitignore"
    done
    git -C "$repo" ls-files -z --cached -i --exclude-standard 2>/dev/null |
        xargs -0 -r git -C "$repo" rm -q --cached -- 2>/dev/null || true
    return 0
}
