#!/usr/bin/env bats

setup() {
  load helper
  setup_sandbox
}

teardown() { teardown_sandbox; }

in_strict_shell() {
  run bash -euo pipefail -c "source \"\$DOT_ROOT/lib/dot.sh\"; $1"
}

@test "picker: returns real module names, not words from the description" {
  fzf() { cat; }

  run wizard_pick_modules "$(printf 'git\n')"

  [ "$status" -eq 0 ]
  [ "$output" = "$(modules_all)" ]
}

@test "picker: every returned name is a module that actually exists" {
  fzf() { cat; }
  local name
  while IFS= read -r name; do
    module_exists "$name" || {
      echo "picker returned '$name', which is not a module"
      return 1
    }
  done < <(wizard_pick_modules "$(printf 'git\n')")
}

@test "picker: a module in the preset is marked, and still returns its name" {
  fzf() { grep -F '*' | head -1; }
  run wizard_pick_modules "$(printf 'git\n')"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "picker: preset rows are pre-toggled, not just starred" {
  fzf() {
    printf '%s\n' "$*" >"$DOT_TMP/fzf_args"
    cat
  }
  wizard_pick_modules "$(printf 'dev-cli\nzsh\n')" >/dev/null

  local i=0 name expected=''
  while IFS= read -r name; do
    i=$((i + 1))
    case $name in dev-cli | zsh) expected+="pos($i)+toggle+" ;; esac
  done < <(modules_all)

  run cat "$DOT_TMP/fzf_args"
  [[ $output == *"--bind load:${expected}first"* ]]
}

@test "picker: cancelling fzf yields nothing instead of killing the run" {
  in_strict_shell '
    fzf() { cat >/dev/null; return 130; }
    out=$(wizard_pick_modules "git")
    [[ -z $out ]] && echo EMPTY
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *EMPTY* ]]
  [[ $output == *SURVIVED* ]]
}

@test "enabled: an unknown module sorting last does not abort the caller" {
  config_generate "A" "a@b.c" "$(printf 'git\nzzz-bogus\n')"
  in_strict_shell '
    list=$(modules_enabled)
    echo "list=[$(echo $list)]"
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *"list=[git]"* ]]
  [[ $output == *SURVIVED* ]]
}

@test "enabled: a config where nothing is known is not an error" {
  config_generate "A" "a@b.c" "$(printf 'nope\n')"
  in_strict_shell '
    list=$(modules_enabled)
    [[ -z $list ]] && echo EMPTY
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *EMPTY* ]]
  [[ $output == *SURVIVED* ]]
}

@test "enabled: an empty module list is not an error" {
  config_generate "A" "a@b.c" ""
  in_strict_shell '
    list=$(modules_enabled)
    [[ -z $list ]] && echo EMPTY
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *EMPTY* ]]
  [[ $output == *SURVIVED* ]]
}

@test "validate: a config naming only real modules passes" {
  config_generate "A" "a@b.c" "$(printf 'git\nzsh\n')"
  run modules_require_known
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: an empty module list passes" {
  config_generate "A" "a@b.c" ""
  run modules_require_known
  [ "$status" -eq 0 ]
}

@test "validate: an unknown module stops the run and says what is valid" {
  config_generate "A" "a@b.c" "$(printf 'git\ntypoo\n')"
  run modules_require_known
  [ "$status" -eq 1 ]
  [[ $output == *typoo* ]]
  [[ $output == *"do not exist"* ]]
  [[ $output == *available* ]]
  [[ $output == *git* ]]
}

@test "validate: every unknown name is listed, not just the first" {
  config_generate "A" "a@b.c" "$(printf 'aaa\ngit\nzzz\n')"
  run modules_require_known
  [ "$status" -eq 1 ]
  [[ $output == *aaa* ]]
  [[ $output == *zzz* ]]
}

@test "wizard: offers none, and never offers custom" {
  local hits
  hits=$(grep -vE '^[[:space:]]*#' "$DOT_ROOT/lib/wizard.sh" | grep -c custom || true)
  [ "$hits" -eq 0 ]

  fzf() {
    cat >&2
    printf 'none\n'
  }
  run wizard_run </dev/null
  [[ $output == *none* ]]
  [[ $output == *personal* ]]
  [[ $output != *custom* ]]
}

@test "wizard: the none profile writes an empty list and skips the picker" {
  fzf() { printf 'none\n'; }
  run wizard_run < <(printf 'y\n')
  [ "$status" -eq 0 ]
  says modules 'none -- you add them to the config yourself'
  [ -f "$DOT_CONFIG" ]
  [ "$(cfg_list 'modules.enabled')" = "" ]
}

@test "wizard: end-of-input at the confirm prompt cancels and writes nothing" {
  in_strict_shell '
    fzf() { printf "none\n"; }
    wizard_run </dev/null
    echo REACHED-THE-END
  '
  [ "$status" -eq 0 ]
  [[ $output == *"Cancelled"* ]]
  [[ $output != *"REACHED-THE-END"* ]]
  [ ! -f "$DOT_CONFIG" ]
}

@test "profile: a hyphenated name resolves -- dasel reads a dash as subtraction" {
  DOT_PROFILES="$DOT_TMP/profiles.toml"
  cat >"$DOT_PROFILES" <<'EOF'
[user]
name = "Ada Lovelace"
email = "ada@example.com"
signingkey = ""

[profiles]
work-laptop = ["git"]
EOF
  fzf() {
    if [[ -f $DOT_TMP/picked ]]; then
      cat >&2
      printf 'git\tgit\n'
    else
      : >"$DOT_TMP/picked"
      printf 'work-laptop\n'
    fi
  }
  run wizard_run < <(printf 'y\n')
  [ "$status" -eq 0 ]
  [[ $output == *"* git"* ]]
}

@test "identity: comes from profiles.toml, and the wizard never asks" {
  DOT_PROFILES="$DOT_TMP/profiles.toml"
  cat >"$DOT_PROFILES" <<'EOF'
[user]
name = "Ada Lovelace"
email = "ada@example.com"
signingkey = "ssh-ed25519 AAAAKEY"

[profiles]
solo = ["git"]
EOF
  fzf() { printf 'none\n'; }
  run wizard_run < <(printf 'y\n')
  [ "$status" -eq 0 ]
  [[ $output != *"Full name"* ]]
  [ "$(cfg_get 'user.name')" = "Ada Lovelace" ]
  [ "$(cfg_get 'user.email')" = "ada@example.com" ]
  [ "$(cfg_get 'settings["git"].signingkey')" = "ssh-ed25519 AAAAKEY" ]
}

@test "identity: no signing key leaves a commented example, not an empty value" {
  config_generate 'A' 'a@b.c' '' ''
  run cfg_get 'settings["git"].signingkey'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '# signingkey = "ssh-ed25519 AAAA\.\.\."' "$DOT_CONFIG"
}

@test "round trip: what the picker returns is what apply enables" {
  fzf() { cat; }
  local picked
  picked=$(wizard_pick_modules "$(printf 'git\n')")

  config_generate "Ada Lovelace" "ada@example.com" "$picked"

  [ "$(modules_enabled | sort)" = "$(printf '%s\n' "$picked" | sort)" ]
}

@test "round trip: every name the wizard writes is one apply will accept" {
  fzf() { cat; }
  config_generate "A" "a@b.c" "$(wizard_pick_modules "$(printf 'git\n')")"

  run modules_require_known
  [ "$status" -eq 0 ]
  [ -z "$(modules_unknown)" ]
}

@test "enabled: reading the module list is silent, however often it is read" {
  config_generate "A" "a@b.c" "$(printf 'git\nbogus\n')"
  run bash -c '
    source "$DOT_ROOT/lib/dot.sh"
    while IFS= read -r n; do :; done < <(modules_enabled)
    while IFS= read -r n; do :; done < <(modules_enabled)
    while IFS= read -r n; do :; done < <(modules_enabled_dirs)
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unknown: each stale name is listed exactly once" {
  config_generate "A" "a@b.c" "$(printf 'git\nbogus\n')"
  run modules_unknown
  [ "$status" -eq 0 ]
  [ "$output" = "bogus" ]
}

@test "enabled: an unknown module is skipped, not applied" {
  config_generate "A" "a@b.c" "$(printf 'git\nbogus\n')"
  run modules_enabled
  [[ $output != *bogus* ]]
  [[ $output == *git* ]]
}

@test "preview: names the packages, the files and the hooks of a module" {
  run wizard_preview containers
  [ "$status" -eq 0 ]
  [[ $output == *"$(module_desc containers)"* ]]
  [[ $output == *packages* ]]
  [[ $output == *".colima"* ]]
  [[ $output == *hooks* ]]
}

@test "preview: a package set has nothing but packages to show" {
  run wizard_preview work-apps
  [ "$status" -eq 0 ]
  [[ $output == *packages* ]]
  [[ $output != *links* ]]
  [[ $output != *hooks* ]]
}

@test "preview: every module previews without failing" {
  local name
  while IFS= read -r name; do
    run wizard_preview "$name"
    [ "$status" -eq 0 ] || {
      echo "wizard_preview $name exited $status"
      return 1
    }
    [ -n "$output" ]
  done < <(modules_all)
}

@test "review: the totals count the chosen modules, and only those" {
  local one two
  IFS=$'\t' read -r _ one < <(__wizard_totals "$(printf 'git\n')")
  IFS=$'\t' read -r _ two < <(__wizard_totals "$(printf 'git\nzsh\n')")
  [ "$one" -gt 0 ]
  [ "$two" -gt "$one" ]
}

@test "picker: the real fzf accepts every option the wizard passes it" {
  command -v fzf >/dev/null 2>&1 || skip 'no fzf on this machine'
  local -a opts
  mapfile -t opts < <(__wizard_fzf_opts)

  run bash -c 'printf "personal\nnone\n" | fzf "$@" --prompt="Profile > " \
    --border-label=" step " --header="h" --filter=personal' _ "${opts[@]}"
  [ "$status" -eq 0 ]

  run bash -c 'printf "containers\tcontainers  desc\n" | fzf "$@" --multi \
    --delimiter="\t" --with-nth=2 --border-label=" step " --header="h" \
    --bind "load:pos(1)+toggle+first" --preview "true {1}" \
    --preview-window="right,50%,border-left" --filter=containers' _ "${opts[@]}"
  [ "$status" -eq 0 ]
}

@test "picker: the preview survives the quoting fzf runs it through" {
  run sh -c "$BASH -c 'source \"$DOT_ROOT/lib/dot.sh\"; wizard_preview containers'"
  [ "$status" -eq 0 ]
  [[ $output == *"$(module_desc containers)"* ]]
}

@test "review: nothing chosen totals nothing, rather than failing" {
  local packages files
  IFS=$'\t' read -r packages files < <(__wizard_totals '')
  [ "$packages" -eq 0 ]
  [ "$files" -eq 0 ]
}

@test "picker: every row is described before fzf starts, so the preset has rows to toggle" {
  module_desc() {
    : >"$DOT_TMP/desc-$1"
    printf 'described\n'
  }
  fzf() {
    find "$DOT_TMP" -name 'desc-*' | wc -l | tr -d ' ' >"$DOT_TMP/described"
    cat >/dev/null
  }
  wizard_pick_modules "$(printf 'git\n')" >/dev/null

  [ "$(cat "$DOT_TMP/described")" -eq "$(modules_all | wc -l | tr -d ' ')" ]
}

@test "confirm: the question is a line of output, not a read prompt" {
  fzf() { printf 'none\n'; }
  run wizard_run < <(printf 'y\n')
  [ "$status" -eq 0 ]
  [[ $output == *'Write this config? [Y/n]'* ]]
}
