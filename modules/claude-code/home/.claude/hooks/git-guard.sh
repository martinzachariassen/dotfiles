#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ -n $cmd ]] || exit 0

deny() {
  jq -nc --arg why "git-guard: $1. Ask the user to run it themselves if it is really meant." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $why}}'
  exit 0
}

protected() { [[ $1 == main || $1 == master ]]; }

# Heredoc bodies and quoted strings are data: a commit message may name
# --no-verify without running it.
code=$(awk '
  stop != "" { if ($0 ~ "^[[:space:]]*" stop "[[:space:]]*$") stop = ""; next }
  { print
    if (match($0, /(^|[^<])<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      t = substr($0, RSTART, RLENGTH); sub(/.*<<-?[[:space:]]*["\047]?/, "", t); stop = t
    } }' <<<"$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

check_push() {
  local a positional=() dst tags=0 here
  here=$(git -C "${cwd:-.}" branch --show-current 2>/dev/null || true)
  for a in "$@"; do
    case $a in
      --force-with-lease* | --force-if-includes) ;;
      --tags) tags=1 ;;
      --force) deny 'force-push is refused; use --force-with-lease only if the user asks' ;;
      --no-verify) deny '--no-verify skips the hooks the repo relies on' ;;
      --*) ;;
      -*f*) deny 'force-push is refused; use --force-with-lease only if the user asks' ;;
      -*) ;;
      +*) deny "a + refspec ($a) is a force-push" ;;
      *) positional+=("$a") ;;
    esac
  done
  if ((${#positional[@]} > 1)); then
    for a in "${positional[@]:1}"; do
      dst=${a##*:}
      dst=${dst#refs/heads/}
      if [[ $dst == HEAD ]]; then dst=$here; fi
      if protected "$dst"; then deny "pushing to $dst directly; open a pull request instead"; fi
    done
  elif ((! tags)) && protected "$here"; then
    deny "pushing to $here directly; open a pull request instead"
  fi
}

check_git() {
  local sub a dry=0 force=0
  while (($#)) && [[ $1 == -* ]]; do
    case $1 in
      -C)
        cwd=${2:-$cwd}
        shift 2 || return 0
        ;;
      -c) shift 2 || return 0 ;;
      *) shift ;;
    esac
  done
  (($#)) || return 0
  sub=$1
  shift
  case $sub in
    push) check_push "$@" ;;
    commit)
      for a in "$@"; do
        if [[ $a == --no-verify || $a == -n ]]; then deny '--no-verify skips the hooks the repo relies on'; fi
      done
      ;;
    reset)
      for a in "$@"; do
        if [[ $a == --hard ]]; then deny 'reset --hard throws away uncommitted work'; fi
      done
      ;;
    clean)
      for a in "$@"; do
        case $a in
          --dry-run) dry=1 ;;
          --force) force=1 ;;
          --*) ;;
          -*)
            if [[ $a == *n* ]]; then dry=1; fi
            if [[ $a == *f* ]]; then force=1; fi
            ;;
        esac
      done
      if ((force && ! dry)); then deny 'clean -f deletes untracked files for good'; fi
      ;;
  esac
}

while IFS= read -r segment; do
  read -ra words <<<"$segment" || true
  i=0
  while ((i < ${#words[@]})); do
    case ${words[i]} in
      *=* | env | command | exec | sudo | time | nohup) ((i += 1)) ;;
      *) break ;;
    esac
  done
  if ((i < ${#words[@]})) && [[ ${words[i]##*/} == git ]]; then
    check_git "${words[@]:i+1}"
  fi
done < <(tr ';&|(){}`' '[\n*]' <<<"$code")

exit 0
