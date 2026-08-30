#!/usr/bin/env bash
# verbs.sh — the single source of truth for the dotfiles command surface.
#
# The verb list used to exist in five hand-synced places: the `chezhelp`
# heredoc, README.md, docs/commands.md, the 99-completion hook, and CLAUDE.md.
# Nothing checked four of them. This table is now the one that counts, and
# tests/registry.bats holds the others to it in both directions.
#
# Columns, tab-separated:
#   verb     the subcommand, as in `chez <verb>`
#   feature  owning directory under features/, or "-" for a registry verb
#   group    heading it appears under in `chez help`
#   module   module that must be enabled for the verb to exist, or "-"
#   summary  one line, present tense, no trailing period beyond the first
#
# Summaries are the wording already shipped in `chezhelp`; keep them that way
# unless the behaviour changes.

[ -n "${__DOTFILES_VERBS_SH:-}" ] && return 0
__DOTFILES_VERBS_SH=1

# verbs_table — emit the table as TSV. Comments and blank lines are stripped so
# callers can read it without filtering.
verbs_table() {
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' <<'TABLE'
up	converge	everyday	-	Pull → preview → apply. The command you run most.
doctor	doctor	everyday	-	Read-only health check (repo, brew, auth, mise, shell).
setup	setup	setup	-	Fill in newly-added setup keys; keeps existing answers.
sign	sign	setup	-	Set the git signing key on its own; keeps every other answer.
auth	auth	setup	-	Sign in to gh and the cloud CLIs after a fresh install.
xcode	xcode	setup	appleDev	Install Xcode + iOS simulator runtime (Apple ID, ~40 GB).
distill	distill	setup	claudeDistiller	Distil Claude conversations into the MAIN.md Claude loads.
apply	converge	maintenance	-	Apply without pulling. Flags drift; never uninstalls.
status	converge	maintenance	-	Explain pending file + package drift in plain words (read-only).
bump	brew	maintenance	-	Upgrade deps: brew upgrade + mise upgrade.
mirror	brew	maintenance	-	Uninstall untracked packages (removal only), confirming each.
reconcile	converge	maintenance	-	Full package reconcile: install then remove.
clean	clean	maintenance	-	Remove untracked top-level ~/.* entries, confirming each.
macos	macos	hood	-	(Re-)apply macOS system defaults on their own.
cd	-	maintenance	-	cd into the source repo.
help	-	hood	-	Show this list.
TABLE
}

# verbs_all — every verb name, one per line, in table order.
verbs_all() { verbs_table | cut -f1; }

# verbs_field VERB N — column N of VERB's row (1-indexed). Empty if unknown.
verbs_field() {
    verbs_table | awk -F'\t' -v v="$1" -v n="$2" '$1 == v { print $n; exit }'
}

# verbs_feature VERB / verbs_group VERB / verbs_module VERB / verbs_summary VERB
verbs_feature() { verbs_field "$1" 2; }
verbs_group() { verbs_field "$1" 3; }
verbs_module() { verbs_field "$1" 4; }
verbs_summary() { verbs_field "$1" 5; }

# verbs_legacy_name VERB — the pre-dispatcher name, for the transition aliases
# and for checking the docs that still use it.
verbs_legacy_name() {
    case "$1" in
        cd) printf 'dotfiles\n' ;;
        macos) printf 'macos-defaults\n' ;;
        auth) printf '\n' ;; # never had one; bootstrap-auth.sh was run by path
        *) printf 'chez%s\n' "$1" ;;
    esac
}
