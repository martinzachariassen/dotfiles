#!/usr/bin/env bats
#
# fzf is replaced by a shell function (function lookup beats PATH). Some tests
# run in a fresh `bash -euo pipefail`: bats does not enable errexit in a test body.

setup() {
  load helper
  setup_sandbox
}

teardown() { teardown_sandbox; }

# The same shell options bin/dot uses, so a `set -e` abort is observable.
in_strict_shell() {
  run bash -euo pipefail -c "source \"\$DOT_ROOT/lib/dot.sh\"; $1"
}

# --- The module picker ------------------------------------------------------

@test "picker: returns real module names, not words from the description" {
  # Rows outside the profile are marked with a space; a parser that skips
  # leading whitespace returns the first word of the description instead.
  fzf() { cat; } # the user confirms every row offered

  # A preset that excludes most modules, so most markers are a space.
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
  fzf() { grep -F '*' | head -1; } # user takes the first marked row
  run wizard_pick_modules "$(printf 'git\n')"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "picker: preset rows are pre-toggled, not just starred" {
  # `*` is cosmetic to fzf; only pos(N)+toggle selects the row for Enter.
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
  # Esc makes fzf exit 130; inside `modules=$(...)` under `set -e` that is fatal.
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

# --- The `&&`-in-a-loop landmine --------------------------------------------
#
# A false test on the LAST iteration leaves a loop at status 1; in
# modules_enabled pipefail carries that out through `| sort` to the caller.

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
  # The state the `none` profile writes.
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

# --- Validation on apply -----------------------------------------------------

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

# --- No `custom` profile ------------------------------------------------------

@test "wizard: offers none, and never offers custom" {
  # The config file is the one way to hand-assemble a module list.
  local hits
  hits=$(grep -vE '^[[:space:]]*#' "$DOT_ROOT/lib/wizard.sh" | grep -c custom || true)
  [ "$hits" -eq 0 ]

  # The menu is whatever the picker feeds fzf on stdin, so echo it back out.
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
  # One answer: the confirm. Not `</dev/null` -- end-of-input cancels, and the
  # test would prove nothing about a config anybody agreed to.
  run wizard_run < <(printf 'y\n')
  [ "$status" -eq 0 ]
  says modules 'none -- you add them to the config yourself'
  [ -f "$DOT_CONFIG" ]
  [ "$(cfg_list 'modules.enabled')" = "" ]
}

@test "wizard: end-of-input at the confirm prompt cancels and writes nothing" {
  # A bare read trips errexit on Ctrl-D; falling through would read
  # end-of-input as YES via ${reply:-y}.
  in_strict_shell '
    fzf() { printf "none\n"; }
    wizard_run </dev/null
    echo REACHED-THE-END
  '
  [ "$status" -eq 0 ]
  [[ $output == *"Cancelled"* ]]
  # __wizard_cancel exits, so nothing after wizard_run may run.
  [[ $output != *"REACHED-THE-END"* ]]
  [ ! -f "$DOT_CONFIG" ]
}

@test "profile: a hyphenated name resolves -- dasel reads a dash as subtraction" {
  # `profiles.$profile` parses `work-laptop` as `work` minus `laptop`;
  # toml_list swallows stderr, so the preset comes back EMPTY with no error.
  # Same landmine as module_setting in lib/modules.sh.
  DOT_PROFILES="$DOT_TMP/profiles.toml"
  cat >"$DOT_PROFILES" <<'EOF'
[user]
name = "Ada Lovelace"
email = "ada@example.com"
signingkey = ""

[profiles]
work-laptop = ["git"]
EOF
  # Call 1 picks the profile; call 2 is the module picker, which echoes its
  # menu. A counter FILE: fzf runs inside a pipeline, so a variable would die
  # with the subshell.
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
  # `* git` renders only when the preset actually resolved to something.
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
  # Exactly one line of input: the confirm. Were identity still prompted, the
  # `y` would be eaten as the name and the confirm would cancel.
  run wizard_run < <(printf 'y\n')
  [ "$status" -eq 0 ]
  [[ $output != *"Full name"* ]]
  [ "$(cfg_get 'user.name')" = "Ada Lovelace" ]
  [ "$(cfg_get 'user.email')" = "ada@example.com" ]
  [ "$(cfg_get 'settings["git"].signingkey')" = "ssh-ed25519 AAAAKEY" ]
}

@test "identity: no signing key leaves a commented example, not an empty value" {
  # `signingkey = ""` reads as "configured, and blank".
  config_generate 'A' 'a@b.c' '' ''
  # cfg_get answers with its default for an absent key: an empty ANSWER, not a
  # non-zero status.
  run cfg_get 'settings["git"].signingkey'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '# signingkey = "ssh-ed25519 AAAA\.\.\."' "$DOT_CONFIG"
}

# --- The whole round trip ---------------------------------------------------

@test "round trip: what the picker returns is what apply enables" {
  fzf() { cat; }
  local picked
  picked=$(wizard_pick_modules "$(printf 'git\n')")

  config_generate "Ada Lovelace" "ada@example.com" "$picked"

  # modules_enabled sorts; the picker does not. Compare as sets.
  [ "$(modules_enabled | sort)" = "$(printf '%s\n' "$picked" | sort)" ]
}

@test "round trip: every name the wizard writes is one apply will accept" {
  # Ask the validator `dot apply` gates on, not for a string that lives in
  # bin/dot and can never appear here.
  fzf() { cat; }
  config_generate "A" "a@b.c" "$(wizard_pick_modules "$(printf 'git\n')")"

  run modules_require_known
  [ "$status" -eq 0 ]
  [ -z "$(modules_unknown)" ]
}

# --- Stale module names -----------------------------------------------------

@test "enabled: reading the module list is silent, however often it is read" {
  # The real call shape: every reader is a `< <(modules_enabled)` subshell, so
  # a warning inside cannot be deduplicated with a cache variable. Asserted as
  # TOTALLY silent, not "silent about one phrase".
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

# --- The preview ------------------------------------------------------------
#
# fzf runs it as its own process per keystroke, so it has to stand alone. What
# it says is the only thing between a name and a decision about that name.

@test "preview: names the packages, the files and the hooks of a module" {
  run wizard_preview containers
  [ "$status" -eq 0 ]
  [[ $output == *"$(module_desc containers)"* ]]
  [[ $output == *packages* ]]
  [[ $output == *".colima"* ]]
  [[ $output == *hooks* ]]
}

@test "preview: a package set has nothing but packages to show" {
  run wizard_preview apps
  [ "$status" -eq 0 ]
  [[ $output == *packages* ]]
  [[ $output != *links* ]]
  [[ $output != *hooks* ]]
}

@test "preview: every module previews without failing" {
  # It runs inside fzf, where a crash is an empty pane and nothing else.
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
  # The numbers are the point of the review: a list of names says nothing about
  # how much is about to happen.
  local one two
  IFS=$'\t' read -r _ one < <(__wizard_totals "$(printf 'git\n')")
  IFS=$'\t' read -r _ two < <(__wizard_totals "$(printf 'git\nzsh\n')")
  [ "$one" -gt 0 ]
  [ "$two" -gt "$one" ]
}

@test "picker: the real fzf accepts every option the wizard passes it" {
  # Every other test here stubs fzf out, so an option this fzf does not know
  # would surface for the first time on a fresh machine, inside the one command
  # that runs before anything else works. --filter parses the whole option list
  # and then exits, which is the part worth checking.
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
  # fzf hands the preview command to a shell as one string, so the nesting of
  # quotes around $DOT_ROOT is the thing that breaks. lib/dot.sh already refuses
  # a checkout path holding a quote, a backtick, a $ or a backslash, which is
  # what makes this safe rather than lucky.
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

# --- Not tested here, and why -------------------------------------------------
#
# The picker DRAWING -- the border label, the preview pane, the header -- was
# checked by hand against a real fzf in a pty, and it draws. It is not a test:
# under bats the pty never gets its EOF and the run hangs, and a test that hangs
# costs more than the one it replaces. What can be pinned without a terminal is
# pinned above: every option the real fzf accepts, the preview command surviving
# the quoting fzf runs it through, and the name the picker returns.
