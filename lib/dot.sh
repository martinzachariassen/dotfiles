# shellcheck shell=bash
#
# The single entrypoint: everything sources this and gets the whole library.

[[ -n ${__DOT_SH:-} ]] && return 0
__DOT_SH=1

# Catches the entry points that bypass bin/dot's re-exec: a hook run by hand,
# and bats.
if ((BASH_VERSINFO[0] < 5)); then
  printf 'dotfiles needs bash 5 or newer; this is %s. Run: brew install bash\n' \
    "$BASH_VERSION" >&2
  exit 1
fi

# An inherited DOT_ROOT wins: the shim exports it and every hook inherits it.
if [[ -z ${DOT_ROOT:-} ]]; then
  DOT_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
export DOT_ROOT

# core/apply.sh and uninstall.sh bake this path into generated script;
# core/doctor.sh and uninstall.sh grep -F for it. Refusing once here beats
# escaping in each of them.
if [[ $DOT_ROOT != "${DOT_ROOT//[\"\`\$\\]/}" || $DOT_ROOT == *$'\n'* ]]; then
  printf 'dotfiles: the repo path contains a character that cannot be quoted safely:\n  %s\nMove the checkout somewhere with no " ` $ \\ or newline in its path.\n' \
    "$DOT_ROOT" >&2
  exit 1
fi

DOT_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DOT_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
DOT_CONFIG=${DOT_CONFIG:-$DOT_CONFIG_HOME/dotfiles/config.toml}
DOT_STATE=${DOT_STATE:-$DOT_STATE_HOME/dotfiles}
export DOT_CONFIG DOT_STATE

DOT_DRY_RUN=${DOT_DRY_RUN:-0}
export DOT_DRY_RUN

# Exported, not memoised: every process in a run must compute the same backup
# directory (fs_backup_dir), and hooks are separate processes.
DOT_RUN_ID=${DOT_RUN_ID:-$(date +%Y%m%d-%H%M%S)}
export DOT_RUN_ID

source "$DOT_ROOT/lib/ui.sh"
source "$DOT_ROOT/lib/config.sh"
source "$DOT_ROOT/lib/fs.sh"
source "$DOT_ROOT/lib/brew.sh"
source "$DOT_ROOT/lib/modules.sh"
source "$DOT_ROOT/lib/wizard.sh"

__DOT_REPORTED=0
__dot_on_err() {
  # Captured before the guards below overwrite BASH_COMMAND.
  local status=$? cmd=$BASH_COMMAND src=${BASH_SOURCE[1]} line=${BASH_LINENO[0]}
  # errtrace fires inside $( ) too, where toml_get probes for missing keys.
  ((BASH_SUBSHELL == 0)) || return 0
  ((__DOT_REPORTED)) && return 0
  __DOT_REPORTED=1
  # __ui_render, not fail: a crash is not a tallied finding, and a record here
  # would be swallowed by a collapse instead of naming what broke.
  __ui_render fail '' "${src#"$DOT_ROOT"/}:$line: $cmd (exit $status)" >&2
  return 0
}

# bats installs its own ERR trap; stomping on it hides the failing assertion.
if [[ -z $(trap -p ERR) ]]; then
  set -o errtrace
  trap __dot_on_err ERR
fi

__dot_on_exit() {
  local status=$?

  # fd 3/4 and __DOT_TEE_PID are the contract with bin/dot's
  # __transcript_start. Draining here rather than there covers the `die` path;
  # without it bash exits unreaped and the log loses the lines naming the
  # failure.
  if [[ -n ${__DOT_TEE_PID:-} ]]; then
    exec 1>&3 2>&4
    wait "$__DOT_TEE_PID" 2>/dev/null || true
  fi

  if [[ ${DOT_FAILURES:-0} -gt 0 ]]; then
    exit 1
  fi
  if ((status == 0 && ${DOT_WARNINGS:-0} > 0 && ${__DOT_EXIT_WARN:-1})); then
    exit "$DOT_STATUS_WARN"
  fi
  exit "$status"
}

if [[ -z $(trap -p EXIT) ]]; then
  trap __dot_on_exit EXIT
fi
