# shellcheck shell=bash
#
# First-run config generation. Runs after phase 1 has installed fzf, which is
# why the picker is one call rather than a hand-rolled menu.

DOT_PROFILES="$DOT_ROOT/profiles.toml"

# Esc/Ctrl-C make fzf exit 130 with no output; every picker ends in `|| true`
# and signals cancellation by printing nothing.
__wizard_cancel() {
  say 'Cancelled -- no config was written.'
  exit 0
}

# The module name travels as a hidden first field (--with-nth=2), never
# recovered from the rendered text.
wizard_pick_modules() {
  local preset=$1 name mark i=0 preselect=''
  local -a names
  mapfile -t names < <(modules_all)

  # `*` is cosmetic to fzf; pos(N)+toggle is what actually selects the preset
  # rows. Built here, not inside the pipeline, which runs in a subshell.
  for name in "${names[@]}"; do
    i=$((i + 1))
    grep -qxF -- "$name" <<<"$preset" && preselect+="pos($i)+toggle+"
  done

  for name in "${names[@]}"; do
    mark=' '
    grep -qxF -- "$name" <<<"$preset" && mark='*'
    printf '%s\t%s %-20s %s\n' "$name" "$mark" "$name" "$(module_desc "$name")"
  done |
    fzf --multi --height=60% --reverse --prompt='Modules > ' \
      --delimiter=$'\t' --with-nth=2 \
      --bind "load:${preselect}first" \
      --header='TAB to toggle, Enter to confirm, Esc to abort. * = in the profile.' |
    cut -f1 || true
}

wizard_run() {
  local profiles profile modules name email signingkey reply

  # `none` writes an empty list; the config file is the only other route.
  heading 'Choose what to install'
  profiles=$(printf '%s\nnone\n' "$(toml_list "$DOT_PROFILES" 'profiles.keys()')")
  profile=$(printf '%s\n' "$profiles" | grep -v '^$' |
    fzf --height=40% --reverse --prompt='Profile > ' \
      --header='Module list to start from. none = choose them yourself, in the config. Esc to abort.' || true)
  [[ -z $profile ]] && __wizard_cancel

  if [[ $profile == none ]]; then
    modules=''
  else
    # Bracket syntax: dasel reads `work-laptop` as subtraction.
    modules=$(wizard_pick_modules "$(toml_list "$DOT_PROFILES" "profiles[\"$profile\"]")")
    [[ -z $modules ]] && __wizard_cancel
  fi

  # Identity never varies by machine, so it is read from profiles.toml, not asked.
  name=$(toml_get "$DOT_PROFILES" 'user.name')
  email=$(toml_get "$DOT_PROFILES" 'user.email')
  signingkey=$(toml_get "$DOT_PROFILES" 'user.signingkey')

  heading 'Review'
  if [[ -n $modules ]]; then
    say "modules   $(tr '\n' ' ' <<<"$modules")"
  else
    say 'modules   (none -- you add them to the config yourself)'
  fi
  say "identity  ${name:-(unset)} <${email:-(unset)}>"
  if [[ -n $signingkey ]]; then say "signing   ${signingkey:0:36}..."; fi
  # `|| cancel`: a bare read trips errexit on Ctrl-D, and falling through would
  # read end-of-input as yes.
  read -r -p '  Write this config? [Y/n]: ' reply || __wizard_cancel
  [[ ${reply:-y} == [Yy]* ]] || __wizard_cancel

  config_generate "$name" "$email" "$modules" "$signingkey"
  [[ -n $modules ]] || dim "Add modules to $DOT_CONFIG, then run: dot apply"
}
