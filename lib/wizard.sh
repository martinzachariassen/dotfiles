# shellcheck shell=bash

DOT_PROFILES="$DOT_ROOT/profiles.toml"

__wizard_cancel() {
  say 'Cancelled -- no config was written.'
  exit 0
}

__wizard_fzf_opts() {
  printf '%s\n' \
    --reverse --height=70% --border=rounded --info=inline \
    --pointer="$__G_STEP" --marker="$__G_OK" \
    --color='border:dim,header:italic,marker:green,pointer:blue'
}

wizard_preview() {
  local name=$1 dir file n
  dir=$(modules_dir "$name")

  say "$(module_desc "$name")"
  printf '\n'

  if [[ -f $dir/Brewfile ]]; then
    n=$(grep -cE '^[[:space:]]*(brew|cask|tap|mas) ' "$dir/Brewfile" || true)
    say packages "$(ui_count "$n" package)"
  fi

  n=0
  while IFS=$'\t' read -r _ file; do
    n=$((n + 1))
  done < <(fs_pairs "$dir")
  if ((n > 0)); then
    say links "$(ui_count "$n" file) into your home directory:"
    ui_nest
    while IFS=$'\t' read -r _ file; do
      say "${file/#$HOME/\~}"
    done < <(fs_pairs "$dir")
    ui_unnest
  fi

  local hooks=''
  for file in apply.sh doctor.sh remove.sh; do
    if [[ -f $dir/$file ]]; then hooks+=", ${file%.sh}"; fi
  done
  if [[ -n $hooks ]]; then say hooks "${hooks:2}"; fi
}

wizard_pick_modules() {
  local preset=$1 name mark i=0 preselect=''
  local -a names opts
  mapfile -t names < <(modules_all)
  mapfile -t opts < <(__wizard_fzf_opts)

  for name in "${names[@]}"; do
    i=$((i + 1))
    # `*` is cosmetic to fzf; pos(N)+toggle is what selects the preset rows.
    grep -qxF -- "$name" <<<"$preset" && preselect+="pos($i)+toggle+"
  done

  local rows='' row
  for name in "${names[@]}"; do
    mark=' '
    grep -qxF -- "$name" <<<"$preset" && mark='*'
    printf -v row '%s\t%s %-20s %s\n' "$name" "$mark" "$name" "$(module_desc "$name")"
    rows+=$row
  done

  # The whole list before fzf starts: `load` fires while a streamed list is still
  # arriving, and pos(N) on a row that is not there toggles nothing.
  printf '%s' "$rows" |
    fzf "${opts[@]}" --multi --prompt='Modules > ' \
      --delimiter=$'\t' --with-nth=2 \
      --border-label=' Step 2 of 3 -- what goes on this machine ' \
      --bind "load:${preselect}first" \
      --preview "$BASH -c 'source \"$DOT_ROOT/lib/dot.sh\"; wizard_preview {1}'" \
      --preview-window='right,50%,border-left' \
      --header='TAB to toggle, Enter to confirm, Esc to abort. * = in the profile.' |
    cut -f1 || true
}

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
    modules=$(wizard_pick_modules "$(toml_list "$DOT_PROFILES" "profiles[\"$profile\"]")")
    [[ -z $modules ]] && __wizard_cancel
  fi

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

  printf '\n'
  say 'Write this config? [Y/n]'
  # A bare read trips errexit on Ctrl-D, and falling through would read
  # end-of-input as yes.
  read -r reply || __wizard_cancel
  [[ ${reply:-y} == [Yy]* ]] || __wizard_cancel

  config_generate "$name" "$email" "$modules" "$signingkey"
  if [[ -n $modules ]]; then
    dim 'Edit it any time with `dot config`.'
  else
    dim "Add modules to ${DOT_CONFIG/#$HOME/\~}, then run: dot apply"
  fi
}
