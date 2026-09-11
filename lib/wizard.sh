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

# One look for both pickers. --height, not full screen: the step heading above
# stays visible, so the picker reads as part of the run rather than a mode.
__wizard_fzf_opts() {
  printf '%s\n' \
    --reverse --height=70% --border=rounded --info=inline \
    --pointer="$__G_STEP" --marker="$__G_OK" \
    --color='border:dim,header:italic,marker:green,pointer:blue'
}

# wizard_preview NAME -- what a module would actually do, shown beside the
# picker. Its own process per keystroke, which is why it sources the library
# rather than being handed anything.
wizard_preview() {
  local name=$1 dir file n
  dir=$(modules_dir "$name")

  printf '%s\n\n' "$(module_desc "$name")"

  if [[ -f $dir/Brewfile ]]; then
    n=$(grep -cE '^[[:space:]]*(brew|cask|tap|mas) ' "$dir/Brewfile" || true)
    printf 'packages  %s\n' "$n"
  fi

  n=0
  while IFS=$'\t' read -r _ file; do
    n=$((n + 1))
  done < <(fs_pairs "$dir")
  if ((n > 0)); then
    printf 'links     %s file(s) into your home directory:\n' "$n"
    while IFS=$'\t' read -r _ file; do
      printf '            %s\n' "${file/#$HOME/\~}"
    done < <(fs_pairs "$dir")
  fi

  local hooks=''
  for file in apply.sh doctor.sh remove.sh; do
    if [[ -f $dir/$file ]]; then hooks+=", ${file%.sh}"; fi
  done
  if [[ -n $hooks ]]; then printf 'hooks     %s\n' "${hooks:2}"; fi
}

# The module name travels as a hidden first field (--with-nth=2), never
# recovered from the rendered text.
wizard_pick_modules() {
  local preset=$1 name mark i=0 preselect=''
  local -a names opts
  mapfile -t names < <(modules_all)
  mapfile -t opts < <(__wizard_fzf_opts)

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
    fzf "${opts[@]}" --multi --prompt='Modules > ' \
      --delimiter=$'\t' --with-nth=2 \
      --border-label=' Step 2 of 3 -- what goes on this machine ' \
      --bind "load:${preselect}first" \
      --preview "$BASH -c 'source \"$DOT_ROOT/lib/dot.sh\"; wizard_preview {1}'" \
      --preview-window='right,50%,border-left' \
      --header='TAB to toggle, Enter to confirm, Esc to abort. * = in the profile.' |
    cut -f1 || true
}

# How many files and packages the choice adds up to, so Review says something
# the module list alone does not.
__wizard_totals() {
  local modules=$1 name files=0 packages=0 n
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    n=$(fs_pairs "$(modules_dir "$name")" | wc -l | tr -d ' ')
    files=$((files + n))
    if [[ -f $(modules_dir "$name")/Brewfile ]]; then
      n=$(grep -cE '^[[:space:]]*(brew|cask|tap|mas) ' "$(modules_dir "$name")/Brewfile" || true)
      packages=$((packages + n))
    fi
  done <<<"$modules"
  printf '%s\t%s\n' "$packages" "$files"
}

wizard_run() {
  local profiles profile modules name email signingkey reply packages files
  local -a opts
  mapfile -t opts < <(__wizard_fzf_opts)

  # `none` writes an empty list; the config file is the only other route.
  heading 'Profile' 'step 1 of 3'
  say 'A profile is a starting list of modules. You edit it in the next step.'
  profiles=$(printf '%s\nnone\n' "$(toml_list "$DOT_PROFILES" 'profiles.keys()')")
  profile=$(printf '%s\n' "$profiles" | grep -v '^$' |
    fzf "${opts[@]}" --prompt='Profile > ' \
      --border-label=' Step 1 of 3 -- profile ' \
      --header='none = choose them yourself, in the config. Esc to abort.' || true)
  [[ -z $profile ]] && __wizard_cancel

  if [[ $profile == none ]]; then
    modules=''
  else
    heading 'Modules' 'step 2 of 3'
    say "Starting from the '$profile' profile. Toggle anything you want changed."
    # Bracket syntax: dasel reads `work-laptop` as subtraction.
    modules=$(wizard_pick_modules "$(toml_list "$DOT_PROFILES" "profiles[\"$profile\"]")")
    [[ -z $modules ]] && __wizard_cancel
  fi

  # Identity never varies by machine, so it is read from profiles.toml, not asked.
  name=$(toml_get "$DOT_PROFILES" 'user.name')
  email=$(toml_get "$DOT_PROFILES" 'user.email')
  signingkey=$(toml_get "$DOT_PROFILES" 'user.signingkey')

  heading 'Review' 'step 3 of 3'
  if [[ -n $modules ]]; then
    IFS=$'\t' read -r packages files < <(__wizard_totals "$modules")
    say modules "$(grep -c . <<<"$modules") chosen: $(tr '\n' ' ' <<<"$modules" | sed 's/ *$//')"
    say packages "$packages named across their Brewfiles"
    say files "$files linked into your home directory"
  else
    say modules 'none -- you add them to the config yourself'
  fi
  say identity "${name:-(unset)} <${email:-(unset)}>"
  if [[ -n $signingkey ]]; then say signing "${signingkey:0:36}..."; fi
  say config "${DOT_CONFIG/#$HOME/\~}"
  dim 'Nothing has been written yet. `dot apply` is what installs and links.'

  # `|| cancel`: a bare read trips errexit on Ctrl-D, and falling through would
  # read end-of-input as yes.
  printf '\n'
  read -r -p "  ${__C_BOLD}Write this config?${__C_RESET} [Y/n]: " reply || __wizard_cancel
  [[ ${reply:-y} == [Yy]* ]] || __wizard_cancel

  config_generate "$name" "$email" "$modules" "$signingkey"
  if [[ -n $modules ]]; then
    dim 'Edit it any time with `dot config`.'
  else
    dim "Add modules to ${DOT_CONFIG/#$HOME/\~}, then run: dot apply"
  fi
}
