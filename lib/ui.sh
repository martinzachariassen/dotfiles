# shellcheck shell=bash
#
# Terminal output. The only file that emits colour or glyphs.

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  __C_RESET=$'\033[0m'
  __C_DIM=$'\033[2m'
  __C_BOLD=$'\033[1m'
  __C_RED=$'\033[31m'
  __C_GREEN=$'\033[32m'
  __C_YELLOW=$'\033[33m'
  __C_BLUE=$'\033[34m'
else
  __C_RESET='' __C_DIM='' __C_BOLD='' __C_RED='' __C_GREEN='' __C_YELLOW='' __C_BLUE=''
fi

# `fail` never exits; lib/dot.sh's EXIT trap turns the tally into a status.
DOT_FAILURES=0
DOT_WARNINGS=0

# The exit status of a hook that only warned. 3, not 2: bash owns 2 for syntax
# errors, so a hook that never ran must not read as "finished with a note".
DOT_STATUS_WARN=3

heading() { printf '\n%s%s%s\n' "$__C_BOLD" "$*" "$__C_RESET"; }
say() { printf '  %s\n' "$*"; }
dim() { printf '  %s%s%s\n' "$__C_DIM" "$*" "$__C_RESET"; }
ok() { printf '  %s✓%s %s\n' "$__C_GREEN" "$__C_RESET" "$*"; }
info() { printf '  %s→%s %s\n' "$__C_BLUE" "$__C_RESET" "$*"; }
warn() {
  printf '  %s!%s %s\n' "$__C_YELLOW" "$__C_RESET" "$*" >&2
  DOT_WARNINGS=$((DOT_WARNINGS + 1))
}

fail() {
  printf '  %s✗%s %s\n' "$__C_RED" "$__C_RESET" "$*" >&2
  DOT_FAILURES=$((DOT_FAILURES + 1))
}

# fold_status MESSAGE CMD... -- run a child process and fold its exit status
# back into the tallies. The child has already printed its own detail; MESSAGE
# only says which hook broke.
fold_status() {
  local msg=$1 status=0
  shift
  "$@" || status=$?
  case $status in
    0) ;;
    "$DOT_STATUS_WARN") DOT_WARNINGS=$((DOT_WARNINGS + 1)) ;;
    *) fail "$msg" ;;
  esac
}

die() {
  printf '  %s✗%s %s\n' "$__C_RED" "$__C_RESET" "$*" >&2
  exit 1
}
