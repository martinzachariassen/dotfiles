#!/usr/bin/env bats
# A corpus states its own identity, and a URL is not one. Attaching, adopting a
# corpus that merely moved, refusing another scope's, and reporting what the
# remote actually HAS rather than what it is called.
#
# Harness in core/testing/distill.bash; engine in features/distill/lib/.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/distill'
    distill_setup
}

# ─── One corpus per Mac ───────────────────────────────────────────────────────
#
# `hits` is counted over the WHOLE corpus, so two scopes sharing a remote is not
# untidy — a rule seen twice in one scope is promoted into the other scope's
# MAIN.md the moment the histories meet, and a push cannot be taken back.
#
# What guards that is no longer a table of URLs in this repo. It is the stamp the
# corpus carries, checked offline from the local copy, plus a prompted seed that
# only ever points a state repo with no origin. The table could not see a URL it
# did not already know, which is how a renamed repo walked straight through it.

PERSONAL_URL="https://github.com/me/claude-memory-personal.git"
WORK_URL="https://github.com/me/claude-memory-work.git"

# seed_setup SCOPE [SEED-URL] — the engine as if setup had been answered so.
seed_setup() {
    DISTILL_SCOPE="$1"
    DISTILL_CORPUS_REMOTE="${2:-}"
    export DISTILL_SCOPE DISTILL_CORPUS_REMOTE
    load_lib
}

# stamp SCOPE [SCHEMA] — write this Mac's corpus.json. Schema 2 spells the stamp
# `scope`; schema 1, still in the wild, spelled it `profile`.
stamp() {
    if [ "${2:-2}" = "1" ]; then
        jq -n --arg s "$1" \
            '{schema:1, id:"c-x", profile:$s, created:"2026-01-01T00:00:00Z", createdBy:"other"}' \
            >"$(distill_corpus_file)"
    else
        jq -n --arg s "$1" \
            '{schema:2, id:"c-x", scope:$s, created:"2026-01-01T00:00:00Z", createdBy:"other"}' \
            >"$(distill_corpus_file)"
    fi
}

origin_of() { git -C "$STATE" remote get-url origin 2>/dev/null; }

@test "the seed points a state repo that has no origin" {
    seed_setup personal "$PERSONAL_URL"
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ "$(origin_of)" = "$PERSONAL_URL" ]
}

@test "a blank seed leaves the corpus local, and says nothing is wrong" {
    seed_setup personal ""
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ -z "$(origin_of)" ]

    run distill_backup_state
    [ "$output" = "no-remote" ]
}

# The seed is a seed, not a setting: origin is the authority once there is one.
@test "an origin already set is never overwritten by the seed" {
    seed_setup personal "$PERSONAL_URL"
    git -C "$STATE" init -q -b main
    git -C "$STATE" remote add origin "https://git.example.com/me/my-own-mirror.git"
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ "$(origin_of)" = "https://git.example.com/me/my-own-mirror.git" ]
}

# ...but an answer given on an already-attached Mac must not vanish silently.
@test "a seed naming a different repo than origin is surfaced, not obeyed" {
    seed_setup personal "$WORK_URL"
    git -C "$STATE" init -q -b main
    git -C "$STATE" remote add origin "$PERSONAL_URL"

    run distill_remote_drift
    [ "$status" -eq 0 ]
    [ "$output" = "$WORK_URL" ]

    run distill_status
    [[ "$output" == *"chez distill --remote"* ]] || return 1
}

@test "one repo spelled two ways is not drift" {
    seed_setup personal "git@github.com:Me/Claude-Memory-Personal.git"
    git -C "$STATE" init -q -b main
    git -C "$STATE" remote add origin "$PERSONAL_URL"
    run distill_remote_drift
    [ "$status" -eq 1 ]
}

@test "a corpus stamped for another scope is refused, by name" {
    seed_setup work
    distill_state_repo_init
    stamp personal

    run distill_corpus_check_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"personal"* ]] || return 1
}

# The stamp outlives the rename. A Mac that has been running since before schema
# 2 has a corpus.json spelling the scope `profile`, and reading only `scope`
# would make every one of them look unstamped — which is the ONE reading that
# waves a foreign corpus through, because the guard cannot fire on an empty
# stamp. Backward compatibility here is a security property, not a courtesy.
@test "a schema-1 corpus is still read, and still refused" {
    seed_setup work
    distill_state_repo_init
    stamp personal 1

    [ "$(distill_corpus_scope)" = "personal" ]
    run distill_corpus_check_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"personal"* ]] || return 1
}

@test "nothing is committed while the corpus is stamped for another scope" {
    seed_setup work
    distill_state_repo_init
    stamp personal
    extract 2026-08-22 "[$(item 'a scoped rule' s1)]"

    run distill_commit_local "chore(distill): test"
    [ "$status" -eq 0 ]
    run git -C "$STATE" rev-list --count HEAD
    [ "$status" -ne 0 ]
}

@test "preflight refuses to run against another scope's corpus" {
    seed_setup work
    distill_state_repo_init
    stamp personal
    run distill_preflight
    [ "$status" -eq 1 ]
    [[ "$output" == *"personal"* ]] || return 1
}

@test "--status still reports when the corpus is what is wrong" {
    seed_setup work
    distill_state_repo_init
    stamp personal
    run distill_status
    [ "$status" -eq 0 ]
    [[ "$output" != *"paths    unusable"* ]] || return 1
}

# Kept because the normaliser is still load-bearing — for the tracked README and
# for the drift advisory above. It is NOT a guard any more; comparing URLs is
# exactly what a repo rename defeated.
@test "spellings GitHub treats as one repo compare as one repo" {
    seed_setup work
    a="$(distill_remote_id "https://github.com/Me/Claude-Memory-Work.git")"
    [ "$a" = "github.com/me/claude-memory-work" ]
    [ "$(distill_remote_id "git@github.com:me/claude-memory-work")" = "$a" ]
    [ "$(distill_remote_id "ssh://git@github.com/me/claude-memory-work.git")" = "$a" ]
    [ "$(distill_remote_id "https://github.com/me/claude-memory-work/")" = "$a" ]
    [ "$(distill_remote_id "https://github.com/me/claude-memory-personal")" != "$a" ]
}

# ─── The corpus actually reaching its remote ──────────────────────────────────
#
# Every test above this line points its remote at a URL nobody ever contacts, so
# for three years nothing exercised a push, a fetch or a restore — which is
# exactly how a backup that had never once worked kept reporting a green tick.
# These use local bare repos, so they are real git operations and still offline.
#
# Every one names its branch. `git init` follows init.defaultBranch, which is set
# on the author's Mac and unset on CI, so a test that omitted it would exercise
# `main` locally and `master` in CI.

# isolate_git — run against a git that has been configured by nobody.
#
# Not optional. This machine sets push.autoSetupRemote=true globally, which
# quietly sets the upstream that the old code never set, so three of the tests
# below passed against the very bug they exist to catch. CI sets neither that nor
# init.defaultBranch. Without this the suite would prove the fix works here and
# ship the failure to every machine configured differently.
isolate_git() {
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig-none"
    export GIT_CONFIG_SYSTEM=/dev/null
    : >"$GIT_CONFIG_GLOBAL"
}

bare_remote() {
    local b="${1:-main}" d
    isolate_git
    d="$BATS_TEST_TMPDIR/bare-$b-$RANDOM.git"
    git init -q --bare -b "$b" "$d"
    printf '%s\n' "$d"
}

# seed_remote BARE BRANCH SHARD… — a corpus that already exists, as if another
# Mac had been running for months.
seed_remote() {
    local bare="$1" branch="$2" work shard
    shift 2
    work="$BATS_TEST_TMPDIR/seed-$RANDOM"
    git clone -q -b "$branch" "$bare" "$work" 2>/dev/null || {
        git init -q -b "$branch" "$work"
        git -C "$work" remote add origin "$bare"
    }
    mkdir -p "$work/extracts"
    for shard in "$@"; do
        jq -n --argjson i "[$(item 'a remembered rule' "s-$shard")]" '{items:$i}' \
            >"$work/extracts/$shard.json"
    done
    git -C "$work" -c user.name=t -c user.email=t@t add -A
    git -C "$work" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
        commit -q -m "seed"
    git -C "$work" push -q origin "$branch"
}

attach_state() {
    local bare="$1" branch="${2:-main}"
    isolate_git
    git -C "$STATE" init -q -b "$branch"
    git -C "$STATE" remote add origin "$bare"
}

@test "the first push sets an upstream" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"

    [ "$(git -C "$STATE" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = "origin/main" ]
    [ "$(git -C "$bare" rev-list --count main)" -ge 1 ]
}

@test "a corpus that already exists is restored onto a machine that has none" {
    load_lib
    bare="$(bare_remote main)"
    seed_remote "$bare" main 2026-08-01.mac-a
    attach_state "$bare" main

    distill_state_repo_init
    [ -f "$STATE/extracts/2026-08-01.mac-a.json" ]
    [ "$(git -C "$STATE" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = "origin/main" ]
}

@test "a restored corpus keeps deriving what the other Mac wrote" {
    load_lib
    bare="$(bare_remote main)"
    seed_remote "$bare" main 2026-08-01.mac-a
    attach_state "$bare" main
    distill_state_repo_init

    run distill_derive
    [[ "$output" == *"a remembered rule"* ]] || return 1
}

@test "a remote on master is followed, not overwritten with main" {
    load_lib
    bare="$(bare_remote master)"
    seed_remote "$bare" master 2026-08-01.mac-a
    attach_state "$bare" master
    distill_state_repo_init

    [ -f "$STATE/extracts/2026-08-01.mac-a.json" ]
    [ "$(git -C "$STATE" symbolic-ref --short HEAD)" = "master" ]
}

@test "a remote that moved ahead is merged, and never left mid-rebase" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'mine' s1)]"
    distill_commit_local "chore(distill): mine"

    # Another Mac pushes its own shard in the meantime.
    seed_remote "$bare" main 2026-08-23.mac-b

    extract 2026-08-24 "[$(item 'mine later' s2)]"
    distill_commit_local "chore(distill): mine later"

    [ ! -d "$STATE/.git/rebase-merge" ]
    [ ! -d "$STATE/.git/rebase-apply" ]
    # Both Macs' work is on the remote.
    run git -C "$bare" ls-tree -r --name-only main
    [[ "$output" == *"2026-08-23.mac-b.json"* ]] || return 1
    [[ "$output" == *"2026-08-24."* ]] || return 1
}

@test "an unreachable remote defers instead of wedging the repo" {
    load_lib
    attach_state "$BATS_TEST_TMPDIR/nope.git" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    run distill_commit_local "chore(distill): test"

    [ "$status" -eq 0 ]
    [ ! -d "$STATE/.git/rebase-merge" ]
    [ "$(git -C "$STATE" rev-list --count HEAD)" -ge 1 ]
}

@test "a wedged repo is reported, and never committed onto" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): first"

    # The state the machine was found in: HEAD detached, no branch to push.
    git -C "$STATE" checkout -q --detach HEAD

    before="$(git -C "$STATE" rev-list --count HEAD)"
    extract 2026-08-23 "[$(item 'later' s2)]"
    run distill_commit_local "chore(distill): second"

    [ "$status" -eq 0 ]
    [[ "$output" == *"detached"* ]] || return 1
    [ "$(git -C "$STATE" rev-list --count HEAD)" -eq "$before" ]
}

@test "commits that never reached the remote do not read as backed up" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"

    # The remote goes away underneath us, exactly as a rename does.
    rm -rf "$bare"
    git -C "$STATE" commit -q --allow-empty -m "chore(distill): later"

    run distill_backup_state
    [[ "$output" == ahead* ]] || return 1

    run distill_status
    [[ "$output" != *"commit(s), pushed to"* ]] || return 1
}

@test "a corpus in step with its remote reads as backed up" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"

    run distill_backup_state
    [ "$output" = "synced" ]
}

# ─── Corpus identity, and attaching one ───────────────────────────────────────
#
# The guard these replace compared the origin URL against a table of known ones.
# That fails in the direction that actually happened here: the repo was renamed,
# the URL changed, and every string comparison still passed while the push had
# been failing for two days. A corpus now says who it is, in a tracked file that
# travels with it, so a rename is recognised and a cross-scope mix-up is not.

# seed_corpus BARE BRANCH SCOPE ID SHARD… — a corpus that already exists, with
# an identity. SCOPE empty means a legacy corpus that predates corpus.json.
seed_corpus() {
    local bare="$1" branch="$2" prof="$3" id="$4" work shard
    shift 4
    work="$BATS_TEST_TMPDIR/seed-$RANDOM"
    git init -q -b "$branch" "$work"
    mkdir -p "$work/extracts"
    [ -n "$prof" ] && jq -n --arg i "$id" --arg p "$prof" \
        '{schema:2, id:$i, scope:$p, created:"2026-01-01T00:00:00Z", createdBy:"seed"}' \
        >"$work/corpus.json"
    for shard in "$@"; do
        jq -n --argjson i "[$(item 'a shared rule' "s-$shard")]" '{items:$i}' \
            >"$work/extracts/$shard.json"
    done
    git -C "$work" -c user.name=t -c user.email=t@t add -A
    git -C "$work" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
        commit -q -m seed
    git -C "$work" push -q "$bare" "$branch"
}

local_shard() {
    mkdir -p "$STATE/extracts"
    jq -n --argjson i "[$(item "${2:-a local rule}" "${3:-loc1}")]" '{items:$i}' \
        >"$STATE/extracts/$1.json"
}

@test "a corpus is stamped once, and never re-stamped" {
    load_lib
    isolate_git
    distill_state_repo_init
    first="$(distill_corpus_id)"
    [ -n "$first" ]
    [ "$(distill_corpus_scope)" = "$(distill_scope)" ]

    distill_state_repo_init
    [ "$(distill_corpus_id)" = "$first" ]
}

@test "the stamp is tracked, so it travels with the corpus" {
    load_lib
    isolate_git
    distill_state_repo_init
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"
    run git -C "$STATE" ls-files
    [[ "$output" == *"corpus.json"* ]] || return 1
}

@test "attaching to an empty remote makes this Mac's corpus the corpus" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    local_shard 2026-08-20.mac-one

    run distill_remote_attach "$bare"
    [ "$status" -eq 0 ]
    run git -C "$bare" ls-tree -r --name-only main
    [[ "$output" == *"extracts/2026-08-20.mac-one.json"* ]] || return 1
    [[ "$output" == *"corpus.json"* ]] || return 1
}

@test "attaching a machine with nothing restores the corpus whole" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    seed_corpus "$bare" main personal c-known 2026-07-01.other-mac

    DISTILL_SCOPE=personal
    run distill_remote_attach "$bare"
    [ "$status" -eq 0 ]
    [ -f "$STATE/extracts/2026-07-01.other-mac.json" ]
    [ "$(distill_corpus_id)" = "c-known" ]
}

# The property the whole design rests on: joining loses nothing from either side.
#
# Asserted on the ONE entry it is about, with jq — a substring match for
# `"hits":2` also passes on any other entry that happens to have two, which is
# how an earlier version of this went green locally while the number it meant to
# check was wrong. The two sides are given DISJOINT sessions in the shard whose
# name they share, so a union that dropped either one shows up as a hit count of
# 1 rather than as a passing test.
@test "joining a corpus loses nothing from either side" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    # The remote knows the rule from its own session, s-2026-07-01.other-mac.
    seed_corpus "$bare" main personal c-known 2026-07-01.other-mac
    DISTILL_SCOPE=personal

    mkdir -p "$STATE/extracts"
    # This Mac wrote the SAME shard name, from a different session.
    jq -n --argjson i "[$(item 'a shared rule' s-mine)]" '{items:$i}' \
        >"$STATE/extracts/2026-07-01.other-mac.json"
    # ...and a shard only this Mac has at all.
    local_shard 2026-08-20.this-mac 'a local rule' loc1

    run distill_remote_attach "$bare"
    [ "$status" -eq 0 ]

    run git -C "$bare" ls-tree -r --name-only main
    [[ "$output" == *"2026-07-01.other-mac.json"* ]] || return 1
    [[ "$output" == *"2026-08-20.this-mac.json"* ]] || return 1

    # Both sessions survived the collision — 1 would mean one side was dropped.
    hits="$(distill_derive | jq -r 'select(.text == "a shared rule") | .hits')"
    [ "$hits" = "2" ]
    hits="$(distill_derive | jq -r 'select(.text == "a local rule") | .hits')"
    [ "$hits" = "1" ]
}

@test "a shard both Macs wrote is unioned, not replaced" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    seed_corpus "$bare" main personal c-known 2026-07-01.shared
    DISTILL_SCOPE=personal
    mkdir -p "$STATE/extracts"
    jq -n --argjson i "[$(item 'mine only' s-mine)]" '{items:$i}' \
        >"$STATE/extracts/2026-07-01.shared.json"

    distill_remote_attach "$bare"
    run jq -r '[.items[].session] | sort | join(",")' "$STATE/extracts/2026-07-01.shared.json"
    [ "$output" = "s-2026-07-01.shared,s-mine" ]
}

@test "another scope's corpus is refused before anything is pushed" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    seed_corpus "$bare" main personal c-personal 2026-07-01.their-mac
    before="$(git -C "$bare" rev-parse main)"

    DISTILL_SCOPE=work
    local_shard 2026-08-20.work-mac
    run distill_remote_attach "$bare"

    [ "$status" -eq 1 ]
    [[ "$output" == *"personal"* ]] || return 1
    [ "$(git -C "$bare" rev-parse main)" = "$before" ]
}

# The incident this design exists for: the repo was renamed, so the URL is new
# and the corpus is not.
@test "the same corpus at a new address is recognised, not merged" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    seed_corpus "$bare" main personal c-known 2026-07-01.other-mac
    DISTILL_SCOPE=personal
    distill_remote_attach "$bare"

    moved="$BATS_TEST_TMPDIR/moved.git"
    git clone -q --bare "$bare" "$moved"

    run distill_remote_attach "$moved"
    [ "$status" -eq 0 ]
    [[ "$output" == *"same corpus"* ]] || return 1
    [ "$(git -C "$STATE" remote get-url origin)" = "$moved" ]
}

@test "a corpus older than identities is adopted, then stamped" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    seed_corpus "$bare" main "" "" 2026-07-01.old-mac

    run distill_remote_attach "$bare"
    [ "$status" -eq 0 ]
    [ -f "$STATE/extracts/2026-07-01.old-mac.json" ]
    [ -n "$(distill_corpus_id)" ]
    [ "$(distill_corpus_scope)" = "$(distill_scope)" ]
}

@test "detaching is a decision the next run does not undo" {
    load_lib
    isolate_git
    bare="$(bare_remote main)"
    local_shard 2026-08-20.mac-one
    distill_remote_attach "$bare"
    [ -n "$(origin_of)" ]

    distill_remote_detach
    [ -z "$(origin_of)" ]

    # A configured remote is exactly what would re-attach it, unguarded.
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg p "$bare" '{remotes:{personal:$p}}')")"
    _DISTILL_CFG=""
    DISTILL_SCOPE=personal
    distill_state_repo_init
    [ -z "$(origin_of)" ]
}

@test "a corpus stamped for another scope stops the run, offline" {
    load_lib
    isolate_git
    distill_state_repo_init
    stamp work
    DISTILL_SCOPE=personal

    run distill_corpus_check_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"work"* ]] || return 1

    run distill_preflight
    [ "$status" -eq 1 ]
}

# ─── Where the scope comes from ───────────────────────────────────────────────
#
# distill_scope is the left-hand side of every comparison above, so anything that
# makes it return empty disarms all of them at once — [ -n "$mine" ] is how each
# guard declines to judge, and it cannot tell "no opinion" from "read it wrong".

# as_data JSON — the answers chezmoi would hand back, without running chezmoi.
# Pokes the memo directly, the way the detach test above pokes _DISTILL_CFG:
# _distill_data's only other input is `chezmoi data`, and a test that shelled out
# to it would read the author's real config.
as_data() {
    load_lib
    _DISTILL_DATA="$1"
    _DISTILL_SCOPE=""
    unset DISTILL_SCOPE DISTILL_PROFILE
}

# A Mac set up before memoryScope existed has only `profile` saved, and its
# corpus is already stamped with that value. Ignoring it would not merely lose a
# label: the machine would claim no scope, the guard would abstain, and the first
# `--remote` typo would merge two corpora that have spent a year apart.
@test "a Mac with only the retired profile key keeps its scope" {
    as_data '{"profile":"work"}'
    [ "$(distill_scope)" = "work" ]
}

@test "memoryScope wins over the retired profile key" {
    as_data '{"profile":"work","memoryScope":"lab"}'
    [ "$(distill_scope)" = "lab" ]
}

# jq's `//` only skips null and false, so a saved empty string would win here and
# hand back "" — the one value that turns every guard above into a no-op.
# promptStringOnce treats a saved "" as a real answer, so this is reachable by
# anyone who pressed Enter at the wrong prompt, not just by a corrupt file.
@test "an empty memoryScope falls through to the profile, not to nothing" {
    as_data '{"profile":"work","memoryScope":""}'
    [ "$(distill_scope)" = "work" ]
}

@test "neither key set means no opinion, not an error" {
    as_data '{}'
    run distill_scope
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Honoured for one release so a shell, a launchd plist or a half-applied Mac that
# still exports the old name does not silently fall back to no scope at all.
@test "the retired DISTILL_PROFILE env name still sets the scope" {
    as_data '{}'
    DISTILL_PROFILE=work
    [ "$(distill_scope)" = "work" ]
}

@test "a corpus this Mac starts is stamped with its scope, under schema 2" {
    as_data '{"memoryScope":"lab"}'
    isolate_git
    distill_state_repo_init

    [ "$(jq -r .schema "$(distill_corpus_file)")" = "2" ]
    [ "$(jq -r .scope "$(distill_corpus_file)")" = "lab" ]
    [ "$(distill_corpus_scope)" = "lab" ]
}

@test "unioning a shard twice changes nothing the second time" {
    load_lib
    mkdir -p "$STATE/extracts"
    a="$STATE/extracts/a.json"
    b="$STATE/extracts/b.json"
    jq -n --argjson i "[$(item 'one' s1)]" '{items:$i}' >"$a"
    jq -n --argjson i "[$(item 'two' s2)]" '{items:$i}' >"$b"

    distill_extract_union "$a" "$b" "$a"
    once="$(cat "$a")"
    distill_extract_union "$a" "$b" "$a"
    [ "$once" = "$(cat "$a")" ]
}
