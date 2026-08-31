#!/usr/bin/env bash
# distill.sh — the chezdistill engine: harvest Claude Code transcripts and render
# the memory tier Claude loads.
#
# Two destinations, because the two have nothing in common:
#   DISTILL_MEMORY  ~/.config/claude/memory — MAIN.md, Topics/, Candidates.md.
#                   Read by Claude, and by nothing else.
#   DISTILL_STATE   ~/.local/state/chezdistill — the extract corpus, Pinned.md,
#                   cursor, spend, run log. The extracts ARE the memory: every
#                   rule, hit count and date is derived from them on each render.
#
# Design principle: the model extracts, bash decides and writes. Every judgement —
# hit counts, what earns a place in MAIN, what gets demoted — is computed here
# from the extract corpus, so a re-run of a day already distilled is a no-op. No
# model invocation in this file has write access.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_DISTILL_SH:-}" ] && return 0
__DOTFILES_DISTILL_SH=1

# The engine was one 2,605-line file. It is the same engine, split along the
# seams its own section banners already marked, and this is the only entry
# point: source lib.sh and you have all of it, exactly as before.
#
# Order matters only for the handful of top-level assignments, which all live in
# config.sh — everything else is function definitions.
_DISTILL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib"

for _distill_part in \
    config.sh \
    preflight.sh \
    harvest.sh \
    model.sh \
    spend.sh \
    runlog.sh \
    ledger.sh \
    render.sh \
    backup.sh \
    corpus.sh \
    attach.sh \
    remote.sh \
    status.sh \
    reports.sh \
    nightly.sh; do
    if [ ! -r "$_DISTILL_LIB_DIR/$_distill_part" ]; then
        printf 'chezdistill: missing %s\n' "$_DISTILL_LIB_DIR/$_distill_part" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    . "$_DISTILL_LIB_DIR/$_distill_part"
done
unset _distill_part
