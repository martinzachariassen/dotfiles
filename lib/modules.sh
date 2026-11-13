# shellcheck shell=bash
#
# The directory listing is the registry; contract.bats walks the same glob.

modules_dir() { printf '%s\n' "$DOT_ROOT/modules/$1"; }
module_manifest() { printf '%s\n' "$(modules_dir "$1")/module.toml"; }

modules_all() {
  local dir
  for dir in "$DOT_ROOT"/modules/*/; do
    [[ -f "$dir/module.toml" ]] || continue
    basename "$dir"
  done
}

module_exists() { [[ -f $(module_manifest "$1") ]]; }

module_desc() { toml_get "$(module_manifest "$1")" 'description' "$1"; }

# module_setting NAME KEY [DEFAULT] -- brackets, because dasel reads
# `settings.macos-defaults` as subtraction.
module_setting() {
  local name=$1 key=$2 default=${3:-}
  cfg_get "settings[\"$name\"].$key" "$default"
}

module_setting_bool() {
  [[ $(module_setting "$1" "$2" "${3:-false}") == true ]]
}

# Silent: read in subshells, so a warning would print once per caller.
# modules_require_known complains, once.
modules_enabled() {
  local name
  while IFS= read -r name; do
    if module_exists "$name"; then printf '%s\n' "$name"; fi
  done < <(cfg_list 'modules.enabled') | sort
}

modules_unknown() {
  local name
  while IFS= read -r name; do
    if ! module_exists "$name"; then printf '%s\n' "$name"; fi
  done < <(cfg_list 'modules.enabled')
}

modules_require_known() {
  local unknown available n
  unknown=$(modules_unknown | tr '\n' ' ')
  [[ -z ${unknown// /} ]] && return 0
  available=$(modules_all | tr '\n' ' ')
  n=$(wc -w <<<"$unknown" | tr -d ' ')
  die "config lists $(ui_count "$n" module) that do not exist: ${unknown% }" \
    available "${available% }" \
    edit "${DOT_CONFIG/#$HOME/\~}"
}

modules_enabled_dirs() {
  local name
  while IFS= read -r name; do
    modules_dir "$name"
  done < <(modules_enabled)
}

modules_all_dirs() {
  local name
  while IFS= read -r name; do
    modules_dir "$name"
  done < <(modules_all)
}

# modules_preflight -- `bash -n` every hook this run may execute, before
# anything in $HOME moves.
modules_preflight() {
  local dir hook script
  local -a bad=()
  while IFS= read -r dir; do
    for hook in apply.sh doctor.sh remove.sh; do
      script="$dir/$hook"
      [[ -f $script ]] || continue
      "$BASH" -n "$script" || bad+=("${script#"$DOT_ROOT"/}")
    done
  done < <(
    printf '%s\n' "$DOT_ROOT/core"
    modules_enabled_dirs
  )

  ((${#bad[@]} == 0)) && return 0
  die "$(ui_count "${#bad[@]}" hook) will not parse -- nothing was changed" \
    hooks "${bad[*]}" \
    reproduce "bash -n $DOT_ROOT/${bad[0]}"
}

# Executed, never sourced: only an exit status leaks back.
module_run_hook() {
  local name=$1 hook=$2 script
  script="$(modules_dir "$name")/$hook"
  [[ -f $script ]] || return 0

  DOT_MODULE=$name \
    DOT_MODULE_DIR="$(modules_dir "$name")" \
    "$BASH" "$script"
}

# module_apply NAME -- packages, links, then apply.sh, which relies on that order.
module_apply() {
  local name=$1 dir packaged=1
  dir=$(modules_dir "$name")

  if [[ ! -d $dir/home && ! -f $dir/apply.sh ]]; then
    dim 'packages only -- nothing to link, no hook to run'
  fi

  # A failing Brewfile stops this module, not the run.
  brew_bundle "$dir/Brewfile" "$name" || packaged=0

  fs_link_tree "$dir"

  if ((packaged)); then
    fold_status "$name: apply.sh failed" module_run_hook "$name" apply.sh
  else
    dim skipped "$name/apply.sh -- its packages are not installed"
  fi
}

# module_doctor NAME -- read-only; tallies rather than returns a status.
module_doctor() {
  local name=$1 dir tracked=''
  dir=$(modules_dir "$name")

  if [[ -d $dir/home ]]; then
    tracked=$(find "$dir/home" -type f -print -quit)
  fi

  brew_check "$dir/Brewfile" "$name"

  if [[ -z $tracked && ! -f $dir/doctor.sh ]]; then
    [[ -f $dir/Brewfile ]] || dim 'nothing to check'
    return 0
  fi

  if fs_check_tree "$dir"; then
    if [[ -n $tracked ]]; then ok files 'all linked'; fi
  else
    fail files 'not linked -- run: dot apply'
  fi

  fold_status "$name: doctor.sh reported problems" module_run_hook "$name" doctor.sh
}

# module_remove NAME -- uninstall.sh calls it for every module, enabled or not.
module_remove() {
  fold_status "$1: remove.sh failed" module_run_hook "$1" remove.sh
}
